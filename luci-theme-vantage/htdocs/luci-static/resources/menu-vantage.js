'use strict';
'require baseclass';
'require ui';
'require rpc';
'require vantage-theme.host as host';

/*
 * Vantage theme - shell behaviour.
 *
 * Renders the icon rail + flyouts (bottom bar + sheet on phones), the
 * breadcrumb, level-3 page tabs, the Ctrl+K / "/" command palette, the host
 * chip, the theme switch and decorates LuCI's #indicators. Everything here is
 * built from ui.menu (ACL filtered server side) and rpc; the templates stay
 * data-free.
 *
 * DOM rule: LuCI's E()/dom.append() assign a plain string argument to
 * innerHTML, so every piece of text (menu titles, breadcrumbs, palette
 * entries, indicator labels, host chip) is passed inside an array, which
 * dom.append() inserts as text nodes; links are built with L.url() at the
 * point of use. security-tests/check_dom_sinks.js enforces this.
 */

const callBoard = rpc.declare({ object: 'system', method: 'board' });
const callWirelessDevices = rpc.declare({ object: 'luci-rpc', method: 'getWirelessDevices' });

const THEME_KEY = 'vantage.theme';
const RAIL_KEY = 'vantage.rail';

/* 24px stroke icons, drawn for this theme: constant [tag, attributes] lists,
   built with createElementNS (no markup parsing, no user data) */
const ICONS = {
	dashboard: [ [ 'rect', { x: '3.5', y: '3.5', width: '7', height: '9', rx: '1.5' } ], [ 'rect', { x: '13.5', y: '3.5', width: '7', height: '5', rx: '1.5' } ], [ 'rect', { x: '13.5', y: '11.5', width: '7', height: '9', rx: '1.5' } ], [ 'rect', { x: '3.5', y: '15.5', width: '7', height: '5', rx: '1.5' } ] ],
	status: [ [ 'path', { d: 'M3 12h3.5l2.5-6.5 5 13 2.5-6.5H21' } ] ],
	system: [ [ 'rect', { x: '5.5', y: '5.5', width: '13', height: '13', rx: '2' } ], [ 'rect', { x: '9.5', y: '9.5', width: '5', height: '5', rx: '.8' } ], [ 'path', { d: 'M9.5 2.5v3M14.5 2.5v3M9.5 18.5v3M14.5 18.5v3M2.5 9.5h3M2.5 14.5h3M18.5 9.5h3M18.5 14.5h3' } ] ],
	network: [ [ 'rect', { x: '9', y: '3', width: '6', height: '5', rx: '1' } ], [ 'rect', { x: '3', y: '16', width: '6', height: '5', rx: '1' } ], [ 'rect', { x: '15', y: '16', width: '6', height: '5', rx: '1' } ], [ 'path', { d: 'M12 8v4M6 16v-2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v2' } ] ],
	services: [ [ 'rect', { x: '4', y: '4', width: '7', height: '7', rx: '1.5' } ], [ 'rect', { x: '13', y: '4', width: '7', height: '7', rx: '1.5' } ], [ 'rect', { x: '4', y: '13', width: '7', height: '7', rx: '1.5' } ], [ 'path', { d: 'M16.5 13v7M13 16.5h7' } ] ],
	vpn: [ [ 'path', { d: 'M12 3 5 6v5c0 4.5 3 8.2 7 10 4-1.8 7-5.5 7-10V6z' } ], [ 'path', { d: 'm9 12 2 2 4-4' } ] ],
	statistics: [ [ 'path', { d: 'M5 20v-8M10 20V5M15 20v-5M20 20V9M3 20.5h18' } ] ],
	storage: [ [ 'ellipse', { cx: '12', cy: '6', rx: '7', ry: '2.5' } ], [ 'path', { d: 'M5 6v12c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5V6M5 12c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5' } ] ],
	generic: [ [ 'circle', { cx: '12', cy: '12', r: '8' } ], [ 'circle', { cx: '12', cy: '12', r: '2.2' } ] ],
	page: [ [ 'path', { d: 'M7 3.5h6.5l4.5 4.5v12.5H7z' } ], [ 'path', { d: 'M13.5 3.5V8H18' } ] ],
	caret: [ [ 'path', { d: 'm9 6 6 6-6 6' } ] ],
	enter: [ [ 'path', { d: 'M19 5v6a3 3 0 0 1-3 3H6M10 10l-4 4 4 4' } ] ],
	search: [ [ 'circle', { cx: '11', cy: '11', r: '6.5' } ], [ 'path', { d: 'm16 16 4.5 4.5' } ] ],
	sun: [ [ 'circle', { cx: '12', cy: '12', r: '4' } ], [ 'path', { d: 'M12 2.5v2M12 19.5v2M4.6 4.6 6 6M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4' } ] ],
	moon: [ [ 'path', { d: 'M19.5 14.5A7.5 7.5 0 0 1 9.5 4.5a7.5 7.5 0 1 0 10 10z' } ] ],
	auto: [ [ 'circle', { cx: '12', cy: '12', r: '8' } ], [ 'path', { d: 'M12 4a8 8 0 0 1 0 16z', 'class': 'vt-fill' } ] ],
	logout: [ [ 'path', { d: 'M14 4h4.5A1.5 1.5 0 0 1 20 5.5v13a1.5 1.5 0 0 1-1.5 1.5H14' } ], [ 'path', { d: 'M10 8l-4 4 4 4M6 12h10' } ] ],
	pin: [ [ 'path', { d: 'M4 5v14M9 12h11M15 7l5 5-5 5' } ] ]
};

function iconFor(name) {
	if (/overview|dashboard|home/.test(name)) return 'dashboard';
	if (/^(status|system|network|services|vpn|statistics)$/.test(name)) return name;
	if (/nas|storage|disk/.test(name)) return 'storage';
	return 'generic';
}

const SVGNS = 'http://www.w3.org/2000/svg';

/* SVG elements from constant descriptions (ICONS, chart defs, chart
   shapes). Tags and attribute names are closed sets written as literals:
   anything else throws, so no caller can create script, a, foreignObject
   or animation elements or set href, style or on* through this helper. */
function svgNode(tag) {
	switch (tag) {
	case 'svg': return document.createElementNS(SVGNS, 'svg');
	case 'path': return document.createElementNS(SVGNS, 'path');
	case 'rect': return document.createElementNS(SVGNS, 'rect');
	case 'circle': return document.createElementNS(SVGNS, 'circle');
	case 'ellipse': return document.createElementNS(SVGNS, 'ellipse');
	case 'defs': return document.createElementNS(SVGNS, 'defs');
	case 'linearGradient': return document.createElementNS(SVGNS, 'linearGradient');
	case 'stop': return document.createElementNS(SVGNS, 'stop');
	}
	throw new Error('svgEl: tag not allowed: ' + tag);
}

function svgAttr(el, k, v) {
	v = String(v);
	switch (k) {
	case 'viewBox': el.setAttribute('viewBox', v); break;
	case 'width': el.setAttribute('width', v); break;
	case 'height': el.setAttribute('height', v); break;
	case 'aria-hidden': el.setAttribute('aria-hidden', v); break;
	case 'focusable': el.setAttribute('focusable', v); break;
	case 'class': el.setAttribute('class', v); break;
	case 'id': el.setAttribute('id', v); break;
	case 'd': el.setAttribute('d', v); break;
	case 'x': el.setAttribute('x', v); break;
	case 'y': el.setAttribute('y', v); break;
	case 'rx': el.setAttribute('rx', v); break;
	case 'ry': el.setAttribute('ry', v); break;
	case 'cx': el.setAttribute('cx', v); break;
	case 'cy': el.setAttribute('cy', v); break;
	case 'r': el.setAttribute('r', v); break;
	case 'x1': el.setAttribute('x1', v); break;
	case 'y1': el.setAttribute('y1', v); break;
	case 'x2': el.setAttribute('x2', v); break;
	case 'y2': el.setAttribute('y2', v); break;
	case 'offset': el.setAttribute('offset', v); break;
	default: throw new Error('svgEl: attribute not allowed: ' + k);
	}
}

function svgEl(tag, attrs) {
	const el = svgNode(tag);
	for (const k of Object.keys(attrs || {})) svgAttr(el, k, attrs[k]);
	return el;
}

function svg(name, size) {
	const s = svgEl('svg', {
		'viewBox': '0 0 24 24', 'width': size || 20, 'height': size || 20, 'aria-hidden': 'true', 'focusable': 'false'
	});
	(ICONS[name] || ICONS.generic).forEach(part => s.appendChild(svgEl(part[0], part[1])));
	return s;
}

function storageGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
function storageSet(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) {} }

function isTyping(el) {
	if (!el) return false;
	const tag = el.tagName;
	return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || el.isContentEditable ||
		!!(el.closest && el.closest('.cbi-dropdown[open]'));
}

/* subsequence match with bonuses for word starts and runs; null = no match */
function fuzzy(query, text) {
	const q = query.toLowerCase().replace(/\s+/g, '');
	const t = text.toLowerCase();
	if (!q) return { score: 0, idx: [] };
	let score = 0, from = 0, prev = -2;
	const idx = [];
	for (const ch of q) {
		const at = t.indexOf(ch, from);
		if (at < 0) return null;
		let s = 1;
		if (at === prev + 1) s += 5;
		if (at === 0 || /[\s\/›\-_(.]/.test(t[at - 1])) s += 7;
		s -= Math.min(at - from, 6) * .25;
		score += s;
		idx.push(at);
		prev = at;
		from = at + 1;
	}
	const plain = query.toLowerCase().trim();
	if (t.startsWith(plain)) score += 14;
	else if (t.indexOf(plain) >= 0) score += 8;
	return { score: score - t.length * .02, idx };
}

function highlight(text, idx) {
	const out = E('span', { 'class': 'vt-pal-title' });
	const set = new Set(idx);
	let run = '';
	let marked = false;
	const flush = () => {
		if (!run) return;
		out.appendChild(marked ? E('mark', {}, [ run ]) : document.createTextNode(run));
		run = '';
	};
	for (let i = 0; i < text.length; i++) {
		const m = set.has(i);
		if (m !== marked) { flush(); marked = m; }
		run += text[i];
	}
	flush();
	return out;
}

/* cells holding only addresses, counters, rates or durations get the mono stack */
const UNITS = /(?<![A-Za-z])(?:[kKMGTP]?i?B(?:\/s)?|[kMG]?bit\/s|[kMG]?bps|dBm|dB|[kMG]?Hz|ms|us|MCS|NSS|EHT|HE|VHT|HT|pkts?|packets|bytes|min|d|h|m|s)(?![A-Za-z])/g;
function technical(text) {
	const t = text.trim();
	if (!t || t.length > 120 || !/\d/.test(t)) return false;
	const rest = t.replace(UNITS, '');
	return /\d/.test(rest) && /^[\s0-9a-fA-F.:,\/%()+\-x[\]~=]*$/.test(rest);
}

/* ---------------------------------------------------------------------------
 * Stock-page enhancers, only where CSS cannot restructure LuCI's markup
 * (Status -> Overview: fused memory bar, per-mount storage bars, radio band
 * chips). Rules:
 *  - DOM is built with E() and array content (text nodes), never HTML;
 *  - LuCI's own nodes stay in the DOM (hidden by class) so its code keeps
 *    working; nothing of LuCI's is moved or removed;
 *  - idempotent: the status includes re-render their container on every
 *    poll (dom.content), the observer rebuilds from the fresh nodes before
 *    the next paint, and a pass that finds nothing to do mutates nothing.
 * ------------------------------------------------------------------------ */

const BYTE_UNITS = { '': 1, K: 1024, M: 1048576, G: 1073741824, T: 1099511627776, P: 1125899906842624 };

function parseBytes(s) {
	const m = /(-?\d+(?:\.\d+)?)\s*([KMGTP]?)i?B\b/.exec(s || '');
	return m ? parseFloat(m[1]) * BYTE_UNITS[m[2]] : null;
}

/* progressbar title "534.50 MiB / 856.19 MiB (62%)" -> { value, total } */
function parseBarTitle(title) {
	const parts = String(title || '').split(' / ');
	if (parts.length < 2) return null;
	const value = parseBytes(parts[0]), total = parseBytes(parts[1]);
	return (value != null && total != null && total > 0) ? { value, total } : null;
}

function fmtBytes(n) { return String.format('%1024.1mB', Math.max(0, n)); }
function pctOf(n, total) { return total > 0 ? Math.round(100 * n / total) : 0; }

/* the Overview .cbi-section whose title (text before the Hide/Show label) is `title` */
function statusSections(title) {
	return Array.prototype.filter.call(document.querySelectorAll('#view .cbi-section > .cbi-title > h3'), hd => {
		const t = hd.firstChild;
		return t && t.nodeType === 3 && t.data.trim() === title;
	}).map(hd => hd.parentNode.parentNode);
}

/* the include's freshly rendered table, if it has not been enhanced yet */
function pendingTable(section) {
	const box = section.children[1];
	const table = box && box.querySelector(':scope > table.table');
	return (table && !table.hasAttribute('data-v-done')) ? table : null;
}

function barRows(table) {
	return Array.prototype.map.call(table.querySelectorAll(':scope > tr, :scope > tbody > tr'), tr => {
		const bar = tr.querySelector('.cbi-progressbar');
		return { label: (tr.firstElementChild ? tr.firstElementChild.textContent : '').trim(),
		         pair: bar ? parseBarTitle(bar.getAttribute('title')) : null };
	});
}

function segment(cls, value, total, title) {
	const s = E('span', { 'class': 'v-seg ' + cls, 'title': title });
	s.style.width = (total > 0 ? Math.min(100, 100 * value / total) : 0).toFixed(2) + '%';
	return s;
}

function legendKey(cls, label, value, note) {
	return E('li', {}, [ E('span', { 'class': 'v-key ' + cls }), E('span', {}, [ label ]), E('b', {}, [ fmtBytes(value) ]), note ? E('em', {}, [ note ]) : '' ]);
}

function replaceTable(table, block) {
	table.setAttribute('data-v-done', '1');
	table.classList.add('v-src-hidden');
	const prev = table.previousElementSibling;
	if (prev && prev.classList.contains('v-enhanced')) prev.remove();
	block.classList.add('v-enhanced');
	table.parentNode.insertBefore(block, table);
}

/* Memory: one bar. in use = total - available; cache (reclaimable) =
   available - free; free = total - LuCI's "Used" (which is total - free). */
function enhanceMemory() {
	statusSections(_('Memory')).forEach(section => {
		const table = pendingTable(section);
		if (!table) return;
		const rows = barRows(table), get = l => (rows.find(r => r.label === l) || {}).pair;
		const avail = get(_('Total Available')), used = get(_('Used')),
		      buffered = get(_('Buffered')), cached = get(_('Cached')), swap = get(_('Swap free'));
		const total = (used || avail || {}).total;
		if (!total || !used) return;

		const free = Math.max(0, total - used.value);
		let available = avail ? avail.value : free + (buffered ? buffered.value : 0) + (cached ? cached.value : 0);
		available = Math.min(total, Math.max(available, free));
		const inuse = total - available, reclaim = available - free;
		const usedPct = pctOf(inuse, total);

		const summary = '%s: %s %s, %s %s (%s), %s %s, %s %s'.format(_('Memory'),
			_('In use'), fmtBytes(inuse), _('Cache'), fmtBytes(reclaim), _('reclaimable'),
			_('Free'), fmtBytes(free), _('Total'), fmtBytes(total));

		const children = [
			E('div', { 'class': 'v-meter-head' }, [
				E('span', { 'class': 'v-meter-big' }, [ pctOf(available, total) + '%', E('small', {}, [ _('available') ]) ]),
				E('span', { 'class': 'v-meter-sub' }, [ '%s / %s'.format(fmtBytes(available), fmtBytes(total)) ])
			]),
			E('div', { 'class': 'v-meter-bar', 'role': 'img', 'aria-label': summary }, [
				segment('v-seg-used' + (usedPct >= 90 ? ' is-crit' : usedPct >= 75 ? ' is-warn' : ''), inuse, total, _('In use')),
				segment('v-seg-cache', reclaim, total, _('Cache') + ' (' + _('reclaimable') + ')')
			]),
			E('ul', { 'class': 'v-meter-legend', 'aria-hidden': 'true' }, [
				legendKey('v-seg-used', _('In use'), inuse),
				legendKey('v-seg-cache', _('Cache'), reclaim, _('reclaimable')),
				legendKey('v-seg-free', _('Free'), free)
			])
		];

		if (swap) {
			const swapUsed = swap.total - swap.value;
			children.push(E('div', { 'class': 'v-meter-rows v-meter-swap' }, E('div', { 'class': 'v-meter-row' }, [
				E('span', { 'class': 'v-meter-label' }, [ _('Swap') ]),
				E('div', { 'class': 'v-meter-bar is-thin', 'role': 'img',
				           'aria-label': '%s: %s / %s'.format(_('Swap'), fmtBytes(swapUsed), fmtBytes(swap.total)) },
					segment('v-seg-used', swapUsed, swap.total)),
				E('span', { 'class': 'v-meter-val' }, [ E('b', {}, [ fmtBytes(swapUsed) ]), ' / ' + fmtBytes(swap.total) ])
			])));
		}

		replaceTable(table, E('div', { 'class': 'v-meter v-meter-mem' }, children));
	});
}

/* Storage: one thin bar per mount, "used · free of total" beside it */
function enhanceStorage() {
	statusSections(_('Storage')).forEach(section => {
		const table = pendingTable(section);
		if (!table) return;
		const rows = barRows(table);
		if (!rows.length) return;

		replaceTable(table, E('div', { 'class': 'v-meter-rows v-meter-disk' }, rows.map(r => {
			const m = /^(.*) \((\/.*)\)$/.exec(r.label);
			const label = E('span', { 'class': 'v-meter-label' }, m ? [ m[2], E('small', {}, [ m[1] ]) ] : [ r.label ]);
			if (!r.pair)
				return E('div', { 'class': 'v-meter-row' }, [ label, E('div', { 'class': 'v-meter-bar is-thin' }), E('span', { 'class': 'v-meter-val' }, [ '?' ]) ]);
			const used = r.pair.value, size = r.pair.total, p = pctOf(used, size);
			return E('div', { 'class': 'v-meter-row' }, [
				label,
				E('div', { 'class': 'v-meter-bar is-thin', 'role': 'img',
				           'aria-label': '%s: %s %s, %s %s'.format(r.label, fmtBytes(used), _('used'), fmtBytes(size - used), _('free')) },
					segment('v-seg-used' + (p >= 95 ? ' is-crit' : p >= 80 ? ' is-warn' : ''), used, size)),
				E('span', { 'class': 'v-meter-val' }, [
					E('b', {}, [ fmtBytes(used) ]), ' ' + _('used') + ' · ' + fmtBytes(size - used) + ' ' + _('free') + ' · ' + fmtBytes(size)
				])
			]);
		})));
	});
}

/* Wireless radio boxes: band chip from the "Channel: 6 (2.437 GHz)" line */
function decorateRadios() {
	statusSections(_('Wireless')).forEach(section => {
		section.querySelectorAll('.network-status-table > .ifacebox').forEach(box => {
			const head = box.querySelector(':scope > .ifacebox-head');
			if (!head || head.hasAttribute('data-v-band')) return;
			let band = '';
			box.querySelectorAll('.ifacebox-body > span > .nowrap').forEach(n => {
				const label = n.querySelector('strong');
				const m = label && label.textContent.indexOf(_('Channel')) === 0 && /(\d+(?:\.\d+)?)\s*GHz/.exec(n.textContent);
				if (m) {
					const f = parseFloat(m[1]);
					band = f < 3 ? '2.4 GHz' : f < 5.925 ? '5 GHz' : f < 7.2 ? '6 GHz' : '60 GHz';
				}
			});
			if (band) head.setAttribute('data-v-band', band);
		});
	});
}

function setupStockEnhancers() {
	const view = document.getElementById('view');
	if (!view || !window.MutationObserver) return;
	if (!/^admin(-status(-overview)?)?$/.test(document.body.getAttribute('data-page') || '')) return;
	let busy = false;
	const run = () => {
		if (busy) return;
		busy = true;
		try { enhanceMemory(); enhanceStorage(); decorateRadios(); }
		catch (e) { if (window.console) console.warn('vantage: status enhancer', e); }
		busy = false;
	};
	new MutationObserver(run).observe(view, { childList: true, subtree: true });
	run();
}

/* ---------------------------------------------------------------------------
 * Stock charts: Status -> Realtime Graphs (load, bandwidth, wireless,
 * connections) and Status -> Channel Analysis. Every one of these views
 * fetches its svg/*.svg template and inserts it inline (E(markup)), so
 * vantage.css reaches the chart directly and follows the theme toggle
 * through CSS variables. This code only adds what CSS cannot:
 *  - one hidden <svg><defs> holding the series area gradients the CSS
 *    references (fill: url(#v-grad-N));
 *  - Channel Analysis: a smooth hump (path.v-ca-shape) drawn from each
 *    network's trapezoid polyline (which CSS hides), palette slots per
 *    network, the AP's own BSSIDs marked, crowded channel labels thinned.
 * LuCI's polling, polylines, labels and tables are left as the view draws
 * them; nodes are created with createElementNS and attributes only.
 * ------------------------------------------------------------------------ */

function ensureChartDefs() {
	if (document.getElementById('v-chart-defs')) return;
	const box = svgEl('svg', { 'id': 'v-chart-defs', 'width': '0', 'height': '0', 'aria-hidden': 'true', 'focusable': 'false' });
	const defs = svgEl('defs');
	for (let n = 1; n <= 6; n++) {
		const g = svgEl('linearGradient', { 'id': 'v-grad-' + n, 'class': 'v-grad v-grad-' + n, 'x1': '0', 'y1': '0', 'x2': '0', 'y2': '1' });
		g.appendChild(svgEl('stop', { 'offset': '0', 'class': 'v-stop-top' }));
		g.appendChild(svgEl('stop', { 'offset': '1', 'class': 'v-stop-bottom' }));
		defs.appendChild(g);
	}
	box.appendChild(defs);
	document.body.appendChild(box);
}

/* "x0,h,x1,y,x2,y,x3,h" (the view sets an array, so commas throughout) ->
   a symmetric hump through the same feet and peak height */
function humpPath(points) {
	const n = String(points || '').split(/[\s,]+/).filter(Boolean).map(Number);
	if (n.length < 8 || n.some(v => !isFinite(v))) return null;
	const x0 = n[0], base = n[1], peak = n[3], x3 = n[n.length - 2];
	if (!(x3 > x0)) return null;
	const k = (x3 - x0) * .16;
	const cy = (4 * peak - base) / 3;           /* cubic midpoint lands on the peak */
	const r = v => Math.round(v * 10) / 10;
	return 'M' + r(x0) + ',' + r(base) + 'C' + r(x0 + k) + ',' + r(cy) + ' ' + r(x3 - k) + ',' + r(cy) + ' ' + r(x3) + ',' + r(base) + 'Z';
}

function setupChannelAnalysis() {
	const view = document.getElementById('view');
	const own = new Set();
	const slots = new Map();
	let next = 0;
	/* slot 1 (the accent) is the AP itself; neighbours take 2..6 in the order
	   they first appear (the view sorts by channel, so neighbours differ) */
	const slotFor = (colour, mine) => {
		if (mine) return 1;
		if (!slots.has(colour)) slots.set(colour, 2 + (next++ % 5));
		return slots.get(colour);
	};

	/* write an attribute only when its value changes (null removes it);
	   the names are a closed set, each written with a literal name */
	const setAttr = (el, k, v) => {
		if (v == null) { if (el.hasAttribute(k)) el.removeAttribute(k); return; }
		v = String(v);
		if (el.getAttribute(k) === v) return;
		switch (k) {
		case 'd': el.setAttribute('d', v); break;
		case 'data-v-band': el.setAttribute('data-v-band', v); break;
		case 'data-v-series': el.setAttribute('data-v-series', v); break;
		case 'data-v-own': el.setAttribute('data-v-own', v); break;
		}
	};

	const run = () => {
		view.querySelectorAll('div[id="channel_graph"]').forEach(hostEl => {
			const svg = hostEl.querySelector(':scope > svg');
			const tab = hostEl.closest('[data-tab]') || hostEl.parentNode;
			if (!svg || !tab) return;
			/* data-tab is ifname + band ("radio02", "radio16") */
			const band = /[256]$/.exec(tab.getAttribute('data-tab') || '');
			setAttr(hostEl, 'data-v-band', band ? band[0] : null);

			/* table rows: colour dot -> BSSID. A row is ours only when its
			   BSSID is one of this device's: the SSID cell is whatever a
			   neighbour broadcasts, "Local Interface" included. Until the
			   BSSIDs are known nothing is marked (the stock look). */
			const mineByColour = new Map();
			tab.querySelectorAll('tr').forEach(tr => {
				const dot = tr.querySelector('span[style*="color"]');
				const cells = tr.querySelectorAll(':scope > td, :scope > .td');
				if (!cells.length) return;
				const bssid = cells[cells.length - 1].textContent.trim().toUpperCase();
				const mine = own.has(bssid);
				if (tr.classList.contains('v-ca-own') !== mine) tr.classList.toggle('v-ca-own', mine);
				if (!dot) return;
				const colour = dot.style.color;
				if (mine) mineByColour.set(colour, true);
				setAttr(dot, 'data-v-series', slotFor(colour, mine));
			});

			svg.querySelectorAll(':scope > g').forEach(g => {
				const poly = g.querySelector(':scope > polyline');
				const label = g.querySelector(':scope > text');
				if (!poly) return;
				const colour = poly.style.stroke;
				/* LuCI derives each network's colour from its BSSID */
				const mine = mineByColour.has(colour);
				const slot = slotFor(colour, mine);
				let shape = g.querySelector(':scope > path.v-ca-shape');
				if (!shape) {
					shape = svgEl('path', { 'class': 'v-ca-shape' });
					g.insertBefore(shape, g.firstChild);
				}
				const d = humpPath(poly.getAttribute('points'));
				if (d) setAttr(shape, 'd', d);
				setAttr(shape, 'data-v-series', slot);
				setAttr(shape, 'data-v-own', mine ? '1' : null);
				if (label) {
					if (!label.classList.contains('v-ca-label')) label.classList.add('v-ca-label');
					setAttr(label, 'data-v-own', mine ? '1' : null);
				}
			});

			if (hostEl.offsetParent) {
				/* SSID labels: stronger (higher) first; a colliding weaker one
				   moves down below it (transform only; the view owns x/y) */
				const placed = [];
				const right = hostEl.clientWidth - 4;
				Array.prototype.map.call(svg.querySelectorAll(':scope > g > text.v-ca-label'), t => {
					if (t.hasAttribute('transform')) t.removeAttribute('transform');
					const b = t.getBBox();
					const dx = Math.min(0, right - (b.x + b.width));   /* keep it inside the plot */
					return { t, x: b.x + dx, dx, y: b.y, w: b.width, h: b.height };
				}).filter(l => l.w > 0).sort((a, b) => a.y - b.y || a.x - b.x).forEach(l => {
					let dy = 0;
					for (let guard = 0; guard < 8; guard++) {
						const hit = placed.find(p => l.x < p.x + p.w + 4 && p.x < l.x + l.w + 4 && l.y + dy < p.y + p.h + 1 && p.y < l.y + dy + l.h + 1);
						if (!hit) break;
						dy = hit.y + hit.h + 1 - l.y;
					}
					if (dy || l.dx) l.t.setAttribute('transform', 'translate(' + Math.round(l.dx) + ' ' + Math.round(dy) + ')');
					placed.push({ x: l.x, y: l.y + dy, w: l.w, h: l.h });
				});

				/* channel numbers: drop labels that would collide (6 GHz has ~60) */
				const ticks = Array.prototype.filter.call(svg.children, el => el.tagName === 'text' && !el.id)
					.map(t => ({ t, x: parseFloat(t.getAttribute('x')) || 0 })).sort((a, b) => a.x - b.x);
				let end = -Infinity;
				ticks.forEach(({ t, x }) => {
					const w = t.getComputedTextLength ? t.getComputedTextLength() : 0;
					const hide = x < end + 8;
					if (t.classList.contains('v-ca-hide') !== hide) t.classList.toggle('v-ca-hide', hide);
					if (!hide) end = x + w;
				});
			}
		});
	};

	let busy = false;
	const safeRun = () => {
		if (busy) return;
		busy = true;
		try { run(); }
		catch (e) { if (window.console) console.warn('vantage: channel analysis', e); }
		busy = false;
	};

	L.resolveDefault(callWirelessDevices(), {}).then(devs => {
		for (const r of Object.values(devs || {}))
			for (const i of (r && Array.isArray(r.interfaces)) ? r.interfaces : [])
				[ i.iwinfo && i.iwinfo.bssid, i.config && i.config.macaddr ].forEach(b => {
					if (typeof b === 'string' && b) own.add(b.toUpperCase());
				});
		safeRun();
	});
	new MutationObserver(safeRun).observe(view, { childList: true, subtree: true, attributes: true, attributeFilter: [ 'points', 'data-tab-active' ] });
	safeRun();
}

function setupCharts() {
	const page = document.body.getAttribute('data-page') || '';
	if (!/^admin-status-(realtime|channel_analysis)/.test(page) || !document.getElementById('view')) return;
	ensureChartDefs();
	if (/^admin-status-channel_analysis/.test(page) && window.MutationObserver) setupChannelAnalysis();
}

return baseclass.extend({
	__init__() {
		this.root = document.documentElement;
		this.mqMobile = window.matchMedia('(max-width: 720px)');
		this.mqNarrow = window.matchMedia('(max-width: 900px)');
		this.closeTimer = null;
		this.openTimer = null;
		this.entries = [];

		this.setupTheme();
		this.setupIndicators();
		this.setupNumerals();
		setupStockEnhancers();
		setupCharts();
		this.setupKeys();
		this.loadHost();

		ui.menu.load().then(L.bind(this.render, this));
	},

	/* ---------------------------------------------------------- menu */

	render(tree) {
		const admin = tree && tree.children && tree.children.admin;
		if (!admin) return;

		this.admin = admin;
		this.dp = (L.env.dispatchpath || []).slice();

		this.cats = ui.menu.getChildren(admin)
			.filter(c => c.name !== 'logout')
			.map(c => {
				const raw = admin.children[c.name];
				const pages = ui.menu.getChildren(c).map(p => {
					const rawPage = raw && raw.children && raw.children[p.name];
					return {
						name: p.name,
						title: _(p.title),
						subs: rawPage ? ui.menu.getChildren(rawPage).map(s => ({ name: s.name, title: _(s.title) })) : []
					};
				});
				return {
					name: c.name,
					title: _(c.title),
					icon: iconFor(c.name),
					leaf: !(c.action && c.action.type === 'firstchild'),
					pages
				};
			})
			.filter(c => c.leaf || c.pages.length);

		this.renderRail();
		this.renderCrumbs();
		this.renderTabs();
		this.buildIndex();
	},

	isPinned() {
		return this.root.getAttribute('data-rail') === 'pinned' && !this.mqNarrow.matches;
	},

	renderRail() {
		const list = document.getElementById('vt-rail-list');
		const fly = document.getElementById('vt-flyout');
		if (!list || !fly) return;

		this.fly = fly;
		this.scrim = document.getElementById('vt-scrim');
		list.textContent = '';

		for (const cat of this.cats) {
			const active = this.dp[1] === cat.name;
			const li = E('li', { 'class': 'vt-rail-item' + (active ? ' is-active is-expanded' : ''), 'data-cat': cat.name });
			let link;

			if (cat.leaf) {
				link = E('a', { 'class': 'vt-rail-link', 'href': L.url('admin', cat.name), 'aria-current': active ? 'page' : null, 'title': cat.title }, [
					svg(cat.icon), E('span', { 'class': 'vt-rail-label' }, [ cat.title ])
				]);
			}
			else {
				link = E('button', {
					'type': 'button', 'class': 'vt-rail-link', 'aria-expanded': 'false', 'aria-controls': 'vt-flyout',
					'aria-current': active ? 'true' : null, 'title': cat.title
				}, [ svg(cat.icon), E('span', { 'class': 'vt-rail-label' }, [ cat.title ]), svg('caret', 14) ]);
				link.lastChild.setAttribute('class', 'vt-rail-caret');

				link.addEventListener('click', ev => this.handleRailClick(ev, cat, li, link));
				li.addEventListener('pointerenter', ev => {
					if (ev.pointerType !== 'mouse' || this.isPinned() || this.mqMobile.matches) return;
					this.cancelClose();
					window.clearTimeout(this.openTimer);
					this.openTimer = window.setTimeout(() => this.openFlyout(cat, li, link, false), this.fly.hidden ? 90 : 0);
				});
				li.addEventListener('pointerleave', ev => {
					if (ev.pointerType !== 'mouse') return;
					window.clearTimeout(this.openTimer);
					this.scheduleClose();
				});

				/* pinned rail: inline pages */
				const sub = E('ul', { 'class': 'vt-rail-sub' });
				for (const p of cat.pages) {
					const cur = this.dp[1] === cat.name && this.dp[2] === p.name;
					sub.appendChild(E('li', {}, E('a', { 'href': L.url('admin', cat.name, p.name), 'aria-current': cur ? 'page' : null }, [ p.title ])));
				}
				li.appendChild(link);
				li.appendChild(sub);
				list.appendChild(li);
				continue;
			}

			li.appendChild(link);
			list.appendChild(li);
		}

		list.addEventListener('keydown', ev => this.handleRailKeys(ev, list));

		fly.addEventListener('pointerenter', () => this.cancelClose());
		fly.addEventListener('pointerleave', ev => { if (ev.pointerType === 'mouse') this.scheduleClose(); });
		fly.addEventListener('keydown', ev => this.handleFlyKeys(ev));
		if (this.scrim) this.scrim.addEventListener('click', () => this.closeFlyout(false));

		document.addEventListener('click', ev => {
			if (fly.hidden) return;
			if (ev.target.closest('#vt-flyout') || ev.target.closest('#vt-rail')) return;
			this.closeFlyout(false);
		});

		const pin = document.getElementById('vt-rail-pin');
		if (pin) {
			const sync = () => {
				const pinned = this.root.getAttribute('data-rail') === 'pinned';
				pin.setAttribute('aria-pressed', pinned ? 'true' : 'false');
				const label = pinned ? _('Collapse navigation') : _('Expand navigation');
				pin.setAttribute('aria-label', label);
				pin.setAttribute('title', label);
			};
			pin.addEventListener('click', () => {
				const pinned = this.root.getAttribute('data-rail') === 'pinned';
				if (pinned) this.root.removeAttribute('data-rail');
				else this.root.setAttribute('data-rail', 'pinned');
				storageSet(RAIL_KEY, pinned ? null : 'pinned');
				this.closeFlyout(false);
				sync();
			});
			sync();
		}
	},

	handleRailClick(ev, cat, li, link) {
		if (this.isPinned()) {
			li.classList.toggle('is-expanded');
			link.setAttribute('aria-expanded', li.classList.contains('is-expanded') ? 'true' : 'false');
			return;
		}
		if (!this.fly.hidden && this.fly.getAttribute('data-cat') === cat.name && ev.detail !== 0 && !this.mqMobile.matches && ev.pointerType !== 'touch') {
			/* mouse click on an already hovered category: keep it open */
			return;
		}
		if (!this.fly.hidden && this.fly.getAttribute('data-cat') === cat.name) {
			this.closeFlyout(true);
			return;
		}
		this.openFlyout(cat, li, link, ev.detail === 0);
	},

	handleRailKeys(ev, list) {
		const links = Array.prototype.slice.call(list.querySelectorAll('.vt-rail-link'));
		const i = links.indexOf(document.activeElement);
		if (i < 0) return;
		const vertical = !this.mqMobile.matches;
		const next = vertical ? 'ArrowDown' : 'ArrowRight';
		const prev = vertical ? 'ArrowUp' : 'ArrowLeft';
		if (ev.key === next || ev.key === prev) {
			ev.preventDefault();
			links[(i + (ev.key === next ? 1 : links.length - 1)) % links.length].focus();
		}
		else if (ev.key === 'Home' || ev.key === 'End') {
			ev.preventDefault();
			links[ev.key === 'Home' ? 0 : links.length - 1].focus();
		}
		else if (vertical && ev.key === 'ArrowRight' && links[i].tagName === 'BUTTON' && !this.isPinned()) {
			ev.preventDefault();
			links[i].click();
		}
		else if (ev.key === 'Escape' && !this.fly.hidden) {
			ev.preventDefault();
			this.closeFlyout(true);
		}
	},

	handleFlyKeys(ev) {
		const links = Array.prototype.slice.call(this.fly.querySelectorAll('a'));
		const i = links.indexOf(document.activeElement);
		if (ev.key === 'Escape' || (ev.key === 'ArrowLeft' && !this.mqMobile.matches)) {
			ev.preventDefault();
			this.closeFlyout(true);
		}
		else if ((ev.key === 'ArrowDown' || ev.key === 'ArrowUp') && links.length) {
			ev.preventDefault();
			const d = ev.key === 'ArrowDown' ? 1 : -1;
			links[(i + d + links.length) % links.length].focus();
		}
		else if (ev.key === 'Tab' && links.length) {
			/* leaving the panel returns to the rail */
			const edge = ev.shiftKey ? 0 : links.length - 1;
			if (i === edge) { ev.preventDefault(); this.closeFlyout(true); }
		}
	},

	openFlyout(cat, li, link, focusFirst) {
		const fly = this.fly;
		this.cancelClose();
		if (fly.getAttribute('data-cat') !== cat.name || fly.hidden) {
			fly.textContent = '';
			const total = cat.pages.length;
			fly.appendChild(E('div', { 'class': 'vt-fly-head' }, [
				svg(cat.icon, 18),
				E('span', { 'class': 'vt-fly-title', 'id': 'vt-fly-title' }, [ cat.title ]),
				E('span', { 'class': 'vt-fly-count' }, [ '%d %s'.format(total, total === 1 ? _('page') : _('pages')) ])
			]));
			const ul = E('ul', { 'class': 'vt-fly-list', 'role': 'list' });
			for (const p of cat.pages) {
				const cur = this.dp[1] === cat.name && this.dp[2] === p.name;
				const item = E('li', {}, E('a', { 'class': 'vt-fly-link', 'href': L.url('admin', cat.name, p.name), 'aria-current': cur ? 'page' : null }, [
					E('span', {}, [ p.title ]),
					p.subs.length ? E('span', { 'class': 'vt-fly-meta' }, [ String(p.subs.length) ]) : ''
				]));
				if (p.subs.length > 1) {
					const sub = E('ul', { 'class': 'vt-fly-sub' });
					for (const s of p.subs) {
						const scur = cur && this.dp[3] === s.name;
						sub.appendChild(E('li', {}, E('a', { 'href': L.url('admin', cat.name, p.name, s.name), 'aria-current': scur ? 'page' : null }, [ s.title ])));
					}
					item.appendChild(sub);
				}
				ul.appendChild(item);
			}
			fly.appendChild(ul);
			fly.appendChild(E('div', { 'class': 'vt-fly-foot' }, [ _('Press'), ' ', E('kbd', {}, [ 'Ctrl K' ]), ' ', _('to search all pages') ]));
			fly.setAttribute('data-cat', cat.name);
			fly.setAttribute('role', 'region');
			fly.setAttribute('aria-labelledby', 'vt-fly-title');
		}

		document.querySelectorAll('.vt-rail-item.is-open').forEach(n => {
			if (n === li) return;
			n.classList.remove('is-open');
			const b = n.querySelector('.vt-rail-link[aria-expanded]');
			if (b) b.setAttribute('aria-expanded', 'false');
		});
		li.classList.add('is-open');
		link.setAttribute('aria-expanded', 'true');
		this.openLink = link;
		fly.hidden = false;
		if (this.scrim) this.scrim.hidden = !this.mqMobile.matches;

		if (focusFirst) {
			const first = fly.querySelector('a[aria-current]') || fly.querySelector('a');
			if (first) first.focus();
		}
	},

	closeFlyout(refocus) {
		if (!this.fly || this.fly.hidden) return;
		this.cancelClose();
		this.fly.hidden = true;
		if (this.scrim) this.scrim.hidden = true;
		document.querySelectorAll('.vt-rail-item.is-open').forEach(n => {
			n.classList.remove('is-open');
			const b = n.querySelector('.vt-rail-link[aria-expanded]');
			if (b) b.setAttribute('aria-expanded', 'false');
		});
		if (refocus && this.openLink) this.openLink.focus();
	},

	scheduleClose() {
		this.cancelClose();
		this.closeTimer = window.setTimeout(() => this.closeFlyout(false), 220);
	},

	cancelClose() {
		if (this.closeTimer) window.clearTimeout(this.closeTimer);
		this.closeTimer = null;
	},

	/* ------------------------------------------------- crumbs + tabs */

	renderCrumbs() {
		const nav = document.getElementById('vt-crumbs');
		if (!nav) return;
		const parts = [];
		let node = this.admin;
		for (let i = 1; i < this.dp.length && i <= 3; i++) {
			node = node && node.children ? node.children[this.dp[i]] : null;
			if (!node || !node.title) break;
			parts.push({ title: _(node.title), segs: [ 'admin' ].concat(this.dp.slice(1, i + 1)) });
		}
		if (!parts.length) return;

		nav.textContent = '';
		parts.forEach((p, i) => {
			const last = i === parts.length - 1;
			if (i) nav.appendChild(E('span', { 'class': 'vt-crumb-sep', 'aria-hidden': 'true' }, [ '›' ]));
			nav.appendChild(last
				? E('span', { 'class': 'vt-crumb vt-crumb-current', 'aria-current': 'page' }, [ p.title ])
				: E('a', { 'class': 'vt-crumb', 'href': L.url.apply(L, p.segs) }, [ p.title ]));
		});

		this.pageTitle = parts[parts.length - 1].title;
		this.updateTitle();
	},

	renderTabs() {
		const bar = document.getElementById('vt-tabs');
		if (!bar || this.dp.length < 3) return;
		const cat = this.admin.children[this.dp[1]];
		const page = cat && cat.children ? cat.children[this.dp[2]] : null;
		if (!page) return;
		const tabs = ui.menu.getChildren(page);
		if (tabs.length < 2) return;

		bar.textContent = '';
		for (const t of tabs) {
			const cur = this.dp[3] === t.name;
			bar.appendChild(E('a', {
				'class': 'vt-tab', 'href': L.url('admin', this.dp[1], this.dp[2], t.name), 'aria-current': cur ? 'page' : null
			}, [ _(t.title) ]));
		}
		bar.hidden = false;
		const active = bar.querySelector('[aria-current]');
		if (active && active.scrollIntoView && bar.scrollWidth > bar.clientWidth)
			bar.scrollLeft = active.offsetLeft - 16;
	},

	/* ------------------------------------------------------ palette */

	buildIndex() {
		const seen = new Set();
		const add = e => {
			const key = e.segs.join('/') + '|' + e.title;
			if (seen.has(key)) return;
			seen.add(key);
			e.hay = (e.path ? e.path + ' › ' : '') + e.title;
			this.entries.push(e);
		};
		for (const c of this.cats) {
			if (c.leaf) add({ title: c.title, path: '', group: c.title, segs: [ 'admin', c.name ], icon: c.icon });
			for (const p of c.pages) {
				add({ title: p.title, path: c.title, group: c.title, segs: [ 'admin', c.name, p.name ], icon: c.icon });
				if (p.subs.length > 1)
					for (const s of p.subs)
						add({ title: s.title, path: c.title + ' › ' + p.title, group: c.title, segs: [ 'admin', c.name, p.name, s.name ], icon: 'page' });
			}
		}
	},

	actions() {
		const pref = this.themePref();
		const list = [];
		if (pref !== 'dark') list.push({ title: _('Use dark theme'), path: _('Appearance'), icon: 'moon', run: () => this.setTheme('dark') });
		if (pref !== 'light') list.push({ title: _('Use light theme'), path: _('Appearance'), icon: 'sun', run: () => this.setTheme('light') });
		if (pref !== 'auto') list.push({ title: _('Follow system theme'), path: _('Appearance'), icon: 'auto', run: () => this.setTheme('auto') });
		list.push({ title: _('Log out'), path: _('Session'), icon: 'logout', segs: [ 'admin', 'logout' ] });
		list.forEach(a => { a.hay = a.path + ' › ' + a.title; a.group = _('Actions'); });
		return list;
	},

	openPalette() {
		if (this.pal) return;
		this.closeFlyout(false);
		this.palReturn = document.activeElement;

		const input = E('input', {
			'class': 'vt-pal-input', 'type': 'text', 'role': 'combobox', 'aria-expanded': 'true',
			'aria-controls': 'vt-pal-list', 'aria-autocomplete': 'list', 'autocomplete': 'off', 'spellcheck': 'false',
			'placeholder': _('Jump to a page or action…'), 'aria-label': _('Search pages')
		});
		const list = E('ul', { 'class': 'vt-pal-list', 'id': 'vt-pal-list', 'role': 'listbox', 'aria-label': _('Results') });
		const count = E('span', { 'class': 'vt-pal-count' });
		const box = E('div', { 'class': 'vt-pal', 'role': 'dialog', 'aria-modal': 'true', 'aria-label': _('Command palette') }, [
			E('div', { 'class': 'vt-pal-field' }, [ svg('search', 18), input, E('kbd', {}, [ 'Esc' ]) ]),
			list,
			E('div', { 'class': 'vt-pal-foot' }, [
				E('span', {}, [ E('kbd', {}, [ '↑' ]), E('kbd', {}, [ '↓' ]), _('navigate') ]),
				E('span', {}, [ E('kbd', {}, [ '↵' ]), _('open') ]),
				E('span', {}, [ E('kbd', {}, [ 'Esc' ]), _('close') ]),
				count
			])
		]);
		const overlay = E('div', { 'class': 'vt-pal-overlay' }, box);
		overlay.addEventListener('mousedown', ev => { if (ev.target === overlay) this.closePalette(); });

		this.pal = { overlay, input, list, count, items: [], active: 0 };
		input.addEventListener('input', () => this.filterPalette());
		input.addEventListener('keydown', ev => this.handlePaletteKeys(ev));

		document.body.appendChild(overlay);
		this.filterPalette();
		input.focus();
	},

	closePalette() {
		if (!this.pal) return;
		this.pal.overlay.remove();
		this.pal = null;
		if (this.palReturn && this.palReturn.focus) this.palReturn.focus();
	},

	filterPalette() {
		const pal = this.pal;
		const q = pal.input.value.trim();
		const pool = this.entries.concat(this.actions());
		let results;

		if (!q) {
			results = pool.map(e => ({ e, idx: [] }));
		}
		else {
			results = [];
			for (const e of pool) {
				const onTitle = fuzzy(q, e.title);
				const onPath = onTitle ? null : fuzzy(q, e.hay);
				if (onTitle) results.push({ e, score: onTitle.score + 6, idx: onTitle.idx });
				else if (onPath) results.push({ e, score: onPath.score * .6, idx: [] });
			}
			results.sort((a, b) => b.score - a.score);
			results = results.slice(0, 40);
		}

		pal.list.textContent = '';
		pal.items = [];
		let group = null;
		results.forEach((r, n) => {
			if (!q && r.e.group !== group) {
				group = r.e.group;
				pal.list.appendChild(E('li', { 'class': 'vt-pal-group', 'role': 'presentation' }, [ group ]));
			}
			const li = E('li', { 'class': 'vt-pal-item', 'role': 'option', 'id': 'vt-pal-opt-' + n, 'aria-selected': 'false' }, [
				svg(r.e.icon, 18),
				highlight(r.e.title, r.idx),
				r.e.path ? E('span', { 'class': 'vt-pal-path' }, [ r.e.path ]) : '',
				E('kbd', { 'class': 'vt-pal-enter' }, [ '↵' ])
			]);
			li.addEventListener('mousemove', () => this.setPaletteActive(n, false));
			li.addEventListener('click', () => this.runEntry(r.e));
			pal.list.appendChild(li);
			pal.items.push({ li, e: r.e });
		});

		if (!results.length)
			pal.list.appendChild(E('li', { 'class': 'vt-pal-empty', 'role': 'presentation' }, [ _('No matching pages') ]));

		pal.count.textContent = q ? '%d / %d'.format(results.length, pool.length) : '%d %s'.format(pool.length, _('items'));
		this.setPaletteActive(0, true);
	},

	setPaletteActive(n, scroll) {
		const pal = this.pal;
		if (!pal || !pal.items.length) { if (pal) pal.input.removeAttribute('aria-activedescendant'); return; }
		n = (n + pal.items.length) % pal.items.length;
		if (pal.items[pal.active]) pal.items[pal.active].li.setAttribute('aria-selected', 'false');
		pal.active = n;
		const li = pal.items[n].li;
		li.setAttribute('aria-selected', 'true');
		pal.input.setAttribute('aria-activedescendant', li.id);
		if (scroll) {
			if (n === 0) pal.list.scrollTop = 0;
			else li.scrollIntoView({ block: 'nearest' });
		}
	},

	handlePaletteKeys(ev) {
		const pal = this.pal;
		switch (ev.key) {
		case 'ArrowDown': ev.preventDefault(); this.setPaletteActive(pal.active + 1, true); break;
		case 'ArrowUp': ev.preventDefault(); this.setPaletteActive(pal.active - 1, true); break;
		case 'PageDown': ev.preventDefault(); this.setPaletteActive(Math.min(pal.active + 8, pal.items.length - 1), true); break;
		case 'PageUp': ev.preventDefault(); this.setPaletteActive(Math.max(pal.active - 8, 0), true); break;
		case 'Enter':
			ev.preventDefault();
			if (pal.items[pal.active]) this.runEntry(pal.items[pal.active].e);
			break;
		case 'Escape': ev.preventDefault(); this.closePalette(); break;
		case 'Tab': ev.preventDefault(); break;
		}
	},

	runEntry(e) {
		if (e.run) { this.closePalette(); e.run(); return; }
		if (e.segs) window.location.href = L.url.apply(L, e.segs);
	},

	setupKeys() {
		const btn = document.getElementById('vt-search-btn');
		if (btn) btn.addEventListener('click', () => this.openPalette());

		document.addEventListener('keydown', ev => {
			if ((ev.ctrlKey || ev.metaKey) && !ev.altKey && (ev.key === 'k' || ev.key === 'K')) {
				ev.preventDefault();
				if (this.pal) this.closePalette(); else this.openPalette();
				return;
			}
			if (ev.key === '/' && !ev.ctrlKey && !ev.metaKey && !ev.altKey && !this.pal &&
			    !isTyping(ev.target) && !document.body.classList.contains('modal-overlay-active')) {
				ev.preventDefault();
				this.openPalette();
				return;
			}
			if (ev.key === 'Escape' && this.fly && !this.fly.hidden && !this.pal)
				this.closeFlyout(true);
		});

		const reset = () => { if (this.fly && this.scrim) this.scrim.hidden = this.fly.hidden || !this.mqMobile.matches; };
		if (this.mqMobile.addEventListener) this.mqMobile.addEventListener('change', reset);
	},

	/* -------------------------------------------------------- theme */

	themePref() {
		const p = storageGet(THEME_KEY);
		return (p === 'light' || p === 'dark') ? p : 'auto';
	},

	setTheme(pref) {
		storageSet(THEME_KEY, pref === 'auto' ? null : pref);
		this.applyTheme();
	},

	applyTheme() {
		const pref = this.themePref();
		const sysDark = !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
		const dark = pref === 'dark' || (pref === 'auto' && sysDark);
		this.root.setAttribute('data-darkmode', dark ? 'true' : 'false');
		this.root.setAttribute('data-theme', pref);

		const btn = document.getElementById('vt-theme');
		if (btn) {
			const names = { auto: _('Auto'), light: _('Light'), dark: _('Dark') };
			const label = '%s: %s'.format(_('Colour theme'), names[pref]) + (pref === 'auto' ? ' (%s)'.format(dark ? names.dark : names.light) : '');
			btn.textContent = '';
			btn.appendChild(svg(pref === 'auto' ? 'auto' : (pref === 'dark' ? 'moon' : 'sun'), 18));
			btn.setAttribute('aria-label', label);
			btn.setAttribute('title', label);
		}
	},

	setupTheme() {
		const btn = document.getElementById('vt-theme');
		const order = { auto: 'light', light: 'dark', dark: 'auto' };
		if (btn) btn.addEventListener('click', () => this.setTheme(order[this.themePref()]));
		const mq = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)');
		if (mq && mq.addEventListener) mq.addEventListener('change', () => { if (this.themePref() === 'auto') this.applyTheme(); });
		window.addEventListener('storage', ev => { if (ev.key === THEME_KEY) this.applyTheme(); });
		this.applyTheme();
	},

	/* --------------------------------------------------- host chip */

	loadHost() {
		const chip = document.getElementById('vt-host');
		L.resolveDefault(callBoard(), {}).then(board => {
			if (!board || !board.hostname) return;
			const product = host.productName(board);
			this.hostname = board.hostname;
			this.updateTitle();
			if (!chip) return;
			chip.textContent = '';
			/* device strings go in as text nodes (E() would parse a string as HTML) */
			const text = v => [ document.createTextNode(String(v)) ];
			chip.appendChild(E('b', {}, text(board.hostname)));
			if (product) {
				chip.appendChild(E('span', { 'class': 'vt-host-sep', 'aria-hidden': 'true' }, text('·')));
				chip.appendChild(E('span', {}, text(product)));
			}
			const rel = board.release && board.release.description;
			chip.setAttribute('title', [ board.hostname, product, rel ].filter(Boolean).join('\n'));
			chip.hidden = false;
		});
	},

	updateTitle() {
		const parts = [ this.pageTitle, this.hostname ].filter(Boolean);
		if (parts.length) document.title = parts.join(' · ');
	},

	/* -------------------------------------------------- indicators */

	setupIndicators() {
		const box = document.getElementById('indicators');
		if (!box) return;
		const decorate = () => {
			box.querySelectorAll('span[data-indicator]').forEach(el => {
				const node = el.firstChild;
				const text = (node && node.nodeType === 3) ? node.data : el.textContent;
				const m = /^(.*?):\s*(\d+)\s*$/.exec(text || '');
				if (m) {
					if (el.getAttribute('data-count') !== m[2]) el.setAttribute('data-count', m[2]);
					if (el.getAttribute('data-label') !== m[1]) el.setAttribute('data-label', m[1]);
				}
				else if (el.hasAttribute('data-count')) {
					el.removeAttribute('data-count');
					el.removeAttribute('data-label');
				}
				if (el.getAttribute('title') !== text) el.setAttribute('title', text);
				if (el.hasAttribute('data-clickable') && !el.hasAttribute('tabindex')) {
					el.setAttribute('tabindex', '0');
					el.setAttribute('role', 'button');
					el.addEventListener('keydown', ev => {
						if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); el.click(); }
					});
				}
			});
		};
		new MutationObserver(decorate).observe(box, { childList: true, subtree: true, characterData: true });
		decorate();
	},

	/* ------------------------------------------ technical numerals */

	setupNumerals() {
		const main = document.getElementById('maincontent');
		if (!main || !window.MutationObserver) return;
		/* the dashboard app sets its own numerals */
		if (document.body.getAttribute('data-page') === 'admin-dashboard') return;
		let queued = false;
		const skip = 'input,select,textarea,button,.btn,.cbi-button,.cbi-dropdown,img,.ifacebadge,.zonebadge,.cbi-progressbar,table,.table';
		const scan = () => {
			queued = false;
			main.querySelectorAll('td, .td, .ifacebox-body > span > span').forEach(cell => {
				if (cell.closest('.vt-app')) return;
				const text = cell.textContent;
				if (cell._vtText === text) return;
				cell._vtText = text;
				cell.classList.toggle('vt-num', !cell.querySelector(skip) && technical(text));
			});
		};
		new MutationObserver(() => {
			if (queued) return;
			queued = true;
			window.requestAnimationFrame(scan);
		}).observe(main, { childList: true, subtree: true, characterData: true });
		scan();
	}
});
