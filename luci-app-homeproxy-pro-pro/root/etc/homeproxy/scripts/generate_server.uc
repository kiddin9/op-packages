#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     scripts/generate_server.uc: process-level entry point.
 *
 * Mirror of scripts/generate_client.uc for the server instance. The
 * server generator (generator/server.uc) returns null when no inbound
 * is enabled; the shell then exits 1 so init.d can detect
 * "server disabled" without a separate UCI check.
 */

'use strict';

import { mkdtemp, writefile } from 'fs';
import { Loader } from './config/loader.uc';
import { generate_server } from './generator/server.uc';
import { removeBlankAttrs, RUN_DIR, shellQuote, UCICONFIG_DIR } from './homeproxy.uc';

const dm = Loader.load(UCICONFIG_DIR);
const config = generate_server(dm);
if (!config)
	exit(1);

const cleaned = removeBlankAttrs(config);
system('mkdir -p ' + shellQuote(RUN_DIR));

/* A private scratch directory rather than a fixed `<out>.tmp`.
 *
 * Two generation runs can still overlap (a LuCI apply while the cron entry
 * reloads, or a manual and a triggered reload). With a fixed name both wrote
 * the same file, and `sing-box check` could be validating a file the other run
 * was still writing - the winner then installed a half-written config.
 *
 * mkdtemp() is this package's existing primitive for that (executeCommand()
 * uses it) and gives a 0700 directory under /tmp.  The path here comes from
 * mkdtemp() so it is safe today, but it goes through shellQuote() anyway:
 * the "all shell args quoted" rule is the machine-checkable
 * invariant, not a comment about today's safety. */
const work_dir = mkdtemp();
const tmp = work_dir + '/sing-box-s.json';

/* Same reason as the client path: a failed write used to be reported as a
 * failed `sing-box check`. */
if (writefile(tmp, sprintf('%.J\n', cleaned)) == null) {
	system('rm -rf ' + shellQuote(work_dir));
	die('failed to write the generated server configuration to ' + tmp);
}

if (system('sing-box check --config ' + shellQuote(tmp)) !== 0) {
	system('rm -rf ' + shellQuote(work_dir));
	exit(1);
}

if (system('mv -f ' + shellQuote(tmp) + ' ' + shellQuote(RUN_DIR) + '/sing-box-s.json') !== 0) {
	system('rm -rf ' + shellQuote(work_dir));
	exit(1);
}

/* The server config carries inbound credentials and the REALITY/ECH key
 * material, and writefile() has no mode argument, so it lands with the
 * process umask.  0600 matches what sing-box needs to read it as its own
 * user. */
system('chmod 600 ' + shellQuote(RUN_DIR) + '/sing-box-s.json');

system('rm -rf ' + shellQuote(work_dir));