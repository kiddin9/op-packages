#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * homeproxy-pro.js calcStringMD5() must be *the* MD5 of RFC 1321, because its
 * output is compared against a value another language computed.
 *
 * The contract, end to end:
 *
 *   update_subscriptions.uc  url = replace(url, /#.*$/, ''); md5(url)
 *                            -> written to UCI as the node's `grouphash`
 *   repository.uc            md5(node.grouphash + label)
 *                            -> the UCI section name of a subscription node
 *   view/homeproxy-pro/node.js   hp.calcStringMD5(suburl.replace(/#.*$/, ''))
 *                            -> matched against `grouphash` to decide which
 *                               subscription tab a section belongs to, and
 *                               whether it is a subscription node at all
 *
 * So the browser's digest and ucode's `digest.md5()` have to agree byte for
 * byte. Nothing verified that before this file: the suite had no MD5 vector
 * anywhere, and the implementation it was checking was a minified snippet that
 * did two non-standard things - it normalised CRLF to LF before hashing, and
 * it encoded UTF-8 one UTF-16 code unit at a time, so any astral character
 * (emoji) produced invalid UTF-8. Either one silently mismatches ucode, and
 * the failure mode is quiet: the subscription's nodes stop matching
 * `grouphash`, so they fall out of their tab and reappear as user nodes
 * instead of erroring.
 *
 * Why this is hand-rolled at all is explained at the method. Briefly:
 * crypto.subtle.digest() has no MD5 (the Web Crypto spec lists only SHA-1,
 * SHA-256, SHA-384, SHA-512) and the algorithm cannot be changed without
 * invalidating every existing install's `grouphash`.
 *
 * Two independent references are used, so a shared mistake is unlikely to pass
 * both:
 *
 *   1. the seven test vectors of RFC 1321 appendix A.5, hardcoded here;
 *   2. Node's crypto.createHash('md5').update(s, 'utf8') over a wider corpus,
 *      including the padding boundaries of section 3.1 (55/56, 63/64, 119/120
 *      bytes) and the UTF-8 cases above.
 *
 * tests/ucode/test_subscription_repository.uc pins the ucode half to the same
 * RFC 1321 vectors, which is what turns "each side is standard" into "the two
 * sides are equal".
 *
 * Usage: node tests/frontend-md5.js <repo-root>
 */

'use strict';

const path = require('path');
const crypto = require('crypto');

const { loadLuciModule } = require('./lib/luci-module.js');

const root = path.resolve(process.argv[2] || '.');

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

/* calcStringMD5() only needs the module's own class; the deps are the same
 * inert set tests/frontend-validators.js uses, since the method touches none
 * of them. */
const hp = loadLuciModule(
	path.join(root, 'htdocs/luci-static/resources/homeproxy-pro.js'),
	{
		baseclass: { extend: (o) => o },
		form: { DynamicList: { extend: (o) => o } },
		fs: {}, rpc: {}, uci: {}, ui: {}
	});

/* An independent MD5, from the platform, as the second opinion. */
const reference = (s) => crypto.createHash('md5').update(s, 'utf8').digest('hex');

/* --- 1. RFC 1321 appendix A.5, verbatim -------------------------------- */

const RFC1321 = [
	[ '', 'd41d8cd98f00b204e9800998ecf8427e' ],
	[ 'a', '0cc175b9c0f1b6a831c399e269772661' ],
	[ 'abc', '900150983cd24fb0d6963f7d28e17f72' ],
	[ 'message digest', 'f96b697d7cb7938d525a2f31aaf161d0' ],
	[ 'abcdefghijklmnopqrstuvwxyz', 'c3fcd3d76192e4007dfb496cca67e13b' ],
	[ 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789',
		'd174ab98d277d9f5a5611c2c9f419d9f' ],
	[ '12345678901234567890123456789012345678901234567890123456789012345678901234567890',
		'57edf4a22be3c955ac49da2e2107b67a' ]
];

for (const [ input, expected ] of RFC1321) {
	const got = hp.calcStringMD5(input);
	check(`RFC 1321 A.5 ${JSON.stringify(input.slice(0, 24))}`, got === expected,
		`got ${got}, expected ${expected}`);
}

/* --- 2. shape ---------------------------------------------------------- */

check('output is lowercase hex', /^[0-9a-f]{32}$/.test(hp.calcStringMD5('anything')));
check('output is 32 characters', hp.calcStringMD5('anything').length === 32,
	String(hp.calcStringMD5('anything').length));

/* --- 3. the two divergences the old body had --------------------------- */

/* It called `e.replace(/\r\n/g, '\n')` first, so these two inputs hashed
 * alike. RFC 1321 hashes the bytes it is given, and so does ucode. */
check('CRLF is not normalised to LF',
	hp.calcStringMD5('\r\n') === reference('\r\n') &&
	hp.calcStringMD5('\r\n') !== hp.calcStringMD5('\n'),
	`CRLF=${hp.calcStringMD5('\r\n')} LF=${hp.calcStringMD5('\n')}`);

/* It encoded one UTF-16 code unit at a time, so a surrogate pair became two
 * orphaned three-byte sequences instead of one four-byte sequence. */
check('an astral character uses real UTF-8',
	hp.calcStringMD5('\u{1F600}') === reference('\u{1F600}'),
	`got ${hp.calcStringMD5('\u{1F600}')}, expected ${reference('\u{1F600}')}`);

check('CJK uses real UTF-8',
	hp.calcStringMD5('\u4e2d\u6587') === reference('\u4e2d\u6587'),
	`got ${hp.calcStringMD5('\u4e2d\u6587')}, expected ${reference('\u4e2d\u6587')}`);

/* --- 4. cross-check against the platform MD5 --------------------------- */

const corpus = [
	'',
	' ',
	'https://example.com/sub?token=abc',
	'https://example.com/sub?token=abc#Node%20Name',
	'https://sub.example.com/api/v1/client/subscribe?token=deadbeef',
	'\u4e2d\u6587',
	'\u{1F600}',
	'\u{1F1E8}\u{1F1F3} flag pair',
	'mixed \u4e2d\u6587 and \u{1F600} emoji',
	'\t\n\r\n\u0000',
	'y'.repeat(54), 'y'.repeat(55), 'y'.repeat(56), 'y'.repeat(57),
	'y'.repeat(62), 'y'.repeat(63), 'y'.repeat(64), 'y'.repeat(65),
	'y'.repeat(118), 'y'.repeat(119), 'y'.repeat(120), 'y'.repeat(121),
	'y'.repeat(1000),
	'\u00e9'.repeat(40),
	'\u{1F600}'.repeat(20)
];

for (const input of corpus) {
	const got = hp.calcStringMD5(input);
	const expected = reference(input);
	check(`cross-check ${input.length} bytes ${JSON.stringify(input.slice(0, 16))}`,
		got === expected, `got ${got}, expected ${expected}`);
}

/* --- 5. the grouphash shape, exactly as both sides build it ------------ */

/* node.js hashes the subscription URL with its fragment stripped; the
 * fragment carries the label a user appended and is deliberately excluded, so
 * appending one must not move the digest. */
const base = 'https://example.com/sub?token=abc';
check('stripping the fragment is what makes the two forms agree',
	hp.calcStringMD5(base) === hp.calcStringMD5(base + '#Some%20Label'.replace(/#.*$/, '')),
	`${hp.calcStringMD5(base)} vs ${hp.calcStringMD5(base + '#Some%20Label'.replace(/#.*$/, ''))}`);

/* --- 6. non-strings fail loudly ---------------------------------------- */

/* The old body threw here only by accident (`null.replace` is a TypeError).
 * TextEncoder would encode the text "null" and return a digest, which would
 * silently name a UCI section after a string nobody asked for - so the check
 * is explicit and this test keeps it that way. */
for (const bad of [ null, undefined, 42, {}, [], true ]) {
	const label = bad === null ? 'null' : (Array.isArray(bad) ? 'array' : typeof bad);
	let threw = null;
	try {
		hp.calcStringMD5(bad);
	}
	catch (e) {
		threw = e;
	}
	check(`calcStringMD5 rejects ${label}`, threw instanceof TypeError,
		threw ? String(threw) : 'returned a digest instead of throwing');
}

console.log(`frontend md5: ${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
