#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Direct unit tests for subscription/fetcher.uc. The fetcher is a
 * thin wrapper around wGETVerbose (subscription byte fetch + log +
 * return), so the unit-testable surface is narrow:
 *
 *   - empty content (network error / wget returned no body):
 *     - logs the failure with a redacted URL
 *     - returns { content: null, error: '...' }
 *   - non-empty content:
 *     - returns { content: <string>, error: null } with no log call
 *
 * The wGETVerbose used by the fetcher is imported from `homeproxy`.
 * Tests stage a `homeproxy` module that overrides only wGETVerbose
 * (everything else falls through to the real homeproxy.uc, so
 * redactUrl/isEmpty are not stubbed). The override reads the
 * pre-canned response / exit code from globals - global is the
 * only cross-module shared state ucode exposes without a real
 * dependency-injection hook.
 *
 * REDACTION COVERAGE
 * ------------------
 * redactUrl() is exported from homeproxyuc and is what stops the
 * subscription token from landing in /var/run/homeproxy/homeproxy.log.
 * The fetcher is the only place that logs a subscription URL on the
 * failure path; this test makes sure the redacted URL reaches the
 * log sink rather than the original (a security regression would
 * fail here).
 */

'use strict';

import { fetch } from 'fetcher';

let failures = 0,
    checks = 0;

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL %s: expected %J, got %J\n', name, want, actual);
		failures++;
	}
}

/* Capture the log() callback into a local buffer so we can inspect
 * what the fetcher decided to log. */
function make_log_capture() {
	let buf = [];
	const log = (...args) => { push(buf, join(' ', args)); };
	return { buf, log };
}

/* Test 1: empty content -> failure logged + null returned.
 * Global override returns { content: '', error: '...' }. */
{
	const cap = make_log_capture();
	/* globals stub */
	global.HP_TEST_WGET_CONTENT = '';
	global.HP_TEST_WGET_ERROR = 'connection refused';
	const r = fetch('https://user:tok@host.example.com/path?q=token=secret', null, cap.log);
	expect('empty.content', r.content, null);
	expect('empty.error is what wGETVerbose returned', r.error, 'connection refused');
	if (length(cap.buf) !== 1) {
		printf('FAIL empty.log count: expected 1, got %d\n', length(cap.buf));
		failures++;
	} else {
		checks++;
		/* The URL in the log must be redacted: no user:tok, no token=secret. */
		const line = cap.buf[0];
		if (index(line, 'tok') !== -1 || index(line, 'token=secret') !== -1) {
			printf('FAIL empty.log redaction: token leaked: %s\n', line);
			failures++;
		} else {
			checks++;
			printf('PASS empty.log redaction: %s\n', line);
		}
	}
}

/* Test 2: non-empty content -> no log, body round-trips, error null. */
{
	const cap = make_log_capture();
	global.HP_TEST_WGET_CONTENT = 'stub-body';
	global.HP_TEST_WGET_ERROR = null;
	const r = fetch('https://host.example.com/path?q=anything', null, cap.log);
	expect('ok.content', r.content, 'stub-body');
	expect('ok.error', r.error, null);
	if (length(cap.buf) !== 0) {
		printf('FAIL ok.log: expected 0, got %d (%J)\n', length(cap.buf), cap.buf);
		failures++;
	} else {
		checks++;
	}
}

/* Test 3: the path carries the token too. Many providers hand out
 * https://host:port/<user>/<token> with no query string at all - that is
 * what the device this was found on is configured with - and the redaction
 * used to keep the path while claiming homeproxy.log is world-readable.
 * The host and port have to survive, or the message stops being useful. */
{
	const cap = make_log_capture();
	global.HP_TEST_WGET_CONTENT = '';
	global.HP_TEST_WGET_ERROR = 'connection refused';
	const r = fetch('https://bwg.example.net:2345/wjp/SECRETPATHTOKEN', null, cap.log);
	expect('path.content', r.content, null);
	if (length(cap.buf) !== 1) {
		printf('FAIL path.log count: expected 1, got %d\n', length(cap.buf));
		failures++;
	} else {
		checks++;
		const line = cap.buf[0];
		if (index(line, 'SECRETPATHTOKEN') !== -1 || index(line, 'wjp') !== -1) {
			printf('FAIL path.log redaction: the path token leaked: %s\n', line);
			failures++;
		} else if (index(line, 'bwg.example.net:2345') === -1) {
			printf('FAIL path.log redaction: host and port must survive: %s\n', line);
			failures++;
		} else {
			checks++;
			printf('PASS path.log redaction: %s\n', line);
		}
	}
}

/* --- summary ----------------------------------------------------------- */

if (failures > 0)
	printf('FAIL: %d/%d checks failed\n', failures, checks);
else
	printf('PASS: %d checks\n', checks);

exit(failures > 0 ? 1 : 0);