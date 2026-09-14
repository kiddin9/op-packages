'use strict';
'require view';
'require uci';
'require form';
'require ui';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('linkback'),
			uci.load('network')
		]);
	},

	// Comprehensive validation: check all conditions required for the service
	// to be safely enabled. Returns an error message string, or null if OK.
	_validateServiceConfig: function() {
		var link_sections = uci.sections('linkback', 'link') || [];

		// Rule 1: At least 2 interfaces
		if (link_sections.length < 2) {
			return _('Cannot enable service: At least 2 monitored WAN interfaces must be configured for failover switcher.');
		}

		// Rule 2: ALL interfaces must have a health check configured
		for (var i = 0; i < link_sections.length; i++) {
			var s_id = link_sections[i]['.name'];
			var iface_name = uci.get('linkback', s_id, 'name') || s_id;
			var has_check = uci.get('linkback', s_id, 'ping_targets') ||
			                uci.get('linkback', s_id, 'dns_server') ||
			                uci.get('linkback', s_id, 'tcp_target');
			if (!has_check) {
				return _('Cannot enable service: Interface "%s" has no health check configured.').format(iface_name);
			}
		}

		// Rule 3: No duplicate priorities
		var priorities = {};
		for (var i = 0; i < link_sections.length; i++) {
			var s_id = link_sections[i]['.name'];
			var iface_name = uci.get('linkback', s_id, 'name') || s_id;
			var prio = uci.get('linkback', s_id, 'priority') || '1';
			if (priorities[prio]) {
				return _('Cannot enable service: Interfaces "%s" and "%s" have the same priority %s.').format(priorities[prio], iface_name, prio);
			}
			priorities[prio] = iface_name;
		}

		return null;
	},

	render: function() {
		var m, s, o;
		var self = this;

		// 智能判断当前是否为中文环境，并提供实时校验的翻译 fallback
		var is_zh = (_('Base Metric') === '默认跃点' || _('Base Metric') === '默认跃点 (Metric)');
		var t_priority_empty = is_zh ? '优先级不能为空。' : _('Priority must not be empty.');
		var t_priority_conflict = is_zh ? '优先级 %s 与接口 "%s" 冲突。优先级必须是唯一的。' : _('Priority %s conflicts with interface "%s". Priorities must be unique.');


		// Helper function to expand table column controls and eliminate right empty space
		var makeTableColumnExpand = function(opt, width) {
			var origRender = opt.render;
			opt.render = function(option_index, section_id, in_table) {
				return Promise.resolve(origRender.call(this, option_index, section_id, in_table)).then(function(node) {
					if (in_table && node) {
						if (width) {
							node.style.width = width;
						}
						var input = node.querySelector('input, select, .cbi-dropdown');
						if (input) {
							input.style.width = '100%';
							input.style.maxWidth = 'none';
						}
					}
					return node;
				});
			};
		};

		m = new form.Map('linkback',
			_('LinkBack 链路守护') + ' - ' + _('Settings'),
			_('Configure Multi-WAN failover service, health check parameters, and monitored link interfaces.'));

		// --- Global Settings Section ---
		s = m.section(form.TypedSection, 'global', _('Global Settings'));
		s.anonymous = true;

		// Enable switch (总开关) - must be the first option
		o = s.option(form.Flag, 'enabled', _('Enable Service'),
			_('Master switch to enable or disable the LinkBack failover daemon.'));
		o.rmempty = false;
		// Intercept at UCI write level to validate before enabling.
		o.write = function(section_id, value) {
			if (value === '1') {
				var err = self._validateServiceConfig();
				if (err) {
					ui.addNotification(null, E('p', err), 'error');
					uci.set('linkback', section_id, 'enabled', '0');
					return;
				}
			}
			uci.set('linkback', section_id, 'enabled', value);
		};

		// --- Monitored Links Section ---
		s = m.section(form.GridSection, 'link', _('Monitored WAN Interfaces'),
			_('Add and prioritize your WAN interfaces. Lower priority number means higher preference (e.g., 1 = primary, 2 = backup).'));
		s.anonymous = true;
		s.addremove = true;

		// Custom dynamic Modal title for gorgeous UX
		s.modaltitle = function(section_id) {
			var parent_title = _('LinkBack 链路守护') + ' - ' + _('Settings');
			var is_new = (this.map.addedSection === section_id) || !uci.get('linkback', section_id, 'name');
			if (is_new) {
				return parent_title + ' - ' + _('Add Monitored Interface');
			} else {
				var name = uci.get('linkback', section_id, 'name') || section_id;
				return parent_title + ' - ' + _('Edit Monitored Interface') + ' (' + name + ')';
			}
		};

		// When service is already enabled and user modifies/deletes links,
		// re-validate on the GridSection level. If the resulting config is invalid,
		// show a warning and auto-disable the service to maintain safety.
		var origRemove = s.handleRemove;
		s.handleRemove = function(section_id, ev) {
			return origRemove.apply(this, arguments).then(function() {
				var enabled = uci.get('linkback', '@global[0]', 'enabled');
				if (enabled === '1') {
					var err = self._validateServiceConfig();
					if (err) {
						ui.addNotification(null, E('p',
							_('Service has been auto-disabled because the configuration is no longer valid: ') + err
						), 'warning');
						uci.set('linkback', '@global[0]', 'enabled', '0');
					}
				}
			});
		};

		// 1. Enabled (Enabled as the first column)
		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.rmempty = false;
		makeTableColumnExpand(o, '8%');

		// 2. Interface name - dynamic dropdown (No description for main column)
		o = s.option(form.ListValue, 'name', _('Interface'));
		o.rmempty = false;

		// Once-off load of all network interfaces safely avoiding race conditions
		var network_interfaces = {};
		uci.sections('network', 'interface').forEach(function(sec) {
			var n = sec['.name'];
			if (n !== 'loopback' && n !== 'lan') {
				network_interfaces[n] = true;
				o.value(n);
			}
		});

		// Safeguard to show already configured interfaces even if they were deleted from network config
		uci.sections('linkback', 'link').forEach(function(sec) {
			if (sec.name && !network_interfaces[sec.name]) {
				o.value(sec.name, _('%s (configured)').format(sec.name));
			}
		});

		// 动态隐藏已被配置的接口：通过在 renderWidget 中进行局部变量过滤与实例化 ui.Select，
		// 完全不修改全局的 this.keylist 和 this.keyvalues，保证 100% 线程安全和无副作用
		o.renderWidget = function(section_id, option_index, cfgvalue) {
			// 找出已经被其他 Section 选中的网卡（已配置接口名）
			var used_names = {};
			uci.sections('linkback', 'link').forEach(function(sec) {
				if (sec['.name'] !== section_id && sec.name) {
					used_names[sec.name] = true;
				}
			});

			// 动态生成仅针对当前渲染 section_id 的 choices 和 keylist
			var filtered_choices = {};
			var filtered_keylist = [];
			if (Array.isArray(this.keylist)) {
				for (var i = 0; i < this.keylist.length; i++) {
					var key = this.keylist[i];
					if (!used_names[key]) {
						filtered_keylist.push(key);
						filtered_choices[key] = this.vallist[i];
					}
				}
			}

			// 判断当前是编辑已有配置还是添加新配置
			// 如果在 UCI 中已经保存了 name，则是编辑状态，此时网卡不可编辑
			var is_edit = !!uci.get('linkback', section_id, 'name');

			// 直接在局部变量中实例化 ui.Select，避免任何时序与引用问题
			var widget = new ui.Select((cfgvalue != null) ? cfgvalue : this.default, filtered_choices, {
				id: this.cbid(section_id),
				size: this.size,
				sort: filtered_keylist,
				widget: this.widget,
				optional: this.optional,
				orientation: this.orientation,
				placeholder: this.placeholder,
				validate: (typeof(this.getValidator) === 'function') ? this.getValidator(section_id) : (this.validate ? this.validate.bind(this, section_id) : null),
				disabled: is_edit ? true : ((this.readonly != null) ? this.readonly : this.map.readonly)
			});

			return widget.render();
		};

		o.validate = function(section_id, value) {
			var added = false;
			uci.sections('linkback', 'link').forEach(function(sec) {
				if (sec['.name'] !== section_id && sec.name === value) {
					added = true;
				}
			});
			if (added) {
				return _('This interface has already been configured.');
			}
			return true;
		};

		makeTableColumnExpand(o, '25%');

		// 3. Priority (No description for main column)
		o = s.option(form.Value, 'priority', _('Priority'));
		o.datatype = 'uinteger';
		o.default = '1';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (value == null || value === '') {
				return t_priority_empty;
			}
			var self_opt = this;
			var has_conflict = false;
			var conflicting_iface = '';
			uci.sections('linkback', 'link').forEach(function(sec) {
				var sid = sec['.name'];
				if (sid !== section_id) {
					var other_val = self_opt.formvalue(sid);
					if (other_val == null || other_val === '') {
						other_val = uci.get('linkback', sid, 'priority');
					}
					if (other_val != null && other_val !== '' && String(other_val) === String(value)) {
						has_conflict = true;
						conflicting_iface = uci.get('linkback', sid, 'name') || sid;
					}
				}
			});
			if (has_conflict) {
				return t_priority_conflict.format(value, conflicting_iface);
			}
			return true;
		};
		makeTableColumnExpand(o, '15%');

		// 4. Metric (Read-only, generated from priority * 10)
		var metric_title = _('Base Metric');
		if (metric_title === '默认跃点 (Metric)') {
			metric_title = '默认跃点';
		}
		o = s.option(form.DummyValue, 'metric', metric_title);
		o.cfgvalue = function(section_id) {
			var prio = uci.get('linkback', section_id, 'priority');
			var prio_val = parseInt(prio, 10);
			if (isNaN(prio_val) || prio_val <= 0) {
				prio_val = 1;
			}
			return prio_val * 10;
		};
		makeTableColumnExpand(o, '15%');

		// 5. Dummy display option for Check Type in main Grid table (read-only)
		o = s.option(form.DummyValue, 'check_type_disp', _('Check Type'));
		o.modalonly = false;
		o.cfgvalue = function(section_id) {
			if (uci.get('linkback', section_id, 'ping_targets'))
				return _('Ping Probe');
			if (uci.get('linkback', section_id, 'dns_server'))
				return _('DNS Probe');
			if (uci.get('linkback', section_id, 'tcp_target'))
				return _('TCP Probe');
			return _('-- Not Configured --');
		};
		makeTableColumnExpand(o, '20%');

		// 6. Check Type Dropdown (Virtual field, Modal only to avoid Save & Apply side-effects)
		o = s.option(form.ListValue, 'check_type', _('Check Type'));
		o.value('ping', _('Ping Probe'));
		o.value('dns', _('DNS Probe'));
		o.value('tcp', _('TCP Probe'));
		o.default = 'ping';
		o.rmempty = false;
		o.modalonly = true;

		// Derive the check type from which probe target is configured in UCI.
		o.cfgvalue = function(section_id) {
			if (uci.get('linkback', section_id, 'ping_targets'))
				return 'ping';
			if (uci.get('linkback', section_id, 'dns_server'))
				return 'dns';
			if (uci.get('linkback', section_id, 'tcp_target'))
				return 'tcp';
			return 'ping'; // Default to ping if not configured
		};

		// Only write when the check type actually CHANGES from the current state.
		o.write = function(section_id, value) {
			var current = uci.get('linkback', section_id, 'ping_targets') ? 'ping' :
			              (uci.get('linkback', section_id, 'dns_server') ? 'dns' :
			              (uci.get('linkback', section_id, 'tcp_target') ? 'tcp' : ''));
			var next = (value == null) ? 'ping' : String(value);

			// No change - do nothing
			if (next === current) {
				return;
			}

			// Clear old type's fields and any legacy weights/thresholds
			uci.remove('linkback', section_id, 'weight_threshold');
			uci.remove('linkback', section_id, 'ping_weight');
			uci.remove('linkback', section_id, 'dns_weight');
			uci.remove('linkback', section_id, 'tcp_weight');

			if (current === 'ping' || current === '') {
				uci.remove('linkback', section_id, 'ping_targets');
			}
			if (current === 'dns' || current === '') {
				uci.remove('linkback', section_id, 'dns_server');
				uci.remove('linkback', section_id, 'dns_domain');
			}
			if (current === 'tcp' || current === '') {
				uci.remove('linkback', section_id, 'tcp_target');
				uci.remove('linkback', section_id, 'tcp_port');
			}
		};

		// 7. Ping Probe Parameters
		o = s.option(form.Value, 'ping_targets', _('Ping Targets'),
			_('Comma-separated list of IPs to ping (e.g., 223.5.5.5,8.8.8.8).'));
		o.rmempty = true;
		o.modalonly = true;
		o.depends('check_type', 'ping');
		o.validate = function(section_id, value) {
			if (!value) return true;
			var ips = value.replace(/\s+/g, '').split(',');
			for (var i = 0; i < ips.length; i++) {
				var ipPattern = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
				if (!ipPattern.test(ips[i])) {
					return _('Invalid IP address: "%s"').format(ips[i]);
				}
			}
			return true;
		};
		o.write = function(section_id, value) {
			if (value != null) {
				var cleaned = String(value).replace(/\s+/g, '');
				uci.set('linkback', section_id, 'ping_targets', cleaned);
			} else {
				uci.remove('linkback', section_id, 'ping_targets');
			}
		};

		// 7. DNS Probe Parameters
		o = s.option(form.Value, 'dns_server', _('DNS Server'),
			_('DNS server IP for UDP query probe (e.g., 119.29.29.29).'));
		o.datatype = 'ip4addr';
		o.rmempty = true;
		o.modalonly = true;
		o.depends('check_type', 'dns');

		o = s.option(form.Value, 'dns_domain', _('DNS Domain'),
			_('Domain name to resolve for DNS probe (e.g., www.baidu.com).'));
		o.rmempty = true;
		o.modalonly = true;
		o.depends('check_type', 'dns');

		// 8. TCP Probe Parameters
		o = s.option(form.Value, 'tcp_target', _('TCP Target'),
			_('Target IP for TCP handshake probe.'));
		o.datatype = 'ip4addr';
		o.rmempty = true;
		o.modalonly = true;
		o.depends('check_type', 'tcp');

		o = s.option(form.Value, 'tcp_port', _('TCP Port'),
			_('Target port for TCP handshake probe.'));
		o.datatype = 'port';
		o.rmempty = true;
		o.modalonly = true;
		o.depends('check_type', 'tcp');

		// 9. Individual health check options (Modal only)
		o = s.option(form.Value, 'check_interval', _('Check Interval (s)'),
			_('Time in seconds between each health check cycle for this link.'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'check_timeout', _('Check Timeout (s)'),
			_('Maximum wait time in seconds for each individual check probe for this link.'));
		o.datatype = 'uinteger';
		o.default = '3';
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'recovery_delay', _('Recovery Delay'),
			_('Number of consecutive successful checks required before marking this link as healthy (failback anti-flap).'));
		o.datatype = 'uinteger';
		o.default = '3';
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'failover_delay', _('Failover Delay'),
			_('Number of consecutive failed checks required before marking this link as faulted (failover anti-flap).'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;
		o.modalonly = true;

		return m.render();
	}
});
