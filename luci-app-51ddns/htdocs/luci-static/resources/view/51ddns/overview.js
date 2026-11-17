'use strict';
'require view';
'require form';
'require rpc';
'require uci';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { '': {} },
});

const callLocalStatus = rpc.declare({
	object: 'luci.51ddns',
	method: 'status',
	expect: { '': {} },
});

const callAgentInfo = rpc.declare({
	object: 'luci.51ddns',
	method: 'info',
	expect: { '': {} },
});

function serviceState(data) {
	const instances = data?.['51ddns-agent']?.instances || {};
	const running = Object.values(instances).some(instance => instance?.running);

	return {
		running,
		label: running ? _('Running') : _('Not running'),
		className: running ? 'alert-message success' : 'alert-message warning',
	};
}

function formatDate(value) {
	const date = new Date(value || '');

	if (Number.isNaN(date.getTime()))
		return _('Synchronizing');

	return date.toLocaleString([], {
		year: 'numeric',
		month: '2-digit',
		day: '2-digit',
		hour: '2-digit',
		minute: '2-digit',
	});
}

function remainingState(value) {
	const expires = new Date(value || '');

	if (Number.isNaN(expires.getTime()))
		return { label: _('Synchronizing'), className: 'alert-message notice' };

	const milliseconds = expires.getTime() - Date.now();
	if (milliseconds <= 0)
		return { label: _('Expired'), className: 'alert-message error' };

	const hours = Math.ceil(milliseconds / 3600000);
	const days = Math.ceil(hours / 24);
	const label = hours > 48
		? N_(days, 'About %d day', 'About %d days').format(days)
		: N_(hours, '%d hour', '%d hours').format(hours);

	return {
		label,
		className: milliseconds <= 3 * 86400000
			? 'alert-message warning'
			: 'alert-message success',
	};
}

function quotaExceeded(local, running) {
	if (!running || local?.error_code !== 'device_quota_exceeded')
		return false;

	const updatedAt = Date.parse(local.updated_at || '');
	const routerTime = Date.parse(local.router_time || '');
	const age = (Number.isFinite(routerTime) ? routerTime : Date.now()) - updatedAt;
	return Number.isFinite(age) && age >= -30000 && age <= 120000;
}

const deviceIDPattern = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;

return view.extend({
	load() {
		return Promise.all([
			uci.load('51ddns'),
			L.resolveDefault(callServiceList('51ddns-agent'), {}),
			L.resolveDefault(callLocalStatus(), {}),
			L.resolveDefault(callAgentInfo(), {}),
		]);
	},

	render(data) {
		const state = serviceState(data[1]);
		const local = data[2] || {};
		const info = data[3] || {};
		const plan = local.plan || null;
		const quotaBlocked = quotaExceeded(local, state.running);
		const remaining = remainingState(plan?.expires_at);
		const configuredDeviceID = uci.get('51ddns', 'main', 'device_id') || '';
		const savedDeviceID = local.identity_state === 'saved' && deviceIDPattern.test(local.saved_device_id || '') ? local.saved_device_id : '';
		const map = new form.Map(
			'51ddns',
			_('51DDNS Remote Access'),
			_('Enter your account token. For a device already created in the console, enter its exact device UUID below. Leave the ID blank for automatic registration only when this router has no saved device ID and your account has a free device slot.'),
		);
		const section = map.section(form.NamedSection, 'main', 'agent', _('Quick setup'));
		section.addremove = false;

		const status = section.option(form.DummyValue, '_status', _('Service status'));
		status.rawhtml = true;
		status.cfgvalue = () =>
			`<span class="${state.className}"><strong>${state.label}</strong></span>`;

		const version = section.option(form.DummyValue, '_version', _('Agent version'));
		version.cfgvalue = () => info.version || _('Unavailable');

		if (quotaBlocked) {
			const quota = section.option(form.DummyValue, '_quota', _('Device quota'));
			quota.rawhtml = true;
			quota.cfgvalue = () =>
				`<strong style="color:#b91c1c">${_('Device limit reached. If this router already has a device record in the console, use its exact device ID to continue binding. Upgrade or purchase a plan only when adding another device.')}</strong> ` +
				`<a href="https://console.51ddns.com/console#/plans" target="_blank" rel="noopener noreferrer" style="color:#b91c1c">${_('Go to device plans')}</a>`;
		}

		const planName = section.option(form.DummyValue, '_plan_name', _('Current plan'));
		planName.cfgvalue = () => plan?.product_name || _('No active plan');

		const expiresAt = section.option(form.DummyValue, '_expires_at', _('Expires at'));
		expiresAt.cfgvalue = () => plan ? formatDate(plan.expires_at) : _('Not bound');

		const remainingTime = section.option(form.DummyValue, '_remaining_time', _('Time remaining'));
		remainingTime.rawhtml = true;
		remainingTime.cfgvalue = () => {
			if (!plan)
				return `<span class="alert-message warning"><strong>${_('Bind or purchase a plan')}</strong></span>`;

			return `<span class="${remaining.className}"><strong>${remaining.label}</strong></span>`;
		};

		const consoleButton = section.option(form.Button, '_console', _('Console'));
		consoleButton.inputtitle = _('Open 51DDNS Console');
		consoleButton.inputstyle = 'apply';
		consoleButton.onclick = () =>
			window.open('https://console.51ddns.com/console#/workbench', '_blank', 'noopener,noreferrer');

		const enabled = section.option(form.Flag, 'enabled', _('Enable'));
		enabled.rmempty = false;
		enabled.default = enabled.disabled;

		const token = section.option(form.Value, 'account_token', _('Account token'));
		token.password = true;
		token.rmempty = false;
		token.placeholder = '51d_...';
		token.description = _('Copy the token from the 51DDNS console. Updating it keeps the saved device ID. A token from another account will be rejected until the device identity is migrated.');

		const deviceID = section.option(form.Value, 'device_id', _('Existing device ID (optional)'));
		deviceID.rmempty = true;
		deviceID.description = _('Paste the exact UUID of the device created in the console. If verification failed before this router saved an identity, stop the agent to correct or clear this field. A saved router ID is never cleared here.');
		deviceID.validate = (_sectionId, value) => {
			// Stopping the service must remain possible with a stale configured ID.
			if (enabled.formvalue(_sectionId) === enabled.disabled)
				return true;
			if (value && !deviceIDPattern.test(value))
				return _('Enter a valid device UUID from the console.');
			const matchesSaved = value && savedDeviceID && value.toLowerCase() === savedDeviceID.toLowerCase();
			if (value !== configuredDeviceID && configuredDeviceID && savedDeviceID && !matchesSaved)
				return _('This router already has a configured device ID. Changing it requires a separate migration.');
			if (value && savedDeviceID && value.toLowerCase() !== savedDeviceID.toLowerCase())
				return _('This router already has a saved device ID. Changing it requires a separate migration.');
			if (value && !savedDeviceID && local.identity_state !== 'empty')
				return _('The saved device identity could not be verified. Refresh the page before setting a device ID.');
			if (value && !savedDeviceID && state.running)
				return _('Disable the agent and save first. Then enter the existing device ID and enable it again.');
			return true;
		};
		// Only an unbound, stopped router may clear a failed first-bind selection.
		deviceID.remove = () => {
			if (!savedDeviceID && local.identity_state === 'empty' && !state.running)
				uci.unset('51ddns', 'main', 'device_id');
		};

		return map.render();
	},
});
