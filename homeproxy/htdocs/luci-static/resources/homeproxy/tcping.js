/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 节点测速前端 helper。
 */

'use strict';
'require baseclass';
'require rpc';
'require ui';

const MAX_NODES = 300;
const HELP_TEXT = _('Speed tests use the current runtime configuration. To test all nodes, add them to a running node group with a node regex such as .*');
const running = {};

const callNodesTcping = rpc.declare({
	object: 'luci.homeproxy_tcping',
	method: 'nodes_tcping',
	params: [ 'sections' ],
	expect: { '': {} }
});

const callNodeTcping = rpc.declare({
	object: 'luci.homeproxy_tcping',
	method: 'node_tcping',
	params: [ 'section' ],
	expect: { '': {} }
});

function replaceElementContent(el, content) {
	if (!el)
		return;

	while (el.firstChild)
		el.removeChild(el.firstChild);

	if (Array.isArray(content)) {
		for (let node of content)
			el.appendChild((typeof node === 'string') ? document.createTextNode(node) : node);
	} else {
		el.appendChild((typeof content === 'string') ? document.createTextNode(content) : content);
	}
}

function svgElement(tag, attrs, children) {
	let el = document.createElementNS('http://www.w3.org/2000/svg', tag);

	for (let key in (attrs || {}))
		el.setAttribute(key, attrs[key]);

	for (let child of (children || []))
		el.appendChild(child);

	return el;
}

function renderSpeedtestIcon(extra_class) {
	return svgElement('svg', {
		'xmlns': 'http://www.w3.org/2000/svg',
		'width': '18',
		'height': '18',
		'viewBox': '0 0 24 24',
		'fill': 'none',
		'stroke': 'currentColor',
		'stroke-width': '2',
		'stroke-linecap': 'round',
		'stroke-linejoin': 'round',
		'class': extra_class || ''
	}, [
		svgElement('path', { 'd': 'M5.636 19.364a9 9 0 1 1 12.728 0' }),
		svgElement('path', { 'd': 'M16 9l-4 4' })
	]);
}

function renderSpinner() {
	return E('span', { 'class': 'homeproxy-tcping-spinner' });
}

function setButtonIcon(btn, busy) {
	if (!btn)
		return;

	replaceElementContent(btn, renderSpeedtestIcon(busy ? 'homeproxy-tcping-icon homeproxy-tcping-icon-busy' : 'homeproxy-tcping-icon'));
}

function nodeId(section_id) {
	return 'homeproxy-node-tcping-' + String(section_id).replace(/[^A-Za-z0-9_-]/g, (c) =>
		'_' + c.charCodeAt(0).toString(16) + '_');
}

function ensureStyle() {
	if (document.getElementById('homeproxy-tcping-style'))
		return;

	document.head.appendChild(E('style', { 'id': 'homeproxy-tcping-style' }, `
@keyframes homeproxy-tcping-spin { to { transform: rotate(360deg); } }
@keyframes homeproxy-tcping-pulse { 50% { opacity: .45; } }
.homeproxy-tcping-button {
	width: 36px;
	min-width: 36px;
	height: 36px;
	padding: 0;
	display: inline-flex;
	align-items: center;
	justify-content: center;
	line-height: 1;
}
.homeproxy-tcping-icon {
	width: 18px;
	height: 18px;
}
.homeproxy-tcping-icon-busy {
	animation: homeproxy-tcping-pulse 1s ease-in-out infinite;
}
.homeproxy-latency-pill {
	display: inline-flex;
	align-items: center;
	justify-content: center;
	min-width: 4.8em;
	min-height: 1.7em;
	padding: .16em .55em;
	border-radius: 6px;
	cursor: pointer;
	font-variant-numeric: tabular-nums;
	line-height: 1.3;
	user-select: none;
	transition: background-color .15s ease, transform .15s ease;
}
.homeproxy-latency-pill:hover {
	background-color: rgba(128, 128, 128, .14);
	transform: scale(1.04);
}
.homeproxy-latency-pill:active {
	transform: scale(.96);
}
.homeproxy-latency-pill.homeproxy-tcping-busy {
	color: gray !important;
}
.homeproxy-tcping-spinner {
	width: 1em;
	height: 1em;
	border: 2px solid currentColor;
	border-top-color: transparent;
	border-radius: 999px;
	animation: homeproxy-tcping-spin .8s linear infinite;
}
`));
}

function formatTestedAt(result) {
	let tested_at = result?.tested_at;
	if (!tested_at)
		return '';

	try {
		return _('Tested at: %s').format(new Date(tested_at * 1000).toLocaleString());
	} catch (e) {
		return '';
	}
}

function setResult(section_id, text, color, title) {
	let el = document.getElementById(nodeId(section_id));

	if (!el)
		return false;

	replaceElementContent(el, text);
	el.title = title || '';
	el.style.setProperty('color', color || '');
	el.classList.remove('homeproxy-tcping-busy');
	el.setAttribute('aria-busy', 'false');

	return true;
}

function setBusy(section_id) {
	let el = document.getElementById(nodeId(section_id));

	if (!el)
		return false;

	replaceElementContent(el, renderSpinner());
	el.title = _('Testing...');
	el.classList.add('homeproxy-tcping-busy');
	el.setAttribute('aria-busy', 'true');

	return true;
}

function renderResult(section_id, result) {
	let target = result?.target || '',
	    error = result?.error || '',
	    tested_at = formatTestedAt(result),
	    title = [ target, error, tested_at ].filter((v) => v).join('\n');

	switch (result?.status) {
	case 'ok':
		setResult(section_id, '%d ms'.format(result.delay), 'green', title);
		break;
	case 'timeout':
		setResult(section_id, _('Timeout'), 'red', title);
		break;
	case 'unsupported':
		setResult(section_id, _('Unsupported'), 'gray', title);
		break;
	case 'invalid':
		setResult(section_id, _('No address'), 'red', title);
		break;
	case 'missing':
		setResult(section_id, _('Missing'), 'red', title);
		break;
	case 'skipped':
		setResult(section_id, _('Skipped'), 'gray', title);
		break;
	case 'unloaded':
		setResult(section_id, _('Not loaded'), 'gray', title);
		break;
	default:
		setResult(section_id, _('Failed'), 'red', title);
		break;
	}

	return true;
}

function runSingle(section_id, notices) {
	return L.resolveDefault(callNodeTcping(section_id), {}).then((res) => {
		if (!res.result) {
			let message = res.error || _('Connectivity test failed.');
			renderResult(section_id, { status: 'failed', error: message });
			notices[message] = true;
			return;
		}

		if (res.warning)
			notices[res.warning] = true;

		renderResult(section_id, res.node);
	}).catch((err) => {
		let message = err.message || String(err);
		renderResult(section_id, { status: 'failed', error: message });
		notices[message] = true;
	});
}

return baseclass.extend({
	helpText: HELP_TEXT,

	nodeId: nodeId,
	ensureStyle: ensureStyle,
	renderIcon: renderSpeedtestIcon,

	runNode(section_id, ev) {
		let notices = {};

		if (ev) {
			ev.preventDefault();
			ev.stopPropagation();
		}

		if (running[section_id])
			return Promise.resolve();

		running[section_id] = true;
		setBusy(section_id);

		return runSingle(section_id, notices).then(() => {
			for (let message in notices)
				ui.addNotification(null, E('p', message));
		}).finally(() => {
			running[section_id] = false;
		});
	},

	runNodes(section_ids, ev) {
		let btn = ev?.currentTarget || ev?.target,
		    test_sections = section_ids.slice(0, MAX_NODES),
		    skipped_sections = section_ids.slice(MAX_NODES),
		    notices = {};

		if (!section_ids.length) {
			ui.addNotification(null, E('p', _('No testable nodes.')));
			return Promise.resolve();
		}

		let visible = 0;

		for (let section_id of test_sections) {
			if (setBusy(section_id))
				visible++;
		}
		for (let section_id of skipped_sections)
			renderResult(section_id, {
				status: 'skipped',
				error: _('At most %d nodes can be tested at once.').format(MAX_NODES)
			});

		if (!visible)
			ui.addNotification(null, E('p', _('No latency column was found on this page. Force-refresh the page and try again.')));

		if (btn) {
			btn.disabled = true;
			setButtonIcon(btn, true);
		}

		return L.resolveDefault(callNodesTcping(test_sections), {}).then((res) => {
			if (!res.result)
				throw new Error(res.error || _('Connectivity test failed.'));

			if (res.warning)
				notices[res.warning] = true;

			let nodes = res.nodes || {};
			for (let section_id of test_sections)
				renderResult(section_id, nodes[section_id]);
		}).catch((err) => {
			let message = err.message || String(err);

			for (let section_id of test_sections)
				renderResult(section_id, { status: 'failed', error: message });

			notices[message] = true;
		}).then(() => {
			for (let message in notices)
				ui.addNotification(null, E('p', message));
		}).then(() => {
			if (skipped_sections.length) {
				let message = _('Skipped %d nodes. At most %d nodes can be tested at once.').format(skipped_sections.length, MAX_NODES);
				ui.addNotification(null, E('p', message));
			}

			if (btn) {
				btn.disabled = false;
				setButtonIcon(btn, false);
			}
		});
	}
});
