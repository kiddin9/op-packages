'use strict';

const fs = require('fs');
const vm = require('vm');

function load(path) {
	return vm.runInNewContext(`(function(){${fs.readFileSync(path, 'utf8')}\n})()`, {
		baseclass: { extend: value => value },
		encodeURIComponent
	});
}

const common = load('luci/shared.js');

function equal(actual, expected, label) {
	if (JSON.stringify(actual) !== JSON.stringify(expected))
		throw new Error(`${label}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
}

equal(common.percentEncode('a;b\nя'), 'a%3Bb%0A%D1%8F', 'percent encoding');
equal(common.payload({ ssid: 'Guest', encryption: 'none' }),
	'WIFI:S:Guest;;', 'open network');
equal(common.payload({ ssid: 'Main', encryption: 'sae-mixed', key: 'secret' }),
	'WIFI:T:WPA;S:Main;P:secret;;', 'transition network');
equal(common.payload({ ssid: 'Main', encryption: 'sae', key: 'secret', hidden: '1' }),
	'WIFI:T:WPA;R:0;S:Main;H:true;P:secret;;', 'WPA3 network');
equal(common.payload({ ssid: 'Corp', encryption: 'wpa2', key: 'secret' }), null,
	'enterprise network');

const config = { values: {
	radio0: { '.type': 'wifi-device', band: '2g' },
	radio1: { '.type': 'wifi-device', band: '5g' },
	radio2: { '.type': 'wifi-device', band: '6g', disabled: '1' },
	ap0: { '.type': 'wifi-iface', device: 'radio0', mode: 'ap', ssid: 'Home', encryption: 'psk2', key: 'same' },
	ap1: { '.type': 'wifi-iface', device: 'radio1', mode: 'ap', ssid: 'Home', encryption: 'sae-mixed', key: 'same' },
	ap2: { '.type': 'wifi-iface', device: 'radio2', mode: 'ap', ssid: 'Off', encryption: 'sae', key: 'off' },
	sta0: { '.type': 'wifi-iface', device: 'radio1', mode: 'sta', ssid: 'Upstream', encryption: 'psk2', key: 'skip' },
	broken: { '.type': 'wifi-iface', device: 'radio1', mode: 'ap', ssid: 'Broken', encryption: 'psk2', key: 'skip' }
} };
const runtime = {
	radio0: { up: true, interfaces: [ { section: 'ap0', ifname: 'phy0-ap0', config: { mode: 'ap' } } ] },
	radio1: { up: true, interfaces: [
		{ section: 'ap1', ifname: 'phy1-ap0', config: { mode: 'ap' } },
		{ section: 'sta0', ifname: 'phy1-sta0', config: { mode: 'sta' } }
	] },
	radio2: { up: false, interfaces: [ { section: 'ap2', ifname: 'phy2-ap0', config: { mode: 'ap' } } ] }
};

equal(common.collect(config, runtime), [ {
	ssid: 'Home',
	payload: 'WIFI:T:WPA;S:Home;P:same;;',
	bands: [ '2.4 GHz', '5 GHz' ]
} ], 'active AP collection and deduplication');
equal(common.collect(config.values, runtime).length, 1, 'RPC-unwrapped UCI response');

console.log('shared tests OK');
