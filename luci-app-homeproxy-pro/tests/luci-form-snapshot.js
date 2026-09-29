#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * Dump the LuCI form definition of the homeproxy-pro node/client/server views as
 * JSON, using a minimal mock of the LuCI client runtime. It is meant to be run
 * against two checkouts (e.g. HEAD and the working tree) and the resulting
 * snapshots diffed, so that a pure refactor can be proven not to change any
 * option name, dependency, default or label.
 *
 * Usage: node tests/luci-form-snapshot.js <repo-root> [node|client|server]
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/* --- Function fingerprints --------------------------------------------- *
 * `props` used to drop every function-valued property, which made the 36
 * `o.validate = ...` assignments in the views invisible: deleting one, or
 * pointing it at a different function, produced a byte-identical snapshot.
 *
 * Record a digest of the function body instead of its source text, so a
 * comment or an indentation change is not noise. The digest is
 * `<length>:<sha1-12>` of the comment- and whitespace-normalised source.
 *
 * L.bind() returns a native-code bound function whose toString() is
 * `function () { [native code] }` for every bound function, so six of the
 * validators would be indistinguishable. L.bind() below therefore remembers
 * the target and the stable bound arguments, and the fingerprint folds them
 * in: `bind(<target>;arg,arg)`.
 */
const bindSources = new WeakMap();

function describeArg(value) {
	if (value === null)
		return 'null';
	if (value === undefined)
		return 'undefined';
	const kind = typeof value;
	if (kind === 'string')
		return JSON.stringify(value);
	if (kind === 'number' || kind === 'boolean')
		return String(value);
	return `<${kind}>`;
}

/* Remove // and /* *\/ comments without touching string/template literals.
 * Regex literals are left alone: an unescaped '/' cannot appear in one. */
function stripComments(src) {
	let out = '';
	let quote = null;

	for (let i = 0; i < src.length; i++) {
		const c = src[i], d = src[i + 1];

		if (quote) {
			out += c;
			if (c === '\\') { out += d === undefined ? '' : d; i++; }
			else if (c === quote) quote = null;
			continue;
		}
		if (c === '"' || c === "'" || c === '`') { quote = c; out += c; continue; }
		if (c === '/' && d === '/') {
			while (i < src.length && src[i] !== '\n') i++;
			out += '\n';
			continue;
		}
		if (c === '/' && d === '*') {
			i += 2;
			while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++;
			i++;
			out += ' ';
			continue;
		}
		out += c;
	}
	return out;
}

function fnFingerprint(fn) {
	const bound = bindSources.get(fn);
	const src = stripComments(String(bound ? bound.target : fn)).replace(/\s+/g, ' ').trim();
	const digest = crypto.createHash('sha1').update(src).digest('hex').slice(0, 12);

	if (bound)
		return `bind(${src.length}:${digest};${bound.args.join(',')})`;
	return `fn(${src.length}:${digest})`;
}

/* --- LuCI runtime mock start ------------------------------------------- */

String.prototype.format = function (...args) {
	const values = args.length === 1 && Array.isArray(args[0]) ? args[0] : args;
	let i = 0;
	return this.replace(/%[sdj%]/g, (m) => m === '%%' ? '%' : (i < values.length ? String(values[i++]) : m));
};

function E(tag, attrs, children) {
	return { tag: tag, attrs: attrs, children: children };
}

function _(text) { return text; }

const L = {
	bind: (fn, self, ...args) => {
		const bound = fn.bind(self, ...args);
		if (typeof fn === 'function')
			bindSources.set(bound, { target: fn, args: args.map(describeArg) });
		return bound;
	},
	resolveDefault: (promise, fallback) => promise.catch(() => fallback),
	ui: { hideModal: () => {}, addNotification: () => {}, changes: { apply: () => {} } },
	env: { paths: {} }
};

let sectionSeq = 0;

class Option {
	constructor(kind, name, title, description) {
		this.__kind = kind;
		this.__name = name;
		this.__title = title;
		this.__description = description;
		this.__depends = [];
		this.__values = [];
	}

	depends(...args) { this.__depends.push(args.length === 1 ? args[0] : args); }
	value(value, label) { this.__values.push([ value, label === undefined ? null : label ]); }

	toJSON() {
		const props = {};
		for (const key of Object.keys(this).sort()) {
			if (key.startsWith('__') || key === 'subsection')
				continue;
			const value = this[key];
			if (value === undefined)
				continue;
			/* A function-valued prop (validate, load, onclick, ...) gets a
			   stable digest rather than being dropped. */
			if (typeof value === 'function') {
				props[key] = fnFingerprint(value);
				continue;
			}
			props[key] = value;
		}
		return {
			kind: this.__kind,
			name: this.__name,
			title: this.__title,
			description: this.__description === undefined ? null : this.__description,
			depends: this.__depends,
			values: this.__values,
			/* A SectionValue option owns the nested form (`o.subsection`).
			   Skipping it dropped the node form's entire body - every
			   per-protocol option - and client.js's rule sections, which is
			   why node.json held 14 options while server.json held 97. */
			subsection: this.subsection ? this.subsection.toJSON() : null,
			props: props
		};
	}
}

class Section {
	constructor(kind, name) {
		this.__kind = kind;
		this.__name = name;
		this.__id = `${kind}:${name || ''}#${sectionSeq++}`;
		this.__options = [];
		this.__tabs = [];
		if (kind === 'SectionValue')
			this.subsection = new Section('GridSection', name);
	}

	option(kind, name, title, description) {
		const kindName = kind && kind.__name__ ? kind.__name__ : String(kind);
		const option = new Option(kindName, name, title, description);
		if (kindName === 'SectionValue')
			option.subsection = new Section('GridSection', name);
		this.__options.push(option);
		return option;
	}

	tab(id, title) { this.__tabs.push([ id, title ]); }
	taboption(_tab, ...args) { return this.option(...args); }

	toJSON() {
		return {
			id: this.__id,
			kind: this.__kind,
			name: this.__name,
			tabs: this.__tabs,
			options: this.__options.map((o) => o.toJSON()),
			subsection: this.subsection ? this.subsection.toJSON() : null
		};
	}
}

const classes = [ 'Value', 'ListValue', 'Flag', 'DynamicList', 'MultiValue', 'TextValue', 'Button', 'TypedSection',
	'NamedSection', 'GridSection', 'SectionValue' ];

const form = {};
for (const name of classes) {
	form[name] = class {};
	form[name].__name__ = name;
}

form.DynamicList.extend = function (obj) {
	const cls = class extends form.DynamicList {};
	Object.assign(cls.prototype, obj);
	cls.__name__ = obj.__name__ || 'DynamicList';
	return cls;
};

form.Value.extend = function (obj) {
	const cls = class extends form.Value {};
	Object.assign(cls.prototype, obj);
	cls.__name__ = obj.__name__ || 'Value';
	return cls;
};

form.Map = class {
	constructor(title) { this.title = title; this.sections = []; }
	section(kind, name) {
		const section = new Section(kind && kind.__name__ ? kind.__name__ : String(kind), name);
		this.sections.push(section);
		return section;
	}
	render() { return { sections: this.sections.map((s) => s.toJSON()) }; }
};

const uci = {
	load: () => Promise.resolve(),
	get: () => undefined,
	get_first: () => null,
	get_all: () => ({}),
	sections: () => {},
	foreach: () => {},
	set: () => {}, add: () => 'section', remove: () => {}, save: () => Promise.resolve()
};

const ui = {
	addNotification: () => {},
	showModal: () => {},
	hideModal: () => {},
	uploadFile: () => Promise.resolve({}),
	addValidator: () => {},
	Textarea: class { render() { return E('textarea'); } getValue() { return ''; } },
	createHandlerFn: (self, fn) => fn
};

const baseclass = { extend: (obj) => obj };
const view = { extend: (obj) => obj };
const poll = { add: () => {} };
const rpc = { declare: () => () => Promise.resolve({}) };
const fsMock = { exec_direct: () => Promise.resolve(''), read: () => Promise.resolve(''), write: () => Promise.resolve() };
const widgets = { DeviceSelect: class {} };

const deps = {
	baseclass, form, fs: fsMock, rpc, uci, ui, view, poll,
	'luci.http': { urldecode: (s) => s, urlencode: (s) => s, urldecode_params: () => ({}) },
	'luci.sys': { init_action: () => {} },
	'tools.widgets': widgets,
	/* tools.firewall exports two helpers - addIPOption / addMACOption -
	 * that wire a TextValue into the firewall zone matcher UI. The
	 * real implementation reads UCI host sections and renders a
	 * multi-select with validation. The snapshot only needs the
	 * shape of the returned option object so we stub them out:
	 * each one returns a TaggedValue-like object with the same
	 * `.value`/`.datatype`/`.depends`/`.validate` interface that
	 * the form framework traverses during rendering. The snapshots
	 * are pure structural diffs; this mock only has to keep the
	 * form render from throwing. */
	'tools.firewall': {
		addIPOption(section, _optName, _title, _description, _family, _hosts, _noHostCheck) {
			return section.option(form.Value, _optName, _title, _description);
		},
		addMACOption(section, _optName, _title, _description, _hosts) {
			return section.option(form.Value, _optName, _title, _description);
		}
	}
};

/* --- LuCI runtime mock end --------------------------------------------- */

/* The loader itself lives in tests/lib/luci-module.js, shared with the
 * frontend invariant tests; this just binds it to the mock runtime above. */
const { loadLuciModule: loadModule } = require('./lib/luci-module.js');

function loadLuciModule(file, extraDeps) {
	return loadModule(file, Object.assign({}, deps, extraDeps), { _: _, E: E, L: L });
}

function main() {
	const root = process.argv[2];
	const target = process.argv[3] || 'node';
	if (!root)
		throw new Error('usage: luci-form-snapshot.js <repo-root> [node|client|server]');
	if (!['node', 'client', 'server'].includes(target))
		throw new Error(`unknown snapshot target: ${target} (expected node|client|server)`);

	const viewDir = path.join(root, 'htdocs/luci-static/resources');
	const homeproxy-pro = loadLuciModule(path.join(viewDir, 'homeproxy-pro.js'), {});

	/* Per-tab modules of the client view. Each one is loaded with the deps
	 * it actually `require`s - the loader rewrites the 'require ... as X;'
	 * directive into a __deps lookup, so a missing key here becomes a
	 * runtime error inside the first tab render. The dep set is the same
	 * per-tab shape the modules had at the top of client.js before the
	 * split, plus `common` for the modules that pull in renderRuleSection.
	 */
	const tabsBase = { baseclass, homeproxy-pro, form, uci };
	const tabs = {};
	if (target === 'client') {
		const tabDir = path.join(viewDir, 'view/homeproxy-pro/client');
		tabs['view.homeproxy-pro.client.common']       = loadLuciModule(path.join(tabDir, 'common.js'),
				{ ...tabsBase });
		tabs['view.homeproxy-pro.client.routing']      = loadLuciModule(path.join(tabDir, 'routing.js'),
				{ ...tabsBase, 'view.homeproxy-pro.client.common': tabs['view.homeproxy-pro.client.common'] });
		tabs['view.homeproxy-pro.client.nodes']        = loadLuciModule(path.join(tabDir, 'nodes.js'),
				{ ...tabsBase, 'tools.widgets': widgets });
		tabs['view.homeproxy-pro.client.dns']          = loadLuciModule(path.join(tabDir, 'dns.js'),
				{ ...tabsBase, 'view.homeproxy-pro.client.common': tabs['view.homeproxy-pro.client.common'] });
		tabs['view.homeproxy-pro.client.subscription'] = loadLuciModule(path.join(tabDir, 'subscription.js'),
				{ ...tabsBase });
		tabs['view.homeproxy-pro.client.access']       = loadLuciModule(path.join(tabDir, 'access.js'),
				{ ...tabsBase, 'tools.widgets': widgets, 'tools.firewall': deps['tools.firewall'] });
		tabs['view.homeproxy-pro.client.udp_nat']      = loadLuciModule(path.join(tabDir, 'udp_nat.js'),
				{ ...tabsBase });
		tabs['view.homeproxy-pro.client.tun_dns']      = loadLuciModule(path.join(tabDir, 'tun_dns.js'),
				{ ...tabsBase });
	}

	const mod = loadLuciModule(path.join(viewDir, 'view/homeproxy-pro', target + '.js'), { homeproxy-pro, ...tabs });

	const features = {
		version: '1.14.0',
		with_acme: true, with_grpc: true, with_gvisor: true, with_quic: true,
		with_utls: true, with_wireguard: true, hp_has_tcp_brutal: true,
		hp_has_tproxy: true, hp_has_tun: true, hp_has_ip_full: true
	};

	const rendered = mod.render([ undefined, features ]);
	process.stdout.write(JSON.stringify(rendered, null, '\t') + '\n');
}

main();
