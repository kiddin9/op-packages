#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * Dump the LuCI form definition of the homeproxy node/client/server views as
 * JSON, using a minimal mock of the LuCI client runtime. It is meant to be run
 * against two checkouts (e.g. HEAD and the working tree) and the resulting
 * snapshots diffed, so that a pure refactor can be proven not to change any
 * option name, dependency, default or label.
 *
 * Usage: node tests/luci-form-snapshot.js <repo-root> [node|server]
 */

'use strict';

const fs = require('fs');
const path = require('path');

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
	bind: (fn, self, ...args) => fn.bind(self, ...args),
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
			if (typeof value === 'function' || value === undefined)
				continue;
			props[key] = value;
		}
		return {
			kind: this.__kind,
			name: this.__name,
			title: this.__title,
			description: this.__description === undefined ? null : this.__description,
			depends: this.__depends,
			values: this.__values,
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
	'tools.widgets': widgets
};

/* --- LuCI runtime mock end --------------------------------------------- */

function loadLuciModule(file, extraDeps) {
	let src = fs.readFileSync(file, 'utf8');
	src = src.replace(/^'require ([^']+) as (\w+)';$/gm,
		(_m, mod, alias) => `const ${alias} = __deps[${JSON.stringify(mod)}];`);
	src = src.replace(/^'require ([^']+)';$/gm,
		(_m, mod) => `const ${mod.split('.').pop().replace(/[^\w]/g, '_')} = __deps[${JSON.stringify(mod)}];`);
	/* eslint-disable-next-line no-new-func */
	const factory = new Function('__deps', '_', 'E', 'L', src);
	return factory(Object.assign({}, deps, extraDeps), _, E, L);
}

function main() {
	const root = process.argv[2];
	const target = process.argv[3] || 'node';
	if (!root)
		throw new Error('usage: luci-form-snapshot.js <repo-root> [node|server]');

	const viewDir = path.join(root, 'htdocs/luci-static/resources');
	const homeproxy = loadLuciModule(path.join(viewDir, 'homeproxy.js'), {});
	const mod = loadLuciModule(path.join(viewDir, 'view/homeproxy', target + '.js'), { homeproxy });

	const features = {
		version: '1.14.0',
		with_acme: true, with_grpc: true, with_gvisor: true, with_quic: true,
		with_utls: true, with_wireguard: true, hp_has_tcp_brutal: true
	};

	const rendered = mod.render([ undefined, features ]);
	process.stdout.write(JSON.stringify(rendered, null, '\t') + '\n');
}

main();
