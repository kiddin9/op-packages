'use strict';
'require baseclass';

function enabled(value) {
	return value !== true && value !== 1 && value !== '1';
}

function percentEncode(value) {
	var encoded = encodeURIComponent(String(value));
	var bytes = [];
	var output = '';
	var offset;

	for (offset = 0; offset < encoded.length; offset++) {
		if (encoded.charAt(offset) === '%') {
			bytes.push(parseInt(encoded.substr(offset + 1, 2), 16));
			offset += 2;
		}
		else {
			bytes.push(encoded.charCodeAt(offset));
		}
	}

	for (var i = 0; i < bytes.length; i++) {
		var byte = bytes[i];
		var printable = (byte >= 0x20 && byte <= 0x3a) ||
			(byte >= 0x3c && byte <= 0x7e);
		output += printable ? String.fromCharCode(byte) :
			'%' + byte.toString(16).toUpperCase().padStart(2, '0');
	}

	return output;
}

function security(config) {
	var encryption = String(config.encryption || 'none').toLowerCase();
	var key = config.key;

	if (encryption === 'none')
		return { type: '', key: '', transition: '' };

	if (encryption === 'sae')
		return key ? { type: 'WPA', key: key, transition: '0' } : null;

	if (encryption === 'sae-mixed' || encryption === 'psk' ||
	    encryption === 'psk2' || encryption === 'psk-mixed' ||
	    encryption === 'psk+psk2')
		return key ? { type: 'WPA', key: key, transition: '' } : null;

	return null;
}

function payload(config) {
	var auth = security(config);
	var ssid = config.ssid;

	if (!auth || ssid == null || String(ssid) === '')
		return null;

	return [
		'WIFI:',
		auth.type ? 'T:' + auth.type + ';' : '',
		auth.transition !== '' ? 'R:' + auth.transition + ';' : '',
		'S:' + percentEncode(ssid) + ';',
		config.hidden === true || config.hidden === 1 || config.hidden === '1' ?
			'H:true;' : '',
		auth.key ? 'P:' + percentEncode(auth.key) + ';' : '',
		';'
	].join('');
}

function bandLabel(device) {
	var band = String((device || {}).band || '').toLowerCase();
	if (band === '2g') return '2.4 GHz';
	if (band === '5g') return '5 GHz';
	if (band === '6g') return '6 GHz';
	return band ? band.toUpperCase() : '';
}

function activeSections(runtime) {
	var active = {};
	Object.keys(runtime || {}).forEach(function(radioName) {
		var radio = runtime[radioName] || {};
		if (radio.up === false || radio.disabled === true)
			return;
		(radio.interfaces || []).forEach(function(iface) {
			var section = iface && iface.section;
			var config = (iface && iface.config) || {};
			if (section && config.mode === 'ap' && iface.ifname)
				active[section] = true;
		});
	});
	return active;
}

function collect(configResponse, runtime) {
	/* rpc.declare({ expect: { values: {} } }) unwraps the `values` member.
	 * Accept the raw ubus shape too so the collector stays easy to test. */
	var values = (configResponse && configResponse.values) || configResponse || {};
	var active = activeSections(runtime);
	var grouped = {};

	Object.keys(values).forEach(function(section) {
		var config = values[section] || {};
		var device = values[config.device] || {};
		var code;

		if (config['.type'] !== 'wifi-iface' || config.mode !== 'ap' ||
		    !enabled(config.disabled) || !enabled(device.disabled) || !active[section])
			return;

		code = payload(config);
		if (!code)
			return;

		if (!grouped[code])
			grouped[code] = {
				ssid: String(config.ssid),
				payload: code,
				bands: []
			};

		var band = bandLabel(device);
		if (band && grouped[code].bands.indexOf(band) < 0)
			grouped[code].bands.push(band);
	});

	return Object.keys(grouped).map(function(code) {
		grouped[code].bands.sort();
		return grouped[code];
	}).sort(function(left, right) {
		return left.ssid < right.ssid ? -1 : left.ssid > right.ssid ? 1 :
			left.payload < right.payload ? -1 : left.payload > right.payload ? 1 : 0;
	});
}

function fingerprint(networks) {
	return JSON.stringify(networks.map(function(network) {
		return [ network.ssid, network.payload, network.bands ];
	}));
}

return baseclass.extend({
	percentEncode: percentEncode,
	payload: payload,
	collect: collect,
	fingerprint: fingerprint
});
