'use strict';

// LuCI glue: poll gating under the dashboard and the language list/switch.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('htdocs/luci-static/resources/menu-carbon.js', 'utf8');

function load({ uci = {}, lang = 'en', info = {}, meminfo = null } = {}) {
	const calls = [], indicators = [];
	const poll = {
		running: true,
		active() { return this.running; },
		start() { calls.push('start'); this.running = true; },
		stop() { calls.push('stop'); this.running = false; }
	};
	const writes = [];
	const declare = ({ object, method }) => (...args) => {
		if (object === 'system' && method === 'info') return info instanceof Error ? Promise.reject(info) : Promise.resolve(info);
		if (object === 'uci' && method === 'get') return Promise.resolve((uci[args[0]] || {})[args[1]] || {});
		if (object === 'uci' && method === 'set') { writes.push(['set', ...args]); return Promise.resolve(0); }
		if (object === 'uci' && method === 'commit') { writes.push(['commit', ...args]); return Promise.resolve(0); }
		return Promise.resolve({});
	};
	const listeners = {};
	const context = {
		baseclass: { extend: (v) => v }, session: {},
		fs: { read: (path) => {
			assert.equal(path, '/proc/meminfo');
			return meminfo instanceof Error ? Promise.reject(meminfo) : Promise.resolve(meminfo);
		} }, poll,
		ui: { menu: {}, hideIndicator: (id) => indicators.push(id) },
		rpc: { declare },
		L: { resolveDefault: (p, d) => Promise.resolve(p).catch(() => d) },
		window: { Carbon: { version: 'test' }, setTimeout: (fn) => fn() },
		E: () => ({}),
		document: {
			getElementById: (id) => id === 'maincontent' ? { insertBefore() {} } : null,
			documentElement: { getAttribute: () => lang },
			addEventListener: (name, fn) => { listeners[name] = fn; }
		}
	};
	const subject = vm.runInNewContext('(function() {\n' + source + '\n})()', context);
	return { subject, poll, calls, indicators, writes, listeners, context };
}

function infoProvider(options) {
	const f = load(options);
	let provider;
	f.context.window.Carbon = {
		Dashboard: { mount(host, p) { provider = p; } },
		mode: { get: () => 'simple' },
		detailsToggle() {}
	};
	f.subject.mountDashboard('admin', {});
	return provider;
}

const containerMeminfo = `MemTotal:        1048576 kB
MemFree:          593908 kB
MemAvailable:     940418 kB
Buffers:               0 kB
Cached:           337720 kB
Shmem:             12000 kB
SwapTotal:        524288 kB
SwapFree:         500000 kB
`;
const systemInfo = {
	memory: { total: 67135332352, free: 25797705728, available: 962987008, buffered: 557117440, cached: 345825280 },
	swap: { total: 8589934592, free: 4294967296 },
	uptime: 1234, load: [100, 200, 300], root: { total: 1000, free: 400 }
};

test('memory provider uses the container proc view and preserves other system information', async () => {
	const result = await infoProvider({ info: systemInfo, meminfo: containerMeminfo }).info();
	assert.deepEqual(JSON.parse(JSON.stringify(result.memory)), {
		total: 1073741824, free: 593908 * 1024, available: 940418 * 1024,
		buffered: 0, cached: 337720 * 1024, shared: 12000 * 1024
	});
	assert.deepEqual(JSON.parse(JSON.stringify(result.swap)), { total: 524288 * 1024, free: 500000 * 1024 });
	const usedPercent = (result.memory.total - result.memory.available) / result.memory.total * 100;
	assert.ok(usedPercent > 10 && usedPercent < 11, 'container usage is about 10%, not 98%');
	assert.equal(result.uptime, systemInfo.uptime);
	assert.equal(result.load, systemInfo.load);
	assert.equal(result.root, systemInfo.root);
	assert.equal(systemInfo.memory.total, 67135332352, 'do not mutate the RPC response');
});

test('missing MemAvailable retains the dashboard cache-aware fallback', async () => {
	const text = containerMeminfo.replace(/^MemAvailable:.*\n/m, '');
	const { memory } = await infoProvider({ info: systemInfo, meminfo: text }).info();
	assert.equal('available' in memory, false, 'do not retain host available or substitute MemFree');
	assert.equal(memory.free + memory.buffered + memory.cached, (593908 + 337720) * 1024);
});

test('zero available and zero swap are valid readings', async () => {
	const text = containerMeminfo.replace(/MemAvailable:\s+\d+/, 'MemAvailable: 0')
		.replace(/SwapTotal:\s+\d+/, 'SwapTotal: 0').replace(/SwapFree:\s+\d+/, 'SwapFree: 0');
	const result = await infoProvider({ info: systemInfo, meminfo: text }).info();
	assert.equal(result.memory.available, 0);
	assert.deepEqual(JSON.parse(JSON.stringify(result.swap)), { total: 0, free: 0 });
});

test('unreadable or invalid meminfo preserves the original system information', async () => {
	for (const text of [new Error('Permission denied'), null, {}, '', 'MemTotal: 0 kB\nMemFree: 0 kB',
		'MemTotal: 1024 kB', 'MemFree: 512 kB', 'MemTotal: nope kB\nMemFree: 512 kB',
		'MemTotal: 99999999999999999999 kB\nMemFree: 512 kB']) {
		assert.equal(await infoProvider({ info: systemInfo, meminfo: text }).info(), systemInfo);
	}
});

test('incomplete swap information does not replace the RPC swap readings', async () => {
	const text = containerMeminfo.replace(/^SwapFree:.*\n/m, '');
	const result = await infoProvider({ info: systemInfo, meminfo: text }).info();
	assert.equal(result.memory.total, 1073741824);
	assert.equal(result.swap, systemInfo.swap);
});

test('unavailable system info keeps the existing provider failure semantics', async () => {
	for (const info of [null, {}])
		assert.equal(await infoProvider({ info, meminfo: containerMeminfo }).info(), null);
	await assert.rejects(infoProvider({ info: new Error('RPC failed'), meminfo: containerMeminfo }).info(), /RPC failed/);
});

test('dashboard ACL grants read-only access to meminfo', () => {
	const acl = JSON.parse(fs.readFileSync('root/usr/share/rpcd/acl.d/luci-theme-carbon.json', 'utf8'))['luci-theme-carbon'];
	assert.deepEqual(acl.read.file['/proc/meminfo'], ['read']);
	assert.equal(acl.write.file?.['/proc/meminfo'], undefined);
});

test('collapsed details pause LuCI polling and hide the paused badge; expanding resumes', () => {
	const f = load();
	f.subject.gatePoll(false);
	assert.deepEqual(f.calls, ['stop']);
	assert.deepEqual(f.indicators, ['poll-status']);
	f.subject.gatePoll(false);
	assert.deepEqual(f.calls, ['stop'], 'no repeated stop');
	f.subject.gatePoll(true);
	assert.deepEqual(f.calls, ['stop', 'start']);
});

test('a poll started later by the status view is stopped again while collapsed', () => {
	const f = load();
	let toggle;
	f.context.window.Carbon = {
		Dashboard: { mount() {} },
		mode: { get: () => 'simple' },
		detailsToggle: (host, open, onToggle) => { toggle = onToggle; onToggle(false); }
	};
	f.subject.mountDashboard('admin', {});
	assert.deepEqual(f.calls, ['stop']);
	f.poll.running = true;              // status/index.js calls poll.add() after our mount
	f.listeners['poll-start']();
	assert.deepEqual(f.calls, ['stop', 'stop']);
	toggle(true);
	f.listeners['poll-start']();
	assert.deepEqual(f.calls, ['stop', 'stop', 'start'], 'expanded details keep LuCI polling');
});

test('language list offers English plus installed catalogues with native names', async () => {
	const f = load({ uci: { luci: {
		languages: { '.name': 'languages', '.type': 'internal', zh_cn: '简体中文 (Chinese Simplified)', zh_tw: '繁體中文 (Chinese Traditional)', de: 'Deutsch (German)', 'bad key': 'x' },
		main: { lang: 'auto' }
	} } });
	const info = await f.subject.language.load();
	assert.deepEqual(JSON.parse(JSON.stringify(info.options.map((o) => [o.code, o.label, o.short]))), [
		['en', 'English', 'EN'], ['de', 'Deutsch', 'DE'], ['zh_cn', '简体中文', '简'], ['zh_tw', '繁體中文', '繁']
	]);
	assert.equal(info.selected, 'auto');
});

test('a single Chinese catalogue is labelled 中; unknown saved languages fall back to auto', async () => {
	const f = load({ uci: { luci: { languages: { zh_cn: '中文 (Chinese)' }, main: { lang: 'fr' } } } });
	const info = await f.subject.language.load();
	assert.equal(info.options[1].short, '中');
	assert.equal(info.selected, 'auto');
});

test('switching language writes luci.main.lang only for installed languages', async () => {
	const f = load({ uci: { luci: { languages: { zh_cn: '简体中文 (Chinese Simplified)' }, main: { lang: 'en' } } } });
	await f.subject.language.set('zh_cn');
	assert.deepEqual(JSON.parse(JSON.stringify(f.writes)), [['set', 'luci', 'main', { lang: 'zh_cn' }], ['commit', 'luci']]);
	await assert.rejects(() => f.subject.language.set('ru'), /not installed/);
	await f.subject.language.set('auto');
	assert.equal(f.writes.length, 4);
});
