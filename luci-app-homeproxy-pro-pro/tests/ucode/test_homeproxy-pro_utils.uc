#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * Regression tests for homeproxy.uc helpers, focused on executeCommand():
 * return shape, stderr/exit-code capture, binary detection and (most
 * importantly) that the temporary descriptors are closed on every run.
 */

'use strict';

import { lsdir } from 'fs';
import { executeCommand, isValidCIDR, isValidPEM, redactReason, redactUrl, shellQuote, wGETVerbose } from 'homeproxy';

let failures = 0,
    checks = 0;

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL %s: expected %J, got %J\n', name, want, actual);
		failures++;
	}
}

function fd_count() {
	let n = 0;
	for (let _entry in lsdir('/proc/self/fd'))
		n++;
	return n;
}

/* successful command */
const ok = executeCommand('echo', 'hello');
expect('ok.exitcode', ok.exitcode, 0);
expect('ok.stdout', ok.stdout, 'hello\n');
expect('ok.stderr', ok.stderr, '');
expect('ok.binary', ok.binary, false);
expect('ok.command', ok.command, 'echo hello');

/* failing command keeps stderr and the exit code */
const bad = executeCommand('sh', '-c', shellQuote('echo oops >&2; exit 3'));
expect('bad.exitcode', bad.exitcode, 3);
expect('bad.stderr', bad.stderr, 'oops\n');
expect('bad.stdout', bad.stdout, '');

/* nondescript exit code */
expect('false.exitcode', executeCommand('false').exitcode, 1);

/* binary output is detected and withheld */
const bin = executeCommand('sh', '-c', shellQuote('printf "\\001\\002\\003"'));
expect('bin.binary', bin.binary, true);
expect('bin.stdout', bin.stdout, null);

/* executeCommand() must be able to return one byte past HP_FETCH_CAP, or
 * wGETVerbose()'s "response exceeds the limit" branch can never fire: the
 * reader used to stop at 512 KiB, so every subscription between 512 KiB and
 * 5 MiB arrived at the parser as a truncated body with error: null - silently
 * truncated, and reported as complete.  600 KiB sits between the old reader
 * cap and HP_FETCH_CAP, so this fails on that code and passes on the fix. */
const BIG_LEN = 600 * 1024;
const big = executeCommand('sh', '-c', shellQuote('head -c ' + BIG_LEN + ' /dev/zero | tr "\\0" a'));
expect('big.exitcode', big.exitcode, 0);
expect('big.stdout.length', length(big.stdout || ''), BIG_LEN);

/* isValidPEM(): certificate vs private key, boundaries and body */
const pem_cert = '-----BEGIN CERTIFICATE-----\nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n-----END CERTIFICATE-----';
const pem_key = '-----BEGIN RSA PRIVATE KEY-----\nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n-----END RSA PRIVATE KEY-----';
expect('pem.cert', isValidPEM(pem_cert, false), true);
expect('pem.cert-as-key', isValidPEM(pem_cert, true), false);
expect('pem.key', isValidPEM(pem_key, true), true);
expect('pem.key-as-cert', isValidPEM(pem_key, false), false);
expect('pem.garbage', isValidPEM('not a pem at all', false), false);
expect('pem.empty', isValidPEM('', false), false);

/* wGETVerbose() must not hand wget an option the target's wget does not have.
 * It used to pass --max-filesize, which busybox wget does not support: wget
 * exited 2 with "unrecognized option" before making a request, so every
 * subscription fetch failed while the test suite stayed green (the fetcher
 * tests mock wGETVerbose itself).  A closed local port makes the fetch fail
 * fast either way; what is asserted is that it fails for a network reason and
 * not a usage one. */
const wget = wGETVerbose('http://127.0.0.1:1/never');
expect('wget.not-a-usage-error',
	match(wget.error || '', /unrecognized option|invalid option|Usage:/) == null, true);
expect('wget.reports-a-reason', length(wget.error || '') > 0, true);
expect('wget.no-content-on-failure', wget.content, null);

/* Review H3: an HTTP-level wget failure echoes the target, query string and
 * all, so `<URL>?token=secret: 404 Not Found` is what would reach the log.
 * A *connection* failure is the cheap case to reproduce here, but wget prints
 * only `failed: Connection refused.` for it - no URL - so this fetch proves
 * the end-to-end path hands back no token, not that redaction ran.  The
 * redactReason() block below covers redaction itself, using the shapes wget
 * actually emits. */
const tokwget = wGETVerbose('http://127.0.0.1:1/?token=secret');
expect('wget.token-not-in-error',
	match(tokwget.error || '', /token=secret/) == null, true);

/* redactReason(): central redaction that protects every wGETVerbose caller.
 * Tested in isolation so the assertion does not depend on wget being
 * present - this runs anywhere ucode runs. */
{
	/* Canonical wget failure shape: '<URL>: <reason>' - the URL must lose
	 * its query string and userinfo. */
	const r1 = redactReason('https://user:tok@host.example.com/path?q=token=secret: Bad port \'80080\'.');
	expect('redactReason.query',
		match(r1, /\?\*\*\*/) != null, true);
	expect('redactReason.userinfo',
		match(r1, /user:tok/) == null, true);
	expect('redactReason.host-preserved',
		match(r1, /host\.example\.com/) != null, true);
	expect('redactReason.reason-preserved',
		match(r1, /Bad port/) != null, true);

	/* A second URL in the same message - both must be redacted. */
	const r2 = redactReason('first https://a.example/?token=A then https://b.example/?token=B end');
	expect('redactReason.both-redacted',
		match(r2, /token=A/) == null && match(r2, /token=B/) == null, true);

	/* No URL at all: returned unchanged. */
	expect('redactReason.no-url-unchanged',
		redactReason('wget: bad port'), 'wget: bad port');

	/* Empty / non-string: returned unchanged (the function is safe to
	 * apply to the trimmed stderr without a guard). */
	expect('redactReason.empty',       redactReason(''),    '');
	expect('redactReason.null',        redactReason(null),  null);
	expect('redactReason.non-string',  redactReason(123),   123);

	/* URL with port: the port must survive (the path is what we keep;
	 * only query and userinfo go). */
	const r3 = redactReason('wget: https://host:80080/path?q=token=secret: failed');
	expect('redactReason.port-survives',
		match(r3, /host:80080/) != null, true);
	expect('redactReason.port-query-redacted',
		match(r3, /token=secret/) == null, true);
}

/* isValidCIDR(): reject injection through the /boundary.  Previously the
 * prefix was checked with `int(prefix) < 0 || int(prefix) > 32`, which
 * let `int('24;}')` parse as 24 (strtoll stops at the first non-digit),
 * so a poisoned china_ip4.txt line like `1.2.3.4/24;}` sailed through
 * and ended up verbatim in the fw4 ruleset.  These cases pin both the
 * unanchored-injection reject and the basic shape coverage. */
expect('cidr4.basic',           isValidCIDR('1.2.3.4', 4),         true);
expect('cidr4.with-prefix',     isValidCIDR('1.2.3.4/24', 4),      true);
expect('cidr4.boundary-0',      isValidCIDR('0.0.0.0/0', 4),       true);
expect('cidr4.boundary-32',     isValidCIDR('255.255.255.255/32', 4), true);
expect('cidr4.octet-overflow',  isValidCIDR('1.2.3.999', 4),       false);
expect('cidr4.empty',           isValidCIDR('', 4),                false);
expect('cidr4.whitespace',      isValidCIDR('   ', 4),             false);
expect('cidr4.leading-space',   isValidCIDR(' 1.2.3.4', 4),        true);
expect('cidr4.bad-family',      isValidCIDR('1.2.3.4', 99),        false);
/* Injection vectors - the actual bug shape. */
expect('cidr4.prefix-injection',     isValidCIDR('1.2.3.4/24;}', 4),    false);
expect('cidr4.prefix-comment',       isValidCIDR('1.2.3.4/24 #evil', 4), false);
expect('cidr4.prefix-non-digit',     isValidCIDR('1.2.3.4/abc', 4),     false);
expect('cidr4.prefix-overflow',      isValidCIDR('1.2.3.4/33', 4),      false);
expect('cidr4.prefix-negative',      isValidCIDR('1.2.3.4/-1', 4),      false);
expect('cidr4.prefix-too-many',      isValidCIDR('1.2.3.4/12345', 4),   false);
expect('cidr4.two-slashes',          isValidCIDR('1.2.3.4/24/32', 4),   false);
expect('cidr4.empty-prefix',         isValidCIDR('1.2.3.4/', 4),        false);
expect('cidr4.tail-after-ip',        isValidCIDR('1.2.3.4 garbage', 4),  false);

/* IPv6: same anchor logic.  Compressed / uncompressed / invalid shapes. */
expect('cidr6.basic',           isValidCIDR('::1', 6),                 true);
expect('cidr6.uncompressed',    isValidCIDR('2001:db8::1', 6),         true);
expect('cidr6.full',            isValidCIDR('fe80::1/64', 6),          true);
expect('cidr6.boundary-128',    isValidCIDR('::1/128', 6),             true);
expect('cidr6.prefix-overflow', isValidCIDR('::1/129', 6),             false);
expect('cidr6.prefix-injection',isValidCIDR('::1/64;}', 6),            false);
expect('cidr6.two-colons',      isValidCIDR('1::2::3', 6),             false);
expect('cidr6.empty',           isValidCIDR('', 6),                    false);

/* descriptors must not leak across calls */
const before = fd_count();
for (let i = 0; i < 200; i++)
	executeCommand('true');
const after = fd_count();

checks++;
if (after > before) {
	printf('FAIL descriptor leak: %d -> %d after 200 calls\n', before, after);
	failures++;
}

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);
