'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require dom';

var callGetLogs = rpc.declare({
	object: 'luci.cf-optimizer',
	method: 'get_logs'
});

var callClearLogs = rpc.declare({
	object: 'luci.cf-optimizer',
	method: 'clear_logs'
});

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return callGetLogs();
	},

	handleClearLogs: function(ev) {
		return callClearLogs().then(function() {
			var textarea = document.getElementById('cf-log-textarea');
			if (textarea) textarea.value = '';
			ui.addNotification(null, E('p', {}, _('日志已清空')), 'info');
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, e.message));
		});
	},

	render: function(data) {
		data = data || {};
		var lines = Array.isArray(data.logs) ? data.logs : [];
		var logText = lines.join('\n');

		var textarea = E('textarea', {
			'id': 'cf-log-textarea',
			'class': 'cbi-input-textarea',
			'style': 'width: 100%; height: 480px; font-family: monospace; font-size: 12px; line-height: 1.5; resize: vertical; box-sizing: border-box; padding: 10px; border-radius: 4px;',
			'readonly': 'readonly',
			'wrap': 'off'
		}, logText);

		// 默认滚动到底部
		setTimeout(function() {
			textarea.scrollTop = textarea.scrollHeight;
		}, 100);

		var autoRefreshCheckbox = E('input', {
			'type': 'checkbox',
			'id': 'cf-auto-refresh',
			'checked': 'checked',
			'style': 'margin-right: 6px; vertical-align: middle;'
		});

		var controls = E('div', {
			'style': 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;'
		}, [
			E('label', { 'style': 'cursor: pointer; user-select: none; font-size: 13px;' }, [
				autoRefreshCheckbox,
				_('自动刷新 (每 4 秒)')
			]),
			E('button', {
				'class': 'btn cbi-button cbi-button-remove',
				'click': ui.createHandlerFn(this, 'handleClearLogs')
			}, _('清空日志'))
		]);

		poll.add(function() {
			var chk = document.getElementById('cf-auto-refresh');
			if (!chk || !chk.checked) return;

			return callGetLogs().then(function(res) {
				res = res || {};
				var ta = document.getElementById('cf-log-textarea');
				if (ta && Array.isArray(res.logs)) {
					var wasAtBottom = (ta.scrollHeight - ta.clientHeight <= ta.scrollTop + 50);
					ta.value = res.logs.join('\n');
					if (wasAtBottom) {
						ta.scrollTop = ta.scrollHeight;
					}
				}
			});
		}, 4);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Cloudflare 优选加速') + ' - ' + _('运行日志')),
			E('div', { 'class': 'cbi-map-descr' }, _('查看后台优选测速与 hosts 重载的实时运行记录。')),
			E('fieldset', { 'class': 'cbi-section' }, [
				controls,
				textarea
			])
		]);
	}
});
