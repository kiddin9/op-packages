'use strict';
'require view';
'require ui';
'require uci';
'require honk.common as honk';
'require honk.dashprofiles as dash';

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			uci.load('honk')
		]);
	},

	render: function() {
		var sec = (uci.sections('honk', 'honk')[0] || {});
		var sid = sec['.name'] || 'config';
		var dashType = uci.get('honk', sid, 'dashboard') || 'none';

		var profile = dash.getProfile(dashType);
		var currentInfo = null;
		var iframeLoaded = false;

		function createDashboardSelect() {
			var sel = E('select', { 
				'class': 'cbi-input-select',
				'change': function(ev) {
					var newType = ev.target.value;
					sel.disabled = true;
					honk.switchDashboardAndWait(newType).then(function(res) {
						if (res && res.pending) {
							sel.disabled = false;
							honk.showNotification(null, E('p', _('Saved, but the panel files are not installed yet — download the panel first.')), 'warning');
							loadInfo(true);
							return;
						}

						// The switch changes the stored settings, and the reloaded page has
						// to paint the tabs that apply to the new dashboard.
						honk.refreshTabVisibility().then(function() {
							window.location.reload();
						});
					}).catch(function(err) {
						sel.disabled = false;
						honk.showNotification(null, E('p', _('Failed to switch dashboard:') + ' ' + (err.message || err)), 'error');
					});
				}
			});
			var optNone = E('option', { 'value': 'none' }, _('None'));
			if (dashType === 'none') optNone.selected = true;
			sel.appendChild(optNone);
			Object.keys(dash.profiles).forEach(function(k) {
				var opt = E('option', { 'value': k }, dash.profiles[k].label());
				if (k === dashType) opt.selected = true;
				sel.appendChild(opt);
			});
			return sel;
		}

		function reloadIframe(forceFresh) {
			if (!currentInfo) return;
			var url = dash.buildUrl(dashType, currentInfo, forceFresh);
			iframe.src = 'about:blank';
			setTimeout(function() {
				iframe.src = url;
				iframeLoaded = true;
			}, 60);
		}

		// Create HTML elements
		var style = E('style', {}, [
			'#dash_iframe_wrap {',
			'	position: relative;',
			'	width: 100%;',
			'	height: calc(100vh - 210px);',
			'	min-height: 600px;',
			'	border: 1px solid var(--border, var(--hairline, var(--border-color-medium, #ccc)));',
			'	border-radius: var(--radius-base, 4px);',
			'	overflow: hidden;',
			'}',
			'#dash_iframe_wrap.fullscreen {',
			'	position: fixed !important;',
			'	top: 0 !important;',
			'	left: 0 !important;',
			'	right: 0 !important;',
			'	bottom: 0 !important;',
			'	width: 100vw !important;',
			'	height: 100vh !important;',
			'	height: 100dvh !important;',
			'	z-index: 999999 !important;',
			'	border: none !important;',
			'	border-radius: 0 !important;',
			'	margin: 0 !important;',
			'}',
			'#dash_iframe {',
			'	width: 100%;',
			'	height: 100%;',
			'	border: none;',
			'	display: block;',
			'	transform-origin: 0 0;',
			'}',
			'#dash_exit_fullscreen_btn {',
			'	position: absolute;',
			'	top: max(12px, env(safe-area-inset-top, 12px));',
			'	right: max(12px, env(safe-area-inset-right, 12px));',
			'	z-index: 1000000;',
			'	display: none;',
			'	cursor: pointer;',
			'}',
			'.dash-toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; flex-wrap: wrap; gap: 6px; }',
			'.dash-toolbar-info { display: flex; align-items: center; gap: 6px; flex-wrap: nowrap; }',
			'.dash-toolbar-actions { display: flex; align-items: center; gap: 6px; flex-wrap: nowrap; flex-shrink: 0; }',
			'.dash-toolbar-actions select { width: auto !important; max-width: 120px !important; margin: 0 !important; }',
			'.dash-toolbar-actions > * { white-space: nowrap !important; flex-shrink: 0; }',
			'@media (max-width: 768px) {',
			'	#dash_iframe_wrap {',
			'		height: calc(100vh - 190px);',
			'		height: calc(100dvh - 190px);',
			'		min-height: 520px;',
			'	}',
			'	.dash-toolbar-info { width: 100%; display: flex; align-items: center; justify-content: flex-start; gap: 4px; flex-wrap: nowrap !important; }',
			'	.dash-toolbar-info .label { font-size: 11px !important; padding: 2px 5px !important; white-space: nowrap !important; flex-shrink: 0 !important; }',
			'	.dash-toolbar-actions { width: 100%; display: flex; flex-wrap: wrap; gap: 4px; align-items: center; }',
			'	.dash-toolbar-actions select { width: auto !important; max-width: 90px !important; margin: 0 !important; padding: 2px 18px 2px 6px !important; font-size: 12px !important; height: 26px !important; line-height: 20px !important; flex: 0 0 auto !important; }',
			'	.dash-toolbar-actions .btn, .dash-toolbar-actions .cbi-button { padding: 3px 6px !important; font-size: 12px !important; flex: 0 0 auto !important; }',
			'}',
			'.dash-log-box {',
			'	max-height: 150px; overflow-y: auto; font-family: var(--font-mono, monospace);',
			'	font-size: 12px; line-height: 1.4; padding: 8px; margin: 8px 0;',
			'	background: var(--surface-raised, var(--surface-sunken, var(--background-color-low, transparent)));',
			'	border: 1px solid var(--border, var(--hairline, var(--border-color-medium, #ccc)));',
			'	border-radius: var(--radius-base, 3px); white-space: pre-wrap; word-break: break-all;',
			'}'
		].join('\n'));

		// Loading view
		var stateLoading = E('div', { 'class': 'cbi-section', 'style': 'text-align: center; padding: 30px;' }, [
			E('p', {}, E('em', {}, _('Checking Dashboard and API configuration...')))
		]);

		// Unconfigured view
		var quickEnableMsg = E('span', { 'style': 'margin-left: 8px;' });
		var enableBtnText = _('One-click Enable Default Native API');
		var btnQuickEnable = E('button', {
			'type': 'button',
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				btnQuickEnable.disabled = true;
				btnQuickEnable.innerText = _('Enabling Native API and restarting HONK...');
				honk.switchDashboardAndWait(dashType).then(function(res) {
					btnQuickEnable.disabled = false;
					btnQuickEnable.innerText = enableBtnText;
					quickEnableMsg.innerText = (res && res.pending)
						? _('Saved, but the panel files are not installed yet — download the panel first.')
						: _('Successfully enabled! Restarting service and initializing dashboard...');
					loadInfo(true);
				}).catch(function(err) {
					btnQuickEnable.disabled = false;
					btnQuickEnable.innerText = enableBtnText;
					honk.showNotification(null, E('p', _('Failed to enable:') + ' ' + (err.message || err)), 'error');
				});
			}
		}, enableBtnText);

		var unconfTitle = _('Dashboard / Native API Unconfigured');
		var unconfDescr = _('HONK has not enabled Native API in its configuration file. Dashboard requires native API listener and dashboard UI path.');
		var unconfWarn = _('Please configure experimental.native_api block in API Settings, and ensure listen and ui are configured.');

		var stateUnconfigured = E('div', { 'class': 'cbi-section', 'style': 'display: none;' }, [
			E('h3', {}, unconfTitle),
			E('div', { 'class': 'cbi-section-descr' }, unconfDescr),
			E('div', { 'class': 'alert-message warning', 'style': 'margin: 12px 0;' }, unconfWarn),
			E('div', { 'style': 'margin-top: 10px;' }, [
				E('label', { 'class': 'cbi-value-title' }, E('strong', {}, _('Example Configuration (/etc/honk/config.d/api.dae):'))),
				E('pre', { 'style': 'padding: 10px; margin-top: 6px; border: 1px solid var(--border-color-medium, #ccc); border-radius: 4px;' },
					dash.exampleConfig(profile)
				)
			]),
			E('div', { 'style': 'margin-top: 16px; display: flex; gap: 10px; align-items: center; flex-wrap: wrap;' }, [
				createDashboardSelect(),
				E('a', { 'href': L.url('admin/services/honk/api'), 'class': 'cbi-button' }, _('Configure in API Settings')),
				btnQuickEnable,
				quickEnableMsg
			])
		]);

		// Disabled view
		var selectDashboardNone = createDashboardSelect();
		var stateNone = E('div', { 'class': 'cbi-section', 'style': 'display: none;' }, [
			E('h3', {}, _('Dashboard Disabled')),
			E('div', { 'class': 'cbi-section-descr' },
				_('Dashboard type is currently set to "None". Web dashboard and API listener are disabled.')
			),
			E('table', { 'class': 'table', 'style': 'margin: 14px 0;' }, [
				E('tr', {}, [
					E('th', { 'style': 'width: 25%; vertical-align: middle;' }, _('Dashboard Type')),
					E('td', {}, selectDashboardNone)
				])
			])
		]);

		// Missing UI view
		var metaUiDir = E('td', {}, profile.defaultDir);
		var metaController = E('td', {}, dash.defaults.host + ':' + dash.defaults.port);
		var metaSecret = E('td', {}, _('(Not set)'));

		var radioGithub = E('input', { 'type': 'radio', 'class': 'cbi-input-radio', 'name': 'dash_dl_src', 'value': profile.githubRelease, 'checked': 'checked' });
		var radioMirror1 = E('input', { 'type': 'radio', 'class': 'cbi-input-radio', 'name': 'dash_dl_src', 'value': profile.ghfastMirror });
		var radioMirror2 = E('input', { 'type': 'radio', 'class': 'cbi-input-radio', 'name': 'dash_dl_src', 'value': profile.ghproxyMirror });
		var radioCustom = E('input', { 'type': 'radio', 'class': 'cbi-input-radio', 'name': 'dash_dl_src', 'value': 'custom' });
		var inputCustomUrl = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'style': 'width: 100%;', 'placeholder': 'https://.../' + profile.pkgName });
		var customUrlWrap = E('div', { 'style': 'display: none; margin-top: 8px;' }, [ inputCustomUrl ]);

		var dlLogBox = E('div', { 'class': 'dash-log-box' });
		var dlProgressWrap = E('div', { 'style': 'display: none; margin: 12px 0;' }, [
			E('div', { 'style': 'font-weight: bold; margin-bottom: 4px;' }, _('Preparing download...')),
			dlLogBox
		]);

		function updateCustomVisibility() {
			customUrlWrap.style.display = radioCustom.checked ? 'block' : 'none';
		}
		radioGithub.addEventListener('change', updateCustomVisibility);
		radioMirror1.addEventListener('change', updateCustomVisibility);
		radioMirror2.addEventListener('change', updateCustomVisibility);
		radioCustom.addEventListener('change', updateCustomVisibility);

		var btnStartDownload = E('button', {
			'type': 'button',
			'class': 'cbi-button cbi-button-apply',
			'click': function() {
				var url = '';
				if (radioCustom.checked) {
					url = (inputCustomUrl.value || '').trim();
					if (!url) {
						honk.showNotification(null, E('p', _('Please enter a valid download URL')), 'error');
						return;
					}
				} else if (radioMirror1.checked) {
					url = radioMirror1.value;
				} else if (radioMirror2.checked) {
					url = radioMirror2.value;
				} else {
					url = radioGithub.value;
				}

				btnStartDownload.disabled = true;
				btnStartDownload.innerText = _('Processing...');
				honk.triggerDashboardDownload(url, dashType, dlLogBox, dlProgressWrap, function(success) {
					btnStartDownload.disabled = false;
					btnStartDownload.innerText = _('Start Download & Install Dashboard');
					if (success) {
						honk.switchDashboardAndWait(dashType).then(function(res) {
							if (res && res.pending)
								honk.showNotification(null, E('p', _('Saved, but the panel files are not installed yet — download the panel first.')), 'warning');

							loadInfo(true);
						}).catch(function() {
							loadInfo(true);
						});
					}
				});
			}
		}, _('Start Download & Install Dashboard'));

		var selectDashboardMissing = createDashboardSelect();
		var stateMissingUi = E('div', { 'class': 'cbi-section', 'style': 'display: none;' }, [
			E('h3', {}, _('%s UI Files Not Found').format(profile.name)),
			E('div', { 'class': 'cbi-section-descr' },
				_('Native API is configured, but dashboard files are missing in the UI directory. You can download and deploy it directly.')
			),
			E('table', { 'class': 'table', 'style': 'margin: 14px 0;' }, [
				E('tr', {}, [ E('th', { 'style': 'width: 25%;' }, _('Target Dashboard')), E('td', {}, selectDashboardMissing) ]),
				E('tr', {}, [ E('th', {}, _('Target Directory (ui)')), metaUiDir ]),
				E('tr', {}, [ E('th', {}, _('Listen Address & Port')), metaController ]),
				E('tr', {}, [ E('th', {}, _('API Secret')), metaSecret ])
			]),
			E('div', { 'style': 'margin: 16px 0;' }, [
				E('label', { 'style': 'font-weight: bold; display: block; margin-bottom: 8px;' },
					_('Download Source:')
				),
				E('div', { 'style': 'display: flex; flex-direction: column; gap: 8px;' }, [
					E('label', { 'style': 'display: flex; align-items: center; gap: 8px; cursor: pointer;' }, [
						radioGithub, E('span', {}, [ E('strong', {}, _('GitHub Release ')), '(' + profile.pkgName + ')' ])
					]),
					E('label', { 'style': 'display: flex; align-items: center; gap: 8px; cursor: pointer;' }, [
						radioMirror1, E('span', {}, [ E('strong', {}, _('Mirror 1') + ' '), '(ghfast.top)' ])
					]),
					E('label', { 'style': 'display: flex; align-items: center; gap: 8px; cursor: pointer;' }, [
						radioMirror2, E('span', {}, [ E('strong', {}, _('Mirror 2') + ' '), '(ghproxy.net)' ])
					]),
					E('label', { 'style': 'display: flex; align-items: center; gap: 8px; cursor: pointer;' }, [
						radioCustom, E('span', {}, E('strong', {}, _('Custom URL')))
					])
				]),
				customUrlWrap
			]),
			dlProgressWrap,
			E('div', { 'style': 'margin-top: 16px;' }, [ btnStartDownload ])
		]);

		// Ready view
		var httpsAlert = E('div', { 'class': 'alert-message warning', 'style': 'display: none; margin-bottom: 10px; justify-content: space-between; align-items: center;' }, [
			E('div', {}, [
				E('strong', {}, _('HTTPS access detected:') + ' '),
				E('span', {}, _('Modern browsers may block HTTP iframe resources under HTTPS. If the dashboard fails to display, open it in a new tab.'))
			]),
			E('a', { 'href': '#', 'target': '_blank', 'class': 'cbi-button cbi-button-action', 'style': 'white-space: nowrap; margin-left: 10px;' }, _('Open in New Tab'))
		]);

		var honkPortLabel = E('span', { 'class': 'honk_port_label' }, profile.defaultPort);
		var honkStopAlert = E('div', { 'class': 'alert-message warning', 'style': 'display: none; margin-bottom: 10px; justify-content: space-between; align-items: center;' }, [
			E('div', {}, [
				E('strong', {}, _('HONK service is currently not running:') + ' '),
				E('span', {}, [ _('Dashboard API port ('), honkPortLabel, _(') is not listening. Start the service to display data.') ])
			]),
			E('a', { 'href': L.url('admin/services/honk/global'), 'class': 'cbi-button cbi-button-action', 'style': 'white-space: nowrap; margin-left: 10px;' }, _('Start HONK'))
		]);

		var statusServicePill = E('span', { 'class': 'label success' }, _('Running'));
		var statusEndpointPill = E('span', { 'class': 'label notice', 'style': 'font-family: monospace; text-transform: none !important;' });
		var tokenText = E('span', {
			'style': 'user-select: all; -webkit-user-select: all; font-weight: bold; text-transform: none !important;',
			'title': _('Click to copy API Token')
		});
		var tokenPill = E('span', {
			'class': 'label info',
			'style': 'font-family: monospace; display: none; padding: 2px 6px; cursor: pointer; text-transform: none !important;',
			'title': _('Click to copy API Token'),
			'click': function(ev) {
				ev.stopPropagation();
				var val = (tokenText.innerText || tokenText.textContent || '').trim();
				if (!val) return;
				if (navigator.clipboard && navigator.clipboard.writeText) {
					navigator.clipboard.writeText(val).then(function() {
						honk.showNotification(null, E('p', _('Token copied to clipboard: ') + val), 'info', 2000);
					}).catch(function() {
						honk.showNotification(null, E('p', _('Token: ') + val), 'info', 3000);
					});
				} else {
					honk.showNotification(null, E('p', _('Token: ') + val), 'info', 3000);
				}
			}
		}, [ _('Token: '), tokenText ]);
		var btnExternalOpen = E('a', { 'href': '#', 'target': '_blank', 'class': 'cbi-button cbi-button-action', 'title': _('Open independently in a new tab') }, _('New Tab'));
		var iframe = E('iframe', { 'id': 'dash_iframe', 'src': 'about:blank', 'allow': 'fullscreen; clipboard-read; clipboard-write' });

		var scaleStorageKey = 'honk_dash_scale';
		var isMobileInit = (window.innerWidth <= 768);
		var currentScale = localStorage.getItem(scaleStorageKey) || (isMobileInit ? '0.85' : '1');
		var scaleCycle = ['0.85', '1', '0.75'];

		function formatScaleLabel(s) {
			if (s === '1') return '100%';
			if (s === '0.85') return '85%';
			if (s === '0.75') return '75%';
			return Math.round(parseFloat(s) * 100) + '%';
		}

		function applyScale(scaleVal) {
			if (scaleVal) {
				currentScale = scaleVal;
			}
			var s = parseFloat(currentScale);
			if (isNaN(s) || s <= 0 || s > 1.5) {
				s = 1;
			}

			if (s === 1) {
				iframe.style.width = '100%';
				iframe.style.height = '100%';
				iframe.style.transform = 'none';
			} else {
				var pct = (100 / s).toFixed(4) + '%';
				iframe.style.width = pct;
				iframe.style.height = pct;
				iframe.style.transform = 'scale(' + s + ')';
			}
		}

		var btnScale = E('button', {
			'type': 'button',
			'class': 'btn cbi-button',
			'title': _('Click to switch scale (85% / 100% / 75%)'),
			'click': function() {
				var idx = scaleCycle.indexOf(currentScale);
				var nextScale = scaleCycle[(idx + 1) % scaleCycle.length];
				currentScale = nextScale;
				localStorage.setItem(scaleStorageKey, nextScale);
				btnScale.innerText = formatScaleLabel(nextScale);
				applyScale(nextScale);
			}
		}, formatScaleLabel(currentScale));

		applyScale();

		window.addEventListener('resize', function() {
			if (!localStorage.getItem(scaleStorageKey)) {
				var mob = (window.innerWidth <= 768);
				var newScale = mob ? '0.85' : '1';
				if (newScale !== currentScale) {
					currentScale = newScale;
					btnScale.innerText = formatScaleLabel(newScale);
					applyScale();
				}
			}
		});

		var btnExitFullscreen = E('button', {
			'id': 'dash_exit_fullscreen_btn',
			'type': 'button',
			'class': 'btn cbi-button',
			'title': _('Exit Fullscreen'),
			'click': function(ev) {
				ev.stopPropagation();
				toggleFullscreen(false);
			}
		}, ['\u2715 ' + _('Exit Fullscreen')]);

		var iframeWrap = E('div', { 'id': 'dash_iframe_wrap' }, [iframe, btnExitFullscreen]);

		// Update Modal
		var updateTargetLabel = E('code', {
			'style': 'background: var(--surface-sunken, var(--background-color-low, rgba(128, 128, 128, 0.12))); padding: 2px 6px; border-radius: 4px; font-family: var(--font-mono, monospace); font-weight: bold;'
		}, profile.defaultDir);

		var modalRadioGithub = E('input', { 'type': 'radio', 'class': 'cbi-input-radio', 'name': 'modal_dl_src', 'value': profile.githubRelease, 'checked': 'checked' });
		var modalRadioMirror = E('input', { 'type': 'radio', 'class': 'cbi-input-radio', 'name': 'modal_dl_src', 'value': profile.ghfastMirror });
		var modalLogBox = E('div', { 'class': 'dash-log-box' });
		var modalStatusAlert = E('div', { 'class': 'alert-message', 'style': 'display: none; margin-bottom: 8px;' });
		var modalProgressWrap = E('div', { 'style': 'display: none; margin-top: 12px;' }, [ modalStatusAlert, modalLogBox ]);

		var btnCancelModal = E('button', {
			'type': 'button',
			'class': 'btn cbi-button',
			'click': ui.hideModal
		}, _('Cancel'));

		var btnConfirmUpdate = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-action' }, _('Start Update'));

		function startModalUpdate() {
			var url = modalRadioMirror.checked ? modalRadioMirror.value : modalRadioGithub.value;
			btnConfirmUpdate.disabled = true;
			btnConfirmUpdate.innerText = _('Processing...');
			btnCancelModal.disabled = true;
			modalStatusAlert.style.display = 'none';

			honk.triggerDashboardDownload(url, dashType, modalLogBox, modalProgressWrap, function(success) {
				if (success) {
					modalStatusAlert.className = 'alert-message success';
					modalStatusAlert.innerText = _('Installation completed successfully!');
					modalStatusAlert.style.display = 'block';
					btnConfirmUpdate.disabled = false;
					btnConfirmUpdate.className = 'btn cbi-button cbi-button-apply';
					btnConfirmUpdate.innerText = _('Close');
					btnConfirmUpdate.onclick = function() { ui.hideModal(); };
					btnCancelModal.style.display = 'none';
						honk.switchDashboardAndWait(dashType).then(function(res) {
							if (res && res.pending)
								honk.showNotification(null, E('p', _('Saved, but the panel files are not installed yet — download the panel first.')), 'warning');

							loadInfo(true);
						}).catch(function() {
							loadInfo(true);
						});
				} else {
					modalStatusAlert.className = 'alert-message warning';
					modalStatusAlert.innerText = _('Installation failed. Please check logs.');
					modalStatusAlert.style.display = 'block';
					btnConfirmUpdate.disabled = false;
					btnConfirmUpdate.className = 'btn cbi-button cbi-button-action';
					btnConfirmUpdate.innerText = _('Start Update');
					btnConfirmUpdate.onclick = startModalUpdate;
					btnCancelModal.style.display = '';
					btnCancelModal.disabled = false;
				}
			});
		}

		btnConfirmUpdate.onclick = startModalUpdate;

		var btnUpdateDashboard = E('button', {
			'type': 'button',
			'class': 'btn cbi-button',
			'title': _('Update to latest') + ' ' + profile.name,
			'click': function() {
				modalProgressWrap.style.display = 'none';
				modalStatusAlert.style.display = 'none';
				modalLogBox.innerText = '';
				btnConfirmUpdate.disabled = false;
				btnConfirmUpdate.className = 'btn cbi-button cbi-button-action';
				btnConfirmUpdate.innerText = _('Start Update');
				btnConfirmUpdate.onclick = startModalUpdate;
				btnCancelModal.style.display = '';
				btnCancelModal.disabled = false;

				ui.showModal(_('Update Dashboard') + ' - ' + profile.name, [
					E('p', { 'class': 'cbi-section-descr' }, [
						_('The latest version (%s) will be downloaded and deployed to:').format(profile.pkgName),
						' ',
						updateTargetLabel
					]),
					E('div', { 'class': 'alert-message info', 'style': 'margin: 8px 0;' },
						_('Tip: If the dashboard still shows the old version, press Ctrl+F5 or open in a new tab to bypass PWA cache.')
					),
					E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, _('Select download source')),
						E('div', { 'class': 'cbi-value-field', 'style': 'display: flex; flex-direction: column; gap: 8px;' }, [
							E('label', { 'style': 'display: flex; align-items: center; gap: 8px; cursor: pointer;' }, [
								modalRadioGithub, E('span', {}, [ E('strong', {}, _('GitHub Release ')), '(' + profile.pkgName + ')' ])
							]),
							E('label', { 'style': 'display: flex; align-items: center; gap: 8px; cursor: pointer;' }, [
								modalRadioMirror, E('span', {}, [ E('strong', {}, _('Mirror') + ' '), '(ghfast.top)' ])
							])
						])
					]),
					modalProgressWrap,
					E('div', { 'class': 'right', 'style': 'margin-top: 16px; display: flex; justify-content: flex-end; gap: 10px;' }, [
						btnCancelModal,
						btnConfirmUpdate
					])
				]);
			}
		}, _('Update Dashboard'));

		var btnRefreshIframe = E('button', {
			'type': 'button',
			'class': 'btn cbi-button',
			'title': _('Refresh dashboard content'),
			'click': function() {
				if (currentInfo) {
					reloadIframe(true);
				}
			}
		}, _('Refresh'));

		function toggleFullscreen(enable) {
			var isFull = (typeof enable === 'boolean') ? enable : !iframeWrap.classList.contains('fullscreen');
			if (isFull) {
				iframeWrap.classList.add('fullscreen');
				document.body.classList.add('dash-body-fullscreen');
				btnExitFullscreen.style.display = 'inline-flex';
				btnToggleFullscreen.innerText = _('Exit Fullscreen');
				if (iframeWrap.requestFullscreen) {
					iframeWrap.requestFullscreen().catch(function() {});
				} else if (iframeWrap.webkitRequestFullscreen) {
					iframeWrap.webkitRequestFullscreen().catch(function() {});
				}
			} else {
				iframeWrap.classList.remove('fullscreen');
				document.body.classList.remove('dash-body-fullscreen');
				btnExitFullscreen.style.display = 'none';
				btnToggleFullscreen.innerText = _('Fullscreen');
				if (document.fullscreenElement || document.webkitFullscreenElement) {
					if (document.exitFullscreen) {
						document.exitFullscreen().catch(function() {});
					} else if (document.webkitExitFullscreen) {
						document.webkitExitFullscreen().catch(function() {});
					}
				}
			}
			applyScale();
		}

		document.addEventListener('fullscreenchange', function() {
			if (!document.fullscreenElement && iframeWrap.classList.contains('fullscreen')) {
				toggleFullscreen(false);
			}
		});
		document.addEventListener('webkitfullscreenchange', function() {
			if (!document.webkitFullscreenElement && iframeWrap.classList.contains('fullscreen')) {
				toggleFullscreen(false);
			}
		});
		document.addEventListener('keydown', function(e) {
			if (e.key === 'Escape' && iframeWrap.classList.contains('fullscreen')) {
				toggleFullscreen(false);
			}
		});

		var btnToggleFullscreen = E('button', {
			'type': 'button',
			'class': 'btn cbi-button',
			'title': _('Toggle fullscreen display'),
			'click': function() {
				toggleFullscreen();
			}
		}, _('Fullscreen'));

		// Add dashboard switcher in header
		var selectDashboard = createDashboardSelect();

		var stateReady = E('div', { 'style': 'display: none;' }, [
			httpsAlert,
			honkStopAlert,
			E('div', { 'class': 'dash-toolbar' }, [
				E('div', { 'class': 'dash-toolbar-info' }, [
					statusServicePill,
					statusEndpointPill,
					tokenPill
				]),
				E('div', { 'class': 'dash-toolbar-actions' }, [
					selectDashboard,
					btnToggleFullscreen,
					btnRefreshIframe,
					btnScale,
					btnExternalOpen,
					btnUpdateDashboard
				])
			]),
			iframeWrap
		]);

		function showState(name) {
			stateLoading.style.display = (name === 'loading') ? 'block' : 'none';
			stateNone.style.display = (name === 'none') ? 'block' : 'none';
			stateUnconfigured.style.display = (name === 'unconfigured') ? 'block' : 'none';
			stateMissingUi.style.display = (name === 'missing_ui') ? 'block' : 'none';
			stateReady.style.display = (name === 'ready') ? 'block' : 'none';
		}

		function updateHonkRunningState(running, port) {
			if (running) {
				statusServicePill.className = 'label success';
				statusServicePill.innerText = _('Running');
				honkStopAlert.style.display = 'none';
			} else {
				statusServicePill.className = 'label warning';
				statusServicePill.innerText = _('Not Running');
				honkStopAlert.style.display = 'flex';
				honkPortLabel.innerText = port || profile.defaultPort;
			}
		}

		function loadInfo(forceReload) {
			if (dashType === 'none') {
				showState('none');
				return;
			}
			honk.callHonkDashboardInfo(dashType).then(function(data) {
				if (!data || !data.configured) {
					showState('unconfigured');
					return;
				}
				currentInfo = data;

				if (!data.has_ui) {
					metaUiDir.innerText = data.external_ui || profile.defaultDir;
					metaController.innerText = data.external_controller || (dash.defaults.host + ':' + profile.defaultPort);
					metaSecret.innerText = data.secret ? data.secret : _('Not configured (Empty)');
					showState('missing_ui');
					return;
				}

				// Ready state
				showState('ready');
				var targetHost = dash.getTargetHost(data.host);
				var port = data.port || profile.defaultPort;
				var fullUrl = dash.buildUrl(dashType, data);

				updateHonkRunningState(data.running, port);

				statusEndpointPill.innerText = targetHost + ':' + port;
				if (data.secret) {
					tokenText.innerText = data.secret;
					tokenPill.style.display = 'inline-block';
				} else {
					tokenPill.style.display = 'none';
				}
				btnExternalOpen.href = fullUrl;

				var httpsBtn = httpsAlert.querySelector('a');
				if (httpsBtn) httpsBtn.href = fullUrl;

				if (window.location.protocol === 'https:') {
					httpsAlert.style.display = 'flex';
				} else {
					httpsAlert.style.display = 'none';
				}

				var normalizedSrc = (iframe.src || '').replace(/\/$/, '');
				var normalizedFullUrl = (fullUrl || '').replace(/\/$/, '');
				if (forceReload) {
					reloadIframe(true);
				} else if (!iframeLoaded || normalizedSrc !== normalizedFullUrl) {
					iframe.src = fullUrl;
					iframeLoaded = true;
				}

				updateTargetLabel.innerText = data.external_ui || profile.defaultDir;
			}).catch(function() {
				showState('unconfigured');
			});
		}

		loadInfo();

		var dashStatusPollFn = function() {
			if (document.hidden) {
				return Promise.resolve();
			}
			if (currentInfo && currentInfo.configured && currentInfo.has_ui) {
				return honk.callHonkStatus().then(function(res) {
					var isRunning = (res && res.running);
					updateHonkRunningState(isRunning, currentInfo.port);
				}).catch(function() { });
			}
			return Promise.resolve();
		};

		honk.addElementPoll(dashStatusPollFn, iframe, 5);

		return E('div', { 'class': 'dash-wrap' }, [
			style,
			stateLoading,
			stateNone,
			stateUnconfigured,
			stateMissingUi,
			stateReady
		]);
	}
});
