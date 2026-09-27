// SPDX-License-Identifier: GPL-2.0-only
// Adds a temperature row to Status -> Overview. Reads the status file the daemon
// writes, so the overview never talks to the modem itself.
'use strict';
'require baseclass';
'require fs';

var STATUS_FILE = '/var/run/thermal-guard.status';

function parseStatus(text) {
	var st = {};
	(text || '').split('\n').forEach(function(line) {
		var i = line.indexOf('=');
		if (i > 0)
			st[line.substring(0, i)] = line.substring(i + 1).trim();
	});
	return st;
}

function num(v) {
	var n = parseInt(v, 10);
	return isNaN(n) ? null : n;
}

// Sensor names come straight from the kernel. Translate the ones people actually
// recognise, leave the rest as reported rather than guessing.
function sensorLabel(name) {
	var m = name.match(/^(?:mt79\d\d|mtwifi)_phy(\d)/);
	if (m)
		return _('Wi-Fi %d').format(parseInt(m[1], 10) + 1);
	if (name.indexOf('mdio_bus') === 0 || name.indexOf('phy') === 0)
		return _('Ethernet');
	if (name === 'nvme')
		return _('SSD');
	return name;
}

function extraSensors(st) {
	var out = [];
	for (var k in st) {
		if (k.indexOf('sensor.') === 0 && st[k] !== '')
			out.push([ sensorLabel(k.substring(7)), parseInt(st[k], 10) ]);
	}
	return out.sort(function(a, b) { return a[0] > b[0] ? 1 : -1; });
}

function temp(value, warn, crit) {
	if (value === null)
		return E('em', {}, _('no reading'));

	var colour = '';
	if (crit !== null && value >= crit)
		colour = 'color:#f44336;font-weight:bold';
	else if (warn !== null && value >= warn)
		colour = 'color:#ff9800;font-weight:bold';

	return E('span', { 'style': colour }, '%d °C'.format(value));
}

return baseclass.extend({
	title: _('Temperatures'),

	load: function() {
		return fs.read(STATUS_FILE).catch(function() { return null; });
	},

	render: function(text) {
		if (text === null)
			return null;

		var st = parseStatus(text);
		var stage = num(st.stage);
		var rows = [
			[ _('Processor'), temp(num(st.cpu_c), num(st.cpu_warn), num(st.cpu_crit)) ]
		];

		if (st.modem_src || st.modem_c)
			rows.push([ _('Modem'), temp(num(st.modem_c), num(st.modem_warn), num(st.modem_crit)) ]);

		extraSensors(st).forEach(function(s) {
			rows.push([ s[0], temp(s[1], null, null) ]);
		});

		// fan_view is what can be read, even where fan_mode leaves the fan to
		// another controller. Older status files only carry fan_mode.
		var fanView = st.fan_view || st.fan_mode;
		if (fanView && fanView !== 'none') {
			var state = num(st.fan_state), max = num(st.fan_max), rpm = num(st.fan_rpm),
			    percent = num(st.fan_percent);
			var label = (percent !== null)
				? '%d %%'.format(percent)
				: (state === null ? '-'
					: (max ? _('fan step %d of %d').format(state, max) : String(state)));
			if (rpm !== null && rpm > 0)
				label += ' (%d rpm)'.format(rpm);
			rows.push([ _('Fan'), label ]);
		}

		if (stage !== null && stage >= 0)
			rows.push([
				_('Thermal Guard'),
				E('span', { 'style': 'color:#f44336;font-weight:bold' },
					_('protection stage %d active').format(stage + 1))
			]);

		return E('table', { 'class': 'table' }, rows.map(function(row) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, row[0]),
				E('td', { 'class': 'td left' }, row[1])
			]);
		}));
	}
});
