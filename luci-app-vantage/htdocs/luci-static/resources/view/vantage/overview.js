'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require dom';
'require vantage.fmt as fmt';
'require vantage.wifi as wifi';
'require vantage.names as names';
'require vantage.model as model';
'require vantage.insight as insight';
'require vantage.series as series';

/* Vantage dashboard (luci-app-vantage): a live, read-only overview of the
   device, its uplink, radios, SSIDs and stations. The only write is the
   station alias (uci vantage, own ACL). All DOM is built with E() and
   text nodes; no string is ever parsed as markup. */

var POLL_S = 5;
var WINDOW_MS = 5 * 60 * 1000;        /* throughput history shown */
var HIST_MAX = 90;
var GONE_KEEP_MS = 5 * 60 * 1000;     /* disconnected stations stay listed */
var STORE_KEY = 'vantage.hist.v1';
var SVGNS = 'http://www.w3.org/2000/svg';
var HOSTAPD_OBJ = /^[A-Za-z0-9_.-]{1,64}$/;

var callBoard = rpc.declare({ object: 'system', method: 'board' });
var callInfo = rpc.declare({ object: 'system', method: 'info' });
var callRead = rpc.declare({ object: 'file', method: 'read', params: [ 'path' ], expect: { data: '' } });
var callIfDump = rpc.declare({ object: 'network.interface', method: 'dump', expect: { 'interface': [] } });
var callDevs = rpc.declare({ object: 'network.device', method: 'status', expect: { '': {} } });
/* luci.vantage is the app's own rpcd ucode plugin: network.wireless status
   without keys or RADIUS secrets, and the validated alias write */
var callWifi = rpc.declare({ object: 'luci.vantage', method: 'wireless', expect: { '': {} } });
var callHints = rpc.declare({ object: 'luci-rpc', method: 'getHostHints', expect: { '': {} } });
var callIwInfo = rpc.declare({ object: 'iwinfo', method: 'info', params: [ 'device' ], expect: { '': {} } });
var callAssoc = rpc.declare({ object: 'iwinfo', method: 'assoclist', params: [ 'device' ], expect: { results: [] } });
var callRrdns = rpc.declare({ object: 'network.rrdns', method: 'lookup', params: [ 'addrs', 'timeout', 'limit' ], expect: { '': {} } });
var callMdns = rpc.declare({ object: 'umdns', method: 'hosts' });
var callUciGet = rpc.declare({ object: 'uci', method: 'get', params: [ 'config' ], expect: { values: {} } });
var callSetAlias = rpc.declare({ object: 'luci.vantage', method: 'set_alias', params: [ 'mac', 'name', 'icon' ] });
var callAccess = rpc.declare({ object: 'session', method: 'access', params: [ 'scope', 'object', 'function' ], expect: { access: false } });

var hostapdCalls = {};
function hostapd(ifname, method) {
	var obj = 'hostapd.' + ifname, key = obj + ' ' + method;
	if (!HOSTAPD_OBJ.test(obj)) return Promise.resolve(null);
	if (!hostapdCalls[key]) hostapdCalls[key] = rpc.declare({ object: obj, method: method, expect: { '': {} } });
	return L.resolveDefault(hostapdCalls[key](), null);
}

var cssPromise = null;
function loadCss() {
	if (cssPromise) return cssPromise;
	cssPromise = fetch(L.resource('vantage/app.css')).then(function(r) { return r.ok ? r.text() : ''; }).then(function(text) {
		if (!text || !('adoptedStyleSheets' in document) || typeof CSSStyleSheet !== 'function') return;
		var sheet = new CSSStyleSheet();
		sheet.replaceSync(text);
		document.adoptedStyleSheets = document.adoptedStyleSheets.concat([ sheet ]);
	}).catch(function() {});
	return cssPromise;
}

function reducedMotion() {
	return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
}

/* ------------------------------------------------------------- SVG kit */

var ICONS = {
	globe: [ 'M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18Z', 'M3.4 9.2h17.2M3.4 14.8h17.2', 'M12 3c2.4 2.5 3.6 5.5 3.6 9s-1.2 6.5-3.6 9c-2.4-2.5-3.6-5.5-3.6-9s1.2-6.5 3.6-9Z' ],
	ap: [ 'M4.5 15h15a1.5 1.5 0 0 1 1.5 1.5v1.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18v-1.5A1.5 1.5 0 0 1 4.5 15Z', 'M7 17.25h.01', 'M8.6 10.6a4.8 4.8 0 0 1 6.8 0', 'M6.1 8.1a8.4 8.4 0 0 1 11.8 0', 'M11.3 12.9a1 1 0 0 1 1.4 0' ],
	radio: [ 'M12 12.5v8', 'M8.5 20.5h7', 'M9.2 8.7a4 4 0 0 0 0 5.6', 'M14.8 8.7a4 4 0 0 1 0 5.6', 'M6.4 5.9a8 8 0 0 0 0 11.2', 'M17.6 5.9a8 8 0 0 1 0 11.2', 'M12 10.3a1.2 1.2 0 1 1 0 2.4a1.2 1.2 0 1 1 0-2.4Z' ],
	wifi: [ 'M3.3 9.4a12.3 12.3 0 0 1 17.4 0', 'M6.3 12.4a8 8 0 0 1 11.4 0', 'M9.3 15.4a3.8 3.8 0 0 1 5.4 0', 'M12 18.6h.01' ],
	cpu: [ 'M7.5 6h9A1.5 1.5 0 0 1 18 7.5v9a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 16.5v-9A1.5 1.5 0 0 1 7.5 6Z', 'M10 10h4v4h-4z', 'M9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3' ],
	memory: [ 'M4 7.5h16a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1Z', 'M7 16.5v2.5M11 16.5v2.5M15 16.5v2.5M19 16.5v2.5', 'M6.5 10.5h3v3h-3zM10.5 10.5h3v3h-3zM14.5 10.5h3v3h-3z' ],
	disk: [ 'M4.5 6.5c0-1.4 3.4-2.5 7.5-2.5s7.5 1.1 7.5 2.5v11c0 1.4-3.4 2.5-7.5 2.5s-7.5-1.1-7.5-2.5z', 'M4.5 6.5c0 1.4 3.4 2.5 7.5 2.5s7.5-1.1 7.5-2.5', 'M4.5 12c0 1.4 3.4 2.5 7.5 2.5s7.5-1.1 7.5-2.5' ],
	clock: [ 'M12 3.5a8.5 8.5 0 1 0 0 17a8.5 8.5 0 1 0 0-17Z', 'M12 7.5V12l3 2' ],
	down: [ 'M12 5v14', 'M6.5 13.5 12 19l5.5-5.5' ],
	up: [ 'M12 19V5', 'M6.5 10.5 12 5l5.5 5.5' ],
	close: [ 'M6.5 6.5l11 11M17.5 6.5l-11 11' ],
	search: [ 'M10.5 4.5a6 6 0 1 0 0 12a6 6 0 1 0 0-12Z', 'M15 15l4.5 4.5' ],
	chevron: [ 'M9.5 6l6 6-6 6' ],
	out: [ 'M9 15 16.5 7.5', 'M10 7.5h6.5V14', 'M13 4.5H6A1.5 1.5 0 0 0 4.5 6v12A1.5 1.5 0 0 0 6 19.5h12a1.5 1.5 0 0 0 1.5-1.5v-7' ],
	check: [ 'M5 12.5l4.5 4.5L19 7.5' ],
	warn: [ 'M10.3 4.6 3 17.5A2 2 0 0 0 4.7 20.5h14.6A2 2 0 0 0 21 17.5L13.7 4.6a2 2 0 0 0-3.4 0Z', 'M12 9.5v4.5', 'M12 17h.01' ],
	err: [ 'M12 3.5a8.5 8.5 0 1 0 0 17a8.5 8.5 0 1 0 0-17Z', 'M9 9l6 6M15 9l-6 6' ],
	info: [ 'M12 3.5a8.5 8.5 0 1 0 0 17a8.5 8.5 0 1 0 0-17Z', 'M12 11v5.5', 'M12 7.8h.01' ],
	pencil: [ 'M4.5 19.5h4l10-10-4-4-10 10z', 'M13 7l4 4' ],
	lock: [ 'M6.5 11h11a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1Z', 'M8.5 11V8a3.5 3.5 0 0 1 7 0v3' ],
	unlock: [ 'M6.5 11h11a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1Z', 'M8.5 11V8a3.5 3.5 0 0 1 6.8-1.2' ],
	users: [ 'M9 11a3.5 3.5 0 1 0 0-7a3.5 3.5 0 1 0 0 7Z', 'M2.5 20c.8-3.4 3.3-5.5 6.5-5.5s5.7 2.1 6.5 5.5', 'M16 4.3a3.5 3.5 0 0 1 0 6.4', 'M18 14.8c1.8.8 3 2.6 3.5 5.2' ],
	spark: [ 'M12 3.5v4M12 16.5v4M3.5 12h4M16.5 12h4M6 6l2.6 2.6M15.4 15.4 18 18M6 18l2.6-2.6M15.4 8.6 18 6' ],
	pulse: [ 'M3 12h4l2.5-6 5 12 2.5-6H21' ],
	phone: [ 'M8 3h8a1.5 1.5 0 0 1 1.5 1.5v15A1.5 1.5 0 0 1 16 21H8a1.5 1.5 0 0 1-1.5-1.5v-15A1.5 1.5 0 0 1 8 3Z', 'M11 18h2' ],
	laptop: [ 'M5.5 5.5h13a1 1 0 0 1 1 1v8.5h-15V6.5a1 1 0 0 1 1-1Z', 'M2.5 18.5h19l-1.5-3.5h-16z' ],
	tablet: [ 'M6.5 3h11A1.5 1.5 0 0 1 19 4.5v15a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19.5v-15A1.5 1.5 0 0 1 6.5 3Z', 'M11 18h2' ],
	desktop: [ 'M4.5 4.5h15a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1Z', 'M9 20h6', 'M12 15.5V20' ],
	tv: [ 'M4 6h16a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1Z', 'M8 20.5h8' ],
	speaker: [ 'M7.5 3h9A1.5 1.5 0 0 1 18 4.5v15a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 19.5v-15A1.5 1.5 0 0 1 7.5 3Z', 'M12 7h.01', 'M12 11a3 3 0 1 0 0 6a3 3 0 1 0 0-6Z' ],
	printer: [ 'M7 8V3.5h10V8', 'M7 16.5H4.5A1.5 1.5 0 0 1 3 15V9.5A1.5 1.5 0 0 1 4.5 8h15A1.5 1.5 0 0 1 21 9.5V15a1.5 1.5 0 0 1-1.5 1.5H17', 'M7 13h10v7.5H7z' ],
	camera: [ 'M4.5 7.5h3l1.5-2h6l1.5 2h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-10a1 1 0 0 1 1-1Z', 'M12 10a3.2 3.2 0 1 0 0 6.4a3.2 3.2 0 1 0 0-6.4Z' ],
	console: [ 'M7.5 8h9a4.5 4.5 0 0 1 4.5 4.5v.5a3.5 3.5 0 0 1-6.3 2.1L14 14h-4l-.7 1.1A3.5 3.5 0 0 1 3 13v-.5A4.5 4.5 0 0 1 7.5 8Z', 'M7.5 10.5v3M6 12h3', 'M15.5 11.5h.01M17.5 13h.01' ],
	watch: [ 'M8.5 6h7A1.5 1.5 0 0 1 17 7.5v9a1.5 1.5 0 0 1-1.5 1.5h-7A1.5 1.5 0 0 1 7 16.5v-9A1.5 1.5 0 0 1 8.5 6Z', 'M9 6l.5-3h5l.5 3M9 18l.5 3h5l.5-3' ],
	iot: [ 'M9 18h6', 'M10 21h4', 'M12 3a6 6 0 0 0-3.5 10.9V16h7v-2.1A6 6 0 0 0 12 3Z' ],
	router: [ 'M4.5 13h15a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z', 'M7 16h.01M10 16h.01', 'M8 13 6 6.5M16 13l2-6.5' ],
	device: [ 'M7 3.5h10A1.5 1.5 0 0 1 18.5 5v14a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5Z', 'M10 17.5h4', 'M9 7.5h6' ]
};

function svgRoot(cls, viewBox) {
	var s = document.createElementNS(SVGNS, 'svg');
	s.setAttribute('class', cls);
	s.setAttribute('viewBox', viewBox);
	s.setAttribute('aria-hidden', 'true');
	s.setAttribute('focusable', 'false');
	return s;
}

function svgPath(d, cls) {
	var p = document.createElementNS(SVGNS, 'path');
	p.setAttribute('d', d);
	if (cls) p.setAttribute('class', cls);
	return p;
}

function svgRect(x, y, w, h, rx, cls) {
	var r = document.createElementNS(SVGNS, 'rect');
	r.setAttribute('x', String(x));
	r.setAttribute('y', String(y));
	r.setAttribute('width', String(w));
	r.setAttribute('height', String(h));
	r.setAttribute('rx', String(rx));
	if (cls) r.setAttribute('class', cls);
	return r;
}

function icon(name, cls) {
	var s = svgRoot('vt-ico' + (cls ? ' ' + cls : ''), '0 0 24 24');
	var list = Object.prototype.hasOwnProperty.call(ICONS, name) ? ICONS[name] : ICONS.device;
	list.forEach(function(d) { s.appendChild(svgPath(d)); });
	return s;
}

/* four rising bars, `bars` of them lit, coloured by level */
function signalGlyph(sig) {
	var s = svgRoot('vt-sig vt-lvl-' + sig.level, '0 0 20 16');
	for (var i = 0; i < 4; i++)
		s.appendChild(svgRect(1 + i * 5, 12 - i * 3.5, 3.4, 3 + i * 3.5, 1, i < sig.bars ? 'vt-sig-on' : 'vt-sig-off'));
	return s;
}

/* vertical fade for area fills: the series colour (--vt-sc) at the
   chart fill opacity at the top, transparent at the baseline. Returns the
   paint reference for the fill attribute. */
var gradSeq = 0;
function fadeFill(svg) {
	var id = 'vt-fade-' + (++gradSeq);
	var defs = document.createElementNS(SVGNS, 'defs');
	var lg = document.createElementNS(SVGNS, 'linearGradient');
	lg.setAttribute('id', id);
	lg.setAttribute('x1', '0'); lg.setAttribute('y1', '0');
	lg.setAttribute('x2', '0'); lg.setAttribute('y2', '1');
	[ [ '0', 'vt-fade-top' ], [ '1', 'vt-fade-end' ] ].forEach(function(st) {
		var stop = document.createElementNS(SVGNS, 'stop');
		stop.setAttribute('offset', st[0]);
		stop.setAttribute('class', st[1]);
		lg.appendChild(stop);
	});
	defs.appendChild(lg);
	svg.appendChild(defs);
	return 'url(#' + id + ')';
}

function pos(el, xPct, yPct) {
	el.style.left = Math.max(0, Math.min(100, xPct)).toFixed(2) + '%';
	el.style.top = Math.max(0, Math.min(100, yPct)).toFixed(2) + '%';
	return el;
}

/* Compact chart in the dashboard's chart language: the first column as a
   line over a fading area, a second column as a faint dashed line, a
   marker on the newest value, a faint top grid line and (opts.scale) the
   axis maximum with its unit. Before a minute of history the data is
   drawn from the right edge. opts: { min: axis floor, scale: fn(max),
   thresh: value for a dashed reference line, threshLabel } */
function sparkline(data, cols, vmax, cls, opts) {
	opts = opts || {};
	var W = 100, H = 26;
	var wrap = E('div', { 'class': 'vt-sk' + (cls ? ' ' + cls : '') });
	var s = svgRoot('vt-spark', '0 0 ' + W + ' ' + H);
	s.setAttribute('preserveAspectRatio', 'none');
	wrap.appendChild(s);
	s.appendChild(svgPath('M0 0H' + W, 'vt-spark-grid'));
	s.appendChild(svgPath('M0 ' + H + 'H' + W, 'vt-spark-base'));
	if (!data || data.length < 2) {
		wrap.classList.add('vt-sk-empty');
		wrap.appendChild(E('span', { 'class': 'vt-sk-note' }, [ _('collecting…') ]));
		return wrap;
	}
	var t1 = data[data.length - 1][0], t0 = Math.min(data[0][0], t1 - 60000);
	var max = vmax > 0 ? vmax : series.niceCeil(Math.max(series.max(data, cols) * 1.05, opts.min || 0));
	if (opts.thresh != null) {
		var ty = H - Math.max(0, Math.min(1, opts.thresh / max)) * H;
		s.appendChild(svgPath('M0 ' + ty.toFixed(1) + 'H' + W, 'vt-spark-thresh'));
		if (opts.threshLabel) wrap.appendChild(pos(E('span', { 'class': 'vt-sk-thresh' }, [ opts.threshLabel ]), 100, ty / H * 100));
	}
	cols.slice().reverse().forEach(function(ci) {
		var k = cols.indexOf(ci);
		var segs = series.segments(data, ci, t0, t1, max, W, H, POLL_S * 3500);
		var g = document.createElementNS(SVGNS, 'g');
		g.setAttribute('class', 'vt-spark-s' + k);
		if (k === 0) {
			var area = svgPath(series.areaPath(segs, H), 'vt-spark-area');
			area.setAttribute('fill', fadeFill(s));
			g.appendChild(area);
		}
		g.appendChild(svgPath(series.linePath(segs), 'vt-spark-line'));
		s.appendChild(g);
		if (k === 0) {
			var last = segs.length ? segs[segs.length - 1] : null, pt = last && last[last.length - 1];
			if (pt) wrap.appendChild(pos(E('span', { 'class': 'vt-sk-dot' }), pt[0] / W * 100, pt[1] / H * 100));
		}
	});
	if (opts.scale) wrap.appendChild(E('span', { 'class': 'vt-sk-max vt-tn' }, [ opts.scale(max) ]));
	return wrap;
}

/* -------------------------------------------------------------- helpers */

function txt(el, s) { el.textContent = (s == null ? '' : String(s)); return el; }
function setW(el, pct) { el.style.width = Math.max(0, Math.min(100, +pct || 0)).toFixed(2) + '%'; }
function hueOf(mac) {
	var h = 0, s = String(mac || '');
	for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
	return h;
}

function avatar(c, small) {
	var el = E('span', { 'class': 'vt-av' + (small ? ' vt-av-sm' : '') + (c.gone ? ' vt-av-gone' : '') }, [ icon(c.icon || 'device') ]);
	el.style.setProperty('--vt-h', hueOf(c.mac).toFixed(0));
	return el;
}

function bandBadge(band, label) {
	return E('span', { 'class': 'vt-band vt-band-' + (band || 'x') }, [ label || wifi.bandLabel(band) ]);
}

function pill(text, tone, title) {
	var el = E('span', { 'class': 'vt-pill vt-pill-' + (tone || 'muted') }, [ text ]);
	if (title) el.setAttribute('title', title);
	return el;
}

function rateLine(down, up, cls) {
	return E('span', { 'class': 'vt-rates' + (cls ? ' ' + cls : '') }, [
		E('span', { 'class': 'vt-rate vt-rate-down', 'title': _('Download (to clients)') }, [ icon('down'), fmt.bits(down) ]),
		E('span', { 'class': 'vt-rate vt-rate-up', 'title': _('Upload (from clients)') }, [ icon('up'), fmt.bits(up) ])
	]);
}

function kv(label, value, mono) {
	return E('div', { 'class': 'vt-kv' }, [
		E('dt', {}, [ label ]),
		E('dd', { 'class': mono ? 'vt-mono' : '' }, [].concat(value == null || value === '' ? fmt.DASH : value))
	]);
}

function tileHead(ic, title, extra) {
	return E('header', { 'class': 'vt-tile-head' }, [
		E('h3', { 'class': 'vt-tile-title' }, [ icon(ic), E('span', {}, [ title ]) ]),
		E('div', { 'class': 'vt-tile-extra' }, extra || [])
	]);
}

function pageLink(page, label) {
	return E('a', { 'class': 'vt-link', 'href': L.url.apply(L, page) }, [ E('span', {}, [ label ]), icon('chevron') ]);
}

/* axis labels: round numbers without a trailing '.0' ('15 Mbit/s') */
function bitsLabel(v) {
	var p = fmt.bitsParts(v);
	return p.u ? String(+p.v || p.v) + ' ' + p.u : p.v;
}

/* '5 min ago' / '45 s ago' for the left end of a time axis */
function spanAgo(ms) {
	var s = Math.round(ms / 1000);
	return s >= 90 ? _('%d min ago').format(Math.round(s / 60)) : _('%d s ago').format(s);
}

/* '1 min' / '40 s' of collected history */
function spanShort(ms) {
	var s = Math.max(0, Math.round(ms / 1000));
	return s >= 60 ? _('%d min').format(Math.floor(s / 60)) : _('%d s').format(s);
}

function readStore() {
	try { return JSON.parse(window.sessionStorage.getItem(STORE_KEY) || 'null'); } catch (e) { return null; }
}

function writeStore(v) {
	try { window.sessionStorage.setItem(STORE_KEY, JSON.stringify(v)); } catch (e) {}
}

/* Sections that fold on narrow screens; the choice is remembered per
   browser. Defaults keep the phone page short: radios and the network
   path start condensed. */
var FOLD_KEY = 'vantage.fold.v1';
var FOLD_DEFAULT = { radios: true, hero: true, ssids: false, chart: false, sys: false };

function readFolds() {
	var out = Object.assign({}, FOLD_DEFAULT), v = null;
	try { v = JSON.parse(window.localStorage.getItem(FOLD_KEY) || 'null'); } catch (e) { v = null; }
	if (v && typeof v === 'object')
		Object.keys(FOLD_DEFAULT).forEach(function(k) { if (typeof v[k] === 'boolean') out[k] = v[k]; });
	return out;
}

function writeFolds(v) {
	try { window.localStorage.setItem(FOLD_KEY, JSON.stringify(v)); } catch (e) {}
}

/* ================================================================= view */

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	/* ---------------------------------------------------------- loading */

	load: function() {
		return Promise.all([
			loadCss(),
			L.resolveDefault(callBoard(), {}),
			L.resolveDefault(callAccess('access-group', 'luci-app-vantage-names', 'write'), false),
			this.loadAliases(),
			L.resolveDefault(callMdns(), null),
			this.fetch(),
			/* reverse DNS is an optional grant: without it, skip it quietly */
			L.resolveDefault(callAccess('access-group', 'luci-app-vantage-rdns', 'read'), false)
		]).then(function(r) {
			return { board: r[1] || {}, canWrite: r[2] === true, mdns: r[4], raw: r[5], canRdns: r[6] === true };
		});
	},

	loadAliases: function() {
		var self = this;
		return L.resolveDefault(callUciGet('vantage'), {}).then(function(values) {
			var list = (values && typeof values === 'object') ? Object.keys(values).map(function(k) { return values[k]; }) : [];
			self.aliases = names.aliasMap(list.slice(0, names.ALIAS_MAX + 1));
			return self.aliases;
		});
	},

	/* one poll's worth of raw replies; missing pieces degrade to {} */
	fetch: function() {
		var started = Date.now();
		return Promise.all([
			L.resolveDefault(callInfo(), {}),
			L.resolveDefault(callRead('/proc/stat'), ''),
			L.resolveDefault(callIfDump(), []),
			L.resolveDefault(callDevs(), {}),
			L.resolveDefault(callWifi(), {}),
			L.resolveDefault(callHints(), {})
		]).then(function(r) {
			var wifiDevs = (r[4] && typeof r[4] === 'object') ? r[4] : {};
			var ifnames = [];
			Object.keys(wifiDevs).forEach(function(rn) {
				var ifs = (wifiDevs[rn] && Array.isArray(wifiDevs[rn].interfaces)) ? wifiDevs[rn].interfaces : [];
				ifs.forEach(function(i) {
					if (i && typeof i.ifname === 'string' && HOSTAPD_OBJ.test(i.ifname) && ifnames.indexOf(i.ifname) < 0) ifnames.push(i.ifname);
				});
			});
			/* iwinfo per interface: channel and power for the radio, BSSID
			   and SSID for each network (luci.vantage wireless carries
			   configuration only) */
			var per = [];
			ifnames.forEach(function(ifn) {
				per.push(L.resolveDefault(callAssoc(ifn), []).then(function(v) { return [ 'assoc', ifn, v ]; }));
				per.push(hostapd(ifn, 'get_clients').then(function(v) { return [ 'hapd', ifn, v ]; }));
				per.push(hostapd(ifn, 'get_status').then(function(v) { return [ 'hapdStatus', ifn, v ]; }));
				per.push(L.resolveDefault(callIwInfo(ifn), {}).then(function(v) { return [ 'iwinfo', ifn, v ]; }));
			});
			return Promise.all(per).then(function(parts) {
				var assoc = Object.create(null), hapd = Object.create(null), hapdStatus = Object.create(null), iwinfo = Object.create(null);
				parts.forEach(function(p) {
					if (p[0] === 'assoc') assoc[p[1]] = p[2];
					else if (p[0] === 'hapd') hapd[p[1]] = p[2];
					else if (p[0] === 'hapdStatus') hapdStatus[p[1]] = p[2];
					else iwinfo[p[1]] = p[2];
				});
				return { info: r[0] || {}, stat: r[1] || '', ifaces: r[2] || [], devs: r[3] || {}, wifi: wifiDevs, hints: r[5] || {},
					assoc: assoc, hapd: hapd, hapdStatus: hapdStatus, iwinfo: iwinfo, at: Date.now(), started: started };
			});
		});
	},

	/* ------------------------------------------------------------ state */

	initState: function(data) {
		var stored = readStore() || {}, now = Date.now();
		/* keys come from sessionStorage: no prototype to overwrite */
		var net = Object.create(null);
		if (stored.net && typeof stored.net === 'object')
			Object.keys(stored.net).forEach(function(k) {
				if (/^[A-Za-z0-9_.:-]{1,40}$/.test(k)) net[k] = series.valid(stored.net[k], 3, HIST_MAX, now);
			});
		var clientHist = Object.create(null);
		if (stored.clients && typeof stored.clients === 'object')
			Object.keys(stored.clients).slice(0, 64).forEach(function(k) {
				var mac = names.normMac(k);
				if (mac) clientHist[mac] = series.valid(stored.clients[k], 4, 150, now);
			});
		this.board = data.board || {};
		this.canWrite = data.canWrite;
		this.st = {
			clock: null, stat: null, cpu: null,
			devPrev: null, staPrev: null, devRates: Object.create(null), staRates: Object.create(null), radioRates: Object.create(null), ssidRates: Object.create(null),
			hist: { net: net, cpu: series.valid(stored.cpu, 2, HIST_MAX, now), mem: series.valid(stored.mem, 2, HIST_MAX, now) },
			clientHist: clientHist, bestStd: Object.create(null),
			presence: null, isNew: Object.create(null), gone: [],
			rdns: Object.create(null), rdnsBusy: false, rdnsOff: !data.canRdns,
			mdns: Object.create(null), mdnsOff: true, mdnsAt: 0,
			oui: null, ouiLoading: false,
			lastOk: 0, lastErr: null, paused: false
		};
		this.ui = { sort: 'live', dir: -1, filter: '', chip: 'all', chart: 'down', drawer: null, editing: null, hover: null };
		this.folds = readFolds();
		this.foldEls = {};
		this.foldBtns = {};
		this.applyMdns(data.mdns);
		this.aliases = this.aliases || {};
	},

	applyMdns: function(reply) {
		/* umdns missing (NOT_FOUND / no permission) answers a number */
		if (reply && typeof reply === 'object') { this.st.mdns = names.mdnsMap(reply); this.st.mdnsOff = false; }
		else this.st.mdnsOff = true;
		this.st.mdnsAt = Date.now();
	},

	/* raw replies -> model + rates + histories */
	ingest: function(raw) {
		var st = this.st, self = this;
		var now = raw.at || Date.now();
		st.clock = model.sampleClock(st.clock, now, raw.info && raw.info.localtime);
		var at = st.clock.at;

		/* CPU */
		var stat = model.parseStat(raw.stat);
		if (stat) {
			var cpu = model.cpuUsage(st.stat, stat);
			if (cpu) { st.cpu = cpu; series.push(st.hist.cpu, [ at, cpu.pct ], WINDOW_MS, HIST_MAX); }
			if (!st.stat || stat.all.total !== st.stat.all.total) st.stat = stat;
		}

		var m = model.build({
			board: this.board, info: raw.info, ifaces: raw.ifaces, devs: raw.devs, wifi: raw.wifi, iwinfo: raw.iwinfo,
			assoc: raw.assoc, hapd: raw.hapd, hapdStatus: raw.hapdStatus, hints: raw.hints,
			aliases: this.aliases, rdns: st.rdns, mdns: st.mdns,
			vendor: st.oui ? function(k) { return k ? st.oui.lookup(k) : null; } : null
		});
		if (m.device.memory) series.push(st.hist.mem, [ at, m.device.memory.usedPct ], WINDOW_MS, HIST_MAX);

		/* interface counters */
		var devCounters = Object.create(null);
		Object.keys(raw.devs || {}).forEach(function(n) {
			var s = raw.devs[n] && raw.devs[n].statistics;
			if (s) devCounters[n] = { rx: s.rx_bytes, tx: s.tx_bytes };
		});
		var dr = model.rates(st.devPrev, devCounters, at);
		st.devPrev = dr.next;
		if (Object.keys(dr.rates).length || !Object.keys(devCounters).length) st.devRates = dr.rates;

		function sum(list) {
			var rx = 0, tx = 0, ok = false;
			list.forEach(function(n) { var r = st.devRates[n]; if (r) { rx += r.rx; tx += r.tx; ok = true; } });
			return ok ? { rx: rx, tx: tx } : null;
		}
		st.radioRates = Object.create(null);
		m.radios.forEach(function(r) { var v = sum(r.ifnames); if (v) st.radioRates[r.id] = v; });
		st.ssidRates = Object.create(null);
		m.ssids.forEach(function(s) { var v = s.ifname ? sum([ s.ifname ]) : null; if (v) st.ssidRates[s.id] = v; });
		var upRate = m.uplink ? st.devRates[m.uplink.statsDev] : null;
		st.uplinkRate = upRate || null;

		/* throughput history (only for ticks that produced a rate) */
		if (upRate) this.pushNet('uplink', at, upRate);
		m.radios.forEach(function(r) { if (st.radioRates[r.id]) self.pushNet(r.id, at, st.radioRates[r.id]); });

		/* station counters, per-station history */
		var staCounters = Object.create(null);
		m.clients.forEach(function(c) { staCounters[c.mac] = { rx: c.rxBytes, tx: c.txBytes }; });
		var sr = model.rates(st.staPrev, staCounters, at);
		st.staPrev = sr.next;
		if (Object.keys(sr.rates).length || !m.clients.length) st.staRates = sr.rates;
		m.clients.forEach(function(c) {
			var h = st.clientHist[c.mac] || (st.clientHist[c.mac] = []);
			var r = st.staRates[c.mac];
			series.push(h, [ at, c.signal != null ? -c.signal : NaN, r ? r.tx : NaN, r ? r.rx : NaN ], 10 * 60 * 1000, 150);
		});

		/* presence: new since the page opened, recently gone */
		var p = insight.presence(st.presence, m.clients, now, GONE_KEEP_MS);
		st.presence = p.state;
		st.isNew = p.isNew;
		st.gone = p.gone;
		Object.keys(st.clientHist).forEach(function(mac) {
			if (!p.state.firstSeen[mac]) delete st.clientHist[mac];
		});

		/* per-station history is kept for the session (60 points each,
		   stations seen in the last minutes only) */
		var keepClients = {};
		Object.keys(st.clientHist).slice(0, 32).forEach(function(mac) {
			keepClients[mac] = st.clientHist[mac].slice(-60).filter(function(p) { return p.every(function(v) { return isFinite(v); }); });
		});
		writeStore({ net: st.hist.net, cpu: st.hist.cpu, mem: st.hist.mem, clients: keepClients });

		this.stickyGen(m);
		m.clients.forEach(function(c) { c.exp = insight.experience(c); c.firstSeen = p.state.firstSeen[c.mac]; c.isNew = !!p.isNew[c.mac]; });
		st.health = insight.health(m, { cpu: st.cpu, uplinkRate: st.uplinkRate });
		st.summary = insight.summary(st.health);
		st.radioInsights = insight.radioInsights(m.radios, st.radioRates);
		st.talkers = insight.topTalkers(m.clients, st.staRates, 5);
		this.m = m;
		this.lastRaw = raw;
		this.resolveMore(m);
		return m;
	},

	/* The generation shown is the best standard a station used this
	   session: single frames (management, retries) go out at legacy
	   rates and would make the badge flicker. */
	stickyGen: function(m) {
		var best = this.st.bestStd, order = [ 'legacy', 'HT', 'VHT', 'HE', 'EHT' ];
		m.clients.forEach(function(c) {
			var cur = order.indexOf(c.std), prev = order.indexOf(best[c.mac]);
			if (prev > cur) { c.std = best[c.mac]; c.gen = wifi.genName(c.std, c.band); }
			else if (cur >= 0) best[c.mac] = c.std;
		});
	},

	pushNet: function(key, at, r) {
		var h = this.st.hist.net[key] || (this.st.hist.net[key] = []);
		series.push(h, [ at, r.rx, r.tx ], WINDOW_MS, HIST_MAX);
	},

	/* names beyond what one poll carries: reverse DNS once per new
	   address, mDNS every minute when present, the vendor table once */
	resolveMore: function(m) {
		var st = this.st, self = this;
		var ips = [];
		m.clients.forEach(function(c) {
			c.ips.forEach(function(ip) { if (!(ip in st.rdns) && ips.indexOf(ip) < 0 && ips.length < 64) ips.push(ip); });
		});
		if (ips.length && !st.rdnsBusy && !st.rdnsOff) {
			st.rdnsBusy = true;
			ips.forEach(function(ip) { st.rdns[ip] = ''; });
			/* rpcd-mod-rrdns is optional: when the object or the grant is
			   missing the first call says so and reverse DNS stays off;
			   a timeout or a network error only skips this batch */
			callRrdns(ips, 1500, 1000).catch(function(e) {
				if (/ubus code [2-6]\b|error -320\d\d\b/.test(String(e && e.message))) st.rdnsOff = true;
				return {};
			}).then(function(res) {
				var hit = false;
				if (res && typeof res === 'object')
					Object.keys(res).forEach(function(ip) { if (typeof res[ip] === 'string' && ips.indexOf(ip) >= 0) { st.rdns[ip] = res[ip]; hit = true; } });
				if (hit) self.rerender();
			}).finally(function() { st.rdnsBusy = false; });
		}
		if (!st.mdnsOff && Date.now() - st.mdnsAt > 60000) {
			st.mdnsAt = Date.now();
			L.resolveDefault(callMdns(), null).then(function(r) { self.applyMdns(r); });
		}
		var wantVendor = m.clients.some(function(c) { return c.nameSource === 'mac'; });
		if (wantVendor && !st.oui && !st.ouiLoading) {
			st.ouiLoading = true;
			L.require('vantage.oui').then(function(mod) { st.oui = mod; self.rerender(); }).catch(function() {});
		}
	},

	/* rebuild the model from the last replies (names changed) */
	rerender: function() {
		if (!this.lastRaw) return;
		var st = this.st, raw = this.lastRaw;
		var m = model.build({
			board: this.board, info: raw.info, ifaces: raw.ifaces, devs: raw.devs, wifi: raw.wifi, iwinfo: raw.iwinfo,
			assoc: raw.assoc, hapd: raw.hapd, hapdStatus: raw.hapdStatus, hints: raw.hints,
			aliases: this.aliases, rdns: st.rdns, mdns: st.mdns,
			vendor: st.oui ? function(k) { return k ? st.oui.lookup(k) : null; } : null
		});
		this.stickyGen(m);
		m.clients.forEach(function(c) { c.exp = insight.experience(c); c.firstSeen = st.presence && st.presence.firstSeen[c.mac]; c.isNew = !!st.isNew[c.mac]; });
		st.talkers = insight.topTalkers(m.clients, st.staRates, 5);
		st.health = insight.health(m, { cpu: st.cpu, uplinkRate: st.uplinkRate });
		st.summary = insight.summary(st.health);
		this.m = m;
		this.paint();
	},

	refresh: function() {
		var self = this;
		if (document.hidden) { this.st.paused = true; this.paintLive(); return Promise.resolve(); }
		this.st.paused = false;
		return this.fetch().then(function(raw) {
			self.ingest(raw);
			self.st.lastOk = Date.now();
			self.st.lastErr = null;
			self.paint();
		}).catch(function(err) {
			self.st.lastErr = err;
			self.paintLive();
		});
	},

	/* ----------------------------------------------------------- render */

	render: function(data) {
		var self = this;
		this.initState(data);
		this.ingest(data.raw);
		this.st.lastOk = Date.now();

		this.el = {};
		/* .vt-body is the size container for the layout; the drawer stays
		   outside it (a size container would trap position: fixed) */
		var root = E('div', { 'class': 'vt-app', 'id': 'vt-app' }, [
			E('div', { 'class': 'vt-body' }, [
				this.buildHead(),
				this.el.health = E('div', { 'class': 'vt-health', 'role': 'list', 'aria-label': _('Health checks') }),
				E('div', { 'class': 'vt-grid' }, [
					this.buildHero(),
					this.buildSystem(),
					this.buildChart(),
					this.buildRadios(),
					this.buildClients(),
					E('div', { 'class': 'vt-side' }, [ this.buildTalkers(), this.buildSsids() ])
				])
			]),
			this.buildDrawer()
		]);
		this.el.root = root;

		this.paint();

		poll.add(L.bind(this.refresh, this), POLL_S);
		document.addEventListener('visibilitychange', function() {
			if (!document.hidden && self.st.paused) self.refresh();
			else self.paintLive();
		});
		document.addEventListener('keydown', L.bind(this.handleKey, this));
		window.setInterval(function() { self.paintLive(); }, 1000);
		if (window.ResizeObserver) new ResizeObserver(function() { self.scheduleWires(); }).observe(this.el.path);
		window.addEventListener('hashchange', function() { self.openFromHash(); });
		window.requestAnimationFrame(function() { self.drawWires(); self.openFromHash(); });
		return root;
	},

	paint: function() {
		this.paintHead();
		this.paintHealth();
		this.paintHero();
		this.paintSystem();
		this.paintChart();
		this.paintRadios();
		this.paintClients();
		this.paintTalkers();
		this.paintSsids();
		this.paintDrawer();
		this.paintLive();
		this.scheduleWires();
	},

	/* ------------------------------------------------------------ folds */

	foldButton: function(key, label) {
		var self = this;
		var btn = E('button', { 'type': 'button', 'class': 'vt-fold-btn', 'aria-expanded': 'true', 'aria-label': label, 'title': label,
			'click': function() { self.toggleFold(key); } }, [ icon('chevron') ]);
		this.foldBtns[key] = btn;
		return btn;
	},

	foldable: function(key, el) {
		this.foldEls[key] = el;
		el.classList.add('vt-fold');
		this.applyFold(key);
		return el;
	},

	applyFold: function(key) {
		var folded = !!this.folds[key], el = this.foldEls[key], btn = this.foldBtns[key];
		if (el) el.classList.toggle('vt-folded', folded);
		if (btn) btn.setAttribute('aria-expanded', String(!folded));
	},

	toggleFold: function(key) {
		this.folds[key] = !this.folds[key];
		writeFolds(this.folds);
		this.applyFold(key);
		if (key === 'hero') this.scheduleWires();
		if (key === 'chart') this.paintChart();
	},

	/* ------------------------------------------------------------- head */

	buildHead: function() {
		var el = this.el;
		return E('header', { 'class': 'vt-head' }, [
			el.orb = E('span', { 'class': 'vt-orb' }, [ E('span', { 'class': 'vt-orb-core' }) ]),
			E('div', { 'class': 'vt-head-text' }, [
				el.headline = E('h2', { 'class': 'vt-headline' }),
				el.subline = E('p', { 'class': 'vt-subline' })
			]),
			el.live = E('div', { 'class': 'vt-livepill', 'role': 'status', 'aria-live': 'off' }, [
				E('span', { 'class': 'vt-live-beat' }),
				el.liveText = E('span', { 'class': 'vt-live-text' })
			])
		]);
	},

	paintHead: function() {
		var s = this.st.summary, d = this.m.device;
		this.el.orb.className = 'vt-orb vt-orb-' + s.level;
		txt(this.el.headline, s.headline);
		var clients = this.m.clients.length;
		txt(this.el.subline, [ d.model, d.hostname, d.firmware ? d.firmware.replace(/\s+r\d+-[0-9a-f]+$/, '') : null,
			clients === 1 ? _('1 client') : _('%d clients').format(clients) ].filter(Boolean).join('  ·  '));
	},

	paintLive: function() {
		if (!this.el || !this.el.live) return;
		var st = this.st, state, label;
		if (st.paused || document.hidden) { state = 'paused'; label = _('Paused while hidden'); }
		else if (st.lastErr) { state = 'err'; label = _('Reconnecting…'); }
		else { state = 'ok'; label = _('Live') + ' · ' + fmt.ago(Date.now() - st.lastOk); }
		this.el.live.className = 'vt-livepill vt-live-' + state;
		this.el.live.setAttribute('title', label);
		txt(this.el.liveText, label);
	},

	/* ----------------------------------------------------------- health */

	paintHealth: function() {
		var self = this;
		dom.content(this.el.health, this.st.health.map(function(c) {
			var ic = c.level === 'ok' ? 'check' : c.level === 'err' ? 'err' : c.level === 'warn' ? 'warn' : 'info';
			var body = [
				E('span', { 'class': 'vt-chip-ico' }, [ icon(ic) ]),
				E('span', { 'class': 'vt-chip-main' }, [
					E('span', { 'class': 'vt-chip-top' }, [ E('span', { 'class': 'vt-chip-title' }, [ c.title ]), E('span', { 'class': 'vt-chip-value' }, [ c.value ]) ]),
					E('span', { 'class': 'vt-chip-reason' }, [ c.reason ])
				])
			];
			if (c.client)
				return E('button', { 'type': 'button', 'class': 'vt-chip vt-chip-' + c.level, 'role': 'listitem', 'title': c.detail || c.reason,
					'click': function() { self.openDrawer('client', c.client); } }, body);
			return E('a', { 'class': 'vt-chip vt-chip-' + c.level, 'role': 'listitem', 'title': c.detail || c.reason, 'href': L.url.apply(L, c.page) }, body);
		}));
	},

	/* ------------------------------------------------------------- hero */

	buildHero: function() {
		var self = this, el = this.el;
		el.path = E('div', { 'class': 'vt-path' });
		el.wires = svgRoot('vt-wires', '0 0 10 10');
		el.path.appendChild(el.wires);
		this.wireMap = {};
		el.kpis = E('div', { 'class': 'vt-kpis vt-fold-keep' });
		return this.foldable('hero', E('section', { 'class': 'vt-tile vt-hero', 'aria-label': _('Network path') }, [
			tileHead('pulse', _('Network path'), [ E('span', { 'class': 'vt-hint vt-hint-wide' }, [ _('Click any node for details') ]), this.foldButton('hero', _('Show or hide the network path')) ]),
			el.path,
			el.kpis
		]));
	},

	paintHero: function() {
		var self = this, m = this.m, st = this.st, up = m.uplink, path = this.el.path;
		var up_r = st.uplinkRate;

		/* keep the wires layer, rebuild the nodes (cheap, a dozen elements) */
		while (path.lastChild && path.lastChild !== this.el.wires) path.removeChild(path.lastChild);
		while (path.firstChild && path.firstChild !== this.el.wires) path.removeChild(path.firstChild);

		this.nodes = {};
		var gw = E('button', { 'type': 'button', 'class': 'vt-node vt-node-gw', 'click': function() { self.openDrawer('uplink', 'uplink'); } }, [
			E('span', { 'class': 'vt-node-ico' }, [ icon('globe') ]),
			E('span', { 'class': 'vt-node-body' }, [
				E('span', { 'class': 'vt-node-kicker' }, [ up && up.isWan ? _('Internet') : _('Gateway') ]),
				E('span', { 'class': 'vt-node-title' }, [ up && up.gateway ? up.gateway : _('No default route') ]),
				E('span', { 'class': 'vt-node-sub' }, [ up && up.dns.length ? _('DNS %s').format(up.dns[0]) : _('Reachability not probed') ])
			])
		]);
		this.nodes.gw = gw;

		var link = E('div', { 'class': 'vt-link-label' }, [
			E('span', { 'class': 'vt-link-rate vt-link-down' }, [ icon('down'), E('b', {}, [ up_r ? fmt.bitsParts(up_r.rx).v : fmt.DASH ]), E('small', {}, [ up_r ? fmt.bitsParts(up_r.rx).u : '' ]) ]),
			E('span', { 'class': 'vt-link-below' }, [
			E('span', { 'class': 'vt-link-rate vt-link-up' }, [ icon('up'), E('b', {}, [ up_r ? fmt.bitsParts(up_r.tx).v : fmt.DASH ]), E('small', {}, [ up_r ? fmt.bitsParts(up_r.tx).u : '' ]) ]),
			E('span', { 'class': 'vt-link-meta' }, [ up ? [ up.dev, up.speed ? (up.speed.mbps >= 1000 ? (up.speed.mbps / 1000) + 'G' : up.speed.mbps + 'M') + (up.speed.duplex === 'full' ? ' FD' : up.speed.duplex === 'half' ? ' HD' : '') : null ].filter(Boolean).join(' · ') : _('no uplink') ])
			])
		]);

		var d = m.device;
		var ap = E('button', { 'type': 'button', 'class': 'vt-node vt-node-ap', 'click': function() { self.openDrawer('device', 'device'); } }, [
			E('span', { 'class': 'vt-node-ico' }, [ icon('ap') ]),
			E('span', { 'class': 'vt-node-body' }, [
				E('span', { 'class': 'vt-node-kicker' }, [ _('This access point') ]),
				E('span', { 'class': 'vt-node-title' }, [ d.model ]),
				E('span', { 'class': 'vt-node-sub vt-mono' }, [ up && up.ipv4[0] ? up.ipv4[0].split('/')[0] : fmt.DASH ]),
				E('span', { 'class': 'vt-node-sub' }, [ d.uptime != null ? _('up %s').format(fmt.duration(d.uptime)) : '' ])
			])
		]);
		this.nodes.ap = ap;

		var branches = E('div', { 'class': 'vt-branches' });
		this.nodes.radios = [];
		m.radios.forEach(function(r) {
			var rr = st.radioRates[r.id];
			var rnode = E('button', { 'type': 'button', 'class': 'vt-node vt-node-radio' + (r.up ? '' : ' vt-node-off'), 'click': function() { self.openDrawer('radio', r.id); } }, [
				E('span', { 'class': 'vt-node-body' }, [
					E('span', { 'class': 'vt-node-kicker' }, [ bandBadge(r.band), E('span', { 'class': 'vt-node-gen' }, [ r.gen || '' ]) ]),
					E('span', { 'class': 'vt-node-title vt-tn' }, [ r.channel ? _('Ch %d · %d MHz').format(r.channel, r.width || 20) : _('Channel —') ]),
					E('span', { 'class': 'vt-node-sub vt-tn' }, [ r.disabled ? _('Disabled') : !r.up ? _('Down') : rr ? '↓ ' + fmt.bits(rr.tx) : fmt.DASH ])
				])
			]);
			var ssidCol = E('div', { 'class': 'vt-branch-ssids' });
			var ssNodes = [];
			m.ssids.filter(function(s) { return s.radio === r.id; }).forEach(function(s) {
				var dots = E('span', { 'class': 'vt-dots' });
				m.clients.filter(function(c) { return c.ssidId === s.id; }).slice(0, 8).forEach(function(c) {
					var dot = E('span', { 'class': 'vt-dot vt-lvl-' + c.level.level, 'title': c.name + ' · ' + fmt.dbm(c.signal) });
					dots.appendChild(dot);
				});
				var sn = E('button', { 'type': 'button', 'class': 'vt-node vt-node-ssid' + (s.clients ? '' : ' vt-node-idle'), 'title': _('Show the clients of %s').format(s.ssid),
					'click': function() { self.filterSsid(s.ssid, s.band); } }, [
					E('span', { 'class': 'vt-node-body' }, [
						E('span', { 'class': 'vt-node-title vt-ssid-name' }, [ icon(s.security.tone === 'open' ? 'unlock' : 'lock', 'vt-ico-sm'), E('span', {}, [ s.ssid || _('(hidden)') ]) ]),
						E('span', { 'class': 'vt-node-sub' }, [ dots, E('span', { 'class': 'vt-tn' }, [ s.clients === 1 ? _('1 client') : _('%d clients').format(s.clients) ]) ])
					])
				]);
				ssNodes.push({ el: sn, active: !!(st.ssidRates[s.id] && st.ssidRates[s.id].rx + st.ssidRates[s.id].tx > 50e3) });
				ssidCol.appendChild(sn);
			});
			if (!ssNodes.length) ssidCol.appendChild(E('span', { 'class': 'vt-empty-inline' }, [ _('No SSIDs') ]));
			self.nodes.radios.push({ el: rnode, ssids: ssNodes, active: !!(rr && rr.rx + rr.tx > 50e3), rate: rr ? rr.rx + rr.tx : 0 });
			branches.appendChild(E('div', { 'class': 'vt-branch' }, [ rnode, ssidCol ]));
		});
		if (!m.radios.length) branches.appendChild(E('div', { 'class': 'vt-empty-inline' }, [ _('No radios reported') ]));

		this.nodes.upActive = !!(up_r && up_r.rx + up_r.tx > 50e3);
		this.nodes.upRate = up_r ? up_r.rx + up_r.tx : 0;
		path.insertBefore(gw, this.el.wires);
		path.insertBefore(link, this.el.wires);
		path.insertBefore(ap, this.el.wires);
		path.insertBefore(branches, this.el.wires);
		this.paintKpis();
	},

	/* four numbers under the path: who is here, what flows, where, and
	   who is worst off */
	paintKpis: function() {
		var self = this, m = this.m, st = this.st, up = st.uplinkRate;
		var byBand = {};
		m.clients.forEach(function(c) { byBand[c.band] = (byBand[c.band] || 0) + 1; });
		var bandText = Object.keys(byBand).sort().map(function(b) { return _('%d on %s').format(byBand[b], wifi.bandLabel(b)); }).join(' · ');
		var busiest = null;
		m.radios.forEach(function(r) { var i = st.radioInsights[r.id]; if (i && i.busiest) busiest = { r: r, share: i.share }; });
		var weakest = m.clients.filter(function(c) { return c.signal != null; }).sort(function(a, b) { return a.signal - b.signal; })[0];

		function kpi(label, value, sub, tone, onclick) {
			var body = [ E('span', { 'class': 'vt-kpi-label' }, [ label ]), E('span', { 'class': 'vt-kpi-value vt-tn' }, [ value ]), E('span', { 'class': 'vt-kpi-sub' }, [ sub ]) ];
			return onclick
				? E('button', { 'type': 'button', 'class': 'vt-kpi vt-kpi-' + (tone || 'plain'), 'click': onclick }, body)
				: E('div', { 'class': 'vt-kpi vt-kpi-' + (tone || 'plain') }, body);
		}
		dom.content(this.el.kpis, [
			kpi(_('Clients'), String(m.clients.length), bandText || _('none connected'), 'plain', function() { self.el.clients.scrollIntoView({ behavior: reducedMotion() ? 'auto' : 'smooth', block: 'start' }); }),
			kpi(_('Traffic now'), up ? '↓ ' + fmt.bits(up.rx) : fmt.DASH, up ? _('↑ %s · via %s').format(fmt.bits(up.tx), m.uplink ? m.uplink.dev : '') : _('measuring'), 'plain', function() { self.openDrawer('uplink', 'uplink'); }),
			busiest ? kpi(_('Busiest radio'), busiest.r.bandLabel, _('%s of Wi-Fi traffic').format(fmt.pct(busiest.share * 100)), 'plain', function() { self.openDrawer('radio', busiest.r.id); })
				: kpi(_('Busiest radio'), fmt.DASH, _('no Wi-Fi traffic yet'), 'plain'),
			weakest ? kpi(_('Weakest signal'), fmt.dbm(weakest.signal), weakest.name, weakest.signal < insight.WEAK_DBM ? 'warn' : 'plain', function() { self.openDrawer('client', weakest.mac); })
				: kpi(_('Weakest signal'), fmt.DASH, _('no clients'), 'plain')
		]);
	},

	scheduleWires: function() {
		var self = this;
		if (this.wirePending) return;
		this.wirePending = true;
		window.requestAnimationFrame(function() { self.wirePending = false; self.drawWires(); });
	},

	/* connectors between the hero nodes, measured after layout; wires are
	   kept by key so the flow animation does not restart every poll */
	drawWires: function() {
		var path = this.el && this.el.path, svg = this.el && this.el.wires, n = this.nodes;
		if (!path || !svg || !n || !path.isConnected) return;
		var box = path.getBoundingClientRect();
		if (!box.width) return;
		svg.setAttribute('viewBox', '0 0 ' + Math.round(box.width) + ' ' + Math.round(box.height));
		svg.setAttribute('width', String(Math.round(box.width)));
		svg.setAttribute('height', String(Math.round(box.height)));

		function rect(el) {
			var r = el.getBoundingClientRect();
			return { l: r.left - box.left, r: r.right - box.left, t: r.top - box.top, b: r.bottom - box.top, cy: (r.top + r.bottom) / 2 - box.top };
		}
		function curve(a, b) {
			var x1, y1, x2, y2;
			if (b.l >= a.r - 2) {
				x1 = a.r; y1 = a.cy; x2 = b.l; y2 = b.cy;
				var mx = (x1 + x2) / 2;
				return 'M' + x1.toFixed(1) + ' ' + y1.toFixed(1) + 'C' + mx.toFixed(1) + ' ' + y1.toFixed(1) + ' ' + mx.toFixed(1) + ' ' + y2.toFixed(1) + ' ' + x2.toFixed(1) + ' ' + y2.toFixed(1);
			}
			/* stacked layout: an elbow down the left edge */
			x1 = a.l + 18; y1 = a.b; x2 = b.l; y2 = b.cy;
			if (x2 <= x1 + 6) return 'M' + x1.toFixed(1) + ' ' + y1.toFixed(1) + 'V' + b.t.toFixed(1);
			var rad = Math.min(8, Math.max(0, y2 - y1));
			return 'M' + x1.toFixed(1) + ' ' + y1.toFixed(1) + 'V' + (y2 - rad).toFixed(1) + 'Q' + x1.toFixed(1) + ' ' + y2.toFixed(1) + ' ' + (x1 + rad).toFixed(1) + ' ' + y2.toFixed(1) + 'H' + x2.toFixed(1);
		}
		function speed(bps) { return bps > 100e6 ? 3 : bps > 5e6 ? 2 : 1; }

		var want = [];
		want.push({ key: 'gw', d: curve(rect(n.gw), rect(n.ap)), active: n.upActive, speed: speed(n.upRate), main: true });
		n.radios.forEach(function(r, i) {
			var rr = rect(r.el);
			want.push({ key: 'r' + i, d: curve(rect(n.ap), rr), active: r.active, speed: speed(r.rate) });
			r.ssids.forEach(function(s, j) { want.push({ key: 'r' + i + 's' + j, d: curve(rr, rect(s.el)), active: s.active, speed: 1 }); });
		});

		var seen = {}, map = this.wireMap;
		want.forEach(function(w) {
			seen[w.key] = true;
			var g = map[w.key];
			if (!g) {
				g = map[w.key] = { base: svgPath('', 'vt-wire'), flow: svgPath('', 'vt-flow') };
				svg.appendChild(g.base);
				svg.appendChild(g.flow);
			}
			if (g.d !== w.d) { g.base.setAttribute('d', w.d); g.flow.setAttribute('d', w.d); g.d = w.d; }
			g.base.setAttribute('class', 'vt-wire' + (w.main ? ' vt-wire-main' : '') + (w.active ? ' vt-wire-on' : ''));
			g.flow.setAttribute('class', 'vt-flow vt-flow-' + w.speed + (w.active ? ' vt-flow-on' : ''));
		});
		Object.keys(map).forEach(function(k) {
			if (seen[k]) return;
			svg.removeChild(map[k].base);
			svg.removeChild(map[k].flow);
			delete map[k];
		});
	},

	/* ----------------------------------------------------------- system */

	buildSystem: function() {
		var el = this.el;
		el.sysUptime = E('span', { 'class': 'vt-hint vt-tn' });
		el.cpuVal = E('span', { 'class': 'vt-big vt-tn' });
		el.cpuCores = E('div', { 'class': 'vt-cores' });
		el.cpuSpark = E('div', { 'class': 'vt-spark-slot' });
		el.cpuLoad = E('span', { 'class': 'vt-hint vt-tn', 'title': _('Load average over 1, 5 and 15 minutes') });
		el.memHead = E('div', { 'class': 'vt-mem-head' });
		el.memBar = E('div', { 'class': 'vt-seg', 'role': 'img' });
		el.memLegend = E('div', { 'class': 'vt-legend' });
		el.swap = E('div', { 'class': 'vt-swap' });
		el.storage = E('div', { 'class': 'vt-storage' });
		el.fw = E('div', { 'class': 'vt-fw' });
		return this.foldable('sys', E('section', { 'class': 'vt-tile vt-sys', 'aria-label': _('System') }, [
			tileHead('cpu', _('System'), [ el.sysUptime, this.foldButton('sys', _('Show or hide system details')) ]),
			E('div', { 'class': 'vt-sys-cpu' }, [
				E('div', { 'class': 'vt-sys-cpu-l' }, [
					E('span', { 'class': 'vt-label' }, [ _('CPU') ]),
					el.cpuVal,
					el.cpuLoad
				]),
				E('div', { 'class': 'vt-sys-cpu-r' }, [
					E('div', { 'class': 'vt-spark-box' }, [ el.cpuSpark, E('span', { 'class': 'vt-cap' }, [ _('last 5 min') ]) ]),
					E('div', { 'class': 'vt-cores-box', 'title': _('Busy share of each CPU core') }, [ el.cpuCores, E('span', { 'class': 'vt-cap' }, [ _('per core') ]) ])
				])
			]),
			E('div', { 'class': 'vt-sys-mem' }, [
				E('span', { 'class': 'vt-label' }, [ _('Memory') ]),
				el.memHead, el.memBar, el.memLegend, el.swap
			]),
			E('div', { 'class': 'vt-sys-store' }, [ E('span', { 'class': 'vt-label' }, [ _('Storage') ]), el.storage ]),
			el.fw
		]));
	},

	paintSystem: function() {
		var el = this.el, d = this.m.device, cpu = this.st.cpu;
		txt(el.sysUptime, d.uptime != null ? _('Up %s').format(fmt.duration(d.uptime)) : '');
		txt(el.cpuVal, cpu ? Math.round(cpu.pct) + '%' : fmt.DASH);
		el.cpuVal.className = 'vt-big vt-tn' + (cpu && cpu.pct >= 90 ? ' vt-t-err' : cpu && cpu.pct >= 70 ? ' vt-t-warn' : '');
		txt(el.cpuLoad, _('Load avg %s').format(d.load.map(fmt.load).join(' · ')));
		dom.content(el.cpuSpark, [ sparkline(this.st.hist.cpu, [ 1 ], 100, 'vt-spark-cpu', { scale: function() { return '100%'; } }) ]);
		dom.content(el.cpuCores, (cpu ? cpu.cores : []).map(function(p, i) {
			var fill = E('span', { 'class': 'vt-core-fill' });
			fill.style.height = Math.max(4, Math.min(100, p || 0)).toFixed(1) + '%';
			return E('span', { 'class': 'vt-core', 'title': _('Core %d: %s').format(i, fmt.pct(p)) }, [ fill ]);
		}));

		/* memory: one bar, three named segments */
		var mem = d.memory;
		if (mem) {
			dom.content(el.memHead, [
				E('span', { 'class': 'vt-mem-avail vt-tn' }, [ _('%s available').format(fmt.pct(mem.availPct)) ]),
				E('span', { 'class': 'vt-mem-of vt-tn' }, [ _('%s of %s').format(fmt.bytes(mem.available), fmt.bytes(mem.total)) ])
			]);
			if (!el.memSegs) {
				el.memSegs = mem.segments.map(function(s) { var x = E('span', { 'class': 'vt-seg-part vt-seg-' + s.key }); el.memBar.appendChild(x); return x; });
			}
			mem.segments.forEach(function(s, i) { setW(el.memSegs[i], s.pct); el.memSegs[i].setAttribute('title', s.label + ': ' + fmt.bytes(s.bytes)); });
			el.memBar.setAttribute('aria-label', mem.segments.map(function(s) { return s.label + ' ' + fmt.bytes(s.bytes); }).join(', '));
			dom.content(el.memLegend, mem.segments.map(function(s) {
				return E('span', { 'class': 'vt-legend-item' }, [ E('span', { 'class': 'vt-key vt-seg-' + s.key }), E('span', {}, [ s.label ]), E('b', { 'class': 'vt-tn' }, [ fmt.bytes(s.bytes) ]) ]);
			}));
		}
		else {
			dom.content(el.memHead, [ E('span', { 'class': 'vt-muted' }, [ _('Not reported') ]) ]);
		}
		if (d.swap) {
			var sb = E('span', { 'class': 'vt-thin-fill' });
			setW(sb, d.swap.usedPct);
			dom.content(el.swap, [ E('span', { 'class': 'vt-swap-label' }, [ _('Swap') ]), E('span', { 'class': 'vt-thin' }, [ sb ]),
				E('span', { 'class': 'vt-tn vt-hint' }, [ _('%s of %s').format(fmt.bytes(d.swap.used), fmt.bytes(d.swap.total)) ]) ]);
		}
		else dom.content(el.swap, []);

		dom.content(el.storage, d.storage.map(function(s) {
			var f = E('span', { 'class': 'vt-bar-fill' + (s.usedPct >= 95 ? ' vt-bg-err' : s.usedPct >= 85 ? ' vt-bg-warn' : '') });
			setW(f, Math.max(s.usedPct, 0.8));
			return E('div', { 'class': 'vt-mount' }, [
				E('div', { 'class': 'vt-mount-top' }, [ E('span', {}, [ s.label ]), E('span', { 'class': 'vt-tn vt-hint' }, [ _('%s used of %s').format(fmt.bytes(s.used), fmt.bytes(s.total)) ]) ]),
				E('div', { 'class': 'vt-bar' }, [ f ])
			]);
		}));
		dom.content(el.fw, [
			E('span', {}, [ d.firmware || '' ]),
			d.kernel ? E('span', { 'class': 'vt-hint' }, [ _('Kernel %s').format(d.kernel) ]) : ''
		]);
	},

	/* ------------------------------------------------------------ chart */

	buildChart: function() {
		var self = this, el = this.el;
		el.chartSub = E('span', { 'class': 'vt-chart-sub vt-tn' });
		el.chartRows = E('div', { 'class': 'vt-mults' });
		el.chartCursor = E('div', { 'class': 'vt-cursor', 'hidden': 'hidden' });
		el.chartTip = E('div', { 'class': 'vt-tip', 'hidden': 'hidden' });
		el.chartOver = E('div', { 'class': 'vt-mult-over', 'aria-hidden': 'true' }, [ el.chartCursor, el.chartTip ]);
		el.chartX = E('div', { 'class': 'vt-mult-x', 'aria-hidden': 'true' });
		el.chartBtns = {};
		var seg = E('div', { 'class': 'vt-seg-ctl', 'role': 'group', 'aria-label': _('Direction') }, [ 'down', 'up' ].map(function(k) {
			return el.chartBtns[k] = E('button', { 'type': 'button', 'class': 'vt-seg-btn', 'aria-pressed': 'false',
				'click': function() { self.ui.chart = k; self.paintChart(); } }, [ icon(k), E('span', {}, [ k === 'down' ? _('Download') : _('Upload') ]) ]);
		}));
		var plot = E('div', { 'class': 'vt-mult-wrap', 'tabindex': '0', 'role': 'group',
			'aria-label': _('Throughput per link; arrow keys read the values over time') }, [ el.chartRows, el.chartOver, el.chartX ]);
		plot.addEventListener('pointermove', function(ev) { self.chartPointer(ev); });
		plot.addEventListener('pointerleave', function() { if (!self.ui.hover || self.ui.hover.x != null) self.chartHide(); });
		plot.addEventListener('keydown', function(ev) { self.chartKey(ev); });
		plot.addEventListener('blur', function() { self.chartHide(); });
		el.plot = plot;
		el.chartLive = E('p', { 'class': 'vt-sr', 'aria-live': 'polite' });
		return this.foldable('chart', E('section', { 'class': 'vt-tile vt-chart', 'aria-label': _('Throughput') }, [
			E('header', { 'class': 'vt-tile-head' }, [
				E('h3', { 'class': 'vt-tile-title' }, [ icon('pulse'), E('span', {}, [ _('Throughput') ]), el.chartSub ]),
				E('div', { 'class': 'vt-tile-extra' }, [ seg, this.foldButton('chart', _('Show or hide the throughput chart')) ])
			]),
			plot,
			el.chartLive
		]));
	},

	/* one small multiple per link: the uplink, then each radio. Each has
	   its own y scale (a busy uplink would flatten an idle radio), labelled
	   with its unit, on a shared time axis and crosshair. */
	chartSeries: function() {
		var m = this.m, down = this.ui.chart === 'down';
		var list = [ { key: 'uplink', label: m.uplink ? _('Uplink %s').format(m.uplink.dev) : _('Uplink'), cls: 'vt-c-up', col: down ? 1 : 2 } ];
		m.radios.forEach(function(r) { list.push({ key: r.id, label: _('%s radio').format(r.bandLabel), cls: 'vt-c-' + (r.band || 'x'), col: down ? 2 : 1 }); });
		return list;
	},

	paintChart: function() {
		var self = this, el = this.el, net = this.st.hist.net, W = 600, H = 100, now = Date.now();
		var list = this.chartSeries(), down = this.ui.chart === 'down';
		Object.keys(el.chartBtns).forEach(function(k) { el.chartBtns[k].setAttribute('aria-pressed', String(self.ui.chart === k)); });

		var dm = series.domain(list.map(function(s) { return net[s.key]; }), now, 60000, WINDOW_MS);
		var ticks = [];
		for (var k = 1; k * 60000 < dm.span - 20000; k++) ticks.push(k);
		var rows = [], samples = 0;
		this.chartMeta = { t0: dm.t0, t1: dm.t1, rows: rows };

		dom.content(el.chartRows, list.map(function(s) {
			var d = (net[s.key] || []).filter(function(p) { return p[0] >= dm.t0 - POLL_S * 1000; });
			var st = series.stats(d, s.col, dm.t0);
			var last = d.length ? d[d.length - 1] : null, fresh = !!(last && now - last[0] < POLL_S * 3000);
			var vmax = series.niceCeil(Math.max((st.peak || 0) * 1.05, 1000));
			samples = Math.max(samples, st.n);

			var svg = svgRoot('vt-mult-svg', '0 0 ' + W + ' ' + H);
			svg.setAttribute('preserveAspectRatio', 'none');
			svg.appendChild(svgPath('M0 0.5H' + W + 'M0 ' + (H / 2) + 'H' + W, 'vt-chart-grid'));
			ticks.forEach(function(k) {
				var x = (1 - k * 60000 / dm.span) * W;
				svg.appendChild(svgPath('M' + x.toFixed(1) + ' 0V' + H, 'vt-chart-vgrid'));
			});
			var segs = series.segments(d, s.col, dm.t0, dm.t1, vmax, W, H, POLL_S * 3500);
			var area = svgPath(series.areaPath(segs, H), 'vt-series-area');
			area.setAttribute('fill', fadeFill(svg));
			svg.appendChild(area);
			svg.appendChild(svgPath(series.linePath(segs), 'vt-series-line'));

			var tail = segs.length ? segs[segs.length - 1] : null, pt = tail && tail[tail.length - 1];
			var dot = E('span', { 'class': 'vt-mult-dot', 'hidden': 'hidden' });
			rows.push({ s: s, d: d, vmax: vmax, dot: dot });
			return E('div', { 'class': 'vt-mult ' + s.cls }, [
				E('div', { 'class': 'vt-mult-head' }, [
					E('span', { 'class': 'vt-mult-name' }, [ E('span', { 'class': 'vt-lg-key' }), E('span', {}, [ s.label ]) ]),
					E('b', { 'class': 'vt-mult-now vt-tn' }, [ fresh && st.now != null ? fmt.bits(last[s.col]) : fmt.DASH ]),
					E('span', { 'class': 'vt-mult-stats vt-tn' }, st.n > 1 ? [
						E('span', {}, [ _('peak'), ' ', E('b', {}, [ fmt.bits(st.peak) ]) ]),
						E('span', {}, [ _('avg'), ' ', E('b', {}, [ fmt.bits(st.avg) ]) ])
					] : [ E('span', {}, [ _('measuring…') ]) ])
				]),
				E('div', { 'class': 'vt-mult-plot' }, [
					svg,
					st.n ? E('span', { 'class': 'vt-mult-max vt-tn' }, [ bitsLabel(vmax) ]) : '',
					st.n < 2 ? E('span', { 'class': 'vt-sk-note' }, [ _('collecting…') ]) : '',
					pt && fresh ? pos(E('span', { 'class': 'vt-sk-dot' }), pt[0] / W * 100, pt[1] / H * 100) : '',
					dot
				])
			]);
		}));

		/* minute ticks get a label unless it would collide with the ends */
		dom.content(el.chartX, [ E('span', { 'class': 'vt-mx vt-mx-0' }, [ spanAgo(dm.span) ]) ].concat(ticks.filter(function(k) {
			var f = 1 - k * 60000 / dm.span;
			return f > 0.2 && f < 0.85;
		}).map(function(k) {
			var l = E('span', { 'class': 'vt-mx vt-mx-t' + (k % 2 ? ' vt-mx-odd' : '') }, [ _('−%d min').format(k) ]);
			l.style.left = ((1 - k * 60000 / dm.span) * 100).toFixed(2) + '%';
			return l;
		})).concat([ E('span', { 'class': 'vt-mx vt-mx-1' }, [ _('now') ]) ]));

		var age = dm.age;
		txt(el.chartSub, (down ? _('to clients') : _('from clients')) + ' · ' + (dm.full ? _('last 5 min')
			: samples < 2 ? _('collecting · first samples') : _('collecting · %s of data').format(spanShort(age))));
		el.plot.classList.toggle('vt-collecting', !dm.full);
		if (this.ui.hover) this.chartShow(this.ui.hover);
	},

	chartPointer: function(ev) {
		var r = this.el.chartOver.getBoundingClientRect();
		if (!this.chartMeta || !r.width || ev.clientX < r.left - 6) { this.chartHide(); return; }
		this.chartShow({ x: Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width)) });
	},

	/* the longest series gives the sample times the crosshair snaps to */
	chartRef: function() {
		var ref = [];
		(this.chartMeta ? this.chartMeta.rows : []).forEach(function(r) { if (r.d.length > ref.length) ref = r.d; });
		return ref;
	},

	/* at: { x: 0..1 of the plot width } (pointer) or { t: sample time } (keys) */
	chartShow: function(at) {
		var meta = this.chartMeta, el = this.el;
		if (!meta) return;
		var ref = this.chartRef(), span = meta.t1 - meta.t0;
		var t = at.t != null ? at.t : meta.t0 + at.x * span;
		var i = series.nearest(ref, t);
		if (i < 0 || ref[i][0] < meta.t0 - 1000 || (at.x != null && Math.abs(ref[i][0] - t) > POLL_S * 2000)) { this.chartHide(); return; }
		var tp = ref[i][0], x = (tp - meta.t0) / span * 100;
		this.ui.hover = at.t != null ? { t: tp } : at;
		el.chartCursor.hidden = false;
		el.chartCursor.style.left = x.toFixed(2) + '%';
		var tipRows = meta.rows.map(function(r) {
			var j = series.nearest(r.d, tp), v = (j >= 0 && Math.abs(r.d[j][0] - tp) < POLL_S * 1000) ? r.d[j][r.s.col] : null;
			r.dot.hidden = v == null;
			if (v != null) pos(r.dot, x, (1 - Math.min(1, v / r.vmax)) * 100);
			return E('div', { 'class': 'vt-tip-row ' + r.s.cls }, [ E('span', { 'class': 'vt-lg-key' }), E('b', { 'class': 'vt-tn' }, [ v == null ? fmt.DASH : fmt.bits(v) ]), E('span', { 'class': 'vt-tip-label' }, [ r.s.label ]) ]);
		});
		dom.content(el.chartTip, [ E('div', { 'class': 'vt-tip-time vt-tn' }, [ new Date(tp).toLocaleTimeString(), E('span', {}, [ fmt.ago(Date.now() - tp) ]) ]) ].concat(tipRows));
		el.chartTip.hidden = false;
		el.chartTip.style.left = x.toFixed(2) + '%';
		el.chartTip.classList.toggle('vt-tip-left', x > 55);
		if (at.t != null) txt(el.chartLive, [ new Date(tp).toLocaleTimeString() ].concat(tipRows.map(function(r) { return r.textContent; })).join('; '));
	},

	chartHide: function() {
		var el = this.el;
		this.ui.hover = null;
		el.chartCursor.hidden = true;
		el.chartTip.hidden = true;
		(this.chartMeta ? this.chartMeta.rows : []).forEach(function(r) { r.dot.hidden = true; });
	},

	chartKey: function(ev) {
		var ref = this.chartRef(), meta = this.chartMeta;
		if (!ref.length || !meta) return;
		var cur = this.ui.hover && this.ui.hover.t != null ? series.nearest(ref, this.ui.hover.t) : -1, i = cur;
		if (ev.key === 'ArrowLeft') i = cur < 0 ? ref.length - 1 : Math.max(0, cur - 1);
		else if (ev.key === 'ArrowRight') i = cur < 0 ? ref.length - 1 : Math.min(ref.length - 1, cur + 1);
		else if (ev.key === 'Home') i = 0;
		else if (ev.key === 'End') i = ref.length - 1;
		else if (ev.key === 'Escape' && this.ui.hover) { ev.stopPropagation(); this.chartHide(); return; }
		else return;
		ev.preventDefault();
		while (i < ref.length - 1 && ref[i][0] < meta.t0) i++;
		this.chartShow({ t: ref[i][0] });
	},

	/* ----------------------------------------------------------- radios */

	buildRadios: function() {
		var el = this.el;
		el.radioCount = E('span', { 'class': 'vt-hint vt-tn' });
		el.radioSum = E('div', { 'class': 'vt-radio-sum vt-fold-keep' });
		el.radioList = E('div', { 'class': 'vt-radio-list' });
		el.radios = E('section', { 'class': 'vt-radios', 'aria-label': _('Radios') }, [
			E('header', { 'class': 'vt-tile-head vt-sec-head' }, [
				E('h3', { 'class': 'vt-tile-title' }, [ icon('radio'), E('span', {}, [ _('Radios') ]) ]),
				E('div', { 'class': 'vt-tile-extra' }, [ el.radioCount, this.foldButton('radios', _('Show or hide the radio details')) ])
			]),
			el.radioSum,
			el.radioList
		]);
		return this.foldable('radios', el.radios);
	},

	paintRadios: function() {
		var self = this, m = this.m, st = this.st;
		txt(this.el.radioCount, m.radios.length === 1 ? _('1 radio') : _('%d radios').format(m.radios.length));
		/* condensed rows, shown when the section is folded on a phone */
		dom.content(this.el.radioSum, m.radios.map(function(r) {
			var rr = st.radioRates[r.id];
			return E('button', { 'type': 'button', 'class': 'vt-rsum', 'click': function() { self.openDrawer('radio', r.id); } }, [
				E('span', { 'class': 'vt-status vt-status-' + (r.disabled ? 'warn' : r.up ? 'ok' : 'err'), 'aria-hidden': 'true' }),
				bandBadge(r.band),
				E('span', { 'class': 'vt-rsum-main vt-tn' }, [ r.channel ? _('Ch %d · %d MHz').format(r.channel, r.width || 20) : fmt.DASH ]),
				E('span', { 'class': 'vt-rsum-sub vt-tn' }, [ r.clients === 1 ? _('1 client') : _('%d clients').format(r.clients) ]),
				E('span', { 'class': 'vt-rsum-rate vt-tn' }, [ r.disabled ? _('Disabled') : !r.up ? _('Down') : rr ? '↓ ' + fmt.bits(rr.tx) : fmt.DASH ]),
				icon('chevron', 'vt-ico-sm')
			]);
		}));
		if (!m.radios.length) {
			dom.content(this.el.radioList, [ E('div', { 'class': 'vt-tile vt-empty' }, [ icon('radio'), E('p', {}, [ _('No wireless radios are reported by this device.') ]) ]) ]);
			return;
		}
		dom.content(this.el.radioList, m.radios.map(function(r) {
			var rr = st.radioRates[r.id], ins = st.radioInsights[r.id] || { notes: [] };
			var sp = r.spectrum, spec = E('div', { 'class': 'vt-spectrum', 'title': sp ? _('%d–%d MHz of the %d–%d MHz band').format(sp.lo, sp.hi, sp.bandLo, sp.bandHi) : '' });
			if (sp) {
				var blk = E('span', { 'class': 'vt-spectrum-blk' });
				blk.style.left = (sp.from * 100).toFixed(2) + '%';
				blk.style.width = Math.max(1.2, (sp.to - sp.from) * 100).toFixed(2) + '%';
				spec.appendChild(blk);
				spec.appendChild(E('span', { 'class': 'vt-spectrum-lo vt-tn' }, [ String(sp.bandLo) ]));
				spec.appendChild(E('span', { 'class': 'vt-spectrum-hi vt-tn' }, [ _('%s MHz').format(sp.bandHi) ]));
			}
			var hist = st.hist.net[r.id] || [];
			var clients = m.clients.filter(function(c) { return c.radio === r.id; });
			return E('article', { 'class': 'vt-tile vt-radio vt-radio-' + (r.band || 'x') + (r.up ? '' : ' vt-radio-off') + (ins.busiest ? ' vt-radio-busiest' : '') }, [
				E('header', { 'class': 'vt-radio-head' }, [
					bandBadge(r.band),
					E('span', { 'class': 'vt-radio-name' }, [ r.gen || r.id ]),
					E('span', { 'class': 'vt-status vt-status-' + (r.disabled ? 'warn' : r.up ? 'ok' : 'err') }, [ r.disabled ? _('Disabled') : r.up ? _('Up') : _('Down') ]),
					E('button', { 'type': 'button', 'class': 'vt-icon-action', 'title': _('Radio details'), 'aria-label': _('Radio details'),
						'click': function() { self.openDrawer('radio', r.id); } }, [ icon('chevron') ])
				]),
				E('div', { 'class': 'vt-radio-chan' }, [
					E('span', { 'class': 'vt-big vt-tn' }, [ r.channel ? _('Ch %d').format(r.channel) : fmt.DASH ]),
					E('span', { 'class': 'vt-radio-width vt-tn' }, [ r.width ? _('%s MHz').format(r.width) : '', r.auto ? ' · ' + _('auto') : '' ])
				]),
				spec,
				E('dl', { 'class': 'vt-stats' }, [
					kv(_('Clients'), E('span', { 'class': 'vt-tn' }, [ String(r.clients) ])),
					kv(_('Tx power'), E('span', { 'class': 'vt-tn' }, [ r.txpower != null ? _('%s dBm').format(r.txpower) : fmt.DASH ])),
					kv(_('Noise'), r.noise != null ? E('span', { 'class': 'vt-tn' }, [ fmt.dbm(r.noise) ]) : E('span', { 'class': 'vt-muted', 'title': _('The driver reports a placeholder value, so no noise floor or SNR is shown') }, [ _('not reported') ])),
					kv(_('Airtime'), r.airtime != null ? E('span', { 'class': 'vt-tn' }, [ fmt.pct(r.airtime) ]) : E('span', { 'class': 'vt-muted' }, [ _('not reported') ]))
				]),
				E('div', { 'class': 'vt-radio-live' }, [
					rateLine(rr ? rr.tx : null, rr ? rr.rx : null),
					sparkline(hist, [ 2, 1 ], 0, 'vt-spark-' + (r.band || 'x'), { min: 1000, scale: bitsLabel })
				]),
				E('ul', { 'class': 'vt-notes' }, ins.notes.map(function(n) {
					return E('li', { 'class': 'vt-note vt-note-' + n.level }, [ icon(n.level === 'warn' ? 'warn' : n.level === 'err' ? 'err' : 'info', 'vt-ico-sm'), E('span', {}, [ n.text ]) ]);
				})),
				E('footer', { 'class': 'vt-radio-foot' }, [
					E('span', { 'class': 'vt-avs' }, clients.slice(0, 6).map(function(c) { return avatar(c, true); })),
					pageLink(insight.PAGES.wireless, _('Radio settings'))
				])
			]);
		}));
	},

	/* ----------------------------------------------------------- clients */

	buildClients: function() {
		var self = this, el = this.el;
		el.filter = E('input', { 'type': 'text', 'class': 'vt-filter-input', 'placeholder': _('Filter by name, address, SSID…'),
			'aria-label': _('Filter clients'), 'autocomplete': 'off', 'spellcheck': 'false',
			'input': function(ev) { self.ui.filter = ev.target.value; self.paintClients(); } });
		el.filterClear = E('button', { 'type': 'button', 'class': 'vt-filter-clear', 'aria-label': _('Clear filter'), 'hidden': 'hidden',
			'click': function() { self.setFilter(''); el.filter.focus(); } }, [ icon('close') ]);
		el.chips = E('div', { 'class': 'vt-fchips', 'role': 'group', 'aria-label': _('Quick filters') });
		el.count = E('span', { 'class': 'vt-count vt-tn' });
		el.thead = E('thead');
		el.tbody = E('tbody');
		el.clientsEmpty = E('div', { 'class': 'vt-empty', 'hidden': 'hidden' });
		this.rowMap = new Map();
		el.clients = E('section', { 'class': 'vt-tile vt-clients', 'id': 'vt-clients', 'aria-label': _('Clients') }, [
			tileHead('users', _('Clients'), [ el.count ]),
			E('div', { 'class': 'vt-toolbar' }, [
				E('label', { 'class': 'vt-filter' }, [ icon('search'), el.filter, E('kbd', { 'class': 'vt-key-hint' }, [ 'F' ]), el.filterClear ]),
				el.chips
			]),
			E('div', { 'class': 'vt-table-wrap' }, [ E('table', { 'class': 'vt-ctable' }, [ el.thead, el.tbody ]) ]),
			el.clientsEmpty
		]);
		return el.clients;
	},

	setFilter: function(v) {
		this.ui.filter = v;
		this.el.filter.value = v;
		this.paintClients();
	},

	filterSsid: function(ssid, band) {
		this.ui.chip = 'all';
		this.setFilter(ssid);
		this.el.clients.scrollIntoView({ behavior: reducedMotion() ? 'auto' : 'smooth', block: 'start' });
	},

	sortValue: function(c, key) {
		var r = this.st.staRates[c.mac];
		switch (key) {
		case 'name': return String(c.name).toLowerCase();
		case 'signal': return c.signal == null ? -999 : c.signal;
		case 'ssid': return (c.ssid + ' ' + c.band).toLowerCase();
		case 'rate': return Math.max(c.tx && c.tx.rate || 0, c.rx && c.rx.rate || 0);
		case 'exp': return c.exp ? c.exp.score : -1;
		case 'time': return c.connected || 0;
		default: return r ? r.rx + r.tx : -1;
		}
	},

	matches: function(c) {
		var chip = this.ui.chip, q = String(this.ui.filter || '').trim().toLowerCase();
		if (chip === 'weak' && !(c.signal != null && c.signal < insight.WEAK_DBM)) return false;
		if (chip === 'new' && !c.isNew) return false;
		if (chip === 'active' && !(this.st.staRates[c.mac] && this.st.staRates[c.mac].rx + this.st.staRates[c.mac].tx > 8000)) return false;
		if (/^band:/.test(chip) && c.band !== chip.slice(5)) return false;
		if (!q) return true;
		var hay = [ c.name, c.macLabel, c.mac, c.ssid, c.bandLabel, c.gen, c.vendor, c.wps, c.nameSourceLabel ].concat(c.ips || []).join(' ').toLowerCase();
		return q.split(/\s+/).every(function(w) { return hay.indexOf(w) >= 0; });
	},

	paintClients: function() {
		var self = this, m = this.m, st = this.st, el = this.el, ui = this.ui;

		/* quick filter chips: all / bands present / weak / new / active */
		var chipDefs = [ [ 'all', _('All'), m.clients.length ] ];
		var bands = [];
		m.clients.forEach(function(c) { if (c.band && bands.indexOf(c.band) < 0) bands.push(c.band); });
		bands.sort().forEach(function(b) { chipDefs.push([ 'band:' + b, wifi.bandLabel(b), m.clients.filter(function(c) { return c.band === b; }).length ]); });
		chipDefs.push([ 'active', _('Active'), m.clients.filter(function(c) { var r = st.staRates[c.mac]; return r && r.rx + r.tx > 8000; }).length ]);
		chipDefs.push([ 'weak', _('Weak signal'), m.clients.filter(function(c) { return c.signal != null && c.signal < insight.WEAK_DBM; }).length ]);
		chipDefs.push([ 'new', _('New'), m.clients.filter(function(c) { return c.isNew; }).length ]);
		if (!chipDefs.some(function(d) { return d[0] === ui.chip; })) ui.chip = 'all';
		dom.content(el.chips, chipDefs.map(function(d) {
			return E('button', { 'type': 'button', 'class': 'vt-fchip' + (ui.chip === d[0] ? ' vt-fchip-on' : '') + (d[0] === 'weak' && d[2] ? ' vt-fchip-warn' : ''),
				'aria-pressed': String(ui.chip === d[0]), 'click': function() { ui.chip = d[0]; self.paintClients(); } }, [
				E('span', {}, [ d[1] ]), E('span', { 'class': 'vt-fchip-n vt-tn' }, [ String(d[2]) ])
			]);
		}));
		el.filterClear.hidden = !ui.filter;

		/* header with sort buttons */
		var cols = [ [ 'name', _('Device') ], [ 'signal', _('Signal') ], [ 'ssid', _('Network') ], [ 'rate', _('Link rate') ], [ 'live', _('Live') ], [ 'exp', _('Experience') ], [ 'time', _('Online') ] ];
		dom.content(el.thead, [ E('tr', {}, cols.map(function(c) {
			var on = ui.sort === c[0];
			return E('th', { 'class': 'vt-th-' + c[0], 'scope': 'col', 'aria-sort': on ? (ui.dir > 0 ? 'ascending' : 'descending') : 'none' }, [
				E('button', { 'type': 'button', 'class': 'vt-sort' + (on ? ' vt-sort-on' : ''), 'click': function() {
					if (ui.sort === c[0]) ui.dir = -ui.dir; else { ui.sort = c[0]; ui.dir = (c[0] === 'name' || c[0] === 'ssid') ? 1 : -1; }
					self.paintClients();
				} }, [ E('span', {}, [ c[1] ]), E('span', { 'class': 'vt-sort-ind', 'aria-hidden': 'true' }, [ on ? (ui.dir > 0 ? '↑' : '↓') : '' ]) ])
			]);
		})) ]);

		var list = m.clients.filter(L.bind(this.matches, this));
		list.sort(function(a, b) {
			var va = self.sortValue(a, ui.sort), vb = self.sortValue(b, ui.sort);
			if (va < vb) return -ui.dir;
			if (va > vb) return ui.dir;
			return a.mac < b.mac ? -1 : 1;
		});
		var gone = (ui.chip === 'all' || ui.chip === 'new') ? st.gone.map(function(g) { return Object.assign({}, g.client, { gone: true, goneAt: g.at }); }).filter(function(c) {
			return !ui.filter || self.matches(Object.assign({}, c, { isNew: false }));
		}) : [];
		if (ui.chip === 'new') gone = [];

		var maxRate = 0;
		m.clients.forEach(function(c) { var r = st.staRates[c.mac]; if (r && r.rx + r.tx > maxRate) maxRate = r.rx + r.tx; });

		var keep = new Set();
		list.concat(gone).forEach(function(c) {
			var key = (c.gone ? 'gone:' : '') + c.mac;
			keep.add(key);
			var tr = self.rowMap.get(key);
			if (!tr) {
				tr = E('tr', { 'class': 'vt-row vt-row-enter', 'tabindex': '0' });
				tr.addEventListener('click', function() { self.openDrawer('client', tr.getAttribute('data-mac')); });
				tr.addEventListener('keydown', function(ev) { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); self.openDrawer('client', tr.getAttribute('data-mac')); } });
				self.rowMap.set(key, tr);
			}
			tr.setAttribute('data-mac', c.mac);
			tr.classList.toggle('vt-row-gone', !!c.gone);
			tr.classList.toggle('vt-row-sel', !!(ui.drawer && ui.drawer.kind === 'client' && ui.drawer.id === c.mac));
			tr.setAttribute('aria-label', _('Open details of %s').format(c.name));
			dom.content(tr, self.clientCells(c, maxRate));
			el.tbody.appendChild(tr);
		});
		this.rowMap.forEach(function(tr, key) {
			if (keep.has(key)) return;
			if (tr.parentNode) tr.parentNode.removeChild(tr);
			self.rowMap.delete(key);
		});
		window.setTimeout(function() { self.rowMap.forEach(function(tr) { tr.classList.remove('vt-row-enter'); }); }, 600);

		var total = m.clients.length;
		txt(el.count, list.length === total ? (total === 1 ? _('1 connected') : _('%d connected').format(total)) : _('%d of %d').format(list.length, total));

		el.clientsEmpty.hidden = list.length + gone.length > 0;
		if (!el.clientsEmpty.hidden) {
			dom.content(el.clientsEmpty, !total ? [
				icon('wifi'), E('p', { 'class': 'vt-empty-title' }, [ _('No clients connected') ]),
				E('p', {}, [ _('Stations appear here as soon as they associate with one of the SSIDs.') ])
			] : [
				icon('search'), E('p', { 'class': 'vt-empty-title' }, [ ui.filter ? _('No clients match “%s”').format(fmt.safeText(ui.filter, 40)) : _('No clients in this view') ]),
				E('button', { 'type': 'button', 'class': 'vt-btn', 'click': function() { ui.chip = 'all'; self.setFilter(''); } }, [ _('Show all clients') ])
			]);
		}
	},

	clientCells: function(c, maxRate) {
		var st = this.st, r = c.gone ? null : st.staRates[c.mac];
		var total = r ? r.rx + r.tx : 0;
		var bar = E('span', { 'class': 'vt-mini-fill' });
		setW(bar, maxRate > 0 ? total / maxRate * 100 : 0);
		var tags = [];
		if (c.gone) tags.push(pill(_('Left %s').format(fmt.ago(Date.now() - c.goneAt)), 'muted'));
		else if (c.isNew) tags.push(pill(_('New'), 'accent', _('Connected after you opened this page')));
		if (c.legacyOnRadio && !c.gone) tags.push(pill(c.gen === 'legacy' ? _('Legacy') : c.gen, 'warn', _('Older Wi-Fi generation than the radio; uses more airtime')));
		var exp = c.exp || { score: 0, level: 'muted', grade: fmt.DASH, reason: '' };

		return [
			E('td', { 'class': 'vt-td-name', 'data-title': _('Device') }, [
				E('div', { 'class': 'vt-who' }, [
					avatar(c),
					E('div', { 'class': 'vt-who-text' }, [
						E('div', { 'class': 'vt-who-label', 'title': c.name }, [ c.name ]),
						E('div', { 'class': 'vt-who-sub' }, [ E('span', { 'class': 'vt-src vt-src-' + c.nameSource, 'title': _('Name from: %s').format(this.sourceText(c)) }, [ c.nameSourceLabel ]) ].concat(tags, [ E('span', { 'class': 'vt-mono vt-who-id' }, [ c.secondary ]) ]))
					])
				])
			]),
			E('td', { 'class': 'vt-td-signal', 'data-title': _('Signal') }, c.gone ? [ E('span', { 'class': 'vt-muted' }, [ fmt.DASH ]) ] : [
				E('span', { 'class': 'vt-signal', 'title': c.level.word }, [ signalGlyph(c.level), E('span', { 'class': 'vt-tn' }, [ fmt.dbm(c.signal) ]) ])
			]),
			E('td', { 'class': 'vt-td-net', 'data-title': _('Network') }, [
				E('div', { 'class': 'vt-net' }, [ E('span', { 'class': 'vt-net-ssid' }, [ c.ssid ]), E('span', { 'class': 'vt-net-badges' }, [ bandBadge(c.band), c.gen ? E('span', { 'class': 'vt-gen' }, [ c.gen ]) : '' ]) ])
			]),
			E('td', { 'class': 'vt-td-rate', 'data-title': _('Link rate'),
				'title': _('To device: %s').format(c.tx ? c.tx.label : fmt.DASH) + '\n' + _('From device: %s').format(c.rx ? c.rx.label : fmt.DASH) }, [
				E('div', { 'class': 'vt-phy vt-tn' }, [ icon('down', 'vt-ico-sm'), E('b', {}, [ c.tx ? fmt.phyRate(c.tx.rate) : fmt.DASH ]) ]),
				E('div', { 'class': 'vt-phy vt-phy-up vt-tn' }, [ [ c.tx && c.tx.mhz ? _('%s MHz').format(c.tx.mhz) : null, c.tx && c.tx.std ? (c.tx.std === 'legacy' ? _('legacy') : c.tx.std) : null ].filter(Boolean).join(' · ') ])
			]),
			E('td', { 'class': 'vt-td-live', 'data-title': _('Live') }, [
				E('div', { 'class': 'vt-live-cell' }, [
					E('span', { 'class': 'vt-tn vt-live-total' }, [ r ? fmt.bits(total) : fmt.DASH ]),
					E('span', { 'class': 'vt-mini' }, [ bar ]),
					E('span', { 'class': 'vt-live-split vt-tn', 'title': r ? _('To device %s, from device %s').format(fmt.bits(r.tx), fmt.bits(r.rx)) : '' }, [ r ? '↓ ' + fmt.bitsShort(r.tx) + '  ↑ ' + fmt.bitsShort(r.rx) : '' ])
				])
			]),
			E('td', { 'class': 'vt-td-exp', 'data-title': _('Experience') }, c.gone ? [ E('span', { 'class': 'vt-muted' }, [ fmt.DASH ]) ] : [
				E('div', { 'class': 'vt-exp', 'title': exp.reason }, [
					E('span', { 'class': 'vt-score vt-score-' + exp.level + ' vt-tn' }, [ String(exp.score) ]),
					E('span', { 'class': 'vt-exp-text' }, [ E('b', {}, [ exp.grade ]), E('span', {}, [ exp.short || exp.reason ]) ])
				])
			]),
			E('td', { 'class': 'vt-td-time vt-tn', 'data-title': _('Connected') }, [ c.gone ? fmt.DASH : fmt.duration(c.connected) ])
		];
	},

	/* ----------------------------------------------------- top talkers */

	buildTalkers: function() {
		this.el.talkers = E('div', { 'class': 'vt-talkers' });
		return E('section', { 'class': 'vt-tile vt-talk', 'aria-label': _('Top talkers') }, [
			tileHead('pulse', _('Top talkers'), [ E('span', { 'class': 'vt-hint' }, [ _('who uses the bandwidth') ]) ]),
			this.el.talkers
		]);
	},

	paintTalkers: function() {
		var self = this, m = this.m, t = this.st.talkers || [];
		if (!t.length) {
			dom.content(this.el.talkers, [ E('p', { 'class': 'vt-empty-inline' }, [ m.clients.length ? _('Nobody is moving data right now.') : _('No clients connected.') ]) ]);
			return;
		}
		var byMac = {};
		m.clients.forEach(function(c) { byMac[c.mac] = c; });
		dom.content(this.el.talkers, t.map(function(x, i) {
			var c = byMac[x.mac] || { mac: x.mac, name: x.name, icon: 'device' };
			var fill = E('span', { 'class': 'vt-talk-fill' });
			setW(fill, x.share * 100);
			return E('button', { 'type': 'button', 'class': 'vt-talk-row', 'click': function() { self.openDrawer('client', x.mac); } }, [
				E('span', { 'class': 'vt-talk-rank vt-tn' }, [ String(i + 1) ]),
				avatar(c, true),
				E('span', { 'class': 'vt-talk-main' }, [
					E('span', { 'class': 'vt-talk-top' }, [ E('span', { 'class': 'vt-talk-name', 'title': c.name }, [ c.name ]) ]),
					E('span', { 'class': 'vt-talk-bar' }, [ fill ]),
					E('span', { 'class': 'vt-talk-sub vt-tn', 'title': _('To device %s, from device %s').format(fmt.bits(x.down), fmt.bits(x.up)) }, [
						E('b', {}, [ fmt.bits(x.total) ]), E('span', { 'class': 'vt-talk-share' }, [ fmt.pct(x.share * 100) ]), '↓ ' + fmt.bitsShort(x.down) + '  ↑ ' + fmt.bitsShort(x.up) ])
				])
			]);
		}));
	},

	/* ------------------------------------------------------------ SSIDs */

	buildSsids: function() {
		this.el.ssids = E('div', { 'class': 'vt-ssids' });
		return this.foldable('ssids', E('section', { 'class': 'vt-tile vt-ssid-tile', 'aria-label': _('Wireless networks') }, [
			tileHead('wifi', _('Wireless networks'), [ pageLink(insight.PAGES.wireless, _('Edit')), this.foldButton('ssids', _('Show or hide the wireless networks')) ]),
			this.el.ssids
		]));
	},

	paintSsids: function() {
		var self = this, m = this.m, st = this.st;
		var groups = model.groupSsids(m.ssids);
		if (!groups.length) {
			dom.content(this.el.ssids, [ E('p', { 'class': 'vt-empty-inline' }, [ _('No wireless networks configured.') ]) ]);
			return;
		}
		dom.content(this.el.ssids, groups.map(function(g) {
			var rx = 0, tx = 0, has = false;
			g.ids.forEach(function(id) { var r = st.ssidRates[id]; if (r) { rx += r.rx; tx += r.tx; has = true; } });
			var bands = g.bands.map(function(b) { return bandBadge(b); });
			return E('button', { 'type': 'button', 'class': 'vt-ssid' + (g.clients ? '' : ' vt-ssid-idle'), 'title': _('Show the clients of %s').format(g.ssid),
				'click': function() { self.filterSsid(g.ssid); } }, [
				E('span', { 'class': 'vt-ssid-ico' + (g.security.tone === 'open' || g.security.tone === 'weak' ? ' vt-t-warn' : '') }, [ icon(g.security.tone === 'open' ? 'unlock' : 'lock') ]),
				E('span', { 'class': 'vt-ssid-main' }, [
					E('span', { 'class': 'vt-ssid-top' }, [ E('span', { 'class': 'vt-ssid-name' }, [ g.ssid || _('(hidden)') ]), g.hidden ? pill(_('Hidden'), 'muted') : '' ]),
					E('span', { 'class': 'vt-ssid-meta' }, bands.concat([ E('span', { 'class': 'vt-sec', 'title': g.security.long }, [ g.security.short ]) ]))
				]),
				E('span', { 'class': 'vt-ssid-side' }, [
					E('span', { 'class': 'vt-ssid-n vt-tn' }, [ String(g.clients) ]),
					E('span', { 'class': 'vt-hint vt-tn' }, [ g.clients ? (has ? '↓ ' + fmt.bits(tx) : fmt.DASH) : _('idle') ])
				])
			]);
		}));
	},

	/* ----------------------------------------------------------- drawer */

	buildDrawer: function() {
		var self = this, el = this.el;
		el.drawerTitle = E('div', { 'class': 'vt-drawer-title', 'id': 'vt-drawer-title' });
		el.drawerBody = E('div', { 'class': 'vt-drawer-body' });
		el.drawerClose = E('button', { 'type': 'button', 'class': 'vt-drawer-close', 'aria-label': _('Close'), 'click': function() { self.closeDrawer(); } }, [ icon('close') ]);
		el.drawer = E('aside', { 'class': 'vt-drawer', 'role': 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'vt-drawer-title', 'hidden': 'hidden' }, [
			E('div', { 'class': 'vt-drawer-grip', 'aria-hidden': 'true' }),
			E('header', { 'class': 'vt-drawer-head' }, [ el.drawerTitle, el.drawerClose ]),
			el.drawerBody
		]);
		el.drawerBack = E('div', { 'class': 'vt-drawer-back', 'hidden': 'hidden', 'click': function() { self.closeDrawer(); } });
		return E('div', { 'class': 'vt-drawer-layer' }, [ el.drawerBack, el.drawer ]);
	},

	openDrawer: function(kind, id) {
		var el = this.el;
		this.ui.drawer = { kind: kind, id: id };
		this.ui.editing = null;
		if (!el.drawer.hidden) { this.paintDrawer(); this.paintClients(); return; }
		this.lastFocus = document.activeElement;
		el.drawer.hidden = false;
		el.drawerBack.hidden = false;
		this.paintDrawer();
		this.paintClients();
		try { history.replaceState(null, '', '#' + kind + '=' + encodeURIComponent(id)); } catch (e) {}
		window.requestAnimationFrame(function() { el.root.classList.add('vt-drawer-open'); el.drawerClose.focus(); });
	},

	closeDrawer: function() {
		var el = this.el, self = this;
		if (el.drawer.hidden) return;
		this.ui.drawer = null;
		this.ui.editing = null;
		el.root.classList.remove('vt-drawer-open');
		window.setTimeout(function() { if (!self.ui.drawer) { el.drawer.hidden = true; el.drawerBack.hidden = true; } }, reducedMotion() ? 0 : 260);
		try { history.replaceState(null, '', location.pathname + location.search); } catch (e) {}
		this.paintClients();
		if (this.lastFocus && this.lastFocus.isConnected) this.lastFocus.focus();
	},

	/* A deep link names an existing thing or nothing: a client by a
	   station MAC, a radio this device reports; uplink and device take no
	   id. Anything else is dropped from the address bar, so a crafted link
	   cannot put its own text in the drawer title. */
	openFromHash: function() {
		var hash = location.hash || '', m = /^#(client|radio|uplink|device)=(.{1,128})$/.exec(hash), id = null;
		if (m) {
			try { id = decodeURIComponent(m[2]); } catch (e) { id = null; }
			if (id == null) { /* malformed escape */ }
			else if (m[1] === 'client') id = names.normMac(id);
			else if (m[1] === 'radio') id = this.m && this.m.radios.some(function(r) { return r.id === id; }) ? id : null;
			else id = m[1];
		}
		if (id != null) { this.openDrawer(m[1], id); return; }
		if (/^#(client|radio|uplink|device)=/.test(hash)) {
			try { history.replaceState(null, '', location.pathname + location.search); } catch (e) {}
		}
	},

	paintDrawer: function() {
		var d = this.ui.drawer, el = this.el;
		if (!d || !el.drawer || el.drawer.hidden) return;
		if (this.ui.editing) return;   /* do not replace a form being typed in */
		var content;
		if (d.kind === 'client') content = this.drawerClient(d.id);
		else if (d.kind === 'radio') content = this.drawerRadio(d.id);
		else if (d.kind === 'uplink') content = this.drawerUplink();
		else content = this.drawerDevice();
		dom.content(el.drawerTitle, content.title);
		dom.content(el.drawerBody, content.body);
	},

	section: function(title, children, cls) {
		return E('section', { 'class': 'vt-dsec' + (cls ? ' ' + cls : '') }, [ E('h4', { 'class': 'vt-dsec-title' }, [ title ]) ].concat(children));
	},

	drawerClient: function(mac) {
		var self = this, st = this.st, c = null, gone = null;
		this.m.clients.forEach(function(x) { if (x.mac === mac) c = x; });
		if (!c) st.gone.forEach(function(g) { if (g.client.mac === mac) gone = g; });
		if (!c && gone) c = Object.assign({}, gone.client, { gone: true, goneAt: gone.at });
		if (!c) return {
			title: [ E('span', { 'class': 'vt-drawer-name' }, [ names.normMac(mac) ? fmt.mac(mac) : _('Unknown device') ]) ],
			body: [ E('div', { 'class': 'vt-empty' }, [ icon('wifi'), E('p', { 'class': 'vt-empty-title' }, [ _('Not connected') ]), E('p', {}, [ _('This station is not associated right now.') ]) ]) ]
		};

		var r = c.gone ? null : st.staRates[c.mac], hist = st.clientHist[c.mac] || [];
		var exp = c.exp || insight.experience(c);
		var radio = this.m.radios.filter(function(x) { return x.id === c.radio; })[0];

		var title = [
			avatar(c),
			E('div', { 'class': 'vt-drawer-titles' }, [
				E('div', { 'class': 'vt-drawer-name', 'id': 'vt-drawer-name' }, [ c.name ]),
				E('div', { 'class': 'vt-drawer-sub' }, [
					E('span', { 'class': 'vt-src vt-src-' + c.nameSource }, [ c.nameSourceLabel ]),
					E('span', { 'class': 'vt-mono' }, [ c.secondary ])
				])
			])
		];

		var rename = this.canWrite ? E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-ghost', 'click': function() { self.startRename(c); } }, [ icon('pencil'), E('span', {}, [ c.alias ? _('Rename') : _('Name this device') ]) ]) : '';
		var sigSeries = hist.map(function(p) { return [ p[0], p[1] ]; }).filter(function(p) { return isFinite(p[1]); });
		/* dBm as headroom above -95 dBm: -30 dBm at the top, the -75 dBm
		   weak-signal line dashed */
		var sigSpark = sparkline(sigSeries.map(function(p) { return [ p[0], Math.max(0, 95 - p[1]) ]; }), [ 1 ], 65, 'vt-spark-' + (c.band || 'x'),
			{ thresh: 95 + insight.WEAK_DBM, threshLabel: fmt.dbm(insight.WEAK_DBM) });
		var sigVals = sigSeries.map(function(p) { return -p[1]; });

		var body = [
			c.gone ? E('div', { 'class': 'vt-banner vt-banner-muted' }, [ icon('info'), E('span', {}, [ _('Disconnected %s; shown from the last sample.').format(fmt.ago(Date.now() - c.goneAt)) ]) ]) : '',
			E('div', { 'class': 'vt-dactions' }, [ rename, pageLink(insight.PAGES.wireless, _('Wireless settings')) ]),
			this.el.renameSlot = E('div', { 'class': 'vt-rename-slot' }),
			c.gone ? '' : E('div', { 'class': 'vt-expcard vt-expcard-' + exp.level }, [
				E('div', { 'class': 'vt-ring vt-tn' }, [ this.ring(exp.score, exp.level), E('span', { 'class': 'vt-ring-n' }, [ String(exp.score) ]) ]),
				E('div', { 'class': 'vt-expcard-text' }, [
					E('div', { 'class': 'vt-expcard-grade' }, [ _('%s experience').format(exp.grade) ]),
					E('div', { 'class': 'vt-expcard-reason' }, [ exp.reason ]),
					exp.factors.length > 1 ? E('ul', { 'class': 'vt-factors' }, exp.factors.filter(function(f) { return f.cost > 0; }).map(function(f) {
						return E('li', {}, [ E('span', { 'class': 'vt-tn' }, [ '−' + f.cost ]), E('span', {}, [ f.text ]) ]);
					})) : ''
				])
			]),
			E('div', { 'class': 'vt-dgrid' }, [
				E('div', { 'class': 'vt-dcard' }, [
					E('div', { 'class': 'vt-dcard-label' }, [ _('Signal') ]),
					E('div', { 'class': 'vt-dcard-value' }, [ c.gone ? fmt.DASH : fmt.dbm(c.signal) ]),
					E('div', { 'class': 'vt-dcard-sub' }, [ c.gone ? '' : c.level.word + (sigVals.length > 1 ? ' · ' + _('range %s … %s').format(fmt.dbm(Math.min.apply(null, sigVals)), fmt.dbm(Math.max.apply(null, sigVals))) : '') ]),
					sigSpark
				]),
				E('div', { 'class': 'vt-dcard' }, [
					E('div', { 'class': 'vt-dcard-label' }, [ _('Throughput') ]),
					E('div', { 'class': 'vt-dcard-value' }, [ r ? fmt.bits(r.tx + r.rx) : fmt.DASH ]),
					E('div', { 'class': 'vt-dcard-sub vt-tn' }, [ r ? '↓ ' + fmt.bits(r.tx) + ' · ↑ ' + fmt.bits(r.rx) : _('measuring') ]),
					sparkline(hist, [ 2, 3 ], 0, 'vt-spark-' + (c.band || 'x'), { min: 1000, scale: bitsLabel })
				])
			]),
			this.section(_('Link'), [ E('dl', { 'class': 'vt-kvs' }, [
				kv(_('To device'), c.tx ? [ c.tx.label, c.tx.detail ? E('small', {}, [ c.tx.detail ]) : '' ] : fmt.DASH),
				kv(_('From device'), c.rx ? [ c.rx.label, c.rx.detail ? E('small', {}, [ c.rx.detail ]) : '' ] : fmt.DASH),
				kv(_('Generation'), c.gen ? [ c.gen, c.legacyOnRadio ? E('small', { 'class': 'vt-t-warn' }, [ _('older than the radio (%s)').format(radio && radio.gen || '') ]) : '' ] : fmt.DASH),
				kv(_('Capabilities'), [ c.wmm ? 'WMM' : null, c.mfp ? _('PMF') : null, c.caps && c.caps.rrm ? '802.11k' : null, c.caps && c.caps.mbo ? 'MBO' : null ].filter(Boolean).join(' · ') || fmt.DASH),
				kv(_('Noise / SNR'), c.noise != null && c.signal != null ? fmt.dbm(c.noise) + ' · ' + (c.signal - c.noise) + ' dB' : E('span', { 'class': 'vt-muted' }, [ _('not reported by the driver') ]))
			]) ]),
			this.section(_('Connection'), [ E('dl', { 'class': 'vt-kvs' }, [
				kv(_('Network'), [ c.ssid, ' ', bandBadge(c.band) ]),
				kv(_('Radio'), radio ? _('%s · channel %d · %d MHz').format(radio.id, radio.channel || 0, radio.width || 20) : c.radio),
				kv(_('Connected for'), c.gone ? fmt.DASH : fmt.duration(c.connected)),
				kv(_('Last activity'), c.inactive == null || c.gone ? fmt.DASH : c.inactive < 1000 ? _('now') : _('%s ago').format(fmt.duration(c.inactive / 1000))),
				kv(_('Seen since'), c.firstSeen ? (c.isNew ? _('%s (new this session)').format(new Date(c.firstSeen).toLocaleTimeString()) : _('before this page opened')) : fmt.DASH)
			]) ]),
			this.section(_('Traffic'), [ E('dl', { 'class': 'vt-kvs' }, [
				kv(_('Downloaded'), fmt.bytes(c.txBytes)),
				kv(_('Uploaded'), fmt.bytes(c.rxBytes)),
				kv(_('Frames to device'), c.txPackets ? _('%d sent · %s retried · %s failed').format(c.txPackets, fmt.pct(c.txRetries / Math.max(1, c.txPackets) * 100, 1), fmt.pct(c.txFailed / Math.max(1, c.txPackets + c.txFailed) * 100, 1)) : fmt.DASH)
			]) ]),
			this.section(_('Identity'), [ E('dl', { 'class': 'vt-kvs' }, [
				kv(_('MAC address'), c.macLabel, true),
				kv(_('Address type'), c.isPrivate ? _('Private Wi-Fi address (randomised by the device)') : (c.vendor ? _('Globally unique · %s').format(c.vendor) : _('Globally unique'))),
				kv(_('IP addresses'), c.ips && c.ips.length ? c.ips.join('\n') : E('span', { 'class': 'vt-muted' }, [ _('not known to this AP') ]), true),
				kv(_('Name from'), this.sourceText(c)),
				c.wps && c.nameSource !== 'wps' ? kv(_('WPS device name'), c.wps) : ''
			]) ])
		];
		return { title: title, body: body };
	},

	sourceText: function(c) {
		switch (c.nameSource) {
		case 'alias': return _('Your name for this device');
		case 'dns': return _('Reverse DNS of its address');
		case 'mdns': return _('mDNS announcement');
		case 'dhcp': return _('DHCP hostname');
		case 'wps': return _('The name the device announces (WPS)');
		case 'vendor': return _('Manufacturer of the network adapter');
		case 'private': return _('Nothing better known; the address is randomised');
		}
		return _('Nothing better known');
	},

	ring: function(score, level) {
		var s = svgRoot('vt-ring-svg vt-lvlc-' + level, '0 0 36 36');
		var c = 2 * Math.PI * 15.5, f = Math.max(0, Math.min(100, score)) / 100 * c;
		var track = document.createElementNS(SVGNS, 'circle');
		track.setAttribute('cx', '18'); track.setAttribute('cy', '18'); track.setAttribute('r', '15.5');
		track.setAttribute('class', 'vt-ring-track');
		var arc = document.createElementNS(SVGNS, 'circle');
		arc.setAttribute('cx', '18'); arc.setAttribute('cy', '18'); arc.setAttribute('r', '15.5');
		arc.setAttribute('class', 'vt-ring-arc');
		arc.setAttribute('stroke-dasharray', f.toFixed(2) + ' ' + c.toFixed(2));
		s.appendChild(track);
		s.appendChild(arc);
		return s;
	},

	/* inline alias editor; Enter saves, Escape cancels, empty clears */
	startRename: function(c) {
		var self = this, slot = this.el.renameSlot, chosen = { icon: (this.aliases[c.mac] && this.aliases[c.mac].icon) || null };
		this.ui.editing = c.mac;
		var err = E('p', { 'class': 'vt-form-err', 'role': 'alert', 'hidden': 'hidden' });
		var input = E('input', { 'type': 'text', 'class': 'vt-rename-input', 'maxlength': String(names.NAME_MAX * 2), 'autocomplete': 'off',
			'placeholder': _('e.g. Living room TV'), 'aria-label': _('Device name') });
		input.value = c.alias || '';
		var iconBtns = names.ICONS.map(function(ic) {
			return E('button', { 'type': 'button', 'class': 'vt-icon-pick', 'title': ic, 'aria-label': ic, 'aria-pressed': String(chosen.icon === ic),
				'click': function(ev) {
					chosen.icon = chosen.icon === ic ? null : ic;
					iconBtns.forEach(function(b) { b.setAttribute('aria-pressed', String(b.getAttribute('aria-label') === chosen.icon)); });
				} }, [ icon(ic) ]);
		});
		function save() {
			var v = names.validateAlias(input.value);
			if (!v.ok) { txt(err, v.error); err.hidden = false; input.focus(); return; }
			saveBtn.disabled = true;
			self.saveAlias(c.mac, v.value, chosen.icon).then(function(ok) {
				saveBtn.disabled = false;
				if (typeof ok === 'string') { txt(err, ok); err.hidden = false; return; }
				if (!ok) { txt(err, _('Could not save the name (no permission or the device refused it).')); err.hidden = false; return; }
				self.ui.editing = null;
				self.rerender();
			});
		}
		function cancel() { self.ui.editing = null; dom.content(slot, []); self.paintDrawer(); }
		input.addEventListener('keydown', function(ev) {
			if (ev.key === 'Enter') { ev.preventDefault(); save(); }
			else if (ev.key === 'Escape') { ev.preventDefault(); ev.stopPropagation(); cancel(); }
		});
		var saveBtn = E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-primary', 'click': save }, [ _('Save') ]);
		dom.content(slot, [ E('div', { 'class': 'vt-rename' }, [
			E('label', { 'class': 'vt-rename-label' }, [ _('Name'), input ]),
			E('div', { 'class': 'vt-icon-picks', 'role': 'group', 'aria-label': _('Device type') }, iconBtns),
			err,
			E('div', { 'class': 'vt-rename-actions' }, [
				saveBtn,
				E('button', { 'type': 'button', 'class': 'vt-btn', 'click': cancel }, [ _('Cancel') ]),
				c.alias ? E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-ghost', 'click': function() { input.value = ''; save(); } }, [ _('Remove name') ]) : '',
				E('span', { 'class': 'vt-hint' }, [ _('Stored on this device in /etc/config/vantage') ])
			])
		]) ]);
		input.focus();
	},

	/* Checked here for a quick answer, then sent to luci.vantage
	   set_alias, which checks again, keeps one section per MAC and writes
	   /etc/config/vantage directly (no staged uci changes, so LuCI's
	   apply/rollback lock does not block it). The names are reloaded after
	   every attempt, failed or not, so the next one starts from what the
	   device holds.
	   -> Promise<true | false | string (error text)> */
	saveAlias: function(mac, name, iconName) {
		var self = this, key = names.normMac(mac);
		var op = names.aliasOp(key ? this.aliases[key] || null : null, mac, name, iconName);
		if (!op.ok) return Promise.resolve(op.error);
		var value = op.op === 'add' || op.op === 'set' ? op.values.name : '';
		var icon = value ? (names.validIcon(iconName) || '') : '';
		return Promise.resolve(callSetAlias(key, value, icon)).then(function(r) {
			return (r && typeof r === 'object' && r.ok === true) ? true : self.aliasError(r);
		}, function() { return false; }).then(function(res) {
			return self.loadAliases().then(function() { return res; }, function() { return res; });
		});
	},

	/* set_alias refusal -> message; false for anything else (no grant, no
	   plugin, transport error) */
	aliasError: function(r) {
		switch (r && typeof r === 'object' ? r.error : null) {
		case 'invalid-mac': return _('Not a station MAC address');
		case 'invalid-name': return _('Name contains invisible or control characters');
		case 'name-too-long': return _('Name is longer than %d characters').format(names.NAME_MAX);
		case 'invalid-icon': return _('Unknown device type');
		case 'too-many': return _('This device already stores %d names; remove some first.').format(names.ALIAS_MAX);
		case 'failed': return _('The device could not write /etc/config/vantage.');
		}
		return false;
	},

	drawerRadio: function(id) {
		var self = this, r = this.m.radios.filter(function(x) { return x.id === id; })[0];
		if (!r) return { title: [ E('span', { 'class': 'vt-drawer-name' }, [ _('Unknown radio') ]) ], body: [ E('p', { 'class': 'vt-empty-inline' }, [ _('This radio is not reported any more.') ]) ] };
		var rr = this.st.radioRates[r.id], ins = this.st.radioInsights[r.id] || { notes: [] };
		var clients = this.m.clients.filter(function(c) { return c.radio === r.id; });
		return {
			title: [ E('span', { 'class': 'vt-drawer-ico' }, [ icon('radio') ]), E('div', { 'class': 'vt-drawer-titles' }, [
				E('div', { 'class': 'vt-drawer-name' }, [ r.bandLabel + ' · ' + (r.gen || r.id) ]),
				E('div', { 'class': 'vt-drawer-sub vt-mono' }, [ r.id + (r.htmode ? ' · ' + r.htmode : '') ])
			]) ],
			body: [
				E('div', { 'class': 'vt-dactions' }, [ pageLink(insight.PAGES.wireless, _('Radio settings')) ]),
				E('div', { 'class': 'vt-dgrid' }, [
					E('div', { 'class': 'vt-dcard' }, [ E('div', { 'class': 'vt-dcard-label' }, [ _('Channel') ]), E('div', { 'class': 'vt-dcard-value' }, [ r.channel ? String(r.channel) : fmt.DASH ]), E('div', { 'class': 'vt-dcard-sub' }, [ [ r.width ? _('%s MHz').format(r.width) : null, r.freq ? fmt.mhz(r.freq) : null ].filter(Boolean).join(' · ') ]) ]),
					E('div', { 'class': 'vt-dcard' }, [ E('div', { 'class': 'vt-dcard-label' }, [ _('Traffic') ]), E('div', { 'class': 'vt-dcard-value' }, [ rr ? fmt.bits(rr.tx + rr.rx) : fmt.DASH ]), E('div', { 'class': 'vt-dcard-sub vt-tn' }, [ rr ? '↓ ' + fmt.bits(rr.tx) + ' · ↑ ' + fmt.bits(rr.rx) : '' ]), sparkline(this.st.hist.net[r.id] || [], [ 2, 1 ], 0, 'vt-spark-' + (r.band || 'x'), { min: 1000, scale: bitsLabel }) ])
				]),
				ins.notes.length ? E('ul', { 'class': 'vt-notes' }, ins.notes.map(function(n) { return E('li', { 'class': 'vt-note vt-note-' + n.level }, [ icon(n.level === 'warn' ? 'warn' : 'info', 'vt-ico-sm'), E('span', {}, [ n.text ]) ]); })) : '',
				this.section(_('Radio'), [ E('dl', { 'class': 'vt-kvs' }, [
					kv(_('Status'), r.disabled ? _('Disabled') : r.up ? _('Up') : _('Down')),
					kv(_('Mode'), [ r.htmode || fmt.DASH, r.hwmodes ? E('small', {}, [ r.hwmodes ]) : '' ]),
					kv(_('Centre frequency'), r.spectrum ? _('%d MHz (%d–%d MHz)').format(r.spectrum.centre, r.spectrum.lo, r.spectrum.hi) : fmt.DASH),
					kv(_('Tx power'), r.txpower != null ? _('%s dBm').format(r.txpower) + (r.txpowerCfg != null && r.txpowerCfg !== r.txpower ? ' ' + _('(configured %d dBm, limited by regulatory rules)').format(r.txpowerCfg) : '') : fmt.DASH),
					kv(_('Noise floor'), r.noise != null ? fmt.dbm(r.noise) : E('span', { 'class': 'vt-muted' }, [ r.noiseRaw != null ? _('not reported (driver placeholder %s)').format(fmt.dbm(r.noiseRaw)) : _('not reported') ])),
					kv(_('Country'), r.country || fmt.DASH)
				]) ]),
				this.section(_('Clients on this radio'), clients.length ? [ E('div', { 'class': 'vt-dlist' }, clients.map(function(c) {
					return E('button', { 'type': 'button', 'class': 'vt-dlist-row', 'click': function() { self.openDrawer('client', c.mac); } }, [
						avatar(c, true), E('span', { 'class': 'vt-dlist-name' }, [ c.name ]),
						E('span', { 'class': 'vt-signal' }, [ signalGlyph(c.level), E('span', { 'class': 'vt-tn' }, [ fmt.dbm(c.signal) ]) ])
					]);
				})) ] : [ E('p', { 'class': 'vt-empty-inline' }, [ _('No clients; an idle radio is fine.') ]) ])
			]
		};
	},

	drawerUplink: function() {
		var up = this.m.uplink, r = this.st.uplinkRate;
		if (!up) return { title: [ E('span', { 'class': 'vt-drawer-name' }, [ _('Uplink') ]) ], body: [ E('p', { 'class': 'vt-empty-inline' }, [ _('No interface with a route is up.') ]) ] };
		var s = up.stats || {};
		return {
			title: [ E('span', { 'class': 'vt-drawer-ico' }, [ icon('globe') ]), E('div', { 'class': 'vt-drawer-titles' }, [
				E('div', { 'class': 'vt-drawer-name' }, [ _('Uplink · %s').format(up.iface) ]),
				E('div', { 'class': 'vt-drawer-sub vt-mono' }, [ up.l3dev + (up.dev !== up.l3dev ? ' → ' + up.dev : '') ])
			]) ],
			body: [
				E('div', { 'class': 'vt-dactions' }, [ pageLink(insight.PAGES.network, _('Interfaces')), pageLink(insight.PAGES.realtime, _('Realtime graphs')) ]),
				E('div', { 'class': 'vt-dgrid' }, [
					E('div', { 'class': 'vt-dcard' }, [ E('div', { 'class': 'vt-dcard-label' }, [ _('From network') ]), E('div', { 'class': 'vt-dcard-value' }, [ r ? fmt.bits(r.rx) : fmt.DASH ]), E('div', { 'class': 'vt-dcard-sub' }, [ _('received on %s').format(up.dev) ]) ]),
					E('div', { 'class': 'vt-dcard' }, [ E('div', { 'class': 'vt-dcard-label' }, [ _('To network') ]), E('div', { 'class': 'vt-dcard-value' }, [ r ? fmt.bits(r.tx) : fmt.DASH ]), E('div', { 'class': 'vt-dcard-sub' }, [ _('sent on %s').format(up.dev) ]) ])
				]),
				E('div', { 'class': 'vt-dspark' }, [ sparkline(this.st.hist.net.uplink || [], [ 1, 2 ], 0, 'vt-spark-up', { min: 1000, scale: bitsLabel }) ]),
				this.section(_('Link'), [ E('dl', { 'class': 'vt-kvs' }, [
					kv(_('Carrier'), up.carrier === false ? _('No link') : _('Up')),
					kv(_('Speed'), model.speedLabel(up.speed)),
					kv(_('Protocol'), up.proto || fmt.DASH),
					kv(_('Interface up for'), up.uptime != null ? fmt.duration(up.uptime) : fmt.DASH)
				]) ]),
				this.section(_('Addresses'), [ E('dl', { 'class': 'vt-kvs' }, [
					kv(_('IPv4'), up.ipv4.join('\n') || fmt.DASH, true),
					kv(_('IPv6'), up.ipv6.join('\n') || fmt.DASH, true),
					kv(_('Gateway'), up.gateway || fmt.DASH, true),
					kv(_('DNS'), up.dns.join('\n') || fmt.DASH, true)
				]) ]),
				this.section(_('Counters since boot'), [ E('dl', { 'class': 'vt-kvs' }, [
					kv(_('Received'), fmt.bytes(s.rx_bytes) + ' · ' + _('%d errors').format(+s.rx_errors || 0)),
					kv(_('Sent'), fmt.bytes(s.tx_bytes) + ' · ' + _('%d errors').format(+s.tx_errors || 0)),
					kv(_('Dropped'), _('%d in · %d out').format(+s.rx_dropped || 0, +s.tx_dropped || 0))
				]) ])
			]
		};
	},

	drawerDevice: function() {
		var d = this.m.device, cpu = this.st.cpu;
		return {
			title: [ E('span', { 'class': 'vt-drawer-ico' }, [ icon('ap') ]), E('div', { 'class': 'vt-drawer-titles' }, [
				E('div', { 'class': 'vt-drawer-name' }, [ d.model ]),
				E('div', { 'class': 'vt-drawer-sub' }, [ d.hostname || '' ])
			]) ],
			body: [
				E('div', { 'class': 'vt-dactions' }, [ pageLink([ 'admin', 'system', 'system' ], _('System settings')), pageLink(insight.PAGES.processes, _('Processes')) ]),
				this.section(_('Device'), [ E('dl', { 'class': 'vt-kvs' }, [
					kv(_('Model'), d.model),
					kv(_('Platform'), [ d.target || fmt.DASH, d.system ? E('small', {}, [ d.system ]) : '' ]),
					kv(_('Firmware'), d.firmware || fmt.DASH),
					kv(_('Kernel'), d.kernel || fmt.DASH),
					kv(_('Uptime'), d.uptime != null ? fmt.duration(d.uptime) : fmt.DASH),
					kv(_('Local time'), d.localtime != null ? new Date(d.localtime * 1000).toISOString().replace('T', ' ').replace(/\.\d+Z$/, '') : fmt.DASH, true)
				]) ]),
				this.section(_('Load'), [ E('dl', { 'class': 'vt-kvs' }, [
					kv(_('CPU'), cpu ? _('%s over %d cores').format(fmt.pct(cpu.pct), cpu.cores.length || 1) : fmt.DASH),
					kv(_('Load average'), d.load.map(fmt.load).join(' · ')),
					kv(_('Memory in use'), d.memory ? _('%s of %s').format(fmt.bytes(d.memory.used), fmt.bytes(d.memory.total)) : fmt.DASH)
				]) ])
			]
		};
	},

	/* ---------------------------------------------------------- keyboard */

	handleKey: function(ev) {
		var t = ev.target, typing = t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
		if (ev.key === 'Escape' && this.ui.drawer && !document.body.classList.contains('modal-overlay-active')) {
			this.closeDrawer();
			return;
		}
		/* 'f' focuses the client filter; '/' and Ctrl+K belong to the theme */
		if ((ev.key === 'f' || ev.key === 'F') && !typing && !ev.ctrlKey && !ev.metaKey && !ev.altKey && !this.ui.drawer) {
			ev.preventDefault();
			this.el.filter.focus();
			this.el.filter.select();
		}
		if (ev.key === 'Escape' && t === this.el.filter && this.ui.filter) this.setFilter('');
	}
});
