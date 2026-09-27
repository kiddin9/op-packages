// SPDX-License-Identifier: GPL-2.0-only
'use strict';
'require view';
'require poll';
'require dom';
'require fs';
'require ui';

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

// Colour follows the configured thresholds, not a fixed scale, so the bar means
// the same thing on a passively cooled box and on one with a fan.
function tempClass(value, warn, crit) {
	if (value === null)
		return '';
	if (crit !== null && value >= crit)
		return 'tg-crit';
	if (warn !== null && value >= warn)
		return 'tg-warn';
	return 'tg-ok';
}

function gauge(value, warn, crit, max) {
	var pct = (value === null) ? 0 : Math.max(0, Math.min(100, Math.round(value * 100 / max)));
	return E('div', { 'class': 'tg-gauge' }, [
		E('div', {
			'class': 'tg-fill ' + tempClass(value, warn, crit),
			'style': 'width:%d%%'.format(pct)
		})
	]);
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

function row(label, valueNode, gaugeNode) {
	return E('div', { 'class': 'tg-row' }, [
		E('div', { 'class': 'tg-label' }, label),
		gaugeNode || E('div', { 'class': 'tg-gauge tg-empty' }, []),
		E('div', { 'class': 'tg-value' }, valueNode)
	]);
}

// Stage 2 and 3 do whatever the Actions tab says, so the banner has to read the
// configured action instead of naming the default.
function actionLabel(action) {
	switch (action) {
		case 'modem_radio_off': return _('modem radio off');
		case 'wifi_off':        return _('Wi-Fi off');
		case 'interface_down':  return _('network interface down');
		case 'command':         return _('custom command');
		case 'none':            return _('no action');
		default:                return action || _('unknown action');
	}
}

function stageText(stage, st) {
	switch (stage) {
		case 0: return st.fan_mode === 'none'
			? _('Stage 1 of 3 active: warning, fan left to its own controller')
			: _('Stage 1 of 3 active: fan at full speed');
		case 1: return _('Stage 2 of 3 active: %s').format(actionLabel(st.stage1_action));
		case 2: return _('Stage 3 of 3 active: %s').format(actionLabel(st.stage2_action));
		default: return _('No intervention, temperatures within range');
	}
}

// Why the page might be showing something other than a live reading. The daemon
// stamps every write with "now": a file that stopped being written means the
// service is gone, while a fresh file holding an old reading means it is
// running but not measuring.
function serviceState(st) {
	var written = parseInt(st.now, 10),
	    interval = parseInt(st.interval, 10) || 30,
	    age = written ? Math.floor(Date.now() / 1000) - written : null;

	// Three missed writes, with a floor so a short interval is not jumpy.
	if (age !== null && age > Math.max(90, interval * 3))
		return 'stopped';
	if (st.enabled === '0')
		return 'paused';
	return 'running';
}

function fmtAge(ts) {
	var n = parseInt(ts, 10);
	if (!n)
		return '-';
	var age = Math.max(0, Math.floor(Date.now() / 1000) - n);
	if (age < 90)
		return _('%d s ago').format(age);
	return _('%d min ago').format(Math.round(age / 60));
}

return view.extend({
	load: function() {
		return fs.read(STATUS_FILE).catch(function() { return null; });
	},

	render: function(text) {
		var style = E('style', {}, [
			'.tg-row{display:flex;align-items:center;gap:.6em;margin:.35em 0}',
			'.tg-label{flex:0 0 12em}',
			'.tg-value{flex:0 0 7em;text-align:right;font-weight:bold}',
			'.tg-gauge{flex:1 1 auto;height:1.1em;background:rgba(128,128,128,.25);border-radius:.55em;overflow:hidden;min-width:6em}',
			'.tg-gauge.tg-empty{background:transparent}',
			'.tg-fill{height:100%;border-radius:.55em;transition:width .4s}',
			'.tg-ok{background:#4caf50}.tg-warn{background:#ff9800}.tg-crit{background:#f44336}',
			'.tg-banner{padding:.6em .8em;border-radius:.3em;margin-bottom:1em}',
			'.tg-banner.tg-active{background:rgba(244,67,54,.15);border-left:4px solid #f44336}',
			'.tg-banner.tg-idle{background:rgba(76,175,80,.12);border-left:4px solid #4caf50}',
			'.tg-banner.tg-warn-banner{background:rgba(255,152,0,.15);border-left:4px solid #ff9800}',
			'.tg-meta{opacity:.7;font-size:90%;margin-top:.8em}'
		].join('\n'));

		var body = E('div', { 'id': 'tg-body' }, []);
		var container = E('div', { 'class': 'cbi-map' }, [
			style,
			E('h2', {}, _('Thermal Guard')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Current temperatures and protection state. Thresholds and actions are configured under System, Thermal Guard.')),
			body
		]);

		this.update(body, text);

		poll.add(L.bind(function() {
			return fs.read(STATUS_FILE)
				.catch(function() { return null; })
				.then(L.bind(function(t) { this.update(body, t); }, this));
		}, this), 5);

		return container;
	},

	update: function(body, text) {
		if (text === null) {
			dom.content(body, E('div', { 'class': 'alert-message warning' },
				_('No data yet. Check whether the Thermal Guard service is running.')));
			return;
		}

		var st = parseStatus(text);
		var cpu = num(st.cpu_c), modem = num(st.modem_c), stage = num(st.stage);
		var cpuWarn = num(st.cpu_warn), cpuCrit = num(st.cpu_crit);
		var modemWarn = num(st.modem_warn), modemCrit = num(st.modem_crit);
		var fanState = num(st.fan_state), fanMax = num(st.fan_max), rpm = num(st.fan_rpm);

		var rows = [
			row(_('Processor temperature'),
				cpu === null ? '-' : '%d °C'.format(cpu),
				gauge(cpu, cpuWarn, cpuCrit, num(st.cpu_emergency) || 100))
		];

		if (st.modem_src !== '' || modem !== null)
			rows.push(row(_('Modem temperature'),
				modem === null ? _('no reading') : '%d °C'.format(modem),
				gauge(modem, modemWarn, modemCrit, (num(st.modem_crit) || 90) + 10)));

		extraSensors(st).forEach(function(s) {
			rows.push(row(s[0], '%d °C'.format(s[1]), gauge(s[1], null, null, 100)));
		});

		// fan_view is what can be read, even where fan_mode leaves the fan to
		// another controller. Older status files only carry fan_mode.
		var fanView = st.fan_view || st.fan_mode;
		if (fanView && fanView !== 'none') {
			// The daemon computes the percentage because only it knows which way
			// the raw scale runs; an inverted board reports full speed as 0.
			var fanPercent = num(st.fan_percent);
			var fanLabel = (fanPercent !== null)
				? '%d %%'.format(fanPercent)
				: (fanState === null ? '-'
					: (fanMax ? _('fan step %d of %d').format(fanState, fanMax) : String(fanState)));
			if (rpm !== null && rpm > 0)
				fanLabel += ' (%d rpm)'.format(rpm);
			rows.push(row(_('Fan'), fanLabel,
				(fanPercent !== null) ? gauge(fanPercent, null, null, 100)
					: ((fanState !== null && fanMax) ? gauge(fanState, null, null, fanMax) : null)));

			if (st.fan_foreign === '1')
				rows.push(row(_('Fan control'),
					_('Another service is controlling this fan'), null));
		}

		// Only shown where this service manages the kernel's switching
		// temperatures; elsewhere they are none of its business.
		if (st.trip_state === 'active') {
			var tripDelta = num(st.trip_delta);
			rows.push(row(_('Fan switching temperatures'),
				(st.trip_now || '-').replace(/\//g, ' / ') + ' °C', null));
			if (tripDelta)
				rows.push(row('', _('lowered by %d K for the modem').format(tripDelta), null));
		}

		var active = (stage !== null && stage >= 0),
		    state = serviceState(st),
		    noSensor = (st.no_sensor === '1'),
		    banner = [ E('strong', {}, noSensor
				? _('This device does not report any temperature')
				: stageText(stage, st)) ];

		// Not a fault to chase: some boards expose no thermal zone and no hwmon
		// temperature input at all. Saying so beats a page full of dashes.
		if (noSensor)
			banner.push(E('div', {},
				_('No thermal sensor was found, so the processor is not watched on this hardware. The modem thresholds still apply while the modem reports a temperature.')));

		// A stage that is still applied while nothing is watching is the one
		// thing an operator has to be told about, so it comes before the rest.
		if (state !== 'running' && !noSensor)
			banner.push(E('div', {}, state === 'stopped'
				? (active
					? _('The service is not running. Protection stages stay applied and the fan is not handed back.')
					: _('The service is not running. Temperatures are not being watched.'))
				: (active
					? _('The service is paused. Protection stages stay applied and the fan is not handed back.')
					: _('The service is paused. Temperatures are not being watched.'))));

		if (st.trip_dt_changed === '1')
			banner.push(E('div', {},
				_('The firmware brings new fan switching temperatures (%s °C). Your own values still apply; review them under System, Thermal Guard, Fan.').format((st.trip_dt || '').replace(/\//g, ', '))));

		if (active)
			banner.push(E('div', {}, [
				E('div', {}, _('Protection stages stay active until you clear them. Clear them once the cause is fixed, for example a replaced fan.')),
				E('button', {
					'class': 'btn cbi-button cbi-button-reset',
					'style': 'margin-top:.5em',
					'click': ui.createHandlerFn(this, 'handleClear')
				}, _('Clear protection stages'))
			]));

		dom.content(body, [
			E('div', {
				'class': 'tg-banner ' + ((state !== 'running' || noSensor) ? 'tg-warn-banner'
					: (active ? 'tg-active' : 'tg-idle'))
			}, banner),
			E('div', {}, rows),
			E('div', { 'class': 'tg-meta' }, [
				_('Last reading: %s').format(fmtAge(st.ts)),
				st.modem_src ? ' · ' + _('modem source: %s').format(st.modem_src) : '',
				st.fan_mode ? ' · ' + _('fan mode: %s').format(st.fan_mode) : '',
				st.version ? ' · ' + _('version %s').format(st.version) : ''
			].join(''))
		]);
	},

	// Runs "thermal-guard reset": hands the fan back, radio on, stage cleared.
	handleClear: function() {
		return fs.exec('/usr/sbin/thermal-guard', [ 'reset' ]).then(function(res) {
			if (res.code !== 0)
				ui.addNotification(null, E('p', {}, _('Clearing failed: %s').format(res.stderr || res.stdout || res.code)), 'error');
			else
				ui.addNotification(null, E('p', {}, _('Protection stages cleared.')), 'info');
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, _('Clearing failed: %s').format(err)), 'error');
		});
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
