'use strict';
'require view';
'require uci';
'require form';
'require ui';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('linkback'),
			uci.load('network'),
			uci.load('firewall').catch(function() { return {}; })
		]);
	},

	// Comprehensive validation: check all conditions required for the service
	// to be safely enabled. Returns an error message string, or null if OK.
	_validateServiceConfig: function() {
		var global_sec = uci.sections('linkback', 'global')[0] || {};
		var mode = global_sec.mode || 'multi_wan';
		var link_sections = uci.sections('linkback', 'link') || [];

		// Rule 1: At least 2 targets
		if (link_sections.length < 2) {
			return _('Cannot enable service: At least 2 monitored links/gateways must be configured for failover switcher.');
		}

		if (mode === 'multi_gw') {
			var iface = global_sec.interface || 'wan';
			if (!iface) {
				return _('Cannot enable service: WAN interface must be configured in Multi-Gateway mode.');
			}
		}

		// Rule 2: ALL targets must have a health check configured
		var priorities = {};
		var gateways = {};
		var names = {};

		for (var i = 0; i < link_sections.length; i++) {
			var s_id = link_sections[i]['.name'];
			var target_name = uci.get('linkback', s_id, 'name') || s_id;
			var gw = uci.get('linkback', s_id, 'gateway');
			var prio = uci.get('linkback', s_id, 'priority') || '1';

			var has_check = uci.get('linkback', s_id, 'ping_targets') ||
			                uci.get('linkback', s_id, 'dns_server') ||
			                uci.get('linkback', s_id, 'tcp_target');
			if (!has_check) {
				return _('Cannot enable service: Target "%s" has no health check configured.').format(target_name);
			}

			// Priority uniqueness
			if (priorities[prio]) {
				return _('Cannot enable service: Targets "%s" and "%s" have the same priority %s.').format(priorities[prio], target_name, prio);
			}
			priorities[prio] = target_name;

			// Mode specific checks
			if (mode === 'multi_gw') {
				var ipPattern = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
				if (!gw || !ipPattern.test(gw)) {
					return _('Cannot enable service: Target "%s" has an invalid or missing Gateway IP.').format(target_name);
				}
				if (gateways[gw]) {
					return _('Cannot enable service: Targets "%s" and "%s" have the same Gateway IP %s.').format(gateways[gw], target_name, gw);
				}
				gateways[gw] = target_name;
			} else {
				if (names[target_name]) {
					return _('Cannot enable service: Interface "%s" is configured multiple times.').format(target_name);
				}
				names[target_name] = true;
			}
		}

		return null;
	},

	render: function() {
		var m, s, o;
		var self = this;

		var getActiveMode = function() {
			var global_sec = uci.sections('linkback', 'global')[0] || {};
			var sid = global_sec['.name'] || '@global[0]';
			var sel = document.querySelector('[name="cbid.linkback.' + sid + '.mode"]') ||
			          document.querySelector('select[id*="mode"], select[name*="mode"]');
			if (sel && sel.value) {
				return sel.value;
			}
			return uci.get('linkback', sid, 'mode') || 'multi_wan';
		};

		var current_mode = getActiveMode();

		// 智能提取 firewall 中 wan 区域关联的所有网络接口
		var wan_interfaces = {};
		var has_wan_zone = false;
		uci.sections('firewall', 'zone').forEach(function(sec) {
			if (sec.name === 'wan') {
				has_wan_zone = true;
				var nets = sec.network;
				if (Array.isArray(nets)) {
					nets.forEach(function(n) { if (n) wan_interfaces[n] = true; });
				} else if (typeof(nets) === 'string') {
					nets.split(/\s+/).forEach(function(n) { if (n) wan_interfaces[n] = true; });
				}
			}
		});

		// 若未配置 wan 区域，则安全回退至系统非回环非 lan 接口
		if (!has_wan_zone || Object.keys(wan_interfaces).length === 0) {
			uci.sections('network', 'interface').forEach(function(sec) {
				var n = sec['.name'];
				if (n !== 'loopback' && n !== 'lan') {
					wan_interfaces[n] = true;
				}
			});
		}

		// 智能判断当前是否为中文环境，并提供实时校验的翻译 fallback
		var is_zh = (_('Base Metric') === '默认跃点' || _('Base Metric') === '默认跃点 (Metric)');
		var t_priority_empty = is_zh ? '优先级不能为空。' : _('Priority must not be empty.');
		var t_priority_conflict = is_zh ? '优先级 %s 与其他目标冲突。优先级必须是唯一的。' : _('Priority %s conflicts with another target. Priorities must be unique.');

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
			_('Configure Multi-WAN / Multi-Gateway failover service, shared health check parameters, and monitored targets.'));

		// --- Global Settings Section ---
		s = m.section(form.TypedSection, 'global', _('Global Settings'));
		s.anonymous = true;

		// 1. Enable switch
		o = s.option(form.Flag, 'enabled', _('Enable Service'),
			_('Master switch to enable or disable the LinkBack failover daemon.'));
		o.rmempty = false;
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

		// 2. Working Mode
		o = s.option(form.ListValue, 'mode', _('Working Mode'),
			_('Choose failover mode: Multi-WAN interface failover or Single-WAN multi-gateway redundancy.'));
		o.value('multi_wan', _('多wan口模式'));
		o.value('multi_gw', _('单wan多网关模式'));
		o.default = 'multi_wan';
		o.rmempty = false;
		o.onchange = function(ev, section_id, value) {
			uci.set('linkback', section_id, 'mode', value);
			var links = uci.sections('linkback', 'link') || [];
			if (links.length > 0) {
				if (value === 'multi_gw') {
					ui.addNotification(null, E('p',
						_('已切换为单wan多网关模式。请确保监控目标列表中配置了有效的网关 IP。')
					), 'info');
				} else {
					ui.addNotification(null, E('p',
						_('已切换为多wan口模式。请确保监控目标列表中选择了正确的 WAN 接口。')
					), 'info');
				}
			}
		};

		// 3. WAN Interface in Multi-Gateway mode
		o = s.option(form.ListValue, 'interface', _('wan网络接口'),
			_('选择存在多个wan网关的接口'));
		o.default = 'wan';
		o.rmempty = false;
		o.depends('mode', 'multi_gw');

		Object.keys(wan_interfaces).forEach(function(iface) {
			o.value(iface);
		});

		// 4. Global Shared Health Check & Failover Parameters (共用调度超时)
		o = s.option(form.Value, 'check_interval', _('Check Interval (s)'),
			_('Shared interval in seconds between health check cycles for all targets.'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = s.option(form.Value, 'check_timeout', _('Check Timeout (s)'),
			_('Shared maximum wait time in seconds for each probe (1s recommended to prevent blocking).'));
		o.datatype = 'uinteger';
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'recovery_delay', _('Recovery Delay'),
			_('Number of consecutive successful checks required before marking link as recovered (failback anti-flap).'));
		o.datatype = 'uinteger';
		o.default = '3';
		o.rmempty = false;

		o = s.option(form.Value, 'failover_delay', _('Failover Delay'),
			_('Number of consecutive failed checks required before marking link as faulted (failover anti-flap).'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		// --- Monitored Targets Section ---
		s = m.section(form.GridSection, 'link', _('Monitored Targets'),
			_('Configure monitored WAN interfaces or next-hop gateways with custom probe targets and priorities (1 = primary, 2 = backup).'));
		s.anonymous = true;
		s.addremove = true;

		// Custom dynamic Modal title
		s.modaltitle = function(section_id) {
			var parent_title = _('LinkBack 链路守护') + ' - ' + _('Settings');
			var mode = getActiveMode();
			var is_new = (this.map.addedSection === section_id) ||
			             (mode === 'multi_gw' ? !uci.get('linkback', section_id, 'gateway') : !uci.get('linkback', section_id, 'name'));
			if (mode === 'multi_gw') {
				if (is_new) {
					return parent_title + ' - ' + _('Add Monitored Gateway');
				} else {
					var gw = uci.get('linkback', section_id, 'gateway') || uci.get('linkback', section_id, 'name') || section_id;
					return parent_title + ' - ' + _('Edit Monitored Gateway') + ' (' + gw + ')';
				}
			} else {
				if (is_new) {
					return parent_title + ' - ' + _('Add Monitored WAN Interface');
				} else {
					var iface = uci.get('linkback', section_id, 'name') || section_id;
					return parent_title + ' - ' + _('Edit Monitored WAN Interface') + ' (' + iface + ')';
				}
			}
		};

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

		// 1. Enabled
		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.rmempty = false;
		makeTableColumnExpand(o, '8%');

		// 2. Monitored Target Display (Table only)
		o = s.option(form.DummyValue, '_target_disp', _('Monitored Target'));
		o.modalonly = false;
		o.cfgvalue = function(section_id) {
			var gw = uci.get('linkback', section_id, 'gateway');
			var name = uci.get('linkback', section_id, 'name');
			var mode = getActiveMode();
			if (mode === 'multi_gw' || gw) {
				if (gw) {
					if (name && name !== gw) {
						return gw + ' (' + name + ')';
					}
					return gw;
				}
				return name ? (_('Missing Gateway IP: %s').format(name)) : _('Unset');
			} else {
				return name || _('Unselected');
			}
		};
		makeTableColumnExpand(o, '24%');

		// 3a. Gateway IP (Multi-GW mode only, Modal only)
		var o_gw = s.option(form.Value, 'gateway', _('Gateway IP'),
			_('Next-hop IPv4 address of this gateway (e.g. 192.168.1.254).'));
		o_gw.datatype = 'ip4addr';
		o_gw.modalonly = true;
		o_gw.placeholder = '192.168.1.254';
		var origRenderGw = o_gw.render;
		o_gw.render = function(option_index, section_id, in_table) {
			if (getActiveMode() !== 'multi_gw') {
				return Promise.resolve(E('div', { 'style': 'display: none !important;' }));
			}
			return origRenderGw.call(this, option_index, section_id, in_table);
		};
		o_gw.validate = function(section_id, value) {
			if (getActiveMode() !== 'multi_gw') {
				return true;
			}
			if (!value || value.trim() === '') {
				return _('Gateway IP is required.');
			}
			var val = value.trim();
			var self_opt = this;
			var conflict = false;
			uci.sections('linkback', 'link').forEach(function(sec) {
				var sid = sec['.name'];
				if (sid !== section_id) {
					var other_gw = self_opt.formvalue(sid) || uci.get('linkback', sid, 'gateway');
					if (other_gw && other_gw === val) {
						conflict = true;
					}
				}
			});
			if (conflict) {
				return _('Gateway IP %s is already used by another link.').format(val);
			}
			return true;
		};
		o_gw.write = function(section_id, value) {
			if (getActiveMode() === 'multi_gw') {
				if (value != null && value.trim() !== '') {
					uci.set('linkback', section_id, 'gateway', value.trim());
				} else {
					uci.remove('linkback', section_id, 'gateway');
				}
			} else {
				uci.remove('linkback', section_id, 'gateway');
			}
		};

		// 3b. Gateway Alias (Multi-GW mode only, Modal only)
		var o_alias = s.option(form.Value, 'name_alias', _('Gateway Alias (Optional)'),
			_('Descriptive alias for this gateway (e.g. Bypass_GW, Main_Router). If empty, Gateway IP will be used.'));
		o_alias.modalonly = true;
		o_alias.placeholder = 'Bypass_GW';
		var origRenderAlias = o_alias.render;
		o_alias.render = function(option_index, section_id, in_table) {
			if (getActiveMode() !== 'multi_gw') {
				return Promise.resolve(E('div', { 'style': 'display: none !important;' }));
			}
			return origRenderAlias.call(this, option_index, section_id, in_table);
		};
		o_alias.cfgvalue = function(section_id) {
			if (getActiveMode() === 'multi_gw') {
				var gw = uci.get('linkback', section_id, 'gateway');
				var name = uci.get('linkback', section_id, 'name');
				if (name && name !== gw) {
					return name;
				}
			}
			return '';
		};
		o_alias.write = function(section_id, value) {
			if (getActiveMode() === 'multi_gw') {
				var gw = uci.get('linkback', section_id, 'gateway');
				if (!value || value.trim() === '') {
					uci.set('linkback', section_id, 'name', gw || section_id);
				} else {
					uci.set('linkback', section_id, 'name', value.trim());
				}
			}
		};

		// 3c. WAN Interface (Multi-WAN mode only, Modal only)
		var o_iface = s.option(form.ListValue, 'name_iface', _('WAN Interface'),
			_('Logical interface from firewall WAN zone.'));
		o_iface.modalonly = true;
		Object.keys(wan_interfaces).forEach(function(iface) {
			o_iface.value(iface);
		});
		uci.sections('linkback', 'link').forEach(function(sec) {
			if (sec.name && !wan_interfaces[sec.name]) {
				o_iface.value(sec.name, _('%s (configured)').format(sec.name));
			}
		});
		var origRenderIface = o_iface.render;
		o_iface.render = function(option_index, section_id, in_table) {
			if (getActiveMode() !== 'multi_wan') {
				return Promise.resolve(E('div', { 'style': 'display: none !important;' }));
			}
			return origRenderIface.call(this, option_index, section_id, in_table);
		};
		o_iface.cfgvalue = function(section_id) {
			if (getActiveMode() === 'multi_wan') {
				return uci.get('linkback', section_id, 'name');
			}
			return null;
		};
		o_iface.validate = function(section_id, value) {
			if (getActiveMode() !== 'multi_wan') {
				return true;
			}
			if (!value) {
				return _('WAN Interface is required.');
			}
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
		o_iface.write = function(section_id, value) {
			if (getActiveMode() === 'multi_wan') {
				uci.set('linkback', section_id, 'name', value);
				uci.remove('linkback', section_id, 'gateway');
			}
		};

		// 3. Priority
		o = s.option(form.Value, 'priority', _('Priority'),
			_('Lower number indicates higher priority (e.g. 1 = Primary, 2 = Backup).'));
		o.datatype = 'uinteger';
		o.default = '1';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (value == null || value === '') {
				return t_priority_empty;
			}
			var self_opt = this;
			var has_conflict = false;
			uci.sections('linkback', 'link').forEach(function(sec) {
				var sid = sec['.name'];
				if (sid !== section_id) {
					var other_val = self_opt.formvalue(sid);
					if (other_val == null || other_val === '') {
						other_val = uci.get('linkback', sid, 'priority');
					}
					if (other_val != null && other_val !== '' && String(other_val) === String(value)) {
						has_conflict = true;
					}
				}
			});
			if (has_conflict) {
				return t_priority_conflict.format(value);
			}
			return true;
		};
		makeTableColumnExpand(o, '12%');

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
		makeTableColumnExpand(o, '12%');

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
		makeTableColumnExpand(o, '18%');

		// 6. Check Type Dropdown (Virtual field, Modal only)
		o = s.option(form.ListValue, 'check_type', _('Check Type'),
			_('Health probe method for this specific target.'));
		o.value('ping', _('Ping Probe'));
		o.value('dns', _('DNS Probe'));
		o.value('tcp', _('TCP Probe'));
		o.default = 'ping';
		o.rmempty = false;
		o.modalonly = true;

		o.cfgvalue = function(section_id) {
			if (uci.get('linkback', section_id, 'ping_targets'))
				return 'ping';
			if (uci.get('linkback', section_id, 'dns_server'))
				return 'dns';
			if (uci.get('linkback', section_id, 'tcp_target'))
				return 'tcp';
			return 'ping';
		};

		o.write = function(section_id, value) {
			var current = uci.get('linkback', section_id, 'ping_targets') ? 'ping' :
			              (uci.get('linkback', section_id, 'dns_server') ? 'dns' :
			              (uci.get('linkback', section_id, 'tcp_target') ? 'tcp' : ''));
			var next = (value == null) ? 'ping' : String(value);

			if (next === current) {
				return;
			}

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

		// 7. Custom Ping Probe Parameters
		o = s.option(form.Value, 'ping_targets', _('Ping Targets'),
			_('Custom IP list to ping through this link/gateway (comma-separated, e.g. 223.5.5.5,119.29.29.29).'));
		o.default = '223.5.5.5,119.29.29.29';
		o.rmempty = false;
		o.modalonly = true;
		o.depends('check_type', 'ping');
		o.validate = function(section_id, value) {
			if (!value) return _('Ping Targets is required.');
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

		// 8. Custom DNS Probe Parameters
		o = s.option(form.Value, 'dns_server', _('DNS Server'),
			_('DNS server IP for UDP query probe (e.g. 119.29.29.29).'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.modalonly = true;
		o.depends('check_type', 'dns');

		o = s.option(form.Value, 'dns_domain', _('DNS Domain'),
			_('Domain name to resolve for DNS probe (e.g. www.baidu.com).'));
		o.default = 'www.baidu.com';
		o.rmempty = false;
		o.modalonly = true;
		o.depends('check_type', 'dns');

		// 9. Custom TCP Probe Parameters
		o = s.option(form.Value, 'tcp_target', _('TCP Target'),
			_('Target IP for TCP handshake probe.'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.modalonly = true;
		o.depends('check_type', 'tcp');

		o = s.option(form.Value, 'tcp_port', _('TCP Port'),
			_('Target port for TCP handshake probe (e.g. 80 or 443).'));
		o.datatype = 'port';
		o.default = '80';
		o.rmempty = false;
		o.modalonly = true;
		o.depends('check_type', 'tcp');

		// 提示：超时与防抖延迟由全局配置统一管理，子项完全无需重复配置
		return m.render();
	}
});
