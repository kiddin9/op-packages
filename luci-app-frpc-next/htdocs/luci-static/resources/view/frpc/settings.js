'use strict';
'require view';
'require rpc';
'require ui';

const callGetConfig = rpc.declare({
	object: 'luci.frpc',
	method: 'get_config'
});

const callSaveConfig = rpc.declare({
	object: 'luci.frpc',
	method: 'save_config',
	params: [ 'config' ]
});

const callValidateConfig = rpc.declare({
	object: 'luci.frpc',
	method: 'validate_config',
	params: [ 'config' ]
});

const callStatus = rpc.declare({
	object: 'luci.frpc',
	method: 'get_status'
});

const callSetEnabled = rpc.declare({
	object: 'luci.frpc',
	method: 'set_enabled',
	params: [ 'enabled' ]
});

const callServiceAction = rpc.declare({
	object: 'luci.frpc',
	method: 'service_action',
	params: [ 'action' ]
});

function parseErrorPosition(errText) {
	const s = String(errText || '');
	let m = s.match(/line\s+(\d+)\s*[,;:]?\s*(?:col|column)\s+(\d+)/i);
	if (m)
		return { line: +m[1], col: +m[2] };

	m = s.match(/at\s+line\s+(\d+)\s*[,;:]?\s*column\s+(\d+)/i);
	if (m)
		return { line: +m[1], col: +m[2] };

	m = s.match(/line\s+(\d+)/i);
	if (m)
		return { line: +m[1], col: null };

	return null;
}

return view.extend({
	_validateTimer: null,
	_errorLine: null,

	injectStyle: function() {
		if (document.getElementById('frpc_editor_style'))
			return;

		const css = [
			'.frpc-editor-wrap{border:1px solid #ccc;border-radius:4px;overflow:hidden;background:#fff;max-width:900px;box-sizing:border-box;}',
			'.frpc-editor-main{display:flex;min-height:400px;max-height:65vh;}',
			'.frpc-editor-gutter{width:48px;background:#f7f7f7;color:#888;border-right:1px solid #e5e5e5;overflow:hidden;font:13px/1.5 monospace;padding:12px 6px;text-align:right;user-select:none;box-sizing:border-box;}',
			'.frpc-editor-gutter-line{height:1.5em;line-height:1.5;}',
			'.frpc-editor-gutter-line.err{background:#ffe8e8;color:#b00020;font-weight:700;}',
			'.frpc-editor-input-wrap{flex:1;background:#fff;position:relative;}',
			'.frpc-editor-input{width:100%;min-height:100%;box-sizing:border-box;border:0;outline:none;resize:vertical;overflow-wrap:anywhere;white-space:pre;word-break:keep-all;font:13px/1.5 monospace;padding:12px;margin:0;display:block;}'
		].join('\n');

		document.head.appendChild(E('style', { id: 'frpc_editor_style' }, css));
	},

	refreshEditor: function() {
		const ta = document.getElementById('frpc_config');
		const gutter = document.getElementById('frpc_editor_gutter');
		if (!ta || !gutter)
			return;

		const text = ta.value || '';
		const lineCount = Math.max(1, text.split('\n').length);
		gutter.innerHTML = '';
		for (let i = 1; i <= lineCount; i++) {
			gutter.appendChild(E('div', {
				'class': 'frpc-editor-gutter-line' + (this._errorLine === i ? ' err' : '')
			}, String(i)));
		}
	},

	renderEditor: function(configText) {
		const gutter = E('div', { id: 'frpc_editor_gutter', 'class': 'frpc-editor-gutter' });
		const ta = E('textarea', {
			id: 'frpc_config',
			class: 'frpc-editor-input',
			spellcheck: 'false',
			wrap: 'off'
		}, configText || '');

		ta.addEventListener('keydown', function(ev) {
			if (ev.keyCode === 9) { // Tab key
				ev.preventDefault();
				const start = this.selectionStart;
				const end = this.selectionEnd;
				const val = this.value;
				this.value = val.substring(0, start) + '  ' + val.substring(end);
				this.selectionStart = this.selectionEnd = start + 2;
			}
		});

		ta.addEventListener('input', L.bind(function() {
			this.refreshEditor();
			this.scheduleValidate();
		}, this));

		ta.addEventListener('scroll', function() {
			gutter.scrollTop = ta.scrollTop;
		});

		window.setTimeout(L.bind(function() { this.refreshEditor(); }, this), 0);

		const inputWrap = E('div', { 'class': 'frpc-editor-input-wrap' }, [ ta ]);

		return E('div', { 'class': 'frpc-editor-wrap' }, [
			E('div', { 'class': 'frpc-editor-main' }, [ gutter, inputWrap ])
		]);
	},

	setValidateHint: function(ok, message, pos) {
		const hint = document.getElementById('frpc_validate_hint');
		if (!hint)
			return;

		hint.style.color = ok ? 'green' : 'red';
		hint.textContent = message;
		this._errorLine = (!ok && pos && pos.line) ? pos.line : null;
		this.refreshEditor();
	},

	runValidate: function() {
		const content = document.getElementById('frpc_config')?.value || '';
		if (!content.trim()) {
			this.setValidateHint(true, _('Configuration is empty.'));
			return Promise.resolve();
		}

		return callValidateConfig(content).then(L.bind(function(res) {
			if (res && res.success) {
				this.setValidateHint(true, _('Configuration is valid.'));
				return;
			}

			const err = (res && res.error) ? String(res.error).trim() : _('Unknown error');
			const pos = parseErrorPosition(err);
			let msg = _('Verification failed: ') + err;
			if (pos && pos.line)
				msg += ' (' + _('Line') + ' ' + pos.line + (pos.col ? ', ' + _('Column') + ' ' + pos.col : '') + ')';
			this.setValidateHint(false, msg, pos);
		}, this));
	},

	scheduleValidate: function() {
		if (this._validateTimer)
			window.clearTimeout(this._validateTimer);

		this._validateTimer = window.setTimeout(L.bind(function() {
			this.runValidate().catch(function() {});
		}, this), 700);
	},

	load: function() {
		return Promise.all([ callGetConfig(), callStatus() ]);
	},

	render: function(data) {
		this.injectStyle();
		const cfg = data && data[0] ? data[0] : {};
		const st = data && data[1] ? data[1] : {};
		const configText = cfg.config || '';
		const enabled = (st.enabled === 1 || st.enabled === true);

		window.setTimeout(L.bind(function() {
			this.runValidate().catch(function() {});
		}, this), 0);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Frp Client Title') + ' - ' + _('Settings')),
			E('div', { 'class': 'cbi-map-descr' }, _('Configure the Frp client parameters. Complete the server link details and local port forwarding rules to build an intranet penetration channel.')),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'class': 'cbi-section-title' }, _('Service Control')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Enabled')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('input', {
							id: 'frpc_enabled',
							type: 'checkbox',
							checked: enabled ? 'checked' : null
						})
					])
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'class': 'cbi-section-title' }, _('Configuration Editor')),
				this.renderEditor(configText)
			]),
			E('div', { 'class': 'cbi-section frpc-editor-buttons' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					click: ui.createHandlerFn(this, function() {
						return this.runValidate();
					})
				}, _('Verify Configuration')),
				E('span', { id: 'frpc_validate_hint', style: 'margin-left:12px;' }, '')
			])
		]);
	},

	validateAndSave: function() {
		const configText = document.getElementById('frpc_config')?.value || '';
		const enabledCheckbox = document.getElementById('frpc_enabled');
		const on = enabledCheckbox && enabledCheckbox.checked ? 1 : 0;

		ui.showModal(null, [ E('p', { 'class': 'spinning' }, [ _('Applying changes...') ]) ]);

		return callValidateConfig(configText).then(L.bind(function(res) {
			if (!res || !res.success) {
				ui.hideModal();
				const err = (res && res.error) ? String(res.error).trim() : _('Unknown error');
				this.setValidateHint(false, _('Verification failed: ') + err, parseErrorPosition(err));
				ui.addNotification(null, E('pre', { style: 'white-space:pre-wrap; margin:0;' }, _('frpc config verify failed:\n') + err), 'danger');
				throw new Error('frpc verify failed');
			}

			this.setValidateHint(true, _('Configuration is valid.'));

			return callSetEnabled(on).then(L.bind(function(setRes) {
				if (!setRes || !setRes.success) {
					ui.hideModal();
					ui.addNotification(null, E('p', _('Failed to update service enable state.')), 'danger');
					throw new Error('frpc set enabled failed');
				}

				return callSaveConfig(configText).then(L.bind(function(saveRes) {
					ui.hideModal();
					if (saveRes && saveRes.success) {
						if (on === 0) {
							return callServiceAction('stop');
						} else {
							if (saveRes.applied === false) {
								ui.addNotification(null, E('p', _('Configuration saved, but service is not running or reload failed. Please force restart service.')), 'warning');
							}
						}
						return;
					}

					ui.addNotification(null, E('p', _('Configuration save failed: ') + (saveRes && saveRes.error ? saveRes.error : _('Unknown error'))), 'danger');
					throw new Error('frpc config save failed');
				}, this));
			}, this));
		}, this)).catch(function(err) {
			ui.hideModal();
			throw err;
		});
	},

	handleSave: function() {
		return this.validateAndSave();
	},

	handleSaveApply: function() {
		return this.validateAndSave();
	}
});
