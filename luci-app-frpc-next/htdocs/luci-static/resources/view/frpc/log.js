'use strict';
'require view';
'require rpc';
'require poll';

const callFrpcLog = rpc.declare({
	object: 'luci.frpc',
	method: 'get_log'
});

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	render: function() {
		const area = E('textarea', {
			id: 'frpc_log_content',
			style: 'width:100%; height:500px; background:#f4f4f4; color:#333; padding:10px; border:1px solid #ccc; border-radius:3px; font-family:monospace; font-size:12px; overflow-y:auto; white-space:pre-wrap; word-break:break-all; margin-top:10px;',
			readonly: 'readonly'
		}, _('Loading logs...'));

		poll.add(() => this.updateLogs(), 5);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Frp Client Title') + ' - ' + _('Log')),
			E('div', { 'class': 'cbi-map-descr' }, _('Real-time background system logs of the active frpc process, helping you diagnose server handshake and protocol errors.')),
			E('fieldset', { 'class': 'cbi-section' }, [
				E('legend', {}, _('Logs')),
				E('div', { 'class': 'cbi-section-node' }, area)
			])
		]);
	},

	updateLogs: function() {
		return callFrpcLog().then(function(res) {
			const area = document.getElementById('frpc_log_content');
			if (area) {
				area.value = res && res.log ? res.log : _('No logs available...');
				area.scrollTop = area.scrollHeight;
			}
		});
	}
});
