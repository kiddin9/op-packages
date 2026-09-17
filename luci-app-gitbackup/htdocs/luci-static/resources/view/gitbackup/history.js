'use strict';
'require view';
'require rpc';
'require ui';
'require view.gitbackup.diffview as diffview';
'require view.gitbackup.oplog as oplog';
/* global diffview, oplog */
// See overview.js's own identical comment: the project's eslint config
// (openwrt/luci's own) only knows a fixed list of stock LuCI module names
// as globals, not this app's own diffview.js/oplog.js aliases.

// gitbackup -- History (ticket 14, spec "Решения по реализации -> LuCI ->
// History", "Формат коммита", "Восстановление"). Client-side JS only,
// luci-base only, same jsmin-conservative style (plain ES5, `var`/
// `function`, no let/const/arrow/template literals, every statement
// semicolon-terminated) as overview.js (ticket 11) and paths.js (ticket 13),
// both read before writing this file -- their style/rpcd/poller-cleanup
// patterns are reused here rather than reinvented.
//
// Brief, verbatim: "History -- последние N коммитов своей ветки -- дата из
// subject, SHA, список изменившихся путей. Клик -> diff в ui.showModal.
// Кнопка Restore с двойным подтверждением: первый экран показывает список
// перезаписываемых файлов, второй требует ввести имя устройства; если
// board.json выбранного коммита не совпадает с текущим, на первом же
// экране -- красное предупреждение о том, что имена интерфейсов и wireless
// не подойдут."
//
// ---------------------------------------------------------------------
// rpcd bindings -- copied from root/usr/share/rpcd/acl.d/luci-app-
// gitbackup.json and usr/libexec/rpcd/luci.gitbackup's own gbrpc_*
// handlers (package/gitbackup, out of this ticket's zone). This view adds
// no rpcd method of its own: `status` (device name for the restore
// confirmation gate), `history` (the commit list), `diff` (two already-
// committed shas -- interfaces.md, ticket 13's own "Чем пользоваться":
// "diff -- твоё") and `restore` (write tier) are the whole surface it
// needs.
// ---------------------------------------------------------------------

var callStatus = rpc.declare({
	object: 'luci.gitbackup',
	method: 'status'
});

var callHistory = rpc.declare({
	object: 'luci.gitbackup',
	method: 'history',
	params: [ 'limit' ]
});

var callDiff = rpc.declare({
	object: 'luci.gitbackup',
	method: 'diff',
	params: [ 'from', 'to' ]
});

var callLog = rpc.declare({
	object: 'luci.gitbackup',
	method: 'log',
	params: [ 'lines' ]
});

var callRestore = rpc.declare({
	object: 'luci.gitbackup',
	method: 'restore',
	params: [ 'device', 'commit', 'dry_run', 'force', 'with_packages' ]
});

// "Последние N коммитов" (brief, verbatim) -- one fixed page size, not a
// user-adjustable control: the brief never asks for pagination, and
// `history` already runs a real `git fetch` per call (interfaces.md,
// ticket 11-13: "Долгие вызовы (config_diff, history) не вешаются на
// первичную загрузку страницы"), so a bigger N only means a slower single
// load, not a cheaper one.
var GB_HISTORY_LIMIT = 30;

// ---------------------------------------------------------------------
// Pure helpers -- no DOM access, easy to reason about and to keep in sync
// with the shell side by inspection.
// ---------------------------------------------------------------------

// gbCommitTime <subject> -- the leading "YYYY-MM-DD HH:MM" a backup
// commit's subject always starts with (spec "Формат коммита", G03: "по
// списку коммитов в вебе видно, когда снят каждый, без открывания") --
// same extraction overview.js's own gbCommitTime already does for the
// single most recent commit; duplicated here rather than shared because
// each view here is its own self-contained file, same convention
// paths.js's own private GB_CSS/gbSequentialMap already follow.
function gbCommitTime(subject) {
	var m = (subject || '').match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2})/);
	return m ? m[1] : null;
}

// gbShortenRepoPath <path> -- a path as it appears in this device's own
// branch tree (e.g. "devices/r1/files/etc/config/network",
// "devices/r1/meta/board.json", "devices/r1/manifest.json") rewritten to
// what an operator actually recognizes: the real absolute path under
// "files/", or a short "meta/..." / "manifest.json" label for anything
// else. The device-specific "devices/<id>/" prefix itself is never
// hard-coded here -- collect.sh's own `path_prefix` (gitbackup.main.
// path_prefix) can be a custom template, so this looks for the "/files/"
// or "/meta/" marker instead of assuming a fixed prefix shape.
function gbShortenRepoPath(path) {
	var idx = path.indexOf('/files/');
	if (idx !== -1)
		return path.substring(idx + '/files'.length);

	idx = path.indexOf('/meta/');
	if (idx !== -1)
		return path.substring(idx + 1);

	if (/\/manifest\.json$/.test(path))
		return 'manifest.json';

	return path;
}

// gbSummarizeList <items[]> <max> -- "a, b, c" or, past <max> entries,
// "a, b, c and N more" -- the same "до трёх... больше трёх -- и ещё N"
// convention the commit subject itself already uses (spec "Формат
// коммита"), applied here to `changed[]` (history's own full per-commit
// path list, which for a device's very first backup commit is every file
// it has -- unabridged, unlike the subject's own three-item cap).
function gbSummarizeList(items, max) {
	if (!items.length)
		return '';
	if (items.length <= max)
		return items.join(', ');
	return items.slice(0, max).join(', ') + ' ' + _('and %d more').format(items.length - max);
}

// ---------------------------------------------------------------------
// Diff parsing -- `diff` (gbrpc_diff) hands back plain `git diff <a> <b>`
// text, unrestricted (interfaces.md: "diff принимает два уже закоммиченных
// sha... и даёт git diff между ними"). Everything below reads that text
// only; no assumption is made beyond git's own documented unified-diff
// output shape (`diff --git a/X b/X`, optional "new file mode"/"deleted
// file mode", "--- "/"+++ " headers, "@@ ... @@" hunks, body lines
// prefixed ' '/'+'/'-').
// ---------------------------------------------------------------------

// gbDiffSections <text> -- one entry per "diff --git " block: { header,
// body[] } (body = every following line up to, not including, the next
// "diff --git " line). The one grouping both the file list and the
// board.json comparison below are built from, so the two can never
// disagree about where one file's diff ends and the next begins.
function gbDiffSections(text) {
	var lines = (text || '').split('\n');
	var sections = [];
	var cur = null;
	var i;

	for (i = 0; i < lines.length; i++) {
		if (lines[i].indexOf('diff --git ') === 0) {
			cur = { header: lines[i], body: [] };
			sections.push(cur);
		} else if (cur) {
			cur.body.push(lines[i]);
		}
	}

	return sections;
}

// gbSectionPath <header> -- the "b/..." side of a "diff --git a/X b/X"
// line. Git always fills in the same path on both sides for a plain add
// or delete (no rename detection requested), so this never needs the
// "a/" side at all.
function gbSectionPath(header) {
	var m = header.match(/^diff --git a\/(.+) b\/(.+)$/);
	return m ? m[2] : null;
}

// gbSectionStatus <section> -- 'added' | 'deleted' | 'modified', from
// git's own "new file mode" / "deleted file mode" body lines (present
// only for those two cases).
function gbSectionStatus(section) {
	var i;
	for (i = 0; i < section.body.length; i++) {
		if (section.body[i].indexOf('new file mode') === 0)
			return 'added';
		if (section.body[i].indexOf('deleted file mode') === 0)
			return 'deleted';
	}
	return 'modified';
}

// gbDiffFileList <text> -- [{ path, status }], one per changed file.
function gbDiffFileList(text) {
	return gbDiffSections(text).map(function(s) {
		return { path: gbSectionPath(s.header), status: gbSectionStatus(s) };
	}).filter(function(f) { return f.path; });
}

// gbBoardMismatch <text> -- true when the diff between the current branch
// tip and the commit about to be restored changed meta/board.json's own
// "model" or "target" field. Mirrors restore.sh's own authoritative check
// (_gb_restore_check_board: "model" plus "release.target", the same two
// fields device.sh's board strategy and the armsr/generic-target case
// both rely on -- interfaces.md's own note that `model` is `null` on
// those targets) rather than "board.json changed at all": board.json also
// carries a plain `hostname` field, and flagging every rename as a board
// mismatch would train an operator to ignore the warning. This can only
// approximate restore.sh's live `ubus call system board` comparison with
// the closest thing a read-only rpcd surface exposes -- the most recent
// commit's own meta/board.json, i.e. what the last successful backup run
// saw. restore.sh itself remains the actual, authoritative gate (it always
// re-checks against the live board and refuses without --force); this is
// only the up-front warning the brief asks for.
function gbBoardMismatch(text) {
	var sections = gbDiffSections(text);
	var i, j, path, line, ch;

	for (i = 0; i < sections.length; i++) {
		path = gbSectionPath(sections[i].header);
		if (!path || !/\/meta\/board\.json$/.test(path))
			continue;

		for (j = 0; j < sections[i].body.length; j++) {
			line = sections[i].body[j];
			ch = line.charAt(0);
			if (ch !== '+' && ch !== '-')
				continue;
			if (line.indexOf('+++') === 0 || line.indexOf('---') === 0)
				continue;
			if (line.indexOf('"model"') !== -1 || line.indexOf('"target"') !== -1)
				return true;
		}
	}

	return false;
}

// gbFilesPath <path> -- the real absolute filesystem path for an entry
// under ".../files/...", or null for anything else (meta/*, manifest.json).
// `restore` (restore.sh's own gb_restore) only ever writes manifest
// entries -- i.e. the "files/" tree -- back onto the router; it never
// touches meta/board.json, manifest.json or any other bookkeeping file on
// disk. A changed-file list built straight from `gbDiffFileList` would
// therefore mislabel bookkeeping-only commits (a manifest.json-only diff,
// say) as "these files will be overwritten" when nothing on disk would
// actually change.
function gbFilesPath(path) {
	var idx = path.indexOf('/files/');
	return idx === -1 ? null : path.substring(idx + '/files'.length);
}

// gbRestorePlan <diffText> -- [{ path, action }], action is 'create' (the
// path exists in the target commit but not in the current branch tip, so
// restore will write it fresh) or 'overwrite' (exists in both, content
// differs). A file that exists in the current tip but NOT in the target
// ('deleted' in git-diff terms, moving tip -> target) is deliberately
// left out: restore.sh has no delete pass at all (spec: "разложить файлы,
// затем применить mode/uid/gid... пересоздать симлинки" -- nothing about
// removing a file the target commit does not mention), so that path would
// simply be left untouched by a real restore, not "removed", and listing
// it as something that will be "overwritten" would be flatly wrong.
function gbRestorePlan(diffText) {
	var files = gbDiffFileList(diffText);
	var plan = [];
	var i, real;

	for (i = 0; i < files.length; i++) {
		if (files[i].status === 'deleted')
			continue;
		real = gbFilesPath(files[i].path);
		if (!real)
			continue;
		plan.push({ path: real, action: files[i].status === 'added' ? 'create' : 'overwrite' });
	}

	return plan;
}

// The colored-<pre> diff viewer itself moved to diffview.js (ticket 23:
// "не пиши второй просмотрщик diff") once Overview needed one too, for a
// different diff format (config_diff's manifest-field lines, not a real
// `git diff`) -- see that file's own header comment for why this is two
// explicit renderers in one shared place rather than one that guesses.
// handleViewDiff below calls diffview.unified(res.diff): `diff` (gbrpc_diff,
// two already-committed shas) is real `git diff --end-of-options <a> <b>`
// output (usr/sbin/gitbackup's cmd_diff, its two-argument form), exactly
// what diffview.unified expects.

// ---------------------------------------------------------------------
// Restore log classification -- restore.sh's own gb_log calls (all of
// them: success, every refusal, every fetch/checkout failure) go through
// `logger -t gitbackup` (lib.sh's gb_log), which `log`/logread already
// tag-filters -- the exact same mechanism overview.js's own live-log
// poller already reads for `run`/`test`. Restore's plain `printf` on
// success ("restored %s from %s") is NOT captured here: gbrpc_restore
// backgrounds the CLI with its stdout sent to /dev/null (same shape as
// run/test), so only the gb_log line right before it ("gb_restore:
// restored $device from $target on $branch") is ever visible through this
// poller -- reason this regex keys on that line, not the printf one.
// ---------------------------------------------------------------------
// Ticket 23: 'writing one or more files failed' used to sit here instead of
// the line below, and never matched anything restore.sh actually logs --
// found while tracing ticket 19's own change (restore.sh, _gb_restore:
// "a partially-restored router with correct permissions... always tells
// the operator the truth (below) with a non-zero exit" prints
// "gb_restore: the following paths were NOT written:<list>" via gb_log,
// never the old string) against this poller's own terminal-line set. With
// the wrong string here, a partial restore (ticket 19's own headline
// outcome -- content written, permissions applied, exit 1) never matched
// GB_RESTORE_TERMINAL_RE at all and this poller ran all the way to its own
// 60s-idle/5-minute ceiling before saying anything, exactly the
// "непонятно, чем кончилось" ticket 23 exists to fix.
var GB_RESTORE_TERMINAL_RE = new RegExp(
	[
		'gb_restore: restored .+ from .+ on ',
		'the following paths were NOT written:',
		'this backup was taken on a different board',
		'sha256 mismatch, refusing to write anything to disk',
		'does not exist on .+ yet -- nothing to restore',
		'was not found on .+ at ',
		'could not read .+ from .+ on .+:',
		'git fetch .+ failed',
		'cannot create a work directory',
		'repository url is required'
	].join('|')
);

function gbRestoreLogSuccess(line) {
	return line.indexOf('gb_restore: restored ') !== -1;
}

// gbClassifyRestoreLog <line> -- the human-readable, three-severity outcome
// behind GB_RESTORE_TERMINAL_RE's own match (ticket 23: "каждая долгая
// операция заканчивается явным сообщением... причина неудачи написана
// человеческим языком"). 'partial' is its own kind, deliberately distinct
// from both 'success' and 'error' -- ticket 19's restore.sh always applies
// permissions to whatever DID get written even when something else did not
// (spec: "частичный успех... обязан быть виден и отличаться от полного"),
// and folding it into either extreme would misreport which one actually
// happened. 'blocked' covers the one refusal that is a safety check working
// as intended (a board mismatch neither this view's own heuristic nor the
// operator's confirmation caught), kept apart from a genuine 'error' (a
// network/fetch/config problem) since the next step for each is different.
function gbClassifyRestoreLog(line) {
	if (gbRestoreLogSuccess(line))
		return { kind: 'success', message: _('Restore finished. This router now matches the backup you selected.') };

	if (line.indexOf('the following paths were NOT written:') !== -1)
		return {
			kind: 'partial',
			message: _('Restore finished, but some files could not be written -- see the log below for which ones and why. Permissions were still applied to every file that DID get written. Consider restoring again once the problem (a busy mount, a read-only path) is resolved.')
		};

	if (line.indexOf('this backup was taken on a different board') !== -1)
		return { kind: 'blocked', message: _('Refused: this backup was taken on a different router model -- nothing was restored.') };

	if (line.indexOf('sha256 mismatch, refusing to write anything to disk') !== -1)
		return { kind: 'error', message: _('Refused: the files in this backup could not be verified (a checksum did not match) -- nothing was written to disk.') };

	if (/does not exist on .+ yet -- nothing to restore/.test(line))
		return { kind: 'error', message: _('This device has no backup on that branch yet -- nothing was restored.') };

	if (/was not found on .+ at /.test(line))
		return { kind: 'error', message: _('The selected backup could not be found on the remote -- nothing was restored.') };

	if (/could not read .+ from .+ on .+:/.test(line))
		return { kind: 'error', message: _('Could not read the backup\'s manifest from the remote -- nothing was restored.') };

	if (/git fetch .+ failed/.test(line))
		return { kind: 'error', message: _('Could not reach the remote repository -- nothing was restored.') };

	if (line.indexOf('cannot create a work directory') !== -1)
		return { kind: 'error', message: _('Could not create a temporary work directory on the router -- nothing was restored.') };

	if (line.indexOf('repository url is required') !== -1)
		return { kind: 'error', message: _('The repository URL is not configured -- nothing was restored.') };

	return { kind: 'error', message: _('Restore failed -- see the log below for details.') };
}

// gbRestoreSeverity <kind> -- gbClassifyRestoreLog's own four kinds
// collapsed to the three severities showRestoreResult below actually
// styles: 'success' -> ok, 'partial'/'blocked' -> warn (something is worth
// a second look, but this is not the network/config failures 'error'
// means), 'error' (and anything unrecognized) -> error.
function gbRestoreSeverity(kind) {
	if (kind === 'success')
		return 'ok';
	if (kind === 'partial' || kind === 'blocked')
		return 'warn';
	return 'error';
}

var GB_CSS = [
	'.gitbackup-view { container-type: inline-size; }',
	'.gitbackup-card-hint { font-size: .9em; color: var(--text-color-medium, #666); }',
	'.gitbackup-banner { border-radius: 4px; padding: .6em 1em; margin: 0 0 .75em; background: var(--error-color-medium, #f44336); color: var(--on-error-color, #fff); }',
	'.gitbackup-banner p { margin: .2em 0; }',
	'.gitbackup-history-list { list-style: none; margin: .75em 0; padding: 0; }',
	'.gitbackup-history-row { border: 1px solid var(--background-color-medium, #ddd); border-radius: 4px; padding: .6em .9em; margin: 0 0 .6em; background: var(--background-color-low, #f5f5f5); }',
	'.gitbackup-history-head { display: flex; flex-wrap: wrap; align-items: baseline; justify-content: space-between; gap: .5em 1em; }',
	'@container (max-width: 560px) { .gitbackup-history-head { flex-direction: column; align-items: flex-start; } }',
	'.gitbackup-history-date { font-weight: bold; color: var(--text-color-high, #333); }',
	'.gitbackup-history-sha { font-family: monospace; font-size: .85em; color: var(--text-color-medium, #666); }',
	'.gitbackup-history-subject { font-size: .9em; color: var(--text-color-high, #333); margin: .35em 0 0; }',
	'.gitbackup-history-changed { font-size: .85em; color: var(--text-color-medium, #666); margin: .3em 0 0; word-break: break-word; }',
	'.gitbackup-history-actions { display: flex; flex-wrap: wrap; gap: .5em; margin-top: .6em; }',
	'.gitbackup-restore-files { list-style: none; margin: .5em 0; padding: 0; max-height: 260px; overflow: auto; border: 1px solid var(--background-color-medium, #ddd); border-radius: 4px; }',
	'.gitbackup-restore-file-row { display: flex; gap: .6em; padding: .3em .6em; border-bottom: 1px solid var(--background-color-medium, #ddd); font-family: monospace; font-size: .85em; color: var(--text-color-high, #333); }',
	'.gitbackup-restore-file-row:last-child { border-bottom: none; }',
	'.gitbackup-restore-action-create { color: var(--success-color-high, #2e7d32); }',
	'.gitbackup-restore-action-overwrite { color: var(--warn-color-high, #b45f06); }',
	'.gitbackup-confirm-input { width: 100%; box-sizing: border-box; margin: .5em 0; }',
	'.gitbackup-modal-actions { display: flex; justify-content: flex-end; gap: .5em; margin-top: 1em; }',
	'.gitbackup-log { max-height: 320px; overflow: auto; background: var(--background-color-low, #f5f5f5); color: var(--text-color-high, #333); border: 1px solid var(--background-color-medium, #ddd); border-radius: 4px; padding: .6em .8em; font-family: monospace; font-size: .85em; white-space: pre-wrap; }',
	// gitbackup-hint-ok/-warn/-error -- same three severities settings.js's
	// own copy already uses (ticket 12); reused here (ticket 23) for
	// showRestoreResult's own success/partial-or-blocked/error message.
	'.gitbackup-hint-ok { color: var(--success-color-high, #2e7d32); }',
	'.gitbackup-hint-warn { color: var(--warn-color-high, #b45f06); }',
	'.gitbackup-hint-error { color: var(--error-color-high, #c62828); }',
	'.gitbackup-restore-outcome { font-weight: bold; }'
];

return view.extend({
	// Not a config form -- see overview.js's own identical comment. Rule 11
	// of the spec's style guide: the stock Save/Apply/Reset row is switched
	// off through this documented hook, never hidden with CSS.
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		// `status` only (device name for the second restore-confirmation
		// screen) -- local file reads, same "cheap" bucket overview.js's
		// own load() puts status/log/service in. `history` itself is
		// deliberately NOT here: it is a real `git fetch` against the
		// configured remote with no timeout of its own (interfaces.md,
		// tickets 11/13: "Долгие вызовы... не вешаются на первичную
		// загрузку страницы" -- measured live at several seconds against a
		// real GitHub remote). render() below starts it once the rest of
		// the page is already on screen, same pattern overview.js's own
		// refreshHistory() already uses.
		return L.resolveDefault(callStatus(), null);
	},

	render: function(status) {
		var self = this;
		var view;

		self._status = status || {};
		self._commits = null;

		view = E('div', { 'class': 'gitbackup-view' }, [
			E('style', { 'type': 'text/css' }, [ GB_CSS.concat(diffview.css).join('\n') ]),

			E('h2', {}, [ _('Git Backup - History / Restore') ]),

			// Ticket 22: found-in-the-field complaint was "restore exists
			// but nobody looks for it on a tab called History" -- this
			// hint is the fix's cheap half (the tab rename above is the
			// other): it states the round-trip capability up front, in
			// plain text, with no hover required, before a single commit
			// row has even loaded.
			E('p', { 'class': 'gitbackup-card-hint' },
				[ _('You can restore this router to any backup listed below, using that backup\'s own "Restore" button. Click "View diff" first to see exactly what it would change.') ]),

			E('div', { 'id': 'gitbackup-history-body' }, [
				E('p', { 'class': 'gitbackup-card-hint' }, [ _('Loading…') ])
			])

			// Ticket 23: the old page-level "#gitbackup-restore-log" <pre>
			// that used to live here is gone -- the confirmation modal
			// itself now stays open for the whole restore and shows the
			// live log and the final outcome in place (see
			// handleConfirmRestore/showRestoreProgress/showRestoreResult
			// below), instead of hiding itself immediately and leaving an
			// operator to notice a page element they were never told to
			// watch (spec: "модальное окно... не должно просто
			// закрываться... а в конце говорит, что восстановлено").
		]);

		// Fired once render() has already returned the tree above, exactly
		// like overview.js's own refreshHistory() -- see load()'s own
		// comment for why `history` cannot run inside load() itself.
		self.refreshHistory();

		return view;
	},

	refreshHistory: function() {
		var self = this;

		return L.resolveDefault(callHistory(GB_HISTORY_LIMIT), null).then(function(res) {
			self._commits = (res && res.commits) || null;
			self._historyErr = (!res) ?
				_('Could not reach the remote repository.') :
				(res.reason || null);
			self.renderBody();
		});
	},

	renderBody: function() {
		var self = this;
		var body = document.getElementById('gitbackup-history-body');
		var commits = self._commits;

		if (!body)
			return;

		body.textContent = '';

		if (self._historyErr && (!commits || !commits.length)) {
			body.appendChild(E('p', { 'class': 'gitbackup-card-hint' },
				[ _('Could not load the backup history: %s').format(self._historyErr) ]));
			return;
		}

		if (!commits || !commits.length) {
			body.appendChild(E('p', { 'class': 'gitbackup-card-hint' },
				[ _('No backups on this device\'s branch yet.') ]));
			return;
		}

		body.appendChild(E('ul', { 'class': 'gitbackup-history-list' },
			commits.map(function(commit, i) {
				return self.buildHistoryRow(commit, (i + 1 < commits.length) ? commits[i + 1].sha : null);
			})));
	},

	buildHistoryRow: function(commit, parentSha) {
		var self = this;
		var time = gbCommitTime(commit.subject);
		var changed = (commit.changed || []).map(gbShortenRepoPath);

		return E('li', { 'class': 'gitbackup-history-row' }, [
			E('div', { 'class': 'gitbackup-history-head' }, [
				E('span', { 'class': 'gitbackup-history-date' }, [ time || _('(no date found in subject)') ]),
				E('span', { 'class': 'gitbackup-history-sha' }, [ commit.sha.substring(0, 12) ])
			]),
			E('div', { 'class': 'gitbackup-history-subject' }, [ commit.subject || '-' ]),
			E('div', { 'class': 'gitbackup-history-changed' },
				[ changed.length ? _('Changed: %s').format(gbSummarizeList(changed, 6)) : _('Nothing recorded as changed.') ]),
			E('div', { 'class': 'gitbackup-history-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': ui.createHandlerFn(self, 'handleViewDiff', commit, parentSha)
				}, [ _('View diff') ]),
				E('button', {
					'class': 'cbi-button cbi-button-negative',
					'click': ui.createHandlerFn(self, 'handleRestoreClick', commit)
				}, [ _('Restore') ])
			])
		]);
	},

	// handleViewDiff <commit> <parentSha> -- the per-commit diff (spec:
	// "Клик -> diff в ui.showModal"), i.e. what THAT backup changed versus
	// the one right before it. `history`'s commits are newest-first and
	// this branch's own push machinery (gitio.sh's gb_commit_push) always
	// commits with exactly one parent, so the previous ROW's sha (already
	// known client-side) is that parent -- no extra round trip needed to
	// find it. The oldest row on screen has no such neighbour: its actual
	// parent (if any) sits outside this page's own GB_HISTORY_LIMIT
	// window, and fabricating a diff against the wrong commit would be
	// worse than admitting this view simply does not know it.
	handleViewDiff: function(commit, parentSha, ev) {
		var self = this;

		if (!parentSha) {
			ui.addNotification(null, E('p', {},
				[ _('No earlier backup loaded to compare against -- this is the oldest commit in this list.') ]), 'info');
			return;
		}

		ui.showModal(_('Loading diff…'), [ E('p', { 'class': 'spinning' }, [ _('Fetching diff from the remote…') ]) ]);

		return L.resolveDefault(callDiff(parentSha, commit.sha), null).then(function(res) {
			if (!res || typeof res.diff !== 'string') {
				ui.showModal(_('Diff'), [
					E('p', {}, [ _('Could not load the diff: %s').format((res && res.reason) || _('unknown error')) ]),
					E('div', { 'class': 'gitbackup-modal-actions' }, [
						E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ _('Close') ])
					])
				]);
				return;
			}

			ui.showModal(_('Diff: %s').format(gbCommitTime(commit.subject) || commit.sha.substring(0, 12)), [
				diffview.unified(res.diff),
				E('div', { 'class': 'gitbackup-modal-actions' }, [
					E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ _('Close') ])
				])
			]);
		});
	},

	// handleRestoreClick <commit> -- step 0: fetch the one diff this whole
	// confirmation flow is built on (current branch tip -> the commit
	// about to be restored) before showing anything, so the first
	// confirmation screen (spec: "первый экран показывает список
	// перезаписываемых файлов") is never a guess.
	handleRestoreClick: function(commit, ev) {
		var self = this;
		var headSha = (self._commits && self._commits[0] && self._commits[0].sha) || commit.sha;

		ui.showModal(_('Restore backup?'), [ E('p', { 'class': 'spinning' }, [ _('Comparing against the current commit…') ]) ]);

		return L.resolveDefault(callDiff(headSha, commit.sha), null).then(function(res) {
			var diffText = (res && typeof res.diff === 'string') ? res.diff : '';
			var plan = gbRestorePlan(diffText);
			var mismatch = gbBoardMismatch(diffText);

			self.showRestoreConfirm1(commit, plan, mismatch);
		});
	},

	// showRestoreConfirm1 -- first confirmation screen (spec, verbatim
	// above): the list of files that will actually be written, and, when
	// applicable, the board-mismatch warning ahead of any second screen --
	// never after.
	showRestoreConfirm1: function(commit, plan, mismatch) {
		var self = this;
		var body = [];

		if (mismatch) {
			body.push(E('div', { 'class': 'gitbackup-banner' }, [
				E('p', {}, [ _('This backup was taken on a different router model than the one it would be restored onto. Interface names and wireless radios from that hardware will not match this one -- restoring anyway may leave the network unreachable until the configuration is fixed by hand.') ])
			]));
		}

		body.push(E('p', {},
			[ _('Restoring the backup from %s (%s) will write the following files:')
				.format(gbCommitTime(commit.subject) || commit.sha, commit.sha.substring(0, 12)) ]));

		if (plan.length) {
			body.push(E('ul', { 'class': 'gitbackup-restore-files' }, plan.map(function(p) {
				return E('li', { 'class': 'gitbackup-restore-file-row' }, [
					E('span', { 'class': 'gitbackup-restore-action-' + p.action }, [ p.action ]),
					E('span', {}, [ p.path ])
				]);
			})));
		} else {
			body.push(E('p', { 'class': 'gitbackup-card-hint' },
				[ _('No file differs from the current commit -- restoring will not change anything on disk.') ]));
		}

		body.push(E('div', { 'class': 'gitbackup-modal-actions' }, [
			E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ _('Cancel') ]),
			E('button', {
				'class': 'cbi-button cbi-button-negative',
				'click': ui.createHandlerFn(self, 'showRestoreConfirm2', commit, mismatch)
			}, [ _('Continue') ])
		]));

		ui.showModal(_('Restore backup?'), body);
	},

	// showRestoreConfirm2 -- second confirmation screen (spec, verbatim:
	// "второй требует ввести имя устройства"): the operator has to type
	// this device's own name back, the same friction a destructive cloud
	// console action usually asks for. `status.device` (gitbackup status's
	// own `device` field, interfaces.md tickets 01/08-10) is the device
	// this router itself resolves to -- and the one `restore` is about to
	// be called for, since History only ever shows this router's own
	// branch.
	showRestoreConfirm2: function(commit, mismatch, ev) {
		var self = this;
		var device = self._status.device || '';
		var input, confirmBtn;

		input = E('input', {
			'type': 'text',
			'class': 'cbi-input-text gitbackup-confirm-input',
			'placeholder': device
		});

		confirmBtn = E('button', {
			'class': 'cbi-button cbi-button-negative',
			'disabled': true,
			'click': ui.createHandlerFn(self, 'handleConfirmRestore', commit, mismatch)
		}, [ _('Restore') ]);

		input.addEventListener('input', function() {
			confirmBtn.disabled = !device || (input.value !== device);
		});

		ui.showModal(_('Confirm restore'), [
			E('p', {}, [ _('Type this device\'s name (%s) to confirm restoring it.').format(device || _('(device name not configured)')) ]),
			input,
			E('div', { 'class': 'gitbackup-modal-actions' }, [
				E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ _('Cancel') ]),
				confirmBtn
			])
		]);
	},

	// handleConfirmRestore -- fires `restore` (write tier) and switches to
	// oplog.js's shared bounded live-log poller (ticket 23: "не изобретать
	// четвёртый механизм" -- the exact pattern overview.js's own
	// handleRun/handleTest use for run/test). The call itself only starts
	// the CLI in the background (gbrpc_restore always answers
	// `{started:true}` immediately) and can take a while for real (network
	// fetch of the target commit, sha256 verification of every file), so
	// this must not block the page.
	//
	// Ticket 23's own headline complaint about restore specifically:
	// the confirmation modal used to call ui.hideModal() right here and
	// let the page's own <pre> carry the live log silently underneath --
	// closing the one dialog that had the operator's attention just as an
	// irreversible, file-system-rewriting operation started, then saying
	// nothing further unless it failed to even START. It no longer hides
	// at all: showRestoreProgress below replaces this same dialog's
	// content in place, and stays open, showing the live log, until
	// showRestoreResult replaces it again with the actual outcome --
	// success, partial, or failure, spelled out in words (spec: "пусть
	// остаётся, показывает ход и в конце говорит, что восстановлено, что
	// не удалось и что делать дальше").
	//
	// `force` is passed whenever the board-mismatch warning fired on the
	// previous screen -- without it restore.sh's own
	// _gb_restore_check_board refuses outright (exit 4), which would turn
	// an operator's informed "restore anyway" into a silent no-op visible
	// only by reading the log by hand.
	handleConfirmRestore: function(commit, mismatch, ev) {
		var self = this;
		var device = self._status.device || '';

		self.showRestoreProgress();

		return oplog.start({
			fetch: function() { return L.resolveDefault(callLog(500), null).then(function(res) { return (res && res.text) || ''; }); },
			terminalRe: GB_RESTORE_TERMINAL_RE,
			onProgress: function(add) { self.appendRestoreProgress(add); },
			onFinish: function(line) {
				self.showRestoreResult(gbClassifyRestoreLog(line));
				self.refreshHistory();
			},
			onTimeout: function() {
				self.showRestoreResult({
					kind: 'unknown',
					message: _('No result from the restore after a while -- check the log below or the syslog by hand.')
				});
				self.refreshHistory();
			}
		}).then(function() {
			return callRestore(device, commit.sha, undefined, mismatch ? true : undefined);
		}).then(function(res) {
			if (!res || res.started !== true) {
				oplog.stop();
				self.showRestoreResult({ kind: 'error', message: _('Could not start the restore.') });
			}
		}).catch(function(e) {
			oplog.stop();
			self.showRestoreResult({ kind: 'error', message: _('Could not start the restore: %s').format(e.message) });
		});
	},

	// showRestoreProgress -- replaces the confirmation modal's own content
	// with a spinner and an empty live-log pane, IN THE SAME DIALOG (no
	// ui.hideModal() anywhere in this whole flow) -- see
	// handleConfirmRestore's own comment for why staying open matters here
	// specifically. No Close/Cancel control on purpose: restore.sh has no
	// interrupt handling once it starts writing, so a "Cancel" here could
	// only ever stop watching, never stop the restore itself, and offering
	// it would suggest otherwise.
	showRestoreProgress: function() {
		ui.showModal(_('Restoring…'), [
			E('p', { 'class': 'spinning' },
				[ _('Restoring the backup -- this can take a while. Do not power off the router.') ]),
			E('pre', { 'class': 'gitbackup-log', 'id': 'gitbackup-restore-modal-log' }, [ '' ])
		]);
	},

	appendRestoreProgress: function(add) {
		var pre = document.getElementById('gitbackup-restore-modal-log');

		if (!pre)
			return;

		pre.textContent = pre.textContent ? pre.textContent + '\n' + add : add;
		pre.scrollTop = pre.scrollHeight;
	},

	// showRestoreResult <cls> -- the final screen of the restore flow:
	// <cls> is gbClassifyRestoreLog's own {kind, message} (or the
	// onTimeout/could-not-start shapes handleConfirmRestore builds inline
	// above, both the same shape). Reads the progress pane's own
	// accumulated text (still in the DOM at this point, since this is the
	// same ui.showModal call that is about to replace it) rather than
	// keeping a second copy of it in JS state.
	//
	// Ticket 23's own explicit ask beyond "say what happened": "что делать
	// дальше" for the one outcome that actually has a next step worth
	// naming -- 'partial' (ticket 19's own headline case: content written,
	// permissions applied, one or more paths failed) points at the log
	// right below it, already showing exactly which paths and why.
	showRestoreResult: function(cls) {
		var pre = document.getElementById('gitbackup-restore-modal-log');
		var fullLog = pre ? pre.textContent : '';
		var severity = gbRestoreSeverity(cls.kind);
		var title = cls.kind === 'success' ? _('Restore finished') :
			cls.kind === 'partial' ? _('Restore finished with problems') :
			cls.kind === 'blocked' ? _('Restore refused') :
			_('Restore failed');
		var body = [
			E('p', { 'class': 'gitbackup-restore-outcome gitbackup-hint-' + severity }, [ cls.message ])
		];

		if (fullLog)
			body.push(E('pre', { 'class': 'gitbackup-log' }, [ fullLog ]));

		body.push(E('div', { 'class': 'gitbackup-modal-actions' }, [
			E('button', { 'class': 'cbi-button', 'click': ui.hideModal }, [ _('Close') ])
		]));

		ui.showModal(title, body);
	}
});
