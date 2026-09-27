'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require uci';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { '': {} }
});

function getServiceStatus() {
	return L.resolveDefault(callServiceList('meow'), {}).then(function(res) {
		try {
			var instances = res.meow.instances;
			if (!instances)
				return false;

			for (var key in instances) {
				if (instances[key].running === true)
					return true;
			}

			return false;
		}
		catch (e) {
			return false;
		}
	});
}

function renderStatus(running) {
	return running
		? E('span', { 'style': 'color:#2e7d32;font-weight:bold;' }, _('RUNNING'))
		: E('span', { 'style': 'color:#c62828;font-weight:bold;' }, _('NOT RUNNING'));
}

return view.extend({
	load: function() {
		return uci.load('meow');
	},

	render: function() {
		var m, s, o;

		m = new form.Map(
			'meow',
			_('meow'),
			_('Rule-based tunneling proxy kernel, compatible with mihomo (Clash Meta). ' +
			  'Proxies, rules and DNS are configured in the YAML file below; ' +
			  'use the Panel tab for runtime control.'));

		s = m.section(form.NamedSection, 'main', 'meow');

		/* ---- Status ---- */
		o = s.option(form.DummyValue, '_status', _('Status'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			var node = E('span', {}, _('Collecting data…'));

			poll.add(function() {
				return getServiceStatus().then(function(running) {
					while (node.firstChild)
						node.removeChild(node.firstChild);

					node.appendChild(renderStatus(running));
				});
			});

			return node;
		};

		/* ---- Basic ---- */
		o = s.option(form.Flag, 'enabled', _('Enable'), _('Start the service at boot.'));
		o.rmempty = false;

		o = s.option(form.Value, 'config_file', _('Configuration file'));
		o.default = '/etc/meow/config.yaml';
		o.rmempty = false;

		o = s.option(form.Value, 'work_dir', _('Working directory'));
		o.default = '/etc/meow';
		o.rmempty = false;

		o = s.option(form.Value, 'panel_port', _('Panel port'));
		o.datatype = 'port';
		o.default = '9090';
		o.rmempty = false;

		/* ---- Transparent gateway ---- */
		o = s.option(form.Flag, 'gateway', _('Transparent gateway'));
		o.default = false;
		o.enabled = '1';
		o.disabled = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'tproxy_port', _('tproxy port'));
		o.datatype = 'port';
		o.default = '7893';
		o.depends('gateway', '1');

		o = s.option(form.Value, 'dns_port', _('DNS hijack port'));
		o.datatype = 'port';
		o.default = '1053';
		o.depends('gateway', '1');

		return m.render();
	}
});
