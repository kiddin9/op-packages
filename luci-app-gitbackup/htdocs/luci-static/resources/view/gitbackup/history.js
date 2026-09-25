'use strict';
'require view';
'require rpc';
'require ui';
'require view.gitbackup.common as common';
'require view.gitbackup.oplog as oplog';
/* global common, oplog */
// openwrt/luci's eslint config only knows stock module names as globals.

var callDiff = rpc.declare({
	object: 'luci.gitbackup',
	method: 'diff',
	params: [ 'from', 'to' ]
});

var callRestore = rpc.declare({
	object: 'luci.gitbackup',
	method: 'restore',
	params: [ 'device', 'commit', 'dry_run', 'force', 'with_packages' ]
});

// Every `history` call is a real git fetch.
var GB_HISTORY_LIMIT = 30;

// path_prefix is a template, so look for the marker, not a fixed prefix.
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

function gbSummarizeList(items, max) {
	if (!items.length)
		return '';
	if (items.length <= max)
		return items.join(', ');
	return items.slice(0, max).join(', ') + ' ' + _('and %d more').format(items.length - max);
}

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

function gbSectionPath(header) {
	var m = header.match(/^diff --git a\/(.+) b\/(.+)$/);
	return m ? m[2] : null;
}

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

function gbDiffFileList(text) {
	return gbDiffSections(text).map(function(s) {
		return { path: gbSectionPath(s.header), status: gbSectionStatus(s) };
	}).filter(function(f) { return f.path; });
}

// The same two fields restore.sh checks against the live board; restore.sh
// stays the real gate, this is only the up-front warning.
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

function gbFilesPath(path) {
	var idx = path.indexOf('/files/');
	return idx === -1 ? null : path.substring(idx + '/files'.length);
}

// A file only in the tip is left out: restore has no delete pass.
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

// restore.sh's success printf goes to /dev/null, so the gb_log line is what
// counts. Checked against tests/fixtures/terminal-markers.tsv.
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

function gbClassifyRestoreLog(line) {
	if (line.indexOf('gb_restore: restored ') !== -1)
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

function gbRestoreSeverity(kind) {
	if (kind === 'success')
		return 'ok';
	if (kind === 'partial' || kind === 'blocked')
		return 'warn';
	return 'error';
}

var GB_CSS = [
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
	'.gitbackup-restore-outcome { font-weight: bold; }'
];

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	// history is a git fetch; render() starts it after the first paint.
	load: function() {
		return L.resolveDefault(common.callStatus(), null);
	},

	render: function(status) {
		var self = this;
		var view;

		self._status = status || {};
		self._commits = null;

		view = E('div', { 'class': 'gitbackup-view' }, [
			E('style', { 'type': 'text/css' }, [ common.css.concat(GB_CSS).join('\n') ]),

			E('h2', {}, [ _('Git Backup - History / Restore') ]),

			E('p', { 'class': 'gitbackup-card-hint' },
				[ _('You can restore this router to any backup listed below, using that backup\'s own "Restore" button. Click "View diff" first to see exactly what it would change.') ]),

			E('div', { 'id': 'gitbackup-history-body' }, [
				E('p', { 'class': 'gitbackup-card-hint' }, [ _('Loading…') ])
			])
		]);

		self.refreshHistory();

		return view;
	},

	refreshHistory: function() {
		var self = this;

		return L.resolveDefault(common.callHistory(GB_HISTORY_LIMIT), null).then(function(res) {
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
		var time = common.commitTime(commit.subject);
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

	// The previous row is the only parent; the oldest row's is off the page.
	handleViewDiff: function(commit, parentSha, ev) {
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
					common.modalButtons()
				]);
				return;
			}

			ui.showModal(_('Diff: %s').format(common.commitTime(commit.subject) || commit.sha.substring(0, 12)), [
				common.unified(res.diff),
				common.modalButtons()
			]);
		});
	},

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

	showRestoreConfirm1: function(commit, plan, mismatch) {
		var self = this;
		var body = [];

		if (mismatch) {
			body.push(E('div', { 'class': 'alert-message error' }, [
				E('p', {}, [ _('This backup was taken on a different router model than the one it would be restored onto. Interface names and wireless radios from that hardware will not match this one -- restoring anyway may leave the network unreachable until the configuration is fixed by hand.') ])
			]));
		}

		body.push(E('p', {},
			[ _('Restoring the backup from %s (%s) will write the following files:')
				.format(common.commitTime(commit.subject) || commit.sha, commit.sha.substring(0, 12)) ]));

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

		body.push(common.modalButtons(_('Cancel'), [
			E('button', {
				'class': 'cbi-button cbi-button-negative',
				'click': ui.createHandlerFn(self, 'showRestoreConfirm2', commit, mismatch)
			}, [ _('Continue') ])
		]));

		ui.showModal(_('Restore backup?'), body);
	},

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
			common.modalButtons(_('Cancel'), [ confirmBtn ])
		]);
	},

	// `force` goes along when the board warning was shown, otherwise
	// restore.sh refuses the mismatch outright.
	handleConfirmRestore: function(commit, mismatch, ev) {
		var self = this;
		var device = self._status.device || '';

		// No Cancel: restore.sh cannot be interrupted once it writes.
		ui.showModal(_('Restoring…'), [
			E('p', { 'class': 'spinning' },
				[ _('Restoring the backup -- this can take a while. Do not power off the router.') ]),
			E('pre', { 'class': 'gitbackup-log', 'id': 'gitbackup-restore-modal-log' }, [ '' ])
		]);

		return oplog.run({
			call: function() {
				return callRestore(device, commit.sha, undefined, mismatch ? true : undefined);
			},
			pre: 'gitbackup-restore-modal-log',
			terminalRe: GB_RESTORE_TERMINAL_RE,
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
			},
			onFail: function(reason) {
				self.showRestoreResult({ kind: 'error', message: reason ?
					_('Could not start the restore: %s').format(reason) :
					_('Could not start the restore.') });
			}
		});
	},

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

		body.push(common.modalButtons());

		ui.showModal(title, body);
	}
});
