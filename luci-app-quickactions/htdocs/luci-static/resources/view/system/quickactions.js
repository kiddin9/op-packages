/**
 * luci-app-quickactions
 * All-in-one dashboard and system-control surface for OpenWrt / ImmortalWrt.
 *
 * Bundles 14 tabs: Dashboard, Essential, Tools, Logs, Services, Hotplug,
 * Crontab, Guest WiFi, Terminal (ttyd), Task Plan, Network Setup, Command,
 * Dependencies, Configuration.
 *
 * Licensed to the GNU General Public License v3.0.
 */

'use strict';
'require view';
'require ui';
'require uci';
'require rpc';
'require form';
'require fs';
'require poll';
'require dom';
'require uqr';
'require tools.widgets as widgets';

// =====================================================================
// LuCI 26.203 workaround — dom.data() crashes on stale data-idref nodes
//
// dom.content() deletes registry entries for every descendant with a
// data-idref attribute, but leaves the attribute on the node. Any later
// dom.data(node, key, value) on those nodes throws
//   "Cannot set properties of undefined (setting '_class')"
// which crashes form.js's CBIMap.renderContents(), the last step of
// form.Map.save(). The writes reach the server first, but the promise
// chain rejects and the UI reports failure.
//
// Reinitialize the registry slot when we detect it's been dropped.
// =====================================================================
(function patchDOMData() {
    try {
        if (!dom || dom._qaDataPatched) return;
        var _orig = dom.data;
        dom.data = function(node, key, val) {
            if (node && typeof node.getAttribute === 'function') {
                var id = node.getAttribute('data-idref');
                if (id != null && this.registry && !this.registry[id]) {
                    // Fires for BOTH the getter and setter paths. dom.content()
                    // deletes registry entries when nodes are detached but
                    // leaves the data-idref attribute on the node. The next
                    // dom.data(node, '_class') then hits
                    //   this.registry[id][key]
                    // with registry[id] === undefined and throws
                    //   "Cannot read properties of undefined (reading '_class')".
                    // Seed a fresh empty slot so the getter returns undefined.
                    this.registry[id] = {};
                }
            }
            return _orig.apply(this, arguments);
        };
        dom._qaDataPatched = true;
        console.log('[qa-fix] dom.data patched (getter+setter, data-idref)');
    } catch(e) {
        console.warn('[qa-fix] failed to patch dom.data:', e);
    }
})();



function getCurrentLanIp() {
	var lanIpRaw = uci.get('network', 'lan', 'ipaddr');
	var lanIp = Array.isArray(lanIpRaw) ? (lanIpRaw[0] || '192.168.10.1') : (lanIpRaw || '192.168.10.1');
	return String(lanIp).split(' ')[0];
}

var GuestWifiViewClass = (function() {

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
	if (document.getElementById('guest-wifi-styles')) return;
	let style = document.createElement('style');
	style.id = 'guest-wifi-styles';
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

	// Layout fixups for the narrow iframe context. The outer page
	// reserves sidebar space, so the iframe viewport is smaller than
	// a full page; these rules keep modals and controls usable.
	if (!document.getElementById('guest-wifi-layout-styles')) {
		let ls = document.createElement('style');
		ls.id = 'guest-wifi-layout-styles';
		ls.type = 'text/css';
		ls.textContent = '\
			.modal.cbi-modal { width: min(95vw, 1200px) !important; max-width: 95vw !important; min-width: 0 !important; }\
			.modal.cbi-modal .cbi-value { display: flex !important; flex-wrap: nowrap !important; align-items: flex-start !important; }\
			.modal.cbi-modal .cbi-value-title { flex: 0 0 200px !important; }\
			.modal.cbi-modal .cbi-value-field { flex: 1 1 auto !important; min-width: 0 !important; }\
			.cbi-value-field { min-width: 0 !important; }\
			.cbi-value-field select,\
			.cbi-value-field input,\
			.cbi-value-field .cbi-dropdown { max-width: 100% !important; }\
			.btn.qr-code { display: inline-flex; align-items: center; gap: .5em; }\
			.btn.qr-code svg { display: block; height: 1.5em; width: auto; }\
			html, body { background-color: var(--background-color-default, #141414) !important; background-image: none !important; }\
			#view.spinning::before,\
			#view.spinning::after,\
			body > .spinning,\
			body > .loading-overlay,\
			body > .spinner { display: none !important; visibility: hidden !important; }\
			.cbi-input-password { padding-right: 34px !important; }\
		';
		document.head.appendChild(ls);
	}
}

// Un-cap .container inside the embed page. The embed view is a full
// LuCI page loaded at ?embed=guestwifi, so it has its own theme
// wrapper (.container) that caps width at ~940px. Un-cap here so the
// guest wifi form and its modals use the entire iframe viewport.
(function(){
	if (document.getElementById('qa-embed-fullwidth')) return;
	var s = document.createElement('style');
	s.id = 'qa-embed-fullwidth';
	s.type = 'text/css';
	s.textContent = '.container,.main,.main-right,.cbi-map,.fs-content,.fs-main{' +
		'max-width:none !important;width:100% !important;' +
		'padding-left:0 !important;padding-right:0 !important;' +
		'margin-left:0 !important;margin-right:0 !important;}' +
		'html,body{height:auto !important;min-height:0 !important;}' +
		'body>.container,body>#view,body>main{min-height:0 !important;}'
	document.head.appendChild(s);
})();

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
		// Persist enable explicitly — form.Flag.default is not written to
		// UCI on its own, so without this the toggle renders off even when
		// the app treats a missing enable key as enabled.
		uci.set('guestwifi', sid, 'enable', enabled ? '1' : '0');
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

		// Original 4IceG/luci-app-guest-wifi-js form — uci.add() unconditional
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

		uci.add('dhcp', 'dhcp', dhcpName);
		uci.set('dhcp', dhcpName, OWNER_TAG, sid);
		uci.set('dhcp', dhcpName, 'start', dhcpStart);
		uci.set('dhcp', dhcpName, 'limit', dhcpLimit);
		uci.set('dhcp', dhcpName, 'leasetime', dhcpLease);
		uci.set('dhcp', dhcpName, 'interface', networkName);
		uci.set('dhcp', dhcpName, 'dhcpv4', 'server');
		uci.set('dhcp', dhcpName, 'ignore', enabled ? '0' : '1');

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

		let dhcpRuleSid = uci.add('firewall', 'rule');
		uci.set('firewall', dhcpRuleSid, OWNER_TAG, sid);
		uci.set('firewall', dhcpRuleSid, 'src', networkName);
		uci.set('firewall', dhcpRuleSid, 'proto', 'udp');
		uci.set('firewall', dhcpRuleSid, 'src_port', fwDhcpPorts);
		uci.set('firewall', dhcpRuleSid, 'dest_port', fwDhcpPorts);
		uci.set('firewall', dhcpRuleSid, 'target', 'ACCEPT');
		uci.set('firewall', dhcpRuleSid, 'family', 'ipv4');

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
		// form.Map.save() can throw synchronously (from checkDepends ->
		// triggerValidation -> getUIElement) if a dependent option's DOM
		// node lost its data-idref registry slot. Wrap in a resolved
		// promise so the .catch() at the end of this chain actually fires.
		return Promise.resolve().then(function() {
			return m.save();
		}).then(function() {
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
			// Auto-apply removed: only Save & Apply triggers it.
		}).catch(function(err) {
			var msg = (err && err.message) ? err.message : String(err);
			if (/No data|code 5|Permission denied|code 6/i.test(msg)) {
				return;
			}
			ui.addNotification(null, E('p', {}, _('Error saving configuration:') + ' ' + msg), 'error');
			return Promise.reject(err);
		});
	},

	render: function() {
		let self = this;

		addGuestWifiStyles();

		// Modal sweep: LuCI pre-renders the modal once and toggles
		// its display. No DOM insertion event fires on open, so we
		// actively sweep for visible modals and force the width via
		// inline !important. Runs on click, on interval, and once now.
		if (!window._qaWidenModals) {
			window._qaWidenModals = function() {
				try {
					var mods = document.querySelectorAll('.modal, .cbi-modal');
					for (var i = 0; i < mods.length; i++) {
						var m = mods[i];
						var r = m.getBoundingClientRect();
						if (r.width < 100 || r.height < 50) continue;
						m.style.setProperty('width', 'min(95vw, 2200px)', 'important');
						m.style.setProperty('max-width', 'calc(100vw - 32px)', 'important');
						m.style.setProperty('min-width', '0', 'important');
					}
				} catch(e) {}
			};
			if (!window._qaModalSweepTimer) {
				window._qaModalSweepTimer = setInterval(window._qaWidenModals, 400);
			}
			document.addEventListener('click', function() {
				setTimeout(window._qaWidenModals, 30);
				setTimeout(window._qaWidenModals, 150);
				setTimeout(window._qaWidenModals, 400);
			}, true);
		}
		setTimeout(window._qaWidenModals, 100);

		let wifiDevices = uci.sections('wireless', 'wifi-device');
		let radios = wifiDevices.map(function(d) { return d['.name']; });
		if (!radios.length)
			radios = ['radio0', 'radio1', 'radio2'];

		let m = new form.Map('guestwifi', _('Guest Wi-Fi'),
			_('A user interface for easily creating and management isolated Wi-Fi networks for guests, each with its own access point, DHCP, and firewall rules.'));

		self.map = m;

		// The map's own page-actions (Save / Save & Apply buttons)
		// call map.handleSave / map.handleSaveApply — form.Map's
		// defaults — which only run form.Map.save(). They never reach
		// applyAll(), so the runtime network/wireless/dhcp/firewall
		// sections tagged with guest_owner were never created.
		// Route the map's handlers through applyAll() as well.
		m.handleSave = function(ev) {
			return self.applyAll(m);
		};
		m.handleSaveApply = function(ev, mode) {
			return self.applyAll(m);
		};

		let s = m.section(form.GridSection, 'guest', _('Guest networks'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.addbtntitle = _('Add new guest network...');

		let o = s.option(form.Flag, 'enable', _('Enabled'),
			_('Enable guest network.'));
		o.rmempty = false;
		o.default = '1';
		o.editable = true;
		// Read side: show ON for a fresh section, else UCI value.
		o.cfgvalue = function(section_id) {
			let v = uci.get('guestwifi', section_id, 'enable');
			return (v == null || v === '') ? '1' : v;
		};
		// Formvalue: read the checkbox from the DOM directly. LuCI's
		// base formvalue() returns null when getUIElement() can't find
		// the widget, and base save() then writes '0' (this.remove()).
		o.formvalue = function(section_id) {
			// The element at this.cbid() is often a wrapper div, not the
			// actual <input type=checkbox>. Dig one level.
			let cbid = this.cbid(section_id);
			let el = document.getElementById(cbid);
			let inp = el;
			if (inp && inp.tagName !== 'INPUT')
				inp = inp.querySelector('input[type="checkbox"]');
			if (inp && typeof inp.checked === 'boolean')
				return inp.checked ? '1' : '0';
			// Fallback: search the whole row for the checkbox
			if (el && el.closest) {
				let rowCb = el.closest('tr, .cbi-rowstyle-1, .cbi-rowstyle-2, .tr');
				if (rowCb) {
					let rInput = rowCb.querySelector('input[type="checkbox"]');
					if (rInput && typeof rInput.checked === 'boolean')
						return rInput.checked ? '1' : '0';
				}
			}
			let v = uci.get('guestwifi', section_id, 'enable');
			return (v == null || v === '') ? '1' : v;
		};
		// Write: bypass Flag.save()'s default-skip and uci.set direct.
		o.write = function(section_id, formvalue) {
			if (formvalue == null || formvalue === '')
				formvalue = '1';
			let on = (formvalue === '1' || formvalue === true ||
			          formvalue === 1 || formvalue === 'on');
			uci.set('guestwifi', section_id, 'enable', on ? '1' : '0');
		};

		o = s.option(form.Value, 'ssid', _('Network name (SSID)'));
		o.rmempty = false;
		o.default = DEFAULTS.ssid;
		o.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default;
			return ssidBadge(section_id, val);
		};

		o = s.option(form.ListValue, 'radio', _('Radio'),
			_('The radio on which the guest network will work.'));
		radios.forEach(function(r) { o.value(r, radioLabel(r, wifiDevices)); });
		o.default = DEFAULTS.radio;
		o.rmempty = false;
		o.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default;
			return radioBadge(section_id, val, wifiDevices);
		};

		o = s.option(form.ListValue, 'encryption', _('Encryption'),
			_('WPA2-PSK is recommended for most devices. WPA3-SAE offers the strongest security but requires WPA3-capable clients.'));
		ENCRYPTION_MODES.forEach(function(m) { o.value(m[0], m[1]); });
		o.default = DEFAULTS.encryption;
		o.rmempty = false;
		o.textvalue = function(section_id) {
			let val = this.cfgvalue(section_id) || this.default;
			return encryptionLabel(val);
		};

		o = s.option(form.Value, 'password', _('Password'), ' ');
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

		o = s.option(form.Value, 'password_length', _('Password length'),
			_('Minimum length is 8 characters, 13 characters recommended.'));
		o.datatype = 'range(8,63)';
		o.default = '13';
		o.rmempty = true;
		o.modalonly = true;
		passwordDependsOn(o);

		o = s.option(cbiPasswordComponentsValue, 'password_components', _('Password composition'),
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

		o = s.option(form.Button, '_password_generate', _('Generate password'));
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

		o = s.option(form.DummyValue, '_qrops', _('QR Code'),
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

		o = s.option(form.Value, 'interface_ip', _('Interface IP address'));
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

		o = s.option(form.Value, 'netmask', _('Netmask'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.default = DEFAULTS.netmask;
		o.modalonly = true;

		o = s.option(form.Value, 'dhcp_start', _('DHCP range start'),
			_('Lowest leased address, as offset from the network address.'));
		o.datatype = 'uinteger';
		o.rmempty = false;
		o.default = DEFAULTS.dhcpStart;
		o.modalonly = true;

		o = s.option(form.Value, 'dhcp_limit', _('DHCP client limit'),
			_('Maximum number of leased addresses.'));
		o.datatype = 'uinteger';
		o.rmempty = false;
		o.default = DEFAULTS.dhcpLimit;
		o.modalonly = true;

		o = s.option(form.Value, 'dhcp_lease', _('DHCP lease time'),
			_('E.g. "1h", "30m", "12h". Minimum is "2m".'));
		o.rmempty = false;
		o.default = DEFAULTS.dhcpLease;

		o = s.option(form.ListValue, 'isolate', _('Client isolation'),
			_('Blocks communication between clients on this guest network.'));
		o.value('1', _('Yes'));
		o.value('0', _('No'));
		o.default = DEFAULTS.isolate;
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'macaddr', _('MAC address'),
			_('Override default MAC address - the range of usable addresses might be limited by the driver'));
		o.value('', _('driver default'));
		o.value('random', _('randomly generated'));
		o.datatype = "or('random',macaddr)";
		o.default = DEFAULTS.macaddr;
		o.rmempty = true;
		o.modalonly = true;

		o = s.option(widgets.ZoneSelect, 'fw_forward_dest', _('Forwarding destination zone'),
			_('Firewall zone guest traffic is forwarded to (usually "wan"). Pick an existing zone from the list or fill out the <em>-- custom --</em> field to enter one manually.'));
		o.rmempty = false;
		o.default = DEFAULTS.fwForwardDest;
		o.modalonly = true;

		o = s.option(form.ListValue, 'fw_input', _('Input'),
			_('Traffic from guests to the router itself (e.g. LuCI, SSH).'));
		o.value('REJECT', _('reject')); o.value('ACCEPT', _('accept')); o.value('DROP', _('drop'));
		o.default = DEFAULTS.fwInput;
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.ListValue, 'fw_output', _('Output'),
			_('Traffic from the router itself to guests. ACCEPT is recommended so router services (DHCP, DNS) keep working.'));
		o.value('REJECT', _('reject')); o.value('ACCEPT', _('accept')); o.value('DROP', _('drop'));
		o.default = DEFAULTS.fwOutput;
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.ListValue, 'fw_forward', _('Forward'),
			_('Traffic passing between guests and other networks/zones (e.g. LAN). Keep this REJECT or DROP to isolate guests from your LAN. ACCEPT would allow guests to reach other networks.'));
		o.value('REJECT', _('reject')); o.value('ACCEPT', _('accept')); o.value('DROP', _('drop'));
		o.default = DEFAULTS.fwForward;
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'fw_dhcp_ports', _('DHCP rule ports'),
			_('UDP port range for DHCP traffic, e.g. "67-68".'));
		o.rmempty = false;
		o.default = DEFAULTS.fwDhcpPorts;
		o.modalonly = true;

		o = s.option(form.Value, 'fw_dns_port', _('DNS rule port'));
		o.datatype = 'port';
		o.rmempty = false;
		o.default = DEFAULTS.fwDnsPort;
		o.modalonly = true;

		return m.render().then(function(node) {
			// LuCI theme often wins specificity over our injected <style>.
			// Set inline style with !important on every modal that opens.
			if (!window._qaModalObserver) {
				try {
					window._qaModalObserver = new MutationObserver(function(muts) {
						for (let i = 0; i < muts.length; i++) {
							let added = muts[i].addedNodes;
							for (let j = 0; j < added.length; j++) {
								let n = added[j];
								if (!n || n.nodeType !== 1) continue;
								let targets = [];
								if (n.classList && n.classList.contains('modal')) targets.push(n);
								if (n.querySelectorAll) {
									let inner = n.querySelectorAll('.modal, .cbi-modal');
									for (let k = 0; k < inner.length; k++) targets.push(inner[k]);
								}
								for (let t = 0; t < targets.length; t++) {
									targets[t].style.setProperty('width', 'min(95vw, 1200px)', 'important');
									targets[t].style.setProperty('max-width', 'calc(100vw - 32px)', 'important');
								}
							}
						}
					});
					window._qaModalObserver.observe(document.body, { childList: true, subtree: true });
				} catch(e) {}
			}
			return node;
		});
	},

	handleSave: function(ev) {
		return this.applyAll(this.map);
	},
	handleSaveApply: null,
	handleReset: null
});

})();

return view.extend({
    pollInterval: 5,
    designStyle: '3d',
    timerId: null,
    customMappings: {},
    installedThemes: [],
    callInitStatus: null,
    callSystemCommand: null,
    activeTab: 'dashboard',

    load: function() {
        var self = this;
        this.callInitStatus = rpc.declare({ object: 'luci', method: 'getInitList', expect: { '': {} } });
        this.callSystemCommand = rpc.declare({ object: 'file', method: 'exec', params: [ 'command', 'params' ], expect: { '': {} } });
        return Promise.all([
            uci.load('quickactions').catch(function(){}),
            uci.load('system').catch(function(){}),
            uci.load('wireless').catch(function(){}),
            uci.load('network').catch(function(){}),
            uci.load('guestwifi').catch(function(){})
        ]).then(function() {
            var interval = uci.get('quickactions', 'global', 'poll_interval');
            self.pollInterval = parseInt(interval, 10) || 5;
            self.designStyle = uci.get('quickactions', 'global', 'design_style') || '3d';
            var maps = uci.sections('quickactions', 'mapping') || [];
            self.customMappings = {};
            maps.forEach(function(sec) {
                if (sec.keyword) {
                    self.customMappings[sec.keyword.toLowerCase().trim()] = {
                        service: sec.service ? sec.service.trim() : null,
                        dangerous: sec.dangerous === '1',
                        icon: sec.icon ? sec.icon.trim() : ''
                    };
                }
            });
            return self.fetchThemeList().then(function(themes) {
                self.installedThemes = themes || [];
                return self.fetchLanguageList().then(function(langs) {
                    self.installedLanguages = langs || [];
                    return Promise.all([
                        uci.load('luci').then(function() { return uci.sections('luci', 'command'); }).catch(function(){ return []; }),
                        self.callInitStatus().catch(function(){ return {}; })
                    ]);
                });
            });
        });
    },

    refreshPendingCount: function() {
        var self = this;
        return Promise.resolve(uci.changes()).then(function(changes) {
            var n = 0;
            for (var k in changes) { n += Object.keys(changes[k]).length; }
            var bar = document.getElementById('qa-pending-bar');
            var cnt = document.getElementById('qa-pending-count');
            if (!bar) return;
            if (n === 0) {
                bar.style.display = 'none';
            } else {
                bar.style.display = 'flex';
                if (cnt) cnt.textContent = n + ' pending change' + (n === 1 ? '' : 's') + ' in memory (not committed)';
            }
        }).catch(function() {});
    },

    pendingApply: function() {
        var self = this;
        return Promise.resolve(uci.changes()).then(function(changes) {
            var lines = [];
            for (var conf in changes) {
                for (var sid in changes[conf]) {
                    for (var opt in changes[conf][sid]) {
                        var v = changes[conf][sid][opt];
                        if (Array.isArray(v)) v = v.join(', ');
                        lines.push(conf + '.' + sid + '.' + opt + ' = ' + v);
                    }
                }
            }
            if (lines.length === 0) {
                ui.addNotification('Nothing to apply', 'No pending changes.', 'info');
                return;
            }
            var preview = lines.slice(0, 20).join('\n') + (lines.length > 20 ? '\n... and ' + (lines.length - 20) + ' more' : '');
            if (!confirm('Apply ALL pending changes system-wide?\n\n' + preview + '\n\nThis commits and applies everything, not just this page.')) return;

            ui.addNotification('Applying', 'Committing ' + lines.length + ' change(s)...', 'info');
            return uci.apply(10).then(function() {
                ui.addNotification('Applied', 'All changes committed and applied.', 'info');
                self.refreshPendingCount();
            }).catch(function(err) {
                ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
            });
        });
    },

    fetchThemeList: function() {
        var self = this;
        // Multi-source theme detection (four independent methods)
        var sh = 'ls -1 /www/luci-static/ 2>/dev/null; ' +
                 'echo "---"; ' +
                 'ls -1 /usr/lib/opkg/info/ 2>/dev/null | grep "^luci-theme-"; ' +
                 'echo "---"; ' +
                 'opkg list-installed 2>/dev/null | awk "/^luci-theme-/ {print \$1}"; ' +
                 'apk list -I 2>/dev/null | grep -o "^luci-theme-[^ ]*"';

        return this.callSystemCommand('/bin/sh', ['-c', sh]).then(function(r) {
            var seen = {}, themes = [];
            (r.stdout || '').split('\n').forEach(function(line) {
                line = line.trim();
                if (!line || line === '---') return;
                var name = line
                    .replace(/^luci-theme-/, '')
                    .replace(/\.(list|control)$/, '')
                    .trim();
                if (['resources', 'fonts', 'index.css', 'index.css.gz', 'menu', 'loading.svg'].indexOf(name) !== -1) return;
                if (/^[a-zA-Z0-9_\-]+$/.test(name) === false) return;
                if (name.length < 2 || name.length > 32) return;
                if (seen[name]) return;
                seen[name] = 1;
                themes.push(name);
            });
            return themes;
        }).catch(function() { return []; });
    },

    fetchLanguageList: function() {
        var sh = "ls -1 /usr/lib/lua/luci/i18n/ 2>/dev/null | grep -E '^base\..*\.lmo$' | sed 's/^base\.//; s/\.lmo$//' | sort -u";
        return this.callSystemCommand('/bin/sh', ['-c', sh]).then(function(r) {
            var list = [];
            (r.stdout || '').split('\n').forEach(function(line) {
                line = line.trim();
                if (line && /^[a-zA-Z_]+$/.test(line)) list.push(line);
            });
            return list;
        }).catch(function() { return []; });
    },

    handleThemeSwitch: function(themeKey) {
        uci.load('luci').then(function() {
            var cur = uci.get('luci', 'main', 'mediaurlbase');
            var nb = '/luci-static/' + themeKey;
            if (cur === nb) { ui.addNotification('Theme', 'Already using "' + themeKey + '".', 'info'); return; }
            ui.addNotification('Theme', 'Applying "' + themeKey + '"...', 'info');
            uci.set('luci', 'main', 'mediaurlbase', nb);
            uci.save().then(function() { return ui.changes.apply(false); }).then(function() { setTimeout(function() { window.location.reload(); }, 500); })
              .catch(function(err) { ui.addNotification('Theme Error', (err && err.message) ? err.message : String(err), 'danger'); });
        }).catch(function(err) { ui.addNotification('Theme Error', (err && err.message) ? err.message : String(err), 'danger'); });
    },

    handleLanguageSwitch: function(langCode) {
        uci.load('luci').then(function() {
            var cur = uci.get('luci', 'main', 'lang') || 'en';
            if (cur === langCode) { ui.addNotification('Language', 'Already set.', 'info'); return; }
            ui.addNotification('Language', 'Switching to ' + langCode + '...', 'info');
            uci.set('luci', 'main', 'lang', langCode);
            uci.save().then(function() { return ui.changes.apply(false); }).then(function() { setTimeout(function() { window.location.reload(); }, 500); })
              .catch(function(err) { ui.addNotification('Language Error', (err && err.message) ? err.message : String(err), 'danger'); });
        }).catch(function(err) { ui.addNotification('Language Error', (err && err.message) ? err.message : String(err), 'danger'); });
    },

    moveItem: function(section, name, direction) {
        var self = this;
        var secs = (uci.sections('quickactions', section) || []).slice();
        if (secs.length < 2) return;
        secs.sort(function(a, b) { return (parseInt(a.order, 10) || 999) - (parseInt(b.order, 10) || 999); });
        var idx = -1;
        for (var i = 0; i < secs.length; i++) { if (secs[i]['.name'] === name) { idx = i; break; } }
        if (idx < 0) return;
        var target = direction === 'up' ? idx - 1 : idx + 1;
        if (target < 0 || target >= secs.length) return;
        secs.forEach(function(s, i) { uci.set('quickactions', s['.name'], 'order', String((i + 1) * 10)); });
        var aOrder = (idx + 1) * 10;
        var bOrder = (target + 1) * 10;
        uci.set('quickactions', secs[idx]['.name'], 'order', String(bOrder));
        uci.set('quickactions', secs[target]['.name'], 'order', String(aOrder));
        return uci.save().then(function() { ui.addNotification('Reordered', name + ' moved ' + direction, 'info'); });
    },

    getServiceInfo: function(buttonName) {
        var name = buttonName.toLowerCase();
        for (var kw in this.customMappings) { if (name.includes(kw)) return this.customMappings[kw]; }
        return null;
    },

    getServiceStatus: function(buttonName, initList) {
        if (!buttonName || !initList) return null;
        var name = buttonName.toLowerCase();
        var info = this.getServiceInfo(buttonName);
        if (info && info.service && initList[info.service]) return initList[info.service].enabled && initList[info.service].running;
        var fb = { 'dns':'dnsmasq','dhcp':'dnsmasq','firewall':'firewall','vpn':'openvpn','wireguard':'network' };
        for (var k in fb) { if (name.includes(k) && initList[fb[k]]) return initList[fb[k]].enabled && initList[fb[k]].running; }
        return null;
    },

    executeValidatedCommand: function(commandStr, buttonName, btnElement) {
        var self = this;

        // LuCI pseudo-command: @download:<url> means "open this URL in a new
        // browser tab" (typically the cgi-backup endpoint). It cannot be run
        // through /bin/sh; handle it here.
        if (/^@download:/.test(commandStr)) {
            var url = commandStr.substring(10);
            btnElement.setAttribute('data-executing', 'true');
            btnElement.style.opacity = '0.5';
            try {
                var link = document.createElement('a');
                link.href = url;
                link.target = '_blank';
                link.rel = 'noopener';
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
                ui.addNotification(null,
                    E('p', {}, _('Downloading: ') + url), 'info');
            } catch (e) {
                ui.addNotification(null,
                    E('p', {}, _('Download failed: ') + (e.message || e)), 'danger');
            }
            setTimeout(function() {
                btnElement.setAttribute('data-executing', 'false');
                btnElement.style.opacity = '1';
            }, 800);
            return;
        }

        btnElement.setAttribute('data-executing', 'true');
        btnElement.style.opacity = '0.5';
        if (typeof ui.addTimeLimitedNotification === 'function') {
            ui.addTimeLimitedNotification('Executing', buttonName + ' is running...', 8000, 'info');
        } else {
            ui.addNotification('Executing', buttonName + ' is running...', 'info');
        }
        this.callSystemCommand('/bin/sh', [ '-c', commandStr ]).then(function(result) {
            btnElement.setAttribute('data-executing', 'false');
            btnElement.style.opacity = '1';
            var output = result.stdout || '';
            if (result.stderr) output += '\n[stderr]\n' + result.stderr;
            var __failed = (result.code != null && result.code !== 0);
            if (!output.trim()) output = __failed ? '(no output)' : 'Done.';
            if (__failed) output = '[exit code ' + result.code + ']\n' + output;
            var uid = 'qa-out-' + Date.now();
            var pre = document.createElement('pre');
            pre.id = uid;
            pre.style.cssText = 'text-align:left;white-space:pre-wrap;max-height:70vh;overflow-y:auto;background:#1e1e1e;color:#00ff00;padding:15px;border-radius:8px;font-family:monospace;font-size:0.9em;width:100%;box-sizing:border-box;margin:0;';
            pre.textContent = output;
            ui.addNotification(
                __failed ? (buttonName + ' \u2014 exit ' + result.code) : (buttonName + ' Done'),
                pre,
                __failed ? 'warning' : 'info');
            var el = document.getElementById(uid);
            if (el && el.closest) { var c = el.closest('.alert'); if (c) { c.style.maxWidth = '95%'; c.style.width = 'auto'; } }
            self.updateAllButtonsRealtime();
        }).catch(function(err) {
            btnElement.setAttribute('data-executing', 'false');
            btnElement.style.opacity = '1';
            ui.addNotification('Failed', (err && err.message) ? err.message : String(err), 'danger');
        });
    },

    handleButtonClick: function(commandStr, buttonName, btnElement) {
        if (btnElement.getAttribute('data-executing') === 'true') return;
        var info = this.getServiceInfo(buttonName);
        if (info && info.dangerous) {
            if (confirm('Warning: high-risk operation (' + buttonName + ').\nProceed?')) this.executeValidatedCommand(commandStr, buttonName, btnElement);
        } else this.executeValidatedCommand(commandStr, buttonName, btnElement);
    },

    applyLiveColor: function(element, isRunning) {
        if (isRunning) { element.style.backgroundColor = '#2ed573'; if (this.designStyle === '3d') element.style.borderBottom = '5px solid #26b360'; }
        else { element.style.backgroundColor = '#ff4757'; if (this.designStyle === '3d') element.style.borderBottom = '5px solid #d93d4b'; }
    },

    updateAllButtonsRealtime: function() {
        var self = this;
        var gridNode = document.getElementById('quickactions-grid-container');
        if (!gridNode) return;  // tab is not Dashboard - skip, keep interval alive
        this.callInitStatus().then(function(initList) {
            var buttons = gridNode.getElementsByClassName('custom-action-btn');
            for (var i = 0; i < buttons.length; i++) {
                var btn = buttons[i];
                if (btn.getAttribute('data-executing') === 'true') continue;
                var bName = btn.getAttribute('data-name');
                var isRunning = self.getServiceStatus(bName, initList);
                if (isRunning !== null) self.applyLiveColor(btn, isRunning);
            }
        }).catch(function(){});
    },

    runCommand: function(cmd, label) {
        // Legacy LuCI pseudo-command. The old /cgi-bin/cgi-backup endpoint
        // requires a POST with a CSRF token; opening it as a GET returns
        // "Invalid form data". Guide the user to LuCI's working backup page.
        if (/^@download:/.test(cmd)) {
            var url = cmd.substring(10);
            ui.addNotification(null, E('div', {},
                E('p', {}, _('The legacy download endpoint no longer works directly.')),
                E('p', {}, _('Please use System → Backup / Flash Firmware to download a config backup.')),
                E('p', { 'style': 'margin-top:6px;' },
                    E('a', { 'href': '/cgi-bin/luci/admin/system/flash', 'target': '_blank' },
                        _('Open backup page →')))
            ), 'info');
            return Promise.resolve({ code: 0, stdout: '', stderr: '' });
        }
        return this.callSystemCommand('/bin/sh', [ '-c', cmd ]).then(function(r) {
            var out = r.stdout || '';
            if (r.stderr) out += '\n[stderr]\n' + r.stderr;
            var __failed = (r.code != null && r.code !== 0);
            if (!out.trim()) out = __failed ? '(no output)' : 'Done.';
            if (__failed) out = '[exit code ' + r.code + ']\n' + out;
            var uid = 'qa-tool-out-' + Date.now();
            var pre = document.createElement('pre');
            pre.id = uid;
            pre.style.cssText = 'text-align:left;white-space:pre-wrap;max-height:70vh;overflow-y:auto;background:#1e1e1e;color:#00ff00;padding:12px;border-radius:6px;font-family:monospace;font-size:0.9em;width:100%;box-sizing:border-box;margin:0;';
            pre.textContent = out;
            ui.addNotification(
                __failed ? (label + ' \u2014 exit ' + r.code) : (label + ' Done'),
                pre,
                __failed ? 'warning' : 'info');
            var el = document.getElementById(uid);
            if (el && el.closest) { var c = el.closest('.alert'); if (c) { c.style.maxWidth = '95%'; c.style.width = 'auto'; } }
            return r;
        });
    },

    renderDashboard: function(cmds, initList) {
        var self = this;
        var currentLang = (uci.get('luci', 'main', 'lang') || 'en');
        var themeBar = E('div', { 'style': 'background:rgba(0,0,0,0.04);padding:12px 14px;border-radius:8px;margin-bottom:12px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;' }, [E('strong', { 'style': 'min-width:130px;' }, 'Theme Switcher: ')]);
        if (this.installedThemes.length === 0) {
            themeBar.appendChild(E('span', { 'style': 'color:#777;font-style:italic;' }, 'No themes detected'));
            themeBar.appendChild(E('button', { 'class': 'btn cbi-button', 'style': 'padding:2px 10px;font-size:0.8em;margin-left:6px;', 'click': function() {
                var cmd = [
                    'echo "=== /www/luci-static/ ==="',
                    'ls -1 /www/luci-static/ 2>/dev/null',
                    'echo ""',
                    'echo "=== /usr/lib/opkg/info (luci-theme) ==="',
                    'ls -1 /usr/lib/opkg/info/ 2>/dev/null | grep "^luci-theme-"',
                    'echo ""',
                    'echo "=== opkg list-installed (luci-theme) ==="',
                    'opkg list-installed 2>/dev/null | grep "^luci-theme-"',
                    'echo ""',
                    'echo "=== apk list -I (luci-theme) ==="',
                    'apk list -I 2>/dev/null | grep -o "^luci-theme-[^ ]*"'
                ].join('\n');
                self.callSystemCommand('/bin/sh', ['-c', cmd]).then(function(r) {
                    var out = (r.stdout || '') + (r.stderr ? '\n[stderr]\n' + r.stderr : '');
                    ui.addNotification('Theme Diagnostic',
                        E('pre', { 'style': 'text-align:left;white-space:pre-wrap;background:#1e1e1e;color:#0f0;padding:12px;border-radius:4px;font-family:monospace;font-size:0.85em;max-height:400px;overflow:auto;' }, out),
                        'info');
                });
            } }, 'Diagnose'));
        }
        else this.installedThemes.forEach(function(t) {
            themeBar.appendChild(E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'style': 'padding:4px 12px;text-transform:capitalize;font-weight:bold;', 'click': function() { self.handleThemeSwitch(t); } }, t));
        });
        var langBar = E('div', { 'style': 'background:rgba(0,0,0,0.04);padding:12px 14px;border-radius:8px;margin-bottom:20px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;' }, [E('strong', { 'style': 'min-width:130px;' }, 'Language Switcher: ')]);
        var LANG_NAMES = {
            'en': 'English', 'bn': '\u09ac\u09be\u0982\u09b2\u09be', 'bn_BD': '\u09ac\u09be\u0982\u09b2\u09be',
            'zh_Hans': '\u7b80\u4f53\u4e2d\u6587', 'zh_Hant': '\u7e41\u9ad4\u4e2d\u6587',
            'ar': '\u0627\u0644\u0639\u0631\u0628\u064a\u0629', 'cs': '\u010ce\u0161tina', 'da': 'Dansk',
            'de': 'Deutsch', 'el': '\u0395\u03bb\u03bb\u03b7\u03bd\u03b9\u03ba\u03ac', 'es': 'Espa\u00f1ol',
            'fa': '\u0641\u0627\u0631\u0633\u06cc', 'fi': 'Suomi', 'fil': 'Filipino',
            'fr': 'Fran\u00e7ais', 'he': '\u05e2\u05d1\u05e8\u05d9\u05ea', 'hi': '\u0939\u093f\u0928\u094d\u0926\u0940',
            'hu': 'Magyar', 'it': 'Italiano', 'ja': '\u65e5\u672c\u8a9e',
            'ko': '\ud55c\uad6d\uc5b4', 'ms': 'Bahasa Melayu', 'nb_NO': 'Norsk Bokm\u00e5l',
            'nl': 'Nederlands', 'pl': 'Polski', 'pt': 'Portugu\u00eas',
            'pt_BR': 'Portugu\u00eas (BR)', 'ro': 'Rom\u00e2n\u0103', 'ru': '\u0420\u0443\u0441\u0441\u043a\u0438\u0439',
            'sk': 'Sloven\u010dina', 'sv': 'Svenska', 'tr': 'T\u00fcrk\u00e7e',
            'uk': '\u0423\u043a\u0440\u0430\u0457\u043d\u0441\u044c\u043a\u0430', 'vi': 'Ti\u1ebfng Vi\u1ec7t'
        };
        var langs = (self.installedLanguages && self.installedLanguages.length)
            ? self.installedLanguages.slice()
            : ['en', 'bn_BD'];
        if (langs.indexOf('en') === -1) langs.unshift('en');
        langs.forEach(function(code) {
            var label = LANG_NAMES[code] || code;
            var active = (currentLang === code);
            var btn = E('button', { 'class': 'btn cbi-button ' + (active ? 'cbi-button-action important' : 'cbi-button-neutral'), 'style': 'padding:4px 14px;font-weight:bold;', 'click': function() { self.handleLanguageSwitch(code); } }, label);
            langBar.appendChild(btn);
        });
        var grid = E('div', { 'id': 'quickactions-grid-container', 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;' });
        if (cmds.length === 0) grid.appendChild(E('p', { 'style': 'grid-column:1/-1;color:#888;' }, 'No custom commands. Add them in System > Custom Commands first.'));
        else {
            var is3d = this.designStyle === '3d';
            cmds.forEach(function(c) {
                var name = c.name || c.command;
                var style = 'padding:14px 12px;font-size:0.9em;font-weight:bold;cursor:pointer;text-align:center;' +
                            'color:#ffffff !important;' +
                            'background:#747d8c !important;' +
                            'background-color:#747d8c !important;' +
                            'box-shadow:0 4px 6px rgba(0,0,0,0.1);' +
                            'word-wrap:break-word;white-space:normal;line-height:1.3;' +
                            'text-shadow:0 1px 1px rgba(0,0,0,0.25);';
                style += is3d ? 'border-radius:8px;border:none;' : 'border-radius:4px;border:1px solid rgba(0,0,0,0.1);';
                var info = self.getServiceInfo(name);
                var label = (info && info.icon) ? info.icon + ' ' + name : name;
                var btn = E('button', { 'class': 'btn cbi-button custom-action-btn', 'style': style + (is3d ? 'border-bottom:5px solid #57606f !important;' : ''), 'data-name': name, 'data-executing': 'false' }, label);
                var r = self.getServiceStatus(name, initList);
                if (r !== null) self.applyLiveColor(btn, r);
                btn.addEventListener('click', function() { self.handleButtonClick(c.command, name, btn); });
                grid.appendChild(btn);
            });
        }
        return E('div', {}, [themeBar, langBar, grid]);
    },

    renderEssential: function() {
        var self = this;
        var secs = (uci.sections('quickactions', 'essential') || []).slice();
        secs.sort(function(a, b) { return (parseInt(a.order, 10) || 999) - (parseInt(b.order, 10) || 999); });
        var is3d = this.designStyle === '3d';
        var grid = E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px;' });
        if (secs.length === 0) grid.appendChild(E('p', { 'style': 'grid-column:1/-1;color:#888;' }, 'No essential buttons. Add them in the Configuration tab.'));
        else secs.forEach(function(s, idx) {
            var cmd = s.command || '';
            var label = s.label || s['.name'];
            var icon = s.icon || '';
            var needsConfirm = s.confirm === '1';
            var isFirst = idx === 0;
            var isLast = idx === secs.length - 1;
            var style = 'padding:14px 12px;font-size:0.92em;font-weight:bold;cursor:pointer;text-align:center;' +
                        'color:#ffffff !important;' +
                        'background:#1e90ff !important;' +
                        'background-color:#1e90ff !important;' +
                        'box-shadow:0 4px 6px rgba(0,0,0,0.1);' +
                        'word-wrap:break-word;white-space:normal;line-height:1.35;flex:1;';
            style += is3d ? 'border-radius:8px;border:none;border-bottom:5px solid #197ad9 !important;' : 'border-radius:4px;border:1px solid rgba(0,0,0,0.1);';
            var btn = E('button', { 'class': 'btn cbi-button', 'style': style, 'data-executing': 'false' }, (icon ? icon + '  ' : '') + label);
            btn.addEventListener('click', function() {
                if (btn.getAttribute('data-executing') === 'true') return;
                if (!cmd) { ui.addNotification('Error', 'No command', 'danger'); return; }
                if (needsConfirm && !confirm('Confirm: ' + label + '\n\nCommand:\n' + cmd + '\n\nProceed?')) return;
                btn.setAttribute('data-executing', 'true'); btn.style.opacity = '0.5';
                if (typeof ui.addTimeLimitedNotification === 'function') {
                    ui.addTimeLimitedNotification('Running', label + '...', 8000, 'info');
                } else {
                    ui.addNotification('Running', label + '...', 'info');
                }
                self.runCommand(cmd, label).then(function() { btn.setAttribute('data-executing', 'false'); btn.style.opacity = '1'; })
                    .catch(function(err) { btn.setAttribute('data-executing', 'false'); btn.style.opacity = '1'; ui.addNotification('Failed', (err && err.message) ? err.message : String(err), 'danger'); });
            });
            var upBtn = E('button', { 'class': 'btn cbi-button', 'style': 'padding:2px 6px;font-size:0.7em;line-height:1;', 'title': 'Move up', 'click': function() { if (isFirst) return; self.moveItem('essential', s['.name'], 'up').then(function() { self.switchTab('essential'); }); } }, '▲');
            var downBtn = E('button', { 'class': 'btn cbi-button', 'style': 'padding:2px 6px;font-size:0.7em;line-height:1;', 'title': 'Move down', 'click': function() { if (isLast) return; self.moveItem('essential', s['.name'], 'down').then(function() { self.switchTab('essential'); }); } }, '▼');
            var arrows = E('div', { 'style': 'display:flex;flex-direction:column;gap:2px;' }, [upBtn, downBtn]);
            var row = E('div', { 'style': 'display:flex;gap:6px;align-items:stretch;' }, [btn, arrows]);
            grid.appendChild(row);
        });
        return E('div', {}, [
            E('p', { 'style': 'color:#777;font-size:0.9em;margin-bottom:14px;' }, 'Essential operations. Use ▲▼ arrows to reorder. Edit in Configuration tab.'),
            grid
        ]);
    },

    renderTools: function() {
        var self = this;
        function section(title, body) {
            return E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;margin-bottom:18px;' }, [E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, title), body]);
        }
        function inputRow(label, id, type) {
            return E('div', { 'style': 'margin-bottom:10px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, label),
                E('input', { 'id': id, 'type': type || 'text', 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;box-sizing:border-box;' })
            ]);
        }
        var pppoeSection = section('PPPoE Internet Setup', E('div', {}, [
            E('p', { 'style': 'color:#666;font-size:0.9em;margin:0 0 12px 0;' }, 'Configure WAN as PPPoE. Backs up /etc/config/network first.'),
            inputRow('PPPoE Username', 'qa-pppoe-user'),
            inputRow('PPPoE Password', 'qa-pppoe-pass', 'password'),
            E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:8px;', 'click': function() {
                var u = document.getElementById('qa-pppoe-user').value;
                var p = document.getElementById('qa-pppoe-pass').value;
                if (!u || !p) { ui.addNotification('Error', 'Username and password required.', 'danger'); return; }
                if (!confirm('Reconfigure WAN as PPPoE with user "' + u + '"? Internet may drop briefly.')) return;
                var cmd = 'cp /etc/config/network /etc/config/network.bak.$(date +%s) 2>/dev/null; uci -q delete network.wan 2>/dev/null; uci set network.wan=interface; uci set network.wan.proto=pppoe; uci set network.wan.username="' + u + '"; uci set network.wan.password="' + p + '"; uci commit network; /etc/init.d/network restart';
                if (typeof ui.addTimeLimitedNotification === 'function') {
                    ui.addTimeLimitedNotification('Running', 'Configuring PPPoE...', 8000, 'info');
                } else {
                    ui.addNotification('Running', 'Configuring PPPoE...', 'info');
                }
                self.runCommand(cmd, 'PPPoE Setup');
            } }, 'Apply PPPoE')
        ]));
        var pwSection = section('Change Root Password', E('div', {}, [
            inputRow('New Password', 'qa-pw', 'password'),
            inputRow('Confirm Password', 'qa-pw2', 'password'),
            E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:8px;', 'click': function() {
                var p1 = document.getElementById('qa-pw').value;
                var p2 = document.getElementById('qa-pw2').value;
                if (!p1 || p1.length < 4) { ui.addNotification('Error', 'Password too short.', 'danger'); return; }
                if (p1 !== p2) { ui.addNotification('Error', 'Passwords do not match.', 'danger'); return; }
                if (!confirm('Change root password? You will be logged out.')) return;
                var rpcSetPw = rpc.declare({ object: 'luci', method: 'setPassword', params: [ 'username', 'password' ], expect: { '': {} } });
                rpcSetPw('root', p1).then(function() { ui.addNotification('Success', 'Password changed. Log in again.', 'info'); document.getElementById('qa-pw').value = ''; document.getElementById('qa-pw2').value = ''; })
                    .catch(function(err) { ui.addNotification('Failed', (err && err.message) ? err.message : String(err), 'danger'); });
            } }, 'Change Password')
        ]));
        var shortcutSecs = (uci.sections('quickactions', 'shortcut') || []).slice();
        shortcutSecs.sort(function(a, b) { return (parseInt(a.order, 10) || 999) - (parseInt(b.order, 10) || 999); });
        var shortcutBody;
        if (shortcutSecs.length === 0) shortcutBody = E('p', { 'style': 'color:#888;' }, 'No shortcuts.');
        else {
            shortcutBody = E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:10px;' });
            shortcutSecs.forEach(function(s, idx) {
                var path = s.path || '', label = s.label || s['.name'], icon = s.icon || '';
                var isFirst = idx === 0, isLast = idx === shortcutSecs.length - 1;
                var navBtn = E('button', { 'class': 'btn cbi-button', 'style': 'padding:12px 10px;font-weight:bold;flex:1;background:rgba(128,128,128,0.15) !important;background-color:rgba(128,128,128,0.15) !important;color:inherit !important;border:1px solid rgba(0,0,0,0.15) !important;', 'click': function() { if (path) window.location.href = '/cgi-bin/luci/' + path; } }, (icon ? icon + '  ' : '') + label);
                var upBtn = E('button', { 'class': 'btn cbi-button', 'style': 'padding:2px 6px;font-size:0.7em;line-height:1;', 'click': function() { if (isFirst) return; self.moveItem('shortcut', s['.name'], 'up').then(function() { self.switchTab('tools'); }); } }, '▲');
                var downBtn = E('button', { 'class': 'btn cbi-button', 'style': 'padding:2px 6px;font-size:0.7em;line-height:1;', 'click': function() { if (isLast) return; self.moveItem('shortcut', s['.name'], 'down').then(function() { self.switchTab('tools'); }); } }, '▼');
                var arrows = E('div', { 'style': 'display:flex;flex-direction:column;gap:2px;' }, [upBtn, downBtn]);
                shortcutBody.appendChild(E('div', { 'style': 'display:flex;gap:6px;align-items:stretch;' }, [navBtn, arrows]));
            });
        }
        var shortcutSection = section('Quick Navigation Shortcuts', shortcutBody);
        // ---- Wireless Quick Edit ----
        var wifiBody = (function() {
            var ifaces = uci.sections('wireless', 'wifi-iface') || [];
            if (!ifaces.length)
                return E('p', { 'style': 'color:#888;' }, _('No wireless interfaces found.'));

            var table = E('table', { 'style': 'width:100%;border-collapse:collapse;font-size:0.9em;' });
            table.appendChild(E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' }, [
                E('th', { 'style': 'padding:8px;' }, _('Status')),
                E('th', { 'style': 'padding:8px;' }, _('Radio')),
                E('th', { 'style': 'padding:8px;' }, _('Mode')),
                E('th', { 'style': 'padding:8px;' }, _('SSID')),
                E('th', { 'style': 'padding:8px;' }, _('Security')),
                E('th', { 'style': 'padding:8px;' }, _('Password')),
                E('th', { 'style': 'padding:8px;' }, _('Network')),
                E('th', { 'style': 'padding:8px;text-align:right;' }, _(''))
            ]));

            ifaces.forEach(function(w) {
                var sid = w['.name'];
                var disabled = (w.disabled === '1');
                var key = w.key || w.key1 || '';
                var keyShown = key ? (key.length > 6 ? key.slice(0,3) + '…' + key.slice(-2) : '••••') : '';
                var mode = w.mode || 'ap';
                var row = E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.06);' });
                row.appendChild(E('td', { 'style': 'padding:8px;' },
                    E('span', { 'class': 'gw-badge ' + (disabled ? 'gw-badge-off' : 'gw-badge-on') },
                        disabled ? _('disabled') : _('enabled'))));
                row.appendChild(E('td', { 'style': 'padding:8px;' }, w.device || '—'));
                row.appendChild(E('td', { 'style': 'padding:8px;' }, mode));
                row.appendChild(E('td', { 'style': 'padding:8px;' }, w.ssid || '—'));
                row.appendChild(E('td', { 'style': 'padding:8px;' }, w.encryption || '—'));
                row.appendChild(E('td', { 'style': 'padding:8px;font-family:monospace;' }, keyShown || '—'));
                row.appendChild(E('td', { 'style': 'padding:8px;' }, w.network || '—'));
                row.appendChild(E('td', { 'style': 'padding:8px;text-align:right;' },
                    E('button', { 'class': 'btn cbi-button',
                        'style': 'padding:4px 12px;font-size:0.85em;',
                        'click': function() { self.wirelessQuickEdit(sid); } }, _('Edit'))));
                table.appendChild(row);
            });
            return table;
        })();
        var wifiSection = section('Wireless Quick Edit', E('div', {}, [
            E('p', { 'style': 'color:#666;font-size:0.9em;margin:0 0 12px 0;' },
                _('Change SSID, security, password, or attach a network interface — for every wireless interface on both radios (master / client / mesh / guest / iot).')),
            wifiBody
        ]));

        return E('div', {}, [pppoeSection, pwSection, wifiSection, shortcutSection]);
    },

    renderLogs: function() {
        var self = this;
        var levels = [
            { v: 8, label: 'Debug (8)' }, { v: 7, label: 'Info (7)' }, { v: 6, label: 'Notice (6)' },
            { v: 5, label: 'Warning (5)' }, { v: 4, label: 'Error (4)' }, { v: 3, label: 'Critical (3)' },
            { v: 2, label: 'Alert (2)' }, { v: 1, label: 'Emergency (1)' }, { v: 0, label: 'Silent (0)' }
        ];
        var current = uci.get('system', '@system[0]', 'log_level') || '5';
        var select = E('select', { 'id': 'qa-log-level', 'style': 'padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;min-width:220px;' });
        levels.forEach(function(l) {
            var opt = E('option', { 'value': String(l.v) }, l.label);
            if (String(l.v) === String(current)) opt.selected = true;
            select.appendChild(opt);
        });
        return E('div', {}, [
            E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;margin-bottom:18px;' }, [
                E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, 'System Log Level'),
                E('p', { 'style': 'color:#777;font-size:0.9em;margin:0 0 12px 0;' }, 'Current: ' + current + '. Lower = fewer logs.'),
                select,
                E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:12px;margin-left:8px;', 'click': function() {
                    var v = document.getElementById('qa-log-level').value;
                    if (!confirm('Change log level to ' + v + '?')) return;
                    var cmd = 'uci set system.@system[0].log_level=' + v + '; uci commit system; /etc/init.d/log restart';
                    self.runCommand(cmd, 'Set log level').then(function() { ui.addNotification('Done', 'Log level set to ' + v + ' — reloading...', 'info'); setTimeout(function() { window.location.reload(); }, 1200); });
                } }, 'Apply')
            ]),
            E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;margin-bottom:18px;' }, [
                E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, 'Cron Log Level'),
                E('p', { 'style': 'color:#777;font-size:0.9em;margin:0 0 12px 0;' }, 'OpenWrt cron is BusyBox crond — logs go to syslog at current system level.'),
                E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() {
                    self.runCommand('/etc/init.d/cron restart && logger -t cron "cron restarted"', 'Restart cron');
                } }, 'Restart Cron'),
                E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'style': 'margin-left:8px;', 'click': function() {
                    self.runCommand('logread | grep -i cron | tail -30', 'Recent cron log');
                } }, 'Show Recent Cron Log')
            ]),
            E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;' }, [
                E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, 'Log Viewer'),
                E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() { self.runCommand('logread | tail -50', 'Last 50 log lines'); } }, 'Last 50 lines'),
                E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'style': 'margin-left:8px;', 'click': function() { self.runCommand('logread | grep -i error | tail -30', 'Errors'); } }, 'Errors only'),
                E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'style': 'margin-left:8px;', 'click': function() { self.runCommand('dmesg | tail -30', 'Kernel messages'); } }, 'Kernel (dmesg)')
            ])
        ]);
    },

    renderServices: function() {
        var self = this;
        function inputRow(label, id, placeholder) {
            return E('div', { 'style': 'margin-bottom:10px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, label),
                E('input', { 'id': id, 'placeholder': placeholder || '', 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;box-sizing:border-box;' })
            ]);
        }
        var actionSelect = E('select', { 'id': 'qa-svc-action', 'style': 'padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;min-width:220px;' }, [
            E('option', { 'value': 'enable_start' }, 'Enable + Start'),
            E('option', { 'value': 'disable_stop' }, 'Disable + Stop'),
            E('option', { 'value': 'restart' }, 'Restart'),
            E('option', { 'value': 'status' }, 'Show Status')
        ]);
        var row2 = E('div', { 'style': 'margin-bottom:10px;' }, [
            E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, 'Action'),
            actionSelect
        ]);

        var applierSection = E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;margin-bottom:18px;' }, [
            E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, 'Service Mode Applier'),
            E('p', { 'style': 'color:#777;font-size:0.9em;margin:0 0 12px 0;' }, 'Enable, disable, restart, or check any service on the router.'),
            inputRow('Service Name', 'qa-svc-name', 'e.g. dnsmasq, firewall, uhttpd'),
            row2,
            E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:8px;', 'click': function() {
                var name = document.getElementById('qa-svc-name').value.trim();
                var action = document.getElementById('qa-svc-action').value;
                if (!name) { ui.addNotification('Error', 'Enter service name', 'danger'); return; }
                if (!/^[a-zA-Z0-9_\-]+$/.test(name)) { ui.addNotification('Error', 'Invalid service name', 'danger'); return; }
                var cmd;
                if (action === 'enable_start') cmd = '/etc/init.d/' + name + ' enable && /etc/init.d/' + name + ' start';
                else if (action === 'disable_stop') cmd = '/etc/init.d/' + name + ' stop; /etc/init.d/' + name + ' disable';
                else if (action === 'restart') cmd = '/etc/init.d/' + name + ' restart';
                else cmd = '/etc/init.d/' + name + ' enabled; /etc/init.d/' + name + ' running 2>/dev/null; ubus call service list "{\\"name\\":\\"' + name + '\\"}" 2>/dev/null';
                if (!confirm('Apply "' + action + '" to service "' + name + '"?\n\nCommand:\n' + cmd)) return;
                ui.addNotification('Running', name + ' ' + action, 'info');
                self.runCommand(cmd, name + ': ' + action);
            } }, 'Apply')
        ]);

        var listSection = E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;' }, [
            E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, 'Service Lists'),
            E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() { self.runCommand('/etc/init.d/* enabled 2>/dev/null; echo "---"; ls /etc/init.d/', 'Enabled services'); } }, 'Enabled Services'),
            E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'style': 'margin-left:8px;', 'click': function() { self.runCommand('for s in /etc/init.d/*; do n=$(basename $s); /etc/init.d/$n enabled 2>/dev/null || echo "DISABLED: $n"; done', 'Disabled services'); } }, 'Disabled Services'),
            E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'style': 'margin-left:8px;', 'click': function() { self.runCommand('ubus list | sort', 'All ubus services'); } }, 'Active ubus Services')
        ]);
        return E('div', {}, [applierSection, listSection]);
    },

    renderDependencies: function() {
        var self = this;
        var inputRow = E('div', { 'style': 'margin-bottom:10px;' }, [
            E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, 'Package name (leave blank to list all)'),
            E('input', { 'id': 'qa-dep-pkg', 'placeholder': 'e.g. luci-app-firewall', 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;box-sizing:border-box;' })
        ]);

        function runSingle() {
            var pkg = document.getElementById('qa-dep-pkg').value.trim();
            if (!pkg) { ui.addNotification('Error', 'Enter a package name', 'danger'); return; }
            if (!/^[a-zA-Z0-9_\-\+\.]+$/.test(pkg)) { ui.addNotification('Error', 'Invalid package name', 'danger'); return; }
            var cmd = 'if command -v apk >/dev/null 2>&1; then echo "=== apk info --depends ' + pkg + ' ==="; apk info --depends ' + pkg + ' 2>&1 || apk info -R ' + pkg + ' 2>&1; else echo "=== opkg info ' + pkg + ' ==="; opkg info ' + pkg + ' 2>&1 | grep -A50 "^Package:"; fi';
            ui.addNotification('Running', 'Fetching ' + pkg + ' dependencies...', 'info');
            self.runCommand(cmd, 'Dependencies: ' + pkg);
        }

        var singleBox = E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;margin-bottom:18px;' }, [
            E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, 'Package Dependency Inspector'),
            E('p', { 'style': 'color:#777;font-size:0.9em;margin:0 0 12px 0;' }, 'Auto-detects apk (OpenWrt 25.12+) vs opkg (older). Enter a package name to view its dependencies.'),
            inputRow,
            E('button', { 'class': 'btn cbi-button cbi-button-action important', 'click': runSingle }, 'Show Dependencies')
        ]);

        var allBox = E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;' }, [
            E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, 'All Installed Packages with Dependencies'),
            E('p', { 'style': 'color:#777;font-size:0.9em;margin:0 0 12px 0;' }, 'Lists every installed package and its full dependency tree. Output may be large.'),
            E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() {
                var cmd = 'if command -v apk >/dev/null 2>&1; then apk list --installed -I 2>/dev/null | head -200; echo ""; echo "=== Total installed ==="; apk list -I 2>/dev/null | wc -l; else opkg list-installed; fi';
                ui.addNotification('Running', 'Listing all packages...', 'info');
                self.runCommand(cmd, 'All packages');
            } }, 'List All Packages'),
            E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'style': 'margin-left:8px;', 'click': function() {
                var cmd = 'if command -v apk >/dev/null 2>&1; then apk list -I --depends 2>/dev/null | head -300; else awk \'/^Package:/{p=$2} /^Depends:/{print p " -> " $0}\' /usr/lib/opkg/status; fi';
                ui.addNotification('Running', 'Listing dependencies...', 'info');
                self.runCommand(cmd, 'Package dependencies');
            } }, 'List All Dependencies'),
            E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'style': 'margin-left:8px;', 'click': function() {
                var cmd = 'if command -v apk >/dev/null 2>&1; then apk info --depends 2>/dev/null | head -200; else opkg status | grep -E "^(Package|Depends):"; fi';
                ui.addNotification('Running', 'Fetching dependency pairs...', 'info');
                self.runCommand(cmd, 'Dependency pairs');
            } }, 'Compact View')
        ]);

        var totalsBox = E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:16px;margin-top:18px;' }, [
            E('h3', { 'style': 'margin:0 0 12px 0;font-size:1.05em;' }, 'System Package Summary'),
            E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() {
                var cmd = 'echo "Package manager:"; command -v apk >/dev/null 2>&1 && echo "apk (OpenWrt 25.12+)" || echo "opkg (OpenWrt <=24.10)"; echo ""; echo "Total installed packages:"; if command -v apk >/dev/null 2>&1; then apk list -I 2>/dev/null | wc -l; else opkg list-installed | wc -l; fi; echo ""; echo "Recent installs:"; if command -v apk >/dev/null 2>&1; then apk list -I 2>/dev/null | tail -20; else opkg list-installed | tail -20; fi';
                self.runCommand(cmd, 'Package summary');
            } }, 'System Package Summary')
        ]);

        return E('div', {}, [singleBox, allBox, totalsBox]);
    },

    renderCommand: function() {
        var self = this;
        function docBox(title, content) {
            var details = E('details', { 'style': 'margin-bottom:12px;background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.08);border-radius:8px;padding:12px 16px;' });
            details.appendChild(E('summary', { 'style': 'cursor:pointer;font-weight:bold;color:#1e90ff;font-size:1em;' }, title));
            details.appendChild(E('div', { 'style': 'padding-top:10px;font-size:0.92em;line-height:1.5;' }, content));
            return details;
        }
        function codeBlock(text) {
            return E('pre', { 'style': 'background:#1e1e1e;color:#00ff00;padding:10px;border-radius:6px;font-family:monospace;font-size:0.85em;overflow-x:auto;margin:8px 0;white-space:pre-wrap;' }, text);
        }
        var runnerBox = E('div', { 'style': 'background:rgba(30,144,255,0.08);border:1px solid rgba(30,144,255,0.2);border-radius:8px;padding:16px;margin-bottom:20px;' }, [
            E('h3', { 'style': 'margin:0 0 10px 0;' }, 'Direct Command Execution'),
            E('p', { 'style': 'color:#666;font-size:0.9em;margin:0 0 12px 0;' }, 'Run shell commands as root. Output in notification.'),
            E('textarea', { 'id': 'qa-cmd-input', 'placeholder': 'e.g. df -h', 'style': 'width:100%;min-height:90px;padding:10px;border:1px solid #ccc;border-radius:4px;font-family:monospace;font-size:0.9em;box-sizing:border-box;' }),
            E('div', { 'style': 'margin-top:10px;display:flex;gap:10px;flex-wrap:wrap;' }, [
                E('button', { 'class': 'btn cbi-button cbi-button-action important', 'click': function() {
                    var cmd = document.getElementById('qa-cmd-input').value.trim();
                    if (!cmd) return;
                    if (!confirm('Run this command?\n\n' + cmd)) return;
                    ui.addNotification('Running', 'Command executing...', 'info');
                    self.runCommand(cmd, 'Command');
                } }, 'Run Command'),
                E('button', { 'class': 'btn cbi-button', 'click': function() { document.getElementById('qa-cmd-input').value = ''; } }, 'Clear')
            ])
        ]);
        var docs = E('div', {}, [
            E('h3', { 'style': 'margin:0 0 12px 0;' }, 'OpenWrt Command Reference'),
            docBox('System Information', E('div', {}, [codeBlock('uname -a\ncat /etc/openwrt_release\ncat /proc/cpuinfo\nfree -h\ndf -h\nuptime')])),
            docBox('Network Diagnostics', E('div', {}, [codeBlock('ip addr show\nip route show\niwinfo\nping -c 4 8.8.8.8\nnslookup google.com\ntraceroute 8.8.8.8')])),
            docBox('WiFi Management', E('div', {}, [codeBlock('/sbin/wifi down\n/sbin/wifi up\nwifi status\niwinfo wlan0 scan')])),
            docBox('Firewall / Routing', E('div', {}, [codeBlock('nft list ruleset\nuci show firewall\nuci show network\nfw4 reload')])),
            docBox('Package Management', E('div', {}, [codeBlock('opkg update && opkg list-installed\napk update && apk list -I')])),
            docBox('Service Control', E('div', {}, [codeBlock('/etc/init.d/network restart\nservice <name> enable\nservice <name> disable')])),
            docBox('Logs and Debugging', E('div', {}, [codeBlock('logread\nlogread -f\ndmesg\nlogread | grep error')])),
            docBox('UCI Configuration', E('div', {}, [codeBlock('uci show\nuci get network.wan.proto\nuci set network.wan.proto=dhcp\nuci commit network')])),
            docBox('Process Management', E('div', {}, [codeBlock('ps w\ntop -n 1\nkill <pid>\nlsmod')])),
            docBox('GPIO / Hardware Buttons', E('div', {}, [codeBlock('ubus call system board\nls /sys/class/gpio/\n/etc/rc.button/reset')])),
            docBox('Backup and Restore', E('div', {}, [codeBlock('sysupgrade -b /tmp/backup.tar.gz\nsysupgrade -r /tmp/backup.tar.gz\nfirstboot -y')])),
            docBox('Useful One-Liners', E('div', {}, [
                E('p', {}, 'Clear cache:'), codeBlock('rm -rf /tmp/luci-* && /etc/init.d/rpcd restart && /etc/init.d/uhttpd restart'),
                E('p', {}, 'LEDs off:'), codeBlock('for f in /sys/class/leds/*/brightness; do echo 0 > $f; done'),
                E('p', {}, 'Reboot in 5 min:'), codeBlock('(sleep 300 && reboot) &')
            ]))
        ]);
        return E('div', {}, [runnerBox, docs]);
    },

    renderHotplug: function() {
        var self = this;

        var regenBar = E('div', { 'style': 'background:rgba(30,144,255,0.08);border:1px solid rgba(30,144,255,0.2);border-radius:8px;padding:12px;margin-bottom:16px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:10px;' }, [
            E('div', { 'style': 'font-size:0.9em;' }, [
                E('strong', {}, 'Generator: '),
                E('span', {}, 'Rules are stored in UCI. After Save & Apply, click Regenerate to write the handler scripts into /etc/hotplug.d/iface/.')
            ]),
            E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': function() {
                if (!confirm('Regenerate hotplug handler scripts from /etc/config/hotplug?')) return;
                ui.addNotification('Running', 'Regenerating handlers...', 'info');
                self.callSystemCommand('/bin/sh', [ '-c', '/etc/init.d/quickactions-hotplug restart' ]).then(function(r) {
                    var out = r.stdout || '';
                    if (r.stderr) out += '\n' + r.stderr;
                    var uid = 'qa-hp-gen-' + Date.now();
                    var pre = document.createElement('pre');
                    pre.id = uid;
                    pre.style.cssText = 'text-align:left;white-space:pre-wrap;background:#1e1e1e;color:#00ff00;padding:12px;border-radius:6px;font-family:monospace;font-size:0.85em;width:100%;box-sizing:border-box;margin:0;';
                    pre.textContent = out || 'Handlers regenerated.';
                    ui.addNotification('Regenerated', pre, 'info');
                    var el = document.getElementById(uid);
                    if (el && el.closest) { var c = el.closest('.alert'); if (c) { c.style.maxWidth = '95%'; c.style.width = 'auto'; } }
                }).catch(function(err) {
                    ui.addNotification('Failed', (err && err.message) ? err.message : String(err), 'danger');
                });
            } }, 'Regenerate Handlers')
        ]);

        var m = new form.Map('hotplug', _('Hotplug Rules'),
            _('Run commands on network interface events or when connectivity monitors fail. Replaces luci-app-hotplug.'));

        var s = m.section(form.GridSection, 'iface', _('Interface Events'),
            _('Execute commands when a logical interface goes up, down, or changes state.'));
        s.addremove = true;
        s.nodescriptions = true;
        var o = s.option(form.TextValue, 'description', _('Description'));
        o.placeholder = _('e.g. Restart firewall on WAN up');
        o = s.option(form.Flag, 'enabled', _('Enabled'));
        o.default = '1';
        o.rmempty = false;
        o = s.option(form.ListValue, 'action', _('Trigger event'));
        o.default = 'ifup';
        o.value('ifup', _('Interface up'));
        o.value('ifdown', _('Interface down'));
        o.value('ifup-failed', _('Interface up failed'));
        o.value('ifupdate', _('Interface changed'));
        o.value('free', _('Interface removed'));
        o.value('reload', _('Interface reload'));
        o.value('iflink', _('Interface received link'));
        o.value('create', _('Interface created'));
        o = s.option(form.Value, 'interface', _('Interface'),
            _('The logical interface to watch (e.g. wan, lan)'));
        o.rmempty = false;
        o = s.option(form.DynamicList, 'command', _('Commands to run'));
        o.datatype = 'string';
        o.placeholder = _('/etc/init.d/firewall restart');

        var s2 = m.section(form.GridSection, 'hotplug', _('Connectivity Monitors'),
            _('Ping test hosts through an interface. After consecutive failures, reset the interface or reboot.'));
        s2.addremove = true;
        s2.nodescriptions = true;
        o = s2.option(form.Flag, 'enabled', _('Enabled'));
        o.default = '1';
        o.rmempty = false;
        o = s2.option(form.Value, 'iface', _('Ping interface'));
        o.rmempty = false;
        o = s2.option(form.DynamicList, 'testip', _('Test hosts'));
        o.datatype = 'or(hostname,ipaddr("nomask"))';
        o.placeholder = '1.1.1.1';
        o = s2.option(form.Value, 'check_period', _('Check period (seconds)'));
        o.default = '60';
        o.datatype = 'and(uinteger,min(20))';
        o.rmempty = false;
        o = s2.option(form.Value, 'sw_before_modres', _('Failures before interface reset'));
        o.default = '3';
        o.datatype = 'and(uinteger,min(0),max(100))';
        o.rmempty = false;
        o = s2.option(form.Value, 'sw_before_sysres', _('Failures before reboot'));
        o.default = '0';
        o.datatype = 'and(uinteger,min(0),max(100))';
        o.rmempty = false;

        return m.render().then(function(formNode) {
            var saveBtn = E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:14px;', 'click': function() {
                if (!confirm('Save hotplug config and regenerate handlers?')) return;
                ui.addNotification('Saving', 'Applying hotplug config...', 'info');
                m.save().then(function() {
                    return uci.apply(10);
                }).then(function() {
                    return self.callSystemCommand('/bin/sh', ['-c', '/etc/init.d/quickactions-hotplug restart']).catch(function(){ return {}; });
                }).then(function() {
                    ui.addNotification('Saved', 'Hotplug config saved, applied, and handlers regenerated.', 'info');
                    self.switchTab('hotplug');
                }).catch(function(err) {
                    ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
                });
            } }, 'Save & Apply Hotplug');
            return E('div', {}, [regenBar, formNode, saveBtn]);
        });
    },

    cwAddStyles: function() {
        if (document.getElementById('cw-styles')) return;
        var style = document.createElement('style');
        style.id = 'cw-styles';
        style.type = 'text/css';
        style.textContent = `
        .cw-root .cron-multiselect {
          width: 100%; min-height: 140px;
          background: rgba(0,0,0,0.03);
          color: inherit; border: 1px solid rgba(0,0,0,0.15);
          border-radius: 4px; padding: 4px; font-family: inherit;
          font-size: 13px; line-height: 1.4; outline: none;
        }
        :root[data-darkmode="true"] .cw-root .cron-multiselect {
          background: #2a2f34; color: #e5e7eb; border-color: #3a4146;
        }
        .cw-root .cron-minute-head  { background: #fdd2d6; color: #263238; font-weight: bold; padding: 8px; }
        .cw-root .cron-hour-head    { background: #cfead1; color: #263238; font-weight: bold; padding: 8px; }
        .cw-root .cron-day-head     { background: #ffd8ad; color: #263238; font-weight: bold; padding: 8px; }
        .cw-root .cron-month-head   { background: #bbdefb; color: #263238; font-weight: bold; padding: 8px; }
        .cw-root .cron-weekday-head { background: #e1bee7; color: #263238; font-weight: bold; padding: 8px; }
        :root[data-darkmode="true"] .cw-root .cron-minute-head  { background: #8b4f5a; color: #ffcdd2; }
        :root[data-darkmode="true"] .cw-root .cron-hour-head    { background: #4f6b52; color: #c8e6c9; }
        :root[data-darkmode="true"] .cw-root .cron-day-head     { background: #7a5838; color: #ffe0b2; }
        :root[data-darkmode="true"] .cw-root .cron-month-head   { background: #4a6b8e; color: #bbdefb; }
        :root[data-darkmode="true"] .cw-root .cron-weekday-head { background: #5a4f71; color: #e1bee7; }
        .cw-root .cron-badge {
          display: inline-block; padding: 3px 6px; border-radius: 6px;
          border: 1px solid rgba(0,0,0,0.15); font-weight: 600;
        }
        :root[data-darkmode="true"] .cw-root .cron-badge { border-color: rgba(255,255,255,0.2); }
        .cw-root #cw_preview {
          min-height: 40px; padding: 8px; border-radius: 6px;
          border: 1px solid rgba(0,0,0,0.15); font-family: monospace;
          background: rgba(0,0,0,0.03);
        }
        :root[data-darkmode="true"] .cw-root #cw_preview { background: #2a2f34; border-color: #3a4146; }
        .cw-root .cw-section { background: rgba(0,0,0,0.02); border: 1px solid rgba(0,0,0,0.06); border-radius: 8px; padding: 16px; margin-bottom: 18px; }
        :root[data-darkmode="true"] .cw-root .cw-section { background: rgba(255,255,255,0.03); border-color: rgba(255,255,255,0.08); }
        `;
        document.head.appendChild(style);
    },

    cwColors: {
        light: { minute:'#fdd2d6', hour:'#cfead1', day:'#ffd8ad', month:'#bbdefb', weekday:'#e1bee7' },
        dark:  { minute:'#5b2f35', hour:'#2f4732', day:'#4a3828', month:'#30475e', weekday:'#3a2f41' }
    },
    cwGetCurrentColors: function() {
        return document.documentElement.getAttribute('data-darkmode') === 'true' ? this.cwColors.dark : this.cwColors.light;
    },
    cwGetBadgeTextColor: function() {
        return document.documentElement.getAttribute('data-darkmode') === 'true' ? '#ffffff' : '#111111';
    },
    cwWeekdayNames: function() {
        return [ _('Sunday'), _('Monday'), _('Tuesday'), _('Wednesday'), _('Thursday'), _('Friday'), _('Saturday') ];
    },
    cwMonthNames: function() {
        return [ '', _('January'), _('February'), _('March'), _('April'), _('May'), _('June'),
                 _('July'), _('August'), _('September'), _('October'), _('November'), _('December') ];
    },
    cwDescribeCron: function(minute, hour, day, month, weekday, command) {
        var parts = [];
        if (minute !== '*') parts.push(_('minute: %s').format(minute));
        if (hour !== '*') parts.push(_('hour: %s').format(hour));
        if (day !== '*') parts.push(_('day: %s').format(day));
        if (month !== '*') parts.push(_('month: %s').format(month));
        if (weekday !== '*') parts.push(_('weekday: %s').format(weekday));
        if (parts.length === 0) return command ? _('Command "%s" will run every minute.').format(command) : '';
        return command ? _('Command "%s" will run at').format(command) + ': ' + parts.join('; ')
                       : _('Runs at') + ': ' + parts.join('; ');
    },

    cwBadge: function(bg, content) {
        var color = this.cwGetBadgeTextColor();
        return '<span class="cron-badge" style="background:' + bg + ';color:' + color + '">' + content + '</span>';
    },
    cwGetSelectedValues: function(selectId) {
        var sel = document.getElementById(selectId);
        if (!sel) return [];
        return Array.prototype.slice.call(sel.selectedOptions || []).map(function(o){ return o.value; });
    },
    cwNormalizeSelection: function(values) {
        if (!values || values.length === 0) return ['*'];
        if (values.indexOf('*') >= 0) return ['*'];
        var seen = {};
        values.forEach(function(v){ seen[parseInt(v,10)] = 1; });
        return Object.keys(seen).map(Number).sort(function(a,b){ return a-b; }).map(String);
    },
    cwCompressValues: function(values) {
        if (!values || values.length === 0) return '*';
        if (values.length === 1) return values[0];
        var nums = values.map(Number), parts = [], start = nums[0], prev = nums[0];
        for (var i = 1; i < nums.length; i++) {
            var cur = nums[i];
            if (cur === prev + 1) { prev = cur; continue; }
            parts.push(start === prev ? String(start) : (start + '-' + prev));
            start = prev = cur;
        }
        parts.push(start === prev ? String(start) : (start + '-' + prev));
        return parts.join(',');
    },
    cwBuildField: function(selectId, checkboxId) {
        var vals = this.cwNormalizeSelection(this.cwGetSelectedValues(selectId));
        if (checkboxId) {
            var cb = document.getElementById(checkboxId);
            if (cb && cb.checked) {
                var sel = vals[0];
                return (sel === '*' || sel === undefined) ? '*' : '*/' + sel;
            }
        }
        if (vals.length === 0 || vals[0] === '*') return '*';
        return this.cwCompressValues(vals);
    },

    cwUpdatePreview: function() {
        var minute  = this.cwBuildField('cw_minute',  'cw_minute_cb');
        var hour    = this.cwBuildField('cw_hour',    'cw_hour_cb');
        var day     = this.cwBuildField('cw_day',     'cw_day_cb');
        var month   = this.cwBuildField('cw_month');
        var weekday = this.cwBuildField('cw_weekday');
        var cmdEl   = document.getElementById('cw_command');
        var command = cmdEl ? cmdEl.value : '';

        var colors = this.cwGetCurrentColors();
        var html = '';
        html += (minute  !== '*') ? this.cwBadge(colors.minute,  minute)  : minute;  html += ' ';
        html += (hour    !== '*') ? this.cwBadge(colors.hour,    hour)    : hour;    html += ' ';
        html += (day     !== '*') ? this.cwBadge(colors.day,     day)     : day;     html += ' ';
        html += (month   !== '*') ? this.cwBadge(colors.month,   month)   : month;   html += ' ';
        html += (weekday !== '*') ? this.cwBadge(colors.weekday, weekday) : weekday; html += ' ';
        html += command ? '<span class="cron-badge" style="background:#90a4ae">' + command + '</span>' : '';

        var prev = document.getElementById('cw_preview');
        if (prev) prev.innerHTML = html;
        var txt = document.getElementById('cw_preview_text');
        if (txt) txt.value = minute + ' ' + hour + ' ' + day + ' ' + month + ' ' + weekday + ' ' + command;
        var hum = document.getElementById('cw_human');
        if (hum) hum.value = this.cwDescribeCron(minute, hour, day, month, weekday, command);
    },

    cwAppend: function() {
        var input = document.getElementById('cw_preview_text');
        if (!input) return;
        var line = (input.value || '').trim();
        if (!line || line === '* * * * *') { ui.addNotification('Error', _('Check the cron entry - it must contain time + command'), 'danger'); return; }
        if (line.split(/\s+/).length < 6) { ui.addNotification('Error', _('Please enter the command'), 'danger'); return; }
        if (!confirm('Add this cron entry?\n\n' + line)) return;

        fs.read('/etc/crontabs/root').catch(function(){ return ''; }).then(function(content) {
            var cur = (content || '').replace(/\r\n/g, '\n');
            var haystack = '\n' + cur + (cur.slice(-1) === '\n' ? '' : '\n');
            if (haystack.indexOf('\n' + line + '\n') >= 0) {
                ui.addNotification('Duplicate', _('This entry already exists'), 'info');
                return null;
            }
            if (cur && cur.slice(-1) !== '\n') cur += '\n';
            cur += line + '\n';
            return fs.write('/etc/crontabs/root', cur).then(function() {
                return fs.exec('/etc/init.d/cron', ['restart']);
            }).then(function() {
                ui.addNotification('Added', E('p', {}, line), 'info');
            });
        }).catch(function(e) {
            ui.addNotification('Error', (e && e.message) ? e.message : String(e), 'danger');
        });
    },

    cwGenerateOptions: function(start, end, labels) {
        var opts = [ E('option', { value: '*', selected: true }, '*') ];
        if (labels) {
            for (var i = 0; i < labels.length; i++) opts.push(E('option', { value: String(start + i) }, labels[i]));
        } else {
            for (var j = start; j <= end; j++) opts.push(E('option', { value: String(j) }, String(j)));
        }
        return opts;
    },
    cwResetMulti: function(id) {
        var sel = document.getElementById(id);
        if (!sel) return;
        Array.prototype.slice.call(sel.options).forEach(function(o){ o.selected = (o.value === '*'); });
    },

    renderCrontabWizard: function() {
        var self = this;
        this.cwAddStyles();

        var grid = E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1em;margin-bottom:1em;' });

        function cwSelect(id, opts, cbId, cbLabel) {
            var sel = E('select', { 'id': id, 'class': 'cron-multiselect', 'multiple': true, 'size': 8, 'change': function(){ self.cwUpdatePreview(); } }, opts);
            var kids = [ sel ];
            if (cbId) {
                kids.push(E('div', { 'style': 'display:flex;align-items:center;gap:5px;margin-top:6px;' }, [
                    E('input', { 'type': 'checkbox', 'id': cbId, 'change': function(){ self.cwUpdatePreview(); } }),
                    E('label', { 'for': cbId, 'style': 'font-size:12px;' }, cbLabel)
                ]));
            }
            return E('div', { 'class': 'cw-section', 'style': 'padding:0;' }, [
                E('div', { 'class': id.replace('cw_', 'cron-') + '-head' }, cbLabel || id),
                E('div', { 'style': 'padding:8px;' }, kids)
            ]);
        }

        grid.appendChild(cwSelect('cw_minute',  this.cwGenerateOptions(0, 59), 'cw_minute_cb', _('Minute')));
        grid.appendChild(cwSelect('cw_hour',    this.cwGenerateOptions(0, 23), 'cw_hour_cb',   _('Hour')));
        grid.appendChild(cwSelect('cw_day',     this.cwGenerateOptions(1, 31), 'cw_day_cb',    _('Day')));
        grid.appendChild(cwSelect('cw_month',   this.cwGenerateOptions(1, 12, this.cwMonthNames().slice(1)), null, _('Month')));
        grid.appendChild(cwSelect('cw_weekday', this.cwGenerateOptions(0, 6, this.cwWeekdayNames()), null, _('Weekday')));

        var root = E('div', { 'class': 'cw-root' }, [
            E('h3', { 'style': 'margin:0 0 4px 0;' }, _('Graphical Crontab Configurator')),
            E('p', { 'style': 'color:#888;font-size:0.9em;margin:0 0 16px 0;' }, _('Pick time units, type a command, preview the generated cron line, then add it.')),
            grid,
            E('div', { 'class': 'cw-section' }, [
                E('label', { 'style': 'font-weight:bold;display:block;margin-bottom:5px;' }, _('Command to execute:')),
                E('input', { 'id': 'cw_command', 'class': 'cbi-input-text', 'style': 'width:100%;margin-bottom:12px;', 'placeholder': 'echo hello', 'keyup': function(){ self.cwUpdatePreview(); }, 'change': function(){ self.cwUpdatePreview(); } }),
                E('label', { 'style': 'font-weight:bold;display:block;margin-bottom:5px;' }, _('Preview:')),
                E('div', { 'id': 'cw_preview' }),
                E('label', { 'style': 'font-weight:bold;display:block;margin:12px 0 5px 0;' }, _('Description:')),
                E('textarea', { 'id': 'cw_human', 'readonly': true, 'style': 'width:100%;min-height:50px;font-size:0.85em;resize:vertical;' }),
                E('label', { 'style': 'font-weight:bold;display:block;margin:12px 0 5px 0;' }, _('Generated cron entry:')),
                E('input', { 'id': 'cw_preview_text', 'readonly': true, 'style': 'width:100%;font-family:monospace;' }),
                E('div', { 'style': 'margin-top:12px;display:flex;gap:10px;justify-content:flex-end;' }, [
                    E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() {
                        self.cwResetMulti('cw_minute'); self.cwResetMulti('cw_hour'); self.cwResetMulti('cw_day');
                        self.cwResetMulti('cw_month'); self.cwResetMulti('cw_weekday');
                        document.getElementById('cw_command').value = '';
                        ['cw_minute_cb','cw_hour_cb','cw_day_cb'].forEach(function(id){ var e = document.getElementById(id); if (e) e.checked = false; });
                        self.cwUpdatePreview();
                    } }, _('Reset')),
                    E('button', { 'class': 'btn cbi-button cbi-button-action important', 'click': function(){ self.cwAppend(); } }, _('Add to Cron'))
                ])
            ])
        ]);

        setTimeout(function(){ self.cwUpdatePreview(); }, 0);
        return root;
    },

    renderGuestWifi: function() {
        var self = this;
        var gw = new GuestWifiViewClass();
        return gw.load().then(function() {
            return gw.render();
        }).then(function(node) {
            var actions = node.querySelector('.cbi-page-actions');
            if (actions) actions.style.display = 'none';
            var saveBtn = E('button', {
                'class': 'btn cbi-button cbi-button-action important',
                'click': function() {
                    if (!confirm('Save and apply guest WiFi configuration?')) return;
                    ui.addNotification('Saving', 'Applying guest WiFi configuration...', 'info');
                    Promise.resolve(gw.handleSave()).then(function() {
                        ui.addNotification('Success', 'Guest WiFi configuration saved and applied.', 'info');
                    }).catch(function(err) {
                        ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
                    });
                }
            }, 'Save Guest WiFi');
            return E('div', {}, [node, E('div', { 'style': 'margin-top:20px;text-align:right;' }, [saveBtn])]);
        });
    },

    renderTtyd: function() {
        var self = this;
        var enabled = uci.get('ttyd', 'ttyd', 'enable') !== '0';
        var port = uci.get('ttyd', 'ttyd', 'port') || '7681';
        var ssl = uci.get('ttyd', 'ttyd', 'ssl') || '0';
        var override = uci.get('ttyd', 'ttyd', 'url_override');
        // ttyd config may use an anonymous section (@ttyd[0])
        var currentCmd = uci.get_first('ttyd', 'ttyd', 'command')
                      || uci.get('ttyd', 'ttyd', 'command')
                      || '/bin/login';
        var autoLogin = (currentCmd === '/bin/sh' || currentCmd === '/bin/ash');

        // --- Auto-login: status badge + explicit Enable / Disable buttons ---
        function setTtydCommand(newCmd, label) {
            uci.load('ttyd').then(function() {
                var secs = uci.sections('ttyd', 'ttyd');
                var targetSec = (secs && secs.length > 0) ? secs[0]['.name'] : null;
                if (!targetSec) {
                    uci.set('ttyd', 'ttyd', 'ttyd');
                    targetSec = 'ttyd';
                }
                uci.set('ttyd', targetSec, 'command', newCmd);
                return uci.save();
            }).then(function() {
                return self.callSystemCommand('/bin/sh', ['-c', '/etc/init.d/ttyd restart']);
            }).then(function() {
                ui.addNotification('Success', label + ' applied. ttyd restarted.', 'info');
                self.switchTab('ttyd');
            }).catch(function(err) {
                ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
            });
        }

        var loginStatusBadge = autoLogin
            ? E('span', { 'style': 'padding:4px 10px;border-radius:4px;background:rgba(220,53,69,0.18);color:#dc3545;font-weight:bold;font-size:0.85em;' }, '🔴 Auto-Login: ON')
            : E('span', { 'style': 'padding:4px 10px;border-radius:4px;background:rgba(40,167,69,0.15);color:#28a745;font-weight:bold;font-size:0.85em;' }, '🔒 Login Required');

        // Active button gets a solid background + thick border.
        // Inactive button stays clickable but dimmed.
        var ENABLE_ACTIVE_STYLE   = 'padding:5px 14px;font-size:0.85em;font-weight:bold;background-color:#28a745 !important;background:#28a745 !important;color:#fff !important;border:2px solid #1e7e34 !important;';
        var ENABLE_INACTIVE_STYLE = 'padding:5px 14px;font-size:0.85em;opacity:0.6;border:2px solid transparent;';
        var DISABLE_ACTIVE_STYLE  = 'padding:5px 14px;font-size:0.85em;font-weight:bold;background-color:#dc3545 !important;background:#dc3545 !important;color:#fff !important;border:2px solid #a71d2a !important;';
        var DISABLE_INACTIVE_STYLE= 'padding:5px 14px;font-size:0.85em;opacity:0.6;border:2px solid transparent;';

        var enableLoginBtn = E('button', {
            'class': 'btn cbi-button',
            'title': autoLogin ? 'Currently active' : 'Click to enable root auto-login',
            'style': autoLogin ? ENABLE_ACTIVE_STYLE : ENABLE_INACTIVE_STYLE,
            'click': function() {
                if (autoLogin) {
                    ui.addNotification('Already Enabled', 'Auto-login is already active. Terminal runs ' + currentCmd + '.', 'info');
                    return;
                }
                var msg = '⚠️ WARNING: Enable root auto-login?\n\nThis changes ttyd command to /bin/sh. Anyone who can reach port ' + port + ' gets a root shell without credentials.\n\nEnsure ttyd is bound to loopback or LAN-only and your network is trusted.\n\nProceed?';
                if (!confirm(msg)) return;
                setTtydCommand('/bin/sh', 'Auto-login enabled');
            }
        }, 'Enable Auto-Login');

        var disableLoginBtn = E('button', {
            'class': 'btn cbi-button',
            'title': !autoLogin ? 'Currently active' : 'Click to disable root auto-login',
            'style': !autoLogin ? DISABLE_ACTIVE_STYLE : DISABLE_INACTIVE_STYLE,
            'click': function() {
                if (!autoLogin) {
                    ui.addNotification('Already Disabled', 'Terminal already requires login (' + currentCmd + ').', 'info');
                    return;
                }
                if (!confirm('Disable root auto-login and return to /bin/login prompt?')) return;
                setTtydCommand('/bin/login', 'Auto-login disabled');
            }
        }, 'Disable Auto-Login');

        var statusBar = E('div', { 'style': 'background:rgba(30,144,255,0.08);border:1px solid rgba(30,144,255,0.2);border-radius:8px;padding:12px;margin-bottom:14px;font-size:0.9em;' }, [
            E('div', { 'style': 'display:flex;align-items:center;gap:10px;flex-wrap:wrap;' }, [
                E('strong', {}, 'Terminal (ttyd):'),
                E('code', { 'style': 'background:rgba(0,0,0,0.15);padding:2px 6px;border-radius:3px;' }, currentCmd),
                loginStatusBadge,
                E('span', { 'style': 'flex:1;' }),
                enableLoginBtn,
                disableLoginBtn
            ])
        ]);

        var parts = [statusBar];

        if (!enabled) {
            parts.push(E('div', { 'class': 'alert-message warning' }, 'ttyd is disabled. Enable it below and save.'));
        } else if (port === '0') {
            parts.push(E('div', { 'class': 'alert-message warning' }, 'Random ttyd port not supported. Set a fixed port below.'));
        } else {
            var url = override || ((ssl === '1' ? 'https' : 'http') + '://' + window.location.hostname + ':' + port);
            // Mixed content check: if SSL is on but page is HTTP, iframe will be blocked
            var isPageHTTPS = window.location.protocol === 'https:';
            var isIframeHTTPS = (ssl === '1');
            var mixedContentBlocked = (!isPageHTTPS && isIframeHTTPS);

            if (mixedContentBlocked) {
                parts.push(E('div', { 'class': 'alert-message warning', 'style': 'margin-bottom:12px;' }, [
                    E('strong', {}, '⚠️ Mixed content block: '),
                    E('span', {}, 'ttyd is configured with SSL but you access LuCI over HTTP. The browser will refuse to load the terminal. '),
                    E('span', {}, 'Either access LuCI over HTTPS, or disable SSL in the ttyd config below.')
                ]));
            }

            var iframeEl = E('iframe', {
                'id': 'qa-ttyd-iframe',
                'src': url,
                'style': 'width:100%;min-height:60vh;border:1px solid rgba(0,0,0,0.15);border-radius:6px;resize:vertical;background:#000;'
            });
            parts.push(iframeEl);

            // Add reconnect buttons
            parts.push(E('div', { 'style': 'margin-top:10px;display:flex;gap:10px;flex-wrap:wrap;' }, [
                E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': function() {
                    if (!confirm('Force reconnect?\n\nThis kills all ttyd sessions and restarts the service. Any open terminal in another tab will be disconnected.')) return;
                    ui.addNotification('Reconnect', 'Killing stale ttyd sessions...', 'info');
                    self.callSystemCommand('/bin/sh', ['-c', 'killall ttyd 2>/dev/null; sleep 1; /etc/init.d/ttyd restart 2>/dev/null; sleep 1']).then(function() {
                        var f = document.getElementById('qa-ttyd-iframe');
                        if (f) {
                            var baseSrc = f.src.split('?')[0];
                            f.src = 'about:blank';
                            setTimeout(function(){ f.src = baseSrc + '?_t=' + Date.now(); }, 300);
                        }
                        ui.addNotification('Reconnected', 'Terminal service restarted. If blank, click Reconnect again.', 'info');
                    }).catch(function(err) {
                        ui.addNotification('Error', 'Restart failed: ' + ((err && err.message) ? err.message : String(err)), 'danger');
                    });
                } }, _('↻ Force Reconnect')),
                E('a', {
                    'class': 'btn cbi-button cbi-button-neutral',
                    'href': url,
                    'target': '_blank',
                    'rel': 'noopener noreferrer',
                    'style': 'text-decoration:none;'
                }, _('↗ Open in New Tab')),
                E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() {
                    var f = document.getElementById('qa-ttyd-iframe');
                    if (!f) { ui.addNotification('Focus', 'Terminal iframe not found.', 'warning'); return; }
                    try {
                        // 1. Focus the iframe element itself
                        f.focus();
                        if (f.contentWindow) f.contentWindow.focus();

                        // 2. ttyd uses xterm.js — its hidden helper-textarea captures keys
                        var doc = f.contentDocument;
                        if (doc) {
                            var ta = doc.querySelector('.xterm-helper-textarea');
                            if (ta) { ta.focus(); }
                            else {
                                // Fallback: any input/textarea/canvas inside
                                var el = doc.querySelector('textarea, input, .xterm canvas, canvas');
                                if (el) {
                                    el.focus();
                                    // Simulate a click to activate xterm
                                    try {
                                        el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                                    } catch(e) {}
                                }
                            }
                        }
                        ui.addNotification('Focused', 'Terminal focused. Start typing to interact.', 'info');
                    } catch(e) {
                        ui.addNotification('Focus failed', (e && e.message) ? e.message : String(e), 'warning');
                    }
                } }, _('Focus Terminal'))
            ]));

            // Auto-check if terminal went blank (WebSocket timeout)
            // Tracked on self to prevent stacking intervals on tab re-entry
            if (self._ttydWatchdogTimeout)  { clearTimeout(self._ttydWatchdogTimeout);  self._ttydWatchdogTimeout = null; }
            if (self._ttydWatchdogInterval) { clearInterval(self._ttydWatchdogInterval); self._ttydWatchdogInterval = null; }
            var lastCheck = Date.now();
            self._ttydWatchdogTimeout = setTimeout(function() {
                self._ttydWatchdogInterval = setInterval(function() {
                    var f = document.getElementById('qa-ttyd-iframe');
                    if (!f || !f.contentWindow) {
                        if (self._ttydWatchdogInterval) { clearInterval(self._ttydWatchdogInterval); self._ttydWatchdogInterval = null; }
                        return;
                    }
                    try {
                        var doc = f.contentDocument;
                        if (!doc) return;
                        var bodyText = doc.body ? doc.body.textContent : '';
                        var looksDead = bodyText.indexOf('to Reconnect') !== -1
                                     || bodyText.indexOf('Connection closed') !== -1
                                     || bodyText.indexOf('Disconnected') !== -1
                                     || (bodyText.length < 20 && doc.querySelector('canvas') === null);
                        if (looksDead && (Date.now() - lastCheck) > 20000) {
                            lastCheck = Date.now();
                            ui.addNotification('Terminal idle',
                                E('p', {}, 'The terminal session expired. Click "Reconnect Terminal" above to resume.'),
                                'info');
                        }
                    } catch(e) { /* cross-origin */ }
                }, 15000);
            }, 5000);
        }

        // --- Full config form via LuCI form.Map ---
        var m = new form.Map('ttyd', _('ttyd Configuration'), _('All backend options. Save applies and restarts ttyd.'));
        var s = m.section(form.TypedSection, 'ttyd', _('ttyd Instance'));
        s.anonymous = true;
        s.addremove = false;

        var o;
        o = s.option(form.Flag, 'enable', _('Enable'));
        o.default = true;
        s.option(form.Flag, 'unix_sock', _('UNIX socket'), _('Bind to UNIX domain socket instead of IP port'));
        o = s.option(form.Value, 'port', _('Port'), _('Port to listen (default: 7681, use 0 for random)'));
        o.depends('unix_sock', '0');
        o.datatype = 'port';
        o.placeholder = '7681';
        o = s.option(form.Value, 'interface', _('Interface'), _('Network interface to bind (e.g. br-lan, lo)'));
        o.depends('unix_sock', '0');
        o = s.option(form.Value, 'credential', _('Credential'), _('Basic auth user:password'));
        o.placeholder = 'username:password';
        o = s.option(form.Value, 'uid', _('User ID'));
        o.datatype = 'uinteger';
        o = s.option(form.Value, 'gid', _('Group ID'));
        o.datatype = 'uinteger';
        o = s.option(form.Value, 'signal', _('Signal'), _('Signal to send to command on exit (default: 1)'));
        o.datatype = 'uinteger';
        s.option(form.Flag, 'url_arg', _('Allow URL args'));
        s.option(form.Flag, 'readonly', _('Read-only'), _('Deny client write access to TTY'));
        o = s.option(form.DynamicList, 'client_option', _('Client option'), _('Send option to client'));
        o.placeholder = 'key=value';
        o = s.option(form.Value, 'terminal_type', _('Terminal type'));
        o.placeholder = 'xterm-256color';
        s.option(form.Flag, 'check_origin', _('Check origin'), _('Block cross-origin WebSocket'));
        o = s.option(form.Value, 'max_clients', _('Max clients'));
        o.datatype = 'uinteger';
        o.placeholder = '0';
        s.option(form.Flag, 'once', _('Once'), _('Accept one client then exit'));
        o = s.option(form.Value, 'index', _('Index'), _('Custom index.html path'));
        s.option(form.Flag, 'ipv6', _('IPv6'));
        s.option(form.Flag, 'ssl', _('SSL'));
        o = s.option(form.Value, 'ssl_cert', _('SSL cert'));
        o.depends('ssl', '1');
        o = s.option(form.Value, 'ssl_key', _('SSL key'));
        o.depends('ssl', '1');
        o = s.option(form.Value, 'ssl_ca', _('SSL CA'));
        o.depends('ssl', '1');
        o = s.option(form.ListValue, 'debug', _('Debug'), _('Log level'));
        o.value('1', _('Error'));
        o.value('3', _('Warning'));
        o.value('7', _('Notice'));
        o.value('15', _('Info'));
        o.default = '7';
        o = s.option(form.Value, 'command', _('Command'), _('Command to run in the shell'));
        o.placeholder = '/bin/login';
        s.option(form.Value, 'url_override', _('URL override'), _('Override URL in Terminal tab (for reverse proxy)'));

        return m.render().then(function(formNode) {
            // Strip page actions so LuCI doesn't hijack the outer view
            var actions = formNode.querySelectorAll('.cbi-page-actions');
            for (var i = 0; i < actions.length; i++) {
                if (actions[i].parentNode) actions[i].parentNode.removeChild(actions[i]);
            }

            var saveBtn = E('button', {
                'class': 'btn cbi-button cbi-button-action important',
                'style': 'margin-top:14px;',
                'click': function() {
                    if (!confirm('Save ttyd config and restart the service?')) return;
                    ui.addNotification('Saving', 'Applying ttyd config...', 'info');
                    m.save().then(function() {
                        return self.callSystemCommand('/bin/sh', ['-c', '/etc/init.d/ttyd restart']);
                    }).then(function() {
                        ui.addNotification('Saved', 'ttyd config updated and service restarted.', 'info');
                        self.switchTab('ttyd');
                    }).catch(function(err) {
                        ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
                    });
                }
            }, _('Save & Restart ttyd'));

            var cfgBox = E('details', { 'style': 'margin-top:20px;background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:12px 16px;' }, [
                E('summary', { 'style': 'cursor:pointer;font-weight:bold;color:#1e90ff;font-size:1em;' }, _('ttyd Configuration — full settings')),
                E('div', { 'style': 'padding-top:12px;' }, [formNode, saveBtn])
            ]);

            parts.push(cfgBox);
            return E('div', {}, parts);
        }).catch(function(err) {
            parts.push(E('div', { 'class': 'alert-message error' }, 'Form error: ' + (err && err.message ? err.message : String(err))));
            return E('div', {}, parts);
        });
    },

    renderTaskPlanScheduled: function() {
        var self = this;
        return uci.load('taskplan').then(function() {
            var m = new form.Map('taskplan', _('Scheduled Tasks'),
                _('Scheduled and startup tasks. Presets include reboot, shutdown, network restart, memory cleanup, custom scripts.'));

            var s = m.section(form.TypedSection, 'global');
            s.anonymous = true;
            var e = s.option(form.TextValue, 'customscript', _('Edit Custom Script'));
            e.description = _('Shell commands for [Customscript] task type');
            e.rows = 5;
            e.optional = false;
            e = s.option(form.TextValue, 'customscript2', _('Edit Custom Script2'));
            e.description = _('Shell commands for [Customscript2] task type');
            e.rows = 5;
            e.optional = false;

            var ss = m.section(form.TypedSection, 'stime', '');
            ss.addremove = true;
            ss.anonymous = true;
            ss.sortable = true;
            ss.template = 'cbi/tblsection';
            var remarks = ss.option(form.Value, 'remarks', _('Remarks')); remarks.optional = false;
            var enable = ss.option(form.Flag, 'enable', _('Enable')); enable.rmempty = false; enable.default = 1;
            var stype = ss.option(form.ListValue, 'stype', _('Scheduled Type'));
            stype.value(1, _('Scheduled Reboot'));
            stype.value(2, _('Scheduled Poweroff'));
            stype.value(3, _('Scheduled ReNetwork'));
            stype.value(4, _('Scheduled RestartSamba'));
            stype.value(5, _('Scheduled Restartwan'));
            stype.value(6, _('Scheduled Closewan'));
            stype.value(7, _('Scheduled Clearmem'));
            stype.value(8, _('Scheduled Sysfree'));
            stype.value(9, _('Scheduled DisReconn'));
            stype.value(10, _('Scheduled DisRereboot'));
            stype.value(11, _('Scheduled Restartmwan3'));
            stype.value(13, _('Scheduled Wifiup'));
            stype.value(14, _('Scheduled Wifidown'));
            stype.value(12, _('Scheduled Customscript'));
            stype.value(15, _('Scheduled Customscript2'));
            stype.default = 1;
            var month = ss.option(form.Value, 'month', _('Month(0~11)')); month.rmempty = false; month.default = '*'; month.datatype = 'string';
            var week = ss.option(form.Value, 'week', _('Week Day(0~6)')); week.rmempty = true; week.default = '*'; week.datatype = 'string';
            var hour = ss.option(form.Value, 'hour', _('Hour(0~23)')); hour.rmempty = false; hour.default = 0; hour.datatype = 'string';
            var minute = ss.option(form.Value, 'minute', _('Minute(0~59)')); minute.rmempty = false; minute.default = 0; minute.datatype = 'string';

            // Note: apply_on_parse intentionally NOT set — the Save & Apply button
            // below is the sole writer. Setting apply_on_parse caused the form to
            // commit immediately on open and again on Save, doubling the writes.
            return m.render().then(function(formNode) {
                var saveBtn = E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:14px;', 'click': function() {
                    if (!confirm('Save scheduled tasks and apply?')) return;
                    ui.addNotification('Saving', 'Applying scheduled tasks...', 'info');
                    m.save().then(function() {
                        return uci.apply(10);
                    }).then(function() {
                        return self.callSystemCommand('/bin/sh', ['-c', '/etc/init.d/quickactions-taskplan start']).catch(function(){ return {}; });
                    }).then(function() {
                        ui.addNotification('Saved', 'Scheduled tasks applied.', 'info');
                        self.switchTab('taskplan');
                    }).catch(function(err) {
                        ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
                    });
                } }, 'Save & Apply Scheduled Tasks');
                return E('div', {}, [formNode, saveBtn]);
            });
        });
    },

    renderTaskPlanStartup: function() {
        var self = this;
        return uci.load('taskplan').then(function() {
            var m = new form.Map('taskplan', _('Startup Tasks'),
                _('Tasks to run after boot, with a delay in seconds.'));

            var s = m.section(form.TypedSection, 'global');
            s.anonymous = true;
            var e = s.option(form.TextValue, 'customscript', _('Edit Custom Script')); e.rows = 5; e.optional = false;
            e = s.option(form.TextValue, 'customscript2', _('Edit Custom Script2')); e.rows = 5; e.optional = false;

            var ls = m.section(form.TypedSection, 'ltime', '');
            ls.addremove = true; ls.anonymous = true; ls.sortable = true; ls.template = 'cbi/tblsection';
            var remarks = ls.option(form.Value, 'remarks', _('Remarks')); remarks.optional = false;
            var enable = ls.option(form.Flag, 'enable', _('Enable')); enable.rmempty = false; enable.default = 1;
            var stype = ls.option(form.ListValue, 'stype', _('Startup Type'));
            stype.value(1, _('Scheduled Reboot'));
            stype.value(2, _('Scheduled Poweroff'));
            stype.value(3, _('Scheduled ReNetwork'));
            stype.value(4, _('Scheduled RestartSamba'));
            stype.value(5, _('Scheduled Restartwan'));
            stype.value(6, _('Scheduled Closewan'));
            stype.value(7, _('Scheduled Clearmem'));
            stype.value(8, _('Scheduled Sysfree'));
            stype.value(9, _('Scheduled DisReconn'));
            stype.value(10, _('Scheduled DisRereboot'));
            stype.value(11, _('Scheduled Restartmwan3'));
            stype.value(13, _('Scheduled Wifiup'));
            stype.value(14, _('Scheduled Wifidown'));
            stype.value(12, _('Scheduled Customscript'));
            stype.value(15, _('Scheduled Customscript2'));
            stype.default = 12;
            var delay = ls.option(form.Value, 'delay', _('Delayed Start(seconds)')); delay.datatype = 'uinteger'; delay.default = 10; delay.optional = false;

            // Note: apply_on_parse intentionally NOT set — the Save & Apply button
            // below is the sole writer.
            return m.render().then(function(formNode) {
                var saveBtn = E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:14px;', 'click': function() {
                    if (!confirm('Save startup tasks and apply?')) return;
                    ui.addNotification('Saving', 'Applying startup tasks...', 'info');
                    m.save().then(function() {
                        return uci.apply(10);
                    }).then(function() {
                        return self.callSystemCommand('/bin/sh', ['-c', '/etc/init.d/quickactions-taskplan start']).catch(function(){ return {}; });
                    }).then(function() {
                        ui.addNotification('Saved', 'Startup tasks applied.', 'info');
                        self.switchTab('taskplan');
                    }).catch(function(err) {
                        ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
                    });
                } }, 'Save & Apply Startup Tasks');
                return E('div', {}, [formNode, saveBtn]);
            });
        });
    },

    renderTaskPlanLog: function() {
        var self = this;
        var logPath = '/etc/quickactions-taskplan/taskplan.log';
        var logArea = E('textarea', {
            'id': 'qa-tp-log',
            'readonly': 'readonly',
            'wrap': 'off',
            'style': 'width:100%;height:500px;font-family:monospace;font-size:12px;padding:10px;border-radius:4px;background:#1e1e1e;color:#00ff00;box-sizing:border-box;'
        });
        var reversed = false;

        function refreshLog() {
            return fs.read(logPath).catch(function() { return ''; }).then(function(content) {
                if (reversed) content = content.split('\n').reverse().join('\n');
                logArea.value = content;
                if (!reversed) logArea.scrollTop = logArea.scrollHeight;
            });
        }

        if (self._tpLogTimeout)  { clearTimeout(self._tpLogTimeout);  self._tpLogTimeout = null; }
        if (self._tpLogInterval) { clearInterval(self._tpLogInterval); self._tpLogInterval = null; }
        self._tpLogTimeout = setTimeout(function() {
            refreshLog();
            self._tpLogInterval = setInterval(function() {
                if (!document.getElementById('qa-tp-log')) {
                    if (self._tpLogInterval) { clearInterval(self._tpLogInterval); self._tpLogInterval = null; }
                    return;
                }
                refreshLog();
            }, 5000);
        }, 100);

        var btnClear = E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': function() {
            if (!confirm('Clear the task plan log?')) return;
            fs.write(logPath, '').then(function() { ui.addNotification('Cleared', 'Log cleared.', 'info'); refreshLog(); }).catch(function(e) { ui.addNotification('Error', e.message, 'danger'); });
        } }, _('Clear Log'));
        var btnReverse = E('button', { 'class': 'btn cbi-button cbi-button-edit', 'click': function() { reversed = !reversed; refreshLog(); } }, _('Reverse Order'));
        var btnDownload = E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() {
            fs.read(logPath).then(function(c) {
                if (!c) { ui.addNotification('Empty', 'Log is empty.', 'info'); return; }
                var blob = new Blob([c], { type: 'text/plain' });
                var a = document.createElement('a');
                a.href = URL.createObjectURL(blob);
                a.download = 'quickactions-taskplan.log';
                a.click();
            });
        } }, _('Download Log'));

        return E('div', {}, [
            E('div', { 'style': 'margin-bottom:10px;display:flex;gap:8px;flex-wrap:wrap;' }, [btnClear, btnReverse, btnDownload]),
            logArea
        ]);
    },

    renderTaskPlan: function() {
        var self = this;
        var current = 'scheduled';
        var subButtons = {};

        var subBar = E('div', { 'style': 'display:flex;gap:4px;border-bottom:2px solid rgba(0,0,0,0.08);margin:0 0 16px 0;' });
        var content = E('div');

        function showSub(id) {
            current = id;
            Object.keys(subButtons).forEach(function(k) {
                var b = subButtons[k];
                if (k === id) { b.style.borderBottomColor = '#1e90ff'; b.style.color = '#1e90ff'; b.style.fontWeight = 'bold'; }
                else { b.style.borderBottomColor = 'transparent'; b.style.color = '#666'; b.style.fontWeight = '500'; }
            });
            content.innerHTML = '';
            content.appendChild(E('p', { 'style': 'color:#888;padding:20px;' }, 'Loading ' + id + '...'));
            Promise.resolve().then(function() {
                if (id === 'scheduled') return self.renderTaskPlanScheduled();
                if (id === 'startup') return self.renderTaskPlanStartup();
                if (id === 'log') return self.renderTaskPlanLog();
            }).then(function(node) {
                content.innerHTML = '';
                content.appendChild(node);
            }).catch(function(err) {
                content.innerHTML = '';
                content.appendChild(E('div', { 'class': 'alert-message error' }, 'Task Plan error: ' + (err && err.message ? err.message : String(err))));
            });
        }

        [ { id: 'scheduled', label: _('Scheduled Tasks') },
          { id: 'startup', label: _('Startup Tasks') },
          { id: 'log', label: _('Log Viewer') } ].forEach(function(t) {
            var b = E('div', { 'style': 'padding:8px 18px;cursor:pointer;border-bottom:3px solid transparent;color:#666;font-weight:500;font-size:0.9em;user-select:none;', 'click': function() { showSub(t.id); } }, t.label);
            subButtons[t.id] = b;
            subBar.appendChild(b);
        });

        setTimeout(function() { showSub('scheduled'); }, 0);
        return E('div', {}, [subBar, content]);
    },

    nsFormSave: function(changes) {
        // Changes is a flat list of [config, section, option, value]
        var self = this;
        return self.callSystemCommand('/usr/libexec/quickactions-netwizard/backup.sh', [])
            .catch(function(){ return {}; })
            .then(function() {
                return uci.load('network').catch(function(){});
            })
            .then(function() { return uci.load('firewall').catch(function(){}); })
            .then(function() { return uci.load('dhcp').catch(function(){}); })
            .then(function() { return uci.load('wireless').catch(function(){}); })
            .then(function() { return uci.load('wizard').catch(function(){}); })
            .then(function() { return uci.load('netwizard').catch(function(){}); })
            .then(function() {
                changes.forEach(function(c) {
                    try { uci.set(c[0], c[1], c[2], c[3]); } catch(e) {}
                });
                return uci.save();
            });
    },

    nsShow: function(id) {
        var self = this;
        this.nsCurrent = id;
        var btns = document.querySelectorAll('.qa-ns-sub');
        for (var i = 0; i < btns.length; i++) {
            var b = btns[i];
            var bid = b.getAttribute('data-ns');
            if (bid === id) { b.style.borderBottomColor = '#1e90ff'; b.style.color = '#1e90ff'; b.style.fontWeight = 'bold'; }
            else { b.style.borderBottomColor = 'transparent'; b.style.color = '#666'; b.style.fontWeight = '500'; }
        }
        this.nsContent.innerHTML = '';
        this.nsContent.appendChild(E('p', { 'style': 'color:#888;padding:20px;' }, 'Loading ' + id + '...'));
        var builder = { mode: 'renderNsMode', wan: 'renderNsWan', wireless: 'renderNsWireless',
                        firmware: 'renderNsFirmware', shortcuts: 'renderNsShortcuts', advanced: 'renderNsAdvanced' }[id];
        Promise.resolve(self[builder]()).then(function(node) {
            self.nsContent.innerHTML = '';
            self.nsContent.appendChild(node);
        }).catch(function(err) {
            self.nsContent.innerHTML = '';
            self.nsContent.appendChild(E('div', { 'class': 'alert-message error' }, 'Error: ' + (err && err.message ? err.message : String(err))));
        });
    },

    renderNetworkSetup: function() {
        var self = this;
        // Load all configs this tab touches
        var pkgs = ['network', 'wireless', 'dhcp', 'firewall', 'wizard', 'netwizard', 'uhttpd', 'nginx'];
        var loads = pkgs.map(function(p) { return uci.load(p).catch(function(){ return null; }); });
        return Promise.all(loads).then(function() {
            return self.renderNetworkSetupInner();
        });
    },

    renderNetworkSetupInner: function() {
        var self = this;
        var subs = [
            { id: 'mode', label: 'Mode Selection' },
            { id: 'wan', label: 'WAN Settings' },
            { id: 'wireless', label: 'Wireless' },
            { id: 'firmware', label: 'Firmware' },
            { id: 'shortcuts', label: 'Shortcuts' },
            { id: 'advanced', label: 'Advanced' }
        ];
        var subBar = E('div', { 'style': 'display:flex;gap:4px;border-bottom:2px solid rgba(0,0,0,0.08);margin:0 0 16px 0;flex-wrap:wrap;' });
        subs.forEach(function(t) {
            subBar.appendChild(E('div', {
                'class': 'qa-ns-sub', 'data-ns': t.id,
                'style': 'padding:8px 16px;cursor:pointer;border-bottom:3px solid transparent;color:#666;font-weight:500;font-size:0.9em;user-select:none;',
                'click': function() { self.nsShow(t.id); }
            }, t.label));
        });
        this.nsSubBar = subBar;
        this.nsContent = E('div');

        var intro = E('div', { 'style': 'background:rgba(30,144,255,0.08);border:1px solid rgba(30,144,255,0.2);border-radius:8px;padding:12px;margin-bottom:14px;font-size:0.9em;' }, [
            E('strong', {}, 'Smart mode: '),
            E('span', {}, 'Only fields you change are written. Backup taken before every apply. Aggressive rebuild available in Advanced.')
        ]);

        setTimeout(function() { self.nsShow('mode'); }, 0);
        return E('div', {}, [intro, subBar, this.nsContent]);
    },

    renderNsMode: function() {
        var self = this;
        var currentProto = uci.get('wizard', 'default', 'wan_proto');
        if (!currentProto) {
            // Scan all network interfaces for wan-like protos
            var wanSecs = uci.sections('network', 'interface') || [];
            var hasPppoe = false, hasDhcp = false, hasStatic = false, hasSiderouter = false;
            wanSecs.forEach(function(s) {
                var p = s.proto || '';
                if (p === 'pppoe') hasPppoe = true;
                else if (p === 'dhcp' || p === 'dhcpv6') hasDhcp = true;
                else if (p === 'static' && s.ipaddr && s.gateway) hasSiderouter = true;
            });
            // Detect siderouter: lan has explicit gateway but wan is missing or auto=0
            var lanGw = uci.get('network', 'lan', 'gateway');
            var wanAuto = uci.get('network', 'wan', 'auto');
            if (lanGw && (wanAuto === '0' || !uci.get('network', 'wan'))) {
                currentProto = 'siderouter';
            } else if (hasPppoe) {
                currentProto = 'pppoe';
            } else if (hasDhcp) {
                currentProto = 'dhcp';
            } else if (hasSiderouter) {
                currentProto = 'siderouter';
            } else {
                currentProto = 'dhcp';
            }
        }

        function card(mode, label, desc, color) {
            var active = (currentProto === mode);
            var c = E('div', {
                'style': 'flex:1;min-width:200px;max-width:280px;border:2px solid ' + (active ? color : 'transparent') + ';border-radius:10px;padding:22px 16px;cursor:pointer;text-align:center;background:rgba(0,0,0,' + (active ? '0.08' : '0.02') + ');transition:all 0.2s;',
                'onmouseover': function() { this.style.transform = 'translateY(-2px)'; },
                'onmouseout': function() { this.style.transform = 'translateY(0)'; },
                'click': function() {
                    if (!confirm('Switch mode to "' + label + '"?\n\nFinish configuration in WAN Settings.')) return;
                    uci.load('wizard').then(function() {
                        uci.set('wizard', 'default', 'wan_proto', mode);
                        return uci.save();
                    }).then(function() {
                        ui.addNotification('Mode set', 'Now fill in WAN Settings.', 'info');
                        self.nsShow('wan');
                    }).catch(function(err) {
                        ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
                    });
                }
            }, [
                E('div', { 'style': 'font-size:2.5em;margin-bottom:8px;' }, mode === 'pppoe' ? '🛰️' : (mode === 'dhcp' ? '🔌' : '🔀')),
                E('div', { 'style': 'font-weight:bold;font-size:1.1em;color:' + color + ';margin-bottom:6px;' }, label),
                E('div', { 'style': 'font-size:0.85em;color:#888;line-height:1.4;' }, desc),
                active ? E('div', { 'style': 'margin-top:10px;font-size:0.8em;font-weight:bold;color:' + color + ';' }, '● CURRENT') : ''
            ]);
            return c;
        }

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, 'Select Network Mode'),
            E('p', { 'style': 'color:#888;font-size:0.9em;' }, 'Choose the mode that matches your setup.'),
            E('div', { 'style': 'display:flex;gap:16px;flex-wrap:wrap;margin-top:14px;' }, [
                card('dhcp', 'DHCP Client', 'Default router. WAN gets IP from upstream.', '#339af0'),
                card('pppoe', 'PPPoE Dial-up', 'Fiber/DSL. Requires username & password.', '#ff6b6b'),
                card('siderouter', 'Side-Router', 'Bypass gateway. LAN stays, WAN unused.', '#51cf66')
            ])
        ]);
    },

    renderNsWan: function() {
        var self = this;
        var proto = uci.get('wizard', 'default', 'wan_proto') || uci.get('network', 'wan', 'proto') || 'dhcp';
        var wanIf = uci.get('network', 'wan', 'device') || uci.get('network', 'wan', 'ifname') || 'eth1';
        var setlan = uci.get('wizard', 'default', 'setlan') || '0';

        // Current network values
        var lanIp = getCurrentLanIp();
        var lanMask = uci.get('network', 'lan', 'netmask') || '255.255.255.0';
        var lanGw = uci.get('network', 'lan', 'gateway') || '';
        var lanProto = uci.get('network', 'lan', 'proto') || 'static';
        var lanDns = uci.get('network', 'lan', 'dns');
        var dhcpProto = uci.get('network', 'wan', 'proto') === 'static' ? 'static' : 'dhcp';
        var wanIp = uci.get('network', 'wan', 'ipaddr') || '';
        var wanMask = uci.get('network', 'wan', 'netmask') || '255.255.255.0';
        var wanGw = uci.get('network', 'wan', 'gateway') || '';
        var wanDns = uci.get('network', 'wan', 'dns');
        var pppoeU = uci.get('network', 'wan', 'username') || '';
        var pppoeP = uci.get('network', 'wan', 'password') || '';
        var ipv6On = (uci.get('network', 'wan', 'ipv6') || 'auto') !== '0';
        var lanDhcpOff = uci.get('dhcp', 'lan', 'ignore') === '1';
        var dnsset = uci.get('wizard', 'default', 'dnsset') || '0';
        var dnsTables = uci.get('wizard', 'default', 'dns_tables') || '1';
        var synflood = uci.get('wizard', 'default', 'synflood') || '0';

        function vRow(label, id, val, type, ph) {
            return E('div', { 'style': 'margin-bottom:10px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#888;margin-bottom:4px;' }, label),
                E('input', { 'id': 'ns-wan-' + id, 'type': type || 'text', 'value': val, 'placeholder': ph || '', 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;box-sizing:border-box;' })
            ]);
        }
        function fRow(label, id, val, hint) {
            var cb = E('input', { 'id': 'ns-wan-' + id, 'type': 'checkbox' });
            cb.checked = !!val;
            return E('div', { 'style': 'margin-bottom:10px;display:flex;align-items:center;gap:8px;' }, [
                cb, E('label', { 'style': 'font-size:0.9em;' }, label),
                hint ? E('span', { 'style': 'font-size:0.78em;color:#888;' }, hint) : null
            ]);
        }
        function selRow(label, id, val, options) {
            var s = E('select', { 'id': 'ns-wan-' + id, 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;' });
            options.forEach(function(o) {
                var opt = E('option', { 'value': o[0] }, o[1]);
                if (o[0] === val) opt.selected = true;
                s.appendChild(opt);
            });
            return E('div', { 'style': 'margin-bottom:10px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#888;margin-bottom:4px;' }, label), s
            ]);
        }
        function dnsRow(label, id, val) {
            var v = (Array.isArray(val) ? val.join(', ') : (val || ''));
            return E('div', { 'style': 'margin-bottom:10px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#888;margin-bottom:4px;' }, label),
                E('input', { 'id': 'ns-wan-' + id, 'type': 'text', 'value': v, 'placeholder': '1.1.1.1, 8.8.8.8', 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;' })
            ]);
        }

        // device list
        var netDevs = [];
        try {
            var devices = uci.sections('network', 'device') || [];
            devices.forEach(function(d) { if (d.name && !/^br-|^@/.test(d.name)) netDevs.push(d.name); });
        } catch(e){}
        // fallback
        ['eth0','eth1','eth2','wan'].forEach(function(d) { if (netDevs.indexOf(d) === -1) netDevs.push(d); });

        var rows = [];

        rows.push(selRow('WAN Protocol / Mode', 'proto', proto, [
            ['dhcp', 'DHCP Client'],
            ['pppoe', 'PPPoE Dial-up'],
            ['siderouter', 'Side-Router']
        ]));

        if (proto !== 'siderouter') {
            rows.push(selRow('WAN interface device', 'iface', wanIf, netDevs.map(function(d){ return [d, d]; })));
            rows.push(fRow('Add LAN port configuration (setlan)', 'setlan', setlan === '1'));
        }

        if (proto === 'pppoe') {
            rows.push(vRow('PPPoE Username', 'pppoe_u', pppoeU));
            rows.push(vRow('PPPoE Password', 'pppoe_p', pppoeP, 'password'));
        }

        if (proto === 'dhcp') {
            rows.push(selRow('WAN IP address mode', 'dhcp_proto', dhcpProto, [
                ['dhcp', 'DHCP (automatic)'],
                ['static', 'Static IP']
            ]));
            if (dhcpProto === 'static') {
                rows.push(vRow('WAN IPv4 Address', 'wan_ip', wanIp));
                rows.push(vRow('WAN IPv4 Netmask', 'wan_mask', wanMask));
                rows.push(vRow('WAN IPv4 Gateway', 'wan_gw', wanGw));
            }
        }

        if (proto === 'dhcp' || proto === 'pppoe') {
            rows.push(dnsRow('WAN custom DNS (comma-separated, empty = auto)', 'wan_dns', wanDns));
        }

        if (proto === 'siderouter') {
            rows.push(selRow('LAN IP address mode', 'lan_proto', lanProto, [
                ['static', 'Static IP'],
                ['dhcp', 'DHCP client']
            ]));
        }

        // LAN IP fields
        var showLan = (proto === 'siderouter') || (proto !== 'siderouter' && setlan === '1');
        if (showLan) {
            rows.push(vRow('LAN IPv4 Address', 'lan_ip', lanIp));
            rows.push(selRow('LAN IPv4 Netmask', 'lan_mask', lanMask, [
                ['255.255.255.0', '255.255.255.0 (/24)'],
                ['255.255.0.0', '255.255.0.0 (/16)'],
                ['255.0.0.0', '255.0.0.0 (/8)']
            ]));
            if (proto === 'siderouter') {
                rows.push(vRow('LAN Gateway (upstream router IP)', 'lan_gw', lanGw));
                rows.push(dnsRow('LAN custom DNS (comma-separated)', 'lan_dns', lanDns));
            }
        }

        rows.push(fRow('Enable IPv6', 'ipv6', ipv6On));
        rows.push(fRow('Disable DHCP Server on LAN', 'lan_dhcp_off', lanDhcpOff,
            'Recommended for siderouter mode.'));
        rows.push(fRow('Enable DNS notification to clients', 'dnsset', dnsset === '1'));
        if (dnsset === '1') {
            rows.push(selRow('DNS to push to clients', 'dns_tables', dnsTables, [
                ['1', 'Use router LAN IP (default)'],
                ['223.5.5.5', 'Ali DNS: 223.5.5.5'],
                ['8.8.8.8', 'Google DNS: 8.8.8.8'],
                ['1.1.1.1', 'Cloudflare DNS: 1.1.1.1']
            ]));
        }
        rows.push(fRow('Enable SYN-flood defense', 'synflood', synflood === '1',
            'Adds firewall.syn_flood=1, synflood_protect=1.'));

        var saveBtn = E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:14px;', 'click': function() {
            var changes = [];
            var list = [];

            var get = function(id) { var e = document.getElementById('ns-wan-' + id); return e ? e.value : ''; };
            var getCb = function(id) { var e = document.getElementById('ns-wan-' + id); return e && e.checked; };

            var nProto = get('proto');
            var nIface = get('iface');
            var nSetlan = getCb('setlan') ? '1' : '0';

            // Mode change
            if (nProto !== proto) {
                changes.push(['wizard', 'default', 'wan_proto', nProto]);
                list.push('Mode → ' + nProto);

                // Mode-specific network writes
                if (nProto === 'siderouter') {
                    changes.push(['network', 'wan', 'auto', '0']);
                    changes.push(['firewall', 'lan', 'masq', '1']);
                } else {
                    changes.push(['network', 'wan', 'proto', nProto]);
                    changes.push(['network', 'wan', 'auto', '1']);
                    changes.push(['firewall', 'lan', 'masq', '0']);
                }
            }

            if (nProto !== 'siderouter' && nIface && nIface !== wanIf) {
                changes.push(['network', 'wan', 'device', nIface]);
                list.push('WAN device → ' + nIface);
            }

            if (nSetlan !== setlan) {
                changes.push(['wizard', 'default', 'setlan', nSetlan]);
                list.push('setlan → ' + nSetlan);
            }

            if (nProto === 'pppoe') {
                var nu = get('pppoe_u'), np = get('pppoe_p');
                if (nu !== pppoeU) { changes.push(['network', 'wan', 'username', nu]); list.push('PPPoE username'); }
                if (np !== pppoeP) { changes.push(['network', 'wan', 'password', np]); list.push('PPPoE password'); }
            }

            if (nProto === 'dhcp') {
                var ndp = get('dhcp_proto');
                if (ndp === 'static') {
                    if (get('wan_ip')) { changes.push(['network', 'wan', 'ipaddr', get('wan_ip')]); list.push('WAN IP → ' + get('wan_ip')); }
                    if (get('wan_mask')) { changes.push(['network', 'wan', 'netmask', get('wan_mask')]); list.push('WAN mask'); }
                    if (get('wan_gw')) { changes.push(['network', 'wan', 'gateway', get('wan_gw')]); list.push('WAN GW'); }
                    changes.push(['network', 'wan', 'proto', 'static']);
                }
            }

            if (nProto === 'dhcp' || nProto === 'pppoe') {
                var wdns = get('wan_dns').split(',').map(function(s){ return s.trim(); }).filter(Boolean);
                if (wdns.length) { changes.push(['network', 'wan', 'dns', wdns]); list.push('WAN DNS set'); }
            }

            // LAN fields (recompute showLan from the NEW values, not render-time state)
            var nShowLan = (nProto === 'siderouter') || (nProto !== 'siderouter' && nSetlan === '1');
            if (nShowLan) {
                var nLanIp = get('lan_ip');
                var nLanMask = get('lan_mask');
                if (nLanIp && nLanIp !== lanIp) { changes.push(['network', 'lan', 'ipaddr', nLanIp]); list.push('LAN IP → ' + nLanIp); }
                if (nLanMask && nLanMask !== lanMask) { changes.push(['network', 'lan', 'netmask', nLanMask]); list.push('LAN mask → ' + nLanMask); }
                if (nProto === 'siderouter') {
                    var nGw = get('lan_gw');
                    if (nGw !== lanGw) { changes.push(['network', 'lan', 'gateway', nGw || '']); list.push('LAN GW → ' + (nGw || '(none)')); }
                    var ldns = get('lan_dns').split(',').map(function(s){ return s.trim(); }).filter(Boolean);
                    changes.push(['network', 'lan', 'dns', ldns]);
                    if (ldns.length) list.push('LAN DNS set');

                    var nlp = get('lan_proto');
                    if (nlp !== lanProto) { changes.push(['network', 'lan', 'proto', nlp]); list.push('LAN proto → ' + nlp); }
                }
            }

            var nIpv6 = getCb('ipv6');
            if (nIpv6 !== ipv6On) {
                changes.push(['network', 'wan', 'ipv6', nIpv6 ? 'auto' : '0']);
                list.push('IPv6 → ' + (nIpv6 ? 'on' : 'off'));
            }

            var nDhcpOff = getCb('lan_dhcp_off');
            if (nDhcpOff !== lanDhcpOff) {
                changes.push(['dhcp', 'lan', 'ignore', nDhcpOff ? '1' : '0']);
                list.push('LAN DHCP → ' + (nDhcpOff ? 'off' : 'on'));
            }

            var nDnsset = getCb('dnsset') ? '1' : '0';
            if (nDnsset !== dnsset) {
                changes.push(['wizard', 'default', 'dnsset', nDnsset]);
                list.push('DNS notify → ' + nDnsset);
            }
            if (nDnsset === '1') {
                var ndt = get('dns_tables');
                if (ndt !== dnsTables) { changes.push(['wizard', 'default', 'dns_tables', ndt]); list.push('DNS push → ' + ndt); }
            }

            var nSf = getCb('synflood') ? '1' : '0';
            if (nSf !== synflood) {
                changes.push(['wizard', 'default', 'synflood', nSf]);
                if (nSf === '1') { changes.push(['firewall', '@defaults[0]', 'syn_flood', '1']); changes.push(['firewall', '@defaults[0]', 'synflood_protect', '1']); }
                else { changes.push(['firewall', '@defaults[0]', 'syn_flood', '0']); changes.push(['firewall', '@defaults[0]', 'synflood_protect', '0']); }
                list.push('SYN-flood → ' + nSf);
            }

            if (list.length === 0) { ui.addNotification('No changes', 'Nothing to save.', 'info'); return; }
            if (!confirm('Save WAN changes?\n\n• ' + list.join('\n• ') + '\n\nBackup will be taken first.')) return;

            ui.addNotification('Saving', list.length + ' change(s) applying...', 'info');
            var lanIpChanged = (nShowLan && get('lan_ip') && get('lan_ip') !== lanIp);

            self.nsFormSave(changes).then(function() {
                return self.callSystemCommand('/bin/sh', ['-c',
                    '/etc/init.d/network reload; /etc/init.d/dhcp reload; /etc/init.d/firewall reload'
                ]).catch(function(){ return {}; });
            }).then(function() {
                if (lanIpChanged) {
                    // Redirect modal (matches wizard source)
                    var newIp = get('lan_ip');
                    var sec = 15;
                    var countSpan = E('strong', {}, String(sec));
                    ui.showModal(_('LAN IP Address Changed'), [
                        E('p', {}, ['New LAN IP: ', E('strong', {}, newIp)]),
                        E('p', {}, ['Redirecting in ', countSpan, ' seconds...']),
                        E('div', { 'style': 'margin-top:10px;text-align:right;' }, [
                            E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': function() { window.location.href = window.location.protocol + '//' + newIp + '/cgi-bin/luci/'; } }, 'Redirect Now')
                        ])
                    ]);
                    var timer = setInterval(function() {
                        sec--;
                        countSpan.textContent = String(sec);
                        if (sec <= 0) { clearInterval(timer); window.location.href = window.location.protocol + '//' + newIp + '/cgi-bin/luci/'; }
                    }, 1000);
                } else {
                    ui.addNotification('Saved', 'Network settings updated.', 'info');
                    self.nsShow('wan');
                }
            }).catch(function(err) {
                ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
            });
        } }, _('Save WAN Settings (smart diff)'));

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, 'WAN Settings — ' + proto),
            E('div', { 'style': 'background:rgba(0,0,0,0.03);border-radius:6px;padding:10px;margin-bottom:14px;font-size:0.85em;' }, [
                E('div', {}, ['Current mode: ', E('strong', {}, proto)]),
                E('div', {}, ['WAN device: ', E('code', {}, wanIf)]),
                E('div', {}, ['LAN IP: ', E('code', {}, lanIp + '/' + lanMask)])
            ]),
            E('div', {}, rows),
            saveBtn
        ]);
    },

    renderNsWireless: function() {
        var self = this;
        var devices = uci.sections('wireless', 'wifi-device') || [];
        if (devices.length === 0) return E('div', { 'class': 'alert-message warning' }, 'No wireless devices detected.');

        var ifaces = uci.sections('wireless', 'wifi-iface') || [];
        var apIfaces = ifaces.filter(function(i){ return i.mode === 'ap' || !i.mode; });
        if (apIfaces.length === 0) return E('div', { 'class': 'alert-message warning' }, 'No AP wireless interfaces found.');

        // Get base SSID (strip band suffix from first AP)
        var rawSsid = apIfaces[0].ssid || '';
        var baseSsid = rawSsid.replace(/_(2\.4G|5G|6G)$/i, '').trim();
        var key = apIfaces[0].key || '';
        var enc = apIfaces[0].encryption || 'psk2';

        var ssidIn = E('input', { 'id': 'ns-wl-ssid', 'type': 'text', 'value': baseSsid, 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
        var keyIn = E('input', { 'id': 'ns-wl-key', 'type': 'password', 'value': key, 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
        var encSel = E('select', { 'id': 'ns-wl-enc', 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
        [['psk2','WPA2-PSK'],['sae','WPA3-SAE'],['sae-mixed','WPA2/WPA3 Mixed'],['psk','WPA-PSK'],['none','Open']].forEach(function(o) {
            var opt = E('option', { 'value': o[0] }, o[1]);
            if (o[0] === enc) opt.selected = true;
            encSel.appendChild(opt);
        });

        var bandInfo = apIfaces.map(function(i) {
            var dev = devices.filter(function(d){ return d['.name'] === i.device; })[0];
            var band = '2.4G';
            if (dev) {
                if (dev.band === '5g') band = '5G';
                else if (dev.band === '6g') band = '6G';
                else if (/^11a/.test(dev.hwmode || '') && !/^11ax/.test(dev.hwmode || '')) band = '5G';
            }
            return { iface: i['.name'], device: i.device, band: band };
        });

        // Detect if APs currently have DIFFERENT passwords — saving would squash them all
        var distinctKeys = {};
        apIfaces.forEach(function(i) { if (i.key) distinctKeys[i.key] = true; });
        var keysDiffer = Object.keys(distinctKeys).length > 1;

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, 'Wireless Settings'),
            E('p', { 'style': 'color:#888;font-size:0.9em;' }, 'Base SSID will auto-append _2.4G, _5G, _6G per radio.'),
            E('div', { 'style': 'margin-bottom:12px;font-size:0.85em;' }, bandInfo.map(function(b) {
                return E('div', {}, [b.device + ' (' + b.band + ') → AP: ', E('code', {}, b.iface)]);
            })),
            E('div', { 'style': 'margin-bottom:12px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#888;margin-bottom:4px;' }, 'Base SSID'), ssidIn]),
            E('div', { 'style': 'margin-bottom:12px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#888;margin-bottom:4px;' }, 'Encryption'), encSel]),
            E('div', { 'style': 'margin-bottom:12px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#888;margin-bottom:4px;' }, 'Password'), keyIn]),
            keysDiffer ? E('div', { 'class': 'alert-message warning', 'style': 'margin-bottom:12px;' },
                _('Your APs currently have different passwords. Saving will overwrite every AP with the password entered above.')) : null,
            E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:8px;', 'click': function() {
                var ns = document.getElementById('ns-wl-ssid').value.trim();
                var nk = document.getElementById('ns-wl-key').value;
                var ne = document.getElementById('ns-wl-enc').value;
                if (!ns) { ui.addNotification('Error', 'SSID required.', 'danger'); return; }
                if (ne !== 'none' && nk && nk.length < 8) { ui.addNotification('Error', 'Password must be ≥ 8 chars.', 'danger'); return; }
                if (keysDiffer && nk && !confirm('WARNING: APs currently have DIFFERENT passwords. Saving will overwrite all of them with the new one.\n\nContinue?')) return;
                if (!confirm('Apply wireless changes? SSID: ' + ns + ', encryption: ' + ne)) return;

                var changes = [];
                bandInfo.forEach(function(b) {
                    var newSsid = ns + '_' + b.band;
                    changes.push(['wireless', b.iface, 'ssid', newSsid]);
                    changes.push(['wireless', b.iface, 'encryption', ne]);
                    if (ne !== 'none' && nk) changes.push(['wireless', b.iface, 'key', nk]);
                    changes.push(['wireless', b.iface, 'disabled', '0']);
                });
                // Also update wizard store
                changes.push(['wizard', 'default', 'wifi_ssid', ns]);
                changes.push(['wizard', 'default', 'wifi_key', nk]);

                self.nsFormSave(changes).then(function() {
                    return self.callSystemCommand('/bin/sh', ['-c', '/sbin/wifi reload']);
                }).then(function() {
                    ui.addNotification('Saved', 'Wireless updated.', 'info');
                    self.nsShow('wireless');
                }).catch(function(err) { ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger'); });
            } }, _('Save Wireless'))
        ]);
    },

    renderNsFirmware: function() {
        var self = this;
        var cur = {
            autoupgrade_fm: uci.get('wizard', 'default', 'autoupgrade_fm') || '1',
            coremark: uci.get('wizard', 'default', 'coremark') || '0',
            cookie_p: uci.get('wizard', 'default', 'persistent_cookies') || '1',
            https: uci.get('wizard', 'default', 'https') || '0',
            landing_page: uci.get('wizard', 'default', 'landing_page') || 'default'
        };
        function fRow(label, id, val, hint) {
            var cb = E('input', { 'id': 'ns-fw-' + id, 'type': 'checkbox' });
            cb.checked = (val === '1');
            return E('div', { 'style': 'margin-bottom:12px;display:flex;align-items:center;gap:8px;' }, [
                cb, E('label', { 'style': 'font-size:0.9em;' }, label),
                hint ? E('span', { 'style': 'font-size:0.78em;color:#888;' }, hint) : null
            ]);
        }
        var landingSel = E('select', { 'id': 'ns-fw-landing', 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
        [['default','Default'],['routerdog','RouterDog'],['nas','NAS'],['next-nas','Next-NAS'],['router','Router']].forEach(function(o) {
            var opt = E('option', { 'value': o[0] }, o[1]);
            if (o[0] === cur.landing_page) opt.selected = true;
            landingSel.appendChild(opt);
        });

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, 'Firmware & System Settings'),
            fRow('Firmware upgrade notices', 'autoupgrade', cur.autoupgrade_fm),
            fRow('Run CoreMark on boot', 'coremark', cur.coremark, 'Runs once into /etc/bench.log.'),
            fRow('Persistent login cookies', 'cookie', cur.cookie_p),
            fRow('Enforce HTTPS redirect', 'https', cur.https, 'Requires uhttpd SSL or nginx.'),
            E('div', { 'style': 'margin-bottom:12px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#888;margin-bottom:4px;' }, 'Landing page'), landingSel
            ]),
            E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:8px;', 'click': function() {
                var changes = [];
                var list = [];
                var na = document.getElementById('ns-fw-autoupgrade').checked ? '1' : '0';
                var nc = document.getElementById('ns-fw-coremark').checked ? '1' : '0';
                var np = document.getElementById('ns-fw-cookie').checked ? '1' : '0';
                var nh = document.getElementById('ns-fw-https').checked ? '1' : '0';
                var nl = document.getElementById('ns-fw-landing').value;
                if (na !== cur.autoupgrade_fm) { changes.push(['wizard', 'default', 'autoupgrade_fm', na]); list.push('upgrade notices → ' + na); }
                if (nc !== cur.coremark) { changes.push(['wizard', 'default', 'coremark', nc]); list.push('coremark → ' + nc); }
                if (np !== cur.cookie_p) { changes.push(['wizard', 'default', 'persistent_cookies', np]); list.push('cookies → ' + np); }
                if (nh !== cur.https) { changes.push(['wizard', 'default', 'https', nh]); list.push('https → ' + nh); }
                if (nl !== cur.landing_page) { changes.push(['wizard', 'default', 'landing_page', nl]); list.push('landing → ' + nl); }
                if (list.length === 0) { ui.addNotification('No changes', 'Nothing to save.', 'info'); return; }
                if (!confirm('Save firmware settings?\n\n• ' + list.join('\n• '))) return;
                self.nsFormSave(changes).then(function() {
                    // Re-run init to pick up cookie/https changes
                    return self.callSystemCommand('/bin/sh', ['-c', '/etc/init.d/quickactions-netwizard restart']).catch(function(){ return {}; });
                }).then(function() {
                    ui.addNotification('Saved', 'Firmware settings updated.', 'info');
                }).catch(function(err) { ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger'); });
            } }, _('Save Firmware Settings'))
        ]);
    },

    renderNsShortcuts: function() {
        var self = this;
        return fs.stat('/etc/config/nginx').then(function() {
            return uci.load('wizard').catch(function(){}).then(function() {
                var secs = uci.sections('wizard', 'shortcuts') || [];
                var grid = E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:10px;margin-top:12px;' });
                secs.forEach(function(s) {
                    var sid = s['.name'];
                    var label = s.shortcut || sid;
                    var url = s.to_url || '';
                    grid.appendChild(E('div', { 'style': 'background:rgba(0,0,0,0.03);border-radius:6px;padding:12px;' }, [
                        E('div', { 'style': 'font-weight:bold;margin-bottom:4px;' }, label + '/'),
                        E('div', { 'style': 'font-size:0.85em;color:#888;word-break:break-all;margin-bottom:8px;' }, url),
                        E('button', { 'class': 'btn cbi-button', 'style': 'padding:2px 10px;font-size:0.85em;', 'click': function() {
                            if (!confirm('Delete shortcut "' + label + '"?')) return;
                            uci.load('wizard').then(function() { uci.remove('wizard', sid); return uci.save(); })
                                .then(function() { return self.callSystemCommand('/usr/libexec/quickactions-netwizard/apply-shortcuts.sh', []).catch(function(){ return {}; }); })
                                .then(function() { ui.addNotification('Deleted', label, 'info'); self.nsShow('shortcuts'); });
                        } }, 'Delete')
                    ]));
                });
                if (secs.length === 0) grid.appendChild(E('p', { 'style': 'color:#888;' }, 'No shortcuts yet.'));

                var scIn = E('input', { 'id': 'ns-sc-key', 'placeholder': 'g', 'style': 'padding:6px 10px;border:1px solid #ccc;border-radius:4px;width:120px;' });
                var urlIn = E('input', { 'id': 'ns-sc-url', 'placeholder': 'https://google.com', 'style': 'padding:6px 10px;border:1px solid #ccc;border-radius:4px;width:280px;' });

                return E('div', {}, [
                    E('h3', { 'style': 'margin-top:0;' }, 'Shortcuts (nginx + dnsmasq)'),
                    E('p', { 'style': 'color:#888;font-size:0.9em;' }, 'Type shortcut + "/" in any browser on this network → redirects.'),
                    grid,
                    E('div', { 'style': 'margin-top:14px;display:flex;gap:10px;align-items:center;flex-wrap:wrap;' }, [
                        scIn, E('span', {}, '→'), urlIn,
                        E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': function() {
                            var k = document.getElementById('ns-sc-key').value.trim();
                            var u = document.getElementById('ns-sc-url').value.trim();
                            if (!k || !/^[a-zA-Z0-9_-]+$/.test(k)) { ui.addNotification('Error', 'Shortcut must be alphanumeric.', 'danger'); return; }
                            if (!u || !/^https?:\/\//i.test(u)) { ui.addNotification('Error', 'URL must start with http(s)://', 'danger'); return; }
                            uci.load('wizard').then(function() {
                                var sid = 'sc_' + k + '_' + Date.now();
                                uci.add('wizard', 'shortcuts', sid);
                                uci.set('wizard', sid, 'shortcut', k);
                                uci.set('wizard', sid, 'to_url', u);
                                return uci.save();
                            }).then(function() {
                                return self.callSystemCommand('/usr/libexec/quickactions-netwizard/apply-shortcuts.sh', []).catch(function(){ return {}; });
                            }).then(function() {
                                ui.addNotification('Added', k + ' → ' + u, 'info');
                                self.nsShow('shortcuts');
                            }).catch(function(err) { ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger'); });
                        } }, 'Add')
                    ])
                ]);
            });
        }).catch(function() {
            return E('div', { 'class': 'alert-message notice' }, 'Shortcuts require nginx. Install nginx package to enable.');
        });
    },

    renderNsAdvanced: function() {
        var self = this;
        var aggressiveMode = false;

        var backupBtn = E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': function() {
            ui.addNotification('Backing up', 'Creating backup...', 'info');
            self.callSystemCommand('/usr/libexec/quickactions-netwizard/backup.sh', []).then(function(r) {
                var out = (r.stdout || '') + (r.stderr ? '\n' + r.stderr : '');
                ui.addNotification('Backup complete', E('pre', { 'style': 'text-align:left;white-space:pre-wrap;background:#1e1e1e;color:#00ff00;padding:10px;border-radius:4px;font-size:0.85em;' }, out), 'info');
            }).catch(function(err) { ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger'); });
        } }, 'Backup Now');

        var listBtn = E('button', { 'class': 'btn cbi-button', 'click': function() {
            self.callSystemCommand('/usr/libexec/quickactions-netwizard/list-backups.sh', []).then(function(r) {
                var out = (r.stdout || '(none)').trim();
                var ul = E('div', { 'style': 'margin-top:10px;' });
                if (!out) ul.appendChild(E('div', { 'style': 'color:#888;' }, 'No backups yet.'));
                out.split('\n').forEach(function(line) {
                    if (!line.trim()) return;
                    ul.appendChild(E('div', { 'style': 'display:flex;gap:10px;align-items:center;padding:6px;border-bottom:1px solid rgba(0,0,0,0.06);' }, [
                        E('code', { 'style': 'flex:1;font-size:0.85em;' }, line),
                        E('button', { 'class': 'btn cbi-button cbi-button-action', 'style': 'padding:2px 10px;font-size:0.85em;', 'click': function() {
                            if (!confirm('Restore from ' + line + '?\n\nCurrent config will be saved as pre-restore backup first.')) return;
                            self.callSystemCommand('/usr/libexec/quickactions-netwizard/restore.sh', [line]).then(function(rr) {
                                ui.addNotification('Restored', E('pre', { 'style': 'text-align:left;white-space:pre-wrap;' }, (rr.stdout || '') + (rr.stderr ? '\n' + rr.stderr : '')), 'info');
                            });
                        } }, 'Restore')
                    ]));
                });
                ui.addNotification('Backups', ul, 'info');
            });
        } }, 'List Backups');

        var aggressiveSection = E('div', { 'style': 'margin-top:20px;padding:14px;border:1px solid rgba(220,53,69,0.4);border-radius:8px;background:rgba(220,53,69,0.06);' }, [
            E('h4', { 'style': 'margin:0 0 8px 0;color:#dc3545;' }, '⚠️ Aggressive Mode (opt-in)'),
            E('p', { 'style': 'font-size:0.9em;margin:0 0 12px 0;' }, 'Matches the original wizard: DELETES and RECREATES WAN, wan6, lan6, and the WAN firewall zone. Custom WAN routes / WAN firewall rules / WAN forwarding rules will be lost. A backup is taken automatically.'),
            E('label', { 'style': 'display:flex;align-items:center;gap:8px;cursor:pointer;' }, [
                E('input', { 'type': 'checkbox', 'id': 'ns-adv-agg', 'change': function() { aggressiveMode = this.checked; } }),
                E('strong', {}, 'I understand — rebuild my network config from scratch')
            ]),
            E('button', { 'class': 'btn cbi-button cbi-button-action important', 'style': 'margin-top:12px;background-color:#dc3545;', 'click': function() {
                if (!aggressiveMode) { ui.addNotification('Error', 'Check the box above first.', 'danger'); return; }
                var proto = uci.get('wizard', 'default', 'wan_proto') || 'dhcp';
                var lanIp = getCurrentLanIp();
                var pu = uci.get('network', 'wan', 'username') || '';
                var pp = uci.get('network', 'wan', 'password') || '';
                if (!confirm('AGGRESSIVE REBUILD\n\nMode: ' + proto + '\nLAN: ' + lanIp + '\nPPPoE user: ' + (pu || '(none)') + '\n\nBackup first. Proceed?')) return;
                ui.addNotification('Running', 'Aggressive apply in progress...', 'info');
                self.callSystemCommand('/usr/libexec/quickactions-netwizard/apply-aggressive.sh', [proto, lanIp, pu, pp]).then(function(r) {
                    var out = (r.stdout || '') + (r.stderr ? '\n' + r.stderr : '');
                    ui.addNotification('Complete', E('pre', { 'style': 'text-align:left;white-space:pre-wrap;background:#1e1e1e;color:#00ff00;padding:10px;border-radius:4px;font-size:0.85em;' }, out), 'info');
                }).catch(function(err) {
                    ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
                });
            } }, 'Apply Aggressive Rebuild')
        ]);

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, 'Advanced'),
            E('p', { 'style': 'color:#888;font-size:0.9em;' }, 'Backups, restore, opt-in aggressive rebuild.'),
            E('div', { 'style': 'display:flex;gap:10px;flex-wrap:wrap;' }, [backupBtn, listBtn]),
            aggressiveSection
        ]);
    },

    renderScripts: function() {
        var self = this;

        var rpcList = rpc.declare({
            object: 'luci.quickactions-scripts', method: 'list', expect: { '': {} }
        });
        var rpcRead = rpc.declare({
            object: 'luci.quickactions-scripts', method: 'read',
            params: ['sid'], expect: { '': {} }
        });
        var rpcWrite = rpc.declare({
            object: 'luci.quickactions-scripts', method: 'write',
            params: ['sid','name','category','content','args','timeout','enabled'], expect: { '': {} }
        });
        var rpcDelete = rpc.declare({
            object: 'luci.quickactions-scripts', method: 'delete',
            params: ['sid'], expect: { '': {} }
        });
        var rpcRun = rpc.declare({
            object: 'luci.quickactions-scripts', method: 'run',
            params: ['sid'], expect: { '': {} }
        });
        var rpcChmod = rpc.declare({
            object: 'luci.quickactions-scripts', method: 'chmod',
            params: ['sid','mode'], expect: { '': {} }
        });
        var rpcPreset = rpc.declare({
            object: 'luci.quickactions-scripts', method: 'install_preset',
            params: ['preset'], expect: { '': {} }
        });
        var rpcDetail = rpc.declare({
            object: 'luci.quickactions-scripts', method: 'detail',
            params: ['sid'], expect: { '': {} }
        });

        function catIcon(c) {
            return ({ 'failover': '🔁', 'network': '🌐', 'system': '⚙️',
                      'iot': '📡', 'custom': '📜' })[c] || '📜';
        }

        // ---- Table ----
        var tableWrap = E('div', { 'id': 'qa-scripts-table', 'style': 'overflow-x:auto;' });

        function refreshTable() {
            tableWrap.innerHTML = '';
            tableWrap.appendChild(E('p', { 'style': 'color:#888;padding:20px;' }, _('Loading scripts...')));
            rpcList().then(function(r) {
                var scripts = (r && r.scripts) || [];
                tableWrap.innerHTML = '';

                var addBar = E('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px;' }, [
                    E('button', { 'class': 'btn cbi-button cbi-button-action important',
                        'click': function() { openEditor(null); } }, _('+ Create new script')),
                    E('button', { 'class': 'btn cbi-button',
                        'click': function() {
                            if (!confirm(_('Install Failover-lite preset? Adds an editable MWAN3-substitute script.'))) return;
                            rpcPreset('failover').then(function(res) {
                                ui.addNotification(null, E('p', {}, _('Preset installed: ') + (res.sid || '')), 'info');
                                refreshTable();
                            }).catch(function(err) {
                                ui.addNotification(null, E('p', {}, 'Failed: ' + (err.message || err)), 'danger');
                            });
                        } }, _('Install Failover-lite preset')),
                    E('button', { 'class': 'btn cbi-button',
                        'click': function() {
                            ui.showModal(_('Scripts — help'), [
                                E('div', { 'style': 'line-height:1.6;font-size:0.92em;max-width:640px;' }, [
                                    E('p', {}, _('Scripts live in /etc/quickactions/scripts/. Each script is a normal shell file.')),
                                    E('ul', {}, [
                                        E('li', {}, _('Name — display name.')),
                                        E('li', {}, _('Category — failover / network / system / iot / custom (icon only).')),
                                        E('li', {}, _('Timeout — seconds before the script is force-killed.')),
                                        E('li', {}, _('Arguments — passed as $1 $2 on Run.')),
                                        E('li', {}, _('Script body — the actual shell script.'))
                                    ]),
                                    E('p', {}, _('Use "Install Failover-lite preset" for an MWAN3 substitute on low-RAM routers.')),
                                    E('p', { 'style': 'color:#c00;' }, _('Scripts execute as root. Only run scripts you trust.'))
                                ]),
                                E('div', { 'style': 'margin-top:14px;text-align:right;' }, [
                                    E('button', { 'class': 'btn cbi-button cbi-button-action',
                                        'click': function() {
                                            document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                                if (m.parentNode) m.parentNode.removeChild(m);
                                            });
                                            document.body.classList.remove('modal-overlay-active');
                                        } }, _('Close'))
                                ])
                            ]);
                        } }, _('❔ Help'))
                ]);
                tableWrap.appendChild(addBar);

                if (!scripts.length) {
                    tableWrap.appendChild(E('p', { 'style': 'color:#888;padding:14px;' },
                        _('No scripts yet.')));
                    return;
                }

                var table = E('table', { 'style': 'width:100%;border-collapse:collapse;font-size:0.9em;' });
                table.appendChild(E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' }, [
                    E('th', { 'style': 'padding:8px;' }, _('Name')),
                    E('th', { 'style': 'padding:8px;' }, _('Category')),
                    E('th', { 'style': 'padding:8px;text-align:center;' }, _('Enabled')),
                    E('th', { 'style': 'padding:8px;text-align:right;' }, _('Size')),
                    E('th', { 'style': 'padding:8px;text-align:right;' }, _('Actions'))
                ]));

                scripts.forEach(function(s) {
                    var sid = s.sid;
                    var en = String(s.enabled) === '1';
                    var toggle = E('input', { 'type': 'checkbox' });
                    if (en) toggle.checked = true;
                    toggle.addEventListener('change', function(ev) {
                        uci.load('quickactions').then(function() {
                            uci.set('quickactions', sid, 'enabled', ev.target.checked ? '1' : '0');
                            return uci.save();
                        }).then(function() {
                            ui.addNotification(null, E('p', {}, _('Saved to memory.')), 'info');
                            self.refreshPendingCount();
                        });
                    });

                    var row = E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.06);' }, [
                        E('td', { 'style': 'padding:8px;' }, [
                            E('strong', {}, catIcon(s.category || 'custom') + ' ' + (s.name || sid)),
                            E('br'),
                            E('code', { 'style': 'font-size:0.78em;color:#888;word-break:break-all;' },
                              s.path || ('/etc/quickactions/scripts/' + sid + '.sh'))
                        ]),
                        E('td', { 'style': 'padding:8px;font-size:0.9em;' }, s.category || 'custom'),
                        E('td', { 'style': 'padding:8px;text-align:center;' }, toggle),
                        E('td', { 'style': 'padding:8px;text-align:right;font-size:0.85em;color:#888;' },
                          (s.size || 0) + ' B'),
                        E('td', { 'style': 'padding:8px;text-align:right;' }, [
                            E('button', { 'class': 'btn cbi-button',
                                'style': 'padding:2px 10px;font-size:0.85em;margin-right:4px;',
                                'click': function() { openDetail(sid); } }, _('Info')),
                            E('button', { 'class': 'btn cbi-button',
                                'style': 'padding:2px 10px;font-size:0.85em;margin-right:4px;',
                                'click': function() { openEditor(sid); } }, _('Edit')),
                            E('button', { 'class': 'btn cbi-button cbi-button-action',
                                'style': 'padding:2px 10px;font-size:0.85em;margin-right:4px;',
                                'click': function() { runScript(sid, s.name); } }, _('Run')),
                            E('button', { 'class': 'btn cbi-button cbi-button-negative',
                                'style': 'padding:2px 10px;font-size:0.85em;',
                                'click': function() { deleteScript(sid, s.name); } }, _('Delete'))
                        ])
                    ]);
                    table.appendChild(row);
                });

                tableWrap.appendChild(table);
            }).catch(function(err) {
                tableWrap.innerHTML = '';
                tableWrap.appendChild(E('div', { 'class': 'alert-message error',
                    'style': 'padding:12px;' }, 'List failed: ' + (err.message || err)));
            });
        }

        // ---- Editor modal ----
        function openEditor(sid) {
            var isNew = !sid;

            function build(fields) {
                var inputs = {
                    name: E('input', { 'type': 'text', 'value': fields.name || '',
                        'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' }),
                    category: (function() {
                        var s = E('select', { 'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
                        [['failover','Failover'],['network','Network'],['system','System'],
                         ['iot','IoT'],['custom','Custom']].forEach(function(c) {
                            var o = E('option', { 'value': c[0] }, c[1]);
                            if (c[0] === (fields.category || 'custom')) o.selected = true;
                            s.appendChild(o);
                        });
                        return s;
                    })(),
                    timeout: E('input', { 'type': 'text', 'value': fields.timeout || '60',
                        'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' }),
                    args: E('input', { 'type': 'text', 'value': fields.args || '',
                        'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' }),
                    content: E('textarea', { 'spellcheck': 'false',
                        'style': 'width:100%;min-height:320px;font-family:monospace;font-size:0.9em;padding:8px;' },
                        fields.content || '#!/bin/sh\n\n# Write your script here\n')
                };

                var body = E('div', {}, [
                    E('div', { 'style': 'margin-bottom:10px;' }, [
                        E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Name *')),
                        inputs.name
                    ]),
                    E('div', { 'style': 'display:flex;gap:12px;margin-bottom:10px;flex-wrap:wrap;' }, [
                        E('div', { 'style': 'flex:1 1 200px;' }, [
                            E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Category')),
                            inputs.category
                        ]),
                        E('div', { 'style': 'flex:1 1 200px;' }, [
                            E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Timeout (s)')),
                            inputs.timeout
                        ])
                    ]),
                    E('div', { 'style': 'margin-bottom:10px;' }, [
                        E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Arguments (space-separated)')),
                        inputs.args
                    ]),
                    E('div', { 'style': 'margin-bottom:10px;' }, [
                        E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Script body *')),
                        inputs.content
                    ])
                ]);

                var saveBtn = E('button', {
                    'class': 'btn cbi-button',
                    'style': 'background-color:#28a745 !important;background:#28a745 !important;color:#fff !important;padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;'
                }, _('Save'));
                saveBtn.addEventListener('click', function() {
                    var n = inputs.name.value.trim();
                    var c = inputs.content.value;
                    if (!n) { ui.addNotification(null, E('p', {}, 'Name required'), 'danger'); return; }
                    if (!c) { ui.addNotification(null, E('p', {}, 'Script body required'), 'danger'); return; }
                    var payload = {
                        sid: sid || '',
                        name: n,
                        category: inputs.category.value,
                        content: c,
                        args: inputs.args.value,
                        timeout: inputs.timeout.value || '60',
                        enabled: '1'
                    };
                    rpcWrite(
                        payload.sid, payload.name, payload.category, payload.content,
                        payload.args, payload.timeout, payload.enabled
                    ).then(function(res) {
                        ui.addNotification(null, E('p', {}, _('Saved')), 'info');
                        document.querySelectorAll('.modal-overlay').forEach(function(m) {
                            if (m.parentNode) m.parentNode.removeChild(m);
                        });
                        document.body.classList.remove('modal-overlay-active');
                        uci.load('quickactions').then(function() {
                            self.refreshPendingCount();
                            refreshTable();
                        });
                    }).catch(function(err) {
                        ui.addNotification(null, E('p', {}, 'Save failed: ' + (err.message || err)), 'danger');
                    });
                });
                var cancelBtn = E('button', { 'class': 'btn cbi-button',
                    'style': 'margin-right:8px;',
                    'click': function() {
                        document.querySelectorAll('.modal-overlay').forEach(function(m) {
                            if (m.parentNode) m.parentNode.removeChild(m);
                        });
                        document.body.classList.remove('modal-overlay-active');
                    }
                }, _('Cancel'));

                ui.showModal(_(isNew ? 'Create script' : ('Edit: ' + (fields.name || sid))), [
                    body,
                    E('div', { 'style': 'margin-top:14px;text-align:right;' }, [cancelBtn, saveBtn])
                ]);
            }

            if (isNew) {
                build({});
            } else {
                rpcRead(sid).then(function(r) {
                    return rpcDetail(sid).then(function(d) {
                        build({
                            name: d.name || sid,
                            category: d.category || 'custom',
                            timeout: d.timeout || '60',
                            args: d.args || '',
                            content: r.content || ''
                        });
                    });
                }).catch(function(err) {
                    ui.addNotification(null, E('p', {}, 'Load failed: ' + (err.message || err)), 'danger');
                });
            }
        }

        function openDetail(sid) {
            rpcDetail(sid).then(function(d) {
                ui.showModal(_('Script detail: ' + (d.name || sid)), [
                    E('div', { 'style': 'line-height:1.7;font-size:0.92em;' }, [
                        E('div', {}, [E('strong', {}, _('Name: ')), d.name || '—']),
                        E('div', {}, [E('strong', {}, _('Category: ')), d.category || '—']),
                        E('div', {}, [E('strong', {}, _('Path: ')), E('code', {}, d.path || '')]),
                        E('div', {}, [E('strong', {}, _('Enabled: ')), d.enabled === '1' ? 'yes' : 'no']),
                        E('div', {}, [E('strong', {}, _('Timeout: ')), d.timeout || '—']),
                        E('div', {}, [E('strong', {}, _('Arguments: ')), d.args || '—']),
                        E('div', {}, [E('strong', {}, _('Size: ')), (d.size || 0) + ' B']),
                        E('div', {}, [E('strong', {}, _('Permissions: ')), E('code', {}, d.permissions || '—')])
                    ]),
                    E('div', { 'style': 'margin-top:14px;text-align:right;' }, [
                        E('button', { 'class': 'btn cbi-button', 'style': 'margin-right:8px;',
                            'click': function() {
                                rpcChmod(sid, '755').then(function() {
                                    ui.addNotification(null, E('p', {}, 'chmod 755 ok'), 'info');
                                });
                            } }, _('Make executable')),
                        E('button', { 'class': 'btn cbi-button cbi-button-action',
                            'click': function() {
                                document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                    if (m.parentNode) m.parentNode.removeChild(m);
                                });
                                document.body.classList.remove('modal-overlay-active');
                            } }, _('Close'))
                    ])
                ]);
            });
        }

        function runScript(sid, name) {
            ui.addNotification(null, E('p', {}, _('Running ' + name + '...')), 'info');
            rpcRun(sid).then(function(r) {
                var out = (r && r.output) ? r.output : '(no output)';
                var rc = (r && r.exit_code != null) ? r.exit_code : '?';
                var dur = (r && r.duration != null) ? r.duration + 's' : '';
                ui.addNotification(
                    E('strong', {}, name + ' · exit ' + rc + (dur ? ' · ' + dur : '')),
                    E('pre', { 'style': 'text-align:left;white-space:pre-wrap;max-height:60vh;overflow:auto;background:#111;color:#0f0;padding:12px;border-radius:4px;font-size:0.85em;' }, out),
                    rc === 0 ? 'info' : 'warning'
                );
            }).catch(function(err) {
                ui.addNotification(null, E('p', {}, 'Run failed: ' + (err.message || err)), 'danger');
            });
        }

        function deleteScript(sid, name) {
            if (!confirm(_('Delete script "' + name + '"? Removes file and UCI entry.'))) return;
            rpcDelete(sid).then(function() {
                ui.addNotification(null, E('p', {}, 'Deleted'), 'info');
                uci.load('quickactions').then(refreshTable);
            }).catch(function(err) {
                ui.addNotification(null, E('p', {}, 'Delete failed: ' + (err.message || err)), 'danger');
            });
        }

        refreshTable();

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, _('Scripts')),
            E('div', { 'style': 'background:rgba(30,144,255,0.08);border:1px solid rgba(30,144,255,0.2);border-radius:6px;padding:12px 16px;margin-bottom:16px;font-size:0.9em;' }, [
                E('strong', {}, _('Scripts ')),
                _('— create, edit, run, and manage shell scripts. Files live in '),
                E('code', {}, '/etc/quickactions/scripts/'),
                _('. Metadata in '),
                E('code', {}, '/etc/config/quickactions'),
                _('.')
            ]),
            tableWrap
        ]);
    },

    // ============ VLAN tab ============
    renderVlan: function() {
        var self = this;

        // Resolve tier (auto → based on detect; else honor uci override)
        function resolvedTier(detect) {
            var override = uci.get('quickactions', 'vlan', 'tier') || 'auto';
            if (override === 'low' || override === 'high') return override;
            var mb = parseInt(detect.mem_mb, 10) || 0;
            return (mb >= 64) ? 'high' : 'low';
        }

        // ---------- top bar with subtab buttons ----------
        var SUBTABS = [
            { id: 'overview',    label: _('Overview') },
            { id: 'wizard',      label: _('Wizard') },
            { id: 'edit',        label: _('Edit') },
            { id: 'library',     label: _('Library'),     tier: 'high' },
            { id: 'ssid',        label: _('SSID') },
            { id: 'import',      label: _('Import') },
            { id: 'safety',      label: _('Safety') },
            { id: 'diagnostics', label: _('Diagnostics'), tier: 'high' },
            { id: 'guide',       label: _('Guide') }
        ];

        var subBar = E('div', {
            'style': 'display:flex;gap:4px;border-bottom:2px solid rgba(0,0,0,0.08);' +
                     'margin:0 0 16px 0;flex-wrap:wrap;'
        });
        var subContent = E('div');

        var subButtons = {};
        var tierResolved = null;

        function paintSubTabButtons() {
            SUBTABS.forEach(function(t) {
                var b = subButtons[t.id];
                if (!b) return;
                var hidden = (t.tier === 'high' && tierResolved !== 'high');
                b.style.display = hidden ? 'none' : '';
                if (t.id === self.vlanActiveSubTab) {
                    b.style.borderBottomColor = '#1e90ff';
                    b.style.color = '#1e90ff';
                    b.style.fontWeight = 'bold';
                } else {
                    b.style.borderBottomColor = 'transparent';
                    b.style.color = '#666';
                    b.style.fontWeight = '500';
                }
            });
        }

        SUBTABS.forEach(function(t) {
            var b = E('div', {
                'style': 'padding:8px 16px;cursor:pointer;border-bottom:3px solid transparent;' +
                         'color:#666;font-weight:500;font-size:0.9em;user-select:none;',
                'click': function() { self.vlanShowSub(t.id); }
            }, t.label);
            subButtons[t.id] = b;
            subBar.appendChild(b);
        });

        // stash refs on the view for helper methods
        self._vlanSubButtons = subButtons;
        self._vlanSubContent = subContent;
        self._vlanPaintSubTabButtons = paintSubTabButtons;
        self._vlanResolvedTier = resolvedTier;

        // initial subtab
        self.vlanActiveSubTab = self.vlanActiveSubTab || 'overview';

        // first-time detect (needed to know the tier)
        self.callVlan('detect').then(function(detect) {
            self._vlanDetect = detect;
            tierResolved = resolvedTier(detect);
            self.vlanTier = tierResolved;
            paintSubTabButtons();
            self.vlanShowSub(self.vlanActiveSubTab);
        }).catch(function(err) {
            subContent.innerHTML = '';
            subContent.appendChild(E('div', {
                'class': 'alert-message error',
                'style': 'padding:16px;'
            }, 'VLAN detect failed: ' + (err && err.message ? err.message : String(err))));
        });

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, _('VLAN Management')),
            E('p', { 'style': 'color:#888;font-size:0.9em;margin-top:-8px;' },
                _('View, create, and edit VLANs on this router and generate matching configs for MikroTik, Cisco, and EdgeOS devices.')),
            subBar,
            subContent
        ]);
    },

    // rpc shim for luci.quickactions-vlan
    callVlan: function(method, p1, p2, p3, p4) {
        var sigs = {
            'detect': [],
            'preview': ['plan'],
            'apply': ['plan', 'safe'],
            'snapshot': ['note'],
            'list_snapshots': [],
            'restore': ['path'],
            'confirm': [],
            'generate_cli': ['plan', 'target'],
            'save_template': ['name', 'target', 'plan', 'notes'],
            'list_templates': [],
            'load_template': ['name'],
            'delete_template': ['name'],
            'save_generated': ['name', 'target', 'content'],
            'list_generated': [],
            'delete_generated': ['name'],
            'lldp_neighbors': [],
            'snmp_query': ['ip', 'community'],
            'bridge_vlan_show': [],
            'kernel_ifaces': [],
            'iface_stats': ['ifaces'],
            'ping_test': ['iface', 'ip']
        };
        var sig = sigs[method] || [];
        var call = rpc.declare({
            object: 'luci.quickactions-vlan',
            method: method,
            params: sig,
            expect: { '': {} }
        });
        var args = [p1 || '', p2 || '', p3 || '', p4 || ''].slice(0, sig.length);
        return call.apply(null, args);
    },

    // sub-tab dispatcher
    vlanShowSub: function(id) {
        var self = this;
        self.vlanActiveSubTab = id;
        if (self._vlanPaintSubTabButtons) self._vlanPaintSubTabButtons();
        var subContent = self._vlanSubContent;
        if (!subContent) return;
        subContent.innerHTML = '';
        subContent.appendChild(E('p', { 'style': 'color:#888;padding:20px;' },
            _('Loading ') + id + _('...')));

        var builder = {
            overview:    'vlanRenderOverview',
            wizard:      'vlanRenderWizard',
            edit:        'vlanRenderEdit',
            library:     'vlanRenderLibrary',
            ssid:        'vlanRenderSsid',
            import:      'vlanRenderImport',
            safety:      'vlanRenderSafety',
            diagnostics: 'vlanRenderDiagnostics',
            guide:       'vlanRenderGuide'
        }[id];

        if (!builder || typeof self[builder] !== 'function') {
            subContent.innerHTML = '';
            subContent.appendChild(E('p', { 'style': 'color:#888;padding:20px;' },
                _('This section is coming in a follow-up patch.')));
            return;
        }

        Promise.resolve(self[builder]()).then(function(node) {
            subContent.innerHTML = '';
            if (node) subContent.appendChild(node);
        }).catch(function(err) {
            subContent.innerHTML = '';
            subContent.appendChild(E('div', {
                'class': 'alert-message error',
                'style': 'padding:16px;'
            }, 'Error: ' + (err && err.message ? err.message : String(err))));
        });
    },

    // ---------- Overview ----------
    vlanRenderOverview: function() {
        var self = this;
        var d = self._vlanDetect;
        if (!d) return E('p', { 'style': 'color:#888;' }, _('Detection has not run yet.'));

        function card(title, body) {
            return E('div', {
                'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);' +
                         'border-radius:8px;padding:14px 16px;margin-bottom:16px;'
            }, [
                E('h4', { 'style': 'margin:0 0 10px 0;font-size:1em;' }, title),
                body
            ]);
        }

        function table(cols, rows) {
            var t = E('table', { 'style': 'width:100%;border-collapse:collapse;font-size:0.9em;' });
            var hr = E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' });
            cols.forEach(function(c) {
                hr.appendChild(E('th', { 'style': 'padding:6px 8px;font-weight:600;' }, c));
            });
            t.appendChild(hr);
            rows.forEach(function(r) {
                var tr = E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.05);' });
                r.forEach(function(cell) {
                    tr.appendChild(E('td', { 'style': 'padding:6px 8px;' },
                        typeof cell === 'string' ? cell : cell));
                });
                t.appendChild(tr);
            });
            return t;
        }

        // Platform card
        var currentTier = self.vlanTier || self._vlanResolvedTier(d);
        var platformBody = E('div', {}, [
            E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:8px;' }, [
                E('div', {}, [E('strong', {}, _('Mode: ')), d.mode === 'dsa' ? 'DSA (bridge VLAN filtering)' : (d.mode === 'swconfig' ? 'swconfig (legacy)' : 'unknown')]),
                E('div', {}, [E('strong', {}, _('Kernel: ')), d.kernel || '—']),
                E('div', {}, [E('strong', {}, _('Memory: ')), (d.mem_mb || '—') + ' MB']),
                E('div', {}, [E('strong', {}, _('Hostname: ')), d.hostname || '—'])
            ]),
            E('div', { 'style': 'margin-top:10px;display:flex;align-items:center;gap:10px;flex-wrap:wrap;' }, [
                E('span', { 'style': 'font-size:0.9em;color:#666;' }, _('Resource mode: ')),
                (function() {
                    var override = uci.get('quickactions', 'vlan', 'tier') || 'auto';
                    var wrap = E('div', { 'style': 'display:flex;gap:6px;' });
                    [['auto','Auto'],['low','Low'],['high','High']].forEach(function(o) {
                        var btn = E('button', {
                            'class': 'btn cbi-button' + (override === o[0] ? ' cbi-button-action important' : ''),
                            'style': 'padding:4px 12px;font-size:0.85em;',
                            'click': function() {
                                uci.load('quickactions').then(function() {
                                    uci.set('quickactions', 'vlan', 'tier', o[0]);
                                    return uci.save();
                                }).then(function() {
                                    ui.addNotification(null, E('p', {}, _('Tier saved. Reload the tab to apply.')), 'info');
                                    self.refreshPendingCount();
                                });
                            }
                        }, o[1]);
                        wrap.appendChild(btn);
                    });
                    return wrap;
                })(),
                E('span', { 'style': 'font-size:0.85em;color:#888;' },
                    _('Resolved: ') + (currentTier || '—').toUpperCase())
            ])
        ]);

        // Bridges
        var bridgeRows = (d.bridges || []).map(function(b) {
            return [
                b.name || b.sid,
                b.vlan_filtering === '1' ? '✓' : '—',
                (b.sid && b.sid.indexOf('@') === 0) ? _('anonymous') : b.sid
            ];
        });

        // VLANs
        var vlanRows = (d.bridge_vlans || []).map(function(v) {
            return [v.device || '', v.vlan || '', v.ports || '', v.sid || ''];
        });

        // Interfaces
        var ifaceRows = (d.interfaces || []).map(function(i) {
            return [i.sid || '', i.device || '', i.proto || '', i.ipaddr || '', i.netmask || ''];
        });

        // DHCP
        var dhcpRows = (d.dhcp || []).map(function(x) {
            return [x.sid || '', x.interface || '', x.start || '', x.limit || ''];
        });

        // Zones
        var zoneRows = (d.zones || []).map(function(z) {
            return [z.name || '', z.network || '', z.input || '', z.output || '', z.forward || ''];
        });

        // Wifi
        var wifiRows = (d.wifi || []).map(function(w) {
            return [w.ssid || w.sid || '', w.device || '', w.mode || '', w.network || ''];
        });

        // Easymesh devices
        var easymeshRows = (d.easymesh || []).map(function(x) { return [x]; });

        var refreshRow = E('div', { 'style': 'margin-bottom:14px;' }, [
            E('button', {
                'class': 'btn cbi-button',
                'style': 'padding:6px 14px;',
                'click': function() {
                    self.callVlan('detect').then(function(dd) {
                        self._vlanDetect = dd;
                        self.vlanShowSub('overview');
                    });
                }
            }, _('↻ Refresh'))
        ]);

        return E('div', {}, [
            refreshRow,
            card(_('Platform'), platformBody),
            card(_('Bridges') + ' (' + (d.bridges || []).length + ')',
                table([_('Name'), _('VLAN filtering'), _('Section')], bridgeRows.length ? bridgeRows :
                    [[E('em', { 'style': 'color:#888;' }, _('(none)')), '', '']])),
            card(_('VLANs') + ' (' + vlanRows.length + ')',
                table([_('Device'), _('VLAN ID'), _('Ports'), _('Section')], vlanRows.length ? vlanRows :
                    [[E('em', { 'style': 'color:#888;' }, _('(no bridge-vlan entries yet)')), '', '', '']])),
            card(_('Interfaces') + ' (' + ifaceRows.length + ')',
                table([_('Name'), _('Device'), _('Proto'), _('IP address'), _('Netmask')], ifaceRows)),
            card(_('DHCP pools') + ' (' + dhcpRows.length + ')',
                table([_('Section'), _('Interface'), _('Start'), _('Limit')], dhcpRows)),
            card(_('Firewall zones') + ' (' + zoneRows.length + ')',
                table([_('Name'), _('Networks'), _('Input'), _('Output'), _('Forward')], zoneRows)),
            card(_('Wireless') + ' (' + wifiRows.length + ')',
                table([_('SSID'), _('Radio'), _('Mode'), _('Attached network')], wifiRows)),
            easymeshRows.length ? card(_('EasyMesh bat0 devices'),
                table([_('Device')], easymeshRows)) : null
        ].filter(Boolean));
    },

    // ---------- Guide ----------
    vlanRenderGuide: function() {
        function h4(t) { return E('h4', { 'style': 'margin:20px 0 8px 0;font-size:1.05em;color:#1e90ff;' }, t); }
        function p(t) { return E('p', { 'style': 'margin:6px 0;line-height:1.6;font-size:0.92em;' }, t); }
        function pre(t) { return E('pre', { 'style': 'background:#111;color:#0f0;padding:10px 12px;border-radius:4px;overflow-x:auto;font-size:0.85em;white-space:pre-wrap;' }, t); }
        function li(t) { return E('li', { 'style': 'line-height:1.6;font-size:0.9em;' }, t); }
        function box(children, color) {
            return E('div', {
                'style': 'background:rgba(' + (color || '30,144,255') + ',0.08);' +
                         'border:1px solid rgba(' + (color || '30,144,255') + ',0.2);' +
                         'border-radius:6px;padding:12px 16px;margin:12px 0;font-size:0.9em;'
            }, children);
        }

        var guide = E('div', { 'style': 'line-height:1.6;' }, [
            p(_('This tab lets you view, create, and edit VLANs on this router. It can also generate matching configs for external switches (MikroTik, Cisco, EdgeOS).')),

            h4(_('📘 What is a VLAN?')),
            p(_('A VLAN (Virtual Local Area Network) divides one physical LAN into multiple logical networks. Devices on the same switch can be isolated into separate groups — as if they were on entirely different networks.')),

            h4(_('🛠️ Why use VLAN?')),
            E('ul', { 'style': 'padding-left:22px;' }, [
                li(_('Security: keep sensitive devices (printers, NAS) separate from guest traffic.')),
                li(_('Traffic management: reduce broadcast traffic and improve speed.')),
                li(_('Easy management: move a device without reconfiguring its network.')),
                li(_('Cost efficiency: no extra switches or routers needed.'))
            ]),

            h4(_('🔍 First check: DSA or swconfig?')),
            box([
                E('strong', {}, _('Your router: ')),
                p(_('Network → Interfaces → Devices with "Bridge VLAN filtering" = DSA (modern).')),
                p(_('Network → Switch menu = swconfig (legacy).')),
                p(_('OpenWrt 21.02+ typically uses DSA. Some single-port travel routers do not support VLAN filtering at all.'))
            ]),

            h4(_('📂 Types of VLAN')),
            E('ul', { 'style': 'padding-left:22px;' }, [
                li(_('Port-based: one port = one VLAN.')),
                li(_('Tagged (802.1Q): one port carries multiple VLANs, each packet tagged.')),
                li(_('MAC-based: VLAN membership decided by MAC address.')),
                li(_('Protocol-based: VLAN membership decided by packet protocol.'))
            ]),

            h4(_('💻 OpenWrt DSA quick example — VLAN 20 for a Guest network')),
            box([
                E('strong', { 'style': 'color:#c00;' }, _('⚠️ Connect via a LAN port you will NOT modify. Never apply VLAN changes over Wi-Fi or over the port you are changing. You will lock yourself out.'))
            ], '220,53,69'),
            p(_('Step 1 — Enable VLAN filtering on the bridge:')),
            pre('Network → Interfaces → Devices → br-lan → Configure → Bridge VLAN filtering → Enable'),
            p(_('Step 2 — Add VLAN 20: pick ports, mark them tagged or untagged.')),
            p(_('Step 3 — Create the interface (protocol static, IP 192.168.20.1/24, device br-lan.20).')),
            p(_('Step 4 — Create the firewall zone, then click Save & Apply.')),
            p(_('Use the Wizard subtab above to do all four steps in one flow.')),

            h4(_('📶 Tagging a Wi-Fi SSID to a VLAN')),
            p(_('You do not tag the SSID directly — you attach the wireless interface to the VLAN\'s logical network.')),
            p(_('Use the SSID subtab above: pick the SSID, pick the VLAN interface, save.')),

            h4(_('🛡️ Client Isolation')),
            p(_('Blocks guests from reaching each other on the same SSID. Enable "Isolate clients" in the wireless advanced settings, or use the SSID subtab in this tab.')),

            h4(_('📖 Term definitions')),
            E('ul', { 'style': 'padding-left:22px;' }, [
                li([E('strong', {}, _('VLAN ID: ')), _('number 1–4094. Avoid 0, 1, 4095.')]),
                li([E('strong', {}, _('Access port: ')), _('a port dedicated to one VLAN.')]),
                li([E('strong', {}, _('Trunk port: ')), _('a port carrying multiple VLANs (tagged).')]),
                li([E('strong', {}, _('Tagged packet: ')), _('carries a VLAN tag identifying its network.')])
            ]),

            h4(_('🪵 Inter-VLAN Routing (Router-on-a-Stick)')),
            p(_('The router is the gateway between VLANs. Traffic between them goes through the firewall zone forwarding rules.')),

            h4(_('🔥 Zone Forwarding')),
            p(_('Allow LAN → Guest (one-way): Network → Firewall → Zones → lan → Allow forward to guest_zone.')),
            box([
                E('strong', { 'style': 'color:#c00;' }, _('⚠️ Never enable Guest → LAN. That defeats the isolation.'))
            ], '220,53,69'),

            h4(_('🛟 Anti-lockout & rollback')),
            p(_('The Safety subtab above takes snapshots and supports a 90-second auto-rollback after every apply.')),
            p(_('Manual restore:')),
            pre('cp /etc/quickactions/vlan/network.bak.<ts> /etc/config/network\n/etc/init.d/network reload'),

            h4(_('🌐 Cross-platform notes')),
            p(_('DSA bridge-vlan → MikroTik /interface bridge vlan add bridge=... vlan-ids=N tagged=... untagged=...')),
            p(_('Cisco: switchport trunk allowed vlan 10,20 ; switchport trunk native vlan 1')),
            p(_('EdgeOS: set interfaces ethernet ethN vif <id> address <ip>')),

            box([
                E('strong', {}, _('Generated CLI examples ')),
                _('are available in the Wizard subtab once you build a plan and pick a target platform.')
            ])
        ]);

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, _('VLAN Guide')),
            guide
        ]);
    },

    // ---------- Wizard ----------
    vlanRenderWizard: function() {
        var self = this;
        var d = self._vlanDetect || {};
        var ifaces = d.interfaces || [];
        var bridges = d.bridges || [];

        // Collect all physical ports from UCI network.device (non-bridge) + interface devices
        function collectPorts() {
            var ports = {};
            // bridge members
            (uci.sections('network', 'device') || []).forEach(function(dev) {
                if (dev.type === 'bridge') {
                    var p = dev.ports;
                    if (typeof p === 'string') p = p.split(/\s+/);
                    if (Array.isArray(p)) p.forEach(function(x) { if (x) ports[x] = 1; });
                } else if (dev.name) {
                    ports[dev.name] = 1;
                }
            });
            // interface devices
            ifaces.forEach(function(i) {
                if (i.device && i.device.indexOf('@') !== 0) ports[i.device] = 1;
            });
            // physical /sys/class/net
            return Object.keys(ports).sort();
        }
        var allPorts = collectPorts();

        // ---- Step state ----
        var state = {
            target:    'openwrt-dsa',
            vlanId:    '20',
            bridge:    (bridges[0] && bridges[0].name) || 'br-lan',
            newBridge: '',
            ports:     {},   // {port: 'off'|'u'|'t'}
            ifaceOn:   true,
            ifaceName: 'GUEST',
            ifaceProto:'static',
            ifaceIp:   '192.168.20.1',
            ifaceMask: '255.255.255.0',
            dhcpOn:    true,
            dhcpStart: '100',
            dhcpLimit: '150',
            dhcpLease: '12h',
            zoneOn:    true,
            zoneName:  'guest_zone',
            zoneInput: 'REJECT',
            zoneOutput:'ACCEPT',
            zoneForward:'REJECT',
            zoneMasq:  false,
            zoneForwardTo: 'wan',
            ssidOn:    false,
            ssidNew:   true,
            ssidName:  'GUEST-WiFi',
            ssidEnc:   'psk2',
            ssidPass:  '',
            ssidPick:  ''
        };

        allPorts.forEach(function(p) { state.ports[p] = 'off'; });

        // ---- Simple field helpers ----
        function field(label, el, hint) {
            return E('div', { 'style': 'margin-bottom:12px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;font-weight:500;' }, label),
                el,
                hint ? E('div', { 'style': 'font-size:0.8em;color:#888;margin-top:3px;' }, hint) : null
            ]);
        }
        function txtInput(v, ph) {
            return E('input', { 'type': 'text', 'value': v || '', 'placeholder': ph || '',
                'style': 'width:100%;max-width:400px;padding:8px 10px;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;' });
        }
        function numInput(v, min, max) {
            return E('input', { 'type': 'number', 'value': v, 'min': min, 'max': max,
                'style': 'width:100%;max-width:200px;padding:8px 10px;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;' });
        }
        function select(opts, val) {
            var s = E('select', { 'style': 'width:100%;max-width:400px;padding:8px 10px;border:1px solid #ccc;border-radius:4px;' });
            opts.forEach(function(o) {
                var opt = E('option', { 'value': o[0] }, o[1]);
                if (o[0] === val) opt.selected = true;
                s.appendChild(opt);
            });
            return s;
        }
        function check(label, checked, hint) {
            var cb = E('input', { 'type': 'checkbox' });
            if (checked) cb.checked = true;
            return E('div', { 'style': 'margin-bottom:10px;display:flex;align-items:flex-start;gap:10px;' }, [
                cb,
                E('div', {}, [
                    E('label', { 'style': 'font-size:0.95em;font-weight:500;' }, label),
                    hint ? E('div', { 'style': 'font-size:0.8em;color:#888;margin-top:2px;' }, hint) : null
                ])
            ]);
        }

        // ---- Step 0: Target platform ----
        var targetSel = select([
            ['openwrt-dsa',     'OpenWrt DSA (this router)'],
            ['openwrt-swconfig','OpenWrt swconfig (this router)'],
            ['mikrotik',        'MikroTik RouterOS 6/7 (generate CLI)'],
            ['cisco',           'Cisco IOS / NX-OS (generate CLI)'],
            ['edgeos',          'EdgeOS / EdgeSwitch (generate CLI)'],
            ['generic',         'Generic 802.1Q (table + JSON)']
        ], state.target);
        targetSel.addEventListener('change', function() { state.target = targetSel.value; });

        // ---- Step 1: VLAN ID + parent bridge ----
        var vidEl = numInput(state.vlanId, 2, 4094);
        vidEl.addEventListener('input', function() { state.vlanId = vidEl.value; });

        var bridgeSel = select(bridges.map(function(b) { return [b.name, b.name]; }).concat([['__new__', 'Create new bridge...']]), state.bridge);
        bridgeSel.addEventListener('change', function() { state.bridge = bridgeSel.value; });
        var newBridgeEl = txtInput('', 'br-vlan');
        newBridgeEl.addEventListener('input', function() { state.newBridge = newBridgeEl.value; });

        // ---- Step 2: Ports ----
        var portRows = [];
        function rebuildPortTable() {
            portRows = allPorts.map(function(p) {
                var sel = E('select', { 'style': 'width:120px;padding:4px 8px;border:1px solid #ccc;border-radius:4px;' });
                [['off','— off'],['u','Untagged'],['t','Tagged']].forEach(function(o) {
                    var opt = E('option', { 'value': o[0] }, o[1]);
                    if (o[0] === state.ports[p]) opt.selected = true;
                    sel.appendChild(opt);
                });
                sel.addEventListener('change', function() { state.ports[p] = sel.value; });
                return E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.05);' }, [
                    E('td', { 'style': 'padding:4px 8px;font-family:monospace;' }, p),
                    E('td', { 'style': 'padding:4px 8px;' }, sel)
                ]);
            });
            var t = E('table', { 'style': 'border-collapse:collapse;' });
            t.appendChild(E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' }, [
                E('th', { 'style': 'padding:6px 8px;' }, _('Port')),
                E('th', { 'style': 'padding:6px 8px;' }, _('Mode'))
            ]));
            portRows.forEach(function(r) { t.appendChild(r); });
            return t;
        }

        // ---- Step 3: Interface ----
        var ifNameEl = txtInput(state.ifaceName);
        ifNameEl.addEventListener('input', function() { state.ifaceName = ifNameEl.value; });
        var ifProtoSel = select([['static','Static'],['dhcp','DHCP'],['none','None']], state.ifaceProto);
        ifProtoSel.addEventListener('change', function() { state.ifaceProto = ifProtoSel.value; });
        var ifIpEl = txtInput(state.ifaceIp);
        ifIpEl.addEventListener('input', function() { state.ifaceIp = ifIpEl.value; });
        var ifMaskEl = txtInput(state.ifaceMask);
        ifMaskEl.addEventListener('input', function() { state.ifaceMask = ifMaskEl.value; });

        // ---- Step 4: DHCP ----
        var dhStartEl = numInput(state.dhcpStart, 1, 250);
        dhStartEl.addEventListener('input', function() { state.dhcpStart = dhStartEl.value; });
        var dhLimitEl = numInput(state.dhcpLimit, 1, 250);
        dhLimitEl.addEventListener('input', function() { state.dhcpLimit = dhLimitEl.value; });
        var dhLeaseEl = txtInput(state.dhcpLease, '12h');
        dhLeaseEl.addEventListener('input', function() { state.dhcpLease = dhLeaseEl.value; });

        // ---- Step 5: Firewall zone ----
        var zNameEl = txtInput(state.zoneName);
        zNameEl.addEventListener('input', function() { state.zoneName = zNameEl.value; });
        var zInSel = select([['REJECT','REJECT'],['ACCEPT','ACCEPT'],['DROP','DROP']], state.zoneInput);
        zInSel.addEventListener('change', function() { state.zoneInput = zInSel.value; });
        var zOutSel = select([['ACCEPT','ACCEPT'],['REJECT','REJECT'],['DROP','DROP']], state.zoneOutput);
        zOutSel.addEventListener('change', function() { state.zoneOutput = zOutSel.value; });
        var zFwdSel = select([['REJECT','REJECT'],['ACCEPT','ACCEPT'],['DROP','DROP']], state.zoneForward);
        zFwdSel.addEventListener('change', function() { state.zoneForward = zFwdSel.value; });
        var zDestSel = select(
            (d.zones || []).map(function(z) { return [z.name, z.name]; }),
            state.zoneForwardTo
        );
        zDestSel.addEventListener('change', function() { state.zoneForwardTo = zDestSel.value; });

        // ---- Step 6: SSID attach ----
        var ssidPickSel = select(
            (d.wifi || []).map(function(w) { return [w.sid, (w.ssid || w.sid) + ' (' + w.device + ')']; }),
            state.ssidPick
        );
        ssidPickSel.addEventListener('change', function() { state.ssidPick = ssidPickSel.value; });
        var ssidNameEl = txtInput(state.ssidName);
        ssidNameEl.addEventListener('input', function() { state.ssidName = ssidNameEl.value; });
        var ssidEncSel = select([['psk2','WPA2-PSK'],['sae','WPA3-SAE'],['sae-mixed','WPA2/WPA3'],['none','Open']], state.ssidEnc);
        ssidEncSel.addEventListener('change', function() { state.ssidEnc = ssidEncSel.value; });
        var ssidPassEl = txtInput(state.ssidPass, 'min 8 chars');
        ssidPassEl.addEventListener('input', function() { state.ssidPass = ssidPassEl.value; });

        // ---- Build plan object ----
        function buildPlan() {
            var tagged = [], untagged = [];
            Object.keys(state.ports).forEach(function(p) {
                if (state.ports[p] === 't') tagged.push(p);
                else if (state.ports[p] === 'u') untagged.push(p);
            });
            var bridge = (state.bridge === '__new__') ? (state.newBridge || 'br-vlan') : state.bridge;
            var plan = {
                vlans: [{
                    sid: 'vlan' + state.vlanId,
                    bridge: bridge,
                    vlan: state.vlanId,
                    tagged: tagged,
                    untagged: untagged,
                    purpose: ''
                }]
            };
            if (state.ifaceOn) {
                plan.interfaces = [{
                    name: state.ifaceName,
                    device: bridge + '.' + state.vlanId,
                    proto: state.ifaceProto,
                    ipaddr: state.ifaceIp,
                    netmask: state.ifaceMask
                }];
            }
            if (state.dhcpOn) {
                plan.dhcp = [{
                    name: state.ifaceName,
                    interface: state.ifaceName,
                    start: state.dhcpStart,
                    limit: state.dhcpLimit,
                    leasetime: state.dhcpLease
                }];
            }
            if (state.zoneOn) {
                plan.zones = [{
                    name: state.zoneName,
                    network: [state.ifaceName],
                    input: state.zoneInput,
                    output: state.zoneOutput,
                    forward: state.zoneForward,
                    masq: state.zoneMasq ? '1' : '0',
                    forward_to: state.zoneForwardTo
                }];
            }
            if (state.ssidOn && !state.ssidNew && state.ssidPick) {
                plan.attach_wifi = [{ sid: state.ssidPick, network: state.ifaceName }];
            }
            return plan;
        }

        // ---- Preview + Apply ----
        var previewOut = E('pre', {
            'style': 'background:#111;color:#0f0;padding:12px;border-radius:4px;' +
                     'font-size:0.85em;white-space:pre-wrap;max-height:300px;overflow:auto;' +
                     'margin:0;display:none;'
        });

        function updatePreview() {
            var plan = buildPlan();
            previewOut.style.display = 'block';
            previewOut.textContent = JSON.stringify(plan, null, 2);
        }

        var previewBtn = E('button', { 'class': 'btn cbi-button',
            'style': 'padding:8px 18px;',
            'click': updatePreview }, _('Preview plan'));

        var applyBtn = E('button', {
            'class': 'btn cbi-button',
            'style': 'background:#28a745 !important;background-color:#28a745 !important;' +
                     'color:#fff !important;padding:8px 22px;font-weight:bold;border:none;' +
                     'border-radius:4px;cursor:pointer;margin-left:8px;'
        }, _('Apply to this router'));
        applyBtn.addEventListener('click', function() {
            var plan = buildPlan();
            if (!confirm(_('Apply this VLAN plan to the router?\n\nA snapshot will be taken first. Network will reload.'))) return;
            self.callVlan('apply', JSON.stringify(plan), '0').then(function(r) {
                if (r && r.error) {
                    ui.addNotification(null, E('p', {}, 'Apply failed: ' + r.error), 'danger');
                    return;
                }
                ui.addNotification(null,
                    E('p', {}, _('VLAN applied. Network reloaded.')),
                    'info');
                self.vlanShowSub('overview');
            }).catch(function(err) {
                ui.addNotification(null, E('p', {}, 'Apply failed: ' + (err.message || err)), 'danger');
            });
        });

        var applySafeBtn = E('button', {
            'class': 'btn cbi-button',
            'style': 'background:#dc3545 !important;background-color:#dc3545 !important;' +
                     'color:#fff !important;padding:8px 22px;font-weight:bold;border:none;' +
                     'border-radius:4px;cursor:pointer;margin-left:8px;'
        }, _('Apply with 90s rollback'));
        applySafeBtn.addEventListener('click', function() {
            var plan = buildPlan();
            if (!confirm(_('Apply with 90-second rollback?\n\nIf you lose access, the network will auto-restore after 90 seconds.'))) return;
            self.callVlan('apply', JSON.stringify(plan), '1').then(function(r) {
                if (r && r.error) {
                    ui.addNotification(null, E('p', {}, 'Apply failed: ' + r.error), 'danger');
                    return;
                }
                ui.addNotification(null,
                    E('p', {}, _('Applied with rollback in 90s. Click Confirm in Safety subtab to keep.')),
                    'warning');
                self.vlanShowSub('overview');
            }).catch(function(err) {
                ui.addNotification(null, E('p', {}, 'Apply failed: ' + (err.message || err)), 'danger');
            });
        });

        var genBtn = E('button', {
            'class': 'btn cbi-button',
            'style': 'background:#17a2b8 !important;background-color:#17a2b8 !important;' +
                     'color:#fff !important;padding:8px 22px;font-weight:bold;border:none;' +
                     'border-radius:4px;cursor:pointer;margin-left:8px;'
        }, _('Generate CLI for selected target'));
        genBtn.addEventListener('click', function() {
            var plan = buildPlan();
            var target = (state.target === 'openwrt-dsa' || state.target === 'openwrt-swconfig') ? 'generic' : state.target;
            self.callVlan('generate_cli', JSON.stringify(plan), target).then(function(r) {
                if (r && r.cli) {
                    ui.showModal(_('Generated CLI for ') + target, [
                        E('pre', {
                            'style': 'background:#111;color:#0f0;padding:12px;border-radius:4px;' +
                                     'font-size:0.85em;white-space:pre-wrap;max-height:60vh;overflow:auto;width:100%;' +
                                     'box-sizing:border-box;'
                        }, r.cli),
                        E('div', { 'style': 'margin-top:14px;text-align:right;' }, [
                            E('button', { 'class': 'btn cbi-button', 'style': 'margin-right:8px;',
                                'click': function() {
                                    navigator.clipboard && navigator.clipboard.writeText(r.cli);
                                    ui.addNotification(null, E('p', {}, _('Copied to clipboard.')), 'info');
                                } }, _('Copy')),
                            E('button', { 'class': 'btn cbi-button cbi-button-action',
                                'click': function() {
                                    document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                        if (m.parentNode) m.parentNode.removeChild(m);
                                    });
                                    document.body.classList.remove('modal-overlay-active');
                                } }, _('Close'))
                        ])
                    ]);
                }
            });
        });

        // ---- Render ----
        var step = function(title, body) {
            return E('div', {
                'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);' +
                         'border-radius:8px;padding:14px 18px;margin-bottom:14px;'
            }, [
                E('h4', { 'style': 'margin:0 0 12px 0;font-size:1.02em;color:#1e90ff;' }, title),
                body
            ]);
        };

        var warn = E('div', {
            'style': 'background:rgba(220,53,69,0.08);border:1px solid rgba(220,53,69,0.3);' +
                     'border-radius:6px;padding:12px 16px;margin-bottom:16px;font-size:0.9em;'
        }, [
            E('strong', { 'style': 'color:#c00;' }, _('⚠️ Connect via a LAN port you will NOT modify. ')),
            _('Never apply VLAN changes over Wi-Fi or over the port you are changing.')
        ]);

        return E('div', {}, [
            warn,
            step(_('Step 0 — Target platform'), field(_('Target'), targetSel,
                _('Choose "this router" to apply directly. Other targets generate a CLI script to paste into the external device.'))),
            step(_('Step 1 — VLAN ID and parent bridge'), E('div', {}, [
                field(_('VLAN ID (2–4094)'), vidEl, _('Avoid VLAN 0, 1 and 4095.')),
                field(_('Parent bridge'), bridgeSel),
                (state.bridge === '__new__') ? field(_('New bridge name'), newBridgeEl) : null
            ].filter(Boolean))),
            step(_('Step 2 — Port assignment'), E('div', {}, [
                E('p', { 'style': 'font-size:0.88em;color:#888;margin:0 0 10px 0;' },
                    _('Choose per-port mode. Leave ports on "off" if unused.')),
                rebuildPortTable()
            ])),
            step(_('Step 3 — Logical interface'), E('div', {}, [
                check(_('Create logical interface'), state.ifaceOn),
                field(_('Interface name'), ifNameEl),
                field(_('Protocol'), ifProtoSel),
                field(_('IP address'), ifIpEl),
                field(_('Netmask'), ifMaskEl)
            ])),
            step(_('Step 4 — DHCP server'), E('div', {}, [
                check(_('Create DHCP pool'), state.dhcpOn),
                field(_('Start offset'), dhStartEl),
                field(_('Client limit'), dhLimitEl),
                field(_('Lease time'), dhLeaseEl)
            ])),
            step(_('Step 5 — Firewall zone'), E('div', {}, [
                check(_('Create / update firewall zone'), state.zoneOn),
                field(_('Zone name'), zNameEl),
                field(_('Input'), zInSel),
                field(_('Output'), zOutSel),
                field(_('Forward'), zFwdSel),
                field(_('Forward to zone'), zDestSel)
            ])),
            step(_('Step 6 — Attach SSID (optional)'), E('div', {}, [
                check(_('Attach an existing SSID to this VLAN interface'), state.ssidOn),
                state.ssidOn ? E('div', {}, [
                    field(_('Existing SSID'), ssidPickSel)
                ]) : null
            ].filter(Boolean))),
            E('div', { 'style': 'margin-top:18px;display:flex;flex-wrap:wrap;gap:8px;align-items:center;' }, [
                previewBtn, applyBtn, applySafeBtn, genBtn
            ]),
            E('div', { 'style': 'margin-top:14px;' }, [previewOut])
        ]);
    },

    // ---------- Edit ----------
    vlanRenderEdit: function() {
        var self = this;
        var d = self._vlanDetect || {};

        function table(cols, rows, editFn) {
            var t = E('table', { 'style': 'width:100%;border-collapse:collapse;font-size:0.9em;' });
            var hr = E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' });
            cols.forEach(function(c) { hr.appendChild(E('th', { 'style': 'padding:6px 8px;' }, c)); });
            if (editFn) hr.appendChild(E('th', { 'style': 'padding:6px 8px;text-align:right;' }, _('')));
            t.appendChild(hr);
            rows.forEach(function(r) {
                var tr = E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.05);' });
                r.forEach(function(cell) {
                    tr.appendChild(E('td', { 'style': 'padding:6px 8px;' }, cell));
                });
                if (editFn) {
                    tr.appendChild(E('td', { 'style': 'padding:6px 8px;text-align:right;' },
                        E('button', {
                            'class': 'btn cbi-button',
                            'style': 'padding:2px 10px;font-size:0.85em;',
                            'click': function() { editFn(r); }
                        }, _('Edit'))));
                }
                t.appendChild(tr);
            });
            return t;
        }

        function card(title, body) {
            return E('div', {
                'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);' +
                         'border-radius:8px;padding:14px 16px;margin-bottom:16px;'
            }, [E('h4', { 'style': 'margin:0 0 10px 0;font-size:1em;' }, title), body]);
        }

        // Bridge VLAN editor
        var vlanRows = (d.bridge_vlans || []).map(function(v) {
            return [v.device || '', v.vlan || '', v.ports || '', v.sid || ''];
        });

        function editVlan(row) {
            var sid = row[3];
            var devEl = E('input', { 'type': 'text', 'value': row[0],
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            var vidEl = E('input', { 'type': 'text', 'value': row[1],
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            var portsEl = E('input', { 'type': 'text', 'value': row[2],
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-family:monospace;' });
            ui.showModal(_('Edit VLAN ' + sid), [
                E('div', { 'style': 'margin-bottom:10px;' }, [
                    E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Device')),
                    devEl
                ]),
                E('div', { 'style': 'margin-bottom:10px;' }, [
                    E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('VLAN ID')),
                    vidEl
                ]),
                E('div', { 'style': 'margin-bottom:10px;' }, [
                    E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Ports (space-separated, use :t for tagged)')),
                    portsEl
                ]),
                E('div', { 'style': 'margin-top:14px;text-align:right;' }, [
                    E('button', { 'class': 'btn cbi-button', 'style': 'margin-right:8px;',
                        'click': function() {
                            document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                if (m.parentNode) m.parentNode.removeChild(m);
                            });
                            document.body.classList.remove('modal-overlay-active');
                        } }, _('Cancel')),
                    (function() {
                        var b = E('button', { 'class': 'btn cbi-button',
                            'style': 'background:#28a745 !important;background-color:#28a745 !important;color:#fff !important;padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;' }, _('Save'));
                        b.addEventListener('click', function() {
                            uci.load('network').then(function() {
                                uci.set('network', sid, 'device', devEl.value);
                                uci.set('network', sid, 'vlan', vidEl.value);
                                uci.set('network', sid, 'ports', portsEl.value.split(/\s+/));
                                return uci.save();
                            }).then(function() {
                                ui.addNotification(null, E('p', {}, _('Saved to memory. Use Save & Apply at the top to commit.')), 'info');
                                document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                    if (m.parentNode) m.parentNode.removeChild(m);
                                });
                                document.body.classList.remove('modal-overlay-active');
                                self.vlanShowSub('edit');
                                self.refreshPendingCount();
                            });
                        });
                        return b;
                    })()
                ])
            ]);
        }

        // Interface editor
        var ifRows = (d.interfaces || []).map(function(i) {
            return [i.sid || '', i.device || '', i.proto || '', i.ipaddr || '', i.netmask || ''];
        });

        function editIface(row) {
            var sid = row[0];
            var devEl = E('input', { 'type': 'text', 'value': row[1],
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            var protoEl = E('input', { 'type': 'text', 'value': row[2],
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            var ipEl = E('input', { 'type': 'text', 'value': row[3],
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            var maskEl = E('input', { 'type': 'text', 'value': row[4],
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            ui.showModal(_('Edit interface ' + sid), [
                E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Device')), devEl]),
                E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Protocol')), protoEl]),
                E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('IP address')), ipEl]),
                E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Netmask')), maskEl]),
                E('div', { 'style': 'margin-top:14px;text-align:right;' }, [
                    E('button', { 'class': 'btn cbi-button', 'style': 'margin-right:8px;',
                        'click': function() {
                            document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                if (m.parentNode) m.parentNode.removeChild(m);
                            });
                            document.body.classList.remove('modal-overlay-active');
                        } }, _('Cancel')),
                    (function() {
                        var b = E('button', { 'class': 'btn cbi-button',
                            'style': 'background:#28a745 !important;background-color:#28a745 !important;color:#fff !important;padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;' }, _('Save'));
                        b.addEventListener('click', function() {
                            uci.load('network').then(function() {
                                uci.set('network', sid, 'device', devEl.value);
                                uci.set('network', sid, 'proto', protoEl.value);
                                if (ipEl.value) uci.set('network', sid, 'ipaddr', ipEl.value);
                                if (maskEl.value) uci.set('network', sid, 'netmask', maskEl.value);
                                return uci.save();
                            }).then(function() {
                                ui.addNotification(null, E('p', {}, _('Saved to memory.')), 'info');
                                document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                    if (m.parentNode) m.parentNode.removeChild(m);
                                });
                                document.body.classList.remove('modal-overlay-active');
                                self.vlanShowSub('edit');
                                self.refreshPendingCount();
                            });
                        });
                        return b;
                    })()
                ])
            ]);
        }

        return E('div', {}, [
            E('p', { 'style': 'color:#888;font-size:0.9em;' },
                _('Edit existing configuration. Every change is saved to memory; use the top-bar Save & Apply to commit.')),
            card(_('Bridge-VLANs') + ' (' + vlanRows.length + ')',
                table([_('Device'), _('VLAN'), _('Ports'), _('Section')], vlanRows, editVlan)),
            card(_('Interfaces') + ' (' + ifRows.length + ')',
                table([_('Name'), _('Device'), _('Proto'), _('IP'), _('Netmask')], ifRows, editIface)),
            E('div', { 'style': 'margin-top:12px;text-align:right;' }, [
                (function() {
                    var b = E('button', { 'class': 'btn cbi-button',
                        'style': 'background:#28a745 !important;background-color:#28a745 !important;color:#fff !important;padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;' }, _('Save & Apply all VLAN changes'));
                    b.addEventListener('click', function() {
                        uci.save().then(function() {
                            return ui.changes.apply(false);
                        }).then(function() {
                            ui.addNotification(null, E('p', {}, _('Changes applied.')), 'info');
                            self.vlanShowSub('overview');
                        }).catch(function(err) {
                            var m = (err && err.message) ? err.message : String(err);
                            if (/No data|code 5/i.test(m)) return;
                            ui.addNotification(null, E('p', {}, 'Apply failed: ' + m), 'danger');
                        });
                    });
                    return b;
                })()
            ])
        ]);
    },

    // ---------- Import ----------
    vlanRenderImport: function() {
        var self = this;

        var textarea = E('textarea', {
            'spellcheck': 'false',
            'style': 'width:100%;min-height:240px;font-family:monospace;font-size:0.88em;' +
                     'padding:10px;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;',
            'placeholder': '/interface bridge vlan\nadd bridge=bridge1 tagged=ether1,ether2 untagged=ether3 vlan-ids=10'
        });

        var formatSel = E('select', { 'style': 'width:100%;max-width:400px;padding:8px 10px;border:1px solid #ccc;border-radius:4px;' });
        [['auto','Auto-detect'],
         ['mikrotik','MikroTik RouterOS'],
         ['cisco','Cisco IOS / NX-OS'],
         ['edgeos','EdgeOS / EdgeSwitch'],
         ['generic','Generic 802.1Q'],
         ['json','JSON (from this app)']].forEach(function(o) {
            formatSel.appendChild(E('option', { 'value': o[0] }, o[1]));
        });

        var preview = E('pre', {
            'style': 'background:#111;color:#0f0;padding:12px;border-radius:4px;font-size:0.85em;' +
                     'white-space:pre-wrap;max-height:320px;overflow:auto;margin-top:14px;display:none;'
        });

        // ---- Parsers ----
        function parseMikrotik(txt) {
            var vlans = {};
            txt.split('\n').forEach(function(line) {
                if (line.indexOf('vlan-ids=') === -1) return;
                var bridge = (line.match(/bridge=([^\s]+)/) || [])[1] || 'bridge1';
                var vid = (line.match(/vlan-ids=([^\s]+)/) || [])[1];
                if (!vid) return;
                var tagged = ((line.match(/tagged=([^\s]+)/) || [])[1] || '').split(',').filter(Boolean);
                var untagged = ((line.match(/untagged=([^\s]+)/) || [])[1] || '').split(',').filter(Boolean);
                vlans[vid] = { sid: 'vlan' + vid, bridge: bridge, vlan: vid, tagged: tagged, untagged: untagged };
            });
            return { vlans: Object.keys(vlans).map(function(k) { return vlans[k]; }) };
        }

        function parseCisco(txt) {
            var vlans = {};
            var curVid = null, curIface = null, allowed = {}, native = {};
            txt.split('\n').forEach(function(line) {
                var l = line.trim();
                if (/^vlan \d+/.test(l)) {
                    curVid = l.match(/\d+/)[0];
                } else if (/^interface\s+(.+)/.test(l)) {
                    curIface = l.match(/^interface\s+(.+)/)[1];
                } else if (/switchport trunk allowed vlan/i.test(l)) {
                    var m = l.match(/vlan\s+(.+)/i);
                    if (m) allowed[curIface] = m[1].split(',').map(function(x) { return x.trim(); });
                } else if (/switchport trunk native vlan/i.test(l)) {
                    var n = l.match(/vlan\s+(\d+)/i);
                    if (n) native[curIface] = n[1];
                } else if (/switchport access vlan/i.test(l)) {
                    var a = l.match(/vlan\s+(\d+)/i);
                    if (a && curIface) {
                        if (!vlans[a[1]]) vlans[a[1]] = { sid: 'vlan' + a[1], bridge: 'br-lan', vlan: a[1], tagged: [], untagged: [] };
                        vlans[a[1]].untagged.push(curIface);
                    }
                }
            });
            Object.keys(allowed).forEach(function(iface) {
                allowed[iface].forEach(function(v) {
                    if (!vlans[v]) vlans[v] = { sid: 'vlan' + v, bridge: 'br-lan', vlan: v, tagged: [], untagged: [] };
                    vlans[v].tagged.push(iface);
                });
            });
            return { vlans: Object.keys(vlans).map(function(k) { return vlans[k]; }) };
        }

        function parseEdgeos(txt) {
            var vlans = {};
            txt.split('\n').forEach(function(line) {
                var m = line.match(/set interfaces ethernet (\S+) vif (\d+)/);
                if (m) {
                    var iface = m[1], vid = m[2];
                    if (!vlans[vid]) vlans[vid] = { sid: 'vlan' + vid, bridge: 'br-lan', vlan: vid, tagged: [], untagged: [] };
                    vlans[vid].tagged.push(iface);
                }
                var p = line.match(/set interfaces ethernet (\S+) pvid (\d+)/);
                if (p) {
                    var if2 = p[1], vid2 = p[2];
                    if (!vlans[vid2]) vlans[vid2] = { sid: 'vlan' + vid2, bridge: 'br-lan', vlan: vid2, tagged: [], untagged: [] };
                    vlans[vid2].untagged.push(if2);
                }
            });
            return { vlans: Object.keys(vlans).map(function(k) { return vlans[k]; }) };
        }

        function parseGeneric(txt) {
            var vlans = {};
            txt.split('\n').forEach(function(line) {
                var m = line.match(/VLAN\s+(\d+)\s+tagged:\s*([^\s]+)\s+untagged:\s*([^\s]+)/i);
                if (!m) return;
                var vid = m[1];
                vlans[vid] = {
                    sid: 'vlan' + vid, bridge: 'br-lan', vlan: vid,
                    tagged: m[2].split(',').filter(Boolean),
                    untagged: m[3].split(',').filter(Boolean)
                };
            });
            return { vlans: Object.keys(vlans).map(function(k) { return vlans[k]; }) };
        }

        function parseInput(txt, fmt) {
            var t = txt.trim();
            if (fmt === 'json' || t.startsWith('{')) return JSON.parse(t);
            if (fmt === 'mikrotik' || (fmt === 'auto' && /\/interface bridge vlan/.test(t))) return parseMikrotik(t);
            if (fmt === 'cisco' || (fmt === 'auto' && /switchport (trunk|mode)/i.test(t))) return parseCisco(t);
            if (fmt === 'edgeos' || (fmt === 'auto' && /set interfaces ethernet/.test(t))) return parseEdgeos(t);
            if (fmt === 'generic' || (fmt === 'auto' && /VLAN \d+/.test(t))) return parseGeneric(t);
            throw new Error('Could not detect format. Please pick one manually.');
        }

        var parseBtn = E('button', { 'class': 'btn cbi-button',
            'style': 'padding:8px 18px;',
            'click': function() {
                try {
                    var plan = parseInput(textarea.value, formatSel.value);
                    preview.style.display = 'block';
                    preview.textContent = JSON.stringify(plan, null, 2);
                    window._vlanImportedPlan = plan;
                    ui.addNotification(null, E('p', {},
                        (plan.vlans || []).length + ' VLAN(s) parsed. Click Apply to write them.'),
                        'info');
                } catch (e) {
                    preview.style.display = 'block';
                    preview.textContent = 'Error: ' + (e.message || e);
                    window._vlanImportedPlan = null;
                }
            } }, _('Parse'));

        var applyBtn = E('button', {
            'class': 'btn cbi-button',
            'style': 'background:#28a745 !important;background-color:#28a745 !important;color:#fff !important;' +
                     'padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;margin-left:8px;'
        }, _('Apply to this router'));
        applyBtn.addEventListener('click', function() {
            var plan = window._vlanImportedPlan;
            if (!plan || !plan.vlans || !plan.vlans.length) {
                ui.addNotification(null, E('p', {}, 'Nothing to apply — parse first.'), 'warning');
                return;
            }
            if (!confirm('Apply ' + plan.vlans.length + ' VLAN(s) to this router? Snapshot will be taken first.')) return;
            self.callVlan('apply', JSON.stringify(plan), '0').then(function(r) {
                if (r && r.error) {
                    ui.addNotification(null, E('p', {}, 'Apply failed: ' + r.error), 'danger');
                    return;
                }
                ui.addNotification(null, E('p', {}, 'Applied.'), 'info');
                self.vlanShowSub('overview');
            }).catch(function(err) {
                ui.addNotification(null, E('p', {}, 'Apply failed: ' + (err.message || err)), 'danger');
            });
        });

        var genBtn = E('button', {
            'class': 'btn cbi-button',
            'style': 'background:#17a2b8 !important;background-color:#17a2b8 !important;color:#fff !important;' +
                     'padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;margin-left:8px;'
        }, _('Generate CLI'));
        genBtn.addEventListener('click', function() {
            var plan = window._vlanImportedPlan;
            if (!plan || !plan.vlans || !plan.vlans.length) {
                ui.addNotification(null, E('p', {}, 'Parse first.'), 'warning');
                return;
            }
            ui.showModal(_('Generate CLI for'), [
                E('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap;' }, [
                    ['mikrotik','MikroTik'],['cisco','Cisco'],['edgeos','EdgeOS'],['generic','Generic']
                    .map(function(t) {
                        return E('button', { 'class': 'btn cbi-button', 'style': 'padding:8px 16px;',
                            'click': function() {
                                self.callVlan('generate_cli', JSON.stringify(plan), t[0]).then(function(r) {
                                    if (r && r.cli) {
                                        ui.showModal(_('Generated ') + t[1] + _(' CLI'), [
                                            E('pre', { 'style': 'background:#111;color:#0f0;padding:12px;border-radius:4px;font-size:0.85em;white-space:pre-wrap;max-height:60vh;overflow:auto;width:100%;box-sizing:border-box;' }, r.cli),
                                            E('div', { 'style': 'margin-top:14px;text-align:right;' }, [
                                                E('button', { 'class': 'btn cbi-button',
                                                    'click': function() {
                                                        navigator.clipboard && navigator.clipboard.writeText(r.cli);
                                                        ui.addNotification(null, E('p', {}, 'Copied.'), 'info');
                                                    } }, _('Copy')),
                                                E('button', { 'class': 'btn cbi-button cbi-button-action',
                                                    'style': 'margin-left:8px;',
                                                    'click': function() {
                                                        document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                                            if (m.parentNode) m.parentNode.removeChild(m);
                                                        });
                                                        document.body.classList.remove('modal-overlay-active');
                                                    } }, _('Close'))
                                            ])
                                        ]);
                                    }
                                });
                            } }, t[1]);
                    })
                ])
            ]);
        });

        return E('div', {}, [
            E('p', { 'style': 'color:#888;font-size:0.9em;' },
                _('Paste a VLAN configuration from another platform. Parsers run in your browser — nothing is sent to the router until you click Apply.')),
            E('div', { 'style': 'margin-bottom:12px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Format')),
                formatSel
            ]),
            textarea,
            E('div', { 'style': 'margin-top:14px;' }, [parseBtn, applyBtn, genBtn]),
            preview
        ]);
    },

    // ---------- SSID ----------
    vlanRenderSsid: function() {
        var self = this;
        var d = self._vlanDetect || {};
        var ifaces = d.wifi || [];
        var nets = (d.interfaces || []).map(function(i) { return i.sid; }).sort();

        function reload() {
            self.callVlan('detect').then(function(dd) {
                self._vlanDetect = dd;
                self.vlanShowSub('ssid');
            });
        }

        function openEdit(w) {
            var sid = w.sid;
            var ssidEl = E('input', { 'type': 'text', 'value': w.ssid || '',
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            var encEl = E('select', { 'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            [['psk2','WPA2-PSK'],['sae','WPA3-SAE'],['sae-mixed','WPA2/WPA3'],
             ['psk-mixed','WPA/WPA2'],['psk','WPA-PSK'],['owe','OWE'],
             ['none','Open']].forEach(function(o) {
                var opt = E('option', { 'value': o[0] }, o[1]);
                if (o[0] === (uci.get('wireless', sid, 'encryption') || 'psk2')) opt.selected = true;
                encEl.appendChild(opt);
            });
            var keyEl = E('input', { 'type': 'text',
                'value': uci.get('wireless', sid, 'key') || uci.get('wireless', sid, 'key1') || '',
                'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;font-family:monospace;' });
            var netEl = E('select', { 'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
            netEl.appendChild(E('option', { 'value': '' }, _('— none —')));
            nets.forEach(function(n) {
                var opt = E('option', { 'value': n }, n);
                if (n === w.network) opt.selected = true;
                netEl.appendChild(opt);
            });
            var isoCb = E('input', { 'type': 'checkbox' });
            if (uci.get('wireless', sid, 'isolate') === '1') isoCb.checked = true;

            var saveBtn = E('button', { 'class': 'btn cbi-button',
                'style': 'background:#28a745 !important;background-color:#28a745 !important;color:#fff !important;padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;' }, _('Save & Apply'));
            saveBtn.addEventListener('click', function() {
                uci.load('wireless').then(function() {
                    uci.set('wireless', sid, 'ssid', ssidEl.value);
                    uci.set('wireless', sid, 'encryption', encEl.value);
                    if (encEl.value !== 'none' && encEl.value !== 'owe') {
                        uci.set('wireless', sid, 'key', keyEl.value);
                    }
                    if (netEl.value) uci.set('wireless', sid, 'network', netEl.value);
                    uci.set('wireless', sid, 'isolate', isoCb.checked ? '1' : '0');
                    return uci.save();
                }).then(function() {
                    return ui.changes.apply(false);
                }).then(function() {
                    ui.addNotification(null, E('p', {}, _('SSID saved and applied.')), 'info');
                    document.querySelectorAll('.modal-overlay').forEach(function(m) {
                        if (m.parentNode) m.parentNode.removeChild(m);
                    });
                    document.body.classList.remove('modal-overlay-active');
                    reload();
                }).catch(function(err) {
                    var m = (err && err.message) ? err.message : String(err);
                    if (/No data|code 5/i.test(m)) { reload(); return; }
                    ui.addNotification(null, E('p', {}, 'Failed: ' + m), 'danger');
                });
            });

            ui.showModal(_('Edit SSID: ') + (w.ssid || sid), [
                E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('SSID')), ssidEl]),
                E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Encryption')), encEl]),
                E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Password')), keyEl]),
                E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Attach to network (VLAN interface)')), netEl]),
                E('div', { 'style': 'margin-bottom:10px;display:flex;align-items:center;gap:8px;' }, [isoCb, E('label', { 'style': 'font-size:0.9em;' }, _('Client isolation'))]),
                E('div', { 'style': 'margin-top:14px;text-align:right;' }, [
                    E('button', { 'class': 'btn cbi-button', 'style': 'margin-right:8px;',
                        'click': function() {
                            document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                if (m.parentNode) m.parentNode.removeChild(m);
                            });
                            document.body.classList.remove('modal-overlay-active');
                        } }, _('Cancel')),
                    saveBtn
                ])
            ]);
        }

        var t = E('table', { 'style': 'width:100%;border-collapse:collapse;font-size:0.9em;' });
        t.appendChild(E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' }, [
            E('th', { 'style': 'padding:8px;' }, _('SSID')),
            E('th', { 'style': 'padding:8px;' }, _('Radio')),
            E('th', { 'style': 'padding:8px;' }, _('Mode')),
            E('th', { 'style': 'padding:8px;' }, _('Network')),
            E('th', { 'style': 'padding:8px;text-align:right;' }, _(''))
        ]));
        ifaces.forEach(function(w) {
            var tr = E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.05);' }, [
                E('td', { 'style': 'padding:8px;' }, w.ssid || w.sid),
                E('td', { 'style': 'padding:8px;font-family:monospace;' }, w.device || '—'),
                E('td', { 'style': 'padding:8px;' }, w.mode || 'ap'),
                E('td', { 'style': 'padding:8px;' }, w.network || '—'),
                E('td', { 'style': 'padding:8px;text-align:right;' },
                    E('button', { 'class': 'btn cbi-button',
                        'style': 'padding:2px 12px;font-size:0.85em;',
                        'click': function() { openEdit(w); } }, _('Edit')))
            ]);
            t.appendChild(tr);
        });

        return E('div', {}, [
            E('p', { 'style': 'color:#888;font-size:0.9em;' },
                _('Every wireless interface on every radio — attach any SSID to a VLAN network with one click.')),
            t
        ]);
    },

    // ---------- Library ----------
    vlanRenderLibrary: function() {
        var self = this;

        function card(title, body) {
            return E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:14px 16px;margin-bottom:16px;' },
                [E('h4', { 'style': 'margin:0 0 10px 0;font-size:1em;' }, title), body]);
        }

        var tplOut = E('div', { 'id': 'qa-vlan-tpl-list' });
        var genOut = E('div', { 'id': 'qa-vlan-gen-list' });

        function loadTemplates() {
            tplOut.innerHTML = '';
            tplOut.appendChild(E('p', { 'style': 'color:#888;padding:10px;' }, _('Loading...')));
            self.callVlan('list_templates').then(function(r) {
                var items = (r && r.templates) || [];
                tplOut.innerHTML = '';
                if (!items.length) {
                    tplOut.appendChild(E('p', { 'style': 'color:#888;padding:6px;' },
                        _('No templates yet. Save one from the Wizard after you build a plan.')));
                    return;
                }
                var t = E('table', { 'style': 'width:100%;border-collapse:collapse;font-size:0.9em;' });
                t.appendChild(E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' }, [
                    E('th', { 'style': 'padding:6px 8px;' }, _('Name')),
                    E('th', { 'style': 'padding:6px 8px;' }, _('Target')),
                    E('th', { 'style': 'padding:6px 8px;text-align:right;' }, _(''))
                ]));
                items.forEach(function(it) {
                    var meta = {};
                    try { meta = JSON.parse(it.meta || '{}'); } catch(e) {}
                    t.appendChild(E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.05);' }, [
                        E('td', { 'style': 'padding:6px 8px;font-family:monospace;' }, it.name),
                        E('td', { 'style': 'padding:6px 8px;' }, meta.target || '—'),
                        E('td', { 'style': 'padding:6px 8px;text-align:right;' }, [
                            E('button', { 'class': 'btn cbi-button',
                                'style': 'padding:2px 10px;font-size:0.85em;margin-right:4px;',
                                'click': function() {
                                    self.callVlan('load_template', it.name).then(function(rr) {
                                        try {
                                            window._vlanLoadedTemplate = JSON.parse(rr.plan || '{}');
                                            ui.addNotification(null, E('p', {},
                                                _('Template loaded. Switch to Wizard to edit and apply.')),
                                                'info');
                                        } catch(e) {
                                            ui.addNotification(null, E('p', {}, 'Bad template JSON'), 'danger');
                                        }
                                    });
                                } }, _('Load')),
                            E('button', { 'class': 'btn cbi-button cbi-button-negative',
                                'style': 'padding:2px 10px;font-size:0.85em;',
                                'click': function() {
                                    if (!confirm(_('Delete template "' + it.name + '"?'))) return;
                                    self.callVlan('delete_template', it.name).then(function() {
                                        ui.addNotification(null, E('p', {}, _('Deleted')), 'info');
                                        loadTemplates();
                                    });
                                } }, _('Delete'))
                        ])
                    ]));
                });
                tplOut.appendChild(t);
            });
        }

        function loadGenerated() {
            genOut.innerHTML = '';
            genOut.appendChild(E('p', { 'style': 'color:#888;padding:10px;' }, _('Loading...')));
            self.callVlan('list_generated').then(function(r) {
                var items = (r && r.generated) || [];
                genOut.innerHTML = '';
                if (!items.length) {
                    genOut.appendChild(E('p', { 'style': 'color:#888;padding:6px;' },
                        _('No generated scripts yet. Use Generate CLI in the Wizard.')));
                    return;
                }
                var t = E('table', { 'style': 'width:100%;border-collapse:collapse;font-size:0.9em;' });
                t.appendChild(E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' }, [
                    E('th', { 'style': 'padding:6px 8px;' }, _('Name')),
                    E('th', { 'style': 'padding:6px 8px;' }, _('Target')),
                    E('th', { 'style': 'padding:6px 8px;text-align:right;' }, _(''))
                ]));
                items.forEach(function(it) {
                    t.appendChild(E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.05);' }, [
                        E('td', { 'style': 'padding:6px 8px;font-family:monospace;' }, it.name),
                        E('td', { 'style': 'padding:6px 8px;' }, it.target || '—'),
                        E('td', { 'style': 'padding:6px 8px;text-align:right;' },
                            E('button', { 'class': 'btn cbi-button cbi-button-negative',
                                'style': 'padding:2px 10px;font-size:0.85em;',
                                'click': function() {
                                    if (!confirm(_('Delete generated script "' + it.name + '"?'))) return;
                                    self.callVlan('delete_generated', it.name).then(function() {
                                        loadGenerated();
                                    });
                                } }, _('Delete')))
                    ]));
                });
                genOut.appendChild(t);
            });
        }

        var saveBtn = E('button', { 'class': 'btn cbi-button',
            'style': 'padding:8px 18px;',
            'click': function() {
                var plan = window._vlanImportedPlan || window._vlanLoadedTemplate;
                if (!plan || !plan.vlans) {
                    ui.addNotification(null, E('p', {}, _('Build a plan in the Wizard or Import first.')), 'warning');
                    return;
                }
                var nameEl = E('input', { 'type': 'text', 'placeholder': 'template-name',
                    'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
                var targetSel = E('select', { 'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
                ['openwrt-dsa','openwrt-swconfig','mikrotik','cisco','edgeos','generic'].forEach(function(v) {
                    targetSel.appendChild(E('option', { 'value': v }, v));
                });
                var notesEl = E('input', { 'type': 'text',
                    'style': 'width:100%;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });

                var save = E('button', { 'class': 'btn cbi-button',
                    'style': 'background:#28a745 !important;background-color:#28a745 !important;color:#fff !important;padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;' }, _('Save'));
                save.addEventListener('click', function() {
                    if (!nameEl.value.trim()) { ui.addNotification(null, E('p', {}, 'Name required'), 'danger'); return; }
                    self.callVlan('save_template', nameEl.value.trim(), targetSel.value, JSON.stringify(plan), notesEl.value).then(function() {
                        ui.addNotification(null, E('p', {}, _('Template saved')), 'info');
                        document.querySelectorAll('.modal-overlay').forEach(function(m) {
                            if (m.parentNode) m.parentNode.removeChild(m);
                        });
                        document.body.classList.remove('modal-overlay-active');
                        loadTemplates();
                    });
                });

                ui.showModal(_('Save current plan as template'), [
                    E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Name')), nameEl]),
                    E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Target platform')), targetSel]),
                    E('div', { 'style': 'margin-bottom:10px;' }, [E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:4px;' }, _('Notes')), notesEl]),
                    E('div', { 'style': 'margin-top:14px;text-align:right;' }, [
                        E('button', { 'class': 'btn cbi-button', 'style': 'margin-right:8px;',
                            'click': function() {
                                document.querySelectorAll('.modal-overlay').forEach(function(m) {
                                    if (m.parentNode) m.parentNode.removeChild(m);
                                });
                                document.body.classList.remove('modal-overlay-active');
                            } }, _('Cancel')),
                        save
                    ])
                ]);
            }
        }, _('Save current plan as template'));

        loadTemplates();
        loadGenerated();

        return E('div', {}, [
            E('p', { 'style': 'color:#888;font-size:0.9em;' },
                _('Reusable VLAN schemes. Templates can be loaded back into the Wizard and applied on this or another router.')),
            E('div', { 'style': 'margin-bottom:14px;' }, [saveBtn]),
            card(_('Templates'), tplOut),
            card(_('Generated scripts'), genOut)
        ]);
    },

    // ---------- Safety ----------
    vlanRenderSafety: function() {
        var self = this;

        function card(title, body) {
            return E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:14px 16px;margin-bottom:16px;' },
                [E('h4', { 'style': 'margin:0 0 10px 0;font-size:1em;' }, title), body]);
        }

        var listOut = E('div');
        var pendingOut = E('div');

        function load() {
            pendingOut.innerHTML = '';
            listOut.innerHTML = '';
            self.callVlan('list_snapshots').then(function(r) {
                // Pending rollback warning
                if (r && r.pending) {
                    var dl = parseInt(r.pending, 10);
                    var now = Math.floor(Date.now() / 1000);
                    var left = dl - now;
                    if (left > 0) {
                        pendingOut.appendChild(E('div', {
                            'style': 'background:rgba(220,53,69,0.12);border:1px solid rgba(220,53,69,0.4);' +
                                     'border-radius:6px;padding:12px 16px;margin-bottom:14px;font-size:0.95em;'
                        }, [
                            E('strong', { 'style': 'color:#c00;' }, _('⚠️ Pending auto-rollback in ' + left + 's. ')),
                            _('Click Confirm to keep the changes, or do nothing to revert.'),
                            E('button', { 'class': 'btn cbi-button', 'style': 'margin-left:12px;padding:6px 16px;background:#28a745 !important;color:#fff !important;border:none;',
                                'click': function() {
                                    self.callVlan('confirm').then(function() {
                                        ui.addNotification(null, E('p', {}, _('Rollback cancelled.')), 'info');
                                        load();
                                    });
                                } }, _('Confirm'))
                        ]));
                    }
                }

                var items = (r && r.snapshots) || [];
                if (!items.length) {
                    listOut.appendChild(E('p', { 'style': 'color:#888;' }, _('No snapshots yet.')));
                    return;
                }
                var t = E('table', { 'style': 'width:100%;border-collapse:collapse;font-size:0.9em;' });
                t.appendChild(E('tr', { 'style': 'text-align:left;border-bottom:2px solid rgba(0,0,0,0.1);' }, [
                    E('th', { 'style': 'padding:6px 8px;' }, _('Timestamp')),
                    E('th', { 'style': 'padding:6px 8px;' }, _('Size')),
                    E('th', { 'style': 'padding:6px 8px;' }, _('Note')),
                    E('th', { 'style': 'padding:6px 8px;text-align:right;' }, _(''))
                ]));
                items.forEach(function(it) {
                    var fname = (it.path || '').split('/').pop();
                    t.appendChild(E('tr', { 'style': 'border-bottom:1px solid rgba(0,0,0,0.05);' }, [
                        E('td', { 'style': 'padding:6px 8px;font-family:monospace;' }, fname),
                        E('td', { 'style': 'padding:6px 8px;' }, (it.size || 0) + ' B'),
                        E('td', { 'style': 'padding:6px 8px;' }, it.note || '—'),
                        E('td', { 'style': 'padding:6px 8px;text-align:right;' },
                            E('button', { 'class': 'btn cbi-button cbi-button-action',
                                'style': 'padding:2px 12px;font-size:0.85em;',
                                'click': function() {
                                    if (!confirm(_('Restore from ' + fname + '?\n\nNetwork will reload.'))) return;
                                    self.callVlan('restore', it.path).then(function() {
                                        ui.addNotification(null, E('p', {}, _('Restored.')), 'info');
                                        setTimeout(function() { window.location.reload(); }, 1500);
                                    });
                                } }, _('Restore')))
                    ]));
                });
                listOut.appendChild(t);
            });
        }

        var snapBtn = E('button', { 'class': 'btn cbi-button cbi-button-action',
            'style': 'padding:8px 18px;',
            'click': function() {
                var note = prompt(_('Snapshot note (optional):'), 'manual');
                if (note === null) return;
                self.callVlan('snapshot', note || 'manual').then(function(r) {
                    if (r && r.path) {
                        ui.addNotification(null, E('p', {}, _('Snapshot saved: ') + r.path), 'info');
                        load();
                    }
                });
            } }, _('📸 Snapshot now'));

        load();

        return E('div', {}, [
            pendingOut,
            card(_('Snapshot / Restore'),
                E('div', {}, [
                    E('p', { 'style': 'color:#888;font-size:0.9em;' },
                        _('Every VLAN apply takes an automatic snapshot first. Restore if something goes wrong.')),
                    E('div', { 'style': 'margin-bottom:14px;' }, [snapBtn]),
                    listOut
                ]))
        ]);
    },

    // ---------- Diagnostics ----------
    vlanRenderDiagnostics: function() {
        var self = this;

        // Load kernel interfaces once, cache for both dropdowns.
        var kernelLoad = (self._vlanKernelIfaces ? Promise.resolve(self._vlanKernelIfaces) :
            self.callVlan('kernel_ifaces').then(function(r) {
                self._vlanKernelIfaces = (r && r.ifaces) || [];
                return self._vlanKernelIfaces;
            })).catch(function() { return []; });

        function card(title, body) {
            return E('div', { 'style': 'background:rgba(0,0,0,0.02);border:1px solid rgba(0,0,0,0.06);border-radius:8px;padding:14px 16px;margin-bottom:16px;' },
                [E('h4', { 'style': 'margin:0 0 10px 0;font-size:1em;' }, title), body]);
        }

        // Bridge VLAN show
        var bvOut = E('pre', { 'style': 'background:#111;color:#0f0;padding:12px;border-radius:4px;font-size:0.85em;white-space:pre-wrap;max-height:400px;overflow:auto;margin:0;' }, _('(not loaded)'));
        var bvBtn = E('button', { 'class': 'btn cbi-button', 'style': 'padding:6px 14px;',
            'click': function() {
                bvOut.textContent = _('Loading...');
                self.callVlan('bridge_vlan_show').then(function(r) {
                    bvOut.textContent = (r && r.output) || '(empty)';
                });
            } }, _('Load bridge vlan show'));

        // iface stats — kernel device dropdown
        var ifSel = E('select', { 'style': 'width:100%;max-width:400px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
        kernelLoad.then(function(ifs) {
            ifSel.innerHTML = '';
            ifs.forEach(function(i) {
                var label = i.name + (i.up ? ' (up)' : '');
                ifSel.appendChild(E('option', { 'value': i.name }, label));
            });
            if (!ifs.length) ifSel.appendChild(E('option', { 'value': '' }, 'no interfaces'));
        });
        var statOut = E('pre', { 'style': 'background:#111;color:#0f0;padding:12px;border-radius:4px;font-size:0.85em;white-space:pre-wrap;margin:10px 0 0 0;' }, '');
        var statBtn = E('button', { 'class': 'btn cbi-button', 'style': 'padding:6px 14px;',
            'click': function() {
                var dev = ifSel.value;
                if (!dev) { statOut.textContent = 'No interface selected.'; return; }
                statOut.textContent = 'Loading...';
                self.callVlan('iface_stats', dev).then(function(r) {
                    statOut.textContent = JSON.stringify(r, null, 2);
                });
            } }, _('Show stats'));

        // cross-vlan ping
        var srcSel = E('select', { 'style': 'width:100%;max-width:300px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
        kernelLoad.then(function(ifs) {
            srcSel.innerHTML = '';
            // Filter to useful ping sources: bridges, pppoe, physical
            var preferred = ifs.filter(function(i) {
                var n = i.name;
                return /^br-/.test(n) || /^pppoe-/.test(n) ||
                       /^eth[0-9]/.test(n) || /^usb[0-9]/.test(n) ||
                       n === 'tailscale0' || /^lan[0-9]/.test(n);
            });
            var list = preferred.length ? preferred : ifs;
            list.forEach(function(i) {
                var label = i.name + (i.up ? ' (up)' : '');
                srcSel.appendChild(E('option', { 'value': i.name }, label));
            });
            if (!list.length) srcSel.appendChild(E('option', { 'value': '' }, 'no interfaces'));
        });
        var ipEl = E('input', { 'type': 'text', 'placeholder': '8.8.8.8',
            'style': 'width:100%;max-width:300px;padding:6px 10px;border:1px solid #ccc;border-radius:4px;' });
        var pingOut = E('pre', { 'style': 'background:#111;color:#0f0;padding:12px;border-radius:4px;font-size:0.85em;white-space:pre-wrap;margin:10px 0 0 0;' }, '');
        var pingBtn = E('button', { 'class': 'btn cbi-button', 'style': 'padding:6px 14px;',
            'click': function() {
                var iface = srcSel.value;
                var ip = ipEl.value.trim();
                if (!iface) { pingOut.textContent = 'No interface selected.'; return; }
                if (!ip) { pingOut.textContent = 'Enter a target IP or host.'; return; }
                pingOut.textContent = 'Pinging ' + ip + ' through ' + iface + '...';
                self.callVlan('ping_test', iface, ip).then(function(r) {
                    var out = (r && r.output) ? r.output : '';
                    var rc = (r && r.exit_code != null) ? r.exit_code : '?';
                    if (!out) {
                        out = 'No output. Command: ping -I ' + iface + ' -c 3 -W 3 ' + ip + '\n' +
                              'Exit code: ' + rc + '\n\n' +
                              'Common causes:\n' +
                              '- Interface has no route to target\n' +
                              '- Interface is down\n' +
                              '- Wrong device (use pppoe-wan for PPPoE WAN, not eth1)';
                    } else {
                        out = 'Exit code: ' + rc + '\n' + out;
                    }
                    pingOut.textContent = out;
                });
            } }, _('Run ping'));

        return E('div', {}, [
            E('p', { 'style': 'color:#888;font-size:0.9em;' },
                _('Diagnostics tools. Load on demand — nothing runs in the background.')),
            card(_('Bridge VLAN table'), E('div', {}, [bvBtn, E('div', { 'style': 'margin-top:10px;' }, [bvOut])])),
            card(_('Interface stats'), E('div', {}, [ifSel, E('div', { 'style': 'margin-top:10px;' }, [statBtn]), statOut])),
            card(_('Cross-VLAN ping'), E('div', {}, [
                E('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap;align-items:center;' }, [srcSel, ipEl]),
                E('div', { 'style': 'margin-top:10px;' }, [pingBtn]),
                pingOut
            ]))
        ]);
    },

    renderFailover: function() {
        var self = this;

        var rpcStatus = rpc.declare({
            object: 'luci.quickactions-failover', method: 'status', expect: { '': {} }
        });
        var rpcInterfaces = rpc.declare({
            object: 'luci.quickactions-failover', method: 'interfaces', expect: { '': {} }
        });
        var rpcAction = rpc.declare({
            object: 'luci.quickactions-failover', method: 'action',
            params: ['action'], expect: { '': {} }
        });

        function cfg(k, d) {
            var v = uci.get('quickactions', 'failover', k);
            return (v == null || v === '') ? d : v;
        }

        // ---- Status bar ----
        var statusLabel = E('span', {
            'style': 'font-weight:bold;padding:6px 12px;border-radius:4px;background:rgba(0,0,0,0.1);display:inline-block;'
        }, '...');

        function refreshStatus() {
            return rpcStatus().then(function(r) {
                var on = String(r.enabled) === '1';
                var backup = String(r.on_backup) === '1';
                statusLabel.textContent = 'STATUS: ' + (on ? 'ON' : 'OFF') +
                    '   ·   MODE: ' + (backup ? 'BACKUP' : 'PRIMARY');
                statusLabel.style.background = on
                    ? (backup ? 'rgba(255,193,7,0.25)' : 'rgba(40,167,69,0.2)')
                    : 'rgba(220,53,69,0.2)';
                var log = document.getElementById('qa-fo-lastlog');
                if (log) log.textContent = r.last_log || '(no recent log)';
            }).catch(function() {});
        }

        // ---- Action buttons ----
        function doAction(action, msg) {
            if (!confirm(msg)) return;
            rpcAction(action).then(function(r) {
                ui.addNotification(null, E('pre', {
                    'style': 'margin:0;white-space:pre-wrap;font-size:0.85em;'
                }, (r && r.output) || '(done)'), 'info');
                refreshStatus();
            }).catch(function(err) {
                ui.addNotification(null, E('p', {}, 'Failed: ' + (err.message || err)), 'danger');
            });
        }

        var controlBar = E('div', {
            'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin-bottom:18px;' }, [
            statusLabel,
            E('button', { 'class': 'btn cbi-button',
                'style': 'background-color:#28a745 !important;background:#28a745 !important;color:#fff !important;padding:8px 18px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;',
                'click': function() { doAction('on',  'Enable failover cron + hotplug?'); } }, _('Enable')),
            E('button', { 'class': 'btn cbi-button',
                'style': 'background-color:#dc3545 !important;background:#dc3545 !important;color:#fff !important;padding:8px 18px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;',
                'click': function() { doAction('off', 'Disable failover cron + hotplug?'); } }, _('Disable')),
            E('button', { 'class': 'btn cbi-button',
                'click': function() {
                    ui.addNotification(null, E('p', {}, 'Running watchdog manually...'), 'info');
                    rpcAction('test').then(function(r) {
                        ui.addNotification(null, E('pre', {
                            'style': 'margin:0;white-space:pre-wrap;font-size:0.85em;'
                        }, (r && r.output) || '(no output)'), 'info');
                        refreshStatus();
                    });
                } }, _('Run watchdog')),
            E('button', { 'class': 'btn cbi-button', 'click': refreshStatus }, _('Refresh'))
        ]);

        // ---- Interface dropdowns ----
        var primSel = E('select', {
            'style': 'width:100%;max-width:440px;padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;' });

        var backSel = E('select', {
            'multiple': true, 'size': 8,
            'style': 'width:100%;max-width:440px;padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;' });

        var curPrim = cfg('primary', 'wan');
        var curBackups = (cfg('backups', '') || '').split(/\s+/).filter(Boolean);

        rpcInterfaces().then(function(r) {
            var raw = (r && r.interfaces) ? String(r.interfaces).trim() : '';
            var list = raw ? raw.split(/\s+/) : [];
            list.forEach(function(n) {
                if (!n) return;
                var o1 = E('option', { 'value': n }, n);
                if (n === curPrim) o1.selected = true;
                primSel.appendChild(o1);

                var o2 = E('option', { 'value': n }, n);
                if (curBackups.indexOf(n) !== -1) o2.selected = true;
                backSel.appendChild(o2);
            });
        }).catch(function(err) {
            ui.addNotification(null, E('p', {}, 'Interface list failed: ' + (err.message || err)), 'warning');
        });

        function fieldRow(label, el, hint) {
            return E('div', { 'style': 'margin-bottom:14px;' }, [
                E('label', { 'style': 'display:block;font-size:0.9em;color:#666;margin-bottom:5px;font-weight:500;' }, label),
                el,
                hint ? E('div', { 'style': 'font-size:0.8em;color:#888;margin-top:4px;' }, hint) : null
            ]);
        }

        function textField(key, dflt, hint) {
            return fieldRow(_(key), E('input', {
                'type': 'text', 'id': 'qa-fo-' + key,
                'value': cfg(key, dflt),
                'style': 'width:100%;max-width:440px;padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-size:0.95em;box-sizing:border-box;'
            }), hint);
        }

        function checkboxRow(key, dflt, label, hint) {
            var cb = E('input', { 'type': 'checkbox', 'id': 'qa-fo-' + key });
            if (cfg(key, dflt) === '1') cb.checked = true;
            return E('div', { 'style': 'margin-bottom:12px;display:flex;align-items:flex-start;gap:10px;' }, [
                cb,
                E('div', {}, [
                    E('label', { 'style': 'font-size:0.95em;font-weight:500;' }, label),
                    hint ? E('div', { 'style': 'font-size:0.8em;color:#888;margin-top:2px;' }, hint) : null
                ])
            ]);
        }

        var formGrid = E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px;' }, [
            textField('check_ips', '1.1.1.1 8.8.8.8',
                _('Space-separated. Pings go out through the primary interface.')),
            textField('check_interval', '60',
                _('Seconds between cron runs.')),
            textField('ping_timeout', '5',
                _('Per-ping timeout in seconds.')),
            textField('fail_threshold', '2',
                _('Consecutive failures before failover.')),
            textField('recover_threshold', '1',
                _('Consecutive successes before switching back.'))
        ]);

        var checkboxes = E('div', { 'style': 'margin-top:16px;' }, [
            checkboxRow('tailscale_restart', '0',
                _('Restart Tailscale on failover and recovery'),
                _('Fixes stuck tailscale0 routes when the WAN IP changes.')),
            checkboxRow('firewall_reset', '1',
                _('Reset firewall on failover'),
                _('Prevents the "LAN access lost" bug on some OpenWrt forks.')),
            checkboxRow('log_healthy', '0',
                _('Log every healthy check'),
                _('Generates ~1440 log lines per day. Leave off unless debugging.'))
        ]);

        function gather() {
            var backups = [];
            for (var i = 0; i < backSel.options.length; i++)
                if (backSel.options[i].selected) backups.push(backSel.options[i].value);

            uci.set('quickactions', 'failover', 'primary', primSel.value);
            uci.set('quickactions', 'failover', 'backups', backups.join(' '));
            ['check_ips', 'check_interval', 'ping_timeout',
             'fail_threshold', 'recover_threshold'].forEach(function(k) {
                var el = document.getElementById('qa-fo-' + k);
                if (el) uci.set('quickactions', 'failover', k, el.value);
            });
            ['tailscale_restart', 'firewall_reset', 'log_healthy'].forEach(function(k) {
                var el = document.getElementById('qa-fo-' + k);
                if (el) uci.set('quickactions', 'failover', k, el.checked ? '1' : '0');
            });
            return uci.save();
        }

        var actionBar = E('div', { 'style': 'margin-top:22px;padding-top:16px;border-top:1px solid rgba(0,0,0,0.08);display:flex;gap:10px;justify-content:flex-end;flex-wrap:wrap;' }, [
            E('button', {
                'class': 'btn cbi-button',
                'style': 'background-color:#6c757d !important;background:#6c757d !important;color:#fff !important;padding:8px 18px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;',
                'click': function() {
                    if (confirm('Discard form changes?')) self.switchTab('failover');
                } }, _('Reset')),
            E('button', {
                'class': 'btn cbi-button',
                'style': 'background-color:#17a2b8 !important;background:#17a2b8 !important;color:#fff !important;padding:8px 18px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;',
                'click': function() {
                    gather().then(function() {
                        ui.addNotification(null, E('p', {}, 'Saved to memory. Use Save & Apply to commit.'), 'info');
                        self.refreshPendingCount();
                    }).catch(function(err) {
                        ui.addNotification(null, E('p', {}, 'Save failed: ' + (err.message || err)), 'danger');
                    });
                } }, _('Save')),
            E('button', {
                'class': 'btn cbi-button',
                'style': 'background-color:#28a745 !important;background:#28a745 !important;color:#fff !important;padding:8px 20px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;',
                'click': function() {
                    gather().then(function() {
                        return ui.changes.apply(false);
                    }).then(function() {
                        ui.addNotification(null, E('p', {}, 'Saved and applied.'), 'info');
                        self.refreshPendingCount();
                        refreshStatus();
                    }).catch(function(err) {
                        var m = (err && err.message) ? err.message : String(err);
                        if (/No data|code 5/i.test(m)) return;
                        ui.addNotification(null, E('p', {}, 'Apply failed: ' + m), 'danger');
                    });
                } }, _('Save & Apply'))
        ]);

        var infoBar = E('div', {
            'style': 'background:rgba(30,144,255,0.08);border:1px solid rgba(30,144,255,0.2);border-radius:6px;padding:12px 16px;margin-bottom:18px;font-size:0.9em;line-height:1.55;' }, [
            E('strong', {}, _('Failover — lightweight mwan3 alternative. ')),
            _('Cron-driven ping tests run once per minute through the primary interface. ' +
              'On repeated failure, the conntrack table is flushed so the kernel falls back to the backup ' +
              'with the lowest route metric. Zero background RAM when idle — a single ping run per minute.')
        ]);

        var logBox = E('pre', {
            'id': 'qa-fo-lastlog',
            'style': 'background:#111;color:#0f0;padding:10px 12px;border-radius:4px;font-size:0.85em;' +
                     'white-space:pre-wrap;word-break:break-all;max-height:100px;overflow:auto;margin:0;'
        }, _('(no recent log)'));

        refreshStatus();
        if (self._failoverTimer) clearInterval(self._failoverTimer);
        self._failoverTimer = setInterval(refreshStatus, 8000);

        return E('div', {}, [
            E('h3', { 'style': 'margin-top:0;' }, _('WAN Failover')),
            infoBar,
            controlBar,
            E('h4', { 'style': 'margin:22px 0 12px 0;' }, _('Interfaces')),
            fieldRow(_('Primary (fastest) interface'), primSel,
                _('Traffic uses this interface whenever it is healthy.')),
            fieldRow(_('Backup interfaces (multi-select)'), backSel,
                _('Traffic switches to whichever backup is up with the lowest route metric.')),
            E('h4', { 'style': 'margin:22px 0 12px 0;' }, _('Health check')),
            formGrid,
            E('h4', { 'style': 'margin:22px 0 12px 0;' }, _('Options')),
            checkboxes,
            actionBar,
            E('h4', { 'style': 'margin:22px 0 12px 0;' }, _('Last log line')),
            logBox
        ]);
    },

    wirelessQuickEdit: function(sid) {
        var self = this;
        var dev = uci.get('wireless', sid, 'device') || '';
        var ssid = uci.get('wireless', sid, 'ssid') || '';
        var enc = uci.get('wireless', sid, 'encryption') || 'psk2';
        var key = uci.get('wireless', sid, 'key') || uci.get('wireless', sid, 'key1') || '';
        var net = uci.get('wireless', sid, 'network') || '';
        var disabled = uci.get('wireless', sid, 'disabled') === '1';

        var ssidEl = E('input', { 'type':'text', 'value': ssid,
            'style':'width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;' });
        var encSel = E('select', { 'style':'width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;' });
        [['psk2','WPA2-PSK'],['sae','WPA3-SAE'],['sae-mixed','WPA2/WPA3 mixed'],
         ['psk-mixed','WPA/WPA2 mixed'],['psk','WPA-PSK'],
         ['owe','OWE (enhanced open)'],['none','Open']]
            .forEach(function(o) {
                var opt = E('option', { 'value': o[0] }, o[1]);
                if (o[0] === enc) opt.selected = true;
                encSel.appendChild(opt);
            });
        var keyEl = E('input', { 'type':'text', 'value': key,
            'style':'width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:4px;font-family:monospace;box-sizing:border-box;' });

        var netSel = E('select', { 'style':'width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;' });
        var netOpts = (uci.sections('network', 'interface') || []).map(function(s) { return s['.name']; });
        if (netOpts.indexOf(net) === -1 && net) netOpts.push(net);
        netOpts.sort();
        netOpts.forEach(function(n) {
            var opt = E('option', { 'value': n }, n);
            if (n === net) opt.selected = true;
            netSel.appendChild(opt);
        });

        var disEl = E('input', { 'type':'checkbox' });
        if (!disabled) disEl.checked = true;

        var body = E('div', {}, [
            E('div', { 'style':'margin-bottom:12px;' }, [
                E('label', { 'style':'display:block;font-size:0.9em;color:#666;margin-bottom:5px;font-weight:500;' }, _('SSID')),
                ssidEl
            ]),
            E('div', { 'style':'margin-bottom:12px;' }, [
                E('label', { 'style':'display:block;font-size:0.9em;color:#666;margin-bottom:5px;font-weight:500;' }, _('Security')),
                encSel
            ]),
            E('div', { 'style':'margin-bottom:12px;' }, [
                E('label', { 'style':'display:block;font-size:0.9em;color:#666;margin-bottom:5px;font-weight:500;' }, _('Password')),
                keyEl
            ]),
            E('div', { 'style':'margin-bottom:12px;' }, [
                E('label', { 'style':'display:block;font-size:0.9em;color:#666;margin-bottom:5px;font-weight:500;' }, _('Network interface')),
                netSel
            ]),
            E('div', { 'style':'margin-bottom:12px;display:flex;align-items:center;gap:10px;' }, [
                disEl, E('label', { 'style':'font-size:0.95em;' }, _('Enabled'))
            ]),
            E('div', { 'style':'font-size:0.82em;color:#888;' }, _('Device: ') + dev)
        ]);

        function gather() {
            uci.set('wireless', sid, 'ssid', ssidEl.value);
            uci.set('wireless', sid, 'encryption', encSel.value);
            if (encSel.value === 'none' || encSel.value === 'owe') {
                uci.unset('wireless', sid, 'key');
                uci.unset('wireless', sid, 'key1');
            } else {
                uci.set('wireless', sid, 'key', keyEl.value);
            }
            uci.set('wireless', sid, 'network', netSel.value);
            uci.set('wireless', sid, 'disabled', disEl.checked ? '0' : '1');

            // If this iface carries a guest_owner tag, mirror the changes
            // into the corresponding guestwifi.@guest[X] section so the
            // Guest WiFi tab also reflects them.
            var owner = uci.get('wireless', sid, 'guest_owner');
            if (owner) {
                var match = (uci.sections('guestwifi', 'guest') || []).filter(function(g) {
                    return g['.name'] === owner;
                })[0];
                if (match) {
                    uci.set('guestwifi', owner, 'ssid', ssidEl.value);
                    uci.set('guestwifi', owner, 'encryption', encSel.value);
                    if (encSel.value !== 'none' && encSel.value !== 'owe') {
                        uci.set('guestwifi', owner, 'password', keyEl.value);
                    }
                    // Mirror the enable/disable state as well. Guest tab
                    // reads guestwifi.*.enable, so without this the toggle
                    // wouldn't reflect back.
                    uci.set('guestwifi', owner, 'enable', disEl.checked ? '1' : '0');
                }
            }
        }

        function closeModal() {
            document.querySelectorAll('.modal-overlay').forEach(function(m) {
                if (m.parentNode) m.parentNode.removeChild(m);
            });
            document.body.classList.remove('modal-overlay-active');
        }

        var cancelBtn = E('button', {
            'class': 'btn cbi-button',
            'style': 'margin-right:8px;padding:8px 20px;'
        }, _('Cancel'));
        cancelBtn.addEventListener('click', closeModal);

        var saveBtn = E('button', {
            'class': 'btn cbi-button',
            'style': 'background-color:#17a2b8 !important;background:#17a2b8 !important;color:#fff !important;padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;margin-right:8px;'
        }, _('Save'));
        saveBtn.addEventListener('click', function() {
            gather();
            uci.save().then(function() {
                closeModal();
                self.refreshPendingCount();
                try { window.scrollTo({ top: 0, behavior: 'smooth' }); } catch(e) { window.scrollTo(0, 0); }
                ui.addNotification(null,
                    E('p', {}, _('Saved. Scroll to the top of the page and click "Save & Apply" to commit.')),
                    'info');
            }).catch(function(err) {
                ui.addNotification(null, E('p', {}, 'Save failed: ' + (err.message||err)), 'danger');
            });
        });

        var applyBtn = E('button', {
            'class': 'btn cbi-button',
            'style': 'background-color:#28a745 !important;background:#28a745 !important;color:#fff !important;padding:8px 22px;font-weight:bold;border:none;border-radius:4px;cursor:pointer;'
        }, _('Save & Apply'));
        applyBtn.addEventListener('click', function() {
            gather();
            var applyRpc = rpc.declare({
                object: 'uci', method: 'apply',
                params: ['rollback'], expect: { '': {} }
            });
            uci.save().then(function() {
                // Raw rpc uci/apply — the LuCI wrapper ui.changes.apply()
                // reloads the current view after applying, which resets the
                // tab hash and drops us back on the Dashboard.
                return applyRpc(0);
            }).then(function() {
                closeModal();
                ui.addNotification(null,
                    E('p', {}, _('Wireless saved and applied. Reloading...')),
                    'info');
                // Reload the page. This clears LuCI's stale change counter
                // (the tracker lives in browser memory) and gives the Guest
                // WiFi iframe a fresh load so it picks up the new config.
                setTimeout(function() {
                    window.location.reload();
                }, 900);
            }).catch(function(err) {
                var m = (err && err.message) ? err.message : String(err);
                if (/No data|code 5/i.test(m)) {
                    closeModal();
                    return;
                }
                ui.addNotification(null, E('p', {}, 'Apply failed: ' + m), 'danger');
            });
        });

        ui.showModal(_('Edit wireless: ' + (ssid || sid)), [
            body,
            E('div', { 'style':'margin-top:16px;text-align:right;' }, [cancelBtn, saveBtn, applyBtn])
        ]);
    },

    renderConfigForm: function() {
        var self = this;
        var m = new form.Map('quickactions', 'Quick Actions Configuration', 'Manage all sections. Use Order field to control sequence (lower = first).');
        var s = m.section(form.NamedSection, 'global', 'settings', 'Global Settings');
        s.anonymous = true;
        var o = s.option(form.Value, 'poll_interval', 'Polling Interval (seconds)');
        o.datatype = 'integer'; o.placeholder = '5';
        o = s.option(form.ListValue, 'design_style', 'Button Style');
        o.value('flat', 'Modern Flat'); o.value('3d', 'Tactile 3D'); o.default = '3d';

        var s2 = m.section(form.GridSection, 'essential', 'Essential Buttons', 'Reorder field controls display order.');
        s2.anonymous = true; s2.addremove = true;
        o = s2.option(form.Value, 'order', 'Order'); o.datatype = 'integer'; o.placeholder = '10';
        s2.option(form.Value, 'label', 'Label');
        o = s2.option(form.Value, 'icon', 'Icon / Emoji'); o.placeholder = '🔄';
        o = s2.option(form.Value, 'command', 'Shell Command'); o.placeholder = '/sbin/reboot';
        s2.option(form.Flag, 'confirm', 'Require Confirmation');

        var s3 = m.section(form.GridSection, 'mapping', 'Service Mappings', 'Map keywords to init services.');
        s3.anonymous = true; s3.addremove = true;
        o = s3.option(form.Value, 'order', 'Order'); o.datatype = 'integer';
        s3.option(form.Value, 'keyword', 'Label Keyword');
        s3.option(form.Value, 'service', 'Target Service');
        o = s3.option(form.Value, 'icon', 'Icon / Emoji'); o.placeholder = '⚙️';
        s3.option(form.Flag, 'dangerous', 'Require Confirmation');

        var s4 = m.section(form.GridSection, 'shortcut', 'Navigation Shortcuts', 'Buttons that jump to other LuCI pages.');
        s4.anonymous = true; s4.addremove = true;
        o = s4.option(form.Value, 'order', 'Order'); o.datatype = 'integer';
        s4.option(form.Value, 'label', 'Label');
        o = s4.option(form.Value, 'icon', 'Icon / Emoji'); o.placeholder = '🔗';
        o = s4.option(form.Value, 'path', 'LuCI Path'); o.placeholder = 'admin/network/firewall';

        self.configMap = m;
        return m.render();
    },

    render: function(data) {
        var self = this;

        // Embedded mode — ?embed=guestwifi renders only the guest wifi form (no outer tabs)
        var embedParam = '';
        try { embedParam = new URLSearchParams(window.location.search).get('embed') || ''; } catch(e) {}

        if (embedParam === 'guestwifi') {
            // Walk the parent document and un-cap max-width on every
            // ancestor of this iframe. The theme (Argon) sets
            // .container{max-width:940px}, and injecting a <style> into
            // the parent loses to theme CSS that loads after us. Inline
            // !important on the actual DOM nodes always wins.
            try {
                var pd2 = window.parent && window.parent.document;
                if (pd2) {
                    var iframeEl = pd2.getElementById('qa-guestwifi-iframe');
                    var anc = iframeEl ? iframeEl.parentNode : null;
                    while (anc && anc.tagName && anc.tagName !== 'BODY') {
                        try {
                            anc.style.setProperty('max-width', 'none', 'important');
                            anc.style.setProperty('width', '100%', 'important');
                        } catch(e) {}
                        anc = anc.parentNode;
                    }
                }
            } catch(e) {}
            // Walk the parent document and un-cap max-width on every
            // ancestor of this iframe. Runs on a 1s interval so if
            // LuCI re-renders its view container (which re-applies
            // the theme's .container{max-width:940px} rule), we snap
            // it back to full width.
            function qaUncapAncestors() {
                try {
                    var pd2 = window.parent && window.parent.document;
                    if (!pd2) return;
                    var iframeEl = pd2.getElementById('qa-guestwifi-iframe');
                    if (!iframeEl) return;
                    iframeEl.style.setProperty('width', '100%', 'important');
                    iframeEl.style.setProperty('max-width', 'none', 'important');
                    var anc = iframeEl.parentNode;
                    while (anc && anc.tagName && anc.tagName !== 'BODY') {
                        try {
                            anc.style.setProperty('max-width', 'none', 'important');
                            anc.style.setProperty('width', '100%', 'important');
                        } catch(e) {}
                        anc = anc.parentNode;
                    }
                } catch(e) {}
            }
            qaUncapAncestors();
            if (!window._qaUncapTimer) {
                window._qaUncapTimer = setInterval(qaUncapAncestors, 1000);
            }
            var gw = new GuestWifiViewClass();
            self.embedGuestWifi = gw;
            return Promise.resolve(gw.load()).then(function() {
                return gw.render();
            }).catch(function(err) {
                return E('div', { 'class': 'alert-message error', 'style': 'padding:20px;' }, 'Guest WiFi form error: ' + (err && err.message ? err.message : String(err)));
            });
        }

        var cmds = data[0] || [];
        var initList = data[1] || {};
        var tabBar = E('div', { 'style': 'display:flex;gap:2px;border-bottom:2px solid rgba(0,0,0,0.08);margin:0 0 20px 0;flex-wrap:wrap;' });
        var tabContent = E('div');
        var tabButtons = {};
        var tabs = [
            { id: 'dashboard', label: 'Dashboard' },
            { id: 'essential', label: 'Essential' },
            { id: 'tools', label: 'Tools' },
            { id: 'logs', label: 'Logs' },
            { id: 'services', label: 'Services' },
            { id: 'hotplug', label: 'Hotplug' },
            { id: 'crontab', label: 'Crontab' },
            { id: 'guestwifi', label: 'Guest WiFi' },
            { id: 'ttyd', label: 'Terminal' },
            { id: 'taskplan', label: 'Task Plan' },
            { id: 'netwizard', label: 'Network Setup' },
            { id: 'command', label: 'Command' },
            { id: 'dependencies', label: 'Dependencies' },
            { id: 'scripts', label: 'Scripts' },
            { id: 'vlan', label: 'VLAN' },
            { id: 'failover', label: 'Failover' },
            { id: 'config', label: 'Configuration' }
        ];
        function showTab(id) {
            self.activeTab = id;
            try {
                if (window.location.hash !== '#' + id) {
                    // Prefer replaceState (no hashchange event, no LuCI re-dispatch)
                    if (window.history && window.history.replaceState) {
                        window.history.replaceState(null, '', '#' + id);
                    } else {
                        // Fallback: direct hash assignment (fires hashchange — guarded below)
                        window.location.hash = id;
                    }
                    // Verify write succeeded (some themes/dispatchers strip the hash)
                    setTimeout(function() {
                        if (window.location.hash !== '#' + id) {
                            try { window.location.hash = id; } catch(e) {}
                        }
                    }, 50);
                }
            } catch(e) {}
            Object.keys(tabButtons).forEach(function(tid) {
                var b = tabButtons[tid];
                if (tid === id) { b.style.borderBottomColor = '#1e90ff'; b.style.color = '#1e90ff'; b.style.fontWeight = 'bold'; }
                else { b.style.borderBottomColor = 'transparent'; b.style.color = '#666'; b.style.fontWeight = '500'; }
            });
            tabContent.innerHTML = '';
            self.hideLuCIPageActions();
            if (id === 'dashboard') tabContent.appendChild(self.renderDashboard(cmds, initList));
            else if (id === 'essential') tabContent.appendChild(self.renderEssential());
            else if (id === 'tools') tabContent.appendChild(self.renderTools());
            else if (id === 'logs') tabContent.appendChild(self.renderLogs());
            else if (id === 'services') tabContent.appendChild(self.renderServices());
            else if (id === 'hotplug') {
                tabContent.appendChild(E('p', { 'style': 'color:#888;padding:20px;' }, 'Loading hotplug form...'));
                Promise.resolve(self.renderHotplug()).then(function(node) { tabContent.innerHTML = ''; tabContent.appendChild(node); })
                    .catch(function(err) { tabContent.innerHTML = ''; tabContent.appendChild(E('div', { 'class': 'alert-message error' }, 'Hotplug error: ' + (err && err.message ? err.message : String(err)))); });
            }
            else if (id === 'crontab') tabContent.appendChild(self.renderCrontabWizard());
            else if (id === 'guestwifi') {
                // Guest WiFi's form.Map hijacks #view when rendered inline. Isolate it in an iframe.
                var baseUrl = window.location.pathname;
                // Cache-bust so the iframe always reloads its config from disk
                var iframeUrl = baseUrl + (baseUrl.indexOf('?') >= 0 ? '&' : '?')
                    + 'embed=guestwifi&_t=' + Date.now();
                var infoBar = E('div', { 'style': 'background:rgba(30,144,255,0.08);border:1px solid rgba(30,144,255,0.2);border-radius:8px;padding:10px 12px;margin-bottom:12px;font-size:0.85em;display:flex;align-items:center;gap:12px;flex-wrap:wrap;' }, [
                    E('span', { 'style': 'flex:1;' }, 'Guest WiFi runs in an isolated frame so this tab bar stays visible. Save & Apply works normally inside the frame.'),
                    E('a', { 'href': iframeUrl, 'target': '_blank', 'style': 'color:#1e90ff;font-weight:bold;' }, 'Open in new tab ↗'),
                    E('button', { 'class': 'btn cbi-button', 'style': 'padding:2px 10px;font-size:0.85em;', 'click': function() {
                        var f = document.getElementById('qa-guestwifi-iframe');
                        if (f) { var s = f.src; f.src = 'about:blank'; setTimeout(function(){ f.src = s; }, 50); }
                    } }, '↻ Reload')
                ]);
                var ifr = document.createElement('iframe');
                ifr.id = 'qa-guestwifi-iframe';
                ifr.style.cssText = 'width:100%;height:400px;min-height:200px;max-height:calc(100vh - 140px);display:block;border:1px solid rgba(0,0,0,0.1);border-radius:6px;background:transparent;overflow:hidden;';

                function stripEmbedChrome() {
                    var f = document.getElementById('qa-guestwifi-iframe');
                    if (!f) return;
                    try {
                        var doc = f.contentDocument;
                        if (!doc || !doc.body) return;

                        // 1. Inject generic "hide chrome" CSS
                        if (!doc.getElementById('qa-embed-css')) {
                            var s = doc.createElement('style');
                            s.id = 'qa-embed-css';
                            s.textContent = [
                                'html, body { padding: 0 !important; margin: 0 !important; }',
                                'body > header, body > nav, body > aside, body > footer { display: none !important; }',
                                'header, nav, aside, #header, #mainmenu, #menubar, #sidebar, .header, .main-menu, .sidebar, .navigation, .navbar { display: none !important; visibility: hidden !important; height: 0 !important; overflow: hidden !important; }',
                                '.main-left, .main-left * { display: none !important; }',
                                '.main { padding-top: 0 !important; margin-top: 0 !important; top: 0 !important; }',
                                '.main-right { margin-left: 0 !important; padding: 0 !important; }',
                                '#maincontent, #view, .cbi-map { padding-top: 0 !important; margin-top: 0 !important; }',
                                'body { overflow-x: hidden; }',
                                'a[href*="logout"], .logout, .main-right .logout { display: none !important; }',
                                'footer, .footer, .fs-footer, #footer, [role="contentinfo"] { display: none !important; visibility: hidden !important; height: 0 !important; overflow: hidden !important; padding: 0 !important; margin: 0 !important; }'
                            ].join('\n');
                            doc.head.appendChild(s);
                        }

                        // 2. DOM-walk: hide every sibling on the path from target up to body
                        var target = doc.querySelector('#maincontent')
                            || doc.querySelector('#view')
                            || doc.querySelector('.cbi-map')
                            || doc.querySelector('.main-right')
                            || doc.querySelector('.main');
                        if (!target) return;

                        var el = target;
                        while (el && el.parentNode && el.parentNode !== doc.documentElement) {
                            var parent = el.parentNode;
                            var kids = parent.children;
                            for (var i = 0; i < kids.length; i++) {
                                var k = kids[i];
                                if (k === el) continue;
                                if (k.tagName === 'SCRIPT' || k.tagName === 'STYLE' || k.tagName === 'LINK') continue;
                                var kid = (k.id || '') + ' ' + (k.className || '');
                                if (/modal|overlay|notification|alert|dialog|spinning|popup|tooltip/i.test(kid)) continue;
                                k.style.display = 'none';
                            }
                            if (parent === doc.body) break;
                            el = parent;
                        }

                        // 3. Explicitly show the target chain
                        var showChain = target;
                        while (showChain && showChain !== doc.documentElement) {
                            showChain.style.display = '';
                            showChain.style.visibility = '';
                            showChain = showChain.parentNode;
                        }
                    } catch(e) { /* cross-origin, ignore */ }
                }

                function autoSizeIframe() {
                    try {
                        var f = document.getElementById('qa-guestwifi-iframe');
                        if (!f) return;
                        var d = f.contentDocument;
                        if (!d || !d.body) return;
                        // Reset to a small height first so we can measure natural content height
                        f.style.height = '100px';
                        var h = Math.max(
                            d.body.scrollHeight,
                            d.documentElement ? d.documentElement.scrollHeight : 0,
                            400
                        );
                        f.style.height = (h + 8) + 'px';
                    } catch(e) {}
                }

                ifr.addEventListener('load', function() {
                    stripEmbedChrome();

                    // Hide the parent page footer once (outer LuCI layout "Powered by" line)
                    try {
                        if (!window._qaParentFooterHidden) {
                            window._qaParentFooterHidden = true;
                            var pfs = document.querySelectorAll('footer, .fs-footer, #footer, [role="contentinfo"]');
                            for (var pi = 0; pi < pfs.length; pi++) {
                                if (!pfs[pi].closest('#qa-guestwifi-iframe')) {
                                    pfs[pi].setAttribute('data-qa-hidden', '1');
                                    pfs[pi].style.setProperty('display', 'none', 'important');
                                }
                            }
                        }
                    } catch(e) {}

                    // Guest WiFi form is rendered inside the iframe with its own
                    // LuCI page-actions. Make sure they are visible inside the iframe.
                    try {
                        var doc = ifr.contentDocument;
                        if (doc) {
                            var pa = doc.querySelectorAll('.cbi-page-actions');
                            for (var i = 0; i < pa.length; i++) {
                                pa[i].style.display = '';
                                pa[i].style.visibility = '';
                                pa[i].style.marginTop = '14px';
                                pa[i].style.paddingTop = '12px';
                                pa[i].style.borderTop = '1px solid rgba(0,0,0,0.08)';
                            }
                        }
                    } catch(e) {}

                    // Auto-resize: fire multiple times to catch late DOM/CSS settling
                    setTimeout(autoSizeIframe, 150);
                    setTimeout(autoSizeIframe, 500);
                    setTimeout(autoSizeIframe, 1500);
                    setTimeout(autoSizeIframe, 3000);

                    // Re-measure when iframe content changes (modals, save notifications, etc.)
                    // Disconnect previous observer to avoid stacking on every iframe reload
                    if (self._guestWifiMO) { try { self._guestWifiMO.disconnect(); } catch(e) {} self._guestWifiMO = null; }
                    try {
                        var d2 = ifr.contentDocument;
                        if (d2 && d2.body && window.MutationObserver) {
                            self._guestWifiMO = new MutationObserver(function() { autoSizeIframe(); });
                            self._guestWifiMO.observe(d2.body, { childList: true, subtree: true, attributes: true });
                        }
                    } catch(e) {}
                });
                ifr.src = iframeUrl;

                // Force the iframe and its ancestors to full width from
                // the OUTER view. Runs independently of the embed's own
                // JS so it survives any parent-side re-render or theme
                // rule that re-applies .container{max-width:940px}.
                function qaForceIframeFullWidth() {
                    try {
                        var el = ifr;
                        var i = 0;
                        while (el && el.tagName && el.tagName !== 'BODY' && i < 12) {
                            try {
                                el.style.setProperty('width', '100%', 'important');
                                el.style.setProperty('max-width', 'none', 'important');
                            } catch(e) {}
                            el = el.parentNode; i++;
                        }
                    } catch(e) {}
                }
                if (self._qaForceTimer) { clearInterval(self._qaForceTimer); }
                qaForceIframeFullWidth();
                setTimeout(qaForceIframeFullWidth, 50);
                setTimeout(qaForceIframeFullWidth, 250);
                setTimeout(qaForceIframeFullWidth, 800);
                setTimeout(qaForceIframeFullWidth, 2000);
                self._qaForceTimer = setInterval(qaForceIframeFullWidth, 1000);

                // Belt-and-suspenders: poll a few times in case load fires early
                setTimeout(stripEmbedChrome, 150);
                setTimeout(stripEmbedChrome, 500);
                setTimeout(stripEmbedChrome, 1200);
                setTimeout(stripEmbedChrome, 2500);
                tabContent.innerHTML = '';
                tabContent.appendChild(infoBar);
                tabContent.appendChild(ifr);
            }
            else if (id === 'ttyd') {
                tabContent.innerHTML = '';
                tabContent.appendChild(E('p', { 'style': 'color:#888;padding:20px;' }, 'Loading ttyd configuration...'));
                Promise.resolve(typeof uci.unload === 'function' ? uci.unload('ttyd') : null).then(function() {
                    return uci.load('ttyd');
                }).then(function() {
                    return self.renderTtyd();
                }).then(function(node) {
                    tabContent.innerHTML = '';
                    tabContent.appendChild(node);
                }).catch(function(err) {
                    tabContent.innerHTML = '';
                    tabContent.appendChild(E('div', { 'class': 'alert-message error' }, 'ttyd error: ' + (err && err.message ? err.message : String(err))));
                });
            }
            else if (id === 'taskplan') tabContent.appendChild(self.renderTaskPlan());
            else if (id === 'netwizard') {
                tabContent.appendChild(E('p', { 'style': 'color:#888;padding:20px;' }, 'Loading network config...'));
                Promise.resolve(self.renderNetworkSetup()).then(function(node) {
                    tabContent.innerHTML = '';
                    tabContent.appendChild(node);
                }).catch(function(err) {
                    tabContent.innerHTML = '';
                    tabContent.appendChild(E('div', { 'class': 'alert-message error' }, 'Network Setup error: ' + (err && err.message ? err.message : String(err))));
                });
            }
            else if (id === 'scripts') tabContent.appendChild(self.renderScripts());
            else if (id === 'vlan') tabContent.appendChild(self.renderVlan());
            else if (id === 'failover') tabContent.appendChild(self.renderFailover());
            else if (id === 'command') tabContent.appendChild(self.renderCommand());
            else if (id === 'dependencies') tabContent.appendChild(self.renderDependencies());
            else if (id === 'config') {
                tabContent.appendChild(E('p', { 'style': 'color:#888;padding:20px;' }, 'Loading configuration...'));
                self.renderConfigForm().then(function(node) {
                    tabContent.innerHTML = '';
                    tabContent.appendChild(node);

                    // Add our own Save / Save & Apply / Reset buttons
                    var btnRow = E('div', { 'class': 'qa-page-actions', 'style': 'margin-top:20px;padding-top:15px;border-top:1px solid rgba(0,0,0,0.08);display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap;' }, [
                        E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': function() {
                            if (!confirm('Discard unsaved changes to this tab?')) return;
                            self.switchTab('config');
                        } }, _('Reset')),
                        E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': function() {
                            var map = self.configMap;
                            if (!map) { ui.addNotification('Error', 'Form not ready', 'danger'); return; }
                            map.save().then(function() {
                                ui.addNotification('Saved', 'Configuration saved to memory. Use the yellow bar at the top to apply.', 'info');
                                self.refreshPendingCount();
                            }).catch(function(err) { ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger'); });
                        } }, _('Save')),
                        E('button', { 'class': 'btn cbi-button cbi-button-apply', 'click': function() {
                            var map = self.configMap;
                            if (!map) { ui.addNotification('Error', 'Form not ready', 'danger'); return; }
                            map.save().then(function() {
                                return self.pendingApply();
                            }).catch(function(err) { ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger'); });
                        } }, _('Save & Apply'))
                    ]);
                    tabContent.appendChild(btnRow);
                }).catch(function(err) {
                    tabContent.innerHTML = '';
                    tabContent.appendChild(E('div', { 'class': 'alert-message error' }, 'Form error: ' + (err && err.message ? err.message : String(err))));
                });
            }
        }
        tabs.forEach(function(t) {
            var b = E('div', { 'style': 'padding:10px 16px;cursor:pointer;border-bottom:3px solid transparent;color:#666;font-weight:500;font-size:0.9em;user-select:none;', 'click': function() { showTab(t.id); } }, t.label);
            tabButtons[t.id] = b;
            tabBar.appendChild(b);
        });
        // Pending changes indicator
        var pendingBar = E('div', { 'id': 'qa-pending-bar', 'style': 'display:none;background:rgba(255,193,7,0.15);border:1px solid rgba(255,193,7,0.5);border-radius:6px;padding:10px 14px;margin-bottom:14px;display:none;align-items:center;gap:12px;flex-wrap:wrap;' }, [
            E('span', { 'id': 'qa-pending-count', 'style': 'font-weight:bold;' }, ''),
            E('span', { 'style': 'flex:1;' }),
            E('button', { 'class': 'btn cbi-button cbi-button-reset', 'click': function() {
                if (!confirm('Discard ALL pending UCI changes?')) return;
                Promise.resolve(ui.changes.revert()).then(function() {
                    ui.addNotification('Reverted', 'All pending changes discarded.', 'info');
                    self.refreshPendingCount();
                }).catch(function(err) {
                    ui.addNotification('Error', (err && err.message) ? err.message : String(err), 'danger');
                });
            } }, _('Discard All')),
            E('button', { 'class': 'btn cbi-button cbi-button-apply important', 'click': function() {
                self.pendingApply();
            } }, _('Save & Apply All'))
        ]);

        var container = E('div', { 'class': 'cbi-map' }, [
            E('h2', { 'style': 'margin-bottom:4px;' }, 'Quick Actions'),
            E('p', { 'style': 'margin-top:0;margin-bottom:20px;color:#888;font-style:italic;font-size:0.95em;' }, 'Live Status, Commands & Controls'),
            pendingBar,
            tabBar, tabContent
        ]);

        self.pendingBar = pendingBar;
        this.switchTab = showTab;
        if (this.timerId) clearInterval(this.timerId);
        this.timerId = setInterval(function() { self.updateAllButtonsRealtime(); }, this.pollInterval * 1000);
        var initialTab = 'dashboard';
        try {
            // Strip leading '#', trailing '/', and any query after the tab id
            var rawHash = (window.location.hash || '').replace(/^#/, '');
            rawHash = rawHash.split('?')[0].split('/')[0];
            var known = ['dashboard','essential','tools','logs','services','hotplug','crontab','guestwifi','ttyd','taskplan','netwizard','command','dependencies','scripts','vlan','failover','config'];
            if (rawHash && known.indexOf(rawHash) !== -1) initialTab = rawHash;
        } catch(e) {}
        showTab(initialTab);

        // Re-assert hash after LuCI's own dispatcher finishes touching the URL
        setTimeout(function() {
            try {
                if (window.location.hash !== '#' + self.activeTab) {
                    if (window.history && window.history.replaceState) {
                        window.history.replaceState(null, '', '#' + self.activeTab);
                    }
                }
            } catch(e) {}
        }, 200);
        // Poll pending changes every 3s
        self.refreshPendingCount();
        setInterval(function() { self.refreshPendingCount(); }, 3000);
        window.addEventListener('hashchange', function() {
            var nh = (window.location.hash || '').replace(/^#/, '').split('?')[0].split('/')[0];
            var known = ['dashboard','essential','tools','logs','services','hotplug','crontab','guestwifi','ttyd','taskplan','netwizard','command','dependencies','scripts','vlan','failover','config'];
            if (nh && known.indexOf(nh) !== -1 && nh !== self.activeTab) showTab(nh);
        });

        // Hide LuCI's auto-generated Save/Apply/Reset footer.
        // We manage our own per-tab save buttons, so LuCI's would either duplicate
        // them (Hotplug/TaskPlan/Config) or appear uselessly (Crontab/Dependencies/Command).
        self.hideLuCIPageActions();
        return container;
    },

    hideLuCIPageActions: function() {
        // Runs a few times to catch delayed DOM injection by LuCI dispatcher
        function doHide() {
            // LuCI typically appends page-actions to the view container's parent
            var candidates = document.querySelectorAll(
                '#view > .cbi-page-actions, ' +
                '#view .cbi-page-actions:not(.qa-page-actions), ' +
                '#maincontent > .cbi-page-actions, ' +
                '.main > .cbi-page-actions, ' +
                'body > .cbi-page-actions'
            );
            for (var i = 0; i < candidates.length; i++) {
                candidates[i].style.display = 'none';
            }
        }
        // Fire immediately, after microtask, and after network
        doHide();
        setTimeout(doHide, 50);
        setTimeout(doHide, 250);
        setTimeout(doHide, 1000);
    },

    handleSaveApply: function(ev, mode) {
        if (!this.embedGuestWifi)
            return Promise.resolve();
        return this.embedGuestWifi.handleSave(ev).then(function() {
            return ui.changes.apply(false);
        }).catch(function(err) {
            var msg = (err && err.message) ? err.message : String(err);
            if (/No data|code 5/i.test(msg)) return;
            ui.addNotification(null, E('p', {}, 'Apply failed: ' + msg), 'danger');
            throw err;
        });
    },
    handleSave: function(ev) {
        if (!this.embedGuestWifi)
            return Promise.resolve();

        return this.embedGuestWifi.handleSave(ev).then(function() {
            ui.addNotification(null,
                E('p', {}, _('Guest WiFi configuration saved and applied.')),
                'info');
        }).catch(function(err) {
            var msg = (err && err.message) ? err.message : String(err);
            if (/No data|code 5/i.test(msg))
                return;
            ui.addNotification(null,
                E('p', {}, _('Save failed:') + ' ' + msg),
                'danger');
            throw err;
        });
    },
    handleReset: function(ev) {
        return Promise.resolve();
    }
});
