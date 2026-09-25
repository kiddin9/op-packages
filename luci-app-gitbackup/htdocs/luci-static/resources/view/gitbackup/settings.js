'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require view.gitbackup.common as common';
'require view.gitbackup.oplog as oplog';
/* global common, oplog */
// openwrt/luci's eslint config only knows stock module names as globals.

// The one view that is a form.Map, so the stock Save/Apply/Reset row stays.

var callPubkey = rpc.declare({
	object: 'luci.gitbackup',
	method: 'pubkey'
});

// keygen(force) never replaces an existing key: it answers
// {confirm_required, fingerprint}; keygen(force, fingerprint) goes through.
var callKeygen = rpc.declare({
	object: 'luci.gitbackup',
	method: 'keygen',
	params: [ 'force', 'confirm' ]
});

var callValidateCron = rpc.declare({
	object: 'luci.gitbackup',
	method: 'validate_cron',
	params: [ 'expr' ]
});

var callSetSecret = rpc.declare({
	object: 'luci.gitbackup',
	method: 'set_secret',
	params: [ 'value' ]
});

// hostkey() shows the remote's host key; hostkey(fingerprint) records it.
// `test` runs with stdin </dev/null, so this is the only web path to it.
var callHostkey = rpc.declare({
	object: 'luci.gitbackup',
	method: 'hostkey',
	params: [ 'fingerprint' ]
});

// formvalue() once the widget exists, the saved cfgvalue() before that --
// checkDepends runs on the first paint before any widget is built.
function gbFieldValue(section, section_id, name) {
	var v = section.formvalue(section_id, name);
	return (v != null) ? v : section.cfgvalue(section_id, name);
}

// navigator.clipboard needs a secure context, and LuCI over plain LAN
// http:// is not one: fall back to a throwaway <textarea> inside this view.
function gbCopyViaTextarea(text, container) {
	var ta = document.createElement('textarea');
	var ok;

	ta.value = text;
	ta.setAttribute('readonly', 'readonly');
	ta.style.position = 'fixed';
	ta.style.top = '0';
	ta.style.left = '0';
	ta.style.opacity = '0';
	container.appendChild(ta);

	ta.focus();
	ta.select();
	ta.setSelectionRange(0, text.length);

	try {
		ok = document.execCommand('copy');
	} catch (e) {
		ok = false;
	}

	container.removeChild(ta);
	return ok;
}

function gbCopyText(text, container) {
	if (window.isSecureContext && window.navigator && navigator.clipboard && navigator.clipboard.writeText) {
		return navigator.clipboard.writeText(text).then(function() {
			return true;
		}, function() {
			return gbCopyViaTextarea(text, container);
		});
	}

	return Promise.resolve(gbCopyViaTextarea(text, container));
}

function gbClassifyTestLog(text) {
	var lines = (text || '').split('\n');
	var i, line;

	for (i = lines.length - 1; i >= 0; i--) {
		line = lines[i];
		if (!line)
			continue;

		if (line.indexOf('reachable and authenticated') !== -1)
			return { kind: 'ok', message: _('Connected -- the remote is reachable and the credentials work.') };

		if (line.indexOf('publicly visible to an anonymous request') !== -1)
			return { kind: 'public', message: _('Blocked: this repository is publicly visible to an anonymous request. Push is refused until it is made private, or the remote is changed.') };

		if (line.indexOf('could not verify whether') !== -1 && line.indexOf('is public') !== -1)
			return { kind: 'unknown_visibility', message: _('Could not verify whether the repository is public -- the network or the provider\'s API was unreachable. Try again once connectivity is confirmed.') };

		if (line.indexOf('cannot reach ') !== -1)
			return { kind: 'network', message: _('Could not reach the remote -- check the URL, DNS and internet connectivity.') };

		if (line.indexOf('authentication to ') !== -1 && line.indexOf('failed') !== -1)
			return { kind: 'auth', message: _('The remote was reached, but authentication failed -- check the deploy key or the token.') };

		if (line.indexOf('host key was not accepted') !== -1)
			return { kind: 'auth', message: _('The SSH host key was not accepted.') };

		// No stdin to confirm the host key on -- see showHostkeyPrompt.
		if (line.indexOf('host key needs confirmation') !== -1)
			return { kind: 'hostkey_pending', message: _('The SSH host key has not been confirmed yet -- see its fingerprint below and accept it once to continue.') };

		if (line.indexOf('host key could not be obtained') !== -1)
			return { kind: 'network', message: _('Could not reach the remote to obtain its SSH host key -- check the URL and connectivity.') };
	}

	return { kind: 'pending', message: _('Waiting for the test to finish…') };
}

function gbTestSeverity(kind) {
	if (kind === 'ok')
		return 'ok';
	if (kind === 'public' || kind === 'network' || kind === 'auth')
		return 'error';
	return 'warn';
}

// Checked against tests/fixtures/terminal-markers.tsv.
var GB_TEST_TERMINAL_RE = new RegExp(
	[
		'reachable and authenticated',
		'publicly visible to an anonymous request',
		'could not verify whether .* is public',
		'cannot reach ',
		'authentication to .* failed',
		'host key was not accepted',
		'host key needs confirmation',
		'host key could not be obtained'
	].join('|')
);

// The deploy-key block, rebuilt by id after keygen so the rest of the
// form keeps whatever the operator is editing.
function gbBuildDeployKeyBody(view) {
	var pubkey = view._pubkey;
	var wrap = E('div', { 'id': 'gitbackup-deploykey-body' }, []);

	if (pubkey) {
		wrap.appendChild(E('textarea', {
			'class': 'gitbackup-pubkey',
			'id': 'gitbackup-pubkey-text',
			'rows': '3',
			'readonly': 'readonly'
		}, [ pubkey ]));
		wrap.appendChild(E('div', { 'class': 'gitbackup-actions' }, [
			E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'click': ui.createHandlerFn(view, 'handleCopyPubkey')
			}, [ _('Copy') ]),
			E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'id': 'gitbackup-btn-regenerate',
				'click': ui.createHandlerFn(view, 'handleGenerateKey', true)
			}, [ _('Regenerate key') ]),
			E('span', { 'class': 'gitbackup-copy-status', 'id': 'gitbackup-copy-status' }, [ '' ])
		]));
	} else {
		wrap.appendChild(E('p', {}, [ _('No deploy key has been generated on this router yet.') ]));
		wrap.appendChild(E('div', { 'class': 'gitbackup-actions' }, [
			E('button', {
				'class': 'cbi-button cbi-button-action',
				'click': ui.createHandlerFn(view, 'handleGenerateKey', false)
			}, [ _('Generate deploy key') ])
		]));
	}

	wrap.appendChild(E('div', { 'id': 'gitbackup-keygen-confirm', 'class': 'gitbackup-box', 'hidden': true }));

	wrap.appendChild(E('p', { 'class': 'gitbackup-hint', 'id': 'gitbackup-keygen-status', 'hidden': true }));

	return wrap;
}

// checkDepends is overridden because "auto on an unknown host" cannot be a
// plain .depends(); it also rebuilds the content in place, since checkDepends
// alone only toggles visibility.
function gbDeployHelpOption(s, name, title, wantGeneric, build) {
	var o = s.option(form.DummyValue, name, title);

	o.checkDepends = function(section_id) {
		var old = document.getElementById('gitbackup-' + name);
		var generic = common.provider(gbFieldValue(this.section, section_id, 'url'),
			gbFieldValue(this.section, section_id, 'provider')) === 'generic';

		if (old && old.parentNode)
			old.parentNode.replaceChild(this.renderWidget(section_id), old);

		return gbFieldValue(this.section, section_id, 'auth') === 'sshkey' && generic === wantGeneric;
	};
	o.renderWidget = function(section_id) {
		var info = common.deployKeyLink(gbFieldValue(this.section, section_id, 'url'),
			gbFieldValue(this.section, section_id, 'provider'));

		return E('div', { 'id': 'gitbackup-' + name, 'class': 'gitbackup-box' }, [].concat(build(info)));
	};

	return o;
}

var GB_CSS = [
	'.gitbackup-box { border: 1px solid var(--background-color-medium, #ddd); border-radius: 4px; padding: .75em 1em; margin: .5em 0; background: var(--background-color-low, #f5f5f5); }',
	'.gitbackup-box p { margin: .3em 0; }',
	'.gitbackup-box-title { font-weight: bold; color: var(--text-color-high, #333); margin: 0 0 .4em; }',
	'.gitbackup-pubkey { width: 100%; box-sizing: border-box; font-family: monospace; font-size: .8em; resize: vertical; }',
	'@container (max-width: 480px) { .gitbackup-actions { flex-direction: column; align-items: stretch; } }',
	'.gitbackup-copy-status { font-size: .85em; color: var(--text-color-medium, #666); }',
	'.gitbackup-warn-text { color: var(--warn-color-high, #b45f06); font-weight: bold; }',
	'.gitbackup-log { max-height: 220px; margin-top: .5em; }',
	'.gitbackup-test-result { font-weight: bold; margin-top: .4em; }'
];

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(common.callStatus(), null),
			L.resolveDefault(callPubkey(), null)
		]);
	},

	render: function(data) {
		var self = this;
		var m, s, o;

		self._status = data[0] || {};
		self._pubkey = (data[1] && typeof data[1].pubkey === 'string') ? data[1].pubkey : null;

		m = new form.Map('gitbackup', _('Git Backup - Settings'),
			_('Configuration for the whole gitbackup package. Saving reloads the schedule and, if the repository is public, forces config scrubbing on -- see the Overview tab for what that means.'));

		s = m.section(form.NamedSection, 'main', 'gitbackup', _('General'));
		s.addremove = false;

		s.option(form.Flag, 'enabled', _('Enabled'),
			_('Turns the whole package on or off -- scheduled runs, the config-change trigger and manual "Backup now" all stay inert while this is unchecked.'));

		o = s.option(form.Flag, 'archive', _('Keep a local archive'),
			_('Also write a backup.tar.gz next to the working tree on every run, for a quick local copy in addition to the git history.'));
		o.default = '1';

		o = s.option(form.ListValue, 'device_id', _('Device identifier'),
			_('How this router names itself in the repository -- its own branch and path prefix are built from this.'));
		o.value('hostname', _('System hostname'));
		o.value('custom', _('Custom name (set below)'));
		o.value('board', _('Board model'));
		o.default = 'hostname';

		o = s.option(form.Value, 'device', _('Custom device name'),
			_('Used only when "Device identifier" above is set to "Custom name".'));
		o.depends('device_id', 'custom');

		o = s.option(form.Value, 'path_prefix', _('Path prefix'),
			_('Where this device\'s files live inside the repository. "{device}" is replaced with the resolved device identifier.'));
		o.placeholder = 'devices/{device}';
		o.default = 'devices/{device}';

		o = s.option(form.Flag, 'on_config_change', _('Back up on config change'),
			_('Watches every UCI config in the backup set and starts a run a short while after any of them changes, instead of waiting for the next scheduled run.'));
		o.default = '1';

		o = s.option(form.Value, 'debounce', _('Debounce (seconds)'),
			_('How long to wait after the last detected config change before actually starting a run -- a burst of edits in the UI collapses into one commit instead of one per change.'));
		o.datatype = 'uinteger';
		o.placeholder = '60';
		o.default = '60';
		o.depends('on_config_change', '1');

		o = s.option(form.ListValue, 'schedule', _('Schedule'));
		o.value('off', _('Off -- manual backups only'));
		o.value('hourly', _('Hourly (minute chosen per device)'));
		o.value('daily', _('Daily, once in a randomized night window'));
		o.value('weekly', _('Weekly, once in a randomized night window'));
		o.value('cron', _('Custom cron expression'));
		o.default = 'daily';
		o.description = _('The hourly/daily/weekly presets deliberately do not all fire at the same wall-clock time: the minute (and, for daily/weekly, the hour) is derived from this device\'s own identifier, so a whole fleet of routers on the same preset does not wake up in the same second and hit the provider\'s API all at once.');

		// Validated live by schedule.sh itself (validate_cron), debounced.
		o = s.option(form.Value, 'cron_expr', _('Cron expression'),
			_('Five fields: minute hour day-of-month month day-of-week. Validated live against exactly the grammar busybox crond on this router understands -- it has no "@daily"/"@hourly"/"@reboot" support at all, and silently drops any line shorter than five fields.'));
		o.placeholder = '0 3 * * *';
		o.depends('schedule', 'cron');
		o.renderWidget = function(section_id, option_index, cfgvalue) {
			var node = form.Value.prototype.renderWidget.apply(this, arguments);
			var input = node.querySelector('input');
			var hint = E('div', { 'class': 'gitbackup-hint', 'id': 'gitbackup-cron-hint' }, [ '' ]);
			var timer = null;

			function show(kind, text) {
				hint.className = 'gitbackup-hint' + (kind ? ' gitbackup-hint-' + kind : '');
				hint.textContent = text;
			}

			function revalidate() {
				var expr = input.value;

				if (!expr)
					return show('', '');

				L.resolveDefault(callValidateCron(expr), null).then(function(res) {
					if (input.value !== expr)
						return;
					if (!res)
						show('', '');
					else if (!res.valid)
						show('error', res.reason);
					else
						show('ok', _('Valid.'));
				});
			}

			input.addEventListener('input', function() {
				if (timer)
					clearTimeout(timer);
				timer = setTimeout(revalidate, 300);
			});

			node.appendChild(hint);
			if (cfgvalue)
				setTimeout(revalidate, 0);

			return node;
		};

		s = m.section(form.NamedSection, 'origin', 'remote', _('Remote'));
		s.addremove = false;

		o = s.option(form.Value, 'url', _('Repository URL'),
			_('One of: git@host:owner/repo.git, ssh://[user@]host[:port]/owner/repo.git, or https://host[:port]/owner/repo.git.'));
		o.placeholder = 'git@github.com:owner/repo.git';

		o = s.option(form.Value, 'branch', _('Branch'),
			_('"{device}" is replaced with the resolved device identifier -- the default gives every device its own branch on a shared repository.'));
		o.placeholder = 'device/{device}';
		o.default = 'device/{device}';

		o = s.option(form.ListValue, 'auth', _('Authentication'));
		o.value('sshkey', _('SSH deploy key'));
		o.value('token', _('API token'));
		o.default = 'sshkey';

		o = s.option(form.ListValue, 'provider', _('Provider'),
			_('"Auto" detects github.com/gitlab.com/bitbucket.org/codeberg.org by hostname and treats anything else as generic (self-hosted, unknown API). Set this explicitly if a self-hosted GitLab or Gitea/Forgejo instance should get that provider\'s deploy-key link instead of the generic instructions.'));
		o.value('auto', _('Auto-detect'));
		o.value('github', 'GitHub');
		o.value('gitlab', 'GitLab');
		o.value('gitea', _('Gitea / Forgejo'));
		o.value('bitbucket', 'Bitbucket');
		o.value('generic', _('Generic (self-hosted, unknown API)'));
		o.default = 'auto';

		// Not gated on auth: it exercises whichever credential is configured.
		o = s.option(form.DummyValue, '_test', _('Connection test'));
		o.renderWidget = function() {
			return E('div', {}, [
				E('div', { 'class': 'gitbackup-actions' }, [
					E('button', {
						'class': 'cbi-button cbi-button-neutral',
						'click': ui.createHandlerFn(self, 'handleTestConnection')
					}, [ _('Test connection') ])
				]),
				E('div', { 'id': 'gitbackup-test-result', 'class': 'gitbackup-test-result' }),
				E('div', { 'id': 'gitbackup-hostkey-prompt', 'class': 'gitbackup-box', 'hidden': true }),
				E('pre', { 'class': 'gitbackup-log', 'id': 'gitbackup-test-log', 'hidden': true }, [ '' ])
			]);
		};

		o = s.option(form.DummyValue, '_deploykey', _('Deploy key'));
		o.depends('auth', 'sshkey');
		o.renderWidget = function() {
			return gbBuildDeployKeyBody(self);
		};

		gbDeployHelpOption(s, 'deploylink', _('Add the key to the repository'), false, function(info) {
			return [
				E('p', { 'class': 'gitbackup-warn-text' },
					[ _('Before saving the key on the provider, tick "Allow write access" (or the equivalent) -- without it the key can read the repository but every push fails silently.') ]),
				(info.kind === 'link') ?
					E('div', { 'class': 'gitbackup-actions' }, [
						E('a', {
							'href': info.url,
							'target': '_blank',
							'rel': 'noopener noreferrer',
							'class': 'cbi-button cbi-button-action'
						}, [ _('Open the repository’s deploy-key page') ])
					]) :
					E('p', { 'class': 'gitbackup-hint' },
						[ _('Enter a valid repository URL above to get a direct link to the provider’s deploy-key page.') ])
			];
		});

		gbDeployHelpOption(s, 'deploygeneric', _('Add the key to the server'), true, function(info) {
			var host = (info.kind === 'generic') ? info.host : _('the server');
			var pubkeyText = self._pubkey ? self._pubkey.replace(/\s+$/, '') : 'ssh-ed25519 AAAA... gitbackup';

			return [
				E('p', {},
					[ _('This provider has no API to link to a settings page. On %s, append the public key above to the "git" user’s ~/.ssh/authorized_keys, ideally prefixed with restrict,command="git-shell" so the key can only run git operations, e.g.:').format(host) ]),
				E('pre', { 'class': 'gitbackup-log' },
					[ 'restrict,command="git-shell" ' + pubkeyText ])
			];
		});

		o = s.option(form.Value, 'key_file', _('Deploy key path'));
		o.placeholder = '/etc/gitbackup/id_ed25519';
		o.default = '/etc/gitbackup/id_ed25519';
		o.depends('auth', 'sshkey');

		// Virtual: the secret never comes back to the browser and never goes
		// into UCI -- write() sends it to set_secret; blank changes nothing.
		o = s.option(form.Value, '_token', _('API token'));
		o.password = true;
		o.rmempty = true;
		o.depends('auth', 'token');
		o.placeholder = self._status.token_set ?
			'••••• (configured)' :
			_('paste a token to enable token authentication');
		o.cfgvalue = function() { return null; };
		o.write = function(section_id, formvalue) {
			return callSetSecret(formvalue);
		};
		o.remove = function() { return null; };

		o = s.option(form.Value, 'token_file', _('Token file path'));
		o.placeholder = '/etc/gitbackup/token';
		o.default = '/etc/gitbackup/token';
		o.depends('auth', 'token');

		o = s.option(form.Value, 'ca_file', _('Custom CA certificate path'),
			_('Only needed for an https remote behind a private certificate authority. Leave empty to use the system’s own trust store.'));
		o.optional = true;
		o.depends('auth', 'token');

		o = s.option(form.ListValue, 'visibility', _('Repository visibility'));
		o.value('private', _('Private'));
		o.value('public', _('Public'));
		o.default = 'private';

		o = s.option(form.DummyValue, '_visibility_private', '');
		o.depends('visibility', 'private');
		o.renderWidget = function() {
			return E('div', { 'class': 'gitbackup-box' }, [
				E('p', {}, [ _('The remote is expected to be private. Before every push, this is checked anonymously against the provider’s API (no token needed for the check itself) -- if the repository turns out to be publicly visible, the push is refused outright and a red banner appears on the Overview tab. Config scrubbing stays off unless something else requires it.') ])
			]);
		};

		o = s.option(form.DummyValue, '_visibility_public', '');
		o.depends('visibility', 'public');
		o.renderWidget = function() {
			return E('div', { 'class': 'gitbackup-box' }, [
				E('p', { 'class': 'gitbackup-warn-text' }, [ _('Anyone with the URL will be able to read every backup ever pushed.') ]),
				E('p', {}, [ _('Saving this forces config scrubbing on (Security section below): the following are stripped from every config file before it is committed --') ]),
				E('ul', { 'class': 'gitbackup-leak-list' }, [
					E('li', {}, [ _('every value listed under "Scrub these UCI options" below (Wi-Fi pre-shared keys by default)') ])
				]),
				E('p', {}, [ _('Restoring from a public branch will therefore be incomplete: scrubbed values are gone from the backup entirely and have to be re-entered by hand after a restore, the same way a factory-reset router would need them re-entered.') ])
			]);
		};

		o = s.option(form.Flag, 'acknowledged', _('I accept the risk and confirm this repository is actually private'));
		o.checkDepends = function(section_id) {
			return common.provider(gbFieldValue(this.section, section_id, 'url'),
				gbFieldValue(this.section, section_id, 'provider')) === 'generic';
		};
		o.validate = function(section_id, value) {
			if (!this.checkDepends(section_id) || value === this.enabled)
				return true;
			return _('This provider cannot be checked automatically -- tick the box above to confirm the repository is private before saving.');
		};
		o.renderWidget = function(section_id, option_index, cfgvalue) {
			return E('div', { 'class': 'gitbackup-box' }, [
				E('p', { 'class': 'gitbackup-box-title' },
					[ _('This provider’s visibility cannot be checked automatically (spec: "generic — проверить нельзя ни при каких условиях"). If this repository is actually public, everything below is exposed in plain text to anyone who can read it:') ]),
				common.leakList(),
				form.Flag.prototype.renderWidget.apply(this, arguments)
			]);
		};

		s = m.section(form.NamedSection, 'security', 'security', _('Security'));
		s.addremove = false;

		s.option(form.Flag, 'scrub', _('Scrub secrets before committing'),
			_('Forced on automatically whenever "Repository visibility" above is set to Public -- this checkbox only matters while it is still Private.'));

		o = s.option(form.DynamicList, 'scrub_option', _('Scrub these UCI options'),
			_('UCI paths to blank out before every commit, e.g. "wireless.@wifi-iface[*].key". Applied with uci -c against a scratch copy of the config tree, never touching the router’s own live configuration.'));
		o.placeholder = 'wireless.@wifi-iface[*].key';

		return m.render().then(function(mapEl) {
			mapEl.classList.add('gitbackup-view');
			mapEl.insertBefore(E('style', { 'type': 'text/css' }, [ common.css.concat(GB_CSS).join('\n') ]), mapEl.firstChild);
			return mapEl;
		});
	},

	// Only "Regenerate" destroys a key, so only it needs a confirmation.
	handleGenerateKey: function(force, ev) {
		var self = this;

		if (force)
			return self.showKeygenConfirm();

		self.setKeygenStatus('busy', _('Generating…'));
		return callKeygen().then(function(res) {
			return self.applyKeygenResult(res, false);
		}, function(e) {
			self.setKeygenStatus('error', _('Could not generate a deploy key: %s').format(e.message));
		});
	},

	showKeygenConfirm: function() {
		var self = this;
		var box = document.getElementById('gitbackup-keygen-confirm');
		var fill = function(nodes) {
			box.textContent = '';
			nodes.forEach(function(n) { box.appendChild(n); });
		};

		if (!box)
			return;

		box.hidden = false;
		fill([ E('p', { 'class': 'spinning' }, [ _('Reading the current key’s fingerprint…') ]) ]);

		return callKeygen(true).then(function(res) {
			// ok: the key vanished since page load and a fresh one was made.
			if (res && res.ok === true) {
				self.hideKeygenConfirm();
				return self.applyKeygenResult(res, true);
			}

			if (!res || res.confirm_required !== true || !res.fingerprint) {
				fill([ E('p', { 'class': 'gitbackup-hint-error' },
					[ _('Could not read the current key: %s').format((res && res.reason) || _('unknown error')) ]) ]);
				return;
			}

			self._keygenFingerprint = res.fingerprint;
			fill([
				E('p', { 'class': 'gitbackup-warn-text' },
					[ _('Regenerating destroys this key beyond recovery, and the deploy key already added at your git provider stops working the instant it does. This cannot be undone from here -- after regenerating, add the NEW public key at the provider before the next backup runs.') ]),
				E('p', {}, [ _('Key currently in use (fingerprint):') ]),
				E('pre', { 'class': 'gitbackup-log' }, [ res.fingerprint ]),
				E('div', { 'class': 'gitbackup-actions' }, [
					E('button', {
						'class': 'cbi-button cbi-button-negative',
						'click': ui.createHandlerFn(self, 'handleConfirmRegenerateKey')
					}, [ _('Destroy it and regenerate') ]),
					E('button', {
						'class': 'cbi-button cbi-button-neutral',
						'click': ui.createHandlerFn(self, 'hideKeygenConfirm')
					}, [ _('Cancel') ])
				])
			]);
		}, function(e) {
			fill([ E('p', { 'class': 'gitbackup-hint-error' },
				[ _('Could not read the current key: %s').format(e.message) ]) ]);
		});
	},

	hideKeygenConfirm: function() {
		var box = document.getElementById('gitbackup-keygen-confirm');

		if (box) {
			box.hidden = true;
			box.textContent = '';
		}
		this._keygenFingerprint = null;
	},

	// Sends back exactly the fingerprint shown; anything else is refused.
	handleConfirmRegenerateKey: function(ev) {
		var self = this;
		var fp = self._keygenFingerprint;

		if (!fp)
			return;

		self.setKeygenStatus('busy', _('Regenerating…'));

		return callKeygen(true, fp).then(function(res) {
			self.hideKeygenConfirm();
			return self.applyKeygenResult(res, true);
		}, function(e) {
			self.setKeygenStatus('error', _('Could not generate a deploy key: %s').format(e.message));
		});
	},

	applyKeygenResult: function(res, force) {
		var self = this;

		if (!res || res.ok !== true) {
			self.setKeygenStatus('error', _('Could not generate a deploy key: %s').format((res && res.reason) || _('unknown error')));
			return;
		}

		return L.resolveDefault(callPubkey(), null).then(function(pk) {
			var old = document.getElementById('gitbackup-deploykey-body');

			self._pubkey = (pk && typeof pk.pubkey === 'string') ? pk.pubkey : null;

			if (old && old.parentNode)
				old.parentNode.replaceChild(gbBuildDeployKeyBody(self), old);

			// Set on the freshly rebuilt status line.
			self.setKeygenStatus('ok', force ?
				_('Deploy key regenerated. Add the new public key above at your provider.') :
				_('Deploy key generated.'));
		});
	},

	setKeygenStatus: function(kind, text) {
		var el = document.getElementById('gitbackup-keygen-status');

		if (!el)
			return;

		el.hidden = false;
		el.className = 'gitbackup-hint' + (kind === 'busy' ? ' spinning' : ' gitbackup-hint-' + kind);
		el.textContent = text;
	},

	// "Copied" only on actual success, never on the click.
	handleCopyPubkey: function(ev) {
		var statusEl = document.getElementById('gitbackup-copy-status');
		var container = document.querySelector('.cbi-map') || document.body;

		return gbCopyText(this._pubkey || '', container).then(function(ok) {
			if (statusEl)
				statusEl.textContent = ok ?
					_('Copied.') :
					_('Could not copy automatically -- select the text above and copy it by hand.');
		});
	},

	setTestResult: function(kind, text) {
		var el = document.getElementById('gitbackup-test-result');

		if (!el)
			return;

		el.className = 'gitbackup-test-result' + (kind === 'busy' ? ' spinning' : ' gitbackup-hint-' + kind);
		el.textContent = text;
	},

	handleTestConnection: function(ev) {
		var self = this;

		self.setTestResult('busy', _('Testing…'));
		self.hideHostkeyPrompt();

		return oplog.run({
			call: common.callTest,
			pre: 'gitbackup-test-log',
			terminalRe: GB_TEST_TERMINAL_RE,
			onFinish: function(line) {
				var cls = gbClassifyTestLog(line);

				self.setTestResult(gbTestSeverity(cls.kind), cls.message);
				if (cls.kind === 'hostkey_pending')
					return self.showHostkeyPrompt();
			},
			onTimeout: function() {
				self.setTestResult('warn', _('No result after a while -- check the log below or the syslog by hand.'));
			},
			onFail: function(reason) {
				self.setTestResult('error', reason ?
					_('Could not start a connection test: %s').format(reason) :
					_('Could not start a connection test.'));
			}
		});
	},

	showHostkeyPrompt: function() {
		var self = this;
		var wrap = document.getElementById('gitbackup-hostkey-prompt');

		if (!wrap)
			return;

		wrap.hidden = false;
		wrap.textContent = '';
		wrap.appendChild(E('p', { 'class': 'spinning' }, [ _('Fetching the remote’s SSH host key…') ]));

		return callHostkey().then(function(res) {
			wrap.textContent = '';

			// Already trusted by now (another tab, an earlier test).
			if (!res || res.trusted === true) {
				wrap.hidden = true;
				return;
			}

			if (!res.fingerprint) {
				wrap.appendChild(E('p', { 'class': 'gitbackup-hint-error' },
					[ _('Could not obtain the host key: %s').format(res.reason || _('unknown error')) ]));
				return;
			}

			self._hostkeyFingerprint = res.fingerprint;
			wrap.appendChild(E('p', {}, [ _('The remote presented this SSH host key fingerprint. Verify it out of band if you can, then accept it once to continue -- this only has to be done the first time.') ]));
			wrap.appendChild(E('pre', { 'class': 'gitbackup-log' }, [ res.fingerprint ]));
			wrap.appendChild(E('div', { 'class': 'gitbackup-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-positive',
					'click': ui.createHandlerFn(self, 'handleAcceptHostkey')
				}, [ _('Accept and remember this host key') ]),
				E('span', { 'class': 'gitbackup-hint', 'id': 'gitbackup-hostkey-accept-status' }, [ '' ])
			]));
		}, function(e) {
			wrap.textContent = '';
			wrap.appendChild(E('p', { 'class': 'gitbackup-hint-error' },
				[ _('Could not obtain the host key: %s').format(e.message) ]));
		});
	},

	hideHostkeyPrompt: function() {
		var wrap = document.getElementById('gitbackup-hostkey-prompt');

		if (wrap) {
			wrap.hidden = true;
			wrap.textContent = '';
		}
	},

	// Sends back exactly the fingerprint shown; anything else is refused.
	handleAcceptHostkey: function(ev) {
		var self = this;
		var fp = self._hostkeyFingerprint;
		var statusEl = document.getElementById('gitbackup-hostkey-accept-status');
		var fail = function(reason) {
			if (statusEl) {
				statusEl.className = 'gitbackup-hint gitbackup-hint-error';
				statusEl.textContent = _('Could not accept the host key: %s').format(reason);
			}
		};

		if (!fp)
			return;

		return callHostkey(fp).then(function(res) {
			if (!res || res.ok !== true)
				return fail((res && res.reason) || _('unknown error'));

			self.hideHostkeyPrompt();
			self.setTestResult('ok', _('Host key accepted. Click “Test connection” again to verify the rest.'));
		}, function(e) {
			fail(e.message);
		});
	}
});
