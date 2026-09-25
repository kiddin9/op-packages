'use strict';
'require baseclass';
'require view.footstrap-files.grammars as grammars';

/* The editor, assembled by hand out of prism-code-editor rather than taken from its `setups`.
 *
 * WHY NOT `setups/index.js`. It is one import and it costs the whole library: measured on the stand
 * with the search widget and the history exercised, the ready-made setup fetched 263 FILES —
 * `languages/index.js` is a barrel that imports every grammar the project ships, zig and xojo
 * included. The pieces below are the same editor with the grammars this router needs, and nothing
 * is loaded until the reader opens a file.
 *
 * WHAT THE PACKAGE VENDORS, and why each file is there:
 *   index.js + core-*.js        the editor itself
 *   prism/index.js + core-*.js  the tokenizer
 *   (no grammars at all)        uci, shell and json are ours, in grammars.js: the library's bash
 *                               was 5,672 bytes of a language nobody writes in /etc/config, and its
 *                               json dragged a shared patterns module behind it for two regexes
 *   extensions/search           find and replace, which a config file needs and a textarea has not
 *   extensions/matchBrackets    the one thing that makes a nested config readable
 *   layout.css, search.css        the library's own layout and widget styling — the COLOURS are
 *                               ours, in editor.css, off the theme's export tier
 *
 * WHAT IS DELIBERATELY NOT HERE: `languages/<lang>.js`, the library's indent and comment rules.
 * They write into `languageMap`, and in this build NOBODY READS IT — the reader is
 * `extensions/commands`, which we do not load. Measured on the stand before removing them: Enter
 * inside a `{` produced a bare newline and Ctrl+/ did nothing, exactly as it does now. Four files
 * of two lines each pulled 3,970 bytes of shared and jsx-shared machinery behind them.
 *
 * Its stylesheets go into the editor's own SHADOW ROOT, so `<head>` is untouched and the theme's
 * cascade layer order cannot be inverted from here (footstrap docs/css.md). That is the property
 * that ruled out Ace, whose sheets land first in <head> unless `useStrictCSP` is set. */

/* E() WITH THE MARKUP SINK CLOSED: a primitive last argument becomes a text node, never
 * innerHTML. The reasoning, and the stand proof, are on the same shim in browser.js. */
function E() {
	const args = Array.prototype.slice.call(arguments);
	const last = args.length - 1;
	if (last >= 1 && args[last] != null && typeof args[last] !== 'object' && typeof args[last] !== 'function')
		args[last] = [ args[last] ];
	return window.E.apply(null, args);
}

/* Under `resources/view/<app>/`, which is where a LuCI app keeps what belongs to one view — the
 * shape stock luci-app-filemanager uses for its own HexEditor, and what the theme's app guide asks
 * for. A library in a SHARED path (`/luci-static/resources/codemirror/`, as AdGuardHome ships it) is
 * overwritten by the next app that vendors a different version of the same thing. */
const V = L.resource('view/footstrap-files/vendor/pce');

/* UCI HAS ITS OWN GRAMMAR NOW. It used to be highlighted as shell, which was the closest thing the
 * library shipped and still wrong: `config interface 'lan'` has no keywords in bash, so a config
 * file came out as bare words with quoted strings. Prism's `ini` was worse — measured on
 * /etc/config/network, 9 tokens in 120 lines, because INI wants `key=value` and `[section]`.
 *
 * `ini` and `nginx` had grammars of their own and no longer do: a router that has nginx at all is
 * rare, `.ini` rarer still, and both are closer to shell than either was to uci.
 *
 * EVERY LANGUAGE HERE IS ONE grammars.js REGISTERS, so nothing is fetched and nothing can 404:
 * anything that is not uci or json is edited as shell. */

function languageFor(path) {
	if ((/^\/etc\/config\//).test(path)) return 'uci';
	return (/\.json$/i).test(path) ? 'json' : 'shell';
}

let _loaded = null;

/* One load for the life of the page, whatever is opened afterwards. The modules are ES modules with
 * RELATIVE imports, so the browser resolves them straight from the router — no bundler runs in this
 * package's build, and none is needed. */
function loadEditor() {
	if (_loaded) return _loaded;
	_loaded = Promise.all([
		import(`${V}/index.js`),
		import(`${V}/prism/index.js`),
		import(`${V}/extensions/search/index.js`),
		import(`${V}/extensions/matchBrackets/index.js`),
	]).then(([ core, prism, search, brackets ]) => {
		/* ours, registered against the tokenizer the library just brought in */
		grammars.register(prism.languages);
		return { core, prism, search, brackets };
	});
	return _loaded;
}

return baseclass.extend({
	/* Everything the caller needs: give it a container and a file, get an editor back. The container
	 * keeps its own stylesheets, so nothing this returns leaks into the document. */
	open(container, path, text) {
		const lang = languageFor(path);
		return loadEditor().then((mods) => {
			const editor = mods.core.createEditor(container, {
				language: lang,
				value: text,
				lineNumbers: true,
				tabSize: 4,
				insertSpaces: false,		/* uci and shell are tab-indented on this platform */
			});
			editor.addExtensions(mods.search.searchWidget(), mods.brackets.matchBrackets());
			return editor;
		});
	},

	/* The sheets the editor needs, as <link>s the CALLER owns: appended inside the view's tree, they
	 * die with `#view` on the next navigation. */
	styles() {
		return [
			E('link', { rel: 'stylesheet', href: `${V}/layout.css` }),
			E('link', { rel: 'stylesheet', href: `${V}/search.css` }),
			/* OURS, not the library's: one sheet for both modes, on the export tier */
			E('link', { rel: 'stylesheet', href: L.resource('view/footstrap-files/editor.css') }),
		];
	},
});
