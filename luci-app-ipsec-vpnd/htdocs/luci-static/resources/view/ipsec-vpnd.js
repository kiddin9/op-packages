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

const callIpsecApply = rpc.declare({
	object: 'ipsec-vpnd',
	method: 'apply',
	expect: { '': {} }
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

const callIpsecDeps = rpc.declare({
	object: 'ipsec-vpnd',
	method: 'deps',
	expect: { '': {} }
});

const callIpsecStatus = rpc.declare({
	object: 'ipsec-vpnd',
	method: 'status',
	expect: { '': {} }
});

function getServiceStatus() {
	// 后端直接报两件事：UCI 里的 enabled 总开关，以及系统 ipsec 服务是否在跑。
	// 只看服务状态会出现"开关是关的、服务却在跑"这种自相矛盾的情况。
	return L.resolveDefault(callIpsecStatus(), {}).then(function(res) {
		return {
			enabled: (res && res.enabled === '1'),
			running: !!(res && res.running)
		};
	});
}

function renderStatus(st) {
	let spanTemp = '<em><span style="color:%s"><strong>%s %s</strong></span></em>';
	let renderHTML;

	if (!st.enabled)
		renderHTML = spanTemp.format('orange', _('IPSec VPN'), _('DISABLED'));
	else if (st.running)
		renderHTML = spanTemp.format('green', _('IPSec VPN'), _('RUNNING'));
	else
		renderHTML = spanTemp.format('red', _('IPSec VPN'), _('NOT RUNNING'));

	return renderHTML;
}

return view.extend({
	render() {
		let m, s, o;

		// 配置落盘成功后，渲染 ipsec.conf 并按 enabled 启停服务。
		// 挂在 "uci-applied" 上是为了保证读到的是**已经落盘**的配置。
		if (!document.ipsecVpndApplyHook) {
			document.ipsecVpndApplyHook = true;
			document.addEventListener('uci-applied', function() {
				L.resolveDefault(callIpsecApply(), {});
			});
		}

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

		// 依赖诊断：strongSwan 运行时不全时，页面直接说明缺什么、怎么装。
		// 没有这块的话，用户只会看到 NOT RUNNING，无从判断是缺包还是配置问题。
		s = m.section(form.TypedSection);
		s.anonymous = true;
		s.render = function() {
			let box = E('div', { class: 'cbi-section-error' });
			let wrap = E('div', { id: 'ipsec_vpnd_deps_wrap', style: 'display:none' }, [ box ]);

			let update = function() {
				return L.resolveDefault(callIpsecDeps(), {}).then(function(res) {
					let files = (res && Array.isArray(res.files)) ? res.files : [];
					let missing = files.filter(function(d) { return d.status !== 'ok'; });
					if (missing.length === 0) {
						wrap.style.display = 'none';
						return;
					}
					wrap.style.display = '';
					box.textContent = '';
					box.appendChild(E('h3', {}, _('Missing dependencies')));
					missing.forEach(function(d) {
						box.appendChild(E('p', {}, d.detail || d.key));
					});
					box.appendChild(E('p', {}, _('Install the missing packages with:')));
					let mgr = (res && res.pkg_mgr === 'opkg') ? 'opkg' : 'apk';
					let cmd = (mgr === 'opkg')
						? 'opkg update && opkg install strongswan-minimal strongswan-mod-xauth-generic strongswan-mod-kernel-libipsec strongswan-mod-des'
						: 'apk update && apk add strongswan-minimal strongswan-mod-xauth-generic strongswan-mod-kernel-libipsec strongswan-mod-des';
					box.appendChild(E('pre', {}, cmd));
				});
			};

			poll.add(update, 15);
			update();

			return wrap;
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
					// 在线但还没拿到虚拟地址：CHILD_SA 尚未装好，或解析不到 /32
					// 选择器。给一句明确提示，别让用户对着 "-" 猜。
					let vipText = s.vip;
					if (!vipText)
						vipText = s.vip_pending ? _('Assigned IP pending') : '-';
					clientBody.appendChild(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, s.user || '-'),
						E('td', { 'class': 'td' }, s.remote || '-'),
						E('td', { 'class': 'td' }, vipText),
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

		// 保存只负责把改动交给 LuCI 暂存；真正落盘（apply）由页面在所有 map
		// 保存完之后统一触发，落盘成功时 LuCI 会在 document 上派发 "uci-applied"。
		//
		// 渲染配置、启停服务必须放在那个事件里：早一步的话渲染器读到的是
		// 落盘前的旧值 —— 结果就是"启用"开关点了没反应（配置存下去了，
		// ipsec.conf 还是按旧的 enabled 生成的）。
		m.save = function(ev) {
			return form.Map.prototype.save.call(this);
		};

		return m.render();
	}
});
