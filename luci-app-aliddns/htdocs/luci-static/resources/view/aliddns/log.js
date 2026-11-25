'use strict';
'require view';
'require dom';
'require poll';
'require rpc';
'require ui';

const callGetLog = rpc.declare({
	object: 'luci.aliddns',
	method: 'get_log',
	params: [ 'lines' ],
	expect: { '': {} }
});

const callClearLog = rpc.declare({
	object: 'luci.aliddns',
	method: 'clear_log',
	expect: { '': {} }
});

const callTriggerUpdate = rpc.declare({
	object: 'luci.aliddns',
	method: 'trigger_update',
	params: [ 'force', 'record_id' ],
	expect: { '': {} }
});

function ensureStylesheet() {
	const href = L.resource('aliddns/aliddns.css');
	if (!document.querySelector('link[href="' + href + '"]')) {
		document.head.appendChild(E('link', {
			'rel': 'stylesheet',
			'type': 'text/css',
			'href': href
		}));
	}
}

function classifyLogLine(line) {
	if (line.indexOf('[ERROR]') !== -1)
		return 'aliddns-log-line aliddns-log-error';
	if (line.indexOf('[WARN]') !== -1)
		return 'aliddns-log-line aliddns-log-warn';
	if (line.indexOf('成功') !== -1 || line.indexOf('UPDATED') !== -1)
		return 'aliddns-log-line aliddns-log-updated';
	return 'aliddns-log-line';
}

return view.extend({
	rawLog: '',
	logContainer: null,
	countLabel: null,
	reverseOrder: true,
	autoRefresh: true,
	levelFilter: 'all',
	keyword: '',

	renderLogNodes: function() {
		if (!this.logContainer)
			return;

		const text = (this.rawLog || '').trim();
		if (!text) {
			dom.content(this.logContainer, E('div', { 'style': 'opacity:0.65;' }, _('No log entries yet.')));
			if (this.countLabel)
				this.countLabel.textContent = _('0 entries');
			return;
		}

		let lines = text.split('\n');
		const totalCount = lines.length;

		if (this.levelFilter === 'warn_error') {
			lines = lines.filter(function(l) {
				return l.indexOf('[ERROR]') !== -1 || l.indexOf('[WARN]') !== -1;
			});
		} else if (this.levelFilter === 'changes') {
			lines = lines.filter(function(l) {
				return l.indexOf('成功') !== -1 || l.indexOf('[ERROR]') !== -1 || l.indexOf('[WARN]') !== -1;
			});
		}

		const kw = (this.keyword || '').trim().toLowerCase();
		if (kw) {
			lines = lines.filter(function(l) {
				return l.toLowerCase().indexOf(kw) !== -1;
			});
		}

		if (this.reverseOrder)
			lines.reverse();

		if (this.countLabel)
			this.countLabel.textContent = _('Showing %d / %d entries').format(lines.length, totalCount);

		if (lines.length === 0) {
			dom.content(this.logContainer, E('div', { 'style': 'opacity:0.65;' }, _('No matching log entries.')));
			return;
		}

		const nodes = lines.map(function(l) {
			return E('div', { 'class': classifyLogLine(l) }, l);
		});
		dom.content(this.logContainer, nodes);
	},

	refreshLogs: function() {
		const self = this;
		return callGetLog(300).then(function(res) {
			self.rawLog = (res && res.log) ? res.log : '';
			self.renderLogNodes();
		}).catch(function() {});
	},

	load: function() {
		return callGetLog(300).catch(function() { return { log: '' }; });
	},

	render: function(data) {
		ensureStylesheet();
		const self = this;
		this.rawLog = (data && data.log) ? data.log : '';

		this.logContainer = E('div', { 'class': 'aliddns-log-box' });
		this.countLabel = E('span', { 'class': 'aliddns-meta-item' }, '');

		const filterSelect = E('select', {
			'class': 'cbi-input-select',
			'style': 'width:auto;min-width:150px;',
			'change': function(ev) {
				self.levelFilter = ev.target.value;
				self.renderLogNodes();
			}
		}, [
			E('option', { 'value': 'all' }, _('All Log Levels')),
			E('option', { 'value': 'changes' }, _('Updates & Alerts Only')),
			E('option', { 'value': 'warn_error' }, _('Warnings & Errors Only'))
		]);

		const searchInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:200px;',
			'placeholder': _('Filter by domain or IP...'),
			'input': function(ev) {
				self.keyword = ev.target.value || '';
				self.renderLogNodes();
			}
		});

		const reverseToggle = E('input', {
			'type': 'checkbox',
			'checked': 'checked',
			'change': function(ev) {
				self.reverseOrder = !!ev.target.checked;
				self.renderLogNodes();
			}
		});

		const autoToggle = E('input', {
			'type': 'checkbox',
			'checked': 'checked',
			'change': function(ev) {
				self.autoRefresh = !!ev.target.checked;
			}
		});

		const btnSync = E('button', {
			'type': 'button',
			'class': 'btn cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, function() {
				return callTriggerUpdate(true, '').then(function() {
					return new Promise(function(resolve) {
						window.setTimeout(resolve, 1200);
					});
				}).then(function() {
					return self.refreshLogs();
				});
			})
		}, _('Sync All'));

		const btnDownload = E('button', {
			'type': 'button',
			'class': 'btn cbi-button cbi-button-neutral',
			'click': function() {
				const blob = new Blob([ self.rawLog || '' ], { type: 'text/plain;charset=utf-8' });
				const url = URL.createObjectURL(blob);
				const a = document.createElement('a');
				a.href = url;
				a.download = 'aliddns.log';
				document.body.appendChild(a);
				a.click();
				document.body.removeChild(a);
				URL.revokeObjectURL(url);
			}
		}, _('Export Log'));

		const btnClear = E('button', {
			'type': 'button',
			'class': 'btn cbi-button cbi-button-reset',
			'click': ui.createHandlerFn(this, function() {
				return callClearLog().then(function() {
					return self.refreshLogs();
				});
			})
		}, _('Clear Log'));

		this.renderLogNodes();

		poll.add(function() {
			if (!self.autoRefresh)
				return Promise.resolve();
			return self.refreshLogs();
		}, 5);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('AliDDNS') + ' - ' + _('Log Viewer')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Live synchronization log from /var/log/aliddns.log (automatically retains the latest 300 entries).')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-section-node', 'style': 'padding:12px 16px;' }, [
					E('div', { 'class': 'aliddns-log-toolbar' }, [
						E('div', { 'class': 'aliddns-log-filters' }, [
							filterSelect,
							searchInput,
							E('label', { 'style': 'display:inline-flex;align-items:center;gap:5px;cursor:pointer;font-size:12.5px;' }, [
								reverseToggle,
								_('Newest first')
							]),
							E('label', { 'style': 'display:inline-flex;align-items:center;gap:5px;cursor:pointer;font-size:12.5px;' }, [
								autoToggle,
								_('Auto refresh')
							]),
							this.countLabel
						]),
						E('div', { 'class': 'aliddns-btn-group' }, [ btnSync, btnDownload, btnClear ])
					]),
					this.logContainer
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
