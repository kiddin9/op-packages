#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 *
 * The orchestrator no
 * longer touches UCI directly. All UCI writes live in
 * subscription/repository.uc. The pipeline is:
 *
 *   Loader.load()           -> read subscription + main_node refs
 *   parse_uri()             -> flat UCI keys (the parser's output shape)
 *   normalize()             -> canonical Node (parser/normalize.uc)
 *   apply_policy()          -> policy tweaks on the canonical Node
 *                              (tls.insecure, protocol_options.packet_encoding)
 *   Repository.apply_nodes  -> writes UCI for subscription nodes
 *                              (internally flatten()s the canonical
 *                              nodes, so the orchestrator never
 *                              touches UCI).
 *   Repository.apply_main_node_refs -> writes UCI for main_node /
 *                              main_udp_node / urltest cleanup.
 *   Repository.scrub_stale_urltest_refs -> one-shot pass over UCI
 *                              routing_nodes for stale urltest_nodes
 *                              entries.
 *
 * The canonical Node is the only object the orchestrator hands the
 * Repository, and the only one policy is applied to. The parser's flat
 * UCI-key dict survives here for one thing only: the duplicate
 * fingerprint, which identifies the parsed link and must not move when a
 * subscription-level policy changes.
 *
 * Every UCI write the run performs is therefore in
 * subscription/repository.uc. The orchestrator's only UCI side
 * effect is passing its cursor to the Repository methods.
 *
 * A2 (single commit): the Repository commits nothing; this script owns the
 * one uci.commit() the run performs, after every mutation is staged and
 * before the reload. Read the comment above that commit for what the
 * multi-commit order used to allow.
 *
 * A4 (lock before snapshot): the cursor, the domain model and the recovery
 * snapshot are all read inside the lock. See load_locked_state().
 */

'use strict';

import { md5 } from 'digest';
import { lstat, open, readfile, writefile } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import {
	executeCommand, getTime, isEmpty, HP_DIR, RUN_DIR, redactUrl, shellQuote,
	UCICONFIG_DIR
} from './homeproxy-pro.uc';

import { parse_uri } from './parser/uri.uc';
import { normalize } from './parser/normalize.uc';

import { check as filter_check, apply_policy } from './subscription/filter.uc';
import { decode as decode_subscription } from './subscription/decoder.uc';
import { fetch as fetch_subscription } from './subscription/fetcher.uc';
import { Repository } from './subscription/repository.uc';

import { Loader } from './config/loader.uc';

/* UCI cursor, configuration and recovery snapshot the run works on.
 *
 * A4: none of this is read at module scope any more. The lock used to guard
 * only the write phase - the subscription list, the domain model and the
 * backup were all read first - so a run that read while another one held the
 * lock and then acquired it after that one finished would commit against the
 * base it had read before, and, on failure, restore a snapshot older than the
 * run that had just committed. Everything below is now filled by
 * load_locked_state(), which is called only after acquire_lock() returns true.
 *
 * A2: the run performs exactly one uci.commit(). The Repository modules stage
 * mutations only.
 *
 * UCICONFIG_DIR (homeproxy-pro.uc) is the config *directory* Loader.load() takes,
 * and the sandboxed test points it at its own config instead of /etc/config
 * (tests/ucode/test_subscription_updater_runs.sh rewrites that line in
 * homeproxy-pro.uc and fails loudly if the rewrite did not apply). */
const CONFIG_FILE = UCICONFIG_DIR + '/homeproxy-pro';
const uciconfig = 'homeproxy-pro';

const ucimain = 'config',
      ucinode = 'node';

/* Filled by load_locked_state(). `let`, so the reads could move into the lock
 * without threading a state object through every use site. */
let uci, loaded, sub, routing_mode,
    allow_insecure, filter_mode, filter_keywords, packet_encoding,
    subscription_urls, user_agent, main_node, main_udp_node,
    config_backup = null;

/* Read everything the run needs, under the lock. Read-only: nothing here
 * mutates, so a failure cannot leave a partial state behind. */
function load_locked_state() {
	uci = cursor();
	uci.load(uciconfig);

	/* The orchestrator used to hold its own
	 * uci.cursor() and re-read subscription.* / config.* one field at
	 * a time. Now it goes through Loader.load(), which is read-only
	 * and exposes the canonical sub-objects
	 * (`config.access_control.subscription`). The Repository methods
	 * continue to take the raw cursor for the writes because the
	 * cursor is the UCI writer contract. */
	loaded = Loader.load(UCICONFIG_DIR);
	sub = loaded.access_control.subscription;
	routing_mode = loaded.general.routing_mode;

	allow_insecure = sub.allow_insecure || '0';
	filter_mode = sub.filter_nodes || 'disabled';
	/* subscription_urls and filter_keywords are siblings of `subscription`,
	 * not members of it: load_access_control() puts them straight on
	 * access_control (loader.uc:303-304), and test_domain_model_skeleton.uc
	 * asserts that shape.  Reading them through `sub.` yielded [] forever, so
	 * the guard below never called main() and the updater exited 0 having done
	 * nothing - the LuCI button and the cron entry were both silent no-ops. */
	filter_keywords = loaded.access_control.filter_keywords || [];
	packet_encoding = sub.packet_encoding || 'xudp';
	subscription_urls = loaded.access_control.subscription_urls || [];
	user_agent = sub.user_agent;

	main_node = null;
	main_udp_node = null;
	if (routing_mode !== 'custom') {
		main_node = loaded.general.main_node;
		main_udp_node = loaded.general.main_udp_node;
	}

	/* The snapshot the failure path restores. It is read here, under the
	 * lock, so it is the state this run actually started from - not whatever
	 * was on disk while the process was still waiting for the lock. */
	config_backup = readfile(CONFIG_FILE);
}


function log(...args) {
	const logfile = open(`${RUN_DIR}/homeproxy-pro.log`, 'a');
	logfile.write(`${getTime()} [SUBSCRIBE] ${join(' ', args)}\n`);
	logfile.close();
}

/* One updater at a time.
 *
 * The cron entry and the LuCI button can both start this script, and the update
 * is a sequence of commits (nodes, then main_node refs, then the repository's
 * single commit). Two runs interleaving them is last-writer-wins, and a failing
 * run restores ITS snapshot over whatever the other just wrote - so a
 * concurrent update can lose a whole node set.
 *
 * mkdir is the lock: it is atomic on every filesystem this runs on and needs no
 * flock binding. A lock older than HP_LOCK_STALE is treated as abandoned (a
 * killed process cannot clean up after itself) and broken, so a crash cannot
 * block every future update. */
const LOCK_DIR = RUN_DIR + '/update_subscriptions.lock';
const LOCK_STALE = 600;

function lock_age() {
	const st = lstat(LOCK_DIR);

	if (!st)
		return null;

	/* time() is the epoch; getTime() is this package's *formatter*
	 * (getTime(epoch) -> 'YYYY-MM-DD@HH:MM:SS'), so subtracting it produced
	 * NaN and the stale check never fired. */
	return max(0, time() - (st.mtime || 0));
};

function acquire_lock() {
	system(sprintf('mkdir -p %s', shellQuote(RUN_DIR)));

	if (system(sprintf('mkdir %s 2>/dev/null', shellQuote(LOCK_DIR))) === 0)
		return true;

	const age = lock_age();

	if (age != null && age > LOCK_STALE) {
		log(sprintf('Breaking a stale update lock (%s seconds old).', age));
		system(sprintf('rmdir %s 2>/dev/null', shellQuote(LOCK_DIR)));

		return system(sprintf('mkdir %s 2>/dev/null', shellQuote(LOCK_DIR))) === 0;
	}

	return false;
};

function release_lock() {
	system(sprintf('rmdir %s 2>/dev/null', shellQuote(LOCK_DIR)));
};


function main() {
	const node_cache = {};
	const node_result = [];

	const ubus = connect();
	/* ubus is unreachable when no ubusd is running (dev host)
	 * and the feature query is optional: fall back to the same
	 * empty feature set the code below already handles. */
	const sing_features = (ubus?.call('luci.homeproxy-pro', 'singbox_get_features', {})) || {};
	if (isEmpty(sing_features))
		log('Warning: Failed to query sing-box features via ubus, assuming defaults.');

	/* Fetch, decode, parse and filter everything BEFORE touching
	 * the service or UCI. The previous version stopped the proxy
	 * first, so a slow or failing subscription left the router
	 * without a proxy for the whole fetch - the stop -> modify
	 * -> discover-an-error pattern the refactor guide forbids.
	 * Nothing below runs until a full candidate set exists in
	 * memory. */
	for (let url in subscription_urls) {
		url = replace(url, /#.*$/, '');
		const groupHash = md5(url);
		node_cache[groupHash] = {};

		/* Keep the lock's mtime current for as long as this run is alive.
		 * The stale window (LOCK_STALE) is what lets a later run reclaim a
		 * lock a killed process left behind, but nothing refreshed it while
		 * the fetch was in progress - and the fetch is one request per URL,
		 * ten seconds each.  A run that crosses the threshold while still
		 * working can therefore have its lock broken underneath it, and the
		 * two runs then interleave their read-modify-write exactly like the
		 * comment above acquire_lock() describes. */
		system(sprintf('touch %s 2>/dev/null', shellQuote(LOCK_DIR)));

		const fetched = fetch_subscription(url, user_agent, log);
		if (fetched.content === null)
			continue;

		const nodes = decode_subscription(fetched.content, log, url);

		let count = 0;
		for (let node in nodes) {
			let flat;
			if (!isEmpty(node))
				flat = parse_uri(node, sing_features, log);
			if (isEmpty(flat))
				continue;

			const label = flat.label;
			flat.label = null;
			const confHash = md5(sprintf('%J', flat)),
			      nameHash = md5(groupHash + label);
			flat.label = label;

			if (filter_check(flat.label, filter_mode, filter_keywords, log))
				log(sprintf('Skipping blacklist node: %s.', flat.label));
			else if (node_cache[groupHash][confHash] || node_cache[groupHash][nameHash])
				log(sprintf('Skipping duplicate node: %s.', flat.label));
			else {
				/* normalize() first: the canonical Node is the only
				 * business object this orchestrator hands the Repository.
				 * The policy tweaks used to be applied to `flat` before
				 * this, which meant the pipeline was flat -> flat(tweaked)
				 * -> canonical, and only the Repository's internal
				 * flatten() brought it back. Now it is
				 * parse -> normalize -> apply_policy -> Repository.
				 *
				 * `flat` stays in scope for the fingerprint above only.
				 * That fingerprint is taken from the parser's output on
				 * purpose: it identifies the parsed link, and the policy
				 * tweaks belong to the subscription rather than to the
				 * node. */
				const node_canonical = normalize(flat);
				node_canonical.grouphash = groupHash;

				/* normalize() exposes the source label as `name`; the
				 * Repository identifies a node by
				 * md5(grouphash + label), so without this every node in
				 * one subscription hashes to the SAME section name and
				 * they overwrite each other - a 4-node subscription
				 * collapsed into a single section carrying one protocol's
				 * `type` with several protocols' options mixed in.
				 * The cache is keyed by the same hash, so this also makes
				 * an unchanged node match on the next run instead of
				 * being deleted and re-added every time. */
				node_canonical.label = flat.label;

				apply_policy(node_canonical, { allow_insecure, packet_encoding });

				push(node_result, [ node_canonical ]);
				node_cache[groupHash][confHash] = node_canonical;
				node_cache[groupHash][nameHash] = node_canonical;

				count++;
			}
		}

		if (count === 0)
			log(sprintf('No valid node found in %s.', redactUrl(url)));
		else
			log(sprintf('Successfully fetched %s nodes of total %s from %s.', count, length(nodes), redactUrl(url)));
	}

	if (isEmpty(node_result)) {
		/* Nothing was touched yet (the fetch phase never writes),
		 * so the running service and the stored configuration
		 * stay as they are. */
		log('Failed to update subscriptions: no valid node found.');
		return false;
	}

	/* The add / update / remove walk and the
	 * final commit now live in subscription/repository.uc. The
	 * orchestrator just hands it the canonical Node cache +
	 * result built during the fetch phase and uses the
	 * { added, removed } counts for the end-of-run log. */
	const repository_result = Repository.apply_nodes(
		uci, uciconfig, ucinode, node_cache, node_result, log
	);
	const added = repository_result.added,
	      removed = repository_result.removed;

	/* The 6 inline uci.set/commit sites
	 * (main_urltest_nodes cleanup, main_node switch on missing
	 * target, main_udp_urltest_nodes cleanup, main_udp_node
	 * switch, reset-to-'nil', routing_node urltest scrub) moved
	 * into subscription/repository.uc. The orchestrator now
	 * drives three Repository methods and replays the log lines
	 * the Repository attached to its result. */
	if (!isEmpty(main_node)) {
		const main_refs = Repository.apply_main_node_refs(
			uci, uciconfig, ucimain, ucinode,
			{ main_node, main_udp_node, has_nodes: added > 0 },
			log
		);
		for (let line in main_refs.log)
			log(line);
	}

	Repository.scrub_stale_urltest_refs(uci, uciconfig, log);

	/* A2: the run's single transaction boundary.
	 *
	 * apply_nodes(), apply_main_node_refs() and scrub_stale_urltest_refs()
	 * stage every mutation on this one cursor and commit nothing. Before
	 * this, each of them committed for itself - eight sites inside the
	 * repository - so a crash (or a kill) between two of them could leave
	 * the subscription's nodes written while main_node still pointed at a
	 * section that had just been deleted. The commit below is the only
	 * point at which the run becomes visible, and the reload only ever sees
	 * a fully applied state.
	 *
	 * commit() returns true on success, so a failure is detected here rather
	 * than by generating a configuration from a half-written file. */
	if (uci.commit(uciconfig) !== true) {
		log('FAILED to commit the new configuration; the previous configuration is kept.');
		return false;
	}

	/* Reload once, after the whole candidate set is committed
	 * and stale references are scrubbed. The old code stopped
	 * the service before fetching and then did stop+start; the
	 * reload path now validates the new configuration and rolls
	 * back if an instance fails to come up, so the service is
	 * only ever restarted onto a config that passed `sing-box
	 * check`. */
	log('Reloading service...');

	/* Run the init script directly. The previous code called
	 * `init_action('homeproxy-pro', 'reload')` imported from luci.sys, but
	 * neither openwrt/luci nor immortalwrt/luci exports an `init_action`
	 * from that module (it has process_list / conntrack_list /
	 * init_list / init_index / init_enabled), so the import failed to
	 * resolve and this script could not load on a router at all.
	 *
	 * executeCommand() is the package's own runner (homeproxy-pro.uc); unlike
	 * a bare system() call it returns the exit status and the captured
	 * stderr, so a failed reload is recorded instead of disappearing. */
	const reload = executeCommand('/etc/init.d/homeproxy-pro', 'reload');
	if (reload.exitcode !== 0)
		log(sprintf('Warning: reload exited with status %d: %s',
			reload.exitcode, trim(reload.stderr || '')));
	else if (reload.stderr_truncated)
		/* Non-zero exit + stderr_truncated is unambiguous; the
		 * log line above already carries the message. The truncated
		 * case is the subtle one: a clean exit can still hide a
		 * sing-box check warning that was truncated out of view. */
		log('Warning: reload stderr was truncated (>512 KiB); the captured output is incomplete.');

	log(sprintf('%s nodes added, %s removed.', added, removed));
	log('Successfully updated subscriptions.');
}

/* A4: the lock comes first, and every read happens inside it.
 *
 * This block used to test the subscription list before taking the lock, so
 * the read of the configuration happened outside the critical section. The
 * order is now: acquire -> read -> mutate -> commit -> reload -> release.
 * The pre-lock "nothing configured" shortcut is preserved in meaning (no
 * fetch, no write, no log) but it is decided after the lock is held; taking
 * and releasing an uncontended mkdir lock costs nothing measurable next to
 * the fetch that would follow. */
if (!acquire_lock()) {
	log('Another subscription update is already running; skipping this one.');
}
else {
	/* ucode has no `finally`, so the release is written out on both paths by
	 * the explicit call after the try/catch. */
	try {
		load_locked_state();

		if (isEmpty(subscription_urls)) {
			/* Nothing configured: no fetch, no write, no log line - the same
			 * silent no-op the pre-lock check performed. */
		}
		else {
			call(main);
		}
	} catch(e) {
		log('[FATAL ERROR] An error occurred during updating subscriptions:');
		log(sprintf('%s: %s', e.type, e.message));
		log(e.stacktrace[0].context);

		if (config_backup != null) {
			/* Write the snapshot beside the config and rename it into place.
			 * A bare writefile() truncates first, so a crash or a full disk
			 * part-way through the restore leaves /etc/config/homeproxy-pro
			 * partial or empty - losing the very configuration this is
			 * meant to protect. rename() is atomic within a directory. */
			const restore_tmp = CONFIG_FILE + '.hp-restore';

			if (writefile(restore_tmp, config_backup) != null
			    && system(sprintf('mv -f %s %s', shellQuote(restore_tmp), shellQuote(CONFIG_FILE))) === 0) {
				log('Restored the previous configuration; the running service was not stopped.');
			}
			else {
				system(sprintf('rm -f %s', shellQuote(restore_tmp)));
				log('FAILED to restore the previous configuration - the file on disk may be incomplete.');
			}
		}
	}

	release_lock();
}