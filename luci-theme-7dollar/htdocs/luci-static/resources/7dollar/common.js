'use strict';
'require baseclass';
'require rpc';
'require fs';
'require ui';

/*
 * Shared helpers for the 7Dollar theme: menu grouping, settings storage,
 * formatting and the device list used by the home and devices pages.
 */

const ZH = /^zh/i.test(document.documentElement.getAttribute('lang') || '');
const T = (zh, en) => ZH ? zh : en;
const SPRITE = '/luci-static/7dollar/icons.svg';
const ACTIVE = /\/7dollar$/.test(L.env.media || '');

const callUciGet = rpc.declare({ object: 'uci', method: 'get', params: [ 'config', 'section' ], expect: { values: {} } });
const callUciGetType = rpc.declare({ object: 'uci', method: 'get', params: [ 'config', 'type' ], expect: { values: {} } });
const callUciSet = rpc.declare({ object: 'uci', method: 'set', params: [ 'config', 'section', 'values' ] });
const callUciAdd = rpc.declare({ object: 'uci', method: 'add', params: [ 'config', 'type', 'name', 'values' ] });
const callUciDelete = rpc.declare({ object: 'uci', method: 'delete', params: [ 'config', 'section', 'options' ] });
const callUciCommit = rpc.declare({ object: 'uci', method: 'commit', params: [ 'config' ] });
const callFileRead64 = rpc.declare({ object: 'file', method: 'read', params: [ 'path', 'base64' ], expect: { data: '' } });
const callLeases = rpc.declare({ object: 'luci-rpc', method: 'getDHCPLeases', expect: { '': {} } });
const callHints = rpc.declare({ object: 'luci-rpc', method: 'getHostHints', expect: { '': {} } });
const callWireless = rpc.declare({ object: 'luci-rpc', method: 'getWirelessDevices', expect: { '': {} } });
const callAssoc = rpc.declare({ object: 'iwinfo', method: 'assoclist', params: [ 'device' ], expect: { results: [] } });
const callDevices = rpc.declare({ object: 'luci-rpc', method: 'getNetworkDevices', expect: { '': {} } });
const callIfDump = rpc.declare({ object: 'network.interface', method: 'dump', expect: { interface: [] } });
const callBoard = rpc.declare({ object: 'system', method: 'board' });
const callInfo = rpc.declare({ object: 'system', method: 'info' });
const callServices = rpc.declare({ object: 'service', method: 'list', expect: { '': {} } });
const callMounts = rpc.declare({ object: 'luci', method: 'getMountPoints', expect: { result: [] } });

const DEFAULTS = { palette: 'clay', mode: 'auto', hidden_cards: '', shown_cards: '' };
const OPT_IN = [ 'apps' ];   // cards that are off until switched on (they show plugin information)

const words = s => String(s || '').split(/[\s,]+/).filter(Boolean);

/* Whether a home card is on: normal cards unless hidden, opt-in cards only when shown. */
function cardOn(conf, key) {
	return OPT_IN.indexOf(key) > -1 ? words(conf.shown_cards).indexOf(key) > -1 : words(conf.hidden_cards).indexOf(key) < 0;
}

const PALETTES = [
	[ 'clay',     T('陶土', 'Clay') ],
	[ 'celadon',  T('青瓷', 'Celadon') ],
	[ 'mist',     T('雾蓝', 'Mist') ],
	[ 'dusk',     T('暮紫', 'Dusk') ],
	[ 'graphite', T('石墨', 'Graphite') ]
];

/* Menu regrouping: native LuCI pages -> seven plain-language sections. `pages` are the everyday
 * ones, shown as pills; `more` and anything matched by `prefix` sit behind the group's "More" pill.
 * Plugins also put themselves under System or Status (other themes' settings, file transfer, disk
 * tools ...); those are apps. So System's prefixes only take LuCI's own pages, told apart by the
 * view they open (`own`), which also covers native pages added in newer LuCI versions. */
const GROUPS = [
	{ id: 'home', icon: 'home', label: T('总览', 'Overview'), pages: [ 'admin/home' ] },
	{ id: 'devices', icon: 'devices', label: T('设备', 'Devices'), pages: [ 'admin/clients' ] },
	{ id: 'wifi', icon: 'wifi', label: 'Wi‑Fi', pages: [ 'admin/network/wireless', 'admin/status/channel_analysis' ] },
	{ id: 'internet', icon: 'globe', label: T('上网', 'Internet'),
	  pages: [ 'admin/network/network', 'admin/network/dhcp', 'admin/network/dns', 'admin/network/diagnostics' ],
	  more: [ 'admin/network/routes', 'admin/status/routes', 'admin/status/routesj', 'admin/network/switch' ],
	  prefix: [ 'admin/network' ] },
	{ id: 'security', icon: 'shield', label: T('安全', 'Security'), mob: false,
	  pages: [ 'admin/network/firewall', 'admin/status/nftables', 'admin/status/iptables', 'admin/system/admin' ] },
	{ id: 'apps', icon: 'grid', label: T('应用', 'Apps'), mob: false, pages: [ 'admin/apps' ],
	  prefix: [ 'admin/services', 'admin/vpn', 'admin/nas', 'admin/docker', 'admin/statistics' ] },
	{ id: 'system', icon: 'gear', label: T('系统', 'System'), short: T('更多', 'More'),
	  pages: [ 'admin/system/system', 'admin/system/appearance', 'admin/status/overview', 'admin/status/logs',
	           'admin/system/package-manager', 'admin/system/opkg', 'admin/system/flash', 'admin/system/reboot' ],
	  more: [ 'admin/dashboard', 'admin/status/realtime', 'admin/system/crontab', 'admin/system/startup', 'admin/status/processes', 'admin/system/mounts',
	          'admin/system/leds', 'admin/status/syslog', 'admin/status/dmesg', 'admin/status/dashboard' ],
	  prefix: [ 'admin/system', 'admin/status' ], own: true }
];

/* A page LuCI itself ships: it opens one of LuCI's status/system views, or points into them.
 * (The patterns sit in constants: the buildroot's jsmin misreads a regex that follows `return`.) */
const OWN_VIEW = /^(status|system|admin_status)\//, OWN_ALIAS = /^admin\/(status|system)\//;

function own(node) {
	const a = (node && node.action) || {}, path = a.path || '';
	return OWN_VIEW.test(path) || (a.type == 'alias' && OWN_ALIAS.test(path));
}

const LABELS = {
	'admin/home': T('总览', 'Overview'),
	'admin/dashboard': T('仪表盘', 'Dashboard'),
	'admin/clients': T('设备', 'Devices'),
	'admin/apps': T('全部应用', 'All apps'),
	'admin/network/wireless': T('无线网络', 'Wireless'),
	'admin/status/channel_analysis': T('信道分析', 'Channel analysis'),
	'admin/network/network': T('网络接口', 'Interfaces'),
	'admin/network/diagnostics': T('网络诊断', 'Diagnostics'),
	'admin/network/routes': T('静态路由', 'Static routes'),
	'admin/status/routes': T('路由表', 'Routing table'),
	'admin/status/routesj': T('路由表', 'Routing table'),
	'admin/network/switch': T('交换机', 'Switch'),
	'admin/network/firewall': T('防火墙', 'Firewall'),
	'admin/status/nftables': T('防火墙规则', 'Firewall status'),
	'admin/status/iptables': T('防火墙规则', 'Firewall status'),
	'admin/system/admin': T('管理员', 'Administration'),
	'admin/system/system': T('通用', 'General'),
	'admin/system/appearance': T('外观与首页', 'Appearance'),
	'admin/status/overview': T('运行状态', 'Status'),
	'admin/status/realtime': T('实时监控', 'Realtime'),
	'admin/status/logs': T('日志', 'Logs'),
	'admin/status/processes': T('进程', 'Processes'),
	'admin/system/package-manager': T('软件包', 'Software'),
	'admin/system/opkg': T('软件包', 'Software'),
	'admin/system/flash': T('备份与升级', 'Backup & upgrade'),
	'admin/system/startup': T('启动项', 'Startup'),
	'admin/system/crontab': T('计划任务', 'Scheduled tasks'),
	'admin/system/mounts': T('挂载点', 'Mount points'),
	'admin/system/leds': T('指示灯', 'LEDs'),
	'admin/system/reboot': T('重启', 'Reboot'),
	'admin/services/openclash': 'OpenClash',
	'admin/services/ksmbd': T('文件共享', 'File sharing')
};

const APP_ICONS = [
	[ /clash|passwall|homeproxy|ssr|v2ray|xray|sing|mihomo|proxy|nikki|daed/i, 'route' ],
	[ /smb|samba|ksmbd|nfs|ftp|disk|share|alist|aria|transmission|qbit|minidlna/i, 'folder' ],
	[ /vpn|wireguard|openvpn|zerotier|tailscale|frp|ipsec/i, 'vpn' ],
	[ /ddns|dns|adguard|mosdns|smartdns/i, 'globe' ],
	[ /docker|dockerman/i, 'box' ],
	[ /stat|nlbw|bandwidth|netdata/i, 'pulse' ],
	[ /upnp|qos|sqm|eqos/i, 'sliders' ],
	[ /wol|wake/i, 'power' ],
	[ /cron|sched|time/i, 'clock' ]
];

function esc(s) {
	return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function icon(id, cls) {
	return `<svg class="i${cls ? ' ' + cls : ''}" aria-hidden="true"><use href="${SPRITE}#${id}"></use></svg>`;
}

function html(s) {
	const t = document.createElement('template');
	t.innerHTML = s.trim();
	return t.content.childNodes.length == 1 ? t.content.firstChild : t.content;
}

function title(path, node) {
	if (LABELS[path])
		return LABELS[path];
	return node && node.title ? _(node.title) : path.split('/').pop();
}

/* ui.menu.getChildren() replaces alias nodes (e.g. Firewall → Zones) with a copy of
 * their target, which drops the alias's own sub-pages. Always keep the real node. */
function realNode(parent, child) {
	return (parent.children && parent.children[child.name]) || child;
}

/* True if the menu has this page. LuCI only lists pages whose dependencies are met, so this
 * doubles as a free feature check (e.g. Wireless needs a wifi-device, OpenClash needs the app). */
function menuHas(tree, path) {
	let n = tree;
	for (const k of ('admin/' + path).split('/')) n = n && n.children && n.children[k];
	return !!n;
}

/* The software page: package-manager since 24.10, opkg on 23.05; null when neither app is installed. */
function software(tree) {
	return [ 'system/package-manager', 'system/opkg' ].find(p => menuHas(tree, p)) || null;
}

let menuPromise;

/* A menu cached before switching themes can omit our home page. Refresh it once and share the
 * result between navigation and views; never invent entries that the server did not authorize. */
function loadMenu() {
	if (!menuPromise)
		menuPromise = ui.menu.load().then(tree => {
			const home = tree && tree.children && tree.children.admin && tree.children.admin.children && tree.children.admin.children.home;
			if (!ACTIVE || (home && home.satisfied && home.action && home.action.path == '7dollar/home'))
				return tree;

			ui.menu.flushCache();
			ui.menu.menu = null;
			return ui.menu.load();
		});

	return menuPromise;
}

function flatten(tree) {
	/* Returns [{ path, node, title, group }] for every navigable page. */
	const admin = tree && tree.children && tree.children.admin;
	const out = [];

	if (!admin)
		return out;

	ui.menu.getChildren(admin).forEach(t => {
		const top = realNode(admin, t);

		if (top.name == 'logout')
			return;

		const tpath = 'admin/' + top.name;
		const kids = ui.menu.getChildren(top);

		if (!kids.length)
			out.push({ path: tpath, node: top });
		else
			kids.forEach(k => out.push({ path: tpath + '/' + k.name, node: realNode(top, k) }));
	});

	out.forEach(p => {
		p.title = title(p.path, p.node);
		p.group = groupOf(p.path, p.node);
	});

	return out;
}

function groupOf(path, node) {
	for (const g of GROUPS)
		if (g.pages.concat(g.more || []).indexOf(path) > -1)
			return g.id;

	for (const g of GROUPS)
		for (const pre of (g.prefix || []))
			if ((path == pre || path.indexOf(pre + '/') == 0) && (!g.own || own(node)))
				return g.id;

	return 'apps';
}

function grouped(pages) {
	return GROUPS.map(g => {
		const order = g.pages.concat(g.more || []), list = pages.filter(p => p.group == g.id);
		list.sort((a, b) => {
			const ia = order.indexOf(a.path), ib = order.indexOf(b.path);
			return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib);
		});
		return Object.assign({}, g, { list: list });
	}).filter(g => g.list.length);
}

function appIcon(path) {
	for (const [ re, id ] of APP_ICONS)
		if (re.test(path))
			return id;
	return 'grid';
}

/* The procd service behind an app page, matched by name (services/openclash ↔ openclash,
 * nas/ksmbd ↔ ksmbd, services/upnp ↔ miniupnpd): { name, running }, or null if none fits. */
function service(services, path) {
	const leaf = path.split('/').pop().toLowerCase().replace(/[^a-z0-9]/g, '');
	const name = Object.keys(services || {}).find(k => {
		const s = k.toLowerCase().replace(/[^a-z0-9]/g, '');
		return s == leaf || (leaf.length > 3 && s.indexOf(leaf) > -1) || (s.length > 3 && leaf.indexOf(s) > -1);
	});
	if (!name) return null;
	const inst = services[name].instances || {};
	return { name: name, running: Object.keys(inst).some(k => inst[k].running) };
}

/* ---------------- settings (stored in /etc/config/7dollar) ---------------- */

function loadSettings() {
	return L.resolveDefault(callUciGet('7dollar', 'main'), {}).then(v => Object.assign({}, DEFAULTS, v || {}));
}

function saveSettings(values) {
	const set = {}, del = [];

	for (const k in values) {
		if (values[k] === '' || values[k] == null)
			del.push(k);
		else
			set[k] = String(values[k]);
	}

	return L.resolveDefault(callUciGet('7dollar', 'main'), null).then(exists => {
		const steps = [];

		if (exists == null || !Object.keys(exists).length)
			steps.push(() => callUciAdd('7dollar', 'theme', 'main', set));
		else if (Object.keys(set).length)
			steps.push(() => callUciSet('7dollar', 'main', set));

		if (del.length)
			steps.push(() => L.resolveDefault(callUciDelete('7dollar', 'main', del), null));

		steps.push(() => callUciCommit('7dollar'));

		return steps.reduce((p, fn) => p.then(fn), Promise.resolve());
	});
}

/* ---------------- motion ---------------- */

/* Durations live in cascade.css (--fast / --base / --slow); scripts read them so CSS and JS move alike. */
const calm = matchMedia('(prefers-reduced-motion: reduce)');
function motion(name) {
	return calm.matches ? 0 : parseFloat(getComputedStyle(document.documentElement).getPropertyValue(`--${name}`)) * 1000 || 0;
}

/* Exits mirror entrances: fade (and sink) out, then go. */
function leave(el) {
	if (el.classList.contains('td-out')) return;
	el.classList.add('td-out');
	setTimeout(() => el.remove(), motion('fast'));
}

function applyLook(s) {
	const r = document.documentElement;
	const dark = s.mode == 'auto' ? matchMedia('(prefers-color-scheme: dark)').matches : s.mode == 'dark';
	const paint = () => {
		r.setAttribute('data-palette', s.palette);
		r.setAttribute('data-mode', s.mode);
		r.setAttribute('data-theme', dark ? 'dark' : 'light');
		r.setAttribute('data-darkmode', dark ? 'true' : 'false');
		document.dispatchEvent(new CustomEvent('td-look', { detail: s }));
	};
	/* one cross-fade of the whole page instead of every colour easing on its own */
	if (document.startViewTransition && motion('base')) document.startViewTransition(paint);
	else paint();
}

let toastTimer;
function toast(msg) {
	let t = document.querySelector('.td-toast:not(.td-out)');
	if (!t) document.body.appendChild(t = E('div', { 'class': 'td-toast', 'role': 'status' }));
	t.textContent = msg;
	clearTimeout(toastTimer);
	toastTimer = setTimeout(() => leave(t), 1800);
}

/* ---------------- formatting ---------------- */

function rate(bytesPerSec) {
	const bits = Math.max(0, bytesPerSec * 8);
	if (bits >= 1e9) return [ (bits / 1e9).toFixed(2), 'Gbps' ];
	if (bits >= 1e6) return [ (bits / 1e6).toFixed(bits >= 1e8 ? 0 : 1), 'Mbps' ];
	if (bits >= 1e3) return [ (bits / 1e3).toFixed(0), 'Kbps' ];
	return [ bits.toFixed(0), 'bps' ];
}

function bytes(n) {
	n = +n || 0;
	if (n >= 1099511627776) return (n / 1099511627776).toFixed(1) + ' TB';
	if (n >= 1073741824) return (n / 1073741824).toFixed(1) + ' GB';
	if (n >= 1048576) return (n / 1048576).toFixed(0) + ' MB';
	if (n >= 1024) return (n / 1024).toFixed(0) + ' KB';
	return n + ' B';
}

function duration(sec) {
	sec = Math.max(0, Math.floor(sec || 0));
	const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
	if (ZH) {
		if (d) return `${d} 天 ${h} 小时`;
		if (h) return `${h} 小时 ${m} 分钟`;
		return `${Math.max(m, 1)} 分钟`;
	}
	if (d) return `${d}d ${h}h`;
	if (h) return `${h}h ${m}m`;
	return `${Math.max(m, 1)}m`;
}

function signal(dbm) {
	if (dbm == null || dbm == 0) return [ T('未知', 'Unknown'), 0 ];
	if (dbm >= -55) return [ T('信号很好', 'Excellent'), 4 ];
	if (dbm >= -65) return [ T('信号良好', 'Good'), 3 ];
	if (dbm >= -75) return [ T('信号一般', 'Fair'), 2 ];
	return [ T('信号较弱', 'Weak'), 1 ];
}

function quality(dbm) {
	if (!dbm) return 0;
	return Math.max(4, Math.min(100, Math.round((dbm + 92) / 50 * 100)));
}

function bandName(b) {
	return ({ '2g': '2.4 GHz', '5g': '5 GHz', '6g': '6 GHz', '60g': '60 GHz' })[b] || b || 'Wi‑Fi';
}

function kind(name) {
	name = name || '';
	if (/watch/i.test(name)) return 'watch';
	if (/ipad|pad|tab|kindle/i.test(name)) return 'tablet';
	if (/book\d*\b|laptop|thinkpad|surface/i.test(name)) return 'laptop';   // MacBook, MateBook, Vivobook, Galaxy Book3
	if (/iphone|pixel|android|phone|oppo|vivo|xiaomi|redmi|huawei|honor|galaxy|oneplus|realme|meizu|nokia|mi-/i.test(name)) return 'phone';
	if (/tv\b|roku|chromecast|fire-?stick|\bshield\b|x?box\b/i.test(name)) return 'tv';
	if (/\b(mac|imac|mini|pc|desktop|win|ubuntu|linux|nas|server)\b/i.test(name)) return 'desktop';
	return 'devices';
}

function pretty(name) {
	if (!name) return '';
	return name.replace(/[-_]+/g, ' ').replace(/\s+/g, ' ').trim();
}

/* ---------------- data ---------------- */

function readFile(path) {
	return L.resolveDefault(fs.read(path), null);
}

/* MACs a bridge has heard from in the last few minutes: its forwarding table forgets a port after
 * 300 s of silence, while an ARP entry can outlive a device by hours. Entries are 16 bytes
 * (6 of MAC) in the binary brforward file. null when none of the devices is a bridge. */
function heard(bridges) {
	return Promise.all(bridges.map(b => L.resolveDefault(callFileRead64(`/sys/class/net/${b}/brforward`, true), null))).then(datas => {
		let macs = null;
		datas.forEach(d => {
			if (d == null) return;
			const bin = atob(d);
			macs = macs || {};
			for (let i = 0; i + 16 <= bin.length; i += 16)
				macs[Array.from(bin.slice(i, i + 6), c => ('0' + c.charCodeAt(0).toString(16)).slice(-2)).join(':').toUpperCase()] = true;
		});
		return macs;
	});
}

/* CPU temperature lives in different places per platform (thermal_zone0 on most SoCs,
 * coretemp/k10temp hwmon on x86). Pick the best sensor once; later reads cost one file. */
const TEMP_PREF = [ /^coretemp/, /^k10temp/, /^zenpower/, /^x86_pkg_temp/, /^cpu[-_]?thermal/, /^soc[-_]?thermal/, /^acpitz/ ];
let tempPath;

function tempSensor() {
	if (tempPath !== undefined)
		return Promise.resolve(tempPath);

	const list = dir => L.resolveDefault(fs.list(dir), []).then(l => l.map(e => dir + '/' + e.name));
	const rank = name => { const i = TEMP_PREF.findIndex(r => r.test(name)); return i < 0 ? TEMP_PREF.length : i };

	return Promise.all([ list('/sys/class/thermal'), list('/sys/class/hwmon') ]).then(([ zones, hwmons ]) => Promise.all([].concat(
		zones.filter(d => /thermal_zone\d+$/.test(d)).map(d => readFile(d + '/type').then(n => ({ name: n, path: d + '/temp' }))),
		hwmons.map(d => readFile(d + '/name').then(n => ({ name: n, path: d + '/temp1_input' })))
	))).then(found => {
		/* Known CPU sensors first, then any thermal zone; never radio/PHY/disk sensors. */
		const cands = found.filter(c => c.name).map(c => ({ path: c.path, r: rank(c.name.trim()) }))
			.filter(c => c.r < TEMP_PREF.length || /thermal_zone/.test(c.path))
			.sort((a, b) => a.r - b.r || (a.path < b.path ? -1 : 1));

		const next = i => i >= cands.length ? null
			: readFile(cands[i].path).then(v => +v > 0 ? cands[i].path : next(i + 1));
		return next(0);
	}).then(p => (tempPath = p));
}

function temperature() {
	return tempSensor().then(p => p ? readFile(p) : null).then(v => +v > 0 ? +v / 1000 : null);
}

function wifiInfo() {
	return L.resolveDefault(callWireless(), {}).then(radios => {
		const aps = [];

		Object.keys(radios || {}).sort().forEach(rname => {
			const r = radios[rname] || {};
			(r.interfaces || []).forEach(i => {
				if ((i.config || {}).mode == 'ap' && i.ifname)
					aps.push({ radio: rname, band: (r.config || {}).band, ifname: i.ifname, ssid: (i.iwinfo || {}).ssid || (i.config || {}).ssid,
					           network: (i.config || {}).network || [], up: !!r.up && !(i.config || {}).disabled });
			});
		});

		return Promise.all(aps.map(ap => ap.up ? L.resolveDefault(callAssoc(ap.ifname), []) : Promise.resolve([])))
			.then(lists => {
				aps.forEach((ap, i) => ap.stations = lists[i] || []);
				return { radios: radios || {}, aps: aps };
			});
	});
}

function clients(wifi, uplink) {
	return Promise.all([
		L.resolveDefault(callLeases(), {}),
		L.resolveDefault(callHints(), {}),
		wifi ? Promise.resolve(wifi) : wifiInfo(),
		readFile('/proc/net/arp'),
		uplink !== undefined ? uplink : wan()
	]).then(([ leases, hints, wi, arp, up ]) => {
		up = up || {};
		/* neighbours on the uplink side (a main router's WAN port, a repeater's Wi-Fi link) are not
		 * our devices; a side router's uplink is the LAN itself, so there only the gateway is skipped.
		 * What a side router sees on its LAN port may well be a phone on the main router's Wi-Fi,
		 * so those count as "lan" rather than "wired". The same goes for a box with no Wi-Fi of its
		 * own (x86, radios off): its Wi-Fi devices arrive through an access point on a LAN port. */
		const side = up.mode == 'side', skip = side ? [] : [ up.device, up.port ];
		const lan = side || !(wi.aps || []).some(ap => ap.up);
		const byMac = {};
		const get = mac => {
			mac = String(mac).toUpperCase();
			return byMac[mac] || (byMac[mac] = { mac: mac, online: false });
		};

		(leases.dhcp_leases || []).forEach(l => {
			if (!l.macaddr) return;
			const c = get(l.macaddr);
			c.name = c.name || l.hostname;
			c.ip = l.ipaddr;
			c.expires = l.expires;
			c.lease = true;
		});

		const wifiMacs = {};

		(wi.aps || []).forEach(ap => ap.stations.forEach(s => {
			const c = get(s.mac);
			const h = (hints || {})[c.mac] || {};
			c.online = true;
			c.conn = 'wifi';
			c.band = ap.band;
			c.ssid = ap.ssid;
			c.signal = s.signal;
			c.link = Math.max((s.tx || {}).rate || 0, (s.rx || {}).rate || 0) / 1000;
			c.since = s.connected_time;
			c.name = c.name || h.name;
			c.ip = c.ip || (h.ipaddrs || [])[0];
			wifiMacs[c.mac] = true;
		}));

		/* Wired devices are whatever answers ARP on our side, leased or not (static IPs, or a side
		 * router whose DHCP is off), whatever the LAN is called (br-lan, eth0, br-lan.10 ...).
		 * The gateway is the upstream router; containers and loopback are not devices either.
		 * The bridge's own table then drops whoever has gone quiet (a Wi-Fi device that left). */
		const rows = String(arp || '').split('\n').slice(1).map(line => line.trim().split(/\s+/)).filter(f =>
			f.length >= 6 && f[2] == '0x2' && f[0] != up.gw && !skip.includes(f[5]) && !/^(lo|docker|veth)|^br-[0-9a-f]{12}$/.test(f[5]) && !wifiMacs[f[3].toUpperCase()]);
		const bridges = [ ...new Set(rows.map(f => f[5].replace(/\.\d+$/, ''))) ];

		return heard(bridges).then(macs => {
			rows.forEach(f => {
				if (macs && !macs[f[3].toUpperCase()]) return;
				const c = get(f[3]);
				c.online = true;
				c.conn = lan ? 'lan' : 'wired';
				c.ip = c.ip || f[0];
			});

			for (const mac in (hints || {})) {
				const h = hints[mac], c = byMac[mac.toUpperCase()];
				if (c) {
					c.name = c.name || h.name;
					c.ip = c.ip || (h.ipaddrs || h.ipv4 || [])[0];
				}
			}

			const list = Object.values(byMac).map(c => {
				c.display = pretty(c.name) || c.ip || c.mac;
				c.kind = kind(c.name);
				return c;
			});

			list.sort((a, b) => (b.online - a.online) || ((b.link || 0) - (a.link || 0)) || a.display.localeCompare(b.display));

			return list;
		});
	});
}

/* The uplink is whichever device carries the kernel's default route. Asking the kernel instead of
 * netifd covers every layout (main router, bypass/side router, routes added by scripts). */
function defaultRoute(text) {
	let best = null;
	String(text || '').split('\n').slice(1).forEach(line => {
		const f = line.trim().split(/\s+/);
		if (f[1] != '00000000' || f[7] != '00000000' || !(parseInt(f[3], 16) & 1)) return;
		if (!best || +f[6] < best.metric)
			best = { dev: f[0], metric: +f[6], gw: f[2].match(/../g).reverse().map(h => parseInt(h, 16)).join('.') };
	});
	return best;
}

function wan() {
	return Promise.all([ L.resolveDefault(callIfDump(), []), readFile('/proc/net/route') ]).then(([ ifs, rt ]) => {
		const def = defaultRoute(rt);
		const dev = i => i.l3_device || i.device;
		const list = ifs || [];
		const lan = list.find(i => i.interface == 'lan');
		const v4 = i => ((i['ipv4-address'] || [])[0] || {}).address;
		const v6 = i => ((i['ipv6-address'] || []).find(a => !/^fe80:/i.test(a.address)) || {}).address;   // never the link-local one

		if (!def) {
			const w = list.find(i => i.interface == 'wan');
			return w ? { up: false, mode: 'wan', proto: w.proto, device: dev(w) } : null;
		}

		const i = list.filter(i => i.up && dev(i) == def.dev)
			.sort((a, b) => !!(b['ipv4-address'] || []).length - !!(a['ipv4-address'] || []).length)[0] || {};

		/* Any other interface with a default route of its own (IPTV, a backup WAN) is another line.
		 * The IPv6 half of the WAN (wan6) is not: it rides on the WAN's device or port with no IPv4 route. */
		const deflt = (x, re) => (x.route || []).some(r => r.mask == 0 && re.test(r.target));
		const port = n => String(n || '').split('.')[0];
		const seen = new Set([ def.dev, lan && dev(lan) ]);
		const more = list.filter(x => x.up && x.interface != 'loopback' && deflt(x, /^(0\.0\.0\.0|::)$/) && !seen.has(dev(x))
		                         && (deflt(x, /^0\.0\.0\.0$/) || port(x.device) != port(i.device)) && seen.add(dev(x)))
			.map(x => ({ name: x.interface.toUpperCase(), proto: x.proto, device: dev(x), port: x.device, ip: v4(x) || v6(x), uptime: x.uptime }));

		return {
			up: true,
			/* side: uplink shares the LAN (bypass router / AP); sta: Wi-Fi uplink (repeater) */
			mode: lan && dev(lan) == def.dev ? 'side' : /-sta\d+$/.test(def.dev) ? 'sta' : 'wan',
			proto: i.proto,
			device: def.dev,
			port: i.device,
			ip: v4(i),
			ip6: v6(i),
			gw: def.gw != '0.0.0.0' ? def.gw : null,
			dns: i['dns-server'] || [],
			uptime: i.uptime,
			more: more
		};
	});
}

/* Physical Ethernet ports in use: the uplink ports, named after their line (WAN, IPTV, ...), then
 * whatever sits in a bridge (lan1…lan4, eth1, …). Switch ports are "dsa" devices, a plain NIC is
 * "ethernet". A VLAN on top (eth0.7, wan.10) counts as its port. Empty on swconfig boxes, where
 * the kernel only sees the CPU port. */
function ports(up) {
	const base = n => String(n || '').split('.')[0];
	const line = new Map();
	const tag = (n, name) => (n = base(n)) && !line.has(n) && line.set(n, name);
	if (up && up.mode != 'side') { tag(up.port, 'WAN'); tag(up.device, 'WAN'); }
	((up && up.more) || []).forEach(u => { tag(u.port, u.name); tag(u.device, u.name); });
	const order = [ ...line.keys() ], rank = n => { const k = order.indexOf(n); return k < 0 ? order.length : k };
	return L.resolveDefault(callDevices(), {}).then(devs => Object.values(devs || {})
		.filter(d => /^(ethernet|dsa)$/.test(d.devtype) && !d.wireless && d.name.indexOf('.') < 0 && !/^(docker|veth|br-)/.test(d.name)
		          && (d.master || line.has(d.name)))
		.map(d => ({ name: d.name, line: line.get(d.name), up: !!(d.link || {}).carrier, speed: +(d.link || {}).speed || 0 }))
		.sort((a, b) => (rank(a.name) - rank(b.name)) || a.name.localeCompare(b.name, 'en', { numeric: true })));
}

function connName(c) {
	return c.conn == 'lan' ? T('局域网', 'LAN') : T('有线连接', 'Wired');
}

const DNS_NAMES = {
	'223.5.5.5': T('阿里', 'AliDNS'), '223.6.6.6': T('阿里', 'AliDNS'),
	'119.29.29.29': T('腾讯', 'DNSPod'), '119.28.28.28': T('腾讯', 'DNSPod'), '182.254.116.116': T('腾讯', 'DNSPod'),
	'114.114.114.114': '114DNS', '114.114.115.115': '114DNS',
	'180.76.76.76': T('百度', 'Baidu'), '1.1.1.1': 'Cloudflare', '1.0.0.1': 'Cloudflare',
	'8.8.8.8': 'Google', '8.8.4.4': 'Google', '9.9.9.9': 'Quad9'
};

function dnsName(list, gw, gwName) {
	const names = [];
	(list || []).forEach(ip => {
		const n = DNS_NAMES[ip] || (ip == gw ? gwName || T('上级路由', 'Upstream') : ip);
		if (names.indexOf(n) < 0) names.push(n);
	});
	return names.slice(0, 2).join(' · ') || '—';
}

function netdev(text) {
	const out = {};
	String(text || '').split('\n').slice(2).forEach(line => {
		const m = line.match(/^\s*([^:]+):\s*(.*)$/);
		if (!m) return;
		const f = m[2].trim().split(/\s+/).map(Number);
		out[m[1]] = { rx: f[0], tx: f[8] };
	});
	return out;
}

function cpuStat(text) {
	const f = String(text || '').split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
	if (f.length < 4) return null;
	const idle = f[3] + (f[4] || 0);
	return { idle: idle, total: f.reduce((a, b) => a + b, 0) };
}

const uciType = (config, type) => L.resolveDefault(callUciGetType(config, type), {});
const uciSection = (config, section) => L.resolveDefault(callUciGet(config, section), {});

return baseclass.extend({
	ZH: ZH, T: T,
	active: ACTIVE,
	PALETTES: PALETTES, OPT_IN: OPT_IN, words: words, cardOn: cardOn,
	esc: esc, icon: icon, html: html,
	loadMenu: loadMenu, flatten: flatten, realNode: realNode, menuHas: menuHas, software: software, grouped: grouped, appIcon: appIcon, service: service,
	loadSettings: loadSettings, saveSettings: saveSettings, applyLook: applyLook, toast: toast, motion: motion, leave: leave,
	rate: rate, bytes: bytes, duration: duration, signal: signal, quality: quality, bandName: bandName, connName: connName,
	readFile: readFile, temperature: temperature, wifiInfo: wifiInfo, clients: clients, wan: wan, ports: ports, dnsName: dnsName, netdev: netdev, cpuStat: cpuStat,
	board: () => L.resolveDefault(callBoard(), {}),
	sysinfo: () => L.resolveDefault(callInfo(), {}),
	services: () => L.resolveDefault(callServices(), {}), mounts: () => L.resolveDefault(callMounts(), []),
	uciType: uciType, uciSection: uciSection,
	uciSet: (config, section, values) => callUciSet(config, section, values).then(() => callUciCommit(config))
});
