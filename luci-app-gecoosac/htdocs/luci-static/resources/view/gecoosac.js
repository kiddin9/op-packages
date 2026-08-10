'use strict';
'require form';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

const DEFAULT_UPLOAD_DIR = '/tmp/gecoosac/upload';
const DEFAULT_DB_DIR = '/etc/gecoosac';
const DEFAULT_CRT_FILE = '/etc/gecoosac/tls/gecoosac.crt';
const DEFAULT_KEY_FILE = '/etc/gecoosac/tls/gecoosac.key';
const DEFAULT_PID_DIR = '/var/run';
const DB_DIR_PREFIXES = [ '/etc/gecoosac', '/tmp/gecoosac', '/var/lib/gecoosac' ];
const PID_DIR_PREFIXES = [ '/var/run', '/tmp/gecoosac' ];
const CLEAR_STAGE_PATH_ERROR = _('Paths under .gecoosac-clear.* are reserved for upload cleanup.');

let statusPollRegistered = false;

const callServiceStatus = rpc.declare({
	object: 'luci.gecoosac',
	method: 'status',
	expect: { '': {} },
	reject: true
});

const callClearUpload = rpc.declare({
	object: 'luci.gecoosac',
	method: 'clear_upload',
	expect: { '': {} }
});

const callPathPolicy = rpc.declare({
	object: 'luci.gecoosac',
	method: 'path_policy',
	expect: { '': {} },
	reject: true
});

const RPC_ERROR_MESSAGES = {
	'Unable to query service status': _('Unable to query service status'),
	'Invalid service status response': _('Invalid service status response'),
	'Expecting an absolute path': _('Expecting an absolute path'),
	'Only Gecoos upload directories can be cleared': _('Only Gecoos upload directories can be cleared'),
	'Upload directory contains a mount point': _('Upload directory contains a mount point'),
	'Upload directory or its parent is not root-owned and private': _('Upload directory or its parent is not root-owned and private'),
	'Unable to resolve upload directory': _('Unable to resolve upload directory'),
	'Unable to read Gecoos configuration': _('Unable to read Gecoos configuration'),
	'Gecoos configuration changed during cleanup': _('Gecoos configuration changed during cleanup'),
	'Unable to prepare upload directory cleanup': _('Unable to prepare upload directory cleanup'),
	'Unable to validate upload cleanup stage': _('Unable to validate upload cleanup stage'),
	'Upload cleanup stage contains a configured protected path': _('Upload cleanup stage contains a configured protected path'),
	'Unable to validate configured paths': _('Unable to validate configured paths'),
	'Upload directory contains a configured protected path': _('Upload directory contains a configured protected path'),
	'Unable to recreate upload directory': _('Unable to recreate upload directory'),
	'Unable to remove upload directory contents': _('Unable to remove upload directory contents'),
	'Unable to remove upload cleanup stage': _('Unable to remove upload cleanup stage'),
	'Unable to resolve managed path policy': _('Unable to resolve managed path policy')
};

function validPort(value, defaultValue) {
	const port = Number(value || defaultValue);
	return Number.isInteger(port) && port >= 1 && port <= 65535 ? String(port) : defaultValue;
}

function validPortValue(value) {
	const text = String(value || '');
	const port = Number(text);

	return /^[0-9]+$/.test(text) && Number.isSafeInteger(port) && port >= 1 && port <= 65535;
}


function validatePortValue(section_id, value, otherOption, singlePortOption, activeInSinglePort) {
	const singlePort = singlePortOption.formvalue(section_id);

	if (!activeInSinglePort && singlePort !== '0')
		return true;

	if (!validPortValue(value))
		return _('Port must be an integer between 1 and 65535.');

	const otherValue = otherOption.formvalue(section_id);

	if (singlePort === '0' && validPortValue(otherValue) && Number(value) === Number(otherValue))
		return _('Interface port and management port must be different.');

	return true;
}

function validateCertificatePath(section_id, value, singlePortOption, httpsOption) {
	if (singlePortOption.formvalue(section_id) !== '0' || httpsOption.formvalue(section_id) !== '1' || !value)
		return true;

	if (String(value).charAt(0) !== '/')
		return _('Expecting an absolute path');

	return usesClearStagePath(value)
		? CLEAR_STAGE_PATH_ERROR
		: true;
}

function triggerActiveValidation(section_id, options) {
	for (const option of options) {
		if (!option.isActive(section_id))
			continue;

		const element = option.getUIElement(section_id);

		if (element)
			element.triggerValidation();
	}
}

function normalizePath(value) {
	const path = String(value || '');

	if (path.charAt(0) !== '/')
		return null;

	const parts = [];
	const segments = path.split('/');

	for (let i = 0; i < segments.length; i++) {
		const segment = segments[i];

		if (!segment || segment === '.')
			continue;

		if (segment === '..') {
			if (parts.length > 0)
				parts.pop();
			continue;
		}

		parts.push(segment);
	}

	return '/' + parts.join('/');
}

function usesClearStagePath(value) {
	const path = normalizePath(value);
	const segments = path === null ? [] : path.split('/');

	for (const segment of segments)
		if (segment.indexOf('.gecoosac-clear.') === 0)
			return true;

	return false;
}

function managedPath(value, policy) {
	const path = normalizePath(value);

	if (path === null)
		return null;

	if (path === '/var/run' || path.indexOf('/var/run/') === 0) {
		if (!policy || policy.ok !== true || policy.var_run_root !== '/tmp/run')
			return null;

		return policy.var_run_root + path.substring('/var/run'.length);
	}

	if (path === '/var' || path.indexOf('/var/') === 0) {
		if (!policy || policy.ok !== true || (policy.var_root !== '/var' && policy.var_root !== '/tmp'))
			return null;

		return policy.var_root + path.substring('/var'.length);
	}

	return path;
}

function usesManagedPath(value) {
	const path = normalizePath(value);

	return path === '/var' || path === '/var/run' ||
		(path !== null && (path.indexOf('/var/') === 0 || path.indexOf('/var/run/') === 0));
}

function uploadStorageRoot(path) {
	if (path === DEFAULT_UPLOAD_DIR)
		return '/tmp';

	const segments = path === null ? [] : path.split('/');

	if (segments.length === 5 && segments[1] === 'mnt' && segments[2] &&
		segments[3] === 'gecoosac' && segments[4] === 'upload')
		return '/mnt/' + segments[2];

	return null;
}

function validUploadDir(value, policy) {
	const path = normalizePath(value);
	const physical = managedPath(value, policy);
	const storageRoot = uploadStorageRoot(path);
	const physicalStorageRoot = uploadStorageRoot(physical);

	return !usesClearStagePath(value) && storageRoot !== null && storageRoot === physicalStorageRoot;
}

function validPathPrefix(value, prefixes) {
	const path = normalizePath(value);

	if (path === null)
		return false;

	for (let i = 0; i < prefixes.length; i++)
		if (path === prefixes[i] || path.indexOf(prefixes[i] + '/') === 0)
			return true;

	return false;
}

function pathInDir(value, dir) {
	const path = normalizePath(value);
	const root = normalizePath(dir);

	return path !== null && root !== null && root !== '/' && (path === root || path.indexOf(root + '/') === 0);
}

function validDbDir(value, uploadDir, policy) {
	const upload = uploadDir || DEFAULT_UPLOAD_DIR;
	const physical = managedPath(value, policy);
	const physicalUpload = managedPath(upload, policy);

	return validPathPrefix(value, DB_DIR_PREFIXES) && physical !== null && physicalUpload !== null &&
		!pathInDir(value, upload) && !pathInDir(physical, physicalUpload);
}

function validPidDir(value, uploadDir, policy) {
	const upload = uploadDir || DEFAULT_UPLOAD_DIR;
	const physical = managedPath(value, policy);
	const physicalUpload = managedPath(upload, policy);

	return validPathPrefix(value, PID_DIR_PREFIXES) && physical !== null && physicalUpload !== null &&
		!pathInDir(value, upload) && !pathInDir(physical, physicalUpload);
}

function serviceRunning(status) {
	const service = status && status.gecoosac;
	const instances = service && service.instances;

	if (status && status.ok === false)
		return false;

	if (status && status.running === true)
		return true;

	if (!instances)
		return false;

	for (const name in instances)
		if (instances[name] && instances[name].running)
			return true;

	return false;
}

function statusFailure() {
	return {
		ok: false,
		error: _('Unable to query service status')
	};
}

function clientHost() {
	let host = window.location.hostname;

	if (host.indexOf(':') !== -1 && host.charAt(0) !== '[')
		host = '[' + host + ']';

	return host;
}

function clientUrl(status) {
	const protocol = status && status.protocol;
	const port = validPort(status && status.port, null);

	if ((protocol === 'http' || protocol === 'https') && port !== null)
		return protocol + '://' + clientHost() + ':' + port;

	return null;
}

function renderStatusContent(status) {
	if (status && status.error)
		return E('p', { 'class': 'gecoosac-stopped' }, _('Service status unavailable') + ': ' +
			(RPC_ERROR_MESSAGES[status.error] || _('Unable to query service status')));

	const running = serviceRunning(status);
	const url = running ? clientUrl(status) : null;
	const text = running
		? _('The GecoosAC service is running.')
		: _('The GecoosAC service is not running.');
	const state = E('span', { 'class': running ? 'gecoosac-running' : 'gecoosac-stopped' }, text);

	if (!running || !url)
		return E('p', {}, state);

	return E('p', {}, [
		state,
		E('button', {
			'class': 'cbi-button cbi-button-reload',
			'click': function() {
				const client = window.open(url, '_blank', 'noopener');
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
	return res && res.error && RPC_ERROR_MESSAGES[res.error]
		? RPC_ERROR_MESSAGES[res.error]
		: _('Upload directory was not cleared');
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('gecoosac'),
			callServiceStatus().catch(function() {
				return statusFailure();
			}),
			callPathPolicy().catch(function() {
				return { ok: false };
			})
		]);
	},

	render(data) {
		let m, s, o, uploadDirOption;
		let portOption, managementPortOption, singlePortOption;
		let httpsOption, certificateOption, keyOption;
		const pathPolicy = data[2] && data[2].ok === true ? data[2] : null;

		m = new form.Map('gecoosac', _('Gecoos AC'),
			_('Only supports Gecoos AP firmware 7.6 and above.') + '<br />' +
				_('Default login password: "admin". Change it immediately after first login.'));

		s = m.section(form.TypedSection, 'gecoosac');
		s.anonymous = true;
		s.render = function() {
			if (!statusPollRegistered) {
				poll.add(function() {
					return callServiceStatus().then(updateStatus).catch(function() {
						updateStatus(statusFailure());
					});
				}, 3);
				statusPollRegistered = true;
			}

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

		portOption = s.option(form.Value, 'port', _('Set interface port'));
		o = portOption;
		o.placeholder = '60650';
		o.default = '60650';
		o.datatype = 'port';
		o.rmempty = false;

		singlePortOption = s.option(form.Flag, 'isonlyoneprot', _('Single Port Mode'),
			_('Do not enable the independent management port, only use one port for management.'));
		o = singlePortOption;
		o.default = '1';
		o.rmempty = false;

		managementPortOption = s.option(form.Value, 'm_port', _('Set management port'));
		o = managementPortOption;
		o.placeholder = '8080';
		o.default = '8080';
		o.datatype = 'port';
		o.depends('isonlyoneprot', '0');

		portOption.validate = function(section_id, value) {
			return validatePortValue(section_id, value, managementPortOption, singlePortOption, true);
		};
		managementPortOption.validate = function(section_id, value) {
			return validatePortValue(section_id, value, portOption, singlePortOption, false);
		};
		singlePortOption.validate = function(section_id, value) {
			if (value === '0') {
				const port = portOption.formvalue(section_id);
				const managementPort = managementPortOption.formvalue(section_id);

				if (validPortValue(port) && validPortValue(managementPort) && Number(port) === Number(managementPort))
					return _('Interface port and management port must be different.');
			}

			return true;
		};
		httpsOption = s.option(form.Flag, 'https', _('Enable HTTPS service'),
			_('Default certificate files are generated when HTTPS starts; custom paths must point to a readable certificate and matching key.'));
		o = httpsOption;
		o.default = '0';
		o.depends('isonlyoneprot', '0');

		certificateOption = s.option(form.Value, 'crt_file', _('Specify crt certificate file'));
		o = certificateOption;
		o.placeholder = DEFAULT_CRT_FILE;
		o.default = DEFAULT_CRT_FILE;
		o.datatype = 'file';
		o.depends({ isonlyoneprot: '0', https: '1' });
		o.validate = function(section_id, value) {
			return validateCertificatePath(section_id, value, singlePortOption, httpsOption);
		};

		keyOption = s.option(form.Value, 'key_file', _('Specify key certificate file'));
		o = keyOption;
		o.placeholder = DEFAULT_KEY_FILE;
		o.default = DEFAULT_KEY_FILE;
		o.datatype = 'file';
		o.depends({ isonlyoneprot: '0', https: '1' });
		o.validate = function(section_id, value) {
			return validateCertificatePath(section_id, value, singlePortOption, httpsOption);
		};

		const revalidateProtocolOptions = function(_event, section_id) {
			triggerActiveValidation(section_id, [
				portOption,
				managementPortOption,
				singlePortOption,
				httpsOption,
				certificateOption,
				keyOption
			]);
		};
		portOption.onchange = revalidateProtocolOptions;
		managementPortOption.onchange = revalidateProtocolOptions;
		singlePortOption.onchange = revalidateProtocolOptions;
		httpsOption.onchange = revalidateProtocolOptions;

		o = s.option(form.Value, 'upload_dir', _('Upload dir path'),
			_('Upload AP upgrade firmware here. Use /tmp/gecoosac/upload or /mnt/storage-name/gecoosac/upload. The /mnt/storage-name directory must already exist and be root-owned and private.'));
		uploadDirOption = o;
		o.placeholder = DEFAULT_UPLOAD_DIR;
		o.default = DEFAULT_UPLOAD_DIR;
		o.datatype = 'directory';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (usesManagedPath(value) && !pathPolicy)
				return _('Unable to validate /var paths on this system.');
			if (usesClearStagePath(value))
				return CLEAR_STAGE_PATH_ERROR;

			return validUploadDir(value, pathPolicy)
				? true
				: _('Upload directory must be /tmp/gecoosac/upload or /mnt/storage-name/gecoosac/upload.');
		};

		o = s.option(form.Value, 'db_dir', _('Database dir path'),
			_('Store the config database under /etc/gecoosac, /tmp/gecoosac, or /var/lib/gecoosac. Do not place it inside the upload directory.'));
		o.placeholder = DEFAULT_DB_DIR;
		o.default = DEFAULT_DB_DIR;
		o.datatype = 'directory';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			const uploadDir = uploadDirOption.formvalue(section_id) || DEFAULT_UPLOAD_DIR;
			if ((usesManagedPath(value) || usesManagedPath(uploadDir)) && !pathPolicy)
				return _('Unable to validate /var paths on this system.');
			if (usesClearStagePath(value))
				return CLEAR_STAGE_PATH_ERROR;

			if (!validPathPrefix(value, DB_DIR_PREFIXES))
				return _('Database directory must be under /etc/gecoosac, /tmp/gecoosac, or /var/lib/gecoosac.');

			return validDbDir(value, uploadDir, pathPolicy)
				? true
				: _('Database directory must not be the upload directory or inside it.');
		};

		o = s.option(form.Value, 'piddir', _('PID dir path'),
			_('Store the AC program pid file under /var/run or /tmp/gecoosac. Do not place it inside the upload directory.'));
		o.placeholder = DEFAULT_PID_DIR;
		o.default = DEFAULT_PID_DIR;
		o.datatype = 'directory';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			const uploadDir = uploadDirOption.formvalue(section_id) || DEFAULT_UPLOAD_DIR;
			if ((usesManagedPath(value) || usesManagedPath(uploadDir)) && !pathPolicy)
				return _('Unable to validate /var paths on this system.');
			if (usesClearStagePath(value))
				return CLEAR_STAGE_PATH_ERROR;

			if (!validPathPrefix(value, PID_DIR_PREFIXES))
				return _('PID directory must be under /var/run or /tmp/gecoosac.');

			return validPidDir(value, uploadDir, pathPolicy)
				? true
				: _('PID directory must not be the upload directory or inside it.');
		};

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
			_('Only files under the saved Gecoos upload directory will be removed. Save and Apply before clearing a newly edited path.'));
		o.inputstyle = 'remove';
		o.inputtitle = _('Clear');
		o.onclick = function() {
			if (!confirm(_('Really clear the saved upload directory?')))
				return Promise.resolve();

			return callClearUpload().then(function() {
				if (arguments[0] && arguments[0].result === true)
					ui.addNotification(null, E('p', {}, _('Saved upload directory cleared')));
				else
					ui.addNotification(null, E('p', {}, clearUploadError(arguments[0])), 'danger');
			}).catch(function() {
				ui.addNotification(null, E('p', {}, _('Upload directory was not cleared')), 'danger');
			});
		};

		return m.render();
	}
});
