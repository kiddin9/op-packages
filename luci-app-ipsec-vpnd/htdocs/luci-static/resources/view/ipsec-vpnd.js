/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Copyright (C) 2022 ImmortalWrt.org
 */

'use strict';
'require form';
'require poll';
'require rpc';
'require uci';
'require view';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

const callServiceInit = rpc.declare({
	object: 'rc',
	method: 'init',
	params: ['name', 'action']
});

const callIpsecSessions = rpc.declare({
	object: 'ipsec-vpnd',
	method: 'sessions',
	expect: { '': {} }
});

const callClearHistory = rpc.declare({
	object: 'ipsec-vpnd',
	method: 'clear_history',
	expect: { '': {} }
});

function getServiceStatus() {
	return L.resolveDefault(callServiceList('ipsec-vpnd'), {}).then(function(res) {
		let isRunning = false;
		try {
			// procd_open_instance 未指定实例名时，procd 按 init 脚本 basename
			// 命名实例为 'ipsec-vpnd'；遍历全部实例，任一 running 即视为运行
			let instances = res['ipsec-vpnd']['instances'] || {};
			for (let name in instances)
				if (instances[name]['running'])
					isRunning = true;
		} catch (e) { }
		return isRunning;
	});
}

function renderStatus(isRunning) {
	let spanTemp = '<em><span style="color:%s"><strong>%s %s</strong></span></em>';
	let renderHTML;
	if (isRunning)
		renderHTML = spanTemp.format('green', _('IPSec VPN'), _('RUNNING'));
	else
		renderHTML = spanTemp.format('red', _('IPSec VPN'), _('NOT RUNNING'));

	return renderHTML;
}

return view.extend({
	render() {
		let m, s, o;

		m = new form.Map('ipsec-vpnd', _('IPSec VPN Server'),
			_('IPSec VPN connectivity using the native built-in VPN Client on iOS or Android (IKEv1 with PSK and Xauth)'));

		s = m.section(form.TypedSection);
		s.anonymous = true;
		s.render = function() {
			poll.add(function() {
				return L.resolveDefault(getServiceStatus()).then(function(res) {
					let view = document.getElementById('service_status');
					view.innerHTML = renderStatus(res);
				});
			});

			return E('div', { class: 'cbi-section', id: 'status_bar' }, [
				E('p', { id: 'service_status' }, _('Collecting data...'))
			]);
		}

		s = m.section(form.NamedSection, 'ipsec', 'service');

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.option(form.Value, 'clientip', _('VPN Client IP'),
			_('Starting IP of the VPN client address pool (CIDR notation). Use a private subnet that does not overlap the LAN, e.g. 10.9.8.10/24'));
		o.datatype = 'ip4addr';
		o.rmempty = false;

		o = s.option(form.Value, 'clientdns', _('VPN Client DNS'),
			_('DNS server assigned to VPN clients. Use the VPN gateway (ipsec0) address, e.g. 10.9.8.1'));
		o.datatype = 'ip4addr';
		o.rmempty = false;

		o = s.option(form.Value, 'account', _('Account'));
		o.rmempty = false;

		o = s.option(form.Value, 'password', _('Password'));
		o.password = true;
		o.rmempty = false;

		o = s.option(form.Value, 'secret', _('Secret Pre-Shared Key'));
		o.password = true;
		o.rmempty = false;

		// 在线客户端列表：页面最底部，5s 轮询刷新。数据来自 rpcd 后端
		// /usr/libexec/rpcd/ipsec-vpnd（解析 `ipsec statusall` 的 stroke 输出）。
		s = m.section(form.TypedSection);
		s.anonymous = true;
		s.render = function() {
			// 用显式 <thead>/<tbody> 渲染：只重建表体，表头固定保留。
			// 不依赖 cbi_update_table 对表头行（tr.table-titles）的处理，更稳。
			let clientBody = E('tbody', { 'id': 'ipsec_clients_body' });
			let clientTable = E('table', { 'class': 'table cbi-section-table', 'id': 'ipsec_clients_table' }, [
				E('thead', {}, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, _('User')),
						E('th', { 'class': 'th' }, _('Remote Address')),
						E('th', { 'class': 'th' }, _('Assigned IP')),
						E('th', { 'class': 'th' }, _('Duration')),
						E('th', { 'class': 'th' }, _('Status'))
					])
				]),
				clientBody
			]);
			let hint = E('p', { 'id': 'ipsec_clients_hint' }, _('Collecting data...'));

			let renderRows = function(sessions) {
				clientBody.textContent = '';
				sessions.forEach(function(s) {
					clientBody.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, s.user || '-'),
						E('td', { 'class': 'td' }, s.remote || '-'),
						E('td', { 'class': 'td' }, s.vip || '-'),
						E('td', { 'class': 'td' }, s.age || '-'),
						E('td', { 'class': 'td' }, s.online ? _('Connected') : _('Disconnected'))
					]));
				});
			};

			let update = function() {
				return L.resolveDefault(callIpsecSessions(), {}).then(function(res) {
					let sessions = (res && Array.isArray(res.sessions)) ? res.sessions : null;
					let hintEl = document.getElementById('ipsec_clients_hint');
					if (sessions === null) {
						if (hintEl) hintEl.textContent = _('Failed to retrieve VPN client information.');
						clientBody.textContent = '';
						return;
					}
					if (sessions.length === 0) {
						if (hintEl) hintEl.textContent = _('No VPN clients are connected.');
						clientBody.textContent = '';
						return;
					}
					if (hintEl) hintEl.textContent = '';
					renderRows(sessions);
				});
			};

			poll.add(update, 5);
			update();

			let clearBtn = E('button', {
				'class': 'btn cbi-button-remove',
				'click': function(ev) {
					ev.preventDefault();
					if (!window.confirm(_('Clear all client history records?')))
						return;
					L.resolveDefault(callClearHistory(), {}).then(function() {
						return update();
					});
				}
			}, [ _('Clear history') ]);

			return E('div', { 'class': 'cbi-section cbi-tblsection' }, [
				E('div', {}, [ E('h3', _('IPSec VPN Clients')), clearBtn ]),
				hint,
				clientTable
			]);
		};

		// 保存后显式 restart 服务：LuCI 保存走 uci commit，不会触发 procd 的
		// config.change reload trigger（实测 commit/reload_config 均不重启服务），
		// 必须显式 rc.init restart 才能让启用/停用即时生效。
		m.save = function(ev) {
			return form.Map.prototype.save.call(this).then(function() {
				return L.resolveDefault(callServiceInit('ipsec-vpnd', 'restart'));
			});
		};

		return m.render();
	}
});
