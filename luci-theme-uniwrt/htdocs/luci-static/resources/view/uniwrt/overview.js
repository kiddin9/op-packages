'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require fs';

var callBoard = rpc.declare({ object: 'system', method: 'board' });
var callInfo  = rpc.declare({ object: 'system', method: 'info' });
var callIfDump = rpc.declare({ object: 'network.interface', method: 'dump', expect: { 'interface': [] } });
var callWifi  = rpc.declare({ object: 'luci-rpc', method: 'getWirelessDevices', expect: { '': {} } });
var callHints = rpc.declare({ object: 'luci-rpc', method: 'getHostHints', expect: { '': {} } });
var callAssoc = rpc.declare({ object: 'iwinfo', method: 'assoclist', params: [ 'device' ], expect: { results: [] } });
/* usteer (optional): stations of the other access points it peers with */
var callUsteer = rpc.declare({ object: 'usteer', method: 'get_clients', expect: { '': {} } });
var callNetDevs = rpc.declare({ object: 'network.device', method: 'status', expect: { '': {} } });

function svgNode(markup) {
	if (markup.indexOf('xmlns') < 0)
		markup = markup.replace('<svg', '<svg xmlns="http://www.w3.org/2000/svg"');
	var doc = new DOMParser().parseFromString(markup, 'image/svg+xml');
	return document.importNode(doc.documentElement, true);
}
function fmtBytes(b) {
	if (!b && b !== 0) return '–';
	if (b >= 1073741824) return (b / 1073741824).toFixed(2) + ' GB';
	if (b >= 1048576) return (b / 1048576).toFixed(1) + ' MB';
	if (b >= 1024) return (b / 1024).toFixed(0) + ' KB';
	return b + ' B';
}
function fmtUptime(s) {
	if (!s) return '–';
	var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
	var p = [];
	if (d) p.push(_('%dd').format(d));
	if (h) p.push(_('%dh').format(h));
	p.push(_('%dm').format(m));
	return p.join(' ');
}
function level(pct) { return pct < 60 ? 'ok' : pct < 85 ? 'warn' : 'crit'; }

function metricCard(icon, title, valueId, subId, withMeter) {
	var body = [
		E('div', { 'class': 'u-card-head' }, [
			E('div', { 'class': 'u-card-ico' }, [ svgNode(icon) ]),
			E('div', { 'class': 'u-card-title' }, [ title ])
		]),
		E('div', { 'class': 'u-card-metric', 'id': valueId }, [ '–' ])
	];
	if (withMeter)
		body.push(E('div', { 'class': 'u-meter', 'id': valueId + '-meter' }, [ E('i', { 'style': 'transform:scaleX(0)' }) ]));
	body.push(E('div', { 'class': 'u-card-sub', 'id': subId }, [ '' ]));
	return E('div', { 'class': 'u-card' }, body);
}

var ICO = {
	chip:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><line x1="9" y1="1" x2="9" y2="4"/><line x1="15" y1="1" x2="15" y2="4"/><line x1="9" y1="20" x2="9" y2="23"/><line x1="15" y1="20" x2="15" y2="23"/><line x1="20" y1="9" x2="23" y2="9"/><line x1="20" y1="14" x2="23" y2="14"/><line x1="1" y1="9" x2="4" y2="9"/><line x1="1" y1="14" x2="4" y2="14"/></svg>',
	ram:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="10" rx="1"/><line x1="6" y1="7" x2="6" y2="17"/><line x1="12" y1="7" x2="12" y2="17"/><line x1="18" y1="7" x2="18" y2="17"/></svg>',
	clock:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 16 14"/></svg>',
	box:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>',
	globe:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><line x1="3" y1="12" x2="21" y2="12"/><path d="M12 3a15 15 0 014 9 15 15 0 01-4 9 15 15 0 01-4-9 15 15 0 014-9z"/></svg>',
	wifi:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.55a11 11 0 0114 0"/><path d="M1.42 9a16 16 0 0121.16 0"/><path d="M8.53 16.11a6 6 0 016.95 0"/><line x1="12" y1="20" x2="12.01" y2="20"/></svg>',
	users:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87"/><path d="M16 3.13a4 4 0 010 7.75"/></svg>',
	disk:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/><path d="M3 12c0 1.66 4 3 9 3s9-1.34 9-3"/></svg>',
	bolt:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><polyline points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>',
	grid:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>',
	down:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="4" x2="12" y2="20"/><polyline points="6 14 12 20 18 14"/></svg>',
	up:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="20" x2="12" y2="4"/><polyline points="6 10 12 4 18 10"/></svg>'
};

/* shared route helper (degrades gracefully if L.url is unavailable) */
function url(path) { try { return L.url(path); } catch (e) { return '/cgi-bin/luci/' + path; } }

/* resolve a quick-action target against the LIVE menu tree so links can never
   404: dispatcher paths differ between LuCI builds, so we (1) try known
   candidate paths in order and (2) fall back to searching the tree for a leaf
   whose node name matches a keyword under a hint branch. Returns a real path
   that exists for THIS device, or null (in which case the tile is hidden). */
function nodeAt(tree, path) {
	var parts = path.split('/'), node = tree;
	for (var i = 0; i < parts.length; i++) {
		var kids = (node && node.children) || {};
		if (!kids[parts[i]]) return null;
		node = kids[parts[i]];
	}
	return node;
}
function searchTree(tree, re, hint) {
	var found = null;
	(function walk(node, path) {
		if (found) return;
		var kids = (node && node.children) || {};
		Object.keys(kids).forEach(function(name) {
			if (found) return;
			var p = path.concat(name);
			if (re.test(name) && (!hint || p.indexOf(hint) >= 0)) { found = p.join('/'); return; }
			walk(kids[name], p);
		});
	})(tree, []);
	return found;
}
function resolvePath(tree, candidates, re, hint) {
	if (!tree) return candidates && candidates[0] || null;   /* tree missing: best-effort */
	for (var i = 0; i < (candidates || []).length; i++)
		if (nodeAt(tree, candidates[i])) return candidates[i];
	return re ? searchTree(tree, re, hint) : null;
}

/* meters are driven by a composited transform rather than width */
function setMeter(meterEl, pct) {
	if (!meterEl) return;
	var fill = meterEl.firstElementChild;
	if (fill) fill.style.transform = 'scaleX(' + Math.max(0, Math.min(100, pct)) / 100 + ')';
}

function fmtRate(bps) {
	var mbps = (bps || 0) * 8 / 1e6;        /* bytes/s -> Mbps */
	if (mbps >= 100) return mbps.toFixed(0);
	if (mbps >= 10)  return mbps.toFixed(1);
	return mbps.toFixed(2);
}

/* Resolve the device whose counters actually reflect WAN throughput. On DSA
   switches (e.g. MT7622) with hardware flow offload the wan PORT's software
   byte counter stays near zero, so we must follow the bridge member and then
   the DSA 'conduit' device — the same resolution the header status bar uses.
   Works entirely from the full `network.device status` map (no extra calls). */
function resolveWanDev(ifaces, devs) {
	if (!Array.isArray(ifaces)) return null;
	var wan = ifaces.filter(function(i){ return i.interface === 'wan'  && i.up; })[0]
	       || ifaces.filter(function(i){ return i.interface === 'wan6' && i.up; })[0]
	       || ifaces.filter(function(i){ return /wan/i.test(i.interface) && i.up; })[0]
	       /* access point behind a main router: the LAN holds the default route */
	       || ifaces.filter(function(i){ return i.up && (i.route || []).some(function(r){ return r.target === '0.0.0.0' && r.mask === 0; }); })[0]
	       || ifaces.filter(function(i){ return i.up && i.interface !== 'loopback' && (i.l3_device || i.device); })[0];
	if (!wan) return null;
	var dev = wan.l3_device || wan.device, name = wan.interface;
	var d = devs && devs[dev];
	if (d) {
		if (d.type === 'bridge' && Array.isArray(d['bridge-members']) && d['bridge-members'].length) {
			/* the uplink port carries everything: take the busiest wired member */
			var most = -1;
			d['bridge-members'].forEach(function(m) {
				if (/^(wl|phy|wlan|ath|ra|rai|apcli)\d/.test(m)) return;
				var st = (devs[m] || {}).statistics || {}, b = (st.rx_bytes || 0) + (st.tx_bytes || 0);
				if (b > most) { most = b; dev = m; }
			});
			if (most < 0) dev = d['bridge-members'][0];
			d = (devs && devs[dev]) || d;
		}
		if (d && d.devtype === 'dsa' && d['hw-tc-offload'] && d.conduit && devs[d.conduit])
			dev = d.conduit;
	}
	return { dev: dev, name: name };
}

return view.extend({
	cores: 1,

	load: function() {
		var self = this;
		return Promise.all([
			L.resolveDefault(callBoard(), {}),
			L.resolveDefault(callInfo(), {}),
			L.resolveDefault(fs.read('/proc/cpuinfo'), ''),
			L.resolveDefault(ui.menu.load(), {})
		]).then(function(d) {
			/* core count comes from the ROUTER, never the browser */
			var m = String(d[2] || '').match(/^processor\s*:/gm);
			self.cores = (m && m.length) || 1;
			self.menuTree = d[3] || {};
			return d;
		});
	},

	render: function(data) {
		var board = data[0] || {}, info = data[1] || {};
		var self = this;

		var grid = E('div', { 'class': 'u-grid', 'style': 'grid-template-columns:repeat(auto-fit,minmax(210px,1fr))' }, [
			metricCard(ICO.box,   _('System'),  'u-ov-sys',  'u-ov-sys-sub',  false),
			metricCard(ICO.chip,  _('CPU Load'),'u-ov-cpu',  'u-ov-cpu-sub',  true),
			metricCard(ICO.ram,   _('Memory'),  'u-ov-ram',  'u-ov-ram-sub',  true),
			metricCard(ICO.clock, _('Uptime'),  'u-ov-up',   'u-ov-up-sub',   false)
		]);

		var ifaceCard = E('div', { 'class': 'u-card' }, [
			E('div', { 'class': 'u-card-head' }, [
				E('div', { 'class': 'u-card-ico' }, [ svgNode(ICO.globe) ]),
				E('div', { 'class': 'u-card-title' }, [ _('Network Interfaces') ])
			]),
			E('div', { 'id': 'u-ov-ifaces' }, [ E('div', { 'class': 'u-card-sub' }, [ _('Loading…') ]) ])
		]);

		var wifiCard = E('div', { 'class': 'u-card' }, [
			E('div', { 'class': 'u-card-head' }, [
				E('div', { 'class': 'u-card-ico' }, [ svgNode(ICO.wifi) ]),
				E('div', { 'class': 'u-card-title' }, [ _('Wireless') ])
			]),
			E('div', { 'id': 'u-ov-wifi' }, [ E('div', { 'class': 'u-card-sub' }, [ _('Loading…') ]) ])
		]);

		var clientsCard = E('div', { 'class': 'u-card' }, [
			E('div', { 'class': 'u-card-head' }, [
				E('div', { 'class': 'u-card-ico' }, [ svgNode(ICO.users) ]),
				E('div', { 'class': 'u-card-title' }, [ _('Clients') ])
			]),
			E('div', { 'id': 'u-ov-clients' }, [ E('div', { 'class': 'u-card-sub' }, [ _('Loading…') ]) ])
		]);

		/* ---- Storage card: root + RAM filesystem usage with bars ---- */
		var storageCard = E('div', { 'class': 'u-card' }, [
			E('div', { 'class': 'u-card-head' }, [
				E('div', { 'class': 'u-card-ico' }, [ svgNode(ICO.disk) ]),
				E('div', { 'class': 'u-card-title' }, [ _('Storage') ])
			]),
			E('div', { 'id': 'u-ov-storage' }, [ E('div', { 'class': 'u-card-sub' }, [ _('Loading…') ]) ])
		]);

		/* ---- Live throughput card: WAN down/up + peak, 24h and since-restart ---- */
		function tpRow(label, downId, upId) {
			return E('div', { 'class': 'u-tp-row' }, [
				E('span', { 'class': 'u-tp-label' }, [ label ]),
				E('span', { 'class': 'u-tp-down', 'id': downId }, [ '–' ]),
				E('span', { 'class': 'u-tp-up', 'id': upId }, [ '–' ])
			]);
		}
		var thruCard = E('div', { 'class': 'u-card' }, [
			E('div', { 'class': 'u-card-head' }, [
				E('div', { 'class': 'u-card-ico' }, [ svgNode(ICO.bolt) ]),
				E('div', { 'class': 'u-card-title' }, [ _('Live Throughput') ])
			]),
			E('div', { 'class': 'u-thru' }, [
				E('div', { 'class': 'u-thru-col' }, [
					E('div', { 'class': 'u-thru-head' }, [ svgNode(ICO.down), _('Download') ]),
					E('div', { 'class': 'u-thru-val', 'id': 'u-ov-rx' }, [ '0.00' ]),
					E('div', { 'class': 'u-thru-unit' }, [ 'Mbps' ])
				]),
				E('div', { 'class': 'u-thru-col' }, [
					E('div', { 'class': 'u-thru-head' }, [ svgNode(ICO.up), _('Upload') ]),
					E('div', { 'class': 'u-thru-val', 'id': 'u-ov-tx' }, [ '0.00' ]),
					E('div', { 'class': 'u-thru-unit' }, [ 'Mbps' ])
				])
			]),
			E('div', { 'class': 'u-tp-stats' }, [
				E('div', { 'class': 'u-tp-row u-tp-headrow' }, [
					E('span', { 'class': 'u-tp-label' }, [ '' ]),
					E('span', { 'class': 'u-tp-down' }, [ '\u2193 ' + _('Download') ]),
					E('span', { 'class': 'u-tp-up' }, [ '\u2191 ' + _('Upload') ])
				]),
				tpRow(_('Peak'),          'u-ov-peak-rx', 'u-ov-peak-tx'),
				tpRow(_('Last 24 h'),     'u-ov-24h-rx',  'u-ov-24h-tx'),
				tpRow(_('Since restart'), 'u-ov-tot-rx',  'u-ov-tot-tx')
			]),
			E('div', { 'class': 'u-card-sub', 'id': 'u-ov-thru-sub', 'style': 'margin-top:10px' }, [ _('Measuring…') ])
		]);

		/* ---- Quick Actions launchpad ----
		   Each entry lists candidate dispatcher paths plus a keyword fallback;
		   resolvePath() picks the one that exists on THIS device. Tiles whose
		   target isn't registered are omitted, so a click can never 404. */
		var actionDefs = [
			{ t: _('Interfaces'),     i: ICO.globe, c: ['admin/network/network'],                                              re: /^(network|interfaces?)$/, h: 'network' },
			{ t: _('Wireless'),       i: ICO.wifi,  c: ['admin/network/wireless'],                                             re: /^(wireless|wifi)$/,       h: 'network' },
			{ t: _('DHCP & DNS'),     i: ICO.users, c: ['admin/network/dhcp'],                                                  re: /^(dhcp|dnsmasq)$/,        h: 'network' },
			{ t: _('Firewall'),       i: ICO.box,   c: ['admin/network/firewall'],                                             re: /^firewall$/,              h: 'network' },
			{ t: _('System Log'),     i: ICO.clock, c: ['admin/status/syslog', 'admin/status/logs/syslog', 'admin/status/logread', 'admin/status/logs'], re: /^(syslog|logread|logs|log)$/, h: 'status' },
			{ t: _('Software'),       i: ICO.disk,  c: ['admin/system/package-manager', 'admin/system/opkg', 'admin/system/software'], re: /^(package-manager|opkg|software)$/, h: 'system' },
			{ t: _('Backup / Flash'), i: ICO.bolt,  c: ['admin/system/flash', 'admin/system/flashops'],                        re: /^(flash|flashops)$/,      h: 'system' },
			{ t: _('Reboot'),         i: ICO.chip,  c: ['admin/system/reboot'],                                                re: /^reboot$/,                h: 'system' }
		];
		var actionTiles = [];
		actionDefs.forEach(function(a) {
			var path = resolvePath(self.menuTree, a.c, a.re, a.h);
			if (!path) return;   /* not present on this build -> skip (never 404) */
			actionTiles.push(E('a', { 'class': 'u-action', 'href': url(path) }, [
				E('span', { 'class': 'u-action-ico' }, [ svgNode(a.i) ]),
				E('span', { 'class': 'u-action-label' }, [ a.t ])
			]));
		});
		var actionsCard = actionTiles.length ? E('div', { 'class': 'u-card' }, [
			E('div', { 'class': 'u-card-head' }, [
				E('div', { 'class': 'u-card-ico' }, [ svgNode(ICO.grid) ]),
				E('div', { 'class': 'u-card-title' }, [ _('Quick Actions') ])
			]),
			E('div', { 'class': 'u-actions' }, actionTiles)
		]) : null;

		var root = E('div', {}, [
			E('p', { 'class': 'cbi-map-descr' }, [ _('Live overview of this device. Figures refresh automatically.') ]),
			grid,
			/* status cards of equal height, then the actions, then the
			   live figures (throughput beside clients) */
			E('div', { 'class': 'u-grid u-ov-cards' }, [ ifaceCard, wifiCard, storageCard ]),
			actionsCard,
			E('div', { 'class': 'u-grid u-ov-live' }, [ thruCard, clientsCard ])
		].filter(Boolean));

		/* keep a handle so updates can resolve tiles even before LuCI
		   attaches this node to the document (otherwise the first paint
		   would no-op and tiles stay blank until the first poll) */
		this.root = root;

		/* static system card */
		var sysVal = board.model || board.board_name || '–';
		var sysSub = [ board.release ? (board.release.distribution + ' ' + board.release.version) : '', board.kernel ? ('Kernel ' + board.kernel) : '' ].filter(Boolean).join(' · ');
		root.querySelector('#u-ov-sys').textContent = sysVal;
		root.querySelector('#u-ov-sys').style.fontSize = '1.05rem';
		root.querySelector('#u-ov-sys-sub').textContent = sysSub;

		this.update(info);

		poll.add(function() {
			if (document.hidden) return;   /* nothing polled from background tabs */
			/* reuse the status bar's system.info reading when it's fresh (<4.5s)
			   so the Overview page issues one system.info per cycle, not two */
			var cached = (window.__uniwrtInfo && (Date.now() - window.__uniwrtInfo.t) < 4500)
				? Promise.resolve(window.__uniwrtInfo.info) : null;
			/* station lists for the AP interfaces seen last time, and usteer,
			   go in the same batched request as everything else */
			var apIfs = (self._apIfs || []).slice();
			return Promise.all([
				cached || L.resolveDefault(callInfo(), {}),
				L.resolveDefault(callIfDump(), []),
				L.resolveDefault(callWifi(), {}),
				L.resolveDefault(callHints(), {}),
				L.resolveDefault(callNetDevs(), {}),
				Promise.all(apIfs.map(function(ifn) { return L.resolveDefault(callAssoc(ifn), []); })),
				L.resolveDefault(callUsteer(), {})
			]).then(function(d) {
				self.update(d[0]);
				self.updateIfaces(d[1]);
				self.updateWifi(d[2]);
				self.updateClients(d[3], d[4], d[1], d[2], { ifs: apIfs, r: [ d[5], d[6] ] });
				self.updateThroughput(d[4], d[1]);
			});
		}, 5);

		/* first interface/wifi/clients/throughput paint */
		Promise.all([ L.resolveDefault(callIfDump(), []), L.resolveDefault(callWifi(), {}), L.resolveDefault(callHints(), {}), L.resolveDefault(callNetDevs(), {}) ])
			.then(function(d) { self.updateIfaces(d[0]); self.updateWifi(d[1]); self.updateClients(d[2], d[3], d[0], d[1]); self.updateThroughput(d[3], d[0]); });

		return root;
	},

	update: function(info) {
		if (!info) return;
		var root = this.root;
		var $ = function(id) { return root ? root.querySelector('#' + id) : document.getElementById(id); };
		var cores = this.cores || 1;

		if (info.load && info.load.length && $('u-ov-cpu')) {
			var load1 = info.load[0] / 65536;
			var pct = Math.min(load1 / cores, 1) * 100;
			$('u-ov-cpu').textContent = pct.toFixed(0) + '%';
			var meter = $('u-ov-cpu-meter');
			if (meter) { meter.className = 'u-meter ' + level(pct); setMeter(meter, pct); }
			$('u-ov-cpu-sub').textContent = _('Load average') + ': ' + load1.toFixed(2) + ' (' + cores + ' ' + (cores === 1 ? _('core') : _('cores')) + ')';
		}
		if (info.memory && info.memory.total && $('u-ov-ram')) {
			var total = info.memory.total, avail = info.memory.available || info.memory.free, used = total - avail;
			var pctR = used / total * 100;
			$('u-ov-ram').textContent = pctR.toFixed(0) + '%';
			var mr = $('u-ov-ram-meter');
			if (mr) { mr.className = 'u-meter ' + level(pctR); setMeter(mr, pctR); }
			$('u-ov-ram-sub').textContent = fmtBytes(used) + ' / ' + fmtBytes(total);
		}
		if (info.uptime && $('u-ov-up')) {
			$('u-ov-up').textContent = fmtUptime(info.uptime);
			$('u-ov-up').style.fontSize = '1.4rem';
			/* 'unixtime' is the real instant; 'localtime' is already shifted by the
			   router's UTC offset, so it may only be shown as if it were UTC */
			if (info.unixtime) $('u-ov-up-sub').textContent = new Date(info.unixtime * 1000).toLocaleString();
			else if (info.localtime) $('u-ov-up-sub').textContent = new Date(info.localtime * 1000).toLocaleString(undefined, { timeZone: 'UTC' });
		}
		this.updateStorage(info);
	},

	updateStorage: function(info) {
		var box = (this.root || document).querySelector('#u-ov-storage');
		if (!box || !info) return;
		function bar(label, used, total) {
			if (!total) return null;
			var pct = Math.round(used / total * 100);
			return E('div', { 'class': 'u-store-row' }, [
				E('div', { 'class': 'u-store-top' }, [
					E('span', {}, [ label ]),
					E('span', { 'class': 'u-store-num' }, [ fmtBytes(used) + ' / ' + fmtBytes(total) + ' (' + pct + '%)' ])
				]),
				E('div', { 'class': 'u-meter ' + level(pct) }, [ E('i', { 'style': 'transform:scaleX(' + (pct / 100) + ')' }) ])
			]);
		}
		/* procd reports root/tmp in KiB (like LuCI's Status page, scale to bytes);
		   swap comes in bytes */
		var kib = function(fs) { return { used: 1024 * (fs.used != null ? fs.used : fs.total - fs.free), total: 1024 * fs.total }; };
		var rows = [], fs;
		if (info.root && info.root.total) { fs = kib(info.root); rows.push(bar(_('Disk (root)'), fs.used, fs.total)); }
		if (info.tmp  && info.tmp.total)  { fs = kib(info.tmp);  rows.push(bar(_('RAM (tmp)'),  fs.used, fs.total)); }
		if (info.swap && info.swap.total) rows.push(bar(_('Swap'),       (info.swap.total - info.swap.free), info.swap.total));
		rows = rows.filter(Boolean);
		box.innerHTML = '';
		rows.length ? rows.forEach(function(r) { box.appendChild(r); })
		            : box.appendChild(E('div', { 'class': 'u-card-sub' }, [ _('Storage info unavailable') ]));
	},

	/* live WAN throughput from interface counter deltas */
	/* live WAN throughput + peak / 24h / since-restart, from interface counters.
	   Byte counters accumulate on the device even when this page is closed, so
	   sparse persisted snapshots let us compute true totals over a time window. */
	updateThroughput: function(devs, ifaces) {
		var q = this.root || document;
		var rxEl = q.querySelector('#u-ov-rx'), txEl = q.querySelector('#u-ov-tx');
		var subEl = q.querySelector('#u-ov-thru-sub');
		if (!rxEl || !txEl) return;
		function set(sel, val) { var el = q.querySelector(sel); if (el) el.textContent = val; }

		/* resolve the counter-bearing device once (conduit-aware) */
		if (!this._wan) {
			var r = resolveWanDev(ifaces, devs);
			if (r) { this._wan = r.dev; this._wanName = r.name; }
		}
		var dev = this._wan;
		var st = dev && devs && devs[dev] && devs[dev].statistics;
		if (!st) { if (subEl) subEl.textContent = _('Waiting for WAN device…'); return; }

		var now = Date.now(), nowS = Math.floor(now / 1000);
		var rx = st.rx_bytes || 0, tx = st.tx_bytes || 0;

		/* load persisted record for this device */
		var key = 'uniwrt-tp-' + dev, rec = null;
		try { rec = JSON.parse(localStorage.getItem(key) || 'null'); } catch (e) {}
		if (!rec || typeof rec !== 'object') rec = { peakRx: 0, peakTx: 0, s: [] };
		if (!Array.isArray(rec.s)) rec.s = [];
		/* counter reset (reboot/iface bounce) -> drop stale history & peaks */
		if (rec.s.length && rx < rec.s[rec.s.length - 1][1]) rec = { peakRx: 0, peakTx: 0, s: [] };

		/* live rate from the in-memory previous sample */
		if (this._lastT) {
			var dt = (now - this._lastT) / 1000;
			if (dt > 0) {
				var rxRate = Math.max(0, (rx - this._lastRx) / dt);
				var txRate = Math.max(0, (tx - this._lastTx) / dt);
				rxEl.textContent = fmtRate(rxRate);
				txEl.textContent = fmtRate(txRate);
				if (rxRate > rec.peakRx) rec.peakRx = rxRate;
				if (txRate > rec.peakTx) rec.peakTx = txRate;
			}
		}
		this._lastRx = rx; this._lastTx = tx; this._lastT = now;

		/* append a sparse snapshot (~every 5 min), keep ~25h */
		var last = rec.s[rec.s.length - 1];
		if (!last || (nowS - last[0]) >= 300) {
			rec.s.push([nowS, rx, tx]);
			var cutoff = nowS - 90000;
			rec.s = rec.s.filter(function(x) { return x[0] >= cutoff; });
		}

		/* 24h window: delta from the oldest snapshot within 24h (else oldest we have) */
		var since = nowS - 86400, base = null;
		for (var i = 0; i < rec.s.length; i++) { if (rec.s[i][0] >= since) { base = rec.s[i]; break; } }
		if (!base && rec.s.length) base = rec.s[0];
		var winH = base ? Math.max(0, (nowS - base[0]) / 3600) : 0;
		var d24rx = base ? Math.max(0, rx - base[1]) : 0;
		var d24tx = base ? Math.max(0, tx - base[2]) : 0;

		try { localStorage.setItem(key, JSON.stringify(rec)); } catch (e) {}

		/* paint the stat rows */
		set('#u-ov-peak-rx', rec.peakRx > 0 ? fmtRate(rec.peakRx) + ' Mbps' : '–');
		set('#u-ov-peak-tx', rec.peakTx > 0 ? fmtRate(rec.peakTx) + ' Mbps' : '–');
		set('#u-ov-24h-rx', base ? fmtBytes(d24rx) : '–');
		set('#u-ov-24h-tx', base ? fmtBytes(d24tx) : '–');
		set('#u-ov-tot-rx', fmtBytes(rx));
		set('#u-ov-tot-tx', fmtBytes(tx));

		/* annotate the 24h row with the real window length until it reaches 24h */
		var row24 = q.querySelector('#u-ov-24h-rx');
		row24 = row24 && row24.parentNode;
		if (row24) {
			var lbl = row24.querySelector('.u-tp-label');
			if (lbl) lbl.textContent = (winH >= 23.5) ? _('Last 24 h')
				: (winH >= 1) ? _('Last %d h').format(Math.round(winH))
				: _('Last 24 h');
			row24.title = base ? _('Measured over the last %s hours').format(winH.toFixed(1)) : '';
		}

		if (subEl) subEl.textContent = (this._wanName || dev) + (dev !== this._wanName ? ' \u00b7 ' + dev : '');
	},

	updateIfaces: function(ifaces) {
		var box = (this.root || document).querySelector('#u-ov-ifaces');
		if (!box || !Array.isArray(ifaces)) return;
		var rows = [];
		ifaces.forEach(function(iface) {
			if (iface.interface === 'loopback') return;
			var up = !!iface.up;
			var addr = (iface['ipv4-address'] && iface['ipv4-address'][0]) ? iface['ipv4-address'][0].address : null;
			if (!addr && iface['ipv6-address'] && iface['ipv6-address'][0]) addr = iface['ipv6-address'][0].address;
			rows.push(E('div', { 'class': 'u-kv' }, [
				E('span', { 'class': 'k' }, [ E('span', { 'class': 'u-dot ' + (up ? 'up' : 'down') }), iface.interface ]),
				E('span', { 'class': 'v' }, [ addr || (up ? _('Connected') : _('Disconnected')) ])
			]));
		});
		box.innerHTML = '';
		rows.length ? rows.forEach(function(r) { box.appendChild(r); }) : box.appendChild(E('div', { 'class': 'u-card-sub' }, [ _('No interfaces') ]));
	},

	updateClients: function(hints, devs, ifaces, wifi, pre) {
		var self = this;
		var box = (this.root || document).querySelector('#u-ov-clients');
		if (!box || !hints) return;
		/* host hints also cover this router's own interfaces and the gateways
		   it talks to (ISP, or the main router on an access point) */
		var own = {}, gws = {};
		Object.keys(devs || {}).forEach(function(n) { var d = devs[n] || {}, m = d.macaddr || d.mac; if (m) own[String(m).toUpperCase()] = true; });
		(Array.isArray(ifaces) ? ifaces : []).forEach(function(i) {
			(i.route || []).forEach(function(r) { if (r.nexthop && r.nexthop !== '0.0.0.0') gws[r.nexthop] = true; });
		});
		function hintOf(mac) { return hints[mac] || hints[mac.toUpperCase()] || hints[mac.toLowerCase()] || {}; }
		function ipOf(h) { return h.ipv4 || (h.ipaddrs && h.ipaddrs[0]) || h.ipv6 || ''; }
		/* an access point by the name its address has in the host hints */
		function apName(ip) {
			var found = null;
			Object.keys(hints).forEach(function(mac) { var h = hints[mac] || {}; if (!found && h.name && (h.ipaddrs || []).indexOf(ip) >= 0) found = h.name; });
			return found || ip;
		}

		/* this device's access point interfaces */
		var apIfs = [];
		Object.keys(wifi || {}).forEach(function(r) {
			((wifi[r] || {}).interfaces || []).forEach(function(i) {
				if (i && i.ifname && (i.config || {}).mode === 'ap') apIfs.push(i.ifname);
			});
		});

		this._apIfs = apIfs;

		/* the poll fetched these with everything else; only the first paint
		   (or a change of AP interfaces) needs a request of its own */
		var token = this._clientsToken = (this._clientsToken || 0) + 1;
		(pre && pre.ifs.join(' ') === apIfs.join(' ') ? Promise.resolve(pre.r) : Promise.all([
			Promise.all(apIfs.map(function(ifn) { return L.resolveDefault(callAssoc(ifn), []); })),
			L.resolveDefault(callUsteer(), {})
		])).then(function(r) {
			if (token !== self._clientsToken) return;
			var list = [], seen = {};
			function add(mac, kind, sub, signal) {
				mac = String(mac).toUpperCase();
				if (seen[mac] || own[mac]) return;
				var h = hintOf(mac), ip = ipOf(h), name = h.name || h.host || '';
				seen[mac] = true;
				list.push({ name: name || ip || mac, ip: name ? ip : '', mac: mac, kind: kind, sub: sub, signal: signal });
			}
			/* 1. stations on this device's radios */
			r[0].forEach(function(st) {
				(Array.isArray(st) ? st : []).forEach(function(s) {
					if (s && s.mac) add(s.mac, 'wifi', s.signal ? s.signal + ' dBm' : _('Wi-Fi'), s.signal || -100);
				});
			});
			/* 2. stations on the other access points usteer knows ('ip#hostapd.ifname') */
			var ust = r[1] || {};
			Object.keys(ust).forEach(function(mac) {
				var nodes = ust[mac] || {}, best = null;
				Object.keys(nodes).forEach(function(k) {
					var n = nodes[k] || {};
					if (n.connected && k.indexOf('#') > 0 && (!best || (n.signal || -150) > (best.signal || -150))) best = { ap: k.split('#')[0], signal: n.signal };
				});
				if (best) add(mac, 'mesh', _('via %s').format(apName(best.ap)) + (best.signal ? ' · ' + best.signal + ' dBm' : ''), best.signal || -150);
			});
			/* 3. everything else the host hints know (wired or idle) */
			Object.keys(hints).forEach(function(mac) {
				var h = hints[mac] || {};
				if ((h.ipaddrs || []).some(function(a) { return gws[a]; })) return;
				if (!(h.name || h.host) && !ipOf(h)) return;
				add(mac, 'other', '', -999);
			});

			var rank = { wifi: 0, mesh: 1, other: 2 };
			list.sort(function(a, b) {
				return (rank[a.kind] - rank[b.kind]) || (b.signal - a.signal) || String(a.name).localeCompare(String(b.name));
			});
			box.innerHTML = '';
			if (!list.length) { box.appendChild(E('div', { 'class': 'u-card-sub' }, [ _('No known clients') ])); return; }
			var wireless = list.filter(function(c) { return c.kind !== 'other'; });
			/* Wi-Fi stations first (strongest first), then other hosts: six rows,
			   or up to ten when more stations are connected; the rest are counted */
			var shown = list.slice(0, Math.max(6, Math.min(wireless.length, 10)));
			shown.forEach(function(c) {
				box.appendChild(E('div', { 'class': 'u-kv' }, [
					E('span', { 'class': 'k', 'title': c.mac }, [ E('span', { 'class': 'u-dot up' }), c.name ]),
					E('span', { 'class': 'v' }, [ [ c.ip, c.sub ].filter(Boolean).join(' · ') ])
				]));
			});
			if (list.length > shown.length)
				box.appendChild(E('div', { 'class': 'u-card-sub', 'style': 'margin-top:8px' }, [ _('+%d more · %d total').format(list.length - shown.length, list.length) ]));
		});
	},


	updateWifi: function(wifi) {
		var box = (this.root || document).querySelector('#u-ov-wifi');
		if (!box || !wifi) return;
		var rows = [];
		Object.keys(wifi).forEach(function(dev) {
			var radio = wifi[dev] || {}, ifaces = radio.interfaces || [];
			ifaces.forEach(function(i) {
				var cfg = i.config || {}, iw = i.iwinfo || {};
				var ssid = cfg.ssid || iw.ssid || '–';
				/* netifd reports 'up' per radio, not per network: a network is up
				   when its radio is and it got an interface */
				var up = ('up' in i) ? !!i.up : (!!radio.up && !!i.ifname && !radio.disabled && cfg.disabled != '1' && cfg.disabled !== true);
				var meta = (iw.channel ? (_('Channel %s').format(iw.channel)) : '') + (iw.signal ? ('  ' + iw.signal + ' dBm') : '');
				rows.push(E('div', { 'class': 'u-kv' }, [
					E('span', { 'class': 'k' }, [ E('span', { 'class': 'u-dot ' + (up ? 'up' : 'down') }), ssid ]),
					E('span', { 'class': 'v' }, [ meta || dev ])
				]));
			});
		});
		box.innerHTML = '';
		rows.length ? rows.forEach(function(r) { box.appendChild(r); }) : box.appendChild(E('div', { 'class': 'u-card-sub' }, [ _('No wireless radios') ]));
	},

	handleSaveApply: null, handleSave: null, handleReset: null
});
