'use strict';
'require view';
'require fs';
'require network';
'require rpc';
'require uci';
'require ui';

var callHostHints = rpc.declare({
	object: 'luci-rpc', method: 'getHostHints', expect: { '': {} }
});
var callDHCPLeases = rpc.declare({
	object: 'luci-rpc', method: 'getDHCPLeases', expect: { '': {} }
});

function macList(section, option) {
	var l = uci.get('meow', section, option);
	if (l == null) return [];
	return (Array.isArray(l) ? l : [ l ]).map(function(m) { return m.toLowerCase(); });
}

return view.extend({
	load: function() {
		return uci.load('meow').then(function() {
			return Promise.all([
				null, uci.load('dhcp').catch(function() {}),
				L.resolveDefault(callHostHints(), {}),
				L.resolveDefault(callDHCPLeases(), {})
			]);
		});
	},

	render: function(data) {
		var self = this;
		var bypass = macList('tproxy', 'bypass_mac');
		var steer = macList('arp', 'client');
		var arpEnabled = uci.get('meow', 'arp', 'enabled') === '1';

		this.bypassChecks = {};
		this.steerChecks = {};

		var rows = [E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('Bypass')),
			E('th', { 'class': 'th' }, _('Steer')),
			E('th', { 'class': 'th' }, _('Hostname')),
			E('th', { 'class': 'th' }, _('IP address')),
			E('th', { 'class': 'th' }, _('MAC address'))
		])];

		var hints = data[2] || {}, leases = (data[3] || {}).dhcp_leases || [];
		var seen = {};
		Object.keys(hints).forEach(function(mac) {
			var h = hints[mac] || {};
			var ip = (h.ipaddrs || h.ipv4 || [])[0];
			if (!ip || /^(00:){5}00$/i.test(mac)) return;
			seen[mac.toLowerCase()] = { mac: mac.toLowerCase(), name: h.name || '', ip: ip };
		});
		leases.forEach(function(l) {
			if (!l.macaddr) return;
			var mac = l.macaddr.toLowerCase();
			seen[mac] = seen[mac] || { mac: mac, name: '', ip: '' };
			if (!seen[mac].name && l.hostname && l.hostname !== '*') seen[mac].name = l.hostname;
			if (l.ipaddr) seen[mac].ip = l.ipaddr;
		});
		bypass.concat(steer).forEach(function(mac) {
			seen[mac] = seen[mac] || { mac: mac, name: '', ip: '' };
		});

		Object.keys(seen).sort().forEach(function(mac) {
			var c = seen[mac];
			var bp = E('input', {
				type: 'checkbox',
				checked: bypass.indexOf(mac) !== -1 ? '' : null,
				change: function() { if (bp.checked) st.checked = false; }
			});
			var st = E('input', {
				type: 'checkbox',
				checked: steer.indexOf(mac) !== -1 ? '' : null,
				change: function() { if (st.checked) bp.checked = false; }
			});
			self.bypassChecks[mac] = bp;
			self.steerChecks[mac] = st;
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, bp),
				E('td', { 'class': 'td', 'style': arpEnabled ? '' : 'display:none;' }, st),
				E('td', { 'class': 'td' }, c.name || '-'),
				E('td', { 'class': 'td' }, c.ip || '-'),
				E('td', { 'class': 'td' }, c.mac)
			]));
		});

		this.arpToggle = E('input', {
			type: 'checkbox', checked: arpEnabled ? '' : null,
			change: function(ev) {
				var on = ev.target.checked;
				Object.keys(self.steerChecks).forEach(function(mac) {
					self.steerChecks[mac].parentNode.style.display = on ? '' : 'none';
				});
			}
		});

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('meow Clients')),
			E('p', {}, _('Tick a client to bypass the transparent proxy, or use Steer for ARP-based client steering.')),
			E('div', { 'class': 'cbi-section' }, [
				E('table', { 'class': 'table cbi-section-table' }, rows)
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('label', {}, [this.arpToggle, ' ', _('Enable ARP client steering')])
			])
		]);
	},

	handleSaveApply: function() {
		function ticked(checks) {
			return Object.keys(checks).filter(function(m) { return checks[m].checked; });
		}
		var bypass = ticked(this.bypassChecks);
		var steer = ticked(this.steerChecks).filter(function(m) { return bypass.indexOf(m) === -1; });
		uci.set('meow', 'tproxy', 'bypass_mac', bypass);
		uci.set('meow', 'arp', 'enabled', this.arpToggle.checked ? '1' : '0');
		uci.set('meow', 'arp', 'client', steer);
		return uci.save().then(function() { return uci.apply(); }).then(function() {
			return fs.exec('/etc/init.d/meow-arp', ['restart']).catch(function() {});
		}).then(function() {
			ui.addTimeLimitedNotification(null, E('p', _('Client settings applied.')), 3000, 'info');
		});
	}
});
