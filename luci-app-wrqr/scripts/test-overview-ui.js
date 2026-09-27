'use strict';

const fs = require('fs');
const vm = require('vm');

let replacements = 0;
let qrRenders = 0;

function node(tag, attrs, children) {
	return {
		tag, attrs: attrs || {}, children: children || []
	};
}

function evaluate(path, context) {
	return vm.runInNewContext(`(function(){${fs.readFileSync(path, 'utf8')}\n})()`, context);
}

const common = evaluate('luci/shared.js', {
	baseclass: { extend: value => value }, encodeURIComponent
});
const rpcCalls = [];
const context = {
	baseclass: { extend: value => value },
	common,
	dom: { content: (target, next) => { replacements++; target.children = next; } },
	uqr: { renderSVG: value => {
		qrRenders++;
		return `<svg xmlns="http://www.w3.org/2000/svg" width="148" height="148">${value}</svg>`;
	} },
	rpc: { declare: spec => (...args) => { rpcCalls.push([spec.object, spec.method, args]); return Promise.resolve({}); } },
	L: { resolveDefault: promise => promise },
	Promise,
	E: (tag, attrs, children) => node(tag, attrs, children)
};
const widget = evaluate('luci/overview.js', context);

const config = { values: {
	radio0: { '.type': 'wifi-device', band: '5g' },
	ap0: { '.type': 'wifi-iface', device: 'radio0', mode: 'ap', ssid: 'Home', encryption: 'sae-mixed', key: 'secret' }
} };
const running = { radio0: { up: true, interfaces: [
	{ section: 'ap0', ifname: 'phy0-ap0', config: { mode: 'ap' } }
] } };

const firstRoot = widget.render([ config, running ]);
if (replacements !== 1 || qrRenders !== 1)
	throw new Error('first render did not create exactly one QR snapshot');
const qrMarkup = firstRoot.children[1].children[0].children[2].children[0].tag;
if (!qrMarkup.includes('viewBox="0 0 148 148"') || qrMarkup.includes(' width="148"'))
	throw new Error('QR SVG was not converted to a scalable viewBox');

replacements = 0;
qrRenders = 0;
const secondRoot = widget.render([ config, running ]);
if (secondRoot !== firstRoot)
	throw new Error('polling replaced the stable widget root');
if (replacements !== 0 || qrRenders !== 0)
	throw new Error('unchanged poll mutated or regenerated the widget');

const stopped = { radio0: { up: false, interfaces: [] } };
widget.render([ config, stopped ]);
if (replacements !== 1)
	throw new Error('runtime change was not rendered');

widget.load().then(() => {
	if (JSON.stringify(rpcCalls.map(call => call.slice(0, 2))) !==
	    JSON.stringify([ [ 'uci', 'get' ], [ 'luci-rpc', 'getWirelessDevices' ] ]))
		throw new Error('load did not refresh configuration and runtime state');
	console.log('overview UI tests OK');
}).catch(error => {
	console.error(error.message);
	process.exit(1);
});
