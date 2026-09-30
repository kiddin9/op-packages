'use strict';
'require baseclass';
'require fs';
'require request';
'require uci';

function write(path, content) {
	var data = new FormData();
	data.append('sessionid', L.env.sessionid);
	data.append('filename', path);
	data.append('filedata', new Blob([content], { type: 'text/plain' }), 'config.yaml');
	return request.post(L.env.cgi_base + '/cgi-upload', data, { timeout: 0 }).then(function(res) {
		if (!res.ok)
			throw new Error(res.statusText || _('Upload request failed'));
		var reply = res.json();
		if (!reply || reply.failure)
			throw new Error((reply && reply.message) || _('Upload request failed'));
	});
}

function validate(content) {
	var token = Array.from(crypto.getRandomValues(new Uint32Array(4)), function(n) {
		return n.toString(16).padStart(8, '0');
	}).join('');
	var scratch = '/tmp/meow-luci-settings-' + token + '.yaml';
	return write(scratch, content).then(function() {
		return fs.exec('/usr/libexec/meow-validate', [token]);
	}).then(function(res) {
		if (res.code !== 0)
			throw new Error(((res.stdout || '') + (res.stderr || '')).replace(/\x1b\[[0-9;]*m/g, '').trim() ||
				_('Configuration test failed'));
	}).finally(function() {
		return fs.remove(scratch).catch(function() {});
	});
}

return baseclass.extend({
	transform: function(content) { return content; },
	prepare: function(content) { return content; },
	save: function() {
		var path = uci.get('meow', 'main', 'config_file') || '/etc/meow/config.yaml';
		if (path !== '/etc/meow/config.yaml')
			return Promise.reject(new Error(_('LuCI edits require /etc/meow/config.yaml.')));
		var self = this;
		var original;
		return fs.read_direct(path).then(function(content) {
			original = content;
			return validate(content);
		}).then(function() {
			return function() {
				return fs.read_direct(path).then(function(current) {
					if (current !== original)
						throw new Error(_('Cannot restore YAML: configuration changed by another session.'));
				});
			};
		});
	}
});
