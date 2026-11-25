'use strict';
'require view';
'require dom';
'require poll';
'require rpc';
'require uci';
'require form';
'require network';
'require ui';

const callGetStatus = rpc.declare({
	object: 'luci.aliddns',
	method: 'get_status',
	expect: { '': {} }
});

const callTriggerUpdate = rpc.declare({
	object: 'luci.aliddns',
	method: 'trigger_update',
	params: [ 'force', 'record_id' ],
	expect: { '': {} }
});

const callServiceAction = rpc.declare({
	object: 'luci.aliddns',
	method: 'service_action',
	params: [ 'action' ],
	expect: { '': {} }
});

const callVerifyCredentials = rpc.declare({
	object: 'luci.aliddns',
	method: 'verify_credentials',
	params: [ 'app_key', 'app_secret' ],
	expect: { '': {} }
});

const callTestNotify = rpc.declare({
	object: 'luci.aliddns',
	method: 'test_notify',
	params: [ 'url', 'method', 'header', 'body' ],
	expect: { '': {} }
});

const LINE_OPTIONS = [
	[ 'default', _('Default Line') ],
	[ 'telecom', _('China Telecom') ],
	[ 'unicom', _('China Unicom') ],
	[ 'mobile', _('China Mobile') ],
	[ 'edu', _('CERNET (Education)') ],
	[ 'oversea', _('Overseas') ],
	[ 'btvn', _('China Broadnet') ]
];

function ensureStylesheet() {
	const href = L.resource('aliddns/aliddns.css');
	if (!document.querySelector('link[href="' + href + '"]')) {
		document.head.appendChild(E('link', {
			'rel': 'stylesheet',
			'type': 'text/css',
			'href': href
		}));
	}
}

function copyTextToClipboard(text) {
	if (!text)
		return;

	const notifyCopied = function() {
		ui.addTimeLimitedNotification(null, E('p', _('Copied to clipboard: %s').format(text)), 2000, 'info');
	};

	if (navigator.clipboard && window.isSecureContext) {
		navigator.clipboard.writeText(text).then(notifyCopied).catch(function() {});
		return;
	}

	const ta = document.createElement('textarea');
	ta.value = text;
	ta.style.position = 'fixed';
	ta.style.opacity = '0';
	document.body.appendChild(ta);
	ta.focus();
	ta.select();
	try {
		if (document.execCommand('copy'))
			notifyCopied();
	} catch (e) {}
	document.body.removeChild(ta);
}

function makeCopyChip(text) {
	if (!text)
		return E('span', { 'style': 'opacity:0.55;' }, '-');
	return E('span', {
		'class': 'aliddns-copyable',
		'title': _('Click to copy'),
		'click': function(ev) {
			ev.stopPropagation();
			copyTextToClipboard(text);
		}
	}, text);
}

function formatLineLabel(line) {
	for (let i = 0; i < LINE_OPTIONS.length; i++) {
		if (LINE_OPTIONS[i][0] === line)
			return LINE_OPTIONS[i][1];
	}
	return line || _('Default Line');
}

function renderFamilyCell(enabled, localIp, remoteIp, status, msg, modeLabel) {
	if (!enabled)
		return E('span', { 'style': 'opacity:0.55;' }, _('Disabled'));

	let badgeColor = '#6c757d';
	let badgeText = _('Pending');
	if (status === 'synced') {
		badgeColor = '#198754';
		badgeText = _('Synced');
	} else if (status === 'updated') {
		badgeColor = '#0d6efd';
		badgeText = _('Updated');
	} else if (status === 'error' || status === 'invalid') {
		badgeColor = '#dc3545';
		badgeText = _('Error');
	}

	const children = [
		E('div', {}, [
			E('span', { 'class': 'aliddns-badge', 'style': 'background:' + badgeColor }, badgeText),
			makeCopyChip(localIp)
		])
	];

	if (modeLabel) {
		children.push(E('div', { 'class': 'aliddns-subtext' }, modeLabel));
	}

	if (remoteIp && remoteIp !== localIp) {
		children.push(E('div', { 'class': 'aliddns-subtext' }, _('Cloud: %s').format(remoteIp)));
	}

	if ((status === 'error' || status === 'invalid') && msg) {
		children.push(E('div', { 'class': 'aliddns-errtext' }, msg));
	}

	return E('div', {}, children);
}

function formatIpv6ModeSummary(r) {
	if (!r.ipv6_enabled)
		return '';
	if (r.ipv6_mode === 'public')
		return _('Mode: Public API');
	if (r.ipv6_mode === 'suffix')
		return _('Mode: %s + Suffix').format(r.ipv6_source || 'wan6');
	if (r.ipv6_mode === 'mac')
		return _('Mode: LAN MAC Discovery');
	return _('Source: %s').format(r.ipv6_source || 'wan6');
}

function buildStatusDashboard(status, viewCtx) {
	const running = !!status.running;
	const syncing = !!status.syncing;
	const enabled = !!status.enabled;
	const records = Array.isArray(status.records) ? status.records : [];

	let activeCount = 0;
	let healthyCount = 0;
	let errorCount = 0;
	for (let i = 0; i < records.length; i++) {
		if (!records[i].enabled)
			continue;
		activeCount++;
		const e4 = records[i].ipv4_enabled && (records[i].ipv4_status === 'error' || records[i].ipv4_status === 'invalid');
		const e6 = records[i].ipv6_enabled && (records[i].ipv6_status === 'error' || records[i].ipv6_status === 'invalid');
		const ok4 = !records[i].ipv4_enabled || records[i].ipv4_status === 'synced' || records[i].ipv4_status === 'updated';
		const ok6 = !records[i].ipv6_enabled || records[i].ipv6_status === 'synced' || records[i].ipv6_status === 'updated';
		if (e4 || e6)
			errorCount++;
		else if (ok4 && ok6 && (records[i].ipv4_enabled || records[i].ipv6_enabled))
			healthyCount++;
	}

	let pillClass = 'aliddns-pill aliddns-pill-stopped';
	let pillText = enabled ? _('Stopped') : _('Not Enabled');
	let pulse = false;

	if (syncing) {
		pillClass = 'aliddns-pill aliddns-pill-syncing';
		pillText = _('Synchronizing...');
		pulse = true;
	} else if (running) {
		pillClass = errorCount > 0 ? 'aliddns-pill aliddns-pill-error' : 'aliddns-pill aliddns-pill-running';
		pillText = status.pid ? _('Running (PID: %d)').format(status.pid) : _('Running');
		pulse = true;
	}

	const stateBadge = E('span', { 'class': pillClass }, [
		E('span', { 'class': 'aliddns-dot' + (pulse ? ' aliddns-dot-pulse' : '') }),
		pillText
	]);

	const kpis = [
		stateBadge,
		E('span', { 'class': 'aliddns-meta-item' }, [
			E('strong', {}, _('Active Records') + ':'),
			'%d / %d (%s: %d)'.format(activeCount, records.length, _('Healthy'), healthyCount)
		]),
		E('span', { 'class': 'aliddns-meta-item' }, [
			E('strong', {}, _('Check Interval') + ':'),
			_('%d min').format(status.interval_min || 10)
		]),
		E('span', { 'class': 'aliddns-meta-item' }, [
			E('strong', {}, _('Last Check') + ':'),
			status.last_run_at || _('Never')
		])
	];

	if (running && status.next_run_at) {
		kpis.push(E('span', { 'class': 'aliddns-meta-item' }, [
			E('strong', {}, _('Next Check') + ':'),
			status.next_run_at
		]));
	}

	const btnSyncAll = E('button', {
		'type': 'button',
		'class': 'btn cbi-button cbi-button-action',
		'disabled': syncing ? 'disabled' : null,
		'click': ui.createHandlerFn(viewCtx, function() {
			return callTriggerUpdate(true, '').then(function() {
				ui.addTimeLimitedNotification(null, E('p', _('Full DDNS synchronization has been triggered.')), 2500, 'info');
				return new Promise(function(resolve) {
					window.setTimeout(resolve, 1200);
				});
			}).then(function() {
				return viewCtx.refreshStatusPanel();
			});
		})
	}, _('Sync All'));

	const btnToggle = E('button', {
		'type': 'button',
		'class': 'btn cbi-button ' + (running ? 'cbi-button-reset' : 'cbi-button-apply'),
		'click': ui.createHandlerFn(viewCtx, function() {
			const act = running ? 'stop' : 'start';
			return callServiceAction(act).then(function() {
				return new Promise(function(resolve) {
					window.setTimeout(resolve, 800);
				});
			}).then(function() {
				return viewCtx.refreshStatusPanel();
			});
		})
	}, running ? _('Stop Service') : _('Start Service'));

	const btnRestart = E('button', {
		'type': 'button',
		'class': 'btn cbi-button cbi-button-neutral',
		'click': ui.createHandlerFn(viewCtx, function() {
			return callServiceAction('restart').then(function() {
				return new Promise(function(resolve) {
					window.setTimeout(resolve, 1000);
				});
			}).then(function() {
				return viewCtx.refreshStatusPanel();
			});
		})
	}, _('Restart Service'));

	const alerts = [];
	if (status.clock_valid === false) {
		alerts.push(E('div', { 'class': 'aliddns-alert aliddns-alert-danger' },
			_('Warning: Router system time appears unsynchronized. Alibaba Cloud OpenAPI rejects requests when clock skew exceeds 15 minutes — please check NTP settings first.')));
	}
	if (enabled && status.has_credentials === false) {
		alerts.push(E('div', { 'class': 'aliddns-alert' },
			_('Tip: Global AccessKey credentials are not saved yet. Enter your AccessKey ID and Secret below, click "Test Credentials", then Save & Apply.')));
	}

	let tableNode;
	if (records.length === 0) {
		tableNode = E('div', {
			'style': 'padding:12px 0 4px 0;opacity:0.75;font-size:13px;'
		}, _('No domain records configured yet. Add a domain record below to start synchronizing.'));
	} else {
		const rows = [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Domain')),
				E('th', { 'class': 'th' }, _('Line / TTL')),
				E('th', { 'class': 'th' }, _('IPv4 (A)')),
				E('th', { 'class': 'th' }, _('IPv6 (AAAA)')),
				E('th', { 'class': 'th' }, _('Last Updated')),
				E('th', { 'class': 'th cbi-section-actions' }, _('Actions'))
			])
		];

		for (let i = 0; i < records.length; i++) {
			const r = records[i];
			const domainTitle = r.domain || _('(Unconfigured Domain)');
			const updatedTime = r.ipv6_updated_at || r.ipv4_updated_at || r.last_check_at || '-';
			const v4Label = r.ipv4_enabled
				? (r.ipv4_source === 'internet' ? _('Mode: Public API') : _('Source: %s').format(r.ipv4_source || 'wan'))
				: '';
			const v6Label = formatIpv6ModeSummary(r);

			const btnRowSync = E('button', {
				'type': 'button',
				'class': 'btn cbi-button cbi-button-action',
				'style': 'padding:2px 10px;font-size:12px;',
				'disabled': (!r.domain || syncing) ? 'disabled' : null,
				'click': ui.createHandlerFn(viewCtx, function() {
					return callTriggerUpdate(true, r.id).then(function() {
						ui.addTimeLimitedNotification(null, E('p', _('Triggered synchronization for %s.').format(domainTitle)), 2200, 'info');
						return new Promise(function(resolve) {
							window.setTimeout(resolve, 1300);
						});
					}).then(function() {
						return viewCtx.refreshStatusPanel();
					});
				})
			}, _('Sync'));

			rows.push(E('tr', { 'class': 'tr', 'style': r.enabled ? '' : 'opacity:0.55;' }, [
				E('td', { 'class': 'td' }, [
					E('div', {}, [
						r.domain ? makeCopyChip(domainTitle) : E('strong', {}, domainTitle),
						r.enabled ? '' : E('span', { 'style': 'margin-left:6px;font-size:11px;opacity:0.75;' }, '(' + _('Disabled') + ')')
					]),
					r.remark ? E('div', { 'class': 'aliddns-subtext' }, r.remark) : ''
				]),
				E('td', { 'class': 'td' }, '%s / %ds'.format(formatLineLabel(r.line), r.ttl || 600)),
				E('td', { 'class': 'td' }, renderFamilyCell(r.ipv4_enabled, r.ipv4_local, r.ipv4_remote, r.ipv4_status, r.ipv4_msg, v4Label)),
				E('td', { 'class': 'td' }, renderFamilyCell(r.ipv6_enabled, r.ipv6_local, r.ipv6_remote, r.ipv6_status, r.ipv6_msg, v6Label)),
				E('td', { 'class': 'td' }, updatedTime),
				E('td', { 'class': 'td cbi-section-actions' }, [ btnRowSync ])
			]));
		}

		tableNode = E('table', { 'class': 'table cbi-section-table', 'style': 'margin-top:12px;' }, rows);
	}

	return E('div', { 'class': 'cbi-section aliddns-dashboard' }, [
		E('h3', {}, _('Service Status & Domain Monitor')),
		E('div', { 'class': 'cbi-section-node', 'style': 'padding:12px 16px;' }, [
			E('div', { 'class': 'aliddns-topbar' }, [
				E('div', { 'class': 'aliddns-kpi-group' }, kpis),
				E('div', { 'class': 'aliddns-btn-group' }, [ btnSyncAll, btnToggle, btnRestart ])
			]),
			...alerts,
			tableNode
		])
	]);
}

function readLiveInputValue(suffix, fallback) {
	const el = document.querySelector('input[id$=".' + suffix + '"], textarea[id$=".' + suffix + '"], select[id$=".' + suffix + '"]');
	return el ? el.value : (fallback || '');
}

return view.extend({
	statusContainer: null,
	mainDomainOption: null,

	refreshStatusPanel: function() {
		const self = this;
		return callGetStatus().then(function(st) {
			if (self.statusContainer)
				dom.content(self.statusContainer, buildStatusDashboard(st || {}, self));
		}).catch(function() {});
	},

	load: function() {
		return Promise.all([
			uci.load('aliddns'),
			network.getNetworks().catch(function() { return []; }),
			callGetStatus().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		ensureStylesheet();
		const networks = data[1] || [];
		const initialStatus = data[2] || {};
		const self = this;

		if (!uci.get('aliddns', 'base')) {
			uci.add('aliddns', 'base', 'base');
			uci.set('aliddns', 'base', 'enable', '0');
			uci.set('aliddns', 'base', 'time', '10');
			uci.set('aliddns', 'base', 'ttl', '600');
			uci.set('aliddns', 'base', 'line', 'default');
			uci.set('aliddns', 'base', 'hotplug', '1');
			uci.set('aliddns', 'base', 'verify_ssl', '1');
		}

		/* Map live interface IPs from RPCD status + LuCI network API */
		const liveIfMap = {};
		const rpcIfs = Array.isArray(initialStatus.interfaces) ? initialStatus.interfaces : [];
		for (let i = 0; i < rpcIfs.length; i++) {
			liveIfMap[rpcIfs[i].name] = rpcIfs[i];
		}

		const netNames = [];
		const seenNets = {};
		const addNet = function(n) {
			if (n && n !== 'loopback' && !seenNets[n]) {
				seenNets[n] = true;
				netNames.push(n);
			}
		};

		for (let i = 0; i < rpcIfs.length; i++)
			addNet(rpcIfs[i].name);
		for (let i = 0; i < networks.length; i++)
			addNet(networks[i].getName());
		for (const fb of [ 'wan', 'wan6', 'wan_6', 'lan' ])
			addNet(fb);

		const formatNetV4Label = function(name) {
			const info = liveIfMap[name];
			if (info && info.ipv4)
				return '%s (%s)'.format(name, info.ipv4);
			return _('Interface: %s').format(name);
		};

		const formatNetV6Label = function(name) {
			const info = liveIfMap[name];
			if (info && info.ipv6)
				return '%s (%s)'.format(name, info.ipv6);
			if (info && info.ipv6_pd)
				return '%s [PD: %s]'.format(name, info.ipv6_pd);
			return _('Interface: %s').format(name);
		};

		const m = new form.Map('aliddns', _('AliDDNS'),
			_('Automatically synchronize dynamic public IPv4 and IPv6 addresses to Alibaba Cloud DNS via native OpenWrt 25.12 ucode daemon.'));

		/* 1. Global Settings */
		let s = m.section(form.NamedSection, 'base', 'base', _('Global Settings'));
		s.anonymous = true;
		s.addremove = false;

		s.tab('basic', _('Basic Settings'));
		s.tab('advanced', _('Advanced Options'));
		s.tab('notify', _('Webhook Notifications'));

		let o = s.taboption('basic', form.Flag, 'enable', _('Enable Service'),
			_('Run the event-driven AliDDNS background daemon and monitor IP changes.'));
		o.rmempty = false;
		o.default = '0';

		o = s.taboption('basic', form.Value, 'app_key', _('AccessKey ID'),
			_('Alibaba Cloud RAM AccessKey ID with AliyunDNSFullAccess permission.'));
		o.placeholder = 'LTAI5t...';
		o.rmempty = true;
		o.write = function(section_id, formvalue) {
			return form.Value.prototype.write.call(this, section_id, (formvalue || '').trim());
		};

		o = s.taboption('basic', form.Value, 'app_secret', _('AccessKey Secret'),
			_('Kept strictly in memory during HMAC-SHA1 signing and never exposed on process command lines.'));
		o.password = true;
		o.rmempty = true;
		o.write = function(section_id, formvalue) {
			return form.Value.prototype.write.call(this, section_id, (formvalue || '').trim());
		};

		o = s.taboption('basic', form.Button, '_verify_credentials', _('Account Connectivity'),
			_('Verify unsaved or saved AccessKey credentials live against Alibaba Cloud and fetch your hosted domain list.'));
		o.inputtitle = _('Test Credentials & Fetch Domains');
		o.inputstyle = 'action';
		o.onclick = ui.createHandlerFn(this, function() {
			const ak = readLiveInputValue('app_key', uci.get('aliddns', 'base', 'app_key')).trim();
			const sk = readLiveInputValue('app_secret', uci.get('aliddns', 'base', 'app_secret')).trim();
			return callVerifyCredentials(ak, sk).then(function(res) {
				if (res && res.ok) {
					const dms = Array.isArray(res.domains) ? res.domains : [];
					if (self.mainDomainOption) {
						for (let i = 0; i < dms.length; i++)
							self.mainDomainOption.value(dms[i], dms[i]);
					}
					const preview = dms.length > 0 ? dms.slice(0, 8).join(', ') + (dms.length > 8 ? '...' : '') : _('None');
					ui.addTimeLimitedNotification(null, E('div', {}, [
						E('p', {}, E('strong', {}, _('Credentials verified (%d ms).').format(res.latency_ms || 0))),
						E('p', {}, _('Hosted domains (%d): %s').format(res.total || dms.length, preview))
					]), 5500, 'info');
				} else {
					ui.addNotification(null, E('p', {},
						_('Credential verification failed: %s').format((res && res.error) ? res.error : _('Unknown error'))), 'danger');
				}
			});
		});

		o = s.taboption('basic', form.Value, 'time', _('Check Interval (Minutes)'),
			_('Periodic verification interval in minutes (1–1440). Network reconnects trigger immediate updates automatically.'));
		o.datatype = 'range(1,1440)';
		o.default = '10';
		o.rmempty = false;
		o.value('5', _('5 Minutes'));
		o.value('10', _('10 Minutes (Recommended)'));
		o.value('15', _('15 Minutes'));
		o.value('30', _('30 Minutes'));
		o.value('60', _('60 Minutes'));

		/* Advanced Tab */
		o = s.taboption('advanced', form.Value, 'ttl', _('Default TTL (Seconds)'),
			_('Alibaba Cloud Free Edition supports 600–86400 seconds; Paid Editions support down to 1 second.'));
		o.datatype = 'range(1,86400)';
		o.default = '600';
		o.value('60', _('60s (1 Minute - Paid Plan)'));
		o.value('120', _('120s (2 Minutes - Paid Plan)'));
		o.value('300', _('300s (5 Minutes - Paid Plan)'));
		o.value('600', _('600s (10 Minutes - Free Default)'));
		o.value('1800', _('1800s (30 Minutes)'));
		o.value('3600', _('3600s (1 Hour)'));
		o.value('86400', _('86400s (24 Hours)'));

		o = s.taboption('advanced', form.ListValue, 'line', _('Default Resolution Line'));
		o.default = 'default';
		for (let i = 0; i < LINE_OPTIONS.length; i++)
			o.value(LINE_OPTIONS[i][0], LINE_OPTIONS[i][1]);

		o = s.taboption('advanced', form.Flag, 'hotplug', _('Sync on Network Reconnect'),
			_('Subscribe to netifd interface events with 5-second debounce coalescing and automatic failure backoff retry.'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('advanced', form.Flag, 'clean', _('Clean Duplicate Records'),
			_('Remove extra duplicate records of the same type and line while updating the primary record in place without downtime.'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('advanced', form.Flag, 'verify_ssl', _('Verify HTTPS Certificate'),
			_('Validate TLS certificates when communicating with alidns.aliyuncs.com and HTTPS IP check endpoints.'));
		o.default = '1';
		o.rmempty = false;

		/* Webhook Notifications Tab */
		o = s.taboption('notify', form.Flag, 'notify_enabled', _('Enable Webhook Notifications'),
			_('Push a message whenever a domain IP address changes. Built-in support for Bark, ServerChan, DingTalk, Feishu, WeCom, and custom webhooks.'));
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('notify', form.Flag, 'notify_on_error', _('Notify on Sync Failure'),
			_('Also send an alert when synchronization fails (rate-limited to once every 30 minutes per domain).'));
		o.default = '0';
		o.depends('notify_enabled', '1');

		o = s.taboption('notify', form.Value, 'notify_url', _('Webhook URL'),
			_('Supports variables {title}, {message}, {domain}, {type}, {ip}, {old_ip}, {time}. DingTalk, Feishu, and WeCom robot URLs are formatted automatically.'));
		o.placeholder = 'https://api.day.app/YOUR_KEY/{title}/{message}';
		o.depends('notify_enabled', '1');

		o = s.taboption('notify', form.ListValue, 'notify_method', _('HTTP Method'));
		o.default = 'AUTO';
		o.value('AUTO', _('Auto Detect (GET for URL templates, POST JSON for IM bots)'));
		o.value('GET', 'GET');
		o.value('POST', 'POST (JSON)');
		o.depends('notify_enabled', '1');

		o = s.taboption('notify', form.Value, 'notify_header', _('Custom HTTP Header'),
			_('Optional single header, e.g. Authorization: Bearer YOUR_TOKEN'));
		o.placeholder = 'Authorization: Bearer ...';
		o.optional = true;
		o.depends('notify_enabled', '1');

		o = s.taboption('notify', form.TextValue, 'notify_body', _('Custom JSON Payload'),
			_('Optional: leave empty for built-in DingTalk / Feishu / WeCom JSON formatting, or customize with {title}, {message}, {domain}, {ip}.'));
		o.rows = 3;
		o.optional = true;
		o.depends('notify_method', 'POST');

		o = s.taboption('notify', form.Button, '_test_notify', _('Test Notification'));
		o.inputtitle = _('Send Test Message');
		o.inputstyle = 'apply';
		o.depends('notify_enabled', '1');
		o.onclick = ui.createHandlerFn(this, function() {
			const url = readLiveInputValue('notify_url', uci.get('aliddns', 'base', 'notify_url')).trim();
			const method = readLiveInputValue('notify_method', uci.get('aliddns', 'base', 'notify_method')).trim();
			const header = readLiveInputValue('notify_header', uci.get('aliddns', 'base', 'notify_header')).trim();
			const body = readLiveInputValue('notify_body', uci.get('aliddns', 'base', 'notify_body')).trim();
			return callTestNotify(url, method, header, body).then(function(res) {
				if (res && res.ok) {
					ui.addTimeLimitedNotification(null, E('p', _('Test notification delivered (HTTP %d).').format(res.http_code || 200)), 3500, 'info');
				} else {
					ui.addNotification(null, E('p', _('Webhook test failed: %s').format((res && res.error) ? res.error : _('Request failed'))), 'danger');
				}
			});
		});

		/* 2. Multi-Domain Records Grid */
		s = m.section(form.GridSection, 'record', _('Domain Records'),
			_('Manage multiple domains, wildcard records (*), apex records (@), and direct IPv6 exposure for LAN NAS/servers.'));
		s.addremove = true;
		s.anonymous = true;
		s.sortable = true;
		s.nodescriptions = true;

		s.tab('general', _('Domain & IP Sources'));
		s.tab('override', _('Optional Overrides'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.editable = true;
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'remark', _('Remark'),
			_('Optional label such as Main Router, Synology NAS, or Home Server.'));
		o.placeholder = _('Optional');
		o.optional = true;

		o = s.taboption('general', form.Value, 'sub_domain', _('Host Record (RR)'),
			_('Enter @ for apex domain, * for wildcard, or a subdomain prefix such as www or nas.'));
		o.default = '@';
		o.placeholder = '@';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			const v = (value || '').trim();
			if (v === '' || v === '@' || v === '*')
				return true;
			if (/^(\*\.)?[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)*$/.test(v))
				return true;
			return _('Invalid host record. Use @, *, or valid subdomain labels (e.g. nas or sub.dev).');
		};
		o.write = function(section_id, formvalue) {
			let v = (formvalue || '').trim();
			if (v === '')
				v = '@';
			return form.Value.prototype.write.call(this, section_id, v);
		};

		o = s.taboption('general', form.Value, 'main_domain', _('Main Domain'),
			_('The registered root domain hosted on Alibaba Cloud DNS, for example: example.com.'));
		o.datatype = 'hostname';
		o.placeholder = 'example.com';
		o.rmempty = false;
		const cachedDomains = Array.isArray(initialStatus.cached_domains) ? initialStatus.cached_domains : [];
		for (let i = 0; i < cachedDomains.length; i++)
			o.value(cachedDomains[i], cachedDomains[i]);
		o.write = function(section_id, formvalue) {
			const cleaned = (formvalue || '').trim().replace(/^https?:\/\//i, '').replace(/\.+$/, '').toLowerCase();
			return form.Value.prototype.write.call(this, section_id, cleaned);
		};
		this.mainDomainOption = o;

		o = s.taboption('general', form.Flag, 'ipv4', _('IPv4 (A)'));
		o.default = '1';
		o.editable = true;
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'interface', _('IPv4 Source'));
		o.default = 'wan';
		o.value('internet', _('Public IP API (Auto Detect)'));
		for (let i = 0; i < netNames.length; i++)
			o.value(netNames[i], formatNetV4Label(netNames[i]));

		o = s.taboption('general', form.Flag, 'ipv6', _('IPv6 (AAAA)'));
		o.default = '0';
		o.editable = true;
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'ipv6_mode', _('IPv6 Address Mode'),
			_('Expose either this router or a downstream LAN host (NAS/server) using dynamic ISP prefix delegation.'));
		o.modalonly = true;
		o.default = 'iface';
		o.value('iface', _('Router Interface Global IPv6'));
		o.value('public', _('Public IPv6 API (Auto Detect)'));
		o.value('suffix', _('Dynamic Prefix + Fixed Host Suffix (LAN Host)'));
		o.value('mac', _('Discover LAN Host Global IPv6 by MAC Address'));
		o.depends('ipv6', '1');

		o = s.taboption('general', form.ListValue, 'interface6', _('IPv6 Interface / Prefix Source'),
			_('Automatically filters Global Unicast IPv6 (2000::/3) and supports PPPoE dynamic wan_6 and prefix-delegated interfaces.'));
		o.default = 'wan6';
		o.value('internet', _('Public IPv6 API (Auto Detect)'));
		for (let i = 0; i < netNames.length; i++)
			o.value(netNames[i], formatNetV6Label(netNames[i]));

		o = s.taboption('general', form.Value, 'ipv6_suffix', _('Fixed IPv6 Host Suffix'),
			_('64-bit interface token appended to the dynamic /64 prefix, for example ::8888 or ::be24:11ff:fe12:3456.'));
		o.modalonly = true;
		o.placeholder = '::1234';
		o.depends({ 'ipv6': '1', 'ipv6_mode': 'suffix' });
		o.validate = function(section_id, value) {
			const v = (value || '').trim();
			if (!v)
				return _('Please enter a valid IPv6 host suffix such as ::1234.');
			if (!/^(:{0,2}[0-9a-fA-F]{1,4})(:[0-9a-fA-F]{1,4}){0,3}$/.test(v))
				return _('Invalid suffix format. Example: ::8888 or ::be24:11ff:fe12:3456');
			return true;
		};

		o = s.taboption('general', form.Value, 'ipv6_mac', _('Target LAN Device MAC'),
			_('Reads the neighbor table (ip -6 neigh) to locate the active Global Unicast IPv6 of the specified LAN device.'));
		o.modalonly = true;
		o.datatype = 'macaddr';
		o.placeholder = 'AA:BB:CC:DD:EE:FF';
		o.depends({ 'ipv6': '1', 'ipv6_mode': 'mac' });

		o = s.taboption('general', form.Flag, 'eui64_fallback', _('SLAAC EUI-64 Fallback'),
			_('If the LAN device is idle and absent from neighbor cache, compute its EUI-64 IPv6 from the /64 prefix and MAC.'));
		o.modalonly = true;
		o.default = '1';
		o.depends({ 'ipv6': '1', 'ipv6_mode': 'mac' });

		o = s.taboption('general', form.ListValue, 'bind_network', _('Outbound Interface for Public API'),
			_('Optional: bind curl to a specific WAN interface when using Public IP API mode to bypass transparent proxies or select a multi-WAN uplink.'));
		o.modalonly = true;
		o.default = '';
		o.value('', _('Default Routing'));
		for (let i = 0; i < netNames.length; i++)
			o.value(netNames[i], _('Interface: %s').format(netNames[i]));
		o.depends('interface', 'internet');
		o.depends('interface6', 'internet');
		o.depends('ipv6_mode', 'public');

		/* Per-Record Overrides Tab */
		o = s.taboption('override', form.ListValue, 'line', _('Resolution Line Override'),
			_('Leave as inherit unless you maintain split-horizon records for different carriers.'));
		o.modalonly = true;
		o.optional = true;
		o.value('', _('Inherit Global Setting'));
		for (let i = 0; i < LINE_OPTIONS.length; i++)
			o.value(LINE_OPTIONS[i][0], LINE_OPTIONS[i][1]);

		o = s.taboption('override', form.Value, 'ttl', _('TTL Override (Seconds)'),
			_('Leave empty to inherit the global default TTL.'));
		o.modalonly = true;
		o.optional = true;
		o.datatype = 'range(1,86400)';
		o.placeholder = _('Inherit Global Setting');

		o = s.taboption('override', form.Value, 'app_key', _('Custom AccessKey ID'),
			_('Optional: override global AccessKey ID if this domain belongs to another Alibaba Cloud account.'));
		o.modalonly = true;
		o.optional = true;
		o.placeholder = _('Inherit Global Credentials');

		o = s.taboption('override', form.Value, 'app_secret', _('Custom AccessKey Secret'),
			_('Optional: override global AccessKey Secret for this domain.'));
		o.modalonly = true;
		o.optional = true;
		o.password = true;
		o.placeholder = _('Inherit Global Credentials');

		return m.render().then(function(mapNode) {
			self.statusContainer = E('div', { 'id': 'aliddns-status-container' }, [
				buildStatusDashboard(initialStatus, self)
			]);

			poll.add(function() {
				return self.refreshStatusPanel();
			}, 5);

			return E('div', {}, [
				self.statusContainer,
				mapNode
			]);
		});
	}
});
