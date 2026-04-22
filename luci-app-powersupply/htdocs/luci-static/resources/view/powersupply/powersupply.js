'use strict';
'require form';
'require view';
'require uci';
'require rpc';
'require ui';
'require poll';

var power_status = rpc.declare({
	object: 'powersupply',
	method: 'info',
	params: [ 'info' ],
	expect: { '': {} }
});

var DummyValueExt = form.DummyValue.extend({
	renderWidget: function(section_id, option_index, cfgvalue) {
		return E([], [
			E('input', {
				'id': this.cbid(section_id),
				'type': 'text',
				'readonly': false
			})
		]);
	}
});

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('powersupply', _('Power Management'));

		s = m.section(form.NamedSection, 'system', _('System Properties'));

		o = s.option(DummyValueExt, 'input_voltage', _('Input power supply voltage, mV'));

		o = s.option(form.ListValue, 'poe_out_power', _('PoE OUT power'));
		o.value(0,_('disabled'));
		o.value(1,_('enabled'));

		o = s.option(form.ListValue, 'poe_out_control', _('Overcurrent protection PoE OUT'));
		o.value(0,_('disabled'));
		o.value(1,_('enabled'));

		o = s.option(form.ListValue, 'usb_power', _('USB power'));
		o.value(0,_('disabled'));
		o.value(1,_('enabled'));

		o = s.option(form.ListValue, 'usb_control', _('Overcurrent protection USB'));
		o.value(0,_('disabled'));
		o.value(1,_('enabled'));

		o = s.option(form.ListValue, 'ext_power', _('Power output 7.5V'));
		o.value(0,_('disabled'));
		o.value(1,_('enabled'));

		return m.render().then(function(mapEl) {
			poll.add(function() {
				return power_status().then(function(t) {
					document.getElementById('cbid.powersupply.system.input_voltage').value = t.input_voltage || 'n/a';
				});
			},1);

			return mapEl;
		});
	}
});
