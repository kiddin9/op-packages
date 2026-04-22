'use strict';
'require form';
'require view';
'require uci';
'require rpc';
'require ui';

var consoleStatus = rpc.declare({
	object: 'pollmydevice',
	method: 'status',
	expect: { '': {} }
});

var consoleDisable = rpc.declare({
	object: 'pollmydevice',
	method: 'con_off',
	expect: { '': {} }
});

var consoleEnable = rpc.declare({
	object: 'pollmydevice',
	method: 'con_on',
	expect: { '': {} }
});

var getID = rpc.declare({
	object: 'pollmydevice',
	method: 'get_id',
	expect: { '': {} }
});

return view.extend({
	load: function() {
		return Promise.all([
			consoleStatus(),
			getID()
		]);
	},
	render: function(rpc_replies) {
		var status = rpc_replies[0];
		var ids = rpc_replies[1];
		var m, s, o;
		
		m = new form.Map('pollmydevice', _('PollMyDevice'));
		m.description = _('TCP to RS232/RS485 converter');

		s = m.section(form.GridSection, 'interface');		
		s.tab('general', _('Mode Settings'));
		s.tab('serial', _('Port Settings'));
		s.addremove = true;
		s.nodescriptions = true;
		s.addbtntitle = _('Add new configuration...');
		s.handleAdd = function(ev,name) {
			for (var i = 0; i < 8; i++) {
				var section = uci.get('pollmydevice', String(i));
				if (section == null) {
					var section_id = String(i);
					uci.add('pollmydevice', 'interface', section_id);
					uci.set('pollmydevice', section_id, 'desc',name);
					uci.set('pollmydevice', section_id, 'devicename','/dev/com1');
					uci.set('pollmydevice', section_id, 'baudrate','9600');
					uci.set('pollmydevice', section_id, 'bytesize','8');
					uci.set('pollmydevice', section_id, 'mode','disabled');
					uci.set('pollmydevice', section_id, 'open_in_firewall','1')
					uci.set('pollmydevice', section_id, 'server_port',String(30000+i))
					this.addedSection = section_id;
					return this.renderMoreOptionsModal(section_id);
				};
			};
			ui.addNotification(null, E('p', 'Exceeded the maximum number of configurations.'), 'error');
		};

		o = s.taboption('general', form.Value, 'desc', _('Description'));
		o.rmempty = false;
		o.optional = false;
		o.datatype = 'uciname';

		o = s.taboption('serial', form.Value, 'devicename', _('Port'));
		o.rmempty = false;
		o.value('/dev/com0');
		o.value('/dev/com1');
		o.textvalue = function(section_id) {
			return uci.get('pollmydevice', section_id, 'devicename');
		}

		o = s.taboption('general', form.ListValue, 'mode', _('Mode'));
		o.default = 'disabled';
		o.value('disabled',_('disabled'));
		o.value('server',_('server'));
		o.value('client',_('client'));

		o = s.taboption('general', form.Flag, 'quiet',_('Disable log messages'));
		o.default = 0;
		o.modalonly = true;
		o.depends({mode: 'server'});
		o.depends({mode: 'client'});

		o = s.taboption('general', form.Value, 'server_port', _('Listening port'), _('Network port used for data exchange with a configurable serial port'));
		o.modalonly = true;
		o.rmempty = false;
		o.optional = false;
		o.datatype = 'or(502,range(1025,65535))';
		o.depends({mode: 'server'});

		o = s.taboption('general', form.Flag, 'open_in_firewall', _("Open a port for incoming connections from the 'wan' zone"),_("A new rule for traffic in the firewall will be created, allowing connections to the specified network port from external networks. Access from the 'lan' zone is open by default for all network ports"))
		o.modalonly = true;
		o.depends({mode: 'server'});

		o = s.taboption('general', form.ListValue, 'connection_mode', _('Connection Mode'));
		o.modalonly = true;
		o.default = 0;
		o.value(0,_('Alternating'));
		o.value(1,_('Simultaneous'));
		o.depends({mode: 'server'});

		o = s.taboption('general', form.Value, 'holdconntime', _('Connection Hold Time (sec)'));
		o.default = 60;
		o.datatype = 'and(uinteger, min(0), max(100000))'
		o.depends({connection_mode: '0'});
		o.modalonly = true;

		o = s.taboption('general', form.Value, 'pack_size', _('Minimum packet size [0-255] (byte)'));
		o.modalonly = true;
		o.default = 0;
		o.datatype = 'and(uinteger, min(0), max(255))';
		o.depends({mode: 'server'});
		o.depends({mode: 'client'});

		o = s.taboption('general', form.Value, 'pack_timeout', _('Packet timeout [0-255] (x100ms)'));
		o.modalonly = true;
		o.default = 0;
		o.datatype = 'and(uinteger, min(0), max(255))';
		for(i=1;i<256;i++){
			o.depends({pack_size: i.toString()});
		}

		o = s.taboption('general', form.Value, 'client_host', _('Server Host or IP Address'));
		o.default = 'hub.m2m24.ru';
		o.datatype = 'string';
		o.depends({mode: 'client'});
		o.textvalue = function(section_id) {
			if(uci.get('pollmydevice', section_id, 'mode') === 'client') {
				return uci.get('pollmydevice', section_id, 'client_host');
			} else {
				return '-'
			}
		};

		o = s.taboption('general', form.DummyValue, 'port', _('Port'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			if(uci.get('pollmydevice', section_id, 'client_port')) return uci.get('pollmydevice', section_id, 'client_port');
			if(uci.get('pollmydevice', section_id, 'server_port')) return uci.get('pollmydevice', section_id, 'server_port');
		}

		o = s.taboption('general', form.Value, 'client_port', _('Server Port'));
		o.modalonly = true;
		o.rmempty = false;
		o.optional = false;
		o.default = 6008;
		o.datatype = 'or(502,range(1025,65535))';
		o.depends({mode: 'client'});

		o = s.taboption('general', form.Value, 'client_timeout', _('Client Reconnection Timeout (sec)'));
		o.modalonly = true;
		o.default = 60;
		o.datatype = 'and(uinteger, min(0), max(100000))';
		o.depends({mode: 'client'});

		o = s.taboption('general', form.ListValue, 'client_auth', _('Client Authentification'));
		o.widget='radio';
		o.default = 0;
		o.value(0,_('Disable'));
		o.value(1,_('Enable'));
		o.depends({mode: 'client'});
		o.textvalue = function(section_id) {
			return this.cfgvalue(section_id)==1 ? 'enabled' : 'disabled';
		};

		o = s.taboption('general', form.DummyValue, 'client_id', _('Client ID'));
		o.modalonly = true;
		o.depends({mode: 'client'});
		o.cfgvalue = function(section_id) {
			return ids['id' + section_id];
		};

		o = s.taboption('general', form.ListValue, 'modbus_gateway', _('Modbus TCP/IP'));
		o.default = 0
		o.value(0,_('Disabled'));
		o.value(1,_('RTU'));
		o.value(2,_('ASCII'));
		o.depends({mode: 'server'});
		o.depends({client_auth: '0'});
		o.textvalue = function(section_id) {
			if(this.cfgvalue(section_id)==0) return 'disabled';
			if(this.cfgvalue(section_id)==1) return 'RTU';
			if(this.cfgvalue(section_id)==2) return 'ASCII';
		};

		o = s.taboption('general', form.DummyValue, 'console_status',_('Console status'));
		o.modalonly = true;
		o.depends({desc: 'console'});
		o.cfgvalue = function(section_id) {
			return _(status.status);
		};

		o = s.taboption('general', form.Button, 'switch',_('Console'),_('Save the changes. The router will reboot'));
		o.modalonly = true;
		o.inputstyle = 'action important';
		o.inputtitle = _('On/Off');
		o.depends({desc: 'console'});
		o.onclick = L.bind(function(section_id) {
			if (status.status == 'activated') {
				consoleDisable().then(function(){
					L.ui.showModal(_('Rebooting…'), [
						E('p', { 'class': 'spinning' }, _('Waiting for device...'))
					]);

					window.setTimeout(function() {
						L.ui.showModal(_('Rebooting…'), [
							E('p', { 'class': 'spinning alert-message warning' },
								_('Device unreachable! Still waiting for device...'))
						]);
					}, 150000);

					L.ui.awaitReconnect();
				})
			} else {
				consoleEnable().then(function(){
					L.ui.showModal(_('Rebooting…'), [
						E('p', { 'class': 'spinning' }, _('Waiting for device...'))
					]);

					window.setTimeout(function() {
						L.ui.showModal(_('Rebooting…'), [
							E('p', { 'class': 'spinning alert-message warning' },
								_('Device unreachable! Still waiting for device...'))
						]);
					}, 150000);

					L.ui.awaitReconnect();
				})
			}
		},this)

		o = s.taboption('serial', form.ListValue, 'baudrate', _('BaudRate'));
		o.default = 9600;
		o.value(300);
		o.value(600);
		o.value(1200);
		o.value(2400);
		o.value(4800);
		o.value(9600);
		o.value(19200);
		o.value(38400);
		o.value(57600);
		o.value(115200);
		o.value(230400);
		o.value(460800);
		o.value(921600);
		o.datatype = 'uinteger';
		o.modalonly = true;
		o.depends({mode: 'disabled', '!reverse': true});

		o = s.taboption('serial', form.ListValue, 'bytesize', _('ByteSize'));
		o.default = 8;
		o.value(5);
		o.value(6);
		o.value(7);
		o.value(8);
		o.datatype = 'uinteger';
		o.modalonly = true;
		o.depends({mode: 'disabled', '!reverse': true});

		o = s.taboption('serial', form.ListValue, 'stopbits', _('StopBits'));
		o.default = 1;
		o.value(1);
		o.value(2);
		o.datatype = 'uinteger';
		o.modalonly = true;
		o.depends({mode: 'disabled', '!reverse': true});

		o = s.taboption('serial', form.ListValue, 'parity', _('Parity'));
		o.default = 'none';
		o.value('even');
		o.value('odd');
		o.value('none');
		o.datatype = 'string';
		o.modalonly = true;
		o.depends({mode: 'disabled', '!reverse': true});

		o = s.taboption('serial', form.ListValue, 'flowcontrol', _('Flow Control'));
		o.modalonly = true;
		o.default = 'none';
		o.value('XON/XOFF');
		o.value('RTS/CTS');
		o.value('none');
		o.datatype = 'string';
		o.depends({mode: 'disabled', '!reverse': true});

		return m.render();
	}
});
