'use strict';

'require rpc';
'require ui';
'require view';

var callStatus = rpc.declare({
	object: 'safeshield',
	method: 'status',
	expect: { }
});

var callRulesList = rpc.declare({
	object: 'safeshield',
	method: 'rules_list',
	params: [ 'action' ],
	expect: { }
});

var callRuleAdd = rpc.declare({
	object: 'safeshield',
	method: 'rule_add',
	params: [ 'action', 'domain', 'refresh' ],
	expect: { }
});

var callRuleDelete = rpc.declare({
	object: 'safeshield',
	method: 'rule_delete',
	params: [ 'action', 'domain', 'refresh' ],
	expect: { }
});

function apiError(response, fallback) {
	if (response && response.error) {
		if (response.error.message)
			return response.error.message;
		if (response.error.code)
			return response.error.code;
	}

	return fallback || _('SafeShield rule request failed.');
}

function notify(level, message) {
	ui.addNotification(null, E('p', {}, [ message ]), level || 'info');
}

function formatTimestamp(value) {
	var n = Number(value || 0);
	var date;

	if (!n)
		return '-';

	date = new Date(n * 1000);
	return isNaN(date.getTime()) ? String(value) : date.toLocaleString();
}

function delay(ms) {
	return new Promise(function(resolve) {
		window.setTimeout(resolve, ms);
	});
}

function waitForLocalApply(beforeSuccess, beforeFailure, timeoutMs) {
	var started = Date.now();

	function check() {
		return callStatus().then(function(status) {
			var timestamps = (status && status.timestamps) || {};
			var success = Number(timestamps.last_local_apply || 0);
			var failure = Number(timestamps.last_local_apply_failure || 0);

			if (success > beforeSuccess)
				return { applied: true, status: status };

			if (failure > beforeFailure)
				return { applied: false, failed: true, status: status };

			if (Date.now() - started >= timeoutMs)
				return { applied: false, pending: true, status: status };

			return delay(1000).then(check);
		});
	}

	return check();
}

function applyMessage(action, mutation, result) {
	var verb = action === 'block' ? _('block') : _('allow');
	var refresh = mutation.refresh || {};

	if (!refresh.requested) {
		if (refresh.reason === 'unchanged')
			return _('The %s rule was already in the requested state.').format(verb);
		if (refresh.reason === 'local_overrides_disabled')
			return _('The rule was saved, but local overrides are disabled so it is not active.');
		return _('The rule was saved without requesting a DNS apply.');
	}

	if (!refresh.accepted) {
		if (refresh.reason === 'disabled')
			return _('The rule was saved, but SafeShield is disabled so it is not active yet.');
		if (refresh.reason === 'service_stopped')
			return _('The rule was saved, but the SafeShield service is stopped.');
		return _('The rule was saved, but the local DNS apply request was not accepted: %s').format(refresh.reason || _('unknown reason'));
	}

	if (result && result.applied)
		return _('The %s rule was saved and applied to DNS.').format(verb);
	if (result && result.failed)
		return _('The rule was saved, but SafeShield reported a local apply failure. Check Overview and system logs.');
	return _('The rule was saved and local apply was accepted, but completion was not observed before the UI timeout. SafeShield may still be applying it.');
}

function mutationLevel(mutation, result) {
	var refresh = mutation.refresh || {};

	if (!refresh.requested && refresh.reason === 'unchanged')
		return 'info';
	if (refresh.requested && refresh.accepted && result && result.applied)
		return 'info';
	return 'warning';
}

function mutateRule(action, domain, add, status) {
	var timestamps = (status && status.timestamps) || {};
	var beforeSuccess = Number(timestamps.last_local_apply || 0);
	var beforeFailure = Number(timestamps.last_local_apply_failure || 0);
	var request = add ? callRuleAdd(action, domain, true) : callRuleDelete(action, domain, true);

	return request.then(function(response) {
		var changedField = add ? 'added' : 'deleted';
		var refresh;

		if (!response || response.ok !== true)
			throw new Error(apiError(response));

		if (!response[changedField])
			return { mutation: response, result: null };

		refresh = response.refresh || {};
		if (!refresh.requested || !refresh.accepted)
			return { mutation: response, result: null };

		return waitForLocalApply(beforeSuccess, beforeFailure, 90000).then(function(result) {
			return { mutation: response, result: result };
		});
	});
}

function renderApplyStatus(status) {
	var timestamps = (status && status.timestamps) || {};
	var local = (status && status.local_overrides) || {};

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ _('Local apply status') ]),
		E('table', { 'class': 'table' }, [
			E('tr', {}, [ E('th', {}, [ _('Local overrides enabled') ]), E('td', {}, [ local.enabled ? _('Yes') : _('No') ]) ]),
			E('tr', {}, [ E('th', {}, [ _('Last local apply') ]), E('td', {}, [ formatTimestamp(timestamps.last_local_apply) ]) ]),
			E('tr', {}, [ E('th', {}, [ _('Last local apply failure') ]), E('td', {}, [ formatTimestamp(timestamps.last_local_apply_failure) ]) ]),
			E('tr', {}, [ E('th', {}, [ _('Current stage') ]), E('td', {}, [ status.stage || '-' ]) ])
		]),
		E('div', { 'class': 'cbi-section-descr' }, [
			_('SafeShield applies rule edits using the cached Hub artifact, then atomically rebuilds the active dnsmasq blocklist and verifies DNS. A full artifact refresh is only used as a fallback when the cached Hub artifact is unavailable.')
		])
	]);
}

function renderRuleSection(action, entries, status, root, reload) {
	var isBlock = action === 'block';
	var title = isBlock ? _('Block list') : _('Allow list');
	var description = isBlock
		? _('Domains in this list are always added to the final SafeShield blocklist.')
		: _('Domains in this list are removed from the final SafeShield blocklist.');
	var input = E('input', {
		'class': 'cbi-input-text',
		'type': 'text',
		'placeholder': 'example.com',
		'autocomplete': 'off',
		'spellcheck': 'false'
	});
	var add = E('button', { 'class': 'btn cbi-button cbi-button-positive' }, [ isBlock ? _('Add block rule') : _('Add allow rule') ]);
	var rows = [];

	function runMutation(domain, adding, button) {
		button.disabled = true;
		mutateRule(action, domain, adding, status).then(function(outcome) {
			notify(mutationLevel(outcome.mutation, outcome.result), applyMessage(action, outcome.mutation, outcome.result));
			return reload();
		}).catch(function(err) {
			notify('danger', err.message || String(err));
		}).finally(function() {
			button.disabled = false;
		});
	}

	add.addEventListener('click', function(ev) {
		var domain = input.value.trim();
		ev.preventDefault();

		if (!domain) {
			notify('warning', _('Enter a domain name first.'));
			return;
		}

		runMutation(domain, true, add);
	});

	input.addEventListener('keydown', function(ev) {
		if (ev.key === 'Enter') {
			ev.preventDefault();
			add.click();
		}
	});

	(entries || []).forEach(function(domain) {
		var remove = E('button', { 'class': 'btn cbi-button cbi-button-negative' }, [ _('Delete') ]);
		remove.addEventListener('click', function(ev) {
			ev.preventDefault();
			if (!window.confirm(_('Delete %s from the %s list?').format(domain, isBlock ? _('block') : _('allow'))))
				return;
			runMutation(domain, false, remove);
		});

		rows.push(E('tr', {}, [
			E('td', {}, [ E('code', {}, [ domain ]) ]),
			E('td', { 'style': 'width: 1%; white-space: nowrap' }, [ remove ])
		]));
	});

	if (!rows.length)
		rows.push(E('tr', {}, [ E('td', { 'colspan': 2 }, [ _('No local rules in this list.') ]) ]));

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ title ]),
		E('div', { 'class': 'cbi-section-descr' }, [ description ]),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, [ _('Domain') ]),
			E('div', { 'class': 'cbi-value-field' }, [ input, ' ', add ])
		]),
		E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [ E('th', {}, [ _('Domain') ]), E('th', {}, [ _('Action') ]) ])
		].concat(rows))
	]);
}

function renderPage(data, root) {
	var rules = data[0] || {};
	var status = data[1] || {};
	var reload = function() {
		return Promise.all([ callRulesList(''), callStatus() ]).then(function(updated) {
			root.replaceChild(renderPage(updated, root), root.firstChild);
			return updated;
		});
	};

	return E('div', {}, [
		E('h2', {}, [ _('SafeShield local rules') ]),
		E('div', { 'class': 'cbi-map-descr' }, [
			_('Local allow and block rules are managed through the public SafeShield rule API. LuCI never edits /etc/safeshield files directly.')
		]),
		renderApplyStatus(status),
		renderRuleSection('allow', rules.allow || [], status, root, reload),
		renderRuleSection('block', rules.block || [], status, root, reload)
	]);
}

return view.extend({
	load: function() {
		return Promise.all([ callRulesList(''), callStatus() ]);
	},

	render: function(data) {
		var root = E('div', {}, []);
		root.appendChild(renderPage(data || [ {}, {} ], root));
		return root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
