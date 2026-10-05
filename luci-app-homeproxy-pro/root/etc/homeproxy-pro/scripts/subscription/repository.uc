/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Every UCI write the
 * subscription pipeline performs now lives in this module. Three
 * entry points cover what used to be six uci.set+commit sites in
 * update_subscriptions.uc plus the existing node add/update/remove
 * walk:
 *
 *   apply_nodes                 - the add / update / remove walk
 *                                 for the nodes the subscription
 *                                 fetch returned this run.
 *   apply_main_node_refs        - main_node / main_udp_node cleanup:
 *                                 remove stale urltest members, switch
 *                                 main_node if its target is gone,
 *                                 reset both to 'nil' when the
 *                                 subscription has no nodes.
 *   scrub_stale_urltest_refs    - one-shot pass over every UCI
 *                                 routing_node that purges dead
 *                                 urltest_nodes entries left behind by
 *                                 nodes that have since been removed.
 *
 * Writes are driven by canonical Node objects (post- parser/normalize).
 * UCI is flat, so apply_nodes expands each node with parser/flatten.uc -
 * and that call is the module's only canonical -> UCI boundary: callers
 * hand this module canonical Nodes, never flat dicts, and every UCI key
 * name comes from parser/mapping.uc. The orchestrator
 * (update_subscriptions.uc) never writes UCI directly; it orchestrates
 * fetch + parse + normalize + filter + policy + reload and owns the one
 * commit.
 *
 * A2 (single commit): this module mutates the caller's cursor and never
 * commits. It used to commit at nine sites - once at the end of
 * apply_nodes, seven inside apply_main_node_refs, and once per scrubbed
 * routing_node - while update_subscriptions.uc's own comments called
 * that "the repository's single commit". A crash between two of them
 * left the nodes written but main_node still pointing at a deleted
 * section, and there was no single point at which the run became
 * visible. The transaction boundary is now the caller's one commit,
 * after every mutation is staged.
 */

'use strict';

import { md5 } from 'digest';

import { isEmpty } from '../homeproxy-pro.uc';

/* Relative, like config/loader.uc's '../parser/mapping.uc': ucode's
 * resolver only searches top-level module names in the -L tree, so a
 * bare 'parser/flatten.uc' does not resolve. */
import { flatten } from '../parser/flatten.uc';

/* --- apply_nodes -------------------------------------------------------- */

/* Add / update / remove the subscription-owned nodes against UCI.
 *
 *   node_cache   - { [groupHash]: { [nameHash]: canonical_node } }
 *                  A lookup table keyed by subscription URL group
 *                  and then by the per-node name hash. The fetch
 *                  loop populates this for de-duplication.
 *   node_result  - [[canonical_node, ...]] (one inner list per URL)
 *                  The de-duplicated, policy-applied nodes in the
 *                  order they should appear in UCI.
 *
 * Behaviour parity with the previous code:
 *   - user-created nodes (no grouphash) are never touched
 *   - nodes whose subscription has no cache entry (network
 *     failure for that URL) are left in place; we don't delete
 *     a node just because today's fetch didn't return it
 *   - a node in UCI but not in the cache is deleted
 *   - a node in both has every field of the new config written
 *     (including options the stored section did not have yet),
 *     and the options the new config no longer carries are removed
 *   - new nodes are added under name = md5(groupHash + label), the
 *     same hash the cache uses, so a subsequent re-fetch recognises
 *     them as existing
 *
 * Returns the { added, removed } counts. No commit here: the caller's
 * single commit is the boundary of "this run wrote something". */
/* --- content identity ---------------------------------------------------- */

/* A fingerprint of a node's *content*: the same server with the same
 * credentials and options, whatever it is called.
 *
 * Section names are md5(grouphash + label), so a subscription that renames a
 * node used to make the repository delete the old section and create a new one
 * - and every reference to it (`main_node`, `main_udp_node`, the urltest lists)
 * was switched away or dropped along with it, silently.  The label is not part
 * of a node's identity, so it is excluded here along with the section metadata
 * and the group hash (the group is already the lookup key).
 *
 * Keys are sorted so the fingerprint cannot depend on insertion order, and the
 * values are serialized with %J because UCI options can be lists. */
function content_key(flat) {
	const parts = [];

	for (let k in sort(keys(flat))) {
		if (k === 'label' || k === 'grouphash' || substr(k, 0, 1) === '.')
			continue;
		push(parts, k + '=' + sprintf('%J', flat[k]));
	}

	return md5(join('\n', parts));
}

/* The section name the orchestrator keyed this node under.
 *
 * Normally md5(grouphash + label).  When two servers of one subscription share
 * a label the orchestrator disambiguates the key with the content fingerprint,
 * and the section has to follow it - otherwise both nodes are written into the
 * same section and one of them is lost.  Returns null for a node the caller did
 * not put in the cache (the unit tests hand nodes in directly), which keeps the
 * previous behaviour as the fallback. */
function section_name_for(node, cache) {
	if (!cache)
		return null;

	for (let key in keys(cache))
		if (cache[key] === node)
			return key;

	return null;
}

/* group hash -> { content_key: canonical node }, built once and only when a
 * section was not found by name: a run without renames pays nothing. */
function build_content_index(node_cache) {
	const index = {};

	for (let group in keys(node_cache)) {
		const group_index = index[group] = {};
		const done = {};
		const cache = node_cache[group];

		for (let key in keys(cache)) {
			const node = cache[key];

			if (done[node])
				continue;
			done[node] = true;
			group_index[content_key(flatten(node))] = node;
		}
	}

	return index;
}

function apply_nodes(uci, uciconfig, ucinode, node_cache, node_result, log) {
	let added = 0, removed = 0;
	/* Mark the canonical Node objects the foreach loop above has
	 * already updated in place, so the second loop skips them. We
	 * use object identity (the same Node object is held in node_cache
	 * and in node_result, so `seen[node] === node` works as a set),
	 * not the section name or nameHash: the orchestrator hands the
	 * Repository the same Node instances, and tying the marker to the
	 * object means a stale string key cannot match a renamed node. */
	const seen = {};

	/* Built on the first section that is not found by name (see below). */
	let content_index = null;

	uci.foreach(uciconfig, ucinode, (cfg) => {
		/* User-created nodes do not have a grouphash. The
		 * repository must never touch them, even if the
		 * subscription fetch returns nothing for today. */
		if (!cfg.grouphash)
			return null;

		/* No cache entry for this subscription group means
		 * the fetch failed for that URL. Leave the existing
		 * nodes in place so the user does not lose them on
		 * a transient network blip. */
		if (!node_cache[cfg.grouphash] || length(node_cache[cfg.grouphash]) === 0)
			return null;

		let incoming = node_cache[cfg.grouphash][cfg['.name']];

		if (!incoming) {
			/* Not found by section name: the node may simply have been
			 * renamed upstream.  Section names hash the label, so without
			 * this the repository would delete the section and add an
			 * identical one under a new name, taking every reference to it
			 * (`main_node`, `main_udp_node`, urltest members) with it - the
			 * user's node selection silently moves to another server. */
			if (content_index === null)
				content_index = build_content_index(node_cache);

			const key = content_key(cfg);

			incoming = content_index[cfg.grouphash][key];

			if (incoming) {
				/* Claim it: two stored sections with the same content must
				 * not both update themselves into the same node, or the
				 * duplicate would never be pruned. */
				delete content_index[cfg.grouphash][key];
				log(sprintf('Node was renamed upstream: %s -> %s; keeping its section and every reference to it.',
					cfg.label || cfg['.name'], incoming.label || incoming.name));
			}
		}

		if (!incoming) {
			uci.delete(uciconfig, cfg['.name']);
			removed++;
			log(sprintf('Removing node: %s.', cfg.label || cfg['name']));
			return null;
		}

		/* Canonical Node -> flat UCI keys. flatten() drops
		 * nulls so a freshly-saved canonical Node does not
		 * litter /etc/config with `tls_sni ''` entries for
		 * fields the parser never set; the Loader treats null
		 * and absent the same, so this is observably
		 * equivalent. */
		const flat = flatten(incoming);

		/* Write every option the new config carries, including
		 * ones the stored section did not have yet. Walking only
		 * the OLD section's keys used to miss new options
		 * (plugin, tls_sni, packet_encoding) the subscription
		 * started sending after the node was first imported. */
		for (let v in keys(flat))
			uci.set(uciconfig, cfg['.name'], v, flat[v]);

		/* Then drop the options the new config no longer
		 * carries. `.name` / `.type` / `.index` are section
		 * metadata, not options; deleting them is meaningless
		 * at best. */
		for (let v in keys(cfg)) {
			if (substr(v, 0, 1) === '.')
				continue;
			if (!(v in flat))
				uci.delete(uciconfig, cfg['.name'], v);
		}

		seen[incoming] = true;
	});

	for (let nodes in node_result)
		map(nodes, (node) => {
			if (seen[node])
				return null;

			/* normalize() exposes the source label as `name`; `label`
			 * is only set when the orchestrator carries it over. Relying
			 * on `label` alone hashed every node of a subscription to the
			 * same section name, because undefined stringifies
			 * identically - four nodes collapsed into one section mixing
			 * several protocols' options. Accept either. */
			const label = node.label || node.name;

			/* The orchestrator's key is the section name: identical to
			 * md5(grouphash + label) for every node but the ones whose
			 * label is shared by a different server. */
			const nameHash = section_name_for(node, node_cache[node.grouphash])
				|| md5(node.grouphash + label);

			/* The one boundary where a canonical Node becomes UCI keys.
			 *
			 * UCI is a flat key/value store, so this expansion has to
			 * happen somewhere; keeping it inside the Repository's write
			 * path is what lets every other layer - the orchestrator, the
			 * filter, the policy step - speak canonical only. If a field
			 * must not reach UCI, or its UCI name must change, this call
			 * and parser/mapping.uc are the places to look; no caller
			 * hands this function a flat dict. */
			const flat = flatten(node);

			uci.set(uciconfig, nameHash, 'node');
			for (let v in keys(flat))
				uci.set(uciconfig, nameHash, v, flat[v]);

			added++;
			log(sprintf('Adding node: %s.', label));
		});

	return { added, removed };
}

/* --- apply_main_node_refs ---------------------------------------------- */

/* Prune the entries of an UCI list that no longer point at a live
 * node. Used twice below for `main_urltest_nodes` and
 * `main_udp_urltest_nodes`; the helper writes the cleaned list back
 * only when it actually changed, and returns it for the caller to
 * inspect (an empty list is the trigger to switch to first_server). */
function maybeScrubUrltestNodes(uci, uciconfig, ucimain, listOption, log) {
	const old_list = uci.get(uciconfig, ucimain, listOption) || [];
	const cleaned = filter(old_list, (v) => {
		if (!uci.get(uciconfig, v)) {
			log(sprintf('Node %s is gone, removing from urltest list.', v));
			return false;
		}
		return true;
	});
	if (length(cleaned) !== length(old_list))
		uci.set(uciconfig, ucimain, listOption, cleaned);
	return cleaned;
}

/* Switch a main_* field off the dangling reference and onto the first
 * available node. The two callers below differ only in the UCI option
 * name (`main_node` vs `main_udp_node`) and the user-facing log line,
 * so this is what made the pre-refactor code mirror itself.
 *
 * `current_value` is what the field currently points at (the user-chosen
 * section name, the literal 'urltest', or 'same' / 'nil').  We only
 * overwrite the field when the section named by `current_value` no
 * longer exists in UCI; the previous version asked `uci.get(uciconfig,
 * field)` which is "does a section literally named `field` exist" - the
 * config has cfg0xxxx names, never one named `main_node`, so the check
 * was always false and the user's pick got silently replaced with
 * first_server on every subscription update.
 *
 * The new value is also pushed onto `result.log` so the orchestrator
 * can replay it (it uses `result.log` to log the same lines verbatim;
 * the homeproxy-pro.log capture goes through the separate `log` arg). */
function switchMainNodeOffDanglingRef(uci, uciconfig, ucimain, field, current_value, first_server, result, log) {
	if (uci.get(uciconfig, current_value))
		return current_value;
	uci.set(uciconfig, ucimain, field, first_server);
	const msg = sprintf('Main%s node is gone, switching to the first node.',
		field === 'main_udp_node' ? ' UDP' : '');
	log(msg);
	push(result.log, msg);
	return first_server;
}

/* Replace the 4 inline uci.set/commit sites (plus the 2-line
 * 'reset to nil' block) in update_subscriptions.uc. Logic parity:
 *
 *   - if main_node is set and at least one subscription node exists:
 *     * when main_node === 'urltest', scrub main_urltest_nodes down
 *       to nodes that still exist, then switch main_node to the first
 *       surviving one if the urltest set is empty
 *     * otherwise, switch main_node to first_server if its target is
 *       gone
 *     * same shape for main_udp_node, only when main_udp_node is set
 *       AND not 'same'
 *   - if main_node is set but no subscription nodes exist, reset
 *     both main_node and main_udp_node to 'nil'
 *
 * `ctx` carries the inputs the orchestrator used to read from UCI:
 *   { main_node, main_udp_node, has_nodes }
 *
 * Mutates only, no commit. The orchestrator commits once after
 * apply_nodes, this method and scrub_stale_urltest_refs have all
 * staged their changes, so a run is either fully visible or not at all.
 *
 * Returns { main_node: <new>, main_udp_node: <new>, log: [..] } so
 * the orchestrator can log "Main node is gone, switching to ..." /
 * "No available node, disable tproxy." exactly as before. */
function apply_main_node_refs(uci, uciconfig, ucimain, ucinode, ctx, log) {
	/* Object destructuring is not part of the dialect the ucode on the
	 * target accepts (ImmortalWrt ucode 2026.01.16 rejects
	 * `const { a } = x` with "Expecting variable name"), so pull the
	 * fields out by name. tests/ucode/test_ucode_grammar.sh guards this. */
	const main_node = ctx.main_node,
	      main_udp_node = ctx.main_udp_node;
	const result = { main_node, main_udp_node, log: [] };

	if (isEmpty(main_node))
		return result;

	const first_server = uci.get_first(uciconfig, ucinode);
	if (!first_server) {
		/* No nodes left at all: reset both to 'nil'. */
		uci.set(uciconfig, ucimain, 'main_node', 'nil');
		uci.set(uciconfig, ucimain, 'main_udp_node', 'nil');
		result.main_node = 'nil';
		result.main_udp_node = 'nil';
		push(result.log, 'No available node, disable tproxy.');
		return result;
	}

	if (main_node === 'urltest') {
		const cleaned = maybeScrubUrltestNodes(uci, uciconfig, ucimain, 'main_urltest_nodes', log);

		if (!length(cleaned))
			result.main_node = switchMainNodeOffDanglingRef(uci, uciconfig, ucimain, 'main_node', main_node, first_server, result, log);
	} else {
		result.main_node = switchMainNodeOffDanglingRef(uci, uciconfig, ucimain, 'main_node', main_node, first_server, result, log);
	}

	if (!isEmpty(main_udp_node) && main_udp_node !== 'same') {
		if (main_udp_node === 'urltest') {
			const cleaned = maybeScrubUrltestNodes(uci, uciconfig, ucimain, 'main_udp_urltest_nodes', log);

			if (!length(cleaned))
				result.main_udp_node = switchMainNodeOffDanglingRef(uci, uciconfig, ucimain, 'main_udp_node', main_udp_node, first_server, result, log);
		} else {
			result.main_udp_node = switchMainNodeOffDanglingRef(uci, uciconfig, ucimain, 'main_udp_node', main_udp_node, first_server, result, log);
		}
	}

	return result;
}

/* --- scrub_stale_urltest_refs ----------------------------------------- */

/* Walk every routing_node and prune the urltest_nodes list to drop
 * entries that no longer point at a live node. Mutates only: the caller
 * commits once after this returns. Returns { changed } - the number of
 * routing_nodes it rewrote - which is what the old `commits` counter
 * measured (it counted its own commits; the previous code committed
 * inside the foreach loop, once per scrubbed routing_node). */
function scrub_stale_urltest_refs(uci, uciconfig, log) {
	let changed = 0;

	uci.foreach(uciconfig, 'routing_node', (cfg) => {
		if (cfg.node !== 'urltest' || isEmpty(cfg.urltest_nodes))
			return null;

		const cleaned_nodes = filter(cfg.urltest_nodes, (v) => uci.get(uciconfig, v));
		if (length(cleaned_nodes) === length(cfg.urltest_nodes))
			return null;

		uci.set(uciconfig, cfg['.name'], 'urltest_nodes', cleaned_nodes);
		changed++;
		log(sprintf('Routing node %s: removed gone nodes from urltest list.', cfg['.name']));
	});

	return { changed };
}

/* Remove subscription nodes whose group is no longer configured at all.
 *
 * apply_nodes() deliberately leaves a group alone when the fetch produced
 * nothing for it - that is the transient-blip protection (a failed fetch must
 * not delete the user's nodes).  The same "no cache entry" state also arises
 * when the user deletes the subscription URL from the configuration, and then
 * the nodes stayed in /etc/config/homeproxy-pro forever, still compiled into the
 * sing-box outbounds and urltest pools while the UI showed them as ordinary
 * nodes.  Only the orchestrator knows which URLs are still configured, so the
 * set is passed in explicitly: a group that is configured but produced no cache
 * is kept (blip), a group that is not configured is pruned (subscription
 * removed).
 *
 * A section without a grouphash is a user-created node and is never touched.
 * Returns the number of pruned sections.
 */
function prune_orphan_nodes(uci, uciconfig, ucinode, configured_groups, log) {
	let pruned = 0;
	const configured = {};

	for (let group in configured_groups)
		configured[group] = true;

	uci.foreach(uciconfig, ucinode, (cfg) => {
		if (!cfg.grouphash)
			return null;

		if (configured[cfg.grouphash])
			return null;

		uci.delete(uciconfig, cfg['.name']);
		pruned++;
		log(sprintf('Removing node of a removed subscription: %s.', cfg.label || cfg['.name']));
		return null;
	});

	return pruned;
}

export const Repository = {
	apply_nodes,
	apply_main_node_refs,
	scrub_stale_urltest_refs,
	prune_orphan_nodes
};