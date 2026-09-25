'use strict';
'require view';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view.gitbackup.common as common';
'require view.gitbackup.oplog as oplog';
/* global common, oplog */
// openwrt/luci's eslint config only knows stock module names as globals.

var callConfigDiff = rpc.declare({
	object: 'luci.gitbackup',
	method: 'config_diff'
});

var callRun = rpc.declare({
	object: 'luci.gitbackup',
	method: 'run'
});

var callCard = rpc.declare({
	object: 'luci.gitbackup',
	method: 'card'
});

// procd's stock object: {"cron":{"instances":{...running:true}}} while crond
// is up, a bare {} once it is stopped.
var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ]
});

function gbClassifyLog(text) {
	var lines = (text || '').split('\n');
	var i, line;

	for (i = lines.length - 1; i >= 0; i--) {
		line = lines[i];
		if (!line)
			continue;

		if (line.indexOf('publicly visible to an anonymous request') !== -1)
			return {
				kind: 'blocked_public',
				synced: null,
				message: _('Blocked: the repository is publicly visible to an anonymous request; the last push was refused.')
			};

		if (/pushed [0-9a-f]+ to /.test(line))
			return {
				kind: 'pushed',
				synced: true,
				message: _('Pushed a new commit on the last run.')
			};

		if (line.indexOf('no changes since the last backup') !== -1)
			return {
				kind: 'no_changes',
				synced: true,
				message: _('No changes since the last commit.')
			};

		if (line.indexOf('another run already holds the lock') !== -1)
			return {
				kind: 'skipped_lock',
				synced: null,
				message: _('Skipped: another run was already in progress.')
			};

		if (/unreachable, skipped/.test(line))
			return {
				kind: 'skipped_network',
				synced: null,
				message: _('Skipped: the remote was unreachable.')
			};

		if (line.indexOf('could not verify whether') !== -1 && line.indexOf('is public') !== -1)
			return {
				kind: 'skipped_visibility',
				synced: null,
				message: _('Skipped: could not verify whether the repository is public.')
			};

		if (line.indexOf('not enough space') !== -1)
			return {
				kind: 'error_space',
				synced: null,
				message: _('Failed: not enough free space under /tmp to build the backup set.')
			};

		if (line.indexOf('reachable and authenticated') !== -1)
			return {
				kind: 'test_ok',
				synced: null,
				message: _('Connection test succeeded.')
			};
	}

	return { kind: 'unknown', synced: null, message: _('No completed run recorded yet.') };
}

// Checked against tests/fixtures/terminal-markers.tsv.
var GB_LOG_TERMINAL_RE = new RegExp(
	[
		'pushed [0-9a-f]+ to ',
		'no changes since the last backup',
		'another run already holds the lock',
		'unreachable, skipped',
		'could not verify whether .* is public',
		'not enough space',
		'publicly visible to an anonymous request',
		'reachable and authenticated'
	].join('|')
);

function gbOutcomeKind(cls) {
	if (cls.kind === 'unknown')
		return 'none';
	if (cls.synced === true || cls.kind === 'test_ok')
		return 'ok';
	if (cls.kind === 'blocked_public' || cls.kind === 'error_space')
		return 'error';
	return 'warn';
}

function gbMissingText(key) {
	switch (key) {
	case 'device_id':
		return _('Device identifier could not be resolved (hostname is still the default "OpenWrt", or a custom device name is empty). Set it on the Settings tab.');
	case 'cron_expr':
		return _('Schedule is set to a custom cron expression, but it is not a valid 5-field busybox crontab line. Fix it on the Settings tab.');
	case 'url':
		return _('Repository URL is not set. Set it on the Settings tab.');
	default:
		return key;
	}
}

function gbScheduleText(schedule, cronExpr) {
	switch (schedule) {
	case 'off':
		return _('Disabled');
	case 'hourly':
		return _('Hourly (minute chosen per device to avoid a fleet-wide stampede)');
	case 'daily':
		return _('Daily, once in a randomized night window (00:00-05:59), per device');
	case 'weekly':
		return _('Weekly, once in a randomized night window, per device');
	case 'cron':
		return _('Custom cron: %s').format(cronExpr || '-');
	default:
		return schedule || '-';
	}
}

function gbFormatDate(iso) {
	var d;

	if (!iso)
		return _('never');

	d = new Date(iso);
	return isNaN(d.getTime()) ? iso : d.toLocaleString();
}

// View models are plain data: render() builds the first paint from them
// (its tree is not attached to document yet), the apply*Dom methods push
// later poll results into the live DOM by id.
function gbStatusView(status, logRes, serviceRes, schedule, cronExpr) {
	var cls = gbClassifyLog((logRes && logRes.text) || '');
	var banners = [];
	var cronRunning = false;
	var k;

	if (!status.configured && status.missing && status.missing.length)
		banners.push(_('Configuration is incomplete:') + ' ' + status.missing.map(gbMissingText).join(' '));

	if (serviceRes && serviceRes.cron && serviceRes.cron.instances) {
		for (k in serviceRes.cron.instances) {
			if (serviceRes.cron.instances[k] && serviceRes.cron.instances[k].running)
				cronRunning = true;
		}
	}
	if (!cronRunning && schedule !== 'off')
		banners.push(_('The cron service (crond) does not appear to be running -- scheduled backups will not happen until it does. Run "/etc/init.d/cron start" or check the System > Startup page.'));

	if (cls.kind === 'blocked_public')
		banners.push(cls.message);

	return {
		enabledText: status.enabled ? _('Enabled') : _('Disabled'),
		scheduleText: gbScheduleText(schedule, cronExpr),
		resultText: cls.message,
		resultDotClass: 'gitbackup-dot gitbackup-dot-' + gbOutcomeKind(cls),
		resultHint: status.last_run ?
			_('Last completed run: %s').format(gbFormatDate(status.last_run)) :
			_('This device has not completed a run yet.'),
		banners: banners
	};
}

function gbHistoryView(historyRes, remoteUrl, provider) {
	var commit = (historyRes && historyRes.commits && historyRes.commits[0]) || null;

	if (!commit)
		return { shaText: _('No commits yet'), shaHref: null, timeText: '-' };

	return {
		shaText: commit.sha.substring(0, 12),
		shaHref: common.commitUrl(remoteUrl, provider, commit.sha),
		timeText: common.commitTime(commit.subject) || commit.subject || '-'
	};
}

// A failed or missing answer must read as "could not check", never "all saved".
function gbConfigDiffView(res) {
	if (!res || typeof res.differs !== 'boolean')
		return {
			text: (res && res.reason) ?
				_('Could not check: %s').format(res.reason) :
				_('Could not check whether the configuration has changed.'),
			kind: 'warn'
		};

	if (res.differs)
		return { text: _('The configuration has changed since the last commit.'), kind: 'warn' };

	return { text: _('The configuration matches the last commit.'), kind: 'ok' };
}

function gbRenderBanner(text) {
	return E('div', { 'class': 'alert-message error' }, [ E('p', {}, [ text ]) ]);
}

// @container, not @media: the sidebar eats width a media query cannot see.
var GB_CSS = [
	'.gitbackup-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .75em; margin: .75em 0; }',
	'@container (max-width: 700px) { .gitbackup-cards { grid-template-columns: 1fr; } }',
	'.gitbackup-card { border: 1px solid var(--background-color-medium, #ddd); border-radius: 4px; padding: .75em 1em; background: var(--background-color-low, #f5f5f5); }',
	// The "Configuration" card is a <button>: undo the browser's chrome.
	'button.gitbackup-card { display: block; width: 100%; text-align: left; font: inherit; color: inherit; cursor: pointer; }',
	'button.gitbackup-card:hover, button.gitbackup-card:focus-visible { border-color: var(--text-color-medium, #666); }',
	'.gitbackup-card-title { font-size: .85em; text-transform: uppercase; letter-spacing: .04em; color: var(--text-color-medium, #666); margin: 0 0 .35em; }',
	'.gitbackup-card-value { font-size: 1.05em; color: var(--text-color-high, #333); word-break: break-word; }',
	'.gitbackup-card .gitbackup-card-hint { margin-top: .35em; }',
	'.gitbackup-op-status { font-weight: bold; }',
	'.gitbackup-link { color: var(--text-color-high, #333); }',
	'.gitbackup-leak { border: 1px solid var(--warn-color-medium, #f0c629); border-radius: 4px; padding: .75em 1em; margin: .75em 0; background: var(--background-color-low, #f5f5f5); }',
	'.gitbackup-leak-title { font-weight: bold; color: var(--text-color-high, #333); margin: 0 0 .4em; }',
	'.gitbackup-dot { display: inline-block; width: .6em; height: .6em; border-radius: 50%; margin-right: .4em; background: var(--text-color-medium, #999); }',
	'.gitbackup-dot-ok { background: var(--success-color-medium, #4caf50); }',
	'.gitbackup-dot-warn { background: var(--warn-color-medium, #f0c629); }',
	'.gitbackup-dot-error { background: var(--error-color-medium, #f44336); }'
];

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		var self = this;

		return uci.load('gitbackup').catch(function() { return null; }).then(function() {
			self._remoteUrl = uci.get('gitbackup', 'origin', 'url') || '';
			self._provider = uci.get('gitbackup', 'origin', 'provider') || 'auto';
			self._schedule = uci.get('gitbackup', 'main', 'schedule') || 'daily';
			self._cronExpr = uci.get('gitbackup', 'main', 'cron_expr') || '';

			// history and config_diff talk to the remote and can hang on a
			// dead network; render() starts them after the first paint.
			return self.fetchStatus();
		});
	},

	render: function(data) {
		var self = this;
		var sv = self.statusView(data);
		var view;

		view = E('div', { 'class': 'gitbackup-view' }, [
			E('style', { 'type': 'text/css' }, [ common.css.concat(GB_CSS).join('\n') ]),

			E('h2', {}, [ _('Git Backup') ]),

			E('div', { 'id': 'gitbackup-banners' }, sv.banners.map(gbRenderBanner)),

			E('div', { 'class': 'gitbackup-cards' }, [
				E('div', { 'class': 'gitbackup-card' }, [
					E('div', { 'class': 'gitbackup-card-title' }, [ _('Status') ]),
					E('div', { 'class': 'gitbackup-card-value', 'id': 'gitbackup-status-enabled' }, [ sv.enabledText ]),
					E('div', { 'class': 'gitbackup-card-hint', 'id': 'gitbackup-status-schedule' }, [ sv.scheduleText ])
				]),
				E('div', { 'class': 'gitbackup-card' }, [
					E('div', { 'class': 'gitbackup-card-title' }, [ _('Last commit') ]),
					E('div', { 'class': 'gitbackup-card-value', 'id': 'gitbackup-commit-sha' }, [ _('Checking…') ]),
					E('div', { 'class': 'gitbackup-card-hint', 'id': 'gitbackup-commit-time' }, [ '-' ])
				]),
				E('div', { 'class': 'gitbackup-card' }, [
					E('div', { 'class': 'gitbackup-card-title' }, [ _('Last run') ]),
					E('div', { 'class': 'gitbackup-card-value', 'id': 'gitbackup-run-result' }, [
						E('span', { 'class': sv.resultDotClass, 'id': 'gitbackup-run-dot' }),
						E('span', { 'id': 'gitbackup-run-text' }, [ sv.resultText ])
					]),
					E('div', { 'class': 'gitbackup-card-hint', 'id': 'gitbackup-run-hint' }, [ sv.resultHint ])
				]),
				E('button', {
					'class': 'gitbackup-card',
					'id': 'gitbackup-configdiff-card',
					'click': ui.createHandlerFn(self, 'handleShowConfigDiff')
				}, [
					E('div', { 'class': 'gitbackup-card-title' }, [ _('Configuration') ]),
					E('div', { 'class': 'gitbackup-card-value', 'id': 'gitbackup-configdiff-result' }, [
						E('span', { 'class': 'gitbackup-dot', 'id': 'gitbackup-configdiff-dot' }),
						E('span', { 'id': 'gitbackup-configdiff-text' }, [ _('Checking…') ])
					]),
					E('div', { 'class': 'gitbackup-card-hint' },
						[ _('Compared against the last commit right now, not just the last run. Click to view the diff.') ])
				])
			]),

			E('div', { 'class': 'gitbackup-leak' }, [
				E('p', { 'class': 'gitbackup-leak-title' },
					[ _('The following ends up in the repository in plain text -- there is no encryption in this tool:') ]),
				common.leakList()
			]),

			E('div', { 'class': 'gitbackup-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'id': 'gitbackup-btn-run',
					'click': ui.createHandlerFn(self, 'handleRun')
				}, [ _('Backup now') ]),
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'id': 'gitbackup-btn-test',
					'click': ui.createHandlerFn(self, 'handleTest')
				}, [ _('Test connection') ]),
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'id': 'gitbackup-btn-card',
					'click': ui.createHandlerFn(self, 'handleDownloadCard')
				}, [ _('Download recovery card') ])
			]),

			E('p', { 'class': 'gitbackup-op-status', 'id': 'gitbackup-op-status', 'hidden': true }),

			E('pre', { 'class': 'gitbackup-log', 'id': 'gitbackup-live-log', 'hidden': true }, [ '' ])
		]);

		// history and config_diff hit the remote: refreshed once here and
		// after an operation, never polled.
		poll.add(L.bind(self.refreshStatus, self), 5);
		self.refreshHistory();
		self.refreshConfigDiff();

		return view;
	},

	fetchStatus: function() {
		return Promise.all([
			L.resolveDefault(common.callStatus(), null),
			L.resolveDefault(oplog.callLog(200), null),
			L.resolveDefault(callServiceList('cron'), null)
		]);
	},

	statusView: function(data) {
		return gbStatusView(data[0] || {}, data[1] || {}, data[2] || {}, this._schedule, this._cronExpr);
	},

	refreshStatus: function() {
		var self = this;

		return self.fetchStatus().then(function(data) {
			self.applyStatusDom(self.statusView(data));
		});
	},

	refreshHistory: function() {
		var self = this;

		return L.resolveDefault(common.callHistory(1), null).then(function(res) {
			self.applyHistoryDom(gbHistoryView(res || {}, self._remoteUrl, self._provider));
		});
	},

	refreshConfigDiff: function() {
		var self = this;

		return L.resolveDefault(callConfigDiff(), null).then(function(res) {
			// Cached so the diff modal can paint at once while it re-fetches.
			self._configDiffRes = res;
			self.applyConfigDiffDom(gbConfigDiffView(res));
		});
	},

	applyStatusDom: function(sv) {
		var set = function(id, text) {
			var el = document.getElementById(id);
			if (el)
				el.textContent = text;
		};
		var dot = document.getElementById('gitbackup-run-dot');
		var bannerBox = document.getElementById('gitbackup-banners');

		set('gitbackup-status-enabled', sv.enabledText);
		set('gitbackup-status-schedule', sv.scheduleText);
		set('gitbackup-run-text', sv.resultText);
		set('gitbackup-run-hint', sv.resultHint);

		if (dot)
			dot.className = sv.resultDotClass;

		if (bannerBox) {
			bannerBox.textContent = '';
			sv.banners.forEach(function(b) { bannerBox.appendChild(gbRenderBanner(b)); });
		}
	},

	applyHistoryDom: function(hv) {
		var shaEl = document.getElementById('gitbackup-commit-sha');
		var timeEl = document.getElementById('gitbackup-commit-time');

		if (!shaEl || !timeEl)
			return;

		shaEl.textContent = '';
		shaEl.appendChild(hv.shaHref ? E('a', {
			'href': hv.shaHref,
			'target': '_blank',
			'rel': 'noopener noreferrer',
			'class': 'gitbackup-link'
		}, [ hv.shaText ]) : document.createTextNode(hv.shaText));

		timeEl.textContent = hv.timeText;
	},

	applyConfigDiffDom: function(cv) {
		var textEl = document.getElementById('gitbackup-configdiff-text');
		var dotEl = document.getElementById('gitbackup-configdiff-dot');

		if (textEl)
			textEl.textContent = cv.text;

		if (dotEl)
			dotEl.className = 'gitbackup-dot gitbackup-dot-' + cv.kind;
	},

	setBusy: function(busy) {
		[ 'gitbackup-btn-run', 'gitbackup-btn-test', 'gitbackup-btn-card' ].forEach(function(id) {
			var btn = document.getElementById(id);
			if (btn)
				btn.disabled = busy;
		});
	},

	setOpStatus: function(kind, text) {
		var el = document.getElementById('gitbackup-op-status');

		if (!el)
			return;

		el.hidden = false;
		el.className = 'gitbackup-op-status' + (kind === 'busy' ? ' spinning' : ' gitbackup-hint-' + kind);
		el.textContent = text;
	},

	startOp: function(call, busyText, failTexts, afterFinish) {
		var self = this;
		var done = function(kind, text) {
			self.setBusy(false);
			self.setOpStatus(kind, text);
			self.refreshStatus();
		};

		self.setBusy(true);
		self.setOpStatus('busy', busyText);

		return oplog.run({
			call: call,
			pre: 'gitbackup-live-log',
			terminalRe: GB_LOG_TERMINAL_RE,
			onFinish: function(line) {
				var cls = gbClassifyLog(line);
				done(gbOutcomeKind(cls), cls.message);
				if (afterFinish)
					afterFinish();
			},
			onTimeout: function() {
				done('warn', _('No result after a while -- check the log below or the syslog by hand.'));
			},
			onFail: function(reason) {
				done('error', reason ? failTexts[1].format(reason) : failTexts[0]);
			}
		});
	},

	handleRun: function(ev) {
		var self = this;

		return self.startOp(callRun, _('Running a backup…'), [
			_('Could not start a backup run.'), _('Could not start a backup run: %s')
		], function() {
			self.refreshHistory();
			self.refreshConfigDiff();
		});
	},

	handleTest: function(ev) {
		return this.startOp(common.callTest, _('Testing the connection…'), [
			_('Could not start a connection test.'), _('Could not start a connection test: %s')
		]);
	},

	// Always re-fetches: this is where the operator asked for the current truth.
	handleShowConfigDiff: function(ev) {
		var self = this;

		ui.showModal(_('Configuration diff'), [
			E('p', { 'class': 'spinning' }, [ _('Checking the current configuration against the last commit…') ])
		]);

		if (self._configDiffRes)
			self.renderConfigDiffModal(self._configDiffRes);

		return L.resolveDefault(callConfigDiff(), null).then(function(res) {
			self._configDiffRes = res;
			self.applyConfigDiffDom(gbConfigDiffView(res));
			self.renderConfigDiffModal(res);
		});
	},

	renderConfigDiffModal: function(res) {
		var cv = gbConfigDiffView(res);

		ui.showModal(_('Configuration diff'), [
			(res && res.differs === true) ?
				common.manifest(res.text) :
				E('p', { 'class': 'gitbackup-hint-' + (cv.kind === 'ok' ? 'ok' : 'error') }, [ cv.text ]),
			common.modalButtons()
		]);
	},

	handleDownloadCard: function(ev) {
		return callCard().then(function(res) {
			var link;

			if (!res || typeof res.card !== 'string') {
				ui.addNotification(null, E('p', {},
					[ _('Could not generate the recovery card: %s').format((res && res.reason) || _('unknown error')) ]), 'error');
				return;
			}

			link = document.createElement('a');
			link.href = window.URL.createObjectURL(new Blob([ res.card ], { type: 'text/markdown' }));
			link.download = 'gitbackup-RECOVERY.md';
			link.click();
			window.URL.revokeObjectURL(link.href);
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, [ _('Could not generate the recovery card: %s').format(e.message) ]), 'error');
		});
	}
});
