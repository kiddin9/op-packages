'use strict';
'require form';
'require view';
'require uci';
'require rpc';
'require tools.widgets as widgets';

return view.extend({
	render: function() {
		var m, s, o;
		
		m = new form.Map('xl2tpd', _('L2TP Server'));
		m.description = _('Simple, quick and convenient L2TP VPN, universal across the platform');

		s = m.section(form.TableSection, 'login');
		s.anonymous = true;
		s.addremove = true;

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.editable = true;

		o = s.option(form.Value, 'username', _('User name'));
		o.editable = true;

		o = s.option(form.Value, 'password', _('Password'));
		o.editable = true;

		o = s.option(form.Value, 'remoteip', _('IP address'));
		o.editable = true;
		o.datatype = 'ipaddr';

		o = s.option(form.Value, 'route', _('Add route'));
		o.editable = true;
		o.datatype = "ipaddr"
		
		return m.render();
	}
});
