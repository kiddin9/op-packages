'use strict';
'require baseclass';
'require vantage.fmt as fmt';
'require vantage.wifi as wifi';
'require vantage.names as names';

/* Turns raw ubus replies into one normalised model of the device, its
   uplink, radios, SSIDs and stations, plus the counter/rate arithmetic.
   Pure functions: the view owns all state and passes it in. */

/* interface names that are wireless even when netifd reports no devtype
   (it does not on ipq53xx/ath12k: phy2g-ap0, phy6g-ap0, ...) */
var WIRELESS_NAME = /^(wlan\d|phy[0-9a-z]*-|ath\d|wl\d|ra\d|rai\d|rax\d|mld\d)/;

/* above any real link: a rate this high means a bad sample, not traffic */
var MAX_BPS = 400e9;

function num(v) { v = +v; return isFinite(v) ? v : 0; }
function finite(v) { return typeof v === 'number' && isFinite(v); }
function own(o, k) { return o != null && Object.prototype.hasOwnProperty.call(o, k); }
function obj(v) { return (v && typeof v === 'object' && !Array.isArray(v)) ? v : {}; }
function arr(v) { return Array.isArray(v) ? v : []; }

return baseclass.extend({
	/* ------------------------------------------------------------- CPU */

	/* /proc/stat -> { all: { idle, total }, cores: [ { idle, total } ] } */
	parseStat: function(text) {
		var out = { all: null, cores: [] };
		String(text || '').split('\n').forEach(function(line) {
			var m = line.match(/^cpu(\d*)\s+([\d\s]+)$/);
			if (!m) return;
			var f = m[2].trim().split(/\s+/).map(num);
			/* user nice system idle iowait irq softirq steal */
			var idle = f[3] + (f[4] || 0), total = 0;
			for (var i = 0; i < Math.min(f.length, 8); i++) total += f[i];
			if (m[1] === '') out.all = { idle: idle, total: total };
			else out.cores[+m[1]] = { idle: idle, total: total };
		});
		out.cores = out.cores.filter(Boolean);
		return out.all ? out : null;
	},

	cpuPercent: function(prev, cur) {
		if (!prev || !cur) return null;
		var dt = cur.total - prev.total, di = cur.idle - prev.idle;
		if (!(dt > 0)) return null;
		return Math.max(0, Math.min(100, (1 - di / dt) * 100));
	},

	/* { pct, cores: [ pct, ... ] } between two parseStat() results */
	cpuUsage: function(prev, cur) {
		if (!prev || !cur) return null;
		var self = this, pct = this.cpuPercent(prev.all, cur.all);
		if (pct == null) return null;
		return { pct: pct, cores: cur.cores.map(function(c, i) { return self.cpuPercent(prev.cores[i], c); }) };
	},

	/* ---------------------------------------------------------- memory */

	/* One bar, three segments that add up to total:
	     In use               total - available
	     Cache (reclaimable)  available - free   (page cache, buffers)
	     Free                 free
	   'available' is the kernel's estimate (MemAvailable); without it
	   free + buffered + cached stands in. */
	memory: function(m) {
		m = obj(m);
		var total = num(m.total);
		if (!(total > 0)) return null;
		var free = Math.min(Math.max(num(m.free), 0), total);
		var avail = finite(m.available) ? m.available : free + num(m.buffered) + num(m.cached);
		avail = Math.min(Math.max(avail, free), total);
		var used = total - avail, cache = avail - free;
		return {
			total: total, available: avail, used: used, cache: cache, free: free,
			availPct: avail / total * 100, usedPct: used / total * 100,
			segments: [
				{ key: 'used', label: _('In use'), bytes: used, pct: used / total * 100 },
				{ key: 'cache', label: _('Cache (reclaimable)'), bytes: cache, pct: cache / total * 100 },
				{ key: 'free', label: _('Free'), bytes: free, pct: free / total * 100 }
			]
		};
	},

	/* system.info swap -> { total, used, free, usedPct } or null when none */
	swap: function(s) {
		s = obj(s);
		var total = num(s.total), free = Math.min(Math.max(num(s.free), 0), total);
		if (!(total > 0)) return null;
		return { total: total, free: free, used: total - free, usedPct: (total - free) / total * 100 };
	},

	/* system.info root/tmp (KiB) -> bytes { total, used, free, usedPct } */
	mount: function(s, label) {
		s = obj(s);
		var total = num(s.total) * 1024;
		if (!(total > 0)) return null;
		var used = Math.min(Math.max(num(s.used) * 1024, 0), total);
		var free = finite(s.avail) ? Math.min(num(s.avail) * 1024, total - used) : total - used;
		return { label: label, total: total, used: used, free: free, usedPct: used / total * 100 };
	},

	/* ---------------------------------------------------------- counters */

	/* Rate between two byte-counter samples { at: ms, rx, tx }.
	   'first': no previous sample; 'skip': under 1 s apart (keep prev as
	   the base); 'reset': a counter went backwards or the rate is not
	   physical (restart from cur); 'ok': rx/tx in bit/s. */
	counterRate: function(prev, cur) {
		if (!prev || !cur || !finite(prev.at) || !finite(cur.at)) return { state: 'first' };
		var dt = (cur.at - prev.at) / 1000;
		if (!(dt >= 1)) return { state: 'skip' };
		var rx = (num(cur.rx) - num(prev.rx)) * 8 / dt, tx = (num(cur.tx) - num(prev.tx)) * 8 / dt;
		if (!(rx >= 0 && tx >= 0 && rx <= MAX_BPS && tx <= MAX_BPS)) return { state: 'reset' };
		return { state: 'ok', rx: rx, tx: tx, dt: dt };
	},

	/* Capture time for one poll's counters. The browser clock is precise
	   but only says when the reply arrived; system.info localtime (whole
	   seconds) says which sample the device served. Same localtime as
	   last poll: the same snapshot again (-> dt 0, the rate is skipped).
	   The two clocks disagree by more than 2 s (a delayed reply, a
	   replayed or skipped sample): trust the device's spacing.
	   prev/next: { at: ms, local: s } */
	sampleClock: function(prev, now, local) {
		if (!finite(local)) return { at: now, local: null };
		if (!prev || !finite(prev.at) || !finite(prev.local)) return { at: now, local: local };
		var dLocal = (local - prev.local) * 1000, dClient = now - prev.at;
		if (dLocal === 0) return { at: prev.at, local: local };
		if (dLocal < 0 || Math.abs(dLocal - dClient) > 2000) return { at: prev.at + Math.max(dLocal, 0) || now, local: local };
		return { at: now, local: local };
	},

	/* Rates for a set of counters { key: { rx, tx } } captured at `at`.
	   Returns { next, rates }; next holds only keys present now, so the
	   state cannot grow with every station that ever associated. */
	rates: function(prevMap, counters, at) {
		var next = Object.create(null), rates = Object.create(null), self = this;
		Object.keys(obj(counters)).forEach(function(k) {
			var c = counters[k];
			if (!c) return;
			var p = own(prevMap, k) ? prevMap[k] : null;
			var cur = { at: at, rx: num(c.rx), tx: num(c.tx) };
			var r = self.counterRate(p, cur);
			if (r.state === 'ok') rates[k] = { rx: r.rx, tx: r.tx };
			next[k] = r.state === 'skip' ? p : cur;
		});
		return { next: next, rates: rates };
	},

	/* ------------------------------------------------------------ uplink */

	isWireless: function(name, dev, known) {
		if (known && known.indexOf(name) >= 0) return true;
		if (dev && (dev.devtype === 'wlan' || dev.wireless === true)) return true;
		return WIRELESS_NAME.test(String(name || ''));
	},

	parseSpeed: function(s) {
		var m = String(s == null ? '' : s).match(/^(\d+)([FH])?/);
		if (!m || +m[1] <= 0) return null;
		return { mbps: +m[1], duplex: m[2] === 'H' ? 'half' : (m[2] === 'F' ? 'full' : null) };
	},

	speedLabel: function(sp) {
		if (!sp) return fmt.DASH;
		var v = sp.mbps >= 1000 ? _('%s Gbit/s').format(sp.mbps / 1000) : _('%s Mbit/s').format(sp.mbps);
		return v + (sp.duplex === 'full' ? ' · ' + _('full duplex') : sp.duplex === 'half' ? ' · ' + _('half duplex') : '');
	},

	/* Pick the interface carrying traffic in/out of this device, and the
	   physical device its counters live on. Routers: wan/wan6/*wan*.
	   Access points: the interface with the default route, else the first
	   one that is up. A bridge is followed to its wired member (wireless
	   members are skipped; netifd 'ethernet' members preferred); DSA with
	   hardware offload uses the conduit's counters. */
	resolveUplink: function(ifaces, devs, wirelessNames) {
		var self = this;
		ifaces = arr(ifaces);
		devs = obj(devs);

		var up = ifaces.filter(function(i) {
			return i && i.up && i.interface !== 'loopback' && (i.l3_device || i.device);
		});
		function named(re) { return up.filter(function(i) { return re.test(i.interface); })[0]; }
		function defRoute(i) {
			return arr(i.route).filter(function(r) {
				return r && +r.mask === 0 && (r.target === '0.0.0.0' || r.target === '::');
			})[0] || null;
		}

		var wan = named(/^wan$/) || named(/^wan6$/) || named(/wan/i);
		var pick = wan || up.filter(defRoute)[0] || up[0];
		if (!pick) return null;

		var l3 = pick.l3_device || pick.device, dev = l3, d = devs[dev];
		if (d && (d.type === 'bridge' || d.devtype === 'bridge') && Array.isArray(d['bridge-members'])) {
			var members = d['bridge-members'];
			var wired = members.filter(function(m) { return !self.isWireless(m, devs[m], wirelessNames); });
			var eth = wired.filter(function(m) { return devs[m] && devs[m].devtype === 'ethernet'; });
			var next = eth[0] || wired[0] || members[0];
			if (next) { dev = next; d = devs[dev] || null; }
		}

		var statsDev = dev;
		if (d && d.devtype === 'dsa' && d['hw-tc-offload'] && d.conduit && devs[d.conduit])
			statsDev = d.conduit;

		var route = defRoute(pick);
		return {
			iface: pick.interface,
			l3dev: l3,
			dev: dev,
			statsDev: statsDev,
			isWan: !!wan,
			proto: pick.proto || null,
			uptime: finite(pick.uptime) ? pick.uptime : null,
			up: !!pick.up,
			carrier: d ? d.carrier !== false : null,
			speed: d ? this.parseSpeed(d.speed) : null,
			ipv4: arr(pick['ipv4-address']).map(function(a) { return a && a.address ? a.address + '/' + a.mask : null; }).filter(Boolean),
			ipv6: arr(pick['ipv6-address']).map(function(a) { return a && a.address ? a.address + '/' + a.mask : null; }).filter(Boolean),
			gateway: route && route.nexthop && route.nexthop !== '0.0.0.0' ? route.nexthop : null,
			dns: arr(pick['dns-server']).filter(function(s) { return typeof s === 'string'; }),
			stats: d && d.statistics ? d.statistics : null
		};
	},

	/* The device tree model is sometimes the SoC reference design
	   ("Qualcomm Technologies, Inc. IPQ5332/RDP442/..."); board_name
	   ("zyxel,nwa50be") names the actual product then. */
	deviceModel: function(board) {
		board = obj(board);
		var model = String(board.model || ''), m = String(board.board_name || '').match(/^([^,]+),(.+)$/);
		if (m && (!model || /Qualcomm Technologies|\bRDP\d|reference board|\bEVB\b|\bRFB\b/i.test(model)))
			return m[1].charAt(0).toUpperCase() + m[1].slice(1) + ' ' + m[2].toUpperCase();
		return model || board.board_name || null;
	},

	/* ------------------------------------------------ address filtering */

	parseIPv4: function(s) {
		var m = typeof s === 'string' ? s.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) : null;
		if (!m) return null;
		var out = [];
		for (var i = 1; i <= 4; i++) {
			if (m[i].length > 1 && m[i].charAt(0) === '0') return null;
			if (+m[i] > 255) return null;
			out.push(+m[i]);
		}
		return out;
	},

	ipv4InSubnet: function(ip, net, mask) {
		var a = this.parseIPv4(ip), b = this.parseIPv4(net);
		mask = +mask;
		if (!a || !b || !(mask >= 0 && mask <= 32)) return false;
		for (var i = 0; i < 4; i++) {
			var bits = Math.max(0, Math.min(8, mask - i * 8));
			if (!bits) break;
			var m = (0xff << (8 - bits)) & 0xff;
			if ((a[i] & m) !== (b[i] & m)) return false;
		}
		return true;
	},

	/* host-hint IPv4 addresses inside one of the given subnets
	   ([ 'a.b.c.d/nn', ... ]); hints are keyed by MAC only, so a hint may
	   name any address. IPv6 link-local and global addresses are kept. */
	hintAddrs: function(hint, subnets) {
		var self = this, out = [];
		hint = obj(hint);
		arr(hint.ipaddrs).forEach(function(ip) {
			if (typeof ip !== 'string' || out.indexOf(ip) >= 0) return;
			if (!subnets.length || subnets.some(function(s) { var p = s.split('/'); return +p[1] >= 8 && self.ipv4InSubnet(ip, p[0], p[1]); }))
				out.push(ip);
		});
		arr(hint.ip6addrs).forEach(function(ip) {
			if (typeof ip === 'string' && /^[0-9a-f:]+$/i.test(ip) && ip.length <= 45 && out.indexOf(ip) < 0) out.push(ip);
		});
		return out;
	},

	/* ------------------------------------------------------------ model */

	/* raw: { board, info, ifaces, devs, wifi, iwinfo: { ifname: info },
	          assoc: { ifname: [ station ] }, hapd: { ifname: { clients } },
	          hapdStatus: { ifname: status }, hints, aliases, rdns, mdns,
	          vendor: fn(mac) -> name|null } */
	build: function(raw) {
		raw = raw || {};
		var self = this, board = obj(raw.board), info = obj(raw.info), devs = obj(raw.devs), hints = obj(raw.hints);
		var wifiDevs = obj(raw.wifi), iw = obj(raw.iwinfo), assoc = obj(raw.assoc), hapd = obj(raw.hapd), hstat = obj(raw.hapdStatus);

		var radios = [], ssids = [], clients = [], wlNames = [];

		Object.keys(wifiDevs).sort().forEach(function(rname) {
			var r = obj(wifiDevs[rname]), cfg = obj(r.config), rIw = obj(r.iwinfo);
			var ifs = arr(r.interfaces).filter(function(i) { return i && typeof i === 'object'; });
			var firstIf = ifs.filter(function(i) { return i.ifname && own(iw, i.ifname); })[0];
			var info0 = firstIf ? obj(iw[firstIf.ifname]) : {};
			var band = wifi.bandKey(cfg.band, info0.frequency || rIw.frequency);
			var ht = wifi.htmode(info0.htmode || cfg.htmode);
			var chan = num(info0.channel || rIw.channel || cfg.channel) || null;
			var radio = {
				id: rname,
				band: band,
				bandLabel: wifi.bandLabel(band),
				up: r.up === true,
				disabled: r.disabled === true || cfg.disabled === true || cfg.disabled === '1',
				pending: r.pending === true,
				channel: chan,
				auto: cfg.channel === 'auto',
				centre: num(info0.center_chan1) || null,
				freq: num(info0.frequency || rIw.frequency) || null,
				width: ht.width,
				std: ht.std,
				gen: wifi.genName(ht.std, band),
				htmode: info0.htmode || cfg.htmode || null,
				txpower: finite(info0.txpower) ? info0.txpower : (finite(rIw.txpower) ? rIw.txpower : null),
				txpowerCfg: cfg.txpower != null && isFinite(+cfg.txpower) ? +cfg.txpower : null,
				noise: wifi.noise(finite(info0.noise) ? info0.noise : rIw.noise),
				noiseRaw: finite(info0.noise) ? info0.noise : (finite(rIw.noise) ? rIw.noise : null),
				country: cfg.country || rIw.country || null,
				hwmodes: arr(rIw.hwmodes || info0.hwmodes).join('/'),
				airtime: null,
				ifnames: [],
				ssids: [],
				clients: 0,
				legacy: 0
			};
			radio.spectrum = wifi.spectrum(band, chan, radio.centre, radio.width);

			ifs.forEach(function(i) {
				var ic = obj(i.config), ifname = typeof i.ifname === 'string' ? i.ifname : null;
				/* luci.vantage wireless has no iwinfo part: the view's
				   per-interface iwinfo info replies stand in for it */
				var iiw = obj(i.iwinfo || (ifname && own(iw, ifname) ? iw[ifname] : null));
				if (ifname) { radio.ifnames.push(ifname); wlNames.push(ifname); }
				var st = ifname ? obj(hstat[ifname]) : {};
				var air = obj(st.airtime);
				if (num(air.time) > 0 || num(air.utilization) > 0)
					radio.airtime = Math.max(radio.airtime || 0, Math.min(100, num(air.utilization) / 2.55));
				var ss = {
					id: ifname || (rname + ':' + (i.section || ssids.length)),
					ifname: ifname,
					section: typeof i.section === 'string' ? i.section : null,
					radio: rname,
					band: band,
					ssid: fmt.safeText(ic.ssid || iiw.ssid || '', 32),
					mode: ic.mode || 'ap',
					hidden: ic.hidden === true || ic.hidden === '1',
					security: wifi.security(ic.encryption),
					pmf: +ic.ieee80211w || 0,
					networks: arr(ic.network),
					bssid: fmt.mac(iiw.bssid || ic.macaddr || ''),
					up: radio.up && !!ifname && (!devs[ifname] || devs[ifname].up !== false),
					clients: 0
				};
				radio.ssids.push(ss.id);
				ssids.push(ss);
			});
			radios.push(radio);
		});

		var uplink = this.resolveUplink(raw.ifaces, devs, wlNames);
		var subnets = uplink ? uplink.ipv4 : [];

		function hintOf(mac) { return obj(hints[mac.toUpperCase()] || hints[mac]); }

		/* mDNS names only where they are unambiguous across all stations */
		var everyone = [];
		ssids.forEach(function(ss) {
			if (ss.ifname) arr(assoc[ss.ifname]).forEach(function(s) {
				var mac = s && names.normMac(s.mac);
				if (mac) everyone.push({ mac: mac, ips: self.hintAddrs(hintOf(mac), subnets) });
			});
		});
		var mdns = names.mdnsForStations(raw.mdns, everyone);

		ssids.forEach(function(ss) {
			if (!ss.ifname) return;
			var hc = obj(obj(hapd[ss.ifname]).clients);
			var hmap = Object.create(null);
			Object.keys(hc).forEach(function(k) { var m = names.normMac(k); if (m) hmap[m] = obj(hc[k]); });
			arr(assoc[ss.ifname]).forEach(function(s) {
				var mac = s && names.normMac(s.mac);
				if (!mac) return;
				var h = hmap[mac] || {}, rx = obj(s.rx), tx = obj(s.tx);
				var hint = hintOf(mac);
				var ips = self.hintAddrs(hint, subnets);
				var std = wifi.clientStd(rx, tx, h);
				var alias = raw.aliases && raw.aliases[mac];
				var nm = names.resolve({
					mac: mac, alias: alias, ips: ips, rdns: raw.rdns, mdns: mdns,
					hint: hint, wps: names.wpsName(h.signature),
					vendor: typeof raw.vendor === 'function' ? raw.vendor(names.ouiKey(mac)) : null
				});
				var radio = radios.filter(function(r) { return r.id === ss.radio; })[0];
				var c = {
					mac: mac,
					macLabel: fmt.mac(mac),
					name: nm.name,
					nameSource: nm.source,
					nameSourceLabel: nm.sourceLabel,
					icon: nm.icon,
					secondary: nm.secondary,
					isPrivate: nm.isPrivate,
					alias: alias ? alias.name : null,
					aliasSid: alias ? alias.sid : null,
					vendor: nm.source === 'vendor' ? (typeof raw.vendor === 'function' ? raw.vendor(names.ouiKey(mac)) : null) : null,
					wps: names.wpsName(h.signature),
					ips: ips,
					ifname: ss.ifname,
					ssid: ss.ssid,
					ssidId: ss.id,
					radio: ss.radio,
					band: ss.band,
					bandLabel: wifi.bandLabel(ss.band),
					signal: finite(s.signal) && s.signal < 0 ? s.signal : null,
					signalAvg: finite(s.signal_avg) && s.signal_avg < 0 ? s.signal_avg : null,
					noise: wifi.noise(s.noise),
					std: std,
					gen: wifi.genName(std, ss.band),
					rx: wifi.phy(rx),
					tx: wifi.phy(tx),
					rxBytes: num(rx.bytes), txBytes: num(tx.bytes),
					rxPackets: num(rx.packets), txPackets: num(tx.packets),
					txRetries: num(tx.retries), txFailed: num(tx.failed),
					connected: finite(s.connected_time) ? s.connected_time : null,
					inactive: finite(s.inactive) ? s.inactive : null,
					authorized: s.authorized !== false,
					mfp: !!(s.mfp || h.mfp),
					wmm: !!(s.wme || h.wmm),
					caps: { ht: !!h.ht, vht: !!h.vht, he: !!h.he, eht: !!h.eht, mbo: !!h.mbo, rrm: arr(h.rrm).some(function(v) { return +v > 0; }) }
				};
				c.level = wifi.signal(c.signal);
				c.legacyOnRadio = !!(radio && radio.std && wifi.genRank(c.gen) >= 0 && wifi.genRank(c.gen) < wifi.genRank(wifi.genName(radio.std, radio.band)) &&
					wifi.genRank(c.gen) <= 4 && wifi.genRank(wifi.genName(radio.std, radio.band)) >= 6);
				if (radio) { radio.clients++; if (c.legacyOnRadio) radio.legacy++; }
				ss.clients++;
				clients.push(c);
			});
		});

		var mem = this.memory(info.memory);
		var release = obj(board.release);
		return {
			device: {
				model: this.deviceModel(board) || _('OpenWrt device'),
				hostname: fmt.safeText(board.hostname || '', 64) || null,
				firmware: release.description || [ release.distribution, release.version ].filter(Boolean).join(' ') || null,
				version: release.version || null,
				target: release.target || null,
				kernel: board.kernel || null,
				system: board.system || null,
				uptime: finite(info.uptime) ? info.uptime : null,
				localtime: finite(info.localtime) ? info.localtime : null,
				load: arr(info.load).slice(0, 3).map(num),
				memory: mem,
				swap: this.swap(info.swap),
				storage: [ this.mount(info.root, _('Root (overlay)')), this.mount(info.tmp, _('Temporary (RAM)')) ].filter(Boolean)
			},
			uplink: uplink,
			radios: radios,
			ssids: ssids,
			clients: clients
		};
	},

	/* SSIDs with the same name and security across radios -> one entry
	   { key, ssid, security, bands: [..], ids: [..], clients } */
	groupSsids: function(ssids) {
		var out = [], idx = Object.create(null);
		arr(ssids).forEach(function(s) {
			var k = s.ssid + '\u0000' + s.security.short;
			if (!idx[k]) { idx[k] = { key: k, ssid: s.ssid, security: s.security, pmf: s.pmf, hidden: s.hidden, bands: [], ids: [], radios: [], clients: 0, up: false }; out.push(idx[k]); }
			var g = idx[k];
			if (s.band && g.bands.indexOf(s.band) < 0) g.bands.push(s.band);
			if (g.radios.indexOf(s.radio) < 0) g.radios.push(s.radio);
			g.ids.push(s.id);
			g.clients += s.clients;
			g.up = g.up || s.up;
		});
		return out;
	}
});
