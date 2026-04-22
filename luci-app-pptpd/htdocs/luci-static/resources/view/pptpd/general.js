'use strict';
'require form';
'require view';
'require uci';
'require rpc';
'require tools.widgets as widgets';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('pptpd', _('PPTP Server'));
		m.description = _('Simple, quick and convenient PPTP VPN, universal across the platform');

		s = m.section(form.NamedSection, 'pptpd', 'pptpd');

		o = s.option(form.Flag, 'enabled', _('Enable PPTP Server'));

		o = s.option(form.Value, 'localip', _('Local IP'));
		o.placeholder = '192.168.0.1';
		o.datatype = 'ipaddr';

		o = s.option(form.Value, 'remoteip_start', _('Remote IP Range Start'));
		o.placeholder = '192.168.0.20';
		o.datatype = 'ipaddr';

		o = s.option(form.Value, 'remoteip_end', _('Remote IP Range End'));
		o.placeholder = '192.168.0.30';
		o.datatype = 'ipaddr';

		return m.render();
	}
});
