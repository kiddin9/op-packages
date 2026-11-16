// SPDX-License-Identifier: GPL-3.0-only
//
// The LuCI page of the dae engine. The doona panel drives dae over its native
// HTTP API and is served by dae itself from /usr/share/doona, so this page
// does not frame it: it shows the state of the service, the address the panel
// lives at and the secret the panel asks for, opens the panel in its own tab,
// and drives the manual geo data update.

'use strict';
'require poll';
'require view';
'require view.dae.rpc as dae';

function el(tag, className, children) {
	return E(tag, className ? { 'class': className } : {}, children);
}

function button(label, className, onClick) {
	const node = E('button', { 'class': className, 'type': 'button' }, label);
	if (onClick)
		node.addEventListener('click', onClick);
	return node;
}

function note(text, hidden) {
	const attrs = { 'class': 'dae-note' };
	// E() turns every attribute into setAttribute, and "hidden=false" is still
	// a hidden element: only add the attribute when it is wanted.
	if (hidden)
		attrs.hidden = '';
	return E('p', attrs, text);
}

function formatBytes(bytes) {
	const value = Number(bytes);
	if (!value)
		return '—';

	const units = [ 'B', 'KB', 'MB', 'GB' ];
	let index = 0;
	let size = value;
	while (size >= 1024 && index < units.length - 1) {
		size = size / 1024;
		index++;
	}

	return (index === 0 ? String(size) : size.toFixed(1)) + ' ' + units[index];
}

function formatTime(seconds) {
	const value = Number(seconds);
	return value ? new Date(value * 1000).toLocaleString() : '—';
}

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			dae.status(),
			dae.geoStatus().catch(function() { return null; })
		]).then(function(results) {
			return { status: results[0], geo: results[1] };
		}).catch(function(error) {
			return { error: error.message || String(error) };
		});
	},

	render: function(data) {
		dae.installStyles();

		const page = E('div', { 'class': 'cbi-map dae-page' });
		const message = el('p', 'dae-status-msg', '');
		message.setAttribute('role', 'status');

		const ui = {};
		const statusCard = el('section', 'dae-card');
		const secretCard = el('section', 'dae-card');
		const geoCard = el('section', 'dae-card');
		let statusData = data.status || null;
		let geoData = data.geo || null;
		let busy = false;
		let geoBusy = false;

		// The tabs are two panes of one view rather than two menu entries: the
		// geo update belongs to the same service as the panel link.
		const tabService = button(_('Service'), 'dae-tab dae-tab--active');
		const tabGeo = button(_('Geo data'), 'dae-tab');
		const paneService = E('div', { 'role': 'tabpanel' });
		const paneGeo = E('div', { 'role': 'tabpanel', 'hidden': true });

		function selectTab(name) {
			const geo = name === 'geo';

			tabService.classList.toggle('dae-tab--active', !geo);
			tabGeo.classList.toggle('dae-tab--active', geo);
			tabService.setAttribute('aria-selected', String(!geo));
			tabGeo.setAttribute('aria-selected', String(geo));
			paneService.hidden = geo;
			paneGeo.hidden = !geo;

			if (geo)
				refreshGeo();
		}

		tabService.addEventListener('click', function() { selectTab('service'); });
		tabGeo.addEventListener('click', function() { selectTab('geo'); });

		// ---- service tab ----------------------------------------------------

		ui.badge = el('span', 'dae-badge dae-badge--stop', _('Disabled'));
		// Autostart is a separate fact from the UCI enabled bit: the Startup
		// page disables it by removing the rc.d link.
		ui.bootBadge = el('span', 'dae-badge dae-badge--boot', _('Autostart'));
		ui.openPanel = E('a', {
			'class': 'cbi-button cbi-button-action',
			'target': '_blank',
			'rel': 'noopener noreferrer'
		}, _('Open panel'));
		ui.toggle = button(_('Start'), 'cbi-button cbi-button-action', function() {
			runAction(ui.toggle.getAttribute('data-action'));
		});
		ui.toggle.setAttribute('data-action', 'start');
		ui.restart = button(_('Restart'), 'cbi-button', function() { runAction('restart'); });
		ui.listenInput = E('input', {
			'class': 'cbi-input-text dae-listen-input',
			'type': 'text',
			'inputmode': 'url',
			'spellcheck': 'false',
			'autocomplete': 'off',
			'placeholder': 'http://192.168.1.1:9527/ui/',
			'aria-label': _('Panel address')
		});
		ui.listenApply = button(_('Confirm listener'), 'cbi-button', runListenSave);
		ui.listenHint = note(_('The address the panel is opened at. Saving restarts the service immediately.'));

		ui.reason = note('');

		statusCard.appendChild(el('div', 'dae-card-head', [
			el('div', 'dae-card-head-main', [
				el('h3', 'dae-card-title', _('Status')),
				ui.badge,
				ui.bootBadge
			]),
			el('div', 'dae-actions', [ ui.openPanel, ui.toggle, ui.restart ])
		]));
		statusCard.appendChild(el('div', 'dae-listen', [
			el('span', 'dae-meta-label', _('Panel address')),
			el('div', 'dae-listen-row', [ ui.listenInput, ui.listenApply ]),
			ui.listenHint
		]));
		statusCard.appendChild(ui.reason);

		// dae refuses every configuration write unless its `api` section turns
		// them on, and then the whole doona configuration page is read-only.
		// The switch lives in UCI and is written into the api section by the
		// init script, so this is the one place an operator can flip it.
		ui.writeState = el('span', 'dae-write-state', '—');
		ui.writeNote = el('p', 'dae-note',
			_('Configuration, nodes, groups and rules can only be edited in the panel while writes are on.'));
		ui.writeToggle = button(_('Allow panel writes'), 'cbi-button', runWriteToggle);
		statusCard.appendChild(el('div', 'dae-write', [
			el('div', 'dae-write-text', [
				el('span', 'dae-meta-label', _('Panel writes')),
				ui.writeState,
				ui.writeNote
			]),
			ui.writeToggle
		]));

		ui.secretValue = el('code', 'dae-secret', _('Loading…'));
		ui.secretShow = button(_('Show'), 'cbi-button');
		ui.secretCopy = button(_('Copy'), 'cbi-button');
		ui.secretCopy.disabled = true;

		secretCard.appendChild(el('h3', 'dae-card-title', _('API secret')));
		secretCard.appendChild(el('div', 'dae-secret-row', [
			ui.secretValue, ui.secretShow, ui.secretCopy
		]));
		secretCard.appendChild(note(
			_('The panel asks for this secret the first time it is opened. It is also readable with: uci get dae.main.api_secret')));

		ui.errorAlert = el('div', 'alert-message', _('Could not read the dae service state.'));
		ui.errorAlert.hidden = true;
		ui.errorNote = note(_('If luci-app-dae was installed just now, restart rpcd so that its backend is registered.'), true);

		paneService.appendChild(ui.errorAlert);
		paneService.appendChild(ui.errorNote);
		paneService.appendChild(statusCard);
		paneService.appendChild(secretCard);

		// ---- geo tab --------------------------------------------------------

		function geoRow(name) {
			const size = el('td', '', '—');
			const modified = el('td', '', '—');
			return {
				row: el('tr', '', [ el('td', '', name), size, modified ]),
				size: size,
				modified: modified
			};
		}

		ui.geoRows = [ geoRow('geoip.dat'), geoRow('geosite.dat') ];
		ui.geoLast = note(_('Never updated.'));
		ui.geoLog = E('pre', { 'class': 'dae-log' }, '');
		ui.geoError = el('div', 'alert-message', _('Could not read the geo data state.'));
		ui.geoError.hidden = true;
		ui.geoUpdate = button(_('Update now'), 'cbi-button cbi-button-action', runGeoUpdate);

		geoCard.appendChild(el('div', 'dae-card-head', [
			el('div', 'dae-card-head-main', [ el('h3', 'dae-card-title', _('Geo data')) ]),
			el('div', 'dae-actions', [ ui.geoUpdate ])
		]));
		geoCard.appendChild(note(
			_('The geoip.dat and geosite.dat files back the geoip: and geosite: rules. dae reads them when it starts, so it is restarted after an update.')));
		geoCard.appendChild(E('table', { 'class': 'dae-geo-table' }, [
			E('thead', {}, E('tr', {}, [
				el('th', '', _('File')), el('th', '', _('Size')), el('th', '', _('Modified'))
			])),
			el('tbody', '', ui.geoRows.map(function(row) { return row.row; }))
		]));
		geoCard.appendChild(ui.geoLast);
		geoCard.appendChild(ui.geoLog);

		paneGeo.appendChild(ui.geoError);
		paneGeo.appendChild(geoCard);

		// ---- rendering ------------------------------------------------------

		function updateStatus(status, error) {
			const unreadable = !!error || !status || typeof status !== 'object' ||
				typeof status.listen !== 'string';

			ui.errorAlert.hidden = !unreadable;
			ui.errorNote.hidden = !unreadable;
			statusCard.hidden = unreadable;
			secretCard.hidden = unreadable;

			if (unreadable)
				return;

			statusData = status;

			const running = status.running === true;
			const enabled = status.enabled === true;

			ui.badge.className = 'dae-badge ' + (running
				? 'dae-badge--run'
				: (enabled ? 'dae-badge--idle' : 'dae-badge--stop'));
			ui.badge.textContent = running ? _('Running') : (enabled ? _('Stopped') : _('Disabled'));

			if (status.boot_enabled === true || status.boot_enabled === false) {
				const boot = status.boot_enabled === true;

				ui.bootBadge.hidden = false;
				ui.bootBadge.className = 'dae-badge ' + (boot ? 'dae-badge--boot' : 'dae-badge--boot-off');
				ui.bootBadge.textContent = boot ? _('Autostart') : _('No autostart');
			}
			else {
				// A backend that predates the field cannot tell; do not claim
				// either state.
				ui.bootBadge.hidden = true;
			}

			if (document.activeElement !== ui.listenInput)
				ui.listenInput.value = dae.panelAddress(status);
			ui.listenInput.disabled = busy;
			ui.listenApply.disabled = busy;

			const write = dae.writeEnabled(status);
			ui.writeState.textContent = write
				? _('On — the panel can change the configuration, nodes and groups.')
				: _('Off — the panel can only read the configuration.');
			ui.writeState.className = 'dae-write-state ' + (write ? 'dae-write-state--on' : 'dae-write-state--off');
			ui.writeToggle.textContent = write ? _('Stop panel writes') : _('Allow panel writes');
			// The value is read by dae only when it starts, and a stopped
			// service has nothing to restart into.
			ui.writeToggle.disabled = busy || !running;

			const url = dae.panelUrl(status);
			if (running && url) {
				ui.openPanel.setAttribute('href', url);
				ui.openPanel.setAttribute('target', '_blank');
				ui.openPanel.setAttribute('rel', 'noopener noreferrer');
				ui.openPanel.removeAttribute('aria-disabled');
				ui.openPanel.classList.remove('dae-disabled');
			}
			else {
				// The panel is served by dae itself; a stopped daemon has no
				// page to open, so the link must not look usable.
				ui.openPanel.removeAttribute('href');
				ui.openPanel.setAttribute('aria-disabled', 'true');
				ui.openPanel.classList.add('dae-disabled');
			}

			ui.toggle.textContent = running ? _('Stop') : _('Start');
			ui.toggle.setAttribute('data-action', running ? 'stop' : 'start');
			// Starting is what turns a disabled service on: the backend sets
			// enabled=1 and creates the boot links before it starts the daemon.
			ui.toggle.disabled = busy || (running && !enabled);
			ui.restart.disabled = busy || !running;
			ui.restart.hidden = !running;

			const reason = dae.panelReason(status) || '';
			ui.reason.textContent = reason;
			ui.reason.hidden = !reason;
		}

		function updateGeo(geo) {
			geoData = geo || null;

			if (!geo) {
				ui.geoError.hidden = false;
				geoCard.hidden = true;
				return;
			}

			ui.geoError.hidden = true;
			geoCard.hidden = false;

			const files = Array.isArray(geo.files) ? geo.files : [];
			ui.geoRows.forEach(function(row, index) {
				const file = files[index] || {};

				if (file.present) {
					row.size.textContent = formatBytes(file.size);
					row.modified.textContent = formatTime(file.modified);
				}
				else {
					row.size.textContent = _('Not installed');
					row.modified.textContent = '—';
				}
			});

			const state = geo.state || 'idle';
			if (state === 'running') {
				ui.geoLast.textContent = _('Updating…');
			}
			else if (state === 'ok' || state === 'failed') {
				const text = geo.message
					? dae.statusIssue(geo.message)
					: (state === 'ok' ? _('The update completed.') : _('The update failed.'));
				ui.geoLast.textContent = (geo.finished ? formatTime(geo.finished) + ' · ' : '') + text;
			}
			else {
				ui.geoLast.textContent = _('Never updated.');
			}

			ui.geoUpdate.disabled = geoBusy || state === 'running';
			ui.geoUpdate.textContent = state === 'running' ? _('Updating…') : _('Update now');

			const log = Array.isArray(geo.log) ? geo.log.join('\n') : (geo.log || '');
			ui.geoLog.textContent = log;
			ui.geoLog.hidden = !log;
		}

		// ---- actions --------------------------------------------------------

		function runAction(action) {
			if (busy)
				return;

			busy = true;
			message.textContent = _('Working…');
			updateStatus(statusData, null);

			dae[action]().then(dae.ensureOk).then(function(result) {
				message.textContent = dae.resultMessage(result, _('The operation completed.'));
			}).catch(function(error) {
				message.textContent = dae.errorMessage(error, _('The operation failed.'));
			}).finally(function() {
				busy = false;
				refreshStatus();
			});
		}

		// Saving the listener restarts dae too: the address is bound at startup,
		// and the backend rolls back to the previous one when the new bind fails.
		function runListenSave() {
			if (busy)
				return;

			const value = ui.listenInput.value.trim();
			if (!value) {
				message.textContent = _('Enter the panel address.');
				return;
			}

			busy = true;
			message.textContent = _('Working…');
			updateStatus(statusData, null);

			dae.setListen(value).then(dae.ensureOk).then(function(result) {
				message.textContent = dae.resultMessage(result, _('The listener was saved.'));
			}).catch(function(error) {
				message.textContent = dae.errorMessage(error, _('The listener was not saved.'));
			}).finally(function() {
				busy = false;
				refreshStatus();
			});
		}

		// Turning writes on restarts dae: the api section is read at startup
		// only, and the init script writes the switch into it then.
		function runWriteToggle() {
			if (busy)
				return;

			const target = !dae.writeEnabled(statusData);

			busy = true;
			message.textContent = _('Working…');
			updateStatus(statusData, null);

			dae.setWrite(target).then(dae.ensureOk).then(function(result) {
				message.textContent = dae.resultMessage(result, _('The operation completed.'));
			}).catch(function(error) {
				message.textContent = dae.errorMessage(error, _('The operation failed.'));
			}).finally(function() {
				busy = false;
				refreshStatus();
			});
		}

		function runGeoUpdate() {
			if (geoBusy)
				return;

			geoBusy = true;
			message.textContent = _('Working…');
			updateGeo(geoData);

			dae.geoUpdate().then(dae.ensureOk).then(function(result) {
				message.textContent = dae.resultMessage(result, _('The update was started.'));
			}).catch(function(error) {
				message.textContent = dae.errorMessage(error, _('The operation failed.'));
			}).finally(function() {
				geoBusy = false;
				refreshGeo();
			});
		}

		function loadSecret() {
			let shown = false;

			dae.secret().then(function(result) {
				const secret = result && result.secret;

				if (!secret) {
					ui.secretValue.textContent = _('The secret is not available to this session.');
					ui.secretShow.disabled = true;
					ui.secretCopy.disabled = true;
					return;
				}

				ui.secretValue.textContent = '••••••••••••';
				ui.secretShow.disabled = false;
				ui.secretCopy.disabled = false;

				ui.secretShow.onclick = function() {
					shown = !shown;
					ui.secretValue.textContent = shown ? secret : '••••••••••••';
					ui.secretShow.textContent = shown ? _('Hide') : _('Show');
				};

				ui.secretCopy.onclick = function() {
					ui.secretCopy.disabled = true;

					const done = function() {
						ui.secretCopy.textContent = _('Copied');
						setTimeout(function() {
							ui.secretCopy.textContent = _('Copy');
							ui.secretCopy.disabled = false;
						}, 3000);
					};

					// The clipboard can be out of reach: a browser that is not
					// allowed to use it refuses the write. The secret is shown
					// then, so it can still be taken over by hand.
					const failed = function() {
						shown = true;
						ui.secretValue.textContent = secret;
						ui.secretShow.textContent = _('Hide');
						ui.secretCopy.disabled = false;
						message.textContent = _('The secret could not be written to the clipboard. It is shown instead.');
					};

					if (navigator.clipboard && navigator.clipboard.writeText)
						navigator.clipboard.writeText(secret).then(done, failed);
					else
						failed();
				};
			}).catch(function() {
				ui.secretValue.textContent = _('The secret is not available to this session.');
				ui.secretShow.disabled = true;
				ui.secretCopy.disabled = true;
			});
		}

		function refreshStatus() {
			return dae.status().then(function(status) {
				updateStatus(status, null);
			}).catch(function() {
				updateStatus(null, true);
			});
		}

		function refreshGeo() {
			return dae.geoStatus().then(function(geo) {
				updateGeo(geo);
			}).catch(function() {
				updateGeo(null);
			});
		}

		// ---- assemble -------------------------------------------------------

		// The tabs replace the page title at the top of the view; the title and
		// its explanation belong to the service pane, so the geo tab opens on its
		// own content.
		paneService.insertBefore(el('div', 'dae-header', [
			el('h2', '', _('dae')),
			el('p', 'dae-header-sub',
				_('The doona panel drives the dae engine over its native HTTP API. dae serves the panel itself; this page shows the service state, opens the panel and updates the geo data.'))
		]), paneService.firstChild);
		page.appendChild(E('div', { 'class': 'dae-tabs', 'role': 'tablist' }, [ tabService, tabGeo ]));
		page.appendChild(paneService);
		page.appendChild(paneGeo);
		page.appendChild(message);

		updateStatus(data.status || null, data.error || null);
		updateGeo(data.geo || null);
		loadSecret();

		// A hidden tab keeps polling, and every poll is an RPC call. The page
		// catches up on the first tick after it is visible again.
		poll.add(function() {
			if (document.hidden)
				return Promise.resolve();

			const tasks = [ refreshStatus() ];
			if (!paneGeo.hidden || (geoData && geoData.state === 'running'))
				tasks.push(refreshGeo());
			return Promise.all(tasks);
		}, 5);

		return page;
	}
});
