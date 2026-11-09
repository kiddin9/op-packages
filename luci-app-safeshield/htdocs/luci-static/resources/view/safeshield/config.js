'use strict';

'require rpc';
'require ui';
'require view';

var callConfig = rpc.declare({
	object: 'safeshield',
	method: 'config',
	expect: { }
});

var callConfigUpdate = rpc.declare({
	object: 'safeshield',
	method: 'config_update',
	params: [ 'values' ],
	expect: { }
});

var callSetEnabled = rpc.declare({
	object: 'safeshield',
	method: 'set_enabled',
	params: [ 'enabled' ],
	expect: { }
});

var callLicenseUpdate = rpc.declare({
	object: 'safeshield',
	method: 'license_update',
	params: [ 'license_key' ],
	expect: { }
});

var CONFIG_SECTIONS = [
	{
		id: 'general',
		title: 'General',
		fields: [
			{ name: 'refresh_on_boot', kind: 'bool', title: 'Refresh on boot', description: 'Refresh the Hub artifact after boot when the existing successful refresh is no longer recent.' },
			{ name: 'refresh_interval_s', kind: 'int', min: 1, max: 2147483647, title: 'Refresh interval', suffix: 'seconds', description: 'Interval between successful Hub artifact refreshes.' },
			{ name: 'require_wan', kind: 'bool', title: 'Require WAN before refresh', description: 'Wait for WAN connectivity before resolving and downloading Hub artifacts.' }
		]
	},
	{
		id: 'rules',
		title: 'Local rules',
		fields: [
			{ name: 'apply_local_overrides', kind: 'bool', title: 'Apply local allow/block rules', description: 'Apply local rules on top of the cached Hub artifact. Rule files are managed through the SafeShield rule API.' }
		]
	},
	{
		id: 'advanced',
		title: 'Artifact and runtime safety',
		fields: [
			{ name: 'max_blocklist_file_size_kb', kind: 'int', min: 1, max: 2147483647, title: 'Maximum blocklist size', suffix: 'KB', description: 'Maximum accepted final blocklist size.' },
			{ name: 'min_valid_line_count', kind: 'int', min: 0, max: 2147483647, title: 'Minimum valid rule count', description: 'Reject an artifact when the generated dnsmasq rule count is below this value.' },
			{ name: 'compress_blocklist', kind: 'bool', title: 'Compress blocklist', description: 'Keep disabled unless the SafeShield runtime explicitly supports compressed dnsmasq blocklists.' },
			{ name: 'initial_dnsmasq_restart', kind: 'bool', title: 'Restart dnsmasq before install', description: 'Restart dnsmasq before installing a newly downloaded artifact. Normally this should stay disabled.' },
			{ name: 'dnsmasq_sanity_check', kind: 'bool', title: 'Run dnsmasq sanity check', description: 'Validate dnsmasq state after installing or applying the blocklist.' },
			{ name: 'download_timeout', kind: 'int', min: 1, max: 86400, title: 'Download timeout', suffix: 'seconds', description: 'Timeout used for Hub resolve and artifact downloads.' },
			{ name: 'download_retry', kind: 'int', min: 1, max: 100, title: 'Download retries', description: 'Maximum retry count for artifact downloads.' },
			{ name: 'pause_timeout', kind: 'int', min: 1, max: 86400, title: 'Pause timeout', suffix: 'seconds', description: 'Maximum duration used by the SafeShield pause command.' },
			{ name: 'boot_start_delay_s', kind: 'int', min: 0, max: 86400, title: 'Boot start delay', suffix: 'seconds', description: 'Delay before SafeShield performs boot-time work.' }
		]
	},
	{
		id: 'diagnostics',
		title: 'Diagnostics',
		fields: [
			{ name: 'verbosity', kind: 'select-int', title: 'Log verbosity', options: [ [ 0, 'Errors only' ], [ 1, 'Warnings' ], [ 2, 'Info' ], [ 3, 'Debug' ] ] },
			{ name: 'debug', kind: 'bool', title: 'Enable debug logging', description: 'Enable additional debug output for troubleshooting.' }
		]
	}
];

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

function boolText(value) {
	return value ? _('Enabled') : _('Disabled');
}

function valueRow(title, field, description) {
	var children = [ field ];

	if (description)
		children.push(E('div', { 'class': 'cbi-value-description' }, [ description ]));

	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title' }, [ title ]),
		E('div', { 'class': 'cbi-value-field' }, children)
	]);
}

function makeInput(spec, value) {
	var input, option;

	if (spec.kind === 'bool') {
		input = E('input', { 'type': 'checkbox' });
		input.checked = !!value;
		return input;
	}

	if (spec.kind === 'select-int') {
		input = E('select', { 'class': 'cbi-input-select' });
		spec.options.forEach(function(item) {
			option = E('option', { 'value': String(item[0]) }, [ _(item[1]) ]);
			if (Number(value) === Number(item[0]))
				option.selected = true;
			input.appendChild(option);
		});
		return input;
	}

	input = E('input', {
		'class': 'cbi-input-text',
		'type': 'number',
		'min': String(spec.min),
		'max': String(spec.max),
		'step': '1',
		'value': String(value == null ? '' : value)
	});

	return input;
}

function readInput(spec, input) {
	var value;

	if (spec.kind === 'bool')
		return !!input.checked;

	value = Number(input.value);
	if (!Number.isInteger(value))
		throw new Error(_('%s must be an integer.').format(_(spec.title)));

	if (spec.min != null && value < spec.min)
		throw new Error(_('%s must be at least %d.').format(_(spec.title), spec.min));

	if (spec.max != null && value > spec.max)
		throw new Error(_('%s must not exceed %d.').format(_(spec.title), spec.max));

	return value;
}

function renderConfigSections(config, inputs) {
	var values = (config && config.values) || {};

	return CONFIG_SECTIONS.map(function(group) {
		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _(group.title) ])
		].concat(group.fields.map(function(spec) {
			var input = makeInput(spec, values[spec.name]);
			var label = _(spec.title);

			inputs[spec.name] = { spec: spec, input: input };
			if (spec.suffix)
				label += ' (' + _(spec.suffix) + ')';

			return valueRow(label, input, spec.description ? _(spec.description) : null);
		})));
	});
}

function collectValues(inputs) {
	var values = {};

	Object.keys(inputs).forEach(function(name) {
		values[name] = readInput(inputs[name].spec, inputs[name].input);
	});

	return values;
}

function renderServiceSection(config, reload) {
	var values = (config && config.values) || {};
	var enabled = values.enabled === true;
	var state = E('strong', {}, [ boolText(enabled) ]);
	var button = E('button', {
		'class': 'btn cbi-button cbi-button-action'
	}, [ enabled ? _('Disable SafeShield') : _('Enable SafeShield') ]);

	button.addEventListener('click', function(ev) {
		ev.preventDefault();
		button.disabled = true;

		callSetEnabled(!enabled).then(function(response) {
			if (!response || response.ok !== true || response.accepted !== true)
				throw new Error(apiError(response, _('SafeShield rejected the lifecycle request.')));

			notify('info', !enabled
				? _('Enable request accepted. Runtime convergence is asynchronous; check Overview for the live state.')
				: _('Disable request accepted. Runtime convergence is asynchronous; check Overview for the live state.'));

			return reload();
		}).catch(function(err) {
			notify('danger', err.message || String(err));
		}).finally(function() {
			button.disabled = false;
		});
	});

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ _('Service state') ]),
		valueRow(_('Configured state'), state, _('SafeShield owns enable/disable lifecycle. LuCI uses safeshield.set_enabled rather than writing UCI directly.')),
		E('div', { 'class': 'cbi-value' }, [
			E('div', { 'class': 'cbi-value-title' }),
			E('div', { 'class': 'cbi-value-field' }, [ button ])
		])
	]);
}

function renderLicenseSection(config, reload) {
	var license = (config && config.license) || {};
	var input = E('input', {
		'class': 'cbi-input-text',
		'type': 'password',
		'autocomplete': 'off',
		'placeholder': license.configured ? _('Enter a new key to replace the configured key') : _('Enter license key')
	});
	var update = E('button', { 'class': 'btn cbi-button cbi-button-positive' }, [ _('Update license') ]);
	var clear = E('button', { 'class': 'btn cbi-button cbi-button-negative' }, [ _('Clear license') ]);

	update.addEventListener('click', function(ev) {
		var key = input.value.trim();
		ev.preventDefault();

		if (!key) {
			notify('warning', _('Enter a license key first. Use Clear license to remove the current key.'));
			return;
		}

		update.disabled = true;
		callLicenseUpdate(key).then(function(response) {
			if (!response || response.ok !== true)
				throw new Error(apiError(response));
			input.value = '';
			notify('info', response.changed
				? _('License key updated. SafeShield requested an artifact refresh.')
				: _('The license key is unchanged.'));
			return reload();
		}).catch(function(err) {
			notify('danger', err.message || String(err));
		}).finally(function() {
			update.disabled = false;
		});
	});

	clear.addEventListener('click', function(ev) {
		ev.preventDefault();
		if (!license.configured)
			return;
		if (!window.confirm(_('Clear the configured SafeShield license key?')))
			return;

		clear.disabled = true;
		callLicenseUpdate('').then(function(response) {
			if (!response || response.ok !== true)
				throw new Error(apiError(response));
			input.value = '';
			notify('info', _('License key cleared. SafeShield will use the unlicensed/free artifact path.'));
			return reload();
		}).catch(function(err) {
			notify('danger', err.message || String(err));
		}).finally(function() {
			clear.disabled = false;
		});
	});

	clear.disabled = !license.configured;

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ _('License') ]),
		valueRow(_('Configured'), E('span', {}, [ license.configured ? _('Yes') : _('No') ])),
		valueRow(_('Masked key'), E('code', {}, [ license.key_masked || '-' ]), _('The raw license key is never returned by the SafeShield API.')),
		valueRow(_('New license key'), input),
		E('div', { 'class': 'cbi-value' }, [
			E('div', { 'class': 'cbi-value-title' }),
			E('div', { 'class': 'cbi-value-field' }, [ update, ' ', clear ])
		])
	]);
}

function renderDeviceSection(config) {
	var device = (config && config.device) || {};

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ _('Device (read only)') ]),
		valueRow(_('Vendor'), E('span', {}, [ device.vendor || '-' ])),
		valueRow(_('Model'), E('span', {}, [ device.model || '-' ])),
		valueRow(_('Architecture'), E('span', {}, [ device.arch || '-' ])),
		valueRow(_('Memory'), E('span', {}, [ device.memory_mb ? device.memory_mb + ' MB' : '-' ]), _('Device identity and profile fields are owned by SafeShield and are not editable from LuCI.'))
	]);
}

function renderPage(config, root) {
	var inputs = {};
	var save = E('button', { 'class': 'btn cbi-button cbi-button-apply important' }, [ _('Save settings') ]);
	var reload = function() {
		return callConfig().then(function(updated) {
			root.replaceChild(renderPage(updated, root), root.firstChild);
			return updated;
		});
	};
	var nodes = [
		E('h2', {}, [ _('SafeShield settings') ]),
		E('div', { 'class': 'cbi-map-descr' }, [
			_('This page uses the public SafeShield ubus API. UCI, local rule files, service lifecycle and license storage remain owned by the safeshield package.')
		]),
		renderServiceSection(config, reload),
		renderLicenseSection(config, reload)
	];

	nodes = nodes.concat(renderConfigSections(config, inputs));
	nodes.push(renderDeviceSection(config));
	nodes.push(E('div', { 'class': 'cbi-page-actions' }, [ save ]));

	save.addEventListener('click', function(ev) {
		var values;
		ev.preventDefault();

		try {
			values = collectValues(inputs);
		}
		catch (err) {
			notify('danger', err.message || String(err));
			return;
		}

		save.disabled = true;
		callConfigUpdate(values).then(function(response) {
			if (!response || response.ok !== true)
				throw new Error(apiError(response));

			if (response.changed && response.changed.length)
				notify('info', _('SafeShield settings saved. The service was restarted and a refresh was requested where applicable.'));
			else
				notify('info', _('No SafeShield settings changed.'));

			return reload();
		}).catch(function(err) {
			notify('danger', err.message || String(err));
		}).finally(function() {
			save.disabled = false;
		});
	});

	return E('div', {}, nodes);
}

return view.extend({
	load: function() {
		return callConfig();
	},

	render: function(data) {
		var root = E('div', {}, []);
		root.appendChild(renderPage(data || {}, root));
		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
