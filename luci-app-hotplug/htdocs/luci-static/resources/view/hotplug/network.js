'use strict';
'require form';
'require view';
'require uci';
'require rpc';
'require tools.widgets as widgets';

return view.extend({
	render: function() {
		var m, s, o;
		
		m = new form.Map('hotplug', _('Network Rules'));
		m.description = _('Running commands when the hotplug trigger occurs. <br/>\
			<br/>\
			ACTION - "add" or "remove" noted <br/>\
			DEVICENAME - configured interface names (br-lan, wlan0, phy1-ap0) <br/>\
			PATH - full path<br/>\
			DEVPATH - full device path (for example “/devices/pci0000:00/0000:00:0b.0/usb1/1-1/1-1:1.0/host7/target7:0:0/7:0:0:0/block/sdc/sdc1”)<br/>\
			DEVTYPE - what the DEVICENAME are names of, ie. br-lan, phy1-ap0 <br/ >\
			INTERFACE - configured interfaces as in DEVTYPE <br/>\
			SEQNUM - seqnum (a number) <br/>\
			SUBSYSTEM - always = “net” <br/>\
			IFINDEX - appears to be related to the configured interfaces. See ifconfig <br/>\
			More information about net event here: <a href="https://openwrt.org/docs/guide-user/base-system/hotplug#net">hotplug#net</a>');

		s = m.section(form.GridSection, 'hotplug');
		s.addremove = true;
		s.nodescriptions = true;

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.rmempty = false;

		o = s.option(widgets.NetworkSelect, 'iface', _('Ping interface'));
		o.rmempty = false;
		o.textvalue = function(section_id) {
			return uci.get('hotplug', section_id, 'iface');
		}

		o = s.option(form.DynamicList, 'testip', _('IP address or hostname of test servers'));
		o.datatype = 'or(hostname,ipaddr("nomask"))';

		o = s.option(form.Value, 'check_period', _('Period of check, sec'));
		o.rmempty = false;
		o.datatype = 'and(uinteger,min(20))';
		o.default = '60';

		o = s.option(form.Value, 'sw_before_modres', _('Failed attempts before iface up/down'), _('0 - not used'));
		o.rmempty = false;
		o.datatype = 'and(uinteger,min(0),max(100))';
		o.default = '3';

		o = s.option(form.Value, 'sw_before_sysres', _('Failed attempts before reboot'), _('0 - not used'));
		o.rmempty = false;
		o.datatype = 'and(uinteger,min(0),max(100))';
		o.default = '0';

		return m.render();
	}
});
