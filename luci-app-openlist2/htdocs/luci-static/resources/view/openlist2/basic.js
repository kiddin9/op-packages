'use strict';
'require dom';
'require form';
'require fs';
'require poll';
'require rpc';
'require uci';
'require view';

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
	const fallbackUrl = `${protocol}//${window.location.hostname}:${webport}/`;
	const configuredUrl = (site_url || '').trim();
	if (configuredUrl) {
		try {
			const url = new URL(configuredUrl, fallbackUrl);
			if (url.protocol === 'http:' || url.protocol === 'https:')
				return url.href;
		} catch (e) { }
	}

	return fallbackUrl;
};

const renderStatus = (isRunning, protocol, webport, site_url) => {
	const status = E('em', {}, E('span', { 'style': `color:${isRunning ? 'green' : 'red'}` },
		E('strong', {}, ['OpenList ', isRunning ? _('RUNNING') : _('NOT RUNNING')])));

	if (isRunning && webport) {
		const buttonUrl = getWebInterfaceUrl(protocol, webport, site_url);
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

const isSafeLogPath = value => /^\/var\/log\/openlist2(?:[._-][A-Za-z0-9._-]+)?$/.test(value || '');

const isEnabledPort = value => {
	const port = (value || '').trim();
	return port !== '' && port !== '-1';
};

const HTTPS_ENABLED_PORT = /^[1-9][0-9]*$/;

const getListenPortValue = (section_id, option, fallback) => {
	const value = uci.get('openlist2', section_id, option);
	return value == null || String(value).trim() === '' ? fallback : value;
};

const getHttpsPortValue = (section_id, httpsPortOption) => {
	const value = httpsPortOption.formvalue(section_id);
	return value == null || String(value).trim() === ''
		? getListenPortValue(section_id, 'listen_https_port', '-1')
		: value;
};

const validateHttpsRequiredFile = (section_id, httpsPortOption, value, message) => {
	if (!HTTPS_ENABLED_PORT.test(String(getHttpsPortValue(section_id, httpsPortOption)).trim()))
		return true;

	return (value || '').trim() ? true : message;
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
	const httpPort = uci.get(config, '@openlist2[0]', 'listen_http_port') || '5244';
	const httpsPort = uci.get(config, '@openlist2[0]', 'listen_https_port') || '-1';

	if (isEnabledPort(httpsPort))
		return { protocol: 'https:', port: httpsPort };

	if (isEnabledPort(httpPort))
		return { protocol: 'http:', port: httpPort };

	return { protocol: 'http:', port: '' };
};

return view.extend({
	load() {
		return Promise.all([
			uci.load('openlist2')
		]);
	},

	async handleResetPassword(data) {
		const data_dir = uci.get(data[0], '@openlist2[0]', 'data_dir') || '/etc/openlist2';
		try {
			const newpassword = await fs.exec('/usr/bin/openlist2', ['admin', 'random', '--data', data_dir]);
			const new_password = newpassword.stdout.match(/password:\s*(\S+)/)[1];

			const textArea = document.createElement('textarea');
			textArea.value = new_password;
			document.body.appendChild(textArea);
			textArea.select();
			document.execCommand('copy');
			document.body.removeChild(textArea);
			alert(`${_('Username:')}admin\n${_('New Password:')}${new_password}\n\n${_('New password has been copied to clipboard.')}`);
		} catch (error) {
			console.error('Failed to reset password: ', error);
		}
	},

	render(data) {
		let m, s, o, httpsPortOption;
		const endpoint = getEffectiveWebEndpoint(data[0]);
		const webport = endpoint.port;
		const protocol = endpoint.protocol;
		const site_url = uci.get(data[0], '@openlist2[0]', 'site_url') || '';

		m = new form.Map('openlist2', _('OpenList'),
			_('A file list program that supports multiple storage.') + '<br />' +
			_('Initial login username is "%s" and password is "%s". Change it immediately after first login.').format('admin', 'admin'));

		s = m.section(form.TypedSection);
		s.anonymous = true;
		s.addremove = false;

		s.render = () => {
			poll.add(() => {
				return L.resolveDefault(getServiceStatus()).then(res => {
					const view = document.getElementById('service_status');
					if (view)
						dom.content(view, renderStatus(res, protocol, webport, site_url));
				});
			});

			return E('div', { class: 'cbi-section', id: 'status_bar' }, [
				E('p', { id: 'service_status' }, _('Collecting data...'))
			]);
		};

		s = m.section(form.NamedSection, '@openlist2[0]', 'openlist2');

		s.tab('basic', _('Basic Settings'));
		s.tab('global', _('Global Settings'));
		s.tab('log', _('Logs'));
		s.tab('database', _('Database'));
		s.tab('search', _('Search'));
		s.tab('scheme', _('Web Protocol'));
		s.tab('tasks', _('Task threads'));
		s.tab('cors', _('CORS Settings'));
		s.tab('s3', _('Object Storage'));
		s.tab('ftp', _('FTP'));
		s.tab('sftp', _('SFTP'));

		// init
		o = s.taboption('basic', form.Flag, 'enabled', _('Enabled'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('basic', form.Flag, 'debug', _('Debug logging'),
			_('Pass --debug to OpenList and send stderr to procd logs.'));
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'delayed_start', _('Delayed Start (seconds)'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('basic', form.Flag, 'allow_wan', _('Open firewall port'));
		o.rmempty = false;

		o = s.taboption('basic', form.Value, 'data_dir', _('Data directory'));
		o.default = '/etc/openlist2';

		o = s.taboption('basic', form.Value, 'temp_dir', _('Cache directory'));
		o.default = '/tmp/openlist2';
		o.rmempty = false;

		o = s.taboption('basic', form.Button, '_newpassword', _('Reset Password'),
			_('Generate a new random password.'));
		o.inputtitle = _('Reset Password');
		o.inputstyle = 'apply';
		o.onclick = L.bind(this.handleResetPassword, this, data);

		// global
		o = s.taboption('global', form.Flag, 'force', _('Force read config'),
			_('Setting this to true will force the program to read the configuration file, ignoring environment variables.'));
		o.default = true;
		o.rmempty = false;

		o = s.taboption('global', form.Value, 'site_url', _('Site URL'),
			_('When the web is reverse proxied to a subdirectory, this option must be filled out to ensure proper functioning of the web. Do not include \'/\' at the end of the URL'));
		o.validate = function(section_id, value) {
			return validateSiteUrl(value);
		};

		o = s.taboption('global', form.Value, 'cdn', _('CDN URL'));
		o.default = '';

		o = s.taboption('global', form.Value, 'jwt_secret', _('JWT Key'));
		o.default = '';

		o = s.taboption('global', form.Value, 'token_expires_in', _('Login Validity Period (hours)'));
		o.datatype = 'uinteger';
		o.default = '48';
		o.rmempty = false;

		o = s.taboption('global', form.Value, 'proxy_address', _('Proxy address'),
			_('HTTP, HTTPS, SOCKS4, SOCKS5 or SOCKS5HOSTNAME proxy used by OpenList outbound requests.'));
		o.default = '';

		o = s.taboption('global', form.Value, 'auto_memory_limit', _('Auto memory limit (MB)'),
			_('0 disables the automatic memory limit. The upstream default is 4 MB.'));
		o.default = '4';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.taboption('global', form.Value, 'min_free_memory', _('Minimum free memory (MB)'),
			_('Values below 16 let OpenList calculate a default; negative values disable memory cache.'));
		o.default = '0';
		o.datatype = 'integer';
		o.rmempty = false;

		o = s.taboption('global', form.Value, 'max_block_limit', _('Maximum block size (MB)'),
			_('Values below 4 let OpenList calculate a default.'));
		o.default = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.taboption('global', form.Value, 'max_connections', _('Max Connections'),
			_('0 is unlimited, It is recommend to set a low number of concurrency (10-20) for poor performance device'));
		o.default = '0';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.taboption('global', form.Value, 'max_concurrency', _('Max concurrency of local proxies'),
		_('0 is unlimited, Limit the maximum concurrency of local agents. The default value is 64'));
		o.default = '64';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.taboption('global', form.Flag, 'tls_insecure_skip_verify', _('Disable TLS Verify'),
			_('Skip remote TLS certificate verification (not recommended).'));
		o.default = false;
		o.rmempty = false;

		// Logs
		o = s.taboption('log', form.Flag, 'log', _('Enable Logs'));
		o.default = 1;
		o.rmempty = false;

		o = s.taboption('log', form.Value, 'log_path', _('Log path'));
		o.default = '/var/log/openlist2.log';
		o.rmempty = false;
		o.depends('log', '1');
		o.validate = function(section_id, value) {
			if (isSafeLogPath(value))
				return true;

			return _('Log path must be /var/log/openlist2* without subdirectories.');
		};

		o = s.taboption('log', form.Value, 'log_max_size', _('Max Size (MB)'));
		o.datatype = 'uinteger';
		o.default = '50';
		o.rmempty = false;
		o.depends('log', '1');

		o = s.taboption('log', form.Value, 'log_max_backups', _('Max backups'));
		o.datatype = 'uinteger';
		o.default = '30';
		o.rmempty = false;
		o.depends('log', '1');

		o = s.taboption('log', form.Value, 'log_max_age', _('Max age'));
		o.datatype = 'uinteger';
		o.default = '28';
		o.rmempty = false;
		o.depends('log', '1');

		o = s.taboption('log', form.Flag, 'log_compress', _('Log Compress'));
		o.default = 'false';
		o.rmempty = false;
		o.depends('log', '1');

		o = s.taboption('log', form.Flag, 'log_filter', _('Enable common log filters'),
			_('Filter noisy access logs such as health checks, HEAD requests and WebDAV PROPFIND.'));
		o.rmempty = false;
		o.depends('log', '1');

		o = s.taboption('log', form.Value, 'log_filter_cidr', _('Custom log filter CIDR'));
		o.depends('log_filter', '1');

		o = s.taboption('log', form.Value, 'log_filter_path', _('Custom log filter path'));
		o.depends('log_filter', '1');

		o = s.taboption('log', form.Value, 'log_filter_method', _('Custom log filter method'));
		o.depends('log_filter', '1');

		// database
		o = s.taboption('database', form.ListValue, 'database_type', _('Database Type'));
		o.default = 'sqlite3';
		o.value('sqlite3', _('SQLite'));
		o.value('mysql', _('MySQL'));
		o.value('postgres', _('PostgreSQL'));

		o = s.taboption('database', form.Value, 'mysql_host', _('Database Host'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = s.taboption('database', form.Value, 'mysql_port', _('Database Port'),
			_('Use 0 to apply the usual default for the selected database: 3306 for MySQL, 5432 for PostgreSQL.'));
		o.datatype = 'port';
		o.default = '0';
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = s.taboption('database', form.Value, 'mysql_username', _('Database Username'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = s.taboption('database', form.Value, 'mysql_password', _('Database Password'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = s.taboption('database', form.Value, 'mysql_database', _('Database Name'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = s.taboption('database', form.Value, 'mysql_table_prefix', _('Database Table Prefix'));
		o.default = 'x_';
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = s.taboption('database', form.Value, 'mysql_ssl_mode', _('Database SSL Mode'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = s.taboption('database', form.Value, 'mysql_dsn', _('Database DSN'));
		o.depends('database_type', 'mysql');
		o.depends('database_type', 'postgres');

		o = s.taboption('search', form.Value, 'meilisearch_host', _('Meilisearch Host'));
		o.default = 'http://localhost:7700';
		o.rmempty = false;

		o = s.taboption('search', form.Value, 'meilisearch_api_key', _('Meilisearch API Key'));
		o.password = true;

		o = s.taboption('search', form.Value, 'meilisearch_index', _('Meilisearch Index'));
		o.default = 'openlist';
		o.rmempty = false;

		// scheme
		o = s.taboption('scheme', form.Value, 'listen_addr', _('Listen address'));
		o.default = '0.0.0.0';
		o.datatype = 'ipaddr';
		o.rmempty = false;

		o = s.taboption('scheme', form.Value, 'listen_http_port', _('HTTP listen port'),
			_('The upstream default is 5244. Set to -1 to disable HTTP.'));
		o.datatype = 'integer';
		o.default = '5244';
		o.rmempty = false;
		o.cfgvalue = section_id => getListenPortValue(section_id, 'listen_http_port', '5244');
		o.validate = function(section_id, value) {
			return validateListenPort(value);
		};

		httpsPortOption = o = s.taboption('scheme', form.Value, 'listen_https_port', _('HTTPS listen port'),
			_('The upstream default is -1 (disabled). Set a valid port number to enable HTTPS.'));
		o.datatype = 'integer';
		o.default = '-1';
		o.rmempty = false;
		o.cfgvalue = section_id => getListenPortValue(section_id, 'listen_https_port', '-1');
		o.validate = function(section_id, value) {
			return validateListenPort(value);
		};

		o = s.taboption('scheme', form.Flag, 'force_https', _('Force HTTPS'));
		o.rmempty = false;

		o = s.taboption('scheme', form.Value, 'ssl_cert', _('SSL cert'),
			_('SSL certificate file path'));
		o.validate = function(section_id, value) {
			return validateHttpsRequiredFile(section_id, httpsPortOption, value,
				_('SSL certificate file path is required when HTTPS is enabled.'));
		};

		o = s.taboption('scheme', form.Value, 'ssl_key', _('SSL key'),
			_('SSL key file path'));
		o.validate = function(section_id, value) {
			return validateHttpsRequiredFile(section_id, httpsPortOption, value,
				_('SSL key file path is required when HTTPS is enabled.'));
		};

		o = s.taboption('scheme', form.Value, 'listen_unix_file', _('Unix socket file'));

		o = s.taboption('scheme', form.Value, 'listen_unix_file_perm', _('Unix socket permission'));

		o = s.taboption('scheme', form.Flag, 'listen_enable_h2c', _('Enable H2C'),
			_('Enable cleartext HTTP/2 for reverse proxies that use grpc_pass.'));
		o.rmempty = false;

		o = s.taboption('scheme', form.Flag, 'listen_enable_h3', _('Enable HTTP/3/QUIC'),
			_('Enable HTTP/3 over QUIC on the HTTPS listen port. HTTPS must be enabled and certificate files must be configured.'));
		o.rmempty = false;

		// tasks
		o = s.taboption('tasks', form.Value, 'download_workers', _('Download Workers'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'download_max_retry', _('Download Max Retry'));
		o.datatype = 'uinteger';
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('tasks', form.Flag, 'download_task_persistant', _('Download Task Persistence'));
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'transfer_workers', _('Transfer Workers'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'transfer_max_retry', _('Transfer Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = s.taboption('tasks', form.Flag, 'transfer_task_persistant', _('Transfer Task Persistence'));
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'upload_workers', _('Upload Workers'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'upload_max_retry', _('Upload Max Retry'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;

		o = s.taboption('tasks', form.Flag, 'upload_task_persistant', _('Upload Task Persistence'));
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'copy_workers', _('Copy Workers'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'copy_max_retry', _('Copy Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = s.taboption('tasks', form.Flag, 'copy_task_persistant', _('Copy Task Persistence'));
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'move_workers', _('Move Workers'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'move_max_retry', _('Move Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = s.taboption('tasks', form.Flag, 'move_task_persistant', _('Move Task Persistence'));
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'decompress_workers', _('Decompress Workers'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'decompress_max_retry', _('Decompress Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = s.taboption('tasks', form.Flag, 'decompress_task_persistant', _('Decompress Task Persistence'));
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'decompress_upload_workers', _('Decompress Upload Workers'));
		o.datatype = 'uinteger';
		o.default = '5';
		o.rmempty = false;

		o = s.taboption('tasks', form.Value, 'decompress_upload_max_retry', _('Decompress Upload Max Retry'));
		o.datatype = 'uinteger';
		o.default = '2';
		o.rmempty = false;

		o = s.taboption('tasks', form.Flag, 'decompress_upload_task_persistant', _('Decompress Upload Task Persistence'));
		o.rmempty = false;

		o = s.taboption('tasks', form.Flag, 'allow_retry_canceled', _('Allow retry canceled tasks'));
		o.rmempty = false;

		// cors
		o = s.taboption('cors', form.Value, 'cors_allow_origins', _('Allow Origins'),
			_('Comma-separated list. Use * to allow any value.'));
		o.default = '*';
		o.rmempty = false;
		o.validate = function(section_id, value) {
			return validateCorsOrigins(value);
		};

		o = s.taboption('cors', form.Value, 'cors_allow_methods', _('Allow Methods'),
			_('Comma-separated list. Use * to allow any value.'));
		o.default = '*';
		o.rmempty = false;

		o = s.taboption('cors', form.Value, 'cors_allow_headers', _('Allow Headers'),
			_('Comma-separated list. Use * to allow any value.'));
		o.default = '*';
		o.rmempty = false;

		// s3
		o = s.taboption('s3', form.Flag, 's3', _('Enabled S3'));
		o.rmempty = false;

		o = s.taboption('s3', form.Value, 's3_port', _('Port'));
		o.datatype = 'and(port,min(1))';
		o.default = 5246;
		o.rmempty = false;

		o = s.taboption('s3', form.Flag, 's3_ssl', _('Enable SSL'));
		o.rmempty = false;

		// ftp
		o = s.taboption('ftp', form.Flag, 'ftp', _('Enabled FTP'));
		o.rmempty = false;

		o = s.taboption('ftp', form.Value, 'ftp_port', _('FTP Port'));
		o.datatype = 'and(port,min(1))';
		o.default = 5221;
		o.rmempty = false;

		o = s.taboption('ftp', form.Value, 'find_pasv_port_attempts', _('Max retries on port conflict during passive transfer'));
		o.datatype = 'uinteger';
		o.default = '50';
		o.rmempty = false;

		o = s.taboption('ftp', form.Flag, 'active_transfer_port_non_20', _('Enable non-20 port for active transfer'));
		o.rmempty = false;

		o = s.taboption('ftp', form.Value, 'idle_timeout', _('Client idle timeout (seconds)'));
		o.datatype = 'uinteger';
		o.default = '900';
		o.rmempty = false;

		o = s.taboption('ftp', form.Value, 'connection_timeout', _('Connection timeout (seconds)'));
		o.datatype = 'uinteger';
		o.default = '30';
		o.rmempty = false;

		o = s.taboption('ftp', form.Flag, 'disable_active_mode', _('Disable active transfer mode'));
		o.rmempty = false;

		o = s.taboption('ftp', form.Flag, 'default_transfer_binary', _('Enable binary transfer mode'));
		o.rmempty = false;

		o = s.taboption('ftp', form.Flag, 'enable_active_conn_ip_check', _('Client IP check in active transfer mode'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('ftp', form.Flag, 'enable_pasv_conn_ip_check', _('Client IP check in passive transfer mode'));
		o.default = '1';
		o.rmempty = false;

		// sftp
		o = s.taboption('sftp', form.Flag, 'sftp', _('Enabled SFTP'));
		o.rmempty = false;

		o = s.taboption('sftp', form.Value, 'sftp_port', _('SFTP Port'));
		o.datatype = 'and(port,min(1))';
		o.default = 5222;
		o.rmempty = false;

		return m.render();
	}
});
