'use strict';
'require view';
'require rpc';
'require ui';
'require dom';
'require poll';

var callGetInfo = rpc.declare({ object: 'luci.lucky', method: 'get_info', expect: { } });
var callGetStatus = rpc.declare({ object: 'luci.lucky', method: 'get_status', expect: { } });
var callService = rpc.declare({ object: 'luci.lucky', method: 'service', params: ['action'], expect: { } });

return view.extend({
	load: function() {
		return callGetInfo();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	handleServiceAction: function(action) {
		ui.showModal(null, [ E('p', { class: 'spinning' }, _('Executing service action...')) ]);
		var self = this;
		var startTime = Date.now();
		var shouldBeRunning = (action === 'start' || action === 'restart');

		return callService(action).then(function() {
			function waitForReady() {
				if (Date.now() - startTime > 20000) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Operation timeout, please refresh the page')), 'error');
					return;
				}
				callGetStatus().then(function(res) {
					var isRunning = res && res.state && res.state !== 'stopped';
					if (shouldBeRunning ? isRunning : !isRunning) {
						ui.hideModal();
						ui.addNotification(null, E('p', _('Service action executed successfully')), 'info');
						self.updateStatus(res);
						// 服务刚启动/重启后，异步刷新完整信息
						if (isRunning) {
							callGetInfo().then(function(info) {
								self.updateInfo(info);
							});
						}
					} else {
						setTimeout(waitForReady, 1000);
					}
				});
			}
			waitForReady();
		});
	},

	updateStatus: function(status) {
		var statusEl = document.getElementById('_status');
		var state = status ? status.state : 'stopped';
		var pid = status ? status.pid : null;
		var running = (state !== 'stopped');

		if (statusEl) {
			var statusText = _('Stopped');
			var statusColor = 'red';
			var isManaged = (state === 'managed');
			var isUnmanaged = (state === 'unmanaged');

			if (isManaged) {
				statusText = _('Running');
				statusColor = 'green';
			} else if (isUnmanaged) {
				statusText = _('Running (Unmanaged)');
				statusColor = 'orange';
			}

			if (pid) {
				statusText += ' [PID: ' + pid + ']';
			}

			var statusNode = [
				E('b', { style: 'color:' + statusColor }, statusText)
			];

			if (running) {
				statusNode.push(E('input', {
					type: 'button', id: '_btnRestart', class: 'btn cbi-button cbi-button-reload', value: _('Restart'),
					style: 'margin-left: 20px;',
					click: ui.createHandlerFn(this, 'handleServiceAction', 'restart')
				}));
			}

			dom.content(statusEl, statusNode);
		}

		var adminLinkEl = document.getElementById('_luckyAdminLink');
		if (adminLinkEl && !running) {
			dom.content(adminLinkEl, E('em', {}, _('Service not running')));
		}
	},

	updateInfo: function(info) {
		var luckyInfo = {};
		try { luckyInfo = JSON.parse(info.luckyInfo || '{}'); } catch(e) {}

		var el;
		el = document.getElementById('_luckyVersion');
		if (el) dom.content(el, luckyInfo.Version || '-');

		el = document.getElementById('_luckyArch');
		if (el) dom.content(el, info.luckyArch || '-');

		el = document.getElementById('_luckyDate');
		if (el) dom.content(el, luckyInfo.Date || '-');

		if (info.running && info.adminPort) {
			var url = 'http://' + window.location.hostname + ':' + info.adminPort + (info.adminSafeUrl || '');
			el = document.getElementById('_luckyAdminLink');
			if (el) dom.content(el, E('a', { href: url, target: '_blank', style: 'font-weight:bold; color:blue;' }, url));
		}
	},

	render: function(info) {
		var running = info.running;

		var container = E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('Lucky') + ' - ' + _('Overview')),
			E('div', { class: 'cbi-map-descr' }, _('Overview of your Lucky routing service status, real-time statistics, and control settings.'))
		]);

		// 解析程序信息
		var luckyInfo = {};
		try { luckyInfo = JSON.parse(info.luckyInfo || '{}'); } catch(e) {}

		// 管理面板链接
		var adminLinkContent;
		if (running && info.adminPort) {
			var url = 'http://' + window.location.hostname + ':' + info.adminPort + (info.adminSafeUrl || '');
			adminLinkContent = E('a', { href: url, target: '_blank', style: 'font-weight:bold; color:blue;' }, url);
		} else if (running) {
			adminLinkContent = E('em', {}, _('Loading...'));
		} else {
			adminLinkContent = E('em', {}, _('Service not running'));
		}

		container.appendChild(
			E('fieldset', { class: 'cbi-section' }, [
				E('legend', {}, _('Service Status')),
				E('div', { class: 'cbi-section-node' }, [
					E('table', { class: 'table' }, [
						E('tr', { class: 'tr' }, [
							E('td', { class: 'td left', width: '33%' }, _('Current Status')),
							E('td', { class: 'td left', id: '_status' }, E('em', {}, _('Loading...')))
						])
					])
				])
			])
		);

		var infoSection = E('fieldset', { class: 'cbi-section' }, [
			E('legend', {}, _('Application Information')),
			E('div', { class: 'cbi-section-node' }, [
				E('table', { class: 'table cbi-section-table' }, [
					E('tr', { class: 'tr' }, [
						E('td', { class: 'td left', width: '33%' }, _('Version')),
						E('td', { class: 'td left', id: '_luckyVersion' }, luckyInfo.Version || '-')
					]),
					E('tr', { class: 'tr' }, [
						E('td', { class: 'td left' }, _('Architecture')),
						E('td', { class: 'td left', id: '_luckyArch' }, info.luckyArch || '-')
					]),
					E('tr', { class: 'tr' }, [
						E('td', { class: 'td left' }, _('Compile Time')),
						E('td', { class: 'td left', id: '_luckyDate' }, luckyInfo.Date || '-')
					]),
					E('tr', { class: 'tr' }, [
						E('td', { class: 'td left' }, _('Admin Panel')),
						E('td', { class: 'td left', id: '_luckyAdminLink' }, adminLinkContent)
					])
				])
			])
		]);
		container.appendChild(infoSection);
		this.updateStatus(info);

		var self = this;
		poll.add(function() {
			return callGetStatus().then(function(res) {
				self.updateStatus(res);
			});
		}, 5);

		return container;
	}
});
