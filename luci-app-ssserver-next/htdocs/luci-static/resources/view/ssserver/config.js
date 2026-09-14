'use strict';
'require view';
'require form';
'require rpc';

var callGetCiphers = rpc.declare({
	object: 'luci.ssserver',
	method: 'get_ciphers',
	expect: {}
});

var callGetTFOStatus = rpc.declare({
	object: 'luci.ssserver',
	method: 'get_tfo_status',
	expect: {}
});

var callGetLanIP = rpc.declare({
	object: 'luci.ssserver',
	method: 'get_lan_ip',
	expect: {}
});

return view.extend({
	load: function() {
		return Promise.all([
			callGetCiphers(),
			callGetTFOStatus(),
			callGetLanIP()
		]);
	},

	render: function(data) {
		var m, s, o;
		var ciphers = data[0].ciphers || [];
		var tfo_val = data[1].value || 0;
		var lan_ip = data[2].ip || '192.168.1.1';

		m = new form.Map('ssserver', _('Shadowsocks Server Title') + ' - ' + _('Settings'),
			_('A fast and secure tunnel proxy that helps you securely access your local network. ' +
			  'This version uses shadowsocks-rust.'));

		s = m.section(form.TypedSection, 'ssserver', _('Settings'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		o = s.option(form.Value, 'server', _('Server Address'),
			_('The address the server will bind to. Use 0.0.0.0 for all interfaces.'));
		o.datatype = 'ipaddr';
		o.placeholder = '0.0.0.0';

		o = s.option(form.Value, 'server_port', _('Server Port'),
			_('The port the server will listen on.'));
		o.datatype = 'port';
		o.placeholder = '8388';

		o = s.option(form.Value, 'password', _('Password'));
		o.password = true;

		o = s.option(form.ListValue, 'method', _('Encryption Method'));
		for (var i = 0; i < ciphers.length; i++) {
			o.value(ciphers[i]);
		}
		if (ciphers.indexOf('chacha20-ietf-poly1305') === -1 && ciphers.length === 0) {
			o.value('chacha20-ietf-poly1305');
			o.value('aes-256-gcm');
			o.value('aes-128-gcm');
		}

		o = s.option(form.Value, 'timeout', _('ssserver timeout'), _('Connection timeout in seconds.'));
		o.datatype = 'uinteger';
		o.placeholder = '300';

		o = s.option(form.ListValue, 'mode', _('Network Mode'));
		o.value('tcp_and_udp', _('TCP and UDP'));
		o.value('tcp_only', _('TCP only'));
		o.value('udp_only', _('UDP only'));
		o.default = 'tcp_and_udp';

		o = s.option(form.Value, 'dns_resolver', _('DNS Resolver'),
			_('DNS server for the shadowsocks server to resolve addresses.'));
		o.datatype = 'ipaddr';
		o.placeholder = lan_ip;
		o.default = lan_ip;

		o = s.option(form.Flag, 'open_firewall', _('Open Firewall'),
			_('Automatically open the server port in the firewall (WAN).'));

		var tfo_status_msg = '';
		if (tfo_val === 0) {
			tfo_status_msg = '<span style="color:red"> (' + _('Not supported or disabled in kernel') + ')</span>';
		} else if (tfo_val === 1) {
			tfo_status_msg = '<span style="color:orange"> (' + _('Enabled for client only') + ')</span>';
		} else if (tfo_val === 2 || tfo_val === 3) {
			tfo_status_msg = '<span style="color:green"> (' + _('Enabled and supported') + ')</span>';
		}

		o = s.option(form.Flag, 'fast_open', _('TCP Fast Open'),
			_('Enable TCP Fast Open (requires kernel support).') + tfo_status_msg);

		return m.render();
	}
});
