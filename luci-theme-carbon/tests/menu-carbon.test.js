'use strict';

// LuCI glue: poll gating under the dashboard and the language list/switch.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('htdocs/luci-static/resources/menu-carbon.js', 'utf8');

function load({ uci = {}, lang = 'en', info = {}, meminfo = null, dirs = {}, files = {}, trafficSource, dashboardAttr, dashboardRpc, simpleMenuAttr, simpleMenuRpc } = {}) {
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
		if (object === 'luci.carbon_update' && method === 'set_dashboard') {
			writes.push(['set_dashboard', ...args]);
			if (typeof dashboardRpc === 'function') return dashboardRpc(...args);
			return Promise.resolve({ dashboard_custom: args[0] !== 'reset' });
		}
		if (object === 'luci.carbon_update' && method === 'set_simple_menu') {
			writes.push(['set_simple_menu', ...args]);
			if (typeof simpleMenuRpc === 'function') return simpleMenuRpc(...args);
			return Promise.resolve({ simple_menu_custom: args[0] !== 'reset' });
		}
		return Promise.resolve({});
	};
	const appEl = (trafficSource != null || dashboardAttr != null || simpleMenuAttr != null) ? {
		dataset: Object.assign(
			{},
			trafficSource != null ? { trafficSource } : {},
			dashboardAttr != null ? { dashboard: dashboardAttr } : {},
			simpleMenuAttr != null ? { simpleMenu: simpleMenuAttr } : {}
		)
	} : null;
	const listeners = {};
	const context = {
		baseclass: { extend: (v) => v }, session: {},
		traffic: { read: source => source },
		fs: {
			list: (dir) => {
				if (!(dir in dirs)) return Promise.reject(new Error('ENOENT: ' + dir));
				return dirs[dir] instanceof Error ? Promise.reject(dirs[dir]) : Promise.resolve(dirs[dir]);
			},
			read: (path) => {
				if (path === '/proc/meminfo' && !(path in files))
					return meminfo instanceof Error ? Promise.reject(meminfo) : Promise.resolve(meminfo);
				if (path in files)
					return files[path] instanceof Error ? Promise.reject(files[path]) : Promise.resolve(files[path]);
				return Promise.reject(new Error('ENOENT: ' + path));
			}
		}, poll,
		ui: { menu: {}, hideIndicator: (id) => indicators.push(id) },
		rpc: { declare },
		L: { resolveDefault: (p, d) => Promise.resolve(p).catch(() => d) },
		window: { Carbon: { version: 'test' }, setTimeout: (fn) => fn() },
		E: () => ({ children: [], appendChild() {} }),
		document: {
			querySelector: selector => selector === '.cb-app' ? appEl : null,
			getElementById: (id) => id === 'maincontent' ? { insertBefore() {} } : null,
			documentElement: { getAttribute: () => lang },
			addEventListener: (name, fn) => { listeners[name] = fn; }
		}
	};
	const subject = vm.runInNewContext('(function() {\n' + source + '\n})()', context);
	return { subject, poll, calls, indicators, writes, listeners, context, appEl };
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

test('device speeds pass only the configured traffic source to the collector', () => {
	for (const [trafficSource, expected] of [[undefined, 'nlbwmon'], ['invalid', 'nlbwmon'], ['nlbwmon', 'nlbwmon'], ['nftables', 'nftables']])
		assert.equal(infoProvider({ trafficSource }).deviceTraffic(), expected);
});

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

test('dashboard mount passes SSR UCI layout and persists save/reset via luci.carbon_update', async () => {
	const attr = 'hero=1;sections=tiles monitor details;monitor=traffic:auto resources;tiles=wifi temp;details=clients';
	const f = load({ dashboardAttr: attr });
	let mountOpts;
	f.context.window.Carbon = {
		dashboardLayout: {
			serialize: () => ({ hero: '1', sections: 'monitor tiles details', monitor: 'traffic:auto traffic:br-lan resources', tiles: 'wifi', details: 'clients' }),
			encodeAttr: () => 'hero=1;sections=monitor tiles details;monitor=traffic:auto traffic:br-lan resources;tiles=wifi;details=clients'
		},
		Dashboard: { mount(host, p, opts) { mountOpts = opts; } },
		mode: { get: () => 'simple' },
		detailsToggle() {}
	};
	f.subject.mountDashboard('admin', {});
	assert.equal(mountOpts.dashboardAttr, attr);

	await mountOpts.saveLayout({});
	assert.deepEqual(JSON.parse(JSON.stringify(f.writes[0])), ['set_dashboard', 'set', '1', 'monitor tiles details', 'traffic:auto traffic:br-lan resources', 'wifi', 'clients']);
	assert.equal(f.appEl.dataset.dashboard, 'hero=1;sections=monitor tiles details;monitor=traffic:auto traffic:br-lan resources;tiles=wifi;details=clients');

	await mountOpts.resetLayout();
	assert.deepEqual(JSON.parse(JSON.stringify(f.writes[1])), ['set_dashboard', 'reset', '', '', '', '', '']);
	assert.equal(f.appEl.dataset.dashboard, undefined);
});

test('dashboard UCI save surfaces permission-denied errors distinctly', async () => {
	const f = load({
		dashboardAttr: '',
		dashboardRpc: () => Promise.reject(new Error('RPC call to luci.carbon_update/set_dashboard failed with ubus code 6: Access denied'))
	});
	let mountOpts;
	f.context.window.Carbon = {
		dashboardLayout: {
			serialize: () => ({ hero: '1', sections: 'monitor tiles details', monitor: 'traffic:auto', tiles: 'none', details: 'none' }),
			encodeAttr: () => ''
		},
		Dashboard: { mount(host, p, opts) { mountOpts = opts; } },
		mode: { get: () => 'simple' },
		detailsToggle() {}
	};
	f.subject.mountDashboard('admin', {});
	await assert.rejects(() => mountOpts.saveLayout({}), (err) => err && err.code === 'denied');
});

test('nav render passes SSR simple menu and persists save/reset via luci.carbon_update', async () => {
	const attr = 'common=status/overview services/openclash;system=system/reboot';
	const f = load({ simpleMenuAttr: attr });
	let navModel;
	f.context._ = (s) => s;
	f.context.L.env = { requestpath: ['admin', 'network', 'network'], dispatchpath: ['admin', 'network', 'network'] };
	f.context.L.url = (...parts) => '/' + parts.join('/');
	f.context.ui.menu.getChildren = (node) => Object.values((node && node.children) || {});
	f.context.window.Carbon = {
		t: (s) => s,
		initShell() {},
		setTitle() {},
		simpleMenu: {
			serialize: () => ({ common: 'status/overview network/dhcp', system: 'system/reboot' }),
			encodeAttr: () => 'common=status/overview network/dhcp;system=system/reboot'
		},
		renderNav(m) { navModel = m; }
	};
	const tree = {
		children: {
			admin: {
				name: 'admin', title: 'Admin',
				children: {
					network: {
						name: 'network', title: 'Network',
						children: { network: { name: 'network', title: 'Interfaces' } }
					}
				}
			}
		}
	};
	f.subject.render(tree);
	assert.equal(navModel.simpleMenuAttr, attr);

	await navModel.saveSimpleMenu({});
	assert.deepEqual(JSON.parse(JSON.stringify(f.writes[0])), ['set_simple_menu', 'set', 'status/overview network/dhcp', 'system/reboot']);
	assert.equal(f.appEl.dataset.simpleMenu, 'common=status/overview network/dhcp;system=system/reboot');

	await navModel.resetSimpleMenu();
	assert.deepEqual(JSON.parse(JSON.stringify(f.writes[1])), ['set_simple_menu', 'reset', '', '']);
	assert.equal(f.appEl.dataset.simpleMenu, undefined);
});

test('simple menu UCI save surfaces permission-denied errors distinctly', async () => {
	const f = load({
		simpleMenuAttr: '',
		simpleMenuRpc: () => Promise.reject(new Error('RPC call to luci.carbon_update/set_simple_menu failed with ubus code 6: Access denied'))
	});
	let navModel;
	f.context._ = (s) => s;
	f.context.L.env = { requestpath: ['admin', 'network', 'network'], dispatchpath: ['admin', 'network', 'network'] };
	f.context.L.url = (...parts) => '/' + parts.join('/');
	f.context.ui.menu.getChildren = (node) => Object.values((node && node.children) || {});
	f.context.window.Carbon = {
		t: (s) => s,
		initShell() {},
		setTitle() {},
		simpleMenu: {
			serialize: () => ({ common: 'status/overview', system: 'none' }),
			encodeAttr: () => 'common=status/overview;system=none'
		},
		renderNav(m) { navModel = m; }
	};
	f.subject.render({ children: { admin: { name: 'admin', title: 'Admin', children: {} } } });
	await assert.rejects(() => navModel.saveSimpleMenu({}), (err) => err && err.code === 'denied');
});

function sysfs({ zones = [], hwmons = [], extraFiles = {} } = {}) {
	const dirs = {};
	const files = Object.assign({}, extraFiles);
	if (zones !== null) {
		dirs['/sys/class/thermal'] = zones.map((z, i) => ({
			name: z.dir || ('thermal_zone' + i),
			type: 'symlink',
			target: z.target || ('../../devices/virtual/thermal/' + (z.dir || ('thermal_zone' + i)))
		}));
		zones.forEach((z, i) => {
			const name = z.dir || ('thermal_zone' + i);
			if (z.type !== undefined) files['/sys/class/thermal/' + name + '/type'] = z.type;
			if (z.temp !== undefined) files['/sys/class/thermal/' + name + '/temp'] = String(z.temp) + '\n';
		});
	}
	if (hwmons !== null) {
		dirs['/sys/class/hwmon'] = hwmons.map((h, i) => ({
			name: h.dir || ('hwmon' + i),
			type: 'symlink',
			target: h.target || ('../../devices/platform/dev' + i + '/hwmon/' + (h.dir || ('hwmon' + i)))
		}));
		hwmons.forEach((h, i) => {
			const name = h.dir || ('hwmon' + i);
			const inputs = h.inputs || (h.temp !== undefined ? [['temp1_input', h.temp]] : []);
			dirs['/sys/class/hwmon/' + name] = [{ name: 'name', type: 'file' }].concat(
				inputs.map(([file]) => ({ name: file, type: 'file' }))
			);
			if (h.name !== undefined) files['/sys/class/hwmon/' + name + '/name'] = h.name;
			inputs.forEach(([file, temp]) => {
				files['/sys/class/hwmon/' + name + '/' + file] = String(temp) + '\n';
			});
		});
	}
	return { dirs, files };
}

test('Phicomm N1 scpi_sensors and SCMI scmi_sensors do not duplicate CPU/SoC thermal zones', async () => {
	const n1 = await infoProvider(sysfs({
		zones: [{ type: 'cpu-thermal\n', temp: 38000 }],
		hwmons: [{
			name: 'scpi_sensors\n',
			target: '../../devices/platform/scpi/scpi:sensors/hwmon/hwmon0',
			temp: 39000
		}]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(n1)), [{ name: 'cpu-thermal', value: 38000 }]);

	const scmi = await infoProvider(sysfs({
		zones: [{ type: 'soc-thermal\n', temp: 44000 }],
		hwmons: [{
			name: 'scmi_sensors\n',
			target: '../../devices/platform/firmware:scmi/scmi_dev.1/hwmon/hwmon0',
			temp: 44500
		}]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(scmi)), [{ name: 'soc-thermal', value: 44000 }]);
});

test('scpi_sensors is kept when no CPU/SoC thermal zone is present', async () => {
	const noThermal = await infoProvider(sysfs({
		zones: [],
		hwmons: [{
			name: 'scpi_sensors\n',
			target: '../../devices/platform/scpi/scpi:sensors/hwmon/hwmon0',
			temp: 41000
		}]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(noThermal)), [{ name: 'scpi_sensors', value: 41000 }]);

	const onlyWifiZone = await infoProvider(sysfs({
		zones: [{ type: 'iwlwifi_1\n', temp: 46000 }],
		hwmons: [{
			name: 'scpi_sensors\n',
			target: '../../devices/platform/scpi/scpi:sensors/hwmon/hwmon0',
			temp: 41000
		}]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(onlyWifiZone)), [
		{ name: 'iwlwifi_1', value: 46000 },
		{ name: 'scpi_sensors', value: 41000 }
	]);
});

test('virtual thermal hwmon bridges are skipped even with mismatched names while Wi-Fi hwmon is kept', async () => {
	const mt = await infoProvider(sysfs({
		zones: [{ type: 'cpu_thermal\n', temp: 52300 }],
		hwmons: [
			{ name: 'thermal0\n', target: '../../devices/virtual/thermal/thermal_zone0/hwmon0', temp: 52400 },
			{ name: 'mt7986_phy1\n', target: '../../devices/platform/18000000.wifi/ieee80211/phy1/hwmon1', temp: 47800 }
		]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(mt)), [
		{ name: 'cpu_thermal', value: 52300 },
		{ name: 'mt7986_phy1', value: 47800 }
	]);

	/* If /sys/class/thermal itself cannot be listed, keep the bridge hwmon as fallback */
	const noThermalDir = await infoProvider(sysfs({
		zones: null,
		hwmons: [
			{ name: 'cpu_thermal\n', target: '../../devices/virtual/thermal/thermal_zone0/hwmon0', temp: 52400 }
		]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(noThermalDir)), [
		{ name: 'cpu_thermal', value: 52400 }
	]);
});

test('hwmon and thermal names that differ only by a trailing thermal suffix are deduplicated', async () => {
	const result = await infoProvider(sysfs({
		zones: [{ type: 'cpu-thermal\n', temp: 49000 }],
		hwmons: [{ name: 'cpu\n', temp: 49500 }]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(result)), [{ name: 'cpu-thermal', value: 49000 }]);
});

test('x86 prefers coretemp over duplicate x86_pkg_temp and preserves peripheral and AMD sensors', async () => {
	const intel = await infoProvider(sysfs({
		zones: [
			{ type: 'acpitz\n', temp: 27800 },
			{ type: 'x86_pkg_temp\n', temp: 43000 }
		],
		hwmons: [
			{ name: 'acpitz\n', target: '../../devices/virtual/thermal/thermal_zone0/hwmon0', temp: 27800 },
			{ name: 'x86_pkg_temp\n', target: '../../devices/virtual/hwmon/hwmon1', temp: 43000 },
			{ name: 'coretemp\n', target: '../../devices/platform/coretemp.0/hwmon/hwmon2', temp: 43000 },
			{ name: 'nvme\n', target: '../../devices/pci0000:00/0000:00:1d.0/nvme/nvme0/hwmon3', temp: 36000 }
		]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(intel)), [
		{ name: 'acpitz', value: 27800 },
		{ name: 'coretemp', value: 43000 },
		{ name: 'nvme', value: 36000 }
	]);

	const pkgOnly = await infoProvider(sysfs({
		zones: [{ type: 'x86_pkg_temp\n', temp: 43000 }],
		hwmons: [{ name: 'nvme\n', temp: 36000 }]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(pkgOnly)), [
		{ name: 'x86_pkg_temp', value: 43000 },
		{ name: 'nvme', value: 36000 }
	]);

	const amd = await infoProvider(sysfs({
		zones: [{ type: 'acpitz\n', temp: 30000 }],
		hwmons: [
			{ name: 'k10temp\n', temp: 47000 },
			{ name: 'nvme\n', temp: 35000 }
		]
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(amd)), [
		{ name: 'acpitz', value: 30000 },
		{ name: 'k10temp', value: 47000 },
		{ name: 'nvme', value: 35000 }
	]);
});

test('temperatures fall back to thermal_zone0 when sysfs directories cannot be listed', async () => {
	const result = await infoProvider(sysfs({
		zones: null,
		hwmons: null,
		extraFiles: { '/sys/class/thermal/thermal_zone0/temp': '45000\n' }
	})).temperatures();
	assert.deepEqual(JSON.parse(JSON.stringify(result)), [{ name: '', value: 45000 }]);
});
