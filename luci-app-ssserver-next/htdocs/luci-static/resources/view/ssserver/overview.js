'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require uci';

const callSsserverStatus = rpc.declare({
	object: 'luci.ssserver',
	method: 'get_status'
});

const callServiceAction = rpc.declare({
	object: 'luci.ssserver',
	method: 'service_action',
	params: [ 'action' ]
});

const callSsserverLanIp = rpc.declare({
	object: 'luci.ssserver',
	method: 'get_lan_ip'
});

function renderState(status) {
	let text = _('Stopped');
	let color = 'red';

	if (status.running) {
		text = _('Running');
		if (status.pid) {
			text += ' [PID: ' + status.pid + ']';
		}
		color = 'green';
	}

	return { text, color };
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			callSsserverStatus(),
			uci.load('ssserver'),
			callSsserverLanIp().catch(function() { return { ip: '' }; })
		]);
	},

	render: function(data) {
		const status = data && data[0] ? data[0] : {};
		const stateInfo = renderState(status);
		const lanIpInfo = data && data[2] ? data[2] : { ip: '' };
		const lanIp = lanIpInfo.ip || '8.8.8.8';

		// Read configurations from UCI
		const ssserverConfig = uci.get('ssserver', 'main') || {};
		const server = ssserverConfig.server || '0.0.0.0';
		const port = ssserverConfig.server_port || '8388';
		const method = ssserverConfig.method || 'chacha20-ietf-poly1305';
		const timeout = ssserverConfig.timeout || '300';
		
		let modeText = _('TCP and UDP');
		if (ssserverConfig.mode === 'tcp_only') modeText = _('TCP only');
		if (ssserverConfig.mode === 'udp_only') modeText = _('UDP only');

		const dns = ssserverConfig.dns_resolver || lanIp;
		const tfo = (ssserverConfig.fast_open === '1') ? _('Enabled') : _('Disabled');
		const firewall = (ssserverConfig.open_firewall === '1') ? _('Enabled') : _('Disabled');

		const container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Shadowsocks Server Title') + ' - ' + _('Overview')),
			E('div', { 'class': 'cbi-map-descr' }, _('Overview of ssserver running status and actual runtime configurations.'))
		]);

		// Service Status Section (Aligned with lucky style)
		const statusSection = E('fieldset', { 'class': 'cbi-section' }, [
			E('legend', {}, _('Service Status')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '33%' }, _('Current Status')),
						E('td', { 'class': 'td left' }, [
							E('span', {
								id: 'ssserver-status-text',
								'style': 'font-weight:bold; color:' + stateInfo.color + '; margin-right:15px;'
							}, stateInfo.text),
							E('button', {
								id: 'ssserver-restart-btn',
								'class': 'btn cbi-button cbi-button-apply',
								'style': 'display:' + (status.running ? 'inline-block' : 'none') + ';',
								click: ui.createHandlerFn(this, function(ev) {
									if (!ev || !ev.currentTarget) return;
									const btn = ev.currentTarget;
									btn.disabled = true;
									
									ui.addNotification(null, E('p', _('Restarting Shadowsocks Server, please wait...')), 'info');
									
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
					])
				])
			])
		]);

		container.appendChild(statusSection);

		// Runtime Configuration Section (Aligned with lucky style)
		const configSection = E('fieldset', { 'class': 'cbi-section' }, [
			E('legend', {}, _('Runtime Configurations')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '33%' }, _('Server Address')),
						E('td', { 'class': 'td left' }, E('code', {}, server))
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Server Port')),
						E('td', { 'class': 'td left' }, E('code', {}, port))
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Encryption Method')),
						E('td', { 'class': 'td left' }, E('code', {}, method))
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Network Mode')),
						E('td', { 'class': 'td left' }, modeText)
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('ssserver timeout')),
						E('td', { 'class': 'td left' }, timeout + ' ' + _('seconds'))
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('DNS Resolver')),
						E('td', { 'class': 'td left' }, E('code', {}, dns))
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('TCP Fast Open')),
						E('td', { 'class': 'td left' }, tfo)
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('Open Firewall')),
						E('td', { 'class': 'td left' }, firewall)
					])
				])
			])
		]);

		container.appendChild(configSection);

		// Add live status polling
		poll.add(function() {
			return callSsserverStatus().then(function(status) {
				const textNode = document.getElementById('ssserver-status-text');
				const restartBtn = document.getElementById('ssserver-restart-btn');
				
				if (textNode && restartBtn) {
					const stateInfo = renderState(status || {});
					
					textNode.textContent = stateInfo.text;
					textNode.style.color = stateInfo.color;
					
					// Toggle button visibility based on runtime state
					if (status.running) {
						restartBtn.style.display = 'inline-block';
					} else {
						restartBtn.style.display = 'none';
					}
				}
			});
		}, 5);

		return container;
	}
});
