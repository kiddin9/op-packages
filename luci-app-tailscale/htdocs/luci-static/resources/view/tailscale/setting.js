/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Copyright (C) 2024 asvow
 */

'use strict';
'require form';
'require fs';
'require network';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

const callAdguardPreflight = rpc.declare({
	object: 'luci.tailscale',
	method: 'adguard_preflight',
	params: [
		'candidate',
		'api_url',
		'username',
		'password_set',
		'password',
		'default_upstreams',
		'tailnet_upstreams',
		'health_domain',
		'expected_ips'
	],
	expect: { '': {} },
	reject: true
});

const callSecretStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'secret_status',
	expect: { '': {} },
	reject: true
});

const callSetSecrets = rpc.declare({
	object: 'luci.tailscale',
	method: 'set_secrets',
	params: ['authkey_set', 'authkey', 'adguard_password_set', 'adguard_password', 'api_url', 'username', 'base_ref'],
	expect: { '': {} },
	reject: true
});

const callOpenclashBypassStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'openclash_bypass_status',
	expect: { '': {} },
	reject: true
});

const callPolicyRoutingStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'policy_routing_status',
	expect: { '': {} },
	reject: true
});

const ADGUARD_PREFLIGHT_CHECKS = [
	{ key: 'adguard_process', label: _('AdGuard process') },
	{ key: 'port_53_adguard', label: _('Port 53 is AdGuard') },
	{ key: 'dhcp_advertises_lan_dns', label: _('LAN DHCP advertises this router as DNS') },
	{ key: 'adguard_api', label: _('AdGuard API') },
	{ key: 'health_check', label: _('Tailnet DNS health check') }
];

async function getInterfaceSubnets(interfaces = ['lan', 'wan']) {
	const networks = await network.getNetworks();
	return [...new Set(
		networks
			.filter(ifc => interfaces.includes(ifc.getName()))
			.flatMap(ifc => ifc.getIPAddrs())
			.filter(addr => addr.includes('/'))
			.map(addr => {
				const [ip, cidr] = addr.split('/');
				const ipParts = ip.split('.').map(Number);
				const mask = ~((1 << (32 - parseInt(cidr))) - 1);
				const subnetParts = ipParts.map((part, i) => (part & (mask >> (24 - i * 8))) & 255);
				return `${subnetParts.join('.')}/${cidr}`;
			})
	)];
}

async function getStatus() {
	const status = {
		isRunning: false,
		backendState: undefined,
		authURL: undefined,
		displayName: undefined,
		onlineExitNodes: [],
		peers: []
	};
	const res = await callServiceList('tailscale');
	try {
		status.isRunning = res['tailscale']['instances']['instance1']['running'];
	} catch (e) {
		return status;
	}
	const tailscaleRes = await fs.exec("/usr/sbin/tailscale", ["status", "--json"]);
	const tailscaleStatus = JSON.parse(tailscaleRes.stdout.replace(/("\w+"):\s*(\d+)/g, '$1:"$2"'));
	if (!tailscaleStatus.AuthURL && tailscaleStatus.BackendState === "NeedsLogin") {
		fs.exec("/usr/sbin/tailscale", ["login"]);
	}
	status.backendState = tailscaleStatus.BackendState;
	status.authURL = tailscaleStatus.AuthURL;
	status.displayName = (status.backendState === "Running") ? tailscaleStatus.User[tailscaleStatus.Self.UserID].DisplayName : undefined;
	if (tailscaleStatus.Peer) {
		status.peers = Object.values(tailscaleStatus.Peer)
			.map(peer => {
				const ip = Array.isArray(peer.TailscaleIPs) ? (peer.TailscaleIPs[0] || '') : '';
				const dnsName = (peer.DNSName || '').replace(/\.$/, '');
				const shortDnsName = dnsName.split('.', 1)[0] || '';
				const hostName = peer.HostName || '';
				const name = shortDnsName || hostName || dnsName || ip;
				const routes = Array.isArray(peer.PrimaryRoutes) ? peer.PrimaryRoutes : [];
				const hasSubnetRoutes = routes.length > 0;
				const displayName = (shortDnsName && hostName && shortDnsName !== hostName)
					? [shortDnsName, '(' + hostName + ')'].join(' ')
					: (shortDnsName || hostName || dnsName || ip);
				const onlineLabel = peer.Online ? _('Online') : _('Offline');
				const label = [
					displayName,
					ip,
					onlineLabel,
					routes.join(', ')
				].filter(Boolean).join('    ');

				return {
					name: name,
					label: label,
					displayName: displayName,
					ip: ip,
					onlineLabel: onlineLabel,
					routes: routes,
					hasSubnetRoutes: hasSubnetRoutes,
					aliases: [hostName, dnsName, shortDnsName, ip].filter(Boolean)
				};
			})
			.filter(peer => peer.name);
		status.onlineExitNodes = Object.values(tailscaleStatus.Peer)
			.flatMap(peer => (peer.ExitNodeOption && peer.Online) ? [peer.HostName] : []);
	}
	return status;
}

function renderStatus(isRunning) {
	const spanTemp = '<em><span style="color:%s"><strong>%s %s</strong></span></em>';
	let renderHTML;
	if (isRunning) {
		renderHTML = String.format(spanTemp, 'green', _('Tailscale'), _('RUNNING'));
	} else {
		renderHTML = String.format(spanTemp, 'red', _('Tailscale'), _('NOT RUNNING'));
	}

	return renderHTML;
}

function renderLogin(loginStatus, authURL, displayName) {
	const spanTemp = '<span style="color:%s">%s</span>';
	let renderHTML;
	if (loginStatus === "NeedsLogin") {
		renderHTML = String.format('<a href="%s" target="_blank">%s</a>', authURL, _('Need to log in'));
	} else if (loginStatus === "Running") {
		renderHTML = String.format('<a href="%s" target="_blank">%s</a>', 'https://login.tailscale.com/admin/machines', displayName);
		renderHTML += String.format('<br><a style="color:green" id="logout_button">%s</a>', _('Log out and Unbind'));
	} else {
		renderHTML = String.format(spanTemp, 'orange', _('NOT RUNNING'));
	}

	return renderHTML;
}

function toList(value) {
	if (!value)
		return [];

	if (Array.isArray(value))
		return value;

	return String(value).trim().split(/\s+/).filter(Boolean);
}

function renderCheck(value) {
	if (value !== 'pass' && value !== 'fail')
		return E('span', { style: 'color:#687586' }, _('Checking ...'));

	const ok = value === 'pass';
	return E('span', { style: 'color:' + (ok ? 'green' : 'red') }, ok ? _('Pass') : _('Fail'));
}

function adguardPreflightCellId(key) {
	return 'adguard_preflight_' + key;
}

function buildAdguardPreflightRequest(values) {
	return {
		candidate: '1',
		api_url: String(values.apiUrl || ''),
		username: String(values.username || ''),
		password_set: values.keepPassword ? '0' : '1',
		password: values.keepPassword ? '' : String(values.password || ''),
		default_upstreams: toList(values.defaultUpstreams).join('\n'),
		tailnet_upstreams: toList(values.tailnetUpstreams).join('\n'),
		health_domain: String(values.healthDomain || ''),
		expected_ips: toList(values.expectedIps).join('\n')
	};
}

function normalizeAdguardApiUrl(value) {
	return String(value || '').replace(/\/+$/, '');
}

function adguardConfigChanged(candidate, persisted) {
	const current = candidate || {};
	const saved = persisted || {};
	return normalizeAdguardApiUrl(current.api_url) !== normalizeAdguardApiUrl(saved.api_url) ||
		String(current.username || '') !== String(saved.username || '') ||
		String(current.default_upstreams || '') !== String(saved.default_upstreams || '') ||
		String(current.tailnet_upstreams || '') !== String(saved.tailnet_upstreams || '') ||
		String(current.health_domain || '') !== String(saved.health_domain || '') ||
		String(current.expected_ips || '') !== String(saved.expected_ips || '');
}

function adguardBindingChanged(candidate, persisted) {
	return normalizeAdguardApiUrl(candidate && candidate.api_url) !== normalizeAdguardApiUrl(persisted && persisted.api_url) ||
		String(candidate && candidate.username || '') !== String(persisted && persisted.username || '');
}

function buildSecretUpdateRequest(values) {
	const authkey = String(values.authkey || '').trim();
	const adguardPassword = values.adguardPassword == null ? '' : String(values.adguardPassword);
	return {
		authkey_set: authkey ? '1' : '0',
		authkey: authkey,
		adguard_password_set: adguardPassword ? '1' : '0',
		adguard_password: adguardPassword,
		api_url: String(values.adguardApiUrl || '').trim(),
		username: String(values.adguardUsername || '').trim(),
		base_ref: String(values.baseRef || '').trim()
	};
}

function saveMapWithSecrets(map, cb, silent, stageSecrets, afterSave) {
	let stagedSecrets;
	map.checkDepends();

	return map.parse()
		.then(cb)
		.then(stageSecrets)
		.then(function(staged) {
			stagedSecrets = staged;
			return map.data.save();
		})
		.then(map.load.bind(map))
		.then(function() {
			return afterSave(stagedSecrets);
		})
		.catch(function(e) {
			if (!silent) {
				ui.showModal(_('Save error'), [
					E('p', {}, [ _('An error occurred while saving the form:') ]),
					E('p', {}, [ E('em', { style: 'white-space:pre-wrap' }, [ e.message ]) ]),
					E('div', { class: 'right' }, [
						E('button', { class: 'cbi-button', click: ui.hideModal }, [ _('Dismiss') ])
					])
				]);
			}
			return Promise.reject(e);
		})
		.then(map.renderContents.bind(map));
}

async function fetchAdguardPreflightStatus(request) {
	const input = request || {
		candidate: '0',
		api_url: '',
		username: '',
		password_set: '0',
		password: '',
		default_upstreams: '',
		tailnet_upstreams: '',
		health_domain: '',
		expected_ips: ''
	};

	try {
		return await callAdguardPreflight(
			input.candidate,
			input.api_url,
			input.username,
			input.password_set,
			input.password,
			input.default_upstreams,
			input.tailnet_upstreams,
			input.health_domain,
			input.expected_ips
		);
	} catch (e) {
		const error = e && (e.message || e.stderr || e) || 'preflight command failed';
		return {
			ready: 'fail',
			error: String(error).replace(/\n/g, ' ')
		};
	}
}

async function writeAdguardDnsSwitchEnabled(section_id, value, candidateRequest, persistedRequest) {
	const persistedEnabled = persistedRequest && persistedRequest.enabled === '1';
	const shouldPreflight = value === '1' && (
		!persistedEnabled ||
		candidateRequest.password_set === '1' ||
		adguardConfigChanged(candidateRequest, persistedRequest)
	);

	if (shouldPreflight) {
		if (persistedEnabled && adguardBindingChanged(candidateRequest, persistedRequest) && !String(candidateRequest.password || ''))
			throw new Error(_('Re-enter the AdGuard password after changing the API URL or username.'));
		const status = await fetchAdguardPreflightStatus(candidateRequest);
		if (status.ready !== 'pass')
			throw new Error(_('Only enable when all status checks pass.'));
	}

	return uci.set('tailscale', section_id, 'adguard_dns_switch_enabled', value);
}

async function refreshAdguardPreflightStatus() {
	const status = await fetchAdguardPreflightStatus();

	ADGUARD_PREFLIGHT_CHECKS.forEach(function(check) {
		const cell = document.getElementById(adguardPreflightCellId(check.key));
		if (!cell)
			return;

		cell.innerHTML = '';
		cell.appendChild(renderCheck(status[check.key] || 'fail'));
	});
}

function renderOpenclashBypassStatus(status) {
	const labels = {
		active: _('Enabled; 4 bypass rules are active'),
		waiting: _('Enabled; waiting for OpenClash nftables chains'),
		disabled: _('Disabled; Tailscale traffic is handled by OpenClash'),
		absent: _('OpenClash is not installed; bypass is not required'),
		unsupported: _('Unsupported; firewall4/nftables is required'),
		error: _('Configuration error')
	};
	return labels[status && status.state] || _('Unknown status');
}

async function refreshOpenclashBypassStatus() {
	const node = document.getElementById('openclash_bypass_status');
	if (!node)
		return;
	try {
		const status = await callOpenclashBypassStatus();
		node.textContent = renderOpenclashBypassStatus(status);
	} catch (error) {
		node.textContent = _('Unable to read OpenClash bypass status.');
	}
}

function renderPolicyRoutingStatus(status) {
	if (status && status.state === 'active' && !status.mwan3_present)
		return _('Enabled; mwan3 is not installed');
	if (status && status.state === 'active' && !status.mwan3_earlier_mark_rule)
		return _('Enabled; no earlier mwan3-marked rule was detected');

	const labels = {
		active: _('Enabled; Tailscale routes take precedence over mwan3'),
		waiting: _('Enabled; waiting for the managed policy rule'),
		disabled: _('Disabled; mwan3 routing is unchanged'),
		blocked_default_route: _('Blocked; table 52 contains a default route'),
		blocked_mwan3_priority: _('Blocked; a mwan3 rule has higher priority than 1000'),
		blocked_priority_conflict: _('Blocked; priority 1000 is already in use'),
		blocked_ownership: _('Blocked; an existing rule is not managed by this app'),
		error: _('Configuration error')
	};
	return labels[status && status.state] || _('Unknown status');
}

async function refreshPolicyRoutingStatus() {
	const node = document.getElementById('policy_routing_status');
	if (!node)
		return;
	try {
		const status = await callPolicyRoutingStatus();
		node.textContent = renderPolicyRoutingStatus(status);
	} catch (error) {
		node.textContent = _('Unable to read Tailscale policy-routing status.');
	}
}

function hasFormListValue(option, section_id) {
	return toList(option.formvalue(section_id)).map(function(value) {
		return String(value || '').trim();
	}).filter(Boolean).length > 0;
}

function getFirewallZones() {
	const zones = uci.sections('firewall', 'zone')
		.map(function(zone) { return zone.name; })
		.filter(Boolean);
	return zones.length ? zones : ['wan'];
}

return view.extend({
	load() {
		return callSecretStatus().then(function(secretStatus) {
			return Promise.all([
				uci.load('tailscale'),
				uci.load('firewall'),
				getStatus(),
				getInterfaceSubnets(),
				uci.load('tailscale_openclash'),
				uci.load('tailscale_policy_routing')
			]).then(function(data) {
				return [
					data[0],
					data[1],
					data[2],
					data[3],
					data[4],
					secretStatus,
					data[5]
				];
			});
		});
	},

	render(data) {
		let m, s, o;
		const statusData = data[2];
		const interfaceSubnets = data[3];
		const firewallZones = getFirewallZones();
		const onlineExitNodes = statusData.onlineExitNodes;
		const peers = statusData.peers;
		const secretStatus = data[5] || {};
		let hasAuthKey = secretStatus.authkey_set === '1';
		const savedKeepalivePeers = toList(uci.get('tailscale', 'settings', 'keepalive_peers'));
		let hasAdguardPassword = secretStatus.adguard_password_set === '1';
		let saveInFlight = null;
		let adguardPasswordOption, authKeyOption;
		let persistedAdguardConfig;

		function readPersistedAdguardConfig() {
			const request = buildAdguardPreflightRequest({
				apiUrl: uci.get('tailscale', 'settings', 'adguard_api_url'),
				username: uci.get('tailscale', 'settings', 'adguard_username'),
				password: '',
				keepPassword: true,
				defaultUpstreams: uci.get('tailscale', 'settings', 'adguard_default_upstreams'),
				tailnetUpstreams: uci.get('tailscale', 'settings', 'adguard_tailnet_upstreams'),
				healthDomain: uci.get('tailscale', 'settings', 'adguard_health_domain'),
				expectedIps: uci.get('tailscale', 'settings', 'adguard_health_expected_ips')
			});
			request.enabled = uci.get('tailscale', 'settings', 'adguard_dns_switch_enabled') === '1' ? '1' : '0';
			return request;
		}

		persistedAdguardConfig = readPersistedAdguardConfig();

		m = new form.Map('tailscale', _('Tailscale'), _('Tailscale is a cross-platform and easy to use virtual LAN.'));

		s = m.section(form.TypedSection);
		s.anonymous = true;
		s.render = function () {
			poll.add(async function() {
				const res = await getStatus();
				const service_view = document.getElementById("service_status");
				const login_view = document.getElementById("login_status_div");
				service_view.innerHTML = renderStatus(res.isRunning);
				login_view.innerHTML = renderLogin(res.backendState, res.authURL, res.displayName);
				const logoutButton = document.getElementById('logout_button');
				if (logoutButton) {
					logoutButton.onclick = function() {
						if (confirm(_('Are you sure you want to log out and unbind the current device?'))) {
							fs.exec("/usr/sbin/tailscale", ["logout"]);
						}
					}
				}
			});

			return E('div', { class: 'cbi-section', id: 'status_bar' }, [
				E('p', { id: 'service_status' }, _('Collecting data ...'))
			]);
		}

		s = m.section(form.NamedSection, 'settings', 'config');
		s.tab('basic', _('Basic Settings'));

		o = s.taboption('basic', form.Flag, 'enabled', _('Enable'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('basic', form.DummyValue, 'login_status', _('Login Status'));
		o.depends('enabled', '1');
		o.renderWidget = function(section_id, option_id) {
			return E('div', { 'id': 'login_status_div' }, _('Collecting data ...'));
		};

		o = s.taboption('basic', form.Value, 'port', _('Port'), _('Set the Tailscale port number.'));
		o.datatype = 'port';
		o.default = '41641';
		o.rmempty = false;

		o = s.taboption('basic', form.Flag, 'allow_wan_direct', _('Allow WAN Direct'), _('Allow inbound UDP traffic from WAN to the local Tailscale listen port so remote peers can establish direct connections without first using DERP.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('basic', form.DynamicList, 'wan_direct_zones', _('WAN Direct Source Zones'), _('Firewall source zones allowed to reach the local Tailscale listen port when WAN direct is enabled.'));
		firewallZones.forEach(function(zone) {
			o.value(zone, zone);
		});
		o.default = 'wan';
		o.depends('allow_wan_direct', '1');
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'config_path', _('Workdir'), _('The working directory contains config files, audit logs, and runtime info.'));
		o.default = '/etc/tailscale';
		o.rmempty = false;

		o = s.taboption('basic', form.ListValue, 'fw_mode', _('Firewall Mode'));
		o.value('nftables', 'nftables');
		o.value('iptables', 'iptables');
		o.default = 'nftables';
		o.rmempty = false;

		o = s.taboption('basic', form.Flag, 'log_stdout', _('StdOut Log'), _('Logging program activities.'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.taboption('basic', form.Flag, 'log_stderr', _('StdErr Log'), _('Logging program errors and exceptions.'));
		o.default = o.enabled;
		o.rmempty = false;

		s.tab('advance', _('Advanced Settings'));

		o = s.taboption('advance', form.Flag, 'accept_routes', _('Accept Routes'), _('Accept subnet routes that other nodes advertise.'));
		o.default = o.disabled;
		o.rmempty = false;

			o = s.taboption('advance', form.Flag, 'mwan3_table52_precedence', _('Prioritize Tailscale Routes Before mwan3'),
				_('Give routes already present in Tailscale table 52 priority over mwan3-marked traffic. This fixes LAN clients being sent to a WAN instead of a Tailnet or routed subnet. Public destinations not present in table 52 continue through mwan3. Disabled leaves mwan3 precedence unchanged. Verify from a real LAN client or with an equivalent mwan3 fwmark; the router\'s unmarked ip route get alone is insufficient. The feature remains blocked while table 52 has a default route, such as when using an exit node.'));
		o.default = o.disabled;
		o.rmempty = false;
		o.cfgvalue = function() {
			return uci.get('tailscale_policy_routing', 'settings', 'enabled') || '0';
		};
		o.write = function(section_id, value) {
			return uci.set('tailscale_policy_routing', 'settings', 'enabled', value);
		};
		o.remove = function() {
			return uci.set('tailscale_policy_routing', 'settings', 'enabled', '0');
		};

		o = s.taboption('advance', form.DummyValue, '_policy_routing_status', _('Policy Routing Status'));
		o.rawhtml = true;
		o.cfgvalue = function() { return ''; };
		o.renderWidget = function() {
			return E('span', { id: 'policy_routing_status' }, _('Checking ...'));
		};

		o = s.taboption('advance', form.Value, 'hostname', _('Device Name'), _("Leave blank to use the device's hostname."));
		o.default = '';
		o.rmempty = true;

		o = s.taboption('advance', form.Flag, 'accept_dns', _('Accept DNS'), _('Accept DNS configuration from the Tailscale admin console.'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.taboption('advance', form.Flag, 'advertise_exit_node', _('Exit Node'), _('Offer to be an exit node for outbound internet traffic from the Tailscale network.'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('advance', form.ListValue, 'exit_node', _('Online Exit Nodes'), _('Select an online machine name to use as an exit node.'));
		if (onlineExitNodes.length > 0) {
			o.optional = true;
			onlineExitNodes.forEach(function(node) {
				o.value(node, node);
			});
		} else {
			o.value('', _('No Available Exit Nodes'));
			o.readonly = true;
		}
		o.default = '';
		o.depends('advertise_exit_node', '0');
		o.rmempty = true;

		o = s.taboption('advance', form.DynamicList, 'advertise_routes', _('Expose Subnets'), _('Expose physical network routes into Tailscale, e.g. <code>10.0.0.0/24</code>.'));
		if (interfaceSubnets.length > 0) {
			interfaceSubnets.forEach(function(subnet) {
				o.value(subnet, subnet);
			});
		}
		o.default = '';
		o.rmempty = true;

		o = s.taboption('advance', form.Flag, 'disable_snat_subnet_routes', _('Site To Site'), _('Use site-to-site layer 3 networking to connect subnets on the Tailscale network.'));
		o.default = o.disabled;
		o.depends('accept_routes', '1');
		o.rmempty = false;

		o = s.taboption('advance', form.MultiValue, 'access', _('Access Control'));
		o.value('ts_ac_lan', _('Tailscale access LAN'));
		o.value('ts_ac_wan', _('Tailscale access WAN'));
		o.value('lan_ac_ts', _('LAN access Tailscale'));
		o.value('wan_ac_ts', _('WAN access Tailscale'));
		o.default = "ts_ac_lan ts_ac_wan lan_ac_ts";
		o.rmempty = true;

		s.tab('keepalive', _('Keepalive'));

		o = s.taboption('keepalive', form.Flag, 'keepalive_enabled', _('Peer Keepalive'), _('Periodically send lightweight Tailscale pings to selected peers.'));
		o.default = o.disabled;
		o.rmempty = false;

		const keepalivePeerChoices = [];
		const keepalivePeerChoiceNames = {};
		const keepalivePeerAliases = {};
		const keepalivePeersByName = {};
		peers.forEach(function(peer) {
			keepalivePeersByName[peer.name] = peer;
			(peer.aliases || []).forEach(function(alias) {
				keepalivePeerAliases[alias] = peer.name;
			});
		});

		const selectedKeepalivePeers = {};
		savedKeepalivePeers.forEach(function(peer) {
			const matchedName = keepalivePeerAliases[peer];
			if (matchedName && keepalivePeersByName[matchedName] && keepalivePeersByName[matchedName].hasSubnetRoutes)
				selectedKeepalivePeers[matchedName] = true;
			else
				selectedKeepalivePeers[peer] = true;
		});

		peers.forEach(function(peer) {
			if (!peer.hasSubnetRoutes)
				return;

			keepalivePeerChoiceNames[peer.name] = true;
			keepalivePeerChoices.push({
				value: peer.name,
				peer: peer
			});
		});

		savedKeepalivePeers.forEach(function(peer) {
			const matchedName = keepalivePeerAliases[peer];
			const matchedPeer = matchedName ? keepalivePeersByName[matchedName] : null;

			if (matchedPeer && matchedPeer.hasSubnetRoutes)
				return;

			if (keepalivePeerChoiceNames[peer])
				return;

			keepalivePeerChoiceNames[peer] = true;
			if (matchedPeer) {
				keepalivePeerChoices.push({
					value: peer,
					peer: matchedPeer,
					warning: _('No subnet routes')
				});
			}
			else {
				keepalivePeerChoices.push({
					value: peer,
					peer: {
						displayName: peer,
						ip: '',
						onlineLabel: '',
						routes: []
					},
					warning: _('Not found')
				});
			}
		});

		const KeepalivePeersValue = form.Value.extend({
			cfgvalue: function() {
				return savedKeepalivePeers;
			},
			formvalue: function(section_id) {
				const node = document.getElementById(this.cbid(section_id));
				const values = node ? Array.from(node.querySelectorAll('input[type="checkbox"]:checked')).map(function(input) {
					return input.value;
				}) : [];
				return values.length ? values : '';
			},
			renderWidget: function(section_id) {
				const disabled = (this.readonly != null) ? this.readonly : this.map.readonly;
				if (keepalivePeerChoices.length === 0) {
					return E('div', {
						id: this.cbid(section_id),
						class: 'keepalive-peer-list'
					}, E('em', _('No Available Peers')));
				}

				return E('div', {
					id: this.cbid(section_id),
					class: 'keepalive-peer-list',
					style: 'display:grid;gap:6px;max-width:680px;width:100%'
				}, keepalivePeerChoices.map(function(choice, index) {
					const peer = choice.peer;
					const meta = [peer.ip, peer.onlineLabel].filter(Boolean).join(' / ');
					const checkboxId = '%s.%d'.format(this.cbid(section_id), index);
					const routes = (peer.routes || []).length ? '%s: %s'.format(_('Subnets'), peer.routes.join(', ')) : '';

					return E('label', {
						'for': checkboxId,
						class: 'keepalive-peer-row',
						style: 'display:grid;grid-template-columns:minmax(320px,1fr) minmax(140px,260px);gap:10px;align-items:center;min-height:42px;padding:5px 10px;border:1px solid #d8dee5;border-radius:4px;box-sizing:border-box;cursor:pointer'
					}, [
						E('span', { class: 'keepalive-peer-main', style: 'display:flex;align-items:center;gap:10px;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis' }, [
							E('span', { class: 'keepalive-peer-check', style: 'display:flex;align-items:center;justify-content:center;line-height:0;flex:0 0 24px' }, E('input', {
								id: checkboxId,
								type: 'checkbox',
								value: choice.value,
								checked: selectedKeepalivePeers[choice.value] ? 'checked' : null,
								disabled: disabled ? 'disabled' : null,
								style: 'margin:0'
							})),
							E('strong', {}, peer.displayName || choice.value),
							meta ? E('span', { style: 'color:#687586;font-size:12px;overflow:hidden;text-overflow:ellipsis' }, meta) : ''
						]),
						E('span', { style: 'color:#687586;font-size:12px;line-height:1.3;text-align:right;white-space:normal;overflow-wrap:anywhere;max-width:260px' }, [
							routes,
							choice.warning ? E('span', { style: routes ? 'color:#b7791f;margin-left:8px' : 'color:#b7791f' }, choice.warning) : ''
						])
					]);
				}, this));
			}
		});

		o = s.taboption('keepalive', KeepalivePeersValue, 'keepalive_peers', _('Keepalive Peers'), _('Only peers advertising subnet routes are shown. Selected peers are periodically pinged to keep cross-subnet paths active.'));
		o.rmempty = true;
		o.depends('keepalive_enabled', '1');

		o = s.taboption('keepalive', form.Value, 'keepalive_interval', _('Keepalive Interval'), _('Seconds between keepalive probes.'));
		o.datatype = 'uinteger';
		o.default = '20';
		o.depends('keepalive_enabled', '1');
		o.rmempty = false;

		o = s.taboption('keepalive', form.Value, 'keepalive_failure_log_interval', _('Failure Log Interval'), _('Seconds between repeated failure log messages for the same peer.'));
		o.datatype = 'uinteger';
		o.default = '300';
		o.depends('keepalive_enabled', '1');
		o.rmempty = false;

		s.tab('adguard_dns', _('AdGuard DNS'));
		let adguardApiUrlOption, adguardUsernameOption;
		let adguardDefaultUpstreamsOption, adguardTailnetUpstreamsOption, adguardHealthDomainOption, adguardHealthExpectedIpsOption;

		adguardApiUrlOption = s.taboption('adguard_dns', form.Value, 'adguard_api_url', _('AdGuard API URL'));
		adguardApiUrlOption.default = 'http://127.0.0.1:3000';
		adguardApiUrlOption.rmempty = false;

		adguardUsernameOption = s.taboption('adguard_dns', form.Value, 'adguard_username', _('AdGuard Username'));
		adguardUsernameOption.default = '';
		adguardUsernameOption.rmempty = true;

		adguardPasswordOption = s.taboption('adguard_dns', form.Value, 'adguard_password', _('AdGuard Password'));
		adguardPasswordOption.password = true;
		adguardPasswordOption.default = '';
		adguardPasswordOption.rmempty = true;
		adguardPasswordOption.placeholder = hasAdguardPassword ? _('Configured') : '';
		adguardPasswordOption.description = _('Leave blank to keep the existing AdGuard password; enter a new value to replace it.');
		adguardPasswordOption.cfgvalue = function() {
			return '';
		};
		adguardPasswordOption.write = function() {};
		adguardPasswordOption.remove = function() {};

		o = s.taboption('adguard_dns', form.DummyValue, '_adguard_dns_status', _('Status'));
		o.renderWidget = function() {
			return E('div', { class: 'table' }, ADGUARD_PREFLIGHT_CHECKS.map(function(check) {
				return E('div', { class: 'tr' }, [
					E('div', { class: 'td left' }, check.label),
					E('div', { class: 'td', id: adguardPreflightCellId(check.key) }, renderCheck())
				]);
			}));
		};

		o = s.taboption('adguard_dns', form.Flag, 'adguard_dns_switch_enabled', _('Enable AdGuard DNS Auto Switch'), _('Only enable when all status checks pass.'));
		o.default = o.disabled;
		o.rmempty = false;
		o.write = function(section_id, value) {
			const password = String(adguardPasswordOption.formvalue(section_id) || '');
			const candidateRequest = buildAdguardPreflightRequest({
				apiUrl: String(adguardApiUrlOption.formvalue(section_id) || '').trim(),
				username: String(adguardUsernameOption.formvalue(section_id) || '').trim(),
				password: password,
				keepPassword: !password && hasAdguardPassword,
				defaultUpstreams: adguardDefaultUpstreamsOption.formvalue(section_id),
				tailnetUpstreams: adguardTailnetUpstreamsOption.formvalue(section_id),
				healthDomain: String(adguardHealthDomainOption.formvalue(section_id) || '').trim(),
				expectedIps: adguardHealthExpectedIpsOption.formvalue(section_id)
			});

			return writeAdguardDnsSwitchEnabled(section_id, value, candidateRequest, persistedAdguardConfig);
		};
		o.validate = function(section_id, value) {
			if (value !== '1')
				return true;

			if (!String(adguardHealthDomainOption.formvalue(section_id) || '').trim())
				return _('Health Check Domain is required before enabling AdGuard DNS auto switch.');

			if (!hasFormListValue(adguardHealthExpectedIpsOption, section_id))
				return _('At least one Expected Internal IP is required before enabling AdGuard DNS auto switch.');

			if (!hasFormListValue(adguardDefaultUpstreamsOption, section_id))
				return _('At least one Default Upstream is required before enabling AdGuard DNS auto switch.');

			if (!hasFormListValue(adguardTailnetUpstreamsOption, section_id))
				return _('At least one Tailnet Upstream is required before enabling AdGuard DNS auto switch.');

			return true;
		};

		adguardDefaultUpstreamsOption = s.taboption('adguard_dns', form.DynamicList, 'adguard_default_upstreams', _('Default Upstreams'), _('Used when Tailnet DNS is unhealthy.'));
		adguardDefaultUpstreamsOption.default = '';
		adguardDefaultUpstreamsOption.rmempty = true;

		adguardTailnetUpstreamsOption = s.taboption('adguard_dns', form.DynamicList, 'adguard_tailnet_upstreams', _('Tailnet Upstreams'), _('Added when Tailnet DNS is healthy.'));
		adguardTailnetUpstreamsOption.default = '';
		adguardTailnetUpstreamsOption.rmempty = true;

		adguardHealthDomainOption = s.taboption('adguard_dns', form.Value, 'adguard_health_domain', _('Health Check Domain'), _('Resolved through Tailscale DNS 100.100.100.100. The result must match one of the expected internal IPs.'));
		adguardHealthDomainOption.rmempty = true;

		adguardHealthExpectedIpsOption = s.taboption('adguard_dns', form.DynamicList, 'adguard_health_expected_ips', _('Expected Internal IPs'));
		adguardHealthExpectedIpsOption.default = '';
		adguardHealthExpectedIpsOption.rmempty = true;

		o = s.taboption('adguard_dns', form.Value, 'adguard_check_interval', _('Check Interval'));
		o.datatype = 'uinteger';
		o.default = '10';
		o.rmempty = false;

		o = s.taboption('adguard_dns', form.Value, 'adguard_success_threshold', _('Success Threshold'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = s.taboption('adguard_dns', form.Value, 'adguard_failure_threshold', _('Failure Threshold'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		s.tab('openclash', _('OpenClash'));

		o = s.taboption('openclash', form.Flag, 'openclash_bypass_enabled', _('Protect Tailscale Traffic (Bypass OpenClash)'),
			_('Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash.'));
		o.default = o.enabled;
		o.rmempty = false;
		o.cfgvalue = function() {
			return uci.get('tailscale_openclash', 'settings', 'enabled') || '1';
		};
		o.write = function(section_id, value) {
			return uci.set('tailscale_openclash', 'settings', 'enabled', value);
		};
		o.remove = function() {
			return uci.set('tailscale_openclash', 'settings', 'enabled', '0');
		};

		o = s.taboption('openclash', form.DummyValue, '_openclash_bypass_status', _('Status'));
		o.rawhtml = true;
		o.cfgvalue = function() { return ''; };
		o.renderWidget = function() {
			return E('span', { id: 'openclash_bypass_status' }, _('Checking ...'));
		};

		s.tab('extra', _('Extra Settings'));

		o = s.taboption('extra', form.DynamicList, 'flags', _('Additional Flags'),
			String.format(
				_('List of extra flags. Format: --flags=value, e.g. <code>--exit-node=10.0.0.1</code>. <br> %s for enabling settings upon the initiation of Tailscale.'),
				'<a href="https://tailscale.com/kb/1241/tailscale-up" target="_blank">' + _('Available flags') + '</a>'
			)
		);
		o.default = '';
		o.rmempty = true;

		s = m.section(form.NamedSection, 'settings', 'config');
		s.title = _('Custom Server Settings');
		s.description = String.format(_('Use %s to deploy a private server.'), '<a href="https://github.com/juanfont/headscale" target="_blank">headscale</a>');

		o = s.option(form.Value, 'login_server', _('Server Address'));
		o.default = '';
		o.rmempty = true;

		authKeyOption = s.option(form.Value, 'authkey', _('Auth Key'));
		authKeyOption.password = true;
		authKeyOption.default = '';
		authKeyOption.rmempty = true;
		authKeyOption.placeholder = hasAuthKey ? _('Configured') : '';
		authKeyOption.description = _('Used once for first-time enrollment or explicit re-enrollment, then removed after a successful connection. Leave blank for normal restarts.');
		authKeyOption.cfgvalue = function() {
			return '';
		};
		authKeyOption.write = function() {};
		authKeyOption.remove = function() {};

		m.save = function(cb, silent) {
			if (saveInFlight)
				return saveInFlight;

			const map = this;
			saveInFlight = saveMapWithSecrets(map, cb, silent, function() {
				const request = Object.freeze(buildSecretUpdateRequest({
					authkey: authKeyOption.formvalue('settings'),
					adguardPassword: adguardPasswordOption.formvalue('settings'),
					adguardApiUrl: adguardApiUrlOption.formvalue('settings'),
					adguardUsername: adguardUsernameOption.formvalue('settings'),
					baseRef: uci.get('tailscale', 'settings', 'secrets_ref')
				}));

				if (request.authkey_set !== '1' && request.adguard_password_set !== '1')
					return { request: request, ref: request.base_ref };

				return callSetSecrets(
					request.authkey_set,
					request.authkey,
					request.adguard_password_set,
					request.adguard_password,
					request.api_url,
					request.username,
					request.base_ref
				).then(function(result) {
					const ref = String(result && result.ref || '');
					if (!result || result.code !== 0 || !/^[A-Za-z0-9_.-]+$/.test(ref))
						throw new Error(_('Failed to stage protected credentials.'));
					uci.set('tailscale', 'settings', 'secrets_ref', ref);
					return { request: request, ref: ref };
				});
			}, function(staged) {
				const request = staged.request;
				const updateStatus = function() {
					if (request.authkey_set === '1') {
						hasAuthKey = true;
						authKeyOption.placeholder = _('Configured');
					}
					if (request.adguard_password_set === '1') {
						hasAdguardPassword = true;
						adguardPasswordOption.placeholder = _('Configured');
					}
					persistedAdguardConfig = readPersistedAdguardConfig();
				};
				updateStatus();
			}).then(function(result) {
				window.setTimeout(refreshOpenclashBypassStatus, 0);
				window.setTimeout(refreshPolicyRoutingStatus, 0);
				return result;
			}).finally(function() {
				saveInFlight = null;
			});
			return saveInFlight;
		};

		return Promise.resolve(m.render()).then(function(node) {
			window.setTimeout(refreshAdguardPreflightStatus, 0);
			window.setTimeout(refreshOpenclashBypassStatus, 0);
			window.setTimeout(refreshPolicyRoutingStatus, 0);
			return node;
		});
	}
});
