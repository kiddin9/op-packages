'use strict';
'require view';
'require dom';
'require rpc';
'require ui';
'require poll';

var callGetLogs = rpc.declare({
	object: 'luci.tencentddns',
	method: 'get_logs',
	params: [ 'lines' ],
	expect: { '': {} }
});

var callClearLogs = rpc.declare({
	object: 'luci.tencentddns',
	method: 'clear_logs',
	expect: { '': {} }
});

return view.extend({
	rawLogs: '',
	levelFilter: 'all',
	keyword: '',
	newestFirst: true,

	load: function() {
		return callGetLogs(500).catch(function() {
			return { logs: '' };
		});
	},

	renderFilteredLogs: function() {
		if (!this.logViewEl)
			return;

		var text = this.rawLogs || '';
		if (!text.trim()) {
			dom.content(this.logViewEl, E('div', { 'style': 'opacity:0.65;padding:8px 0;' }, _('No log entries available.')));
			return;
		}

		var lines = text.split('\n').filter(function(l) { return l.length > 0; });
		var lvl = this.levelFilter;
		var kw = (this.keyword || '').trim().toLowerCase();

		lines = lines.filter(function(line) {
			if (lvl === 'error' && line.indexOf('[ERROR]') < 0)
				return false;
			if (lvl === 'warn' && line.indexOf('[WARN') < 0 && line.indexOf('[ERROR]') < 0)
				return false;
			if (kw && line.toLowerCase().indexOf(kw) < 0)
				return false;
			return true;
		});

		if (this.newestFirst)
			lines.reverse();

		if (lines.length === 0) {
			dom.content(this.logViewEl, E('div', { 'style': 'opacity:0.65;padding:8px 0;' }, _('No matching log entries.')));
			return;
		}

		var nodes = lines.map(function(line) {
			var colorStyle = '';
			if (line.indexOf('[ERROR]') >= 0)
				colorStyle = 'color:#f87171;font-weight:600;';
			else if (line.indexOf('[WARN') >= 0)
				colorStyle = 'color:#fbbf24;';
			else if (line.indexOf('Created ') >= 0 || line.indexOf('Updated ') >= 0)
				colorStyle = 'color:#4ade80;';

			return E('div', {
				'style': 'padding:2px 0;border-bottom:1px solid rgba(128,128,128,0.12);white-space:pre-wrap;word-break:break-all;' + colorStyle
			}, line);
		});

		dom.content(this.logViewEl, nodes);
	},

	refreshLogs: function() {
		var self = this;
		return callGetLogs(500).then(function(res) {
			self.rawLogs = (res && res.logs) ? res.logs : '';
			self.renderFilteredLogs();
		}).catch(function() {});
	},

	handleDownload: function() {
		var blob = new Blob([ this.rawLogs || '' ], { type: 'text/plain;charset=utf-8' });
		var url = URL.createObjectURL(blob);
		var a = E('a', {
			'href': url,
			'download': 'tencentddns-' + new Date().toISOString().slice(0, 10) + '.log'
		});
		document.body.appendChild(a);
		a.click();
		document.body.removeChild(a);
		URL.revokeObjectURL(url);
	},

	handleClear: function() {
		var self = this;
		return callClearLogs().then(function() {
			return self.refreshLogs();
		});
	},

	render: function(data) {
		var self = this;
		self.rawLogs = (data && data.logs) ? data.logs : '';

		self.logViewEl = E('div', {
			'id': 'tencentddns-log-viewer',
			'style': 'background:#0f172a;color:#e2e8f0;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;' +
				'font-size:12.5px;line-height:1.55;padding:12px 14px;border-radius:6px;max-height:560px;overflow-y:auto;'
		});

		var levelSelect = E('select', {
			'class': 'cbi-input-select',
			'style': 'width:auto;min-width:150px;',
			'change': function(ev) {
				self.levelFilter = ev.target.value;
				self.renderFilteredLogs();
			}
		}, [
			E('option', { 'value': 'all' }, _('All Levels')),
			E('option', { 'value': 'warn' }, _('Warnings & Errors')),
			E('option', { 'value': 'error' }, _('Errors Only'))
		]);

		var searchInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:220px;',
			'placeholder': _('Filter by domain or keyword...'),
			'input': function(ev) {
				self.keyword = ev.target.value || '';
				self.renderFilteredLogs();
			}
		});

		var orderBtn = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'click': function(ev) {
				self.newestFirst = !self.newestFirst;
				ev.target.textContent = self.newestFirst ? _('Order: Newest First') : _('Order: Oldest First');
				self.renderFilteredLogs();
			}
		}, _('Order: Newest First'));

		var toolbar = E('div', {
			'style': 'display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:10px;margin-bottom:12px;'
		}, [
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;' }, [
				levelSelect,
				searchInput,
				orderBtn
			]),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:8px;' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(self, 'refreshLogs')
				}, _('Refresh')),
				E('button', {
					'class': 'btn cbi-button cbi-button-neutral',
					'click': L.bind(self.handleDownload, self)
				}, _('Export Log')),
				E('button', {
					'class': 'btn cbi-button cbi-button-reset',
					'click': ui.createHandlerFn(self, 'handleClear')
				}, _('Clear Log'))
			])
		]);

		self.renderFilteredLogs();
		poll.add(L.bind(self.refreshLogs, self), 5);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Tencent Cloud DDNS - Log Viewer')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Real-time synchronization logs from /var/log/tencentddns.log (auto-refreshes every 5 seconds).')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-section-node', 'style': 'padding:12px 16px;' }, [
					toolbar,
					self.logViewEl
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
