#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Frontend RPC boundary.
 *
 * Every backend call goes through `homeproxy-pro.js`'s `rpcCall()`, which is the
 * one place that knows how to declare an RPC and what to do when the call does
 * not come back.  Before that, nine call sites used
 * `L.resolveDefault(call(), {})` - which does NOT catch a rejection, it only
 * substitutes for a null/undefined *result* - so an unreachable rpcd left the
 * caller's `.then()` never running and said nothing: a status bar that silently
 * stopped updating, a capability list that quietly became empty, and an
 * unhandled rejection in the console.
 *
 * This is a source-level invariant rather than a behavioural test because the
 * behaviour needs a browser; what it can pin down is that nobody reintroduces a
 * second declaration site or the swallowing pattern.
 *
 * Usage: node tests/frontend-rpc-inventory.js <repo-root>
 */

'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(process.argv[2] || '.');
const res = path.join(root, 'htdocs/luci-static/resources');
const files = [
	'homeproxy-pro.js',
	'view/homeproxy-pro/node.js',
	'view/homeproxy-pro/client.js',
	'view/homeproxy-pro/server.js',
	'view/homeproxy-pro/status.js'
];

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

/* Comments have to go before the pattern checks.  A naive grep matched the doc
 * comment in homeproxy-pro.js that quotes the old `L.resolveDefault(call(), {})`
 * idiom - which is exactly the trap the plan records for the Architecture
 * Guard: the check has to talk about code, not about prose describing code.
 * Only block comments are stripped; a `//` stripper would cut real code after a
 * URL in a string literal, and hiding a violation is worse than a false alarm. */
function stripComments(src) {
	return src.replace(/\/\*[\s\S]*?\*\//g, '');
}

const sources = {};
for (const f of files)
	sources[f] = stripComments(fs.readFileSync(path.join(res, f), 'utf8'));

/* 1. One declaration site. */
for (const f of files) {
	const n = (sources[f].match(/\brpc\.declare\s*\(/g) || []).length;
	if (f === 'homeproxy-pro.js')
		check('homeproxy-pro.js declares the RPCs', n === 1, `${n} rpc.declare calls, expected 1 (inside rpcCall)`);
	else
		check(`${f} declares no RPC of its own`, n === 0, `${n} rpc.declare call(s) outside the shared helper`);
}

/* 2. The swallowing pattern: a call wrapped in resolveDefault, which reads like
 *    error handling and is not.
 *
 * The pattern used to be `L\.resolveDefault\(\s*call[A-Za-z0-9_]*\s*\(`, which only
 * matched a callee whose name begins with `call` - the spelling the old code
 * happened to use. `L.resolveDefault(hp.rpcCall(...))` passed it, so the check
 * was almost vacuous, and my own reverse verification missed that because it
 * restored the very spelling the regex hardcodes (a circular proof: the
 * pattern was tested against the only form it recognises).
 *
 * Any resolveDefault wrapping is now flagged, and the pattern is self-tested
 * below so it cannot quietly stop matching. */
const SWALLOW = /L\.resolveDefault\s*\(/g;

check('the resolveDefault pattern matches the real-world spelling',
	'L.resolveDefault(hp.rpcCall("list")).then()'.match(SWALLOW)?.length === 1);
check('the resolveDefault pattern matches the historical spelling',
	'L.resolveDefault(call()).then()'.match(SWALLOW)?.length === 1);

for (const f of files) {
	const m = sources[f].match(SWALLOW) || [];
	check(`${f} does not wrap an RPC call in L.resolveDefault`, m.length === 0, m.join(', '));
}

/* 3. rpcCall itself has to catch, and has to have a fallback. */
const hp = sources['homeproxy-pro.js'];
const helper = /rpcCall\s*\(method,\s*args,\s*options\)\s*\{([\s\S]*?)\n\t\}/.exec(hp);
check('homeproxy-pro.js defines rpcCall', !!helper);
if (helper) {
	check('rpcCall catches a failed call', /\.catch\(/.test(helper[1]));
	check('rpcCall has a fallback for a failed call', /fallback/.test(helper[1]));
	check('rpcCall reports the failure to the user', /addNotification/.test(helper[1]));
}

/* 4. A view that calls rpcCall must import the module that provides it. */
for (const f of files) {
	if (f === 'homeproxy-pro.js') continue;
	if (!/\bhp\.rpcCall\s*\(/.test(sources[f])) continue;
	check(`${f} imports homeproxy-pro for hp.rpcCall`, /'require homeproxy-pro as hp';/.test(sources[f]));
}

/* 5. No file keeps an unused `require rpc` after the conversion. */
for (const f of files) {
	if (f === 'homeproxy-pro.js') continue;
	const requiresRpc = /'require rpc';/.test(sources[f]);
	const usesRpc = /\brpc\./.test(sources[f]);
	check(`${f} has no unused 'require rpc'`, !requiresRpc || usesRpc);
}

console.log(`frontend rpc boundary: ${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
