'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

var callGetLogs = rpc.declare({
	object: 'luci.fancontrol',
	method: 'get_logs',
	params: [ 'lines' ]
});

var callClearLogs = rpc.declare({
	object: 'luci.fancontrol',
	method: 'clear_logs'
});

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	render: function() {
		var area = E('textarea', {
			id: 'fancontrol_log_content',
			style: 'width:100%; height:460px; background:#f9f9f9; color:#222; padding:12px; border:1px solid #ccc; border-radius:4px; font-family:monospace; font-size:12px; line-height:1.5; overflow-y:auto; white-space:pre-wrap; word-break:break-all;',
			readonly: 'readonly'
		}, _('正在加载日志...'));

		var btnRefresh = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'style': 'margin-right:10px;',
			click: ui.createHandlerFn(this, 'updateLogs')
		}, _('刷新日志'));

		var btnClear = E('button', {
			'class': 'btn cbi-button cbi-button-reset',
			click: ui.createHandlerFn(this, 'handleClearLogs')
		}, _('清空日志'));

		poll.add(L.bind(this.updateLogs, this), 5);

		// 初始加载一次日志
		this.updateLogs();

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('风扇控制') + ' - ' + _('运行日志')),
			E('div', { 'class': 'cbi-map-descr' }, _('实时展示温控守护进程的调速动作、温度变化与自检日志。')),
			E('fieldset', { 'class': 'cbi-section' }, [
				E('legend', {}, _('系统日志')),
				E('div', { 'class': 'cbi-section-node' }, [
					E('div', { 'style': 'margin-bottom:10px;' }, [ btnRefresh, btnClear ]),
					area
				])
			])
		]);
	},

	updateLogs: function() {
		return callGetLogs(100).then(function(res) {
			var area = document.getElementById('fancontrol_log_content');
			if (area) {
				if (res && res.logs && res.logs.length > 0) {
					area.value = res.logs.join('\n');
					area.scrollTop = area.scrollHeight;
				} else {
					area.value = _('暂无日志记录。');
				}
			}
		}).catch(function(err) {
			var area = document.getElementById('fancontrol_log_content');
			if (area) area.value = _('读取日志失败: %s').format(err.message);
		});
	},

	handleClearLogs: function() {
		return callClearLogs().then(L.bind(function(res) {
			if (res && res.success) {
				ui.addNotification(null, E('p', _('日志已成功清空。')), 'info');
				this.updateLogs();
			} else {
				ui.addNotification(null, E('p', _('清空日志失败。')), 'error');
			}
		}, this)).catch(function(err) {
			ui.addNotification(null, E('p', _('RPC 请求失败: %s').format(err.message)), 'error');
		});
	}
});
