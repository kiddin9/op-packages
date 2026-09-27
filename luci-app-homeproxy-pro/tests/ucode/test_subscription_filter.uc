#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Unit tests for subscription/filter.uc. Both check() and
 * apply_policy() are pure - no UCI access, no module state - so
 * the tests can hand them ordinary values and a no-op logger.
 * apply_policy() takes a canonical Node, so the equivalence block at
 * the end also drives the real normalize()/flatten() pair to prove the
 * move off the flat dict did not change what reaches UCI.
 *
 * Run through tests/ucode/run.sh, which stages the module next to
 * tests/ucode/mocks/homeproxy.uc so the `from 'homeproxy'` import
 * resolves to the test double, and parser/ next to the test so the
 * round-trip imports resolve.
 */

'use strict';

import { check, apply_policy } from 'filter';
import { normalize } from './parser/normalize.uc';
import { flatten } from './parser/flatten.uc';

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

/* --- check(): disabled mode passes everything through --- */
expect('disabled + match',    check('foo',     'disabled', ['foo'], LOG), false);
expect('disabled + miss',     check('foo-bar', 'disabled', ['baz'], LOG), false);
expect('disabled + no kw',    check('foo',     'disabled', [],       LOG), false);

/* --- check(): empty inputs short-circuit --- */
expect('empty name',          check(null, 'blacklist', ['x'], LOG), false);
expect('empty keywords',      check('foo', 'blacklist', [],    LOG), false);

/* --- check(): blacklist --- */
expect('blacklist hit',       check('foo-bar', 'blacklist', ['bar'],     LOG), true);
expect('blacklist miss',      check('foo-bar', 'blacklist', ['baz'],     LOG), false);
expect('blacklist multi-hit', check('foo-bar', 'blacklist', ['baz','bar'],LOG), true);
expect('blacklist invalid-rx skipped',
	check('foo', 'blacklist', ['[unterminated'], LOG), false);

/* --- check(): whitelist inverts the result --- */
expect('whitelist hit (kept)',   check('foo-bar', 'whitelist', ['bar'], LOG), false);
expect('whitelist miss (dropp)', check('foo-bar', 'whitelist', ['baz'], LOG), true);
/* whitelist with no keywords: the early-return guard (isEmpty(keywords))
 * fires before the whitelist inversion, so the node is kept. Documenting
 * this here so a future cleanup of the early-return does not silently
 * change the behaviour. */
expect('whitelist empty kw (kept)', check('foo-bar', 'whitelist', [], LOG), false);

/* --- apply_policy(): canonical Node, tls.insecure override --- */
{
	const node = apply_policy(
		{ type: 'vless', tls: { enabled: '1' }, protocol_options: {} },
		{ allow_insecure: '1', packet_encoding: 'xudp' }
	);
	expect('tls.enabled=1 + allow_insecure=1 sets tls.insecure', node.tls.insecure, '1');
	expect('tls.enabled=1 + allow_insecure=1 also sets packet_encoding',
		node.protocol_options.packet_encoding, 'xudp');
}
{
	const node = apply_policy(
		{ type: 'vless', tls: { enabled: '1' }, protocol_options: {} },
		{ allow_insecure: '0', packet_encoding: 'xudp' }
	);
	expect('tls.enabled=1 + allow_insecure=0 leaves tls.insecure absent',
		'insecure' in node.tls, false);
}
{
	const node = apply_policy(
		{ type: 'vless', tls: { enabled: '0' }, protocol_options: {} },
		{ allow_insecure: '1', packet_encoding: 'xudp' }
	);
	expect('tls.enabled=0 + allow_insecure=1 leaves tls.insecure absent',
		'insecure' in node.tls, false);
}

/* --- apply_policy(): packet_encoding only for vless/vmess --- */
{
	const node = apply_policy(
		{ type: 'trojan', tls: { enabled: '0' }, protocol_options: {} },
		{ allow_insecure: '0', packet_encoding: 'xudp' }
	);
	expect('trojan + packet_encoding not set',
		'packet_encoding' in node.protocol_options, false);
}
{
	const node = apply_policy(
		{ type: 'vmess', tls: { enabled: '0' }, protocol_options: {} },
		{ allow_insecure: '0', packet_encoding: 'xudp' }
	);
	expect('vmess + packet_encoding set', node.protocol_options.packet_encoding, 'xudp');
}

/* A node that did not go through normalize() has no protocol_options; the flat
 * version created that key unconditionally, so this must too. */
{
	const node = apply_policy({ type: 'vless', tls: { enabled: '0' } },
		{ allow_insecure: '0', packet_encoding: 'xudp' });
	expect('a node without protocol_options gets one',
		node.protocol_options.packet_encoding, 'xudp');
}

/* --- apply_policy(): null / undefined guard --- */
expect('apply_policy(null) returns null',
	apply_policy(null, { allow_insecure: '0', packet_encoding: 'xudp' }), null);

/* --- equivalence: flat order and canonical order write the same UCI --------
 *
 * The policy step used to run on the parser's flat dict with normalize() after
 * it; it runs on the canonical Node now. What reaches the router is
 * flatten(node), so the two orders are equivalent exactly when that output is
 * identical - asserted here for every combination the tweaks can produce.
 *
 * The old order is written out as a local helper rather than left in the
 * module: keeping a copy of the thing being replaced is what makes this an
 * equivalence proof instead of a restatement of the new code.
 */
function legacy_flat_policy(flat, opts) {
	if (flat.tls === '1' && opts.allow_insecure === '1')
		flat.tls_insecure = '1';

	if (flat.type in ['vless', 'vmess'])
		flat.packet_encoding = opts.packet_encoding;

	return flat;
}

/* Fresh object per call: apply_policy mutates, so a shared fixture would leak
 * one case's tweaks into the next. */
function flat_vless() {
	return { type: 'vless', address: 'a.example.com', port: '443', label: 'n1',
	         tls: '1', tls_sni: 'a.example.com',
	         uuid: '11111111-2222-3333-4444-555555555555', flow: 'xtls-rprx-vision' };
}
function flat_vless_notls() {
	return { type: 'vless', address: 'a.example.com', port: '443', label: 'n1',
	         tls: '0', uuid: 'u' };
}
function flat_vmess() {
	return { type: 'vmess', address: 'b.example.com', port: '8443', label: 'n2',
	         tls: '0', uuid: 'u' };
}
function flat_trojan() {
	return { type: 'trojan', address: 'c.example.com', port: '443', label: 'n3',
	         tls: '1', password: 'p' };
}

function equivalence(name, fixture, opts) {
	const legacy = flatten(normalize(legacy_flat_policy(fixture(), opts)));
	const node = normalize(fixture());
	apply_policy(node, opts);
	expect(name, sprintf('%J', flatten(node)), sprintf('%J', legacy));
}

equivalence('equivalence: vless + tls + allow_insecure', flat_vless,
	{ allow_insecure: '1', packet_encoding: 'xudp' });
equivalence('equivalence: vless + tls, allow_insecure off', flat_vless,
	{ allow_insecure: '0', packet_encoding: 'xudp' });
equivalence('equivalence: vless without tls, allow_insecure on', flat_vless_notls,
	{ allow_insecure: '1', packet_encoding: 'packet' });
equivalence('equivalence: vmess + packet_encoding', flat_vmess,
	{ allow_insecure: '1', packet_encoding: 'xudp' });
equivalence('equivalence: trojan, no packet_encoding path', flat_trojan,
	{ allow_insecure: '1', packet_encoding: 'xudp' });

/* Both sides could drop the tweak and still be "equivalent", so assert the
 * tweaks actually reach the UCI-key output. */
{
	const node = normalize(flat_vless());
	apply_policy(node, { allow_insecure: '1', packet_encoding: 'xudp' });
	const out = flatten(node);
	expect('the tweaks reach the UCI-key output (tls_insecure)', out.tls_insecure, '1');
	expect('the tweaks reach the UCI-key output (packet_encoding)',
		out.packet_encoding, 'xudp');
}

printf('%d checks, %d failures\n', checks, failures);
exit(failures ? 1 : 0);
