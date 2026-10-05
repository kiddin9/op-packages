#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * PR-03 (Subscription Transaction Boundary): integration test for
 * subscription/repository.uc. The repository writes to the UCI
 * cursor that is passed in, which means the test needs a sandboxed
 * config dir. tests/ucode/test_subscription_repository.sh stages
 * the dir + the pre-existing UCI file and points the cursor at the
 * staging root. The test then exercises the four paths the
 * orchestrator relies on:
 *
 *   - a user-created node (no grouphash) is preserved
 *   - a subscription node still in the cache is updated in place
 *   - a subscription node dropped from the cache is deleted
 *   - a new node in the cache but not in UCI is added under the
 *     md5(groupHash + label) section name
 *   - a node whose label changed but whose content did not keeps its
 *     section (and with it every reference to it), and is not re-added
 *   - two stored sections with the same content: only one may claim it
 *
 * PR-03 changes the input contract: Repository now accepts
 * canonical Node objects (post- parser/normalize), and flattens
 * them via parser/flatten internally. The orchestrator hands
 * Repository.normalize(parse_uri(uri)) directly; the test builds
 * the canonical shape explicitly.
 *
 * Returns 0 on success, 1 on any mismatch. Counts and section
 * names are checked with cursor.get_all() against the live cursor
 * so the test does not need to parse the UCI file by hand.
 */

'use strict';

import { cursor } from 'uci';
import { md5 } from 'digest';
import { readfile } from 'fs';

import { Repository } from './subscription/repository.uc';

/* PR-03: helper for building canonical Node fixtures. The
 * orchestrator gets canonical Nodes from normalize(parse_uri(...));
 * the test feeds them by hand so the repository's input contract
 * (canonical Node, not flat UCI) is what gets exercised. */
function canonical_node(opts) {
	return {
		id: null,
		name: opts.label,
		type: opts.type,
		address: opts.address,
		port: opts.port || null,
		common: {},
		credentials: {},
		tls: { enabled: null, ech: {}, utls: {}, reality: {} },
		transport: { type: null },
		multiplex: { enabled: null, brutal: {} },
		protocol_options: {},
		grouphash: opts.grouphash
		/* No `label`: normalize() sets `name` and the orchestrator adds
		 * `label` only when carrying it over. This helper used to set
		 * `label` too, which is exactly why the section-name collision
		 * below went unnoticed - it made the fixture agree with the
		 * repository instead of with the model. */
	};
}

const CFG = 'homeproxy-pro';
const TYPE = 'node';

/* A2 (single commit): the repository must stage mutations and commit nothing.
 * Unlike the cursor-based checks below, "did it commit" cannot be read out of
 * the cursor - a commit is exactly what makes the cursor and the file agree -
 * so the assertion is behavioural: the file on disk is byte-identical before
 * and after each repository call, and only the test's own commit (standing in
 * for the orchestrator's) makes the change durable. */
const CONFIG_PATH = ARGV[0] + '/' + CFG;

/* apply_main_node_refs() reports the urltest prune through the log()
 * callback and the main_node switches through the returned result.log,
 * so the test needs to see both. */
const seen = [];
const LOG = (...args) => push(seen, join(' ', args));

let failures = 0;
let checks = 0;

function expect(name, actual, expected) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', expected)) {
		printf('FAIL %s: expected %J, got %J\n', name, expected, actual);
		failures++;
	}
}

const uci = cursor(ARGV[0]);
uci.load(CFG);

/* groupHash is what the orchestrator hands the repository. It
 * is a per-subscription-url identifier - any opaque string the
 * orchestrator likes, as long as it stays stable across fetches.
 * Two distinct URLs would get two distinct groupHash values, so
 * the test uses a single group to focus on the per-node logic. */
const groupHash = 'test-group';

/* Pre-existing UCI state: a user node, a subscription node that
 * the new cache will update, and a subscription node the new
 * cache will drop. The cursor.commit() below persists them so
 * the repository's foreach() sees them when it runs. */
const u_user = 'cfgUSER0001';
const u_keep = 'cfgKEEP00001';
const u_drop = 'cfgDROP00001';

uci.set(CFG, u_user, TYPE);
uci.set(CFG, u_user, 'label',  'user-only');
uci.set(CFG, u_user, 'type',   'vless');
uci.set(CFG, u_user, 'address', 'user.example.com');

uci.set(CFG, u_keep, TYPE);
uci.set(CFG, u_keep, 'label',      'kept-node');
uci.set(CFG, u_keep, 'grouphash',  groupHash);
uci.set(CFG, u_keep, 'type',       'vless');
uci.set(CFG, u_keep, 'address',    'old.example.com');
uci.set(CFG, u_keep, 'stale_field', 'remove-me');

uci.set(CFG, u_drop, TYPE);
uci.set(CFG, u_drop, 'label',     'dropped-node');
uci.set(CFG, u_drop, 'grouphash', groupHash);
uci.set(CFG, u_drop, 'type',      'vless');
uci.set(CFG, u_drop, 'address',   'gone.example.com');

uci.commit(CFG);

/* What the orchestrator would have built during the fetch phase
 * for a successful subscription update. Two canonical Nodes from
 * the cache:
 *   - the updated version of u_keep (with new address)
 *   - a brand-new node (will be added under md5(group+label))
 * u_drop is intentionally absent -> the repository must delete it. */
const kept_updated = canonical_node({
	grouphash: groupHash,
	label: 'kept-node',
	type: 'vless',
	address: 'new.example.com',
	port: '443'
});

const new_label = 'fresh-node';
const new_node = canonical_node({
	grouphash: groupHash,
	label: new_label,
	type: 'trojan',
	address: 'fresh.example.com',
	port: '8443'
});

const node_cache = {
	[groupHash]: {
		[u_keep]: kept_updated,
		[md5(groupHash + new_label)]: new_node
	}
};

const node_result = [[kept_updated, new_node]];

const disk_before_apply = readfile(CONFIG_PATH);
const result = Repository.apply_nodes(uci, CFG, TYPE, node_cache, node_result, LOG);
expect('counts: added',   result.added,   1);
expect('counts: removed', result.removed, 1);
expect('commit ownership: apply_nodes left the file untouched',
	readfile(CONFIG_PATH), disk_before_apply);

/* The caller's single transaction boundary (A2). Everything below reads the
 * on-disk state, so this commit is what makes it visible. */
uci.commit(CFG);

/* Reload to see the on-disk state. */
uci.load(CFG);

/* User node preserved verbatim. */
{
	const cfg = uci.get_all(CFG, u_user);
	expect('user: section exists', 'address' in cfg, true);
	expect('user: address kept',  cfg.address,      'user.example.com');
	expect('user: no grouphash leaked in',
		'grouphash' in cfg, false);
}

/* Updated node: the new address is written, the field the new config
 * no longer carries is dropped, and a field that exists only in the
 * new config (port, in this fixture) is ADDED. The old
 * implementation walked only the stored section's keys, so a
 * subscription that started sending a new option could never update
 * an existing node; that behaviour was previously locked in here as a
 * "quirk" and is now asserted to be fixed. */
{
	const cfg = uci.get_all(CFG, u_keep);
	expect('kept: section exists',    'address' in cfg,  true);
	expect('kept: address updated',   cfg.address,       'new.example.com');
	expect('kept: stale_field gone',  'stale_field' in cfg, false);
	expect('kept: new field added',   cfg.port,          '443');
}

/* Dropped node is gone. */
{
	const cfg = uci.get_all(CFG, u_drop);
	/* get_all on a deleted section returns the section metadata
	 * (with .name) but no actual options. The cleanest check is
	 * that the label is no longer present. */
	expect('drop: section removed', 'label' in cfg, false);
}

/* New node added under the md5(group+label) name. */
{
	const nameHash = md5(groupHash + new_label);
	const cfg = uci.get_all(CFG, nameHash);
	expect('new: section added',  'address' in cfg, true);
	expect('new: address correct', cfg.address,      'fresh.example.com');
	expect('new: type correct',   cfg.type,         'trojan');
	expect('new: grouphash set',  cfg.grouphash,    groupHash);
}

/* --- PR-03: apply_main_node_refs ------------------------------------ */

/* Use a fresh cursor so the apply_nodes state above does not pollute the
 * urltest-list assertions below. */
const uci2 = cursor(ARGV[0]);
uci2.load(CFG);

/* The sandbox's first `node` section (file order) is cfgUSER0001, which
 * is what apply_main_node_refs() falls back to when a main_node target is
 * gone. Assert against it explicitly rather than hard-coding a value that
 * only holds for one sandbox layout. */
const FIRST_NODE = 'cfgUSER0001';

const groupB = 'groupB';
const n_alive = 'cfgALIVE0001';
/* Deliberately never created: the point of the prune case is an
 * urltest_nodes entry whose section no longer exists. */
const n_gone = 'cfgGONE00001';

uci2.set(CFG, n_alive, TYPE);
uci2.set(CFG, n_alive, 'label',     'alive-node');
uci2.set(CFG, n_alive, 'grouphash', groupB);
uci2.set(CFG, n_alive, 'type',      'vless');
uci2.set(CFG, n_alive, 'address',   'alive.example.com');

uci2.set(CFG, 'config', 'main_node', 'urltest');
uci2.set(CFG, 'config', 'main_urltest_nodes', [n_alive, n_gone]);
uci2.commit(CFG);
uci2.load(CFG);

const disk_before_refs = readfile(CONFIG_PATH);
const main_refs = Repository.apply_main_node_refs(
	uci2, CFG, 'config', TYPE,
	{ main_node: 'urltest', main_udp_node: 'nil', has_nodes: true },
	LOG
);
expect('main_node_refs: main_node kept as urltest',
	main_refs.main_node, 'urltest');
expect('commit ownership: apply_main_node_refs left the file untouched',
	readfile(CONFIG_PATH), disk_before_refs);

/* The caller's transaction boundary again (A2); the repository never commits,
 * not even on the reconcile paths that used to commit for themselves. */
uci2.commit(CFG);
uci2.load(CFG);
expect('main_node_refs: dead reference pruned',
	sort(uci2.get(CFG, 'config', 'main_urltest_nodes') || []), [n_alive]);
expect('main_node_refs: log line emitted for the prune',
	length(filter(seen, (l) => match(l, /removing from urltest/))),
	1);

/* "main_node points at a live section": the user's choice must be kept.
 *
 * Regression: switchMainNodeOffDanglingRef used to ask
 *   uci.get(uciconfig, field)
 * where field is the *option name* ('main_node'), not the option's
 * current value.  That question is "does a section literally named
 * 'main_node' exist?" - the answer is always false, so the function
 * silently overwrote the user's pick with first_server on every
 * subscription update.  This test pins the new behaviour: same value in,
 * same value out, no UCI mutation, no "switching to" log line. */
uci2.set(CFG, 'config', 'main_node', n_alive);
uci2.commit(CFG);
uci2.load(CFG);

const disk_before_keep = readfile(CONFIG_PATH);
const switches_before = length(filter(seen, (l) => match(l, /switching to/)));
const main_refs_keep = Repository.apply_main_node_refs(
	uci2, CFG, 'config', TYPE,
	{ main_node: n_alive, main_udp_node: 'nil', has_nodes: true },
	LOG
);
expect('main_node_refs: live target kept verbatim',
	main_refs_keep.main_node, n_alive);
expect('main_node_refs: live target left UCI untouched',
	readfile(CONFIG_PATH), disk_before_keep);
expect('main_node_refs: live target emitted no switch log line',
	length(filter(seen, (l) => match(l, /switching to/))),
	switches_before);
uci2.commit(CFG);
uci2.load(CFG);
expect('main_node_refs: live target still in UCI after commit',
	uci2.get(CFG, 'config', 'main_node'), n_alive);

/* "main_node target is gone": point main_node at a section that does not
 * exist. The Repository must switch to the first node in the file. */
uci2.set(CFG, 'config', 'main_node', 'cfgNOPEEEEEE');
uci2.commit(CFG);
uci2.load(CFG);

const disk_before_refs2 = readfile(CONFIG_PATH);
const main_refs2 = Repository.apply_main_node_refs(
	uci2, CFG, 'config', TYPE,
	{ main_node: 'cfgNOPEEEEEE', main_udp_node: 'nil', has_nodes: true },
	LOG
);
expect('main_node_refs: missing target switched to first_server',
	main_refs2.main_node, FIRST_NODE);
expect('main_node_refs: switch logged',
	length(filter(main_refs2.log, (l) => match(l, /switching to/))),
	1);
/* A2: the switch is staged, not committed. */
expect('commit ownership: the main_node switch is not committed by the repository',
	readfile(CONFIG_PATH), disk_before_refs2);
uci2.commit(CFG);
uci2.load(CFG);
expect('main_node_refs: switch persisted to UCI',
	uci2.get(CFG, 'config', 'main_node'), FIRST_NODE);

/* The "no nodes at all" reset path needs a node-free config: delete every
 * node section, then run the reconcile with main_node set. */
for (let s in (uci2.get(CFG, 'config') ? [] : []))
	;
uci2.foreach(CFG, TYPE, (section) => uci2.delete(CFG, section['.name']));
uci2.commit(CFG);
uci2.load(CFG);

expect('main_node_refs: no node sections left',
	uci2.get_first(CFG, TYPE), null);

const disk_before_refs3 = readfile(CONFIG_PATH);
const main_refs3 = Repository.apply_main_node_refs(
	uci2, CFG, 'config', TYPE,
	{ main_node: 'urltest', main_udp_node: 'urltest', has_nodes: false },
	LOG
);
expect('main_node_refs: no-nodes path resets main_node to nil',
	main_refs3.main_node, 'nil');
expect('main_node_refs: no-nodes path resets main_udp_node to nil',
	main_refs3.main_udp_node, 'nil');
/* A2: the reset-to-nil path used to commit for itself; it must not any more. */
expect('main_node_refs: no-nodes path did not commit',
	readfile(CONFIG_PATH), disk_before_refs3);
uci2.commit(CFG);
uci2.load(CFG);
expect('main_node_refs: no-nodes path wrote nil to UCI',
	uci2.get(CFG, 'config', 'main_node'), 'nil');
expect('main_node_refs: no-nodes path wrote nil to UCI for udp',
	uci2.get(CFG, 'config', 'main_udp_node'), 'nil');
expect('main_node_refs: no-nodes path logged the disable',
	length(filter(main_refs3.log, (l) => match(l, /disable tproxy/))),
	1);

/* --- PR-03: scrub_stale_urltest_refs ------------------------------- */

/* A routing_node whose urltest_nodes mixes a live and a missing node. */
const rn_x = 'rn_test';
const n_other = 'cfgOTHER0001';
uci2.set(CFG, n_other, TYPE);
uci2.set(CFG, n_other, 'label',   'other-node');
uci2.set(CFG, n_other, 'type',    'vless');
uci2.set(CFG, n_other, 'address', 'other.example.com');

uci2.set(CFG, rn_x, 'routing_node');
uci2.set(CFG, rn_x, 'node', 'urltest');
uci2.set(CFG, rn_x, 'urltest_nodes', [n_other, n_gone]);
uci2.commit(CFG);
uci2.load(CFG);

const disk_before_scrub = readfile(CONFIG_PATH);
const scrub = Repository.scrub_stale_urltest_refs(uci2, CFG, LOG);
expect('scrub: one routing_node rewritten', scrub.changed, 1);
expect('commit ownership: scrub left the file untouched',
	readfile(CONFIG_PATH), disk_before_scrub);
uci2.commit(CFG);
uci2.load(CFG);
expect('scrub: live ref preserved',
	sort(uci2.get(CFG, rn_x, 'urltest_nodes') || []), [n_other]);

/* An already-clean routing_node must not be rewritten. */
const scrub2 = Repository.scrub_stale_urltest_refs(uci2, CFG, LOG);
expect('scrub: clean state changes nothing', scrub2.changed, 0);

/* --- RFC 1321 MD5 vectors: the cross-language half of the contract ------ */

/* update_subscriptions.uc computes a node's `grouphash` as md5(url, fragment
 * stripped), and the Repository above names each section
 * md5(grouphash + label). The browser compares *its own* MD5 -
 * homeproxy-pro.js calcStringMD5(), which cannot use crypto.subtle because the
 * Web Crypto spec has no MD5 - against that grouphash to decide which
 * subscription tab a section belongs to, and whether it is a subscription
 * node at all.
 *
 * So the two languages have to agree exactly, and nothing in the suite
 * checked it: there was no MD5 vector anywhere, on either side. The failure
 * mode is quiet - a digest that does not match does not raise, it just drops
 * the subscription's nodes out of their tab. tests/frontend-md5.js pins the
 * browser side to these same vectors; this block pins the ucode side, which
 * is what turns "each side is standard" into "the two sides are equal".
 *
 * The last three cover what the browser implementation used to get wrong: it
 * normalised CRLF to LF before hashing, and it encoded UTF-8 one UTF-16 code
 * unit at a time. They are built with chr() rather than spelled as literals
 * so the bytes under test are unambiguous:
 *
 *   U+4E2D U+6587  ->  e4 b8 ad e6 96 87
 *   U+1F600        ->  f0 9f 98 80                                          */
/* --- a renamed node keeps its section --------------------------------- */

/* Section names are md5(grouphash + label), so a subscription that renames a
 * node used to make the repository delete the old section and add an identical
 * one under the new name - taking every reference to it (config.main_node,
 * main_udp_node, the urltest member lists) with it.  Measured on the device
 * before this: "Removing node: OLD-NAME." + "Adding node: NEW-NAME.", the
 * section name changed, and main_node was switched to the new section.  The
 * repository recognises the stored section by its *content* now: same server,
 * same credentials, new label. */
{
	const uci3 = cursor(ARGV[0]);
	uci3.load(CFG);

	const groupR = 'groupRename';
	const u_renamed = 'cfgRENAMED001';

	uci3.set(CFG, u_renamed, TYPE);
	uci3.set(CFG, u_renamed, 'label', 'old-name');
	uci3.set(CFG, u_renamed, 'grouphash', groupR);
	uci3.set(CFG, u_renamed, 'type', 'vless');
	uci3.set(CFG, u_renamed, 'address', 'rename.example.com');
	uci3.set(CFG, u_renamed, 'port', '443');
	uci3.commit(CFG);
	uci3.load(CFG);

	const r_node = canonical_node({
		grouphash: groupR,
		label: 'new-name',
		type: 'vless',
		address: 'rename.example.com',
		port: '443'
	});
	const r_cache = { [groupR]: { [md5(groupR + 'new-name')]: r_node } };

	const r_result = Repository.apply_nodes(uci3, CFG, TYPE, r_cache, [[ r_node ]], LOG);

	expect('rename: not counted as removed', r_result.removed, 0);
	expect('rename: not counted as added',   r_result.added,   0);

	uci3.commit(CFG);
	uci3.load(CFG);

	expect('rename: section kept under its old name',
		'label' in uci3.get_all(CFG, u_renamed), true);
	expect('rename: label updated in place',
		uci3.get_all(CFG, u_renamed).label, 'new-name');
	expect('rename: nothing added under the new name',
		'label' in uci3.get_all(CFG, md5(groupR + 'new-name')), false);
}

/* Two stored sections with identical content must not both update themselves
 * into the same node: the first one claims the content, the duplicate is
 * pruned exactly as before. */
{
	const uci4 = cursor(ARGV[0]);
	uci4.load(CFG);

	const groupD = 'groupDuplicate';
	const u_dup_a = 'cfgDUPA00001';
	const u_dup_b = 'cfgDUPB00001';

	for (let section in [ u_dup_a, u_dup_b ]) {
		uci4.set(CFG, section, TYPE);
		uci4.set(CFG, section, 'label', section);
		uci4.set(CFG, section, 'grouphash', groupD);
		uci4.set(CFG, section, 'type', 'vless');
		uci4.set(CFG, section, 'address', 'dup.example.com');
		uci4.set(CFG, section, 'port', '443');
	}
	uci4.commit(CFG);
	uci4.load(CFG);

	const d_node = canonical_node({
		grouphash: groupD,
		label: 'renamed-dup',
		type: 'vless',
		address: 'dup.example.com',
		port: '443'
	});
	const d_cache = { [groupD]: { [md5(groupD + 'renamed-dup')]: d_node } };

	const d_result = Repository.apply_nodes(uci4, CFG, TYPE, d_cache, [[ d_node ]], LOG);

	expect('duplicate content: one section claims it', d_result.added, 0);
	expect('duplicate content: the other is pruned', d_result.removed, 1);

	uci4.commit(CFG);
	uci4.load(CFG);

	const survived = filter([ u_dup_a, u_dup_b ], (s) => ('label' in uci4.get_all(CFG, s)));
	expect('duplicate content: exactly one section survives', length(survived), 1);
	expect('duplicate content: it carries the new label',
		uci4.get_all(CFG, survived[0]).label, 'renamed-dup');
}

/* --- the orchestrator's key is the section name ----------------------- */

/* Two servers of one subscription can share a label - it is whatever the
 * provider put after '#'.  The orchestrator keeps both and separates them by
 * the content fingerprint, so the second node sits in the cache under a key
 * that is NOT md5(grouphash + label).  The repository has to write that key as
 * the section name, or both nodes end up in one section and one is lost. */
{
	const uci5 = cursor(ARGV[0]);
	uci5.load(CFG);

	const groupS = 'groupSharedLabel';
	const s_first = canonical_node({
		grouphash: groupS,
		label: 'same-label',
		type: 'vless',
		address: 'first.example.com',
		port: '443'
	});
	const s_second = canonical_node({
		grouphash: groupS,
		label: 'same-label',
		type: 'vless',
		address: 'second.example.com',
		port: '443'
	});
	const disambiguated = md5(groupS + 'same-label' + chr(0x00) + 'different-content');
	const s_cache = {
		[groupS]: {
			[md5(groupS + 'same-label')]: s_first,
			[disambiguated]: s_second
		}
	};

	const s_result = Repository.apply_nodes(uci5, CFG, TYPE, s_cache,
		[[ s_first ], [ s_second ]], LOG);
	expect('shared label: both nodes are added', s_result.added, 2);

	uci5.commit(CFG);
	uci5.load(CFG);

	expect('shared label: the first is under md5(grouphash + label)',
		uci5.get_all(CFG, md5(groupS + 'same-label')).address, 'first.example.com');
	expect('shared label: the second is under the disambiguated key',
		uci5.get_all(CFG, disambiguated).address, 'second.example.com');
}

const MD5_CJK = chr(0xe4) + chr(0xb8) + chr(0xad) + chr(0xe6) + chr(0x96) + chr(0x87);
const MD5_EMOJI = chr(0xf0) + chr(0x9f) + chr(0x98) + chr(0x80);

expect('md5: RFC 1321 A.5 ""', md5(''), 'd41d8cd98f00b204e9800998ecf8427e');
expect('md5: RFC 1321 A.5 "a"', md5('a'), '0cc175b9c0f1b6a831c399e269772661');
expect('md5: RFC 1321 A.5 "abc"', md5('abc'), '900150983cd24fb0d6963f7d28e17f72');
expect('md5: RFC 1321 A.5 "message digest"',
	md5('message digest'), 'f96b697d7cb7938d525a2f31aaf161d0');
expect('md5: RFC 1321 A.5 a-z',
	md5('abcdefghijklmnopqrstuvwxyz'), 'c3fcd3d76192e4007dfb496cca67e13b');
expect('md5: RFC 1321 A.5 alphanumeric',
	md5('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'),
	'd174ab98d277d9f5a5611c2c9f419d9f');
expect('md5: RFC 1321 A.5 eighty digits',
	md5('12345678901234567890123456789012345678901234567890123456789012345678901234567890'),
	'57edf4a22be3c955ac49da2e2107b67a');
expect('md5: CJK hashes as UTF-8', md5(MD5_CJK), 'a7bac2239fcdcb3a067903d8077c4a07');
expect('md5: an astral char is one 4-byte sequence',
	md5(MD5_EMOJI), '2a02eac39d716a70ecf37579185927b6');
expect('md5: CRLF is hashed as-is', md5(chr(0x0d) + chr(0x0a)),
	'81051bcc2cf1bedf378224b0a93e2877');
/* The grouphash shape itself: this is md5 of a subscription URL, i.e. what
 * update_subscriptions.uc writes and what node.js has to reproduce after
 * stripping the "#label" fragment. */
expect('md5: the grouphash shape',
	md5('https://example.com/sub?token=abc'), '89167ef6961b44a5ba6e799f7cf8cd30');

printf('%d checks, %d failures\n', checks, failures);
exit(failures ? 1 : 0);