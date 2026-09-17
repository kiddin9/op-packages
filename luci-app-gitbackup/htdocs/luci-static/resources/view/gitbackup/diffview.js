'use strict';

// gitbackup -- shared diff viewer (ticket 23, spec "Не пиши второй
// просмотрщик diff"). Before this file existed, history.js was the only
// place in the project that rendered a diff into a colored <pre>; ticket 23
// adds a second place that needs one (Overview's "Configuration" card, R124/
// R125's own config_diff indicator, which used to show only the bare
// differs/does-not-differ flag and threw the actual text away). A second,
// separately-typed copy of history.js's own gbDiffLineClass/gbBuildDiffPre
// would be exactly the "третья реализация" ticket 23 explicitly forbids, so
// both call sites use this file instead.
//
// This is deliberately TWO renderers, not one that auto-detects its input,
// because the two rpcd methods that feed them answer genuinely different
// questions in genuinely different formats -- collapsing them into one
// "smart" parser would have to guess which format it was looking at from
// the text alone, and a manifest line that happened to start with "+" or
// "-" (this format's own add/remove marker) would be indistinguishable from
// a coincidence:
//
//   unified(text)  -- for `diff` (gbrpc_diff, two already-committed shas,
//   History's per-commit view): plain `git diff --end-of-options <a> <b>`
//   output (usr/sbin/gitbackup's cmd_diff, its two-argument form) -- real
//   unified-diff syntax, "diff --git a/X b/X" headers, "@@ ... @@" hunks,
//   body lines prefixed ' '/'+'/'-'.
//
//   manifest(text) -- for `config_diff` (gbrpc_config_diff, no params,
//   Overview's live-drift check): cmd_diff's OTHER, zero-argument form,
//   which never calls `git diff` at all -- it walks both manifests'
//   entries field by field (_gb_diff_compare/_gb_diff_describe_change,
//   usr/sbin/gitbackup) and prints one line per changed path: "+ path
//   (type)" (added), "- path (type)" (removed), or "~ path: field
//   a->b; ..." (changed) -- the only way this project can show a chmod/
//   chown a real `git diff` never sees at all (same blob, same tree entry
//   mode class either way; interfaces.md, ticket 17/D03).
//
// No content goes through innerHTML anywhere below -- every line is its own
// text node built through E(), the same "чужие данные никогда не
// становятся разметкой" rule history.js's own diff viewer already followed
// (that file's own header comment, out of this ticket's zone, read before
// writing this).
//
// That holds only because every child below is handed to E() INSIDE AN
// ARRAY, and this file originally got that wrong. LuCI's dom.append()
// branches on the shape of its `children` argument: the Array branch is the
// one that runs each string through document.createTextNode(), while a bare
// string falls all the way through to `node.innerHTML = '' + children` and
// is parsed as markup. `E('span', attrs, line)` therefore rendered a diff
// line AS HTML -- and the text here is `git diff` output, i.e. the contents
// of files fetched from the backup remote, which anyone with push access to
// that repository controls byte for byte. `E('span', attrs, [ line ])` is
// the fix, and the bracket is load-bearing, not punctuation: nothing else
// escapes on the way here (gb_json_esc escapes only what JSON needs, LuCI's
// String.format('%s') does not escape at all, and a LuCI page carries no
// CSP). tests/dom_text_children.test.mjs holds the whole view directory to
// this, so a future call site cannot quietly drop the brackets again.

// css -- the class names both renderers below emit, meant to be spliced
// into each CALLING view's own <style> block (rule 1 of the style guide:
// every view returns its styles inside its own tree, never through
// document.head.appendChild -- a shared module has no tree of its own to
// return one in). A plain exported array of rule strings, not a <style>
// this file injects itself, keeps that rule intact while still giving both
// call sites the exact same rules instead of two hand-copied approximations
// of them.
var GB_DIFFVIEW_CSS = [
	'.gitbackup-diff { max-height: 420px; overflow: auto; background: var(--background-color-low, #f5f5f5); border: 1px solid var(--background-color-medium, #ddd); border-radius: 4px; padding: .6em .8em; font-family: monospace; font-size: .85em; white-space: pre-wrap; }',
	'.gitbackup-diffline-add { display: block; color: var(--success-color-high, #2e7d32); }',
	'.gitbackup-diffline-del { display: block; color: var(--error-color-high, #c62828); }',
	'.gitbackup-diffline-change { display: block; color: var(--warn-color-high, #b45f06); }',
	'.gitbackup-diffline-hunk { display: block; color: var(--text-color-medium, #666); }',
	'.gitbackup-diffline-meta { display: block; font-weight: bold; color: var(--text-color-medium, #666); }',
	'.gitbackup-diffline-ctx { display: block; color: var(--text-color-high, #333); }'
];

// gbUnifiedLineClass <line> -- one prefixed class per line of a real `git
// diff` (spec: "Diff-viewer -- свой <pre> с префиксованными классами и
// токенами --success-*/--error-*. Никаких внешних библиотек подсветки").
// Moved here byte-for-byte from history.js's own gbDiffLineClass.
function gbUnifiedLineClass(line) {
	if (line.indexOf('+++') === 0 || line.indexOf('---') === 0)
		return 'gitbackup-diffline-meta';
	if (line.charAt(0) === '+')
		return 'gitbackup-diffline-add';
	if (line.charAt(0) === '-')
		return 'gitbackup-diffline-del';
	if (line.indexOf('@@') === 0)
		return 'gitbackup-diffline-hunk';
	if (line.indexOf('diff --git') === 0 || line.indexOf('index ') === 0)
		return 'gitbackup-diffline-meta';
	return 'gitbackup-diffline-ctx';
}

// gbManifestLineClass <line> -- one prefixed class per line of cmd_diff's
// zero-argument, manifest-field form: "+ "/"- " mark a whole path added or
// removed (green/red, same coloring a real diff's own +/- lines get),
// "~ " marks a path whose fields changed in place (warn, since it is
// neither a pure addition nor a pure removal -- e.g. a chmod), anything
// else (there should be nothing else) falls back to plain context styling.
function gbManifestLineClass(line) {
	if (line.indexOf('+ ') === 0)
		return 'gitbackup-diffline-add';
	if (line.indexOf('- ') === 0)
		return 'gitbackup-diffline-del';
	if (line.indexOf('~ ') === 0)
		return 'gitbackup-diffline-change';
	return 'gitbackup-diffline-ctx';
}

// gbBuildPre <text> <classify> <emptyText> -- shared DOM builder: an empty
// or blank <text> renders <emptyText> as a plain hint paragraph (spec: "diff
// на неизменившейся системе печатает пустой результат" -- both cmd_diff
// shapes agree on this), anything else becomes one <span> text node per
// line inside a scrollable <pre class="gitbackup-diff">, classified by
// <classify>.
function gbBuildPre(text, classify, emptyText) {
	var lines = (text || '').split('\n');

	if (!lines.length || (lines.length === 1 && !lines[0]))
		return E('p', { 'class': 'gitbackup-card-hint' }, [ emptyText ]);

	return E('pre', { 'class': 'gitbackup-diff' }, lines.map(function(line) {
		return E('span', { 'class': classify(line) }, [ line + '\n' ]);
	}));
}

return L.Class.extend({
	css: GB_DIFFVIEW_CSS,

	// unified(text) -- History's per-commit diff (two already-committed
	// shas): real `git diff` output.
	unified: function(text) {
		return gbBuildPre(text, gbUnifiedLineClass, _('No differences.'));
	},

	// manifest(text) -- Overview's live-drift diff (config_diff): cmd_diff's
	// own "+ path (type)" / "- path (type)" / "~ path: field a->b; ..."
	// lines.
	manifest: function(text) {
		return gbBuildPre(text, gbManifestLineClass, _('No differences.'));
	}
});
