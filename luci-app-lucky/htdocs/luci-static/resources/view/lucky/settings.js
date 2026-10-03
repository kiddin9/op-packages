'use strict';
'require view';
'require rpc';
'require uci';
'require ui';
'require dom';
'require form';

var callGetInfo = rpc.declare({ object: 'luci.lucky', method: 'get_info', expect: { } });
var callSetConfig = rpc.declare({ object: 'luci.lucky', method: 'set_config', params: ['key', 'value'], expect: { } });
var callService = rpc.declare({ object: 'luci.lucky', method: 'service', params: ['action'], expect: { } });

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('lucky'),
			callGetInfo()
		]);
	},

	handleUpdate: function(key, value) {
		ui.showModal(null, [ E('p', { class: 'spinning' }, _('Updating configuration and restarting service...')) ]);
		var self = this;
		
		return callSetConfig(key, value).then(function(res) {
			if (res && res.ret === 0) {
				return callService('restart').then(function() {
					var startTime = Date.now();
					function waitForReady() {
						if (Date.now() - startTime > 10000) {
							ui.hideModal();
							ui.addNotification(null, E('p', _('Configuration updated successfully')), 'info');
							self.load().then(function(data) {
								var node = self.render(data);
								var map = document.querySelector('.cbi-map');
								if (map && map.parentNode) dom.content(map.parentNode, node);
							});
							return;
						}
						callGetInfo().then(function(info) {
							if (info && info.running) {
								ui.hideModal();
								ui.addNotification(null, E('p', _('Configuration updated successfully')), 'info');
								self.load().then(function(data) {
									var node = self.render(data);
									var map = document.querySelector('.cbi-map');
									if (map && map.parentNode) dom.content(map.parentNode, node);
								});
							} else {
								setTimeout(waitForReady, 500);
							}
						});
					}
					setTimeout(waitForReady, 500);
				});
			} else {
				ui.hideModal();
				var errMsg = (res && res.error) ? res.error : _('Update failed');
				ui.addNotification(null, E('p', errMsg), 'error');
			}
		});
	},

	render: function(results) {
		var info = results[1] || {};
		var baseConf = {
			AdminWebListenPort: String(info.adminPort || '16601'),
			SafeURL: info.adminSafeUrl || '',
			AllowInternetaccess: info.adminAllowInternet || false
		};

		var m, s, o;
		var self = this;

		m = new form.Map('lucky', _('Lucky') + ' - ' + _('Settings'),
			_('Configure basic settings for the Lucky high-performance routing service, including master enable switch and administrative ports.'));

		s = m.section(form.TypedSection, 'lucky', _('General Settings'));
		s.anonymous = true;

		// Enable service
		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		// Config Directory (UCI)
		o = s.option(form.Value, 'configdir', _('Config Directory Path'));
		o.rmempty = false;
		o.placeholder = '/etc/config/lucky.daji';

		// Admin Panel Settings
		s = m.section(form.TypedSection, 'lucky', _('Admin Panel Settings'));
		s.anonymous = true;

		// Admin Port
		o = s.option(form.Value, 'admin_port', _('Admin Web Listen Port'));
		o.datatype = 'port';
		o.load = function(section_id) { return baseConf.AdminWebListenPort || "16601"; };
		o.write = function(section_id, value) {
			var self = this;
			return callSetConfig('admin_http_port', value).then(function(res) {
				if (res && res.ret !== 0 && res.error) {
					ui.addNotification(null, E('p', res.error), 'error');
				}
				return self.super('write', [section_id, value]);
			});
		};
		o.remove = function(section_id) {
			return this.super('remove', [section_id]);
		};

		// Admin Safe URL
		o = s.option(form.Value, 'admin_safe_url', _('Admin Safe URL'));
		o.load = function(section_id) { return baseConf.SafeURL || ""; };
		o.write = function(section_id, value) {
			var self = this;
			return callSetConfig('admin_safe_url', value).then(function(res) {
				if (res && res.ret !== 0 && res.error) {
					ui.addNotification(null, E('p', res.error), 'error');
				}
				return self.super('write', [section_id, value]);
			});
		};
		o.remove = function(section_id) {
			var self = this;
			return callSetConfig('admin_safe_url', '').then(function() {
				return self.super('remove', [section_id]);
			});
		};

		// Allow Internet Access
		o = s.option(form.Flag, 'admin_internet', _('Allow Internet Access'));
		o.load = function(section_id) {
			return baseConf.AllowInternetaccess ? '1' : '0';
		};
		o.write = function(section_id, value) {
			var self = this;
			return callSetConfig('switch_Internetaccess', (value === '1')).then(function() {
				return self.super('write', [section_id, value]);
			});
		};
		o.remove = function(section_id) {
			var self = this;
			return callSetConfig('switch_Internetaccess', false).then(function() {
				return self.super('remove', [section_id]);
			});
		};

		// Reset Auth
		o = s.option(form.Button, '_reset_auth', _('Reset Account and Password'));
		o.inputtitle = _('Reset to Default (666:666)');
		o.inputstyle = 'negative';
		o.onclick = ui.createHandlerFn(self, function() {
			if (confirm(_('Are you sure you want to reset the admin account and password to default (666:666)?'))) {
				return self.handleUpdate('reset_auth_info', '');
			}
		});

		return m.render();
	}
});
