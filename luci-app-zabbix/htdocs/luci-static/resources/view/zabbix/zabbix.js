'use strict';
'require form';
'require view';
'require uci';
'require ui';
'require fs';

return view.extend({
	render: function() {

		var m, s, o;

		m = new form.Map('zabbix', _('Zabbix Agent configuration'));

		s = m.section(form.TypedSection, 'zabbix');
		s.anonymous = true;
		s.addremove = false;
		s.tab('general', _('General Settings'));
		s.tab('passive', _('Passive Checks'));
		s.tab('active', _('Active Checks'));
		s.tab('tls', _('TLS Configuration'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enabled'));
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'hostname', _('Hostname'), _('Unique hostname used by the agent to register with the Zabbix server. Required for active checks and must match the node name specified on the server.'));
		o.rmempty = false;
		o.datatype = 'host';
		o.cfgvalue = function(section_id) {
			return uci.get('zabbix', section_id, 'hostname') || fs.trimmed('/proc/sys/kernel/hostname')
		};

		o = s.taboption('passive', form.DynamicList, 'server', _('Server'), _('List of IP addresses (or hostnames) of Zabbix servers allowed to connect to this agent. If 0.0.0.0/0 is specified, the agent will accept connections from any IP address.'));
		o.rmempty = false;
		o.datatype = 'or(cidr,ipmask,host)';

		o = s.taboption('passive', form.Value, 'listen_ip', _('ListenIP'), _('IP address of the local network interfaces on which the Zabbix agent will listen for incoming connections from the server.'));
		o.datatype = 'host';

		o = s.taboption('passive', form.Value, 'listen_port', _('ListenPort'), _('The agent will listen on this port for connections from the server.'));
		o.placeholder = 10050;
		o.datatype = 'range(1024,32767)';

		o = s.taboption('passive', form.ListValue, 'tls_accept', _('TLSAccept'), _('The parameter defines which types of TLS connections the agent will accept.'));
		o.default = 'unencrypted';
		o.value('unencrypted',_('without encryption'));
		o.value('psk',_('pre-shared key'));
		o.value('cert',_('certificate'));

		o = s.taboption('active', form.Value, 'server_active', _('ServerActive'), _('IP address or hostname of the Zabbix server for active checks. If the parameter is not specified, active checks are disabled.'));
		o.datatype = 'or(cidr,host,hostport,ipaddrport)';

		o = s.taboption('active', form.ListValue, 'tls_connect', _('TLSConnect'), _('The parameter defines how the agent should establish a secure connection with the Zabbix server or proxy.'));
		o.default = 'unencrypted';
		o.value('unencrypted',_('without encryption'));
		o.value('psk',_('pre-shared key'));
		o.value('cert',_('certificate'));

		o = s.taboption('tls', form.Value, 'tls_psk_identity', _('TLSPSKIdentity'), _('Pre-shared key identifier string. Used for unique identification and management of the pre-shared key, ensuring the security of the connection between the agent and the server.'));
		o.depends({tls_accept: 'psk'});
		o.depends({tls_connect: 'psk'});

		o = s.taboption('tls', form.FileUpload, 'tls_psk_file', _('TLSPSKFile'), _('Agent pre-shared key.'));
		o.depends({tls_accept: 'psk'});
		o.depends({tls_connect: 'psk'});

		o = s.taboption('tls', form.FileUpload, 'tls_ca_file', _('TLSCAFile'), _('Root CA certificate. Used for encrypted connections between Zabbix components.'));
		o.depends({tls_accept: 'cert'});
		o.depends({tls_connect: 'cert'});

		o = s.taboption('tls', form.FileUpload, 'tls_cert_file', _('TLSCertFile'), _('Agent certificate or certificate chain used to establish secure (TLS/SSL) connections between Zabbix components.'));
		o.depends({tls_accept: 'cert'});
		o.depends({tls_connect: 'cert'});

		o = s.taboption('tls', form.FileUpload, 'tls_key_file', _('TLSKeyFile'), _('Agent private key.'));
		o.depends({tls_accept: 'cert'});
		o.depends({tls_connect: 'cert'});

		return m.render();
	}
});
