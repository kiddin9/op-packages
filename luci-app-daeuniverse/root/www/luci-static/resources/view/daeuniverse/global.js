'use strict';
'require view';
'require form';
'require ui';
'require uci';
'require daeuniverse.common as daeu';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('daeuniverse'),
			daeu.callGetCores().catch(function() { return {}; })
		]);
	},

	render: function(loadResults) {
		var coresInfo = loadResults[1] || {};
		var installed = coresInfo.installed_cores || { honk: true, dae: true };
		var versions = coresInfo.versions || {};

		var sections = uci.sections('daeuniverse', 'daeuniverse');
		var sid = (sections && sections[0]) ? sections[0]['.name'] : '@daeuniverse[0]';
		var initialCore = uci.get('daeuniverse', sid, 'core') || 'honk';
		if (initialCore !== 'dae' && initialCore !== 'honk') initialCore = 'honk';

		var globalFilePath = (initialCore === 'dae')
			? '/etc/daeuniverse/dae/config.d/global.dae'
			: '/etc/daeuniverse/honk/config.dae';

		var m, s, o;

		m = new form.Map('daeuniverse', _('Global Settings'), _('Configure global settings for DAE Universe.'));

		s = m.section(form.NamedSection, '_status');
		s.render = function() {
			return daeu.renderStatusHeader();
		};

		s = m.section(form.TypedSection, 'daeuniverse');
		s.anonymous = true;
		s.addremove = false;

		var installedVers = [];
		if (versions.honk) installedVers.push('honk ' + versions.honk);
		if (versions.dae) installedVers.push('dae ' + versions.dae);
		var enabledDesc = installedVers.length
			? _('Installed versions:') + ' ' + installedVers.join(' \u00b7 ')
			: null;

		o = s.option(form.Flag, 'enabled', _('Enabled'), enabledDesc);
		o.rmempty = false;

		var coreDesc = _('Select the proxy engine core. Each core uses its own native configuration directory under /etc/daeuniverse/.');

		o = s.option(form.ListValue, 'core', _('Core Engine'), coreDesc);
		o.value('honk', installed.honk !== false ? _('honk') : _('honk (Not installed)'));
		o.value('dae', installed.dae !== false ? _('dae') : _('dae (Not installed)'));
		o.default = 'honk';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (value === 'honk' && installed.honk === false)
				return _('honk-core is not installed on this system.');
			if (value === 'dae' && installed.dae === false)
				return _('dae is not installed on this system.');
			return true;
		};
		this._coreOption = o;

		o = s.option(form.Flag, 'advanced', _('Advanced Settings'), _('Enable to display full configuration editor and advanced routing/DNS/node tabs.'));
		o.rmempty = false;
		o.default = '0';

		o = s.option(form.ListValue, 'dashboard', _('Dashboard Type'), _('Select the active web dashboard.'));
		o.value('none', _('None'));
		o.value('doona', _('Doona'));
		o.value('doona_lite', _('Doona Lite'));
		o.value('zashboard', _('Zashboard'));
		o.default = 'doona';

		if (initialCore === 'dae') {
			o = s.option(form.DummyValue, '_entry_hint', _('Entry File'));
			o.depends('advanced', '1');
			o.rawhtml = true;
			o.cfgvalue = function() {
				return '<code>/etc/daeuniverse/dae/config.dae</code> &mdash; ' +
					_('automatically includes config.d/*.dae and api.dae.');
			};
		}

		o = s.option(form.TextValue, '_config', _('Global Configuration'),
			(initialCore === 'dae')
				? _('Editing /etc/daeuniverse/dae/config.d/global.dae (dae core).')
				: _('Editing /etc/daeuniverse/honk/config.dae (honk core). Configure include for split configs or full global block.')
		);
		o.depends('advanced', '1');
		o.rows = 25;
		o.wrap = 'off';
		o.load = function() {
			return daeu.readFile(globalFilePath);
		};
		o.write = function(section_id, formvalue) {
			if (!this.isActive(section_id) || formvalue == null) return;
			return daeu.writeFile(globalFilePath, formvalue);
		};

		this._editorDirty = false;
		this._initialCore = initialCore;
		var self = this;
		daeu.bindCodeMirrorToMap(m, function() {
			self._editorDirty = true;
		});
		return m.render();
	},

	handleSaveApply: function(ev, mode) {
		var sections = uci.sections('daeuniverse', 'daeuniverse');
		var sid = (sections && sections[0]) ? sections[0]['.name'] : '@daeuniverse[0]';
		var oldDash = uci.get('daeuniverse', sid, 'dashboard') || 'doona';
		var oldCore = uci.get('daeuniverse', sid, 'core') || 'honk';
		var initialCore = this._initialCore || oldCore;
		var editorDirty = !!this._editorDirty;
		var selectedCore = (this._coreOption && this._coreOption.formvalue(sid)) || oldCore;
		var self = this;

		// Validate target core before mutating UCI or files so failed switches leave no dirty state.
		var preCheck = (selectedCore !== oldCore)
			? daeu.callPrepareCoreSwitch(selectedCore).then(function(res) {
				if (!res || res.success === false)
					throw new Error(daeu.msgText(res, _('Failed to prepare target core')));
				if (res.warning)
					daeu.showNotification(null, E('p', daeu.msgText(res.warning)), 'warning', 6000);
			})
			: Promise.resolve();

		return preCheck.then(function() {
			return self.handleSave(ev);
		}).then(function() {
			var newDash = uci.get('daeuniverse', sid, 'dashboard') || 'doona';
			var newCore = uci.get('daeuniverse', sid, 'core') || 'honk';
			var newEnabled = uci.get('daeuniverse', sid, 'enabled') || '0';

			daeu.applyTabVisibility();

			var dashStep = (newDash !== oldDash)
				? daeu.switchDashboardAndWait(newDash, true).then(function(res) {
					if (res && res.pending)
						daeu.showNotification(null, E('p', _('Saved, but the panel files are not installed yet — download the panel first.')), 'warning');
				})
				: Promise.resolve();

			return dashStep.then(function() {
				self._editorDirty = false;

				var validateEdited = (editorDirty && newEnabled === '1')
					? daeu.callValidateConfig(initialCore).then(function(vres) {
						if (vres && vres.valid === false)
							throw new Error(daeu.msgText(vres, _('Configuration validation failed')));
						if (vres && vres.warning)
							daeu.showNotification(null, E('p', daeu.msgText(vres.warning)), 'warning', 6000);
					})
					: Promise.resolve();

				return validateEdited.then(function() {
					return uci.changes().then(function(changes) {
						var hasUciChanges = !!(changes && changes.daeuniverse && changes.daeuniverse.length);
						if (hasUciChanges) {
							// uci.changes() is async in LuCI; commit once here so procd handles restart cleanly.
							if (ui.changes && typeof ui.changes.apply === 'function')
								return ui.changes.apply(mode == '0');
							return null;
						}

						if (editorDirty && newEnabled === '1') {
							return daeu.callReload().then(function(r) {
								if (!r || r.success === false)
									throw new Error(daeu.msgText(r, _('Service did not accept the request')));
								return daeu.callStatus();
							}).then(function(st) {
								daeu.updateStatus(st);
								daeu.showNotification(null, E('p', _('Configuration applied and service reloaded.')), 'info');
							});
						}

						daeu.showNotification(null, E('p', _('Configuration saved.')), 'info');
						return null;
					});
				});
			});
		}).catch(function(err) {
			daeu.showNotification(null, E('p', _('Failed to apply configuration:') + ' ' + (err.message || err)), 'error', 6000);
		});
	}
});
