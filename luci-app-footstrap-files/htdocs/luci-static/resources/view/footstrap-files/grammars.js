/* The two grammars this router actually needs, written here rather than vendored.
 *
 * WHAT THIS REPLACES: `prism/languages/bash.js`, 5,672 bytes of minified Prism grammar covering
 * process substitution, here-documents, arithmetic expansion and the rest of a language nobody
 * writes in /etc/config. It was also the WRONG grammar: uci is not shell, and the page has carried
 * a note saying so since the first commit — `config interface 'lan'` has no keywords in bash, so
 * the whole file came out as bare words with quoted strings, which is what the screenshots showed.
 *
 * A Prism grammar is an ordered object of regexes, and `languages.<name>` is where the tokenizer
 * looks — the same shape the vendored json grammar uses, and the reason this file needs nothing
 * from the library but that one export.
 *
 * ORDER IS THE GRAMMAR. Prism tries each pattern in turn over what is left, so `comment` before
 * `string` (a `#` inside quotes must not open one — hence `string` first for shell, where `$'…'`
 * and `"…#…"` are ordinary) and `keyword` before the bare-word fallbacks.
 *
 * NO LOOKBEHIND, anywhere. Safari only learned it in 16.4 and this package's floor is 15.4, so a
 * name that follows a keyword is matched as one token with an `inside`, not with `(?<=…)`. */
'use strict';
'require baseclass';

/* ---- uci -----------------------------------------------------------------------------------
 *
 * Three keywords, and everything else is a name or a value:
 *
 *   config interface 'lan'      section: keyword + type, then an optional name
 *   option proto 'static'       entry:   keyword + option name, then the value
 *   list ports 'eth0'
 *
 * The type after `config` is the SUBJECT of the block — what is being configured — so it takes
 * `class-name`, which editor.css paints at the strongest text level rather than as syntax. */
const UCI = {
	comment: { pattern: /#.*/g, greedy: true },
	/* keyword + the word after it, in one match, so the second word can be typed by position
	 * without a lookbehind */
	section: {
		pattern: /^[ \t]*config[ \t]+[\w.-]+/gm,
		inside: {
			keyword: /config/,
			'class-name': /[\w.-]+$/,
		},
	},
	entry: {
		pattern: /^[ \t]*(?:option|list)[ \t]+[\w.-]+/gm,
		inside: {
			keyword: /option|list/,
			property: /[\w.-]+$/,
		},
	},
	string: { pattern: /'[^'\n]*'|"(?:\\.|[^"\\\n])*"/g, greedy: true },
	number: /\b\d+(?:\.\d+)*\b/g,
	/* an unquoted value — uci writes plenty of them */
	variable: /\S+/g,
};

/* ---- json ----------------------------------------------------------------------------------
 *
 * The vendored one was eight regexes and pulled `patterns-DSInPV_c.js` behind it for two of them —
 * 1,070 bytes for a format whose whole grammar fits here. `property` before `string` because a key
 * is a string too, and the lookahead is what tells them apart.
 *
 * `webmanifest` is not aliased and `//` comments are not matched: JSON has no comments, and a file
 * on this router that uses them is JSON5, which is not what the tokenizer was asked for. */
const JSON_ = {
	property: { pattern: /"(?:\\.|[^\\\n"])*"(?=\s*:)/g, greedy: true },
	string: { pattern: /"(?:\\.|[^\\\n"])*"/g, greedy: true },
	number: /-?\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/gi,
	boolean: /\b(?:false|true)\b/g,
	null: { pattern: /\bnull\b/g, alias: 'keyword' },
	operator: /:/g,
	punctuation: /[[\]{},]/g,
};

/* ---- shell ---------------------------------------------------------------------------------
 *
 * Enough for an init script, a hotplug hook and the `.conf` files that are really shell: the
 * shebang, comments, both quotings, expansions, the control words and the builtins a router's
 * scripts are made of. What is deliberately absent is everything Prism's bash grammar carries for
 * an interactive shell — here-docs, process substitution, arithmetic — which no file under /etc on
 * this box uses and which cost 5 KB to describe. */
const VAR = /\$(?:\{[^}\n]*\}|[\w@#?*!$-]+)/g;

const SHELL = {
	shebang: { pattern: /^#!.*/, alias: 'comment' },
	comment: { pattern: /(?:^|[ \t])#.*/g, greedy: true },
	/* SINGLE AND DOUBLE QUOTES ARE DIFFERENT LANGUAGES. `'$HOME'` is four characters; `"$HOME"` is
	 * an expansion, and a shell script on a router is mostly the second kind — so the double-quoted
	 * form carries an `inside` that keeps painting variables, while the single-quoted one is one
	 * flat string. Without this every `"$X"` came out as a plain string and the reader lost the one
	 * thing worth seeing in `[ "$X" = 1 ]`. */
	string: { pattern: /'[^']*'/g, greedy: true },
	dquote: {
		pattern: /"(?:\\.|[^"\\])*"/g,
		greedy: true,
		alias: 'string',
		inside: { variable: VAR },
	},
	variable: VAR,
	keyword: /\b(?:if|then|elif|else|fi|for|while|until|do|done|case|esac|in|function|return|local|export|readonly|break|continue|exit|trap)\b/g,
	builtin: /\b(?:echo|printf|test|cd|read|set|unset|eval|exec|shift|source|sleep|kill|logger|uci|ubus|opkg|apk|service|reload_config)\b/g,
	number: /\b\d+\b/g,
	operator: /(?:&&|\|\||[|&;]|[!=<>]=?|=)/g,
	punctuation: /[{}[\]()]/g,
};

return baseclass.extend({
	/* Registered against the tokenizer the editor already loaded, so this adds a module and no
	 * dependency: `languages` is the one thing the vendored prism entry point exports that anyone
	 * outside it needs. */
	register(languages) {
		languages.uci = UCI;
		languages.shell = SHELL;
		languages.json = JSON_;
	},
});
