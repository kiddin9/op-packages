#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Three frontend call sites whose *wiring* - not their body - decides whether
 * they work, driven the way LuCI drives them:
 *
 *  1. client/nodes.js `urltest_nodes.validate` must not dereference a null
 *     value. It used to re-read the value through `this.section.formvalue()`
 *     (which answers null when the widget is not in the DOM) and then read
 *     `.length` on it, so the save aborted with a TypeError instead of the
 *     "non-empty value" message. The framework already hands the value in:
 *     getValidator() is L.bind(this.validate, this, section_id), so the widget
 *     calls validate(value).
 *
 *  2. client/access.js `_proxy_domain_list.remove` / `_direct_domain_list.remove`
 *     must read routing_mode from the 'config' section. `this.section` is the
 *     nested 'control' NamedSection, whose children do not include
 *     routing_mode, so `formvalue()` returned null and the test was always
 *     true: a reset wiped the domain list even in custom mode.
 *
 *  3. view/homeproxy/status.js `getRuntimeLog` must receive each log's
 *     basename. It used to derive it with `o.option.split('_')[1]`; it is now
 *     the third bound argument, ahead of the framework's
 *     (option_index, section_id, in_table). Shift that by one and the switch
 *     stops matching, so the log-level select disappears and the wrong
 *     basename reaches fs.read_direct and log_clean.
 *
 * The mocks cover only the surface each module touches; the plumbing under
 * test is the value/argument wiring.
 *
 * NOTE: tests/run.sh enumerates its node suites explicitly and is owned by
 * another change, so this file is not in that list yet. Run it directly:
 *
 *   node tests/frontend-view-wiring.js <repo-root>
 */

'use strict';

const path = require('path');
const { loadLuciModule } = require('./lib/luci-module.js');

const root = path.resolve(process.argv[2] || '.');

/* LuCI extends String with format() (luci.js); status.js builds the log path
 * with it. The shared loader does not inject it, so provide it here exactly as
 * tests/luci-form-snapshot.js does. */
if (typeof String.prototype.format !== 'function') {
	String.prototype.format = function (...args) {
		const values = args.length === 1 && Array.isArray(args[0]) ? args[0] : args;
		let i = 0;
		return this.replace(/%[sdj%]/g, (m) => (m === '%%' ? '%' : (i < values.length ? String(values[i++]) : m)));
	};
}

/* cbi.js defines the static form as `''.format.apply(fmt, args)`; status.js
 * builds the log path with it. */
if (typeof String.format !== 'function')
	String.format = function (fmt, ...args) { return String(fmt).format(...args); };

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

/* --- a form mock that records what the views build --------------------- */
class MockOption {
	constructor(kind, name, title, description) {
		this.__kind = kind && kind.__name__ ? kind.__name__ : String(kind);
		this.__name = name;
		this.option = name;
		this.title = title;
		this.description = description;
		if (this.__kind === 'SectionValue')
			this.subsection = new MockSection('NamedSection', name);
	}
	depends() {}
	value() {}
	cbid(section_id) { return `cbid.homeproxy.${section_id}.${this.__name}`; }
}

class MockSection {
	constructor(kind, name) {
		this.__kind = kind;
		this.__name = name;
		this.options = [];
	}
	tab() {}
	taboption(_tab, ...args) { return this.option(...args); }
	option(kind, name, title, description) {
		const o = new MockOption(kind, name, title, description);
		o.section = this;
		this.options.push(o);
		return o;
	}
	/* form.js AbstractSection.formvalue() walks the *children* of this
	 * section and answers null for anything else - which is why
	 * `this.section.formvalue('config', 'routing_mode')` from inside the
	 * nested 'control' section never found routing_mode. */
	formvalue(_section_id, option) {
		for (const child of this.options)
			if (child.__name === option)
				return child.value;
		return null;
	}
}

function makeForm() {
	const form = {};
	for (const name of [ 'Value', 'ListValue', 'Flag', 'DynamicList', 'MultiValue', 'TextValue',
			'DummyValue', 'Button', 'TypedSection', 'NamedSection', 'GridSection', 'SectionValue' ]) {
		form[name] = class {};
		/* form.js names each CBI class on `__name__`; the views use it to
		 * tell a SectionValue (which owns a sub-section) from the rest. */
		form[name].__name__ = name;
	}

	form.Map = class {
		constructor(title) { this.title = title; this.sections = []; }
		section(kind, name) {
			const section = new MockSection(kind && kind.__name__ ? kind.__name__ : String(kind), name);
			this.sections.push(section);
			return section;
		}
		render() { return this; }
	};

	return form;
}

function findOption(section, name) {
	for (const o of section.options)
		if (o.__name === name)
			return o;
	return null;
}

const L = { bind: (fn, self, ...bound) => fn.bind(self, ...bound) };

/* ====================================================================== *
 * 1. nodes.js: the urltest_nodes validator is null-safe
 * ====================================================================== */

function testNodesValidator() {
	const form = makeForm();
	const nodes = loadLuciModule(
		path.join(root, 'htdocs/luci-static/resources/view/homeproxy/client/nodes.js'),
		{
			baseclass: { extend: (o) => o },
			form,
			uci: { sections: () => {} },
			homeproxy: {
				CBIStaticList: class {},
				loadModalTitle: () => '',
				loadDefaultLabel: () => '',
				validateUniqueValue: () => true,
				renderSectionAdd: () => null
			},
			'tools.widgets': { DeviceSelect: class {} }
		},
		{ L, E: () => null });

	const ctx = { s: new MockSection('TypedSection', undefined), proxy_nodes: {} };
	nodes.renderRoutingNodes(ctx);

	const section = ctx.s.options[0].subsection;
	const validate = findOption(section, 'urltest_nodes')?.validate;
	check('nodes.js: urltest_nodes has a validate callback', typeof validate === 'function', typeof validate);
	if (typeof validate !== 'function')
		return;

	/* Before the fix this re-read `this.section.formvalue()` - null here, since
	 * the widget is not in the DOM - and threw on `.length`. */
	let threw = null;
	try {
		check('nodes.js: a missing value passes without throwing',
			validate.call({ section: { formvalue: () => null } }, 'sec1', null) === true);
	}
	catch (e) {
		threw = e;
	}
	check('nodes.js: a null value does not throw', threw === null, threw && threw.message);

	check('nodes.js: an empty list is rejected',
		validate.call({}, 'sec1', []) !== true && String(validate.call({}, 'sec1', [])).length > 0);
	check('nodes.js: a non-empty list passes',
		validate.call({}, 'sec1', [ 'node1' ]) === true);
	check('nodes.js: no section means no validation',
		validate.call({}, null, []) === true);
}

/* ====================================================================== *
 * 2. access.js: the domain-list resets read routing_mode from 'config'
 * ====================================================================== */

function testAccessDomainLists() {
	const form = makeForm();
	const writes = [];
	/* The module closes over its own `uci` dependency, so the per-case values
	 * go into a mutable stub rather than a captured snapshot. */
	const uciStub = { get: () => undefined };

	const access = loadLuciModule(
		path.join(root, 'htdocs/luci-static/resources/view/homeproxy/client/access.js'),
		{
			baseclass: { extend: (o) => o },
			form,
			uci: uciStub,
			homeproxy: {
				rpcCall: (method, args) => {
					writes.push({ method, args });
					return Promise.resolve({ result: true });
				}
			},
			'tools.widgets': { DeviceSelect: class {} },
			'tools.firewall': {
				addIPOption: (ss, _tab, name) => ss.option(form.Value, name),
				addMACOption: (ss, _tab, name) => ss.option(form.Value, name)
			}
		},
		{ L, E: () => null });

	const run = (routing_mode, option_name) => {
		writes.length = 0;
		uciStub.get = (_cfg, _section, option) => (option === 'routing_mode' ? routing_mode : undefined);

		const ctx = {
			s: new MockSection('NamedSection', 'config'),
			hosts: {},
			stubValidator: { apply: () => true }
		};
		access.render(ctx);

		const control = ctx.s.options.find((o) => o.__name === '_control').subsection;
		const so = findOption(control, option_name);
		check(`access.js: ${option_name} exists`, so !== null, String(so));
		if (!so)
			return Promise.resolve([]);

		/* rpcCall() runs synchronously inside remove(), so the snapshot has
		 * to be taken here: the four cases are started in the same tick and a
		 * shared array read from .then() would see all of them. */
		const ret = so.remove.call(so);
		const snapshot = writes.slice();

		return Promise.resolve(ret).then(() => snapshot);
	};

	const cleared = (w, list) =>
		w.length === 1 && w[0].method === 'acllist_write' && w[0].args[0] === list && w[0].args[1] === '';

	return Promise.all([
		run('custom', '_proxy_domain_list').then((w) =>
			check('access.js: custom mode keeps the proxy list', w.length === 0, JSON.stringify(w))),
		run('global', '_proxy_domain_list').then((w) =>
			check('access.js: non-custom mode clears the proxy list', cleared(w, 'proxy_list'), JSON.stringify(w))),
		run('custom', '_direct_domain_list').then((w) =>
			check('access.js: custom mode keeps the direct list', w.length === 0, JSON.stringify(w))),
		run('global', '_direct_domain_list').then((w) =>
			check('access.js: non-custom mode clears the direct list', cleared(w, 'direct_list'), JSON.stringify(w)))
	]);
}

/* ====================================================================== *
 * 3. status.js: each log view keeps its own basename
 * ====================================================================== */

function E(tag, attrs, children) {
	if (Array.isArray(tag) && attrs === undefined)
		return { tag: null, attrs: {}, children: tag, appendChild() {} };

	return {
		tag,
		attrs: attrs || {},
		children: children === undefined ? [] : (Array.isArray(children) ? children : [ children ]),
		appendChild() {}
	};
}

function findClickable(node) {
	if (!node || typeof node !== 'object')
		return null;
	if (node.attrs && typeof node.attrs.click === 'function')
		return node;
	for (const child of node.children || []) {
		const hit = findClickable(child);
		if (hit) return hit;
	}
	return null;
}

function findTag(node, tag) {
	if (!node || typeof node !== 'object')
		return null;
	if (node.tag === tag)
		return node;
	for (const child of node.children || []) {
		const hit = findTag(child, tag);
		if (hit) return hit;
	}
	return null;
}

function testLogViewWiring() {
	const form = makeForm();
	const reads = [];
	const rpcCalls = [];
	let pollHandlers = null;

	const status = loadLuciModule(
		path.join(root, 'htdocs/luci-static/resources/view/homeproxy/status.js'),
		{
			baseclass: {},
			dom: { content: () => {} },
			form,
			fs: { read_direct: (p) => { reads.push(p); return Promise.resolve('log line'); } },
			poll: { add: () => {} },
			uci: { get: () => 'warn' },
			ui: {
				createHandlerFn: (_self, fn) => fn,
				addNotification: () => {},
				changes: { apply: () => {} },
				showModal: () => {},
				hideModal: () => {}
			},
			view: { extend: (o) => o },
			homeproxy: {
				statusPoller: (handlers) => { pollHandlers = handlers; return () => {}; },
				rpcCall: (method, args) => { rpcCalls.push({ method, args }); return Promise.resolve({}); }
			}
		},
		{ L: Object.assign({}, L, { resource: () => 'icons/loading.svg', env: { pollinterval: 5 } }), E });

	const map = status.render();
	const section = map.sections[map.sections.length - 1];

	const wanted = [
		[ '_homeproxy_logview', 'homeproxy' ],
		[ '_sing-box-c_logview', 'sing-box-c' ],
		[ '_sing-box-s_logview', 'sing-box-s' ]
	];

	let rendered = 0;
	for (const [ option_name, basename ] of wanted) {
		const o = findOption(section, option_name);
		check(`status.js: ${option_name} exists`, o !== null, String(o));
		if (!o)
			continue;

		rpcCalls.length = 0;
		/* form.js calls render(option_index, section_id, in_table). */
		const tree = o.render(0, 'cfg01', false);
		rendered++;

		/* log_clean must target the same basename this view reads. */
		const button = findClickable(tree);
		check(`status.js: ${option_name} has a clean button`, button !== null, 'no click handler in the tree');
		if (button) {
			Promise.resolve(button.attrs.click());
			check(`status.js: ${option_name} cleans '${basename}'`,
				rpcCalls.length === 1 && rpcCalls[0].method === 'log_clean' && rpcCalls[0].args[0] === basename,
				JSON.stringify(rpcCalls));
		}

		/* The log-level select is built inside a switch on the basename: a
		 * shifted argument turns it into a label, no case matches, and the
		 * select disappears. */
		const select = findTag(tree, 'select');
		const want_select = basename !== 'homeproxy';
		check(`status.js: ${option_name} log-level select ${want_select ? 'present' : 'absent'}`,
			(select !== null) === want_select, String(select));
		if (select)
			check(`status.js: ${option_name} select carries section_id`,
				String(select.attrs.id || '').includes('cfg01'), String(select.attrs.id));
	}

	check('status.js: all three log views rendered', rendered === 3, String(rendered));
	check('status.js: the log poll was registered', pollHandlers !== null && typeof pollHandlers.read === 'function');

	if (!pollHandlers)
		return Promise.resolve();

	/* One tick reads one file per registered target, keyed by basename. */
	return Promise.resolve(pollHandlers.read()).then(() => {
		check('status.js: the poll reads each log by basename',
			JSON.stringify(reads.slice().sort()) === JSON.stringify([
				'/var/run/homeproxy/homeproxy.log',
				'/var/run/homeproxy/sing-box-c.log',
				'/var/run/homeproxy/sing-box-s.log'
			].sort()),
			JSON.stringify(reads));
	});
}

testNodesValidator();

testAccessDomainLists()
	.then(testLogViewWiring)
	.then(() => {
		console.log(`frontend view wiring: ${checks} checks, ${failures} failures`);
		process.exit(failures ? 1 : 0);
	})
	.catch((e) => {
		console.error('FAIL frontend view wiring threw:', (e && e.stack) || e);
		process.exit(1);
	});
