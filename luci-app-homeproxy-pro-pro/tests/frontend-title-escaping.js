#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Title escaping and subscription-URL parsing.
 *
 * Two sinks with different properties, which is the whole point of this test:
 *
 *   - A form *tab* title is a bare string child of E('a', ...), and LuCI's
 *     dom.append() assigns a bare string to innerHTML.  One decode, so one
 *     level of escaping is both necessary and sufficient.
 *
 *   - A GridSection *modal* title goes through form.titleFn(), which runs the
 *     value through stripTags().  stripTags' documented contract is "HTML tags
 *     removed, and HTML entities DECODED" - it parses `<div>${s}</div>` and
 *     returns textContent - and the decoded result is then handed to the same
 *     innerHTML sink.  Escaping is therefore not enough there, and is in fact
 *     worse than nothing: `&lt;img&gt;` would be decoded back into markup.
 *
 * The test drives the same two decodes the framework performs, so a value that
 * would become markup in the browser fails here instead.
 *
 * Usage: node tests/frontend-title-escaping.js <repo-root>
 */

'use strict';

const path = require('path');

const { loadLuciModule } = require('./lib/luci-module.js');

const root = path.resolve(process.argv[2] || '.');

let checks = 0, failures = 0;
function check(what, ok, detail) {
	checks++;
	if (ok) return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

/* uci.get is what loadModalTitle reads the label through; keep it mutable so
 * the test can present a hostile label. */
let label = null;
const hp = loadLuciModule(
	path.join(root, 'htdocs/luci-static/resources/homeproxy.js'),
	{ baseclass: { extend: (o) => o }, form: { DynamicList: { extend: (o) => o } },
	  fs: {}, rpc: {}, ui: {},
	  uci: { get: (_c, _s, o) => (o === 'label' ? label : null) } });

/* Models what form.stripTags() does to a string: parse it as the innerHTML of
 * a <div>, then read the text back.  For the entities that matter here that is
 * exactly one level of entity decoding - which is why it turns '&lt;' into the
 * character '<'.  Only the five named entities and numeric character
 * references are modelled; that is enough, because those are the only ways to
 * spell '<' without writing it. */
function stripTags(s) {
	if (typeof s == 'string' && !/[<>&]/.test(s))
		return s;

	/* A raw tag is dropped by the parse, which is what makes a *raw* '<...>'
	 * label safe today; only the text outside tags survives. */
	const withoutTags = s.replace(/<[^>]*>/g, '');

	return decodeEntitiesOnce(withoutTags);
}

function decodeEntitiesOnce(s) {
	const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0' };
	return s.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (m, body) => {
		if (body[0] === '#') {
			const code = body[1] === 'x' || body[1] === 'X'
				? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
			return Number.isFinite(code) ? String.fromCodePoint(code) : m;
		}
		return Object.prototype.hasOwnProperty.call(named, body) ? named[body] : m;
	});
}

/* The property that decides whether assigning a string to innerHTML can start
 * a tag: no literal '<' may survive stripTags' single decode.
 *
 * Two callers, deliberately kept apart, because conflating them hides bugs:
 * rendersAsMarkupAfterEscape() takes a RAW value and applies the sanitizer
 * first, so it tests the sanitizer; titleBecomesMarkup() takes a value that
 * has already been sanitized (the output of loadModalTitle) and must NOT
 * sanitize it again - doing so would mask a call site that forgot to. */
function titleBecomesMarkup(alreadyEscaped) {
	return stripTags(alreadyEscaped).includes('<');
}

function rendersAsMarkupAfterEscape(raw) {
	return titleBecomesMarkup(hp.escapeTitleText(raw));
}

const PAYLOADS = [
	'&lt;img src=x onerror=alert(1)&gt;',   // the reported vector
	'<img src=x onerror=alert(1)>',          // raw tag: safe before, must stay safe
	'&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;',
	'&#60;script&#62;alert(1)&#60;/script&#62;',
	'&#x3c;script&#x3e;',
	'"><script>alert(1)</script>',
	"'><svg onload=alert(1)>",
	'&',
	'&&lt;&lt;',
	'a < b > c'
];

for (const p of PAYLOADS) {
	check(`escapeTitleText leaves no live markup for ${JSON.stringify(p)}`,
		!rendersAsMarkupAfterEscape(p),
		`stripTags(escapeTitleText(x)) = ${JSON.stringify(stripTags(hp.escapeTitleText(p)))}`);
}

/* And it must not mangle ordinary names. */
for (const name of ['Tokyo-01', '香港 01', 'a & b', 'node (backup)', 'im?possible', '100%']) {
	check(`escapeTitleText keeps ${JSON.stringify(name)} readable`,
		stripTags(hp.escapeTitleText(name)) === name,
		`got ${JSON.stringify(stripTags(hp.escapeTitleText(name)))}`);
}

/* escapeHtml is the one-decode sink: it must not emit a literal '<' at all,
 * and exactly one decode must give the original back - no more (the value is
 * fully escaped) and no less (it is escaped deeply enough that a single decode
 * cannot re-introduce markup).
 *
 * This check used to read `!decodeEntitiesOnce(escaped).includes('<') || true`,
 * which is unconditionally true, so it never checked anything: for the raw-tag
 * payloads one decode *does* contain '<' (that is what a one-level escape
 * means), and the `|| true` was papering over the wrong property. */
for (const p of PAYLOADS) {
	const escaped = hp.escapeHtml(p);
	check(`escapeHtml emits no literal '<' for ${JSON.stringify(p)}`,
		!escaped.includes('<') && !escaped.includes('>'),
		JSON.stringify(escaped));
	const decoded = decodeEntitiesOnce(escaped);
	check(`escapeHtml survives exactly one decode for ${JSON.stringify(p)}`,
		decoded === p,
		`one decode gave ${JSON.stringify(decoded)}, expected ${JSON.stringify(p)}`);
}

/* The reason escapeTitleText exists at all: on the *raw* tag case, plain
 * escaping hands stripTags something it decodes straight back into markup.
 * This is not a defect in escapeHtml - it is the wrong tool for this sink. */
check('escapeHtml would be unsafe for the modal title (raw tag decoded back)',
	stripTags(hp.escapeHtml('<img src=x onerror=alert(1)>')).includes('<'),
	'if this ever stops being true the comment above is stale');

/* loadModalTitle must use the stripTags-aware escape on the label. */
for (const p of ['&lt;img src=x onerror=alert(1)&gt;', '<img src=x onerror=alert(1)>']) {
	label = p;
	const title = hp.loadModalTitle('Node', 'Add', 'homeproxy', 'n1');
	check(`loadModalTitle escapes the label ${JSON.stringify(p)}`,
		!titleBecomesMarkup(title),
		`title = ${JSON.stringify(title)} -> ${JSON.stringify(stripTags(title))}`);
}
label = null;
check('loadModalTitle falls back to addtitle without a label',
	hp.loadModalTitle('Node', 'Add', 'homeproxy', 'n1') === 'Add');

/* --- subscriptionInfo: the crash and the tab-title sink ------------------ */

/* A fragment of '#%' or '#100%' is accepted by the form validator (it only
 * needs new URL() to succeed and a hostname to exist) but makes
 * decodeURIComponent throw.  That threw out of render() before m.render(),
 * so the whole Node Settings page failed to render. */
for (const u of ['https://h/p#%', 'https://h/p#100%', 'https://h/p#%zz', 'https://h/p#a%']) {
	let info = null, threw = null;
	try { info = hp.subscriptionInfo(u); } catch (e) { threw = e; }
	check(`subscriptionInfo does not throw on ${u}`, threw === null, threw && threw.message);
	check(`subscriptionInfo still returns a hash for ${u}`,
		info && typeof info.hash === 'string' && info.hash.length === 32,
		info && JSON.stringify(info.hash));
	/* The fallback has to be the raw fragment, not the whole URL: a bare
	 * decodeURIComponent() would be caught by the outer guard and display
	 * 'https://h/p#100%' in the tab, which reads as a bug to the user. */
	check(`subscriptionInfo shows the raw fragment for ${u}`,
		info && info.title === u.slice(u.indexOf('#') + 1),
		info && JSON.stringify(info.title));
}

/* A value UCI may hold whatever another package wrote. */
for (const junk of ['not a url', '', null, undefined, 42, {}]) {
	let threw = null;
	try { hp.subscriptionInfo(junk); } catch (e) { threw = e; }
	check(`subscriptionInfo tolerates ${JSON.stringify(junk)}`, threw === null, threw && threw.message);
}
check('subscriptionInfo returns null for an empty string', hp.subscriptionInfo('') === null);
check('subscriptionInfo returns null for a non-string', hp.subscriptionInfo(42) === null);

/* The tab-title path renders the fragment through innerHTML.  Wrapped so a
 * regression fails with a named check instead of a stack trace. */
function info(label, url) {
	try {
		return hp.subscriptionInfo(url);
	}
	catch (e) {
		check(`subscriptionInfo must not throw for ${label}`, false, `${e.name}: ${e.message}`);
		return { hash: '', title: '' };
	}
}

const hostile = info('a raw-tag fragment', 'https://e.com/#<img src=x onerror=alert(1)>');
check('subscriptionInfo escapes a raw-tag fragment',
	!hostile.title.includes('<') && !hostile.title.includes('>'),
	JSON.stringify(hostile.title));

const encoded = info('an entity-encoded fragment', 'https://e.com/#&lt;img src=x onerror=alert(1)&gt;');
check('subscriptionInfo escapes an entity-encoded fragment',
	!encoded.title.includes('<') && !encoded.title.includes('>'),
	JSON.stringify(encoded.title));

const named = info('a percent-encoded fragment', 'https://e.com/#Tokyo%20%26%20Osaka');
check('subscriptionInfo keeps %26 as & (one decode, then escape)',
	named.title === 'Tokyo &amp; Osaka', JSON.stringify(named.title));

const plain = info('a plain URL', 'https://sub.example.com/path');
check('subscriptionInfo falls back to the hostname without a fragment',
	plain.title === 'sub.example.com', JSON.stringify(plain.title));

/* The hash must ignore the fragment, so two URLs that differ only by fragment
 * map to the same subscription. */
check('subscriptionInfo hashes the URL without its fragment',
	info('a fragment x', 'https://e.com/a#x').hash === info('a fragment y', 'https://e.com/a#y').hash);

console.log(`frontend title escaping: ${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
