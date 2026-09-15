/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require form';
'require network';
'require poll';
'require rpc';
'require uci';
'require ui';
'require validation';
'require view';

'require homeproxy as hp';
'require tools.firewall as fwtool';
'require tools.widgets as widgets';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

const callRCInit = rpc.declare({
	object: 'rc',
	method: 'init',
	params: ['name', 'action'],
	expect: { '': {} }
});

const callReadDomainList = rpc.declare({
	object: 'luci.homeproxy',
	method: 'acllist_read',
	params: ['type'],
	expect: { '': {} }
});

const callWriteDomainList = rpc.declare({
	object: 'luci.homeproxy',
	method: 'acllist_write',
	params: ['type', 'content'],
	expect: { '': {} }
});

const callCurrentNode = rpc.declare({
	object: 'luci.homeproxy',
	method: 'current_node_get',
	expect: { '': {} }
});

const callPackageVersion = rpc.declare({
	object: 'luci.homeproxy',
	method: 'package_get_version',
	expect: { '': {} }
});

const callUpdatePanel = rpc.declare({
	object: 'luci.homeproxy',
	method: 'clash_api_update_panel',
	expect: { '': {} }
});

const statusCss = `
#homeproxy_status_panel {
	margin-bottom: 1rem;
}
#homeproxy_status_panel .homeproxy-status-grid {
	display: grid;
	grid-template-columns: repeat(3, minmax(0, 1fr)) auto;
	gap: 10px;
	align-items: center;
}
#homeproxy_status_panel .homeproxy-status-field {
	min-width: 0;
}
#homeproxy_status_panel .homeproxy-status-label {
	font-weight: 600;
	text-align: center;
	margin-bottom: 6px;
}
#homeproxy_status_panel input {
	width: 100%;
	min-width: 0;
}
#homeproxy_status_panel .homeproxy-version-field input {
	width: 100%;
}
#homeproxy_status_panel .homeproxy-core-version-field input {
	width: 100%;
}
#homeproxy_status_panel .homeproxy-core-status-field input {
	width: 100%;
	text-align: center;
}
#homeproxy_status_panel .homeproxy-core-status {
	border: unset;
	font-style: italic;
	font-weight: 700;
}
#homeproxy_status_panel .homeproxy-status-actions {
	display: flex;
	flex-wrap: nowrap;
	gap: 6px;
	align-items: center;
	justify-content: flex-end;
	min-width: 0;
}
#homeproxy_status_panel .homeproxy-status-actions .btn {
	width: auto;
	min-width: 0;
	padding-left: 6px;
	padding-right: 6px;
	white-space: nowrap;
}
@media (max-width: 700px) {
	#homeproxy_status_panel .homeproxy-status-grid {
		grid-template-columns: 1fr;
	}
	#homeproxy_status_panel .homeproxy-status-actions {
		flex-wrap: wrap;
		justify-content: flex-start;
	}
	#homeproxy_status_panel .homeproxy-status-actions .btn {
		flex: 1 1 auto;
	}
}`;

function getServiceStatus() {
	return L.resolveDefault(callServiceList('homeproxy'), {}).then((res) => {
		let isRunning = false;
		try {
			isRunning = res['homeproxy']['instances']['sing-box-c']['running'];
		} catch (e) { }
		return isRunning;
	});
}

function updateCoreStatus(isRunning, currentNode) {
	let status = document.getElementById('homeproxy_core_status');
	if (!status)
		return;

	status.style.color = isRunning ? 'green' : 'red';
	status.value = currentNode ? _('Running: %s').format(currentNode) : (isRunning ? _('Running') : _('Not Running'));
}

function parseControllerPort(externalController) {
	let value = externalController || '127.0.0.1:9090';
	let idx = value.lastIndexOf(':');
	return (idx >= 0) ? value.substring(idx + 1) : '9090';
}

function getClashApiInfo() {
	let port = parseControllerPort(uci.get('homeproxy', 'clash_api', 'external_controller')),
	    secret = uci.get('homeproxy', 'clash_api', 'secret') || '';

	return {
		port,
		secret,
		baseUrl: 'http://' + window.location.hostname + ':' + port
	};
}

function updateDashboard() {
	return callUpdatePanel().then((res) => {
		if (!res?.result) {
			let message = res?.error;
			if (message === 'update_panel_failed')
				message = _('Update panel failed.');
			else if (message === 'clash_api_unavailable')
				message = _('Clash API unavailable.');
			else if (message === 'panel_backup_failed')
				message = _('Backup panel failed.');
			else if (message === 'panel_restore_failed')
				message = _('Restore panel failed.');

			throw new Error(message || _('Update failed.'));
		}
		ui.addNotification(null, E('p', _('Successfully updated.')), 'info');
	}).catch((err) => {
		ui.addNotification(null, E('p', err.message || err), 'danger');
	});
}

function openDashboard() {
	let api = getClashApiInfo();
	let query = new URLSearchParams({
		host: window.location.hostname,
		hostname: window.location.hostname,
		port: api.port,
		secret: api.secret
	}).toString();

	window.open(api.baseUrl + '/ui/?' + query, '_blank');
	return Promise.resolve();
}

function normalizeRuleSetSectionId(tag) {
	return 'ruleset_' + tag.replace(/[^A-Za-z0-9_]/g, '_').replace(/^_+|_+$/g, '');
}

function getDnsServerDefaultPort(type) {
	switch (type) {
	case 'udp':
	case 'tcp':
		return '53';
	case 'tls':
	case 'quic':
		return '853';
	case 'https':
	case 'h3':
		return '443';
	default:
		return 'auto';
	}
}

function getDnsServerAddressPlaceholder(type) {
	switch (type) {
	case 'https':
	case 'h3':
		return '';
	case 'tls':
	case 'quic':
		return 'dns.alidns.com';
	default:
		return '';
	}
}

function validateDnsServerAddress(type, value) {
	if (!value)
		return false;

	if (value.includes('://')) {
		if (!['https', 'h3'].includes(type))
			return false;

		try {
			let url = new URL(value);
			if (url.protocol !== 'https:')
				return false;

			value = url.hostname;
		} catch (e) {
			return false;
		}
	}

	return stubValidator.apply('hostname', value) ||
		stubValidator.apply('ip4addr', value) ||
		stubValidator.apply('ip6addr', value.match(/^\[(.+)\]$/)?.[1] || value);
}

function validateDuration(value) {
	return !value || /^[1-9]\d*(ms|s|m|h|d)$/.test(value);
}

function validateUpdateCron(value) {
	if (!value)
		return true;

	const matched = String(value).trim().match(/^(\d{1,2})\s+(\d{1,2})\s+\*\s+\*\s+([0-7*])$/);
	if (!matched)
		return false;

	return +matched[1] <= 59 && +matched[2] <= 23;
}

function translateKnownError(error) {
	let name = error?.name || '',
	    message = error?.message || error || '';

	if (name === 'TypeError' && String(message).match(/can't convert null to object|Cannot convert undefined or null to object/i))
		return _('Type error') + '\n' + _('Cannot convert null to object.');

	return null;
}

function installKnownErrorTranslator() {
	if (window.__homeproxyKnownErrorTranslator)
		return;

	window.__homeproxyKnownErrorTranslator = true;

	window.addEventListener('error', (ev) => {
		let message = translateKnownError(ev.error || ev.message);
		if (message) {
			ev.preventDefault();
			ui.addNotification(null, E('p', message), 'danger');
		}
	}, true);

	window.addEventListener('unhandledrejection', (ev) => {
		let message = translateKnownError(ev.reason);
		if (message) {
			ev.preventDefault();
			ui.addNotification(null, E('p', message), 'danger');
		}
	}, true);
}

function renderRuleSetAdd(section, extra_class) {
	let el = form.GridSection.prototype.renderSectionAdd.apply(section, [ extra_class ]),
	    nameEl = el.querySelector('.cbi-section-create-name'),
	    button = el.querySelector('.cbi-section-create > .cbi-button-add'),
	    uciconfig = section.uciconfig || section.map.config;

	let tagEl = E('input', {
		'type': 'text',
		'class': nameEl.className
	});
	let hintEl = E('div', { 'class': 'cbi-value-description' });

	nameEl.style.display = 'none';
	nameEl.parentNode.insertBefore(tagEl, nameEl);
	nameEl.parentNode.appendChild(hintEl);
	button.disabled = true;

	let syncSectionName = () => {
		let tag = (tagEl.value || '').trim();
		hintEl.textContent = '';

		if (!tag) {
			nameEl.value = '';
			button.disabled = true;
			return;
		}

		if (!tag.match(/^[A-Za-z0-9_.-]+$/)) {
			nameEl.value = '';
			button.disabled = true;
			hintEl.textContent = _('Expecting: %s').format(_('valid tag'));
			return;
		}

		let duplicate = false;
		uci.sections(uciconfig, 'ruleset', (res) => {
			if ((res.tag || ('cfg-' + res['.name'] + '-rule')) === tag)
				duplicate = true;
		});

		if (duplicate) {
			nameEl.value = '';
			button.disabled = true;
			hintEl.textContent = _('Expecting: %s').format(_('unique value'));
			return;
		}

		let section_id = normalizeRuleSetSectionId(tag),
		    suffix = 1;
		while (uci.get(uciconfig, section_id))
			section_id = normalizeRuleSetSectionId(tag) + '_' + suffix++;

		nameEl.value = section_id;
		nameEl.dataset.sectionId = section_id;
		nameEl.dataset.ruleSetTag = tag;
		button.disabled = null;
	};

	tagEl.addEventListener('input', syncSectionName);
	tagEl.addEventListener('blur', syncSectionName);

	button.addEventListener('click', () => {
		syncSectionName();

		let tag = nameEl.dataset.ruleSetTag,
		    section_id = nameEl.dataset.sectionId;

		window.setTimeout(() => {
			if (tag && section_id && uci.get(uciconfig, section_id)) {
				uci.set(uciconfig, section_id, 'tag', tag);
				uci.set(uciconfig, section_id, 'label', tag);
				uci.set(uciconfig, section_id, 'enabled', '1');
				uci.set(uciconfig, section_id, 'type', 'remote');
				uci.set(uciconfig, section_id, 'format', 'binary');
				uci.set(uciconfig, section_id, 'remote_path', '/etc/homeproxy/ruleset/');
				uci.set(uciconfig, section_id, 'auto_update', '1');
				uci.set(uciconfig, section_id, 'update_interval', '0 0 * * *');
			}
		}, 0);
	});

	return el;
}

let stubValidator = {
	factory: validation,
	apply(type, value, args) {
		if (value != null)
			this.value = value;

		return validation.types[type].apply(this, args);
	},
	assert(condition) {
		return !!condition;
	}
};

return view.extend({
	load() {
		return Promise.all([
			uci.load('homeproxy'),
			hp.getBuiltinFeatures(),
			network.getHostHints(),
			L.resolveDefault(callPackageVersion(), {})
		]);
	},

	render(data) {
		let m, s, o, ss, so;

		installKnownErrorTranslator();
		hp.installCloseButtonText();

		let features = data[1],
		    hosts = data[2]?.hosts,
		    packageVersion = data[3]?.version || '-',
		    routingMode = uci.get(data[0], 'config', 'routing_mode');

		/* Cache all configured proxy nodes, they will be called multiple times */
		let proxy_nodes = {};
		let subscription_groups = {};
		let routing_groups = {};
		let normalizeFormList = function(value) {
			return Array.isArray(value) ? value : (value ? [value] : []);
		};
		uci.sections(data[0], 'node', (res) => {
			let nodeaddr = ((res.type === 'direct') ? res.override_address : res.address) || '',
			    nodeport = ((res.type === 'direct') ? res.override_port : res.port) || '';

			proxy_nodes[res['.name']] =
				String.format('[%s] %s', res.type, res.label || ((stubValidator.apply('ip6addr', nodeaddr) ?
					String.format('[%s]', nodeaddr) : nodeaddr) + ':' + nodeport));
		});
		let subscriptionUrls = normalizeFormList(uci.get(data[0], 'subscription', 'subscription_url')),
		    subscriptionNames = normalizeFormList(uci.get(data[0], 'subscription', 'subscription_name'));
		for (let i = 0; i < subscriptionUrls.length; i++) {
			let url = subscriptionUrls[i],
			    title = String(subscriptionNames[i] || '').trim();

			if (title)
				subscription_groups[hp.calcStringMD5(url.replace(/#.*$/, ''))] = title;
		}
		uci.sections(data[0], 'routing_node', (res) => {
			routing_groups[res['.name']] = res.label || res['.name'];
		});
		let collectSelectedRoutingNodes = function(groups, subscription_nodes, selected_nodes, policy_nodes, section_id) {
			let nodes = [];
			groups = normalizeFormList(groups);
			subscription_nodes = normalizeFormList(subscription_nodes);
			selected_nodes = normalizeFormList(selected_nodes);
			policy_nodes = normalizeFormList(policy_nodes);

			uci.sections(data[0], 'node', (res) => {
				if (res.grouphash && groups.includes(res.grouphash) && !nodes.includes(res['.name']))
					nodes.push(res['.name']);
			});
			for (let node of subscription_nodes)
				if (proxy_nodes[node] && !nodes.includes(node))
					nodes.push(node);
			for (let node of selected_nodes)
				if (proxy_nodes[node] && !nodes.includes(node))
					nodes.push(node);
			for (let node of policy_nodes)
				if (node !== section_id && routing_groups[node] && !nodes.includes(node))
					nodes.push(node);

			return nodes;
		};

		m = new form.Map('homeproxy', _('HomeProxy'),
			_('OpenWrt-designed Sing-box proxy management platform. It is recommended to disable Dnsmasq DNS redirection.'));

		s = m.section(form.TypedSection);
		s.render = function () {
			poll.add(function () {
				return Promise.all([
					L.resolveDefault(getServiceStatus(), false),
					L.resolveDefault(callCurrentNode(), null)
				]).then((res) => {
					let isRunning = res[0],
					    current = res[1],
					    current_label = null;

					if (current?.mode === 'urltest') {
						let active = current.active || {};
						let nodeName = (active?.id && active.id !== 'urltest') ? (proxy_nodes[active.id] || active.label || active.id) : _('Invalid node');

						current_label = _('URLTest: %s').format(nodeName);
					}

					updateCoreStatus(isRunning, current_label);
					});
				});

			let actions = [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, () => callRCInit('homeproxy', 'reload'))
				}, [ _('Reload Service') ]),
				E('button', {
					'class': 'btn cbi-button cbi-button-negative',
					'click': ui.createHandlerFn(this, () => callRCInit('homeproxy', 'restart'))
				}, [ _('Restart Service') ])
			];

			if (routingMode === 'custom') {
				actions.push(
					E('button', {
						'class': 'btn cbi-button cbi-button-positive',
						'click': ui.createHandlerFn(this, updateDashboard)
					}, [ _('Update Panel') ]),
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, (ev) => hp.uploadPanel(null, ev))
					}, [ _('Upload Panel ZIP') ]),
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, openDashboard)
					}, [ _('Open Panel') ])
				);
			}

			return E('div', { class: 'cbi-section', id: 'homeproxy_status_panel' }, [
				E('style', [ statusCss ]),
				E('h3', _('Status')),
				E('div', { class: 'homeproxy-status-grid' }, [
					E('div', { class: 'homeproxy-status-field homeproxy-version-field' }, [
						E('div', { class: 'homeproxy-status-label' }, _('Plugin Version')),
						E('input', { class: 'cbi-input-text', readonly: '', value: packageVersion })
					]),
					E('div', { class: 'homeproxy-status-field homeproxy-core-version-field' }, [
						E('div', { class: 'homeproxy-status-label' }, _('Core Version')),
						E('input', { class: 'cbi-input-text', readonly: '', value: features.version || '-' })
					]),
					E('div', { class: 'homeproxy-status-field homeproxy-core-status-field' }, [
						E('div', { class: 'homeproxy-status-label' }, _('Core Status')),
						E('input', {
							id: 'homeproxy_core_status',
							class: 'cbi-input-text homeproxy-core-status',
							readonly: '',
							value: _('Collecting data...')
						})
					]),
					E('div', { class: 'homeproxy-status-actions' }, actions)
				])
			]);
		}

		s = m.section(form.NamedSection, 'config', 'homeproxy');

		s.tab('routing', _('Routing Settings'));

		o = s.taboption('routing', form.ListValue, 'main_node', _('Main node'));
		o.value('nil', _('Disable'));
		o.value('urltest', _('URLTest'));
		for (let i in proxy_nodes)
			o.value(i, proxy_nodes[i]);
		o.default = 'nil';
		o.depends({'routing_mode': 'custom', '!reverse': true});
		o.rmempty = false;

		o = s.taboption('routing', hp.CBIStaticList, 'main_urltest_nodes', _('URLTest nodes'),
			_('List of nodes to test.'));
		for (let i in proxy_nodes)
			o.value(i, proxy_nodes[i]);
		o.depends('main_node', 'urltest');
		o.rmempty = false;

		o = s.taboption('routing', form.Value, 'main_urltest_interval', _('Test interval'),
			_('The test interval in seconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '180';
		o.depends('main_node', 'urltest');

		o = s.taboption('routing', form.Value, 'main_urltest_tolerance', _('Test tolerance'),
			_('The test tolerance in milliseconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '50';
		o.depends('main_node', 'urltest');

		o = s.taboption('routing', form.ListValue, 'main_udp_node', _('Main UDP node'));
		o.value('nil', _('Disable'));
		o.value('same', _('Same as main node'));
		o.value('urltest', _('URLTest'));
		for (let i in proxy_nodes)
			o.value(i, proxy_nodes[i]);
		o.default = 'same';
		o.depends({'routing_mode': /^((?!custom).)+$/, 'proxy_mode': /^((?!redirect$).)+$/});
		o.rmempty = false;

		o = s.taboption('routing', hp.CBIStaticList, 'main_udp_urltest_nodes', _('URLTest nodes'),
			_('List of nodes to test.'));
		for (let i in proxy_nodes)
			o.value(i, proxy_nodes[i]);
		o.depends('main_udp_node', 'urltest');
		o.rmempty = false;

		o = s.taboption('routing', form.Value, 'main_udp_urltest_interval', _('Test interval'),
			_('The test interval in seconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '180';
		o.depends('main_udp_node', 'urltest');

		o = s.taboption('routing', form.Value, 'main_udp_urltest_tolerance', _('Test tolerance'),
			_('The test tolerance in milliseconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '50';
		o.depends('main_udp_node', 'urltest');

		o = s.taboption('routing', form.Value, 'dns_server', _('DNS server'),
			_('Support UDP, TCP, DoH, DoQ, DoT. TCP protocol will be used if not specified.'));
		o.value('wan', _('WAN DNS (read from interface)'));
		o.value('https://dns.cloudflare.com/dns-query', _('CloudFlare Public DNS (DoH)'));
		o.value('https://dns.google/dns-query', _('Google Public DNS (DoH)'));
		o.value('https://dns.quad9.net/dns-query', _('Quad9 Public DNS (DoH)'));
		o.value('https://dns.adguard-dns.com/dns-query', _('AdGuard Public DNS (DoH)'));
		o.value('https://dns.sb/dns-query', _('DNS.SB Public DNS (DoH)'));
		o.value('https://dns.opendns.com/dns-query', _('Cisco Public DNS (DoH)'));
		o.default = 'https://dns.quad9.net/dns-query';
		o.rmempty = false;
		o.depends({'routing_mode': 'custom', '!reverse': true});
		o.validate = function(section_id, value) {
			if (section_id && !['wan'].includes(value)) {
				if (!value)
					return _('Expecting: %s').format(_('non-empty value'));

				let ipv6_support = this.section.formvalue(section_id, 'ipv6_support');
				try {
					let url = new URL(value.replace(/^.*:\/\//, 'http://'));
					if (stubValidator.apply('hostname', url.hostname))
						return true;
					else if (stubValidator.apply('ip4addr', url.hostname))
						return true;
					else if ((ipv6_support === '1') && stubValidator.apply('ip6addr', url.hostname.match(/^\[(.+)\]$/)?.[1]))
						return true;
					else
						return _('Expecting: %s').format(_('valid DNS server address'));
				} catch(e) {}

				if (!stubValidator.apply((ipv6_support === '1') ? 'ipaddr' : 'ip4addr', value))
					return _('Expecting: %s').format(_('valid DNS server address'));
			}

			return true;
		}

		o = s.taboption('routing', form.Value, 'china_dns_server', _('China DNS server'),
			_('The dns server for resolving China domains. Support UDP, TCP, DoH, DoQ, DoT.'));
		o.value('wan', _('WAN DNS (read from interface)'));
		o.value('https://doh-pure.onedns.net/dns-query', _('ThreatBook Public DNS (DoH)'));
		o.value('https://doh.pub/dns-query', _('Tencent Public DNS (DoH)'));
		o.value('https://dns.alidns.com/dns-query', _('AliYun Public DNS (DoH)'));
		o.depends('routing_mode', 'bypass_mainland_china');
		o.default = 'https://dns.alidns.com/dns-query';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (section_id && !['wan'].includes(value)) {
				if (!value)
					return _('Expecting: %s').format(_('non-empty value'));

				try {
					let url = new URL(value.replace(/^.*:\/\//, 'http://'));
					if (stubValidator.apply('hostname', url.hostname))
						return true;
					else if (stubValidator.apply('ip4addr', url.hostname))
						return true;
					else if (stubValidator.apply('ip6addr', url.hostname.match(/^\[(.+)\]$/)?.[1]))
						return true;
					else
						return _('Expecting: %s').format(_('valid DNS server address'));
				} catch(e) {}

				if (!stubValidator.apply('ipaddr', value))
					return _('Expecting: %s').format(_('valid DNS server address'));
			}

			return true;
		}

		o = s.taboption('routing', form.ListValue, 'routing_mode', _('Routing mode'));
		o.value('gfwlist', _('GFWList'));
		o.value('bypass_mainland_china', _('Bypass mainland China'));
		o.value('proxy_mainland_china', _('Only proxy mainland China'));
		o.value('custom', _('Custom routing'));
		o.value('global', _('Global'));
		o.default = 'bypass_mainland_china';
		o.rmempty = false;
		o.onchange = function(ev, section_id, value) {
			if (section_id && value === 'custom')
				this.map.save(null, true);
		}

		o = s.taboption('routing', form.Value, 'routing_port', _('Routing ports'),
			_('Specify target ports to be proxied. Multiple ports must be separated by commas.'));
		o.value('', _('All ports'));
		o.value('common', _('Common ports only (bypass P2P traffic)'));
		o.validate = function(section_id, value) {
			if (section_id && value && value !== 'common') {

				let ports = [];
				for (let i of value.split(',')) {
					if (!stubValidator.apply('port', i) && !stubValidator.apply('portrange', i))
						return _('Expecting: %s').format(_('valid port value'));
					if (ports.includes(i))
						return _('Port %s alrealy exists!').format(i);
					ports = ports.concat(i);
				}
			}

			return true;
		}

		o = s.taboption('routing', form.ListValue, 'proxy_mode', _('Proxy mode'));
		o.value('redirect', _('Redirect TCP'));
		if (features.hp_has_tproxy)
			o.value('redirect_tproxy', _('Redirect TCP + TProxy UDP'));
		if (features.hp_has_ip_full && features.hp_has_tun) {
			o.value('redirect_tun', _('Redirect TCP + Tun UDP'));
			o.value('tun', _('Tun TCP/UDP'));
		} else {
			o.description = _('To enable Tun support, you need to install <code>ip-full</code> and <code>kmod-tun</code>');
		}
		o.default = 'redirect_tproxy';
		o.rmempty = false;

		o = s.taboption('routing', form.Flag, 'ipv6_support', _('IPv6 support'));
		o.default = o.enabled;
		o.rmempty = false;

		/* Custom routing settings start */
		/* Routing settings start */
		o = s.taboption('routing', form.SectionValue, '_routing', form.NamedSection, 'routing', 'homeproxy');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		so = ss.option(form.ListValue, 'tcpip_stack', _('TCP/IP stack'),
			_('TCP/IP stack.'));
		if (features.with_gvisor) {
			so.value('mixed', _('Mixed'));
			so.value('gvisor', _('gVisor'));
		}
		so.value('system', _('System'));
		so.default = 'system';
		so.depends('homeproxy.config.proxy_mode', 'redirect_tun');
		so.depends('homeproxy.config.proxy_mode', 'tun');
		so.rmempty = false;
		so.onchange = function(ev, section_id, value) {
			let desc = ev.target.nextElementSibling;
			if (value === 'mixed')
				desc.innerHTML = _('Mixed <code>system</code> TCP stack and <code>gVisor</code> UDP stack.')
			else if (value === 'gvisor')
				desc.innerHTML = _('Based on google/gvisor.');
			else if (value === 'system')
				desc.innerHTML = _('Less compatibility and sometimes better performance.');
		}

		so = ss.option(form.Value, 'udp_timeout', _('UDP NAT expiration time'),
			_('In seconds.'));
		so.datatype = 'uinteger';
		so.placeholder = '300';
		so.depends('homeproxy.config.proxy_mode', 'redirect_tproxy');
		so.depends('homeproxy.config.proxy_mode', 'redirect_tun');
		so.depends('homeproxy.config.proxy_mode', 'tun');

		so = ss.option(form.Flag, 'bypass_cn_traffic', _('Bypass CN traffic'),
			_('Bypass mainland China traffic via firewall rules by default.'));
		so.rmempty = false;

		so = ss.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
			_('If set, the requested domain name will be resolved to IP before routing.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);

		so = ss.option(form.Flag, 'sniff_override', _('Override destination'),
			_('Override the connection destination address with the sniffed domain.'));
		so.default = so.enabled;
		so.rmempty = false;

		so = ss.option(form.ListValue, 'default_outbound', _('Default outbound (fallback)'),
			_('Default outbound for connections not matched by any routing rules.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('nil', _('Disable (the service)'));
			this.value('direct-out', _('Direct'));
			this.value('block-out', _('Block'));
			uci.sections(data[0], 'routing_node', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.default = 'nil';
		so.rmempty = false;

		so = ss.option(form.ListValue, 'default_outbound_dns', _('Default outbound DNS'),
			_('Default DNS server for resolving domain name in the server address.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('default-dns', _('Default DNS (issued by WAN)'));
			this.value('system-dns', _('System DNS'));
			uci.sections(data[0], 'dns_server', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.default = 'default-dns';
		so.rmempty = false;
		/* Routing settings end */

		/* Routing nodes start */
		s.tab('routing_node', _('Routing Nodes'));
		o = s.taboption('routing_node', form.SectionValue, '_routing_node', form.GridSection, 'routing_node');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('Routing node'), _('Add a routing node'), data[0]);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, data[0]);
		ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss);

		so = ss.option(form.Value, 'label', _('Label'));
		so.load = L.bind(hp.loadDefaultLabel, this, data[0]);
		so.validate = L.bind(hp.validateUniqueValue, this, data[0], 'routing_node', 'label');
		so.modalonly = true;

		so = ss.option(form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.option(form.ListValue, 'node', _('Node'),
			_('Outbound node'));
		so.value('urltest', _('Auto select'));
		so.value('selector', _('Manual select'));
		for (let i in proxy_nodes)
			so.value(i, proxy_nodes[i]);
		so.default = 'selector';
		so.rmempty = false;
		so.formvalue = function(section_id) {
			let widget = this.getUIElement(section_id),
			    cbid = this.cbid(section_id),
			    overlay = document.getElementById('modal_overlay'),
			    input = null;

			if (overlay)
				for (let el of overlay.querySelectorAll('input, select'))
					if (el.id === cbid || el.name === cbid) {
						input = el;
						break;
					}

			return widget?.getValue() ||
				input?.value ||
				uci.get(data[0], section_id, 'node') ||
				this.default ||
				'selector';
		}
		so.validate = function(section_id, value) {
			value = value || this.formvalue(section_id);

			let result = hp.validateUniqueValue(data[0], 'routing_node', 'node', section_id, value);
			if (result !== true)
				return result;

			if (section_id && (value === 'urltest' || value === 'selector')) {
				let groups = normalizeFormList(this.section.formvalue(section_id, 'subscription_groups')),
				    subscription_nodes = normalizeFormList(this.section.formvalue(section_id, 'subscription_nodes')),
				    selected = normalizeFormList(this.section.formvalue(section_id, 'selected_nodes')),
				    policy_nodes = normalizeFormList(this.section.formvalue(section_id, 'policy_nodes'));

				if (!groups.length && !subscription_nodes.length && !selected.length && !policy_nodes.length)
					return _('Expecting: %s').format(_('non-empty value'));
			}

			return true;
		}

		so = ss.option(form.ListValue, 'domain_resolver', _('Domain resolver'),
			_('For resolving domain name in the server address.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('', _('Default'));
			this.value('default-dns', _('Default DNS (issued by WAN)'));
			this.value('system-dns', _('System DNS'));
			uci.sections(data[0], 'dns_server', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.depends('node', /^((?!(urltest|selector)$).)+$/);
		so.modalonly = true;

		so = ss.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
			_('The domain strategy for resolving the domain name in the address.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);
		so.depends('node', /^((?!(urltest|selector)$).)+$/);
		so.modalonly = true;

		so = ss.option(widgets.DeviceSelect, 'bind_interface', _('Bind interface'),
			_('The network interface to bind to.'));
		so.multiple = false;
		so.noaliases = true;
		so.depends({'outbound': '', 'node': /^((?!(urltest|selector)$).)+$/});
		so.modalonly = true;

		so = ss.option(form.ListValue, 'outbound', _('Outbound'),
			_('The tag of the upstream outbound.<br/>Other dial fields will be ignored when enabled.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('', _('Direct'));
			uci.sections(data[0], 'routing_node', (res) => {
				if (res['.name'] !== section_id && res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.validate = function(section_id, value) {
			if (section_id && value) {
				let node = this.section.formvalue(section_id, 'node');

				let conflict = false;
				uci.sections(data[0], 'routing_node', (res) => {
					if (res['.name'] !== section_id) {
						if (res.outbound === section_id && res['.name'] == value)
							conflict = true;
						else if (res.node === 'urltest' && normalizeFormList(res.urltest_nodes).includes(node) && res['.name'] == value)
							conflict = true;
						else if (res.node === 'urltest' && normalizeFormList(res.subscription_nodes).includes(node) && res['.name'] == value)
							conflict = true;
						else if (res.node === 'urltest' && normalizeFormList(res.selected_nodes).includes(node) && res['.name'] == value)
							conflict = true;
						else if (res.node === 'selector' && normalizeFormList(res.selected_nodes).includes(node) && res['.name'] == value)
							conflict = true;
						else if (res.node === 'selector' && normalizeFormList(res.subscription_nodes).includes(node) && res['.name'] == value)
							conflict = true;
					}
				});
				if (conflict)
					return _('Recursive outbound detected!');
			}

			return true;
		}
		so.depends('node', /^((?!(urltest|selector)$).)+$/);
		so.editable = true;

		so = ss.option(hp.CBIMultiValue, 'subscription_groups', _('Subscriptions'));
		for (let hash in subscription_groups)
			so.value(hash, subscription_groups[hash]);
		so.depends('node', 'urltest');
		so.depends('node', 'selector');
		so.rmempty = true;
		so.modalonly = true;

		so = ss.option(hp.CBIMultiValue, 'subscription_nodes', _('Subscription nodes'),
			_('List of nodes from subscriptions.'));
		uci.sections(data[0], 'node', (res) => {
			if (res.grouphash)
				so.value(res['.name'], proxy_nodes[res['.name']]);
		});
		so.depends('node', 'urltest');
		so.depends('node', 'selector');
		so.rmempty = true;
		so.modalonly = true;

		so = ss.option(hp.CBIMultiValue, 'selected_nodes', _('Custom nodes'));
		uci.sections(data[0], 'node', (res) => {
			if (!res.grouphash)
				so.value(res['.name'], proxy_nodes[res['.name']]);
		});
		so.depends('node', 'urltest');
		so.depends('node', 'selector');
		so.rmempty = true;
		so.modalonly = true;

		so = ss.option(hp.CBIMultiValue, 'policy_nodes', _('Policy nodes'),
			_('List of policy groups.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			uci.sections(data[0], 'routing_node', (res) => {
				if (res['.name'] !== section_id && res.enabled === '1' && ['urltest', 'selector'].includes(res.node))
					this.value(res['.name'], res.label || res['.name']);
			});

			return this.super('load', section_id);
		}
		so.validate = function(section_id, value) {
			if (normalizeFormList(value).includes(section_id))
				return _('Recursive outbound detected!');

			return true;
		}
		so.depends('node', 'selector');
		so.rmempty = true;
		so.modalonly = true;

		so = ss.option(form.ListValue, 'selector_default', _('Default node'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			let groups = normalizeFormList(this.section.formvalue(section_id, 'subscription_groups')),
			    subscription_nodes = normalizeFormList(this.section.formvalue(section_id, 'subscription_nodes')),
			    selected = normalizeFormList(this.section.formvalue(section_id, 'selected_nodes')),
			    policy_nodes = normalizeFormList(this.section.formvalue(section_id, 'policy_nodes'));

			this.value('', _('Default'));
			for (let node of collectSelectedRoutingNodes(groups, subscription_nodes, selected, policy_nodes, section_id))
				this.value(node, proxy_nodes[node] || routing_groups[node]);

			return this.super('load', section_id);
		}
		so.validate = function(section_id, value) {
			if (!value)
				return true;

			let groups = normalizeFormList(this.section.formvalue(section_id, 'subscription_groups')),
			    subscription_nodes = normalizeFormList(this.section.formvalue(section_id, 'subscription_nodes')),
			    selected = normalizeFormList(this.section.formvalue(section_id, 'selected_nodes')),
			    policy_nodes = normalizeFormList(this.section.formvalue(section_id, 'policy_nodes'));

			if (!collectSelectedRoutingNodes(groups, subscription_nodes, selected, policy_nodes, section_id).includes(value))
				return _('Invalid node');

			return true;
		}
		so.depends('node', 'selector');
		so.modalonly = true;

		so = ss.option(form.Flag, 'selector_interrupt_exist_connections', _('Interrupt existing connections'),
			_('Interrupt existing connections when the selected outbound has changed.'));
		so.depends('node', 'selector');
		so.modalonly = true;

		so = ss.option(form.Value, 'urltest_url', _('Test URL'),
			_('The URL to test.'));
		so.placeholder = 'https://www.gstatic.com/generate_204';
		so.validate = function(section_id, value) {
			if (section_id && value) {
				try {
					let url = new URL(value);
					if (!url.hostname)
						return _('Expecting: %s').format(_('valid URL'));
				}
				catch(e) {
					return _('Expecting: %s').format(_('valid URL'));
				}
			}

			return true;
		}
		so.depends('node', 'urltest');
		so.modalonly = true;

		so = ss.option(form.Value, 'urltest_interval', _('Test interval'),
			_('The test interval in seconds.'));
		so.datatype = 'uinteger';
		so.placeholder = '180';
		so.validate = function(section_id, value) {
			if (section_id && value) {
				let idle_timeout = this.section.formvalue(section_id, 'idle_timeout') || '1800';
				if (parseInt(value) > parseInt(idle_timeout))
					return _('Test interval must be less or equal than idle timeout.');
			}

			return true;
		}
		so.depends('node', 'urltest');
		so.modalonly = true;

		so = ss.option(form.Value, 'urltest_tolerance', _('Test tolerance'),
			_('The test tolerance in milliseconds.'));
		so.datatype = 'uinteger';
		so.placeholder = '50';
		so.depends('node', 'urltest');
		so.modalonly = true;

		so = ss.option(form.Value, 'urltest_idle_timeout', _('Idle timeout'),
			_('The idle timeout in seconds.'));
		so.datatype = 'uinteger';
		so.placeholder = '1800';
		so.depends('node', 'urltest');
		so.modalonly = true;

		so = ss.option(form.Flag, 'urltest_interrupt_exist_connections', _('Interrupt existing connections'),
			_('Interrupt existing connections when the selected outbound has changed.'));
		so.depends('node', 'urltest');
		so.modalonly = true;
		/* Routing nodes end */

		/* Routing rules start */
		s.tab('routing_rule', _('Routing Rules'));
		o = s.taboption('routing_rule', form.SectionValue, '_routing_rule', form.GridSection, 'routing_rule');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('Routing rule'), _('Add a routing rule'), data[0]);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, data[0]);
		ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss);

		ss.tab('field_other', _('Other fields'));
		ss.tab('field_host', _('Host/IP fields'));
		ss.tab('field_port', _('Port fields'));
		ss.tab('fields_process', _('Process fields'));

		so = ss.taboption('field_other', form.Value, 'label', _('Label'));
		so.load = L.bind(hp.loadDefaultLabel, this, data[0]);
		so.validate = L.bind(hp.validateUniqueValue, this, data[0], 'routing_rule', 'label');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.taboption('field_other', form.ListValue, 'mode', _('Mode'),
			_('In default mode, rule fields are matched by category. Any condition in the same category can match, while different categories must match at the same time. Rule sets are merged into the rule for matching and are not treated as separate sub-rules.'));
		so.value('default', _('Default'));
		so.default = 'default';
		so.rmempty = false;
		so.readonly = true;

		so = ss.taboption('field_other', form.ListValue, 'ip_version', _('IP version'),
			_('4 or 6. Not limited if empty.'));
		so.value('4', _('IPv4'));
		so.value('6', _('IPv6'));
		so.value('', _('Both'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.MultiValue, 'protocol', _('Protocol'),
			_('Sniffed protocol, see <a target="_blank" href="https://sing-box.sagernet.org/configuration/route/sniff/">Sniff</a> for details.'));
		so.value('bittorrent', _('BitTorrent'));
		so.value('dns', _('DNS'));
		so.value('dtls', _('DTLS'));
		so.value('http', _('HTTP'));
		so.value('quic', _('QUIC'));
		so.value('rdp', _('RDP'));
		so.value('ssh', _('SSH'));
		so.value('stun', _('STUN'));
		so.value('tls', _('TLS'));

		so = ss.taboption('field_other', form.Value, 'client', _('Client'),
			_('Sniffed client type (QUIC client type or SSH client name).'));
		so.value('chromium', _('Chromium / Cronet'));
		so.value('firefox', _('Firefox / uquic firefox'));
		so.value('quic-go', _('quic-go / uquic chrome'));
		so.value('safari', _('Safari / Apple Network API'));
		so.depends('protocol', 'quic');
		so.depends('protocol', 'ssh');
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'network', _('Network'));
		so.value('tcp', _('TCP'));
		so.value('udp', _('UDP'));
		so.value('', _('Both'));

		so = ss.taboption('field_other', form.DynamicList, 'user', _('User'),
			_('Match user name.'));
		so.modalonly = true;

		so = ss.taboption('field_other', hp.CBIStaticList, 'rule_set', _('Rule set'),
			_('Match rule set.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			uci.sections(data[0], 'ruleset', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.tag || res.label);
			});

			return this.super('load', section_id);
		}
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'rule_set_ip_cidr_match_source', _('Rule set IP CIDR as source IP'),
			_('Make IP CIDR in rule set used to match the source IP.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'invert', _('Invert'),
			_('Invert match result.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'action', _('Action'));
		so.value('route', _('Route'));
		so.value('route-options', _('Route options'));
		so.value('reject', _('Reject'));
		so.value('resolve', _('Resolve'));
		so.default = 'route';
		so.rmempty = false;
		so.editable = true;

		so = ss.taboption('field_other', form.ListValue, 'outbound', _('Outbound'),
			_('Tag of the target outbound.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('direct-out', _('Direct'));
			uci.sections(data[0], 'routing_node', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.rmempty = false;
		so.depends('action', 'route');
		so.editable = true;

		so = ss.taboption('field_other', form.Value, 'override_address', _('Override address'),
			_('Override the connection destination address.'));
		so.datatype = 'ipaddr';
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'override_port', _('Override port'),
			_('Override the connection destination port.'));
		so.datatype = 'port';
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'udp_disable_domain_unmapping', _('Disable UDP domain unmapping'),
			_('If enabled, for UDP proxy requests addressed to a domain, the original packet address will be sent in the response instead of the mapped domain.'));
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'udp_connect', _('connect UDP connections'),
			_('If enabled, attempts to connect UDP connection to the destination instead of listen.'));
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'udp_timeout', _('UDP timeout'),
			_('Timeout for UDP connections.<br/>Setting a larger value than the UDP timeout in inbounds will have no effect.'));
		so.datatype = 'uinteger';
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'tls_record_fragment', _('TLS record fragment'),
			_('Fragment TLS handshake into multiple TLS records.'));
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'tls_fragment', _('TLS fragment'),
			_('Fragment TLS handshakes. Due to poor performance, try <code>%s</code> first.').format(
				_('TLS record fragment')));
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'tls_fragment_fallback_delay', _('Fragment fallback delay'),
			_('The fallback value in milliseconds used when TLS segmentation cannot automatically determine the wait time.'));
		so.datatype = 'uinteger';
		so.placeholder = '500';
		so.depends('tls_fragment', '1');
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'resolve_server', _('DNS server'),
			_('Specifies DNS server tag to use instead of selecting through DNS routing.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('', _('Default'));
			this.value('default-dns', _('Default DNS (issued by WAN)'));
			this.value('system-dns', _('System DNS'));
			uci.sections(data[0], 'dns_server', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.depends('action', 'resolve');
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'reject_method', _('Method'));
		so.value('default', _('Reply with TCP RST / ICMP port unreachable'));
		so.value('drop', _('Drop packets'));
		so.depends('action', 'reject');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'reject_no_drop', _('Don\'t drop packets'),
			_('<code>%s</code> will be temporarily overwritten to <code>%s</code> after 50 triggers in 30s if not enabled.').format(
			_('Method'), _('Drop packets')));
		so.depends('reject_method', 'default');
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'resolve_strategy', _('Resolve strategy'),
			_('Domain strategy for resolving the domain names.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);
		so.depends('action', 'resolve');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'resolve_disable_cache', _('Disable DNS memory cache'),
			_('Disable DNS memory cache in this query.'));
		so.depends('action', 'resolve');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'resolve_rewrite_ttl', _('Rewrite TTL'),
			_('Rewrite TTL in DNS responses.'));
		so.datatype = 'uinteger';
		so.depends('action', 'resolve');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'resolve_client_subnet', _('EDNS Client subnet'),
			_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
			'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
		so.datatype = 'or(cidr, ipaddr)';
		so.depends('action', 'resolve');
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'domain', _('Domain name'),
			_('Match full domain.'));
		so.datatype = 'hostname';
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'domain_suffix', _('Domain suffix'),
			_('Match domain suffix.'));
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'domain_keyword', _('Domain keyword'),
			_('Match domain using keyword.'));
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'domain_regex', _('Domain regex'),
			_('Match domain using regular expression.'));
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'source_ip_cidr', _('Source IP CIDR'),
			_('Match source IP CIDR.'));
		so.datatype = 'or(cidr, ipaddr)';
		so.modalonly = true;

		so = ss.taboption('field_host', form.Flag, 'source_ip_is_private', _('Match private source IP'));
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'ip_cidr', _('IP CIDR'),
			_('Match IP CIDR.'));
		so.datatype = 'or(cidr, ipaddr)';
		so.modalonly = true;

		so = ss.taboption('field_host', form.Flag, 'ip_is_private', _('Match private IP'));
		so.modalonly = true;

		so = ss.taboption('field_port', form.DynamicList, 'source_port', _('Source port'),
			_('Match source port.'));
		so.datatype = 'port';
		so.modalonly = true;

		so = ss.taboption('field_port', form.DynamicList, 'source_port_range', _('Source port range'),
			_('Match source port range. Format as START:/:END/START:END.'));
		so.validate = hp.validatePortRange;
		so.modalonly = true;

		so = ss.taboption('field_port', form.DynamicList, 'port', _('Port'),
			_('Match port.'));
		so.datatype = 'port';
		so.modalonly = true;

		so = ss.taboption('field_port', form.DynamicList, 'port_range', _('Port range'),
			_('Match port range. Format as START:/:END/START:END.'));
		so.validate = hp.validatePortRange;
		so.modalonly = true;

		so = ss.taboption('fields_process', form.DynamicList, 'process_name', _('Process name'),
			_('Match process name.'));
		so.modalonly = true;

		so = ss.taboption('fields_process', form.DynamicList, 'process_path', _('Process path'),
			_('Match process path.'));
		so.modalonly = true;

		so = ss.taboption('fields_process', form.DynamicList, 'process_path_regex', _('Process path (regex)'),
			_('Match process path using regular expression.'));
		so.modalonly = true;
		/* Routing rules end */

		/* DNS settings start */
		s.tab('dns', _('DNS Settings'));
		o = s.taboption('dns', form.SectionValue, '_dns', form.NamedSection, 'dns', 'homeproxy');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		so = ss.option(form.ListValue, 'default_strategy', _('Default DNS strategy'),
			_('The DNS strategy for resolving the domain name in the address.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);

		so = ss.option(form.ListValue, 'default_server', _('Default DNS server'),
			_('Daily domain name resolution for clients. Choose an overseas DNS if DNS leak protection is required.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('default-dns', _('Default DNS (issued by WAN)'));
			this.value('system-dns', _('System DNS'));
			uci.sections(data[0], 'dns_server', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.default = 'default-dns';
		so.rmempty = false;

		so = ss.option(form.Flag, 'disable_cache', _('Disable DNS memory cache'));

		so = ss.option(form.Flag, 'disable_cache_expire', _('Disable DNS memory cache expiration'));
		so.depends('disable_cache', '0');

		so = ss.option(form.Flag, 'independent_cache', _('Independent DNS memory cache per server'),
			_('Make each DNS server\'s memory cache independent for special purposes. If enabled, will slightly degrade performance.'));
		so.depends('disable_cache', '0');

		so = ss.option(form.Value, 'client_subnet', _('EDNS Client subnet'),
			_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
			'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
		so.datatype = 'or(cidr, ipaddr)';

		/* DNS settings end */

		/* DNS servers start */
		s.tab('dns_server', _('DNS Servers'));
		o = s.taboption('dns_server', form.SectionValue, '_dns_server', form.GridSection, 'dns_server');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('DNS server'), _('Add a DNS server'), data[0]);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, data[0]);
		ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss);

		so = ss.option(form.Value, 'label', _('Label'));
		so.load = L.bind(hp.loadDefaultLabel, this, data[0]);
		so.validate = L.bind(hp.validateUniqueValue, this, data[0], 'dns_server', 'label');
		so.modalonly = true;

		so = ss.option(form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.option(form.ListValue, 'type', _('Type'));
		so.value('udp', _('UDP'));
		so.value('tcp', _('TCP'));
		so.value('tls', _('TLS'));
		so.value('https', _('HTTPS'));
		so.value('h3', _('HTTP/3'));
		so.value('quic', _('QUIC'));
		so.default = 'udp';
		so.rmempty = false;

		so = ss.option(form.Value, 'server', _('Address'),
			_('Full URL, e.g. https://dns.alidns.com/dns-query'));
		so.placeholder = '';
		so.validate = function(section_id, value) {
			let type = this.section.formvalue(section_id, 'type') ||
				uci.get(data[0], section_id, 'type') ||
				'udp';

			if (!validateDnsServerAddress(type, value))
				return _('Expecting: %s').format(_('valid DNS server address'));

			return true;
		}
		so.renderWidget = function(section_id, option_index, cfgvalue) {
			let node = form.Value.prototype.renderWidget.apply(this, arguments),
			    input = node.querySelector('input'),
			    update = () => {
				let type = this.section.formvalue(section_id, 'type') ||
					uci.get(data[0], section_id, 'type') ||
					'udp';
				if (input)
					input.placeholder = getDnsServerAddressPlaceholder(type);
			};

			update();
			requestAnimationFrame(() => {
				let type_input = document.getElementById(this.cbid(section_id).replace(/\.server$/, '.type'));
				if (type_input) {
					type_input.addEventListener('change', update);
					update();
				}
			});

			return node;
		}
		so.rmempty = false;

		so = ss.option(form.Value, 'server_port', _('Port'),
			_('Leave empty to use the default port.'));
		so.placeholder = '53';
		so.datatype = 'port';
		so.renderWidget = function(section_id, option_index, cfgvalue) {
			let node = form.Value.prototype.renderWidget.apply(this, arguments),
			    input = node.querySelector('input'),
			    update = () => {
				let type = this.section.formvalue(section_id, 'type') ||
					uci.get(data[0], section_id, 'type') ||
					'udp';
				if (input)
					input.placeholder = getDnsServerDefaultPort(type);
			};

			update();
			requestAnimationFrame(() => {
				let type_input = document.getElementById(this.cbid(section_id).replace(/\.server_port$/, '.type'));
				if (type_input) {
					type_input.addEventListener('change', update);
					update();
				}
			});

			return node;
		}
		so.depends('type', 'udp');
		so.depends('type', 'tcp');
		so.depends('type', 'tls');
		so.depends('type', 'quic');

		so = ss.option(form.DynamicList, 'headers', _('Headers'),
			_('Additional headers to be sent to the DNS server.'));
		so.depends('type', 'https');
		so.depends('type', 'h3');
		so.modalonly = true;

		so = ss.option(form.Value, 'tls_sni', _('TLS SNI'),
			_('Used to verify the hostname on the returned certificates.'));
		so.depends('type', 'tls');
		so.depends('type', 'https');
		so.depends('type', 'h3');
		so.depends('type', 'quic');
		so.modalonly = true;

		so = ss.option(form.ListValue, 'address_resolver', _('Address resolver'),
			_('Used to resolve DNS server addresses in domain form. IP addresses do not require it.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('', _('None'));
			this.value('default-dns', _('Default DNS (issued by WAN)'));
			this.value('system-dns', _('System DNS'));
			uci.sections(data[0], 'dns_server', (res) => {
				if (res['.name'] !== section_id && res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.validate = function(section_id, value) {
			if (section_id && value) {
				let conflict = false;
				uci.sections(data[0], 'dns_server', (res) => {
					if (res['.name'] !== section_id)
						if (res.address_resolver === section_id && res['.name'] == value)
							conflict = true;
				});
				if (conflict)
					return _('Recursive resolver detected!');
			}

			return true;
		}
		so.modalonly = true;

		so = ss.option(form.ListValue, 'address_strategy', _('Address strategy'),
			_('The domain strategy for resolving the domain name in the address.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);
		so.depends({'address_resolver': '', '!reverse': true});
		so.modalonly = true;

		so = ss.option(form.ListValue, 'outbound', _('Outbound'),
			_('Tag of an outbound for connecting to the dns server.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('direct-out', _('Direct'));
			uci.sections(data[0], 'routing_node', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.default = 'direct-out';
		so.rmempty = false;
		so.editable = true;
		/* DNS servers end */

		/* DNS rules start */
		s.tab('dns_rule', _('DNS Rules'));
		o = s.taboption('dns_rule', form.SectionValue, '_dns_rule', form.GridSection, 'dns_rule');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('DNS rule'), _('Add a DNS rule'), data[0]);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, data[0]);
		ss.renderSectionAdd = L.bind(hp.renderSectionAdd, this, ss);

		ss.tab('field_other', _('Other fields'));
		ss.tab('field_host', _('Host/IP fields'));
		ss.tab('field_port', _('Port fields'));
		ss.tab('fields_process', _('Process fields'));

		so = ss.taboption('field_other', form.Value, 'label', _('Label'));
		so.load = L.bind(hp.loadDefaultLabel, this, data[0]);
		so.validate = L.bind(hp.validateUniqueValue, this, data[0], 'dns_rule', 'label');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.taboption('field_other', form.ListValue, 'mode', _('Mode'),
			_('In default mode, rule fields are matched by category. Any condition in the same category can match, while different categories must match at the same time. Rule sets are merged into the rule for matching and are not treated as separate sub-rules.'));
		so.value('default', _('Default'));
		so.default = 'default';
		so.rmempty = false;
		so.readonly = true;
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'ip_version', _('IP version'));
		so.value('4', _('IPv4'));
		so.value('6', _('IPv6'));
		so.value('', _('Both'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'query_type', _('Query type'),
			_('Match query type.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'network', _('Network'));
		so.value('tcp', _('TCP'));
		so.value('udp', _('UDP'));
		so.value('', _('Both'));

		so = ss.taboption('field_other', form.MultiValue, 'protocol', _('Protocol'),
			_('Sniffed protocol, see <a target="_blank" href="https://sing-box.sagernet.org/configuration/route/sniff/">Sniff</a> for details.'));
		so.value('bittorrent', _('BitTorrent'));
		so.value('dtls', _('DTLS'));
		so.value('http', _('HTTP'));
		so.value('quic', _('QUIC'));
		so.value('rdp', _('RDP'));
		so.value('ssh', _('SSH'));
		so.value('stun', _('STUN'));
		so.value('tls', _('TLS'));

		so = ss.taboption('field_other', form.DynamicList, 'user', _('User'),
			_('Match user name.'));
		so.modalonly = true;

		so = ss.taboption('field_other', hp.CBIStaticList, 'rule_set', _('Rule set'),
			_('Match rule set.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			uci.sections(data[0], 'ruleset', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.tag || res.label);
			});

			return this.super('load', section_id);
		}
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'rule_set_ip_cidr_match_source', _('Rule set IP CIDR as source IP'),
			_('Make IP CIDR in rule sets match the source IP.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'rule_set_ip_cidr_accept_empty', _('Accept empty query response'),
			_('Make IP CIDR in rule-sets accept empty query response.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'invert', _('Invert'),
			_('Invert match result.'));
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'action', _('Action'));
		so.value('route', _('Route'));
		so.value('route-options', _('Route options'));
		so.value('reject', _('Reject'));
		so.value('predefined', _('Predefined'));
		so.default = 'route';
		so.rmempty = false;
		so.editable = true;

		so = ss.taboption('field_other', form.ListValue, 'server', _('Server'),
			_('Tag of the target dns server.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('default-dns', _('Default DNS (issued by WAN)'));
			this.value('system-dns', _('System DNS'));
			uci.sections(data[0], 'dns_server', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.rmempty = false;
		so.editable = true;
		so.depends('action', 'route');

		so = ss.taboption('field_other', form.ListValue, 'domain_strategy', _('Domain strategy'),
			_('Set domain strategy for this query.'));
		for (let i in hp.dns_strategy)
			so.value(i, hp.dns_strategy[i]);
		so.depends('action', 'route');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'dns_disable_cache', _('Disable DNS memory cache'),
			_('Disable DNS memory cache and persistent cache in this query.'));
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'rewrite_ttl', _('Rewrite TTL'),
			_('Rewrite TTL in DNS responses.'));
		so.datatype = 'uinteger';
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Value, 'client_subnet', _('EDNS Client subnet'),
			_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
			'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
		so.datatype = 'or(cidr, ipaddr)';
		so.depends('action', 'route');
		so.depends('action', 'route-options');
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'reject_method', _('Method'));
		so.value('default', _('Reply with REFUSED'));
		so.value('drop', _('Drop requests'));
		so.default = 'default';
		so.depends('action', 'reject');
		so.modalonly = true;

		so = ss.taboption('field_other', form.Flag, 'reject_no_drop', _('Don\'t drop requests'),
			_('<code>%s</code> will be temporarily overwritten to <code>%s</code> after 50 triggers in 30s if not enabled.').format(
				_('Method'), _('Drop requests')));
		so.depends('reject_method', 'default');
		so.modalonly = true;

		so = ss.taboption('field_other', form.ListValue, 'predefined_rcode', _('RCode'),
			_('The response code.'));
		so.value('NOERROR');
		so.value('FORMERR');
		so.value('SERVFAIL');
		so.value('NXDOMAIN');
		so.value('NOTIMP');
		so.value('REFUSED');
		so.default = 'NOERROR';
		so.depends('action', 'predefined');
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'predefined_answer', _('Answer'),
			_('List of text DNS record to respond as answers.'));
		so.depends('action', 'predefined');
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'predefined_ns', _('NS'),
			_('List of text DNS record to respond as name servers.'));
		so.depends('action', 'predefined');
		so.modalonly = true;

		so = ss.taboption('field_other', form.DynamicList, 'predefined_extra', _('Extra records'),
			_('List of text DNS record to respond as extra records.'));
		so.depends('action', 'predefined');
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'domain', _('Domain name'),
			_('Match full domain.'));
		so.datatype = 'hostname';
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'domain_suffix', _('Domain suffix'),
			_('Match domain suffix.'));
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'domain_keyword', _('Domain keyword'),
			_('Match domain using keyword.'));
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'domain_regex', _('Domain regex'),
			_('Match domain using regular expression.'));
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'source_ip_cidr', _('Source IP CIDR'),
			_('Match source IP CIDR.'));
		so.datatype = 'or(cidr, ipaddr)';
		so.modalonly = true;

		so = ss.taboption('field_host', form.Flag, 'source_ip_is_private', _('Match private source IP'));
		so.modalonly = true;

		so = ss.taboption('field_host', form.DynamicList, 'ip_cidr', _('IP CIDR'),
			_('Match IP CIDR with query response. Current rule will be skipped if not match.'));
		so.datatype = 'or(cidr, ipaddr)';
		so.modalonly = true;

		so = ss.taboption('field_host', form.Flag, 'ip_is_private', _('Match private IP'),
			_('Match private IP with query response.'));
		so.modalonly = true;

		so = ss.taboption('field_port', form.DynamicList, 'source_port', _('Source port'),
			_('Match source port.'));
		so.datatype = 'port';
		so.modalonly = true;

		so = ss.taboption('field_port', form.DynamicList, 'source_port_range', _('Source port range'),
			_('Match source port range. Format as START:/:END/START:END.'));
		so.validate = hp.validatePortRange;
		so.modalonly = true;

		so = ss.taboption('field_port', form.DynamicList, 'port', _('Port'),
			_('Match port.'));
		so.datatype = 'port';
		so.modalonly = true;

		so = ss.taboption('field_port', form.DynamicList, 'port_range', _('Port range'),
			_('Match port range. Format as START:/:END/START:END.'));
		so.validate = hp.validatePortRange;
		so.modalonly = true;

		so = ss.taboption('fields_process', form.DynamicList, 'process_name', _('Process name'),
			_('Match process name.'));
		so.modalonly = true;

		so = ss.taboption('fields_process', form.DynamicList, 'process_path', _('Process path'),
			_('Match process path.'));
		so.modalonly = true;

		so = ss.taboption('fields_process', form.DynamicList, 'process_path_regex', _('Process path (regex)'),
			_('Match process path using regular expression.'));
		so.modalonly = true;
		/* DNS rules end */
		/* Custom routing settings end */

		/* Rule set settings start */
		s.tab('ruleset', _('Rule Set'));
		o = s.taboption('ruleset', form.SectionValue, '_ruleset', form.GridSection, 'ruleset');
		o.depends('routing_mode', 'custom');

		ss = o.subsection;
		ss.addremove = true;
		ss.rowcolors = true;
		ss.sortable = true;
		ss.nodescriptions = true;
		ss.modaltitle = L.bind(hp.loadModalTitle, this, _('Rule set'), _('Add a rule set'), data[0]);
		ss.sectiontitle = L.bind(hp.loadDefaultLabel, this, data[0]);
		ss.renderSectionAdd = L.bind(renderRuleSetAdd, this, ss);

		so = ss.option(form.Value, 'label', _('Label'));
		so.load = L.bind(hp.loadDefaultLabel, this, data[0]);
		so.validate = L.bind(hp.validateUniqueValue, this, data[0], 'ruleset', 'label');
		so.modalonly = true;

	so = ss.option(form.Value, 'tag', _('Tag'),
		_('Used by sing-box rule sets. Please fill it in yourself.'));
	so.rmempty = false;
		so.validate = function(section_id, value) {
			if (section_id) {
				if (!value)
					return _('Expecting: %s').format(_('non-empty value'));
				if (!value.match(/^[A-Za-z0-9_.-]+$/))
					return _('Expecting: %s').format(_('valid tag'));

				let duplicate = false;
				uci.sections(data[0], 'ruleset', (res) => {
					if (res['.name'] !== section_id)
						if ((res.tag || ('cfg-' + res['.name'] + '-rule')) === value)
							duplicate = true;
				});
				if (duplicate)
					return _('Expecting: %s').format(_('unique value'));
			}

			return true;
		}
		so.modalonly = true;

		so = ss.option(form.Flag, 'enabled', _('Enable'));
		so.default = so.enabled;
		so.rmempty = false;
		so.editable = true;

		so = ss.option(form.ListValue, 'type', _('Type'));
		so.value('local', _('Local'));
		so.value('remote', _('Remote'));
		so.default = 'remote';
		so.rmempty = false;

		so = ss.option(form.ListValue, 'format', _('Format'));
		so.value('binary', _('Binary file'));
		so.value('source', _('Source file'));
		so.default = 'binary';
		so.rmempty = false;

		so = ss.option(form.Value, 'path', _('Path'),
			_('The default rule set directory is /etc/homeproxy/ruleset/.'));
		so.datatype = 'file';
		so.rmempty = false;
		so.depends('type', 'local');
		so.modalonly = true;

		so = ss.option(form.Value, 'url', _('Rule set URL'));
		so.validate = function(section_id, value) {
			if (section_id) {
				if (!value)
					return _('Expecting: %s').format(_('non-empty value'));

				try {
					let url = new URL(value);
					if (!url.hostname)
						return _('Expecting: %s').format(_('valid URL'));
				}
				catch(e) {
					return _('Expecting: %s').format(_('valid URL'));
				}
			}

			return true;
		}
		so.rmempty = false;
		so.depends('type', 'remote');
		so.modalonly = true;

		so = ss.option(form.ListValue, 'outbound', _('Outbound'),
			_('Tag of the outbound to download rule set.'));
		so.load = function(section_id) {
			delete this.keylist;
			delete this.vallist;

			this.value('', _('Default'));
			this.value('direct-out', _('Direct'));
			uci.sections(data[0], 'routing_node', (res) => {
				if (res.enabled === '1')
					this.value(res['.name'], res.label);
			});

			return this.super('load', section_id);
		}
		so.depends('type', 'remote');

		so = ss.option(form.Value, 'remote_path', _('Path'));
		so.default = '/etc/homeproxy/ruleset/';
		so.placeholder = '/etc/homeproxy/ruleset/';
		so.validate = function(section_id, value) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));
			if (!value.match(/^\//))
				return _('Expecting: %s').format(_('absolute path'));

			return true;
		}
		so.rmempty = false;
		so.depends('type', 'remote');
		so.modalonly = true;

		so = ss.option(form.Flag, 'auto_update', _('Auto update'));
		so.default = '1';
		so.rmempty = false;
		so.depends('type', 'remote');
		so.modalonly = true;

		so = ss.option(form.Value, 'update_interval', _('Update time (weekly)'));
		so.renderWidget = function() {
			return hp.renderCronSelector.apply(this, arguments);
		};
		so.default = '0 0 * * *';
		so.rmempty = false;
		so.validate = function(section_id, value) {
			value = value || this.formvalue(section_id);
			if (!validateUpdateCron(value))
				return _('Expecting: %s').format(_('valid cron expression'));

			return true;
		};
		so.depends('type', 'remote');
		/* Rule set settings end */

		s.tab('control', _('Access Control'));

		/* NTP settings start */
		s.tab('ntp', _('NTP Settings'));
		o = s.taboption('ntp', form.SectionValue, '_ntp', form.NamedSection, 'ntp', 'homeproxy');
		o.depends('routing_mode', 'custom');
		ss = o.subsection;

		so = ss.option(form.Flag, 'enabled', _('Enable NTP'));
		so.default = so.enabled;
		so.rmempty = false;

		so = ss.option(form.Value, 'server', _('NTP server address'));
		so.default = 'ntp.aliyun.com';
		so.placeholder = 'ntp.aliyun.com';
		so.rmempty = false;
		so.validate = function(_section_id, value) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));

			return stubValidator.apply('hostname', value) ||
				stubValidator.apply('ip4addr', value) ||
				stubValidator.apply('ip6addr', value);
		};
		so.depends('enabled', '1');

		so = ss.option(form.Value, 'server_port', _('NTP server port'));
		so.default = '123';
		so.placeholder = '123';
		so.datatype = 'port';
		so.rmempty = false;
		so.validate = function(_section_id, value) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));

			return stubValidator.apply('port', value);
		};
		so.depends('enabled', '1');

		so = ss.option(form.Value, 'interval', _('NTP time synchronization interval'),
			_('NTP service always uses direct connection and mainly provides accurate time for sing-box features that depend on it, such as TLS certificate verification, VMess, Reality/uTLS and other time-sensitive connection scenarios.') + '<br />' +
			_('Time format examples: 1m = 1 minute, 1h = 1 hour, 1d = 1 day.'));
		so.default = '30m';
		so.placeholder = '30m';
		so.rmempty = false;
		so.validate = function(_section_id, value) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));
			if (!validateDuration(value))
				return _('Expecting: %s').format(_('valid duration'));

			return true;
		};
		so.depends('enabled', '1');
		/* NTP settings end */

		/* Cache settings start */
		s.tab('cache', _('Persistent Cache Settings'));
		o = s.taboption('cache', form.SectionValue, '_cache', form.NamedSection, 'cache', 'homeproxy');
		o.depends('routing_mode', 'custom');
		ss = o.subsection;

		so = ss.option(form.ListValue, 'enabled', _('Enable cache file'));
		so.value('1', _('Enable'));
		so.value('0', _('Disable'));
		so.default = '1';
		so.rmempty = false;

		so = ss.option(form.Value, 'path', _('Persistent cache file path'));
		so.placeholder = '/etc/homeproxy/cache.db';
		so.depends('enabled', '1');

		so = ss.option(form.ListValue, 'store_rdrc', _('Persist RDRC cache'));
		so.value('1', _('Enable'));
		so.value('0', _('Disable'));
		so.default = '1';
		so.rmempty = false;
		so.depends('enabled', '1');

		so = ss.option(form.Value, 'rdrc_timeout', _('RDRC timeout'),
			_('Timeout of rejected DNS response cache in seconds. <code>604800 (7d)</code> is used by default.'));
		so.datatype = 'uinteger';
		so.depends({'enabled': '1', 'store_rdrc': '1'});
		/* Cache settings end */

		/* ACL settings start */
		o = s.taboption('control', form.SectionValue, '_control', form.NamedSection, 'control', 'homeproxy');
		ss = o.subsection;

		/* Interface control start */
		ss.tab('interface', _('Interface Control'));

		so = ss.taboption('interface', widgets.DeviceSelect, 'listen_interfaces', _('Listen interfaces'),
			_('Only process traffic from specific interfaces. Leave empty for all.'));
		so.multiple = true;
		so.noaliases = true;

		so = ss.taboption('interface', widgets.DeviceSelect, 'bind_interface', _('Bind interface'),
			_('Bind outbound traffic to specific interface. Leave empty to auto detect.'));
		so.multiple = false;
		so.noaliases = true;
		/* Interface control end */

		/* LAN IP policy start */
		ss.tab('lan_ip_policy', _('LAN IP Policy'));

		so = ss.taboption('lan_ip_policy', form.ListValue, 'lan_proxy_mode', _('Proxy filter mode'));
		so.value('disabled', _('Disable'));
		so.value('listed_only', _('Proxy listed only'));
		so.value('except_listed', _('Proxy all except listed'));
		so.default = 'disabled';
		so.rmempty = false;

		so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_direct_ipv4_ips', _('Direct IPv4 IP-s'), null, 'ipv4', hosts, true);
		so.depends('lan_proxy_mode', 'except_listed');

		so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_direct_ipv6_ips', _('Direct IPv6 IP-s'), null, 'ipv6', hosts, true);
		so.depends({'lan_proxy_mode': 'except_listed', 'homeproxy.config.ipv6_support': '1'});

		so = fwtool.addMACOption(ss, 'lan_ip_policy', 'lan_direct_mac_addrs', _('Direct MAC-s'), null, hosts);
		so.depends('lan_proxy_mode', 'except_listed');

		so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_proxy_ipv4_ips', _('Proxy IPv4 IP-s'), null, 'ipv4', hosts, true);
		so.depends('lan_proxy_mode', 'listed_only');

		so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_proxy_ipv6_ips', _('Proxy IPv6 IP-s'), null, 'ipv6', hosts, true);
		so.depends({'lan_proxy_mode': 'listed_only', 'homeproxy.config.ipv6_support': '1'});

		so = fwtool.addMACOption(ss, 'lan_ip_policy', 'lan_proxy_mac_addrs', _('Proxy MAC-s'), null, hosts);
		so.depends('lan_proxy_mode', 'listed_only');

		so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_gaming_mode_ipv4_ips', _('Gaming mode IPv4 IP-s'), null, 'ipv4', hosts, true);

		so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_gaming_mode_ipv6_ips', _('Gaming mode IPv6 IP-s'), null, 'ipv6', hosts, true);
		so.depends('homeproxy.config.ipv6_support', '1');

		so = fwtool.addMACOption(ss, 'lan_ip_policy', 'lan_gaming_mode_mac_addrs', _('Gaming mode MAC-s'), null, hosts);

		so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_global_proxy_ipv4_ips', _('Global proxy IPv4 IP-s'), null, 'ipv4', hosts, true);
		so.depends({'homeproxy.config.routing_mode': 'custom', '!reverse': true});

		so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_global_proxy_ipv6_ips', _('Global proxy IPv6 IP-s'), null, 'ipv6', hosts, true);
		so.depends({'homeproxy.config.routing_mode': /^((?!custom).)+$/, 'homeproxy.config.ipv6_support': '1'});

		so = fwtool.addMACOption(ss, 'lan_ip_policy', 'lan_global_proxy_mac_addrs', _('Global proxy MAC-s'), null, hosts);
		so.depends({'homeproxy.config.routing_mode': 'custom', '!reverse': true});
		/* LAN IP policy end */

		/* WAN IP policy start */
		ss.tab('wan_ip_policy', _('WAN IP Policy'));

		so = ss.taboption('wan_ip_policy', form.DynamicList, 'wan_proxy_ipv4_ips', _('Proxy IPv4 IP-s'));
		so.datatype = 'or(ip4addr, cidr4)';

		so = ss.taboption('wan_ip_policy', form.DynamicList, 'wan_proxy_ipv6_ips', _('Proxy IPv6 IP-s'));
		so.datatype = 'or(ip6addr, cidr6)';
		so.depends('homeproxy.config.ipv6_support', '1');

		so = ss.taboption('wan_ip_policy', form.DynamicList, 'wan_direct_ipv4_ips', _('Direct IPv4 IP-s'));
		so.datatype = 'or(ip4addr, cidr4)';

		so = ss.taboption('wan_ip_policy', form.DynamicList, 'wan_direct_ipv6_ips', _('Direct IPv6 IP-s'));
		so.datatype = 'or(ip6addr, cidr6)';
		so.depends('homeproxy.config.ipv6_support', '1');
		/* WAN IP policy end */

		/* Proxy domain list start */
		ss.tab('proxy_domain_list', _('Proxy Domain List'));

		so = ss.taboption('proxy_domain_list', form.TextValue, '_proxy_domain_list');
		so.rows = 10;
		so.monospace = true;
		so.datatype = 'hostname';
		so.depends({'homeproxy.config.routing_mode': 'custom', '!reverse': true});
		so.load = function(/* ... */) {
			return L.resolveDefault(callReadDomainList('proxy_list')).then((res) => {
				return res.content;
			}, {});
		}
		so.write = function(_section_id, value) {
			return callWriteDomainList('proxy_list', value);
		}
		so.remove = function(/* ... */) {
			let routing_mode = this.section.formvalue('config', 'routing_mode');
			if (routing_mode !== 'custom')
				return callWriteDomainList('proxy_list', '');
			return true;
		}
		so.validate = function(section_id, value) {
			if (section_id && value)
				for (let i of value.split('\n'))
					if (i && !stubValidator.apply('hostname', i))
						return _('Expecting: %s').format(_('valid hostname'));

			return true;
		}
		/* Proxy domain list end */

		/* Direct domain list start */
		ss.tab('direct_domain_list', _('Direct Domain List'));

		so = ss.taboption('direct_domain_list', form.TextValue, '_direct_domain_list');
		so.rows = 10;
		so.monospace = true;
		so.datatype = 'hostname';
		so.depends({'homeproxy.config.routing_mode': 'custom', '!reverse': true});
		so.load = function(/* ... */) {
			return L.resolveDefault(callReadDomainList('direct_list')).then((res) => {
				return res.content;
			}, {});
		}
		so.write = function(_section_id, value) {
			return callWriteDomainList('direct_list', value);
		}
		so.remove = function(/* ... */) {
			let routing_mode = this.section.formvalue('config', 'routing_mode');
			if (routing_mode !== 'custom')
				return callWriteDomainList('direct_list', '');
			return true;
		}
		so.validate = function(section_id, value) {
			if (section_id && value)
				for (let i of value.split('\n'))
					if (i && !stubValidator.apply('hostname', i))
						return _('Expecting: %s').format(_('valid hostname'));

			return true;
		}
		/* Direct domain list end */
		/* ACL settings end */

		/* Panel settings start */
		s.tab('panel', _('Panel Settings'));
		o = s.taboption('panel', form.SectionValue, '_clash_api', form.NamedSection, 'clash_api', 'homeproxy');
		o.depends('routing_mode', 'custom');
		ss = o.subsection;

		so = ss.option(form.Value, 'external_ui', _('UI path'));
		so.placeholder = '/etc/homeproxy/run/ui';
		so.default = '/etc/homeproxy/run/ui';

		const panelPresetUrls = {
			'https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip': 'Zashboard CDN Fonts (gh-proxy)',
			'https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip': 'Zashboard CDN Fonts',
			'https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip': 'Zashboard 完整版 (gh-proxy)',
			'https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip': 'Zashboard 完整版',
			'https://gh-proxy.com/https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip': 'MetaCubeXD (gh-proxy)',
			'https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip': 'MetaCubeXD',
			'https://gh-proxy.com/https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip': 'YACD (gh-proxy)',
			'https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip': 'YACD',
			'https://gh-proxy.com/https://github.com/MetaCubeX/Razord-meta/archive/refs/heads/gh-pages.zip': 'Razord (gh-proxy)',
			'https://github.com/MetaCubeX/Razord-meta/archive/refs/heads/gh-pages.zip': 'Razord'
		};

		so = ss.option(form.ListValue, 'external_ui_download_url', _('UI download URL'));
		so.value('https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip', 'Zashboard CDN Fonts (gh-proxy)');
		so.value('https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip', 'Zashboard CDN Fonts');
		so.value('https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip', 'Zashboard 完整版 (gh-proxy)');
		so.value('https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip', 'Zashboard 完整版');
		so.value('https://gh-proxy.com/https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip', 'MetaCubeXD (gh-proxy)');
		so.value('https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip', 'MetaCubeXD');
		so.value('https://gh-proxy.com/https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip', 'YACD (gh-proxy)');
		so.value('https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip', 'YACD');
		so.value('https://gh-proxy.com/https://github.com/MetaCubeX/Razord-meta/archive/refs/heads/gh-pages.zip', 'Razord (gh-proxy)');
		so.value('https://github.com/MetaCubeX/Razord-meta/archive/refs/heads/gh-pages.zip', 'Razord');
		so.value('https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip', 'MetaCubeXD');
		so.value('https://gh-proxy.com/https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip', 'YACD (gh-proxy)');
		so.value('https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip', 'YACD');
		so.value('https://gh-proxy.com/https://github.com/MetaCubeX/Razord-meta/archive/refs/heads/gh-pages.zip', 'Razord (gh-proxy)');
		so.value('https://github.com/MetaCubeX/Razord-meta/archive/refs/heads/gh-pages.zip', 'Razord');
		so.value('__custom__', _('Custom'));
		so.default = 'https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip';
		so.load = function(section_id) {
			const value = uci.get(data[0], section_id, 'external_ui_download_url') ?? this.default;
			return (value in panelPresetUrls) ? value : '__custom__';
		};
		so.write = function(section_id, value) {
			if (value === '__custom__') {
				const customValue = (this.section?.formvalue(section_id, 'external_ui_download_url_custom') || '').trim();
				uci.set(data[0], section_id, 'external_ui_download_url', customValue);
			} else {
				uci.set(data[0], section_id, 'external_ui_download_url', value);
			}
		};

		so = ss.option(form.Value, 'external_ui_download_url_custom', _('Custom URL'));
		so.placeholder = 'https://example.com/dist.zip';
		so.depends('external_ui_download_url', '__custom__');
		so.load = function(section_id) {
			const value = (uci.get(data[0], section_id, 'external_ui_download_url') || '').trim();
			return (value in panelPresetUrls) ? '' : value;
		};
		so.write = function(section_id, value) {
			uci.set(data[0], section_id, 'external_ui_download_url_custom', (value || '').trim());
		};
		so.remove = function(section_id) {
			uci.unset(data[0], section_id, 'external_ui_download_url_custom');
		};

		so = ss.option(form.ListValue, 'external_ui_download_detour', _('UI download detour'));
		so.value('', _('Default'));
		so.value('direct-out', _('Direct'));
		uci.sections(data[0], 'routing_node', (res) => {
			if (res.enabled === '1')
				so.value(res['.name'], res.label);
		});
		so.default = 'direct-out';

		so = ss.option(form.Value, 'external_controller', _('API listen'),
			_('Use 0.0.0.0:port to open the panel from your browser.'));
		so.placeholder = '0.0.0.0:9095';
		so.default = '0.0.0.0:9095';
		so.datatype = 'ipaddrport(1)';
		so.rmempty = false;

		so = ss.option(form.Value, 'secret', _('API password'));
		so.password = true;

		so = ss.option(form.ListValue, 'default_mode', _('Default mode'));
		so.value('rule', _('Rule'));
		so.value('global', _('Global'));
		so.value('direct', _('Direct'));
		so.default = 'rule';
		so.rmempty = false;
		/* Panel settings end */

		return m.render();
	}
});
