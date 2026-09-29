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
'require uci';
'require ui';
'require view';

'require homeproxy as hp';

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
}';

const hp_dir = '/var/run/homeproxy';

/* One view-level poll for all three log views.
 *
 * getRuntimeLog() is bound to an option's render() hook, and every map.reset()
 * - any UCI write, a log level change, saving the token, updating a resource -
 * re-renders each of those options. poll.add() in there therefore added a
 * fresh handler per re-render, so every tick read each log file once per
 * leftover handler, and the stale handlers painted the detached textarea of a
 * previous render.
 *
 * This reuses hp.statusPoller() (see client.js), the same once-per-view
 * registrar that fixes the status bar leak: its flag lives inside the returned
 * registrar, so one handler is added no matter how often render() runs. It is
 * called with all three files at once because a single tick reads them
 * together.
 *
 * `log_targets` always holds the textarea installed by the *current* render,
 * so the poll paints into the live DOM without an id lookup - the three
 * textareas share the `#log_textarea` id and cannot be told apart by id. */
const log_targets = {};

function readRuntimeLog(filename) {
	return fs.read_direct(String.format('%s/%s.log', hp_dir, filename), 'text')
		.then((res) => E('pre', { 'wrap': 'pre' }, [
			res.trim() || _('Log is empty.')
		]))
		.catch((err) => {
			if (err.toString().includes('NotFoundError'))
				return E('pre', { 'wrap': 'pre' }, [ _('Log file does not exist.') ]);

			return E('pre', { 'wrap': 'pre' }, [ _('Unknown error: %s').format(err) ]);
		});
}

const ensureLogPoll = hp.statusPoller({
	poll: poll,
	read: () => Promise.all(Object.keys(log_targets).map((filename) =>
		readRuntimeLog(filename).then((node) => ({ filename: filename, node: node })))),
	paint: (entries) => {
		for (const entry of entries) {
			const target = log_targets[entry.filename];
			if (target)
				dom.content(target, entry.node);
		}
	}
});

function getConnStat(o, site) {
	o.default = E('div', { 'style': 'cbi-value-field' }, [
		E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, () => {
				return hp.rpcCall('connection_check', [site],
						{ params: ['site'], expect: { '': {} } }).then((ret) => {
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
	return hp.rpcCall('resources_get_version', [type],
			{ params: ['type'], expect: { '': {} } }).then((res) => {
		/* Review M7: the version string (the upstream commit date) and
		 * `res.updated_at` (when *this router* last succeeded) are
		 * distinct.  Show both: the upstream date stays the same across
		 * a successful re-run, so it cannot answer "did the cron job run
		 * last night" - only `updated_at` does. */
		const updated_label = res.updated_at
			? _('(last updated %s)').format(res.updated_at)
			: _('(never updated on this device)');
		let spanTemp = E('div', { 'style': 'cbi-value-field' }, [
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(this, () => {
					return hp.rpcCall('resources_update', [type],
							{ params: ['type'], expect: { '': {} } }).then((res) => {
						switch (res.status) {
						case 0:
							o.description = _('Successfully updated.');
							break;
						case 1:
							o.description = _('Update failed.');
							break;
						case 2:
							o.description = _('Already in updating.');
							break;
						case 3:
							o.description = _('Already at the latest version.');
							break;
						default:
							o.description = _('Unknown error.');
							break;
						}

						return o.map.reset();
					});
				})
			}, [ _('Check update') ]),
			' ',
			E('strong', { 'style': (res.error ? 'color:red' : 'color:green') },
				[ res.error ? 'not found' : res.version ]
			),
			' ',
			E('small', { 'style': 'color:gray' }, [ updated_label ]),
		]);

		o.default = spanTemp;
	});
}

/* `filename` is the log's basename (and log_clean's type argument), passed in
 * by the caller. It used to be reverse-engineered from the option name with
 * `o.option.split('_')[1]`, which only works while every option is spelled
 * `_<filename>_logview` - rename one and the reader, the poll and the clean
 * button silently disagree about which file they mean.
 *
 * The parameter sits after `name`, before the framework's
 * (option_index, section_id, in_table): L.bind prepends the bound arguments,
 * so the call sites pass it and the framework keeps handing in the rest. */
function getRuntimeLog(o, name, filename, _option_index, section_id, _in_table) {
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

	const log_textarea = E('div', { 'id': 'log_textarea' },
		E('img', {
			'src': L.resource('icons/loading.svg'),
			'alt': _('Loading'),
			'style': 'vertical-align:middle'
		}, _('Collecting data...'))
	);

	log_targets[filename] = log_textarea;
	ensureLogPoll();

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
						return hp.rpcCall('log_clean', [filename],
								{ params: ['type'], expect: { '': {} } });
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
				})
			}, [ _('Save') ]));

			return node;
		}

		s = m.section(form.NamedSection, 'config', 'homeproxy');
		s.anonymous = true;

		o = s.option(form.DummyValue, '_homeproxy_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('HomeProxy'), 'homeproxy');

		o = s.option(form.DummyValue, '_sing-box-c_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('sing-box client'), 'sing-box-c');

		o = s.option(form.DummyValue, '_sing-box-s_logview');
		o.render = L.bind(getRuntimeLog, this, o, _('sing-box server'), 'sing-box-s');

		return m.render();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
