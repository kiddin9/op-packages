'use strict';
'require form';
'require view';
'require uci';
'require ui';
'require dom';
'require tools.widgets as widgets';
'require uqr';

/*
	Copyright 2026 Rafał Wabik - IceG - From eko.one.pl forum
	
	Licensed to the GNU General Public License v3.0.
*/

let DEFAULTS = {
	ssid:          'Guest-WiFi',
	encryption:    'psk2',
	password:      '',
	radio:         'radio0',
	isolate:       '1',
	macaddr:       '',
	ip:            '172.16.0.1',
	netmask:       '255.240.0.0',
	dhcpStart:     '100',
	dhcpLimit:     '150',
	dhcpLease:     '12h',
	fwForwardDest: 'wan',
	fwInput:       'REJECT',
	fwOutput:      'ACCEPT',
	fwForward:     'REJECT',
	fwDhcpPorts:   '67-68',
	fwDnsPort:     '53'
};

let OWNER_TAG = 'guest_owner';

function addGuestWifiStyles() {
	let style = document.createElement('style');
	style.type = 'text/css';
	style.textContent = '\
		:root {\
			--gw-badge-on-bg:      #34c759;\
			--gw-badge-off-bg:     #7f8c8d;\
			--gw-badge-text:       #ffffff;\
			--gw-badge-shadow:     0 1px 2px rgba(0,0,0,.4), 0 2px 6px rgba(0,0,0,.25);\
			--gw-badge-border-on:  transparent;\
			--gw-badge-border-off: transparent;\
		}\
		:root[data-darkmode="true"] {\
			--gw-badge-on-bg:      rgba(46,204,113,0.28);\
			--gw-badge-off-bg:     rgba(255,255,255,0.12);\
			--gw-badge-text:       #e5e7eb;\
			--gw-badge-shadow:     0 1px 2px rgba(0,0,0,.35), 0 2px 6px rgba(0,0,0,.22);\
			--gw-badge-border-on:  rgba(46,204,113,0.5);\
			--gw-badge-border-off: rgba(255,255,255,0.3);\
		}\
		.gw-badge {\
			display:inline-block;\
			padding:4px 10px;\
			border-radius:4px;\
			color:var(--gw-badge-text);\
			font-size:13px;\
			font-weight:500;\
			white-space:nowrap;\
			text-align:center;\
			border:1px solid transparent;\
			text-shadow:var(--gw-badge-shadow);\
		}\
		.gw-badge-on  { background:var(--gw-badge-on-bg);  border-color:var(--gw-badge-border-on);  }\
		.gw-badge-off { background:var(--gw-badge-off-bg); border-color:var(--gw-badge-border-off); }\
	';
	document.head.appendChild(style);
}

function ssidBadge(section_id, text) {
	let val = uci.get('guestwifi', section_id, 'enable');
	let enabled = (val == null) ? true : (val === '1');
	let cls = 'gw-badge ' + (enabled ? 'gw-badge-on' : 'gw-badge-off');
	return E('span', { 'class': cls }, text || '');
}

function radioBadge(section_id, radioName, wifiDevices) {
	let val = uci.get('guestwifi', section_id, 'enable');
	let enabled = (val == null) ? true : (val === '1');
	let label = radioLabel(radioName, wifiDevices);

	return E('span', { 'class': 'ifacebadge' }, [
		E('img', { 'src': L.resource('icons/wifi%s.svg').format(enabled ? '' : '_disabled') }),
		' ',
		label,
		'\u00A0'
	]);
}

let ENCRYPTION_MODES = [
	['psk2',       'WPA2-PSK'],
	['sae',        'WPA3-SAE'],
	['sae-mixed',  'WPA2-PSK/WPA3-SAE ' + _('Mixed Mode')],
	['psk-mixed',  'WPA-PSK/WPA2-PSK ' + _('Mixed Mode')],
	['psk',        'WPA-PSK'],
	['owe',        'OWE (' + _('Enhanced Open') + ')'],
	['wep-open',   _('WEP Open System')],
	['wep-shared', _('WEP Shared Key')],
	['none',       _('No encryption (open network)')]
];

function encryptionLabel(key) {
	let hit = ENCRYPTION_MODES.filter(function(m) { return m[0] === key; })[0];
	return hit ? hit[1] : key;
}

let PASSWORD_CHARSETS = {
	upper:   'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
	lower:   'abcdefghijklmnopqrstuvwxyz',
	digits:  '1234567890',
	special: '!@#$%^&*()-_=+[]{}?'
};

function secureRandomInt(max) {
	let cryptoObj = window.crypto || window.msCrypto;
	let arr = new Uint32Array(1);

	if (cryptoObj && cryptoObj.getRandomValues) {
		cryptoObj.getRandomValues(arr);
		return arr[0] % max;
	}

	return Math.floor(Math.random() * max);
}

function shuffleArray(arr) {
	for (let i = arr.length - 1; i > 0; i--) {
		let j = secureRandomInt(i + 1);
		let tmp = arr[i];
		arr[i] = arr[j];
		arr[j] = tmp;
	}
	return arr;
}

function generateStrongPassword(length, components) {
	let chosenSets = (components || []).map(function(c) { return PASSWORD_CHARSETS[c]; }).filter(Boolean);

	if (!chosenSets.length)
		chosenSets = [PASSWORD_CHARSETS.lower, PASSWORD_CHARSETS.digits];

	length = Math.max(parseInt(length, 10) || 0, chosenSets.length);
	length = Math.min(Math.max(length, 8), 63);

	let pool = chosenSets.join('');
	let result = chosenSets.map(function(set) { return set.charAt(secureRandomInt(set.length)); });

	for (let i = result.length; i < length; i++)
		result.push(pool.charAt(secureRandomInt(pool.length)));

	return shuffleArray(result).join('');
}

let cbiPasswordComponentsValue = form.ListValue.extend({
	renderWidget: function(section_id, option_index, cfgvalue) {
		let choices = this.transformChoices();
		let widget = new ui.Dropdown(
			(cfgvalue != null) ? cfgvalue : this.default,
			choices,
			{
				id: this.cbid(section_id),
				sort: this.keylist,
				optional: true,
				multiple: true,
				display_items: 4,
				dropdown_items: 4,
				select_placeholder: this.placeholder,
				validate: L.bind(this.validate, this, section_id),
				disabled: (this.readonly != null) ? this.readonly : this.map.readonly
			}
		);

		window.__guestPasswordComponentsDropdown = window.__guestPasswordComponentsDropdown || {};
		window.__guestPasswordComponentsDropdown[section_id] = widget;

		return widget.render();
	}
});

function buildSVGQRCode(data, code, options, dummy) {
	let opts = Object.assign({
		pixelSize: 4,
		whiteColor: 'white',
		blackColor: 'black',
		ecc: 'M'
	}, options);

	let svg = uqr.renderSVG(data, opts);

	if (dummy)
		return svg;

	code.style.opacity = '';
	dom.content(code, Object.assign(E(svg), { style: 'width:100%;height:auto' }));
}

function assignNetIndexes() {
	let defs = uci.sections('guestwifi', 'guest');
	let used = {};

	defs.forEach(function(def) {
		let idx = parseInt(def.net_idx, 10);
		if (idx > 0)
			used[idx] = true;
	});

	let nextIdx = 1;
	function takeNextFreeIdx() {
		while (used[nextIdx]) nextIdx++;
		used[nextIdx] = true;
		return nextIdx;
	}

	defs.forEach(function(def) {
		let idx = parseInt(def.net_idx, 10);
		if (!(idx > 0))
			uci.set('guestwifi', def['.name'], 'net_idx', String(takeNextFreeIdx()));
	});
}

function namesForNetIndex(idx) {
	let suf = (idx > 1) ? String(idx) : '';
	return {
		networkName: 'guest'     + (suf ? '_' + suf : ''),
		deviceName:  'br-guest'  + suf,
		wifiName:    'guestwifi' + (suf ? '_' + suf : ''),
		dhcpName:    'guest'     + (suf ? '_' + suf : '')
	};
}

let IP_POOL_FIRST_OCTET  = 172;
let IP_POOL_SECOND_FIRST = 16;
let IP_POOL_SECOND_LAST  = 31;

function usedInterfaceIps(excludeSid) {
	let used = {};

	uci.sections('guestwifi', 'guest').forEach(function(s) {
		if (s['.name'] === excludeSid) return;
		if (s.interface_ip) used[s.interface_ip] = true;
	});
	uci.sections('network', 'interface').forEach(function(s) {
		if (excludeSid != null && s[OWNER_TAG] === excludeSid) return;
		if (s.ipaddr) used[s.ipaddr] = true;
	});

	return used;
}

function randomFreeGuestIp(excludeSid) {
	let used = usedInterfaceIps(excludeSid);
	let candidates = [];

	for (let o2 = IP_POOL_SECOND_FIRST; o2 <= IP_POOL_SECOND_LAST; o2++) {
		let ip = IP_POOL_FIRST_OCTET + '.' + o2 + '.0.1';
		if (!used[ip])
			candidates.push(ip);
	}

	if (!candidates.length)
		return null;

	return candidates[Math.floor(Math.random() * candidates.length)];
}

function bandLabelForDevice(dev) {
	if (!dev)
		return '';

	let band = dev.band;
	if (band === '2g') return '2.4 GHz';
	if (band === '5g') return '5 GHz';
	if (band === '6g') return '6 GHz';

	let hw = dev.hwmode || '';
	if (/^11a/.test(hw) && !/^11ax/.test(hw)) {
		return '5 GHz';
	}
	if (/^11(b|g)/.test(hw))
		return '2.4 GHz';

	let htmode = dev.htmode || '';
	if (/^HE160|HE80|VHT/.test(htmode))
		return '5 GHz';

	return '';
}

function radioLabel(radioName, wifiDevices) {
	let dev = wifiDevices.filter(function(d) { return d['.name'] === radioName; })[0];
	let band = bandLabelForDevice(dev);
	return band ? (radioName + ' (' + band + ')') : radioName;
}

function uciDeleteMatching(config, type, field, value) {
	uci.sections(config, type).forEach(function(s) {
		if (s[field] === value)
			uci.remove(config, s['.name']);
	});
}

function cleanupGuestConfig(validSids, ownerSid) {
	function shouldRemove(s) {
		let owner = s[OWNER_TAG];
		if (!owner)
			return false;
		if (ownerSid != null)
			return owner === ownerSid;
		return validSids.indexOf(owner) === -1;
	}

	uci.sections('network', 'interface').forEach(function(s) {
		if (shouldRemove(s)) uci.remove('network', s['.name']);
	});
	uci.sections('network', 'device').forEach(function(s) {
		if (shouldRemove(s)) uci.remove('network', s['.name']);
	});
	uci.sections('wireless', 'wifi-iface').forEach(function(s) {
		if (shouldRemove(s)) uci.remove('wireless', s['.name']);
	});
	uci.sections('dhcp', 'dhcp').forEach(function(s) {
		if (shouldRemove(s)) uci.remove('dhcp', s['.name']);
	});
	uci.sections('firewall', 'zone').forEach(function(s) {
		if (shouldRemove(s)) uci.remove('firewall', s['.name']);
	});
	uci.sections('firewall', 'forwarding').forEach(function(s) {
		if (shouldRemove(s)) uci.remove('firewall', s['.name']);
	});
	uci.sections('firewall', 'rule').forEach(function(s) {
		if (shouldRemove(s)) uci.remove('firewall', s['.name']);
	});
}

function collectOwnerSids() {
	let sids = {};

	uci.sections('network', 'interface').forEach(function(s) { if (s[OWNER_TAG]) sids[s[OWNER_TAG]] = true; });
	uci.sections('network', 'device').forEach(function(s) { if (s[OWNER_TAG]) sids[s[OWNER_TAG]] = true; });
	uci.sections('wireless', 'wifi-iface').forEach(function(s) { if (s[OWNER_TAG]) sids[s[OWNER_TAG]] = true; });
	uci.sections('dhcp', 'dhcp').forEach(function(s) { if (s[OWNER_TAG]) sids[s[OWNER_TAG]] = true; });
	uci.sections('firewall', 'zone').forEach(function(s) { if (s[OWNER_TAG]) sids[s[OWNER_TAG]] = true; });
	uci.sections('firewall', 'forwarding').forEach(function(s) { if (s[OWNER_TAG]) sids[s[OWNER_TAG]] = true; });
	uci.sections('firewall', 'rule').forEach(function(s) { if (s[OWNER_TAG]) sids[s[OWNER_TAG]] = true; });

	return Object.keys(sids);
}

function importGuestNetwork(sid) {
	let iface = uci.sections('network', 'interface').filter(function(s) { return s[OWNER_TAG] === sid; })[0];
	let dhcp  = uci.sections('dhcp', 'dhcp').filter(function(s) { return s[OWNER_TAG] === sid; })[0];
	let wifi  = uci.sections('wireless', 'wifi-iface').filter(function(s) { return s[OWNER_TAG] === sid; })[0];
	let zone  = uci.sections('firewall', 'zone').filter(function(s) { return s[OWNER_TAG] === sid; })[0];
	let fwd   = uci.sections('firewall', 'forwarding').filter(function(s) { return s[OWNER_TAG] === sid; })[0];
	let rules = uci.sections('firewall', 'rule').filter(function(s) { return s[OWNER_TAG] === sid; });

	let dhcpRule = rules.filter(function(r) { return r.proto === 'udp'; })[0];
	let dnsRule  = rules.filter(function(r) { return r.proto === 'tcpudp'; })[0];

	uci.add('guestwifi', 'guest', sid);
	uci.set('guestwifi', sid, 'enable', (wifi && wifi.disabled === '1') ? '0' : '1');

	if (wifi) {
		uci.set('guestwifi', sid, 'ssid', wifi.ssid || DEFAULTS.ssid);
		uci.set('guestwifi', sid, 'radio', wifi.device || DEFAULTS.radio);
		uci.set('guestwifi', sid, 'isolate', wifi.isolate || DEFAULTS.isolate);
		if (wifi.macaddr)
			uci.set('guestwifi', sid, 'macaddr', wifi.macaddr);

		if (!wifi.encryption || wifi.encryption === 'none' || wifi.encryption === 'owe') {
			uci.set('guestwifi', sid, 'encryption', wifi.encryption || 'none');
		} else if (wifi.encryption === 'wep-open' || wifi.encryption === 'wep-shared') {
			uci.set('guestwifi', sid, 'encryption', wifi.encryption);
			uci.set('guestwifi', sid, 'password', wifi.key1 || DEFAULTS.password);
		} else {
			uci.set('guestwifi', sid, 'encryption', wifi.encryption);
			uci.set('guestwifi', sid, 'password', wifi.key || DEFAULTS.password);
		}
	}

	if (iface) {
		uci.set('guestwifi', sid, 'interface_ip', iface.ipaddr || DEFAULTS.ip);
		uci.set('guestwifi', sid, 'netmask', iface.netmask || DEFAULTS.netmask);
	}

	if (dhcp) {
		uci.set('guestwifi', sid, 'dhcp_start', dhcp.start || DEFAULTS.dhcpStart);
		uci.set('guestwifi', sid, 'dhcp_limit', dhcp.limit || DEFAULTS.dhcpLimit);
		uci.set('guestwifi', sid, 'dhcp_lease', dhcp.leasetime || DEFAULTS.dhcpLease);
	}

	if (zone) {
		uci.set('guestwifi', sid, 'fw_input', zone.input || DEFAULTS.fwInput);
		uci.set('guestwifi', sid, 'fw_output', zone.output || DEFAULTS.fwOutput);
		uci.set('guestwifi', sid, 'fw_forward', zone.forward || DEFAULTS.fwForward);
	}

	if (fwd) {
		uci.set('guestwifi', sid, 'fw_forward_dest', fwd.dest || DEFAULTS.fwForwardDest);
	}

	if (dhcpRule) {
		uci.set('guestwifi', sid, 'fw_dhcp_ports', dhcpRule.dest_port || DEFAULTS.fwDhcpPorts);
	}

	if (dnsRule) {
		uci.set('guestwifi', sid, 'fw_dns_port', dnsRule.dest_port || DEFAULTS.fwDnsPort);
	}
}

function knownGuestSids() {
	return uci.sections('guestwifi', 'guest').map(function(s) { return s['.name']; });
}

function resolveDuplicateInterfaceIps() {
	let seen = {};

	uci.sections('guestwifi', 'guest').forEach(function(def) {
		let sid = def['.name'];
		let ip  = def.interface_ip;
		if (!ip) return;

		if (seen[ip]) {
			let newIp = randomFreeGuestIp(sid);
			if (newIp) {
				uci.set('guestwifi', sid, 'interface_ip', newIp);
				seen[newIp] = true;
			}
		} else {
			seen[ip] = true;
		}
	});
}

function guessLegacyInterfaceNames() {
	return uci.sections('network', 'interface').filter(function(s) {
		if (s[OWNER_TAG]) return false;
		if (/^cfg[0-9a-f]+$/i.test(s['.name'])) return false;
		return /guest/i.test(s['.name']) || /guest/i.test(s.device || '');
	}).map(function(s) { return s['.name']; });
}

function zoneMatchesNetwork(zone, ifname) {
	let net = zone.network;
	if (Array.isArray(net)) return net.indexOf(ifname) !== -1;
	return net === ifname;
}

function importLegacyGuestNetwork(ifname) {
	let sid = ifname;

	uci.set('network', ifname, OWNER_TAG, sid);

	let iface = uci.sections('network', 'interface').filter(function(s) { return s['.name'] === ifname; })[0];
	let deviceName = iface ? iface.device : null;

	if (deviceName) {
		let dev = uci.sections('network', 'device').filter(function(d) { return d.name === deviceName; })[0];
		if (dev) uci.set('network', dev['.name'], OWNER_TAG, sid);
	}

	let dhcp = uci.sections('dhcp', 'dhcp').filter(function(d) { return d.interface === ifname; })[0];
	if (dhcp) uci.set('dhcp', dhcp['.name'], OWNER_TAG, sid);

	let wifi = uci.sections('wireless', 'wifi-iface').filter(function(w) { return w.network === ifname; })[0];
	if (wifi) uci.set('wireless', wifi['.name'], OWNER_TAG, sid);

	let zone = uci.sections('firewall', 'zone').filter(function(z) { return zoneMatchesNetwork(z, ifname); })[0];
	if (zone) {
		uci.set('firewall', zone['.name'], OWNER_TAG, sid);

		let zoneName = zone.name || zone['.name'];
		uci.sections('firewall', 'forwarding').forEach(function(f) {
			if (f.src === zoneName) uci.set('firewall', f['.name'], OWNER_TAG, sid);
		});
		uci.sections('firewall', 'rule').forEach(function(r) {
			if (r.src === zoneName) uci.set('firewall', r['.name'], OWNER_TAG, sid);
		});
	}

	importGuestNetwork(sid);
}

function importExistingGuestNetworks() {
	collectOwnerSids().forEach(function(sid) {
		if (knownGuestSids().indexOf(sid) === -1)
			importGuestNetwork(sid);
	});

	guessLegacyInterfaceNames().forEach(function(ifname) {
		if (knownGuestSids().indexOf(ifname) === -1)
			importLegacyGuestNetwork(ifname);
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('network'),
			uci.load('wireless'),
			uci.load('dhcp'),
			uci.load('firewall'),
			uci.load('guestwifi')
		]).then(function() {
			importExistingGuestNetworks();
		});
	},

	buildGuestNetwork: function(sid) {
		let get = function(name, def) { return uci.get('guestwifi', sid, name) || def; };

		let enabled    = get('enable', '1') === '1';
		let ssid       = get('ssid', DEFAULTS.ssid);
		let encryption = get('encryption', DEFAULTS.encryption);
		let password   = get('password', DEFAULTS.password);
		let radio      = get('radio', DEFAULTS.radio);
		let isolate    = get('isolate', DEFAULTS.isolate);
		let macaddr    = get('macaddr', DEFAULTS.macaddr);
		let ip         = get('interface_ip', DEFAULTS.ip);
		let netmask    = get('netmask', DEFAULTS.netmask);
		let dhcpStart  = get('dhcp_start', DEFAULTS.dhcpStart);
		let dhcpLimit  = get('dhcp_limit', DEFAULTS.dhcpLimit);
		let dhcpLease  = get('dhcp_lease', DEFAULTS.dhcpLease);
		let fwDest     = get('fw_forward_dest', DEFAULTS.fwForwardDest);
		let fwInput    = get('fw_input', DEFAULTS.fwInput);
		let fwOutput   = get('fw_output', DEFAULTS.fwOutput);
		let fwForward  = get('fw_forward', DEFAULTS.fwForward);
		let fwDhcpPorts= get('fw_dhcp_ports', DEFAULTS.fwDhcpPorts);
		let fwDnsPort  = get('fw_dns_port', DEFAULTS.fwDnsPort);

		let netIdx = parseInt(get('net_idx', ''), 10);
		let names  = namesForNetIndex(netIdx > 0 ? netIdx : 1);
		let networkName = names.networkName;
		let deviceName  = names.deviceName;
		let wifiName    = names.wifiName;
		let dhcpName    = names.dhcpName;

		// NETWORK
		uci.add('network', 'interface', networkName);
		uci.set('network', networkName, OWNER_TAG, sid);
		uci.set('network', networkName, 'device', deviceName);
		uci.set('network', networkName, 'proto', 'static');
		uci.set('network', networkName, 'ipaddr', ip);
		uci.set('network', networkName, 'netmask', netmask);

		let devSid = uci.add('network', 'device');
		uci.set('network', devSid, OWNER_TAG, sid);
		uci.set('network', devSid, 'name', deviceName);
		uci.set('network', devSid, 'type', 'bridge');
		uci.set('network', devSid, 'bridge_empty', '1');

		// DHCP
		uci.add('dhcp', 'dhcp', dhcpName);
		uci.set('dhcp', dhcpName, OWNER_TAG, sid);
		uci.set('dhcp', dhcpName, 'start', dhcpStart);
		uci.set('dhcp', dhcpName, 'limit', dhcpLimit);
		uci.set('dhcp', dhcpName, 'leasetime', dhcpLease);
		uci.set('dhcp', dhcpName, 'interface', networkName);
		uci.set('dhcp', dhcpName, 'dhcpv4', 'server');

		uci.set('dhcp', dhcpName, 'ignore', enabled ? '0' : '1');

		// WIRELESS
		uci.add('wireless', 'wifi-iface', wifiName);
		uci.set('wireless', wifiName, OWNER_TAG, sid);
		uci.set('wireless', wifiName, 'device', radio);
		uci.set('wireless', wifiName, 'mode', 'ap');
		uci.set('wireless', wifiName, 'network', networkName);
		uci.set('wireless', wifiName, 'ssid', ssid);
		uci.set('wireless', wifiName, 'isolate', isolate);

		if (macaddr)
		uci.set('wireless', wifiName, 'macaddr', macaddr);
		uci.set('wireless', wifiName, 'disabled', enabled ? '0' : '1');

		if (encryption === 'none' || encryption === 'owe') {
			uci.set('wireless', wifiName, 'encryption', encryption);
		} else if (encryption === 'wep-open' || encryption === 'wep-shared') {
			uci.set('wireless', wifiName, 'encryption', encryption);
			uci.set('wireless', wifiName, 'key', '1');
			uci.set('wireless', wifiName, 'key1', password);
		} else {
			uci.set('wireless', wifiName, 'encryption', encryption);
			uci.set('wireless', wifiName, 'key', password);
		}

		// FIREWALL
		let zoneSid = uci.add('firewall', 'zone');
		uci.set('firewall', zoneSid, OWNER_TAG, sid);
		uci.set('firewall', zoneSid, 'name', networkName);
		uci.set('firewall', zoneSid, 'network', [ networkName ]);
		uci.set('firewall', zoneSid, 'input', fwInput);
		uci.set('firewall', zoneSid, 'output', fwOutput);
		uci.set('firewall', zoneSid, 'forward', fwForward);

		let fwdSid = uci.add('firewall', 'forwarding');
		uci.set('firewall', fwdSid, OWNER_TAG, sid);
		uci.set('firewall', fwdSid, 'src', networkName);
		uci.set('firewall', fwdSid, 'dest', fwDest);

		// Rule: DHCP
		let dhcpRuleSid = uci.add('firewall', 'rule');
		uci.set('firewall', dhcpRuleSid, OWNER_TAG, sid);
		uci.set('firewall', dhcpRuleSid, 'src', networkName);
		uci.set('firewall', dhcpRuleSid, 'proto', 'udp');
		uci.set('firewall', dhcpRuleSid, 'src_port', fwDhcpPorts);
		uci.set('firewall', dhcpRuleSid, 'dest_port', fwDhcpPorts);
		uci.set('firewall', dhcpRuleSid, 'target', 'ACCEPT');
		uci.set('firewall', dhcpRuleSid, 'family', 'ipv4');

		// Rule: DNS
		let dnsRuleSid = uci.add('firewall', 'rule');
		uci.set('firewall', dnsRuleSid, OWNER_TAG, sid);
		uci.set('firewall', dnsRuleSid, 'src', networkName);
		uci.set('firewall', dnsRuleSid, 'dest_port', fwDnsPort);
		uci.set('firewall', dnsRuleSid, 'target', 'ACCEPT');
		uci.set('firewall', dnsRuleSid, 'family', 'ipv4');
		uci.set('firewall', dnsRuleSid, 'proto', 'tcpudp');
	},

	applyAll: function(m) {
		let self = this;

		return m.save().then(function() {
			resolveDuplicateInterfaceIps();

			assignNetIndexes();

			let defs = uci.sections('guestwifi', 'guest');
			let validSids = defs.map(function(s) { return s['.name']; });

			cleanupGuestConfig(validSids, null);

			defs.forEach(function(def) {
				let sid = def['.name'];
				cleanupGuestConfig(validSids, sid);
				self.buildGuestNetwork(sid);
			});

			return uci.save();
		}).then(function() {
			return ui.changes.apply(false);
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, _('Error saving configuration:') + ' ' + err.message), 'error');
		});
	},

	render: function() {
		let self = this;

		addGuestWifiStyles();

		let wifiDevices = uci.sections('wireless', 'wifi-device');
		let radios = wifiDevices.map(function(d) { return d['.name']; });
		if (!radios.length)
			radios = ['radio0', 'radio1', 'radio2'];

		let m = new form.Map('guestwifi', _('Guest Wi-Fi'),
			_('A user interface for easily creating and management isolated Wi-Fi networks for guests, each with its own access point, DHCP, and firewall rules.'));

		self.map = m;

		let s = m.section(form.GridSection, 'guest', _('Guest networks'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.addbtntitle = _('Add new guest network...');

		s.tab('general', _('General'));
		s.tab('security', _('Security'));
		s.tab('network', _('Network & DHCP'));
		s.tab('firewall', _('Firewall'));

		let o = s.taboption('general', form.Flag, 'enable', _('Enabled'),
			_('Enable guest network.'));
		o.rmempty = false;
		o.default = '1';
		o.editable = true;

		o = s.taboption('general', form.Value, 'ssid', _('Network name (SSID)'));
		o.rmempty = false;
		o.default = DEFAULTS.ssid;
		o.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default;
			return ssidBadge(section_id, val);
		};

		o = s.taboption('general', form.ListValue, 'radio', _('Radio'),
			_('The radio on which the guest network will work.'));
		radios.forEach(function(r) { o.value(r, radioLabel(r, wifiDevices)); });
		o.default = DEFAULTS.radio;
		o.rmempty = false;
		o.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default;
			return radioBadge(section_id, val, wifiDevices);
		};

		o = s.taboption('security', form.ListValue, 'encryption', _('Encryption'),
			_('WPA2-PSK is recommended for most devices. WPA3-SAE offers the strongest security but requires WPA3-capable clients.'));
		ENCRYPTION_MODES.forEach(function(m) { o.value(m[0], m[1]); });
		o.default = DEFAULTS.encryption;
		o.rmempty = false;
		o.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default;
			return encryptionLabel(val);
		};

		o = s.taboption('network', form.Value, 'interface_ip', _('Interface IP address'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.default = DEFAULTS.ip;
		o.cfgvalue = function(section_id) {
			let val = uci.get('guestwifi', section_id, 'interface_ip');
			if (val) return val;
			return randomFreeGuestIp(section_id) || DEFAULTS.ip;
		};

		o.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default;
			return E('code', {}, val);
		};
		o.validate = function(section_id, value) {
			if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(value))
				return true;

			let used = usedInterfaceIps(section_id);
			if (!used[value])
				return true;

			let newIp = randomFreeGuestIp(section_id);
			if (!newIp) {
				return _('The address %s is already in use and no free address is available in the 172.16.0.1 - 172.31.0.1 range.').format(value);
			}

			let el = this.getUIElement(section_id);
			if (el) el.setValue(newIp);
			return true;
		};

		o = s.taboption('network', form.Value, 'netmask', _('Netmask'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.default = DEFAULTS.netmask;
		o.modalonly = true;

		o = s.taboption('network', form.Value, 'dhcp_start', _('DHCP range start'),
			_('Lowest leased address, as offset from the network address.'));
		o.datatype = 'uinteger';
		o.rmempty = false;
		o.default = DEFAULTS.dhcpStart;
		o.modalonly = true;

		o = s.taboption('network', form.Value, 'dhcp_limit', _('DHCP client limit'),
			_('Maximum number of leased addresses.'));
		o.datatype = 'uinteger';
		o.rmempty = false;
		o.default = DEFAULTS.dhcpLimit;
		o.modalonly = true;

		o = s.taboption('network', form.Value, 'dhcp_lease', _('DHCP lease time'),
			_('E.g. "1h", "30m", "12h". Minimum is "2m".'));
		o.rmempty = false;
		o.default = DEFAULTS.dhcpLease;

		o = s.taboption('security', form.Value, 'password', _('Password'), ' ');
		o.password = true;
		o.depends('encryption', 'psk');
		o.depends('encryption', 'psk2');
		o.depends('encryption', 'psk-mixed');
		o.depends('encryption', 'sae');
		o.depends('encryption', 'sae-mixed');
		o.depends('encryption', 'wep-open');
		o.depends('encryption', 'wep-shared');
		o.default = DEFAULTS.password;
		o.modalonly = true;
		o.validate = function(section_id, value) {
			let enc = this.map.lookupOption('encryption', section_id)[0].formvalue(section_id);

			let inputEl = document.getElementById(this.cbid(section_id));
			let strength = inputEl ? inputEl.parentNode.querySelector('.cbi-value-description') : null;
			let strongRegex = new RegExp("^(?=.{8,})(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*\\W).*$", "g"),
			    mediumRegex = new RegExp("^(?=.{7,})(((?=.*[A-Z])(?=.*[a-z]))|((?=.*[A-Z])(?=.*[0-9]))|((?=.*[a-z])(?=.*[0-9]))).*$", "g"),
			    enoughRegex = new RegExp("(?=.{6,}).*", "g");

			if (strength) {
				if (!value || !value.length)
					strength.innerHTML = '';
				else if (false == enoughRegex.test(value))
					strength.innerHTML = '%s: <span style="color:red">%s</span>'.format(_('Password strength'), _('More Characters'));
				else if (strongRegex.test(value))
					strength.innerHTML = '%s: <span style="color:green">%s</span>'.format(_('Password strength'), _('Strong'));
				else if (mediumRegex.test(value))
					strength.innerHTML = '%s: <span style="color:orange">%s</span>'.format(_('Password strength'), _('Medium'));
				else
					strength.innerHTML = '%s: <span style="color:red">%s</span>'.format(_('Password strength'), _('Weak'));
			}

			if (!value)
				return true;

			if (enc === 'wep-open' || enc === 'wep-shared') {
				let isHex = /^[0-9a-fA-F]+$/.test(value);
				let validLength = isHex ? (value.length === 10 || value.length === 26)
				                        : (value.length === 5 || value.length === 13);
				if (!validLength)
					return _('WEP key must be 5 or 13 ASCII characters, or 10 or 26 hexadecimal digits.');
				return true;
			}

			if (enc !== 'none' && enc !== 'owe' && value.length < 8)
				return _('Password must be at least 8 characters long (WPA-PSK/WPA2-PSK/WPA3-SAE).');

			return true;
		};

		let passwordDependsOn = function(opt) {
			opt.depends('encryption', 'psk');
			opt.depends('encryption', 'psk2');
			opt.depends('encryption', 'psk-mixed');
			opt.depends('encryption', 'sae');
			opt.depends('encryption', 'sae-mixed');
			opt.depends('encryption', 'wep-open');
			opt.depends('encryption', 'wep-shared');
		};

		o = s.taboption('security', form.Value, 'password_length', _('Password length'),
			_('Minimum length is 8 characters, 13 characters recommended.'));
		o.datatype = 'range(8,63)';
		o.default = '13';
		o.rmempty = true;
		o.modalonly = true;
		passwordDependsOn(o);

		o = s.taboption('security', cbiPasswordComponentsValue, 'password_components', _('Password composition'),
			_('Character types to use when generating a password.'));
		o.value('upper',   _('Uppercase letters'));
		o.value('lower',   _('Lowercase letters'));
		o.value('digits',  _('Digits'));
		o.value('special', _('Special characters'));
		o.default = ['upper', 'lower', 'digits', 'special'];
		o.placeholder = _('Select password components...');
		o.rmempty = true;
		o.modalonly = true;
		passwordDependsOn(o);

		o = s.taboption('security', form.Button, '_password_generate', _('Generate password'));
		o.inputtitle = _('Generate');
		o.inputstyle = 'action';
		o.modalonly = true;
		passwordDependsOn(o);
		o.onclick = function(ev, section_id) {
			let section = this.section;
			let lengthEl = section.getUIElement(section_id, 'password_length');
			let componentsEl = section.getUIElement(section_id, 'password_components');
			let passwordEl = section.getUIElement(section_id, 'password');

			let length = lengthEl ? parseInt(lengthEl.getValue(), 10) : 16;
			let components = componentsEl ? componentsEl.getValue() : [];

			if (!Array.isArray(components))
				components = components ? [components] : [];

			let newPassword = generateStrongPassword(length, components);

			if (passwordEl) {
				passwordEl.setValue(newPassword);
				if (typeof passwordEl.triggerValidation === 'function')
					passwordEl.triggerValidation();
			}
		};

		o = s.taboption('security', form.DummyValue, '_qrops', _('QR Code'),
			_('Generates a QR code with the guest network data (SSID, encryption, password) so a client device can scan and connect.'));
		o.modalonly = true;

		o.createWiFiPassword = function(section_id) {
			function pctEncode(str) {
				let bytes = new TextEncoder().encode(str);
				let out = '';

				for (let i = 0; i < bytes.length; i++) {
					let b = bytes[i];
					let printable = (b >= 0x20 && b <= 0x3A && b !== 0x3B) || (b >= 0x3C && b <= 0x7E);

					if (printable)
						out += String.fromCharCode(b);
					else
						out += '%' + b.toString(16).toUpperCase().padStart(2, '0');
				}

				return out;
			}

			let wifiSSID = this.section.formvalue(section_id, 'ssid');
			let wifiEncr = this.section.formvalue(section_id, 'encryption') || '';
			let wifiKey  = this.section.formvalue(section_id, 'password');

			let trdisable = '';
			if (wifiEncr === 'sae') trdisable = 0;
			else if (wifiEncr === 'owe') trdisable = 3;

			return [
				'WIFI:',
				(wifiKey) ? 'T:WPA;' : null,
				(trdisable !== '') ? 'R:' + trdisable + ';' : null,
				'S:' + wifiSSID + ';',
				(wifiKey) ? 'P:' + pctEncode(wifiKey) + ';' : null
			].filter(Boolean).join('') + ';';
		};

		o.handleGenerateQR = function(section_id, ev) {
			let parent = s.map;
			let mapNode = document.querySelector('body.modal-overlay-active > #modal_overlay > .modal.cbi-modal > .cbi-map:not(.hidden)');
			let headNode = mapNode.parentNode.querySelector('h4');
			let wifiQRGenerator = this.createWiFiPassword.bind(this, section_id);

			return Promise.all([
				parent.save(null, true)
			]).then(function() {
				let qrm, qrs, qro;

				qrm = new form.JSONMap({ qrcode: {} }, null, _('Scan this QR code with the client device.'));
				qrm.parent = parent;

				qrs = qrm.section(form.NamedSection, 'qrcode');

				function handleQRParamChange(ev, section_id, value) {
					let code = this.map.findElement('.qr-code');
					let conf = this.map.findElement('.wifi-qr-code-content');
					let ecc = this.section.getUIElement(section_id, 'ecc');

					if (this.isValid(section_id)) {
						conf.firstChild.data = wifiQRGenerator(section_id);
						code.style.opacity = '.5';
						buildSVGQRCode(conf.firstChild.data, code, { ecc: ecc.getValue() });
					}
				}

				qro = qrs.option(form.ListValue, 'ecc', _('QR Error Correction Code Level'));
				qro.value('L', _('Low'));
				qro.value('M', _('Medium'));
				qro.value('Q', _('Quartile'));
				qro.value('H', _('High'));
				qro.onchange = handleQRParamChange;

				qro = qrs.option(form.DummyValue, 'output');
				qro.renderWidget = function() {
					let wifi_qr = wifiQRGenerator(section_id);
					let ecc = this.section.formvalue(section_id, 'ecc');

					return E('div', {
						'class': 'qr-code-display',
						'style': 'display:flex; flex-wrap:wrap; align-items:center; gap:.5em'
					}, [
						E('div', { 'class': 'qr-code' }, [
							E(buildSVGQRCode(wifi_qr, null, { ecc: ecc || undefined }, true))
						]),
						E('pre', {
							'class': 'wifi-qr-code-content',
							'style': 'flex:1; overflow:auto; word-break:break-all;',
							'click': function(ev) {
								let sel = window.getSelection();
								let range = document.createRange();

								range.selectNodeContents(ev.currentTarget);

								sel.removeAllRanges();
								sel.addRange(range);
							}
						}, [wifi_qr])
					]);
				};

				return qrm.render().then(function(nodes) {
					let dStyle = mapNode.style;
					mapNode.style.display = 'none';

					let bRowStyle = mapNode.nextElementSibling.style;
					mapNode.nextElementSibling.style.display = 'none';

					headNode.appendChild(E('span', [' » ', _('Generate guest WiFi QR…')]));
					mapNode.parentNode.appendChild(E([], [
						nodes,
						E('div', { 'class': 'right' }, [
							E('button', {
								'class': 'btn',
								'click': function() {
									nodes.parentNode.removeChild(nodes.nextSibling);
									nodes.parentNode.removeChild(nodes);
									mapNode.style = dStyle;
									mapNode.nextSibling.style = bRowStyle;
									headNode.removeChild(headNode.lastChild);
								}
							}, [_('Back to settings')])
						])
					]));
				});
			});
		};

		o.cfgvalue = function(section_id) {
			return E('button', {
				'class': 'btn qr-code',
				'style': 'display:inline-flex;align-items:center;gap:.5em',
				'click': ui.createHandlerFn(this, 'handleGenerateQR', section_id)
			}, [
				E(buildSVGQRCode('openwrt.org', null, { pixelSize: 1, ecc: 'L' }, true)),
				_('Generate QR…')
			]);
		};

		o = s.taboption('security', form.ListValue, 'isolate', _('Client isolation'),
			_('Blocks communication between clients on this guest network.'));
		o.value('1', _('Yes'));
		o.value('0', _('No'));
		o.default = DEFAULTS.isolate;
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('security', form.Value, 'macaddr', _('MAC address'),
			_('Override default MAC address - the range of usable addresses might be limited by the driver'));
		o.value('', _('driver default'));
		o.value('random', _('randomly generated'));
		o.datatype = "or('random',macaddr)";
		o.default = DEFAULTS.macaddr;
		o.rmempty = true;
		o.modalonly = true;

		o = s.taboption('firewall', widgets.ZoneSelect, 'fw_forward_dest', _('Forwarding destination zone'),
			_('Firewall zone guest traffic is forwarded to (usually "wan"). Pick an existing zone from the list or fill out the <em>-- custom --</em> field to enter one manually.'));
		o.rmempty = false;
		o.default = DEFAULTS.fwForwardDest;
		o.modalonly = true;

		o = s.taboption('firewall', form.ListValue, 'fw_input', _('Input'),
			_('Traffic from guests to the router itself (e.g. LuCI, SSH).'));
		o.value('REJECT', _('reject')); o.value('ACCEPT', _('accept')); o.value('DROP', _('drop'));
		o.default = DEFAULTS.fwInput;
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('firewall', form.ListValue, 'fw_output', _('Output'),
			_('Traffic from the router itself to guests. ACCEPT is recommended so router services (DHCP, DNS) keep working.'));
		o.value('REJECT', _('reject')); o.value('ACCEPT', _('accept')); o.value('DROP', _('drop'));
		o.default = DEFAULTS.fwOutput;
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('firewall', form.ListValue, 'fw_forward', _('Forward'),
			_('Traffic passing between guests and other networks/zones (e.g. LAN). Keep this REJECT or DROP to isolate guests from your LAN. ACCEPT would allow guests to reach other networks.'));
		o.value('REJECT', _('reject')); o.value('ACCEPT', _('accept')); o.value('DROP', _('drop'));
		o.default = DEFAULTS.fwForward;
		o.rmempty = false;
		o.modalonly = true;

		o = s.taboption('firewall', form.Value, 'fw_dhcp_ports', _('DHCP rule ports'),
			_('UDP port range for DHCP traffic, e.g. "67-68".'));
		o.rmempty = false;
		o.default = DEFAULTS.fwDhcpPorts;
		o.modalonly = true;

		o = s.taboption('firewall', form.Value, 'fw_dns_port', _('DNS rule port'));
		o.datatype = 'port';
		o.rmempty = false;
		o.default = DEFAULTS.fwDnsPort;
		o.modalonly = true;

		return m.render();
	},

	handleSave: function(ev) {
		return this.applyAll(this.map);
	},
	handleSaveApply: null,
	handleReset: null
});
