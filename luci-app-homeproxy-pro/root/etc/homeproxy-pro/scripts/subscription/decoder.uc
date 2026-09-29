/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Pure subscription decoder. The fetcher returns raw bytes
 * and the orchestrator used to inline the JSON / base64 / SIP008
 * handling. Pulling it out gives the orchestrator a single
 * `decode(content, log, url)` call and lets us unit-test each input
 * shape without involving the network or UCI.
 *
 * Three input shapes are recognised, in order:
 *   1. JSON with a top-level 'servers' array (clash proxy-provider)
 *   2. JSON array directly (the same data, just unwrapped)
 *   3. Shadowsocks SIP008 JSON: top-level array of objects with
 *      server+method. Each entry is tagged nodetype='sip008' so the
 *      orchestrator can dispatch them differently downstream.
 *
 * On JSON failure, decode the content as base64 and split on '\n'
 * to get one share-link URI per line (sing-box subscription format).
 *
 * On total failure (no JSON, no base64), return an empty list and
 * let the caller log the empty result.
 *
 * `url` is optional and only used to enrich the parse-failed log
 * line; the decoder itself never makes a network call.
 */

'use strict';

import { isEmpty, decodeBase64Str, redactUrl } from '../homeproxy-pro.uc';

export function decode(content, log, url) {
	if (isEmpty(content))
		return [];

	let nodes;
	try {
		const parsed = json(content);
		nodes = parsed.servers || parsed;

		/* Shadowsocks SIP008: each entry is a JSON object with
		 * server + method, not a URI string.
		 *
		 * The probe has to check the type first.  It used to be a bare
		 * `nodes[0].server`, which THROWS in ucode when nodes[0] is a
		 * string ("left-hand side expression is not an array or
		 * object") - and the throw was swallowed by the JSON
		 * try/catch below, so a perfectly valid `{"servers":["vless://…"]}`
		 * or `["vless://…"]` subscription fell through to the base64
		 * fallback, failed there too and decoded to an empty list.  Two
		 * real subscription shapes were silently discarded, and the
		 * decoder test had recorded that as the contract.  The same
		 * guard applies inside the loop so a mixed list (SIP008 objects
		 * plus share links) keeps both halves instead of losing
		 * everything on the first string. */
		if (type(nodes[0]) === 'object' && nodes[0].server && nodes[0].method) {
			for (let i = 0; i < length(nodes); i++)
				if (type(nodes[i]) === 'object')
					nodes[i].nodetype = 'sip008';
		}
	} catch (e) {
		/* The URL carries the subscription token and this line lands in
		 * homeproxy-pro.log, which is world-readable.  fetcher.uc and the
		 * orchestrator both redact; this path was missed. */
		const tag = url ? sprintf('for %s, ', redactUrl(url)) : '';
		log(sprintf('JSON parse failed %strying base64: %s', tag, e.message));
		const decoded = decodeBase64Str(content);
		nodes = decoded ? split(trim(decoded), '\n') : [];
	}

	return nodes;
};
