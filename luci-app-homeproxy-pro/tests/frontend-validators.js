#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Frontend validators.
 *
 * The form snapshots record an option's kind, name, title, dependencies and
 * value list - a `validate` callback is a function, so it is not in the dump at
 * all.  Sharing the password validator between the two forms silently added the
 * 2022-blake3 key check to the node form (the server form had it, the node form
 * did not), and nothing in the suite would have noticed either way.
 *
 * So this drives the validators directly with a fake form context: a
 * behavioural test without a browser, since the callbacks only need
 * `this.section.formvalue`.
 *
 * A validator answers `true` or a non-empty message, and that message is a LuCI
 * String object (it carries `.format`), so the predicate is `!== true` with a
 * non-empty rendering rather than a typeof check.
 *
 * Usage: node tests/frontend-validators.js <repo-root>
 */

'use strict';

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

function isError(result) {
	return result !== true && result != null && String(result).length > 0;
}

const hp = loadLuciModule(
	path.join(root, 'htdocs/luci-static/resources/homeproxy-pro.js'),
	{
		baseclass: { extend: (o) => o },
		form: { DynamicList: { extend: (o) => o } },
		fs: {}, rpc: {}, uci: {}, ui: {}
	});

/* A 16 byte key encodes to 24 base64 characters; 32 bytes to 44.  These are the
 * lengths sing-box insists on for the 2022-blake3 ciphers. */
const KEY_128 = 'AAAAAAAAAAAAAAAAAAAAAA==';
const KEY_256 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
check('the 16-byte fixture is 24 characters', KEY_128.length === 24, String(KEY_128.length));
check('the 32-byte fixture is 44 characters', KEY_256.length === 44, String(KEY_256.length));

function run(validator, values, section_id) {
	const ctx = { section: { formvalue: (_id, name) => values[name] } };
	return validator.call(ctx, section_id === undefined ? 'sec1' : section_id, values.password);
}

function ss(method, password) {
	return { type: 'shadowsocks', shadowsocks_encrypt_method: method, password: password };
}

/* The two forms pass different protocol sets; use the values from the call
 * sites rather than inventing a third list. */
const CLIENT_TYPES = [ 'anytls', 'shadowsocks', 'shadowtls', 'snell', 'trojan' ];
const SERVER_TYPES = [ 'anytls', 'http', 'mixed', 'naive', 'shadowsocks', 'snell', 'socks', 'trojan' ];

for (const [label, types] of [['client', CLIENT_TYPES], ['server', SERVER_TYPES]]) {
	const validate = hp.validatePassword(types);

	check(`${label}: rejects an empty value for a protocol this side requires`,
		isError(run(validate, { type: 'trojan', password: '' })));
	check(`${label}: accepts an empty value for a protocol this side does not require`,
		run(validate, { type: 'vless', password: '' }) === true);
	check(`${label}: no section means no validation`,
		run(validate, { type: 'trojan', password: '' }, null) === true);

	/* The shadowsocks 'none' cipher legitimately has no password. */
	check(`${label}: shadowsocks with the 'none' cipher accepts an empty value`,
		run(validate, ss('none', '')) === true);
	check(`${label}: shadowsocks with a real cipher rejects an empty value`,
		isError(run(validate, ss('aes-128-gcm', ''))));

	/* The check the node form was missing until the validator was shared. */
	check(`${label}: 2022-blake3-aes-128-gcm rejects the 44 character key`,
		isError(run(validate, ss('2022-blake3-aes-128-gcm', KEY_256))));
	check(`${label}: 2022-blake3-aes-128-gcm accepts the 24 character key`,
		run(validate, ss('2022-blake3-aes-128-gcm', KEY_128)) === true);
	check(`${label}: 2022-blake3-aes-256-gcm rejects the 24 character key`,
		isError(run(validate, ss('2022-blake3-aes-256-gcm', KEY_128))));
	check(`${label}: 2022-blake3-aes-256-gcm accepts the 44 character key`,
		run(validate, ss('2022-blake3-aes-256-gcm', KEY_256)) === true);
	check(`${label}: 2022-blake3-chacha20-poly1305 uses the 44 character rule`,
		run(validate, ss('2022-blake3-chacha20-poly1305', KEY_256)) === true);
	check(`${label}: a non-base64 value is rejected for a 2022 cipher`,
		isError(run(validate, ss('2022-blake3-aes-128-gcm', 'not base64 at all'))));
}

/* validateBase64Key on its own, since the shared validator delegates to it. */
check('validateBase64Key accepts the correct length', hp.validateBase64Key(24, 'sec1', KEY_128) === true);
check('validateBase64Key rejects the wrong length', isError(hp.validateBase64Key(24, 'sec1', KEY_256)));
check('validateBase64Key ignores an empty value', hp.validateBase64Key(24, 'sec1', '') === true);
check('validateBase64Key ignores a missing section', hp.validateBase64Key(24, null, 'x') === true);
check('validateBase64Key rejects a value with no padding', isError(hp.validateBase64Key(24, 'sec1', 'A'.repeat(24))));

/* validateCertificatePath: the certificate policy has to be the same list the
 * backend enforces (CERT_PATH_ROOTS in homeproxy-pro.uc; guard 29 compares them
 * textually). A path the UI accepts and the backend drops used to make
 * certificate_path null silently, so the TLS listener failed with nothing
 * pointing at the path. The `..` rejection matters on its own: a prefix match
 * alone accepts /etc/ssl/../shadow, and sing-box opens these files as root. */
check('cert path accepts /etc/homeproxy-pro/certs/',
	hp.validateCertificatePath('sec1', '/etc/homeproxy-pro/certs/srv.pem') === true);
check('cert path accepts /etc/acme/',
	hp.validateCertificatePath('sec1', '/etc/acme/example.com/cert.pem') === true);
check('cert path accepts /etc/ssl/',
	hp.validateCertificatePath('sec1', '/etc/ssl/certs/srv.pem') === true);
check('cert path rejects /etc/passwd',
	isError(hp.validateCertificatePath('sec1', '/etc/passwd')));
check('cert path rejects a traversal segment',
	isError(hp.validateCertificatePath('sec1', '/etc/ssl/../shadow')));
check('cert path rejects a bare root',
	isError(hp.validateCertificatePath('sec1', '/etc/ssl/')));
check('cert path rejects a relative path',
	isError(hp.validateCertificatePath('sec1', 'etc/ssl/srv.pem')));
check('cert path ignores an empty value',
	hp.validateCertificatePath('sec1', '') === true);
check('cert path ignores a missing section',
	hp.validateCertificatePath(null, '/etc/passwd') === true);

/* --- dns_server: the legacy 'wan' value has to stay acceptable ---------- *
 * The preset-mode "Overseas DNS server" field used to offer a 'wan' entry
 * ("WAN DNS (read from interface)").  The entry is gone from the dropdown -
 * the ISP resolver is the one thing that must not be picked there - but the
 * literal is what a configuration saved back then still carries, and the
 * generator keeps mapping it to wan_dns
 * (root/etc/homeproxy-pro/scripts/generator/context.uc).  Dropping the entry
 * without keeping the validator in step made those configurations unsaveable:
 * every field's validator runs on save, and 'wan' is neither a hostname nor
 * an address, so the page refused to save a configuration that was working.
 *
 * The callback is inline in renderDnsCache(), so the form is rendered against
 * a minimal Section mock and the stored validate is called the way a widget
 * calls it - with the config section id, not null.
 */
function dnsServerValidate() {
	const classes = [ 'Value', 'ListValue', 'Flag', 'DynamicList', 'MultiValue', 'TextValue',
		'Button', 'TypedSection', 'NamedSection', 'GridSection', 'SectionValue' ];
	const formMock = {};
	for (const name of classes) {
		formMock[name] = class {};
		formMock[name].__name__ = name;
	}

	let captured = null;
	const sectionMock = {
		tab() {},
		taboption(_tab, kind, name, title, description) { return this.option(kind, name, title, description); },
		option(kind, name, title, description) {
			const option = { kind, name, title, description, value() {}, depends() {} };
			if (kind && kind.__name__ === 'SectionValue')
				option.subsection = sectionMock;
			if (name === 'dns_server')
				captured = option;
			return option;
		}
	};

	const dns = loadLuciModule(
		path.join(root, 'htdocs/luci-static/resources/view/homeproxy-pro/client/dns.js'),
		{
			baseclass: { extend: (o) => o },
			form: formMock,
			uci: { load: () => {}, get: () => undefined },
			homeproxy-pro: {},
			'view.homeproxy-pro.client.common': {}
		});

	/* Only the datatypes this validator asks for are implemented.  A stub
	 * that accepted everything would also pass the 'wan' check below, which
	 * is why the empty-value and not-an-address checks are here too. */
	const stubValidator = {
		value: null,
		apply(type, value) {
			if (value != null)
				this.value = value;
			switch (type) {
			case 'ip4addr':
				return /^\d{1,3}(\.\d{1,3}){3}$/.test(this.value) &&
					this.value.split('.').every((octet) => parseInt(octet, 10) <= 255);
			case 'ip6addr':
				return typeof this.value === 'string' && this.value.includes(':');
			case 'ipaddr':
				return this.apply('ip4addr', this.value) || this.apply('ip6addr', this.value);
			case 'hostname':
				return /^[A-Za-z0-9.-]+$/.test(this.value) &&
					!/^\d{1,3}(\.\d{1,3}){3}$/.test(this.value);
			default:
				return true;
			}
		},
		assert: (condition) => !!condition
	};

	dns.renderDnsCache({ s: sectionMock, stubValidator });

	const validator = captured && captured.validate;
	if (typeof validator !== 'function')
		throw new Error('dns.js no longer registers a dns_server validator');

	const ctx = { section: { formvalue: () => '0' } };
	return (value) => validator.call(ctx, 'config', value);
}

const validateDnsServer = dnsServerValidate();

check("dns_server accepts the legacy 'wan' literal the generator still maps",
	validateDnsServer('wan') === true);
check('dns_server still accepts a bare IP', validateDnsServer('1.1.1.1') === true);
check('dns_server still accepts a DoH endpoint',
	validateDnsServer('https://cloudflare-dns.com/dns-query') === true);
check('dns_server still rejects an empty value', isError(validateDnsServer('')));
check('dns_server still rejects a value that is neither a hostname nor an address',
	isError(validateDnsServer('not a dns server')));

console.log(`frontend validators: ${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
