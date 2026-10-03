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
import { BUILTIN_REMOTE_RULE_SETS, declaresBuiltinRemoteRuleSets, rule_set_tags } from './generator/common.uc';
import { removeBlankAttrs, isEmpty, probeRuleSetFile, ruleSetFormatExtension, ruleSetFormatFromPath, ruleSetInitialFallback, RULESET_EMPTY_BINARY, RULESET_EMPTY_SOURCE, RULESET_INITIAL_DIR, shellQuote, validateRuleSetPath, HP_DIR, RUN_DIR, UCICONFIG_DIR } from './homeproxy-pro.uc';

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
/* Write one EMPTY rule-set to <path>, in <format>.
 *
 * The fallback exists so that a remote rule-set with no initial file of the
 * user's own does not have to be downloaded before the inbounds bind - and on
 * a cold cache that is the difference between a router that comes up and one
 * that waits on raw.githubusercontent.com (through the node) before it will
 * listen at all.
 *
 * binary is produced by compiling, not by writing bytes: a file produced by
 * the sing-box that is running cannot drift from it, and the compiler is
 * always there because the very next thing this script does is run it.  The
 * shipped 14-byte constant is the fallback for the fallback - a router where
 * the compile cannot run - and it is a file in the package rather than a byte
 * string in the source, so `hexdump -C` on a device can confirm it.
 *
 * Returns true when <path> holds a usable file afterwards.  A false return is
 * not fatal: the caller skips the initial_path, and the rule-set then behaves
 * exactly as it does today (fetched during initialization, blocking on
 * failure).  That is the point of the whole opt-in - it must never make a
 * situation worse than not having it. */
function writeEmptyRuleSet(path, format) {
	const ext = ruleSetFormatExtension(format);

	if (!ext)
		return false;

	system('mkdir -p ' + shellQuote(RULESET_INITIAL_DIR));

	if (format === 'source') {
		/* No compile needed, and no temp file: the source form is the JSON
		 * itself.  The shipped empty.source.json is the source of record, so
		 * a missing one means the install is incomplete and the copy is the
		 * thing that says so. */
		if (system('cp -f ' + shellQuote(RULESET_EMPTY_SOURCE) + ' ' + shellQuote(path)) !== 0)
			return false;
	} else {
		/* Compile into the destination directly.  A partial output is
		 * possible if the compile dies, so the file is only accepted when the
		 * compile succeeded AND something is there - sing-box opening a
		 * truncated .srs would block startup, which is the outcome this is
		 * all meant to prevent.
		 *
		 * `-o` rather than `--output`, because that is the form
		 * tests/ucode/test_generators.sh already exercises against this
		 * binary, and a flag spelling that only ever runs in production is a
		 * flag spelling nobody has ever seen work. */
		if (system('sing-box rule-set compile ' + shellQuote(RULESET_EMPTY_SOURCE)
			+ ' -o ' + shellQuote(path) + ' >/dev/null 2>&1') !== 0) {
			if (system('cp -f ' + shellQuote(RULESET_EMPTY_BINARY) + ' ' + shellQuote(path)) !== 0)
				return false;
		}

		const st = lstat(path);
		if (!st || st.type !== 'file' || st.size <= 0)
			return false;
	}

	/* The jailed client reads this as the sing-box user.  writefile() has no
	 * mode argument and cp preserves the source's, so the mode is set
	 * explicitly rather than inherited from whatever umask was in force. */
	system('chmod 644 ' + shellQuote(path));

	return true;
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
		ruleset_initial: {}
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

	/* ruleset_safe_start: write the empty fallbacks.
	 *
	 * Recorded as PRESENCE, not as a path: env.ruleset_initial[tag] is true
	 * only once a file for that tag is on disk and readable.  The generator
	 * then emits `initial_path` for exactly the tags it can point at, which
	 * is what keeps the two sides from disagreeing - a file that could not be
	 * written is simply not offered, and that rule-set keeps today's
	 * behaviour (fetched during initialization) instead of pointing at
	 * something that is not there.  sing-box ignores a missing initial_path
	 * and blocks startup exactly as if none had been configured, so this
	 * cannot make a broken install worse - but the point of the opt-in is
	 * that it helps, and a pointer to a nonexistent file helps nobody.
	 *
	 * Built-ins first, then the user's own.  Both come from the same helper
	 * the generator uses, so the format the file was written in and the
	 * format declared in the config are decided by one question asked once. */
	if (dm.general.ruleset_safe_start === '1') {
		if (declaresBuiltinRemoteRuleSets(routing_mode)) {
			for (let rs in BUILTIN_REMOTE_RULE_SETS) {
				const path = ruleSetInitialFallback([ rs.tag ], rs.format, rs.url);
				if (path && writeEmptyRuleSet(path, rs.format))
					env.ruleset_initial[rs.tag] = true;
				else
					warn(sprintf("homeproxy-pro: could not write the empty fallback for '%s'; this rule-set will be fetched during startup, as before.", rs.tag));
			}
		}

		/* User rule-sets are custom-mode only - build_user_rulesets() is not
		 * called in any other mode - so writing fallbacks for them anywhere
		 * else would create files nothing ever points at.  A rule-set with an
		 * initial file of its own is left completely alone. */
		if (routing_mode === 'custom') {
			for (let cfg in (dm.routing.rulesets || [])) {
				if (!cfg.enabled || cfg.type !== 'remote' || !isEmpty(cfg.initial_path))
					continue;

				const format = cfg.format || ruleSetFormatFromPath(cfg.url);
				const tags = rule_set_tags(cfg);
				const template = ruleSetInitialFallback(tags, format, cfg.url);

				if (!template) {
					warn(sprintf("homeproxy-pro: rule-set '%s' has no usable format for the startup fallback (format '%s', url '%s'); it will be fetched during startup, as before.", cfg.name, cfg.format || '', cfg.url || ''));
					continue;
				}

				for (let tag in tags) {
					if (env.ruleset_initial[tag])
						continue;

					/* A single-tag rule-set's template IS the path; a
					 * multi-tag one carries {tag} and needs one file each -
					 * sing-box opens every tag's file, so a missing second
					 * one blocks startup as surely as a missing first. */
					const path = (length(tags) > 1) ? replace(template, '{tag}', tag) : template;

					if (writeEmptyRuleSet(path, format))
						env.ruleset_initial[tag] = true;
					else
						warn(sprintf("homeproxy-pro: could not write the empty fallback for rule-set '%s' (tag %s); it will be fetched during startup, as before.", cfg.name, tag));
				}
			}
		}
	}

	/* One line naming what is running on an empty fallback.
	 *
	 * The CLI already warns per rule-set when a fallback could not be written,
	 * but "which rule-sets are currently on an EMPTY one" is the fact a user
	 * needs and nothing else records it: the running configuration is not
	 * readable by the browser, the health gate does not look at rule-sets, and
	 * sing-box's own log only says the download failed.  This line is the
	 * durable answer, and it goes to homeproxy-pro.log, which the status page can
	 * read with the permission it already has.
	 *
	 * Emitted only when the opt-in is on AND something actually got a
	 * fallback, so the log does not gain a line on every generation of a
	 * configuration that is not using the feature. */
	if (dm.general.ruleset_safe_start === '1' && !isEmpty(env.ruleset_initial)) {
		const tags = [];

		for (let tag in env.ruleset_initial)
			push(tags, tag);

		warn(sprintf("homeproxy-pro: ruleset_safe_start is on; these rule-sets have an EMPTY initial file and match nothing until their download succeeds: %s.", join(', ', tags)));
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