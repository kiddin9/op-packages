'use strict';
'require form';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

const DEFAULT_UPLOAD_DIR = '/tmp/gecoosac/upload/';
const DEFAULT_DB_DIR = '/etc/gecoosac/';
const DEFAULT_CRT_FILE = '/etc/gecoosac/tls/gecoosac.crt';
const DEFAULT_KEY_FILE = '/etc/gecoosac/tls/gecoosac.key';
const DEFAULT_PID_DIR = '/var/run/';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { '': {} }
});

const callClearUpload = rpc.declare({
	object: 'luci.gecoosac',
	method: 'clear_upload',
	expect: { '': {} }
});

function validPort(value, defaultValue) {
	const port = Number(value || defaultValue);
	return Number.isInteger(port) && port >= 1 && port <= 65535 ? String(port) : defaultValue;
}

function stripTrailingSlashes(value) {
	let path = String(value || '');

	while (path.length > 1 && path.endsWith('/'))
		path = path.slice(0, -1);

	return path;
}

function validUploadDir(value) {
	const path = stripTrailingSlashes(value);

	return path.charAt(0) === '/' && path.endsWith('/gecoosac/upload');
}

function serviceRunning(status) {
	const service = status && status.gecoosac;
	const instances = service && service.instances;

	if (!instances)
		return false;

	for (const name in instances)
		if (instances[name] && instances[name].running)
			return true;

	return false;
}

function clientHost() {
	let host = window.location.hostname;

	if (host.indexOf(':') !== -1 && host.charAt(0) !== '[')
		host = '[' + host + ']';

	return host;
}

function clientUrl() {
	const singlePort = uci.get('gecoosac', 'config', 'isonlyoneprot') !== '0';
	const https = uci.get('gecoosac', 'config', 'https') === '1';
	const port = singlePort
		? validPort(uci.get('gecoosac', 'config', 'port'), '60650')
		: validPort(uci.get('gecoosac', 'config', 'm_port'), '8080');

	return (singlePort || !https ? 'http://' : 'https://') + clientHost() + ':' + port;
}

function renderStatusContent(status) {
	const running = serviceRunning(status);
	const text = running
		? _('The GecoosAC service is running.')
		: _('The GecoosAC service is not running.');
	const state = E('span', { 'class': running ? 'gecoosac-running' : 'gecoosac-stopped' }, text);

	if (!running)
		return E('p', {}, state);

	return E('p', {}, [
		state,
		E('button', {
			'class': 'cbi-button cbi-button-reload',
			'click': function() {
				const client = window.open(clientUrl(), '_blank', 'noopener');
				if (client)
					client.opener = null;
			}
		}, _('Open the mgmt page'))
	]);
}

function updateStatus(status) {
	const node = document.getElementById('gecoosac_status');

	if (!node)
		return;

	while (node.firstChild)
		node.removeChild(node.firstChild);

	node.appendChild(renderStatusContent(status));
}

function clearUploadError(res) {
	return res && res.error ? _(res.error) : _('Upload directory was not cleared');
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('gecoosac'),
			L.resolveDefault(callServiceList('gecoosac'), {})
		]);
	},

	render(data) {
		let m, s, o;

		m = new form.Map('gecoosac', _('Gecoos AC'),
			_('Batch management Gecoos AP, Default password: admin') + '<br />' +
			_('The current AC version %s, only supports AP 7.6 and above.').format('2.2'));

		s = m.section(form.TypedSection, 'gecoosac');
		s.anonymous = true;
		s.render = function() {
			poll.add(function() {
				return L.resolveDefault(callServiceList('gecoosac'), {}).then(updateStatus);
			}, 3);

			return E('fieldset', { 'class': 'cbi-section' }, [
				E('style', {}, [
					'#gecoosac_status .gecoosac-running{color:green}',
					'#gecoosac_status .gecoosac-stopped{color:red}',
					'#gecoosac_status .cbi-button{margin-left:1em}'
				].join('\n')),
				E('div', { 'id': 'gecoosac_status' }, renderStatusContent(data[1]))
			]);
		};

		s = m.section(form.TypedSection, 'gecoosac', _('Global Settings'));
		s.addremove = false;
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enabled AC'));
		o.rmempty = false;

		o = s.option(form.Value, 'port', _('Set interface port'));
		o.placeholder = '60650';
		o.default = '60650';
		o.datatype = 'port';
		o.rmempty = false;

		o = s.option(form.Flag, 'isonlyoneprot', _('Single Port Mode'),
			_('Do not enable the independent management port, only use one port for management.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'm_port', _('Set management port'));
		o.placeholder = '8080';
		o.default = '8080';
		o.datatype = 'port';
		o.depends('isonlyoneprot', '0');

		o = s.option(form.Flag, 'https', _('Enable HTTPS service'),
			_('Default certificate files are generated when HTTPS starts; custom paths must point to readable files.'));
		o.default = '0';
		o.depends('isonlyoneprot', '0');

		o = s.option(form.Value, 'crt_file', _('Specify crt certificate file'));
		o.placeholder = DEFAULT_CRT_FILE;
		o.default = DEFAULT_CRT_FILE;
		o.datatype = 'file';
		o.depends({ isonlyoneprot: '0', https: '1' });

		o = s.option(form.Value, 'key_file', _('Specify key certificate file'));
		o.placeholder = DEFAULT_KEY_FILE;
		o.default = DEFAULT_KEY_FILE;
		o.datatype = 'file';
		o.depends({ isonlyoneprot: '0', https: '1' });

		o = s.option(form.Value, 'upload_dir', _('Upload dir path'),
			_('Upload AP upgrade firmware here. For safe cleanup, use an absolute path ending with /gecoosac/upload, for example /tmp/gecoosac/upload/.'));
		o.placeholder = DEFAULT_UPLOAD_DIR;
		o.default = DEFAULT_UPLOAD_DIR;
		o.datatype = 'directory';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			return validUploadDir(value)
				? true
				: _('Upload directory must be an absolute path ending with /gecoosac/upload.');
		};

		o = s.option(form.Value, 'db_dir', _('Database dir path'), _('The path to store the config database'));
		o.placeholder = DEFAULT_DB_DIR;
		o.default = DEFAULT_DB_DIR;
		o.datatype = 'directory';
		o.rmempty = false;

		o = s.option(form.Value, 'piddir', _('PID dir path'), _('The path to store the AC program pid file'));
		o.placeholder = DEFAULT_PID_DIR;
		o.default = DEFAULT_PID_DIR;
		o.datatype = 'directory';
		o.rmempty = false;

		o = s.option(form.ListValue, 'lang', _('Language'));
		o.value('zh', _('Chinese'));
		o.value('en', _('English'));
		o.default = 'zh';
		o.rmempty = false;

		o = s.option(form.Flag, 'debug', _('Debug Mode'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Flag, 'showtip', _('Show IP Tip'),
			_('Show the IP 6.7.8.9 setup tip when it is not configured.'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Flag, 'log', _('Enable Log'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Button, '_clear_upload', _('Clear Upload Directory'),
			_('Only files under the configured Gecoos upload directory will be removed.'));
		o.inputstyle = 'remove';
		o.inputtitle = _('Clear');
		o.onclick = function() {
			if (!confirm(_('Really clear the configured upload directory?')))
				return Promise.resolve();

			return callClearUpload().then(function(res) {
				if (res && res.result === true)
					ui.addNotification(null, E('p', {}, _('Upload directory cleared')));
				else
					ui.addNotification(null, E('p', {}, clearUploadError(res)), 'danger');
			});
		};

		return m.render();
	}
});
