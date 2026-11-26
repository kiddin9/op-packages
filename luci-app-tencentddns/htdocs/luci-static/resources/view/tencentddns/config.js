'use strict';
'require view';
'require dom';
'require form';
'require uci';
'require rpc';
'require ui';
'require poll';
'require tools.widgets as widgets';

var callGetStatus = rpc.declare({
	object: 'luci.tencentddns',
	method: 'get_status',
	expect: { '': {} }
});

var callSyncNow = rpc.declare({
	object: 'luci.tencentddns',
	method: 'sync_now',
	params: [ 'section', 'force' ],
	expect: { '': {} }
});

var callTestRule = rpc.declare({
	object: 'luci.tencentddns',
	method: 'test_rule',
	params: [ 'section' ],
	expect: { '': {} }
});

var callServiceAction = rpc.declare({
	object: 'luci.tencentddns',
	method: 'service_action',
	params: [ 'action' ],
	expect: { '': {} }
});

function formatTimestamp(ts) {
	if (!ts || ts <= 0)
		return _('Never');
	var d = new Date(ts * 1000);
	var pad = function(n) { return (n < 10 ? '0' : '') + n; };
	return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
		' ' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
}

function renderStatusBadge(status, syncing) {
	if (syncing) {
		return E('span', {
			'style': 'display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;background:#e0f2fe;color:#0369a1;'
		}, _('Syncing'));
	}
	if (status === 'synced') {
		return E('span', {
			'style': 'display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;background:#dcfce7;color:#15803d;'
		}, _('Synced'));
	}
	if (status === 'error') {
		return E('span', {
			'style': 'display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;background:#fee2e2;color:#b91c1c;'
		}, _('Error'));
	}
	if (status === 'disabled') {
		return E('span', {
			'style': 'display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;background:#f3f4f6;color:#6b7280;'
		}, _('Disabled'));
	}
	return E('span', {
		'style': 'display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600;background:#fef3c7;color:#b45309;'
	}, _('Pending'));
}

function formatModeLabel(mode) {
	if (mode === 'dual')
		return 'A + AAAA';
	if (mode === 'ipv6')
		return 'AAAA (IPv6)';
	return 'A (IPv4)';
}

function renderIpPair(rec, field) {
	var parts = [];
	if ((rec.ip_mode === 'ipv4' || rec.ip_mode === 'dual') && rec.ipv4 && rec.ipv4[field])
		parts.push(E('div', { 'style': 'font-family:monospace;font-size:12px;' }, 'IPv4: ' + rec.ipv4[field]));
	if ((rec.ip_mode === 'ipv6' || rec.ip_mode === 'dual') && rec.ipv6 && rec.ipv6[field])
		parts.push(E('div', { 'style': 'font-family:monospace;font-size:12px;word-break:break-all;' }, 'IPv6: ' + rec.ipv6[field]));
	if (parts.length === 0)
		return E('span', { 'style': 'opacity:0.6;' }, '-');
	return E('div', {}, parts);
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('tencentddns'),
			callGetStatus().catch(function() { return {}; })
		]);
	},

	buildDashboardContent: function(st) {
		var self = this;
		var running = !!st.service_running;
		var syncing = !!st.syncing;
		var records = Array.isArray(st.records) ? st.records : [];
		var activeCount = records.filter(function(r) { return r.enabled; }).length;

		var svcBadge = E('span', {
			'style': 'display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:12px;font-size:12px;font-weight:600;' +
				(running ? 'background:#dcfce7;color:#15803d;' : 'background:#f3f4f6;color:#4b5563;')
		}, [
			E('span', {
				'style': 'width:8px;height:8px;border-radius:50%;display:inline-block;' +
					(running ? 'background:#16a34a;' : 'background:#9ca3af;')
			}),
			running ? _('Running') : _('Stopped')
		]);

		var authLabel = (st.api_type === 'dnspod_token')
			? _('DNSPod Legacy Token')
			: _('Tencent Cloud API 3.0 (TC3-HMAC-SHA256)');

		var headerBar = E('div', {
			'style': 'display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:12px;margin-bottom:12px;'
		}, [
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:14px;' }, [
				svcBadge,
				E('span', { 'style': 'font-size:13px;opacity:0.85;' },
					_('Active Rules') + ': ' + activeCount + ' / ' + records.length),
				E('span', { 'style': 'font-size:13px;opacity:0.85;' },
					_('Auth Mode') + ': ' + authLabel),
				E('span', { 'style': 'font-size:13px;opacity:0.85;' },
					_('Check Interval') + ': ' + (st.check_interval || 5) + ' ' + _('min'))
			]),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:8px;' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(self, 'handleSyncRule', '')
				}, _('Sync All Now')),
				E('button', {
					'class': 'btn cbi-button ' + (running ? 'cbi-button-neutral' : 'cbi-button-apply'),
					'click': ui.createHandlerFn(self, 'handleServiceCtrl', running ? 'restart' : 'start')
				}, running ? _('Restart Service') : _('Start Service')),
				running ? E('button', {
					'class': 'btn cbi-button cbi-button-reset',
					'click': ui.createHandlerFn(self, 'handleServiceCtrl', 'stop')
				}, _('Stop Service')) : E('span')
			])
		]);

		if (records.length === 0) {
			return E('div', {}, [
				headerBar,
				E('div', { 'class': 'alert-message info', 'style': 'margin:0;' },
					_('No DDNS domain rules configured yet. Click Add below to create your first rule.'))
			]);
		}

		var rows = [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Domain')),
				E('th', { 'class': 'th' }, _('Type / Line')),
				E('th', { 'class': 'th' }, _('Local IP')),
				E('th', { 'class': 'th' }, _('Remote DNS IP')),
				E('th', { 'class': 'th' }, _('Status')),
				E('th', { 'class': 'th' }, _('Last Check')),
				E('th', { 'class': 'th cbi-section-actions' }, _('Actions'))
			])
		];

		records.forEach(function(rec) {
			var statusChildren = [ renderStatusBadge(rec.status, syncing && rec.enabled) ];
			if (rec.error) {
				statusChildren.push(E('div', {
					'style': 'font-size:11px;color:#dc2626;margin-top:4px;max-width:260px;word-break:break-word;'
				}, rec.error));
			}

			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, [
					E('strong', {}, rec.fqdn || '-'),
					rec.remark ? E('div', { 'style': 'font-size:12px;opacity:0.7;' }, rec.remark) : E('span')
				]),
				E('td', { 'class': 'td' }, [
					E('div', {}, formatModeLabel(rec.ip_mode)),
					E('div', { 'style': 'font-size:12px;opacity:0.7;' }, (rec.record_line || _('Default')) + ' / TTL ' + (rec.ttl || 600))
				]),
				E('td', { 'class': 'td' }, renderIpPair(rec, 'local_ip')),
				E('td', { 'class': 'td' }, renderIpPair(rec, 'remote_ip')),
				E('td', { 'class': 'td' }, statusChildren),
				E('td', { 'class': 'td', 'style': 'font-size:12px;' }, formatTimestamp(rec.last_check)),
				E('td', { 'class': 'td cbi-section-actions' }, [
					E('div', { 'style': 'display:flex;gap:6px;justify-content:flex-end;' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-action',
							'click': ui.createHandlerFn(self, 'handleSyncRule', rec.id)
						}, _('Sync Now')),
						E('button', {
							'class': 'btn cbi-button cbi-button-neutral',
							'click': ui.createHandlerFn(self, 'handleTestRule', rec.id, rec.fqdn)
						}, _('Test'))
					])
				])
			]));
		});

		return E('div', {}, [
			headerBar,
			E('table', { 'class': 'table cbi-section-table' }, rows)
		]);
	},

	refreshDashboard: function() {
		var self = this;
		if (!self.dashboardContainer)
			return Promise.resolve();
		return callGetStatus().then(function(st) {
			dom.content(self.dashboardContainer, self.buildDashboardContent(st || {}));
		}).catch(function() {});
	},

	handleSyncRule: function(sectionId) {
		var self = this;
		return callSyncNow(sectionId || '', true).then(function(res) {
			if (res && res.ok) {
				ui.addNotification(null, E('p', _('Synchronization task triggered. Status will refresh automatically.')), 'info');
			} else {
				ui.addNotification(null, E('p', (res && res.error) ? res.error : _('Failed to trigger synchronization')), 'warning');
			}
			window.setTimeout(function() { self.refreshDashboard(); }, 1800);
		});
	},

	handleServiceCtrl: function(action) {
		var self = this;
		return callServiceAction(action).then(function() {
			window.setTimeout(function() { self.refreshDashboard(); }, 1000);
		});
	},

	handleTestRule: function(sectionId, fqdn) {
		ui.showModal(_('Testing Rule Connectivity'), [
			E('p', { 'class': 'spinning' }, _('Testing local IP acquisition and Tencent Cloud API credentials...'))
		]);

		return callTestRule(sectionId || '').then(function(res) {
			var items = [];
			if (!res) {
				items.push(E('div', { 'class': 'alert-message warning' }, _('Empty response from backend')));
			} else if (res.error && !res.ipv4 && !res.ipv6) {
				items.push(E('div', { 'class': 'alert-message warning' }, res.error));
			} else {
				items.push(E('div', {
					'class': 'alert-message ' + (res.ok ? 'notice' : 'warning')
				}, res.ok ? _('Connectivity and API authentication test passed!') : _('Issues detected during connectivity test.')));

				var detailRows = [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, E('strong', {}, _('Domain'))),
						E('td', { 'class': 'td' }, res.fqdn || fqdn || '-')
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, E('strong', {}, _('Auth Mode'))),
						E('td', { 'class': 'td' }, (res.api_type === 'dnspod_token' ? 'DNSPod Token' : 'TC3-HMAC-SHA256') + ' (' + (res.endpoint || 'cn') + ')')
					])
				];

				[ 'ipv4', 'ipv6' ].forEach(function(fam) {
					if (!res[fam])
						return;
					var info = res[fam];
					var label = (fam === 'ipv4') ? 'IPv4 (A)' : 'IPv6 (AAAA)';
					detailRows.push(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, E('strong', {}, label + ' - ' + _('Local IP'))),
						E('td', { 'class': 'td', 'style': 'font-family:monospace;' },
							info.local_ip || (info.ip_error ? ('Error: ' + info.ip_error) : '-'))
					]));
					detailRows.push(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, E('strong', {}, label + ' - ' + _('Remote DNS IP'))),
						E('td', { 'class': 'td', 'style': 'font-family:monospace;' },
							info.api_ok
								? (info.remote_ip ? (info.remote_ip + ' (RecordId: ' + info.record_id + ')') : _('Not created yet (API Auth OK)'))
								: ('API Error: ' + (info.api_error || _('Authentication failed'))))
					]));
				});

				items.push(E('table', { 'class': 'table' }, detailRows));
			}

			items.push(E('div', { 'class': 'right', 'style': 'margin-top:12px;' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-primary',
					'click': ui.hideModal
				}, _('Close'))
			]));

			ui.showModal(_('Connectivity Test Result'), items);
		}).catch(function(err) {
			ui.showModal(_('Connectivity Test Result'), [
				E('div', { 'class': 'alert-message warning' }, '' + err),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Close'))
				])
			]);
		});
	},

	render: function(data) {
		var self = this;
		var initialStatus = data[1] || {};

		if (!uci.get('tencentddns', 'global')) {
			uci.add('tencentddns', 'global', 'global');
			uci.set('tencentddns', 'global', 'enabled', '0');
			uci.set('tencentddns', 'global', 'api_type', 'tc3');
			uci.set('tencentddns', 'global', 'endpoint', 'cn');
			uci.set('tencentddns', 'global', 'check_interval', '5');
			uci.set('tencentddns', 'global', 'force_interval', '24');
			uci.set('tencentddns', 'global', 'retry_interval', '60');
			uci.set('tencentddns', 'global', 'log_max_lines', '500');
		}

		var m = new form.Map('tencentddns', _('Tencent Cloud DDNS'),
			_('Automatically synchronize dynamic public IPv4 / IPv6 addresses to Tencent Cloud DNSPod DNS records via API 3.0 (TC3-HMAC-SHA256) or DNSPod Token.'));

		/* Live Status Section */
		var statusSec = m.section(form.NamedSection, 'global', 'global', _('Service Status'));
		statusSec.anonymous = true;
		statusSec.render = function() {
			self.dashboardContainer = E('div', { 'class': 'cbi-section-node', 'style': 'padding:12px 16px;' },
				self.buildDashboardContent(initialStatus));
			return E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Service Status')),
				self.dashboardContainer
			]);
		};

		/* Global Settings Section */
		var g = m.section(form.NamedSection, 'global', 'global', _('Global Settings'));
		g.anonymous = true;
		g.addremove = false;

		g.tab('basic', _('Basic & Credentials'));
		g.tab('schedule', _('Schedule & Probing'));

		var o;

		o = g.taboption('basic', form.Flag, 'enabled', _('Enable Service'),
			_('Enable background event-driven TencentDDNS daemon and real-time WAN change detection.'));
		o.rmempty = false;

		o = g.taboption('basic', form.ListValue, 'api_type', _('Authentication Mode'),
			_('Tencent Cloud API 3.0 supports CAM sub-account permission isolation and is recommended for all new deployments.'));
		o.value('tc3', _('Tencent Cloud API 3.0 (SecretId / SecretKey, Recommended)'));
		o.value('dnspod_token', _('DNSPod Legacy Token (ID / Token)'));
		o.default = 'tc3';
		o.rmempty = false;

		o = g.taboption('basic', form.ListValue, 'endpoint', _('API Endpoint'),
			_('Choose Mainland China for dnspod.cn / cloud.tencent.com accounts, or International for dnspod.com / tencentcloud.com accounts.'));
		o.value('cn', _('Mainland China (dnspod.tencentcloudapi.com)'));
		o.value('intl', _('International (dnspod.intl.tencentcloudapi.com)'));
		o.default = 'cn';
		o.rmempty = false;

		o = g.taboption('basic', form.Value, 'secret_id', _('SecretId / Token ID'),
			_('Obtain SecretId from <a href="https://console.cloud.tencent.com/cam/capi" target="_blank" rel="noopener noreferrer">Tencent Cloud API Key Console</a> or Token ID from <a href="https://console.dnspod.cn/account/token" target="_blank" rel="noopener noreferrer">DNSPod Token Console</a>.'));
		o.placeholder = 'AKID...';
		o.rmempty = true;
		o.write = function(section_id, formvalue) {
			return this.super('write', [ section_id, (formvalue || '').trim() ]);
		};

		o = g.taboption('basic', form.Value, 'secret_key', _('SecretKey / Token'),
			_('Keep your SecretKey confidential. Use a CAM sub-account with QcloudDNSPodFullAccess for least privilege.'));
		o.password = true;
		o.rmempty = true;
		o.write = function(section_id, formvalue) {
			return this.super('write', [ section_id, (formvalue || '').trim() ]);
		};

		o = g.taboption('schedule', form.Value, 'check_interval', _('Check Interval (Minutes)'),
			_('Periodic verification interval in minutes (1-1440). Network interface up/change events also trigger immediate checks.'));
		o.datatype = 'range(1, 1440)';
		o.default = '5';
		o.rmempty = false;

		o = g.taboption('schedule', form.Value, 'force_interval', _('Force Sync Interval (Hours)'),
			_('Re-verify against Tencent Cloud API even if local IP has not changed (0 to disable).'));
		o.datatype = 'range(0, 720)';
		o.default = '24';
		o.rmempty = false;

		o = g.taboption('schedule', form.Value, 'retry_interval', _('Failure Retry Interval (Seconds)'),
			_('Backoff delay before retrying when IP detection or API request fails.'));
		o.datatype = 'range(10, 3600)';
		o.default = '60';
		o.rmempty = false;

		o = g.taboption('schedule', form.DynamicList, 'ipv4_url', _('IPv4 Check URLs'),
			_('HTTPS endpoints queried in order when IPv4 source is set to Public Check URL.'));
		o.datatype = 'url';

		o = g.taboption('schedule', form.DynamicList, 'ipv6_url', _('IPv6 Check URLs'),
			_('HTTPS endpoints queried in order when IPv6 source is set to Public Check URL.'));
		o.datatype = 'url';

		o = g.taboption('schedule', form.Value, 'log_max_lines', _('Max Log Lines'),
			_('Maximum lines retained in /var/log/tencentddns.log with automatic rolling truncation.'));
		o.datatype = 'range(50, 5000)';
		o.default = '500';
		o.rmempty = false;

		o = g.taboption('schedule', form.Flag, 'insecure_tls', _('Skip TLS Certificate Verification'),
			_('Only enable temporarily for troubleshooting missing CA certificates.'));
		o.default = '0';

		/* Multi-Domain Rules GridSection */
		var s = m.section(form.GridSection, 'record', _('Domain DDNS Rules'),
			_('Configure one or more domains/subdomains. Supports root (@), wildcard (*), multi-level subdomains, dual-stack (A + AAAA), and dynamic IPv6 prefix + host suffix synthesis for LAN servers.'));
		s.addremove = true;
		s.anonymous = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.modaltitle = function(section_id) {
			var sub = uci.get('tencentddns', section_id, 'sub_domain') || '@';
			var main = uci.get('tencentddns', section_id, 'main_domain') || '';
			return main ? (_('Edit Rule') + ': ' + (sub === '@' ? main : sub + '.' + main)) : _('Edit DDNS Rule');
		};

		s.tab('general', _('General Settings'));
		s.tab('source', _('IP Source'));
		s.tab('override', _('Custom Credentials'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.editable = true;
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'remark', _('Remark'),
			_('Optional label such as Home Router or NAS.'));
		o.placeholder = 'NAS';

		o = s.taboption('general', form.Value, 'sub_domain', _('Host Record (Subdomain)'),
			_('Enter @ for root domain, * for wildcard, or a host prefix like www, nas, or *.home.'));
		o.default = '@';
		o.placeholder = '@';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			var v = (value || '').trim();
			if (!v)
				return _('Host record cannot be empty (use @ for root domain)');
			if (v === '@' || v === '*')
				return true;
			if (/^(\*\.)?[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$/.test(v))
				return true;
			return _('Invalid host record format (examples: @, *, www, nas.home)');
		};

		o = s.taboption('general', form.Value, 'main_domain', _('Main Domain'),
			_('Registered root domain hosted on DNSPod, for example example.com.'));
		o.placeholder = 'example.com';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			var v = (value || '').trim().replace(/^https?:\/\//i, '').replace(/\.$/, '');
			if (!v || v.indexOf('.') <= 0 || !/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(v))
				return _('Enter a valid root domain such as example.com');
			return true;
		};

		o = s.taboption('general', form.ListValue, 'ip_mode', _('Record Mode'),
			_('Dual-Stack maintains both IPv4 (A) and IPv6 (AAAA) records under a single rule.'));
		o.value('ipv4', _('IPv4 Only (A)'));
		o.value('ipv6', _('IPv6 Only (AAAA)'));
		o.value('dual', _('Dual-Stack (A + AAAA)'));
		o.default = 'ipv4';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'record_line', _('Split Line'),
			_('DNSPod DNS resolution split line. Leave as Default unless split-horizon routing is required.'));
		o.value('默认', _('Default'));
		o.value('电信', _('China Telecom'));
		o.value('联通', _('China Unicom'));
		o.value('移动', _('China Mobile'));
		o.value('教育网', _('CERNET'));
		o.value('境外', _('Overseas'));
		o.default = '默认';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'ttl', _('TTL (Seconds)'),
			_('DNS record cache time-to-live (minimum depends on DNSPod plan, default 600).'));
		o.value('60', '60s');
		o.value('120', '120s');
		o.value('300', '300s');
		o.value('600', '600s (' + _('Default') + ')');
		o.value('1800', '1800s');
		o.value('3600', '3600s');
		o.datatype = 'range(1, 604800)';
		o.default = '600';
		o.rmempty = false;

		o = s.taboption('general', form.Flag, 'clean_duplicate', _('Clean Duplicate Records'),
			_('Automatically remove extra records of the exact same host, record type, and split line.'));
		o.default = '0';
		o.modalonly = true;

		o = s.taboption('general', form.Flag, 'allow_private_ip', _('Allow Private / CGNAT IP'),
			_('Permit RFC1918, CGNAT (100.64.0.0/10), or IPv6 ULA (fd00::/8) addresses for internal/VPN DNS resolution.'));
		o.default = '0';
		o.modalonly = true;

		/* IPv4 Source Options */
		o = s.taboption('source', form.ListValue, 'ipv4_source', _('IPv4 Source'),
			_('Method used to obtain the local IPv4 address.'));
		o.value('interface', _('OpenWrt Network Interface'));
		o.value('url', _('Public HTTPS Check URL'));
		o.value('device', _('Network Device'));
		o.default = 'interface';
		o.depends('ip_mode', 'ipv4');
		o.depends('ip_mode', 'dual');
		o.modalonly = true;

		o = s.taboption('source', widgets.NetworkSelect, 'ipv4_interface', _('IPv4 Network Interface'),
			_('Logical interface providing the public IPv4 address (typically wan).'));
		o.default = 'wan';
		o.nocreate = true;
		o.multiple = false;
		o.depends({ ip_mode: 'ipv4', ipv4_source: 'interface' });
		o.depends({ ip_mode: 'dual', ipv4_source: 'interface' });
		o.modalonly = true;

		o = s.taboption('source', widgets.DeviceSelect, 'ipv4_device', _('IPv4 Network Device'),
			_('Physical or PPPoE network device (e.g. pppoe-wan, eth1).'));
		o.nocreate = true;
		o.multiple = false;
		o.depends({ ip_mode: 'ipv4', ipv4_source: 'device' });
		o.depends({ ip_mode: 'dual', ipv4_source: 'device' });
		o.modalonly = true;

		o = s.taboption('source', widgets.DeviceSelect, 'ipv4_bind_dev', _('IPv4 Outbound Device (Optional)'),
			_('Optional outbound device binding for multi-WAN public URL probing.'));
		o.nocreate = true;
		o.multiple = false;
		o.optional = true;
		o.depends({ ip_mode: 'ipv4', ipv4_source: 'url' });
		o.depends({ ip_mode: 'dual', ipv4_source: 'url' });
		o.modalonly = true;

		/* IPv6 Source Options */
		o = s.taboption('source', form.ListValue, 'ipv6_source', _('IPv6 Source'),
			_('Prefix + Host Suffix dynamically combines ISP delegated IPv6 PD prefix with a static suffix to expose LAN NAS/hosts.'));
		o.value('interface', _('OpenWrt Network Interface (GUA)'));
		o.value('prefix_suffix', _('Delegated Prefix + Static Host Suffix (LAN Host DDNS)'));
		o.value('url', _('Public HTTPS Check URL'));
		o.value('device', _('Network Device (GUA)'));
		o.default = 'interface';
		o.depends('ip_mode', 'ipv6');
		o.depends('ip_mode', 'dual');
		o.modalonly = true;

		o = s.taboption('source', widgets.NetworkSelect, 'ipv6_interface', _('IPv6 Network Interface'),
			_('Select wan6 / wan_6 or lan (automatically falls back to wan_6 / PD assignment when needed).'));
		o.default = 'wan6';
		o.nocreate = true;
		o.multiple = false;
		o.depends({ ip_mode: 'ipv6', ipv6_source: 'interface' });
		o.depends({ ip_mode: 'dual', ipv6_source: 'interface' });
		o.depends({ ip_mode: 'ipv6', ipv6_source: 'prefix_suffix' });
		o.depends({ ip_mode: 'dual', ipv6_source: 'prefix_suffix' });
		o.modalonly = true;

		o = s.taboption('source', form.Value, 'ipv6_suffix', _('IPv6 Host Suffix'),
			_('Static interface identifier combined with delegated prefix, e.g. ::1 for router or ::be24:11ff:fe12:3456 for a LAN host.'));
		o.default = '::1';
		o.placeholder = '::1';
		o.depends({ ip_mode: 'ipv6', ipv6_source: 'prefix_suffix' });
		o.depends({ ip_mode: 'dual', ipv6_source: 'prefix_suffix' });
		o.modalonly = true;

		o = s.taboption('source', widgets.DeviceSelect, 'ipv6_device', _('IPv6 Network Device'),
			_('Network device holding the global unicast IPv6 address (e.g. br-lan, pppoe-wan).'));
		o.default = 'br-lan';
		o.nocreate = true;
		o.multiple = false;
		o.depends({ ip_mode: 'ipv6', ipv6_source: 'device' });
		o.depends({ ip_mode: 'dual', ipv6_source: 'device' });
		o.modalonly = true;

		o = s.taboption('source', widgets.DeviceSelect, 'ipv6_bind_dev', _('IPv6 Outbound Device (Optional)'),
			_('Optional outbound device binding for multi-WAN IPv6 URL probing.'));
		o.nocreate = true;
		o.multiple = false;
		o.optional = true;
		o.depends({ ip_mode: 'ipv6', ipv6_source: 'url' });
		o.depends({ ip_mode: 'dual', ipv6_source: 'url' });
		o.modalonly = true;

		/* Per-Rule Credential Override */
		o = s.taboption('override', form.Flag, 'use_custom_key', _('Override Global Credentials'),
			_('Enable if this domain belongs to a separate Tencent Cloud / DNSPod account.'));
		o.default = '0';
		o.modalonly = true;

		o = s.taboption('override', form.ListValue, 'api_type', _('Authentication Mode'));
		o.value('tc3', _('Tencent Cloud API 3.0 (SecretId / SecretKey, Recommended)'));
		o.value('dnspod_token', _('DNSPod Legacy Token (ID / Token)'));
		o.default = 'tc3';
		o.depends('use_custom_key', '1');
		o.modalonly = true;

		o = s.taboption('override', form.ListValue, 'endpoint', _('API Endpoint'));
		o.value('cn', _('Mainland China (dnspod.tencentcloudapi.com)'));
		o.value('intl', _('International (dnspod.intl.tencentcloudapi.com)'));
		o.default = 'cn';
		o.depends('use_custom_key', '1');
		o.modalonly = true;

		o = s.taboption('override', form.Value, 'secret_id', _('SecretId / Token ID'));
		o.depends('use_custom_key', '1');
		o.modalonly = true;

		o = s.taboption('override', form.Value, 'secret_key', _('SecretKey / Token'));
		o.password = true;
		o.depends('use_custom_key', '1');
		o.modalonly = true;

		poll.add(L.bind(self.refreshDashboard, self), 5);

		return m.render();
	},

	handleSaveApply: function(ev, mode) {
		var self = this;
		return this.super('handleSaveApply', [ ev, mode ]).then(function() {
			window.setTimeout(function() {
				self.refreshDashboard();
			}, 1500);
		});
	}
});
