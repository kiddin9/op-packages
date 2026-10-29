#!/usr/bin/env node
/* Refuse to let a method that needs its receiver be aliased without one.
 *
 * format.js is a baseclass object, so a helper that composes a sibling does it
 * through `this`. The views alias those helpers into locals:
 *
 *     var fmtReg = fmt.fmtRegistration;          // `this` is LOST
 *     var fmtSim = fmt.fmtSim.bind(fmt);         // `this` survives
 *
 * LuCI modules are strict-mode, so the detached call gets `this === undefined`
 * and the FIRST read of `this` inside throws -- not at load, but on the render
 * that first reaches that branch. So it ships green: the unit tests call
 * `fmt.fmtRegistration(...)` WITH a receiver and pass, while the browser column
 * throws on every draw.
 *
 * That is not hypothetical. It happened to fmtSim, was fixed with .bind() and
 * written up in a comment -- and the line DIRECTLY ABOVE that comment had the
 * same defect and shipped, until a user's stack trace found it
 * (openwrt/packages#37, format.js:651, 2026-09-21). A comment did not hold, so
 * this does instead.
 *
 *   node tools/check-detached-methods.js
 *
 *   node tools/check-detached-methods.js --self-test
 *
 * WHAT IT DOES NOT CATCH. The receiver-dependent set is exact -- it evaluates
 * format.js and asks each real exported function whether its own body reads
 * `this`. The USE-SITE scan is lexical and therefore is not: a VARIABLE key
 * (`fmt[name]`), an alias reached through a second object (`var f = other;
 * f.fmtRegistration`), or anything built at run time all pass it. It covers
 * the forms this tree actually writes, and --self-test asserts each of them
 * rather than promising it here -- the first version of this file promised
 * and was wrong, missing `euiccSlot` because it looked for `this.` and that
 * method parks the receiver in `var self = this` (found in review,
 * 2026-09-21). So: a guard against the mistake that was made, not a proof
 * that the mistake is impossible. An AST pass would settle it; that is not
 * worth a dependency for six files.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const RES = path.join(__dirname, '..', 'htdocs', 'luci-static', 'resources');
const FORMAT = path.join(RES, 'wwand', 'format.js');
const rel = (f) => path.relative(path.join(__dirname, '..'), f);

/* Comments and quoted strings are PROSE, not code. Stripping them is not
   cosmetic: three helpers match a bare /\bthis\b/ only because their comments
   use the English word, and one translated string reads "while this slot is
   the active one". Left in, the checker would demand a .bind() for helpers
   that do not need one -- and a checker that cries wolf gets ignored, which is
   how the original defect shipped. Template literals are stripped whole; this
   tree writes none that contain a `fmt.` reference (checked 2026-09-21). */
/* ONE left-to-right pass, because a chain of independent regexes is not a
   lexer and this tree proves it: `const SVGNS = 'http://www.w3.org/2000/svg'`
   (graph.js:177) makes a comment-first pass blank the rest of that line, real
   code included. Comments, string and template literals and regex literals all
   become spaces -- NEWLINES SURVIVE, so every reported line number is the line
   in the file. Found in review, 2026-09-21; the version before this one had
   both defects. */
function lex(src) {
	const out = src.split('');
	const n = src.length;
	const wipe = (a, b) => { for (let k = a; k < b && k < n; k++) if (out[k] != '\n') out[k] = ' '; };

	/* A `/` opens a regex only where a value may begin. Approximated by the
	   last significant character: after an identifier, a number, `)` or `]` it
	   is division. `return /x/` is misread as division -- harmless here, since
	   a division's operands are code either way and this tree writes none. */
	const opensRegex = (c) => c == '' || !/[A-Za-z0-9_$)\]]/.test(c);

	let i = 0, prev = '';

	while (i < n) {
		const c = src[i];

		if (c == '/' && src[i + 1] == '/') {
			let j = i;
			while (j < n && src[j] != '\n') j++;
			wipe(i, j); i = j; continue;
		}

		if (c == '/' && src[i + 1] == '*') {
			const k = src.indexOf('*/', i + 2);
			const j = k < 0 ? n : k + 2;
			wipe(i, j); i = j; continue;
		}

		if (c == '"' || c == "'" || c == '`') {
			let j = i + 1;

			while (j < n) {
				if (src[j] == '\\') { j += 2; continue; }
				if (src[j] == c) { j++; break; }
				if (src[j] == '\n' && c != '`') break;   /* unterminated: stop at the line */
				j++;
			}

			wipe(i, j); i = j; prev = 'x'; continue;
		}

		if (c == '/' && opensRegex(prev)) {
			let j = i + 1, inClass = false;

			while (j < n) {
				const d = src[j];

				if (d == '\\') { j += 2; continue; }
				if (d == '[') inClass = true;
				else if (d == ']') inClass = false;
				else if (d == '/' && !inClass) { j++; break; }
				else if (d == '\n') break;
				j++;
			}

			wipe(i, j); i = j; prev = 'x'; continue;
		}

		if (!/\s/.test(c)) prev = c;
		i++;
	}

	return out.join('');
}

/* ---- 1. the real exported object, evaluated the way LuCI would ---- */

const src = fs.readFileSync(FORMAT, 'utf8').replace(/^\s*'require [^']*';\s*$/gm, '');

const baseclass = { extend: (o) => o };
const _ = (s) => s;
const E = () => ({});
const ui = {};
const L = {};

if (!String.prototype.format)
	String.prototype.format = function () { return String(this); };

const fmt = new Function('baseclass', '_', 'E', 'ui', 'L', src)(baseclass, _, E, ui, L);

const methods = Object.keys(fmt).filter((k) => typeof fmt[k] == 'function');

/* ANY read of `this`, not just `this.x`: euiccSlot and esimProfileList both
   park it in `var self = this` first and would otherwise pass as standalone.
   Codex found that; it was a real hole in the first version of this file. */
const needsReceiver = new Set(methods.filter((k) => /\bthis\b/.test(lex(fmt[k].toString()))));

/* ---- 2. every detached reference across the shipped JS ---- */

const lineOf = (text, idx) => text.slice(0, idx).split('\n').length;

/* One file's worth of detached references. Returns [{line, name, why}].
   Split out so --self-test can drive it with synthetic sources: the forms
   this claims to catch are asserted, not asserted-in-a-comment. */
function scan(raw) {
	const out = [];
	const text = lex(raw);
	let m, refs = 0;

	const flag = (idx, name, why) => {
		if (needsReceiver.has(name))
			out.push({ line: lineOf(text, idx), name, why });
	};

	/* (a) property reference. `\s*` spans newlines, so a call split across
	       lines is still a call. The next non-space character decides, and it
	       is a CHARACTER, not a parse: `(` is a call; `?` covers both `?.()`
	       and a ternary TEST (`fmt.x ? a : b` only asks whether it exists);
	       `.` covers .bind()/.call()/.apply() and also lets a harmless
	       property read like `.name` through. Each is deliberately generous:
	       none of them stores the bare function, which is the mistake here. */
	let re = /\bfmt\.([A-Za-z_]\w*)\s*(\S?)/g;

	while ((m = re.exec(text)) !== null) {
		if (m[2] == '(' || m[2] == '?' || m[2] == '.')
			continue;

		refs++;
		flag(m.index, m[1], `aliased bare -- fix: fmt.${m[1]}.bind(fmt)`);
	}

	/* (b) destructured out of fmt: every name in the pattern loses `this`. */
	re = /\{([^}]*)\}\s*=\s*fmt\b/g;

	while ((m = re.exec(text)) !== null)
		for (const part of m[1].split(',')) {
			const name = part.split(':')[0].trim();

			if (!name)
				continue;

			refs++;
			flag(m.index, name, `destructured out of fmt -- call it as fmt.${name}()`);
		}

	/* (c) computed access with a literal key, not followed by a call. The key
	       is a string, so lex() has already blanked it -- which is the point:
	       `fmt['euiccSlot']` written INSIDE a string is blanked whole and never
	       matches, while the real one leaves `fmt[` spaces `]` behind. The name
	       is then read back out of the raw source at those same offsets. */
	re = /\bfmt\[(\s+)\]\s*(\S?)/g;

	while ((m = re.exec(text)) !== null) {
		if (m[2] == '(' || m[2] == '?' || m[2] == '.')
			continue;

		const at = m.index + 'fmt['.length;
		const key = raw.slice(at, at + m[1].length).match(/^\s*['"]([A-Za-z_]\w*)['"]\s*$/);

		if (!key)
			continue;

		refs++;
		flag(m.index, key[1], `taken by computed key -- call it as fmt.${key[1]}()`);
	}

	return { out, refs };
}

/* ---- 2b. self-test: prove the scan catches what this file claims ---- */

if (process.argv.includes('--self-test')) {
	/* `euiccSlot` and `fmtSim` need a receiver, `fmtBytes` does not.
	   [ how many findings, which name, what it is, the source ] */
	const CASES = [
		[ 1, 'euiccSlot',       'bare alias',            'var a = fmt.euiccSlot;' ],
		[ 1, 'fmtRegistration', 'destructured',          'const { fmtRegistration } = fmt;' ],
		[ 1, 'euiccSlot',       'computed key',          "var a = fmt['euiccSlot'];" ],
		[ 1, 'fmtSim',          'inside an array',       'var t = [ fmt.fmtSim, 1 ];' ],
		[ 1, 'fmtSim',          'ternary branch',        'var t = x ? fmt.fmtSim : null;' ],
		[ 1, 'fmtRegistration', 'passed as a callback',  'list.map(fmt.fmtRegistration);' ],
		[ 0, null,              'plain call',            'fmt.euiccSlot(s);' ],
		[ 0, null,              'call split over lines', 'fmt.fmtRegistration(\n\tmi);' ],
		[ 0, null,              'optional call',         'fmt.fmtSim?.(a, b);' ],
		[ 0, null,              'bound',                 'var a = fmt.euiccSlot.bind(fmt);' ],
		[ 0, null,              'call/apply',            'fmt.euiccSlot.call(fmt, s);' ],
		[ 0, null,              'computed call',         "fmt['euiccSlot'](s);" ],
		[ 0, null,              'in a comment',          '/* var a = fmt.euiccSlot; */' ],
		[ 0, null,              'in a string',           "var s = 'fmt.euiccSlot';" ],
		[ 0, null,              'standalone helper',     'var a = fmt.fmtBytes;' ],

		/* the four the regex chain this replaced got WRONG. Each is a real
		   shape: graph.js:177 holds an http:// inside a string, and any of
		   these could blank a live reference or invent a dead one. */
		[ 0, null,              'computed key in a string',
			'var s = "fmt[\'euiccSlot\']";' ],
		[ 1, 'euiccSlot',       '// inside a string does not eat the line',
			'var s = "http://example"; var a = fmt.euiccSlot;' ],
		[ 1, 'euiccSlot',       '/* inside a string opens no comment',
			'var s = "/*"; var a = fmt.euiccSlot;' ],
		[ 1, 'euiccSlot',       'a quote inside a regex literal',
			"var r = /'/; var a = fmt.euiccSlot; var s = 'x';" ],
	];

	let bad = 0;

	for (const [ want, name, what, code ] of CASES) {
		const got = scan(code).out;

		if (got.length != want || (name && got[0] && got[0].name != name)) {
			console.error(`  self-test FAILED: ${what} -> ${got.length} finding(s)` +
				`${got[0] ? ' for ' + got[0].name : ''}, wanted ${want}${name ? ' for ' + name : ''}`);
			bad++;
		}
	}

	/* and the reported line survives a multi-line block comment */
	const after = scan('/* one\n   two\n   three\n   four */\nvar x = 1;\nvar a = fmt.euiccSlot;\n');

	if (after.out.length != 1 || after.out[0].line != 6) {
		console.error(`  self-test FAILED: line after a block comment -> ${after.out[0] && after.out[0].line}, wanted 6`);
		bad++;
	}

	if (bad) {
		console.error(`check-detached-methods --self-test: ${bad} failure(s)`);
		process.exit(1);
	}

	console.log(`check-detached-methods --self-test: ${CASES.length + 1} cases, all correct`);
	process.exit(0);
}

/* ---- 2c. the shipped tree ---- */

function walk(dir) {
	return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
		const p = path.join(dir, e.name);
		return e.isDirectory() ? walk(p) : (e.name.endsWith('.js') ? [ p ] : []);
	});
}

const problems = [];
let refs = 0;

for (const file of walk(RES)) {
	if (path.resolve(file) == path.resolve(FORMAT))
		continue;

	const r = scan(fs.readFileSync(file, 'utf8'));

	refs += r.refs;

	for (const p of r.out)
		problems.push({ file: rel(file), ...p });
}

/* ---- 3. verdict ---- */

if (problems.length) {
	console.error('detached method that needs its receiver:\n');

	for (const p of problems)
		console.error(`  ${p.file}:${p.line}: ${p.name}() reads \`this\`, ${p.why}`);

	console.error('');
	process.exit(1);
}

console.log(`check-detached-methods: ${needsReceiver.size} receiver-dependent of ` +
	`${methods.length} methods, ${refs} detached references, all safe`);
