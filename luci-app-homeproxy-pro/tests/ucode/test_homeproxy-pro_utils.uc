#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * Regression tests for homeproxy-pro.uc helpers, focused on executeCommand():
 * return shape, stderr/exit-code capture, binary detection and (most
 * importantly) that the temporary descriptors are closed on every run.
 */

'use strict';

import { lsdir } from 'fs';
import { executeCommand, fetchBinary, isValidCIDR, isValidPEM, redactReason, redactUrl, ruleSetFormatFromBytes,
	ruleSetFormatFromPath, RULESET_PROBE_BYTES, shellQuote, wGETVerbose } from 'homeproxy-pro';

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

/* wGETVerbose() must not hand the fetcher an option the fetcher does not
 * have.
 *
 * This guard already existed once, for --max-filesize, and then failed to catch
 * the same class again: the fetch shelled out to `wget` with GNU-only options
 * (-nv --user-agent --timeout=), and `wget` is whichever implementation the
 * firmware's buildroot compiled.  On a busybox-wget router every one of those is
 * rejected with "unrecognized option" before a request is made, so every
 * subscription fetch, every resource update and the connectivity check failed -
 * while this test ran against GNU wget on CI and on the maintainer's own
 * device, and stayed green.
 *
 * So the guard now runs against tests/fixtures/uclient-fetch-stub, which
 * accepts exactly the option list read off the applet on a real device and
 * rejects everything else the way the applet does.  The accepted set is PINNED
 * rather than inherited from the host, which is the part that was missing.
 * (On a target, where /bin/uclient-fetch really exists, fetchBinary() returns
 * it and these same assertions run against the real applet - so an option
 * nobody verified is caught both off-target and on it.)
 *
 * A closed local port makes the fetch fail fast either way; what is asserted is
 * that it fails for a NETWORK reason and not a usage one. */
const fetch = wGETVerbose('http://127.0.0.1:1/never');
expect('fetch.not-a-usage-error',
	match(fetch.error || '', /unrecognized option|invalid option|Usage:/) == null, true);
expect('fetch.reports-a-reason', length(fetch.error || '') > 0, true);
expect('fetch.no-content-on-failure', fetch.content, null);

/* The binary and HTTP-error shapes below have to be PRODUCED by the fetcher, so
 * which fetcher is in play decides which URL can produce them.
 *
 * Off-target fetchBinary() resolves to the stub, which manufactures both shapes
 * from a magic path in the URL.  On a target it returns the real applet, and a
 * real applet only produces them by talking to a real server - a magic path
 * just looks like an ordinary URL it fails to connect to, which is why these
 * three used to fail there.  run.sh starts a throwaway uhttpd for exactly this
 * and passes its base URL in HP_T_HTTP_BASE.
 *
 * A real applet with no server (no uhttpd, every candidate port taken) cannot
 * be driven at all: report the three as skipped rather than failing, and never
 * let them read as a pass. */
const fetchBin = fetchBinary();
const realApplet = substr(fetchBin, 0, 1) === '/';
const httpBase = getenv('HP_T_HTTP_BASE') || '';
const canDriveFetchShapes = httpBase || !realApplet;
if (realApplet && !httpBase)
	printf('SKIP: binary / HTTP-error fetch shapes (real applet, no local server)\n');

/* A 200 whose body is binary.  executeCommand() nulls stdout for binary
 * content, and the "no content but stderr said something" branch then used to
 * report it as `fetch failed: … Download completed (34185 bytes)` - a message
 * that contradicts itself and sends the user after a network problem they do
 * not have.  Measured on a device against a real .srs. */
if (canDriveFetchShapes) {
	const binURL = httpBase ? `${httpBase}/hp-binary.srs` : 'http://127.0.0.1:1/HP_T_STUB_BINARY';
	const binfetch = wGETVerbose(binURL);
	expect('fetch.binary-is-not-a-failure',
		match(binfetch.error || '', /fetch failed/) == null, true, binfetch.error);
	expect('fetch.binary-says-so',
		match(binfetch.error || '', /binary/) != null, true, binfetch.error);
	expect('fetch.binary-has-no-content', binfetch.content, null);
}

/* A truncated transfer must not look like a subscription.
 *
 * The fetch used to be `uclient-fetch -O - | head -c N`, and system() returns
 * the last command's status - head's, always 0.  A response that declared 244
 * bytes and delivered 80 therefore arrived as `{ content: <80 bytes>, error:
 * null }`: a half-downloaded list would rewrite the node set and nothing
 * anywhere said so.  wGETVerbose() now carries the fetcher's own status out of
 * the pipeline through a file, and this is the shape that proves it.
 *
 * The stub is the only thing that can produce "non-empty body AND non-zero
 * exit" (a real uhttpd sets Content-Length from the file it serves), so on a
 * real-applet run this is skipped on purpose - the same path was measured by
 * hand on the device with a truncated response: real uclient-fetch exits 4
 * with "Connection reset prematurely" and wGETVerbose() reports
 * `fetch exited with status 4: …`. */
if (canDriveFetchShapes) {
	if (realApplet) {
		printf('SKIP: truncated-transfer shape (the real applet cannot be asked for a short body; device-verified by hand)\n');
	} else {
		const truncfetch = wGETVerbose('http://127.0.0.1:1/HP_T_STUB_TRUNCATED');
		expect('fetch.truncated-is-not-a-success', truncfetch.content, null);
		expect('fetch.truncated-reports-the-status',
			match(truncfetch.error || '', /status 4/) != null, true, truncfetch.error);
	}
}

/* Review H3: the fetcher announces the requested URL on stderr before it reports
 * anything else, query string and all, so this is what would reach the log.
 *
 * The old version of this test pointed at a *connection* failure, where the URL
 * happens not to appear - which meant it proved only that the quiet path stayed
 * quiet, never that redaction ran.  The stub announces the URL the way the real
 * applet does, so this now exercises redactReason() through the whole
 * wGETVerbose() path.  The redactReason() block below still covers redaction on
 * its own, against shapes no stub can be asked to produce. */
const tokfetch = wGETVerbose('http://127.0.0.1:1/?token=secret');
expect('fetch.token-not-in-error',
	match(tokfetch.error || '', /token=secret/) == null, true);
/* Redaction must not swallow the diagnostic: the target host still has to be
 * readable, or the message says nothing about what was being fetched. */
expect('fetch.redacted-still-names-the-target',
	match(tokfetch.error || '', /127\.0\.0\.1/) != null, true, tokfetch.error);

/* The HTTP-error shape is the one that leaks - "Downloading '<URL>'" followed
 * by "HTTP error 404" - and it is the common case for a subscription URL that
 * has expired. */
if (canDriveFetchShapes) {
	const errURL = httpBase ? `${httpBase}/hp-missing?token=secret` : 'http://127.0.0.1:1/HP_T_STUB_HTTP_ERROR?token=secret';
	const httpfetch = wGETVerbose(errURL);
	expect('fetch.http-error-token-not-in-error',
		match(httpfetch.error || '', /token=secret/) == null, true);
	expect('fetch.http-error-keeps-the-status',
		match(httpfetch.error || '', /HTTP error/) != null, true, httpfetch.error);
}

/* redactReason(): central redaction that protects every wGETVerbose caller.
 * Tested in isolation so the assertion does not depend on any fetcher being
 * present - this runs anywhere ucode runs. */
{
	/* The shape uclient-fetch actually emits, copied from a device run:
	 *
	 *   Downloading 'https://user:tok@host.example.com/path?q=token=secret'
	 *   HTTP error 404
	 *
	 * It announces the target BEFORE it says anything else, which is why
	 * wGETVerbose does not pass -q - and it is therefore the shape that has
	 * to be redacted.  The URL must lose its query string and its userinfo,
	 * and the host has to survive, or the message says nothing about what was
	 * being fetched. */
	const r1 = redactReason("Downloading 'https://user:tok@host.example.com/path?q=token=secret' HTTP error 404");
	expect('redactReason.query',
		match(r1, /\?\*\*\*/) != null, true, r1);
	expect('redactReason.userinfo',
		match(r1, /user:tok/) == null, true, r1);
	expect('redactReason.host-preserved',
		match(r1, /host\.example\.com/) != null, true, r1);
	expect('redactReason.reason-preserved',
		match(r1, /HTTP error 404/) != null, true, r1);

	/* A second URL in the same message - both must be redacted. */
	const r2 = redactReason('first https://a.example/?token=A then https://b.example/?token=B end');
	expect('redactReason.both-redacted',
		match(r2, /token=A/) == null && match(r2, /token=B/) == null, true);

	/* No URL at all: returned unchanged. */
	expect('redactReason.no-url-unchanged',
		redactReason('Failed to send request: Operation not permitted'),
		'Failed to send request: Operation not permitted');

	/* Empty / non-string: returned unchanged (the function is safe to
	 * apply to the trimmed stderr without a guard). */
	expect('redactReason.empty',       redactReason(''),    '');
	expect('redactReason.null',        redactReason(null),  null);
	expect('redactReason.non-string',  redactReason(123),   123);

	/* URL with port: the port must survive (the path is what we keep;
	 * only query and userinfo go). */
	const r3 = redactReason("Downloading 'https://host:80080/path?q=token=secret' HTTP error 500");
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

/* --- the rule-set format probe -------------------------------------------
 *
 * Two pure functions, so the whole decision is testable without a file and
 * without sing-box: ruleSetFormatFromBytes() looks at bytes, and
 * ruleSetFormatFromPath() says what sing-box's extension inference would
 * have decided for a name.  The pairing is the point - the generator compares
 * the two (generator/ruleset.uc's resolveFormat) and only speaks when they
 * disagree - so a regression in either half has to show up here.
 *
 * "SRS" is 0x53 0x52 0x53.  It is written as a literal because that IS the
 * byte sequence, and the test is about the function answering correctly for
 * the format's own identity, not about how the constant was spelled.
 *
 * Returns are 'binary' | 'source' | null, and the null cases carry most of
 * the weight: the probe must decline to have an opinion rather than guess,
 * because a guess here becomes a `format` declaration that makes sing-box
 * reject the configuration at startup. */
expect('probe: SRS magic is binary',       ruleSetFormatFromBytes('SRS' + 'x', 4), 'binary');
expect('probe: a three-byte SRS is binary', ruleSetFormatFromBytes('SRS', 3), 'binary');
expect('probe: a JSON object is source',   ruleSetFormatFromBytes('{"version":3,"rules":[]}', 21), 'source');
/* Leading whitespace is the normal shape of a file written by an editor or a
 * Windows tool, and the decision must not depend on byte 0 being '{'. */
expect('probe: leading whitespace is still source',
	ruleSetFormatFromBytes('\n\t  {"version":3}', 14), 'source');
expect('probe: a JSON array is source',    ruleSetFormatFromBytes('[{"a":1}]', 8), 'source');

/* Every null case is a "do not touch the user's field" case. */
expect('probe: an empty file is no verdict',  ruleSetFormatFromBytes('', 0), null);
expect('probe: a failed read is no verdict',   ruleSetFormatFromBytes('', 10), null);
expect('probe: two bytes are not the magic',   ruleSetFormatFromBytes('SR', 2), null);
expect('probe: a near-miss magic is no verdict', ruleSetFormatFromBytes('SRX', 3), null);
/* The one that matters most: prose is text and is still not a source
 * rule-set.  If "looks like text" were the test, this would answer 'source'
 * and the generated config would name a JSON file that does not exist. */
expect('probe: printable text is no verdict',  ruleSetFormatFromBytes('hello world', 11), null);
/* What a failed download actually leaves behind under a .srs name. */
expect('probe: an HTML error page is no verdict',
	ruleSetFormatFromBytes('<!DOCTYPE html><html></html>', 27), null);

expect('probe: the read window is a sane size',
	RULESET_PROBE_BYTES >= 8 && RULESET_PROBE_BYTES <= 4096, true);

/* What sing-box's extension inference would have decided, expressed in the
 * same two values.  null is the case that produces "missing format" rather
 * than a wrong parse, and it is the reason a content probe is worth having. */
expect('inference: .srs is binary',   ruleSetFormatFromPath('/etc/homeproxy-pro/ruleset/example.srs'), 'binary');
expect('inference: .json is source',  ruleSetFormatFromPath('/etc/homeproxy-pro/ruleset/example.json'), 'source');
expect('inference: no extension has no verdict', ruleSetFormatFromPath('/etc/homeproxy-pro/ruleset/example'), null);
/* The suffix is what counts, not the first dot in the name. */
expect('inference: .srs.txt is no verdict', ruleSetFormatFromPath('/etc/homeproxy-pro/ruleset/x.srs.txt'), null);
expect('inference: the suffix is case-sensitive', ruleSetFormatFromPath('/etc/homeproxy-pro/ruleset/x.SRS'), null);
/* A {tag} placeholder comes before the suffix, so it must not hide it. */
expect('inference: a {tag} path keeps its suffix', ruleSetFormatFromPath('/etc/homeproxy-pro/ruleset/{tag}.srs'), 'binary');
expect('inference: null has no verdict',  ruleSetFormatFromPath(null), null);
expect('inference: an empty path has no verdict', ruleSetFormatFromPath(''), null);

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
