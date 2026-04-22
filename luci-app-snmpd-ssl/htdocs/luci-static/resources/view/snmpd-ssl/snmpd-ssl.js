'use strict';
'require form';
'require view';
'require uci';
'require ui';
'require fs';

return view.extend({
	render: function() {

		var m, s, o;

		m = new form.Map('snmpd', _('SNMP Settings'));

		s = m.section(form.TypedSection, 'snmpd');
		s.anonymous = true;
		s.addremove = false;
		s.tab('general', _('General Settings'));
		s.tab('snmpv1v2c', _('SNMPv1/SNMPv2c'));
		s.tab('snmpv3', _('SNMPv3'));
		s.tab('system', _('System'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enabled'));
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'ip_family', _('IP family') );
		o.default = 'ipv4';
		o.value('ipv4',_('IPv4'));
		o.value('ipv6',_('IPv6'));
		o.value('both',_('IPv4 and IPv6'));
		o.write = function(section_id, value) {
			var section = uci.get_first('snmpd', 'agent');
			var agentaddress = uci.get('snmpd', section['.name'], 'agentaddress');
			if (!agentaddress)
				return null;
			var port = agentaddress.match(/(?:UDP|UDP6):(\d+)/);
			if (value == "ipv4") {
				uci.set('snmpd', section['.name'], 'agentaddress', 'UDP:%s'.format(port[1]));
			}
			if (value == "ipv6") {
				uci.set('snmpd', section['.name'], 'agentaddress', 'UDP6:%s'.format(port[1]));
			}
			if (value == "both") {
				uci.set('snmpd', section['.name'], 'agentaddress', 'UDP:%s,UDP6:%s'.format(port[1],port[1]));
			}
			uci.set('snmpd', section_id, this.option, value)
		};

		o = s.taboption('general', form.Value, 'port', _('Port'), _('Port for SNMP connections'));
		o.datatype = 'port';
		o.rmempty = false;
		o.cfgvalue = function(section_id) {
			var section = uci.get_first('snmpd', 'agent');
			var agentaddress = uci.get('snmpd', section['.name'], 'agentaddress');
			if (!agentaddress)
				return null;
			var port = agentaddress.match(/(?:UDP|UDP6):(\d+)/);
			return port[1];
		};
		o.write = function(section_id, value) {
			var ip_family = uci.get('snmpd', section_id, 'ip_family');
			var section = uci.get_first('snmpd', 'agent');
			if (ip_family == "ipv4") {
				uci.set('snmpd', section['.name'], 'agentaddress', 'UDP:%s'.format(value));
			}
			if (ip_family == "ipv6") {
				uci.set('snmpd', section['.name'], 'agentaddress', 'UDP6:%s'.format(value));
			}
			if (ip_family == "both") {
				uci.set('snmpd', section['.name'], 'agentaddress', 'UDP:%s,UDP6:%s'.format(value,value));
			}
		};

		o = s.taboption('general', form.ListValue, 'mode', _('SNMP mode'));
		o.default = 'v1_v2c_v3';
		o.value('v1_v2c',_('SNMPv1/SNMPv2c'));
		o.value('v3',_('SNMPv3'));
		o.value('v1_v2c_v3',_('SNMPv1/SNMPv2c/SNMPv3'));

		o = s.taboption('snmpv1v2c', form.Value, 'community_name', _('Community'), _('Community string, sent to the monitoring system along with the request'));
		o.rmempty = false;
		o.depends({mode: /v2c/});
		o.cfgvalue = function(section_id) {
			return uci.get('snmpd', 'public', 'community');
		};
		o.write = function(section_id, value) {
			uci.set('snmpd', 'public', 'community', value);
			uci.set('snmpd', 'public6', 'community', value);
		};

		o = s.taboption('snmpv1v2c', form.ListValue, 'v2c_mode', _('Acces mode'));
		o.value('ro',_('Read-only parameters (monitoring)'));
		o.depends({mode: /v2c/});

		o = s.taboption('snmpv3', form.Value, 'security_name', _('Security name'), _('Username for authentication when working via SNMP'));
		o.rmempty = false;
		o.depends({mode: /v3/});

		o = s.taboption('snmpv3', form.ListValue, 'security_type', _('Security level'), _('Security level selection when working via SNMP'));
		o.default = 'noAuthNoPriv';
		o.value('noAuthNoPriv',_('No authentication and encryption settings'));
		o.value('authNoPriv',_('With authentication'));
		o.value('authPriv',_('With authentication and encryption'));
		o.depends({mode: /v3/});

		o = s.taboption('snmpv3', form.ListValue, 'auth_prot', _('Authentication protocol'), _('Type of authentication protocol'));
		o.default = 'authPriv';
		o.value('MD5');
		o.value('SHA');
		o.value('SHA-224');
		o.value('SHA-256');
		o.value('SHA-384');
		o.value('SHA-512');
		o.depends({mode: /v3/, security_type: /auth/});

		o = s.taboption('snmpv3', form.Value, 'auth_pass', _('Authentication passphrase'), _('Passphrase for authentication when working via SNMP'));
		o.rmempty = false;
		o.depends({mode: /v3/, security_type: /auth/});

		o = s.taboption('snmpv3', form.ListValue, 'priv_prot', _('Privacy protocol'), _('Type of encryption protocol'));
		o.default = 'authPriv';
		o.value('DES');
		o.value('AES');
		o.depends({mode: /v3/, security_type: 'authPriv'});

		o = s.taboption('snmpv3', form.Value, 'priv_pass', _('Privacy passphrase'), _('Passphrase for encrypting the data transmission channel when working via SNMP'));
		o.rmempty = false;
		o.depends({mode: /v3/, security_type: 'authPriv'});

		o = s.taboption('snmpv3', form.ListValue, 'v3_mode', _('Acces mode'));
		o.value('rouser',_('Read-only parameters (monitoring)'));
		o.depends({mode: /v3/});

		function system_section_cfgvalue(section_id) {
			var section = uci.get_first('snmpd', 'system');
			return uci.get('snmpd', section['.name'], this.option);
		};

		function system_section_write(section_id, value) {
			var section = uci.get_first('snmpd', 'system');
			uci.set('snmpd', section['.name'], this.option, value);
		};

		function system_section_remove(section_id) {
			var section = uci.get_first('snmpd', 'system');
			uci.unset('snmpd', section['.name'], this.option);
		};

		o = s.taboption('system', form.Value, 'sysName', _('sysName'), _('Device name in the monitoring system. This field is optional'));
		o.cfgvalue = system_section_cfgvalue;
		o.write = system_section_write;
		o.remove = system_section_remove;

		o = s.taboption('system', form.Value, 'sysContact', _('sysContact'), _('Contact information. This field is optional'));
		o.cfgvalue = system_section_cfgvalue;
		o.write = system_section_write;
		o.remove = system_section_remove;

		o = s.taboption('system', form.Value, 'sysLocation', _('sysLocation'), _('Device location description. This field is optional'));
		o.cfgvalue = system_section_cfgvalue;
		o.write = system_section_write;
		o.remove = system_section_remove;

		o = s.taboption('system', form.Value, 'sysDescr', _('sysDescr'), _('Device description. This field is optional'));
		o.cfgvalue = system_section_cfgvalue;
		o.write = system_section_write;
		o.remove = system_section_remove;

		return m.render();
	}
});
