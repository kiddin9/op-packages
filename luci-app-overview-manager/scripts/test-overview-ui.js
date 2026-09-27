'use strict';

const fs = require('fs');
const vm = require('vm');

let classMutations = 0;

function classList() {
	const values = new Set();
	return {
		add: value => { classMutations++; values.add(value); },
		remove: value => { classMutations++; values.delete(value); },
		contains: value => values.has(value),
		/* The real DOM only mutates when the state actually changes, which is
		 * what keeps the toggle in overview.js from repainting on every poll. */
		toggle: (value, force) => {
			const wanted = force === undefined ? !values.has(value) : !!force;
			if (wanted === values.has(value))
				return wanted;
			classMutations++;
			if (wanted)
				values.add(value);
			else
				values.delete(value);
			return wanted;
		}
	};
}

function section() {
	const attributes = {};
	return {
		classList: classList(),
		parentNode: null,
		getAttribute: name => attributes[name] || null,
		setAttribute: (name, value) => { attributes[name] = value; }
	};
}

function load(path, context) {
	const source = fs.readFileSync(path, 'utf8');
	return vm.runInNewContext(`(function() {${source}\n})()`, context);
}

const common = load('luci/shared.js', {
	baseclass: { extend: value => value },
	E: (tag, attrs, children) => ({ tag, attrs, children })
});

/* luci-mod-status requires its includes as module names, so the .js suffix is
 * not part of the sort. Sorting raw file names would invert this pair and
 * shift every widget onto the wrong section. */
const sorted = [ '20_x-y.js', '20_x.js' ].sort(common.compareWidgets);
if (JSON.stringify(sorted) !== JSON.stringify([ '20_x.js', '20_x-y.js' ]))
	throw new Error(`unexpected widget sort order: ${sorted.join(',')}`);

const names = [
	'00_overview-manager.js',
	'10_system.js',
	'20_memory.js',
	'70_custom.js'
];
const sections = names.map(() => section());
sections.forEach(node => node.classList.add('cbi-section'));

let appendCalls = 0;
const parent = {
	children: sections,
	appendChild(node) {
		appendCalls++;
		const index = this.children.indexOf(node);
		if (index >= 0)
			this.children.splice(index, 1);
		this.children.push(node);
		node.parentNode = this;
	}
};
sections.forEach(node => { node.parentNode = parent; });

let execCalls = [];
const context = {
	baseclass: { extend: value => value },
	common: common,
	fs: {
		exec: (path, args) => {
			execCalls.push(args.join(' '));
			return Promise.resolve({ stdout: stdoutFor(args[0]) });
		}
	},
	L: { resolveDefault: value => value },
	Promise,
	window: {
		requestAnimationFrame: callback => callback(),
		setTimeout: callback => callback()
	},
	E(tag, attrs) {
		if (attrs && attrs['data-overview-manager-marker']) {
			return { closest: () => sections[0] };
		}
		return { tag, attrs };
	}
};

let helperAvailable = true;

function stdoutFor(command) {
	if (!helperAvailable)
		return '';
	if (command === 'files')
		return `${names.join('\n')}\n`;
	return 'order=70_custom.js 10_system.js 20_memory.js\nhidden=20_memory.js\n';
}

const widget = load('luci/overview.js', context);
const data = [
	{ stdout: stdoutFor('files') },
	{ stdout: stdoutFor('layout') }
];

widget.render(data);

function currentOrder() {
	return parent.children.map(node => node.getAttribute('data-overview-widget'));
}

const expected = [
	'00_overview-manager.js',
	'70_custom.js',
	'10_system.js',
	'20_memory.js'
];
if (JSON.stringify(currentOrder()) !== JSON.stringify(expected))
	throw new Error(`unexpected initial order: ${currentOrder().join(',')}`);

const hidden = parent.children.filter(node =>
	node.classList.contains('overview-manager-hidden')
).map(node => node.getAttribute('data-overview-widget'));
if (JSON.stringify(hidden) !== JSON.stringify([
	'00_overview-manager.js',
	'20_memory.js'
]))
	throw new Error(`unexpected hidden widgets: ${hidden.join(',')}`);

/* Regression test for the white flicker: a poll cycle that changes nothing
 * must not move any section or touch any class. */
appendCalls = 0;
classMutations = 0;
widget.render(data);

if (JSON.stringify(currentOrder()) !== JSON.stringify(expected))
	throw new Error(`polling changed the order: ${currentOrder().join(',')}`);
if (appendCalls !== 0)
	throw new Error(`polling re-appended ${appendCalls} sections`);
if (classMutations !== 0)
	throw new Error(`polling caused ${classMutations} class mutations`);

/* A changed layout must still be applied. */
widget.render([
	{ stdout: `${names.join('\n')}\n` },
	{ stdout: 'order=10_system.js 20_memory.js 70_custom.js\nhidden=\n' }
]);
const reordered = [
	'00_overview-manager.js',
	'10_system.js',
	'20_memory.js',
	'70_custom.js'
];
if (JSON.stringify(currentOrder()) !== JSON.stringify(reordered))
	throw new Error(`layout change was not applied: ${currentOrder().join(',')}`);
if (parent.children.filter(node =>
	node.classList.contains('overview-manager-hidden')
).length !== 1)
	throw new Error('unhiding a widget did not take effect');

/* The layout is read once per page load instead of spawning the helper twice
 * on every five-second poll cycle. */
function testLoadCaching() {
	helperAvailable = false;
	execCalls = [];

	return widget.load().then(() => {
		if (execCalls.length !== 2)
			throw new Error(`first load ran ${execCalls.length} helper calls`);
		return widget.load();
	}).then(() => {
		/* An unreachable helper must be retried, not cached as an empty list. */
		if (execCalls.length !== 4)
			throw new Error('a failed load was cached');
		helperAvailable = true;
		execCalls = [];
		return widget.load();
	}).then(() => {
		if (execCalls.length !== 2)
			throw new Error(`recovery load ran ${execCalls.length} helper calls`);
		return widget.load();
	}).then(() => {
		if (execCalls.length !== 2)
			throw new Error(`polling re-ran the helper: ${execCalls.join(', ')}`);
	});
}

testLoadCaching().then(() => {
	console.log('overview UI tests OK');
}).catch(error => {
	console.error(error.message);
	process.exit(1);
});
