/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';
'require dom';
'require form';
'require fs';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

/* Thanks to luci-app-aria2 */
const css = '				\
#log_textarea {				\
	padding: 10px;			\
	text-align: left;		\
}					\
#log_textarea pre {			\
	padding: .5rem;			\
	word-break: break-all;		\
	margin: 0;			\
}					\
.description {				\
	background-color: #33ccff;	\
}';

const hp_dir = '/var/run/homeproxy';

const callResVersion = rpc.declare({
	object: 'luci.homeproxy',
	method: 'resources_get_version',
	params: ['type'],
	expect: { '': {} }
});

const callResUpdate = rpc.declare({
	object: 'luci.homeproxy',
	method: 'resources_update',
	params: ['type'],
	expect: { '': {} }
});

const callResUpdateStatus = rpc.declare({
	object: 'luci.homeproxy',
	method: 'resources_get_update_status',
	params: ['type'],
	expect: { '': {} }
});

/* LuCI's poll queue is global. Keep track of the callbacks registered by this
 * view so a re-render never leaves old ones reading detached DOM nodes. */
let logPolls = [];

function updateResultMessage(status) {
	switch (Number(status)) {
	case 0:
		return _('Successfully updated.');
	case 1:
		return _('Update failed.');
	case 2:
		return _('Already in updating.');
	case 3:
		return _('Already at the latest version.');
	default:
		return _('Unknown error.');
	}
}

function getConnStat(o, site) {
	const callConnStat = rpc.declare({
		object: 'luci.homeproxy',
		method: 'connection_check',
		params: ['site'],
		expect: { '': {} }
	});

	o.default = E('div', { 'style': 'cbi-value-field' }, [
		E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, () => {
				return L.resolveDefault(callConnStat(site), {}).then((ret) => {
                                        let ele = o.default.firstElementChild.nextElementSibling;
					if (ret.result) {
						ele.style.setProperty('color', 'green');
                                                ele.innerHTML = _('passed');
					} else {
						ele.style.setProperty('color', 'red');
                                                ele.innerHTML = _('failed');
					}
				});
			})
		}, [ _('Check') ]),
		' ',
		E('strong', { 'style': 'color:gray' }, _('unchecked')),
	]);
}

function getResVersion(o, type) {
	let button, version_el, status_el;
	let statusPollFn = null, deadline = 0;

	/* The version string itself is the source of truth. Do not rely on the
	 * RPC error flag: the backend's file error state used to be sticky across
	 * calls, which kept showing "not found" after a successful update. */
	const showVersion = (res) => {
		const version = res?.version || '';
		version_el.style.setProperty('color', version ? 'green' : 'red');
		dom.content(version_el, version || 'not found');
	};

	const refreshVersion = () => L.resolveDefault(callResVersion(type), {})
		.then(showVersion);

	const finishUpdate = (status) => {
		if (statusPollFn) {
			poll.remove(statusPollFn);
			statusPollFn = null;
		}
		button.disabled = false;
		dom.content(status_el, updateResultMessage(status));
		return refreshVersion();
	};

	const pollUpdateStatus = () => {
		let seenAttached = false;
		deadline = Date.now() + 300000;

		statusPollFn = () => {
			/* Do not mistake the initial render (node not in the DOM yet) for
			 * the user having navigated away. */
			if (document.body.contains(button))
				seenAttached = true;
			else if (seenAttached) {
				poll.remove(statusPollFn);
				statusPollFn = null;
				return;
			}

			if (Date.now() > deadline)
				return finishUpdate(1);

			return L.resolveDefault(callResUpdateStatus(type), {}).then((res) => {
				if (res.status == null || res.status === 'running')
					return;
				return finishUpdate(res.status);
			}).catch(() => finishUpdate(255));
		};

		poll.add(statusPollFn, 1);
	};

	const startUpdate = (ev) => {
		ev.preventDefault();
		if (button.disabled)
			return;

		/* Keep the button disabled until the background task reports back, so
		 * repeated clicks cannot pile up downloads and RPC requests. */
		button.disabled = true;
		dom.content(status_el, _('Updating...'));

		return L.resolveDefault(callResUpdate(type), {}).then((res) => {
			if (Number(res.status) === 254)
				return pollUpdateStatus();
			return finishUpdate(res.status);
		}).catch(() => finishUpdate(255));
	};

	return L.resolveDefault(callResVersion(type), {}).then((res) => {
		button = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': startUpdate
		}, [ _('Check update') ]);

		version_el = E('strong', {}, '');

		/* Update results are shown in place. Re-rendering the whole map would
		 * re-register every log poll callback and issue another version RPC for
		 * each resource on every click. */
		status_el = E('span', { 'style': 'margin-left: 4px' });

		o.default = E('div', { 'style': 'cbi-value-field' }, [
			button, ' ', version_el, status_el
		]);

		showVersion(res);

		/* A task started before a page reload keeps running in the background. */
		if (res.updating) {
			button.disabled = true;
			dom.content(status_el, _('Updating...'));
			pollUpdateStatus();
		}
	});
}

function getRuntimeLog(o, name, _option_index, section_id, _in_table) {
	const filename = o.option.split('_')[1];

	let section, log_level_el;
	switch (filename) {
	case 'homeproxy':
		section = null;
		break;
	case 'sing-box-c':
		section = 'config';
		break;
	case 'sing-box-s':
		section = 'server';
		break;
	}

	if (section) {
		const selected = uci.get('homeproxy', section, 'log_level') || 'warn';
		const choices = {
			trace: _('Trace'),
			debug: _('Debug'),
			info: _('Info'),
			warn: _('Warn'),
			error: _('Error'),
			fatal: _('Fatal'),
			panic: _('Panic')
		};

		log_level_el = E('select', {
			'id': o.cbid(section_id),
			'class': 'cbi-input-select',
			'style': 'margin-left: 4px; width: 6em;',
			'change': ui.createHandlerFn(this, (ev) => {
				uci.set('homeproxy', section, 'log_level', ev.target.value);
				return o.map.save(null, true).then(() => {
					ui.changes.apply(true);
				});
			})
		});

		Object.keys(choices).forEach((v) => {
			log_level_el.appendChild(E('option', {
				'value': v,
				'selected': (v === selected) ? '' : null
			}, [ choices[v] ]));
		});
	}

	const callLogClean = rpc.declare({
		object: 'luci.homeproxy',
		method: 'log_clean',
		params: ['type'],
		expect: { '': {} }
	});

	const log_textarea = E('div', { 'id': 'log_textarea' },
		E('img', {
			'src': L.resource('icons/loading.svg'),
			'alt': _('Loading'),
			'style': 'vertical-align:middle'
		}, _('Collecting data...'))
	);

	let log, seenAttached = false;
	const logPollFn = () => {
		/* Views have no unload hook, so drop this callback once its textarea
		 * has been attached and later removed from the document. */
		if (document.body.contains(log_textarea))
			seenAttached = true;
		else if (seenAttached) {
			poll.remove(logPollFn);
			return;
		}

		return fs.read_direct(String.format('%s/%s.log', hp_dir, filename), 'text')
		.then((res) => {
			log = E('pre', { 'wrap': 'pre' }, [
				res.trim() || _('Log is empty.')
			]);

			dom.content(log_textarea, log);
		}).catch((err) => {
			if (err.toString().includes('NotFoundError'))
				log = E('pre', { 'wrap': 'pre' }, [
					_('Log file does not exist.')
				]);
			else
				log = E('pre', { 'wrap': 'pre' }, [
					_('Unknown error: %s').format(err)
				]);

			dom.content(log_textarea, log);
		});
	};
	poll.add(logPollFn);
	logPolls.push(logPollFn);

	return E([
		E('style', [ css ]),
		E('div', {'class': 'cbi-map'}, [
			E('h3', {'name': 'content', 'style': 'align-items: center; display: flex;'}, [
				_('%s log').format(name),
				log_level_el || '',
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'style': 'margin-left: 4px;',
					'click': ui.createHandlerFn(this, () => {
						return L.resolveDefault(callLogClean(filename), {});
					})
				}, [ _('Clean log') ])
			]),
			E('div', {'class': 'cbi-section'}, [
				log_textarea,
				E('div', {'style': 'text-align:right'},
					E('small', {}, _('Refresh every %s seconds.').format(L.env.pollinterval))
				)
			])
		])
	]);
}

return view.extend({
	render() {
		let m, s, o;

		logPolls.forEach((fn) => poll.remove(fn));
		logPolls = [];

		m = new form.Map('homeproxy');

		s = m.section(form.NamedSection, 'config', 'homeproxy', _('Connection check'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_check_baidu', _('BaiDu'));
		o.cfgvalue = L.bind(getConnStat, this, o, 'baidu');

		o = s.option(form.DummyValue, '_check_google', _('Google'));
		o.cfgvalue = L.bind(getConnStat, this, o, 'google');

		s = m.section(form.NamedSection, 'config', 'homeproxy', _('Resources management'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_china_ip4_version', _('China IPv4 list version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_ip4');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_china_ip6_version', _('China IPv6 list version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_ip6');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_china_list_version', _('China list version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'china_list');
		o.rawhtml = true;

		o = s.option(form.DummyValue, '_gfw_list_version', _('GFW list version'));
		o.cfgvalue = L.bind(getResVersion, this, o, 'gfw_list');
		o.rawhtml = true;

		o = s.option(form.Value, 'github_token', _('GitHub token'));
		o.password = true;
		o.renderWidget = function() {
			let node = form.Value.prototype.renderWidget.apply(this, arguments);

			(node.querySelector('.control-group') || node).appendChild(E('button', {
				'class': 'cbi-button cbi-button-apply',
				'title': _('Save'),
				'click': ui.createHandlerFn(this, () => {
					return this.map.save(null, true).then(() => {
						ui.changes.apply(true);
					});
				}, this.option)
			}, [ _('Save') ]));

			return node;
		}

		s = m.section(form.NamedSection, 'config', 'homeproxy');
		s.anonymous = true;

		o = s.option(form.DummyValue, '_homeproxy_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('HomeProxy'));

		o = s.option(form.DummyValue, '_sing-box-c_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('sing-box client'));

		o = s.option(form.DummyValue, '_sing-box-s_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('sing-box server'));

		return m.render();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
