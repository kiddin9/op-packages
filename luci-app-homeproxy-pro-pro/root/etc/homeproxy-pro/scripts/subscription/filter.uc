/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Pure subscription filter. The orchestrator
 * (update_subscriptions.uc) used to inline both the keyword
 * whitelist/blacklist check and the post-parse policy application
 * (tls.insecure override, protocol_options.packet_encoding for
 * vless/vmess). They live here so the orchestrator stays focused on
 * the fetch/cache/repository flow and the pure logic is unit-testable
 * without UCI access.
 *
 * Neither function touches module state: mode / keywords / opts
 * come in as arguments, and a logger is passed in for the
 * invalid-regex warning. That makes the module callable from a
 * plain test stub and means the orchestrator can keep its own
 * file-writer log() around the call.
 */

'use strict';

import { isEmpty } from '../homeproxy.uc';

/* Decide whether a node named `name` should be dropped. `mode` is
 * one of:
 *   'disabled'  - filter is off, return false (keep)
 *   'blacklist' - drop if any keyword regex matches
 *   'whitelist' - drop unless any keyword regex matches
 *
 * `keywords` is a list of strings; each is compiled as a regexp.
 * One bad regex is logged and skipped, not treated as fatal - this
 * matches the pre-B1 behaviour, where a stray `[` would not block
 * the whole subscription.
 *
 * Returns true when the node should be skipped. */
export function check(name, mode, keywords, log) {
	if (isEmpty(name) || mode === 'disabled' || isEmpty(keywords))
		return false;

	let matched = false;
	for (let i in keywords) {
		let patten;
		try {
			patten = regexp(i);
		} catch (e) {
			log(sprintf('Skipping invalid filter keyword regex: %s.', i));
			continue;
		}
		if (patten && match(name, patten))
			matched = true;
	}
	if (mode === 'whitelist')
		matched = !matched;

	return matched;
};

/* Apply the two policy tweaks the orchestrator used to do inline. The subject
 * is a canonical Node - the same shape parser/normalize.uc produces and
 * parser/flatten.uc turns back into UCI keys - not the parser's flat
 * UCI-key dict:
 *
 *   - tls.insecure is set when the node has TLS enabled and the user opted in
 *     via subscription.allow_insecure='1'
 *   - protocol_options.packet_encoding is set on vless/vmess nodes to the
 *     subscription's default
 *
 * This used to run on the flat dict, which is why the orchestrator applied
 * policy on one representation and handed a different one to the Repository.
 * The canonical Node is now the only business object between the parser and
 * the Repository, and this was the last step still forcing the flat shape.
 * The tweaks are a property of the subscription, not of the parsed link, so
 * they deliberately do not take part in the duplicate fingerprint - which is
 * computed from the parser output before this runs.
 *
 * Mutates and returns the node; the return value is the same object as the
 * input, so callers can chain. */
export function apply_policy(node, opts) {
	if (!node)
		return node;

	if (node.tls && node.tls.enabled === '1' && opts.allow_insecure === '1')
		node.tls.insecure = '1';

	if (node.type in ['vless', 'vmess']) {
		/* normalize() always builds protocol_options; a hand-made node
		 * (a test fixture, a future caller) may not have it, and the flat
		 * version simply created the key. */
		if (!node.protocol_options)
			node.protocol_options = {};

		node.protocol_options.packet_encoding = opts.packet_encoding;
	}

	return node;
};
