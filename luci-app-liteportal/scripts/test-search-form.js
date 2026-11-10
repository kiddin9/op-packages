#!/usr/bin/env node
/*
 * Regression test for the search settings of the LuCI General form.
 *
 * Bug it guards against (reported by the user 2026-10-16, fixed in 3.0.1-r4):
 * the "Custom search URL" option declared its two conditions as two separate
 * depends() calls. LuCI treats multiple depends() calls as ALTERNATIVES (a
 * logical or) - only the object form `depends({ a: '1', b: '2' })` is an "and"
 * (form.js, "Add a dependency constraint to the option": "Multiple constraints
 * (that is, multiple calls to depends()) are treated as alternatives, forming
 * a logical 'or' expression"). With the search box switched on, the option
 * therefore stayed active for EVERY engine, its validator ran on the empty
 * value, and the save was rejected with
 *     Option "自定义搜索 URL" contains an invalid input value. ...
 * Every save failed, so the engine pick never reached uci and the portal kept
 * using Google no matter which engine was selected - two symptoms, one root
 * cause.
 *
 * What is checked here:
 *   1. search_url has exactly ONE depends() call, in object form, requiring
 *      both search_engine == 'custom' and search_enabled == '1'.
 *   2. Under LuCI's documented dependency semantics the option is inactive
 *      while any preset engine is picked (the exact state that used to fail
 *      the save) and active only for 'custom' with the box on. The simulator
 *      below is fed the dependency calls extracted from the real source, so
 *      re-splitting them into two calls fails the test.
 *   3. The validator matrix: empty/absent -> required error, non-http or a
 *      template without %s -> format error, valid http(s) template -> true.
 *   4. The two-gate invariant: the regular expression in the form is
 *      character-for-character the one liteportal.uc uses.
 *
 * Run: node scripts/test-search-form.js  (wired into scripts/check.sh)
 */

'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const VIEW = path.join(ROOT, 'htdocs/luci-static/resources/view/liteportal/general.js');
const PLUGIN = path.join(ROOT, 'root/usr/share/rpcd/ucode/liteportal.uc');

let fail = 0;
function check(label, cond, extra) {
	if (cond) {
		console.log('  ok  ' + label);
	}
	else {
		fail++;
		console.log('FAIL  ' + label + (extra ? '  [' + extra + ']' : ''));
	}
}

/* Brace-matched slice, so it works on the repo source and on a minified build
 * alike (no reliance on newlines). */
function braceMatch(text, from) {
	let depth = 0, started = false;
	for (let k = from; k < text.length; k++) {
		const c = text[k];
		if (c === '{') { depth++; started = true; }
		else if (c === '}') {
			depth--;
			if (started && depth === 0)
				return text.slice(from, k + 1);
		}
	}
	throw new Error('unbalanced braces');
}

/* Everything of one option: from its s.option() declaration up to the next
 * option's declaration, or to the end of its validate assignment when it has
 * one and no further option follows. */
function optionBlock(src, marker) {
	const start = src.indexOf(marker);
	if (start < 0)
		throw new Error('option not found: ' + marker);

	let end = src.length;

	const next = src.indexOf('s.option(', start + marker.length);
	if (next >= 0)
		end = next;

	const validate = src.indexOf('o.validate =', start);
	if (validate >= 0 && validate < end) {
		const open = src.indexOf('{', validate);
		end = open + braceMatch(src, open).length;
	}

	return src.slice(start, end);
}

/* Every depends() call in a block, as raw argument text. */
function dependsCalls(block) {
	const calls = [];
	let idx = 0;
	while ((idx = block.indexOf('o.depends(', idx)) >= 0) {
		const open = block.indexOf('(', idx);
		let depth = 0, end = -1;
		for (let k = open; k < block.length; k++) {
			if (block[k] === '(') depth++;
			else if (block[k] === ')') {
				depth--;
				if (depth === 0) { end = k; break; }
			}
		}
		if (end < 0)
			throw new Error('unbalanced depends() call');
		calls.push(block.slice(open + 1, end).trim());
		idx = end;
	}
	return calls;
}

/* One depends() argument -> { form, entry }, where entry is the name=>value
 * map LuCI evaluates. */
function parseDepends(arg) {
	if (arg.startsWith('{')) {
		const entry = {};
		const re = /([A-Za-z_][A-Za-z0-9_]*)\s*:\s*'([^']*)'/g;
		let m;
		while ((m = re.exec(arg)))
			entry[m[1]] = m[2];
		if (!Object.keys(entry).length)
			throw new Error('no key: value pairs in object depends: ' + arg);
		return { form: 'object', entry: entry };
	}

	const m = arg.match(/^'([^']+)'\s*,\s*'([^']*)'$/);
	if (m)
		return { form: 'pair', entry: { [m[1]]: m[2] } };

	throw new Error('unparsed depends() argument: ' + arg);
}

/* --------------------------------------------------------------- the test -- */

const view = fs.readFileSync(VIEW, 'utf8');
const plugin = fs.readFileSync(PLUGIN, 'utf8');

const urlBlock = optionBlock(view, "s.option(form.Value, 'search_url'");
const engineBlock = optionBlock(view, "s.option(form.ListValue, 'search_engine'");

console.log('search form: dependency and validator\n');

/* 1. the shape of the dependency declaration -------------------------------- */

const calls = dependsCalls(urlBlock);

check('search_url declares exactly one depends()', calls.length === 1,
	'found ' + calls.length + ': ' + JSON.stringify(calls));

let urlDeps = [];
if (calls.length === 1) {
	const parsed = parseDepends(calls[0]);
	urlDeps = [parsed];

	check('the single depends() uses the object (AND) form', parsed.form === 'object',
		'form is ' + parsed.form);
	check('it requires search_engine == custom',
		parsed.entry.search_engine === 'custom', JSON.stringify(parsed.entry));
	check('it requires search_enabled == 1',
		parsed.entry.search_enabled === '1', JSON.stringify(parsed.entry));
	check('it requires nothing else',
		Object.keys(parsed.entry).length === 2, JSON.stringify(parsed.entry));
}

/* 2. the effect, under LuCI's documented semantics --------------------------- *
 * Entries from separate depends() calls are OR'ed; keys inside one call are
 * AND'ed; a dependency on an option that is itself hidden reads as null. That
 * last rule is what chains search_engine behind search_enabled. */
function evalEntry(entry, state) {
	for (const name in entry) {
		const source = state[name];
		const value = (source && source.active) ? source.value : null;
		if (value !== entry[name])
			return false;
	}
	return true;
}

function isActive(deps, state) {
	if (!deps.length)
		return true;
	for (const d of deps)
		if (evalEntry(d.entry, state))
			return true;
	return false;
}

const engineDeps = dependsCalls(engineBlock).map(parseDepends);

function searchUrlActive(enabled, engine) {
	const state = {
		search_enabled: { active: true, value: enabled }
	};

	/* search_engine is itself behind search_enabled - a dependency on a
	 * hidden option reads as null, which is what chains the two. */
	state.search_engine = { active: isActive(engineDeps, state), value: engine };

	return isActive(urlDeps, state);
}

const GOOGLE = 'https://www.google.com/search?q=%s';
const BING = 'https://www.bing.com/search?q=%s';

check('inactive while Bing is picked and the box is on (the failed save)',
	searchUrlActive('1', BING) === false);
check('inactive while the default Google template is in place',
	searchUrlActive('1', GOOGLE) === false);
check('active for the custom engine with the box on',
	searchUrlActive('1', 'custom') === true);
check('inactive for custom when the box is off',
	searchUrlActive('0', 'custom') === false);
check('inactive when the box is off and a preset is picked',
	searchUrlActive('0', GOOGLE) === false);

/* The simulator must reproduce the reported bug on the old declaration,
 * otherwise the assertions above prove nothing. */
const oldDeps = [
	parseDepends("'search_engine', 'custom'"),
	parseDepends("'search_enabled', '1'")
];
check('the simulator reproduces the bug on two separate depends() calls',
	isActive(oldDeps, {
		search_enabled: { active: true, value: '1' },
		search_engine: { active: true, value: BING }
	}) === true);

/* 3. the validator matrix ---------------------------------------------------- */

const validateSrc = urlBlock.slice(urlBlock.indexOf('o.validate ='));
const validate = new Function('_',
	validateSrc.replace('o.validate =', 'return'))(s => s);

const REQUIRED = 'A custom search URL is required';

const emptyResult = validate('cfg1', '');
check('empty value is refused with the required message',
	typeof emptyResult === 'string' && emptyResult.indexOf(REQUIRED) >= 0,
	'returned: ' + JSON.stringify(emptyResult));
check('whitespace-only value is refused',
	validate('cfg1', '   ') !== true);
check('absent value is refused',
	validate('cfg1', null) !== true);
check('non-http scheme is refused',
	validate('cfg1', 'ftp://example.com/s?q=%s') !== true);
check('template without %s is refused',
	validate('cfg1', 'https://example.com/s?q=') !== true);
check('template without a scheme is refused',
	validate('cfg1', 'example.com/s?q=%s') !== true);
check('https template with %s is accepted',
	validate('cfg1', 'https://example.com/s?q=%s') === true);
check('http template with %s and a fixed suffix is accepted',
	validate('cfg1', 'http://example.com/s?q=%s&lang=zh') === true);
check('surrounding whitespace is trimmed before acceptance',
	validate('cfg1', '  https://example.com/s?q=%s  ') === true);

/* 4. the two gates share one expression -------------------------------------- */

function regexLiteral(text) {
	const i = text.indexOf('/^https?:');
	if (i < 0)
		return null;
	const j = text.indexOf('%s/', i);
	return (j < 0) ? null : text.slice(i, j + 3);
}

const formRe = regexLiteral(view);
const backendRe = regexLiteral(plugin);

check('the form gate regex is present', formRe != null);
check('the backend gate regex is present', backendRe != null);
check('form and backend use the same regex, character for character',
	formRe != null && formRe === backendRe,
	'form=' + formRe + ' backend=' + backendRe);

console.log(fail ? '\n' + fail + ' FAILED' : '\nALL PASS');
process.exit(fail ? 1 : 0);
