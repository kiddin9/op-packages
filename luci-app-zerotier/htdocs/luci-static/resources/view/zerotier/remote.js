'use strict';
'require view';
'require ui';
'require rpc';
'require uci';


/* This firmware ships no client-side i18n bridge: cbi.js's _() reads
 * window.TR but nothing populates it, so JS views render English even with
 * .lmo catalogs installed. Install our own catalog before the first string
 * is needed; idempotent and harmless on firmware that does bridge. */
var ZT_TR = /^zh/i.test(document.documentElement.lang || '')
    ? new Promise(function(resolve) {
        var s = document.createElement('script');
        s.onload = s.onerror = function() { resolve(); };
        s.src = L.env.resource + '/zerotier/tr-zh-cn.js';
        document.head.appendChild(s);
    })
    : Promise.resolve();/*
 * Remote Controller / Moon management.
 *
 * The LuCI page lives on the OpenWrt router, but the Controller and Moon root
 * live on a separate machine with a fixed public IP. Everything here reaches
 * that machine over an SSH-forwarded loopback port; see zerotier-remote.sh for
 * why a tunnel is the only option (no TLS on the control plane, and
 * allowManagementFrom rejects every non-loopback caller).
 *
 * Every remote call costs an SSH handshake (~1-3s), so this page deliberately
 * does NOT poll the way the local Interface Info page does. Diagnostics are
 * refreshed on demand and after mutations.
 */

var rpcHostList = rpc.declare({ object: 'luci-zerotier', method: 'remote_list' });
var rpcHostSet = rpc.declare({
	object: 'luci-zerotier', method: 'remote_host_set',
	params: [ 'section', 'name', 'host', 'port', 'user', 'controller_port', 'private_key' ]
});
var rpcHostDel = rpc.declare({ object: 'luci-zerotier', method: 'remote_host_del', params: [ 'section' ] });
var rpcDiagnose = rpc.declare({ object: 'luci-zerotier', method: 'remote_diagnose', params: [ 'section' ] });
var rpcCtlGet = rpc.declare({ object: 'luci-zerotier', method: 'remote_ctl_get', params: [ 'section', 'path' ] });
var rpcNetSet = rpc.declare({ object: 'luci-zerotier', method: 'remote_network_set', params: [ 'section', 'nwid', 'body' ] });
var rpcNetDel = rpc.declare({ object: 'luci-zerotier', method: 'remote_network_del', params: [ 'section', 'nwid' ] });
var rpcMemberSet = rpc.declare({ object: 'luci-zerotier', method: 'remote_member_set', params: [ 'section', 'nwid', 'member_id', 'body' ] });
var rpcMemberList = rpc.declare({ object: 'luci-zerotier', method: 'remote_member_list', params: [ 'section', 'nwid' ] });
var rpcNetworkList = rpc.declare({ object: 'luci-zerotier', method: 'remote_network_list', params: [ 'section' ] });
var rpcPeerList  = rpc.declare({ object: 'luci-zerotier', method: 'remote_peer_list',  params: [ 'section' ] });
var rpcMoonPlan = rpc.declare({ object: 'luci-zerotier', method: 'remote_moon_plan', params: [ 'section' ] });
var rpcMoonApply = rpc.declare({ object: 'luci-zerotier', method: 'remote_moon_apply', params: [ 'section', 'confirm' ] });

function errText(res, fallback) {
	if (!res) return fallback;
	if (res.error) return res.error;
	return fallback;
}

function yn(v, t, f) {
	return E('span', { 'style': 'color: ' + (v ? 'green' : 'orange') }, [ v ? t : f ]);
}

/* ------------------------------------------------------------------ hosts */

function hostEditor(section, host, onSaved) {
	var isNew = !section;
	var f = section || '';

	var nameI = E('input', { 'type': 'text', 'id': 'zt_r_name', 'value': (host && host.name) || '', 'placeholder': _('My controller') });
	var hostI = E('input', { 'type': 'text', 'id': 'zt_r_host', 'value': (host && host.host) || '', 'placeholder': '203.0.113.10' });
	var portI = E('input', { 'type': 'number', 'id': 'zt_r_port', 'value': (host && host.port) || '22', 'min': '1', 'max': '65535' });
	var userI = E('input', { 'type': 'text', 'id': 'zt_r_user', 'value': (host && host.user) || 'root' });
	var cportI = E('input', { 'type': 'number', 'id': 'zt_r_cport', 'value': (host && host.controller_port) || '27893', 'min': '1', 'max': '65535' });
	var keyI = E('textarea', {
		'id': 'zt_r_key', 'rows': '6', 'style': 'width:100%; font-family:monospace; font-size:12px;',
		'placeholder': isNew
			? _('Required: paste the PRIVATE key of a keypair whose public half is in the remote ~/.ssh/authorized_keys')
			: _('Leave blank to keep the stored key')
	});

	var msg = E('div', { 'style': 'color:red; margin-top:6px;' });
	var saveBtn = E('button', { 'class': 'cbi-button cbi-button-action important' }, [ _('Save') ]);
	var cancelBtn = E('button', { 'class': 'cbi-button', 'click': function() { hostEditor.close(); } }, [ _('Cancel') ]);

	saveBtn.addEventListener('click', function() {
		msg.textContent = '';
		saveBtn.disabled = true;
		var sectName = f || ('zt' + Date.now().toString(36));
		L.resolveDefault(rpcHostSet(
			sectName, nameI.value, hostI.value, portI.value,
			userI.value, cportI.value, keyI.value), {})
		.then(function(res) {
			if (res && res.code === 0) {
				hostEditor.close();
				onSaved();
			} else {
				msg.textContent = errText(res, _('Could not save the host'));
				saveBtn.disabled = false;
			}
		}).catch(function() {
			msg.textContent = _('Could not save the host');
			saveBtn.disabled = false;
		});
	});

	hostEditor.body = E('div', { 'class': 'cbi-section' }, [
		E('h3', {}, [ isNew ? _('Add a remote host') : _('Edit remote host') ]),
		E('div', { 'class': 'cbi-value' }, [ E('label', {}, [_('Label')]), E('div', {}, [ nameI ]) ]),
		E('div', { 'class': 'cbi-value' }, [ E('label', {}, [_('Public IP or host')]), E('div', {}, [ hostI ]) ]),
		E('div', { 'class': 'cbi-value' }, [ E('label', {}, [_('SSH port')]), E('div', {}, [ portI ]) ]),
		E('div', { 'class': 'cbi-value' }, [ E('label', {}, [_('SSH user')]), E('div', {}, [ userI ]) ]),
		E('div', { 'class': 'cbi-value' }, [ E('label', {}, [_('Controller port')]), E('div', {}, [ cportI, E('div', { 'class': 'cbi-value-description' }, [_('The port the controller API listens on, e.g. 27893. Only reachable through the SSH tunnel.')]) ]) ]),
		E('div', { 'class': 'cbi-value' }, [ E('label', {}, [_('SSH private key')]), E('div', {}, [ keyI ]) ]),
		msg,
		E('div', { 'style': 'margin-top:10px; display:flex; gap:8px;' }, [ saveBtn, cancelBtn ])
	]);
	hostEditor.open();
}

hostEditor.open = function() {
	hostEditor.modal = ui.showModal(_('Remote host'), hostEditor.body);
};
hostEditor.close = function() {
	if (hostEditor.modal) { ui.hideModal(); hostEditor.modal = null; }
};

/* ------------------------------------------------------------- diagnostics */

function diagnostics(section, host) {
	var box = E('div', { 'style': 'margin-top:8px;' });
	var btn = E('button', { 'class': 'cbi-button cbi-button-action' }, [ _('Run diagnostics') ]);

	function row(k, v) {
		return E('tr', {}, [ E('td', { 'style': 'width:220px;' }, [ k ]), E('td', {}, [ v ]) ]);
	}

	function paint(res) {
		while (box.firstChild) box.removeChild(box.firstChild);
		if (!res || res.code !== 0) {
			box.appendChild(E('div', { 'style': 'color:red;' }, [ errText(res, _('Diagnostics failed')) ]));
			return;
		}
		box.appendChild(E('table', { 'class': 'table' }, [
			E('tr', {}, [ E('th', { 'colspan': '2' }, [_('Remote host report')]) ]),
			row(_('Operating system'), res.os || '-'),
			row(_('Passwordless sudo'), yn(res.sudo, _('yes'), _('no — required'))),
			row(_('ZeroTier installed'), yn(res.zerotier_installed, _('yes'), _('no'))),
			row(_('ZeroTier version'), res.zerotier_version || '-'),
			row(_('Service state'), res.zerotier_service || '-'),
			row(_('Node address'), E('code', {}, [ res.identity || '-' ])),
			row(_('Controller state present'), res.controller_state ? _('yes') : _('no')),
			row(_('Controller reachable via tunnel'), yn(res.controller_reachable, _('yes'), _('no'))),
			row(_('moon.json on host'), res.moon_json_present ? _('yes') : _('no')),
			row(_('Signed .moon files'), String(res.moon_files || 0))
		]));
	}

	btn.addEventListener('click', function() {
		btn.disabled = true;
		btn.textContent = _('Running...');
		while (box.firstChild) box.removeChild(box.firstChild);
		L.resolveDefault(rpcDiagnose(section), {}).then(function(res) {
			paint(res);
			btn.disabled = false;
			btn.textContent = _('Run diagnostics');
		}).catch(function() {
			paint(null);
			btn.disabled = false;
			btn.textContent = _('Run diagnostics');
		});
	});

	return E('div', {}, [ btn, box ]);
}

/* ---------------------------------------------------------------- networks */

function networksPanel(section) {
	var box = E('div', { 'style': 'margin-top:8px;' });
	var refresh = E('button', { 'class': 'cbi-button cbi-button-action' }, [ _('Refresh') ]);
	var add = E('button', { 'class': 'cbi-button cbi-button-add' }, [ _('Create network') ]);
	var table = E('div', {});

	/* One row of the pool editor. The pool is {ipRangeStart, ipRangeEnd} and
	 * the route needs a CIDR target, so start/end are validated separately. */
	function poolRow(pool, onChange) {
		var s = E('input', { 'type': 'text', 'value': (pool && pool.ipRangeStart) || '', 'placeholder': '192.168.192.1', 'style': 'width:130px;' });
		var e = E('input', { 'type': 'text', 'value': (pool && pool.ipRangeEnd) || '', 'placeholder': '192.168.192.254', 'style': 'width:130px;' });
		var rm = E('button', { 'class': 'cbi-button cbi-button-remove' }, [ _('Remove') ]);
		rm.addEventListener('click', function() { onChange(null, s, e); });
		return { el: E('tr', {}, [
			E('td', {}, [ s ]), E('td', {}, [ e ]),
			E('td', { 'style': 'text-align:right;' }, [ rm ])
		]), start: s, end: e };
	}

	function routeRow(rt, onChange) {
		var t = E('input', { 'type': 'text', 'value': (rt && rt.target) || '', 'placeholder': '192.168.192.0/24', 'style': 'width:150px;' });
		var v = E('input', { 'type': 'text', 'value': (rt && typeof rt.via === 'string') ? rt.via : '', 'placeholder': _('empty = direct'), 'style': 'width:150px;' });
		var rm = E('button', { 'class': 'cbi-button cbi-button-remove' }, [ _('Remove') ]);
		rm.addEventListener('click', function() { onChange(null, t, v); });
		return { el: E('tr', {}, [
			E('td', {}, [ t ]), E('td', {}, [ v ]),
			E('td', { 'style': 'text-align:right;' }, [ rm ])
		]), target: t, via: v };
	}

	function isIp(s) { return /^(\d{1,3}\.){3}\d{1,3}$/.test(s) && s.split('.').every(function (o) { return +o >= 0 && +o <= 255; }); }
	function isCidr(s) {
		var m = /^([0-9.]+)\/(\d{1,2})$/.exec(s);
		return !!m && isIp(m[1]) && +m[2] >= 0 && +m[2] <= 32;
	}

	function netRow(nw) {
		/* ztncui-style rename: the name is a plain span with an edit glyph;
		 * the whole-form Save below commits the last accepted value via
		 * netName, not a live input. */
		var netName = nw.name || '';
		var nameWrap = E('span', { 'style': 'white-space:nowrap;' }, []);
		var nameBusy = false, nameAfterKey = false;
		var nameEdit = E('a', {
			'href': '#', 'title': _('Rename'),
			'style': 'margin-left:6px; text-decoration:none; cursor:pointer;',
			'click': function(ev) { ev.preventDefault(); startRename(); }
		}, [ '✎' ]);
		function drawNameSpan() {
			while (nameWrap.firstChild) nameWrap.removeChild(nameWrap.firstChild);
			nameWrap.appendChild(E('span', {}, [ netName ]));
			nameWrap.appendChild(nameEdit);
		}
		function startRename() {
			if (nameBusy) return;
			while (nameWrap.firstChild) nameWrap.removeChild(nameWrap.firstChild);
			var inp = E('input', { 'type': 'text', 'value': netName, 'style': 'width:150px;' });
			nameWrap.appendChild(inp);
			if (inp.focus) inp.focus();
			function close() { nameBusy = false; drawNameSpan(); }
			function doCommit() {
				var v = inp.value;
				if (v === netName) { close(); return; }
				nameBusy = true;
				L.resolveDefault(rpcNetSet(section, nw.nwid, JSON.stringify({ name: v })), {}).then(function(res) {
					if (res && res.code === 200) netName = v;
					else ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(res, _('Rename failed')) ]), 'warning');
					close();
				});
			}
			inp.addEventListener('keydown', function(ev) {
				if (ev.keyCode === 13) { ev.preventDefault(); nameAfterKey = true; doCommit(); }
				else if (ev.keyCode === 27) { inp.value = netName; close(); }
			});
			inp.addEventListener('blur', function() {
				if (nameAfterKey) { nameAfterKey = false; return; }
				doCommit();
			});
		}
		drawNameSpan();
		var bcast = E('input', { 'type': 'checkbox' });
		bcast.checked = !!nw.enableBroadcast;

		var mtu = E('input', { 'type': 'number', 'value': nw.mtu || 2800, 'min': '1280', 'max': '10000', 'style': 'width:90px;' });
		var mlimit = E('input', { 'type': 'number', 'value': (nw.multicastLimit == null ? 32 : nw.multicastLimit), 'min': '0', 'style': 'width:80px;' });
		var priv = E('input', { 'type': 'checkbox' });
		priv.checked = nw.private !== false;

		/* Scalars are merged by the controller (every field is guarded by a
		 * presence check server-side), but routes and ipAssignmentPools are
		 * arrays replaced wholesale -- so those are read, edited here and
		 * written back whole. Verified against 1.14.2 behaviour, not assumed. */
		var pools = (nw.ipAssignmentPools || []).slice();
		var routes = (nw.routes || []).slice();
		var poolTbl = E('tbody', {});
		var routeTbl = E('tbody', {});

		/* drawPools re-renders from the model, so the input references handed
		 * back by poolRow are captured here and used to focus the new row.
		 * Walking childNodes by index would silently break if the table
		 * structure ever changed. */
		var lastPoolInputs = null;
		function drawPools() {
			while (poolTbl.firstChild) poolTbl.removeChild(poolTbl.firstChild);
			lastPoolInputs = null;
			pools.forEach(function (p, i) {
				var r = poolRow(p, function () { pools.splice(i, 1); drawPools(); });
				poolTbl.appendChild(r.el);
				lastPoolInputs = r;
			});
			if (!pools.length) poolTbl.appendChild(E('tr', {}, [ E('td', { 'colspan': '3', 'style': 'color:orange;' }, [ _('No pool — members get no managed address') ]) ]));
		}
		function drawRoutes() {
			while (routeTbl.firstChild) routeTbl.removeChild(routeTbl.firstChild);
			routes.forEach(function (r, i) {
				routeTbl.appendChild(routeRow(r, function () { routes.splice(i, 1); drawRoutes(); }).el);
			});
			if (!routes.length) routeTbl.appendChild(E('tr', {}, [ E('td', { 'colspan': '3', 'style': 'color:orange;' }, [ _('No route') ]) ]));
		}

		function addPool() {
			pools.push({ ipRangeStart: '', ipRangeEnd: '' });
			drawPools();
			if (lastPoolInputs && lastPoolInputs.start.focus) lastPoolInputs.start.focus();
		}
		function addRoute() { routes.push({ target: '', via: null }); drawRoutes(); }

		drawPools(); drawRoutes();

		/* A pool without a route covering the same subnet leaves members with
		 * no address: the pool is allocated but never installed, and the member
		 * list then shows no IP with no indication why. Reads the live input
		 * values so it reflects unsaved edits. */
		function poolWarning() {
			var rows = poolTbl.childNodes, nets = [], i, j;
			for (i = 0; i < rows.length; i++) {
				var s = rows[i].childNodes[0] && rows[i].childNodes[0].childNodes[0];
				if (!s) continue;
				var sv = (s.value || '').trim();
				if (!sv || !isIp(sv)) continue;
				nets.push(sv.split('.').slice(0, 3).join('.') + '.0/24');
			}
			if (!nets.length) return null;
			var rrows = routeTbl.childNodes, targets = [];
			for (j = 0; j < rrows.length; j++) {
				var t = rrows[j].childNodes[0] && rrows[j].childNodes[0].childNodes[0];
				if (t && (t.value || '').trim()) targets.push(t.value.trim());
			}
			for (i = 0; i < nets.length; i++) {
				if (targets.indexOf(nets[i]) === -1) {
					return _('No route covers ') + nets[i] +
						_(' — members will not receive an address from this pool.');
				}
			}
			return null;
		}

		var save = E('button', { 'class': 'cbi-button cbi-button-apply' }, [ _('Save') ]);
		save.addEventListener('click', function() {
			var warn = poolWarning();
			if (warn && !confirm(warn + '\n\n' + _('Save anyway?'))) return;

			var newPools = [], newRoutes = [], bad = null;
			poolTbl.childNodes.forEach(function (tr) {
				var s = tr.childNodes[0] && tr.childNodes[0].childNodes[0];
				var e = tr.childNodes[1] && tr.childNodes[1].childNodes[0];
				if (!s || !e) return;
				var sv = (s.value || '').trim(), ev = (e.value || '').trim();
				if (!sv && !ev) return;
				if (!isIp(sv) || !isIp(ev)) { bad = _('Pool bounds must be IPv4 addresses'); return; }
				newPools.push({ ipRangeStart: sv, ipRangeEnd: ev });
			});
			if (bad) { ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ bad ]), 'warning'); return; }

			routeTbl.childNodes.forEach(function (tr) {
				var t = tr.childNodes[0] && tr.childNodes[0].childNodes[0];
				var v = tr.childNodes[1] && tr.childNodes[1].childNodes[0];
				if (!t) return;
				var tv = (t.value || '').trim(), vv = (v && v.value || '').trim();
				if (!tv) return;
				if (!isCidr(tv)) { bad = _('Route target must be CIDR, e.g. 192.168.192.0/24'); return; }
				if (vv && !isIp(vv)) { bad = _('Route via must be an IPv4 address, or empty for a direct route'); return; }
				newRoutes.push({ target: tv, via: vv || null });
			});
			if (bad) { ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ bad ]), 'warning'); return; }

			/* v4AssignMode.zt must be enabled for a pool to hand out addresses at
			 * all -- with it false the pool is stored but nothing is allocated,
			 * silently. Verified on 1.14.2: identical pool+routes produce
			 * ipAssignments:[] without it and a real address with it. Sent
			 * unconditionally so a cleared pool also switches assignment off
			 * rather than leaving it dangling.
			 *
			 * The object form is required. The published tutorial shows the
			 * string "zt", but the schema defines an object and the daemon
			 * ignores a wrongly-typed field without complaint. */
		var body = JSON.stringify({
			name: netName,
				enableBroadcast: bcast.checked,
				private: priv.checked,
				mtu: parseInt(mtu.value, 10) || 2800,
				multicastLimit: parseInt(mlimit.value, 10) || 0,
				ipAssignmentPools: newPools,
				routes: newRoutes,
				v4AssignMode: { zt: newPools.length > 0 }
			});

			save.disabled = true;
			L.resolveDefault(rpcNetSet(section, nw.nwid, body), {}).then(function(res) {
				if (res && res.code === 200) load();
				else ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(res, _('Update failed')) ]), 'warning');
				save.disabled = false;
			});
		});

		var del = E('button', {
			'class': 'cbi-button cbi-button-remove',
			'click': function() {
				if (!confirm(_('Delete network ') + nw.nwid + '? Members will lose connectivity.')) return;
				del.disabled = true;
				L.resolveDefault(rpcNetDel(section, nw.nwid), {}).then(function(res) {
					if (res && res.code === 0) load();
					else ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(res, _('Delete failed')) ]), 'warning');
					del.disabled = false;
				});
			}
		}, [ _('Delete') ]);

		var members = E('div', { 'style': 'margin-top:6px; padding-left:12px;' });
		var mToggle = E('button', { 'class': 'cbi-button' }, [ _('Members') ]);
		mToggle.addEventListener('click', function() {
			if (members.firstChild) { while (members.firstChild) members.removeChild(members.firstChild); return; }
			loadMembers(nw.nwid, members);
		});

		var cfg = E('div', { 'style': 'margin-top:8px; padding-left:12px;' }, [
			E('div', { 'style': 'display:flex; gap:10px; flex-wrap:wrap; align-items:center; margin-bottom:6px;' }, [
				E('label', {}, [ _('MTU')]), mtu,
				E('label', {}, [ _('Multicast limit')]), mlimit,
				E('label', {}, [ _('Private')]), priv
			]),
			E('div', { 'style': 'font-weight:bold; margin-top:6px;' }, [ _('IP assignment pools') ]),
			E('div', { 'style': 'color:#666; font-size:12px;' }, [
				_('The controller allocates addresses from these ranges and reports them per member.')
			]),
			E('table', { 'class': 'table' }, [
				E('tr', {}, [ E('th', {}, [_('First IP')]), E('th', {}, [_('Last IP')]), E('th', {}) ]),
				poolTbl
			]),
			E('button', { 'class': 'cbi-button cbi-button-add', 'click': addPool }, [ _('Add pool') ]),
			E('div', { 'style': 'font-weight:bold; margin-top:10px;' }, [ _('Routes') ]),
			E('div', { 'style': 'color:#666; font-size:12px;' }, [
				_('A pool needs a route covering the same subnet, otherwise members receive no address.')
			]),
			E('table', { 'class': 'table' }, [
				E('tr', {}, [ E('th', {}, [_('Target')]), E('th', {}, [_('Via')]), E('th', {}) ]),
				routeTbl
			]),
			E('button', { 'class': 'cbi-button cbi-button-add', 'click': addRoute }, [ _('Add route') ])
		]);
		var cToggle = E('button', { 'class': 'cbi-button' }, [ _('Configure') ]);
		cToggle.addEventListener('click', function() {
			if (cfg.style.display === 'none') { cfg.style.display = 'block'; cToggle.textContent = _('Hide'); }
			else { cfg.style.display = 'none'; cToggle.textContent = _('Configure'); }
		});
		cfg.style.display = 'none';

		/* The editors live outside the network <table> on purpose. Nested
		 * tables share column widths, so a wide pool form stretched the nwid
		 * column until the address broke to one character per line. */
		return E('div', { 'style': 'margin-bottom:14px;' }, [
			E('table', {
				'class': 'table',
				/* auto layout ignores a width on a lone cell and shrinks the
				 * column to the widest unbreakable content, which is one hex
				 * character. Fixed layout honours the column widths below. */
				'style': 'table-layout:fixed; width:100%;'
			}, [ E('tr', {}, [
				E('td', { 'style': 'width:170px; font-family:monospace; white-space:nowrap;' }, [ nw.nwid ]),
				E('td', { 'style': 'width:auto;' }, [ nameWrap ]),
				E('td', { 'style': 'width:90px; text-align:center; white-space:nowrap;' }, [ bcast ]),
				E('td', { 'style': 'width:280px; text-align:right;' }, [
					E('div', { 'style': 'display:flex; flex-wrap:wrap; gap:4px; justify-content:flex-end;' },
						[ save, cToggle, mToggle, del ])
				])
			]) ]),
			E('div', { 'style': 'padding-left:12px;' }, [ cfg, members ])
		]);
	}

	function loadMembers(nwid, into) {
		into.appendChild(E('div', { 'style': 'color:orange;' }, [ _('Loading...') ]));
		/* remote_member_list collapses what used to be an N+1 chain (one
		 * SSH round-trip per member: 30-90s for a 29-member network) into
		 * one call, and remote_peer_list supplies live online / version /
		 * path state in a second. Two parallel calls are fine; the old
		 * comment's warning was about firing thirty at once. */
		Promise.all([
			L.resolveDefault(rpcMemberList(section, nwid), {}),
			L.resolveDefault(rpcPeerList(section), {})
		]).then(function(r) {
			var mres = r[0], pres = r[1];
			/* remote_ctl_get reports the tunnelled HTTP status (200) while
			 * remote_member_set / the batch list calls report the helper's
			 * own 0-for-success; both conventions live on this page, so
			 * accept either. */
			function okList(res) {
				return !!(res && (res.code === 0 || res.code === 200) && Array.isArray(res.body));
			}
			var mok = okList(mres), pok = okList(pres);
			while (into.firstChild) into.removeChild(into.firstChild);
			if (!mok) {
				into.appendChild(E('div', { 'style': 'color:red;' }, [ errText(mres, _('Could not list members')) ]));
				return;
			}
			/* A failed peer list must not fabricate an all-OFFLINE table:
			 * render the members with '-' and a muted note instead. */
			if (!pok)
				into.appendChild(E('div', { 'style': 'color:#888; font-size:12px; margin-bottom:4px;' }, [ _('Peer status unavailable') ]));
			var idI = E('input', { 'type': 'text', 'placeholder': _('Node address (10 hex)'), 'style': 'width:180px;' });
			var authBtn = E('button', { 'class': 'cbi-button cbi-button-add' }, [ _('Authorize') ]);
			authBtn.addEventListener('click', function() {
				var mid = idI.value.trim();
				if (!/^[0-9a-fA-F]{10}$/.test(mid)) {
					ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ _('A node address is exactly 10 hex digits') ]), 'warning');
					return;
				}
				authBtn.disabled = true;
				var body2 = JSON.stringify({ authorized: true, activeBridge: false, capability: null, id: mid, name: '', nodeId: mid });
				L.resolveDefault(rpcMemberSet(section, nwid, mid, body2), {}).then(function(r2) {
					if (r2 && r2.code === 0) { idI.value = ''; loadMembers(nwid, into); }
					else ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(r2, _('Authorize failed')) ]), 'warning');
					authBtn.disabled = false;
				});
			});

			into.appendChild(E('div', { 'style': 'display:flex; gap:6px; align-items:center; margin:6px 0;' }, [ idI, authBtn ]));

		/* The member objects are the cached model: every inline edit commits
		 * against its entry here and the filter re-renders from it, so no
		 * keystroke ever costs an SSH round-trip. */
		var membersArr = mres.body;
		var missingIds = Array.isArray(mres.skipped) ? mres.skipped : [];
		if (!membersArr.length) {
			/* An empty body with skipped entries is every read failing, not
			 * an empty network: say so instead of a success message. */
			if (missingIds.length) {
				into.appendChild(E('div', { 'style': 'color:red;' }, [
					_('Could not read any member of this network') + ' (' + missingIds.length + ')' ]));
				return;
			}
			into.appendChild(E('div', { 'style': 'color:orange;' }, [ _('No members have joined this network yet.') ]));
			return;
		}

		/* The controller's own node address is the first 10 hex of the nwid,
		 * which is why e.g. f08c171006 shows as CONTROLLER. This must be
		 * checked before the online test: a node never peers with itself,
		 * so the controller is absent from the peer list and would
		 * otherwise render OFFLINE. */
		var controllerAddr = nwid.substring(0, 10);
		var peerMap = {};
		if (pok) pres.body.forEach(function(p) { if (p && p.address) peerMap[p.address] = p; });

		/* Online = at least one non-expired physical path. An absent peer
		 * and a peer whose paths have all expired are both OFFLINE. */
		function isOnline(p) {
			if (!p || !Array.isArray(p.paths)) return false;
			for (var i = 0; i < p.paths.length; i++)
				if (p.paths[i] && p.paths[i].expired !== true) return true;
			return false;
		}
		/* PLANET and root peers legitimately report versionMajor -1
		 * ("version":"-1.-1.-1"); a negative or missing major means "no
		 * version", not a version to render. */
		function peerVersion(p) {
			if (!p || p.versionMajor == null || p.versionMajor < 0) return null;
			return 'v' + p.versionMajor + '.' + p.versionMinor + '.' + (p.versionRev || 0);
		}
		function pickPath(p) {
			if (!p || !Array.isArray(p.paths) || !p.paths.length) return null;
			var i, pth = null;
			for (i = 0; i < p.paths.length; i++) if (p.paths[i] && p.paths[i].preferred) { pth = p.paths[i]; break; }
			if (!pth) for (i = 0; i < p.paths.length; i++) if (p.paths[i] && p.paths[i].active) { pth = p.paths[i]; break; }
			return pth || p.paths[0];
		}

		/* ------------------------------------------------------------ refresh
		 *
		 * Every remote call costs an SSH handshake (~2.05s measured on the
		 * target), and that cost is the handshake, not the member count: one
		 * member and 31 members both bottom out at ~2.05s, the 30 extra
		 * fetches adding ~0.6s together. So a refresh re-reads exactly the
		 * member that changed and leaves every other row -- including one the
		 * user is typing into -- untouched. Full redraws would also throw away
		 * the filter text and the scroll position.
		 *
		 * peerMap and pok are refreshed alongside because peer state changes
		 * on its own (a node connects, a path expires) and it costs nothing
		 * extra to fetch in parallel with the member.
		 *
		 * rowRefs maps member id to that row's live cells, so a refresh can
		 * repaint one row in place instead of rebuilding the tbody.
		 */
		var rowRefs = {};

		function applyPeers(peers) {
			pok = Array.isArray(peers);
			peerMap = {};
			if (pok) peers.forEach(function(p) { if (p && p.address) peerMap[p.address] = p; });
			for (var mid in rowRefs) {
				var r = rowRefs[mid];
				if (!r) continue;
				paint(r.status, r.statusText());
				paint(r.addr, r.addrText());
			}
		}
		function paint(td, text) {
			while (td.firstChild) td.removeChild(td.firstChild);
			td.appendChild(typeof text === 'string' ? document.createTextNode(text) : text);
		}

		function refreshMember(mid) {
			return Promise.all([
				L.resolveDefault(rpcCtlGet(section, '/controller/network/' + nwid + '/member/' + mid), {}),
				L.resolveDefault(rpcPeerList(section), {})
			]).then(function (r) {
				var cres = r[0], pres2 = r[1];
				if (pres2 && (pres2.code === 0 || pres2.code === 200) && Array.isArray(pres2.body))
					applyPeers(pres2.body);
				if (!cres || cres.code !== 200 || !cres.body) return null;
				/* Merge onto the cached model rather than replacing the row, so
				 * an input the user is focused in keeps focus and value. */
				var m = null;
				for (var i = 0; i < membersArr.length; i++)
					if (membersArr[i].id === mid) { m = membersArr[i]; break; }
				if (!m) return null;
				m.name = cres.body.name || '';
				m.authorized = !!cres.body.authorized;
				m.activeBridge = !!cres.body.activeBridge;
				m.ipAssignments = cres.body.ipAssignments || [];
				m.vMajor = cres.body.vMajor;
				m.vMinor = cres.body.vMinor;
				m.revision = cres.body.revision;
				var r = rowRefs[mid];
				if (r) {
					r.paintIp();
					r.authCb.checked = m.authorized;
					r.bridgeCb.checked = m.activeBridge;
				}
				return m;
			});
		}

		/* How long after authorizing the address actually appears. Measured on a
		 * real 1.14.2 controller: the POST returns in 1ms with authorized=true
		 * but ipAssignments stays empty at +1s, +2s and +4s, and the address
		 * is there at +8s -- the node has to re-fetch the network config and
		 * come up before the controller assigns it. So the row is marked
		 * "assigning" immediately and re-read once after that delay; fetching
		 * right away would always read an empty list and look like a failure. */
		var IP_ASSIGN_DELAY = 11000;
		var stamp = E('span', { 'style': 'color:#888; font-size:12px;' }, []);
		function setStamp() {
			var d = new Date();
			function p2(n) { return (n < 10 ? '0' : '') + n; }
			while (stamp.firstChild) stamp.removeChild(stamp.firstChild);
			stamp.appendChild(E('span', {}, [ _('updated') + ' ' + p2(d.getHours()) + ':' + p2(d.getMinutes()) + ':' + p2(d.getSeconds()) ]));
		}

		var filterI = E('input', { 'type': 'text', 'placeholder': _('Filter by name, address or IP'), 'style': 'width:220px; margin-right:8px;' });
		var counterHost = E('span', { 'style': 'color:#888; font-size:12px;' }, []);
		var tbody = E('tbody', {});

		/* Pending / saved / failed on a narrow column: signal with the input
		 * border and clear it shortly after, rather than a status element. */
		function flashBorder(el, color) {
			el.style.borderColor = color;
			setTimeout(function() { el.style.borderColor = ''; }, 1500);
		}
		function setCounter(shown) {
			while (counterHost.firstChild) counterHost.removeChild(counterHost.firstChild);
			var txt = shown + ' / ' + (membersArr.length + missingIds.length) + ' ' + _('members');
			if (missingIds.length) txt += ' (' + missingIds.length + ' ' + _('unreadable') + ')';
			counterHost.appendChild(E('span', {}, [ txt ]));
		}

		/* Inline edits post single-field bodies on purpose: the controller
		 * merges presence-checked scalars, and the ztncui reference UI posts
		 * single fields against this same controller in production use. */
		function memberRow(m) {
			var mid = m.id;
			var rmBusy = false;
			var rm = E('a', {
				'href': '#', 'title': _('Remove'),
				'style': 'cursor:pointer; text-decoration:none;',
				'click': function(ev) {
					ev.preventDefault();
					if (rmBusy) return;
					if (!confirm(_('Remove member ') + mid + ' from this network?')) return;
					rmBusy = true;
					L.resolveDefault(rpcMemberSet(section, nwid, mid, JSON.stringify({
						name: '', authorized: false, activeBridge: false, ipAssignments: [], noAutoAssignIps: false
					})), {}).then(function() { loadMembers(nwid, into); });
				}
			}, [ '✕' ]);

			var nameI = E('input', { 'type': 'text', 'value': m.name || '', 'style': 'width:100%; box-sizing:border-box;' });
			var nameBusy = false, nameAfterKey = false;
			function commitName() {
				var v = nameI.value;
				if (v === (m.name || '') || nameBusy) return;
				nameBusy = true;
				nameI.style.borderColor = 'orange';
				L.resolveDefault(rpcMemberSet(section, nwid, mid, JSON.stringify({ name: v })), {}).then(function(r2) {
					nameBusy = false;
					if (r2 && r2.code === 0) { m.name = v; flashBorder(nameI, 'green'); }
					else {
						nameI.value = m.name || '';
						flashBorder(nameI, 'red');
						ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(r2, _('Update failed')) ]), 'warning');
					}
				});
			}
			nameI.addEventListener('blur', function() {
				if (nameAfterKey) { nameAfterKey = false; return; }
				commitName();
			});
			nameI.addEventListener('keydown', function(ev) {
				if (ev.keyCode === 13) { ev.preventDefault(); nameAfterKey = true; commitName(); }
				else if (ev.keyCode === 27) nameI.value = m.name || '';
			});

			var cbs = {};
		function checkboxTd(field) {
			var c = E('input', { 'type': 'checkbox' });
			c.checked = !!m[field];
			var busy = false;
			c.addEventListener('change', function() {
				if (busy) return;
				busy = true;
				var b = {};
				b[field] = c.checked;
				L.resolveDefault(rpcMemberSet(section, nwid, mid, JSON.stringify(b)), {}).then(function(r2) {
					busy = false;
					if (!r2 || r2.code !== 0) {
						c.checked = !!m[field];
						ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(r2, _('Update failed')) ]), 'warning');
						return;
					}
					m[field] = c.checked;
					/* De-authorize re-reads immediately rather than after the
					 * delay: authorized is already final, and the controller
					 * keeps ipAssignments across a revoke/restore cycle
					 * untouched (verified), so only the peer columns can have
					 * moved. */
					if (field === 'authorized') {
						if (c.checked) {
							m.awaitingIp = true;
							drawIp();
							setTimeout(function() {
								refreshMember(mid).then(function(fm) {
									if (fm) fm.awaitingIp = false;
									drawIp();
								});
							}, IP_ASSIGN_DELAY);
						} else {
							refreshMember(mid).then(function() { drawIp(); });
						}
					}
				});
			});
			cbs[field] = c;
			return E('td', { 'style': 'width:9%; text-align:center;' }, [ c ]);
		}

			var ipTd = E('td', { 'style': 'width:13%; font-family:monospace; white-space:nowrap;' }, []);
			var ipBusy = false, ipEditing = false;
			function drawIp() {
			while (ipTd.firstChild) ipTd.removeChild(ipTd.firstChild);
			var ips = m.ipAssignments || [];
			if (m.awaitingIp && !ips.length) {
				ipTd.appendChild(E('span', { 'style': 'color:#888;' }, [ _('assigning address...') ]));
				return;
			}
			var clickable = E('span', { 'style': 'cursor:pointer;' }, ips.length
				? [ ips.join(', ') ]
				: [ E('span', { 'style': 'color:orange;' }, [
					/* Empty ipAssignments with version -1 means the node has
					 * never come up on this network; a positive version with
					 * no IP means the network has no pool. */
					(m.vMajor != null && m.vMajor < 0) ? _('never connected') : _('no pool assigned')
				]) ]);
			ipTd.appendChild(clickable);
		}
			function startIpEdit() {
				if (ipBusy) return;
				ipEditing = true;
				while (ipTd.firstChild) ipTd.removeChild(ipTd.firstChild);
				var inp = E('input', { 'type': 'text', 'value': (m.ipAssignments || []).join(', '), 'style': 'width:100%; box-sizing:border-box; font-family:monospace;' });
				ipTd.appendChild(inp);
				if (inp.focus) inp.focus();
				var afterKey = false;
				function close() { ipEditing = false; drawIp(); }
				function doCommit() {
					var raw = inp.value.trim(), arr = [], i;
					if (raw !== '') {
						arr = raw.split(',');
						for (i = 0; i < arr.length; i++) {
							arr[i] = arr[i].trim();
							if (!isIp(arr[i])) {
								ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ _('Managed IPs must be IPv4 addresses, comma-separated') ]), 'warning');
								return;
							}
						}
					}
					if (arr.join(',') === (m.ipAssignments || []).join(',') || ipBusy) { close(); return; }
					ipBusy = true;
					inp.style.borderColor = 'orange';
					L.resolveDefault(rpcMemberSet(section, nwid, mid, JSON.stringify({ ipAssignments: arr })), {}).then(function(r2) {
						ipBusy = false;
						if (r2 && r2.code === 0) { m.ipAssignments = arr; close(); }
						else {
							flashBorder(inp, 'red');
							ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(r2, _('Update failed')) ]), 'warning');
						}
					});
				}
				inp.addEventListener('blur', function() {
					if (afterKey) { afterKey = false; return; }
					if (ipEditing) doCommit();
				});
				inp.addEventListener('keydown', function(ev) {
					if (ev.keyCode === 13) { ev.preventDefault(); afterKey = true; doCommit(); }
					else if (ev.keyCode === 27) { inp.value = (m.ipAssignments || []).join(', '); close(); }
				});
			}
			ipTd.addEventListener('click', function() { if (!ipEditing) startIpEdit(); });
			drawIp();

			function statusContent() {
				if (!pok) return E('span', { 'style': 'color:#888;' }, [ '-' ]);
				if (mid === controllerAddr) return E('span', { 'style': 'color:green; font-weight:bold;' }, [ 'CONTROLLER' ]);
				var p = peerMap[mid];
				if (!isOnline(p)) return E('span', { 'style': 'color:red; font-weight:bold;' }, [ 'OFFLINE' ]);
				var v = peerVersion(p);
				return E('span', { 'style': 'color:green; font-weight:bold;' }, [ 'ONLINE' + (v ? ' (' + v + ')' : '') ]);
			}
			function addrContent() {
				if (!pok) return '-';
				var p = peerMap[mid];
				var pth = pickPath(p);
				if (!pth || !pth.address) return '-';
				/* latency 0 means "not measured yet", not "0 ms" -- render (-). */
				return pth.address + ((p.latency > 0) ? ' (' + p.latency + ' ms)' : ' (-)');
			}

			var statusTd = E('td', { 'style': 'width:12%;' }, [ statusContent() ]);
		var addrTd = E('td', { 'style': 'width:26%; font-family:monospace;' }, [ addrContent() ]);
		var tr = E('tr', {}, [
			E('td', { 'style': 'width:34px; text-align:center;' }, [ rm ]),
			E('td', { 'style': 'width:19%;' }, [ nameI ]),
			E('td', { 'style': 'width:12%; font-family:monospace; white-space:nowrap;' }, [
				E('code', {}, [ E('a', { 'href': '#', 'click': function(ev) { ev.preventDefault(); } }, [ mid ]) ])
			]),
			checkboxTd('authorized'),
			checkboxTd('activeBridge'),
			ipTd,
			statusTd,
			addrTd
		]);
		rowRefs[mid] = {
			status: statusTd, addr: addrTd,
			statusText: statusContent, addrText: addrContent,
			paintIp: drawIp,
			authCb: cbs.authorized, bridgeCb: cbs.activeBridge
		};
		return tr;
		}

		function drawRows() {
			while (tbody.firstChild) tbody.removeChild(tbody.firstChild);
			/* Clear the cell refs of the rows being replaced: a stale entry would
			 * make applyPeers repaint a detached node, which fails silently
			 * and leaves peer status frozen after any filter change. */
			rowRefs = {};
			var q = filterI.value ? filterI.value.toLowerCase() : '';
			var shown = 0;
			membersArr.forEach(function(m) {
				var hay = ((m.name || '') + ' ' + m.id + ' ' + (m.ipAssignments || []).join(', ')).toLowerCase();
				if (q && hay.indexOf(q) === -1) return;
				shown++;
				tbody.appendChild(memberRow(m));
			});
			if (!shown) tbody.appendChild(E('tr', {}, [ E('td', { 'colspan': '8', 'style': 'color:orange;' }, [ _('No members match.') ]) ]));
			setCounter(shown);
		}
		filterI.addEventListener('input', drawRows);

		/* ztncui column order. Lives inside the members div, never nested in
		 * the network <table>: nested tables share column widths (see the
		 * comment above netRow's return). Header labels may wrap; the fixed
		 * layout plus 34px + 19+12+9+9+13+12+26% keeps the grid stable. */
		/* Deliberately a full reload, unlike refreshMember: this button exists for the
		 * case where the same controller is being edited in another tool. The
		 * filter text survives because drawRows reads it back out of filterI. */
		function refreshAll() {
			Promise.all([
				L.resolveDefault(rpcMemberList(section, nwid), {}),
				L.resolveDefault(rpcPeerList(section), {})
			]).then(function(r) {
			var mres2 = r[0], pres3 = r[1];
			var msk2 = Array.isArray(mres2 && mres2.skipped) ? mres2.skipped : [];
			/* An empty body with skipped entries is every read failing, not an
			 * empty network: keep the table rather than blank it, and say so.
			 * The stamp claims the table is fresh, so only a fetch that
			 * actually replaced it may move it. */
			var mok2 = !!(mres2 && (mres2.code === 0 || mres2.code === 200) && Array.isArray(mres2.body) && (mres2.body.length || !msk2.length));
			if (mok2) {
				membersArr = mres2.body;
				missingIds = msk2;
			}
			else
				ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(mres2, _('Could not refresh the member list; the table is unchanged')) ]), 'warning');
			if (pres3 && (pres3.code === 0 || pres3.code === 200) && Array.isArray(pres3.body))
				applyPeers(pres3.body);
			drawRows();
			if (mok2) setStamp();
			});
		}
		var refreshBtn = E('button', { 'class': 'cbi-button cbi-button-action' }, [ _('Refresh') ]);
		refreshBtn.addEventListener('click', refreshAll);

		var hdr = E('tr', {}, [
			E('th', { 'style': 'width:34px;' }, []),
			E('th', { 'style': 'width:19%;' }, [_('Member name')]),
			E('th', { 'style': 'width:12%;' }, [_('Member ID')]),
			E('th', { 'style': 'width:9%; text-align:center;' }, [_('Authorized')]),
			E('th', { 'style': 'width:9%; text-align:center;' }, [_('Active bridge')]),
			E('th', { 'style': 'width:13%;' }, [_('IP assignment')]),
			E('th', { 'style': 'width:12%;' }, [_('Peer status')]),
			E('th', { 'style': 'width:26%;' }, [_('Peer address / latency')])
		]);
		into.appendChild(E('div', { 'style': 'display:flex; gap:8px; align-items:center; margin:6px 0;' },
			[ filterI, counterHost, refreshBtn, stamp ]));
		/* The scroll wrapper and min-width are load-bearing: table-layout:fixed
		 * pins column widths but does NOT clip or wrap content, so a nowrap cell
		 * wider than its share prints over the next column. Screenshotting the
		 * page at 820px showed "192.168.192.x" on top of "OFFLINE" down the whole
		 * table. 1040px is where the widest nowrap cell (the peer endpoint, 26%
		 * column) stops overflowing; below it the table scrolls instead of
		 * colliding, and above it the min-width is inert. */
		into.appendChild(E('div', { 'style': 'overflow-x:auto;' }, [
			E('table', { 'class': 'table', 'style': 'table-layout:fixed; width:100%; min-width:1040px;' }, [ hdr, tbody ])
		]));
		drawRows();
		setStamp();
		});
	}

	function load() {
		while (table.firstChild) table.removeChild(table.firstChild);
		table.appendChild(E('div', { 'style': 'color:orange;' }, [ _('Loading...') ]));
		L.resolveDefault(rpcNetworkList(section), {}).then(function(res) {
			while (table.firstChild) table.removeChild(table.firstChild);
			var nets = res && Array.isArray(res.body) ? res.body : null;
			if (!nets) {
				table.appendChild(E('div', { 'style': 'color:red;' }, [ errText(res, _('Could not reach the controller')) ]));
				return;
			}
			if (!nets.length) {
				table.appendChild(E('div', { 'style': 'color:orange;' }, [ _('This controller has no networks yet.') ]));
				return;
			}
			var head = E('tr', {}, [
				E('th', { 'style': 'width:170px;' }, [_('Network ID')]),
				E('th', { 'style': 'min-width:160px;' }, [_('Name')]),
				E('th', { 'style': 'text-align:center; white-space:nowrap;' }, [_('Broadcast')]),
				E('th', { 'style': 'text-align:right;' }, [_('Actions')])
			]);
			/* netRow returns a block element, not a <tr>: the per-network editors
			 * below the row must not be trapped inside the table, or their wide
			 * forms stretch the nwid column (see netRow). So the header goes in
			 * its own table and each network follows as a sibling block. */
			table.appendChild(E('table', { 'class': 'table' }, [ head ]));
			nets.forEach(function(nw) { table.appendChild(netRow(nw)); });
			var skipped = res.skipped || [];
			if (skipped.length) {
				table.appendChild(E('div', { 'style': 'color:red; margin-top:6px;' }, [
					_('Could not read these networks, so they are not shown: ') + skipped.join(', ')
				]));
			}
		});
	}

	refresh.addEventListener('click', load);
	add.addEventListener('click', function() {
		add.disabled = true;
		L.resolveDefault(rpcNetSet(section, 'new', '{}'), {}).then(function(res) {
			if (res && res.code === 200) load();
			else ui.addNotification(null, E('span', { 'class': 'alert-message warning' }, [ errText(res, _('Create failed')) ]), 'warning');
			add.disabled = false;
		});
	});

	load();
	return E('div', {}, [ E('div', { 'style': 'display:flex; gap:8px; margin-top:8px;' }, [ refresh, add ]), table ]);
}

/* -------------------------------------------------------------------- moon */

function moonPanel(section) {
	var box = E('div', { 'style': 'margin-top:8px;' });
	var planBtn = E('button', { 'class': 'cbi-button' }, [ _('Show plan') ]);

	function showPlan(res) {
		while (box.firstChild) box.removeChild(box.firstChild);
		if (!res || res.code !== 0) {
			box.appendChild(E('div', { 'style': 'color:red;' }, [ errText(res, _('Could not build a plan')) ]));
			return;
		}
		var go = E('button', { 'class': 'cbi-button cbi-button-action important' }, [ _('Create and sign the moon') ]);
		go.addEventListener('click', function() {
			if (!confirm(_('This will create moon.json (holding the signing secret) and a signed .moon on the remote host. Continue?'))) return;
			go.disabled = true;
			L.resolveDefault(rpcMoonApply(section, res.confirm), {}).then(function(r2) {
				go.disabled = false;
				while (box.firstChild) box.removeChild(box.firstChild);
				if (!r2 || r2.code !== 0) {
					box.appendChild(E('div', { 'style': 'color:red;' }, [ errText(r2, _('Moon creation failed')) ]));
					return;
				}
				var href = 'data:application/octet-stream;base64,' + r2.moon_b64;
				box.appendChild(E('div', { 'style': 'color:green; margin-bottom:6px;' }, [
					_('Moon created: '), E('code', {}, [ r2.moon_id ]), ' — ',
					E('a', { 'href': href, 'download': r2.moon_file || (r2.moon_id + '.moon'), 'class': 'cbi-button' }, [ _('Download .moon') ])
				]));
				box.appendChild(E('div', { 'style': 'color:orange;' }, [
					_('Distribute this file to members, then use Interface Info → Moons → Add Moon on each node. The signing secret never left the remote host.')
				]));
			});
		});

		box.appendChild(E('div', { 'style': 'margin:6px 0;' }, [
			E('div', {}, [ _('The following will run on the remote host:') ]),
			E('pre', {
				/* Same reason as the requirements line: a fixed light background
				 * is unreadable under LuCI's dark theme. */
				'style': 'border:1px solid #666; border-radius:3px; padding:8px; overflow:auto; font-size:12px;'
			}, [ res.script ])
		]));
		box.appendChild(E('div', { 'style': 'color:orange; margin-bottom:6px;' }, [ res.notes ]));
		box.appendChild(go);
	}

	planBtn.addEventListener('click', function() {
		planBtn.disabled = true;
		planBtn.textContent = _('Building...');
		L.resolveDefault(rpcMoonPlan(section), {}).then(function(res) {
			showPlan(res);
			planBtn.disabled = false;
			planBtn.textContent = _('Show plan');
		}).catch(function() {
			showPlan(null);
			planBtn.disabled = false;
			planBtn.textContent = _('Show plan');
		});
	});

	return E('div', {}, [
		planBtn,
		E('div', { 'style': 'color:orange; margin-top:4px;' }, [
			_('The remote host becomes the single root of a new moon. Additional roots are not supported yet.')
		]),
		box
	]);
}

/* --------------------------------------------------------------------- page */

return view.extend({
	load: function() {
		return ZT_TR;
	},

	render: function() {
		var listBox = E('div', {});

		function reload() {
			L.resolveDefault(rpcHostList(), {}).then(function(res) {
				while (listBox.firstChild) listBox.removeChild(listBox.firstChild);
				var hosts = (res && res.hosts) || [];
				if (!hosts.length) {
					listBox.appendChild(E('div', { 'style': 'color:orange;' }, [
						_('No remote hosts configured yet. Add one to manage a Controller or Moon that runs on a separate server.')
					]));
					return;
				}
				hosts.forEach(function(h) {
					var detail = E('div', { 'style': 'display:none; margin:8px 0 16px 0; padding-left:12px; border-left:3px solid #ccc;' });
					var toggle = E('button', { 'class': 'cbi-button cbi-button-action' }, [ _('Manage') ]);
					toggle.addEventListener('click', function() {
						/* A freshly created div has display '', not 'none', so the
						 * open test has to be for 'block' -- testing "!== 'none'"
						 * reads the initial state as already-open and the first
						 * click collapses the panel instead of building it. */
						var isOpen = detail.style.display === 'block';
						detail.style.display = isOpen ? 'none' : 'block';
						toggle.textContent = isOpen ? _('Manage') : _('Hide');
						if (!isOpen && !detail.firstChild) {
							detail.appendChild(E('h4', {}, [_('Diagnostics')]));
							detail.appendChild(diagnostics(h.section, h));
							detail.appendChild(E('h4', {}, [_('Networks')]));
							detail.appendChild(networksPanel(h.section));
							detail.appendChild(E('h4', {}, [_('Moon')]));
							detail.appendChild(moonPanel(h.section));
						}
					});

					var edit = E('button', { 'class': 'cbi-button' }, [ _('Edit') ]);
					edit.addEventListener('click', function() { hostEditor(h.section, h, reload); });

					var del = E('button', { 'class': 'cbi-button cbi-button-remove' }, [ _('Delete') ]);
					del.addEventListener('click', function() {
						if (!confirm(_('Remove ') + h.name + ' from this router? The remote host is not modified.')) return;
						del.disabled = true;
						L.resolveDefault(rpcHostDel(h.section), {}).then(function() { reload(); });
					});

					listBox.appendChild(E('div', { 'class': 'cbi-section' }, [
						E('div', { 'style': 'display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:8px;' }, [
							E('div', {}, [
								E('strong', {}, [ h.name ]),
								E('div', { 'style': 'font-family:monospace; font-size:12px; color:#666;' }, [
									h.user + '@' + h.host + ':' + h.port + _(' (controller port ') + h.controller_port + ')'
								]),
								h.key_present
									? E('div', { 'style': 'font-size:12px; color:green;' }, [_('SSH key installed')])
									: E('div', { 'style': 'font-size:12px; color:red;' }, [_('No SSH key — add one before use')])
							]),
							E('div', { 'style': 'display:flex; gap:6px;' }, [ toggle, edit, del ])
						]),
						detail
					]));
				});
			});
		}

		var addBtn = E('button', { 'class': 'cbi-button cbi-button-add' }, [ _('Add remote host') ]);
		addBtn.addEventListener('click', function() { hostEditor(null, null, reload); });

		reload();

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ _('ZeroTier'), ' - ', _('Remote Controller') ]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [_('How remote management works')]),
				E('div', { 'style': 'margin-bottom:8px;' }, [
					E('p', {}, [ _('A ZeroTier controller or moon root must live on a server with a fixed public IP, reachable by SSH, with passwordless sudo for that user. The controller API has no TLS and refuses every non-loopback caller, so this page never talks to it directly: it opens an SSH tunnel from this router to the remote loopback interface and sends API calls through it. The controller authtoken is read over SSH on demand and is never stored here.') ])
				]),
				E('div', {
					/* No hardcoded background: LuCI has a dark theme, and a fixed
					 * light panel with default-coloured text left this line almost
					 * unreadable. A muted currentColor border works in both. */
					'style': 'border-left:3px solid #888; padding:6px 10px; opacity:0.85; font-size:13px;'
				}, [
					_('Requirements: a fixed public IP · SSH access · a keypair whose public key is in the remote authorized_keys · passwordless sudo · ZeroTier built with the controller (1.14.2, or a 1.16 nonfree build)')
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [_('Configured hosts')]),
				listBox,
				E('div', { 'style': 'margin-top:10px;' }, [ addBtn ])
			])
		]);
	}
});
