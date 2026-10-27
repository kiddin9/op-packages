'use strict';
'require view';
'require fs';
'require ui';
'require poll';

/*
 * LuCI 界面：运营商分流状态与操作
 *
 * 数据来自 `isp-split status --json`，通过 ubus file.exec 调用，
 * 权限由 /usr/share/rpcd/acl.d/luci-app-isp-split.json 授予。
 */

function fmtBytes(n) {
	n = +n || 0;
	var u = ['B', 'KiB', 'MiB', 'GiB', 'TiB'], i = 0;
	while (n >= 1024 && i < u.length - 1) {
		n /= 1024;
		i++;
	}
	return (i === 0 ? n.toFixed(0) : n.toFixed(1)) + ' ' + u[i];
}

return view.extend({
	exec: function(args) {
		return fs.exec('/usr/sbin/isp-split', args);
	},

	setOut: function(text) {
		var out = document.getElementById('isp-out');
		if (out) {
			out.textContent = text;
			out.scrollTop = 0;
		}
	},

	run: function(args, label, confirmText) {
		var self = this;

		var doRun = function() {
			self.setOut('正在执行：isp-split ' + args.join(' ') + ' …');
			return self.exec(args).then(function(res) {
				var text = (res.stdout || '') + (res.stderr || '');
				self.setOut(text || '(无输出)');
				ui.addNotification(null, E('p', {}, [label + ' 已完成']), 'info');
				return self.refresh();
			}).catch(function(err) {
				self.setOut('执行失败：' + String(err));
				ui.addNotification(null, E('p', {}, ['执行失败：' + String(err)]), 'danger');
			});
		};

		if (confirmText) {
			return ui.showModal(_('确认'), [
				E('p', {}, [confirmText]),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn',
						'click': ui.hideModal
					}, [_('取消')]),
					' ',
					E('button', {
						'class': 'cbi-button cbi-button-negative',
						'click': function() { ui.hideModal(); doRun(); }
					}, [_('确认执行')])
				])
			]);
		}

		return doRun();
	},

	refresh: function() {
		var tb = document.getElementById('isp-tbody');
		if (!tb)
			return Promise.resolve();

		return this.exec(['status', '--json']).then(function(res) {
			var rows = [];
			try {
				rows = JSON.parse((res.stdout || '').trim() || '[]');
			} catch (e) {
				rows = [];
			}

			while (tb.firstChild)
				tb.removeChild(tb.firstChild);

			if (!rows.length) {
				tb.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'colspan': 6 }, [
						_('没有启用的运营商。检查 /etc/isp-split.conf 里的 ISP_TABLE。')
					])
				]));
				return;
			}

			rows.forEach(function(r) {
				tb.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, [ r.set ]),
					E('td', { 'class': 'td' }, [ r.src ]),
					E('td', { 'class': 'td', 'style': 'text-align:right' }, [ r.elements != null && r.elements !== '' ? String(r.elements) : '—' ]),
					E('td', { 'class': 'td', 'style': 'text-align:right' }, [ r.exists ? String(r.packets) : '—' ]),
					E('td', { 'class': 'td', 'style': 'text-align:right' }, [ r.exists ? fmtBytes(r.bytes) : '—' ]),
					E('td', { 'class': 'td' }, [ r.policy ])
				]));
			});
		}).catch(function(err) {
			tb.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': 6 }, [ '读取状态失败：' + String(err) ])
			]));
		});
	},

	render: function() {
		var self = this;

	var actions = E('div', { 'class': 'cbi-page-actions' }, [
		E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': function() { self.run(['sync'], _('同步'), _('将下载最新运营商数据、重写 mwan3 规则并刷入 nftables。这会改动分流配置，确认继续？')); }
		}, [ _('同步生效') ]),
		' ',
		E('button', {
			'class': 'cbi-button',
			'click': function() { self.run(['refresh'], _('更新数据')); }
		}, [ _('更新数据') ]),
		' ',
		E('button', {
			'class': 'cbi-button cbi-button-neutral',
			'click': function() { self.run(['verify'], _('核对')); }
		}, [ _('核对规则') ]),
		' ',
		E('button', {
			'class': 'cbi-button',
			'click': function() { self.refresh(); }
		}, [ _('刷新') ])
	]);

		var container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ _('运营商分流') ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('按目标 IP 归属的运营商选择出口线路。数据来自 ispip.clang.cn，每日自动更新；'),
				_('只影响直连流量，代理流量由 OpenClash 自行接管。')
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('table', { 'class': 'table cbi-section-table' }, [
					E('thead', {}, [
						E('tr', { 'class': 'tr table-titles' }, [
							E('th', { 'class': 'th' }, [ _('集合') ]),
							E('th', { 'class': 'th' }, [ _('来源') ]),
							E('th', { 'class': 'th' }, [ _('条目') ]),
							E('th', { 'class': 'th' }, [ _('命中包') ]),
							E('th', { 'class': 'th' }, [ _('流量') ]),
							E('th', { 'class': 'th' }, [ _('策略') ])
						])
					]),
					E('tbody', { 'id': 'isp-tbody' }, [
						E('tr', { 'class': 'tr' }, [
							E('td', { 'class': 'td', 'colspan': 6 }, [ _('读取中…') ])
						])
					])
				])
			]),

			actions,

			E('pre', {
				'id': 'isp-out',
				'style': 'max-height:24em;overflow:auto;white-space:pre-wrap;word-break:break-all;' +
					'font-family:monospace;font-size:12px;padding:10px;border-radius:4px;' +
					'border:1px solid rgba(128,128,128,0.3)'
			}, [ _('命令输出会显示在这里') ])
		]);

		this.refresh();

		poll.add(function() { return self.refresh(); }, 10);

		return container;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
