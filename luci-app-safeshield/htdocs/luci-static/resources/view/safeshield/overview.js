'use strict';

'require poll';
'require rpc';
'require ui';
'require view';

var callStatus = rpc.declare({
	object: 'safeshield',
	method: 'status',
	expect: { }
});

var callSetEnabled = rpc.declare({
	object: 'safeshield',
	method: 'set_enabled',
	params: [ 'enabled' ],
	expect: { }
});

var callRefresh = rpc.declare({
	object: 'safeshield',
	method: 'refresh',
	expect: { }
});

const SUMMARY_MESSAGES = {
	idle: _('SafeShield is idle.'),
	ready: _('SafeShield is ready.'),
	refreshing: _('SafeShield is refreshing the blocklist.'),
	degraded: _('SafeShield is running with degraded protection.'),
	error: _('SafeShield encountered an error.'),
	paused: _('SafeShield is paused.'),
	disabled: _('SafeShield is disabled.')
};


function apiError(response, fallback) {
	if (response && response.error) {
		if (response.error.message)
			return response.error.message;
		if (response.error.code)
			return response.error.code;
	}

	return fallback || _('SafeShield request failed.');
}

function notify(level, message) {
	ui.addNotification(null, E('p', {}, [ message ]), level || 'info');
}

function delay(ms) {
	return new Promise(function(resolve) {
		window.setTimeout(resolve, ms);
	});
}

function enabledStateConverged(status, target) {
	var runtime = (status && status.runtime) || {};

	if (target)
		return status && status.enabled === true && status.active === true && runtime.refreshd_running === true;

	return status && status.enabled === false && status.active === false && runtime.refreshd_running === false;
}

function waitForEnabledState(target, timeoutMs) {
	var started = Date.now();

	function check() {
		return callStatus().then(function(status) {
			if (enabledStateConverged(status, target) || Date.now() - started >= timeoutMs)
				return status;
			return delay(500).then(check);
		});
	}

	return check();
}

function renderActions(status, root) {
	var enabled = status && status.enabled === true;
	var toggle = E('button', { 'class': 'btn cbi-button cbi-button-action' }, [ enabled ? _('Disable SafeShield') : _('Enable SafeShield') ]);
	var refresh = E('button', { 'class': 'btn cbi-button cbi-button-positive' }, [ _('Refresh now') ]);

	function replaceStatus(updated) {
		root.replaceChild(renderStatus(updated, root), root.firstChild);
	}

	toggle.addEventListener('click', function(ev) {
		var target = !enabled;
		ev.preventDefault();
		toggle.disabled = true;

		callSetEnabled(target).then(function(response) {
			if (!response || response.ok !== true || response.accepted !== true)
				throw new Error(apiError(response, _('SafeShield rejected the lifecycle request.')));

			notify('info', target ? _('Enable request accepted.') : _('Disable request accepted.'));
			return waitForEnabledState(target, 15000);
		}).then(function(updated) {
			replaceStatus(updated);
			if (enabledStateConverged(updated, target))
				notify('info', target ? _('SafeShield is enabled and running.') : _('SafeShield is disabled and stopped.'));
			else
				notify('warning', _('SafeShield accepted the request but runtime convergence was not observed within 15 seconds. Status polling will continue.'));
		}).catch(function(err) {
			notify('danger', err.message || String(err));
		}).finally(function() {
			toggle.disabled = false;
		});
	});

	refresh.disabled = !enabled;
	refresh.addEventListener('click', function(ev) {
		ev.preventDefault();
		refresh.disabled = true;

		callRefresh().then(function(response) {
			if (!response || response.ok !== true)
				throw new Error(apiError(response, _('SafeShield refresh request failed.')));

			if (response.accepted)
				notify('info', _('SafeShield refresh started.'));
			else if (response.reason === 'already_running')
				notify('info', _('A SafeShield refresh is already running.'));
			else
				notify('warning', _('Refresh was not started: %s').format(response.reason || _('unknown reason')));

			return callStatus();
		}).then(replaceStatus).catch(function(err) {
			notify('danger', err.message || String(err));
		}).finally(function() {
			refresh.disabled = !enabled;
		});
	});

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ _('Actions') ]),
		E('div', { 'class': 'cbi-section-descr' }, [
			_('Enable/disable and refresh actions use the public SafeShield ubus API. Enable/disable convergence is asynchronous and is verified through safeshield.status.')
		]),
		E('div', {}, [ toggle, ' ', refresh ])
	]);
}

function asText(value, fallback) {
	if (value === null || value === undefined || value === '')
		return fallback || '-';

	if (typeof value === 'boolean')
		return value ? _('Yes') : _('No');

	return String(value);
}

function formatBool(value) {
	if (value === true || value === 1 || value === '1')
		return _('Yes');
	if (value === false || value === 0 || value === '0')
		return _('No');
	return '-';
}

function formatNumber(value) {
	if (value === null || value === undefined || value === '')
		return '-';
	return String(value);
}

function formatSizeKb(value) {
	if (value === null || value === undefined || value === '')
		return '-';
	return String(value) + ' KB';
}

function formatHash(value) {
	if (!value)
		return '-';

	var text = String(value);
	return text.length > 24 ? text.substring(0, 16) + '…' + text.substring(text.length - 8) : text;
}

function formatTimestamp(value) {
	var n, date;

	if (!value)
		return '-';

	if (typeof value === 'number') {
		n = value;
	}
	else if (typeof value === 'string' && /^\d+$/.test(value)) {
		n = Number(value);
	}
	else {
		date = new Date(value);
		return isNaN(date.getTime()) ? String(value) : date.toLocaleString();
	}

	if (!n)
		return '-';

	/* SafeShield RPC returns Unix timestamps in seconds. JavaScript Date expects milliseconds. */
	if (n < 100000000000)
		n = n * 1000;

	date = new Date(n);
	return isNaN(date.getTime()) ? String(value) : date.toLocaleString();
}

function formatDuration(value) {
	var n, days, hours, minutes, seconds, parts = [];

	if (value === null || value === undefined || value === '')
		return '-';

	n = Number(value);
	if (isNaN(n) || n < 0)
		return String(value);

	seconds = Math.floor(n);
	days = Math.floor(seconds / 86400);
	seconds = seconds % 86400;
	hours = Math.floor(seconds / 3600);
	seconds = seconds % 3600;
	minutes = Math.floor(seconds / 60);
	seconds = seconds % 60;

	if (days)
		parts.push(days + 'd');
	if (hours)
		parts.push(hours + 'h');
	if (minutes)
		parts.push(minutes + 'm');
	if (seconds || !parts.length)
		parts.push(seconds + 's');

	return parts.join(' ');
}

function translateValue(value) {
	switch (String(value || '').toLowerCase()) {
	case 'idle': return _('Idle');
	case 'scheduled_wait': return _('Waiting for scheduled refresh');
	case 'boot_delay': return _('Waiting after boot');
	case 'local_apply': return _('Applying local rules');
	case 'local_merge': return _('Merging local rules');
	case 'local_restart_dnsmasq': return _('Restarting DNS service');
	case 'local_runtime_check': return _('Checking DNS service');
	case 'local_blocklist_verify': return _('Verifying blocklist');
	case 'ok': return _('OK');
	case 'ready': return _('Ready');
	case 'success': return _('Success');
	case 'active': return _('Active');
	case 'running': return _('Running');
	case 'refreshing': return _('Refreshing');
	case 'pending': return _('Pending');
	case 'notice': return _('Notice');
	case 'warning': return _('Warning');
	case 'degraded': return _('Degraded');
	case 'disabled': return _('Disabled');
	case 'error': return _('Error');
	case 'failed': return _('Failed');
	case 'failure': return _('Failure');
	case 'expired': return _('Expired');
	case 'revoked': return _('Revoked');
	case 'suspended': return _('Suspended');
	case 'free': return _('Free');
	case 'unlicensed': return _('Unlicensed');
	case 'licensed': return _('Licensed');
	case 'light': return _('Light');
	case 'standard': return _('Standard');
	case 'full': return _('Full');
	case 'block': return _('Block');
	case 'allow': return _('Allow');
	default: return value;
	}
}

function badgeClass(value) {
	switch (String(value || '').toLowerCase()) {
	case 'ok':
	case 'ready':
	case 'success':
	case 'active':
		return 'label success';
	case 'running':
	case 'refreshing':
	case 'pending':
	case 'notice':
	case 'boot_delay':
	case 'scheduled_wait':
	case 'local_apply':
	case 'local_merge':
	case 'local_restart_dnsmasq':
	case 'local_runtime_check':
	case 'local_blocklist_verify':
		return 'label notice';
	case 'warning':
	case 'warn':
	case 'degraded':
	case 'disabled':
		return 'label warning';
	case 'error':
	case 'failed':
	case 'failure':
	case 'expired':
	case 'revoked':
	case 'suspended':
		return 'label danger';
	default:
		return 'label';
	}
}

function badge(value, fallback) {
	var text = asText(value, fallback || '-');
	return E('span', { 'class': badgeClass(text), 'style': 'padding: 0' }, [ translateValue(text) ]);
}

function row(label, value) {
	var children;

	if (Array.isArray(value))
		children = value;
	else if (value && typeof value === 'object')
		children = [ value ];
	else
		children = [ asText(value) ];

	return E('tr', {}, [
		E('th', { 'style': 'width: 32%' }, [ label ]),
		E('td', {}, children)
	]);
}

function table(rows) {
	return E('table', { 'class': 'table' }, rows);
}

function section(title, rows) {
	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ title ]),
		table(rows)
	]);
}

function renderMessage(message) {
	if (typeof message === 'string')
		return message;

	if (message && typeof message === 'object') {
		if (message.message)
			return message.message;
		if (message.code)
			return message.code;
		return JSON.stringify(message);
	}

	return asText(message);
}

function renderMessages(title, items, className) {
	if (!items || !items.length)
		return null;

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ title ]),
		E('ul', { 'class': className || '' }, items.map(function(item) {
			return E('li', {}, [ renderMessage(item) ]);
		}))
	]);
}

function summaryMessage(summary) {
	var code = String((summary && summary.code) || '').toLowerCase();

	return SUMMARY_MESSAGES[code] || asText(summary && summary.message, '-');
}

function renderSummary(summary) {
	if (!summary)
		return '-';

	if (typeof summary === 'string')
		return translateValue(summary);

	return [
		E('span', { 'class': badgeClass(summary.severity || summary.label), 'style': 'padding: 0' }, [ translateValue(asText(summary.label, '-')) ]),
		' ',
		summaryMessage(summary)
	];
}

function renderSources(sources) {
	var items = (sources && sources.items) || [];
	var body;

	if (!items.length) {
		body = [ E('tr', {}, [ E('td', { 'colspan': 8 }, [ _('No sources reported by SafeShield.') ]) ]) ];
	}
	else {
		var cstyle = { 'style': 'text-align:center' };
		body = items.map(function(item) {
			return E('tr', {}, [
				E('td', cstyle, [ asText(item.name || item.id) ]),
				E('td', cstyle, [ translateValue(asText(item.action || sources.mode)) ]),
				E('td', cstyle, [ formatBool(item.enabled) ]),
				E('td', cstyle, [ badge(item.last_result) ]),
				E('td', cstyle, [ formatNumber(item.line_count) ]),
				E('td', cstyle, [ formatSizeKb(item.size_kb) ]),
				E('td', cstyle, [ translateValue(asText(item.artifact_tier)) ]),
				E('td', cstyle, [ asText(item.artifact_version) ])
			]);
		});
	}

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ _('Sources') ]),
		E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', {}, [ _('Name') ]),
				E('th', {}, [ _('Mode / action') ]),
				E('th', {}, [ _('Enabled') ]),
				E('th', {}, [ _('Last result') ]),
				E('th', {}, [ _('Domains / lines') ]),
				E('th', {}, [ _('Size') ]),
				E('th', {}, [ _('Tier') ]),
				E('th', {}, [ _('Version') ])
			])
		].concat(body))
	]);
}

function renderHealth(checks) {
	var names = [
		[ 'api_resolve', _('Artifact metadata resolve') ],
		[ 'artifact_download', _('Artifact download') ],
		[ 'artifact_sha256', _('Artifact SHA-256') ],
		[ 'dnsmasq_binary', _('dnsmasq binary') ],
		[ 'dnsmasq_confdir', _('dnsmasq confdir') ],
		[ 'dnsmasq_initial_restart', _('Initial dnsmasq restart') ],
		[ 'dnsmasq_final_restart', _('Final dnsmasq restart') ],
		[ 'dns_runtime', _('DNS runtime') ],
		[ 'blocklist_verify', _('Blocklist verify') ],
		[ 'min_valid_line_count', _('Minimum valid rule count') ],
		[ 'max_file_size', _('Maximum file size') ]
	];

	return section(_('Health checks'), names.map(function(item) {
		var value = checks ? checks[item[0]] : null;
		return row(item[1], badge(value));
	}));
}

function renderStatus(data, root) {
	var status = data || {};
	var runtime = status.runtime || {};
	var license = status.license || {};
	var device = status.device || {};
	var deviceConfigured = device.configured || {};
	var artifact = status.artifact || {};
	var localOverrides = status.local_overrides || {};
	var blocklist = status.blocklist || {};
	var sources = status.sources || {};
	var health = status.health || {};
	var timestamps = status.timestamps || {};
	var schema = status.schema || {};

	var warnings = renderMessages(_('Warnings'), status.warnings, '');
	var errors = renderMessages(_('Errors'), status.errors, '');

	var nodes = [
		E('h2', {}, [ _('SafeShield') ]),
		renderActions(status, root),

		section(_('Current status'), [
			row(_('Status'), badge(status.status)),
			row(_('Stage'), badge(status.stage)),
			row(_('Summary'), renderSummary(status.summary)),
			row(_('Version'), status.version),
			row(_('Schema'), schema.name ? schema.name + ' v' + asText(schema.version) : '-'),
			row(_('Enabled'), formatBool(status.enabled)),
			row(_('Active'), formatBool(status.active)),
			row(_('Health'), badge(health.overall)),
			row(_('Generated at'), formatTimestamp(timestamps.generated_at)),
			row(_('Last attempt'), formatTimestamp(timestamps.last_attempt)),
			row(_('Last success'), formatTimestamp(timestamps.last_success)),
			row(_('Last failure'), formatTimestamp(timestamps.last_failure)),
			row(_('Last local apply'), formatTimestamp(timestamps.last_local_apply)),
			row(_('Last local apply failure'), formatTimestamp(timestamps.last_local_apply_failure))
		]),

		section(_('Runtime'), [
			row(_('Refresh daemon running'), formatBool(runtime.refreshd_running)),
			row(_('dnsmasq running'), formatBool(runtime.dnsmasq_running)),
			row(_('DNS runtime OK'), formatBool(runtime.dns_runtime_ok)),
			row(_('Config loaded'), formatBool(runtime.config_loaded)),
			row(_('Require WAN'), formatBool(runtime.require_wan)),
			row(_('Refresh on boot'), formatBool(runtime.refresh_on_boot)),
			row(_('Last result'), badge(runtime.last_result)),
			row(_('Last error code'), runtime.last_error_code)
		]),


		section(_('License'), [
			row(_('Configured'), formatBool(license.configured)),
			row(_('Masked key'), license.key_masked),
			row(_('Plan'), translateValue(asText(license.plan))),
			row(_('Status'), badge(license.status))
		]),

		section(_('Device'), [
			row(_('Physical fingerprint'), device.physical_fingerprint),
			row(_('Runtime profile'), device.profile),
			row(_('Configured physical fingerprint'), deviceConfigured.physical_fingerprint),
			row(_('Vendor'), deviceConfigured.vendor),
			row(_('Model'), deviceConfigured.model),
			row(_('Architecture'), deviceConfigured.arch),
			row(_('Memory'), deviceConfigured.memory_mb ? deviceConfigured.memory_mb + ' MB' : '-')
		]),

		section(_('Hub artifact'), [
			row(_('Resolved'), formatBool(artifact.resolved)),
			row(_('Tier'), translateValue(asText(artifact.tier))),
			row(_('Version'), artifact.version),
			row(_('SHA-256'), formatHash(artifact.sha256)),
			row(_('Unique domains'), formatNumber(artifact.unique_domains)),
			row(_('Rules'), formatNumber(artifact.rules)),
			row(_('Download URL present'), formatBool(artifact.download_url_present))
		]),

		section(_('Local overrides'), [
			row(_('Enabled'), formatBool(localOverrides.enabled)),
			row(_('Allowlist path'), localOverrides.allowlist_path),
			row(_('Blocklist path'), localOverrides.blocklist_path)
		]),

		section(_('Blocklist'), [
			row(_('Installed'), formatBool(blocklist.installed)),
			row(_('Path'), blocklist.path),
			row(_('Valid rules'), formatNumber(blocklist.valid_line_count)),
			row(_('File size'), formatSizeKb(blocklist.file_size_kb)),
			row(_('Compressed'), formatBool(blocklist.compressed)),
			row(_('Verification OK'), formatBool(blocklist.verification_ok)),
			row(_('Test domain'), blocklist.test_domain),
			row(_('Test domain success'), formatNumber(blocklist.test_domain_success_count) + ' / ' + formatNumber(blocklist.test_domain_sample_count)),
			row(_('Previous backup available'), formatBool(blocklist.previous_backup_available))
		]),

		section(_('Schedule'), [
			row(_('Refresh interval'), formatDuration(timestamps.refresh_interval_s)),
			row(_('Next refresh'), formatTimestamp(timestamps.next_refresh_at)),
			row(_('Next refresh in'), formatDuration(timestamps.next_refresh_in_s)),
			row(_('Boot start delay'), formatDuration(timestamps.boot_start_delay_s))
		]),

		renderHealth(health.checks),
		renderSources(sources)
	];

	if (warnings)
		nodes.push(warnings);
	if (errors)
		nodes.push(errors);

	return E('div', {}, nodes);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	render: function(data) {
		var root = E('div', {}, []);

		root.appendChild(renderStatus(data, root));

		poll.add(function() {
			return callStatus().then(function(updated) {
				root.replaceChild(renderStatus(updated, root), root.firstChild);
			});
		}, 5);

		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
