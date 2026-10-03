'use strict';
'require view';
'require dom';
'require ui';
'require uci';
'require fs';
'require poll';

var HELPER = '/usr/share/hermes/luci-helper';

function callHelper(args) {
	return L.resolveDefault(fs.exec_direct(HELPER, args), '').then(function(res) {
		try { return JSON.parse(String(res).trim()); }
		catch(e) { return {}; }
	});
}

function fmtMem(kb) {
	kb = parseInt(kb) || 0;
	if (kb <= 0) return '-';
	if (kb >= 1048576) return (kb / 1048576).toFixed(1) + ' GB';
	if (kb >= 1024) return (kb / 1024).toFixed(1) + ' MB';
	return kb + ' KB';
}

/* ── Logo ── */
var LOGO_SVG = '<img src="/luci-static/hermes/logo.svg" width="44" height="44" style="vertical-align:middle;border-radius:8px" onerror="this.style.display=\'none\'">';

/* ── CSS: inherit page theme ── */
var CSS = '\
*,*::before,*::after{box-sizing:border-box}\
#hm-app{margin:0;padding:0;width:100%;color:inherit}\
.hm-header{padding:6px 0 4px;display:flex;align-items:center;gap:10px}\
.hm-header h2{margin:0;font-size:20px;font-weight:600;color:inherit}\
.hm-header .sub{font-size:11px;opacity:.5;margin-top:2px;letter-spacing:.3px}\
.hm-header>*,.hm-header h2,.hm-header .sub{background:transparent!important;box-shadow:none!important;border:none!important;border-radius:0!important;padding:0!important;margin:0!important}\
.hm-tabs{display:flex;border-bottom:2px solid currentColor;border-bottom-color:rgba(128,128,128,.25);overflow:hidden}\
.hm-tab{padding:10px 18px;font-size:13px;font-weight:500;opacity:.55;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px;transition:all .2s;white-space:nowrap;user-select:none;color:inherit}\
.hm-tab:hover{opacity:.85}\
.hm-tab.active{opacity:1;border-bottom-color:var(--primary,#5e72e4)}\
.hm-panel{display:none;padding:20px 0}\
.hm-panel.active{display:block}\
.hm-cards{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:16px}\
.hm-card{border:1px solid rgba(128,128,128,.2);border-radius:10px;padding:14px 16px}\
.hm-card .lbl{font-size:11px;opacity:.55;letter-spacing:.3px}\
.hm-card .val{font-size:22px;font-weight:700;margin-top:4px;line-height:1.2}\
.hm-card .val.sm{font-size:15px;font-weight:600}\
.hm-badge{display:inline-block;padding:3px 14px;border-radius:20px;font-size:12px;font-weight:600}\
.hm-badge-run{background:#e8f5e9;color:#2e7d32}\
.hm-badge-stop{background:#ffebee;color:#c62828}\
.hm-badge-start{background:#fff8e1;color:#f57f17}\
.hm-badge-off{opacity:.5}\
.hm-dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px;vertical-align:middle}\
.hm-dot-g{background:#2e7d32}.hm-dot-r{background:#c62828}.hm-dot-y{background:#f57f17}.hm-dot-x{background:#9e9e9e}\
.hm-info{border:1px solid rgba(128,128,128,.2);border-radius:10px;padding:0;overflow:hidden;margin-bottom:20px}\
.hm-info-title{padding:12px 18px;font-size:13px;font-weight:600;opacity:.7;border-bottom:1px solid rgba(128,128,128,.15)}\
.hm-info table{width:100%;border-collapse:collapse}\
.hm-info tr,.hm-info tr:nth-of-type(2n){background:transparent!important}\
.hm-info td{padding:8px 16px;font-size:13px;border-bottom:1px solid rgba(128,128,128,.1)}\
.hm-info tr:last-child td{border-bottom:none}\
.hm-info td:first-child{width:100px;opacity:.6;font-weight:500}\
.hm-info td:last-child{word-break:break-all}\
.hm-actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:16px}\
.hm-btn{padding:8px 16px;border:none;border-radius:8px;font-size:13px;font-weight:500;cursor:pointer;transition:all .15s;display:inline-flex;align-items:center;gap:6px}\
.hm-btn:hover{filter:brightness(.93)}\
.hm-btn:active{transform:scale(.97)}\
.hm-btn:disabled{opacity:.5;cursor:not-allowed;transform:none;filter:none}\
.hm-btn-p{background:var(--primary,#5e72e4);color:#fff}\
.hm-btn-s{background:#1b5e20;color:#fff;box-shadow:0 2px 6px rgba(27,94,32,.35)}\
.hm-btn-s:hover{background:#2e7d32}\
.hm-btn-d{background:#37474f;color:#fff;box-shadow:0 2px 6px rgba(55,71,79,.3)}\
.hm-btn-d:hover{background:#546e7a}\
.hm-btn-r{background:#1565c0;color:#fff;box-shadow:0 2px 6px rgba(21,101,192,.35)}\
.hm-btn-r:hover{background:#1976d2}\
.hm-btn-g{border:1px solid rgba(128,128,128,.3);color:inherit;background:transparent}\
.hm-btn-icon{padding:6px 10px;font-size:16px;line-height:1;min-width:unset}\
.hm-log-wrap{margin-top:16px;display:none}\
.hm-log-hdr{display:flex;align-items:center;justify-content:space-between;margin-bottom:6px}\
.hm-log-hdr span{font-weight:600;font-size:13px;opacity:.7}\
.hm-log-st{font-size:12px}\
.hm-log{background:#1e1e2e;color:#cdd6f4;padding:14px 16px;border-radius:8px;font-family:Consolas,Monaco,"Courier New",monospace;font-size:12px;line-height:1.6;max-height:380px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;border:1px solid #313244}\
.hm-log-result{margin-top:10px;padding:12px 16px;border-radius:8px;font-size:13px}\
.hm-log-ok{background:#e8f5e9;border:1px solid #c8e6c9;color:#2e7d32}\
.hm-log-fail{background:#ffebee;border:1px solid #ffcdd2;color:#c62828}\
.hm-form{border:1px solid rgba(128,128,128,.2);border-radius:10px;overflow:hidden;margin-bottom:20px}\
.hm-form-title{padding:12px 18px;font-size:13px;font-weight:600;opacity:.7;border-bottom:1px solid rgba(128,128,128,.15)}\
.hm-form-body{padding:6px 18px}\
.hm-form-row{display:flex;align-items:center;padding:12px 0;border-bottom:1px solid rgba(128,128,128,.1)}\
.hm-form-row:last-child{border-bottom:none}\
.hm-form-lbl{width:120px;font-size:13px;font-weight:500;opacity:.7;flex-shrink:0}\
.hm-form-ctl{flex:1;min-width:0}\
.hm-form-ctl input,.hm-form-ctl select{padding:7px 10px;border:1px solid rgba(128,128,128,.3);border-radius:6px;font-size:13px;width:100%;max-width:260px;outline:none;transition:border-color .2s;background:transparent;color:inherit}\
.hm-form-ctl input:focus,.hm-form-ctl select:focus{border-color:var(--primary,#5e72e4)}\
.hm-form-hint{font-size:11px;opacity:.5;margin-top:3px}\
.hm-iframe-wrap{border:2px solid rgba(128,128,128,.2);border-radius:10px;overflow:hidden;margin-top:10px}\
.hm-iframe-wrap iframe{width:100%;height:650px;border:none;display:block}\
.hm-iframe-msg{padding:48px;text-align:center;opacity:.55;font-size:14px;line-height:1.8}\
.hm-iframe-msg .icon{font-size:36px;margin-bottom:12px}\
.hm-switch{position:relative;display:inline-block;width:44px;height:24px}\
.hm-switch input{opacity:0;width:0;height:0}\
.hm-switch .slider{position:absolute;cursor:pointer;top:0;left:0;right:0;bottom:0;background:rgba(128,128,128,.35);border-radius:24px;transition:.3s}\
.hm-switch .slider:before{position:absolute;content:"";height:18px;width:18px;left:3px;bottom:3px;background:#fff;border-radius:50%;transition:.3s}\
.hm-switch input:checked+.slider{background:var(--primary,#5e72e4)}\
.hm-switch input:checked+.slider:before{transform:translateX(20px)}\
.hm-more-wrap{position:relative;display:inline-block}\
.hm-more-menu{position:fixed;border:1px solid rgba(128,128,128,.2);border-radius:10px;box-shadow:0 -4px 20px rgba(0,0,0,.15);min-width:190px;z-index:9999;display:none;overflow:hidden;padding:4px 0;background:var(--background-color-low,#f8f8f8)}\
.hm-more-item{display:flex;align-items:center;gap:8px;padding:10px 16px;font-size:13px;cursor:pointer;border:none;background:none;width:100%;text-align:left;transition:background .12s;color:inherit}\
.hm-more-item:hover{background:rgba(128,128,128,.1)}\
.hm-more-item.danger{color:inherit;background:none}\
.hm-more-item.danger:hover{background:rgba(128,128,128,.1)}\
.hm-more-sep{height:1px;background:rgba(128,128,128,.15);margin:4px 0}\
@media(max-width:768px){\
#hm-app{padding:0 10px;overflow-x:hidden}\
.hm-tabs{max-width:100%}\
.hm-header{padding:8px 0;gap:10px}\
.hm-header h2{font-size:16px}\
.hm-cards{grid-template-columns:repeat(2,1fr);gap:10px}\
.hm-card .val{font-size:17px}\
.hm-card .val.sm{font-size:13px}\
.hm-actions{gap:6px;flex-wrap:wrap;max-width:100%}\
.hm-actions>*{flex:0 1 auto;min-width:0}\
.hm-actions .hm-btn{padding:7px 10px;font-size:12px;white-space:nowrap;justify-content:center}\
.hm-form-row{flex-direction:column;align-items:stretch;gap:4px}\
.hm-form-lbl{width:auto}\
.hm-form-ctl input,.hm-form-ctl select{max-width:100%}\
.hm-iframe-wrap iframe{height:400px}\
.hm-info td:first-child{width:80px}\
}\
@media(max-width:420px){\
.hm-header{padding:6px 0}\
.hm-header h2{font-size:15px}\
.hm-tab{padding:9px 14px;font-size:12px}\
.hm-btn{padding:6px 10px;font-size:12px}\
.hm-actions .hm-btn{padding:6px 8px;font-size:11px}\
.hm-info td{padding:7px 12px;font-size:12px}\
.hm-cards{gap:8px}\
.hm-card{padding:10px 12px}\
.hm-card .val{font-size:16px}\
.hm-iframe-wrap iframe{height:350px}\
}\
';

return view.extend({

	load: function() {
		return Promise.all([
			uci.load('hermes'),
			callHelper(['status'])
		]);
	},

	render: function(data) {
		var st = data[1] || {};
		this._st = st;
		this._setupTimer = null;
		this._tabEls = {};

		var contentEl = E('div', { 'id': 'hm-content' }, [
			this._overview(st),
			this._settings(),
			this._console(st),
			this._terminal(st)
		]);
		this._contentEl = contentEl;

		var app = E('div', { 'id': 'hm-app' }, [
			E('style', {}, [CSS]),
			this._header(),
			this._tabBar(),
			contentEl
		]);

		this._switchTab('overview');
		poll.add(L.bind(this._poll, this), 5);

		document.addEventListener('click', function() {
			var m = document.getElementById('hm-more-menu');
			if (m) m.style.display = 'none';
		});

		return app;
	},

	/* ═══ Header ═══ */
	_header: function() {
		var h = E('div', { 'class': 'hm-header' });
		h.innerHTML = LOGO_SVG +
			'<div><h2>Hermes Agent</h2>' +
			'<div class="sub">' + _('Python AI Agent Gateway for OpenWrt') + '</div></div>';
		return h;
	},

	/* ═══ Tabs ═══ */
	_tabBar: function() {
		var self = this;
		var tabs = [
			['overview', _('Overview')],
			['settings', _('Settings')],
			['console',  _('Web Console')],
			['terminal', _('Config Terminal')]
		];
		var bar = E('div', { 'class': 'hm-tabs' });
		tabs.forEach(function(t) {
			var el = E('div', {
				'class': 'hm-tab',
				'data-tab': t[0],
				'click': function() { self._switchTab(t[0]); }
			}, [t[1]]);
			self._tabEls[t[0]] = el;
			bar.appendChild(el);
		});
		return bar;
	},

	_switchTab: function(id) {
		var self = this;
		Object.keys(this._tabEls).forEach(function(k) {
			self._tabEls[k].classList.toggle('active', k === id);
		});
		var root = this._contentEl || document.getElementById('hm-content');
		if (root) {
			var panels = root.querySelectorAll('.hm-panel');
			if (panels) panels.forEach(function(p) {
				p.classList.toggle('active', p.getAttribute('data-panel') === id);
			});
		}
	},

	/* ═══ Overview Panel ═══ */
	_overview: function(st) {
		return E('div', { 'class': 'hm-panel', 'data-panel': 'overview' }, [
			/* Status Cards */
			E('div', { 'class': 'hm-cards' }, [
				this._card('status',  _('Service Status'), this._badge(st)),
				this._card('port',    _('Gateway Port'),   st.port || '3000', true),
				this._card('memory',  _('Memory'),         fmtMem(st.memory_kb), true),
				this._card('uptime',  _('Uptime'),         st.uptime || '-', true)
			]),
			/* Version Info */
			this._infoTable(st),
			/* Action Buttons */
			this._actionBtns(),
			/* Log Viewer */
			this._logViewer()
		]);
	},

	_card: function(id, label, valueHtml, small) {
		var c = E('div', { 'class': 'hm-card' }, [
			E('div', { 'class': 'lbl' }, [label]),
			E('div', { 'class': 'val' + (small ? ' sm' : ''), 'id': 'hm-c-' + id })
		]);
		if (typeof valueHtml === 'string' && valueHtml.indexOf('<') >= 0)
			c.querySelector('.val').innerHTML = valueHtml;
		else
			c.querySelector('.val').textContent = valueHtml || '-';
		return c;
	},

	_badge: function(st) {
		if (!st || !st.enabled) return '<span class="hm-badge hm-badge-off">' + _('Unknown') + '</span>';
		if (st.enabled !== '1') return '<span class="hm-badge hm-badge-off"><span class="hm-dot hm-dot-x"></span>' + _('Disabled') + '</span>';
		if (st.gateway_running) return '<span class="hm-badge hm-badge-run"><span class="hm-dot hm-dot-g"></span>' + _('Running') + '</span>';
		if (st.gateway_starting) return '<span class="hm-badge hm-badge-start"><span class="hm-dot hm-dot-y"></span>' + _('Starting') + '</span>';
		return '<span class="hm-badge hm-badge-stop"><span class="hm-dot hm-dot-r"></span>' + _('Stopped') + '</span>';
	},

	_infoTable: function(st) {
		var rows = [
			[_('Python'),     'hm-i-python',  st.python_version || _('Not installed')],
			[_('Hermes'),     'hm-i-hermes',  st.hermes_version || _('Not installed')],
			[_('Plugin'),     'hm-i-plugin',  st.plugin_version || '-'],
			[_('Model'),      'hm-i-model',   st.active_model || '-'],
			[_('PID'),        'hm-i-pid',     st.pid || '-'],
			[_('Config PTY'), 'hm-i-pty',     st.pty_running ? '✅ ' + _('Running') + ' (:' + (st.pty_port || '3001') + ')' : '⏹ ' + _('Stopped')]
		];
		var tbody = E('tbody');
		rows.forEach(function(r) {
			tbody.appendChild(E('tr', {}, [
				E('td', {}, [r[0]]),
				E('td', { 'id': r[1] }, [r[2]])
			]));
		});
		return E('div', { 'class': 'hm-info' }, [
			E('div', { 'class': 'hm-info-title' }, [_('System Information')]),
			E('table', {}, [tbody])
		]);
	},

	_actionBtns: function() {
		var self = this;
		var wrap = E('div', { 'class': 'hm-actions' });

		wrap.appendChild(E('button', {
			'class': 'hm-btn hm-btn-s', 'id': 'hm-btn-start',
			'click': function() { self._svcCtl('start'); }
		}, ['▶ ' + _('Start')]));

		wrap.appendChild(E('button', {
			'class': 'hm-btn hm-btn-d', 'id': 'hm-btn-stop',
			'click': function() { self._svcCtl('stop'); }
		}, ['⏹ ' + _('Stop')]));

		wrap.appendChild(E('button', {
			'class': 'hm-btn hm-btn-r', 'id': 'hm-btn-restart',
			'click': function() { self._svcCtl('restart'); }
		}, ['🔄 ' + _('Restart')]));

		/* More menu */
		var gearWrap = E('div', { 'class': 'hm-more-wrap' });
		gearWrap.appendChild(E('button', {
			'class': 'hm-btn hm-btn-g hm-btn-icon', 'title': _('More'),
			'click': function(ev) {
				ev.stopPropagation();
				var m = document.getElementById('hm-more-menu');
				if (!m) return;
				if (m.style.display === 'block') { m.style.display = 'none'; return; }
				var rect = ev.currentTarget.getBoundingClientRect();
				m.style.display = 'block';
				var mh = m.offsetHeight;
				m.style.top = (rect.top - mh - 6) + 'px';
				m.style.left = 'auto';
				m.style.right = (window.innerWidth - rect.right) + 'px';
			}
		}, ['⚙']));

		gearWrap.appendChild(E('div', { 'class': 'hm-more-menu', 'id': 'hm-more-menu' }, [
			E('div', { 'class': 'hm-more-item', 'click': function() { self._closeMenu(); self._showSetupDialog(); } }, ['📦 ' + _('Install Environment')]),
			E('div', { 'class': 'hm-more-sep' }),
			E('div', { 'class': 'hm-more-item', 'click': function() { self._closeMenu(); self._uninstall(); } }, ['🗑️ ' + _('Uninstall')])
		]));

		wrap.appendChild(gearWrap);
		return wrap;
	},

	_closeMenu: function() {
		var m = document.getElementById('hm-more-menu');
		if (m) m.style.display = 'none';
	},

	_logViewer: function() {
		return E('div', { 'class': 'hm-log-wrap', 'id': 'hm-log-wrap' }, [
			E('div', { 'class': 'hm-log-hdr' }, [
				E('span', { 'id': 'hm-log-title' }, ['📋 ' + _('Log')]),
				E('span', { 'class': 'hm-log-st', 'id': 'hm-log-st' })
			]),
			E('pre', { 'class': 'hm-log', 'id': 'hm-log' }),
			E('div', { 'id': 'hm-log-result' })
		]);
	},

	/* ═══ Settings Panel ═══ */
	_settings: function() {
		var self = this;
		var enabled = uci.get('hermes', 'main', 'enabled') === '1';
		var port = uci.get('hermes', 'main', 'port') || '3000';
		var bind = uci.get('hermes', 'main', 'bind') || 'lan';
		var ptyPort = uci.get('hermes', 'main', 'pty_port') || '3001';
		var apiEndpoint = uci.get('hermes', 'main', 'api_endpoint') || 'https://api.boos.lat/v1';
		var apiKey = uci.get('hermes', 'main', 'api_key') || '';
		var model = uci.get('hermes', 'main', 'model') || 'opus4.6';

		return E('div', { 'class': 'hm-panel', 'data-panel': 'settings' }, [
			E('div', { 'class': 'hm-form' }, [
				E('div', { 'class': 'hm-form-title' }, [_('Basic Settings')]),
				E('div', { 'class': 'hm-form-body' }, [
					this._formRow(_('Enable Service'), this._toggle('hm-f-enabled', enabled)),
					this._formRow(_('Gateway Port'), this._input('hm-f-port', port, 'number', _('Default: 3000'))),
					this._formRow(_('Listen Interface'), this._select('hm-f-bind', bind, [
						['lan', 'LAN'],
						['loopback', 'Loopback'],
						['all', _('All Interfaces')]
					])),
					this._formRow(_('PTY Port'), this._input('hm-f-pty-port', ptyPort, 'number', _('Default: 3001')))
				])
			]),
			E('div', { 'class': 'hm-form' }, [
				E('div', { 'class': 'hm-form-title' }, [_('API Settings')]),
				E('div', { 'class': 'hm-form-body' }, [
					this._formRow(_('API Endpoint'), this._input('hm-f-api-endpoint', apiEndpoint, 'text', _('Default: https://api.boos.lat/v1'))),
					this._formRow(_('API Key'), this._input('hm-f-api-key', apiKey, 'password', _('Your API key'))),
					this._formRow(_('Model'), this._input('hm-f-model', model, 'text', _('Default: opus4.6')))
				])
			]),
			E('div', { 'class': 'hm-actions' }, [
				E('button', { 'class': 'hm-btn hm-btn-p', 'click': function() { self._saveSettings(); } }, ['💾 ' + _('Save & Apply')]),
				E('button', { 'class': 'hm-btn hm-btn-g', 'click': function() { location.reload(); } }, [_('Reset')])
			])
		]);
	},

	_formRow: function(label, control) {
		return E('div', { 'class': 'hm-form-row' }, [
			E('div', { 'class': 'hm-form-lbl' }, [label]),
			E('div', { 'class': 'hm-form-ctl' }, [control])
		]);
	},

	_toggle: function(id, checked) {
		var lbl = E('label', { 'class': 'hm-switch' });
		lbl.innerHTML = '<input type="checkbox" id="' + id + '"' + (checked ? ' checked' : '') + '><span class="slider"></span>';
		return lbl;
	},

	_input: function(id, value, type, hint) {
		var wrap = E('div');
		wrap.appendChild(E('input', { 'type': type || 'text', 'id': id, 'value': value }));
		if (hint) wrap.appendChild(E('div', { 'class': 'hm-form-hint' }, [hint]));
		return wrap;
	},

	_select: function(id, value, opts) {
		var sel = E('select', { 'id': id });
		opts.forEach(function(o) {
			var opt = E('option', { 'value': o[0] }, [o[1]]);
			if (o[0] === value) opt.setAttribute('selected', 'selected');
			sel.appendChild(opt);
		});
		return sel;
	},

	/* ═══ Console Panel ═══ */
	_console: function(st) {
		var panel = E('div', { 'class': 'hm-panel', 'data-panel': 'console' });
		var container = E('div', { 'class': 'hm-iframe-wrap' });

		if (st.gateway_running) {
			var proto = window.location.protocol;
			var host = window.location.hostname;
			var base = proto + '//' + host + ':' + (st.port || '3000') + '/';

			container.innerHTML = '<div class="hm-iframe-msg"><div class="icon">⏳</div><div>' + _('Connecting...') + '</div></div>';
			callHelper(['get_token']).then(function(tok) {
				var url = base;
				if (tok && tok.token) url += '?token=' + encodeURIComponent(tok.token);
				container.innerHTML = '';
				container.appendChild(E('iframe', {
					'src': url,
					'id': 'hm-console-iframe',
					'allow': 'clipboard-read; clipboard-write',
					'style': 'width:100%;height:650px;border:none;display:block',
					'loading': 'lazy'
				}));
			});
		} else {
			container.innerHTML = '<div class="hm-iframe-msg">' +
				'<div class="icon">🖥️</div>' +
				'<div>' + _('Web console is not available.') + '</div>' +
				'<div style="margin-top:8px;font-size:12px;color:#aaa">' + _('Please start the Hermes service first.') + '</div></div>';
		}
		panel.appendChild(container);
		return panel;
	},

	/* ═══ Terminal Panel ═══ */
	_terminal: function(st) {
		var panel = E('div', { 'class': 'hm-panel', 'data-panel': 'terminal' });
		var container = E('div', { 'class': 'hm-iframe-wrap' });

		if (st.pty_running) {
			var proto = window.location.protocol;
			var host = window.location.hostname;
			var ptyPort = st.pty_port || '3001';
			var url = proto + '//' + host + ':' + ptyPort + '/';

			container.innerHTML = '<div class="hm-iframe-msg">' +
				'<div class="icon">⏳</div>' +
				'<div>' + _('Connecting to config terminal...') + '</div></div>';
			callHelper(['get_token']).then(function(tok) {
				if (tok && tok.pty_token)
					url += '?token=' + encodeURIComponent(tok.pty_token);
				container.innerHTML = '';
				container.appendChild(E('iframe', {
					'src': url,
					'allow': 'clipboard-read; clipboard-write',
					'style': 'width:100%;height:650px;border:none;display:block',
					'loading': 'lazy'
				}));
			});
		} else {
			container.innerHTML = '<div class="hm-iframe-msg">' +
				'<div class="icon">⌨️</div>' +
				'<div>' + _('Config terminal is not running.') + '</div>' +
				'<div style="margin-top:8px;font-size:12px;color:#aaa">' + _('Please start the Hermes service first.') + '</div></div>';
		}
		panel.appendChild(container);
		return panel;
	},

	/* ═══ Status Polling ═══ */
	_poll: function() {
		var self = this;
		return callHelper(['status']).then(function(st) {
			self._st = st;
			self._updateDisplay(st);
		});
	},

	_updateDisplay: function(st) {
		var el;
		/* Status card */
		el = document.getElementById('hm-c-status');
		if (el) el.innerHTML = this._badge(st);
		/* Port */
		el = document.getElementById('hm-c-port');
		if (el) el.textContent = st.port || '3000';
		/* Memory */
		el = document.getElementById('hm-c-memory');
		if (el) el.textContent = fmtMem(st.memory_kb);
		/* Uptime */
		el = document.getElementById('hm-c-uptime');
		if (el) el.textContent = st.uptime || '-';
		/* Info rows */
		var map = {
			'hm-i-python': st.python_version || _('Not installed'),
			'hm-i-hermes': st.hermes_version || _('Not installed'),
			'hm-i-plugin': st.plugin_version || '-',
			'hm-i-model': st.active_model || '-',
			'hm-i-pid': st.pid || '-',
			'hm-i-pty': st.pty_running ? '✅ ' + _('Running') + ' (:' + (st.pty_port || '3001') + ')' : '⏹ ' + _('Stopped')
		};
		Object.keys(map).forEach(function(id) {
			el = document.getElementById(id);
			if (el) el.textContent = map[id];
		});
		/* Button states */
		var startBtn = document.getElementById('hm-btn-start');
		var stopBtn = document.getElementById('hm-btn-stop');
		if (startBtn) startBtn.disabled = !!st.gateway_running;
		if (stopBtn) stopBtn.disabled = !st.gateway_running;
	},

	/* ═══ Service Control ═══ */
	_svcCtl: function(action) {
		var self = this;
		ui.showModal(_('Service Control'), [
			E('p', {}, [_('Executing: ') + action + '...']),
			E('div', { 'class': 'spinning' })
		]);
		return fs.exec('/etc/init.d/hermes', [action]).then(function() {
			return new Promise(function(resolve) { window.setTimeout(resolve, 2500); });
		}).then(function() {
			return self._poll();
		}).then(function() {
			ui.hideModal();
		}).catch(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, [_('Error: ') + (e.message || e)]));
		});
	},

	/* ═══ Setup Dialog ═══ */
	_showSetupDialog: function() {
		var self = this;

		var overlay = E('div', { 'class': 'hm-dialog-overlay', 'id': 'hm-setup-dlg' });
		var dlg = E('div', { 'class': 'hm-dialog' }, [
			E('h3', {}, ['📦 ' + _('Install Environment')]),
			E('div', { 'class': 'hm-dialog-info' }, [
				E('p', {}, [_('This will install Python 3 and Hermes Agent via pip.')]),
				E('p', {}, [_('Requires internet connection and sufficient disk space (~100MB).')])
			]),
			E('div', { 'class': 'hm-dialog-btns' }, [
				E('button', { 'class': 'hm-btn hm-btn-g', 'click': function() { overlay.remove(); } }, [_('Cancel')]),
				E('button', { 'class': 'hm-btn hm-btn-p', 'click': function() { overlay.remove(); self._doSetup(); } }, [_('Install')])
			])
		]);
		overlay.appendChild(dlg);
		document.body.appendChild(overlay);
	},

	_doSetup: function() {
		var self = this;
		var logWrap = document.getElementById('hm-log-wrap');
		var logEl = document.getElementById('hm-log');
		var stEl = document.getElementById('hm-log-st');
		var resultEl = document.getElementById('hm-log-result');

		if (logWrap) logWrap.style.display = 'block';
		if (logEl) logEl.textContent = _('Starting installation') + '...\n';
		if (stEl) stEl.innerHTML = '<span style="color:#1565c0">⏳ ' + _('Installing...') + '</span>';
		if (resultEl) { resultEl.innerHTML = ''; resultEl.className = ''; }

		callHelper(['setup']).then(function() {
			self._pollSetupLog();
		});
	},

	_pollSetupLog: function() {
		var self = this;
		var lastLen = 0;
		if (this._setupTimer) clearInterval(this._setupTimer);

		this._setupTimer = setInterval(function() {
			callHelper(['setup_log']).then(function(r) {
				var logEl = document.getElementById('hm-log');
				var stEl = document.getElementById('hm-log-st');
				var resultEl = document.getElementById('hm-log-result');
				if (!logEl) return;

				if (r.log && r.log.length > lastLen) {
					logEl.textContent += r.log.substring(lastLen);
					lastLen = r.log.length;
				}
				logEl.scrollTop = logEl.scrollHeight;

				if (r.state === 'running') {
					if (stEl) stEl.innerHTML = '<span style="color:#1565c0">⏳ ' + _('Installing...') + '</span>';
				} else if (r.state === 'success') {
					clearInterval(self._setupTimer);
					if (stEl) stEl.innerHTML = '<span style="color:#2e7d32">✅ ' + _('Complete') + '</span>';
					if (resultEl) {
						resultEl.className = 'hm-log-result hm-log-ok';
						resultEl.innerHTML = '<strong>🎉 ' + _('Installation successful!') + '</strong><br>' +
							'<span style="font-size:12px">' + _('Refresh the page to see updated status.') + '</span>' +
							'<br><button class="hm-btn hm-btn-p" style="margin-top:10px" onclick="location.reload()">🔄 ' + _('Refresh') + '</button>';
					}
				} else if (r.state === 'failed') {
					clearInterval(self._setupTimer);
					if (stEl) stEl.innerHTML = '<span style="color:#c62828">❌ ' + _('Failed') + '</span>';
					if (resultEl) {
						resultEl.className = 'hm-log-result hm-log-fail';
						resultEl.textContent = '❌ ' + _('Installation failed. Check the log above for details.');
					}
				}
			});
		}, 1500);
	},

	/* ═══ Uninstall ═══ */
	_uninstall: function() {
		var self = this;
		ui.showModal(_('Confirm Uninstall'), [
			E('p', { 'style': 'color:#c62828' }, [
				'⚠️ ' + _('This will remove Python, Hermes Agent, and all related data.')
			]),
			E('p', {}, [_('This action cannot be undone.')]),
			E('div', { 'style': 'display:flex;gap:10px;justify-content:flex-end;margin-top:16px' }, [
				E('button', { 'class': 'hm-btn hm-btn-g', 'click': function() { ui.hideModal(); } }, [_('Cancel')]),
				E('button', { 'class': 'hm-btn hm-btn-d', 'click': function() {
					ui.hideModal();
					ui.showModal(_('Uninstalling...'), [E('div', { 'class': 'spinning' })]);
					callHelper(['uninstall']).then(function() {
						ui.hideModal();
						ui.addNotification(null, E('p', {}, ['✅ ' + _('Environment uninstalled successfully')]));
						return self._poll();
					});
				} }, ['🗑️ ' + _('Confirm Uninstall')])
			])
		]);
	},

	/* ═══ Save Settings ═══ */
	_saveSettings: function() {
		var self = this;
		var enabled = document.getElementById('hm-f-enabled');
		var port = document.getElementById('hm-f-port');
		var bind = document.getElementById('hm-f-bind');
		var ptyPort = document.getElementById('hm-f-pty-port');
		var apiEndpoint = document.getElementById('hm-f-api-endpoint');
		var apiKey = document.getElementById('hm-f-api-key');
		var model = document.getElementById('hm-f-model');

		uci.set('hermes', 'main', 'enabled', enabled && enabled.checked ? '1' : '0');
		if (port) uci.set('hermes', 'main', 'port', port.value);
		if (bind) uci.set('hermes', 'main', 'bind', bind.value);
		if (ptyPort) uci.set('hermes', 'main', 'pty_port', ptyPort.value);
		if (apiEndpoint) uci.set('hermes', 'main', 'api_endpoint', apiEndpoint.value);
		if (apiKey) uci.set('hermes', 'main', 'api_key', apiKey.value);
		if (model) uci.set('hermes', 'main', 'model', model.value);

		return uci.save().then(function() {
			return uci.apply();
		}).then(function() {
			ui.addNotification(null, E('p', {}, ['✅ ' + _('Settings saved successfully')]));
			return self._poll();
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, [_('Error: ') + (e.message || e)]));
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
