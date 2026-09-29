/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Load a LuCI frontend module outside LuCI.
 *
 * `'require x as y';` is LuCI's own directive, not JavaScript, so it is
 * rewritten into a dependency lookup before the file is evaluated.  The
 * snapshot renderer and the frontend invariant tests all need this, and there
 * is no reason for them to each carry their own copy - the snapshot script had
 * one, and the first invariant test copy-pasted it.
 *
 * `runtime` supplies the `_` / `E` / `L` globals the module expects; the
 * defaults are inert, which is enough for the tests that only read the
 * module's data (a table, a validator) rather than render it.
 */

'use strict';

const fs = require('fs');

function loadLuciModule(file, deps, runtime) {
	let src = fs.readFileSync(file, 'utf8');
	src = src.replace(/^'require ([^']+) as (\w+)';$/gm,
		(_m, mod, alias) => `const ${alias} = __deps[${JSON.stringify(mod)}];`);
	src = src.replace(/^'require ([^']+)';$/gm,
		(_m, mod) => `const ${mod.split('.').pop().replace(/[^\w]/g, '_')} = __deps[${JSON.stringify(mod)}];`);

	runtime = runtime || {};
	const E = runtime.E || (() => null);
	const L = runtime.L || {};

	/* LuCI's `_()` returns a String object carrying a `format()` method, and
	 * the form code uses both halves (`_('Expecting: %s').format(x)`).  A
	 * plain-string stand-in throws on the second half, so the default has to
	 * be a String object too. */
	const _ = runtime._ || ((s) => {
		const out = new String(s);
		out.format = function(...args) {
			let i = 0;
			return String(this).replace(/%[sdj%]/g, (m) =>
				m === '%%' ? '%' : (i < args.length ? String(args[i++]) : m));
		};
		return out;
	});

	/* eslint-disable-next-line no-new-func */
	const factory = new Function('__deps', '_', 'E', 'L', src);
	return factory(deps, _, E, L);
}

module.exports = { loadLuciModule };
