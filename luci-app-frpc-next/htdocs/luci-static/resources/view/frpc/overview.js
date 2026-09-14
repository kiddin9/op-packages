'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

const callFrpcStatus = rpc.declare({
	object: 'luci.frpc',
	method: 'get_status'
});

const callAdoptProcess = rpc.declare({
	object: 'luci.frpc',
	method: 'adopt_process'
});

const callServiceAction = rpc.declare({
	object: 'luci.frpc',
	method: 'service_action',
	params: [ 'action' ]
});

const callRuntimeInfo = rpc.declare({
	object: 'luci.frpc',
	method: 'get_runtime_info'
});

function renderState(status) {
	let text = _('Unknown');
	let color = '#999';

	if (status.state === 'managed') {
		text = _('Running');
		color = 'green';
	} else if (status.state === 'unmanaged') {
		text = _('Running (Unmanaged)');
		color = 'orange';
	} else if (status.state === 'stopped') {
		text = _('Stopped');
		color = 'red';
	}

	if (status.pid)
		text += ' [PID: ' + status.pid + ']';

	return { text, color };
}

function flattenProxies(statusObj) {
	const rows = [];
	if (!statusObj || typeof statusObj !== 'object')
		return rows;

	Object.keys(statusObj).forEach((ptype) => {
		const arr = statusObj[ptype];
		if (!Array.isArray(arr))
			return;
		arr.forEach((p) => {
			if (!p || typeof p !== 'object')
				return;
			rows.push({
				name: p.name || '-',
				type: p.type || ptype || '-',
				status: p.status || '-',
				local: p.local_addr || '-',
				remote: p.remote_addr || '-',
				err: p.err || ''
			});
		});
	});

	return rows;
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return Promise.all([ callFrpcStatus(), callRuntimeInfo() ]);
	},

	render: function(data) {
		const status = data && data[0] ? data[0] : {};
		const runtime = data && data[1] ? data[1] : {};
		const stateInfo = renderState(status || {});

		const container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Frp Client Title') + ' - ' + _('Overview')),
			E('div', { 'class': 'cbi-map-descr' }, _('Overview of the local frpc service state, active process PID, loaded config files, and detailed online proxy information.'))
		]);

		// Service Status Section (Aligned with lucky style)
		const statusSection = E('fieldset', { 'class': 'cbi-section' }, [
			E('legend', {}, _('Service Status')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '33%' }, _('Current Status')),
						E('td', { 'class': 'td left' }, [
							E('span', { id: 'frpc-status-text', 'style': 'font-weight:bold; color:' + stateInfo.color + '; margin-right:10px;' }, stateInfo.text),
							E('button', {
								id: 'frpc-restart-btn',
								'class': 'btn cbi-button cbi-button-apply',
								'style': 'display:' + ((status.state === 'managed' || status.state === 'unmanaged') ? 'inline-block' : 'none') + ';',
								click: ui.createHandlerFn(this, function(ev) {
									if (!ev || !ev.currentTarget) return;
									const btn = ev.currentTarget;
									btn.disabled = true;
									ui.addNotification(null, E('p', _('Restarting FRP Client, please wait...')), 'info');
									return callServiceAction('restart').then(function(res) {
										btn.disabled = false;
										if (res && res.success) {
											ui.addNotification(null, E('p', _('Service restarted successfully.')), 'info');
										} else {
											ui.addNotification(null, E('p', _('Failed to restart service.')), 'error');
										}
									}).catch(function(err) {
										btn.disabled = false;
										ui.addNotification(null, E('p', _('An error occurred: ') + err.message), 'error');
									});
								})
							}, _('Restart'))
						])
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Generated Runtime Config')),
						E('td', { 'class': 'td left', id: 'frpc-runtime-config' }, status.runtime_config || '-')
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Configured Proxies')),
						E('td', { 'class': 'td left', id: 'frpc-proxy-count' }, String(status.proxy_count || 0))
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('frpc Version')),
						E('td', { 'class': 'td left', id: 'frpc-version' }, status.version || '-')
					])
				])
			])
		]);
		container.appendChild(statusSection);

		const proxyRows = flattenProxies(runtime.status);
		const runtimeSection = E('fieldset', {
			'class': 'cbi-section',
			id: 'frpc-runtime-section',
			style: (status.state === 'managed') ? '' : 'display:none'
		}, [
			E('legend', {}, _('Runtime Details')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '33%' }, _('Web Panel')),
						E('td', { 'class': 'td left' }, [
							E('span', { id: 'frpc-web-api' }, [
								runtime.web_url ? E('a', {
									'class': 'btn cbi-button',
									href: runtime.web_url,
									target: '_blank',
									rel: 'noopener noreferrer'
								}, _('Open')) : '-'
							])
						])
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Connected Server')),
						E('td', { 'class': 'td left' }, [
							E('span', { id: 'frpc-connected-server' }, (runtime.server_addr && runtime.server_port) ? (runtime.server_addr + ':' + runtime.server_port) : '-'),
							E('div', { 'class': 'cbi-value-description', style: 'margin: 4px 0 0 0;' }, _('Connect to FRP server'))
						])
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Proxy Runtime List')),
						E('td', { 'class': 'td left' }, [
							E('div', { 'class': 'cbi-value-description', style: 'margin: 0 0 6px 0;' }, _('Running proxy list')),
							E('div', {
								id: 'frpc-proxy-list-wrap',
								style: 'max-height:220px; overflow:auto;'
							}, proxyRows.length > 0 ? E('table', { 'class': 'table cbi-section-table' }, [
								E('tr', { 'class': 'tr table-titles' }, [
									E('th', { 'class': 'th' }, _('Name')),
									E('th', { 'class': 'th' }, _('Type')),
									E('th', { 'class': 'th' }, _('Status')),
									E('th', { 'class': 'th' }, _('Local')),
									E('th', { 'class': 'th' }, _('Remote')),
									E('th', { 'class': 'th' }, _('Error'))
								]),
								...proxyRows.map((row) => E('tr', { 'class': 'tr' }, [
									E('td', { 'class': 'td' }, row.name),
									E('td', { 'class': 'td' }, row.type),
									E('td', { 'class': 'td' }, row.status),
									E('td', { 'class': 'td' }, row.local),
									E('td', { 'class': 'td' }, row.remote),
									E('td', { 'class': 'td' }, row.err || '-')
								]))
							]) : E('div', {}, _('No running proxies')))
						])
					])
				])
			])
		]);
		container.appendChild(runtimeSection);

		poll.add(() => Promise.all([callFrpcStatus(), callRuntimeInfo()]).then((res) => {
			const s = res[0] || {};
			const r = res[1] || {};
			const next = renderState(s);

			const statusNode = document.getElementById('frpc-status-text');
			if (statusNode) {
				statusNode.textContent = next.text;
				statusNode.style.color = next.color;
			}

			const restartBtnNode = document.getElementById('frpc-restart-btn');
			if (restartBtnNode) {
				if (s.state === 'managed' || s.state === 'unmanaged') {
					restartBtnNode.style.display = 'inline-block';
				} else {
					restartBtnNode.style.display = 'none';
				}
			}

			const runtimeConfigNode = document.getElementById('frpc-runtime-config');
			if (runtimeConfigNode)
				runtimeConfigNode.textContent = s.runtime_config || '-';

			const proxyCountNode = document.getElementById('frpc-proxy-count');
			if (proxyCountNode)
				proxyCountNode.textContent = String(s.proxy_count || 0);

			const versionNode = document.getElementById('frpc-version');
			if (versionNode)
				versionNode.textContent = s.version || '-';

			const runtimeSectionNode = document.getElementById('frpc-runtime-section');
			if (runtimeSectionNode)
				runtimeSectionNode.style.display = (s.state === 'managed') ? '' : 'none';

			const webNode = document.getElementById('frpc-web-api');
			if (webNode) {
				if (r.web_url) {
					webNode.innerHTML = '';
					webNode.appendChild(E('a', {
						'class': 'btn cbi-button',
						href: r.web_url,
						target: '_blank',
						rel: 'noopener noreferrer'
					}, _('Open')));
				} else {
					webNode.textContent = '-';
				}
			}

			const serverNode = document.getElementById('frpc-connected-server');
			if (serverNode)
				serverNode.textContent = (r.server_addr && r.server_port) ? (r.server_addr + ':' + r.server_port) : '-';

			const listWrap = document.getElementById('frpc-proxy-list-wrap');
			if (listWrap) {
				const rows = flattenProxies(r.status);
				listWrap.innerHTML = '';
				if (rows.length === 0) {
					listWrap.appendChild(E('div', {}, _('No running proxies')));
				} else {
					const table = E('table', { 'class': 'table cbi-section-table' }, [
						E('tr', { 'class': 'tr table-titles' }, [
							E('th', { 'class': 'th' }, _('Name')),
							E('th', { 'class': 'th' }, _('Type')),
							E('th', { 'class': 'th' }, _('Status')),
							E('th', { 'class': 'th' }, _('Local')),
							E('th', { 'class': 'th' }, _('Remote')),
							E('th', { 'class': 'th' }, _('Error'))
						])
					]);
					rows.forEach((row) => {
						table.appendChild(E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td' }, row.name),
							E('td', { 'class': 'td' }, row.type),
							E('td', { 'class': 'td' }, row.status),
							E('td', { 'class': 'td' }, row.local),
							E('td', { 'class': 'td' }, row.remote),
							E('td', { 'class': 'td' }, row.err || '-')
						]));
					});
					listWrap.appendChild(table);
				}
			}
		}), 5);

		return container;
	}
});
