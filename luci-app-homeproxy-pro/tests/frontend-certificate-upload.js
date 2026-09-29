#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * The certificate upload buttons: which staging path do they actually write?
 *
 * `hp.uploadCertificate` derives its staging path from the *second* argument
 * the call site binds - the UCI option name:
 *
 *     const tmpPath = '/tmp/homeproxy_cert_' + filename + '.tmp';
 *
 * L.bind() prepends the bound arguments, and LuCI's form.Button calls
 * `onclick(ev, section_id)` (form.js renderWidget), so the event lands on the
 * handler's *first* parameter.  A handler that declares a leading parameter no
 * caller passes therefore shifts everything by one: filename becomes the event
 * object, the path becomes /tmp/homeproxy_cert_[object Event].tmp, and both the
 * ACL whitelist (acl.d/luci-app-homeproxy-pro.json) and certificate_write
 * (luci.homeproxy-pro, which reads /tmp/homeproxy_cert_${filename}.tmp) stop
 * matching.  Every upload fails and the UI only shows a generic error.
 *
 * The unit under test is the *argument alignment*, not the handler body, so
 * this test wires each real call site's arguments exactly as the view does and
 * checks the path and the RPC filename that come out.
 *
 * Usage: node tests/frontend-certificate-upload.js <repo-root>
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { loadLuciModule } = require('./lib/luci-module.js');

const root = path.resolve(process.argv[2] || '.');

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

/* --- the call sites, read from the views --------------------------------- *
 * Parsed rather than hardcoded so a renamed button, a changed UCI option name
 * or a different binding shape is exercised as it is today. */
const VIEWS = [ 'node.js', 'server.js' ];
const calls = [];
for (const view of VIEWS) {
	const file = path.join(root, 'htdocs/luci-static/resources/view/homeproxy-pro', view);
	const src = fs.readFileSync(file, 'utf8');
	const re = /L\.bind\(hp\.uploadCertificate[^;]*\)/g;
	let m;
	while ((m = re.exec(src)) !== null)
		calls.push({ view, text: m[0] });
}

check('the certificate upload buttons were found', calls.length === 4,
	`expected 4 L.bind(hp.uploadCertificate ...) call sites, found ${calls.length}`);

/* Turn `L.bind(hp.uploadCertificate, hp, _('certificate'), 'client_ca')` into
 * ['certificate', 'client_ca']: the arguments the view binds, in order. */
function boundArgs(text) {
	const inner = text.replace(/^L\.bind\(hp\.uploadCertificate\s*,\s*hp\s*,?/, '').replace(/\)$/, '');
	const args = [];
	const re = /_\(\s*'([^']*)'\s*\)|'([^']*)'|"([^"]*)"|([A-Za-z_$][\w$]*)|(\d+)/g;
	let m;
	while ((m = re.exec(inner)) !== null) {
		if (m[1] !== undefined || m[2] !== undefined || m[3] !== undefined)
			args.push(m[1] ?? m[2] ?? m[3]);
		else
			args.push(m[4] !== undefined ? { identifier: m[4] } : Number(m[5]));
	}
	return args;
}

const parsed = calls.map((c) => ({ ...c, args: boundArgs(c.text) }));

/* --- load homeproxy-pro.js the way LuCI does ---------------------------------- */
const uploads = [];
const rpcCalls = [];

const L = {
	bind(fn, self, ...bound) {
		return fn.bind(self, ...bound);
	}
};

/* The recording ui stub goes in the deps record: that is the object the
 * module's own `'require ui'` resolves to (the loader's runtime argument only
 * supplies the _ / E / L globals). */
const uiStub = {
	addNotification: () => {},
	showModal: () => {},
	hideModal: () => {},
	uploadFile: (target, fileEl) => {
		uploads.push({ target, fileEl });
		return Promise.resolve({ size: 1 });
	},
	createHandlerFn: (self, fn) => fn
};

const hp = loadLuciModule(
	path.join(root, 'htdocs/luci-static/resources/homeproxy-pro.js'),
	{
		baseclass: { extend: (o) => o },
		form: { DynamicList: { extend: (o) => o } },
		fs: {}, rpc: {}, uci: {}, ui: uiStub
	},
	{ L, E: () => null }
);

check('homeproxy-pro.js exposes uploadCertificate', typeof hp.uploadCertificate === 'function',
	typeof hp.uploadCertificate);

/* --- drive each call site the way form.js does ---------------------------- */
async function run() {
	for (const call of parsed) {
		const label = `${call.view}: ${call.text}`;
		const handler = L.bind(hp.uploadCertificate, Object.assign({}, hp, {
			rpcCall: (method, params) => {
				rpcCalls.push({ method, params });
				return Promise.resolve({ result: true });
			}
		}), ...call.args);

		uploads.length = 0;
		rpcCalls.length = 0;

		/* form.js: ui.createHandlerFn(this, (section_id, ev) => this.onclick(ev, section_id), section_id)
		 * L.bind prepends, so the handler is invoked with (event, section_id). */
		const fakeFile = { name: 'cert.pem' };
		const ev = { target: { files: [ fakeFile ], value: 'C:\\fakepath\\cert.pem' } };
		await handler(ev, 'cfg01');

		const want = call.args[1];
		const got = uploads.length === 1 ? uploads[0].target : null;
		check(`${label}: uploads to /tmp/homeproxy_cert_${want}.tmp`,
			got === `/tmp/homeproxy_cert_${want}.tmp`, String(got));

		const rpc = rpcCalls.length === 1 ? rpcCalls[0] : null;
		check(`${label}: certificate_write receives the same name`,
			rpc && rpc.method === 'certificate_write' && rpc.params && rpc.params[0] === want,
			rpc ? JSON.stringify(rpc) : 'no rpcCall');
	}
}

run().then(() => {
	console.log(`${checks - failures}/${checks} checks passed`);
	if (failures) {
		console.error('FRONTEND CERTIFICATE UPLOAD TEST FAILED');
		process.exit(1);
	}
	console.log('FRONTEND CERTIFICATE UPLOAD TEST PASSED');
	process.exit(0);
});
