'use strict';

// Unit tests for the DOM-independent parts of carbon.js: formatting, i18n,
// version detection, device merging, ARP parsing and IPv6 uplink detection.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('htdocs/luci-static/carbon/carbon.js', 'utf8');
const brands = fs.readFileSync('htdocs/luci-static/carbon/brands.js', 'utf8');

function load({ lang = 'en', src = '/luci-static/carbon/carbon.js?v=1.2.3-r4', catalogue = null, luciTr = null } = {}) {
	const classes = new Set();
	const element = () => ({
		setAttribute() {}, getAttribute: () => null, classList: { toggle() {}, contains: () => false, add() {}, remove() {} },
		addEventListener() {}, appendChild() {}, style: { setProperty() {} }
	});
	const window = {
		localStorage: { getItem: () => null, setItem() {} },
		matchMedia: () => ({ matches: false, addEventListener() {} }),
		addEventListener() {},
		atob: (b64) => Buffer.from(b64, 'base64').toString('latin1'),
		Carbon: catalogue ? { I18N: catalogue } : undefined
	};
	if (luciTr) window._ = luciTr;
	const document = {
		currentScript: { src },
		documentElement: {
			getAttribute: (name) => name === 'lang' ? lang : null,
			setAttribute() {},
			classList: { toggle: (c, on) => (on ? classes.add(c) : classes.delete(c)), contains: (c) => classes.has(c) }
		},
		querySelector: () => null,
		getElementById: () => null,
		createElement: element,
		addEventListener() {}
	};
	const context = { window, document, navigator: { language: lang }, Intl, Map, WeakSet, setTimeout, clearTimeout, console };
	vm.runInNewContext(source, context);
	return window.Carbon;
}

test('version comes from the ?v= parameter the theme header adds', () => {
	assert.equal(load().version, '1.2.3-r4');
	assert.equal(load({ src: '/luci-static/carbon/carbon.js' }).version, 'dev');
	assert.equal(load({ src: '/x/carbon.js?v=<script>' }).version, 'dev');
});

test('bundled catalogue first, then LuCI catalogues, then English; placeholders fill in order', () => {
	const C = load({ lang: 'zh-cn', catalogue: { 'Show all %d devices': '显示全部 %d 台设备' }, luciTr: (s) => s === 'Memory' ? '内存(LuCI)' : s });
	assert.equal(C.t('Show all %d devices', 12), '显示全部 12 台设备');
	assert.equal(C.t('Memory'), '内存(LuCI)');
	assert.equal(C.t('Unknown string %s', 'x'), 'Unknown string x');
	assert.equal(C.locale, 'zh-CN');
	assert.equal(load({ lang: 'zh_Hant' }).locale, 'zh-TW');
	assert.equal(load({ lang: 'en', luciTr: () => 'wrong' }).t('Memory'), 'Memory');
});

test('placeholders are filled once, literally', () => {
	const C = load();
	assert.equal(C.t('%s and %s', '$& %s', 'b'), '$& %s and b');
	assert.equal(C.t('only %d', 1, 2), 'only 1');
	assert.equal(C.t('%s %s', 'a'), 'a %s');
});

test('durations use translatable patterns', () => {
	const en = load();
	assert.equal(en.fmt.duration(3 * 86400 + 5 * 3600), '3d 5h');
	assert.equal(en.fmt.duration(2 * 3600 + 7 * 60), '2h 7m');
	assert.equal(en.fmt.duration(30), '<1 min');
	const zh = load({ lang: 'zh-cn', catalogue: { '%dd %dh': '%d 天 %d 小时' } });
	assert.equal(zh.fmt.duration(86400 + 3600), '1 天 1 小时');
});

test('byte formatting', () => {
	const C = load();
	assert.deepEqual(Array.from(C.fmt.bytes(1536, true)), ['1.5', 'KB/s']);
	assert.equal(C.fmt.bytesStr(0), '0 B');
	assert.equal(C.fmt.pair(149 * 1048576, 428 * 1048576), '149 / 428 MB');
	assert.deepEqual(Array.from(C.fmt.bytes(null)), ['—', '']);
});

test('device speeds use per-MAC counter deltas with correct directions and actual elapsed time', () => {
	const tracker = new (load().DeviceRates)();
	const sample = (data) => ({ interval: 30, columns: ['tx_bytes', 'mac', 'rx_bytes'], data });
	assert.equal(tracker.update(sample([[100, 'AA:11:22:33:44:55', 200]]), 1000).rates.size, 0);
	const r = tracker.update(sample([[400, 'aa:11:22:33:44:55', 1700], [50, '00:11:22:33:44:66', 100]]), 31000);
	assert.deepEqual(JSON.parse(JSON.stringify(r.rates.get('aa:11:22:33:44:55'))), { down: 50, up: 10 });
	assert.equal(r.rates.has('00:11:22:33:44:66'), false, 'new records need a baseline');
	assert.equal(tracker.update(sample([[400, 'aa:11:22:33:44:55', 1700]]), 61000).rates.get('aa:11:22:33:44:55').down, 0);
});

test('counter reset, missing device, failed read, suspend and changed interval do not show false device speeds', () => {
	const tracker = new (load().DeviceRates)();
	const sample = (n, interval = 30) => ({ interval, columns: ['mac', 'rx_bytes', 'tx_bytes'], data: [['00:11:22:33:44:55', n, n]] });
	tracker.update(sample(1000), 0);
	assert.equal(tracker.update(sample(10), 30000).rates.size, 0, 'reset');
	assert.equal(tracker.update({ ...sample(20), data: [] }, 60000).rates.size, 0, 'missing');
	assert.equal(tracker.update(sample(30), 90000).rates.size, 0, 'reappearing');
	assert.equal(tracker.update(null, 120000), null);
	assert.equal(tracker.update(sample(100), 150000).rates.size, 0, 'first read after error');
	assert.equal(tracker.update(sample(1000), 400000).rates.size, 0, 'suspend');
	assert.equal(tracker.update(sample(1100, 60), 460000).rates.size, 0, 'cadence changed');
	assert.equal(tracker.update(sample(NaN), 520000), null);
	assert.equal(tracker.update(sample(Number.MAX_SAFE_INTEGER + 1), 550000), null);
});

test('invalid placeholder MAC does not discard a valid device rate', () => {
	const tracker = new (load().DeviceRates)();
	const mac = '00:11:22:33:44:55';
	const sample = (n) => ({ interval: 5, columns: ['mac', 'rx_bytes', 'tx_bytes'],
		data: [['00:00:00:00:00:00', null, null], [mac, n, n * 2]] });
	tracker.update(sample(100), 0);
	const rate = tracker.update(sample(200), 5000).rates.get(mac);
	assert.equal(rate.down, 20);
	assert.equal(rate.up, 40);
});

test('switching accounting sources with identical cadence resets unrelated byte totals', () => {
	const tracker = new (load().DeviceRates)();
	const sample = (source, n) => ({ source, interval: 5, columns: ['mac', 'rx_bytes', 'tx_bytes'],
		data: [['00:11:22:33:44:55', n, n]] });
	tracker.update(sample('nlbwmon', 100), 0);
	assert.equal(tracker.update(sample('nftables', 1000000), 5000).rates.size, 0);
	assert.equal(tracker.update(sample('nftables', 172500000), 10000).rates.get('00:11:22:33:44:55').down, 34300000);
	assert.equal(tracker.update(sample('nlbwmon', 300000000), 20000).rates.size, 0);
});

test('nft device creation, removal and recreation leave other device baselines intact', () => {
	const tracker = new (load().DeviceRates)();
	const a = '00:11:22:33:44:55', b = '00:11:22:33:44:66';
	const sample = (data) => ({ source: 'nftables', interval: 5, columns: ['mac', 'rx_bytes', 'tx_bytes', 'identity'], data });
	tracker.update(sample([[a, 100, 100, '[1,2]']]), 0);
	let result = tracker.update(sample([[a, 200, 150, '[1,2]'], [b, 500, 500, '[3,4]']]), 5000);
	assert.equal(result.source, 'nftables');
	assert.equal(result.rates.get(a).down, 20);
	assert.equal(result.rates.has(b), false);
	result = tracker.update(sample([[b, 1000, 1000, '[5,6]'], [a, 300, 200, '[1,2]']]), 10000);
	assert.equal(result.rates.get(a).down, 20);
	assert.equal(result.rates.has(b), false, 'higher totals with new handles still reset');
	result = tracker.update(sample([[a, 400, 250, '[1,2]']]), 15000);
	assert.equal(result.rates.get(a).down, 20, 'removing b leaves a intact');
	assert.equal(tracker.update(null, 20000), null);
	assert.equal(tracker.update(sample([[a, 1000, 1000, '[1,2]']]), 80000).rates.size, 0, 'failure recovery needs fresh baseline');
});

test('early reads do not move the device-speed baseline or invent short-window spikes', () => {
	const tracker = new (load().DeviceRates)();
	const sample = (n) => ({ interval: 30, columns: ['mac', 'rx_bytes', 'tx_bytes'], data: [['00:11:22:33:44:55', n, n]] });
	tracker.update(sample(0), 0);
	assert.equal(tracker.update(sample(100), 5000).rates.size, 0);
	assert.equal(tracker.update(sample(300), 30000).rates.get('00:11:22:33:44:55').down, 10);
});

test('language matching maps LuCI codes to the installed catalogue', () => {
	const C = load();
	const options = [{ code: 'en' }, { code: 'zh_cn' }, { code: 'zh_tw' }, { code: 'pt_br' }];
	assert.equal(C.matchLanguage(options, 'zh-Hans').code, 'zh_cn');
	assert.equal(C.matchLanguage(options, 'zh_Hant').code, 'zh_tw');
	assert.equal(C.matchLanguage(options, 'pt-BR').code, 'pt_br');
	assert.equal(C.matchLanguage(options, 'de').code, 'en');
});

test('ARP parsing keeps complete LAN entries only', () => {
	const C = load();
	const arp = [
		'IP address       HW type     Flags       HW address            Mask     Device',
		'192.168.1.5      0x1         0x2         00:11:32:aa:bb:cc     *        br-lan',
		'192.168.1.9      0x1         0x0         00:00:00:00:00:00     *        br-lan',
		'192.168.1.7      0x1         0x6         AA:BB:CC:00:11:22     *        br-lan',
		'100.64.0.1       0x1         0x2         00:00:5e:00:01:01     *        pppoe-wan'
	].join('\n');
	assert.deepEqual(Array.from(C.parseArp(arp, ['br-lan']), (n) => n.ip), ['192.168.1.5', '192.168.1.7']);
	assert.equal(C.parseArp(arp, null).length, 3);
	assert.equal(C.parseArp(arp, ['br-lan'])[1].mac, 'aa:bb:cc:00:11:22');
});

test('LAN devices exclude non-static uplinks but keep a dumb AP\'s static LAN', () => {
	const C = load();
	const ifs = [
		{ interface: 'lan', up: true, proto: 'static', device: 'br-lan', l3_device: 'br-lan', route: [{ target: '0.0.0.0', mask: 0 }] },
		{ interface: 'wan', up: true, proto: 'pppoe', device: 'eth1', l3_device: 'pppoe-wan', route: [{ target: '0.0.0.0', mask: 0 }] },
		{ interface: 'guest', up: false, proto: 'static', device: 'br-guest' },
		{ interface: 'loopback', up: true, proto: 'static', device: 'lo' }
	];
	assert.deepEqual(Array.from(C.lanDevices(ifs)), ['br-lan']);
	assert.equal(C.lanDevices(null), null);
});

test('DHCP-disabled side routers discover ARP clients even when LAN obtains its address by DHCP', () => {
	const C = load();
	const arp = 'IP address HW type Flags HW address Mask Device\n192.168.1.20 0x1 0x2 00:11:32:aa:bb:cc * br-lan';
	for (const proto of ['static', 'dhcp']) {
		const ifs = [
			{ interface: 'lan', up: true, proto, device: 'br-lan', route: [{ target: '0.0.0.0', mask: 0, nexthop: '192.168.1.1' }] },
			{ interface: 'guest', up: true, proto: 'static', device: 'br-guest' }
		];
		for (const leases of [[], null]) {
			const list = C.mergeDevices({ leases, arp: C.parseArp(arp, C.lanDevices(ifs), ifs) });
			assert.equal(list.length, 1, proto + ': empty or unavailable local DHCP must not hide ARP clients');
			assert.equal(list[0].ipaddr, '192.168.1.20');
			assert.equal(list[0].lease, false);
		}
	}
});

test('separate static and dynamic uplinks, including aliases, are not client networks', () => {
	const C = load();
	for (const proto of ['static', 'dhcp', 'pppoe']) {
		const ifs = [
			{ interface: 'lan', up: true, proto: 'static', device: 'br-lan' },
			{ interface: 'internet', up: true, proto, device: 'eth1', l3_device: 'eth1', route: [{ target: '0.0.0.0', mask: 0 }] },
			{ interface: 'internet6', up: true, proto: 'dhcpv6', device: 'eth1', l3_device: 'eth1', route: [] },
			{ interface: 'guest', up: true, proto: 'static', device: 'br-guest' }
		];
		assert.deepEqual(Array.from(C.lanDevices(ifs)), ['br-lan', 'br-guest'], proto);
	}
	assert.deepEqual(Array.from(C.lanDevices([
		{ interface: 'lan', up: false, device: 'br-lan' },
		{ interface: 'wan', up: true, proto: 'dhcp', device: 'eth1', route: [{ target: '0.0.0.0', mask: 0 }] }
	])), [], 'a disconnected LAN must not cause WAN neighbours to appear');
});

test('a single custom client link with IPv6 aliases remains discoverable', () => {
	const C = load();
	assert.deepEqual(Array.from(C.lanDevices([
		{ interface: 'home', up: true, proto: 'dhcp', device: 'br-home', l3_device: 'br-home', route: [{ target: '0.0.0.0', mask: 0 }] },
		{ interface: 'home6', up: true, proto: 'dhcpv6', device: 'br-home', l3_device: 'br-home', route: [{ target: '::', mask: 0 }] },
		{ interface: 'loopback', up: true, proto: 'static', device: 'lo' }
	])), ['br-home']);
});

test('custom side-router links are not discarded merely because a guest network exists', () => {
	const C = load();
	for (const proto of ['static', 'dhcp']) {
		assert.deepEqual(Array.from(C.lanDevices([
			{ interface: 'home', up: true, proto, device: 'br-home', route: [{ target: '0.0.0.0', mask: 0 }] },
			{ interface: 'guest', up: true, proto: 'static', device: 'br-guest' }
		])), ['br-home', 'br-guest']);
	}
});

test('gateways are identified on their own interface and retained as discovered devices', () => {
	const C = load();
	const ifs = [{ interface: 'lan', up: true, proto: 'static', device: 'br-lan', route: [
		{ target: '0.0.0.0', mask: 0, nexthop: '192.168.1.1' },
		{ target: '10.0.0.0', mask: 8, nexthop: '192.168.1.2' }
	] }];
	const arp = C.parseArp([
		'IP address HW type Flags HW address Mask Device',
		'192.168.1.1 0x1 0x2 00:11:32:aa:bb:01 * br-lan',
		'192.168.1.1 0x1 0x2 00:11:32:aa:bb:02 * br-guest',
		'192.168.1.2 0x1 0x2 00:11:32:aa:bb:03 * br-lan'
	].join('\n'), null, ifs);
	const list = C.mergeDevices({ arp, leases: [{ macaddr: '00:11:32:aa:bb:01', ipaddr: '192.168.1.1' }] });
	assert.equal(list.length, 3);
	assert.deepEqual(Array.from(list, (d) => d.gateway), [true, false, false]);
});

test('traffic picker lists interfaces plus physical ports such as an xPON uplink', () => {
	const C = load();
	/* xPON router: internet and IPTV are PPPoE sessions on VLANs of pon0 */
	const ifs = [
		{ interface: 'lan', up: true, device: 'br-lan', l3_device: 'br-lan' },
		{ interface: 'wan', up: true, device: 'pon0.41', l3_device: 'pppoe-wan' },
		{ interface: 'wan6', up: true, device: 'pppoe-wan', l3_device: 'pppoe-wan' },
		{ interface: 'IPTV', up: true, device: 'pon0mac0.42', l3_device: 'pppoe-IPTV' },
		{ interface: 'guest', up: false, device: 'br-guest' },
		{ interface: 'loopback', up: true, device: 'lo', l3_device: 'lo' }
	];
	const dev = (up, extra) => Object.assign({ flags: { up: up } }, extra);
	const netdevs = {
		lo: dev(true, { flags: { up: true, loopback: true } }), 'br-lan': dev(true), 'pppoe-wan': dev(true), 'pppoe-IPTV': dev(true),
		pon0: dev(true), 'pon0.41': dev(true), pon0mac0: dev(true), 'pon0mac0.42': dev(true), omci0: dev(true),
		lan1: dev(true), lan10: dev(true), lan2: dev(false), eth0: { up: true }, sit0: dev(false), ifb0: dev(true), gre0: dev(true)
	};
	const plain = (x) => JSON.parse(JSON.stringify(x));
	const src = plain(C.trafficSources(ifs, netdevs));
	assert.deepEqual(src.ifaces.map((g) => [g.dev, g.alt, g.names.join('/')]),
		[['br-lan', 'br-lan', 'LAN'], ['pppoe-wan', 'pon0.41', 'WAN/WAN6'], ['pppoe-IPTV', 'pon0mac0.42', 'IPTV']]);
	assert.deepEqual(src.devices.map((d) => d.dev), ['eth0', 'lan1', 'lan10', 'omci0', 'pon0', 'pon0.41', 'pon0mac0', 'pon0mac0.42']);
	/* no device list (old provider, failed call): interfaces only */
	assert.deepEqual(plain(C.trafficSources(ifs, null).devices), []);
	assert.deepEqual(plain(C.trafficSources(null, netdevs).ifaces), []);
});

test('devices merge leases, Wi-Fi stations, ARP and host hints by MAC', () => {
	const C = load();
	const list = C.mergeDevices({
		leases: [
			{ hostname: 'phone', ipaddr: '192.168.1.23', macaddr: 'A6:83:E7:2C:91:0F', expires: 3600 },
			{ hostname: 'laptop', ipaddr: '192.168.1.3', macaddr: 'f0:ee:7a:91:aa:12', expires: false }
		],
		leases6: [{ hostname: 'laptop', ip6addrs: ['fd00::3/128'] }],
		stations: [{ ifname: 'phy1-ap0', mac: 'a6:83:e7:2c:91:0f', signal: -48 }, { ifname: 'phy0-ap0', mac: '11:22:33:44:55:66', signal: 0 }],
		arp: [{ ip: '192.168.1.5', mac: '00:11:32:aa:bb:cc' }, { ip: '192.168.1.3', mac: 'f0:ee:7a:91:aa:12' }],
		hints: { '00:11:32:AA:BB:CC': { name: 'nas', ipaddrs: ['192.168.1.5'] } },
		bands: { 'phy1-ap0': '5 GHz', 'phy0-ap0': '2.4 GHz' }
	});
	const by = Object.fromEntries(list.map((d) => [d.macaddr, d]));
	assert.equal(list.length, 4);
	assert.deepEqual(Array.from(list, (d) => d.ipaddr), ['192.168.1.3', '192.168.1.5', '192.168.1.23', '']);
	assert.deepEqual({ ...by['a6:83:e7:2c:91:0f'].wifi }, { band: '5 GHz', signal: -48 });
	assert.equal(by['f0:ee:7a:91:aa:12'].ip6addr, 'fd00::3');
	assert.equal(by['f0:ee:7a:91:aa:12'].active, true);
	assert.equal(by['00:11:32:aa:bb:cc'].hostname, 'nas');
	assert.equal(by['00:11:32:aa:bb:cc'].lease, false);
	assert.equal(by['11:22:33:44:55:66'].wifi.signal, null);
	assert.deepEqual(Array.from(C.mergeDevices({ leases: [{ macaddr: 'bad' }] })), []);
});

test('devices discard placeholder and IP-only hostnames and avoid false DHCPv6 merges', () => {
	const C = load();
	const list = C.mergeDevices({
		leases: [
			{ hostname: '10.0.0.194', ipaddr: '10.0.0.194', macaddr: '02:11:22:33:44:55', expires: 3600 },
			{ hostname: '*', ipaddr: '10.0.0.195', macaddr: '02:11:22:33:44:56', expires: 3600 },
			{ hostname: '-', ipaddr: '10.0.0.196', macaddr: '02:11:22:33:44:57', expires: 3600 }
		],
		leases6: [
			{ hostname: '*', ip6addrs: ['fd00::99/128'] },
			{ hostname: '10.0.0.194', ip6addrs: ['fd00::94/128'] }
		],
		hints: {
			'02:11:22:33:44:56': { name: 'LivingRoom' },
			'02:11:22:33:44:57': { name: '10.0.0.196' }
		}
	});
	const by = Object.fromEntries(list.map((d) => [d.macaddr, d]));
	assert.equal(by['02:11:22:33:44:55'].hostname, '');
	assert.equal(by['02:11:22:33:44:55'].ip6addr, '', 'IP-only hostname must not merge unrelated DHCPv6 lease');
	assert.equal(by['02:11:22:33:44:56'].hostname, 'LivingRoom', 'placeholder "*" must not shadow a real host hint');
	assert.equal(by['02:11:22:33:44:56'].ip6addr, '', 'placeholder "*" must not merge unrelated DHCPv6 lease');
	assert.equal(by['02:11:22:33:44:57'].hostname, '', 'IP-only host hint is discarded');
});

test('IPv6-only leases are known devices without claiming an ARP or Wi-Fi observation', () => {
	const C = load();
	const list = C.mergeDevices({ leases6: [
		{ hostname: 'ipv6-client', macaddr: '00:11:32:aa:bb:cc', ip6addrs: ['fd00::20/128'], expires: 3600 }
	] });
	assert.equal(list.length, 1);
	assert.equal(list[0].ip6addr, 'fd00::20');
	assert.equal(list[0].lease, true);
	assert.equal(list[0].expires, 3600);
	assert.equal(list[0].active, false);
});

test('IPv6 uplink address ignores link-local and needs a default route', () => {
	const C = load();
	assert.equal(C.wanIPv6([{ interface: 'lan', up: true, 'ipv6-address': [{ address: 'fd00::1', mask: 60 }], route: [] }]), null);
	const v6 = C.wanIPv6([{ interface: 'wan6', up: true, route: [{ target: '::', mask: 0 }],
		'ipv6-address': [{ address: 'fe80::1', mask: 64 }, { address: '240e:3a1::1', mask: 64 }] }]);
	assert.deepEqual({ ...v6 }, { address: '240e:3a1::1', mask: 64, iface: 'wan6' });
	const pd = C.wanIPv6([{ interface: 'wan6', up: true, route: [{ target: '::', mask: 0 }], 'ipv6-prefix': [{ address: '2001:db8:1::', mask: 56 }] }]);
	assert.equal(pd.address, '2001:db8:1::');
});

test('brand identification by hostname, OUI and randomised MAC', () => {
	const C = load();
	vm.runInNewContext(brands, { window: { Carbon: C } });
	assert.ok(C.BRAND_DATA);
	assert.equal(C.identify('iPhone-15', '').brand.n, 'Apple');
	assert.equal(C.identify('', 'f0:ee:7a:66:0b:3e').brand.n, 'Apple');
	assert.equal(C.identify('', 'de:ad:be:ef:12:34').priv, true);
	assert.equal(C.identify('', 'de:ad:be:ef:12:34').brand, null);
});

test('Docker uses the whale icon and its pages get their own icons', () => {
	const C = load();
	assert.equal(C.pageIcon('dockerman'), 'docker');
	assert.equal(C.pageIcon('docker'), 'docker');
	assert.deepEqual(['config', 'overview', 'containers', 'images', 'networks', 'volumes', 'events'].map((n) => C.pageIcon(n, 'docker')),
		['sliders', 'gauge', 'box', 'layers', 'nodes', 'disk', 'pulse']);
	/* the same names elsewhere keep the general rules */
	assert.equal(C.pageIcon('overview', 'status'), 'gauge');
	assert.equal(C.pageIcon('images', 'services'), 'dot');
	assert.equal(C.pageIcon('podman-containers'), 'box');
	assert.match(C.icon('docker'), /<rect /);
	assert.notEqual(C.icon('nodes'), C.icon('nonexistent'));
});

test('FlowCone, HONK and irqbalance reuse existing semantic sidebar icons', () => {
	const C = load();
	assert.equal(C.pageIcon('flowcone', 'network'), 'zap');
	assert.equal(C.pageIcon('honk', 'services'), 'send');
	assert.equal(C.pageIcon('irqbalance', 'services'), 'cpu');
	for (const name of ['zap', 'send', 'cpu'])
		assert.notEqual(C.icon(name), C.icon('nonexistent'));
});

test('dashboard layout defaults, UCI serialization and attribute round-trip', () => {
	const C = load();
	const L = C.dashboardLayout;
	const plain = (x) => JSON.parse(JSON.stringify(x));
	const def = plain(L.defaultLayout());
	assert.deepEqual(def, {
		hero: true,
		sections: ['monitor', 'tiles', 'details'],
		monitor: [{ type: 'traffic', source: 'auto' }, { type: 'resources' }],
		tiles: ['devices', 'connections', 'load', 'uptime'],
		details: ['clients', 'wireless', 'interfaces']
	});
	assert.equal(L.isDefault(def), true);
	assert.equal(L.matchPreset(def), 'default');

	const uci = plain(L.serialize(def));
	assert.deepEqual(uci, {
		hero: '1',
		sections: 'monitor tiles details',
		monitor: 'traffic:auto resources',
		tiles: 'devices connections load uptime',
		details: 'clients wireless interfaces'
	});
	assert.deepEqual(plain(L.normalize(uci)), def);

	const custom = L.normalize({
		hero: '0',
		sections: 'tiles monitor details',
		monitor: 'traffic:pppoe-wan traffic:br-lan resources',
		tiles: 'wifi temp',
		details: 'none'
	});
	assert.equal(L.isDefault(custom), false);
	assert.deepEqual(plain(custom), {
		hero: false,
		sections: ['tiles', 'monitor', 'details'],
		monitor: [
			{ type: 'traffic', source: 'pppoe-wan' },
			{ type: 'traffic', source: 'br-lan' },
			{ type: 'resources' }
		],
		tiles: ['wifi', 'temp'],
		details: []
	});
	assert.equal(L.serialize(custom).details, 'none');
	const attr = L.encodeAttr(custom);
	assert.deepEqual(plain(L.parseAttr(attr)), plain(custom));
});

test('dashboard layout normalization enforces bounds, deduplication and non-empty invariant', () => {
	const C = load();
	const L = C.dashboardLayout;
	const plain = (x) => JSON.parse(JSON.stringify(x));

	// Duplicate items, invalid names, >4 traffic panels, missing sections, unsafe device names
	const cleaned = plain(L.normalize({
		hero: '1',
		sections: 'details bogus details',
		monitor: 'traffic:auto traffic:bad/dev traffic:eth0:0 traffic:pon0.41 traffic:br-lan traffic:eth2 resources resources',
		tiles: 'wifi bogus wifi temp',
		details: 'interfaces bogus interfaces'
	}));
	assert.deepEqual(cleaned.sections, ['details', 'monitor', 'tiles']);
	assert.deepEqual(cleaned.monitor, [
		{ type: 'traffic', source: 'auto' },
		{ type: 'traffic', source: 'auto' },
		{ type: 'traffic', source: 'eth0:0' },
		{ type: 'traffic', source: 'pon0.41' },
		{ type: 'resources' }
	]);
	assert.deepEqual(cleaned.tiles, ['wifi', 'temp']);
	assert.deepEqual(cleaned.details, ['interfaces']);

	// Completely empty layout falls back to default
	assert.deepEqual(plain(L.normalize({ hero: '0', sections: 'monitor tiles details', monitor: 'none', tiles: 'none', details: 'none' })),
		plain(L.defaultLayout()));

	// Legacy carbon.traffic seeds the default layout when no custom layout exists
	const seeded = plain(L.defaultLayout('pon0'));
	assert.equal(seeded.monitor[0].source, 'pon0');
	assert.equal(L.isDefault(seeded), false);

	// Presets match structurally even when traffic sources differ
	const presets = L.presets();
	assert.deepEqual(Array.from(presets, (p) => p.id), ['default', 'wifi', 'multi']);
	const multi = plain(presets.find((p) => p.id === 'multi').layout);
	multi.monitor[1].source = 'wg0';
	assert.equal(L.matchPreset(multi), 'multi');
});

test('dashboard auto-span packing guarantees balanced 12-column rows on desktop and mobile', () => {
	const C = load();
	const L = C.dashboardLayout;
	const plain = (x) => JSON.parse(JSON.stringify(x));
	const T = { type: 'traffic', source: 'auto' }, R = { type: 'resources' };

	assert.deepEqual(plain(L.monitorSpans([T, R])), [8, 4]);
	assert.deepEqual(plain(L.monitorSpans([R, T])), [4, 8]);
	assert.deepEqual(plain(L.monitorSpans([T, T])), [6, 6]);
	assert.deepEqual(plain(L.monitorSpans([T, T, R])), [6, 6, 12]);
	assert.deepEqual(plain(L.monitorSpans([R, T, T])), [4, 8, 12]);
	assert.deepEqual(plain(L.monitorSpans([T, R, T])), [8, 4, 12]);
	assert.deepEqual(plain(L.monitorSpans([T, T, T, R])), [6, 6, 8, 4]);
	assert.deepEqual(plain(L.monitorSpans([T, T, T, T, R])), [6, 6, 6, 6, 12]);
	assert.deepEqual(plain(L.monitorSpans([T])), [12]);
	assert.deepEqual(plain(L.monitorSpans([R])), [12]);

	assert.deepEqual(plain(L.tileSpans(0)), []);
	assert.deepEqual(plain(L.tileSpans(1)), [12]);
	assert.deepEqual(plain(L.tileSpans(2)), [6, 6]);
	assert.deepEqual(plain(L.tileSpans(3)), [4, 4, 4]);
	assert.deepEqual(plain(L.tileSpans(4)), [3, 3, 3, 3]);
	assert.deepEqual(plain(L.tileSpans(5)), [4, 4, 4, 6, 6]);
	assert.deepEqual(plain(L.tileSpans(6)), [4, 4, 4, 4, 4, 4]);

	assert.deepEqual(plain(L.detailSpans(['clients', 'wireless', 'interfaces'])), [12, 6, 6]);
	assert.deepEqual(plain(L.detailSpans(['clients', 'interfaces'])), [12, 12]);
	assert.deepEqual(plain(L.detailSpans(['wireless', 'interfaces', 'clients'])), [6, 6, 12]);
	assert.deepEqual(plain(L.detailSpans(['wireless', 'clients', 'interfaces'])), [12, 12, 12]);
	assert.deepEqual(plain(L.detailSpans(['wireless', 'interfaces'])), [6, 6]);
	assert.deepEqual(plain(L.detailSpans(['interfaces'])), [12]);
});

test('inline hero logo stays in sync with logo.svg and uses unique defs IDs per render', () => {
	const C = load();
	const first = C.logo();
	const second = C.logo();
	const file = fs.readFileSync('htdocs/luci-static/carbon/logo.svg', 'utf8').trim();
	const ids = (svg) => [...svg.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]);
	const refs = (svg) => [...svg.matchAll(/\burl\(#([^)]+)\)/g)].map((m) => m[1]);
	const normalize = (svg) => svg
		.replace(/^<svg\b[^>]*>/, '<svg>')
		.replace(/\bcb-(?:logo|h\d+)-/g, 'cb-x-');

	assert.ok(ids(first).length > 0, 'logo defines gradients/clipPaths');
	for (const ref of refs(first)) assert.ok(ids(first).includes(ref), `unresolved ref ${ref}`);
	assert.equal(new Set(ids(first)).size, ids(first).length, 'no duplicate IDs within one logo');
	for (const id of ids(first)) assert.ok(!ids(second).includes(id), `reused ID ${id} across renders`);
	assert.equal(normalize(first), normalize(file), 'inline hero logo matches logo.svg geometry');
});

test('loadStatus classifies 1-minute load relative to CPU core count', () => {
	const C = load();
	const plain = (x) => JSON.parse(JSON.stringify(x));
	assert.deepEqual(plain(C.loadStatus(0.0, 4)), { level: 'ok', label: 'Normal' });
	assert.deepEqual(plain(C.loadStatus(2.79, 4)), { level: 'ok', label: 'Normal' });
	assert.deepEqual(plain(C.loadStatus(2.8, 4)), { level: 'warn', label: 'Busy' });
	assert.deepEqual(plain(C.loadStatus(3.99, 4)), { level: 'warn', label: 'Busy' });
	assert.deepEqual(plain(C.loadStatus(4.0, 4)), { level: 'bad', label: 'High' });
	assert.deepEqual(plain(C.loadStatus(0.69, 1)), { level: 'ok', label: 'Normal' });
	assert.deepEqual(plain(C.loadStatus(0.7, 1)), { level: 'warn', label: 'Busy' });
	assert.deepEqual(plain(C.loadStatus(1.0, 1)), { level: 'bad', label: 'High' });
	assert.equal(C.loadStatus(0.5, 0), null, 'unknown cores must not guess a single core');
	assert.equal(C.loadStatus(0.5, null), null);
	assert.equal(C.loadStatus(-0.1, 4), null);
	assert.equal(C.loadStatus(NaN, 4), null);
});

test('wirelessSummary computes per-SSID band, bandwidth, encryption and deduplicated client counts', () => {
	const C = load();
	const plain = (x) => JSON.parse(JSON.stringify(x));
	const wireless = {
		radio0: {
			up: true,
			config: { band: '2g', channel: '6', htmode: 'HE40' },
			interfaces: [
				{ ifname: 'phy0-ap0', config: { mode: 'ap', ssid: 'Home', encryption: 'psk2+ccmp' } },
				{ ifname: 'phy0-ap1', config: { mode: 'ap', ssid: 'Guest', encryption: 'psk-mixed', disabled: true } },
				{ ifname: 'phy0-sta0', config: { mode: 'sta', ssid: 'Uplink' } }
			]
		},
		radio1: {
			up: true,
			config: { band: '5g', channel: '149', htmode: 'HE160' },
			interfaces: [
				{ ifname: 'phy1-ap0', config: { mode: 'ap', ssid: 'Home', encryption: 'sae-mixed' } },
				{ ifname: 'phy1-ap1', config: { mode: 'ap', ssid: '', encryption: 'owe' } }
			]
		},
		radio2: {
			up: true,
			config: { channel: '36', htmode: 'VHT80' },
			interfaces: [
				{ ifname: 'phy2-ap0', config: { mode: 'ap', ssid: 'Fallback5G', encryption: 'none' } }
			]
		}
	};
	const stations = [
		{ ifname: 'phy0-ap0', mac: 'AA:11:22:33:44:55' },
		{ ifname: 'phy0-ap0', mac: 'aa:11:22:33:44:55' },
		{ ifname: 'phy0-ap0', mac: '00:00:00:00:00:00' },
		{ ifname: 'phy1-ap0', mac: 'bb:11:22:33:44:55' },
		{ ifname: 'phy1-ap0', mac: 'cc:11:22:33:44:55' }
	];
	const res = plain(C.wirelessSummary(wireless, stations));
	assert.equal(res.totalClients, 3);
	assert.equal(res.rows.length, 5, 'non-AP sta interface excluded; dual-band same SSID stays separate');
	assert.deepEqual(res.rows[0], {
		radio: 'radio0', ifname: 'phy0-ap0', ssid: 'Home', hidden: false,
		band: '2.4 GHz', bandKey: '2g', channel: '6', width: '40 MHz', encryption: 'WPA2',
		meta: 'CH 6 · 40 MHz · WPA2', sub: '2.4 GHz · CH 6 · 40 MHz · WPA2', on: true, clients: 1
	});
	assert.equal(res.rows[1].ssid, 'Guest');
	assert.equal(res.rows[1].encryption, 'WPA/WPA2');
	assert.equal(res.rows[1].on, false);
	assert.equal(res.rows[1].clients, null, 'disabled AP does not report a client count');
	assert.equal(res.rows[2].ssid, 'Home');
	assert.equal(res.rows[2].band, '5 GHz');
	assert.equal(res.rows[2].bandKey, '5g');
	assert.equal(res.rows[2].width, '160 MHz');
	assert.equal(res.rows[2].encryption, 'WPA2/WPA3');
	assert.equal(res.rows[2].clients, 2);
	assert.equal(res.rows[3].hidden, true);
	assert.equal(res.rows[3].encryption, 'OWE');
	assert.equal(res.rows[3].clients, 0, 'active AP with no stations reports 0');
	assert.equal(res.rows[4].band, '5 GHz', 'numeric channel fallback infers 5 GHz');
	assert.equal(res.rows[4].meta, 'CH 36 · 80 MHz');
	assert.equal(res.rows[4].clients, 0);

	// Unavailable stations (null) keeps client counts unknown instead of showing false 0
	const unknown = plain(C.wirelessSummary(wireless, null));
	assert.equal(unknown.totalClients, null);
	assert.ok(unknown.rows.every((r) => r.clients === null));

	// OpenWrt HT40+/HT40-/VHT80+80/NOHT widths, case-insensitive band, and active-AP-only totalClients
	const edgeW = {
		radio0: {
			up: true,
			config: { band: '2G', channel: '6', htmode: 'HT40+' },
			interfaces: [
				{ ifname: 'phy0-ap0', config: { mode: 'ap', ssid: 'Plus40', encryption: 'psk2' } },
				{ ifname: 'phy0-ap1', config: { mode: 'ap', ssid: 'DisabledAP', encryption: 'psk2', disabled: true } },
				{ ifname: 'phy0-sta0', config: { mode: 'sta', ssid: 'ClientLink' } }
			]
		},
		radio1: {
			up: true,
			config: { band: '5g', channel: '36', htmode: 'VHT80+80' },
			interfaces: [
				{ ifname: 'phy1-ap0', config: { mode: 'ap', ssid: 'Dual80', encryption: 'sae' } }
			]
		},
		radio2: {
			up: true,
			config: { band: '2g', channel: '11', htmode: 'HT40-' },
			interfaces: [
				{ ifname: 'phy2-ap0', config: { mode: 'ap', ssid: 'Minus40', encryption: 'none' } }
			]
		},
		radio3: {
			up: true,
			config: { band: '2g', channel: '1', htmode: 'NOHT' },
			interfaces: [
				{ ifname: 'phy3-ap0', config: { mode: 'ap', ssid: 'Legacy', encryption: 'none' } }
			]
		}
	};
	const edgeRes = plain(C.wirelessSummary(edgeW, [
		{ ifname: 'phy0-ap0', mac: '11:22:33:44:55:01' },
		{ ifname: 'phy0-ap1', mac: '11:22:33:44:55:02' },
		{ ifname: 'phy0-sta0', mac: '11:22:33:44:55:03' },
		{ ifname: 'stale-if0', mac: '11:22:33:44:55:04' }
	]));
	assert.equal(edgeRes.rows[0].band, '2.4 GHz');
	assert.equal(edgeRes.rows[0].width, '40 MHz');
	assert.equal(edgeRes.rows[2].width, '80+80 MHz');
	assert.equal(edgeRes.rows[3].width, '40 MHz');
	assert.equal(edgeRes.rows[4].width, null);
	assert.equal(edgeRes.totalClients, 1, 'stations on disabled, non-AP or unmatched interfaces do not inflate totalClients');
	assert.equal(C.wirelessSummary(edgeW, []).totalClients, 0, 'empty station list reports 0 total clients');
});

test('simpleMenu validates paths, resolves defaults and opkg/package-manager aliases, normalizes and round-trips attributes', () => {
	const C = load();
	const M = C.simpleMenu;
	const plain = (v) => JSON.parse(JSON.stringify(v));

	for (const ok of ['status/overview', 'system/package-manager', 'services/ssr-plus', 'services/v2rayA', 'status/channel_analysis', 'services/luci.app', 'docker'])
		assert.equal(M.isValidPath(ok), true, ok);
	for (const bad of ['', null, 'none', 'logout', 'logout/sub', '../etc', 'status/..', '.hidden', 'status/.hidden', 'a/b/c', 'a b', 'a;b', 'a/b..c'])
		assert.equal(M.isValidPath(bad), false, String(bad));

	// Default resolves installed paths (24.10 opkg without Wi-Fi vs 25.x package-manager with Wi-Fi)
	const known24 = {
		'admin/status/overview': { path: 'admin/status/overview', title: 'Overview' },
		'admin/network/network': { path: 'admin/network/network', title: 'Interfaces' },
		'admin/system/opkg': { path: 'admin/system/opkg', title: 'Software' },
		'admin/system/carbon-update': { path: 'admin/system/carbon-update', title: 'Carbon Theme Settings' },
		'admin/system/admin': { path: 'admin/system/admin', title: 'Administration' },
		'admin/system/flash': { path: 'admin/system/flash', title: 'Backup / Flash Firmware' },
		'admin/system/reboot': { path: 'admin/system/reboot', title: 'Reboot' }
	};
	const def24 = plain(M.defaultConfig(known24, 'admin'));
	assert.deepEqual(def24, {
		common: ['status/overview', 'network/network'],
		system: ['system/opkg', 'system/carbon-update', 'system/admin', 'system/flash', 'system/reboot']
	});
	assert.equal(M.isDefault(def24, known24, 'admin'), true);
	assert.equal(M.isDefault({ common: ['status/overview'], system: def24.system }, known24, 'admin'), false);

	// Alias resolution: saved system/opkg resolves to system/package-manager after OpenWrt upgrade
	const known25 = Object.assign({}, known24, { 'admin/system/package-manager': { path: 'admin/system/package-manager', title: 'Software' } });
	delete known25['admin/system/opkg'];
	const resolved = M.resolvePath('system/opkg', known25, 'admin');
	assert.equal(resolved.path, 'admin/system/package-manager');
	assert.equal(resolved.builtin.icon, 'box');
	assert.equal(M.resolvePath('services/missing', known25, 'admin'), null);

	// Normalization deduplicates across groups (common wins), strips invalid tokens, enforces 32-item cap, falls back when empty
	const norm = plain(M.normalize({
		common: 'status/overview ../bad status/overview services/openclash logout',
		system: 'services/openclash system/reboot none'
	}));
	assert.deepEqual(norm, {
		common: ['status/overview', 'services/openclash'],
		system: ['system/reboot']
	});

	const many = Array.from({ length: 40 }, (_, i) => 'services/p' + i);
	const capped = M.normalize({ common: many, system: ['system/reboot'] });
	assert.equal(M.count(capped), 32);
	assert.equal(capped.system.length, 0);

	// Per-group 1024-byte cap matches backend UCI validation
	const longPaths = Array.from({ length: 20 }, (_, i) => 'services/' + 'a'.repeat(55) + i);
	const byteCapped = M.normalize({ common: longPaths, system: [] });
	assert.ok(M.serialize(byteCapped).common.length <= M.MAX_BYTES);
	assert.ok(byteCapped.common.length < 20);

	assert.deepEqual(plain(M.normalize({ common: 'none', system: 'none' })), plain(M.defaultConfig()));

	// Serialization & attribute parsing
	const attr = M.encodeAttr({ common: ['status/overview', 'services/openclash'], system: [] });
	assert.equal(attr, 'common=status/overview services/openclash;system=none');
	assert.deepEqual(plain(M.parseAttr(attr)), { common: ['status/overview', 'services/openclash'], system: [] });
	assert.equal(M.parseAttr(''), null);
	assert.equal(M.parseAttr('common=none;system=none'), null);
	assert.equal(M.parseAttr('common=../bad;system=logout'), null);
	assert.equal(M.parseAttr('bogus=status/overview'), null);
});
