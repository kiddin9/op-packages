'use strict';
'require view';
'require rpc';
'require poll';

var callGetLog = rpc.declare({
	object: 'luci.linkback',
	method: 'get_log'
});

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	render: function() {
		var area = E('textarea', {
			id: 'linkback_log_content',
			style: 'width:100%; height:500px; background:#f4f4f4; color:#333; padding:10px; border:1px solid #ccc; border-radius:3px; font-family:monospace; font-size:12px; overflow-y:auto; white-space:pre-wrap; word-break:break-all; margin-top:10px;',
			readonly: 'readonly'
		}, _('Loading logs...'));

		poll.add(L.bind(this.updateLogs, this), 5);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('LinkBack 链路守护') + ' - ' + _('Log')),
			E('div', { 'class': 'cbi-map-descr' }, _('Real-time routing adjustments and health check state transitions from the linkbackd daemon.')),
			E('fieldset', { 'class': 'cbi-section' }, [
				E('legend', {}, _('System Logs')),
				E('div', { 'class': 'cbi-section-node' }, area)
			])
		]);
	},

	updateLogs: function() {
		return callGetLog().then(function(res) {
			var area = document.getElementById('linkback_log_content');
			if (area) {
				area.value = res && res.log ? res.log : _('No logs available.');
				area.scrollTop = area.scrollHeight;
			}
		});
	}
});
