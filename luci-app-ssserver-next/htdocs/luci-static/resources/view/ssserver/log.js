'use strict';
'require view';
'require rpc';
'require poll';

var callGetLog = rpc.declare({
	object: 'luci.ssserver',
	method: 'get_log',
	expect: {}
});

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	render: function() {
		var log_view = E('textarea', {
			id: 'ssserver_log_content',
			style: 'width:100%; height:500px; background:#f4f4f4; color:#333; padding:10px; border:1px solid #ccc; border-radius:3px; font-family:monospace; font-size:12px; overflow-y:auto; white-space:pre-wrap; word-break:break-all; margin-top:10px;',
			readonly: 'readonly'
		}, _('Loading logs...'));

		poll.add(function() {
			return callGetLog().then(function(res) {
				var area = document.getElementById('ssserver_log_content');
				if (area) {
					if (res && res.log) {
						area.value = res.log;
						area.scrollTop = area.scrollHeight;
					} else {
						area.value = _('No log entries found.');
					}
				}
			});
		}, 5);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Shadowsocks Server Title') + ' - ' + _('Log')),
			E('div', { 'class': 'cbi-map-descr' }, _('Logs are updated every 5 seconds.')),
			E('fieldset', { 'class': 'cbi-section' }, [
				E('legend', {}, _('Log')),
				E('div', { 'class': 'cbi-section-node' }, log_view)
			])
		]);
	}
});
