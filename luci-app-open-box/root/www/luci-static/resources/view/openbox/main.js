'use strict';
'require view';
'require fs';
'require ui';
'require uci';
'require rpc';
'require poll';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { '': {} }
});

return view.extend({
	pollInterval: 3,

	load: function() {
		return Promise.all([
			fs.read('/opt/open-box/meta.json').catch(function() { return null; }),
			fs.read('/opt/open-box/data/panel-port').catch(function() { return null; }),
			fs.exec_direct('/usr/bin/open-box', [ 'password' ]).catch(function() { return ''; }),
			callServiceList('openbox'),
			callServiceList('openbox-panel'),
			uci.load('network').catch(function() { return null; }),
			uci.load('openbox').catch(function() { return null; })
		]);
	},

	render: function(data) {
		var metaRaw = data[0];
		var portRaw = data[1];
		var password = (data[2] || '').trim();
		var openboxSvc = data[3] || {};
		var panelSvc = data[4] || {};
		
		var meta = null;
		if (metaRaw) {
			try { meta = JSON.parse(metaRaw); } catch(e) {}
		}

		var port = (portRaw || '').replace(/[^0-9]/g, '');
		if (!port) {
			port = (uci.get('openbox', 'main', 'port') || '3036');
		}

		var lanIp = uci.get('network', 'lan', 'ipaddr');
		if (Array.isArray(lanIp)) lanIp = lanIp[0];
		if (lanIp && lanIp.indexOf('/') !== -1) lanIp = lanIp.split('/')[0];
		if (!lanIp) lanIp = window.location.hostname || '192.168.1.1';

		var panelRunning = (panelSvc['openbox-panel'] && panelSvc['openbox-panel']['instances'] && Object.keys(panelSvc['openbox-panel']['instances']).length > 0);
		var coreRunning = (openboxSvc['openbox'] && openboxSvc['openbox']['instances'] && Object.keys(openboxSvc['openbox']['instances']).length > 0);

		var panelUrl = 'http://' + lanIp + ':' + port;

		var viewRoot = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ _('Open-Box') + ' ' + (meta && meta.version ? 'v' + meta.version : '') ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Open-Box 是路由器上的一体化透明代理方案，内置 sing-box 内核、Node.js 运行时与 Web 管理面板。本页面为 LuCI 兜底管理页，可用于启停服务、修改端口、找回密码或执行维护操作。')
			])
		]);

		// 1. 面板直达与密码卡片
		var accessCard = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Open-Box 管理面板') ]),
			E('div', { 'class': 'cbi-section-descr' }, [
				_('日常代理节点选择、分流规则配置、订阅管理及流量统计请在独立 Web 面板中进行。')
			]),
			E('div', { 'class': 'table' }, [
				E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left', 'style': 'width:30%' }, [ E('strong', {}, _('面板访问地址')) ]),
					E('div', { 'class': 'td' }, [
						E('a', { 'href': panelUrl, 'target': '_blank', 'class': 'cbi-button cbi-button-action' }, [
							_('打开管理面板') + ' (' + panelUrl + ')'
						])
					])
				]),
				E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, [ E('strong', {}, _('面板当前密码')) ]),
					E('div', { 'class': 'td' }, [
						E('span', { 'style': 'font-family: monospace; font-size: 1.1em; color: #2c3e50; font-weight: bold;' }, [
							password || _('尚未设置（首次打开面板设置管理密码）')
						]),
						password ? E('button', {
							'class': 'cbi-button cbi-button-neutral',
							'style': 'margin-left: 1em;',
							'click': function() {
								navigator.clipboard.writeText(password).then(function() {
									ui.addNotification(null, E('p', {}, _('密码已复制到剪贴板。')), 'info');
								});
							}
						}, [ _('复制密码') ]) : E('span')
					])
				]),
				E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, [ E('strong', {}, _('面板监听端口')) ]),
					E('div', { 'class': 'td' }, [
						E('span', { 'style': 'font-family: monospace; margin-right: 1em;' }, [ port ]),
						E('button', {
							'class': 'cbi-button cbi-button-apply',
							'click': ui.createHandlerFn(this, 'handlePortChange', port)
						}, [ _('修改端口') ])
					])
				])
			])
		]);
		viewRoot.appendChild(accessCard);

		// 2. 服务运行状态卡片
		var statusCard = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('服务运行状态') ]),
			E('div', { 'class': 'table' }, [
				E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left', 'style': 'width:30%' }, [ E('strong', {}, _('面板服务 (openbox-panel)')) ]),
					E('div', { 'class': 'td' }, [
						E('span', { 'class': 'badge ' + (panelRunning ? 'badge-success' : 'badge-danger') }, [
							panelRunning ? _('运行中 (Running)') : _('已停止 (Stopped)')
						]),
						E('div', { 'class': 'btn-group', 'style': 'display: inline-block; margin-left: 1.5em;' }, [
							E('button', {
								'class': 'cbi-button ' + (panelRunning ? 'cbi-button-reset' : 'cbi-button-action'),
								'click': ui.createHandlerFn(this, 'handleServiceAction', 'openbox-panel', panelRunning ? 'stop' : 'start')
							}, [ panelRunning ? _('停止面板') : _('启动面板') ]),
							E('button', {
								'class': 'cbi-button cbi-button-neutral',
								'style': 'margin-left: 0.5em;',
								'click': ui.createHandlerFn(this, 'handleServiceAction', 'openbox-panel', 'restart')
							}, [ _('重启面板') ])
						])
					])
				]),
				E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, [ E('strong', {}, _('内核代理服务 (openbox)')) ]),
					E('div', { 'class': 'td' }, [
						E('span', { 'class': 'badge ' + (coreRunning ? 'badge-success' : 'badge-danger') }, [
							coreRunning ? _('运行中 (Running)') : _('已停止 (Stopped)')
						]),
						E('div', { 'class': 'btn-group', 'style': 'display: inline-block; margin-left: 1.5em;' }, [
							E('button', {
								'class': 'cbi-button ' + (coreRunning ? 'cbi-button-reset' : 'cbi-button-action'),
								'click': ui.createHandlerFn(this, 'handleServiceAction', 'openbox', coreRunning ? 'stop' : 'start')
							}, [ coreRunning ? _('紧急停止内核 (恢复直连)') : _('启动内核') ]),
							E('button', {
								'class': 'cbi-button cbi-button-neutral',
								'style': 'margin-left: 0.5em;',
								'click': ui.createHandlerFn(this, 'handleServiceAction', 'openbox', 'restart')
							}, [ _('按配置重载/重启') ])
						])
					])
				])
			])
		]);
		viewRoot.appendChild(statusCard);

		// 3. 核心组件与更新维护卡片
		var hasCore = (meta !== null);
		var maintenanceCard = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('组件与更新维护') ]),
			E('div', { 'class': 'cbi-section-descr' }, [
				hasCore ? _('当前已安装 Open-Box 核心组件（安装目录：/opt/open-box）。') :
				_('检测到核心组件尚未安装或 /opt/open-box 不完整。您可以直接使用下方一键下载安装功能完成初始化。')
			]),
			E('div', { 'class': 'table' }, [
				E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left', 'style': 'width:30%' }, [ E('strong', {}, _('核心组件状态')) ]),
					E('div', { 'class': 'td' }, [
						hasCore ? E('span', { 'class': 'badge badge-success' }, [
							_('已就绪') + ' (' + (meta.arch || 'unknown') + ', ' + (meta.version || 'v' + meta.version) + ')'
						]) : E('span', { 'class': 'badge badge-danger' }, [ _('尚未就绪') ]),
						!hasCore ? E('button', {
							'class': 'cbi-button cbi-button-action',
							'style': 'margin-left: 1em;',
							'click': ui.createHandlerFn(this, 'handleInstallCore')
						}, [ _('一键安装核心组件') ]) : E('span')
					])
				]),
				E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, [ E('strong', {}, _('更新加速镜像')) ]),
					E('div', { 'class': 'td' }, [
						E('select', { 'id': 'openbox_mirror_select', 'class': 'cbi-input-select' }, [
							E('option', { 'value': 'direct' }, _('GitHub 直连 (官方)')),
							E('option', { 'value': 'https://ghfast.top', 'selected': 'selected' }, 'ghfast.top (' + _('内置推荐') + ')'),
							E('option', { 'value': 'https://gh-proxy.com' }, 'gh-proxy.com'),
							E('option', { 'value': 'https://gh.llkk.cc' }, 'gh.llkk.cc')
						]),
						E('button', {
							'class': 'cbi-button cbi-button-neutral',
							'style': 'margin-left: 1em;',
							'click': ui.createHandlerFn(this, 'handleTestLatency')
						}, [ _('测速/检测可用性') ]),
						E('span', { 'id': 'openbox_probe_result', 'style': 'margin-left: 1em; font-weight: bold;' }, '')
					])
				]),
				E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, [ E('strong', {}, _('系统升级与维护')) ]),
					E('div', { 'class': 'td' }, [
						E('button', {
							'class': 'cbi-button cbi-button-apply',
							'click': ui.createHandlerFn(this, 'handleUpdate', false)
						}, [ _('检查并升级到最新版') ]),
						E('button', {
							'class': 'cbi-button cbi-button-neutral',
							'style': 'margin-left: 0.5em;',
							'click': ui.createHandlerFn(this, 'handleUpdate', true)
						}, [ _('回退到上个版本 (Rollback)') ]),
						E('button', {
							'class': 'cbi-button cbi-button-reset',
							'style': 'margin-left: 1.5em;',
							'click': ui.createHandlerFn(this, 'handleUninstall')
						}, [ _('卸载 Open-Box') ])
					])
				])
			])
		]);
		viewRoot.appendChild(maintenanceCard);

		return viewRoot;
	},

	handleServiceAction: function(service, action) {
		ui.showModal(_('正在处理'), [
			E('p', { 'class': 'spinning' }, _('正在执行操作，请稍候...'))
		]);
		return fs.exec('/etc/init.d/' + service, [ action ]).then(function() {
			window.location.reload();
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, _('操作失败: ') + e.message), 'error');
			ui.hideModal();
		});
	},

	handlePortChange: function(currentPort) {
		var input = E('input', {
			'type': 'number',
			'class': 'cbi-input-text',
			'min': 1024,
			'max': 65535,
			'value': currentPort
		});
		ui.showModal(_('修改面板端口'), [
			E('p', {}, _('请输入 1024 至 65535 之间的可用端口号（修改后将自动重启面板并放行防火墙）：')),
			input,
			E('div', { 'class': 'right', 'style': 'margin-top: 1em;' }, [
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': ui.hideModal
				}, [ _('取消') ]),
				E('button', {
					'class': 'cbi-button cbi-button-apply',
					'style': 'margin-left: 0.5em;',
					'click': function() {
						var newPort = input.value.trim();
						if (!newPort || isNaN(newPort) || newPort < 1024 || newPort > 65535) {
							ui.addNotification(null, E('p', {}, _('请输入合法的端口号 (1024-65535)')), 'error');
							return;
						}
						ui.showModal(_('保存中'), [ E('p', { 'class': 'spinning' }, _('正在应用新端口并重启面板...')) ]);
						fs.exec_direct('/usr/bin/open-box', [ 'port', newPort ]).then(function() {
							window.location.reload();
						}).catch(function(e) {
							ui.addNotification(null, E('p', {}, _('修改失败: ') + e.message), 'error');
							ui.hideModal();
						});
					}
				}, [ _('保存并重启') ])
			])
		]);
	},

	handleTestLatency: function() {
		var select = document.getElementById('openbox_mirror_select');
		var mirror = select ? select.value : 'direct';
		var resultSpan = document.getElementById('openbox_probe_result');
		if (resultSpan) {
			resultSpan.textContent = _('正在检测...');
			resultSpan.style.color = '#3498db';
		}

		var args = [ '--probe', mirror ];
		var execPath = '/opt/open-box/update.sh';
		fs.stat(execPath).catch(function() {
			return fs.stat('/usr/share/openbox/update.sh').then(function() {
				execPath = '/usr/share/openbox/update.sh';
			});
		}).then(function() {
			return fs.exec_direct(execPath, args);
		}).then(function(out) {
			if (resultSpan) {
				var text = (out || '').trim();
				if (text.startsWith('ok')) {
					resultSpan.textContent = '✓ ' + text.replace('ok', _('可用') + ': ');
					resultSpan.style.color = '#27ae60';
				} else {
					resultSpan.textContent = '✗ ' + text.replace('fail', _('失败') + ': ');
					resultSpan.style.color = '#e74c3c';
				}
			}
		}).catch(function(err) {
			if (resultSpan) {
				resultSpan.textContent = '✗ ' + (err.message || _('检测出错'));
				resultSpan.style.color = '#e74c3c';
			}
		});
	},

	handleInstallCore: function() {
		var select = document.getElementById('openbox_mirror_select');
		var mirror = select ? select.value : 'https://ghfast.top';
		var args = [];
		if (mirror !== 'direct') {
			args = [ '--mirror', mirror ];
		}

		ui.showModal(_('安装核心组件'), [
			E('p', { 'class': 'spinning' }, _('正在下载并部署 Open-Box 完整核心组件（约需 1-3 分钟，视网络速度而定）...'))
		]);

		var script = '/usr/share/openbox/install.sh';
		fs.exec(script, args).then(function() {
			ui.addNotification(null, E('p', {}, _('核心组件安装成功！')), 'info');
			window.location.reload();
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, _('安装失败: ') + e.message), 'error');
			ui.hideModal();
		});
	},

	handleUpdate: function(isRollback) {
		var select = document.getElementById('openbox_mirror_select');
		var mirror = select ? select.value : 'direct';
		var args = [ '--detach' ];
		if (isRollback) args.push('--rollback');
		if (mirror === 'direct') {
			args.push('--direct');
		} else {
			args.push('--mirror');
			args.push(mirror);
		}

		var execPath = '/opt/open-box/update.sh';
		fs.stat(execPath).catch(function() {
			execPath = '/usr/share/openbox/update.sh';
		}).then(function() {
			return fs.exec_direct(execPath, args);
		}).then(function() {
			var progressBar = E('div', { 'class': 'cbi-progressbar', 'title': '0%' }, [ E('div', { 'style': 'width: 0%' }) ]);
			var statusText = E('p', {}, _('任务已派发，正在准备下载...'));
			var logPre = E('pre', { 'style': 'max-height: 200px; overflow-y: scroll; font-size: 11px; background: #f8f9fa; padding: 8px;' }, '');

			ui.showModal(isRollback ? _('正在执行版本回退') : _('正在升级 Open-Box'), [
				statusText,
				progressBar,
				E('p', { 'style': 'margin-top: 1em;' }, [ E('strong', {}, _('实时日志:')) ]),
				logPre,
				E('div', { 'class': 'right', 'style': 'margin-top: 1em;' }, [
					E('button', {
						'class': 'cbi-button cbi-button-reset',
						'click': function() {
							fs.exec_direct(execPath, [ '--cancel' ]);
							ui.hideModal();
						}
					}, [ _('取消更新') ])
				])
			]);

			var timer = window.setInterval(function() {
				Promise.all([
					fs.read('/tmp/openbox-update.status').catch(function() { return ''; }),
					fs.read('/tmp/openbox-update.log').catch(function() { return ''; })
				]).then(function(res) {
					var st = res[0] || '';
					var lg = res[1] || '';
					logPre.textContent = lg;
					logPre.scrollTop = logPre.scrollHeight;

					var stage = (st.match(/stage=([^\n]+)/) || [])[1];
					var bytes = parseInt((st.match(/bytes=([0-9]+)/) || [])[1] || 0);
					var total = parseInt((st.match(/total=([0-9]+)/) || [])[1] || 0);
					var msg = (st.match(/message=([^\n]*)/) || [])[1] || '';

					if (stage === 'downloading') {
						if (total > 0) {
							var pct = Math.floor((bytes / total) * 100);
							progressBar.firstElementChild.style.width = pct + '%';
							progressBar.setAttribute('title', pct + '%');
							statusText.textContent = _('正在下载发布包: ') + (bytes / 1048576).toFixed(1) + 'MB / ' + (total / 1048576).toFixed(1) + 'MB (' + pct + '%)';
						} else {
							statusText.textContent = _('正在下载发布包: ') + (bytes / 1048576).toFixed(1) + 'MB';
						}
					} else if (stage === 'extracting') {
						progressBar.firstElementChild.style.width = '80%';
						statusText.textContent = _('正在解包并校验文件完整性...');
					} else if (stage === 'committing') {
						progressBar.firstElementChild.style.width = '90%';
						statusText.textContent = _('正在替换旧组件并重启服务...');
					} else if (stage === 'done') {
						window.clearInterval(timer);
						progressBar.firstElementChild.style.width = '100%';
						statusText.textContent = _('操作完成！') + (msg ? ' (' + msg + ')' : '');
						window.setTimeout(function() { window.location.reload(); }, 2000);
					} else if (stage === 'failed' || stage === 'cancelled') {
						window.clearInterval(timer);
						statusText.textContent = (stage === 'failed' ? _('操作失败: ') : _('操作已取消: ')) + msg;
					}
				});
			}, 1000);
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, _('启动升级失败: ') + e.message), 'error');
		});
	},

	handleUninstall: function() {
		var checkPurge = E('input', { 'type': 'checkbox' });
		ui.showModal(_('卸载 Open-Box'), [
			E('p', {}, _('确定要从系统中卸载 Open-Box 吗？')),
			E('label', { 'class': 'cbi-checkbox', 'style': 'display: block; margin: 1em 0;' }, [
				checkPurge,
				' ' + _('同时删除所有用户数据（/opt/open-box/data 下的节点订阅、规则集与数据库）')
			]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'cbi-button cbi-button-neutral',
					'click': ui.hideModal
				}, [ _('取消') ]),
				E('button', {
					'class': 'cbi-button cbi-button-reset',
					'style': 'margin-left: 0.5em;',
					'click': function() {
						var purge = checkPurge.checked;
						var args = [ '--detach' ];
						if (purge) args.push('--purge');

						var execPath = '/opt/open-box/uninstall.sh';
						fs.stat(execPath).catch(function() {
							execPath = '/usr/share/openbox/uninstall.sh';
						}).then(function() {
							return fs.exec_direct(execPath, args);
						}).then(function() {
							ui.showModal(_('卸载中'), [
								E('p', { 'class': 'spinning' }, _('正在停止服务并清理残留文件...'))
							]);
							window.setTimeout(function() {
								window.location.href = window.location.pathname.replace(/\/admin\/services\/openbox.*/, '/admin/status/overview');
							}, 4000);
						}).catch(function(err) {
							ui.addNotification(null, E('p', {}, _('卸载失败: ') + err.message), 'error');
							ui.hideModal();
						});
					}
				}, [ _('确认卸载') ])
			])
		]);
	}
});
