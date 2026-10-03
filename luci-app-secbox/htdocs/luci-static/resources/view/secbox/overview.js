'use strict';
'require dom';
'require view';
'require poll';
'require fs';
'require ui';
'require uci';

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

function handleToggleService(enable) {
	const action = enable ? 'start' : 'stop';
	const title = enable ? _('Enabling and starting SecBox service...') : _('Stopping and disabling SecBox service...');
	ui.showIndicator('banip-action', title);
	return uci.load('banip').then(function () {
		uci.set('banip', 'global', 'ban_enabled', enable ? '1' : '0');
		return uci.save();
	}).then(function () {
		return uci.apply();
	}).then(function () {
		return fs.exec_direct('/etc/init.d/banip', [enable ? 'restart' : 'stop']);
	}).then(function () {
		ui.hideIndicator('banip-action');
		ui.addNotification(null, E('p', enable ? _('SecBox service enabled and started.') : _('SecBox service stopped and disabled.')), 'info');
		setTimeout(function () {
			location.reload();
		}, 1000);
	}).catch(function (e) {
		ui.hideIndicator('banip-action');
		ui.addNotification(null, E('p', _('Failed to update service status: %s').format(e.message)), 'error');
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
	if (!pairs.length) return ['-'];
	return pairs.map(function (flag) {
		const on = flag[1] === '\u2714';
		return E('span', {
			'style': 'display: inline-block; margin: 0 .4em .35em 0; padding: .2em .55em; border-radius: 4px; font-size: .88em; white-space: nowrap;' +
				(on ? 'background: rgba(16, 185, 129, 0.15); color: #059669; border: 1px solid rgba(16, 185, 129, 0.3);' : 'background: rgba(0, 0, 0, 0.05); color: #64748b; border: 1px solid rgba(0, 0, 0, 0.1);')
		}, [
			(on ? '\u2714 ' : '\u2718 ') + flag[0]
		]);
	});
}

function feedChips(feeds) {
	const chips = (Array.isArray(feeds) ? feeds : []).filter(f => f && f !== '-');
	if (!chips.length) return ['-'];
	return chips.map(function (feed) {
		return E('span', {
			'style': 'display: inline-block; margin: 0 .4em .35em 0; padding: .2em .55em; border-radius: 4px; font-size: .88em; white-space: nowrap; background: rgba(37, 99, 235, 0.1); color: #2563eb; border: 1px solid rgba(37, 99, 235, 0.25);'
		}, [feed]);
	});
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
	'table': _('Table'),
	'priority': _('Priority'),
	'policy': _('Policy'),
	'proto 4': _('IPv4 Protocol'),
	'proto 6': _('IPv6 Protocol'),
	'limit icmp': _('ICMP Limit'),
	'limit syn': _('SYN Limit'),
	'limit udp': _('UDP Limit'),
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
	'error': _('Error'),
	'stopped': _('Stopped'),
	'not running': _('Not Running')
};

return view.extend({
	load: function () {
		return Promise.all([
			uci.load('banip').catch(() => 0),
			L.resolveDefault(fs.stat('/var/run/banIP/banIP.runtime.json'), null)
		]);
	},

	render: function (loadResult) {
		let isEnabled = (uci.get('banip', 'global', 'ban_enabled') === '1');

		const setNodes = (id, nodes) => {
			const el = document.getElementById(id);
			if (el) dom.content(el, nodes);
		};

		const setText = (id, value) => {
			const el = document.getElementById(id);
			if (el) el.textContent = value || '-';
		};

		/*
			poll runtime information
		*/
		let parseErrCount = 0;
		poll.add(function () {
			return L.resolveDefault(fs.stat('/var/run/banIP/banIP.runtime.json'), null).then(function (stat) {
				if (!stat) return;
				return Promise.all([
					L.resolveDefault(fs.read_direct('/var/run/banIP/banIP.runtime.json'), 'null'),
					L.resolveDefault(fs.exec_direct('/etc/init.d/banip', ['actual']), '')
				]).then(function (results) {
					const res = results[0];
					const actual = results[1]?.trim() || '';
					const toggleBtn = document.getElementById('btn-toggle-service');
					const dotEl = document.getElementById('status-dot');
					let info = null;
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
					if (info) {
						const rawState = info.status || '-';
						const isRunning = (rawState === 'active' || rawState === 'processing');
						setText('state_text', stateMap[rawState] || rawState);
						setText('versions', `${info.frontend_ver || '-'} / ${info.backend_ver || '-'}`);
						setNodes('actual', actual ? flagChips(actual) : ['-']);

						if (dotEl) {
							if (rawState === 'active') {
								dotEl.style.background = '#10b981';
								dotEl.style.boxShadow = '0 0 6px #10b981';
							} else if (rawState === 'processing') {
								dotEl.style.background = '#3b82f6';
								dotEl.style.boxShadow = 'none';
							} else if (rawState === 'error') {
								dotEl.style.background = '#ef4444';
								dotEl.style.boxShadow = 'none';
							} else {
								dotEl.style.background = '#94a3b8';
								dotEl.style.boxShadow = 'none';
							}
						}

						if (toggleBtn) {
							if (isRunning) {
								toggleBtn.textContent = _('Stop Service');
								toggleBtn.className = 'btn cbi-button cbi-button-reset';
							} else {
								toggleBtn.textContent = _('Start Service');
								toggleBtn.className = 'btn cbi-button cbi-button-save';
							}
						}

						const elements = splitCount(info.element_count);
						const runPairs = parsePairs(info.last_run);
						const join = list => (Array.isArray(list) && list.length) ? list.join(', ') : '-';

						setText('elements_count', elements.count);
						setText('elements_sub', elements.detail !== '-' ? elements.detail : '');
						setText('last_run_time', pickValue(runPairs, 'date / time'));
						setText('last_run_detail', [pickValue(runPairs, 'mode'), pickValue(runPairs, 'duration'), pickValue(runPairs, 'memory')].filter(v => v && v !== '-').join(', '));

						setText('wan_dev', join(info.wan_devices));
						setText('wan_if', join(info.wan_interfaces));
						setText('vlan_allow', join(info.vlan_allow));
						setText('vlan_block', join(info.vlan_block));

						const uplinks = splitUplinks(info.active_uplink);
						setText('uplink4', uplinks.v4);
						setText('uplink6', uplinks.v6);

						// Render NFT pairs
						const nftPairs = expandPairs(parsePairs(info.nft_info));
						const nftNodes = [];
						nftPairs.forEach((p, idx) => {
							if (p[0]) {
								const k = keyMap[p[0].trim()] || p[0].trim();
								nftNodes.push(E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((idx % 2) ? 2 : 1) }, [
									E('td', { 'class': 'td cbi-section-table-cell op-col-key' }, [k]),
									E('td', { 'class': 'td cbi-section-table-cell op-col-val', 'style': 'font-family: monospace;' }, [p[1]])
								]));
							}
						});
						setNodes('nft_tbody', nftNodes.length ? nftNodes : [
							E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
								E('td', { 'class': 'td cbi-section-table-cell op-col-key' }, ['-']),
								E('td', { 'class': 'td cbi-section-table-cell op-col-val' }, ['-'])
							])
						]);

						// System Info (Full-width row, 16% key : 84% val)
						const sysList = sysPairs(info.system_info);
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
									E('td', { 'colspan': 2, 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important; color: #64748b; padding-left: .85em;' }, [p[1]])
								]));
							}
						});
						setNodes('sys_tbody', sysNodes.length ? sysNodes : [
							E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
								E('td', { 'class': 'td cbi-section-table-cell op-full-key' }, ['-']),
								E('td', { 'class': 'td cbi-section-table-cell op-full-val' }, ['-'])
							])
						]);

						setNodes('feeds_container', feedChips(info.active_feeds));
						setNodes('flags_container', flagChips(info.run_flags));
					}
				});
			});
		}, 3);

		const style = E('style', { 'type': 'text/css' }, [
			'#ban-op-grid .op-grid-2 { display: grid; gap: 1em; grid-template-columns: repeat(2, 1fr); margin-bottom: 1em; align-items: stretch; }' +
			'@media (max-width: 900px) { #ban-op-grid .op-grid-2 { grid-template-columns: 1fr; } }' +
			'#ban-op-grid .op-grid-1 { margin-bottom: 1em; width: 100%; }' +
			'#ban-op-grid .op-card { background: var(--cbi-section-bg, #fff); border: 1px solid var(--cbi-border-color, #e5e7eb); border-radius: 6px; overflow: hidden; display: flex; flex-direction: column; height: 100%; box-sizing: border-box; }' +
			'#ban-op-grid .op-card-header { background: rgba(0, 0, 0, 0.025); min-height: 2.85em; height: 2.85em; padding: 0 1em; box-sizing: border-box; border-bottom: 1px solid var(--cbi-border-color, #e5e7eb); font-weight: 700; font-size: 1.02em; display: flex; align-items: center; justify-content: space-between; flex-shrink: 0; }' +
			'#ban-op-grid .op-card-body { padding: .85em 1em; flex: 1; display: flex; flex-direction: column; justify-content: center; }' +
			'#ban-op-grid .op-card-body-table { padding: 0 !important; justify-content: flex-start; }' +
			'#ban-op-grid .op-hero-val { font-size: 1.65em; font-weight: 700; line-height: 1.25; margin-bottom: .2em; }' +
			'#ban-op-grid .op-hero-sub { font-size: .88em; color: #64748b; }' +
			'#ban-op-grid table.table { width: 100%; border-collapse: separate; border-spacing: 0; table-layout: fixed; margin: 0; }' +
			'#ban-op-grid table.table td { padding: .5em .85em; text-align: left !important; font-size: .95em; vertical-align: middle; }' +
			'#ban-op-grid .op-col-key { width: 32% !important; max-width: 32% !important; min-width: 32% !important; font-weight: 600; text-align: left !important; word-break: break-word; }' +
			'#ban-op-grid .op-col-val { width: 68% !important; text-align: left !important; word-break: break-all; }' +
			'#ban-op-grid .op-full-key { width: 16% !important; max-width: 16% !important; min-width: 16% !important; font-weight: 600; text-align: left !important; word-break: break-word; }' +
			'#ban-op-grid .op-full-val { width: 84% !important; text-align: left !important; word-break: break-word; }' +
			'@media (max-width: 768px) { #ban-op-grid .op-full-key { width: 28% !important; min-width: 28% !important; } #ban-op-grid .op-full-val { width: 72% !important; } }' +
			'@media (prefers-color-scheme: dark) {' +
			'#ban-op-grid .op-card { background: rgba(255, 255, 255, 0.03); border-color: rgba(255, 255, 255, 0.12); }' +
			'#ban-op-grid .op-card-header { background: rgba(255, 255, 255, 0.05); border-color: rgba(255, 255, 255, 0.12); }' +
			'}'
		]);

		function ifRow(label, id, idx) {
			return E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((idx % 2) ? 2 : 1) }, [
				E('td', { 'class': 'td cbi-section-table-cell op-col-key' }, [label]),
				E('td', { 'class': 'td cbi-section-table-cell op-col-val', 'id': id }, ['-'])
			]);
		}

		return E('div', { 'class': 'cbi-map', 'id': 'ban-op-grid' }, [
			style,
			E('h2', { 'name': 'content' }, [_('SecBox Overview')]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Real-time runtime status, active sets and blocking statistics for the SecBox service.')
			]),

			/* Row 1: Strict 2 Columns (Status & Metrics) */
			E('div', { 'class': 'op-grid-2' }, [
				/* 1. Status */
				E('div', { 'class': 'op-card' }, [
					E('div', { 'class': 'op-card-header' }, [
						_('Status'),
						E('button', {
							'id': 'btn-toggle-service',
							'class': isEnabled ? 'btn cbi-button cbi-button-reset' : 'btn cbi-button cbi-button-save',
							'style': 'padding: .2em .65em; font-size: .88em; margin: 0;',
							'click': ui.createHandlerFn(this, function () {
								return handleToggleService(!isEnabled);
							})
						}, [isEnabled ? _('Stop Service') : _('Start Service')])
					]),
					E('div', { 'class': 'op-card-body' }, [
						E('div', { 'style': 'display: flex; align-items: center; gap: .5em; margin-bottom: .3em;' }, [
							E('span', { 'id': 'status-dot', 'style': 'width: .75em; height: .75em; border-radius: 50%; background: #94a3b8; display: inline-block;' }),
							E('span', { 'class': 'op-hero-val', 'id': 'state_text', 'style': 'margin-bottom: 0;' }, ['-'])
						]),
						E('div', { 'class': 'op-hero-sub' }, [
							_('Version'), ': ', E('span', { 'id': 'versions' }, ['-'])
						]),
						E('div', { 'id': 'actual', 'style': 'margin-top: .5em;' }, ['-'])
					])
				]),

				/* 2. Statistics & Run Info */
				E('div', { 'class': 'op-card' }, [
					E('div', { 'class': 'op-card-header' }, [_('Rule Elements & Last Run')]),
					E('div', { 'class': 'op-card-body' }, [
						E('div', { 'style': 'display: flex; justify-content: space-between; align-items: baseline;' }, [
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
			]),

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
			]),

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
			]),

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
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
