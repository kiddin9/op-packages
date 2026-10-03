'use strict';
'require view';
'require fs';
'require ui';
'require uci';

/*
	button handling
*/
function handleAction(report, ev) {
	if (ev === 'search') {
		const triggerSearch = function () {
			let searchInput = document.getElementById('search');
			let ip = searchInput ? searchInput.value.trim().toLowerCase() : '';

			if (ip) {
				window._lastSearchedIP = ip;
				document.getElementById('result').textContent = _('Search is running, please wait...');
				if (window._banipPoller) {
					clearInterval(window._banipPoller);
					window._banipPoller = null;
				}
				L.resolveDefault(fs.write('/var/run/banIP/banIP.search', ''), '').then(function () {
					L.resolveDefault(fs.exec_direct('/etc/init.d/banip', ['search', ip]), '').then(function () {
						let attempts = 0;
						window._banipPoller = setInterval(function () {
							attempts++;
							L.resolveDefault(fs.read('/var/run/banIP/banIP.search'), '').then(function (res) {
								if (res && res.trim()) {
									clearInterval(window._banipPoller);
									window._banipPoller = null;
									document.getElementById('result').textContent = res.trim();
								} else if (attempts >= 40) {
									clearInterval(window._banipPoller);
									window._banipPoller = null;
									document.getElementById('result').textContent = _('Search timed out.');
								}
							});
						}, 3000);
					});
				});
			}
		};

		const appendToList = function (targetFile, listName) {
			const ip = window._lastSearchedIP || (document.getElementById('search')?.value || '').trim();
			if (!ip) {
				ui.addNotification(null, E('p', _('Please enter or search an IP first.')), 'warning');
				return;
			}
			return L.resolveDefault(fs.read_direct(targetFile), '').then(function (cur) {
				const lines = cur.split('\n').map(l => l.trim());
				if (lines.includes(ip)) {
					ui.addNotification(null, E('p', _('IP "%s" is already in %s.').format(ip, listName)), 'info');
					return;
				}
				const newContent = (cur.trim() ? cur.trim() + '\n' : '') + ip + '\n';
				return fs.write(targetFile, newContent).then(function () {
					ui.addNotification(null, E('p', _('Successfully added "%s" to %s!').format(ip, listName)), 'info');
				});
			}).catch(function (e) {
				ui.addNotification(null, E('p', _('Failed to update list: %s').format(e.message)), 'error');
			});
		};

		ui.showModal(_('IP Search & Quick Action'), [
			E('p', _('Search the SecBox-related Sets for a specific IP and take quick actions.')),
			E('div', { 'class': 'left', 'style': 'display:flex; flex-direction:column; margin-bottom:.5em;' }, [
				E('label', { 'style': 'padding-top:.5em', 'id': 'run' }, [
					E('input', {
						'class': 'cbi-input-text',
						'placeholder': '192.168.0.1 or domain',
						'style': 'width:300px; padding: 4px 8px;',
						'spellcheck': 'false',
						'id': 'search',
						'keydown': function (e) {
							if (e.key === 'Enter') {
								e.preventDefault();
								triggerSearch();
							}
						}
					})
				])
			]),
			E('div', { 'class': 'left', 'style': 'display:flex; flex-direction:column' }, [
				E('h5', _('Result')),
				E('textarea', {
					'id': 'result',
					'style': 'width: 100% !important; margin-top:.5em; padding: 6px; font-family: monospace; font-size:12px; border-radius:4px;',
					'readonly': 'readonly',
					'wrap': 'off',
					'rows': 15
				})
			]),
			E('div', { 'style': 'display:flex; justify-content:space-between; align-items:center; margin-top:1em;' }, [
				E('div', {}, [
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'style': 'margin-right:.4em;',
						'click': ui.createHandlerFn(this, function () {
							return appendToList('/etc/banip/banip.allowlist', _('Allowlist'));
						})
					}, [_('+ Add to Allowlist')]),
					E('button', {
						'class': 'btn cbi-button cbi-button-negative',
						'click': ui.createHandlerFn(this, function () {
							return appendToList('/etc/banip/banip.blocklist', _('Blocklist'));
						})
					}, [_('+ Add to Blocklist')])
				]),
				E('div', {}, [
					E('button', {
						'class': 'btn cbi-button',
						'style': 'margin-right:.4em;',
						'click': ui.hideModal
					}, _('Close')),
					E('button', {
						'class': 'btn cbi-button-positive important',
						'click': ui.createHandlerFn(this, function () {
							triggerSearch();
						})
					}, _('Search IP'))
				])
			])
		]);
		document.getElementById('search').focus();
	}
	if (ev === 'content') {
		let content, selectOption;
		let errMsg = false;

		if (report[1]) {
			try {
				content = JSON.parse(report[1]);
			} catch (e) {
				content = "";
				if (!errMsg) {
					errMsg = true;
					return ui.addNotification(null, E('p', _('Unable to parse the ruleset file!')), 'error');
				}
			}
		} else {
			return;
		}
		selectOption = [E('option', { value: '' }, [_('-- Set Selection --')])];
		Object.keys(content.nftables)
			.filter(key => content.nftables[key].set?.name && content.nftables[key].set.table === 'SecBox')
			.sort((a, b) => content.nftables[a].set.name.localeCompare(content.nftables[b].set.name))
			.forEach(key => {
				selectOption.push(E('option', { 'value': content.nftables[key].set.name }, content.nftables[key].set.name));
			});
		ui.showModal(_('Set Content'), [
			E('p', _('List the elements of a specific SecBox-related Set.')),
			E('div', { 'class': 'left', 'style': 'display:flex; flex-direction:column' }, [
				E('label', { 'class': 'cbi-input-select', 'style': 'padding-top:.5em', 'id': 'run' }, [
					E('h5', _('Set')),
					E('select', { 'class': 'cbi-input-select', 'id': 'set' },
						selectOption
					)
				]),
			]),
			E('div', { 'class': 'left', 'style': 'display:flex; flex-direction:column' }, [
				E('label', { 'class': 'cbi-checkbox', 'style': 'padding-top:.5em' }, [
					E('input', {
						'class': 'cbi-checkbox',
						'data-update': 'click change',
						'type': 'checkbox',
						'id': 'chkFilter',
						'disabled': 'disabled',
						'value': 'true'
					}),
					E('span', { 'style': 'margin-left: .5em;' }, _('Show only Set elements with hits'))
				]),
			]),
			E('div', { 'class': 'left', 'style': 'display:flex; flex-direction:column' }, [
				E('h5', _('Result')),
				E('textarea', {
					'id': 'result',
					'style': 'width: 100% !important; margin-top:.5em; padding: 5px; font-family: monospace',
					'readonly': 'readonly',
					'wrap': 'off',
					'rows': 20
				})
			]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn cbi-button',
					'style': 'float:none; margin-right:.4em;',
					'click': ui.hideModal
				}, _('Cancel')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action',
					'click': ui.createHandlerFn(this, function (ev) {
						const checkbox = document.getElementById('chkFilter');
						const isChecked = checkbox.checked ? 'true' : 'false';
						let set = document.getElementById('set').value;
						if (set) {
							document.getElementById('result').textContent = 'Collecting Set content, please wait...';
							return L.resolveDefault(fs.exec_direct('/etc/init.d/banip', ['content', set, isChecked]), '').then(function (res) {
								let result = document.getElementById('result');
								result.textContent = res ? res.trim() : _('Network error');
								document.getElementById('set').value = '';
							});
						}
						document.getElementById('set').focus();
					})
				}, _('Show Content'))
			])
		]);
		if (uci.get('banip', 'global', 'ban_nftcount') === '1') {
			const chk = document.querySelector('#chkFilter');
			if (chk) {
				chk.removeAttribute('disabled');
			}
		}
		document.getElementById('set').focus();
	}
	if (ev === 'map') {
		const modal = ui.showModal(null, [
			E('div', {
				id: 'mapModal',
				style: 'position: relative;'
			}, [
				E('iframe', {
					id: 'mapFrame',
					src: L.resource('view/secbox/map.html'),
					style: 'width: 100%; height: 80vh; border: none;'
				}),
			]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn cbi-button',
					'click': ui.createHandlerFn(this, function (ev) {
						ui.hideModal();
						sessionStorage.clear();
						location.reload();
					})
				}, _('Cancel')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action',
					'click': ui.createHandlerFn(this, function (ev) {
						let iframe = document.getElementById('mapFrame');
						iframe.contentWindow.location.reload();
					})
				}, _('Map Reset'))
			])
		]);
		modal.style.maxWidth = '90%';
		document.getElementById('mapModal').focus();
	}
}

return view.extend({
	load: function () {
		return Promise.all([
			L.resolveDefault(fs.exec_direct('/etc/init.d/banip', ['report', 'json']), '')
				.then(function (res) {
					if (res && res.trim()) return res;
					return L.resolveDefault(fs.read_direct('/tmp/banIP-report/ban_report.jsn'), '')
						.then(function (r) {
							if (r && r.trim()) {
								return L.resolveDefault(fs.read_direct('/tmp/banIP-report/ban_map.jsn'), '[]')
									.then(function (m) {
										let rObj = JSON.parse(r);
										let mObj = JSON.parse(m);
										return JSON.stringify([rObj[0] || rObj, mObj]);
									}).catch(() => r);
							}
							return '';
						});
				}),
			L.resolveDefault(fs.exec_direct('/usr/sbin/nft', ['-tj', 'list', 'sets']), ''),
			uci.load('banip')
		]);
	},

	render: function (report) {
		let content = [], rowSets, tblSets, notMsg;

		if (report) {
			try {
				content = JSON.parse(report[0]);
			} catch (e) {
				content[0] = "";
			}
		} else {
			content[0] = "";
		}

		function fmtCount(value) {
			const text = String(value ?? '').trim();
			if (!/^\d+$/.test(text)) {
				return text || '-';
			}
			return text.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
		}

		function hitStats(sets) {
			const stats = { 'sets': 0, 'counted': 0, 'total': 0, 'hits': [], 'worst': [] };

			Object.keys(sets || {}).forEach(function (key) {
				const set = sets[key];
				stats.sets++;
				if (`${set.cnt_inbound ?? ''}${set.cnt_outbound ?? ''}` === '') {
					return;
				}
				const count = (parseInt(set.cnt_inbound, 10) || 0) + (parseInt(set.cnt_outbound, 10) || 0);
				const elements = parseInt(String(set.cnt_elements).replace(/\D/g, ''), 10) || 0;
				stats.counted++;
				stats.total += count;
				if (count > 0) {
					stats.hits.push({ 'name': key, 'elements': elements, 'hits': count, 'value': count });
				}
				stats.worst.push({ 'name': key, 'elements': elements, 'hits': count, 'value': elements });
			});
			stats.hits.sort(function (a, b) { return b.value - a.value; });
			stats.worst.sort(function (a, b) { return (a.hits - b.hits) || (b.value - a.value); });
			return stats;
		}

		function dirNode(direction, count, bold) {
			const attrs = bold ? { 'style': 'font-weight: bold; text-align: left !important; word-break: break-all;' } : { 'style': 'text-align: left !important; word-break: break-all;' };
			if (!count) {
				return E('em', attrs, [direction]);
			}
			return E('em', attrs, [
				direction, bold ? ' (' : ': (',
				fmtCount(count),
				')'
			]);
		}

		rowSets = [];
		tblSets = E('table', { 'class': 'table cbi-section-table', 'id': 'sets', 'style': 'table-layout: fixed; width: 100%; word-break: break-all;' }, [
			E('tr', { 'class': 'tr cbi-section-table-titles' }, [
				E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 15%; text-align: left !important;' }, [_('Set')]),
				E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 10%; text-align: left !important;' }, [_('Count')]),
				E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 12%; text-align: left !important;' }, [_('Inbound&#160;(packets)')]),
				E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 12%; text-align: left !important;' }, [_('Outbound&#160;(packets)')]),
				E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 13%; text-align: left !important;' }, [_('Port&#160;/&#160;Protocol')]),
				E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 38%; text-align: left !important;' }, [_('Elements (max. 50)')])
			])
		]);

		if (content[0].sets) {
			Object.keys(content[0].sets).sort().forEach(function (key, idx) {
				rowSets.push([
					E('em', { 'style': 'text-align: left !important; word-break: break-all;' }, key),
					E('em', { 'style': 'text-align: left !important;' }, fmtCount(content[0].sets[key].cnt_elements)),
					dirNode(content[0].sets[key].inbound, content[0].sets[key].cnt_inbound, false),
					dirNode(content[0].sets[key].outbound, content[0].sets[key].cnt_outbound, false),
					E('em', { 'style': 'text-align: left !important;' }, content[0].sets[key].port),
					E('em', { 'style': 'text-align: left !important; word-break: break-all; white-space: normal; display: block; overflow-wrap: anywhere;' }, content[0].sets[key].set_elements.join(", "))
				]);
			});
			rowSets.push([
				E('em', { 'style': 'font-weight: bold; text-align: left !important; word-break: break-all;' }, content[0].sum_sets),
				E('em', { 'style': 'font-weight: bold; text-align: left !important;' }, fmtCount(content[0].sum_cntelements)),
				dirNode(content[0].sum_setinbound, content[0].sum_cntinbound, true),
				dirNode(content[0].sum_setoutbound, content[0].sum_cntoutbound, true),
				E('em', { 'style': 'font-weight: bold; text-align: left !important;' }, content[0].sum_setports),
				E('em', { 'style': 'font-weight: bold; text-align: left !important; word-break: break-all;' }, content[0].sum_setelements)
			]);
		}
		cbi_update_table(tblSets, rowSets);

		const sum = content?.[0] || {};
		const hits = hitStats(sum.sets);

		function renderStatRow(label, val, idx) {
			return E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((idx % 2) ? 2 : 1) }, [
				E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 55% !important; max-width: 55% !important; min-width: 55% !important; text-align: left !important; font-weight: 600;' }, [label]),
				E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 45% !important; text-align: left !important; font-weight: bold;' }, [fmtCount(val)])
			]);
		}

		function renderTopCard(title, list) {
			const rows = list.slice(0, 10).map(function (item, index) {
				return E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-' + ((index % 2) ? 2 : 1) }, [
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 50% !important; text-align: left !important; font-family: monospace; word-break: break-all;' }, [item.name]),
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; text-align: left !important;' }, [fmtCount(item.elements)]),
					E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; text-align: left !important; font-weight: bold;' }, [fmtCount(item.hits)])
				]);
			});

			return E('div', { 'class': 'op-card' }, [
				E('div', { 'class': 'op-card-header' }, [title]),
				E('div', { 'class': 'op-card-body', 'style': 'padding: 0;' }, [
					E('table', { 'class': 'table cbi-section-table', 'style': 'table-layout: fixed; width: 100%;' }, [
						E('tr', { 'class': 'tr cbi-section-table-titles' }, [
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 50% !important; text-align: left !important;' }, [_('Set')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 25% !important; text-align: left !important;' }, [_('Elements')]),
							E('th', { 'class': 'th cbi-section-table-cell', 'style': 'width: 25% !important; text-align: left !important;' }, [_('Hits')])
						]),
						E('tbody', {}, rows.length ? rows : [
							E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
								E('td', { 'colspan': 3, 'class': 'td cbi-section-table-cell', 'style': 'text-align: left !important; color: #888;' }, ['-'])
							])
						])
					])
				])
			]);
		}

		const style = E('style', { 'type': 'text/css' }, [
			'#ban-report-grid .op-grid-2 { display: grid; gap: 1em; grid-template-columns: repeat(2, 1fr); margin-bottom: 1em; align-items: stretch; }' +
			'@media (max-width: 900px) { #ban-report-grid .op-grid-2 { grid-template-columns: 1fr; } }' +
			'#ban-report-grid .op-grid-1 { margin-bottom: 1em; width: 100%; }' +
			'#ban-report-grid .op-card { background: var(--cbi-section-bg, #fff); border: 1px solid var(--cbi-border-color, #e5e7eb); border-radius: 6px; overflow: hidden; display: flex; flex-direction: column; height: 100%; box-sizing: border-box; }' +
			'#ban-report-grid .op-card-header { background: rgba(0, 0, 0, 0.025); min-height: 2.85em; height: 2.85em; padding: 0 1em; box-sizing: border-box; border-bottom: 1px solid var(--cbi-border-color, #e5e7eb); font-weight: 700; font-size: 1.02em; display: flex; align-items: center; justify-content: space-between; flex-shrink: 0; }' +
			'#ban-report-grid .op-card-body { padding: .85em 1em; flex: 1; display: flex; flex-direction: column; justify-content: center; }' +
			'#ban-report-grid .op-card-body-table { padding: 0 !important; justify-content: flex-start; }' +
			'#ban-report-grid table.table { width: 100%; border-collapse: separate; border-spacing: 0; table-layout: fixed; margin: 0; }' +
			'#ban-report-grid table.table td { padding: .5em .85em; text-align: left !important; font-size: .95em; vertical-align: middle; }' +
			'@media (prefers-color-scheme: dark) {' +
			'#ban-report-grid .op-card { background: rgba(255, 255, 255, 0.03); border-color: rgba(255, 255, 255, 0.12); }' +
			'#ban-report-grid .op-card-header { background: rgba(255, 255, 255, 0.05); border-color: rgba(255, 255, 255, 0.12); }' +
			'}'
		]);

		const page = E('div', { 'class': 'cbi-map', 'id': 'ban-report-grid' }, [
			style,
			E('h2', { 'name': 'content' }, [_('SecBox Set Reporting')]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('This report shows the latest NFT Set statistics, press the \'Refresh\' button to get a new one. \
				You can also display the specific content of Sets, search for suspicious IPs and finally, these IPs can also be displayed on a map.')
			]),

			/* Row 1: Strict 2 Columns (Summary Overview & Auto-added) */
			E('div', { 'class': 'op-grid-2' }, [
				/* Overview */
				E('div', { 'class': 'op-card' }, [
					E('div', { 'class': 'op-card-header' }, [_('Set Overview')]),
					E('div', { 'class': 'op-card-body op-card-body-table' }, [
						E('table', { 'class': 'table cbi-section-table' }, [
							renderStatRow(_('Sets'), sum.sum_sets, 0),
							renderStatRow(_('Elements'), sum.sum_cntelements, 1),
							renderStatRow(_('Timestamp'), sum.timestamp || '-', 2)
						])
					])
				]),

				/* Auto-added IPs */
				E('div', { 'class': 'op-card' }, [
					E('div', { 'class': 'op-card-header' }, [_('Auto-added IPs')]),
					E('div', { 'class': 'op-card-body op-card-body-table' }, [
						E('table', { 'class': 'table cbi-section-table' }, [
							renderStatRow(_('Auto-added to Allowlist'), sum.autoadd_allow, 0),
							renderStatRow(_('Auto-added to Blocklist'), sum.autoadd_block, 1)
						])
					])
				])
			]),

			/* Row 2: Strict Full-Width (Blocked Packets 6 Metrics in 1 Full Card) */
			E('div', { 'class': 'op-grid-1' }, [
				E('div', { 'class': 'op-card' }, [
					E('div', { 'class': 'op-card-header' }, [_('Blocked Packets')]),
					E('div', { 'class': 'op-card-body op-card-body-table' }, [
						E('table', { 'class': 'table cbi-section-table', 'style': 'table-layout: fixed; width: 100%;' }, [
							E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: 600;' }, [_('syn-flood')]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: bold;' }, [fmtCount(sum.sum_synflood)]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: 600;' }, [_('invalid ct')]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: bold;' }, [fmtCount(sum.sum_ctinvalid)])
							]),
							E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-2' }, [
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: 600;' }, [_('udp-flood')]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: bold;' }, [fmtCount(sum.sum_udpflood)]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: 600;' }, [_('invalid tcp')]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: bold;' }, [fmtCount(sum.sum_tcpinvalid)])
							]),
							E('tr', { 'class': 'tr cbi-section-table-row cbi-rowstyle-1' }, [
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: 600;' }, [_('icmp-flood')]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: bold;' }, [fmtCount(sum.sum_icmpflood)]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: 600;' }, [_('bcp38')]),
								E('td', { 'class': 'td cbi-section-table-cell', 'style': 'width: 25% !important; font-weight: bold;' }, [fmtCount(sum.sum_bcp38)])
							])
						])
					])
				])
			]),

			/* Row 3: Single Row Full-Width (Top Sets) */
			E('div', { 'class': 'op-grid-1' }, [
				renderTopCard(_('Top Sets (Most Hits)'), hits.hits)
			]),

			/* Row 4: Single Row Full-Width (Worst Sets) */
			E('div', { 'class': 'op-grid-1' }, [
				renderTopCard(_('Worst Sets (Least Hits)'), hits.worst)
			]),

			/* Bottom Full-Width Table */
			E('div', { 'class': 'cbi-section', 'style': 'overflow-x: auto;' }, [
				E('h3', _('Set details')),
				E('div', { 'class': 'cbi-section-node' }, [
					tblSets
				])
			]),

			/* Actions */
			E('div', { 'class': 'cbi-page-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': function () {
						const btn = this;
						document.querySelectorAll('.cbi-page-actions button').forEach(function (b) {
							b.disabled = true;
						});
						btn.blur();
						btn.classList.add('spinning');
						L.resolveDefault(fs.write('/var/run/banIP/banIP.report', ''), '').then(function () {
							L.resolveDefault(fs.exec_direct('/etc/init.d/banip', ['report', 'gen']), '');
							let attempts = 0;
							let poller = setInterval(function () {
								L.resolveDefault(fs.read('/var/run/banIP/banIP.report'), '').then(function (res) {
									res = (res || '').trim();
									if (res === '1') {
										clearInterval(poller);
										location.reload();
									} else if (res === '0') {
										// polling
									} else {
										attempts++;
										if (attempts >= 10) {
											clearInterval(poller);
											btn.classList.remove('spinning');
											document.querySelectorAll('.cbi-page-actions button').forEach(function (b) {
												b.disabled = false;
											});
											ui.addNotification(null, E('p', _('Failed to generate a SecBox report!')), 'error');
										}
									}
								});
							}, 3000);
						});
					}
				}, [_('Refresh')]),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function () {
						return handleAction(report, 'search');
					})
				}, [_('IP Search...')]),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function () {
						return handleAction(report, 'content');
					})
				}, [_('Set Content...')]),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'id': 'btnMap',
					'disabled': 'disabled',
					'click': ui.createHandlerFn(this, function () {
						if (Array.isArray(content[1]) && content[1].length > 1) {
							sessionStorage.setItem('mapData', JSON.stringify(content[1]));
							return handleAction(report, 'map');
						} else {
							if (!notMsg) {
								notMsg = true;
								return ui.addNotification(null, E('p', _('No GeoIP Map data!')), 'info');
							}
						}
					})
				}, [_('Map...')])
			])
		]);

		if (uci.get('banip', 'global', 'ban_nftcount') === '1'
			&& uci.get('banip', 'global', 'ban_map') === '1'
			&& (uci.get('banip', 'global', 'ban_allowlistonly') !== '1'
				|| (uci.get('banip', 'global', 'ban_feedin') || "").includes("allowlist")
				|| (uci.get('banip', 'global', 'ban_feedout') || "").includes("allowlist"))) {
			const btn = page.querySelector('#btnMap');
			if (btn) {
				btn.removeAttribute('disabled');
			}
		}
		return page;
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
