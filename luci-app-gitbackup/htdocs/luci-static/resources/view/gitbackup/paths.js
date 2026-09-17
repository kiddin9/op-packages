'use strict';
'require view';
'require rpc';
'require ui';
'require fs';

// gitbackup -- Paths (ticket 13, spec "Решения по реализации -> LuCI -> Paths",
// "Сбор и manifest.json", "Проверенные факты 25.12.4 -> sysupgrade"). Client-side
// JS only, luci-base only -- same constraint and the same jsmin-conservative
// style (plain ES5, `var`/`function`, no let/const/arrow/template literals,
// every statement semicolon-terminated) as overview.js (ticket 11), read
// before writing this file.
//
// The whole point of this screen (spec/brief, verbatim): "Расширение списка --
// редактирование /etc/sysupgrade.conf, а не отдельный UCI-список. То, что
// пользователь добавил ради бэкапа, автоматически переживёт реальный
// sysupgrade." That file is owned entirely by package/gitbackup's paths.sh and
// this file's own rpcd bridge (usr/libexec/rpcd/luci.gitbackup) -- both out of
// this ticket's own zone in the original cut, but the read/write asymmetry
// documented below was later closed in that same package/gitbackup zone, and
// this view was updated alongside it.
//
// ---------------------------------------------------------------------
// Raw vs. entries vs. effective -- the defect this file used to work
// around instead of fixing, closed by making `list_paths` carry three
// sets explicitly:
//
//   - `paths`     -- the RAW, unexpanded content of /etc/sysupgrade.conf
//                    (gb_paths_list), comments and blank lines included.
//                    Not used by this view at all (see `entries` below).
//   - `entries`   -- (ticket 26) `paths`, filtered down to genuine path
//                    entries: comments (sysupgrade.conf's own syntax --
//                    a line starting with '#', including a commented-out
//                    EXAMPLE such as "# /etc/openvpn/", which backs up
//                    nothing) and blank lines are dropped by
//                    gb_paths_entries server-side. This is what this view
//                    lists and edits, and the only thing `set_paths` ever
//                    writes back -- a directory line stays a directory
//                    line across any number of edits, so anything added
//                    to it later keeps being covered by a real sysupgrade
//                    the same way it always was, instead of being frozen
//                    into the exact file list that happened to exist on
//                    the day of the last save here. Before this field
//                    existed, this view built its editable list straight
//                    from `paths`, so a stock router's own header
//                    comments and example lines rendered as four bogus,
//                    removable entries -- and the first save from this
//                    view (any Add or Remove click) silently erased them,
//                    because `set_paths` used to write back only what it
//                    was sent and never looked at the rest of the file.
//                    That erasure is now prevented server-side
//                    (gb_paths_replace_entries, paths.sh) rather than by
//                    this view trying to resend lines it was never shown
//                    in the first place -- see that function's own header
//                    comment for why the fix belongs there.
//   - `effective` -- plain `sysupgrade -l`'s own wider union (spec:
//                    "(/etc/sysupgrade.conf ∪ /lib/upgrade/keep.d/*) ∪
//                    изменённые conffiles"), already recursively expanded
//                    to individual files/symlinks. Read-only: used only
//                    to size the real backup set (the 2 MB warning has to
//                    mean what `sysupgrade -b` will actually build, not
//                    just the lines a human typed) and to show what is
//                    already covered without anyone having added it here.
//
// Earlier, `list_paths` returned only the effective set under the name
// `paths`, so this view's own edits were built on top of the ALREADY
// EXPANDED list -- the first save after a human added a directory line
// via the CLI would write that directory's individual files straight
// back to sysupgrade.conf, permanently losing the one-line-per-directory
// convenience. Editing the raw set instead removes the problem instead of
// working around it.
//
// A second, related gap this same change closes: `set_paths`'s own
// server-side check used to duplicate only two of paths.sh's
// gb_paths_validate rules (absolute, the fixed blacklist), leaving a
// space in the path and a nonexistent path to this view's own JS to
// catch -- which could never reliably tell a dangling symlink (a
// legitimate entry, e.g. /etc/resolv.conf) from a genuinely missing path,
// because no rpcd ACL anywhere grants `fs.lstat` (confirmed live: every
// attempt at fs.lstat here failed with rpcd's own -32002 "Access denied",
// browser console, root login included -- only `fs.stat` is reachable).
// `set_paths` now routes every entry through gb_paths_validate itself,
// which runs ON the router and sees the real filesystem, so it gets `-e
// || -L` right without needing that ACL grant at all. This view keeps its
// own quick client-side checks (gbPathReject below) as a fast first pass
// that avoids an obviously-doomed round trip, but the round trip -- and
// its `rejected[]` response -- is the actual, authoritative gate; this
// view no longer attempts its own existence check at all.
// ---------------------------------------------------------------------

var callListPaths = rpc.declare({
	object: 'luci.gitbackup',
	method: 'list_paths'
});

var callAuditPaths = rpc.declare({
	object: 'luci.gitbackup',
	method: 'audit_paths'
});

var callSetPaths = rpc.declare({
	object: 'luci.gitbackup',
	method: 'set_paths',
	params: [ 'paths' ]
});

// gb_paths_size_kb (paths.sh) rounds bytes up to a whole KB: awk's
// `(s + 1023) / 1024` truncated to an integer is exactly `ceil(s / 1024)`.
// No rpcd method exposes that number directly, so this view derives the
// same total the same way paths.sh does: sum the byte size of every entry
// in `list_paths`'s "effective" set -- the same full set `sysupgrade -l`
// (and `run`'s own pre-flight space check) actually measures, not just
// the raw lines a human typed -- using `fs.stat`, deliberately not
// `fs.lstat`, and not only because of the ACL note above. gb_paths_size_kb's
// own test is plain `[ -f "$path" ]`, which -- confirmed live against this
// stand's busybox ash (a symlink to a regular file passes `-f`) -- FOLLOWS
// a symlink to its target, same as `fs.stat`; only a target that is not a
// regular file (a directory, or a dangling symlink) makes `-f` false and
// the entry contributes 0. Using `fs.lstat` here would size the symlink's
// own few bytes instead of its target's real content and disagree with
// the shell-side total for the exact same set.
var GB_PATHS_WARN_KB = 2048;

// gbPathReject <path> -- null when the path is worth submitting to
// `set_paths`, otherwise one human-readable reason, worded identically to
// package/gitbackup's paths.sh (gb_paths_validate) for the checks that
// module owns and that do not need a filesystem round trip: absolute, no
// space, not in the fixed blacklist. Order matches gb_paths_validate's own
// (absolute first, everything else assumes it). This is a fast first pass
// only -- `set_paths` re-validates every entry server-side (gb_paths_validate
// itself, including existence) and is the actual gate; a path that slips
// past this function is still caught there and reported through
// commitPaths's own `rejected[]` handling below.
function gbPathReject(path) {
	if (path.charAt(0) !== '/')
		return _('%s: not an absolute path').format(path);

	if (path.indexOf(' ') !== -1)
		return _('%s: contains a space -- sysupgrade.conf lines become find(1) arguments and cannot quote one').format(path);

	if (path === '/etc/gitbackup' || path.indexOf('/etc/gitbackup/') === 0)
		return _('%s: reserved for gitbackup itself').format(path);

	if (path === '/proc' || path.indexOf('/proc/') === 0)
		return _('%s: not a real filesystem path').format(path);

	if (path === '/sys' || path.indexOf('/sys/') === 0)
		return _('%s: not a real filesystem path').format(path);

	if (path === '/tmp' || path.indexOf('/tmp/') === 0)
		return _('%s: cleared on every reboot').format(path);

	return null;
}

// gbSequentialMap <items[]> <fn> -- like items.map(fn), but runs one call at
// a time and only starts the next once the previous settles, instead of
// firing every call at once. Confirmed necessary live on the owlab stand:
// stock `uhttpd` there runs with `-n 3` (three concurrent ubus-bridge
// requests, the same limit a real low-memory router ships with, not
// something this dev stand loosened), and firing one `fs.stat` per entry of
// even the 13-line clean-image default set at once left every later ubus
// call queued behind it indefinitely -- confirmed by watching the network
// panel: no request for a later call was even sent until an earlier one's
// slot freed, and with enough of them in flight the rest of the page (this
// view's own next list_paths/set_paths call, even an unrelated view) stayed
// stuck on "Loading view..." until the batch drained. `Promise.all` over
// every path was the original, incorrect implementation.
function gbSequentialMap(items, fn) {
	var results = [];
	var i = 0;

	function next() {
		if (i >= items.length)
			return Promise.resolve(results);

		return fn(items[i]).then(function(res) {
			results.push(res);
			i++;
			return next();
		});
	}

	return next();
}

// gbSumSizes <paths[]> -- { kb, unknown }. `unknown` counts entries whose
// size could not be read at all (permission, or the entry vanished between
// `list_paths` answering and this running) so the total is never silently
// wrong without saying so. Called with the "effective" set, never the raw
// one -- see the file-header comment.
function gbSumSizes(paths) {
	return gbSequentialMap(paths, function(p) {
		return fs.stat(p).then(function(st) { return st; }, function() { return null; });
	}).then(function(stats) {
		var bytes = 0;
		var unknown = 0;
		var i;

		for (i = 0; i < stats.length; i++) {
			if (stats[i] && stats[i].type === 'file')
				bytes += stats[i].size || 0;
			else if (!stats[i])
				unknown++;
		}

		return { kb: Math.ceil(bytes / 1024), unknown: unknown };
	});
}

// gbCoveredBy <rawEntry> <effectivePath> -- true when <effectivePath> is
// exactly <rawEntry>, or lies underneath it as a directory. <rawEntry>'s
// own trailing slash (if any -- sysupgrade.conf directory lines commonly
// carry one) is normalized away first so both spellings of the same
// directory match the same children.
function gbCoveredBy(rawEntry, effectivePath) {
	var prefix = rawEntry.replace(/\/+$/, '') + '/';
	return effectivePath === rawEntry || effectivePath.indexOf(prefix) === 0;
}

// gbAutomaticEntries <rawPaths[]> <effectivePaths[]> -- the "effective" set
// entries not explained by anything a human put in the raw list (not equal
// to a raw entry, not a descendant of a raw directory entry) -- i.e. only
// there because /lib/upgrade/keep.d/* or a changed package conffile
// already covers it. Shown read-only, separately from the editable raw
// list, so the operator can see the difference between "I added this" and
// "this is already covered without me doing anything".
function gbAutomaticEntries(rawPaths, effectivePaths) {
	return effectivePaths.filter(function(p) {
		var i;
		for (i = 0; i < rawPaths.length; i++) {
			if (gbCoveredBy(rawPaths[i], p))
				return false;
		}
		return true;
	});
}

function gbBuildPathRow(self, path, removable) {
	var children = [ E('span', { 'class': 'gitbackup-path-text' }, [ path ]) ];

	if (removable) {
		children.push(E('button', {
			'class': 'cbi-button cbi-button-remove',
			'click': ui.createHandlerFn(self, 'handleRemovePath', path)
		}, [ _('Remove') ]));
	} else {
		children.push(E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': ui.createHandlerFn(self, 'handleAddFromAudit', path)
		}, [ _('Add') ]));
	}

	return E('li', { 'class': 'gitbackup-path-row' }, children);
}

function gbBuildPathsList(self, paths) {
	if (!paths.length)
		return E('p', { 'class': 'gitbackup-card-hint' },
			[ _('Nothing here yet -- the base image\'s own defaults (%s) usually already list a handful of files.').format('/lib/upgrade/keep.d') ]);

	return E('ul', { 'class': 'gitbackup-path-list' }, paths.map(function(p) {
		return gbBuildPathRow(self, p, true);
	}));
}

function gbBuildSizeBox(kb, unknown) {
	var children = [];
	var text;

	if (kb == null)
		text = _('Calculating the backup set size…');
	else
		text = _('Total size of the backup set: %d KB').format(kb);

	if (unknown)
		text += ' ' + _('(some entries could not be measured and are left out of this total)');

	children.push(E('p', { 'class': 'gitbackup-size' }, [ text ]));

	if (kb != null && kb > GB_PATHS_WARN_KB) {
		children.push(E('div', { 'class': 'gitbackup-warn' }, [
			E('p', {}, [ _('This is over 2 MB. A real "sysupgrade -b" builds this archive entirely in RAM, and past this size it can fail on a low-memory device. This is only a warning -- nothing here is blocked, trim the list above if that matters on this device.') ])
		]));
	}

	return E('div', {}, children);
}

function gbBuildAutomaticBox(automatic) {
	var box = E('div', {}, [
		E('h3', { 'class': 'gitbackup-section-title' }, [ _('Also covered automatically') ]),
		E('p', { 'class': 'gitbackup-caption' },
			[ _('These are not part of the list above -- sysupgrade already backs them up on its own (package config changes, or /lib/upgrade/keep.d), whether or not anything is added here. Read-only.') ])
	]);

	if (!automatic.length) {
		box.appendChild(E('p', { 'class': 'gitbackup-card-hint' },
			[ _('Nothing outside the list above right now.') ]));
		return box;
	}

	box.appendChild(E('ul', { 'class': 'gitbackup-path-list' }, automatic.map(function(p) {
		return E('li', { 'class': 'gitbackup-path-row' }, [
			E('span', { 'class': 'gitbackup-path-text' }, [ p ])
		]);
	})));

	return box;
}

function gbBuildAuditBox(self, audit) {
	var box = E('div', {}, [
		E('h3', { 'class': 'gitbackup-section-title' }, [ _('Audit: changed on this router, but not backed up') ]),
		E('p', { 'class': 'gitbackup-caption' },
			[ _('Everything below is different from what the installed packages shipped and is not covered by the path list above -- add it, or leave it if it does not belong in the backup.') ])
	]);

	if (!audit.length) {
		box.appendChild(E('p', { 'class': 'gitbackup-card-hint' },
			[ _('Nothing to show here. Either every local change on this router is already covered by the backup set above, or this environment could not inspect the overlay filesystem to check at all -- an empty list is not, by itself, proof that nothing has changed.') ]));
		return box;
	}

	box.appendChild(E('ul', { 'class': 'gitbackup-path-list' }, audit.map(function(p) {
		return gbBuildPathRow(self, p, false);
	})));

	return box;
}

var GB_CSS = [
	'.gitbackup-view { container-type: inline-size; }',
	'.gitbackup-caption { color: var(--text-color-medium, #666); }',
	'.gitbackup-actions { display: flex; flex-wrap: wrap; gap: .5em; margin: .75em 0; align-items: center; }',
	'.gitbackup-actions input[type="text"] { flex: 1 1 260px; min-width: 200px; }',
	'.gitbackup-card-hint { font-size: .9em; color: var(--text-color-medium, #666); }',
	'.gitbackup-path-list { list-style: none; margin: .5em 0; padding: 0; }',
	'.gitbackup-path-row { display: flex; align-items: center; justify-content: space-between; gap: .75em; padding: .4em .6em; border-bottom: 1px solid var(--background-color-medium, #ddd); }',
	'.gitbackup-path-row:last-child { border-bottom: none; }',
	'.gitbackup-path-text { font-family: monospace; font-size: .9em; color: var(--text-color-high, #333); word-break: break-all; }',
	'@container (max-width: 480px) { .gitbackup-path-row { flex-direction: column; align-items: flex-start; } }',
	'.gitbackup-size { margin: .75em 0; color: var(--text-color-high, #333); }',
	'.gitbackup-warn { border: 1px solid var(--warn-color-medium, #f0c629); border-radius: 4px; padding: .6em 1em; margin: .5em 0; background: var(--background-color-low, #f5f5f5); color: var(--text-color-high, #333); }',
	'.gitbackup-section-title { margin: 1.25em 0 .25em; }'
];

return view.extend({
	// Not a config form -- see overview.js's own identical comment. Rule 11
	// of the spec's style guide: the stock Save/Apply/Reset row is switched
	// off through this documented hook, never hidden with CSS.
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			L.resolveDefault(callListPaths(), null),
			L.resolveDefault(callAuditPaths(), null)
		]);
	},

	render: function(data) {
		var self = this;
		var view;

		self._paths = (data[0] && data[0].entries) || [];
		self._effective = (data[0] && data[0].effective) || [];
		self._audit = (data[1] && data[1].paths) || [];
		self._sizeKb = null;
		self._sizeUnknown = 0;

		view = E('div', { 'class': 'gitbackup-view' }, [
			E('style', { 'type': 'text/css' }, [ GB_CSS.join('\n') ]),

			E('h2', {}, [ _('Git Backup - Paths') ]),

			// Spec, verbatim: the caption is itself a feature, not a footnote
			// -- this edits the same file the router's own firmware-upgrade
			// tool reads, so anything listed here survives a real sysupgrade
			// on its own, whether or not gitbackup itself ever runs again.
			E('p', { 'class': 'gitbackup-caption' },
				[ _('These paths also survive a firmware upgrade: they are written straight into /etc/sysupgrade.conf, the same file the router\'s own sysupgrade reads, not a separate list of this tool\'s own. A directory you add here stays a directory -- anything added to it later is covered too, exactly like a real sysupgrade would.') ]),

			E('div', { 'class': 'gitbackup-actions' }, [
				E('input', {
					'type': 'text',
					'id': 'gitbackup-paths-add-input',
					'class': 'cbi-input-text',
					'placeholder': _('/absolute/path/to/a/file/or/directory'),
					'keydown': function(ev) {
						if (ev.keyCode === 13) {
							ev.preventDefault();
							self.handleAddPath(ev);
						}
					}
				}),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'id': 'gitbackup-paths-add-btn',
					'click': ui.createHandlerFn(self, 'handleAddPath')
				}, [ _('Add path') ])
			]),

			E('div', { 'id': 'gitbackup-paths-body' })
		]);

		self.renderBody();
		self.refreshSizes();

		return view;
	},

	// Rebuilds the size summary, editable path list, automatic-coverage box
	// and audit box from self._paths/self._effective/self._audit -- called
	// after every load and every successful edit (commitPaths/refresh
	// below). Small N (13 keep.d entries on a clean stand plus whatever has
	// been added), so a full rebuild rather than per-row DOM patching is
	// simple and cheap enough.
	renderBody: function() {
		var self = this;
		var body = document.getElementById('gitbackup-paths-body');
		var automatic;

		if (!body)
			return;

		automatic = gbAutomaticEntries(self._paths, self._effective);

		body.textContent = '';
		body.appendChild(gbBuildSizeBox(self._sizeKb, self._sizeUnknown));
		body.appendChild(gbBuildPathsList(self, self._paths));
		body.appendChild(gbBuildAutomaticBox(automatic));
		body.appendChild(gbBuildAuditBox(self, self._audit));
	},

	refreshSizes: function() {
		var self = this;
		var effective = self._effective;

		return gbSumSizes(effective).then(function(res) {
			// A slower stat batch landing after the effective set moved on
			// (another edit already completed) would show a total for a
			// set that is no longer displayed -- discard it instead.
			if (self._effective !== effective)
				return;
			self._sizeKb = res.kb;
			self._sizeUnknown = res.unknown;
			self.renderBody();
		});
	},

	refresh: function() {
		var self = this;

		return Promise.all([
			L.resolveDefault(callListPaths(), null),
			L.resolveDefault(callAuditPaths(), null)
		]).then(function(data) {
			self._paths = (data[0] && data[0].entries) || [];
			self._effective = (data[0] && data[0].effective) || [];
			self._audit = (data[1] && data[1].paths) || [];
			self.renderBody();
			return self.refreshSizes();
		});
	},

	setAddBusy: function(busy) {
		var input = document.getElementById('gitbackup-paths-add-input');
		var btn = document.getElementById('gitbackup-paths-add-btn');

		if (input)
			input.disabled = busy;
		if (btn)
			btn.disabled = busy;
	},

	// commitPaths <newList> [addedPath] -- the one path to `set_paths`.
	// Reports every backend-side rejection by name and reason (spec: "не
	// молча"), then always refreshes from `list_paths` regardless of outcome
	// -- the effective set on disk is the only thing worth trusting after a
	// write, never this view's own optimistic guess at what changed.
	// Resolves to true only when `addedPath` (if given) was not among the
	// rejected entries, so callers adding a single new path know whether to
	// also clear the input field.
	commitPaths: function(newList, addedPath) {
		var self = this;

		return callSetPaths(newList).then(function(res) {
			var rejected = (res && res.rejected) || [];
			var ok = true;
			var i;

			for (i = 0; i < rejected.length; i++) {
				ui.addNotification(null, E('p', {},
					[ _('%s: %s').format(rejected[i].path, rejected[i].reason) ]), 'error');
				if (addedPath && rejected[i].path === addedPath)
					ok = false;
			}

			return self.refresh().then(function() { return ok; });
		}, function(e) {
			ui.addNotification(null, E('p', {},
				[ _('Could not save the path list: %s').format(e.message) ]), 'error');
			return false;
		});
	},

	// handleAddPath -- only the fast, local checks (non-empty, not already
	// present, gbPathReject's syntax-only rules) happen before this ever
	// calls `set_paths`. Existence is deliberately NOT checked here: it
	// needs a real filesystem, `set_paths` already checks it authoritatively
	// server-side (gb_paths_validate), and a client-side attempt at the same
	// question would need `fs.lstat`, which no rpcd ACL here grants -- see
	// the file-header comment.
	handleAddPath: function(ev) {
		var self = this;
		var input = document.getElementById('gitbackup-paths-add-input');
		var path = input ? input.value.replace(/^\s+|\s+$/g, '') : '';
		var reason;

		if (!path) {
			ui.addNotification(null, E('p', {}, [ _('Enter a path first.') ]), 'error');
			return;
		}

		if (self._paths.indexOf(path) !== -1) {
			ui.addNotification(null, E('p', {}, [ _('%s is already in the backup set.').format(path) ]), 'info');
			return;
		}

		reason = gbPathReject(path);
		if (reason) {
			ui.addNotification(null, E('p', {}, [ reason ]), 'error');
			return;
		}

		self.setAddBusy(true);

		return self.commitPaths(self._paths.concat([ path ]), path).then(function(ok) {
			if (ok && input)
				input.value = '';
			self.setAddBusy(false);
		});
	},

	handleAddFromAudit: function(ev, path) {
		var self = this;
		var reason = gbPathReject(path);

		if (reason) {
			ui.addNotification(null, E('p', {}, [ reason ]), 'error');
			return;
		}

		return self.commitPaths(self._paths.concat([ path ]), path);
	},

	handleRemovePath: function(ev, path) {
		var self = this;
		var idx = self._paths.indexOf(path);
		var next;

		if (idx === -1)
			return;

		next = self._paths.slice(0, idx).concat(self._paths.slice(idx + 1));
		return self.commitPaths(next);
	}
});
