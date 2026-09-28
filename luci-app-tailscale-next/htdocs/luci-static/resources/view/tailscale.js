'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require uci';
'require tools.widgets as widgets';

const callGetStatus = rpc.declare({ object: 'tailscale', method: 'get_status' });
const callGetSettings = rpc.declare({ object: 'tailscale', method: 'get_settings' });
const callDoLogin = rpc.declare({ object: 'tailscale', method: 'do_login', params: ['form_data'] });
const callDoLogout = rpc.declare({ object: 'tailscale', method: 'do_logout' });
const callGetSubroutes = rpc.declare({ object: 'tailscale', method: 'get_subroutes' });
const callGetLogs = rpc.declare({ object: 'tailscale', method: 'get_logs' });
const callReloadSettings = rpc.declare({ object: 'tailscale', method: 'reload_settings' });
const callRestart = rpc.declare({ object: 'tailscale', method: 'restart' });
let map;

const tailscaleSettingsConf = [
	[form.Flag, 'service_enabled', _('Enable Tailscale Service'), _('Enable or disable the Tailscale background service (/etc/init.d/tailscale).'), { rmempty: false }],
	[form.Flag, 'runwebclient', _('Enable Web Interface'), _('Expose a local web interface on port 5252 for managing this node over Tailscale (--webclient).'), { rmempty: false }],
	[form.Flag, 'tunnel_snat', _('Enable Tunnel Traffic SNAT'), _('Use OpenWrt system firewall to manage NAT for Tailscale tunnel and subnet traffic. Disabling this option disables source address masquerading to preserve real source IPs of remote peers and subnets in the local network.'), { default: '0', rmempty: false }],
	[form.Flag, 'accept_routes', _('Accept Routes'), _('Allow accepting subnet routes announced by other nodes (--accept-routes).'), { rmempty: false }],
	[form.Flag, 'advertise_exit_node', _('Advertise Exit Node'), _('Declare this device as an exit node, allowing other nodes to route all traffic through it (--advertise-exit-node).'), { rmempty: false }],
	[form.Flag, 'exit_node_allow_lan_access', _('Allow LAN Access'), _('When using or advertising the exit node, allow access to the local LAN (--exit-node-allow-lan-access).'), { rmempty: false, depends: { 'advertise_exit_node': '1' } }],
	[form.Flag, 'ssh', _('Enable Tailscale SSH'), _('Allow connecting to this device through the native SSH function of Tailscale (--ssh).'), { rmempty: false }],
	[form.Flag, 'shields_up', _('Shields Up'), _('When enabled, blocks all inbound connections from the Tailscale network (--shields-up).'), { rmempty: false }],
	[form.ListValue, 'dns_mode', _('DNS Mode'), _('Controls how Tailscale DNS is handled (--accept-dns).') + '<br>' + _('Disabled: system DNS only.') + '<br>' + _('MagicDNS: Tailscale overrides resolv.conf.') + '<br>' + _('OpenWrt Forward: MagicDNS via dnsmasq forwarding.(Only support ts.net)'), { values: [['disabled', _('Disabled')], ['magicdns', 'MagicDNS'], ['openwrt_forward', _('OpenWrt Forward')]], rmempty: false }],
	[form.Flag, 'enable_relay', _('Enable Peer Relay'), _('Enable this device as a Peer Relay server (--peer-relay). Requires a public IP and an UDP port open on the router.'), { rmempty: false }]
];

const daemonConf = [
	[form.Flag, 'daemon_reduce_memory', _('(Experimental) Reduce Memory Usage'), _('Enabling this option can reduce memory usage, but it may sacrifice some performance (set GOGC=10).'), { rmempty: false }]
];

// this function copy from luci-app-frpc. thx
function setParams(o, params) {
	if (!params) return;

	for (const [key, val] of Object.entries(params)) {
		if (key === 'values') {
			[].concat(val).forEach(v =>
				o.value.apply(o, Array.isArray(v) ? v : [v])
			);
		} else if (key === 'depends') {
			const arr = Array.isArray(val) ? val : [val];
			o.deps = arr.map(dep => Object.assign({}, ...o.deps, dep));
		} else {
			o[key] = val;
		}
	}

	if (params.datatype === 'bool')
		Object.assign(o, { enabled: 'true', disabled: 'false' });
}

// this function copy from luci-app-frpc. thx
function defTabOpts(s, t, opts, params) {
	for (let i = 0; i < opts.length; i++) {
		const opt = opts[i];
		const o = s.taboption(t, opt[0], opt[1], opt[2], opt[3]);
		setParams(o, opt[4]);
		setParams(o, params);
	}
}

function getRunningStatus() {
	return L.resolveDefault(callGetStatus(), { running: false }).then(function (res) {
		return res;
	});
}

function formatBytes(bytes) {
	const bytes_num = parseInt(bytes, 10);
	if (isNaN(bytes_num) || bytes_num === 0) return '-';
	const k = 1000;
	const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
	const i = Math.floor(Math.log(bytes_num) / Math.log(k));
	return parseFloat((bytes_num / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatLastSeen(d) {
	if (!d) return _('N/A');
	if (d === '0001-01-01T00:00:00Z') return _('Now');
	const t = new Date(d);
	if (isNaN(t)) return _('Invalid Date');
	const diff = (Date.now() - t) / 1000;
	if (diff < 0) return t.toLocaleString();
	if (diff < 60) return _('Just now');

	const mins = diff / 60, hrs = mins / 60, days = hrs / 24;
	const fmt = (n, s, p) => `${Math.floor(n)} ${Math.floor(n) === 1 ? _(s) : _(p)} ${_('ago')}`;

	if (mins < 60) return fmt(mins, 'minute', 'minutes');
	if (hrs < 24) return fmt(hrs, 'hour', 'hours');
	if (days < 30) return fmt(days, 'day', 'days');

	return t.toISOString().slice(0, 10);
}

const defaultDerpRegions = {
	"1": "NYC", "nyc": "NYC",
	"2": "SFO", "sfo": "SFO",
	"3": "SIN", "sin": "SIN",
	"4": "FRA", "fra": "FRA",
	"5": "SYD", "syd": "SYD",
	"6": "BLR", "blr": "BLR",
	"7": "NRT", "nrt": "NRT",
	"8": "LHR", "lhr": "LHR",
	"9": "DFW", "dfw": "DFW",
	"10": "SEA", "sea": "SEA",
	"11": "MIA", "mia": "MIA",
	"12": "ORD", "ord": "ORD",
	"13": "MAD", "mad": "MAD",
	"14": "AMS", "ams": "AMS",
	"15": "WAW", "waw": "WAW",
	"16": "YUL", "yul": "YUL",
	"17": "LAX", "lax": "LAX",
	"18": "SCL", "scl": "SCL",
	"19": "DXB", "dxb": "DXB",
	"20": "DEN", "den": "DEN",
	"21": "JNB", "jnb": "JNB",
	"22": "GRU", "gru": "GRU",
	"23": "DUB", "dub": "DUB",
	"24": "MAN", "man": "MAN",
	"25": "HND", "hnd": "HND",
	"26": "YYZ", "yyz": "YYZ"
};
let regionCodeMap = Object.assign({}, defaultDerpRegions);

function getRegionName(idOrCode) {
	if (!idOrCode) return '';
	return regionCodeMap[idOrCode] || regionCodeMap[String(idOrCode).toLowerCase()] || '';
}

function formatConnectionInfo(info) {
	if (!info) { return '-'; }
	if (typeof info === 'string' && info.length === 3) {
		const lowerCaseInfo = info.toLowerCase();
		return regionCodeMap[lowerCaseInfo] || info;
	}
	return info;
}

function handleLogin() {
	const customServerInput = document.getElementById('widget.cbid.tailscale.settings.custom_login_url');
	const customServer = (customServerInput ? customServerInput.value : '') || uci.get('tailscale', 'settings', 'custom_login_url') || '';
	const customServerAuthInput = document.getElementById('widget.cbid.tailscale.settings.custom_login_AuthKey');
	const customServerAuth = (customServerAuthInput ? customServerAuthInput.value : '') || uci.get('tailscale', 'settings', 'custom_login_AuthKey') || '';

	const loginWindow = window.open('', '_blank');
	if (!loginWindow) {
		ui.addTimeLimitedNotification(null, [ E('p', _('Could not open a new tab. Please check if your browser or an extension blocked the pop-up.')) ], 10000, 'error');
		return;
	}

	const doc = loginWindow.document;
	doc.body.innerHTML =
		'<h2>' + _('Tailscale Login') + '</h2>' +
		'<p>' + _('Requesting Tailscale login URL... Please wait.') + '</p>' +
		'<p>' + _('This can take up to 30 seconds.') + '</p>';

	ui.showModal(_('Requesting Login URL...'), E('em', {}, _('Please wait.')));
	const payload = {
		loginserver: customServer,
		loginserver_authkey: customServerAuth
	};

	return callDoLogin(payload).then(function(res) {
		ui.hideModal();
		if (res && res.url) {
			loginWindow.location.href = res.url;
		} else {
			doc.body.innerHTML =
				'<h2>' + _('Error') + '</h2>' +
				'<p>' + _('Failed to get login URL. You may close this tab.') + '</p>';
			ui.addTimeLimitedNotification(null, [ E('p', _('Failed to get login URL: Invalid response from server.')) ], 7000, 'error');
		}
	}).catch(function(err) {
		ui.hideModal();
		ui.addTimeLimitedNotification(null, [ E('p', _('Failed to get login URL: %s').format(err.message || _('Unknown error'))) ], 7000, 'error');
	});
}

function handleLogout() {
	const confirmationContent = E([
		E('p', {}, _('Are you sure you want to log out?') + '<br>' + _('This will disconnect this device from your Tailnet and require you to re-authenticate.')),
		E('div', { 'style': 'text-align: right; margin-top: 1em;' }, [
			E('button', {
				'class': 'cbi-button',
				'click': ui.hideModal
			}, _('Cancel')),
			' ',
			E('button', {
				'class': 'cbi-button cbi-button-negative',
				'click': function() {
					ui.hideModal();
					ui.showModal(_('Logging out...'), E('em', {}, _('Please wait.')));

					return callDoLogout().then(function(res) {
						ui.hideModal();
						ui.addTimeLimitedNotification(null, [ E('p', _('Successfully logged out.')) ], 3000, 'info');
						window.location.reload();
					}).catch(function(err) {
						ui.hideModal();
						ui.addTimeLimitedNotification(null, [ E('p', _('Logout failed: %s').format(err.message || _('Unknown error'))) ], 7000, 'error');
					});
				}
			}, _('Logout'))
		])
	]);
	ui.showModal(_('Confirm Logout'), confirmationContent);
}

function handleRestart() {
	ui.showModal(_('Restart Service'), [
		E('p', {}, _('Are you sure you want to restart Tailscale service?')),
		E('div', { 'class': 'right', 'style': 'margin-top: 15px;' }, [
			E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'click': ui.hideModal
			}, _('Cancel')),
			' ',
			E('button', {
				'class': 'cbi-button cbi-button-apply',
				'click': function(ev) {
					ui.showModal(_('Restarting Tailscale...'), [
						E('p', { 'class': 'spinning' }, _('Please wait while the service is restarting...'))
					]);
					return L.resolveDefault(callRestart(), {}).then(function() {
						return new Promise(resolve => setTimeout(resolve, 2000));
					}).then(function() {
						ui.hideModal();
						window.location.reload();
					}).catch(function(e) {
						ui.addNotification(null, E('p', {}, _('Failed to restart: %s').format(e.message || e)), 'error');
						ui.hideModal();
					});
				}
			}, _('Restart'))
		])
	]);
}

function renderStatus(status) {
	// If status object is not yet available, show a loading message.
	if (!status || !status.hasOwnProperty('status')) {
		return E('em', {}, _('Collecting data ...'));
	}

	const customServerUrl = uci.get('tailscale', 'settings', 'custom_login_url');
	let serverDisplayText = _('Official Server (Tailscale SaaS)');
	if (customServerUrl && customServerUrl !== '') {
		serverDisplayText = _('Custom Server (%s)').format(customServerUrl.replace(/^https?:\/\//, ''));
	}

	let statusBadge;
	let actionButtons = [];

	if (status.status === 'not_installed') {
		statusBadge = E('span', { 'style': 'color:red;' }, E('strong', {}, _('NOT INSTALLED')));
	} else if (status.status === 'logout') {
		statusBadge = E('span', { 'style': 'color:red;' }, E('strong', {}, _('NOT LOGGED IN')));
		actionButtons.push(E('button', {
			'class': 'cbi-button cbi-button-action',
			'style': 'margin-left: 10px; padding: 2px 10px;',
			'click': ui.createHandlerFn(this, handleLogin)
		}, _('Login')));
	} else if (status.status === 'running') {
		statusBadge = E('span', { 'style': 'color:green;' }, E('strong', {}, _('RUNNING')));
		actionButtons.push(E('button', {
			'class': 'cbi-button cbi-button-apply',
			'style': 'margin-left: 10px; padding: 2px 10px;',
			'click': ui.createHandlerFn(this, handleRestart)
		}, _('Restart')));
		actionButtons.push(E('button', {
			'class': 'cbi-button cbi-button-remove',
			'style': 'margin-left: 8px; padding: 2px 10px;',
			'click': ui.createHandlerFn(this, handleLogout)
		}, _('Logout')));
	} else {
		// stopped / not running
		statusBadge = E('span', { 'style': 'color:orange;' }, E('strong', {}, _('NOT RUNNING')));
	}

	const statusData = [
		{ label: _('Service Status'), value: E('span', {}, [statusBadge, ...actionButtons]) },
		{ label: _('Control Server'), value: serverDisplayText },
		{ label: _('Version'), value: status.version || 'N/A' },
		{ label: _('TUN Mode'), value: status.TUNMode ? _('Enabled') : _('Disabled') },
		{ label: _('Tailscale IPv4'), value: status.ipv4 || '-' },
		{ label: _('Tailscale IPv6'), value: status.ipv6 || '-' },
		{ label: _('Tailnet Account'), value: status.account || status.domain_name || '-' }
	];

	const statusTable = E('table', { 'style': 'width: 100%; border-spacing: 0 5px;' }, [
		E('tr', {}, statusData.map(item => E('td', { 'style': 'padding-right: 20px;' }, E('strong', {}, item.label)))),
		E('tr', {}, statusData.map(item => E('td', { 'style': 'padding-right: 20px;' }, item.value)))
	]);

	let connSection = null;
	if (status.connectivity) {
		const conn = status.connectivity;
		const badges = [
			{ name: 'Varies', val: conn.varies, ok: (conn.varies === 'No') },
			{ name: 'IPv4', val: conn.ipv4, ok: (conn.ipv4 === 'Yes') },
			{ name: 'IPv6', val: conn.ipv6, ok: (conn.ipv6 === 'Yes') },
			{ name: 'UDP', val: conn.udp, ok: (conn.udp === 'Yes') },
			{ name: 'UPnP', val: conn.upnp, ok: (conn.upnp === 'Yes') },
			{ name: 'PCP', val: conn.pcp, ok: (conn.pcp === 'Yes') },
			{ name: 'NAT-PMP', val: conn.pmp, ok: (conn.pmp === 'Yes') },
			{ name: 'Hairpinning', val: conn.hairpinning, ok: (conn.hairpinning === 'Yes') }
		];

		const badgeElements = badges.map(b => {
			const color = b.ok ? '#28a745' : '#6c757d';
			return E('span', {
				'style': 'display: inline-block; margin-right: 8px; margin-bottom: 6px; padding: 2px 8px; border-radius: 3px; font-size: 12px; font-weight: bold; background: #e9ecef; color: ' + color + '; border: 1px solid #ced4da;'
			}, `${b.name}: ${b.val || 'No'}`);
		});

		let nearestDerpText = '-';
		if (conn.preferred_derp) {
			const regionName = getRegionName(conn.preferred_derp) || `DERP-${conn.preferred_derp}`;
			nearestDerpText = regionName + (conn.derp_latency ? ` (${conn.derp_latency})` : '');
		}

		let endpointsText = (conn.endpoints && conn.endpoints.length > 0) ? conn.endpoints.join(', ') : '-';

		connSection = E('div', { 'style': 'margin-top: 12px; padding-top: 10px; border-top: 1px dashed #ccc;' }, [
			E('div', { 'style': 'font-weight: bold; margin-bottom: 8px; font-size: 14px;' }, [
				_('Client Connectivity')
			]),
			E('div', { 'style': 'margin-bottom: 8px; font-size: 13px;' }, [
				E('strong', {}, _('Nearest Relay') + ': '),
				E('span', { 'style': 'color: #007bff; font-weight: bold;' }, nearestDerpText),
				E('span', { 'style': 'margin-left: 20px;' }, [
					E('strong', {}, _('Public Endpoints') + ': '),
					E('span', {}, endpointsText)
				])
			]),
			E('div', { 'style': 'margin-top: 4px;' }, badgeElements)
		]);
	}

	return E('div', {}, [statusTable, connSection].filter(Boolean));
}

function renderLogs(logs_data) {
	if (!logs_data || !logs_data.logs || logs_data.logs.length === 0) {
		return E('em', {}, _('No tailscale-related logs found.'));
	}

	const lines = logs_data.logs.map(function(line) {
		return E('div', { 'style': 'white-space: pre; font-family: monospace; font-size: 13px; line-height: 1.5;' }, line);
	});

	return E('div', {
		'style': 'max-height: 500px; overflow-y: auto; background: #f5f5f5; border: 1px solid #ccc; padding: 8px; border-radius: 3px;'
	}, lines);
}

function renderDevices(status) {
	if (!status || !status.hasOwnProperty('status')) {
		return E('em', {}, _('Collecting data ...'));
	}

	if (status.status === 'not_installed') {
		return E('em', {}, _('Tailscale is not installed.'));
	}

	if (status.status === 'logout') {
		return E('em', {}, _('Tailscale is not logged in. Please log in to view devices.'));
	}

	if (status.status !== 'running') {
		return E('em', {}, _('Tailscale is not running.'));
	}

	const peers = status.peers;
	if (!peers || Object.keys(peers).length === 0) {
		return E('p', {}, _('No peer devices found.'));
	}

	const peerTableHeaders = [
		{ text: _('Status'), style: 'width: 80px;' },
		{ text: _('Hostname') },
		{ text: _('Tailscale IP') },
		{ text: _('OS') },
		{ text: _('Connection Info') },
		{ text: _('RX') },
		{ text: _('TX') },
		{ text: _('Last Seen') }
	];

	return E('table', { 'class': 'cbi-table' }, [
		E('tr', { 'class': 'cbi-table-header' }, peerTableHeaders.map(header => {
			let th_style = 'padding-right: 20px; text-align: left;';
			if (header.style) {
				th_style += header.style;
			}
			return E('th', { 'class': 'cbi-table-cell', 'style': th_style }, header.text);
		})),

		...Object.entries(peers).map(([peerid, peer]) => {
			const td_style = 'padding-right: 20px;';

			return E('tr', { 'class': 'cbi-row', 'id': `tailscale-peer-${peerid}` }, [
				E('td', { 'class': 'cbi-value-field', 'style': td_style },
					E('span', {
						'class': peer.online ? 'badge-status-positive' : 'badge-status-neutral',
						'style': `color: ${peer.online ? 'green' : 'grey'}; font-size: 1.2em;`,
						'title': (peer.exit_node ? _('Exit Node') + ' ' : '') + (peer.online ? _('Online') : _('Offline'))
					}, peer.online ? '●' : '○')
				),
				E('td', { 'class': 'cbi-value-field', 'style': td_style }, E('strong', {}, peer.hostname + (peer.exit_node_option ? ' (ExNode)' : ''))),
				E('td', { 'class': 'cbi-value-field', 'style': td_style }, peer.ip || 'N/A'),
				E('td', { 'class': 'cbi-value-field', 'style': td_style }, peer.ostype || 'N/A'),
				E('td', { 'class': 'cbi-value-field', 'style': td_style }, formatConnectionInfo(peer.linkadress || '-')),
				E('td', { 'class': 'cbi-value-field', 'style': td_style }, formatBytes(peer.rx)),
				E('td', { 'class': 'cbi-value-field', 'style': td_style }, formatBytes(peer.tx)),
				E('td', { 'class': 'cbi-value-field', 'style': td_style }, formatLastSeen(peer.lastseen))
			]);
		})
	]);
}

return view.extend({
	load() {
		return Promise.all([
			L.resolveDefault(callGetStatus(), { running: '', peers: [] }),
			L.resolveDefault(callGetSettings(), { accept_routes: false }),
			L.resolveDefault(callGetSubroutes(), { routes: [] })
		])
		.then(function([status, settings_from_rpc, subroutes]) {
			return uci.load('tailscale').then(function() {
				if (uci.get('tailscale', 'settings') === null) {
					// No existing settings found; initialize UCI with RPC settings
					uci.add('tailscale', 'settings', 'settings');
					uci.set('tailscale', 'settings', 'service_enabled', '0');
					uci.set('tailscale', 'settings', 'accept_routes', (settings_from_rpc.accept_routes ? '1' : '0'));
					uci.set('tailscale', 'settings', 'advertise_exit_node', ((settings_from_rpc.advertise_exit_node || false) ? '1' : '0'));
					uci.set('tailscale', 'settings', 'advertise_routes', (settings_from_rpc.advertise_routes || []).join(', '));
					uci.set('tailscale', 'settings', 'exit_node', settings_from_rpc.exit_node || '');
					uci.set('tailscale', 'settings', 'exit_node_allow_lan_access', ((settings_from_rpc.exit_node_allow_lan_access || false) ? '1' : '0'));
					uci.set('tailscale', 'settings', 'ssh', ((settings_from_rpc.ssh || false) ? '1' : '0'));
					uci.set('tailscale', 'settings', 'shields_up', ((settings_from_rpc.shields_up || false) ? '1' : '0'));
					uci.set('tailscale', 'settings', 'runwebclient', ((settings_from_rpc.runwebclient || false) ? '1' : '0'));
					uci.set('tailscale', 'settings', 'tunnel_snat', (settings_from_rpc.tunnel_snat || '0'));
					uci.set('tailscale', 'settings', 'dns_mode', 'disabled');

					uci.set('tailscale', 'settings', 'daemon_reduce_memory', '0');
					uci.set('tailscale', 'settings', 'daemon_mtu', '');
					return uci.save();
				}
			}).then(function() {
				var dirty = false;
				// Migrate from old disable_magic_dns to dns_mode if needed
				if (uci.get('tailscale', 'settings', 'dns_mode') === null) {
					var oldMagicDns = uci.get('tailscale', 'settings', 'disable_magic_dns');
					uci.set('tailscale', 'settings', 'dns_mode', oldMagicDns === '1' ? 'disabled' : 'magicdns');
					uci.unset('tailscale', 'settings', 'disable_magic_dns');
					dirty = true;
				}
				// Migrate and clean up legacy nosnat and outbound_masq options
				if (uci.get('tailscale', 'settings', 'tunnel_snat') === null) {
					var oldNosnat = uci.get('tailscale', 'settings', 'nosnat');
					var oldMasq = uci.get('tailscale', 'settings', 'outbound_masq');
					if (oldNosnat !== null) {
						uci.set('tailscale', 'settings', 'tunnel_snat', oldNosnat === '1' ? '0' : '1');
					} else if (oldMasq !== null) {
						uci.set('tailscale', 'settings', 'tunnel_snat', oldMasq === '1' ? '1' : '0');
					} else {
						uci.set('tailscale', 'settings', 'tunnel_snat', '0');
					}
					dirty = true;
				}
				if (uci.get('tailscale', 'settings', 'nosnat') !== null) {
					uci.unset('tailscale', 'settings', 'nosnat');
					dirty = true;
				}
				if (uci.get('tailscale', 'settings', 'outbound_masq') !== null) {
					uci.unset('tailscale', 'settings', 'outbound_masq');
					dirty = true;
				}
				if (dirty) {
					return uci.save();
				}
			}).then(function() {
				return [status, settings_from_rpc, subroutes];
			});
		});
	},

	render ([status = {}, settings = {}, subroutes_obj]) {
		const subroutes = (subroutes_obj && subroutes_obj.routes) ? subroutes_obj.routes : [];

		let s;
		map = new form.Map('tailscale', _('Tailscale'), _('Tailscale is a mesh VPN solution that makes it easy to connect your devices securely. This configuration page allows you to manage Tailscale settings on your OpenWrt device.'));

		let lastStatus = null;
		s = map.section(form.NamedSection, '_status');
		s.anonymous = true;
		s.render = function (section_id) {
			L.Poll.add(
				function () {
					return getRunningStatus().then(function (res) {
						if (lastStatus === 'logout' && (res.status === 'running' || res.status === 'stopped')) {
							L.resolveDefault(callReloadSettings(), {}).then(function() {
								window.location.reload();
							});
						}
						if (res.status === 'logout' || res.status === 'running' || res.status === 'stopped') {
							lastStatus = res.status;
						}

						const view = document.getElementById("service_status_display");
						if (view) {
							const content = renderStatus(res);
							view.replaceChildren(content);
						}

						const devicesView = document.getElementById("tailscale_devices_display");
						if (devicesView) {
							devicesView.replaceChildren(renderDevices(res));
						}
					});
				}, 5);

			return E('div', {}, [
				E('hr', { 'style': 'margin: 5px 0 15px 0; border: 0; border-top: 1px solid #e5e5e5;' }),
				E('div', { 'id': 'service_status_display', 'class': 'cbi-value' },
					_('Collecting data ...')
				)
			]);
		}

		// Bind settings to the 'settings' section of uci
		s = map.section(form.NamedSection, 'settings', 'settings', null);
		s.dynamic = true;

		// Tab 1: General Settings
		s.tab('general', _('General Settings'));

		defTabOpts(s, 'general', tailscaleSettingsConf, { optional: false });

		const relayPort = s.taboption('general', form.Value, 'relay_server_port', _('Peer Relay Port'),
			_('UDP port for the Peer Relay service (--peer-relay-port). Open this port on your router firewall/NAT.')
		);
		relayPort.datatype = 'port';
		relayPort.placeholder = '40000';
		relayPort.rmempty = false;
		relayPort.depends('enable_relay', '1');

		const en = s.taboption('general', form.ListValue, 'exit_node', _('Exit Node'), _('Select an exit node from the list (--exit-node). If enabled, Allow LAN Access is enabled implicitly.'));
		en.value('', _('None'));
		if (status.peers) {
			Object.values(status.peers).forEach(function(peer) {
				if (peer.exit_node_option) {
					const primaryIp = peer.ip.split('<br>')[0];
					const label = peer.hostname ? `${peer.hostname} (${primaryIp})` : primaryIp;
					en.value(primaryIp, label);
				}
			});
		}
		en.rmempty = true;
		en.cfgvalue = function(section_id) {
			if (status && status.status === 'running' && status.peers) {
				for (const id in status.peers) {
					if (status.peers[id].exit_node) {
						return status.peers[id].ip.split('<br>')[0];
					}
				}
				return '';
			}
			return uci.get('tailscale', 'settings', 'exit_node') || '';
		};

		const o = s.taboption('general', form.DynamicList, 'advertise_routes', _('Advertise Subnet Routes'),
			_('Announce subnet routes behind this device (--advertise-routes). Select from the detected subnets below or enter custom routes (comma-separated).')
		);
		if (subroutes.length > 0) {
			subroutes.forEach(function(subnet) {
				o.value(subnet, subnet);
			});
		}
		o.rmempty = true;

		const customLoginUrl = s.taboption('general', form.Value, 'custom_login_url',
			_('Custom Control Server'),
			_('Optional: Specify a custom control server URL (e.g., a Headscale instance, --login-server). Leave blank for default Tailscale control plane.')
		);
		customLoginUrl.placeholder = '';
		customLoginUrl.rmempty = true;

		const customLoginAuthKey = s.taboption('general', form.Value, 'custom_login_AuthKey',
			_('Custom Server Auth Key'),
			_('Optional: Specify an authentication key for the custom control server (--auth-key). Leave blank if not required.')
		);
		customLoginAuthKey.placeholder = '';
		customLoginAuthKey.rmempty = true;

		defTabOpts(s, 'general', daemonConf, { optional: false });

		// Tab 2: Devices List
		s.tab('devices', _('Devices List'));

		const refreshDevicesBtn = s.taboption('devices', form.Button, '_refresh_devices', _('Refresh'));
		refreshDevicesBtn.inputstyle = 'action';
		refreshDevicesBtn.onclick = function() {
			const display = document.getElementById('tailscale_devices_display');
			if (display) {
				display.replaceChildren(E('em', {}, _('Collecting data ...')));
			}
			return getRunningStatus().then(function(res) {
				if (display) {
					display.replaceChildren(renderDevices(res));
				}
			}).catch(function(err) {
				if (display) {
					display.replaceChildren(E('em', {}, _('Failed to load devices: %s').format(err.message || _('Unknown error'))));
				}
			});
		};

		const devicesSection = s.taboption('devices', form.DummyValue, '_devices');
		devicesSection.render = function () {
			return E('div', { 'id': 'tailscale_devices_display', 'class': 'cbi-value' }, renderDevices(status));
		};

		// Tab 3: Logs
		s.tab('logs', _('Logs'));
		const logsSection = s.taboption('logs', form.DummyValue, '_logs');
		logsSection.render = function () {
			const container = E('div', { 'id': 'tailscale_logs_display', 'class': 'cbi-value' },
				_('No tailscale-related logs found.')
			);
			return container;
		};

		const refreshLogsBtn = s.taboption('logs', form.Button, '_refresh_logs', _('Refresh'));
		refreshLogsBtn.inputstyle = 'action';
		refreshLogsBtn.onclick = function() {
			const display = document.getElementById('tailscale_logs_display');
			if (display) {
				display.replaceChildren(E('em', {}, _('Collecting data ...')));
			}
			return callGetLogs().then(function(res) {
				if (display) {
					display.replaceChildren(renderLogs(res));
				}
			}).catch(function(err) {
				if (display) {
					display.replaceChildren(E('em', {}, _('Failed to load logs: %s').format(err.message || _('Unknown error'))));
				}
			});
		};

		return map.render();
	},

	handleSaveApply(ev, mode) {
		return map.save().then(function () {
			return ui.changes.apply(mode == '0');
		});
	}
});
