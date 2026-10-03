// SPDX-License-Identifier: Apache-2.0
'use strict';
'require view';
'require ui';
'require uci';
'require form';
'require dom';
'require fs';
'require request';
'require rpc';

var DEV_GATE_ASSET_VERSION = Date.now();
var callHostHints = rpc.declare({
	object: 'luci-rpc',
	method: 'getHostHints',
	expect: { '': {} }
});
var callDevGateConfig = rpc.declare({
	object: 'uci',
	method: 'get',
	params: [ 'config' ],
	expect: { values: {} },
	reject: true
});
var HOST_PICKER_ID = 'devgate-host-picker-options';
var DEV_GATE_STATUS_REFRESH_INTERVAL = 1000;
var DEV_GATE_MAX_TIME_RANGES = 24;
var DEV_GATE_DEFAULT_TIME_RANGE = '00:00-00:00';
var activeHostPicker = null;
var hostPickerCloseInstalled = false;
var WEEK_DAYS = [
	{ value: '7', label: _('周日') },
	{ value: '1', label: _('周一') },
	{ value: '2', label: _('周二') },
	{ value: '3', label: _('周三') },
	{ value: '4', label: _('周四') },
	{ value: '5', label: _('周五') },
	{ value: '6', label: _('周六') }
];

function normalizeRuleUid(value) {
	var uid = String(value == null ? '' : value).toLowerCase().replace(/[^a-z0-9]/g, '').substring(0, 6);

	return /^[a-z0-9]{6}$/.test(uid) ? uid : null;
}

function randomRuleUid() {
	var value = Math.floor(Math.random() * 0x1000000);
	var bytes;

	if (window.crypto && window.crypto.getRandomValues) {
		bytes = new Uint8Array(3);
		window.crypto.getRandomValues(bytes);
		value = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
	}

	return ('000000' + value.toString(16)).slice(-6);
}

function createRuleUid(usedRuleUids) {
	var uid;

	do {
		uid = randomRuleUid();
	} while (usedRuleUids[uid]);

	return uid;
}

function resolveRuleUid(sectionId, cfgvalue, usedRuleUids, sectionRuleUids) {
	var uid;

	if (sectionRuleUids[sectionId]) {
		return sectionRuleUids[sectionId];
	}

	uid = normalizeRuleUid(cfgvalue);

	if (!uid || (usedRuleUids[uid] && usedRuleUids[uid] !== sectionId)) {
		uid = createRuleUid(usedRuleUids);
	}

	usedRuleUids[uid] = sectionId;
	sectionRuleUids[sectionId] = uid;

	return uid;
}

function getPackageVersion() {
	return L.resolveDefault(fs.read_direct('/usr/lib/opkg/status'), '')
		.then(function (status) {
			var block = String(status || '').match(/(^|\n)Package:\s*luci-app-devgate\n([\s\S]*?)(\n\n|$)/);
			var version = block ? block[2].match(/(^|\n)Version:\s*([^\s]+)/) : null;

			return version ? version[2] : 'unknown';
		})
		.catch(function () {
			return 'unknown';
		});
}

function renderPageHeader(version) {
	return E('div', { 'class': 'devgate-page-header' }, [
		E('h2', {}, [
			E('a', {
				href: 'https://github.com/Antecer/luci-app-devgate',
				target: '_blank',
				rel: 'noreferrer noopener'
			}, 'DevGate v%s'.format(version || 'unknown'))
		])
	]);
}

function renderStylesheet(version) {
	return E('link', {
		rel: 'stylesheet',
		href: L.resource('view/devgate/custom.css') + '?v=' + encodeURIComponent(version || 'dev') + '-' + DEV_GATE_ASSET_VERSION
	});
}

function refreshRuleEnableStates(mapEl) {
	return callDevGateConfig('devgate')
		.then(function (sections) {
			Object.keys(sections || {}).forEach(function (sectionId) {
				var section = sections[sectionId];
				var sid;

				if (!section || section['.type'] !== 'device') {
					return;
				}

				sid = section['.name'] || sectionId;
				var field = mapEl.querySelector('.cbi-value[data-field="cbid.devgate.%s.enable"]'.format(sid));
				var wrapper = field ? field.querySelector('.devgate-rule-enable-control') : null;
				var input = wrapper ? wrapper.querySelector('.devgate-rule-enable-input') : null;
				var enabled = String(section.enable || '0') !== '0';

				if (!input || wrapper.getAttribute('data-changed') === 'true') {
					return;
				}

				if (input.checked !== enabled) {
					input.checked = enabled;
				}
			});
		})
		.catch(function (err) {
			console.warn('DevGate状态刷新失败:', err);
		});
}

function watchRuleEnableStates(mapEl) {
	var timer = window.setInterval(function () {
		if (!document.body.contains(mapEl)) {
			window.clearInterval(timer);
			return;
		}

		refreshRuleEnableStates(mapEl);
	}, DEV_GATE_STATUS_REFRESH_INTERVAL);
}

function closeHostPicker() {
	if (!activeHostPicker) {
		return;
	}

	activeHostPicker.button.removeAttribute('aria-expanded');
	activeHostPicker.input.dispatchEvent(new Event('change', { bubbles: true }));
	activeHostPicker = null;

	var picker = document.getElementById(HOST_PICKER_ID);

	if (picker) {
		picker.classList.remove('is-open');
		picker.removeAttribute('data-target-input');
	}
}

function renderHostChoice(choice) {
	return E('span', { 'class': 'devgate-host-choice' }, [
		E('span', { 'class': 'devgate-host-choice-name' }, choice.name),
		E('span', { 'class': 'devgate-host-choice-mac' }, choice.mac.toUpperCase()),
		E('span', { 'class': 'devgate-host-choice-ip' }, choice.ipText)
	]);
}

function renderHostButtonValue(choice) {
	return choice ? '%s %s %s'.format(choice.name, choice.mac.toUpperCase(), choice.ipText) : _('选择目标设备');
}

function syncHostDisplay(root, choice) {
	var display = root.querySelector('.devgate-host-display');
	var button = root.querySelector('.devgate-host-select');

	if (button) {
		button.value = renderHostButtonValue(choice);
	}

	if (!display) {
		return;
	}

	dom.content(display, choice ? [renderHostChoice(choice)] : [_('选择目标设备')]);
}

function selectHostChoice(choice) {
	if (!activeHostPicker) {
		return;
	}

	activeHostPicker.input.value = choice.mac;
	syncHostDisplay(activeHostPicker.root, choice);
	closeHostPicker();
}

function renderHostPicker(hostChoices) {
	if (!hostPickerCloseInstalled) {
		document.addEventListener('click', function (ev) {
			var picker = document.getElementById(HOST_PICKER_ID);

			if (!activeHostPicker) {
				return;
			}

			if ((picker && picker.contains(ev.target)) || activeHostPicker.root.contains(ev.target)) {
				return;
			}

			closeHostPicker();
		});
		hostPickerCloseInstalled = true;
	}

	return E('div', { id: HOST_PICKER_ID, 'class': 'devgate-host-picker' }, hostChoices.reduce(function (nodes, host, index) {
		nodes.push(E('button', {
			type: 'button',
			'class': 'devgate-host-picker-option',
			'data-mac': host.mac,
			click: function () {
				selectHostChoice(host);
			}
		}, [renderHostChoice(host)]));

		if (index < hostChoices.length - 1) {
			nodes.push(E('div', {
				'class': 'devgate-host-picker-separator',
				role: 'separator'
			}));
		}

		return nodes;
	}, []));
}

function openHostPicker(root, button, input, currentMac) {
	var picker = document.getElementById(HOST_PICKER_ID);
	var rect;

	if (!picker) {
		return;
	}

	if (activeHostPicker && activeHostPicker.root === root) {
		closeHostPicker();
		return;
	}

	closeHostPicker();
	activeHostPicker = {
		root: root,
		button: button,
		input: input
	};

	rect = button.getBoundingClientRect();
	picker.classList.add('is-open');
	picker.setAttribute('data-target-input', input.id);
	picker.style.left = '%spx'.format(Math.round(rect.left));
	picker.style.top = '%spx'.format(Math.round(rect.bottom + 4));
	picker.style.width = '%spx'.format(Math.round(rect.width));
	button.setAttribute('aria-expanded', 'true');

	Array.prototype.forEach.call(picker.querySelectorAll('.devgate-host-picker-option'), function (option) {
		option.classList.toggle('is-selected', option.getAttribute('data-mac') === currentMac);
	});
}

function getRuleField(card, option) {
	return card.querySelector('.cbi-value[data-name="%s"]'.format(option));
}

function findNodeById(root, id) {
	var nodes = root ? root.querySelectorAll('[id]') : [];

	for (var i = 0; i < nodes.length; i++) {
		if (nodes[i].id === id) {
			return nodes[i];
		}
	}

	return null;
}

function isLabelableElement(node) {
	var tag;
	var type;

	if (!node || !node.tagName) {
		return false;
	}

	tag = node.tagName.toLowerCase();

	if (tag === 'input') {
		type = String(node.type || '').toLowerCase();
		return type !== 'hidden';
	}

	return tag === 'button' || tag === 'meter' || tag === 'output' || tag === 'progress' || tag === 'select' || tag === 'textarea';
}

function ensureRuleFieldLabelTarget(field) {
	var title = field ? field.querySelector('.cbi-value-title[for]') : null;
	var valueField = field ? field.querySelector('.cbi-value-field') : null;
	var id = title ? title.getAttribute('for') : null;
	var labelTarget;

	if (!id || isLabelableElement(findNodeById(field, id))) {
		return;
	}

	if (field.classList.contains('devgate-card-uid')) {
		title.removeAttribute('for');
		return;
	}

	labelTarget = (valueField || field).querySelector('button, meter, output, progress, select, textarea, input:not([type="hidden"])');
	if (labelTarget && labelTarget.id && isLabelableElement(labelTarget)) {
		title.setAttribute('for', labelTarget.id);
		return;
	}

	(valueField || field).insertBefore(E('input', {
		id: id,
		type: 'button',
		'class': 'devgate-label-proxy',
		tabindex: '-1',
		'aria-hidden': 'true',
		value: ''
	}), (valueField || field).firstChild);
}

function setupRuleCardField(card, option, className) {
	var field = getRuleField(card, option);

	if (field) {
		field.classList.add('devgate-card-field', className);
		ensureRuleFieldLabelTarget(field);
	}

	return field;
}

function setupRuleCard(section, configName, sectionId, node) {
	var removeTitle = section.titleFn('delbtntitle', sectionId);
	var card = E('div', {
		'id': 'cbi-%s-%s'.format(configName, sectionId),
		'class': 'cbi-section-node devgate-rule-card',
		'data-section-id': sectionId
	}, node);
	var enable;
	var actions;

	setupRuleCardField(card, 'comment', 'devgate-card-name');
	setupRuleCardField(card, 'uid', 'devgate-card-uid');
	setupRuleCardField(card, 'mac', 'devgate-card-target');
	setupRuleCardField(card, 'chain', 'devgate-card-mode');
	setupRuleCardField(card, 'time_ranges', 'devgate-card-time-ranges');
	setupRuleCardField(card, 'week', 'devgate-card-week');
	enable = setupRuleCardField(card, 'enable', 'devgate-card-enable');

	actions = E('div', { 'class': 'devgate-card-actions' }, [
		E('div', { 'class': 'devgate-card-actions-content' }, [
			E('button', {
				'class': 'cbi-button cbi-button-remove',
				'name': 'cbi.rts.%s.%s'.format(configName, sectionId),
				'data-section-id': sectionId,
				'click': ui.createHandlerFn(section, 'handleRemove', sectionId),
				'disabled': section.map.readonly || null
			}, [removeTitle || _('删除')])
		])
	]);

	if (enable) {
		actions.querySelector('.devgate-card-actions-content').appendChild(enable);
	}

	card.appendChild(actions);

	return card;
}

function renderRulesContents(cfgsections, nodes) {
	var configName = this.uciconfig || this.map.config;
	var sectionEl = E('div', {
		'id': 'cbi-%s-%s'.format(configName, this.sectiontype),
		'class': 'cbi-section devgate-rules-section',
		'data-tab': (this.map.tabbed && !this.parentoption) ? this.sectiontype : null,
		'data-tab-title': (this.map.tabbed && !this.parentoption) ? this.title || this.sectiontype : null
	});
	var addEl = this.renderSectionAdd('devgate-rules-add');
	var titleEl = E('h3', { 'class': 'devgate-rules-title' }, [
		this.title || _('设备规则'),
		addEl
	]);
	var gridEl = E('div', { 'class': 'devgate-rule-cards' });
	var i;

	sectionEl.appendChild(titleEl);

	if (this.description != null && this.description !== '') {
		sectionEl.appendChild(E('div', { 'class': 'cbi-section-descr' }, this.description));
	}

	for (i = 0; i < nodes.length; i++) {
		gridEl.appendChild(setupRuleCard(this, configName, cfgsections[i], nodes[i]));
	}

	sectionEl.appendChild(E('div', { 'class': 'devgate-rules-card-scroll' }, gridEl));
	dom.bindClassInstance(sectionEl, this);

	return sectionEl;
}

function normalizeIp(ip) {
	if (ip == null) {
		return null;
	}

	ip = String(ip).trim();

	if (ip === '') {
		return null;
	}

	if (ip.indexOf(',') !== -1) {
		ip = ip.split(',')[0].trim();
	}

	if (ip.indexOf('::ffff:') === 0) {
		ip = ip.substring(7);
	}

	if (/^\[[0-9a-fA-F:]+\](?::\d+)?$/.test(ip)) {
		return ip.replace(/^\[/, '').replace(/\](?::\d+)?$/, '').toLowerCase();
	}

	if (/^([0-9]{1,3}\.){3}[0-9]{1,3}:\d+$/.test(ip)) {
		ip = ip.replace(/:\d+$/, '');
	}

	if (/^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/.test(ip)) {
		ip = ip.replace(/\/[0-9]{1,2}$/, '');
	} else if (/^[0-9a-fA-F:]+\/[0-9]{1,3}$/.test(ip)) {
		ip = ip.replace(/\/[0-9]{1,3}$/, '');
	}

	return ip.toLowerCase();
}

function normalizeMac(mac) {
	if (mac == null) {
		return null;
	}

	mac = String(mac).trim().toLowerCase();

	return /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/.test(mac) ? mac : null;
}

function extractMac(value) {
	var text = String(value == null ? '' : value);
	var direct = normalizeMac(text);
	var match;

	if (direct) {
		return direct;
	}

	match = text.match(/([0-9a-f]{2}:){5}[0-9a-f]{2}/i);

	return match ? normalizeMac(match[0]) : null;
}

function getEnvRemoteAddress() {
	var keys = ['remote_addr', 'REMOTE_ADDR', 'peeraddr', 'client_ip'];

	for (var i = 0; i < keys.length; i++) {
		var value = normalizeIp(L.env && L.env[keys[i]]);

		if (value) {
			return value;
		}
	}

	return null;
}

function addClientIp(ips, value) {
	var ip = normalizeIp(value);

	if (ip) {
		ips[ip] = true;
	}
}

function parseClientIps(text) {
	var ips = {};

	String(text || '').split(/[\r\n]+/).forEach(function (line) {
		line = line.trim();

		if (!line) {
			return;
		}

		line.split(',').forEach(function (part) {
			var forwarded = String(part || '').match(/for="?([^;,"]+)/i);

			addClientIp(ips, forwarded ? forwarded[1] : part);
		});
	});

	return ips;
}

function responseText(res) {
	if (!res) {
		return '';
	}

	if (typeof res.text === 'function') {
		return res.text();
	}

	if (typeof res.text === 'string') {
		return res.text;
	}

	if (typeof res.responseText === 'string') {
		return res.responseText;
	}

	if (res.xhr && typeof res.xhr.responseText === 'string') {
		return res.xhr.responseText;
	}

	return '';
}

function parseRemoteAddressResponse(text) {
	var ips = parseClientIps(text);

	try {
		var data = JSON.parse(text);
		['ipaddr', 'ip', 'remote_addr', 'address'].forEach(function (field) {
			addClientIp(ips, data && data[field]);
		});

		L.toArray(data && data.ips).forEach(function (ip) {
			addClientIp(ips, ip);
		});
	} catch (e) {
	}

	return Object.keys(ips);
}

function normalizeClient(value) {
	var ips = {};

	L.toArray(value && value.ips).forEach(function (ip) {
		addClientIp(ips, ip);
	});

	addClientIp(ips, value && value.ip);

	return {
		ips: Object.keys(ips)
	};
}

function appendCurrentClientIp(client, ip) {
	if (!ip) {
		return;
	}

	client.ips = client.ips || [];

	if (client.ips.indexOf(ip) === -1) {
		client.ips.push(ip);
	}
}

function requestRemoteAddress(path) {
	return request.get(L.url(path))
		.then(function (res) {
			if (res && typeof res.json === 'function') {
				try {
					var data = res.json();
					var jsonIps = {};

					['ipaddr', 'ip', 'remote_addr', 'address'].forEach(function (field) {
						addClientIp(jsonIps, data && data[field]);
					});

					L.toArray(data && data.ips).forEach(function (ip) {
						addClientIp(jsonIps, ip);
					});

					if (Object.keys(jsonIps).length > 0) {
						return Object.keys(jsonIps);
					}
				} catch (e) { }
			}

			return Promise.resolve(responseText(res)).then(function (text) {
				return parseRemoteAddressResponse(text);
			});
		})
		.catch(function () {
			return null;
		});
}

function getCurrentClient() {
	var envIp = getEnvRemoteAddress();
	var client = { ips: [] };

	if (envIp) {
		appendCurrentClientIp(client, envIp);
	}

	return requestRemoteAddress('admin/services/devgate/remote_addr')
		.then(function (ips) {
			L.toArray(ips).forEach(function (ip) {
				appendCurrentClientIp(client, ip);
			});

			return normalizeClient(client);
		});
}

function getHostEntries(hostHints) {
	if (!hostHints) {
		return {};
	}

	return hostHints.hosts || hostHints;
}

function getHostHints() {
	return L.resolveDefault(callHostHints(), {});
}

function normalizeHostIp(value) {
	if (value && typeof value === 'object') {
		value = value.address || value.ipaddr || value.ip || value.addr || value[0];
	}

	return normalizeIp(value);
}

function getHostIps(host) {
	var seen = {};
	var ips = [];
	var fields = ['ipaddrs', 'ipaddr', 'ipv4', 'ipv4-address', 'ip6addrs', 'ip6addr', 'ipv6', 'ipv6-address'];

	fields.forEach(function (field) {
		L.toArray(host && host[field]).forEach(function (value) {
			var ip = normalizeHostIp(value);

			if (ip && !seen[ip]) {
				seen[ip] = true;
				ips.push(ip);
			}
		});
	});

	return ips;
}

function isIpv4(ip) {
	return /^([0-9]{1,3}\.){3}[0-9]{1,3}$/.test(ip);
}

function ipv4ToInt(ip) {
	var parts = String(ip || '').split('.');

	if (parts.length !== 4) {
		return null;
	}

	var value = 0;

	for (var i = 0; i < parts.length; i++) {
		var part = Number(parts[i]);

		if (!Number.isInteger(part) || part < 0 || part > 255) {
			return null;
		}

		value = (value << 8) + part;
	}

	return value >>> 0;
}

function maskToPrefix(mask) {
	var value = ipv4ToInt(mask);
	var prefix = 0;
	var seenZero = false;

	if (value == null) {
		return null;
	}

	for (var i = 31; i >= 0; i--) {
		if (value & (1 << i)) {
			if (seenZero) {
				return null;
			}

			prefix++;
		} else {
			seenZero = true;
		}
	}

	return prefix;
}

function getLanNetworks() {
	var ipaddr = uci.get('network', 'lan', 'ipaddr');
	var netmask = uci.get('network', 'lan', 'netmask');
	var ipaddrs = L.toArray(ipaddr);
	var networks = [];

	ipaddrs.forEach(function (value) {
		var ip = String(value || '').trim();
		var prefix = null;
		var slash = ip.indexOf('/');

		if (slash !== -1) {
			prefix = Number(ip.substring(slash + 1));
			ip = ip.substring(0, slash);
		} else {
			prefix = maskToPrefix(netmask || '255.255.255.0');
		}

		var addr = ipv4ToInt(ip);

		if (addr == null || !Number.isInteger(prefix) || prefix < 0 || prefix > 32) {
			return;
		}

		var mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;

		networks.push({
			network: addr & mask,
			mask: mask
		});
	});

	return networks;
}

function isInNetworks(ip, networks) {
	var addr = ipv4ToInt(ip);

	if (addr == null || networks.length === 0) {
		return false;
	}

	for (var i = 0; i < networks.length; i++) {
		if ((addr & networks[i].mask) === networks[i].network) {
			return true;
		}
	}

	return false;
}

function getHostIpv4s(host) {
	return getHostIps(host).filter(isIpv4);
}

function formatHostChoice(mac, host, ipv4s) {
	var normalizedMac = normalizeMac(mac) || String(mac || '').trim();
	var ipText = ipv4s.length > 0 ? ipv4s.join(', ') : _('未知IP');
	var name = String(host && host.name || '').trim() || _('未知设备');

	return {
		mac: normalizedMac,
		name: name,
		ipText: ipText
	};
}

function formatHostSortText(mac, host, ipv4s) {
	var normalizedMac = normalizeMac(mac) || String(mac || '').trim();
	var ipText = ipv4s.length > 0 ? ipv4s.join(', ') : _('未知IP');
	var name = String(host && host.name || '').trim() || _('未知设备');

	return '%s %s %s'.format(name, normalizedMac.toUpperCase(), ipText);
}

function buildHostChoices(hosts, lanNetworks, protectedClient) {
	var hostChoices = [];
	var hostChoiceByMac = {};

	if (!hosts) {
		return {
			list: hostChoices,
			byMac: hostChoiceByMac
		};
	}

	Object.keys(hosts).forEach(function (mac) {
		var host = hosts[mac];
		var ips = getHostIps(host);
		var lanIpv4s = getHostIpv4s(host).filter(function (ip) {
			return isInNetworks(ip, lanNetworks);
		});
		var optionMac = normalizeMac(mac) || String(mac || '').trim();
		var choice;

		if (!optionMac || lanIpv4s.length === 0 || isProtectedHost(mac, ips, protectedClient)) {
			return;
		}

		choice = formatHostChoice(mac, host, lanIpv4s);
		choice.sortText = formatHostSortText(mac, host, lanIpv4s);

		hostChoices.push(choice);
		hostChoiceByMac[optionMac] = choice;
	});

	hostChoices.sort(function (a, b) {
		return a.sortText.localeCompare(b.sortText);
	});

	return {
		list: hostChoices,
		byMac: hostChoiceByMac
	};
}

function protectHost(protectedClient, mac, host) {
	var normalizedMac = normalizeMac(mac);
	var ips = getHostIps(host);

	if (normalizedMac) {
		protectedClient.macs[normalizedMac] = true;
	}

	for (var i = 0; i < ips.length; i++) {
		protectedClient.ips[ips[i]] = true;
	}
}

function buildProtectedClient(hostHints, currentClient) {
	var protectedClient = {
		ips: {},
		macs: {}
	};
	var hosts = getHostEntries(hostHints);

	L.toArray(currentClient && currentClient.ips).forEach(function (ip) {
		protectedClient.ips[ip] = true;
	});

	if (hostHints && typeof hostHints.getMACAddrByIPAddr === 'function') {
		L.toArray(currentClient && currentClient.ips).forEach(function (ip) {
			var matchedMac = normalizeMac(hostHints.getMACAddrByIPAddr(ip));

			if (matchedMac) {
				if (hosts[matchedMac]) {
					protectHost(protectedClient, matchedMac, hosts[matchedMac]);
				} else {
					protectedClient.macs[matchedMac] = true;
				}
			}
		});
	}

	Object.keys(hosts).forEach(function (mac) {
		var host = hosts[mac];
		var ips = getHostIps(host);
		var isCurrentHost = false;

		for (var i = 0; i < ips.length; i++) {
			if (protectedClient.ips[ips[i]]) {
				isCurrentHost = true;
				break;
			}
		}

		if (isCurrentHost) {
			protectHost(protectedClient, mac, host);
		}
	});

	return protectedClient;
}

function isProtectedTarget(value, protectedClient) {
	var ip = normalizeIp(value);
	var mac = extractMac(value);

	return !!((ip && protectedClient.ips[ip]) || (mac && protectedClient.macs[mac]));
}

function isProtectedHost(mac, ips, protectedClient) {
	var normalizedMac = normalizeMac(mac);

	if (normalizedMac && protectedClient.macs[normalizedMac]) {
		return true;
	}

	for (var i = 0; i < ips.length; i++) {
		if (protectedClient.ips[ips[i]]) {
			return true;
		}
	}

	return false;
}

function normalizeTimeRangeEndpoint(value) {
	var match = String(value || '').trim().match(/^([0-9]{1,2}):([0-9]{1,2})$/);
	var hour;
	var minute;

	if (!match) {
		return null;
	}

	hour = Number(match[1]);
	minute = Number(match[2]);

	if (hour > 24 || minute > 59 || (hour === 24 && minute !== 0)) {
		return null;
	}

	return '%02d:%02d'.format(hour, minute);
}

function isTimeRangeEndpoint(value) {
	return normalizeTimeRangeEndpoint(value) != null;
}

function parseTimeRangesValue(value) {
	var raw = String(value == null ? '' : value).trim();
	var ranges = [];

	if (raw === '') {
		raw = DEV_GATE_DEFAULT_TIME_RANGE;
	}

	raw.split(',').forEach(function (item) {
		var match;
		var start;
		var end;

		if (ranges.length >= DEV_GATE_MAX_TIME_RANGES) {
			return;
		}

		item = String(item || '').trim();
		match = item.match(/^([^,-]+)-([^,-]+)$/);
		start = match ? normalizeTimeRangeEndpoint(match[1]) : null;
		end = match ? normalizeTimeRangeEndpoint(match[2]) : null;

		if (start && end) {
			ranges.push({
				start: start,
				end: end
			});
		}
	});

	if (ranges.length === 0) {
		ranges.push({
			start: '00:00',
			end: '00:00'
		});
	}

	return ranges;
}

function emitTimeRangesChange(root) {
	root.dispatchEvent(new CustomEvent('widget-change', {
		bubbles: true,
		detail: {
			value: getTimeRangesInputValue(root)
		}
	}));
	root.dispatchEvent(new Event('change', { bubbles: true }));
}

function syncTimeRangeButtons(root) {
	var rows = root.querySelectorAll('.devgate-time-range-row');
	var add = root.querySelector('.devgate-time-range-add');
	var readonly = root.getAttribute('data-readonly') === 'true';

	if (add) {
		add.disabled = readonly || rows.length >= DEV_GATE_MAX_TIME_RANGES;
	}

	Array.prototype.forEach.call(root.querySelectorAll('.devgate-time-range-remove'), function (button) {
		button.disabled = readonly || rows.length <= 1;
	});
}

function parseTimeInputMinutes(value) {
	var normalized = normalizeTimeRangeEndpoint(value);
	var match = normalized ? normalized.match(/^([0-9]{2}):([0-9]{2})$/) : null;
	var hour;
	var minute;

	if (!match) {
		return null;
	}

	hour = Number(match[1]);
	minute = Number(match[2]);

	return hour * 60 + minute;
}

function formatTimeInputMinutes(minutes) {
	var hour;
	var minute;

	minutes = Math.max(0, Math.min(24 * 60, minutes));
	hour = Math.floor(minutes / 60);
	minute = minutes % 60;

	return '%02d:%02d'.format(hour, minute);
}

function normalizeTimeRangeInput(input) {
	var value = normalizeTimeRangeEndpoint(input.value);

	if (value != null) {
		input.value = value;
	}
}

function handleTimeInputWheel(root, input, ev) {
	var current;
	var step;
	var direction;

	if (input.disabled || input.readOnly || document.activeElement !== input) {
		return;
	}

	current = parseTimeInputMinutes(input.value);
	if (current == null) {
		current = 0;
	}

	step = ev.shiftKey ? 60 : 1;
	direction = ev.deltaY < 0 ? 1 : -1;
	input.value = formatTimeInputMinutes(current + direction * step);

	ev.preventDefault();
	input.dispatchEvent(new Event('input', { bubbles: true }));
}

function bindTimeRangeInputEvents(root, input) {
	function normalizeAndEmit() {
		normalizeTimeRangeInput(input);
		emitTimeRangesChange(root);
	}

	input.addEventListener('input', function () {
		emitTimeRangesChange(root);
	});
	input.addEventListener('change', normalizeAndEmit);
	input.addEventListener('blur', normalizeAndEmit);
	input.addEventListener('wheel', function (ev) {
		handleTimeInputWheel(root, input, ev);
	}, { passive: false });
}

function appendTimeRangeRow(root, range) {
	var cbid = root.getAttribute('data-cbid');
	var readonly = root.getAttribute('data-readonly') === 'true';
	var index = Number(root.getAttribute('data-next-index') || '0');
	var startId = index === 0 ? 'widget.' + cbid : 'widget.%s.%d.start'.format(cbid, index);
	var endId = index === 0 ? 'widget.%s.end'.format(cbid) : 'widget.%s.%d.end'.format(cbid, index);
	var start = E('input', {
		id: startId,
		type: 'text',
		'class': 'devgate-time-input',
		inputmode: 'numeric',
		maxlength: '5',
		placeholder: '00:00',
		value: range && range.start || '00:00',
		disabled: readonly || null
	});
	var end = E('input', {
		id: endId,
		type: 'text',
		'class': 'devgate-time-input',
		inputmode: 'numeric',
		maxlength: '5',
		placeholder: '24:00',
		value: range && range.end || '00:00',
		disabled: readonly || null
	});
	var action;
	var row;

	root.setAttribute('data-next-index', String(index + 1));

	bindTimeRangeInputEvents(root, start);
	bindTimeRangeInputEvents(root, end);

	if (index === 0) {
		action = E('input', {
			type: 'button',
			'class': 'cbi-button devgate-time-range-action devgate-time-range-add',
			value: _('添加'),
			disabled: readonly || null,
			click: function () {
				if (root.querySelectorAll('.devgate-time-range-row').length >= DEV_GATE_MAX_TIME_RANGES) {
					return;
				}

				appendTimeRangeRow(root, { start: '00:00', end: '00:00' });
				syncTimeRangeButtons(root);
				emitTimeRangesChange(root);
			}
		});
	} else {
		action = E('input', {
			type: 'button',
			'class': 'cbi-button devgate-time-range-action devgate-time-range-remove',
			value: _('移除'),
			disabled: readonly || null,
			click: function () {
				if (root.querySelectorAll('.devgate-time-range-row').length <= 1) {
					return;
				}

				row.parentNode.removeChild(row);
				syncTimeRangeButtons(root);
				emitTimeRangesChange(root);
			}
		});
	}

	row = E('div', { 'class': 'devgate-time-range-row' }, [
		start,
		E('span', { 'class': 'devgate-time-separator' }, '-'),
		end,
		action
	]);

	root.appendChild(row);
}

function renderTimeRanges(option, section_id, cfgvalue) {
	var cbid = option.cbid(section_id);
	var readonly = ((option.readonly != null) ? option.readonly : option.map.readonly) || null;
	var root = E('div', {
		id: cbid,
		'class': 'devgate-time-ranges',
		'data-cbid': cbid,
		'data-readonly': readonly ? 'true' : 'false'
	});

	parseTimeRangesValue(cfgvalue != null ? cfgvalue : option.default).forEach(function (range) {
		appendTimeRangeRow(root, range);
	});

	syncTimeRangeButtons(root);
	return root;
}

function getTimeRangesInputValue(root) {
	var values = [];

	Array.prototype.forEach.call(root.querySelectorAll('.devgate-time-range-row'), function (row) {
		var inputs = row.querySelectorAll('.devgate-time-input');
		var start = inputs[0] ? String(inputs[0].value || '').trim() : '';
		var end = inputs[1] ? String(inputs[1].value || '').trim() : '';

		start = normalizeTimeRangeEndpoint(start) || start;
		end = normalizeTimeRangeEndpoint(end) || end;
		values.push('%s-%s'.format(start, end));
	});

	return values.join(',');
}

function validateTimeRangesValue(value) {
	var raw = String(value == null ? '' : value).trim();
	var ranges = raw ? raw.split(',') : [];
	var timePattern = /^([^,]+)-([^,]+)$/;
	var i;
	var match;

	if (ranges.length < 1) {
		return _('请至少保留一个禁用时段。');
	}

	if (ranges.length > DEV_GATE_MAX_TIME_RANGES) {
		return _('禁用时段最多允许24个。');
	}

	for (i = 0; i < ranges.length; i++) {
		match = String(ranges[i] || '').trim().match(timePattern);
		if (!match || !normalizeTimeRangeEndpoint(match[1]) || !normalizeTimeRangeEndpoint(match[2])) {
			return _('禁用时段范围必须为 00:00-24:00。');
		}
	}

	return true;
}

function parseWeekValue(value) {
	var selected = {};
	var raw = String(value == null ? '' : value).trim();

	if (raw === '' || raw === '0') {
		WEEK_DAYS.forEach(function (day) {
			selected[day.value] = true;
		});
		return selected;
	}

	raw.split(',').forEach(function (day) {
		day = String(day || '').trim();
		if (day) {
			selected[day] = true;
		}
	});

	return selected;
}

function getWeekInputValue(root) {
	var values = [];

	WEEK_DAYS.forEach(function (day) {
		var input = root.querySelector('input[value="%s"]'.format(day.value));

		if (input && input.checked) {
			values.push(day.value);
		}
	});

	return values.length === WEEK_DAYS.length ? '0' : values.join(',');
}

function renderWeekCheckboxes(option, section_id, cfgvalue) {
	var selected = parseWeekValue(cfgvalue != null ? cfgvalue : option.default);
	var cbid = option.cbid(section_id);
	var root = E('div', {
		id: cbid,
		'class': 'devgate-week-checkboxes'
	});

	WEEK_DAYS.forEach(function (day, index) {
		var inputId = index === 0 ? 'widget.' + cbid : 'widget.%s.%d'.format(cbid, index);
		var input = E('input', {
			id: inputId,
			type: 'checkbox',
			value: day.value,
			checked: selected[day.value] ? 'checked' : null,
			disabled: ((option.readonly != null) ? option.readonly : option.map.readonly) || null
		});

		input.addEventListener('change', function (ev) {
			if (!getWeekInputValue(root)) {
				ev.target.checked = true;
			}
		});

		root.appendChild(E('label', { 'class': 'devgate-week-checkbox' }, [
			input,
			E('span', {}, day.label)
		]));
	});

	return root;
}

function renderRuleModeRadios(option, section_id, cfgvalue) {
	var cbid = option.cbid(section_id);
	var value = String(cfgvalue != null ? cfgvalue : option.default || 'forward');
	var readonly = ((option.readonly != null) ? option.readonly : option.map.readonly) || null;
	var choices = [
		{ value: 'forward', label: _('公网') },
		{ value: 'all', label: _('内网') }
	];

	if (value === 'input') {
		value = 'all';
	}

	return E('div', {
		id: cbid,
		'class': 'devgate-mode-radios'
	}, choices.map(function (choice, index) {
		var inputId = index === 0 ? 'widget.' + cbid : 'widget.%s.%d'.format(cbid, index);

		return E('span', { 'class': 'cbi-radio' }, [
			E('input', {
				id: inputId,
				name: cbid,
				type: 'radio',
				'class': 'cbi-input-radio',
				value: choice.value,
				checked: value === choice.value ? 'checked' : null,
				disabled: readonly || null
			}),
			E('label', { 'for': inputId }),
			E('span', {}, choice.label)
		]);
	}));
}

function renderRuleEnableButton(option, section_id, cfgvalue) {
	var enabled = String(cfgvalue != null ? cfgvalue : option.default) !== '0';
	var readonly = ((option.readonly != null) ? option.readonly : option.map.readonly) || null;
	var cbid = option.cbid(section_id);
	var widgetId = 'widget.' + cbid;
	var wrapper;
	var input = E('input', {
		id: widgetId,
		type: 'checkbox',
		'class': 'devgate-rule-enable-input',
		checked: enabled ? 'checked' : null,
		disabled: readonly || null
	});
	var button = E('label', {
		'for': widgetId,
		'class': 'devgate-rule-enable-button'
	});

	input.addEventListener('change', function () {
		wrapper.setAttribute('data-changed', 'true');
		wrapper.dispatchEvent(new CustomEvent('widget-change', {
			bubbles: true,
			detail: {
				value: input.checked ? '1' : '0'
			}
		}));
	});

	wrapper = E('div', {
		id: cbid,
		'class': 'devgate-rule-enable-control'
	}, [
		input,
		button
	]);

	return wrapper;
}

function bindDomOptionValidation(option) {
	option._devgateValidationErrors = {};
	option.isValid = function (section_id) {
		var result = (typeof this.validate === 'function') ? this.validate(section_id, this.formvalue(section_id)) : true;

		if (result === true) {
			delete this._devgateValidationErrors[section_id];
			return true;
		}

		this._devgateValidationErrors[section_id] = result || _('输入无效。');
		return false;
	};
	option.getValidationError = function (section_id) {
		return this._devgateValidationErrors[section_id] || '';
	};
}

return view.extend({
	load: function () {
		return Promise.all([
			uci.load('devgate'),
			uci.load('network'),
			getHostHints(),
			getCurrentClient(),
			getPackageVersion()
		]);
	},

	render: function (data) {
		var m, s, o;
		var hostHints = data[2];
		var hosts = getHostEntries(hostHints);
		var protectedClient = buildProtectedClient(hostHints, data[3]);
		var lanNetworks = getLanNetworks();
		var hostChoices = buildHostChoices(hosts, lanNetworks, protectedClient);
		var usedRuleUids = {};
		var sectionRuleUids = {};

		m = new form.Map('devgate');

		var s = m.section(form.TypedSection, 'device', _('设备规则'));
		s.addremove = true;
		s.anonymous = true;
		s.sortable = false;
		s.addbtntitle = _('添加');
		s.delbtntitle = _('删除');
		s.renderContents = renderRulesContents;

		o = s.option(form.Value, 'comment', _('规则名称'));
		o.optional = true;
		o.placeholder = _('可选规则名称');

		o = s.option(form.Value, 'uid', _('规则ID'));
		o.rmempty = false;
		o.renderWidget = function (section_id, option_index, cfgvalue) {
			return E('input', {
				id: this.cbid(section_id),
				type: 'hidden',
				value: resolveRuleUid(section_id, cfgvalue, usedRuleUids, sectionRuleUids)
			});
		};
		o.formvalue = function (section_id) {
			var elem = this.map.findElement('id', this.cbid(section_id));

			return elem ? elem.value : null;
		};
		o.write = function (section_id, value) {
			return this.map.data.set(
				this.uciconfig || this.map.config,
				section_id,
				this.option,
				normalizeRuleUid(value) || resolveRuleUid(section_id, value, usedRuleUids, sectionRuleUids)
			);
		};

		o = s.option(form.Flag, 'enable', _('启用'));
		o.rmempty = false;
		o.default = '0';
		o.renderWidget = function (section_id, option_index, cfgvalue) {
			return renderRuleEnableButton(this, section_id, cfgvalue);
		};
		o.formvalue = function (section_id) {
			var elem = this.map.findElement('id', this.cbid(section_id));
			var input = elem ? elem.querySelector('input[type="checkbox"]') : null;

			return input ? (input.checked ? '1' : '0') : null;
		};
		o.write = function (section_id, value) {
			return this.map.data.set(this.uciconfig || this.map.config, section_id, this.option, value === '0' ? '0' : '1');
		};

		o = s.option(form.Value, 'mac', _('目标设备'));
		o.rmempty = false;
		// o.description = _('以MAC识别设备，IP仅用于辅助辨认。');
		o.renderWidget = function (section_id, option_index, cfgvalue) {
			var cbid = this.cbid(section_id);
			var mac = extractMac(cfgvalue);
			var value = mac || String(cfgvalue || '').trim();
			var choice = mac ? hostChoices.byMac[mac] : null;
			var disabled = ((this.readonly != null) ? this.readonly : this.map.readonly) || null;
			var input = E('input', {
				id: cbid,
				type: 'hidden',
				'class': 'devgate-host-input',
				value: value
			});
			var display = E('span', { 'class': 'devgate-host-display' });
			var button = E('input', {
				id: 'widget.' + cbid,
				type: 'button',
				'class': 'devgate-host-select cbi-button',
				'aria-haspopup': 'listbox',
				disabled: disabled || null,
				click: function (ev) {
					ev.preventDefault();
					openHostPicker(wrapper, button, input, extractMac(input.value));
				}
			});
			var wrapper = E('div', { 'class': 'devgate-host-control' }, [
				button,
				display,
				input
			]);

			syncHostDisplay(wrapper, choice);

			return wrapper;
		};
		o.formvalue = function (section_id) {
			var elem = this.map.findElement('id', this.cbid(section_id));

			return elem ? elem.value : null;
		};
		o.write = function (section_id, value) {
			var mac = extractMac(value) || String(value || '').trim();

			return this.map.data.set(this.uciconfig || this.map.config, section_id, this.option, mac);
		};
		o.validate = function (section_id, value) {
			if (isProtectedTarget(value, protectedClient)) {
				return _('不能选择当前登录设备。');
			}

			if (String(value || '').trim() !== '' && !extractMac(value)) {
				return _('请选择或输入设备MAC。');
			}

			return true;
		};
		bindDomOptionValidation(o);

		o = s.option(form.ListValue, 'chain', _('管控方式'));
		o.value('forward', _('公网'));
		o.value('all', _('内网'));
		o.default = 'forward';
		o.rmempty = false;
		o.cfgvalue = function (section_id) {
			var value = this.map.data.get(this.uciconfig || this.map.config, section_id, this.option);

			return value === 'input' ? 'all' : value;
		};
		o.renderWidget = function (section_id, option_index, cfgvalue) {
			return renderRuleModeRadios(this, section_id, cfgvalue);
		};
		o.formvalue = function (section_id) {
			var elem = this.map.findElement('id', this.cbid(section_id));
			var checked = elem ? elem.querySelector('input[type="radio"]:checked') : null;

			return checked ? checked.value : null;
		};
		o.write = function (section_id, value) {
			return this.map.data.set(this.uciconfig || this.map.config, section_id, this.option, value === 'input' ? 'all' : value);
		};

		o = s.option(form.Value, 'time_ranges', _('禁用时段'));
		o.default = DEV_GATE_DEFAULT_TIME_RANGE;
		o.rmempty = false;
		o.renderWidget = function (section_id, option_index, cfgvalue) {
			return renderTimeRanges(this, section_id, cfgvalue);
		};
		o.formvalue = function (section_id) {
			var elem = this.map.findElement('id', this.cbid(section_id));

			return elem ? getTimeRangesInputValue(elem) : null;
		};
		o.write = function (section_id, value) {
			return this.map.data.set(this.uciconfig || this.map.config, section_id, this.option, value || DEV_GATE_DEFAULT_TIME_RANGE);
		};
		o.validate = function (section_id, value) {
			return validateTimeRangesValue(value);
		};
		bindDomOptionValidation(o);

		o = s.option(form.Value, 'week', _('生效周期'));
		o.default = '0';
		o.rmempty = false;
		o.renderWidget = function (section_id, option_index, cfgvalue) {
			return renderWeekCheckboxes(this, section_id, cfgvalue);
		};
		o.formvalue = function (section_id) {
			var elem = this.map.findElement('id', this.cbid(section_id));

			return elem ? getWeekInputValue(elem) : null;
		};
		o.write = function (section_id, value) {
			return this.map.data.set(this.uciconfig || this.map.config, section_id, this.option, value || '0');
		};
		o.validate = function (section_id, value) {
			return value ? true : _('请至少选择一天。');
		};
		bindDomOptionValidation(o);
		// o.description = _('规则生效的日期。');

		return m.render().then(function (mapEl) {
			var pageEl = E('div', { 'class': 'devgate-page' }, [
				renderStylesheet(data[4]),
				renderHostPicker(hostChoices.list),
				renderPageHeader(data[4]),
				mapEl
			]);

			(async () => {
				function sleep(ms) {
					return new Promise((resolve) => setTimeout(resolve, ms));
				}
				// 计算容器外部元素占用高度
				var pageOffset = 0;
				var offsetSelectors = ['.bg-primary', '.mobile-hide', '.cbi-page-actions'];
				while (!document.querySelector('.cbi-page-actions')) await sleep(100);
				for (let selector of offsetSelectors) {
					let node = document.querySelector(selector);
					if (node) {
						let style = window.getComputedStyle(node);
						if (style.display === 'none' || style.visibility === 'hidden') continue;
						let rect = node.getBoundingClientRect();
						pageOffset += rect.height + (parseFloat(style.marginTop) || 0) + (parseFloat(style.marginBottom) || 0);
					}
				}
				let container = document.querySelector('#maincontent>.container');
				if (container) {
					let style = window.getComputedStyle(container);
					pageOffset += (parseFloat(style.marginTop) || 0) + (parseFloat(style.marginBottom) || 0);
				}
				pageOffset = Math.ceil(pageOffset);
				if (pageOffset > 0) {
					pageEl.style.setProperty('--devgate-page-offset', '%dpx'.format(pageOffset));
				}
			})();

			watchRuleEnableStates(mapEl);

			return pageEl;
		});
	}
});
