'use strict';
'require rpc';
'require view';
'require dom';
'require ui';

const callLogRead = rpc.declare({
	object: 'log',
	method: 'read',
	params: ['lines', 'stream', 'oneshot'],
	expect: {}
});

return L.Class.extend({
	Logview: function (logtag, title) {
		return L.view.extend({
			load: () => Promise.resolve(),

			render: function () {
				let autoScroll = true;

				const pollFn = () => {
					return callLogRead(1000, false, true).then(res => {
						const logEl = document.getElementById('logfile');
						if (!logEl) return;
						const filtered = (res?.log ?? [])
							.filter(entry => {
								if (!logtag) return true;
								if (entry.msg.includes(logtag)) return true;
								const cleanTag = logtag.replace(/[^a-zA-Z0-9]/g, '').toLowerCase();
								return entry.msg.toLowerCase().includes(cleanTag);
							})
							.map(entry => {
								const d = new Date(entry.time);
								const pad = n => String(n).padStart(2, '0');
								const date = `${pad(d.getFullYear())}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
								const time = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
								return `[${date} ${time}] ${entry.msg}`;
							});
						logEl.value = filtered.length > 0
							? filtered.join('\n')
							: _('No related logs');
						if (autoScroll) {
							logEl.scrollTop = logEl.scrollHeight;
						}
					});
				};

				this._pollFn = pollFn;
				L.Poll.add(pollFn, 3);

				const autoScrollBtn = E('button', {
					'class': 'btn cbi-button cbi-button-neutral',
					'style': 'margin-bottom: .6em;',
					'click': function () {
						autoScroll = !autoScroll;
						this.textContent = autoScroll ? _('Auto-scroll: ON') : _('Auto-scroll: OFF');
					}
				}, [_('Auto-scroll: ON')]);

				return E('div', { 'class': 'cbi-map' }, [
					E('h2', { 'name': 'content' }, [title]),
					E('div', { 'style': 'text-align: right;' }, [autoScrollBtn]),
					E('div', { 'class': 'cbi-section' }, [
						E('div', { 'class': 'cbi-section-node' }, [
							E('textarea', {
								'id': 'logfile',
								'class': 'cbi-input-textarea',
								'style': 'width: 100% !important; box-sizing: border-box !important; height: calc(100vh - 270px); min-height: 520px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size: 12.5px; line-height: 1.5; resize: none !important; display: block;',
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
					L.Poll.remove(this._pollFn);
					this._pollFn = null;
				}
			},

			handleSaveApply: null,
			handleSave: null,
			handleReset: null
		});
	}
});
