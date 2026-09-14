'use strict';
'require dom';
'require form';
'require fs';
'require poll';
'require rpc';
'require uci';
'require ui';
'require view';

const HELPER = '/usr/libexec/openlist2-helper';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

const getServiceStatus = () => {
	return L.resolveDefault(callServiceList('openlist2'), {}).then(res => {
		let isRunning = false;
		try {
			isRunning = res['openlist2']['instances']['openlist2']['running'];
		} catch (e) { }
		return isRunning;
	});
};

const getWebInterfaceUrl = (protocol, webport, site_url) => {
	const configuredUrl = (site_url || '').trim();
	if (configuredUrl) {
		try {
			const url = new URL(configuredUrl);
			if (url.protocol === 'http:' || url.protocol === 'https:')
				return url.href;
		} catch (e) { }
	}
	return webport ? protocol + '//' + window.location.hostname + ':' + webport + '/' : null;
};

const renderStatus = (isRunning, protocol, webport, site_url) => {
	const status = E('em', {}, E('span', { 'style': `color:${isRunning ? 'green' : 'red'}` },
		E('strong', {}, ['OpenList ', isRunning ? _('RUNNING') : _('NOT RUNNING')])));

	if (isRunning && (webport || site_url)) {
		const buttonUrl = getWebInterfaceUrl(protocol, webport, site_url);
		if (!buttonUrl)
			return status;
		const button = E('input', {
			'class': 'cbi-button-reload',
			'type': 'button',
			'style': 'margin-left: 50px',
			'value': _('Open Web Interface')
		});
		button.addEventListener('click', () => window.open(buttonUrl, '_blank', 'noopener'));

		return E('span', {}, [status, button]);
	}

	return status;
};

const isSafeLogPath = value => !/[\r\n]/.test(value || '') &&
	/^\/var\/log\/openlist2(?:[._-][A-Za-z0-9._-]+)?$/.test(value || '');

const isEnabledPort = value => /^\d+$/.test(String(value || '').trim()) && Number(value) >= 1 && Number(value) <= 65535;

const getListenPortValue = (section_id, option, fallback) => {
	const value = uci.get('openlist2', section_id, option);
	if (value != null && String(value).trim() !== '')
		return value;
	const legacyPort = uci.get('openlist2', section_id, 'port');
	const legacySsl = uci.get('openlist2', section_id, 'ssl');
	if (legacyPort != null || legacySsl != null) {
		const tls = ['1', 'true', 'on', 'yes', 'enabled'].includes(legacySsl);
		return option === 'listen_https_port'
			? (tls ? legacyPort || '5244' : '-1')
			: (tls ? '-1' : legacyPort || '5244');
	}
	return fallback;
};

const validateListenPort = value => {
	const port = (value || '').trim();
	if (port === '-1')
		return true;

	if (/^\d+$/.test(port)) {
		const number = Number(port);
		if (number >= 1 && number <= 65535)
			return true;
	}

	return _('Port must be -1 or a valid port number from 1 to 65535.');
};

const isHttpUrl = value => {
	try {
		const url = new URL(value);
		return !!url.hostname && (url.protocol === 'http:' || url.protocol === 'https:');
	} catch (e) {
		return false;
	}
};

const validateSiteUrl = value => {
	const url = (value || '').trim();
	if (!url)
		return true;

	if (isHttpUrl(url) && !url.endsWith('/'))
		return true;

	return _('Site URL must start with http:// or https:// and must not end with /.');
};

const validateCorsOrigins = value => {
	const origins = (value || '').split(',')
		.map(origin => origin.trim())
		.filter(Boolean);

	for (const origin of origins) {
		if (origin === '*' || isHttpUrl(origin))
			continue;

		return _('CORS origins must be * or include http:// or https://.');
	}

	return true;
};

const getEffectiveWebEndpoint = config => {
	const httpPort = getListenPortValue('@openlist2[0]', 'listen_http_port', '5244');
	const httpsPort = getListenPortValue('@openlist2[0]', 'listen_https_port', '-1');

	if (isEnabledPort(httpsPort))
		return { protocol: 'https:', port: String(Number(httpsPort)) };

	if (isEnabledPort(httpPort))
		return { protocol: 'http:', port: String(Number(httpPort)) };

	return { protocol: 'http:', port: '' };
};


const normalizePath = value => String(value || '').replace(/\/+/g, '/').replace(/\/$/, '') || '/';
const containsPath = (parent, child) => child === parent || child.startsWith(parent + '/');
const broadDirectories = new Set(['/', '/bin', '/boot', '/dev', '/etc', '/home', '/lib', '/lib64', '/media', '/mnt', '/opt', '/overlay', '/proc', '/root', '/rom', '/run', '/sbin', '/srv', '/sys', '/tmp', '/usr', '/var', '/www', '/tmp/log', '/tmp/run']);
const isBroadDirectory = path => broadDirectories.has(path) ||
	/^\/(?:usr|bin|sbin|lib|lib64|dev|proc|sys|rom|overlay|www)\//.test(path) ||
	/^\/(?:etc\/(?:config|dropbear|ssl)|tmp\/log)(?:\/|$)/.test(path);

const validateAbsolutePath = (value, required) => {
	const path = String(value || '');
	if (!path && !required)
		return true;
	if (!path.startsWith('/') || /[\x00-\x1f\x7f]/.test(path) || /\/\.{1,2}(?:\/|$)/.test(path))
		return _('Use an absolute path without control characters or dot segments.');
	return true;
};

const passiveRanges = value => (Array.isArray(value) ? value : [value || ''])
	.flatMap(item => String(item).split(/[,\s]+/)).filter(Boolean);

const validatePassivePorts = value => {
	for (const range of passiveRanges(value)) {
		if (!/^\d+(?:-\d+)?$/.test(range))
			return _('Use passive ports or ranges from 1024 to 65535.');
		const [first, last = first] = range.split('-').map(Number);
		if (first < 1024 || last > 65535 || first > last)
			return _('Use passive ports or ranges from 1024 to 65535.');
	}
	return true;
};

const backendUrl = route => {
	const endpoint = getEffectiveWebEndpoint('openlist2');
	const base = getWebInterfaceUrl(endpoint.protocol, endpoint.port,
		uci.get('openlist2', '@openlist2[0]', 'site_url'));
	if (!base)
		return null;
	const url = new URL(base);
	url.pathname = url.pathname.replace(/\/$/, '') + '/' + route.replace(/^\//, '');
	url.search = '';
	url.hash = '';
	return url.href;
};

const pollServiceStatus = () => getServiceStatus().then(running => {
	const node = document.getElementById('service_status');
	const endpoint = L.hasViewPermission() ? getEffectiveWebEndpoint('openlist2') : { protocol: 'http:', port: '' };
	const site = L.hasViewPermission() ? uci.get('openlist2', '@openlist2[0]', 'site_url') : '';
	if (node)
		dom.content(node, renderStatus(running, endpoint.protocol, endpoint.port, site));
});

const renderServiceSection = () => {
	poll.add(pollServiceStatus);
	return E('div', { 'class': 'cbi-section', 'id': 'status_bar' },
		E('p', { 'id': 'service_status' }, _('Collecting data...')));
};

const copyPassword = async value => {
	if (typeof navigator !== 'undefined' && navigator.clipboard) {
		try {
			await navigator.clipboard.writeText(value);
			return true;
		} catch (e) { }
	}
	const field = E('textarea', { 'style': 'position:fixed;left:-10000px' }, value);
	document.body.appendChild(field);
	try {
		field.select();
		return document.execCommand('copy') === true;
	} catch (e) {
		return false;
	} finally {
		document.body.removeChild(field);
	}
};

return view.extend({
	load() {
		// UCI contains credentials; readers may view status and bounded logs only.
		return L.hasViewPermission() ? uci.load('openlist2') : Promise.resolve();
	},

	async handleResetPassword() {
		if (!L.hasViewPermission())
			return;
		try {
			const result = await fs.exec(HELPER, ['password-reset']);
			const output = (result.stdout || '').replace(/\u001b\[[0-9;]*m/g, '');
			const username = output.match(/^username:\s*(.+)$/m);
			const password = output.match(/^password:\s*(\S+)\s*$/m);
			if (result.code !== 0 || !username || !password)
				throw new Error((result.stderr || _('The password reset did not return a username and password.')).trim());

			const newPassword = password[1];
			const message = E('p', { 'role': 'status' }, _('Copy the new password before closing this dialog.'));
			const copy = async () => {
				message.textContent = await copyPassword(newPassword)
					? _('New password has been copied to clipboard.')
					: _('Automatic copy failed. Select and copy the password manually.');
			};
			ui.showModal(_('Password reset'), [
				E('p', {}, _('Username:') + ' ' + username[1].trim()),
				E('label', {}, _('New Password:')),
				E('input', { 'type': 'text', 'readonly': 'readonly', 'value': newPassword, 'style': 'width:100%' }),
				message,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, copy) }, _('Copy password')),
					' ',
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Close'))
				])
			]);
			await copy();
		} catch (error) {
			ui.addNotification(null, E('p', _('Unable to reset the password: %s').format(error.message)));
		}
	},

	render() {
		if (!L.hasViewPermission())
			return E('div', {}, [
				renderServiceSection(),
				E('p', {}, _('Configuration contains credentials and is available only to users with write access.'))
			]);
		let m, s, o;

		m = new form.Map('openlist2', _('OpenList'),
			_('A file list program that supports multiple storage.') + '<br />' +
			_('Initial login username is "%s" and password is "%s". Change it immediately after first login.').format('admin', 'admin'));

		s = m.section(form.TypedSection);
		s.anonymous = true;
		s.addremove = false;

		s.render = renderServiceSection;

		s = m.section(form.NamedSection, '@openlist2[0]', 'openlist2');
		const fields = {};
		const addOption = (tab, type, name, ...args) => {
			const option = s.taboption(tab, type, name, ...args);
			fields[name] = option;
			return option;
		};
		const fieldValue = (section_id, name, fallback = '') => {
			const value = fields[name] && fields[name].formvalue(section_id);
			return value == null ? uci.get('openlist2', section_id, name) ?? fields[name]?.default ?? fallback : value;
		};
		const addBackendLink = (tab, name, route, label, description) => {
			const option = addOption(tab, form.DummyValue, name, label, description);
			option.renderWidget = () => {
				const url = backendUrl(route);
				return url ? E('a', { 'href': url, 'target': '_blank', 'rel': 'noopener noreferrer' }, label)
					: E('span', {}, _('Configure a web port or Site URL to open the management page.'));
			};
			return option;
		};

		s.tab('basic', _('Basic Settings'));
		s.tab('global', _('Global Settings'));
		s.tab('log', _('Logs'));
		s.tab('database', _('Database'));
		s.tab('search', _('Search'));
		s.tab('scheme', _('Web Protocol'));
		s.tab('tasks', _('Task threads'),
			_('Worker counts below only initialize missing settings. After the first start, change worker counts and speed limits in OpenList Management > Settings > Traffic. Upload and decompression-upload tasks do not support persistence.'));
		s.tab('cors', _('CORS Settings'));
		s.tab('s3', _('Object Storage'));
		s.tab('ftp', _('FTP'));
		s.tab('sftp', _('SFTP'));
		s.tab('mcp', _('MCP'));

		// init
		o = addOption('basic', form.Flag, 'enabled', _('Enabled'));
		o.default = o.disabled;
		o.rmempty = false;

		o = addOption('basic', form.Flag, 'debug', _('Debug logging'),
			_('Pass --debug to OpenList and send stderr to procd logs.'));
		o.rmempty = false;

		o = addOption('basic', form.Value, 'delayed_start', _('Delayed Start (seconds)'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;

		o = addOption('basic', form.Flag, 'allow_wan', _('Open firewall port'));
		o.rmempty = false;

		o = addOption('basic', form.Value, 'data_dir', _('Data directory'),
			_('Changing this path does not move data. Stop OpenList, back up and move the complete data directory, then apply the new path.'));
		o.default = '/etc/openlist2';
		o.rmempty = false;

		o = addOption('basic', form.Value, 'temp_dir', _('Cache directory'),
			_('OpenList clears this directory on startup. Use a dedicated empty subdirectory. Never select a disk mount root or a directory containing files you want to keep.'));
		o.default = '/tmp/openlist2';
		o.rmempty = false;

		o = addOption('basic', form.Button, '_newpassword', _('Reset Password'),
			_('Generate a new random password using the saved and applied data directory. Start OpenList once before using this action.'));
		o.inputtitle = _('Reset Password');
		o.inputstyle = 'apply';
		o.onclick = ui.createHandlerFn(this, 'handleResetPassword');

		// global
		o = addOption('global', form.Flag, 'force', _('Force read config'),
			_('Setting this to true will force the program to read the configuration file, ignoring environment variables.'));
		o.default = '1';
		o.rmempty = false;

		o = addOption('global', form.Value, 'site_url', _('Site URL'),
			_('When the web is reverse proxied to a subdirectory, this option must be filled out to ensure proper functioning of the web. Do not include \'/\' at the end of the URL'));
		o.validate = function(section_id, value) {
			return validateSiteUrl(value);
		};

		o = addOption('global', form.Value, 'cdn', _('CDN URL'));
		o.default = '';

		o = addOption('global', form.Value, 'jwt_secret', _('JWT Key'));
		o.password = true;
		o.default = '';

		o = addOption('global', form.Value, 'token_expires_in', _('Login Validity Period (hours)'));
		o.datatype = 'uinteger';
		o.default = '48';
		o.rmempty = false;

		o = addOption('global', form.Value, 'proxy_address', _('Proxy address'),
			_('HTTP, HTTPS, SOCKS4, SOCKS5 or SOCKS5HOSTNAME proxy used by OpenList outbound requests.'));
		o.password = true;
		o.default = '';

		o = addOption('global', form.Value, 'auto_memory_limit', _('Auto memory limit (MB)'),
			_('0 disables the automatic memory limit. The upstream default is 4 MB.'));
		o.default = '4';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = addOption('global', form.Value, 'min_free_memory', _('Minimum free memory (MB)'),
			_('Values below 16 let OpenList calculate a default; negative values disable memory cache.'));
		o.default = '0';
		o.datatype = 'integer';
		o.rmempty = false;

		o = addOption('global', form.Value, 'max_block_limit', _('Maximum block size (MB)'),
			_('Values below 4 let OpenList calculate a default.'));
		o.default = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = addOption('global', form.Value, 'max_connections', _('Max Connections'),
			_('0 is unlimited, It is recommend to set a low number of concurrency (10-20) for poor performance device'));
		o.default = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = addOption('global', form.Value, 'max_concurrency', _('Max concurrency of local proxies'),
		_('0 is unlimited, Limit the maximum concurrency of local agents. The default value is 64'));
		o.default = '64';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = addOption('global', form.Flag, 'tls_insecure_skip_verify', _('Disable TLS Verify'),
			_('Skip remote TLS certificate verification (not recommended).'));
		o.default = '0';
		o.rmempty = false;

		// Logs
		o = addOption('log', form.Flag, 'log', _('Enable Logs'));
		o.default = '1';
		o.rmempty = false;

		o = addOption('log', form.Value, 'log_path', _('Log path'));
		o.default = '/var/log/openlist2.log';
		o.rmempty = false;
		o.depends('log', '1');
		o.validate = function(section_id, value) {
			if (isSafeLogPath(value))
				return true;

			return _('Log path must be /var/log/openlist2* without subdirectories.');
		};

		o = addOption('log', form.Value, 'log_max_size', _('Max Size (MB)'));
		o.datatype = 'uinteger';
		o.default = '1';
		o.rmempty = false;
		o.depends('log', '1');

		o = addOption('log', form.Value, 'log_max_backups', _('Max backups'));
		o.datatype = 'uinteger';
		o.default = '3';
		o.rmempty = false;
		o.depends('log', '1');

		o = addOption('log', form.Value, 'log_max_age', _('Max age'));
		o.datatype = 'uinteger';
		o.default = '28';
		o.rmempty = false;
		o.depends('log', '1');

		o = addOption('log', form.Flag, 'log_compress', _('Log Compress'));
		o.default = '0';
		o.rmempty = false;
		o.depends('log', '1');

		o = addOption('log', form.Flag, 'log_filter', _('Enable common log filters'),
			_('Filter noisy access logs such as health checks, HEAD requests and WebDAV PROPFIND.'));
		o.rmempty = false;
		o.depends('log', '1');

		o = addOption('log', form.Value, 'log_filter_cidr', _('Custom log filter CIDR'));
		o.depends('log_filter', '1');

		o = addOption('log', form.Value, 'log_filter_path', _('Custom log filter path'));
		o.depends('log_filter', '1');

		o = addOption('log', form.Value, 'log_filter_method', _('Custom log filter method'));
		o.depends('log_filter', '1');

		// database
		o = addOption('database', form.ListValue, 'database_type', _('Database Type'));
		o.default = 'sqlite3';
		o.value('sqlite3', _('SQLite'));
		o.value('mysql', _('MySQL'));
		o.value('postgres', _('PostgreSQL'));

		o = addOption('database', form.Value, 'mysql_host', _('Database Host'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = addOption('database', form.Value, 'mysql_port', _('Database Port'),
			_('Use 0 to apply the usual default for the selected database: 3306 for MySQL, 5432 for PostgreSQL.'));
		o.datatype = 'port';
		o.default = '0';
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = addOption('database', form.Value, 'mysql_username', _('Database Username'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = addOption('database', form.Value, 'mysql_password', _('Database Password'));
		o.password = true;
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = addOption('database', form.Value, 'mysql_database', _('Database Name'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = addOption('database', form.Value, 'mysql_table_prefix', _('Database Table Prefix'));
		o.default = 'x_';
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = addOption('database', form.Value, 'mysql_ssl_mode', _('Database SSL Mode'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = addOption('database', form.Value, 'mysql_dsn', _('Database DSN'));
		o.password = true;
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = addOption('search', form.Value, 'meilisearch_host', _('Meilisearch Host'));
		o.default = 'http://localhost:7700';
		o.rmempty = false;

		o = addOption('search', form.Value, 'meilisearch_api_key', _('Meilisearch API Key'));
		o.password = true;

		o = addOption('search', form.Value, 'meilisearch_index', _('Meilisearch Index'));
		o.default = 'openlist';
		o.rmempty = false;

		o = addOption('search', form.Value, 'bleve_dir', _('Bleve index directory'),
			_('Empty uses the bleve subdirectory of the data directory. Keep the index separate from cache and frontend files.'));
		o.default = '';

		o = addOption('global', form.Value, 'dist_dir', _('External frontend directory'),
			_('Optional directory containing index.html from a matching OpenList frontend. Empty uses the bundled frontend. Restart OpenList after changing it.'));
		o.default = '';

		// scheme
		o = addOption('scheme', form.Value, 'listen_addr', _('Listen address'));
		o.default = '0.0.0.0';
		o.datatype = 'ipaddr';
		o.rmempty = false;

		o = addOption('scheme', form.Value, 'listen_http_port', _('HTTP listen port'),
			_('The upstream default is 5244. Set to -1 to disable HTTP.'));
		o.datatype = 'integer';
		o.default = '5244';
		o.rmempty = false;
		o.cfgvalue = section_id => getListenPortValue(section_id, 'listen_http_port', '5244');
		o.validate = function(section_id, value) {
			return validateListenPort(value);
		};

		o = addOption('scheme', form.Value, 'listen_https_port', _('HTTPS listen port'),
			_('Set to -1 to disable HTTPS, or 1-65535 to enable it. Leave both certificate paths empty to use an automatically generated self-signed certificate.'));
		o.datatype = 'integer';
		o.default = '-1';
		o.rmempty = false;
		o.cfgvalue = section_id => getListenPortValue(section_id, 'listen_https_port', '-1');
		o.validate = function(section_id, value) {
			return validateListenPort(value);
		};

		o = addOption('scheme', form.Flag, 'force_https', _('Force HTTPS'),
			_('Redirect HTTP requests to HTTPS. The HTTPS listen port enables HTTPS independently of this option.'));
		o.rmempty = false;

		o = addOption('scheme', form.Value, 'ssl_cert', _('SSL cert'),
			_('Leave both paths empty to manage a self-signed certificate in the TLS subdirectory of the data directory. It is reused and renewed at startup when fewer than 30 days remain. Browsers do not trust self-signed certificates automatically.'));

		o = addOption('scheme', form.Value, 'ssl_key', _('SSL key'),
			_('For custom TLS, specify both certificate and private key paths. The certificate must be currently valid and match its private key. Custom files are never overwritten automatically.'));

		o = addOption('scheme', form.Value, 'listen_unix_file', _('Unix socket file'));

		o = addOption('scheme', form.Value, 'listen_unix_file_perm', _('Unix socket permission'));

		o = addOption('scheme', form.Flag, 'listen_enable_h2c', _('Enable H2C'),
			_('Enable cleartext HTTP/2 for reverse proxies that use grpc_pass.'));
		o.rmempty = false;

		o = addOption('scheme', form.Flag, 'listen_enable_h3', _('Enable HTTP/3/QUIC'),
			_('Enable HTTP/3 over QUIC on the HTTPS listen port. HTTPS must be enabled. Certificate settings are shared with HTTPS.'));
		o.rmempty = false;

		// tasks
		addBackendLink('tasks', '_traffic', '@manage/settings/traffic', _('Open traffic settings'),
			_('Use the OpenList backend to change the effective worker counts and transfer speed limits.'));
		o = addOption('tasks', form.Value, 'download_workers', _('Download Workers (initial)'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'download_max_retry', _('Download Max Retry'));
		o.datatype = 'uinteger';
		o.default = '1';
		o.rmempty = false;

		o = addOption('tasks', form.Flag, 'download_task_persistant', _('Download Task Persistence'));
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'transfer_workers', _('Transfer Workers (initial)'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'transfer_max_retry', _('Transfer Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = addOption('tasks', form.Flag, 'transfer_task_persistant', _('Transfer Task Persistence'));
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'upload_workers', _('Upload Workers (initial)'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'upload_max_retry', _('Upload Max Retry'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;


		o = addOption('tasks', form.Value, 'copy_workers', _('Copy Workers (initial)'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'copy_max_retry', _('Copy Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = addOption('tasks', form.Flag, 'copy_task_persistant', _('Copy Task Persistence'));
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'move_workers', _('Move Workers (initial)'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'move_max_retry', _('Move Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = addOption('tasks', form.Flag, 'move_task_persistant', _('Move Task Persistence'));
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'decompress_workers', _('Decompress Workers (initial)'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'decompress_max_retry', _('Decompress Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = addOption('tasks', form.Flag, 'decompress_task_persistant', _('Decompress Task Persistence'));
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'decompress_upload_workers', _('Decompress Upload Workers (initial)'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = addOption('tasks', form.Value, 'decompress_upload_max_retry', _('Decompress Upload Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;


		o = addOption('tasks', form.Flag, 'allow_retry_canceled', _('Allow retry canceled tasks'));
		o.rmempty = false;

		// cors
		o = addOption('cors', form.Value, 'cors_allow_origins', _('Allow Origins'),
			_('Comma-separated list. Use * to allow any value.'));
		o.default = '*';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			return validateCorsOrigins(value);
		};

		o = addOption('cors', form.Value, 'cors_allow_methods', _('Allow Methods'),
			_('Comma-separated list. Use * to allow any value.'));
		o.default = '*';
		o.rmempty = false;

		o = addOption('cors', form.Value, 'cors_allow_headers', _('Allow Headers'),
			_('Comma-separated list. Use * to allow any value.'));
		o.default = '*';
		o.rmempty = false;

		// s3
		addBackendLink('s3', '_s3_settings', '@manage/settings/s3', _('Open S3 management'),
			_('Generate the S3 access key and secret in OpenList settings, then configure bucket mappings. Restart OpenList after changing credentials.'));
		o = addOption('s3', form.Flag, 's3', _('Enabled S3'));
		o.rmempty = false;

		o = addOption('s3', form.Value, 's3_port', _('Port'));
		o.datatype = 'and(port,min(1))';
		o.default = 5246;
		o.rmempty = false;

		o = addOption('s3', form.Flag, 's3_ssl', _('Enable SSL'),
			_('Use the same custom or automatically generated certificate as HTTPS. Configure certificate paths on the Web Protocol tab.'));
		o.rmempty = false;

		// ftp
		addBackendLink('ftp', '_ftp_settings', '@manage/settings/ftp', _('Open FTP settings'),
			_('Configure the public host and passive port mapping in OpenList. Restart the service after changing FTP settings.'));
		o = addOption('ftp', form.DynamicList, 'ftp_pasv_ports', _('FTP passive firewall ports'),
			_('Ports or ranges to allow from WAN, for example 50000-50100. They must match the listening ports in OpenList passive port mapping. Empty means passive ports must be allowed manually.'));
		o.placeholder = '50000-50100';
		o.depends({ ftp: '1', allow_wan: '1' });
		o = addOption('ftp', form.Flag, 'ftp', _('Enabled FTP'),
			_('Enable FTP/SFTP access for the OpenList account in Management > Users. Also grant FTP/SFTP management permission to allow uploads and changes.'));
		o.rmempty = false;

		o = addOption('ftp', form.Value, 'ftp_port', _('FTP Port'));
		o.datatype = 'and(port,min(1))';
		o.default = 5221;
		o.rmempty = false;

		o = addOption('ftp', form.Value, 'find_pasv_port_attempts', _('Max retries on port conflict during passive transfer'));
		o.datatype = 'uinteger';
		o.default = '50';
		o.rmempty = false;

		o = addOption('ftp', form.Flag, 'active_transfer_port_non_20', _('Enable non-20 port for active transfer'));
		o.rmempty = false;

		o = addOption('ftp', form.Value, 'idle_timeout', _('Client idle timeout (seconds)'));
		o.datatype = 'uinteger';
		o.default = '900';
		o.rmempty = false;

		o = addOption('ftp', form.Value, 'connection_timeout', _('Connection timeout (seconds)'));
		o.datatype = 'uinteger';
		o.default = '30';
		o.rmempty = false;

		o = addOption('ftp', form.Flag, 'disable_active_mode', _('Disable active transfer mode'));
		o.rmempty = false;

		o = addOption('ftp', form.Flag, 'default_transfer_binary', _('Enable binary transfer mode'));
		o.rmempty = false;

		o = addOption('ftp', form.Flag, 'enable_active_conn_ip_check', _('Client IP check in active transfer mode'));
		o.default = '1';
		o.rmempty = false;

		o = addOption('ftp', form.Flag, 'enable_pasv_conn_ip_check', _('Client IP check in passive transfer mode'));
		o.default = '1';
		o.rmempty = false;

		// sftp
		o = addOption('sftp', form.Flag, 'sftp', _('Enabled SFTP'),
			_('Enable FTP/SFTP access for the OpenList account in Management > Users. Also grant FTP/SFTP management permission to allow uploads and changes.'));
		o.rmempty = false;

		o = addOption('sftp', form.Value, 'sftp_port', _('SFTP Port'));
		o.datatype = 'and(port,min(1))';
		o.default = 5222;
		o.rmempty = false;

		// mcp
		o = addOption('mcp', form.Flag, 'mcp', _('Enabled MCP'),
			_('Enable MCP (Model Context Protocol) server.'));
		o.rmempty = false;


		o = addOption('mcp', form.DummyValue, '_mcp_endpoint', _('MCP endpoint'),
			_('Use Streamable HTTP with Authorization: TOKEN, without a Bearer prefix. Use an OpenList administrator login token; retain MCP-Session-Id for subsequent requests.'));
		o.depends('mcp', '1');
		o.renderWidget = () => E('div', {}, [
			E('code', {}, backendUrl('mcp') || _('Configure a web port or Site URL.')),
			E('p', {}, E('a', { 'href': 'https://doc.oplist.org/guide/advanced/mcp', 'target': '_blank', 'rel': 'noopener noreferrer' }, _('MCP documentation')))
		]);

		const validateDirectories = (section_id, changed, value) => {
			const required = changed === 'data_dir' || changed === 'temp_dir';
			const valid = validateAbsolutePath(value, required);
			if (valid !== true)
				return valid;
			const get = (name, fallback) => normalizePath(name === changed ? value || fallback : fieldValue(section_id, name, fallback) || fallback);
			const data = get('data_dir', '/etc/openlist2');
			const cache = get('temp_dir', '/tmp/openlist2');
			const index = get('bleve_dir', data + '/bleve');
			const distValue = changed === 'dist_dir' ? value : fieldValue(section_id, 'dist_dir');
			const dist = distValue ? normalizePath(distValue) : '';
			for (const path of [data, cache, index, dist].filter(Boolean))
				if (isBroadDirectory(path))
					return _('Use a dedicated subdirectory, not a system directory or disk mount root.');
			if (/^\/(?:mnt|media)\/[^/]+$/.test(cache))
				return _('Use a cache subdirectory below the disk mount.');
			if (containsPath(cache, data) || containsPath(index, data) ||
				containsPath(cache, index) || containsPath(index, cache))
				return _('Cache and index directories must be separate and must not contain the data directory.');
			if (dist && (containsPath(dist, data) || containsPath(dist, cache) ||
				containsPath(cache, dist) || containsPath(dist, index) || containsPath(index, dist)))
				return _('Frontend files must be separate from private data, cache and index files.');
			if (tlsRequired(section_id) && !fieldValue(section_id, 'ssl_cert') && !fieldValue(section_id, 'ssl_key')) {
				const tls = data + '/tls';
				for (const directory of [cache, index, dist].filter(Boolean))
					if (containsPath(tls, directory) || containsPath(directory, tls))
						return _('Automatic TLS directory must be separate from cache, index and public frontend directories.');
			}
			return true;
		};
		for (const name of ['data_dir', 'temp_dir', 'bleve_dir', 'dist_dir'])
			fields[name].validate = (section_id, value) => validateDirectories(section_id, name, value);

		const tlsRequired = section_id => {
			const httpsPort = fieldValue(section_id, 'listen_https_port', '-1');
			const s3Enabled = fieldValue(section_id, 's3') === '1';
			const s3Ssl = fieldValue(section_id, 's3_ssl') === '1';
			return isEnabledPort(httpsPort) || (s3Enabled && s3Ssl);
		};
		const validateCertificatePaths = (section_id, changed, value) => {
			if (!tlsRequired(section_id))
				return true;
			const cert = changed === 'ssl_cert' ? value : fieldValue(section_id, 'ssl_cert');
			const key = changed === 'ssl_key' ? value : fieldValue(section_id, 'ssl_key');
			if (!cert && !key)
				return true;
			if (!cert || !key)
				return _('Leave both certificate paths empty for automatic TLS, or provide both custom certificate and key paths.');
			for (const path of [cert, key]) {
				const valid = validateAbsolutePath(path, true);
				if (valid !== true)
					return valid;
			}
			return true;
		};
		for (const name of ['ssl_cert', 'ssl_key'])
			fields[name].validate = (section_id, value) => validateCertificatePaths(section_id, name, value);
		// LuCI passes input.value (always "1") for checkbox validation.
		// Read formvalue() to distinguish checked and unchecked flags.
		for (const name of ['force_https', 'listen_enable_h3'])
			fields[name].validate = section_id => fieldValue(section_id, name) !== '1' || isEnabledPort(fieldValue(section_id, 'listen_https_port', '-1'))
				? true : _('Force HTTPS and HTTP/3 require an enabled HTTPS port.');
		fields.s3_ssl.validate = section_id => fieldValue(section_id, 's3') !== '1' || fieldValue(section_id, 's3_ssl') !== '1'
			? true : validateCertificatePaths(section_id);
		fields.listen_unix_file.validate = (section_id, value) => validateAbsolutePath(value, false);
		fields.listen_unix_file_perm.validate = (section_id, value) => !value || /^[0-7]{3,4}$/.test(value)
			? true : _('Use 3 or 4 octal digits, for example 660 or 0660.');
		fields.log_max_size.datatype = 'and(uinteger,min(1))';

		const validatePorts = (section_id, changed, value) => {
			const get = name => name === changed ? value : fieldValue(section_id, name,
				name === 'listen_http_port' ? '5244' : name === 'listen_https_port' ? '-1' : '');
			const names = ['listen_http_port', 'listen_https_port'];
			if (fieldValue(section_id, 's3') === '1') names.push('s3_port');
			if (fieldValue(section_id, 'ftp') === '1') names.push('ftp_port');
			if (fieldValue(section_id, 'sftp') === '1') names.push('sftp_port');
			const seen = new Set();
			const usePassive = changed === 'ftp_pasv_ports' ||
				(fieldValue(section_id, 'ftp') === '1' && fieldValue(section_id, 'allow_wan') === '1');
			const passive = usePassive ? passiveRanges(changed === 'ftp_pasv_ports' ? value : fieldValue(section_id, 'ftp_pasv_ports')) : [];
			const passiveValid = validatePassivePorts(passive);
			if (passiveValid !== true)
				return passiveValid;
			for (const name of names) {
				const candidate = String(get(name)).trim();
				const valid = validateListenPort(candidate);
				if (valid !== true)
					return valid;
				if (candidate === '-1')
					continue;
				const port = Number(candidate);
				if (seen.has(port))
					return _('Enabled services cannot share TCP port %s.').format(port);
				seen.add(port);
				if (fieldValue(section_id, 'ftp') === '1')
					for (const range of passive) {
						const [first, last = first] = range.split('-').map(Number);
						if (port >= first && port <= last)
							return _('FTP passive ports must not overlap service port %s.').format(port);
					}
			}
			if (!isEnabledPort(get('listen_https_port')) &&
				(fieldValue(section_id, 'force_https') === '1' || fieldValue(section_id, 'listen_enable_h3') === '1'))
				return _('Force HTTPS and HTTP/3 require an enabled HTTPS port.');
			return true;
		};
		for (const name of ['listen_http_port', 'listen_https_port', 's3_port', 'ftp_port', 'sftp_port', 'ftp_pasv_ports'])
			fields[name].validate = (section_id, value) => validatePorts(section_id, name, value);
		const protocolFields = ['listen_http_port', 'listen_https_port', 'force_https', 'listen_enable_h3',
			'ssl_cert', 'ssl_key', 's3', 's3_ssl', 's3_port', 'ftp', 'ftp_port', 'sftp', 'sftp_port',
			'ftp_pasv_ports', 'allow_wan', 'data_dir', 'temp_dir', 'bleve_dir', 'dist_dir'];
		const revalidateProtocolFields = (event, section_id) => {
			for (const name of protocolFields)
				if (fields[name].isActive(section_id))
					fields[name].triggerValidation(section_id);
			ui.tabs.updateTabs(event, m.root);
		};
		for (const name of protocolFields)
			fields[name].onchange = revalidateProtocolFields;
		for (const name of ['ftp_pasv_ports', 'log_path', 'log_max_size', 'log_max_backups', 'log_max_age',
			'log_compress', 'log_filter', 'log_filter_cidr', 'log_filter_path', 'log_filter_method'])
			fields[name].retain = true;

		return m.render();
	}
});
