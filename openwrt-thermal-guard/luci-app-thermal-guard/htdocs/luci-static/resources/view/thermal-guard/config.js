// SPDX-License-Identifier: GPL-2.0-only
'use strict';
'require view';
'require form';
'require uci';
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

// The daemon reports why it cannot manage the trips as a fixed code.
function tripReasonText(code) {
	switch (code) {
		case 'no_cdev':        return _('the kernel knows no fan on this device');
		case 'no_zone':        return _('no thermal zone drives the fan');
		case 'zone_path':      return _('the fan\'s thermal zone is not under /sys/class/thermal');
		case 'no_active_trip': return _('the fan is not bound to any switching temperature');
		case 'not_writable':   return _('the switching temperatures cannot be changed');
		default:               return code || _('unknown reason');
	}
}

function tripList(v) {
	return (v || '').split('/').filter(function(x) { return x !== ''; });
}

// The daemon's defaults, from tg_cfg_default_thresholds. An empty field means
// the daemon uses these, so the order is checked against them as well.
var THRESHOLD_DEFAULTS = {
	cpu_warn: 70, cpu_crit: 80, cpu_emergency: 90, modem_warn: 80, modem_crit: 88
};

// The value the daemon will use: the default when empty, NaN when it is not
// a whole number.
function thresholdValue(option, value) {
	if (value == null || value === '')
		return THRESHOLD_DEFAULTS[option];
	return /^[0-9]+$/.test(value) ? parseInt(value, 10) : NaN;
}

// Thresholds have to stay ordered, otherwise the service falls back to its
// defaults and the protection silently stops doing what the form says. The
// neighbours are read from the form, not from the saved configuration, so a
// change made next to this one counts.
function checkOrder(section, section_id, option, value, below, above, belowLabel, aboveLabel) {
	var v = thresholdValue(option, value);
	if (isNaN(v))
		return _('Enter a whole number');

	if (below) {
		var b = thresholdValue(below, section.formvalue(section_id, below));
		if (!isNaN(b) && v <= b)
			return _('Must be above %s (%d)').format(belowLabel, b);
	}
	if (above) {
		var a = thresholdValue(above, section.formvalue(section_id, above));
		if (!isNaN(a) && v >= a)
			return _('Must be below %s (%d)').format(aboveLabel, a);
	}
	return true;
}

// Mirrors the guards in backends.sh. The service rejects anything outside these
// subtrees anyway, so catching it here saves a silent fallback after Apply.
function checkPathPrefix(value, prefixes) {
	if (!value)
		return true;
	if (value.charAt(0) !== '/' || value.indexOf('..') >= 0)
		return _('Must be an absolute path without ".."');
	for (var i = 0; i < prefixes.length; i++)
		if (value.indexOf(prefixes[i]) === 0)
			return true;
	return _('Path must start with %s').format(prefixes.join(', '));
}

return view.extend({
	load: function() {
		return fs.read(STATUS_FILE).catch(function() { return null; });
	},

	render: function(statusText) {
		var m, s, o,
		    st = parseStatus(statusText),
		    tripDt = tripList(st.trip_dt),
		    tripLimit = parseInt(st.trip_limit, 10);

		m = new form.Map('thermal-guard', _('Thermal Guard'),
			_('Monitors the temperature of the main processor and the modem. If the device gets too hot, it intervenes in up to three protection stages. Stages stay active until you clear them on the status page.'));

		s = m.section(form.NamedSection, 'main', 'thermal-guard');
		s.addremove = false;
		s.tab('general', _('General'));
		s.tab('thresholds', _('Thresholds'),
			_('Temperatures at which each protection stage starts. What actually happens at stage 2 and 3 is set on the Actions tab.'));
		s.tab('fan', _('Fan'));
		s.tab('modem', _('Modem'));
		s.tab('actions', _('Actions'),
			_('What happens when a stage starts. Stage 1 of 3 warns and, if this service drives the fan (Fan tab), sets it to full speed. That cannot be changed.'));

		// ---- general ----
		o = s.taboption('general', form.Flag, 'enabled', _('Enabled'),
			_('Switching this off pauses the temperature checks. Protection stages that are already active stay applied and the fan is not handed back, so a broken fan cannot be hidden by a checkbox. Use Clear on the status page for that.'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'interval', _('Interval'),
			_('Seconds between two temperature readings. Values below five seconds are treated as five.'));
		o.datatype = 'and(uinteger,min(5))';
		o.placeholder = '20';

		o = s.taboption('general', form.Value, 'cpu_temp_path', _('Processor temperature source'),
			_('System file the processor temperature is read from. The default fits most devices; change it only if your device reports its temperature elsewhere.'));
		o.placeholder = '/sys/class/thermal/thermal_zone0/temp';
		o.validate = function(id, v) {
			return checkPathPrefix(v, ['/sys/class/thermal/', '/sys/class/hwmon/', '/sys/devices/']);
		};

		// ---- thresholds ----
		o = s.taboption('thresholds', form.Value, 'cpu_warn', _('Processor warning (stage 1 of 3)'),
			_('Stage 1 of 3 starts when either temperature reaches its warning level: a warning, and full fan speed if this service drives the fan.'));
		o.placeholder = '70';
		o.validate = function(id, v) {
			return checkOrder(this.section, id, 'cpu_warn', v, null, 'cpu_crit', null, _('Processor critical'));
		};

		o = s.taboption('thresholds', form.Value, 'cpu_crit', _('Processor critical (stage 2 of 3)'));
		o.placeholder = '80';
		o.validate = function(id, v) {
			return checkOrder(this.section, id, 'cpu_crit', v, 'cpu_warn', 'cpu_emergency', _('Processor warning'), _('Processor emergency'));
		};

		o = s.taboption('thresholds', form.Value, 'cpu_emergency', _('Processor emergency (stage 3 of 3)'));
		o.placeholder = '90';
		o.validate = function(id, v) {
			return checkOrder(this.section, id, 'cpu_emergency', v, 'cpu_crit', null, _('Processor critical'), null);
		};

		o = s.taboption('thresholds', form.Value, 'modem_warn', _('Modem warning (stage 1 of 3)'));
		o.placeholder = '80';
		o.validate = function(id, v) {
			return checkOrder(this.section, id, 'modem_warn', v, null, 'modem_crit', null, _('Modem critical'));
		};

		o = s.taboption('thresholds', form.Value, 'modem_crit', _('Modem critical (stage 2 of 3)'));
		o.placeholder = '88';
		o.validate = function(id, v) {
			return checkOrder(this.section, id, 'modem_crit', v, 'modem_warn', null, _('Modem warning'), null);
		};

		o = s.taboption('thresholds', form.Value, 'hold_minutes', _('Hold time'),
			_('Minutes a stage has to last before the next one starts on time alone: stage 2 of 3 if the temperature has not dropped, stage 3 of 3 if it is still rising.'));
		o.datatype = 'uinteger';
		o.placeholder = '3';

		o = s.taboption('thresholds', form.Value, 'hysteresis', _('Hysteresis'),
			_('How many degrees the temperature has to fall below the warning level before the device counts as cooled down.'));
		o.datatype = 'uinteger';
		o.placeholder = '10';

		// ---- fan ----
		o = s.taboption('fan', form.ListValue, 'fan_mode', _('Fan control method'),
			_('Leave the fan to the regulator the device already has, unless it has none. Automatic uses the kernel fan control when the device offers it and otherwise leaves the fan alone. It never picks direct control, which needs the fan\'s polarity.'));
		o.value('none', _('Leave the fan alone'));
		o.value('auto', _('Automatic'));
		o.value('cooling_device', _('Kernel fan control'));
		o.value('pwm', _('Direct fan control (PWM)'));
		o.default = 'none';

		o = s.taboption('fan', form.Value, 'fan_cooling_device_type', _('Fan identifier'),
			_('Name the kernel uses for the fan. Change it only if the fan is not found automatically.'));
		o.placeholder = 'pwm-fan';
		o.depends('fan_mode', 'auto');
		o.depends('fan_mode', 'cooling_device');

		o = s.taboption('fan', form.ListValue, 'fan_governor', _('Control mode to restore'),
			_('Control mode handed back to the kernel when the stages are cleared and no earlier control mode was recorded. The default fits almost every device.'));
		// The daemon's list, kernel names and not translated. Not user_space:
		// nothing would regulate the fan after a reset.
		[ 'step_wise', 'fair_share', 'bang_bang', 'power_allocator' ].forEach(function(g) {
			o.value(g);
		});
		o.default = 'step_wise';
		o.depends('fan_mode', 'auto');
		o.depends('fan_mode', 'cooling_device');

		o = s.taboption('fan', form.Value, 'pwm_path', _('Fan speed file'),
			_('Only needed for direct fan control.'));
		o.placeholder = '/sys/class/hwmon/hwmon0/pwm1';
		o.depends('fan_mode', 'pwm');
		o.validate = function(id, v) { return checkPathPrefix(v, ['/sys/class/hwmon/', '/sys/devices/']); };

		o = s.taboption('fan', form.Value, 'pwm_enable_path', _('Fan control file'),
			_('Only needed for direct fan control. Switches the fan chip to manual control.'));
		o.placeholder = '/sys/class/hwmon/hwmon0/pwm1_enable';
		o.depends('fan_mode', 'pwm');
		o.validate = function(id, v) { return checkPathPrefix(v, ['/sys/class/hwmon/', '/sys/devices/']); };

		o = s.taboption('fan', form.Value, 'pwm_full', _('Value for full speed'),
			_('Required for direct fan control. The raw value that makes this fan spin fastest. Some boards wire the signal inverted, where 1 is full speed and 255 stops the fan. Without this value and the slowest one, the fan is left alone.'));
		o.datatype = 'uinteger';
		o.depends('fan_mode', 'pwm');
		o.rmempty = false;

		o = s.taboption('fan', form.Value, 'pwm_idle', _('Value for the slowest setting'),
			_('Required for direct fan control. The opposite end of the same scale. Together with full speed it states the polarity, and it shows the fan speed as a percentage. Never written to the hardware.'));
		o.datatype = 'uinteger';
		o.depends('fan_mode', 'pwm');
		o.rmempty = false;

		// ---- switching temperatures of the kernel fan control ----
		o = s.taboption('fan', form.DummyValue, '_trip_state', _('Kernel fan control'));
		o.cfgvalue = function() {
			switch (st.trip_state) {
				case 'active':
					return _('Managed by this service, switching temperatures now %s °C').format(tripList(st.trip_now).join(', '));
				case 'inactive':
					return _('Not possible on this device: %s').format(tripReasonText(st.trip_reason));
				default:
					return _('Not managed by this service');
			}
		};

		o = s.taboption('fan', form.ListValue, 'trip_boost', _('Speed the fan up for the modem'),
			_('Where the kernel drives the fan, its switching temperatures are lowered while the modem runs hotter than the processor, so the fan speeds up for the modem as well. They only ever go down, never above the base values. A missing modem reading keeps them where they are.'));
		o.value('off', _('Off'));
		o.value('modem', _('Follow the modem temperature'));
		o.default = 'off';

		o = s.taboption('fan', form.Value, 'trip_boost_offset', _('Modem allowance'),
			_('Degrees the modem may run above the processor before the switching temperatures are lowered.'));
		o.datatype = 'range(0,40)';
		o.placeholder = '15';
		o.depends('trip_boost', 'modem');

		o = s.taboption('fan', form.DynamicList, 'trip_active', _('Fan switching temperatures'),
			tripDt.length
				? _('Base values in degrees at which the kernel moves the fan one step up, lowest first, one value per step. Empty uses the values of the installed firmware: %s °C.').format(tripDt.join(', '))
				: _('Base values in degrees at which the kernel moves the fan one step up, lowest first, one value per step. Empty uses the values of the installed firmware.'));
		// Same rules as the service, which falls back to the firmware values
		// on anything it rejects.
		o.validate = function(section_id, value) {
			var list = L.toArray(this.formvalue(section_id)), prev = null;
			for (var i = 0; i < list.length; i++) {
				var raw = String(list[i]).trim(), v = parseInt(raw, 10);
				if (isNaN(v) || String(v) !== raw)
					return _('Enter a whole number');
				if (v < 20 || v > 95)
					return _('Must be between 20 and 95');
				if (prev !== null && v <= prev)
					return _('Each value must be higher than the one before');
				if (!isNaN(tripLimit) && v >= tripLimit)
					return _('Must be below %d, the temperature at which the kernel itself intervenes').format(tripLimit);
				prev = v;
			}
			if (list.length && tripDt.length && list.length !== tripDt.length)
				return _('Needs exactly %d values, one per fan step').format(tripDt.length);
			return true;
		};

		if (st.trip_dt_changed === '1' && tripDt.length) {
			o = s.taboption('fan', form.DummyValue, '_trip_dt_hint', _('New firmware values'));
			o.cfgvalue = function() {
				return _('The installed firmware now uses %s °C. Your own base values were set for an earlier firmware and still apply.').format(tripDt.join(', '));
			};

			// The daemon keeps the firmware values trip_active was made for in
			// a file of its own; trips-keep records the ones of this boot.
			// Resolves to true when that worked.
			var keepTrips = function() {
				var failed = function(why) {
					ui.addNotification(null, E('p', {}, _('Recording the firmware values failed: %s').format(why)), 'error');
					return false;
				};
				return fs.exec('/usr/sbin/thermal-guard', [ 'trips-keep' ]).then(function(res) {
					if (res.code !== 0)
						return failed(res.stderr || res.stdout || res.code);
					ui.addNotification(null, E('p', {}, _('Firmware values recorded. The notice goes away with the next check.')), 'info');
					return true;
				}).catch(failed);
			};

			o = s.taboption('fan', form.Button, '_trip_dt_adopt', ' ');
			o.inputtitle = _('Use the firmware values');
			// Parse the form first, then set the values, otherwise the form
			// writes the old list back over them. Apply reloads the page, so
			// it comes last.
			o.onclick = function() {
				return m.save(function() {
					uci.set('thermal-guard', 'main', 'trip_active', tripDt);
				}).then(keepTrips).then(function(ok) {
					if (ok)
						return ui.changes.apply(true);
				});
			};

			o = s.taboption('fan', form.Button, '_trip_dt_keep', ' ');
			o.inputtitle = _('Keep my values');
			o.onclick = keepTrips;
		}

		if (st.fan_levels) {
			o = s.taboption('fan', form.DummyValue, '_fan_levels', _('Fan steps of the firmware'),
				_('Raw value per fan step from the device tree, with the duty cycle of the signal. They belong to the fan that is fitted and change only with a new firmware image.'));
			o.cfgvalue = function() {
				return st.fan_levels.split(' ').map(function(v, i) {
					return _('step %d: %d (%d %%)').format(i, parseInt(v, 10), Math.round(parseInt(v, 10) * 100 / 255));
				}).join(', ');
			};
		}

		// ---- modem ----
		o = s.taboption('modem', form.ListValue, 'modem_source', _('Modem temperature source'),
			_('Automatic tries the known modem commands in turn. Select your manufacturer if detection fails.'));
		o.value('auto', _('Automatic'));
		o.value('quectel', _('Quectel (AT+QTEMP)'));
		o.value('fibocom', _('Fibocom (AT+GTSENRDTEMP)'));
		o.value('file', _('File'));
		o.value('command', _('Command'));
		o.value('none', _('No modem'));
		o.default = 'auto';

		o = s.taboption('modem', form.Value, 'modem_at_port', _('Modem control port'),
			_('Serial port the commands are sent to. Automatic checks the usual ports.'));
		o.placeholder = 'auto';
		o.depends('modem_source', 'auto');
		o.depends('modem_source', 'quectel');
		o.depends('modem_source', 'fibocom');
		o.validate = function(id, v) {
			if (v === 'auto')
				return true;
			return checkPathPrefix(v, ['/dev/']);
		};

		o = s.taboption('modem', form.Value, 'at_lock', _('Lock file for modem access'),
			_('Prevents this service and other programs from sending commands to the modem at the same time. Point those programs at the same file.'));
		o.placeholder = '/var/lock/modem-at.lock';
		o.depends('modem_source', 'auto');
		o.depends('modem_source', 'quectel');
		o.depends('modem_source', 'fibocom');
		o.validate = function(id, v) { return checkPathPrefix(v, ['/var/lock/', '/var/run/', '/tmp/']); };

		o = s.taboption('modem', form.Value, 'modem_temp_file', _('Temperature file'));
		o.depends('modem_source', 'file');
		o.validate = function(id, v) { return checkPathPrefix(v, ['/var/run/', '/tmp/', '/sys/']); };

		o = s.taboption('modem', form.DummyValue, '_modem_temp_hook', _('Own temperature source'),
			_('Reads /etc/thermal-guard/hooks/modem-temp, which has to print the temperature in degrees as a whole number. Place the file over SSH; it runs as root and is deliberately not editable from here.'));
		o.depends('modem_source', 'command');

		// ---- actions ----
		o = s.taboption('actions', form.ListValue, 'stage1_action', _('Action at stage 2 of 3'));
		o.value('modem_radio_off', _('Switch the modem radio off'));
		o.value('wifi_off', _('Switch Wi-Fi off'));
		o.value('interface_down', _('Take a network interface down'));
		o.value('command', _('Run own script'));
		o.value('none', _('Nothing'));
		o.default = 'modem_radio_off';

		o = s.taboption('actions', form.DummyValue, '_stage1_hook', _('Script at stage 2 of 3'),
			_('Runs /etc/thermal-guard/hooks/stage1. Place the file over SSH and make it executable.'));
		o.depends('stage1_action', 'command');

		o = s.taboption('actions', form.ListValue, 'stage2_action', _('Action at stage 3 of 3'));
		o.value('wifi_off', _('Switch Wi-Fi off'));
		o.value('modem_radio_off', _('Switch the modem radio off'));
		o.value('interface_down', _('Take a network interface down'));
		o.value('command', _('Run own script'));
		o.value('none', _('Nothing'));
		o.default = 'wifi_off';

		o = s.taboption('actions', form.DummyValue, '_stage2_hook', _('Script at stage 3 of 3'),
			_('Runs /etc/thermal-guard/hooks/stage2. Place the file over SSH and make it executable.'));
		o.depends('stage2_action', 'command');

		o = s.taboption('actions', form.ListValue, 'modem_radio_off_at', _('How the modem is switched off'),
			_('Flight mode suits most modems. Use minimum function for a modem that does not accept flight mode. Either way the modem is asked afterwards (AT+CFUN?), and a modem that does not confirm counts as a failed stage.'));
		o.value('AT+CFUN=4', _('Flight mode (AT+CFUN=4)'));
		o.value('AT+CFUN=0', _('Minimum function (AT+CFUN=0)'));
		o.default = 'AT+CFUN=4';
		o.depends('stage1_action', 'modem_radio_off');
		o.depends('stage2_action', 'modem_radio_off');

		o = s.taboption('actions', form.Value, 'action_interface', _('Interface to take down'),
			_('Network interface taken down by the interface action and brought back up when the stages are cleared. Empty uses the modem network interface.'));
		o.datatype = 'uciname';
		o.depends('stage1_action', 'interface_down');
		o.depends('stage2_action', 'interface_down');

		o = s.taboption('actions', form.Value, 'notify_url', _('Notification address'),
			_('The warning text is posted here. Works with ntfy, Gotify, Matrix, Slack and anything else that accepts a plain POST body.'));
		o.placeholder = 'https://ntfy.sh/my-topic';
		// Anchored at both ends, and quotes, backslashes and control characters
		// are refused: the service writes this into a curl config file, where
		// any of them would turn the rest of the value into directives.
		o.validate = function(id, v) {
			if (!v)
				return true;
			if (!/^https?:\/\/[\x21-\x7e]+$/.test(v) || /["\\]/.test(v))
				return _('Must be an http:// or https:// address without quotes or spaces');
			return true;
		};

		o = s.taboption('actions', form.Value, 'notify_header', _('Additional header'),
			_('Sent with the notification, for example an authorisation token. Needs curl installed; the smaller uclient-fetch cannot send headers.'));
		o.placeholder = 'Authorization: Bearer ...';
		o.password = true;
		o.validate = function(id, v) {
			if (!v)
				return true;
			if (!/^[\x20-\x7e]+$/.test(v) || /["\\]/.test(v))
				return _('Must be printable text without quotes or backslashes');
			return true;
		};

		o = s.taboption('actions', form.Value, 'uplink_interface', _('Modem network interface'),
			_('Lets the service tell whether another internet connection exists, so a message from stage 2 of 3 on goes out or waits in the queue. Also the interface the interface action takes when none is set.'));
		o.datatype = 'uciname';

		return m.render();
	}
});
