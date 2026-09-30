'use strict';
'require view';
'require fs';
'require request';
'require ui';
'require uci';
'require tools.meow_settings as settings';
'require tools.meow as meow';

function writeConfig(path, content) {
	var data = new FormData();
	data.append('sessionid', L.env.sessionid);
	data.append('filename', path);
	data.append('filedata', new Blob([ content ], { type: 'text/plain' }), 'config.yaml');
	return request.post(L.env.cgi_base + '/cgi-upload', data, { timeout: 0 }).then(function(res) {
		if (!res.ok) throw new Error(res.statusText || _('Upload request failed'));
		var reply = res.json();
		if (!reply || reply.failure) throw new Error((reply && reply.message) || _('Upload request failed'));
	});
}

return view.extend({
	load: function() {
		return uci.load('meow').then(function() {
			var path = uci.get('meow', 'main', 'config_file') || '/etc/meow/config.yaml';
			return fs.read_direct(path).then(function(content) { return { path: path, content: content }; });
		});
	},

	validate: function(content) {
		var token = Array.from(crypto.getRandomValues(new Uint32Array(4)), function(n) {
			return n.toString(16).padStart(8, '0');
		}).join('');
		var scratch = '/tmp/meow-luci-settings-' + token + '.yaml';
		return writeConfig(scratch, content).then(function() {
			return fs.exec('/usr/libexec/meow-validate', [token]);
		}).then(function(res) {
			if (res.code === 0) return null;
			return ((res.stdout || '') + (res.stderr || '')).replace(/\x1b\[[0-9;]*m/g, '').trim() ||
				_('Configuration test failed');
		}).finally(function() {
			return fs.remove(scratch).catch(function() {});
		});
	},

	handleValidate: function() {
		var content = document.getElementById('meow-yaml').value;
		return this.validate(content).then(function(err) {
			if (err) ui.addNotification(_('Invalid configuration'), E('pre', {}, err), 'error');
			else ui.addTimeLimitedNotification(null, E('p', _('Configuration test passed')), 3000, 'info');
		}).catch(function(e) {
			ui.addNotification(null, E('p', _('Unable to validate: %s').format(e.message)), 'error');
		});
	},

	handleSave: function(ev, path) {
		if (this.saving) return this.saving;
		var self = this;
		var textarea = document.getElementById('meow-yaml');
		var content = textarea.value.replace(/\r\n/g, '\n');
		if (!/\n$/.test(content)) content += '\n';
		return this.saving = this.validate(content).then(function(err) {
			if (err) {
				ui.addNotification(_('Invalid configuration, not saved'), E('pre', {}, err), 'error');
				return;
			}
			return writeConfig(path, content).then(function() {
				self.saved = content;
				self.updateStatus();
				return meow.serviceRunning().then(function(running) {
					if (!running) return;
					return fs.exec('/etc/init.d/meow', ['restart']);
				});
			}).then(function() {
				ui.addTimeLimitedNotification(null, E('p', _('Configuration saved.')), 3000, 'info');
			});
		}).catch(function(e) {
			ui.addNotification(null, E('p', _('Unable to save: %s').format(e.message)), 'error');
		}).finally(function() { self.saving = null; });
	},

	updateStatus: function(text) {
		if (text == null) {
			var ta = document.getElementById('meow-yaml');
			if (!ta) return;
			text = ta.value;
		}
		if (!this.status) return;
		this.dirty = text !== this.saved;
		this.status.textContent = _('%d lines · %s').format(text ? text.split('\n').length : 0, '%1024.1mB'.format(text.length));
		this.status.style.color = this.dirty ? '#ef6c00' : '#888';
		if (this.revert) this.revert.disabled = !this.dirty;
	},

	render: function(data) {
		var self = this;
		this.saved = data.content;
		this.status = E('span', { style: 'color:#888;' });
		this.revert = E('button', {
			type: 'button', class: 'cbi-button cbi-button-reset', disabled: true,
			click: function() { document.getElementById('meow-yaml').value = self.saved; self.updateStatus(); }
		}, _('Revert'));
		var node = E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('meow Configuration')),
			E('div', { class: 'cbi-map-descr' },
				_('Raw YAML configuration at %s. Validate before saving; invalid configuration is never written.').format(data.path)),
			E('div', { class: 'cbi-section' }, [
				E('textarea', {
					id: 'meow-yaml', class: 'cbi-input-textarea',
					style: 'width:100%; min-height:60vh; font-family:monospace; font-size:12px; tab-size:2;',
					spellcheck: false, wrap: 'off',
					input: function() { self.updateStatus(); },
					keydown: function(ev) {
						if (ev.key === 'Tab' && !ev.ctrlKey && !ev.metaKey && !ev.altKey) {
							ev.preventDefault();
							var ta = ev.target, start = ta.selectionStart;
							ta.value = ta.value.slice(0, start) + '  ' + ta.value.slice(ta.selectionEnd);
							ta.selectionStart = ta.selectionEnd = start + 2;
							self.updateStatus();
						} else if (ev.key === 's' && (ev.ctrlKey || ev.metaKey)) {
							ev.preventDefault(); self.handleSave(ev, data.path);
						}
					}
				}, [data.content]),
				E('div', { style: 'margin-top:.3em; font-size:12px;' }, [this.status])
			]),
			E('div', { class: 'cbi-page-actions' }, [
				this.revert, ' ',
				E('button', { type: 'button', class: 'cbi-button cbi-button-neutral', click: ui.createHandlerFn(this, 'handleValidate') }, _('Validate')),
				' ',
				E('button', { type: 'button', class: 'cbi-button cbi-button-save', click: ui.createHandlerFn(this, 'handleSave', null, data.path) }, _('Save'))
			])
		]);
		this.updateStatus(data.content);
		return node;
	}
});
