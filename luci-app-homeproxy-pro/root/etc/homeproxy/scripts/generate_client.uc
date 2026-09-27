#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     scripts/generate_client.uc: process-level entry point.
 *
 * The actual client generator is generator/client.uc; this script is the
 * thin entry point that init.d/homeproxy execve's. Responsibilities:
 *
 *   1. Load UCI into the HomeProxyConfig domain model.
 *   2. Resolve the GenerationContext env: the WAN resolver (ubus) and the two
 *      domain-resource lists (fs). This is the process-level boundary, which
 *      is why it lives here and not under generator/.
 *   3. Call generate(dm, env) to get the sing-box JSON object.
 *   4. Write atomically: candidate tmp -> `sing-box check` -> mv to live.
 *
 * The check is here (and not in the runtime, and not in the generator)
 * because the architecture guide mandates the generator produce
 * "atomic write candidate + serialization" and the runtime is already
 * structured around "a failing generation leaves the previous file in
 * place" (see runtime/config.sh's hp_ensure_live). Having the shell do
 * the check keeps that contract single-sourced.
 */

'use strict';

import { connect } from 'ubus';
import { mkdtemp, readfile, writefile } from 'fs';

import { Loader } from './config/loader.uc';
import { generate } from './generator/client.uc';
import { removeBlankAttrs, HP_DIR, RUN_DIR, shellQuote, UCICONFIG_DIR } from './homeproxy.uc';

/* Resolve the GenerationContext inputs. This is the only impure step on the
 * client generation path, and it is deliberately here rather than under
 * generator/:
 *
 *   - wan_dns is the upstream the default-dns server detours to. ubus may be
 *     unreachable (no ubusd, a dev host, no WAN lease); build_context() then
 *     applies the same mode-dependent public fallback the pre-split generator
 *     used, so an unresolved value stays safe rather than fatal.
 *   - direct_domain_list / proxy_domain_list are the two files the resource
 *     updater maintains. Custom mode ignores both, so they are not read
 *     there - matching the pre-split read exactly.
 *
 * The extra parentheses around the ubus call keep the ?. chain guarded when
 * connect() returns null. */
function resolve_env(dm) {
	const routing_mode = dm.general.routing_mode || 'bypass_mainland_china';
	const ubus = connect();

	const env = {
		wan_dns: (ubus?.call('network.interface', 'status', {'interface': 'wan'}))?.['dns-server']?.[0],
		direct_domain_list: [],
		proxy_domain_list: []
	};

	if (routing_mode !== 'custom') {
		const direct_list_raw = readfile(HP_DIR + '/resources/direct_list.txt');
		env.direct_domain_list = direct_list_raw ? split(trim(direct_list_raw), /[\r\n]/) : [];

		const proxy_list_raw = readfile(HP_DIR + '/resources/proxy_list.txt');
		env.proxy_domain_list = proxy_list_raw ? split(trim(proxy_list_raw), /[\r\n]/) : [];
	}

	return env;
}

const dm = Loader.load(UCICONFIG_DIR);
const config = removeBlankAttrs(generate(dm, resolve_env(dm)));

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
const tmp = work_dir + '/sing-box-c.json';

/* writefile() returns null on failure, and ignoring that turned a full disk or
 * a permission error into a later "sing-box check failed", which points at the
 * wrong thing entirely. */
if (writefile(tmp, sprintf('%.J\n', config)) == null) {
	system('rm -rf ' + shellQuote(work_dir));
	die('failed to write the generated client configuration to ' + tmp);
}

if (system('sing-box check --config ' + shellQuote(tmp)) !== 0) {
	system('rm -rf ' + shellQuote(work_dir));
	exit(1);
}

if (system('mv -f ' + shellQuote(tmp) + ' ' + shellQuote(RUN_DIR) + '/sing-box-c.json') !== 0) {
	system('rm -rf ' + shellQuote(work_dir));
	exit(1);
}

/* The generated config carries every node credential - passwords, UUIDs,
 * private keys - and writefile() has no mode argument, so it lands with the
 * process umask (world-readable at the usual 022).  sing-box runs as its own
 * user and reads the file directly, so 0600 is enough. */
system('chmod 600 ' + shellQuote(RUN_DIR) + '/sing-box-c.json');

system('rm -rf ' + shellQuote(work_dir));