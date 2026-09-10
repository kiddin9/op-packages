'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	load: function() {
		return uci.load('aw-bpf');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('aw-bpf', _('eBPF Traffic Control & DPI'),
			_('eBPF kernel-level bandwidth control, session audit logging and xDPI L7 application/domain recognition.'));

		s = m.section(form.TypedSection, 'aw-bpf', _('General Settings'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enable_event_log', _('Enable Session Event Logging'),
			_('Record TCP/UDP session connection events as structured JSON to system log / syslog. (DNS learning and xDPI protocol recognition are always active in background).'));
		o.rmempty = false;
		o.default = '0';

		return m.render();
	}
});
