'use strict';
'require dom';
'require view';
'require poll';
'require fs';
'require ui';
'require uci';

if (!document.getElementById('secbox-theme-css')) {
	document.head.appendChild(E('link', {
		'id': 'secbox-theme-css',
		'rel': 'stylesheet',
		'type': 'text/css',
		'href': L.resource('view/secbox/custom.css')
	}));
}

/*
	service action handling
*/
function handleAction(ev) {
	ui.showIndicator('banip-action', _('Executing action: %s...').format(ev));
	return fs.exec_direct('/etc/init.d/banip', [ev])
		.then(function () {
			ui.hideIndicator('banip-action');
			ui.addNotification(null, E('p', _('SecBox service action "%s" executed successfully.').format(ev)), 'info');
		})
		.catch(function (e) {
			ui.hideIndicator('banip-action');
			ui.addNotification(null, E('p', _('Failed to execute action "%s": %s').format(ev, e.message)), 'error');
		});
}

function showInlineNotice(type, message) {
	const slot = document.getElementById('secbox-notice-slot');
	if (!slot) return;
	const cls = type === 'ok' ? 'secbox-note secbox-note-ok'
		: type === 'warn' ? 'secbox-note secbox-note-warn'
		: type === 'err' ? 'secbox-note secbox-note-err'
		: 'secbox-note';
	dom.content(slot, [
		E('div', { 'class': cls }, [
			E('span', {}, [message]),
			E('button', {
				'type': 'button',
				'class': 'secbox-note-close',
				'aria-label': _('Close'),
				'click': function () {
					dom.content(slot, []);
				}
			}, ['\u00d7'])
		])
	]);
}

function handleToggleService(enable, onDone) {
	const title = enable ? _('Enabling and starting SecBox service...') : _('Stopping and disabling SecBox service...');
	ui.showIndicator('banip-action', title);
	return uci.load('banip').then(function () {
		uci.set('banip', 'global', 'ban_enabled', enable ? '1' : '0');
		return uci.save();
	}).then(function () {
		return uci.apply();
	}).then(function () {
		return fs.exec_direct('/etc/init.d/banip', [enable ? 'restart' : 'stop'])
			.then(function () {
				if (!enable) {
					return { ok: true, waitingWan: false };
				}
				return L.resolveDefault(fs.read_direct('/var/run/banIP/banIP.runtime.json'), 'null')
					.then(function (res) {
						try {
							const info = JSON.parse(res);
							const hasUplink = Array.isArray(info?.active_uplink) && info.active_uplink.some(v => v && v !== '-');
							const hasWanIf = Array.isArray(info?.wan_interfaces) && info.wan_interfaces.some(v => v && v !== '-');
							if (info && info.status !== 'active' && info.status !== 'processing' && !hasUplink && !hasWanIf) {
								return { ok: true, waitingWan: true };
							}
						} catch (e) {}
						return { ok: true, waitingWan: false };
					});
			})
			.catch(function () {
				return { ok: false, waitingWan: enable };
			});
	}).then(function (res) {
		ui.hideIndicator('banip-action');
		if (!enable) {
			showInlineNotice('info', _('SecBox service stopped and disabled.'));
		} else if (res.waitingWan) {
			showInlineNotice('warn', _('SecBox service is enabled and will start automatically once WAN is connected.'));
		} else {
			showInlineNotice('ok', _('SecBox service enabled and started.'));
		}
		if (typeof onDone === 'function') {
			return onDone();
		}
	}).catch(function (e) {
		ui.hideIndicator('banip-action');
		showInlineNotice('err', _('Failed to update service status: %s').format(e.message));
	});
}

/*
	runtime string helpers
*/
function parsePairs(text) {
	const pairs = [];
	(text || '').split(', ').forEach(function (item) {
		const idx = item.indexOf(': ');
		if (idx > 0) {
			pairs.push([item.substring(0, idx), item.substring(idx + 2)]);
		} else if (item.trim()) {
			pairs.push([null, item.trim()]);
		}
	});
	return pairs;
}

function pickValue(pairs, key) {
	for (let i = 0; i < pairs.length; i++) {
		if (pairs[i][0] === key) {
			return pairs[i][1];
		}
	}
	return '-';
}

function expandPairs(pairs) {
	const result = [];
	pairs.forEach(function (pair) {
		if (!pair[0]) {
			result.push(pair);
			return;
		}
		const group = pair[0].match(/^(.*?)\s*\(([^()]*\/[^()]*)\)$/);
		if (group) {
			const names = group[2].split('/');
			const values = pair[1].split('/');
			if (names.length === values.length) {
				for (let i = 0; i < names.length; i++) {
					result.push([group[1] + ' ' + names[i], values[i]]);
				}
				return;
			}
		}
		result.push(pair);
	});
	return result;
}

function flagChips(text) {
	const pairs = expandPairs(parsePairs(text)).filter(p => p[0]);
	if (!pairs.length) {
		return [E('span', { 'class': 'secbox-muted' }, [_('No runtime flags')])];
	}
	return [E('div', { 'style': 'display: flex; flex-wrap: wrap; gap: 6px; align-items: center;' }, pairs.map(function (flag) {
		const on = flag[1] === '\u2714';
		return E('span', {
			'class': on ? 'secbox-pill secbox-pill-ok' : 'secbox-pill secbox-pill-muted',
			'style': 'margin: 0;'
		}, [
			(on ? '\u2714 ' : '\u2718 ') + flag[0]
		]);
	}))];
}

function feedChips(feeds) {
	const chips = (Array.isArray(feeds) ? feeds : []).filter(f => f && f !== '-');
	if (!chips.length) {
		return [E('span', { 'class': 'secbox-muted' }, [_('No active feeds')])];
	}
	return [E('div', { 'style': 'display: flex; flex-wrap: wrap; gap: 6px; align-items: center;' }, chips.map(function (feed) {
		return E('span', {
			'class': 'secbox-pill secbox-pill-info',
			'style': 'margin: 0;'
		}, [feed]);
	}))];
}

function sysPairs(text) {
	let plain = 0;
	return parsePairs(text).filter(function (pair) {
		return pair[0] || ++plain === 1;
	});
}

function splitCount(text) {
	const value = text || '';
	const idx = value.indexOf(' (');
	if (idx < 0) {
		return { 'count': value || '-', 'detail': '-' };
	}
	return {
		'count': value.substring(0, idx) || '-',
		'detail': value.substring(idx + 2).replace(/\)$/, '') || '-'
	};
}

function splitUplinks(list) {
	const v4 = [], v6 = [];
	(Array.isArray(list) ? list : []).forEach(function (addr) {
		if (addr) {
			(addr.indexOf(':') >= 0 ? v6 : v4).push(addr);
		}
	});
	return {
		'v4': v4.length ? v4.join(', ') : '-',
		'v6': v6.length ? v6.join(', ') : '-'
	};
}

const keyMap = {
	'ver': _('NFT Version'),
	'table': _('Table'),
	'priority': _('Priority'),
	'policy': _('Policy'),
	'loglevel': _('NFT Log Level'),
	'expiry': _('Set Expiry'),
	'proto 4': _('IPv4 Protocol'),
	'proto 6': _('IPv6 Protocol'),
	'limit icmp': _('ICMP Limit'),
	'limit syn': _('SYN Limit'),
	'limit udp': _('UDP Limit'),
	'loglimit rate': _('Log Rate Limit'),
	'loglimit burst': _('Log Burst Limit'),
	'cores': _('CPU Cores'),
	'log': _('Log Service'),
	'fetch': _('Download Tool'),
	'wan-dev': _('WAN Device'),
	'wan-if': _('WAN Interface'),
	'vlan-allow': _('Allowed VLAN'),
	'vlan-block': _('Blocked VLAN'),
	'uplink IPv4': _('Uplink IPv4'),
	'uplink IPv6': _('Uplink IPv6')
};

const stateMap = {
	'active': _('Running (active)'),
	'processing': _('Processing...'),
	'disabled': _('Disabled'),
	'error': _('Not Ready (Check Logs)'),
	'stopped': _('Stopped'),
	'not running': _('Not Running')
};

return view.extend({
	load: function () {
		return Promise.all([
			uci.load('banip').catch(() => 0),
			L.resolveDefault(fs.stat('/var/run/banIP/banIP.runtime.json'), null)
		]).then(function (results) {
			const stat = results[1];
			return Promise.all([
				results[0],
				stat ? L.resolveDefault(fs.read_direct('/var/run/banIP/banIP.runtime.json'), 'null') : Promise.resolve(null),
				L.resolveDefault(fs.exec_direct('/etc/init.d/banip', ['actual']), '')
			]);
		});
	},

	render: function (loadResult) {
		const isEnabled = (uci.get('banip', 'global', 'ban_enabled') === '1');
		let currentRunning = false;

		let viewNode = null;

		const setNodes = (id, nodes) => {
			const el = viewNode ? viewNode.querySelector('#' + id) : document.getElementById(id);
			if (el) dom.content(el, nodes);
		};

		const setText = (id, value, fallback) => {
			const el = viewNode ? viewNode.querySelector('#' + id) : document.getElementById(id);
			if (el) el.textContent = (value !== undefined && value !== null && value !== '') ? value : (fallback !== undefined ? fallback : '-');
		};

		const join = list => {
			const items = (Array.isArray(list) ? list : []).filter(v => v && v !== '-');
			return items.length ? items.join(', ') : '-';
		};

		const emptyTableRow = msg => [
			E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
				E('td', { 'colspan': 2, 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important; color: #64748b;' }, [msg])
			])
		];

		let parseErrCount = 0;
		const applyRuntime = function (res, actualRaw) {
			const actual = (actualRaw || '').trim();
			const toggleBtn = viewNode ? viewNode.querySelector('#btn-toggle-service') : document.getElementById('btn-toggle-service');
			const dotEl = viewNode ? viewNode.querySelector('#status-dot') : document.getElementById('status-dot');
			const statusCard = viewNode ? viewNode.querySelector('#secbox-status-card') : document.getElementById('secbox-status-card');
			const titleBadge = viewNode ? viewNode.querySelector('#secbox-service-badge') : document.getElementById('secbox-service-badge');
			let info = null;

			if (res !== null && res !== undefined) {
				try {
					info = JSON.parse(res);
					parseErrCount = 0;
				} catch (e) {
					info = null;
					parseErrCount++;
					if (parseErrCount >= 3) {
						ui.addNotification(null, E('p', _('Unable to parse the SecBox runtime information!')), 'error');
						poll.stop();
					}
					return;
				}
			}

			const isEnabled = (uci.get('banip', 'global', 'ban_enabled') === '1');
			const rawState = info?.status || (isEnabled ? 'not running' : 'disabled');
			const isRunning = (rawState === 'active' || rawState === 'processing');

			const wanDevStr = join(info?.wan_devices);
			const wanIfStr = join(info?.wan_interfaces);
			const uplinks = splitUplinks(info?.active_uplink);
			const noWanUplink = (wanDevStr === '-' && wanIfStr === '-' && uplinks.v4 === '-' && uplinks.v6 === '-');
			const waitingForWan = isEnabled && !isRunning && noWanUplink && (!info || rawState === 'error' || rawState === 'not running' || rawState === 'stopped');
			const isDisabledError = !isEnabled && !isRunning && rawState === 'error';
			currentRunning = isRunning || waitingForWan;

			const statusLabel = waitingForWan
				? _('Waiting for WAN connection...')
				: (isDisabledError ? _('Disabled') : (stateMap[rawState] || rawState));
			setText('state_text', statusLabel);

			if (titleBadge) {
				const badgeCls = rawState === 'active' ? 'secbox-pill secbox-pill-ok'
					: rawState === 'processing' ? 'secbox-pill secbox-pill-info'
					: waitingForWan ? 'secbox-pill secbox-pill-warn'
					: (rawState === 'error' && !isDisabledError) ? 'secbox-pill secbox-pill-err'
					: 'secbox-pill secbox-pill-muted';
				const dotCls = rawState === 'active' ? 'secbox-dot secbox-dot-ok'
					: rawState === 'processing' ? 'secbox-dot secbox-dot-info'
					: waitingForWan ? 'secbox-dot secbox-dot-warn'
					: (rawState === 'error' && !isDisabledError) ? 'secbox-dot secbox-dot-err'
					: 'secbox-dot secbox-dot-muted';
				titleBadge.className = badgeCls;
				titleBadge.style.margin = '0';
				dom.content(titleBadge, [
					E('span', { 'class': dotCls }),
					statusLabel
				]);
			}

			const frontVer = (info?.frontend_ver && info.frontend_ver !== '-') ? info.frontend_ver : '26.11';
			const backVer = (info?.backend_ver && info.backend_ver !== '-') ? info.backend_ver : '-';
			setText('versions', `${frontVer} / ${backVer}`);
			setNodes('actual', actual ? flagChips(actual) : [E('span', { 'class': 'secbox-muted' }, [_('Service inactive')])]);

			if (dotEl) {
				if (rawState === 'active') {
					dotEl.className = 'secbox-dot secbox-dot-ok';
					if (statusCard) statusCard.className = 'op-card secbox-card-ok';
				} else if (rawState === 'processing') {
					dotEl.className = 'secbox-dot secbox-dot-info';
					if (statusCard) statusCard.className = 'op-card secbox-card-info';
				} else if (waitingForWan) {
					dotEl.className = 'secbox-dot secbox-dot-warn';
					if (statusCard) statusCard.className = 'op-card secbox-card-warn';
				} else if (rawState === 'error' && !isDisabledError) {
					dotEl.className = 'secbox-dot secbox-dot-err';
					if (statusCard) statusCard.className = 'op-card secbox-card-err';
				} else {
					dotEl.className = 'secbox-dot secbox-dot-muted';
					if (statusCard) statusCard.className = 'op-card secbox-card-muted';
				}
			}

			if (toggleBtn) {
				if (isRunning) {
					toggleBtn.textContent = _('Stop Service');
					toggleBtn.className = 'btn cbi-button cbi-button-reset';
				} else if (waitingForWan) {
					toggleBtn.textContent = _('Disable Service');
					toggleBtn.className = 'btn cbi-button cbi-button-reset';
				} else {
					toggleBtn.textContent = _('Start Service');
					toggleBtn.className = 'btn cbi-button cbi-button-save';
				}
			}

			const elements = splitCount(info?.element_count);
			const runPairs = parsePairs(info?.last_run);

			setText('elements_count', elements.count !== '-' ? elements.count : '0');
			setText('elements_sub', elements.detail !== '-' ? elements.detail : _('No active ruleset loaded'), '');

			const runTime = pickValue(runPairs, 'date / time');
			const runDetail = [pickValue(runPairs, 'mode'), pickValue(runPairs, 'duration'), pickValue(runPairs, 'memory')].filter(v => v && v !== '-').join(', ');
			setText('last_run_time', runTime !== '-' ? runTime : _('Not run yet'));
			setText('last_run_detail', runDetail || _('Waiting for first run'), '');

			setNodes('wan_dev', wanDevStr !== '-' ? [wanDevStr] : [E('span', { 'class': 'secbox-muted' }, [_('Not detected')])]);
			setNodes('wan_if', wanIfStr !== '-' ? [wanIfStr] : [E('span', { 'class': 'secbox-muted' }, [_('Not detected')])]);
			const vlanAllowStr = join(info?.vlan_allow);
			const vlanBlockStr = join(info?.vlan_block);
			setNodes('vlan_allow', vlanAllowStr !== '-' ? [vlanAllowStr] : [E('span', { 'class': 'secbox-muted' }, [_('None configured')])]);
			setNodes('vlan_block', vlanBlockStr !== '-' ? [vlanBlockStr] : [E('span', { 'class': 'secbox-muted' }, [_('None configured')])]);
			setNodes('uplink4', uplinks.v4 !== '-' ? [uplinks.v4] : [E('span', { 'class': 'secbox-muted' }, [_('No IPv4 uplink')])]);
			setNodes('uplink6', uplinks.v6 !== '-' ? [uplinks.v6] : [E('span', { 'class': 'secbox-muted' }, [_('No IPv6 uplink')])]);

			// Render NFT pairs
			const nftPairs = expandPairs(parsePairs(info?.nft_info));
			const nftNodes = [];
			nftPairs.forEach((p, idx) => {
				if (p[0]) {
					const k = keyMap[p[0].trim()] || p[0].trim();
					const hasVal = p[1] && p[1].trim() !== '-';
					nftNodes.push(E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((idx % 2) ? 2 : 1) }, [
						E('td', { 'class': 'td cbi-section-table-cell op-col-key' }, [k]),
						E('td', {
							'class': 'td cbi-section-table-cell op-col-val' + (hasVal ? '' : ' secbox-muted'),
							'style': hasVal ? 'font-family: monospace;' : ''
						}, [hasVal ? p[1] : _('Not set')])
					]));
				}
			});
			setNodes('nft_tbody', nftNodes.length ? nftNodes : emptyTableRow(_('No active NFT information available.')));

			// System Info (Full-width row, 16% key : 84% val)
			const sysList = sysPairs(info?.system_info);
			const sysNodes = [];
			sysList.forEach((p, idx) => {
				if (p[0]) {
					const k = keyMap[p[0].trim()] || p[0].trim();
					sysNodes.push(E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((idx % 2) ? 2 : 1) }, [
						E('td', { 'class': 'td cbi-section-table-cell op-full-key' }, [k]),
						E('td', { 'class': 'td cbi-section-table-cell op-full-val' }, [p[1]])
					]));
				} else {
					sysNodes.push(E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((idx % 2) ? 2 : 1) }, [
						E('td', { 'class': 'td cbi-section-table-cell op-full-key' }, [_('Device Model')]),
						E('td', { 'class': 'td cbi-section-table-cell op-full-val' }, [p[1]])
					]));
				}
			});
			setNodes('sys_tbody', sysNodes.length ? sysNodes : emptyTableRow(_('No system runtime data available.')));

			setNodes('feeds_container', feedChips(info?.active_feeds));
			setNodes('flags_container', flagChips(info?.run_flags));
		};

		/*
			poll runtime information
		*/
		this._pollFn = function () {
			return L.resolveDefault(fs.stat('/var/run/banIP/banIP.runtime.json'), null).then(function (stat) {
				return Promise.all([
					stat ? L.resolveDefault(fs.read_direct('/var/run/banIP/banIP.runtime.json'), 'null') : Promise.resolve(null),
					L.resolveDefault(fs.exec_direct('/etc/init.d/banip', ['actual']), '')
				]).then(function (results) {
					applyRuntime(results[0], results[1]);
				});
			});
		};
		poll.add(this._pollFn, 3);

		const style = E('style', { 'type': 'text/css' }, [
			'#ban-op-grid .op-grid-2 { display: grid; gap: 12px; grid-template-columns: repeat(2, 1fr); margin-bottom: 14px; align-items: stretch; }' +
			'@media (max-width: 900px) { #ban-op-grid .op-grid-2 { grid-template-columns: 1fr; } }' +
			'#ban-op-grid .op-grid-1 { margin-bottom: 14px; width: 100%; }' +
			'#ban-op-grid .op-card { display: flex; flex-direction: column; height: 100%; box-sizing: border-box; }' +
			'#ban-op-grid .op-card-body { flex: 1; display: flex; flex-direction: column; justify-content: center; }' +
			'#ban-op-grid .op-card-body-table { padding: 0 !important; justify-content: flex-start; }' +
			'#ban-op-grid table.table { table-layout: fixed; width: 100%; }' +
			'#ban-op-grid table.table td { text-align: left !important; box-sizing: border-box; }' +
			'#ban-op-grid .op-col-key { width: 32% !important; max-width: 32% !important; min-width: 32% !important; font-weight: 600; text-align: left !important; word-break: break-word; }' +
			'#ban-op-grid .op-col-val { width: 68% !important; text-align: left !important; word-break: break-all; }' +
			'#ban-op-grid .op-full-key { width: 16% !important; max-width: 16% !important; min-width: 16% !important; font-weight: 600; text-align: left !important; word-break: break-word; }' +
			'#ban-op-grid .op-full-val { width: 84% !important; text-align: left !important; word-break: break-word; }' +
			'@media (max-width: 768px) { #ban-op-grid .op-full-key { width: 28% !important; min-width: 28% !important; } #ban-op-grid .op-full-val { width: 72% !important; } }'
		]);

		function ifRow(label, id, idx) {
			return E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((idx % 2) ? 2 : 1) }, [
				E('td', { 'class': 'td cbi-section-table-cell op-col-key' }, [label]),
				E('td', { 'class': 'td cbi-section-table-cell op-col-val', 'id': id }, ['-'])
			]);
		}

		viewNode = E('div', { 'class': 'cbi-map secbox-view secbox-view-split', 'id': 'ban-op-grid' }, [
			style,

			/* Panel 1: Header, Notice, Status & Rule Elements */
			E('div', { 'class': 'secbox-panel' }, [
				E('h2', { 'name': 'content' }, [
					_('SecBox Overview'),
					E('span', { 'id': 'secbox-service-badge', 'class': 'secbox-pill secbox-pill-muted', 'style': 'margin: 0;' }, ['-'])
				]),
				E('div', { 'class': 'cbi-map-descr' }, [
					_('Real-time runtime status, active sets and blocking statistics for the SecBox service.')
				]),
				E('div', { 'id': 'secbox-notice-slot' }),

				/* Row 1: Strict 2 Columns (Status & Metrics) */
				E('div', { 'class': 'op-grid-2' }, [
					/* 1. Status */
					E('div', { 'class': 'op-card', 'id': 'secbox-status-card' }, [
						E('div', { 'class': 'op-card-header' }, [_('Status')]),
						E('div', { 'class': 'op-card-body' }, [
							E('div', { 'style': 'display: flex; align-items: flex-start; justify-content: space-between; gap: 12px;' }, [
								E('div', {}, [
									E('div', { 'style': 'display: flex; align-items: center; gap: 8px; margin-bottom: 6px;' }, [
										E('span', { 'id': 'status-dot', 'class': 'secbox-dot secbox-dot-muted' }),
										E('span', { 'class': 'op-hero-val', 'id': 'state_text', 'style': 'margin-bottom: 0;' }, ['-'])
									]),
									E('div', { 'class': 'op-hero-sub' }, [
										_('Version'), ': ', E('span', { 'id': 'versions' }, ['-'])
									])
								]),
								E('button', {
									'id': 'btn-toggle-service',
									'class': isEnabled ? 'btn cbi-button cbi-button-reset' : 'btn cbi-button cbi-button-save',
									'style': 'margin: 0; flex-shrink: 0;',
									'click': ui.createHandlerFn(this, function () {
										return handleToggleService(!currentRunning, this._pollFn);
									})
								}, [isEnabled ? _('Stop Service') : _('Start Service')])
							]),
							E('div', { 'id': 'actual', 'style': 'margin-top: 10px;' }, ['-'])
						])
					]),

					/* 2. Statistics & Run Info */
					E('div', { 'class': 'op-card secbox-card-soft-info' }, [
						E('div', { 'class': 'op-card-header' }, [_('Rule Elements & Last Run')]),
						E('div', { 'class': 'op-card-body' }, [
							E('div', { 'style': 'display: flex; justify-content: space-between; align-items: baseline; flex-wrap: wrap; gap: 12px;' }, [
								E('div', {}, [
									E('div', { 'class': 'op-hero-val', 'id': 'elements_count' }, ['-']),
									E('div', { 'class': 'op-hero-sub', 'id': 'elements_sub' }, ['-'])
								]),
								E('div', { 'style': 'text-align: right;' }, [
									E('div', { 'style': 'font-weight: 700; font-size: 1.15em;', 'id': 'last_run_time' }, ['-']),
									E('div', { 'class': 'op-hero-sub', 'id': 'last_run_detail' }, ['-'])
								])
							])
						])
					])
				])
			]),

			/* Panel 2: NFT Info, Interfaces, System Info & Active Feeds */
			E('div', { 'class': 'secbox-panel' }, [

			/* Row 2: Strict 2 Columns (NFT Info & Interfaces) */
			E('div', { 'class': 'op-grid-2' }, [
				/* NFT Information */
				E('div', { 'class': 'op-card' }, [
					E('div', { 'class': 'op-card-header' }, [_('NFT Information')]),
					E('div', { 'class': 'op-card-body op-card-body-table' }, [
						E('table', { 'class': 'table cbi-section-table' }, [
							E('tbody', { 'id': 'nft_tbody' }, [
								E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
									E('td', { 'class': 'td cbi-section-table-cell op-col-key' }, ['-']),
									E('td', { 'class': 'td cbi-section-table-cell op-col-val' }, ['-'])
								])
							])
						])
					])
				]),

				/* Interfaces */
				E('div', { 'class': 'op-card' }, [
					E('div', { 'class': 'op-card-header' }, [_('Interfaces')]),
					E('div', { 'class': 'op-card-body op-card-body-table' }, [
						E('table', { 'class': 'table cbi-section-table' }, [
							ifRow(_('WAN Device'), 'wan_dev', 0),
							ifRow(_('WAN Interface'), 'wan_if', 1),
							ifRow(_('Allowed VLAN'), 'vlan_allow', 2),
							ifRow(_('Blocked VLAN'), 'vlan_block', 3),
							ifRow(_('Uplink IPv4'), 'uplink4', 4),
							ifRow(_('Uplink IPv6'), 'uplink6', 5)
						])
					])
				])
			])
			]),

			/* Panel 3: System Info */
			E('div', { 'class': 'secbox-panel' }, [
				/* Row 3: Full-Width Row (System Info) */
				E('div', { 'class': 'op-grid-1' }, [
					E('div', { 'class': 'op-card' }, [
						E('div', { 'class': 'op-card-header' }, [_('System Info')]),
						E('div', { 'class': 'op-card-body op-card-body-table' }, [
							E('table', { 'class': 'table cbi-section-table' }, [
								E('tbody', { 'id': 'sys_tbody' }, [
									E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
										E('td', { 'class': 'td cbi-section-table-cell op-full-key' }, ['-']),
										E('td', { 'class': 'td cbi-section-table-cell op-full-val' }, ['-'])
									])
								])
							])
						])
					])
				])
			]),

			/* Panel 4: Active Feeds & Flags */
			E('div', { 'class': 'secbox-panel' }, [
				/* Row 4: Full-Width Row (Active Feeds & Flags) */
				E('div', { 'class': 'op-grid-1' }, [
					E('div', { 'class': 'op-card' }, [
						E('div', { 'class': 'op-card-header' }, [_('Active Feeds & Flags')]),
						E('div', { 'class': 'op-card-body op-card-body-table' }, [
							E('table', { 'class': 'table cbi-section-table' }, [
								E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
									E('td', { 'class': 'td cbi-section-table-cell op-full-key' }, [_('Active Feeds')]),
									E('td', { 'class': 'td cbi-section-table-cell op-full-val', 'id': 'feeds_container' }, ['-'])
								]),
								E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-2' }, [
									E('td', { 'class': 'td cbi-section-table-cell op-full-key' }, [_('Run Flags')]),
									E('td', { 'class': 'td cbi-section-table-cell op-full-val', 'id': 'flags_container' }, ['-'])
								])
							])
						])
					])
				])
			])
		]);

		applyRuntime(loadResult[1], loadResult[2]);
		return viewNode;
	},

	unload: function () {
		if (this._pollFn) {
			poll.remove(this._pollFn);
			this._pollFn = null;
		}
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
