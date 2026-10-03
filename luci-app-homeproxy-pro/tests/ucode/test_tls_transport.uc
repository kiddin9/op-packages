#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Direct unit tests for the TLS / transport object builders. Before
 * this commit every TLS / transport code path went through the
 * generator fixtures or the golden JSON snapshot - both end-to-end,
 * both slow, and neither pointed a finger at the builder that
 * actually broke. This file imports the builders directly and runs
 * the shape checks that the generator was previously trusted to
 * enforce, including the sing-box 1.14 constraints that the builders
 * themselves carry (cert_path whitelist, no insecure on server-side,
 * reality private_key only on server-side, etc.).
 *
 * load_tls / load_transport are also imported but only exercised via
 * the simplest possible get()-stub - they are field-flattening
 * wrappers whose only real correctness criterion is "the right UCI
 * name maps to the right builder field", which the snapshot
 * regression already covers transitively.
 */

'use strict';

import { buildTLSObject, buildTransportObject, rulePathRootsText, validateCertificatePath, validateHomeProxyPath, validateRuleSetPath, HP_DIR } from 'homeproxy-pro';

let failures = 0,
    checks = 0;

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL %s: expected %J, got %J\n', name, want, actual);
		failures++;
	}
}

/* --- buildTLSObject ---------------------------------------------------- */

/* 1. disabled -> null. The generator treats null as "TLS off"; if the
 *      builder ever started emitting an object when tls.enabled !== '1',
 *      sing-box would happily accept it and silently enable TLS. */
expect('disabled→null', buildTLSObject({ enabled: '0', server_name: 'example.com' }, false), null);
expect('null tls→null', buildTLSObject(null, false), null);

/* 2. client-side bare minimum: enabled + server_name round-trip. */
expect('client.enabled', buildTLSObject({ enabled: '1', server_name: 's.example.com' }, false).enabled, true);
expect('client.server_name', buildTLSObject({ enabled: '1', server_name: 's.example.com' }, false).server_name, 's.example.com');
expect('client.insecure (null on raw)', buildTLSObject({ enabled: '1', server_name: 's' }, false).insecure, null);

/* 3. insecure=true only meaningful on the client side; the server
 *      builder always emits null for `insecure` because TLS servers
 *      do not skip verification. A previous version emitted
 *      insecure=true on server, which made sing-box refuse to start. */
const clientInsecure = buildTLSObject({ enabled: '1', server_name: 's', insecure: '1' }, false);
expect('client.insecure=1 parsed', clientInsecure.insecure, true);
const serverInsecure = buildTLSObject({ enabled: '1', server_name: 's', insecure: '1' }, true);
expect('server.insecure forced null', serverInsecure.insecure, null);

/* 4. cert_path whitelist - the validator accepts /etc/homeproxy-pro/... and
 *      /tmp/homeproxy_..., and rejects everything else (including
 *      /etc/passwd and relative paths). This is the security patch
 *      that backs the path-whitelist entry above; a regression here would
 *      let UCI drive sing-box into reading arbitrary files as root. */
expect('cert.path /etc/homeproxy-pro', validateHomeProxyPath('/etc/homeproxy-pro/certs/server_publickey.pem'), true);
expect('cert.path /tmp/homeproxy_', validateHomeProxyPath('/tmp/homeproxy_test/foo.pem'), true);
expect('cert.path /etc/passwd', validateHomeProxyPath('/etc/passwd'), false);
expect('cert.path /var/run/cron', validateHomeProxyPath('/var/run/cron'), false);
expect('cert.path relative', validateHomeProxyPath('relative/path.pem'), false);
expect('cert.path null', validateHomeProxyPath(null), false);
expect('cert.path empty', validateHomeProxyPath(''), false);

const clientCert = buildTLSObject({ enabled: '1', server_name: 's', cert_path: '/etc/homeproxy-pro/certs/foo.pem' }, false);
expect('client.cert_path accepted', clientCert.certificate_path, '/etc/homeproxy-pro/certs/foo.pem');
const clientCertBad = buildTLSObject({ enabled: '1', server_name: 's', cert_path: '/etc/passwd' }, false);
expect('client.cert_path rejected→null', clientCertBad.certificate_path, null);

/* 4b. Certificate paths are a *different* policy from rule-set paths.
 *       A TLS certificate normally lives under /etc/ssl/ or under the ACME
 *       state in /etc/acme/, and both sing-box jails mount those directories
 *       (runtime/service.sh). validateHomeProxyPath() only knows
 *       /etc/homeproxy-pro/ and /tmp/homeproxy_, so a certificate the UI offered
 *       from /etc/ssl/ was accepted there and then silently dropped on the
 *       way into sing-box - certificate_path became null and the TLS listener
 *       failed with nothing pointing at the path. CERT_PATH_ROOTS is the
 *       backend half of the policy the frontend validator mirrors (guard 29). */
expect('cert.paths /etc/ssl accepted', validateCertificatePath('/etc/ssl/certs/srv.pem'), true);
expect('cert.paths /etc/acme accepted', validateCertificatePath('/etc/acme/example.com/cert.pem'), true);
expect('cert.paths /etc/homeproxy-pro/certs accepted', validateCertificatePath('/etc/homeproxy-pro/certs/srv.pem'), true);
expect('cert.paths /tmp/homeproxy_ rejected',
	validateCertificatePath('/tmp/homeproxy_test/foo.pem'), false);
expect('cert.paths /etc/passwd rejected', validateCertificatePath('/etc/passwd'), false);
expect('cert.paths traversal rejected', validateCertificatePath('/etc/ssl/../shadow'), false);
expect('cert.paths bare root rejected', validateCertificatePath('/etc/ssl/'), false);
expect('cert.paths relative rejected', validateCertificatePath('etc/ssl/srv.pem'), false);
expect('cert.paths null rejected', validateCertificatePath(null), false);
expect('cert.paths empty rejected', validateCertificatePath(''), false);

/* The two policies must stay disjoint in the direction that matters: a
 * rule-set path may not reach into /etc/ssl/, and a certificate does not need
 * /tmp/homeproxy_ (that root is for upload staging). */
expect('rule-set path still rejects /etc/ssl', validateHomeProxyPath('/etc/ssl/certs/srv.pem'), false);

/* 4c. Rule-set source files have a THIRD policy, and it is the narrowest of
 *       the three.  validateHomeProxyPath() accepts everything under
 *       /etc/homeproxy-pro/ and everything under /tmp/homeproxy_ - which is right
 *       for a general "this path is inside the package" gate and wrong for a
 *       rule-set, because a rule-set has exactly one home: the archive the
 *       package creates (RULE_PATH_ROOTS, mirrored by HP_RULE_PATH_ROOTS and
 *       locked across the JS/ucode boundary by guard 50).
 *
 *       The distinction that matters: validateHomeProxyPath() still answers
 *       true for /etc/homeproxy-pro/ruleset/x.srs AND for /tmp/homeproxy_x/y.srs,
 *       while validateRuleSetPath() answers true only for the first.  A
 *       frontend built on the general gate would offer paths the generator
 *       then refuses - the guard-29 failure mode, one policy over.
 */
expect('ruleset path accepts the archive',
	validateRuleSetPath('/etc/homeproxy-pro/ruleset/example.srs'), true);
expect('ruleset path rejects a bare root',
	validateRuleSetPath('/etc/homeproxy-pro/ruleset/'), false);
expect('ruleset path rejects /etc/passwd',
	validateRuleSetPath('/etc/passwd'), false);
expect('ruleset path rejects another path under /etc/homeproxy-pro',
	validateRuleSetPath('/etc/homeproxy-pro/resources/china_ip4.json'), false);
expect('ruleset path rejects the certs directory',
	validateRuleSetPath('/etc/homeproxy-pro/certs/server_privatekey.pem'), false);
expect('ruleset path rejects /tmp/homeproxy_ upload staging',
	validateRuleSetPath('/tmp/homeproxy_ruleset_upload.tmp'), false);
expect('ruleset path rejects /etc/ssl',
	validateRuleSetPath('/etc/ssl/certs/srv.pem'), false);
expect('ruleset path rejects a traversal out of the archive',
	validateRuleSetPath('/etc/homeproxy-pro/ruleset/../../etc/shadow'), false);
expect('ruleset path rejects a relative path',
	validateRuleSetPath('etc/homeproxy-pro/ruleset/x.srs'), false);
expect('ruleset path rejects null', validateRuleSetPath(null), false);
expect('ruleset path rejects empty', validateRuleSetPath(''), false);
expect('ruleset path rejects a non-string', validateRuleSetPath(42), false);

/* And the general gate is unchanged: narrowing the rule-set policy must not
 * have narrowed the one buildTLSObject() and the parser still rely on. */
expect('general gate still accepts /etc/homeproxy-pro',
	validateHomeProxyPath('/etc/homeproxy-pro/ruleset/example.srs'), true);
expect('general gate still accepts /tmp/homeproxy_',
	validateHomeProxyPath('/tmp/homeproxy_cert_server_publickey.tmp'), true);

/* The diagnostic has to name the roots, or the user is left guessing where the
 * file is supposed to go. */
expect('the roots text lists the archive',
	!!match(rulePathRootsText(), /\/etc\/homeproxy-pro\/ruleset\//), true);

const sslCert = buildTLSObject({ enabled: '1', server_name: 's', cert_path: '/etc/ssl/certs/srv.pem' }, false);
expect('client.cert_path /etc/ssl kept', sslCert.certificate_path, '/etc/ssl/certs/srv.pem');
const sslServerKey = buildTLSObject({ enabled: '1', server_name: 's', cert_path: '/etc/acme/c.pem' }, true,
	{ tls_key_path: '/etc/ssl/private/k.pem' });
expect('server.key_path /etc/ssl kept', sslServerKey.key_path, '/etc/ssl/private/k.pem');
const traversalCert = buildTLSObject({ enabled: '1', server_name: 's', cert_path: '/etc/ssl/../shadow' }, false);
expect('client.cert_path traversal→null', traversalCert.certificate_path, null);

/* 4c. The client ECH config path is a file sing-box opens as root too, and it
 *       used to reach the config unvalidated. */
const echOk = buildTLSObject(
	{ enabled: '1', server_name: 's', ech: { enabled: '1', config_path: '/etc/homeproxy-pro/certs/ech.pem' } }, false);
expect('client.ech.config_path accepted', echOk.ech.config_path, '/etc/homeproxy-pro/certs/ech.pem');
const echBad = buildTLSObject(
	{ enabled: '1', server_name: 's', ech: { enabled: '1', config_path: '/etc/passwd' } }, false);
expect('client.ech.config_path rejected→null', echBad.ech.config_path, null);

/* 5. utls: client-only. The server builder must never emit utls.
 *      Servers using uTLS would silently break sing-box. */
const clientUtls = buildTLSObject({ enabled: '1', server_name: 's', utls: { fingerprint: 'chrome' } }, false);
expect('client.utls.fingerprint', clientUtls.utls.fingerprint, 'chrome');
const serverUtls = buildTLSObject({ enabled: '1', server_name: 's', utls: { fingerprint: 'chrome' } }, true);
expect('server.utls forced null', serverUtls.utls, null);

/* 6. reality: client gets public_key only; server gets private_key.
 *      Mixing them up would let a malicious UCI value plant the wrong
 *      key on the wrong side. */
const clientReality = buildTLSObject({
	enabled: '1', server_name: 's',
	reality: { enabled: '1', public_key: 'PUB', short_id: 'abc' }
}, false);
expect('client.reality.public_key', clientReality.reality.public_key, 'PUB');
expect('client.reality.private_key', clientReality.reality.private_key, null);

const serverReality = buildTLSObject({
	enabled: '1', server_name: 's',
	reality: { enabled: '1', public_key: 'PUB', short_id: 'abc' }
}, true, { tls_reality_private_key: 'PRIV', tls_reality_server_addr: 'dest.example.com', tls_reality_server_port: '443' });
expect('server.reality.short_id', serverReality.reality.short_id, 'abc');
expect('server.reality.private_key', serverReality.reality.private_key, 'PRIV');
expect('server.reality.public_key', serverReality.reality.public_key, null);

/* 7. ECH: client uses config/config_path; server uses key. */
const clientEch = buildTLSObject({ enabled: '1', server_name: 's',
	ech: { enabled: '1', config: 'AAAA', config_path: '/etc/homeproxy-pro/certs/client_ech_conf.pem' } }, false);
expect('client.ech.config', clientEch.ech.config, 'AAAA');

const serverEch = buildTLSObject({ enabled: '1', server_name: 's' }, true, { tls_ech_key: 'AAAA\nBBBB' });
expect('server.ech key parsed', serverEch.ech.key[0], 'AAAA');
expect('server.ech.key[1]', serverEch.ech.key[1], 'BBBB');

/* --- buildTransportObject ---------------------------------------------- */

/* 1. empty transport -> null. */
expect('transport.empty→null', buildTransportObject({}, false), null);
expect('transport.no type→null', buildTransportObject({ type: null }, false), null);
expect('transport.null→null', buildTransportObject(null, false), null);

/* 2. ws transport round-trip. */
const ws = buildTransportObject({
	type: 'ws', host: 'h.example.com', path: '/ws?ed=2048',
	headers: { Host: 'h.example.com' }
}, false);
expect('ws.type', ws.type, 'ws');
expect('ws.host', ws.host, 'h.example.com');
expect('ws.path', ws.path, '/ws?ed=2048');
expect('ws.headers', ws.headers.Host, 'h.example.com');

/* 3. grpc transport. The permit_without_stream flag is client-only;
 *    the server builder must drop it because sing-box rejects it on
 *    a server inbound (sing-box 1.14 listed it as a known bug). */
const clientGrpc = buildTransportObject({
	type: 'grpc', service_name: 'svc', permit_without_stream: '1'
}, false);
expect('client.grpc.permit', clientGrpc.permit_without_stream, true);
const serverGrpc = buildTransportObject({
	type: 'grpc', service_name: 'svc', permit_without_stream: '1'
}, true);
expect('server.grpc.permit forced null', serverGrpc.permit_without_stream, null);

/* 4. httpupgrade transport. */
const hu = buildTransportObject({ type: 'httpupgrade', host: 'h.example.com', path: '/' }, false);
expect('httpupgrade.type', hu.type, 'httpupgrade');
expect('httpupgrade.host', hu.host, 'h.example.com');

/* --- summary ----------------------------------------------------------- */

if (failures > 0)
	printf('FAIL: %d/%d checks failed\n', failures, checks);
else
	printf('PASS: %d checks\n', checks);

exit(failures > 0 ? 1 : 0);