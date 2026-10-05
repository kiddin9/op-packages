#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Frontend protocol inventory.
 *
 * homeproxy-pro.js carries one ordered `protocols` table and both forms render
 * their type picker from it.  Before that table existed each form had its own
 * hand-written value list, and they had drifted in ways nothing could catch:
 * `snell` had a complete form block, a CREDENTIALS row and a golden outbound
 * but was not in the node form's list, so it could not be selected at all; the
 * node form offered `chacha20`, which sing-box rejects outright.
 *
 * The form snapshots cannot catch this class of bug - they record an option's
 * dependency and default, and the node form's picker lives in a subsection the
 * dump does not reach - so this test reads the table directly and compares it
 * with the backend tables that decide what the generators can actually build.
 *
 * Checks:
 *   1. every offered type is modelled by the backend (parser/mapping.uc
 *      PROTOCOL_TO_UCI) - the table that makes a protocol reachable from UCI;
 *   2. every protocol the outbound adapter can build (OPTION_FIELDS,
 *      REQUIRED_CREDENTIALS) is offered by the CLIENT form - "the backend
 *      supports it and the UI cannot select it" is the snell bug;
 *   3. every protocol offered by the SERVER form has inbound credentials
 *      (model.uc INBOUND_CREDENTIALS) - the reverse direction;
 *   4. the client and server lists match their expected order, because the
 *      order is part of the UI and filtering one table has to reproduce it;
 *   5. protocols the backend models but the UI deliberately does not offer are
 *      listed explicitly, so an accidental omission has to be added here (and
 *      this file is reviewed) rather than passing silently.
 *
 * Usage: node tests/frontend-protocol-inventory.js <repo-root>
 */

'use strict';

const fs = require('fs');
const path = require('path');

const { loadLuciModule } = require('./lib/luci-module.js');

const root = path.resolve(process.argv[2] || '.');
const scripts = path.join(root, 'root/etc/homeproxy-pro/scripts');

/* The registry is data plus the renderer; loading it through the whole LuCI
 * mock would test the mock.  `protocols` only needs the module to evaluate its
 * top-level statements, so the imports are stubbed just far enough for that. */
function loadHomeproxy() {
	return loadLuciModule(
		path.join(root, 'htdocs/luci-static/resources/homeproxy-pro.js'),
		{
			baseclass: { extend: (o) => o },
			form: { DynamicList: { extend: (o) => o } },
			fs: {}, rpc: {}, uci: {}, ui: {}
		});
}

/* Read the keys of one `export const NAME = { ... }` table.  Only depth-1 keys
 * count, so nested per-option maps and the `};` terminator are ignored. */
function tableKeys(file, name) {
	const lines = fs.readFileSync(file, 'utf8').split('\n');
	const head = new RegExp('^export const ' + name + '\\s*=\\s*\\{');
	let start = -1;
	for (let i = 0; i < lines.length; i++) {
		if (head.test(lines[i])) { start = i; break; }
	}
	if (start === -1)
		throw new Error(`table ${name} not found in ${file}`);

	const keys = [];
	let depth = 1;
	for (let i = start + 1; i < lines.length; i++) {
		const line = lines[i];
		if (depth === 1) {
			const m = /^\t([A-Za-z0-9_]+)\s*:/.exec(line);
			if (m) keys.push(m[1]);
		}
		for (const ch of line) {
			if (ch === '{') depth++;
			else if (ch === '}') depth--;
		}
		if (depth <= 0) break;
	}
	return keys;
}

/* Protocols whose table entry names `password`, for tables whose depth-1
 * entries are single lines (arrays in adapter.uc, objects in model.uc). */
function tableKeysWith(file, name, field) {
	const keys = tableKeys(file, name);
	const lines = fs.readFileSync(file, 'utf8').split('\n');
	const head = new RegExp('^export const ' + name + '\\s*=\\s*\\{');
	const found = [];
	let start = -1, depth = 0;

	for (let i = 0; i < lines.length; i++)
		if (head.test(lines[i])) { start = i; depth = 1; break; }
	if (start === -1)
		throw new Error('table ' + name + ' not found');

	for (let i = start + 1; i < lines.length; i++) {
		if (depth === 1) {
			const m = /^\t([A-Za-z0-9_]+)\s*:/.exec(lines[i]);
			if (m && keys.includes(m[1]) && new RegExp('(^|[^A-Za-z_])' + field + '([^A-Za-z_]|$)').test(lines[i]))
				found.push(m[1]);
		}
		for (const ch of lines[i]) {
			if (ch === '{') depth++;
			else if (ch === '}') depth--;
		}
		if (depth <= 0) break;
	}
	return found;
}

function validatorTypes(file) {
	const src = fs.readFileSync(file, 'utf8');
	const m = src.match(/validatePassword\(\s*\[([^\]]+)\]/);
	return m ? m[1].split(',').map((t) => t.trim().replace(/^['"]|['"]$/g, '')).filter(Boolean) : [];
}

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

const hp = loadHomeproxy();
const protocols = hp.protocols;
check('homeproxy-pro.js exports a protocols table', Array.isArray(protocols) && protocols.length > 0);
if (!Array.isArray(protocols)) {
	console.error(`\n${checks} checks, ${failures} failures`);
	process.exit(1);
}

const mapped = tableKeys(path.join(scripts, 'parser/mapping.uc'), 'PROTOCOL_TO_UCI');
const optionFields = tableKeys(path.join(scripts, 'config/adapter.uc'), 'OPTION_FIELDS');
const required = tableKeys(path.join(scripts, 'config/adapter.uc'), 'REQUIRED_CREDENTIALS');
const inboundCredentials = tableKeys(path.join(scripts, 'config/model.uc'), 'INBOUND_CREDENTIALS');
const credentials = tableKeys(path.join(scripts, 'config/model.uc'), 'CREDENTIALS');

const clientList = protocols.filter((p) => p.sides.includes('client')).map((p) => p.type);
const serverList = protocols.filter((p) => p.sides.includes('server')).map((p) => p.type);

check('mapping.uc PROTOCOL_TO_UCI parsed', mapped.length > 0, `${mapped.length} keys`);
check('adapter.uc OPTION_FIELDS parsed', optionFields.length > 0, `${optionFields.length} keys`);
check('adapter.uc REQUIRED_CREDENTIALS parsed', required.length > 0, `${required.length} keys`);
check('model.uc INBOUND_CREDENTIALS parsed', inboundCredentials.length > 0, `${inboundCredentials.length} keys`);

/* 1. Each side is checked against the table that makes it reachable there.
 *    The client side is the outbound half: PROTOCOL_TO_UCI is what the Loader
 *    reads options through.  The server side is the inbound half, which lives
 *    in model.uc's INBOUND_CREDENTIALS - server-only protocols such as naive
 *    and mixed legitimately have no outbound mapping at all. */
for (const p of protocols) {
	check(`'${p.type}' declares at least one side`, p.sides.length > 0);
	/* A label is now wrapped in _() at the table, so it is a translated
	 * String object rather than a primitive when a translation exists.  The
	 * property under test is that it is present and non-empty. */
	check(`'${p.type}' has a label`, p.label != null && String(p.label).length > 0);

	if (p.sides.includes('client'))
		check(`client '${p.type}' is modelled by the backend (PROTOCOL_TO_UCI)`, mapped.includes(p.type));

	if (p.sides.includes('server'))
		check(`server '${p.type}' has inbound credentials (INBOUND_CREDENTIALS)`, inboundCredentials.includes(p.type));
}

/* 2. Outbound-capable in the backend => selectable in the client form.  This
 *    is the direction that catches "the backend supports it and the UI cannot
 *    select it", which is how snell was lost. */
const outboundCapable = [...new Set([...optionFields, ...required])].sort();
for (const type of outboundCapable) {
	check(`outbound-capable '${type}' can be selected in the node form`, clientList.includes(type));
}

/* 4. The rendered order is part of the UI.  Pinned here because the form
 *    snapshots do not reach the node form's picker. */
const expectedClient = [
	'direct', 'anytls', 'http', 'hysteria', 'hysteria2',
	'shadowsocks', 'shadowtls', 'snell', 'socks', 'ssh',
	'trojan', 'tuic', 'wireguard', 'vless', 'vmess'
];
const expectedServer = [
	'anytls', 'http', 'hysteria', 'hysteria2', 'naive', 'mixed',
	'shadowsocks', 'snell', 'socks', 'trojan', 'tuic', 'vless', 'vmess'
];
check('client protocol order', JSON.stringify(clientList) === JSON.stringify(expectedClient),
	`got ${JSON.stringify(clientList)}`);
check('server protocol order', JSON.stringify(serverList) === JSON.stringify(expectedServer),
	`got ${JSON.stringify(serverList)}`);

/* 5. Deliberate omissions, spelled out.  A protocol the backend models but no
 *    form offers has to appear here; adding one to this list is a reviewable
 *    decision instead of a silent gap. */
const DELIBERATE = {
	/* The backend models the inbound side (INBOUND_CREDENTIALS,
	 * REQUIRED_INBOUND_CREDENTIALS, INBOUND_CLAIM_FIELDS) but the inbound
	 * generation path has no fixture/golden coverage, so the server form must
	 * not offer it until that exists.  The client form does offer it. */
	shadowtls: 'server side has no inbound fixture/golden coverage yet',
	/* Endpoint protocols: modelled and buildable, but the client form gates
	 * them behind runtime features (wireguard on with_wireguard+gvisor,
	 * direct is always offered).  Listed here because they are not part of
	 * the adapter's per-protocol OPTION_FIELDS tables. */
	wireguard: 'endpoint, gated on with_wireguard + with_gvisor',
	direct: 'endpoint, always offered by the client form'
};

const unmapped = [...new Set([...mapped, ...credentials, ...inboundCredentials])]
	.filter((t) => !clientList.includes(t) && !serverList.includes(t))
	.sort();
for (const type of unmapped) {
	check(`unoffered protocol '${type}' is a documented decision`, type in DELIBERATE,
		'models it in the backend but no form offers it');
}

/* --- the required-credential surface must be enforced before save ---------
 *
 * A protocol whose backend entry requires a password but whose form validator
 * does not check it can be saved empty; generation then dies and the user sees
 * "my setting did not take".  That is how hysteria2/tuic slipped through: the
 * empty password was accepted at save time and OutboundFactory.create() die()d
 * at generation time.  The validator lists live in the two view files, so they
 * are compared against the backend tables here. */
const clientNeedsPassword = new Set(tableKeysWith(path.join(scripts, 'config/adapter.uc'), 'REQUIRED_CREDENTIALS', 'password'));
const serverNeedsPassword = new Set(tableKeysWith(path.join(scripts, 'config/model.uc'), 'INBOUND_CREDENTIALS', 'password'));
const clientValidated = new Set(validatorTypes(path.join(root, 'htdocs/luci-static/resources/view/homeproxy-pro/node.js')));
const serverValidated = new Set(validatorTypes(path.join(root, 'htdocs/luci-static/resources/view/homeproxy-pro/server.js')));

check('adapter.uc REQUIRED_CREDENTIALS parsed for the password field', clientNeedsPassword.size > 0, [ ...clientNeedsPassword ].join(' '));
check('model.uc INBOUND_CREDENTIALS parsed for the password field', serverNeedsPassword.size > 0, [ ...serverNeedsPassword ].join(' '));

for (const type of clientList) {
	if (!clientNeedsPassword.has(type))
		continue;
	check(`client form validates the password that ${type} requires`, clientValidated.has(type),
		`${type} needs a password in adapter.uc but is missing from node.js's validatePassword list`);
}

for (const type of serverList) {
	if (!serverNeedsPassword.has(type))
		continue;
	check(`server form validates the password that ${type} requires`, serverValidated.has(type),
		`${type} needs a password in model.uc but is missing from server.js's validatePassword list`);
}

console.log(`frontend protocol inventory: ${checks} checks, ${failures} failures`);
console.log(`  client: ${clientList.join(' ')}`);
console.log(`  server: ${serverList.join(' ')}`);
if (unmapped.length)
	console.log(`  deliberately unoffered: ${unmapped.map((t) => `${t} (${DELIBERATE[t] || 'UNDOCUMENTED'})`).join(', ')}`);

process.exit(failures ? 1 : 0);
