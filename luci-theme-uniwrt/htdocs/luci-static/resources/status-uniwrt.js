'use strict';
'require baseclass';
'require rpc';
'require poll';
'require fs';

var callSystemInfo = rpc.declare({ object: 'system', method: 'info' });
var callInterfaceDump = rpc.declare({ object: 'network.interface', method: 'dump', expect: { 'interface': [] } });
var callDeviceStatus = rpc.declare({ object: 'network.device', method: 'status', params: ['name'] });

return baseclass.extend({
	prevStats: null, prevTime: null,
	netDevice: null, netLabel: null, netChecked: false, linkSpeed: null,
	numCores: 1,

	__init__: function() {
		var self = this;
		L.resolveDefault(fs.read('/proc/cpuinfo'), '').then(function(text) {
			var m = text.match(/^processor\s*:/gm);
			self.numCores = (m && m.length) || 1;
		});
		this.setup();
	},

	icons: {
		cpu:    '<svg xmlns="http://www.w3.org/2000/svg" class="indicator-icon" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 9 4 4 7 11 10 2 13 9"/></svg>',
		ram:    '<svg xmlns="http://www.w3.org/2000/svg" class="indicator-icon" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"><path d="M1 3 H13 V10 H8 V9 H6 V10 H1 Z"/><rect x="2.2" y="4.5" width="2" height="3"/><rect x="6" y="4.5" width="2" height="3"/><rect x="9.8" y="4.5" width="2" height="3"/></svg>',
		net:    '<svg xmlns="http://www.w3.org/2000/svg" class="indicator-icon" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><line x1="7" y1="1" x2="7" y2="13"/><polyline points="3 4 7 1 11 4"/><polyline points="3 10 7 13 11 10"/></svg>',
		uptime: '<svg xmlns="http://www.w3.org/2000/svg" class="indicator-icon" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="7" cy="7" r="6"/><polyline points="7 3 7 7 10 9"/></svg>'
	},

	makeIcon: function(name) {
		var markup = this.icons[name];
		if (!markup) return document.createTextNode('');
		var doc = new DOMParser().parseFromString(markup, 'image/svg+xml');
		return document.importNode(doc.documentElement, true);
	},

	chip: function(name, title) {
		var el = document.createElement('span');
		el.className = 'u-chip';
		el.setAttribute('data-indicator', name);
		el.title = title;
		el.appendChild(this.makeIcon(name));
		var val = document.createElement('span');
		val.className = 'indicator-value';
		var cached = null;
		try { cached = sessionStorage.getItem('uniwrt-stat-' + name); } catch(e) {}
		val.textContent = cached || '--';
		el.appendChild(val);
		return el;
	},

	setLevel: function(el, level) { el.setAttribute('data-level', level); },

	setup: function() {
		this.box = document.getElementById('u-stats');
		if (!this.box) return;
		this.cpuEl = this.chip('cpu', 'CPU Load');
		this.ramEl = this.chip('ram', 'Memory Usage');
		this.uptimeEl = this.chip('uptime', 'Uptime');
		this.box.appendChild(this.cpuEl);
		this.box.appendChild(this.ramEl);
		this.box.appendChild(this.uptimeEl);
		this.tick();
		/* use LuCI's poll loop instead of setInterval so it batches with the
		   framework's polling; tick() itself skips while the tab is hidden */
		poll.add(L.bind(this.tick, this), 5);
		poll.start();
	},

	tick: function() {
		var self = this;
		/* LuCI's poll loop keeps running in background tabs; don't make the
		   router answer system.info for a page nobody is looking at */
		if (document.hidden) return;
		L.resolveDefault(callSystemInfo(), {}).then(function(info) {
			self.updateSystem(info);
			/* publish for same-page consumers (the overview dashboard) so the two
			   widgets don't both hit ubus system.info every poll cycle */
			try { window.__uniwrtInfo = { t: Date.now(), info: info }; } catch (e) {}
		});

		if (!this.netChecked) {
			this.netChecked = true;
			L.resolveDefault(callInterfaceDump(), []).then(function(ifaces) {
				var find = function(test) { for (var i = 0; i < ifaces.length; i++) if (test(ifaces[i])) return ifaces[i]; };
				/* 'wan' / 'wan6' by name; otherwise whatever holds the default
				   route (e.g. 'lan' on an access point behind a main router) */
				var w = find(function(i) { return i.interface === 'wan'; })
				     || find(function(i) { return i.interface === 'wan6'; })
				     || find(function(i) { return i.up && (i.route || []).some(function(r) { return r.target === '0.0.0.0' && r.mask === 0; }); });
				self.resolveDevice(w ? (w.l3_device || w.device) : 'wan');
			});
		} else if (this.netDevice) {
			this.pollNet();
		}
	},

	resolveDevice: function(devName) {
		var self = this;
		L.resolveDefault(callDeviceStatus(devName), {}).then(function(dev) {
			if (!dev) return;
			var members = dev['bridge-members'];
			if (dev.type === 'bridge' && members && members.length > 0)
				/* the uplink port carries everything, so it is the busiest wired member */
				return L.resolveDefault(callDeviceStatus(), {}).then(function(all) {
					var best = null, most = -1;
					members.forEach(function(m) {
						if (/^(wl|phy|wlan|ath|ra|rai|apcli)\d/.test(m)) return;
						var st = (all && all[m] || {}).statistics || {}, b = (st.rx_bytes || 0) + (st.tx_bytes || 0);
						if (b > most) { most = b; best = m; }
					});
					self.netDevice = best || members[0];
					return self.netDevice;
				});
			if (dev.statistics) self.netDevice = devName;
			return self.netDevice;
		}).then(function() {
			if (!self.netDevice) return;

			L.resolveDefault(callDeviceStatus(self.netDevice), {}).then(function(phys) {
				if (phys && phys.speed) {
					var m = String(phys.speed).match(/^(\d+)/);
					if (m) self.linkSpeed = parseInt(m[1], 10);
				}
				if (phys && phys.devtype === 'dsa' && phys['hw-tc-offload'] && phys.conduit) {
					self.netLabel = self.netDevice;
					self.netDevice = phys.conduit;
				}
				self.netEl = self.chip('net', 'Throughput');
				self.box.insertBefore(self.netEl, self.uptimeEl);
				self.pollNet();
			});
		});
	},

	pollNet: function() {
		var self = this;
		L.resolveDefault(callDeviceStatus(this.netDevice), {}).then(function(dev) { self.updateNet(dev); });
	},

	updateSystem: function(info) {
		if (!info) return;
		if (info.load && info.load.length) {
			var load1 = info.load[0] / 65536;
			var pct = Math.min(load1 / this.numCores, 1) * 100;
			var s = pct.toFixed(0) + '%';
			this.cpuEl.querySelector('.indicator-value').textContent = s;
			try { sessionStorage.setItem('uniwrt-stat-cpu', s); } catch(e) {}
			this.cpuEl.title = 'CPU: ' + s + ' (load ' + load1.toFixed(2) + ' on ' + this.numCores + (this.numCores === 1 ? ' core)' : ' cores)');
			this.setLevel(this.cpuEl, pct < 60 ? 'ok' : pct < 85 ? 'warn' : 'crit');
		}
		if (info.memory && info.memory.total) {
			var total = info.memory.total;
			var avail = info.memory.available || info.memory.free;
			var pct = ((total - avail) / total * 100).toFixed(0);
			this.ramEl.querySelector('.indicator-value').textContent = pct + '%';
			try { sessionStorage.setItem('uniwrt-stat-ram', pct + '%'); } catch(e) {}
			this.ramEl.title = 'RAM: ' + this.fmtBytes(total - avail) + ' / ' + this.fmtBytes(total) + ' (' + pct + '%)';
			this.setLevel(this.ramEl, pct < 60 ? 'ok' : pct < 85 ? 'warn' : 'crit');
		}
		if (info.uptime) {
			var u = this.fmtUptime(info.uptime);
			this.uptimeEl.querySelector('.indicator-value').textContent = u;
			try { sessionStorage.setItem('uniwrt-stat-uptime', u); } catch(e) {}
			this.uptimeEl.title = 'Uptime: ' + u;
		}
	},

	updateNet: function(dev) {
		if (!dev || !dev.statistics || !this.netEl) return;
		var now = Date.now() / 1000;
		var rx = dev.statistics.rx_bytes || 0, tx = dev.statistics.tx_bytes || 0;
		if (this.prevStats && this.prevTime) {
			var dt = now - this.prevTime;
			if (dt > 0) {
				var rxS = Math.max((rx - this.prevStats.rx) / dt, 0);
				var txS = Math.max((tx - this.prevStats.tx) / dt, 0);
				var txt = '\u2193' + this.fmtMbps(rxS) + ' \u2191' + this.fmtMbps(txS) + ' Mbps';
				this.netEl.querySelector('.indicator-value').textContent = txt;
				try { sessionStorage.setItem('uniwrt-stat-net', txt); } catch(e) {}
				this.netEl.title = (this.netLabel || this.netDevice) + ': \u2193 ' + this.fmtSpeedFull(rxS) + ' / \u2191 ' + this.fmtSpeedFull(txS);
				var peak = Math.max(rxS, txS);
				this.setLevel(this.netEl, peak < 1048576 ? 'ok' : peak < 52428800 ? 'active' : 'busy');
			}
		}
		this.prevStats = { rx: rx, tx: tx };
		this.prevTime = now;
	},

	fmtUptime: function(s) {
		var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
		return d > 0 ? d + 'd ' + h + 'h' : h + 'h ' + m + 'm';
	},
	fmtBytes: function(b) {
		if (b >= 1073741824) return (b / 1073741824).toFixed(1) + ' GB';
		if (b >= 1048576) return (b / 1048576).toFixed(0) + ' MB';
		return (b / 1024).toFixed(0) + ' KB';
	},
	fmtMbps: function(bps) {
		var mbps = bps * 8 / 1e6;            /* bytes/s -> Mbps */
		if (mbps >= 100) return mbps.toFixed(0);
		if (mbps >= 10)  return mbps.toFixed(1);
		return mbps.toFixed(2);
	},
	fmtSpeedFull: function(bps) {
		var bits = bps * 8;
		if (bits >= 1e9) return (bits / 1e9).toFixed(1) + ' Gbps';
		if (bits >= 1e6) return (bits / 1e6).toFixed(1) + ' Mbps';
		if (bits >= 1e3) return (bits / 1e3).toFixed(1) + ' kbps';
		return Math.round(bits) + ' bps';
	}
});
