#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 ImmortalWrt.org
 *
 * Feeds the command line wGETVerbose() builds to the target's real
 * uclient-fetch - the default /usr/bin/wget on OpenWrt/ImmortalWrt. run.sh
 * rewrites the module's wget path to /bin/uclient-fetch and skips this file
 * where that binary does not exist.
 *
 * A closed loopback port is the entire request: what matters is that
 * uclient-fetch gets past getopt. Before the flavour probe existed it did not -
 * `-nv` made it print "unrecognized option: n" and exit before the request was
 * sent, so every subscription fetch came back empty. Any failure observed here
 * must therefore come from the network, never from the option parser.
 */

'use strict';

import { wGETVerbose, wgetFlavor } from 'homeproxy';

let failures = 0, checks = 0;

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL %s: expected %J, got %J\n', name, want, actual);
		failures++;
	}
}

/* uclient-fetch has no --version and rejects it, so it is classified compat. */
expect('flavor', wgetFlavor(), 'compat');

const res = wGETVerbose('http://127.0.0.1:1/subs', 'HomeProxy test UA');
expect('no content', res.content, null);
expect('not an option error', match(res.error || '', /unrecognized option/) == null, true);
expect('error carries the exit code', match(res.error || '', /^wget exited with status \d+: /) != null, true);

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);
