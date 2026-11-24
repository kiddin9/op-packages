'use strict';
'require rpc';
'require view';
'require dom';
'require ui';
'require poll';

if (!document.getElementById('secbox-theme-css')) {
	document.head.appendChild(E('link', {
		'id': 'secbox-theme-css',
		'rel': 'stylesheet',
		'type': 'text/css',
		'href': L.resource('view/secbox/custom.css')
	}));
}

const callLogRead = rpc.declare({
	object: 'log',
	method: 'read',
	params: ['lines', 'stream', 'oneshot'],
	expect: {}
});

return view.extend({
	load: () => Promise.resolve(),

	render: function () {
		let autoScroll = true;
		let lastRawLogs = [];

		const filterSelect = E('select', {
			'class': 'cbi-input-select',
			'style': 'height: 30px; font-size: 12.5px; width: auto; min-width: 120px;',
			'change': function () {
				renderFiltered();
			}
		}, [
			E('option', { 'value': 'all' }, [_('All Logs')]),
			E('option', { 'value': 'firewall' }, [_('Firewall Log')]),
			E('option', { 'value': 'processing' }, [_('Processing Log')])
		]);

		const searchInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'placeholder': _('Filter logs...'),
			'style': 'height: 30px; font-size: 12.5px; width: 180px !important; margin: 0;',
			'input': function () {
				renderFiltered();
			}
		});

		const countPill = E('span', {
			'class': 'secbox-pill secbox-pill-info',
			'style': 'margin: 0;'
		}, ['0']);

		const autoScrollBtn = E('button', {
			'class': 'btn cbi-button cbi-button-neutral',
			'style': 'margin: 0; min-height: 30px; padding: 3px 10px; font-size: 12.5px;',
			'click': function () {
				autoScroll = !autoScroll;
				this.textContent = autoScroll ? _('Auto-scroll: ON') : _('Auto-scroll: OFF');
			}
		}, [_('Auto-scroll: ON')]);

		function renderFiltered() {
			const logEl = document.getElementById('logfile');
			if (!logEl) return;

			const mode = filterSelect.value;
			const kw = searchInput.value.trim().toLowerCase();
			const wasAtBottom = (logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight) < 24;

			const filtered = lastRawLogs
				.filter(entry => {
					const msgLower = (entry.msg || '').toLowerCase();
					if (mode === 'firewall') {
						if (!msgLower.includes('banip/')) return false;
					} else if (mode === 'processing') {
						if (!msgLower.includes('banip-')) return false;
					} else {
						if (!msgLower.includes('banip')) return false;
					}
					if (kw && !msgLower.includes(kw)) return false;
					return true;
				})
				.map(entry => {
					const ts = entry.time < 1e12 ? entry.time * 1000 : entry.time;
					const d = new Date(ts);
					const pad = n => String(n).padStart(2, '0');
					const date = `${pad(d.getFullYear())}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
					const time = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
					return `[${date} ${time}] ${entry.msg}`;
				});

			countPill.textContent = String(filtered.length);
			logEl.value = filtered.length > 0
				? filtered.join('\n')
				: _('No related logs');

			if (autoScroll && wasAtBottom) {
				logEl.scrollTop = logEl.scrollHeight;
			}
		}

		const pollFn = () => {
			return callLogRead(1000, false, true).then(res => {
				lastRawLogs = res?.log ?? [];
				renderFiltered();
			});
		};

		this._pollFn = pollFn;
		poll.add(pollFn, 3);
		pollFn();

		return E('div', { 'class': 'cbi-map secbox-view' }, [
			E('h2', { 'name': 'content' }, [_('Logs')]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Real-time firewall block events and backend processing logs for the SecBox service.')
			]),
			E('div', { 'class': 'op-card' }, [
				E('div', { 'class': 'op-card-head-row', 'style': 'flex-wrap: wrap;' }, [
					E('div', { 'class': 'op-card-header' }, [
						_('Logs'),
						countPill
					]),
					E('div', { 'style': 'display: flex; align-items: center; gap: 8px; flex-wrap: wrap;' }, [
						filterSelect,
						searchInput,
						autoScrollBtn
					])
				]),
				E('div', { 'class': 'op-card-body', 'style': 'padding: 12px;' }, [
					E('textarea', {
						'id': 'logfile',
						'class': 'cbi-input-textarea',
						'style': 'width: 100% !important; box-sizing: border-box !important; height: calc(100vh - 320px); min-height: 460px; resize: none !important; display: block;',
						'readonly': 'readonly',
						'spellcheck': 'false',
						'wrap': 'off'
					})
				])
			])
		]);
	},

	unload: function () {
		if (this._pollFn) {
			poll.remove(this._pollFn);
			this._pollFn = null;
		}
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
