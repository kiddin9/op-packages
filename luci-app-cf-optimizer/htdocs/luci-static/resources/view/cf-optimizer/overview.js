'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require dom';

var callGetStatus = rpc.declare({
	object: 'luci.cf-optimizer',
	method: 'get_status'
});

var callRunOnce = rpc.declare({
	object: 'luci.cf-optimizer',
	method: 'run_once'
});

var callServiceAction = rpc.declare({
	object: 'luci.cf-optimizer',
	method: 'service_action',
	params: [ 'action' ]
});

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return callGetStatus();
	},

	handleRunOnce: function(ev) {
		ui.showModal(_('执行优选'), [
			E('p', { 'class': 'spinning' }, _('正在后台启动优选探测测速任务，请稍候...'))
		]);
		return callRunOnce().then(function() {
			setTimeout(function() {
				ui.hideModal();
				window.location.reload();
			}, 3000);
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, e.message));
			ui.hideModal();
		});
	},

	handleServiceAction: function(action, ev) {
		ui.showModal(_('服务操作'), [
			E('p', { 'class': 'spinning' }, _('正在执行操作，请稍候...'))
		]);
		return callServiceAction(action).then(function() {
			setTimeout(function() {
				ui.hideModal();
				window.location.reload();
			}, 1500);
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, e.message));
			ui.hideModal();
		});
	},

	render: function(data) {
		data = data || {};

		var container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Cloudflare 优选加速') + ' - ' + _('状态概览')),
			E('div', { 'class': 'cbi-map-descr' }, _('监控当前生效的 Cloudflare 优选节点状态，展示各代理域名定向情况与最新测速排行榜。'))
		]);

		// 服务状态卡片
		var isRunning = data.service_running === true;
		var statusText = isRunning ? (_('运行中') + (data.service_pid ? ' [PID: ' + data.service_pid + ']' : '')) : _('已停止');
		var statusColor = isRunning ? '#059669' : '#64748b';

		var statusSection = E('fieldset', { 'class': 'cbi-section' }, [
			E('legend', {}, _('服务状态')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table cbi-section-table' }, [
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left', 'width': '25%' }, _('服务状态')),
						E('td', { 'class': 'td left' }, [
							E('span', { 'id': 'cf-service-status', 'style': 'font-weight:bold; color:' + statusColor + '; margin-right:15px;' }, statusText),
							E('button', {
								'class': 'btn cbi-button cbi-button-action',
								'style': 'margin-right:10px;',
								'click': ui.createHandlerFn(this, 'handleRunOnce')
							}, _('立即执行优选')),
							E('button', {
								'class': 'btn cbi-button cbi-button-reload',
								'click': ui.createHandlerFn(this, 'handleServiceAction', 'restart')
							}, _('重启服务'))
						])
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('上次更新时间')),
						E('td', { 'class': 'td left', 'id': 'cf-last-update' }, data.last_update || '-')
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('生效优选 IP')),
						E('td', { 'class': 'td left', 'id': 'cf-best-ip', 'style': 'font-weight:bold;' }, data.best_ip || '-')
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('次优备选 IP')),
						E('td', { 'class': 'td left', 'id': 'cf-standby-ip' }, data.standby_ip ? (data.standby_ip + ' (' + (data.standby_colo || '-') + ')') : _('暂无备选'))
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('健康看门狗')),
						E('td', { 'class': 'td left', 'id': 'cf-watchdog-status', 'style': 'font-weight:bold; color:' + ((data.watchdog_status && data.watchdog_status.indexOf('倒换') !== -1) ? '#d97706' : '#059669') }, data.watchdog_status || _('未运行'))
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('数据中心')),
						E('td', { 'class': 'td left', 'id': 'cf-best-colo' }, data.best_colo || '-')
					]),
					E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, _('测速延迟')),
						E('td', { 'class': 'td left', 'id': 'cf-best-latency' }, [
							E('span', { 'style': 'color:#2563eb; font-weight:bold;' }, data.best_tcp_lat ? 'TCP: ' + data.best_tcp_lat : '-'),
							E('span', { 'style': 'margin:0 8px; color:#cbd5e1;' }, '|'),
							E('span', { 'style': 'color:#059669; font-weight:bold;' }, data.best_tls_lat ? 'TLS: ' + data.best_tls_lat : '-')
						])
					])
				])
			])
		]);

		// 域名定向列表
		var domainRows = [];
		if (Array.isArray(data.domains) && data.domains.length > 0) {
			for (var i = 0; i < data.domains.length; i++) {
				var d = data.domains[i];
				domainRows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, E('strong', {}, d.domain)),
					E('td', { 'class': 'td' }, d.ip || '-'),
					E('td', { 'class': 'td' }, d.colo || '-'),
					E('td', { 'class': 'td' }, d.tcp_lat || '-'),
					E('td', { 'class': 'td' }, d.tls_lat || '-'),
					E('td', { 'class': 'td' }, E('span', { 'style': 'color:#059669; font-weight:bold;' }, d.status || _('正常')))
				]));
			}
		} else {
			domainRows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': '6', 'style': 'text-align:center; color:#94a3b8;' }, _('暂无生效的域名定向记录，请在参数配置中添加域名并启动服务。'))
			]));
		}

		var domainSection = E('fieldset', { 'class': 'cbi-section' }, [
			E('legend', {}, _('域名定向列表')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table cbi-section-table', 'id': 'cf-domain-table' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, _('目标域名')),
						E('th', { 'class': 'th' }, _('生效优选 IP')),
						E('th', { 'class': 'th' }, _('数据中心')),
						E('th', { 'class': 'th' }, _('TCP 延迟')),
						E('th', { 'class': 'th' }, _('TLS 延迟')),
						E('th', { 'class': 'th' }, _('状态'))
					])
				].concat(domainRows))
			])
		]);

		// 优选候选排行榜
		var rankingRows = [];
		if (Array.isArray(data.rankings) && data.rankings.length > 0) {
			for (var j = 0; j < data.rankings.length; j++) {
				var r = data.rankings[j];
				rankingRows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, r.rank),
					E('td', { 'class': 'td' }, E('strong', {}, r.ip)),
					E('td', { 'class': 'td' }, r.colo || '-'),
					E('td', { 'class': 'td', 'style': 'color:#059669; font-weight:bold;' }, r.avg_lat),
					E('td', { 'class': 'td' }, r.lat_range || '-'),
					E('td', { 'class': 'td' }, r.loss_rate || '0.0%')
				]));
			}
		} else {
			rankingRows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': '6', 'style': 'text-align:center; color:#94a3b8;' }, _('暂无排行榜数据'))
			]));
		}

		var rankingSection = E('fieldset', { 'class': 'cbi-section' }, [
			E('legend', {}, _('优选候选节点排行榜')),
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table cbi-section-table', 'id': 'cf-ranking-table' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, _('排名')),
						E('th', { 'class': 'th' }, _('候选 IP')),
						E('th', { 'class': 'th' }, _('数据中心')),
						E('th', { 'class': 'th' }, _('平均延迟')),
						E('th', { 'class': 'th' }, _('时延范围')),
						E('th', { 'class': 'th' }, _('丢包率'))
					])
				].concat(rankingRows))
			])
		]);

		container.appendChild(statusSection);
		container.appendChild(domainSection);
		container.appendChild(rankingSection);

		// 定时轮询更新
		poll.add(function() {
			return callGetStatus().then(function(res) {
				res = res || {};
				var running = res.service_running === true;
				var stEl = document.getElementById('cf-service-status');
				if (stEl) {
					stEl.textContent = running ? (_('运行中') + (res.service_pid ? ' [PID: ' + res.service_pid + ']' : '')) : _('已停止');
					stEl.style.color = running ? '#059669' : '#64748b';
				}
				var upEl = document.getElementById('cf-last-update');
				if (upEl) upEl.textContent = res.last_update || '-';

				var ipEl = document.getElementById('cf-best-ip');
				if (ipEl) ipEl.textContent = res.best_ip || '-';

				var sbEl = document.getElementById('cf-standby-ip');
				if (sbEl) sbEl.textContent = res.standby_ip ? (res.standby_ip + ' (' + (res.standby_colo || '-') + ')') : _('暂无备选');

				var wdEl = document.getElementById('cf-watchdog-status');
				if (wdEl) {
					wdEl.textContent = res.watchdog_status || _('未运行');
					wdEl.style.color = (res.watchdog_status && res.watchdog_status.indexOf('倒换') !== -1) ? '#d97706' : '#059669';
				}

				var coloEl = document.getElementById('cf-best-colo');
				if (coloEl) coloEl.textContent = res.best_colo || '-';

				var latEl = document.getElementById('cf-best-latency');
				if (latEl) {
					dom.content(latEl, [
						E('span', { 'style': 'color:#2563eb; font-weight:bold;' }, res.best_tcp_lat ? 'TCP: ' + res.best_tcp_lat : '-'),
						E('span', { 'style': 'margin:0 8px; color:#cbd5e1;' }, '|'),
						E('span', { 'style': 'color:#059669; font-weight:bold;' }, res.best_tls_lat ? 'TLS: ' + res.best_tls_lat : '-')
					]);
				}
			});
		}, 3);

		return container;
	}
});
