#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     scripts/generate_client.uc: process-level entry point.
 *
 * The actual client generator is generator/client.uc; this script is the
 * thin entry point that init.d/homeproxy-pro execve's. Responsibilities:
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
import { lstat, mkdtemp, readfile, writefile } from 'fs';

import { Loader } from './config/loader.uc';
import { generate } from './generator/client.uc';
import { rule_set_tags } from './generator/common.uc';
import { removeBlankAttrs, isEmpty, isValidCIDR, probeRuleSetFile, ruleSetFormatFromPath, shellQuote, validateRuleSetPath, validation, HP_DIR, RUN_DIR, UCICONFIG_DIR } from './homeproxy-pro.uc';

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

/* Normalise one server address into `host`, or return null when there is
 * nothing usable.  WireGuard peers and the plain outbounds disagree on the
 * field name and the IPv6 form, so this is the only place that knows both. */
function node_host_of(v) {
	if (isEmpty(v))
		return null;

	let host = trim(v);

	/* `[fdfe::1]` is how an IPv6 literal arrives from a UCI value; the set
	 * syntax wants the bare address. */
	if (length(host) > 2 && substr(host, 0, 1) === '[' && substr(host, -1, 1) === ']')
		host = substr(host, 1, -2);

	return isEmpty(host) ? null : host;
}

/* Export the node server addresses, split by form, into two files the
 * intercept layer reads:
 *
 *   RUN_DIR/node-addr-ips.txt      literal addresses, rendered straight into
 *                                  the nft set by firewall_post.ut
 *   RUN_DIR/node-addr-domains.txt  host names, handed to dnsmasq as
 *                                  `server=` + `nftset=` so the addresses they
 *                                  resolve to land in the same set
 *
 * Why the set exists at all: sing-box's own outbound already carries
 * `routing_mark: self_mark` and every chain returns on that mark, so the
 * tunnel's connection to the node is never re-intercepted.  The LAN's is not.
 * A client opening a connection to the node's own address - the panel, an SSH
 * session to the landing box, anything on a port the proxy covers - was
 * redirected into sing-box, which then dialled the very address it was asked
 * for through the tunnel to that same node: one extra hairpin hop, and the
 * node sees the connection arriving from itself.
 *
 * The generator is the only place that knows which nodes are actually in use
 * (main_node, main_udp_node, urltest membership, custom-mode routing_nodes,
 * wireguard endpoints), so it is the only place that can produce this list
 * without the firewall template re-deriving that selection and drifting.
 *
 * Failure is not fatal.  A missing file means the set renders empty, which is
 * exactly the behaviour before this existed. */
function export_node_addresses(config) {
	const addrs = [];
	const domains = [];

	const add = (v) => {
		const host = node_host_of(v);
		if (host === null)
			return;
		if (isValidCIDR(host, 4) || isValidCIDR(host, 6))
			push(addrs, host);
		else if (validation('hostname', host))
			push(domains, host);
	};

	for (let ob in (config.outbounds || []))
		add(ob.server);

	/* WireGuard moved from `outbounds` to `endpoints` in 1.13, and the peer
	 * address is the node there. */
	for (let ep in (config.endpoints || []))
		for (let peer in (ep.peers || []))
			add(peer.address);

	const dump = (path, list) => {
		if (isEmpty(list))
			return;
		/* ucode's join() takes the separator FIRST: join(sep, list).  With
		 * the arguments the other way round it does not raise, it returns
		 * null - and null + '\n' is the four-character string "null\n", so
		 * the file comes out non-empty and every "is it there?" check on
		 * it passes.  That is exactly how a released r41 ended up with
		 * dnsmasq resolving a host literally named "null". */
		if (writefile(path, join('\n', uniq(list)) + '\n') == null)
			warn(sprintf('homeproxy-pro: could not write %s\n', path));
	};

	dump(RUN_DIR + '/node-addr-ips.txt', addrs);
	dump(RUN_DIR + '/node-addr-domains.txt', domains);
}

function resolve_env(dm) {
	const routing_mode = dm.general.routing_mode || 'bypass_mainland_china';
	const ubus = connect();
	const env = {
		wan_dns: (ubus?.call('network.interface', 'status', {'interface': 'wan'}))?.['dns-server']?.[0],
		direct_domain_list: [],
		proxy_domain_list: [],
		/* Whether the generated mainland rule-set for IPv6 is on disk.
		 *
		 * generator/ may not stat anything (guard 27), and this is exactly
		 * the kind of environment a generator is supposed to be handed:
		 * geoip-cn.srs and china_ip4.json carry no IPv6, so china_ip6.json -
		 * written by hp_prepare_runtime_files from the list the resource
		 * updater maintains - is the only thing that lets the route and DNS
		 * halves recognise a mainland IPv6 destination.  When it is absent
		 * (the list is missing, or had no usable prefix when the file was
		 * last written) both halves have to stay silent about IPv6 instead
		 * of naming a rule-set that is not there: a `rule_set:` pointing at
		 * a missing file makes sing-box reject the entire config, which the
		 * health gate turns into a rollback and an unproxied network.  The
		 * firewall has already degraded to passing IPv6 through, with a
		 * warning in the ruleset and the log.
		 *
		 * lstat(), not the two-argument access(). fs.access() on this ucode
		 * build answers only in its one-argument form: access(path) returns
		 * true for an existing path and null for a missing one, while
		 * access(path, mode) returns null either way. The two-argument form
		 * is therefore the worst possible choice here - it reports every
		 * file as missing, so this flag would be permanently false and the
		 * whole IPv6 split would stay switched off with nothing logged. The
		 * one-argument call sites elsewhere in the tree (homeproxy-pro.uc's
		 * cleanup_exec_dir) are correct and must stay as they are.
		 * lstat() is used because it is unambiguous - there is no second
		 * argument to get wrong - and because the neighbouring stderr-size
		 * check in homeproxy-pro.uc already reads sizes through it. */
		china_ip6_ready: lstat(HP_DIR + '/resources/china_ip6.json') !== null,
		/* The DNS half of the same split: whether china-domain.json is
		 * there.  Same reason, same lstat(), same one-sided default - a
		 * missing file has to leave the DNS rule out rather than name a path
		 * that does not exist and fail the whole start. */
		china_domain_ready: lstat(HP_DIR + '/resources/china-domain.json') !== null,
		/* Which enabled `type: local` rule-sets have a usable file on disk,
		 * keyed by UCI section name.
		 *
		 * The same boundary as china_ip6_ready above, and for the same reason
		 * it is resolved here rather than inside generator/: a rule-set whose
		 * `path` names a file that is not there is a filesystem question, and
		 * asking it from the generator would break the "generator/ is a pure
		 * function of its arguments" invariant guard 27 enforces.
		 *
		 * Only enabled local rule-sets are looked at, mirroring the filter
		 * build_user_rulesets() applies first - a disabled entry never reaches
		 * the generated configuration, so a missing file behind one is not an
		 * error.  The status is three-way on purpose:
		 *
		 *   missing key    the file is not there, or not a regular file, or
		 *                  empty - all three make `sing-box check` fail, the
		 *                  first two with a filesystem error and the third
		 *                  with "invalid sing-box rule-set file"
		 *   true           present and non-empty
		 *   never true     deliberately absent for a disabled or non-local
		 *                  entry, so "not checked" is distinguishable from
		 *                  "checked and absent"
		 *
		 * A `{tag}` placeholder in a path is expanded to one file per tag
		 * before the stat, because that is what sing-box does with it: a
		 * multi-tag rule-set whose second tag has no file fails the same way
		 * the first one would.  rule_set_tags() is imported from
		 * generator/common.uc so this and the generator agree on the tag
		 * names; the UI only offers extra_tags on remote rule-sets, so this
		 * path is reachable through a direct UCI write rather than the form.
		 *
		 * This is root's view of the filesystem, which is what the generator
		 * needs; whether the jailed sing-box user can read the file is the
		 * runtime's business (hp_prepare_runtime_files hands the archive over
		 * on every start). */
		ruleset_local_ready: {},
		/* What each rule-set's own file actually IS, keyed by UCI section
		 * name: { '<section>': 'binary' | 'source' }.
		 *
		 * A verdict about the bytes, so the generator can stop trusting a
		 * field that describes the file's NAME: sing-box infers `format`
		 * from the extension and is wrong in three ways that all end the
		 * same way (`sing-box check` rejects the configuration, the reload
		 * is aborted, the user sees "my change did not take") - content
		 * disagreeing with the name, the field naming the wrong format, and
		 * no extension to infer from at all.  See ruleSetFormatFromBytes()
		 * in homeproxy-pro.uc for the whole argument.
		 *
		 * No entry means no opinion, and that is the normal case for a
		 * remote rule-set with no initial_path: its content comes from a URL
		 * and generation must not touch the network.  A missing entry is
		 * therefore never read as "source" or "binary" - it is read as
		 * "leave the declared format alone", which is also what sing-box
		 * does with a rule-set nobody told anything about. */
		ruleset_formats: {},
		/* Which empty startup fallbacks are actually on disk, keyed by rule_set
		 * tag: { '<tag>': true }.  Presence, not a path - see the block at the
		 * end of this function. */
	};

	if (routing_mode === 'custom') {
		for (let cfg in (dm.routing.rulesets || [])) {
			if (!cfg.enabled)
				continue;

			/* The file sing-box opens at startup: a local rule-set's `path`,
			 * and a remote one's `initial_path` when it has one.  Both are
			 * subject to the same questions (is it there, what is it), which
			 * is why one pass answers both.
			 *
			 * A remote rule-set with no initial_path has nothing to look at:
			 * its content is whatever the URL serves, and fetching that
			 * during generation is exactly what generation must not do. */
			const source = (cfg.type === 'local') ? cfg.path
				: ((cfg.type === 'remote') ? cfg.initial_path : null);
			if (isEmpty(source))
				continue;

			/* One path per tag.  A single-tag rule-set yields exactly one, so
			 * this is the plain case and the loop is the only complication -
			 * and it has to be here, because sing-box substitutes {tag} and
			 * opens EVERY resulting file.  rule_set_tags() is the shared tag
			 * list (see common.uc): a second copy would be free to drift,
			 * and the drift would be silent - a pre-check that stats files
			 * the running configuration never names. */
			const paths = [];
			if (match(source, /\{tag\}/))
				for (let tag in rule_set_tags(cfg))
					push(paths, replace(source, '{tag}', tag));
			else
				push(paths, source);

			/* Both answers below are about paths the sing-box jail opens as
			 * the sing-box user, so an out-of-policy path is not read at all
			 * here.  ruleset.uc refuses it a moment later with the message
			 * the user can act on; producing no opinion about a file this
			 * process has no business opening is the whole point of the
			 * check. */
			let in_policy = true;
			for (let p in paths)
				if (!validateRuleSetPath(p)) {
					in_policy = false;
					break;
				}
			if (!in_policy)
				continue;

			/* Presence: every tag's file, and "present" means a non-empty
			 * regular file - all three states make `sing-box check` fail,
			 * the first two with a filesystem error and the third with
			 * "invalid sing-box rule-set file".  Only a local rule-set
			 * consults this; a remote one is allowed to have no
			 * initial_path, which is the normal case. */
			let all_present = true;
			for (let p in paths) {
				const st = lstat(p);
				if (!st || st.type !== 'file' || st.size <= 0) {
					all_present = false;
					break;
				}
			}
			if (cfg.type === 'local' && all_present)
				env.ruleset_local_ready[cfg.name] = true;

			/* Content: one verdict, and only when every file agrees.
			 *
			 * A disagreement between tags, or a file the probe cannot
			 * classify (a truncated download, an HTML error page saved
			 * under a .srs name), yields no verdict at all rather than the
			 * first answer that came back.  Correcting on ambiguous
			 * evidence is how an auto-correction turns into a second source
			 * of wrongness, and sing-box's own error is a better one than a
			 * guess dressed up as a fix. */
			let verdict = null, unanimous = true;
			for (let p in paths) {
				const seen = probeRuleSetFile(p);

				if (!seen) {
					unanimous = false;
					break;
				}

				if (!verdict)
					verdict = seen;
				else if (verdict !== seen) {
					unanimous = false;
					break;
				}
			}
			if (unanimous && verdict)
				env.ruleset_formats[cfg.name] = verdict;
		}
	}

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

/* Only now, with a configuration sing-box has accepted: the firewall and the
 * dnsmasq snippets read the exported list, and they must never be pointed at
 * addresses from a configuration that does not start. */
export_node_addresses(config);

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