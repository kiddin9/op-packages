#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 ImmortalWrt.org
 *
 * Regression tests for the wget flavour probe and for the command line
 * wGETVerbose() builds from it.
 *
 * OpenWrt/ImmortalWrt's default /usr/bin/wget is uclient-fetch, which rejects
 * GNU-only flags such as -nv with "unrecognized option: n" *before* it opens a
 * connection, so a single GNU-ism turns every subscription update into
 * "no valid node found". run.sh stages a copy of homeproxy.uc whose
 * /usr/bin/wget points at a stub; HP_WGET_STUB_VERSION steers the answer of
 * the `--version` probe (empty output plus a non-zero exit mimics
 * uclient-fetch, whose getopt rejects the option and returns 1).
 */

'use strict';

import { readfile } from 'fs';
import { classifyWgetFlavor, wGETVerbose, wgetFlavor } from 'homeproxy';

let failures = 0, checks = 0;

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL %s: expected %J, got %J\n', name, want, actual);
		failures++;
	}
}

function has(list, value) {
	for (let v in list)
		if (v === value)
			return true;

	return false;
}

/* The value following the first occurrence of `key` */
function after(list, key) {
	let prev = null;

	for (let v in list) {
		if (prev === key)
			return v;

		prev = v;
	}

	return null;
}

/* Classification of the `wget --version` probe. */
expect('gnu.version', classifyWgetFlavor(0, 'GNU Wget 1.25.0 built on linux-gnu.\n'), 'gnu');
expect('gnu.multiline', classifyWgetFlavor(0, "GNU Wget 1.21.4 built on linux-gnu.\n\nCopyright (C) 2015 Free Software Foundation.\n"), 'gnu');
expect('uclient.rejects-version', classifyWgetFlavor(1, null), 'compat');
expect('busybox.version', classifyWgetFlavor(0, 'BusyBox v1.36.1 (2024-01-01) multi-call binary.\n'), 'compat');
expect('empty.stdout', classifyWgetFlavor(0, ''), 'compat');
expect('missing.binary', classifyWgetFlavor(127, null), 'compat');

/* wgetFlavor() probes the stub and caches the answer. */
const want_flavor = getenv('HP_WGET_EXPECT_FLAVOR');
expect('flavor', wgetFlavor(), want_flavor);
expect('flavor.cached', wgetFlavor(), want_flavor);

const res = wGETVerbose('https://example.invalid/subs?token=abc', 'HomeProxy test UA');
expect('content', res.content, 'stub body');
expect('error', res.error, null);

const log = readfile(getenv('HP_WGET_STUB_LOG'));
const args = log ? split(trim(log), '\n') : [];

expect('agent flag', has(args, '-U'), true);
expect('agent value', after(args, '-U'), 'HomeProxy test UA');
expect('timeout flag', after(args, '-T'), '10');
expect('output flag', has(args, '-O-'), true);
expect('url', has(args, 'https://example.invalid/subs?token=abc'), true);

/* -nv is GNU wget's --no-verbose; every other wget on the target rejects it,
 * and -q is the meter switch they all share. */
expect('meter flag', has(args, want_flavor === 'gnu' ? '-nv' : '-q'), true);
expect('no gnu-only flag', has(args, '-nv'), want_flavor === 'gnu');
expect('no long options', has(args, '--user-agent') || has(args, '--timeout=10'), false);

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);
