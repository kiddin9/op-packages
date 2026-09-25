'use strict';
'require view';
'require rpc';
'require ui';
'require view.gitbackup.common as common';
/* global common */

// Writes back `entries`, never `effective` (sysupgrade -l): a directory line
// must stay a directory line, or files created after the save stop being
// backed up. Path validation lives in paths.sh only.

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

var GB_PATHS_WARN_KB = 2048;

// sysupgrade.conf directory lines commonly carry a trailing slash.
function gbCoveredBy(rawEntry, effectivePath) {
	var prefix = rawEntry.replace(/\/+$/, '') + '/';
	return effectivePath === rawEntry || effectivePath.indexOf(prefix) === 0;
}

// Effective entries no raw line explains: kept by /lib/upgrade/keep.d or a
// changed package conffile without the operator adding them.
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

function gbBuildSizeBox(kb) {
	var children = [
		E('p', { 'class': 'gitbackup-size' }, [ _('Total size of the backup set: %d KB').format(kb) ])
	];

	if (kb > GB_PATHS_WARN_KB) {
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
	'.gitbackup-actions input[type="text"] { flex: 1 1 260px; min-width: 200px; }',
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
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			L.resolveDefault(callListPaths(), null),
			L.resolveDefault(callAuditPaths(), null)
		]);
	},

	applyData: function(data) {
		this._paths = (data[0] && data[0].entries) || [];
		this._effective = (data[0] && data[0].effective) || [];
		this._sizeKb = (data[0] && data[0].size_kb) || 0;
		this._audit = (data[1] && data[1].paths) || [];
	},

	render: function(data) {
		var self = this;
		var view;

		self.applyData(data);
		self._body = E('div');

		view = E('div', { 'class': 'gitbackup-view' }, [
			E('style', { 'type': 'text/css' }, [ common.css.concat(GB_CSS).join('\n') ]),

			E('h2', {}, [ _('Git Backup - Paths') ]),

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

			self._body
		]);

		self.renderBody();

		return view;
	},

	renderBody: function() {
		var self = this;
		// A node reference, not getElementById: render() calls this before
		// its tree is attached to the document.
		var body = self._body;
		var automatic = gbAutomaticEntries(self._paths, self._effective);

		body.textContent = '';
		body.appendChild(gbBuildSizeBox(self._sizeKb));
		body.appendChild(gbBuildPathsList(self, self._paths));
		body.appendChild(gbBuildAutomaticBox(automatic));
		body.appendChild(gbBuildAuditBox(self, self._audit));
	},

	refresh: function() {
		var self = this;

		return self.load().then(function(data) {
			self.applyData(data);
			self.renderBody();
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

	// Resolves false when addedPath itself was rejected.
	commitPaths: function(newList, addedPath) {
		var self = this;

		return callSetPaths(newList).then(function(res) {
			var rejected = (res && res.rejected) || [];
			var ok = true;
			var i;

			for (i = 0; i < rejected.length; i++) {
				// The reason already starts with the path.
				ui.addNotification(null, E('p', {}, [ rejected[i].reason ]), 'error');
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

	handleAddPath: function(ev) {
		var self = this;
		var input = document.getElementById('gitbackup-paths-add-input');
		var path = input ? input.value.trim() : '';

		if (!path) {
			ui.addNotification(null, E('p', {}, [ _('Enter a path first.') ]), 'error');
			return;
		}

		if (self._paths.indexOf(path) !== -1) {
			ui.addNotification(null, E('p', {}, [ _('%s is already in the backup set.').format(path) ]), 'info');
			return;
		}

		self.setAddBusy(true);

		return self.commitPaths(self._paths.concat([ path ]), path).then(function(ok) {
			if (ok && input)
				input.value = '';
			self.setAddBusy(false);
		});
	},

	// createHandlerFn passes bound args first, the event last.
	handleAddFromAudit: function(path, ev) {
		return this.commitPaths(this._paths.concat([ path ]), path);
	},

	handleRemovePath: function(path, ev) {
		var self = this;
		var idx = self._paths.indexOf(path);
		var next;

		if (idx === -1)
			return;

		next = self._paths.slice(0, idx).concat(self._paths.slice(idx + 1));
		return self.commitPaths(next);
	}
});
