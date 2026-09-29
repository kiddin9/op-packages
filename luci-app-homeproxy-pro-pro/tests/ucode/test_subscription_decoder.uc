#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * B1.1: unit tests for subscription/decoder.uc. The decoder
 * recognises three input shapes (JSON with `servers`, JSON array,
 * SIP008) and falls back to base64 on JSON failure. Each shape is
 * tested below; the JSON-failure -> base64 path is exercised with
 * a hand-crafted base64 string.
 *
 * Run through tests/ucode/run.sh, which stages the module next to
 * tests/ucode/mocks/homeproxy.uc (which carries decodeBase64Str).
 */

'use strict';

import { decode } from 'decoder';

const LOG = (..._args) => {};

let failures = 0;
let checks = 0;

function expect(name, actual, expected) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', expected)) {
		printf('FAIL %s: expected %J, got %J\n', name, expected, actual);
		failures++;
	}
}

/* --- empty / falsy content short-circuits --- */
expect('empty string', decode('',   LOG, 'sub'), []);
expect('null content', decode(null, LOG, 'sub'), []);

/* --- JSON with 'servers' key (clash proxy-provider) --- */
/* These two shapes used to decode to [] - see the note in
 * subscription/decoder.uc: the SIP008 probe read `.server` off a
 * string, ucode threw, the JSON try/catch swallowed it and the
 * base64 fallback failed.  Both are legitimate subscription
 * payloads whose entries are plain share links, so the assertion is
 * now "the links survive" rather than "the old bug is preserved"
 * (plan 3.2: do not keep a bug as the contract). */
{
	const out = decode('{"servers":["vless://a", "trojan://b"]}', LOG, 'sub');
	expect('json servers: length',  length(out), 2);
	expect('json servers: entry 0', out[0], 'vless://a');
	expect('json servers: entry 1', out[1], 'trojan://b');
}

/* --- JSON array of URI strings --- */
{
	const out = decode('["vless://a", "trojan://b"]', LOG, 'sub');
	expect('json uri array: length',  length(out), 2);
	expect('json uri array: entry 1', out[1], 'trojan://b');
}

/* --- mixed: SIP008 objects and share links in one list --- */
{
	const mixed = '[{"server":"1.2.3.4","server_port":8388,'
	            + '"password":"x","method":"chacha20-ietf-poly1305"},'
	            + '"vless://a"]';
	const out = decode(mixed, LOG, 'sub');
	expect('mixed: length',        length(out), 2);
	expect('mixed: object tagged', out[0].nodetype, 'sip008');
	expect('mixed: link kept',     out[1], 'vless://a');
}

/* --- SIP008: array of objects with server+method --- */
{
	const sip = '[{"server":"1.2.3.4","server_port":8388,'
	          + '"password":"x","method":"chacha20-ietf-poly1305"},'
	          + '{"server":"5.6.7.8","server_port":8389,'
	          + '"password":"y","method":"chacha20-ietf-poly1305"}]';
	const out = decode(sip, LOG, 'sub');
	expect('sip008: length',         length(out), 2);
	expect('sip008: nodetype[0]',    out[0].nodetype, 'sip008');
	expect('sip008: nodetype[1]',    out[1].nodetype, 'sip008');
	expect('sip008: server[0] kept', out[0].server,   '1.2.3.4');
}

/* --- base64 fallback when JSON parse fails --- */
{
	/* "vless://first\ntrojan://second" base64-encoded. Computed
	 * once and hardcoded; if the test ever needs to regenerate it,
	 * the formula is `printf '%s' '<text>' | base64`. */
	const b64 = 'dmxlc3M6Ly9maXJzdAp0cm9qYW46Ly9zZWNvbmQ=';
	const out = decode(b64, LOG, 'sub');
	expect('base64: length', length(out), 2);
	expect('base64: first',  out[0],      'vless://first');
	expect('base64: second', out[1],      'trojan://second');
}

/* --- total failure (neither JSON nor base64) returns [] --- */
{
	const out = decode('!@#$% not json and not base64!', LOG, 'sub');
	expect('total failure: empty', length(out), 0);
}

/* Note: a *mixed* list (first entry is a SIP008 object, rest are
 * URI strings) would crash in ucode on `nodes[1].nodetype = ...`
 * because strings are immutable. The pre-B1 code had the same
 * issue, but in practice subscription providers never emit mixed
 * lists - they're either all SIP008 objects or all URI strings.
 * Documented here so a future cleanup knows not to add mixed
 * fixtures without addressing the immutability first. */

printf('%d checks, %d failures\n', checks, failures);
exit(failures ? 1 : 0);
