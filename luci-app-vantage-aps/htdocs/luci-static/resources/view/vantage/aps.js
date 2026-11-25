'use strict';
'require view';
'require rpc';
'require ui';
'require poll';
'require dom';

/* Network -> Access points (luci-app-vantage-aps): pairs devices so a
   router's dashboard can show its access points, which it reads over SSH.
   Two roles on one page: this device as the router (the access points it
   reads) and as an access point (the routers that may read it). Pairing
   is two pastes, one on each device; luci.vantage.pair checks every code,
   address and key itself, so what this page parses is only for prefilling
   and for saying what went wrong. All DOM is built with E() and text
   nodes; the address of an access point is shown as text, never a link. */

/* status and report are reads, the rest writes (luci-app-vantage-aps) */
var callStatus = rpc.declare({ object: 'luci.vantage.pair', method: 'status', reject: true });
var callRouterCode = rpc.declare({ object: 'luci.vantage.pair', method: 'router_code', reject: true });
var callAddAp = rpc.declare({ object: 'luci.vantage.pair', method: 'add_ap', params: [ 'code', 'addr' ], reject: true });
var callRemoveAp = rpc.declare({ object: 'luci.vantage.pair', method: 'remove_ap', params: [ 'id' ], reject: true });
var callAllowRouter = rpc.declare({ object: 'luci.vantage.pair', method: 'allow_router', params: [ 'code' ], reject: true });
var callRevokeRouter = rpc.declare({ object: 'luci.vantage.pair', method: 'revoke_router', params: [ 'key' ], reject: true });
/* fails (not found) while nothing is paired: then there is no live state */
var callReport = rpc.declare({ object: 'vantage.collector', method: 'report', reject: true });

/* the plugin's limits, for the messages */
var MAX_APS = 16;
var MAX_ROUTERS = 8;
var NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/;
var IPV4_RE = /^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}$/;

function isObject(v) { return v != null && typeof v === 'object' && !Array.isArray(v); }

/* the base sheet (luci-app-vantage) and this add-on's, versioned as LuCI
   versions its scripts; both are adopted at once, in this order, so the
   add-on's rules follow the base ones whichever arrives first */
var cssPromise = null;
function loadCss() {
	if (cssPromise) return cssPromise;
	if (!('adoptedStyleSheets' in document) || typeof CSSStyleSheet !== 'function') return (cssPromise = Promise.resolve());
	var base = new CSSStyleSheet(), own = new CSSStyleSheet();
	document.adoptedStyleSheets = document.adoptedStyleSheets.concat([ base, own ]);
	cssPromise = Promise.all([
		fetch(L.resource('vantage/app.css') + '?v=' + L.env.resource_version).then(function(r) { return r.ok ? r.text() : ''; }).then(function(text) {
			base.replaceSync(text);
		}).catch(function() {}),
		fetch(L.resource('vantage/aps.css') + '?v=' + L.env.resource_version).then(function(r) { return r.ok ? r.text() : ''; }).then(function(text) {
			own.replaceSync(text);
		}).catch(function() {})
	]);
	return cssPromise;
}

var SVGNS = 'http://www.w3.org/2000/svg';
/* the dashboard's own icons (overview.js, firewall.js) */
var ICONS = {
	ap: [ 'M4.5 15h15a1.5 1.5 0 0 1 1.5 1.5v1.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18v-1.5A1.5 1.5 0 0 1 4.5 15Z', 'M7 17.25h.01', 'M8.6 10.6a4.8 4.8 0 0 1 6.8 0', 'M6.1 8.1a8.4 8.4 0 0 1 11.8 0', 'M11.3 12.9a1 1 0 0 1 1.4 0' ],
	router: [ 'M4.5 13h15a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z', 'M7 16h.01M10 16h.01', 'M8 13 6 6.5M16 13l2-6.5' ],
	warn: [ 'M10.3 4.6 3 17.5A2 2 0 0 0 4.7 20.5h14.6A2 2 0 0 0 21 17.5L13.7 4.6a2 2 0 0 0-3.4 0Z', 'M12 9.5v4.5', 'M12 17h.01' ]
};

function icon(name) {
	var s = document.createElementNS(SVGNS, 'svg');
	s.setAttribute('class', 'vt-ico');
	s.setAttribute('viewBox', '0 0 24 24');
	s.setAttribute('aria-hidden', 'true');
	s.setAttribute('focusable', 'false');
	ICONS[name].forEach(function(d) {
		var p = document.createElementNS(SVGNS, 'path');
		p.setAttribute('d', d);
		s.appendChild(p);
	});
	return s;
}

/* a pasted code's fields: line breaks from wrapping and doubled spaces
   are not part of it */
function codeFields(text) {
	var t = String(text == null ? '' : text).trim();
	return t ? t.split(/\s+/) : [];
}

function normCode(text) { return codeFields(text).join(' '); }

/* which kind of line was pasted: 'router' (a router's code), 'ap' (an
   access point's reply) or null */
function codeKind(text) {
	var w = codeFields(text)[0];
	return w === 'vantage-router' ? 'router' : w === 'vantage-ap' ? 'ap' : null;
}

/* an address as the plugin takes it, roughly: dotted IPv4 or something
   IPv6-shaped (the plugin decides) */
function addrLike(v) {
	return IPV4_RE.test(v) || (/^[0-9A-Fa-f:.]{2,45}$/.test(v) && v.indexOf(':') >= 0);
}

/* "vantage-ap 1 ssh-ed25519 <base64> <address> <ssh port> <lan mac> <ap-name>"
   -> { addr, port, name }, or null when it does not look like one */
function parseApReply(text) {
	var f = codeFields(text);
	if (f.length !== 8 || f[0] !== 'vantage-ap' || f[1] !== '1' || f[2] !== 'ssh-ed25519') return null;
	var port = /^[0-9]{1,5}$/.test(f[5]) ? +f[5] : 0;
	if (!/^[A-Za-z0-9+\/]{68}$/.test(f[3]) || !addrLike(f[4]) || port < 1 || port > 65535 ||
		!/^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$/.test(f[6]) || !NAME_RE.test(f[7])) return null;
	return { addr: f[4].toLowerCase(), port: port, name: f[7] };
}

/* the address to send with add_ap: none (the reply's own) unless the
   field holds another one */
function addrOverride(field, parsed) {
	var v = String(field == null ? '' : field).trim();
	if (!v || (parsed && v === parsed.addr)) return undefined;
	return v;
}

/* a key in a row: its last 12 characters (every Ed25519 key starts alike) */
function shortKey(key) {
	key = String(key == null ? '' : key);
	return key.length > 20 ? '…' + key.slice(-12) : key;
}

/* "192.0.2.10", or with its SSH port when that is not 22 */
function where(addr, port) {
	return (port && port !== 22) ? _('%s, SSH port %d').format(addr, port) : String(addr);
}

function ago(s) {
	if (typeof s !== 'number' || !isFinite(s) || s < 0) return null;
	s = Math.round(s);
	if (s < 60) return _('%d s ago').format(s);
	if (s < 3600) return _('%d min ago').format(Math.floor(s / 60));
	if (s < 172800) return _('%d h ago').format(Math.floor(s / 3600));
	return _('%d days ago').format(Math.floor(s / 86400));
}

/* why the collector cannot read an access point (report error codes) */
function reportError(code) {
	switch (code) {
	case 'hostkey': return _('It answered with another SSH host key than the one paired. If it was reset or reinstalled, remove it and pair it again.');
	case 'denied': return _('It refused this router\'s key: it was probably revoked there. Pair it again to read it.');
	case 'unreachable': return _('This router cannot connect to it. Check that it is on and that its SSH port is reachable from here.');
	case 'timeout': return _('It did not answer in time.');
	case 'invalid': return _('It sent a report this router cannot read. Update Vantage on it.');
	case 'missing': return _('Vantage\'s access point add-on is not installed on it. Install luci-app-vantage-aps there again.');
	}
	return _('It could not be read.');
}

/* this device's SSH, as an access point (status ap.ssh); null when fine */
function sshProblem(state) {
	switch (state) {
	case 'ok': return null;
	case 'no-dropbear': return _('Dropbear, the SSH server routers read this device through, is not installed, so pairing is off.');
	case 'no-key-options': return _('This device\'s Dropbear ignores key restrictions; letting a router in would give it full access, so pairing is off.');
	case 'unsupported': return _('Dropbear\'s settings on this device (root login off, a forced command or its own host key files) keep a router from reading it, so pairing is off.');
	case 'no-host-key': return _('Dropbear has no Ed25519 host key yet, so pairing is off. Restarting Dropbear creates one.');
	case 'not-running': return _('Dropbear, the SSH server, is not running, so pairing is off. Start it under System → Startup.');
	case 'keys-unreadable': return _('This device\'s SSH keys (/etc/dropbear/authorized_keys) cannot be read, or are larger than 256 KiB. Which routers can read this device is not known, so pairing is off.');
	case 'no-address': return _('This device has no IPv4 address on its lan interface for a router to reach it at, so pairing is off.');
	}
	return _('SSH on this device is not ready for pairing.');
}

/* add_ap's refusals */
function addError(res, overridden) {
	var e = isObject(res) ? res.error : 'none';
	if (e === 'invalid') return overridden
		? _('Check the reply and the address: the address must be an IPv4 or IPv6 address, without a port.')
		: _('That is not an access point\'s reply. Copy the whole line from the access point, starting with vantage-ap.');
	if (e === 'self') return _('That is this device\'s own reply. Paste the reply of the access point you want to add.');
	if (e === 'duplicate') return _('This access point is already on this dashboard.');
	if (e === 'full') return _('This dashboard already reads %d access points. Remove one first.').format(MAX_APS);
	if (e === 'no-key') return _('This router has no key yet. Close this form and open it again to make one.');
	if (e === 'failed') return _('This device could not save the access point. Try again.');
	return _('The access point could not be added.');
}

/* allow_router's refusals */
function allowError(res) {
	var e = isObject(res) ? res.error : 'none';
	if (e === 'invalid') return _('That is not a router\'s code. Copy the whole line from the router, starting with vantage-router.');
	if (e === 'full') return _('%d routers can already read this access point. Revoke one first.').format(MAX_ROUTERS);
	if (e === 'duplicate') return _('This router\'s key is already in this device\'s SSH keys, added by hand. Remove it under System → Administration → SSH-Keys first.');
	if (e === 'failed') return _('This device could not update its SSH keys. Try again.');
	if (e === 'ok' || typeof e !== 'string' || e === 'none') return _('The router could not be let in.');
	return sshProblem(e);
}

/* no dbclient: nothing to read access points with */
function noClient() { return _('This device has no SSH client (dbclient), so it cannot read access points.'); }

/* router_code's refusals */
function codeError(res) {
	var e = isObject(res) ? res.error : 'none';
	if (e === 'no-dbclient') return noClient();
	if (e === 'failed') return _('This device could not make its SSH key. Try again.');
	return _('The device did not do it. Reload the page and try again.');
}

/* remove_ap's and revoke_router's refusals; unknown (already gone) is none */
function dropError(res) {
	if (isObject(res) && (res.ok === true || res.error === 'unknown')) return null;
	if (isObject(res) && res.error === 'failed') return _('This device could not save the change. Try again.');
	return _('The device did not do it. Reload the page and try again.');
}

/* a refused or failed call (permission denied, no plugin, timeout) */
function failed(err) {
	return _('The request failed: %s').format(err && err.message ? err.message : String(err));
}

/* status, in the shape the page reads; null when it isn't one */
function normStatus(s) {
	if (!isObject(s)) return null;
	var r = isObject(s.router) ? s.router : {}, a = isObject(s.ap) ? s.ap : {};
	return {
		code: typeof r.code === 'string' ? r.code : null,
		aps: (Array.isArray(r.aps) ? r.aps : []).filter(function(x) { return isObject(x) && typeof x.id === 'string'; }).map(function(x) {
			var a = { id: x.id, name: String(x.name == null ? '' : x.name), addr: String(x.addr == null ? '' : x.addr), port: typeof x.port === 'number' ? x.port : 22 };
			/* the network it was paired on, where the router kept one */
			if (typeof x.net === 'string' && x.net) a.net = x.net;
			return a;
		}),
		ssh: typeof a.ssh === 'string' ? a.ssh : null,
		routers: (Array.isArray(a.routers) ? a.routers : []).filter(function(x) { return isObject(x) && typeof x.key === 'string'; }).map(function(x) {
			return { key: x.key, name: String(x.name == null ? '' : x.name) };
		}),
		reply: typeof a.reply === 'string' ? a.reply : null,
		/* a list whose file is there and could not be read: empty, and saying nothing */
		apsUnread: r.unread === true,
		keysUnread: a.unread === true || a.ssh === 'keys-unreadable'
	};
}

/* an access point's live state from the collector's report: null when
   the report could not be read (no live state), waiting when the
   collector has not picked a new pairing up yet */
function liveOf(id, report) {
	if (!isObject(report) || !Array.isArray(report.aps)) return null;
	for (var i = 0; i < report.aps.length; i++)
		if (isObject(report.aps[i]) && report.aps[i].id === id) return report.aps[i];
	return { state: 'waiting' };
}

/* -> { cls, text, why }: the state line and why it is not reporting.
   The collector's states: ok with a report to show (its last one, right
   after a pause in viewing), offline when it could not be reached
   (unreachable, timeout), error when it was refused or made no sense,
   waiting before any fetch has ended */
function stateLine(live) {
	if (!live) return { cls: 'none', text: _('No live state'), why: null };
	var age = ago(live.age);
	switch (live.state) {
	case 'ok': return { cls: 'ok', text: age ? _('Reporting, %s').format(age) : _('Reporting'), why: null };
	case 'waiting': return { cls: 'wait', text: _('Waiting for its first report'), why: null };
	case 'offline': return { cls: 'off', text: age ? _('Offline, last report %s').format(age) : _('Offline'),
		why: typeof live.error === 'string' ? reportError(live.error) : null };
	case 'error': return { cls: 'err', text: _('Not reporting'), why: reportError(live.error) };
	}
	return { cls: 'none', text: _('No live state'), why: null };
}

/* copies a read-only field: the async clipboard needs a secure context,
   and LuCI is often served over plain HTTP, so then the selection and
   execCommand('copy'), which takes the focus to the field: it goes back
   to the Copy button. When neither works the text stays selected */
function copyField(field, note, btn) {
	var say = function(ok) {
		dom.content(note, [ ok ? _('Copied') : _('Select and copy it') ]);
		if (!ok) { field.focus(); field.select(); }
	};
	var fallback = function() {
		var ok = false;
		field.focus();
		field.select();
		try { ok = document.execCommand('copy'); } catch (e) {}
		if (ok && btn) btn.focus();
		say(ok);
	};
	if (window.isSecureContext && navigator.clipboard && typeof navigator.clipboard.writeText === 'function')
		navigator.clipboard.writeText(field.value).then(function() { say(true); }, fallback);
	else
		fallback();
}

function warnNote(text) {
	return E('p', { 'class': 'vt-pair-note is-warn' }, [ icon('warn'), E('span', {}, [ text ]) ]);
}

return view.extend({
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	/* the helpers, for the tests */
	parseApReply: parseApReply,
	codeKind: codeKind,
	normCode: normCode,
	addrOverride: addrOverride,
	shortKey: shortKey,
	reportError: reportError,
	sshProblem: sshProblem,
	addError: addError,
	allowError: allowError,
	codeError: codeError,
	dropError: dropError,
	copyField: copyField,
	stateLine: stateLine,
	liveOf: liveOf,
	normStatus: normStatus,

	load: function() {
		return Promise.all([ loadCss(), L.resolveDefault(callStatus(), null), L.resolveDefault(callReport(), null) ]).then(function(r) {
			return { status: r[1], report: r[2] };
		});
	},

	render: function(data) {
		this.status = normStatus(data.status);
		this.report = isObject(data.report) ? data.report : null;
		if (!this.status)
			return E('div', { 'class': 'vt-app vt-pair-page' }, [ E('div', { 'class': 'vt-body' }, [
				this.head(),
				warnNote(_('Could not read the pairing state. Reload the page; if that does not help, reinstall luci-app-vantage-aps.'))
			]) ]);

		this.el = {};
		var page = E('div', { 'class': 'vt-app vt-pair-page' }, [
			E('div', { 'class': 'vt-body' }, [
				this.head(),
				E('div', { 'class': 'vt-pair-grid' }, [ this.renderRouter(), this.renderAp() ])
			])
		]);
		this.paint();
		poll.add(L.bind(this.refresh, this), 5);
		var self = this;
		document.addEventListener('visibilitychange', function() {
			/* shown again: what was skipped, at once (unless LuCI's
			   refresh is paused: its resume asks) */
			if (!document.hidden && self.skipped && (typeof poll.active !== 'function' || poll.active())) self.refresh();
		});
		return page;
	},

	head: function() {
		return E('header', { 'class': 'vt-head' }, [
			E('div', { 'class': 'vt-head-text' }, [
				E('h2', { 'class': 'vt-headline' }, [ _('Access points') ]),
				E('p', { 'class': 'vt-subline' }, [ _('Pair access points with a router so its dashboard shows their Wi-Fi and wired clients. Both need Vantage; nothing is shared until a code is pasted on each.') ])
			])
		]);
	},

	/* status and the live state again: a failed status read keeps what is
	   shown, a failed report read means no live state. Not in a hidden
	   tab: every report call keeps the collector logging in to each
	   access point, for nobody */
	refresh: function() {
		var self = this;
		if (document.hidden) { this.skipped = true; return Promise.resolve(); }
		this.skipped = false;
		return Promise.all([ L.resolveDefault(callStatus(), null), L.resolveDefault(callReport(), null) ]).then(function(r) {
			var s = normStatus(r[0]);
			if (s) self.status = s;
			self.report = isObject(r[1]) ? r[1] : null;
			self.paint();
		});
	},

	paint: function() {
		this.paintAps();
		this.paintRouters();
	},

	tile: function(ic, title, lead, body) {
		return E('section', { 'class': 'vt-tile', 'aria-label': title }, [
			E('header', { 'class': 'vt-tile-head' }, [
				E('h3', { 'class': 'vt-tile-title' }, [ icon(ic), E('span', {}, [ title ]) ])
			]),
			E('p', { 'class': 'vt-hint vt-pair-lead' }, [ lead ])
		].concat(body));
	},

	/* a read-only field with its Copy button and what copying did */
	copyBox: function(label) {
		var field = E('textarea', { 'class': 'vt-pair-field vt-pair-code', 'readonly': 'readonly', 'rows': 3, 'spellcheck': 'false',
			'aria-label': label, 'focus': function() { field.select(); } });
		var note = E('span', { 'class': 'vt-hint', 'aria-live': 'polite' });
		var btn = E('button', { 'type': 'button', 'class': 'vt-btn', 'click': function() { copyField(field, note, btn); } }, [ _('Copy') ]);
		return {
			field: field, btn: btn, note: note,
			el: E('div', { 'class': 'vt-pair-copy' }, [ field, E('div', { 'class': 'vt-pair-copy-row' }, [ btn, note ]) ]),
			set: function(text) {
				field.value = text || '';
				btn.disabled = !text;
				dom.content(note, []);
			}
		};
	},

	step: function(n, title, body) {
		return E('li', { 'class': 'vt-pair-step' }, [
			E('span', { 'class': 'vt-pair-num', 'aria-hidden': 'true' }, [ String(n) ]),
			E('div', { 'class': 'vt-pair-step-body' }, [ E('span', { 'class': 'vt-pair-label' }, [ title ]) ].concat(body))
		]);
	},

	/* ---------------------------------------- this device as the router */

	renderRouter: function() {
		var el = this.el;
		el.client = E('div', { 'class': 'vt-pair-notes' });
		el.apRows = E('div', { 'class': 'vt-pair-rows', 'role': 'list', 'aria-label': _('Paired access points') });
		el.addBtn = E('button', { 'type': 'button', 'class': 'vt-btn', 'click': L.bind(this.openAdd, this) }, [ _('Add an access point') ]);
		el.addFlow = this.renderAdd();
		return this.tile('ap', _('Access points on this dashboard'),
			_('This device reads each access point over SSH and shows it on its dashboard.'), [
				el.client,
				el.apRows,
				E('div', { 'class': 'vt-pair-actions' }, [ el.addBtn ]),
				el.addFlow,
				E('p', { 'class': 'vt-hint vt-pair-foot' }, [ _('An access point\'s SSH must be on and reachable from this device; this page cannot pair one that is not.') ])
			]);
	},

	paintAps: function() {
		var self = this, el = this.el, aps = this.status.aps;
		/* access points paired and no code to give (or router_code said
		   so): no dbclient, which is why none of them has a live state */
		var blind = !!this.noClient || (this.status.code == null && aps.length > 0);
		if (blind !== this.blindShown) {
			this.blindShown = blind;
			dom.content(el.client, blind ? [ warnNote(noClient()) ] : []);
		}
		var sig = JSON.stringify([ this.status.apsUnread ].concat(aps.map(function(a) { return [ a.id, a.name, a.addr, a.port, a.net ]; })));
		/* rebuilt only when the list changes, so a poll never takes the
		   focus off a button */
		if (sig !== this.apSig) {
			this.apSig = sig;
			this.apEls = {};
			dom.content(el.apRows, aps.length ? aps.map(function(a) { return self.apRow(a); })
				: [ E('p', { 'class': 'vt-empty-inline', 'role': 'listitem' }, [ this.status.apsUnread ? _('Not known while this router\'s list of access points (/etc/vantage/aps.json) cannot be read.')
					: _('No access points yet. Add one to see its clients on this dashboard.') ]) ]);
		}
		aps.forEach(function(a) {
			var row = self.apEls[a.id], live = liveOf(a.id, self.report), st = stateLine(live);
			var model = live && isObject(live.report) && typeof live.report.model === 'string' ? live.report.model : '';
			/* where it last answered (its DHCP address may have moved since
			   pairing; the pinned host key still decides), else the paired one */
			var at = live && typeof live.addr === 'string' && live.addr ? live.addr : a.addr;
			dom.content(row.addr, [ where(at, a.port) ]);
			row.state.className = 'vt-pair-state is-' + st.cls;
			dom.content(row.state, [ st.text ]);
			dom.content(row.model, model ? [ ' · ', model ] : []);
			row.why.hidden = !st.why;
			dom.content(row.why, st.why ? [ st.why ] : []);
		});
		el.addBtn.hidden = !el.addFlow.hidden;
	},

	apRow: function(ap) {
		var self = this;
		var r = {
			state: E('span', { 'class': 'vt-pair-state' }),
			model: E('span', { 'class': 'vt-pair-model' }),
			addr: E('span', { 'class': 'vt-mono' }, [ where(ap.addr, ap.port) ]),
			why: E('p', { 'class': 'vt-pair-why', 'hidden': 'hidden' })
		};
		/* the network it was paired on, as this router names it: text */
		var net = ap.net ? [ E('span', { 'class': 'vt-pair-net', 'title': _('The network it was paired on: this router looks for it there when its address changes') },
			[ ' · ', _('network %s').format(ap.net) ]) ] : [];
		r.remove = E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-ghost vt-pair-act', 'aria-label': _('Remove %s').format(ap.name),
			'click': function() { self.confirmRemove(ap, r.remove); } }, [ _('Remove') ]);
		this.apEls[ap.id] = r;
		return E('div', { 'class': 'vt-pair-row', 'role': 'listitem' }, [
			E('div', { 'class': 'vt-pair-main' }, [
				E('span', { 'class': 'vt-pair-name' }, [ ap.name ]),
				E('span', { 'class': 'vt-pair-sub' }, [ r.addr ].concat(net, [ r.model ]))
			]),
			r.state,
			r.remove,
			r.why
		]);
	},

	confirmRemove: function(ap, opener) {
		ui.showModal(_('Remove access point'), this.confirmBody(
			_('%s will no longer show on this dashboard. Its access point keeps this router\'s key until you revoke it there.').format(ap.name),
			_('Remove'),
			function() { return callRemoveAp(ap.id); },
			opener, this.el.addBtn));
	},

	/* the body of a confirmation: run() is the call, its { ok } or
	   { error: 'unknown' } (already gone) closes the dialog. The focus
	   goes back to the button that opened it, or with its row gone to
	   the tile's own button */
	confirmBody: function(text, label, run, opener, fallback) {
		var self = this;
		var back = function() {
			var to = (opener && opener.isConnected) ? opener : fallback;
			if (to && !to.hidden) to.focus();
		};
		var err = E('p', { 'class': 'alert-message error', 'hidden': 'hidden', 'role': 'alert' });
		var show = function(msg) { err.hidden = false; dom.content(err, [ msg ]); go.disabled = false; };
		var go = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-negative', 'click': function() {
			go.disabled = true;
			err.hidden = true;
			run().then(function(res) {
				var msg = dropError(res);
				if (msg) return show(msg);
				ui.hideModal();
				return self.refresh().then(back, back);
			}, function(e) { show(failed(e)); });
		} }, [ label ]);
		return [
			E('p', {}, [ text ]),
			err,
			E('div', { 'class': 'right' }, [
				E('button', { 'type': 'button', 'class': 'btn cbi-button', 'click': function() { ui.hideModal(); back(); } }, [ _('Cancel') ]),
				' ',
				go
			])
		];
	},

	renderAdd: function() {
		var self = this, f = this.add = {};
		f.code = this.copyBox(_('This router\'s code'));
		f.codeErr = E('p', { 'class': 'vt-form-err', 'hidden': 'hidden', 'role': 'alert' });
		f.reply = E('textarea', { 'class': 'vt-pair-field vt-pair-code', 'rows': 3, 'spellcheck': 'false', 'autocomplete': 'off',
			'aria-label': _('The access point\'s reply'), 'placeholder': 'vantage-ap 1 ssh-ed25519 …', 'input': function() { self.onReply(); } });
		f.seen = E('p', { 'class': 'vt-hint', 'aria-live': 'polite' });
		f.addr = E('input', { 'type': 'text', 'class': 'vt-pair-field', 'spellcheck': 'false', 'autocomplete': 'off',
			'aria-label': _('Address of the access point'), 'input': function() { f.addrEdited = true; } });
		f.err = E('p', { 'class': 'vt-form-err', 'hidden': 'hidden', 'role': 'alert' });
		f.go = E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-primary', 'disabled': 'disabled', 'click': function() { self.submitAdd(); } }, [ _('Add access point') ]);
		return E('div', { 'class': 'vt-pair-flow', 'role': 'group', 'aria-label': _('Add an access point'), 'hidden': 'hidden' }, [
			E('ol', { 'class': 'vt-pair-steps' }, [
				this.step(1, _('Copy this router\'s code'), [
					f.code.el, f.codeErr,
					E('p', { 'class': 'vt-hint' }, [ _('On the access point, open Network → Access points and paste it under “Let a router read this access point”.') ])
				]),
				this.step(2, _('Paste the access point\'s reply'), [ f.reply, f.seen ]),
				this.step(3, _('Check the address'), [
					f.addr,
					E('p', { 'class': 'vt-hint' }, [ _('Where this router reaches it. Change it only if the access point\'s own address is not reachable from here.') ])
				])
			]),
			f.err,
			E('div', { 'class': 'vt-pair-actions' }, [
				f.go,
				E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-ghost', 'click': function() { self.closeAdd(); } }, [ _('Cancel') ])
			])
		]);
	},

	openAdd: function() {
		var self = this, f = this.add;
		f.reply.value = '';
		f.addr.value = '';
		f.addrEdited = false;
		f.err.hidden = true;
		this.onReply();
		this.el.addFlow.hidden = false;
		this.el.addBtn.hidden = true;
		f.code.set('');
		f.codeErr.hidden = true;
		f.code.field.placeholder = _('Getting this router\'s code…');
		/* creates this device's key on first use */
		callRouterCode().then(function(res) {
			self.noClient = isObject(res) && res.error === 'no-dbclient';
			self.paintAps();
			return (isObject(res) && typeof res.code === 'string') ? res.code : Promise.reject(codeError(res));
		}).then(function(code) {
			f.code.field.placeholder = '';
			f.code.set(code);
		}, function(e) {
			f.code.field.placeholder = '';
			f.codeErr.hidden = false;
			dom.content(f.codeErr, [ typeof e === 'string' ? e : failed(e) ]);
		});
		f.code.field.focus();
	},

	closeAdd: function() {
		this.el.addFlow.hidden = true;
		this.el.addBtn.hidden = false;
		this.el.addBtn.focus();
	},

	/* what the pasted reply says, and the address prefilled from it until
	   the field is edited */
	onReply: function() {
		var f = this.add, text = f.reply.value, p = parseApReply(text);
		f.parsed = p;
		if (!f.addrEdited) f.addr.value = p ? p.addr : '';
		f.go.disabled = !normCode(text);
		f.err.hidden = true;
		var msg = '';
		if (p) msg = p.port !== 22 ? _('Access point %s, SSH port %d.').format(p.name, p.port) : _('Access point %s.').format(p.name);
		else if (codeKind(text) === 'router') msg = _('This is a router\'s code: paste it on the access point instead.');
		else if (normCode(text)) msg = _('This does not look like an access point\'s reply yet.');
		dom.content(f.seen, msg ? [ msg ] : []);
	},

	submitAdd: function() {
		var self = this, f = this.add;
		var code = normCode(f.reply.value), addr = addrOverride(f.addr.value, f.parsed);
		if (!code) return;
		f.go.disabled = true;
		f.err.hidden = true;
		return callAddAp(code, addr).then(function(res) {
			if (isObject(res) && typeof res.id === 'string') {
				self.closeAdd();
				return self.refresh();
			}
			f.err.hidden = false;
			dom.content(f.err, [ addError(res, addr !== undefined) ]);
		}, function(e) {
			f.err.hidden = false;
			dom.content(f.err, [ failed(e) ]);
		}).then(function() { f.go.disabled = !normCode(f.reply.value); });
	},

	/* -------------------------------------- this device as an access point */

	renderAp: function() {
		var el = this.el;
		el.ssh = E('div', { 'class': 'vt-pair-notes' });
		el.routerRows = E('div', { 'class': 'vt-pair-rows', 'role': 'list', 'aria-label': _('Routers that can read this access point') });
		el.allowBtn = E('button', { 'type': 'button', 'class': 'vt-btn', 'click': L.bind(this.openAllow, this) }, [ _('Let a router read this access point') ]);
		el.allowFlow = this.renderAllow();
		el.again = this.copyBox(_('This access point\'s reply'));
		el.againBox = E('details', { 'class': 'vt-pair-again', 'hidden': 'hidden' }, [
			E('summary', {}, [ _('Show this access point\'s reply again') ]),
			E('p', { 'class': 'vt-hint' }, [ _('For a router you already let in: paste it there, under Add an access point.') ]),
			el.again.el
		]);
		return this.tile('router', _('Routers that can read this access point'),
			_('A router you let in can fetch this device\'s report (its Wi-Fi networks, clients and wired hosts) over SSH, and nothing else.'), [
				el.ssh,
				el.routerRows,
				E('div', { 'class': 'vt-pair-actions' }, [ el.allowBtn ]),
				el.allowFlow,
				el.againBox
			]);
	},

	paintRouters: function() {
		var self = this, el = this.el, s = this.status;
		var problem = sshProblem(s.ssh);
		if (problem !== this.sshShown) {
			this.sshShown = problem;
			dom.content(el.ssh, problem ? [ warnNote(problem) ] : []);
		}
		/* the key file unread, whatever else is wrong with SSH: an empty list says nothing about who is let in */
		var unknown = s.keysUnread;
		var sig = JSON.stringify([ unknown ].concat(s.routers.map(function(r) { return [ r.key, r.name ]; })));
		if (sig !== this.routerSig) {
			this.routerSig = sig;
			dom.content(el.routerRows, s.routers.length ? s.routers.map(function(r) { return self.routerRow(r); })
				: [ E('p', { 'class': 'vt-empty-inline', 'role': 'listitem' }, [ unknown ? _('Not known while this device\'s SSH keys cannot be read.') : _('No router can read this access point.') ]) ]);
		}
		/* with SSH not ready, letting a router in is refused: no button;
		   the reply again only while the flow (which shows it) is closed */
		el.allowBtn.hidden = !!problem || !el.allowFlow.hidden;
		el.againBox.hidden = !s.reply || !el.allowFlow.hidden;
		if (s.reply && el.again.field.value !== s.reply) el.again.set(s.reply);
	},

	routerRow: function(r) {
		var self = this;
		var revoke = E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-ghost vt-pair-act', 'aria-label': _('Revoke %s').format(r.name),
			'click': function() { self.confirmRevoke(r, revoke); } }, [ _('Revoke') ]);
		return E('div', { 'class': 'vt-pair-row', 'role': 'listitem' }, [
			E('div', { 'class': 'vt-pair-main' }, [
				E('span', { 'class': 'vt-pair-name' }, [ r.name ]),
				E('span', { 'class': 'vt-pair-sub vt-mono', 'title': _('Its SSH key') }, [ shortKey(r.key) ])
			]),
			revoke
		]);
	},

	confirmRevoke: function(r, opener) {
		ui.showModal(_('Revoke router'), this.confirmBody(
			_('%s will no longer be able to read this access point, from its next fetch on.').format(r.name),
			_('Revoke'),
			function() { return callRevokeRouter(r.key); },
			opener, this.el.allowBtn));
	},

	renderAllow: function() {
		var self = this, f = this.allow = {};
		f.code = E('textarea', { 'class': 'vt-pair-field vt-pair-code', 'rows': 3, 'spellcheck': 'false', 'autocomplete': 'off',
			'aria-label': _('The router\'s code'), 'placeholder': 'vantage-router 1 ssh-ed25519 …', 'input': function() { self.onRouterCode(); } });
		f.seen = E('p', { 'class': 'vt-hint', 'aria-live': 'polite' });
		f.where = E('p', { 'class': 'vt-hint' }, [ _('The router shows it under Network → Access points → Add an access point.') ]);
		f.err = E('p', { 'class': 'vt-form-err', 'hidden': 'hidden', 'role': 'alert' });
		f.go = E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-primary', 'disabled': 'disabled', 'click': function() { self.submitAllow(); } }, [ _('Let the router read') ]);
		f.reply = this.copyBox(_('This access point\'s reply'));
		/* step 2 appears under step 1 once the router is in */
		f.step2 = this.step(2, _('Copy this access point\'s reply'), [ f.reply.el,
			E('p', { 'class': 'vt-hint' }, [ _('Paste it on the router, in the form that showed its code.') ]) ]);
		f.step2.hidden = true;
		f.ask = E('div', { 'class': 'vt-pair-actions' }, [ f.go,
			E('button', { 'type': 'button', 'class': 'vt-btn vt-btn-ghost', 'click': function() { self.closeAllow(); } }, [ _('Cancel') ]) ]);
		f.done = E('div', { 'class': 'vt-pair-actions', 'hidden': 'hidden' }, [
			E('button', { 'type': 'button', 'class': 'vt-btn', 'click': function() { self.closeAllow(); } }, [ _('Done') ]) ]);
		return E('div', { 'class': 'vt-pair-flow', 'role': 'group', 'aria-label': _('Let a router read this access point'), 'hidden': 'hidden' }, [
			E('ol', { 'class': 'vt-pair-steps' }, [ this.step(1, _('Paste the router\'s code'), [ f.code, f.seen, f.where ]), f.step2 ]),
			f.err, f.ask, f.done
		]);
	},

	openAllow: function() {
		var f = this.allow;
		f.code.value = '';
		f.code.readOnly = false;
		f.where.hidden = false;
		f.err.hidden = true;
		f.step2.hidden = true;
		f.ask.hidden = false;
		f.done.hidden = true;
		this.onRouterCode();
		this.el.allowFlow.hidden = false;
		this.paintRouters();
		f.code.focus();
	},

	closeAllow: function() {
		this.el.allowFlow.hidden = true;
		this.paintRouters();
		if (!this.el.allowBtn.hidden) this.el.allowBtn.focus();
	},

	onRouterCode: function() {
		var f = this.allow, text = f.code.value;
		f.go.disabled = !normCode(text);
		f.err.hidden = true;
		var kind = codeKind(text), name = codeFields(text)[4];
		var msg = kind === 'ap' ? _('This is an access point\'s reply: paste it on the router instead.')
			: (kind === 'router' && NAME_RE.test(name || '')) ? _('Router %s.').format(name) : '';
		dom.content(f.seen, msg ? [ msg ] : []);
	},

	submitAllow: function() {
		var self = this, f = this.allow, code = normCode(f.code.value);
		if (!code) return;
		f.go.disabled = true;
		f.err.hidden = true;
		return callAllowRouter(code).then(function(res) {
			if (isObject(res) && typeof res.reply === 'string') {
				f.reply.set(res.reply);
				f.code.readOnly = true;
				f.where.hidden = true;
				f.step2.hidden = false;
				f.ask.hidden = true;
				f.done.hidden = false;
				f.reply.btn.focus();
				return self.refresh();
			}
			f.err.hidden = false;
			dom.content(f.err, [ allowError(res) ]);
		}, function(e) {
			f.err.hidden = false;
			dom.content(f.err, [ failed(e) ]);
		}).then(function() { f.go.disabled = !normCode(f.code.value); });
	}
});
