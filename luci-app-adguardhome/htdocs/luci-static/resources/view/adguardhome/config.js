'use strict';

'require dom';
'require form';
'require fs';
'require poll';
'require rpc';
'require uci';
'require view';

const DEFAULT_CONFIG_FILE = '/etc/adguardhome/adguardhome.yaml';
const DEFAULT_WORK_DIR = '/var/lib/adguardhome';
const DEFAULT_USER = 'adguardhome';
const DEFAULT_GROUP = DEFAULT_USER;

const DEFAULT_GOGC = '0';
const DEFAULT_GOMAXPROCS = '0';
const DEFAULT_GOMEMLIMIT = '0';

const PATH_REGEX = new RegExp('^/etc(/[^/]+)?/?$');

// bcrypt hash: $2a$/$2b$/$2x$/$2y$ + 2-digit cost + $ + 53 chars
const BCRYPT_REGEX = /^\$2[abxy]\$\d{2}\$[.\/A-Za-z0-9]{53}$/;

// Fixed list of values the core-update options may hold. The backend script
// maps 'official'/'github' to hard-coded URLs, so no URL is ever stored in UCI.
const CORE_VERSIONS = ['latest', 'beta'];
const UPDATE_SOURCES = ['official', 'github'];

const GITHUB_RELEASE_URL_REGEX = /^https:\/\/github\.com\/AdguardTeam\/AdGuardHome\/releases\//;
const VERSION_TAG_REGEX = /^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$/;

// Directories that must never be handed to the service read-write.
const DANGEROUS_RW_PATHS = ['/', '/etc', '/root', '/usr', '/bin', '/sbin', '/lib', '/boot', '/proc', '/sys', '/dev', '/overlay', '/rom'];

const POLL_INTERVAL = 5;

const RUNNING_SPAN = `<span style="color: green; font-weight: bold">${_('Running')}</span>`;
const NOT_RUNNING_SPAN = `<span style="color: red; font-weight: bold">${_('Not running')}</span>`;

const STORAGE_KEY = 'luci-app-adguardhome';
const STORAGE_KEY_CORE = 'luci-app-adguardhome_core_update';

// Escape a value for safe use in HTML text and quoted attribute values.
function esc(value) {
	return String(value == null ? '' : value).replace(/[&<>"']/g, function(c) {
		return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
	});
}

// Classify an old-style full update URL by its parsed host (not a substring match).
// The value is only used to pick the matching dropdown entry, never to download.
function isLegacyGithubUrl(value) {
	if (typeof value !== 'string') {
		return false;
	}
	try {
		const u = new URL(value);
		return u.protocol === 'https:' && u.hostname === 'github.com';
	} catch (e) {
		return false;
	}
}

function hasControlChars(value) {
	return /[\x00-\x1f\x7f]/.test(value);
}

function hasDotDotSegment(value) {
	return value.split('/').indexOf('..') !== -1;
}

// ---- BEGIN new-release notice ------------------------------------------------
// AdGuard Home's own /control/version.json needs HTTP basic auth (this page only
// ever holds the password hash) and is served on another port, so the page asks
// GitHub directly: the same source as the "Check update" button and update_core.sh.
// The answer is cached in localStorage so opening the page does not cost an API
// request every time (GitHub allows only 60 unauthenticated requests per hour).
const STORAGE_KEY_LATEST = 'luci-app-adguardhome_latest_release';
const RELEASE_CACHE_TTL = 6 * 60 * 60 * 1000;   // after a successful check
const RELEASE_RETRY_DELAY = 30 * 60 * 1000;     // after a failed check
const RELEASE_FETCH_TIMEOUT = 8000;

function storageGet(key) {
	try {
		return window.localStorage.getItem(key);
	} catch (e) {
		return null;
	}
}

function storageSet(key, value) {
	try {
		window.localStorage.setItem(key, value);
	} catch (e) {}
}

// "v0.107.57-b.2" -> { nums: [0, 107, 57], pre: ['b', '2'] }, or null
function parseVersion(str) {
	const m = /v?(\d+)\.(\d+)\.(\d+)(?:-([A-Za-z0-9.]+))?/.exec(String(str || ''));
	if (!m) {
		return null;
	}
	return { nums: [+m[1], +m[2], +m[3]], pre: m[4] ? m[4].split('.') : [] };
}

function formatVersion(v) {
	return 'v' + v.nums.join('.') + (v.pre.length ? '-' + v.pre.join('.') : '');
}

// Comparator result (<0, 0, >0). A pre-release sorts below its release.
function compareVersions(a, b) {
	for (let i = 0; i < 3; i++) {
		if (a.nums[i] !== b.nums[i]) {
			return a.nums[i] - b.nums[i];
		}
	}
	if (!a.pre.length && !b.pre.length) {
		return 0;
	}
	if (!a.pre.length) {
		return 1;
	}
	if (!b.pre.length) {
		return -1;
	}
	const n = Math.max(a.pre.length, b.pre.length);
	for (let i = 0; i < n; i++) {
		const x = a.pre[i];
		const y = b.pre[i];
		if (x === undefined) {
			return -1;
		}
		if (y === undefined) {
			return 1;
		}
		if (x === y) {
			continue;
		}
		const xNum = /^\d+$/.test(x);
		const yNum = /^\d+$/.test(y);
		if (xNum && yNum) {
			return +x - +y;
		}
		if (xNum) {
			return -1;
		}
		if (yNum) {
			return 1;
		}
		return x < y ? -1 : 1;
	}
	return 0;
}

// Newest release of the channel ('latest' or 'beta') as { tag, url }, cached.
// "force" ignores the cache (used by the manual "Check update" button).
// Rejects when GitHub cannot be reached or the answer is not what we expect.
async function getLatestRelease(channel, force) {
	const cacheKey = STORAGE_KEY_LATEST + '_' + channel;
	const now = Date.now();
	let cached = null;
	try {
		cached = JSON.parse(storageGet(cacheKey) || 'null');
	} catch (e) {
		cached = null;
	}

	if (!force && cached && typeof cached.time === 'number') {
		if (cached.failed) {
			if (now - cached.time < RELEASE_RETRY_DELAY) {
				throw new Error('Recent check failed');
			}
		} else if (now - cached.time < RELEASE_CACHE_TTL &&
		           VERSION_TAG_REGEX.test(cached.tag) &&
		           GITHUB_RELEASE_URL_REGEX.test(cached.url)) {
			return cached;
		}
	}

	try {
		const api = 'https://api.github.com/repos/AdguardTeam/AdGuardHome/releases' +
			(channel === 'beta' ? '?per_page=1' : '/latest');
		const ctrl = (typeof AbortController === 'function') ? new AbortController() : null;
		const timer = ctrl ? window.setTimeout(function() { ctrl.abort(); }, RELEASE_FETCH_TIMEOUT) : null;
		let res;
		try {
			res = await fetch(api, ctrl ? { signal: ctrl.signal } : undefined);
		} finally {
			if (timer) {
				window.clearTimeout(timer);
			}
		}
		if (!res.ok) {
			throw new Error('HTTP ' + res.status);
		}
		let data = await res.json();
		if (Array.isArray(data)) {
			data = data[0];
		}
		if (!data || typeof data.tag_name !== 'string' || !VERSION_TAG_REGEX.test(data.tag_name)) {
			throw new Error('Invalid version data');
		}
		const url = (typeof data.html_url === 'string' && GITHUB_RELEASE_URL_REGEX.test(data.html_url))
			? data.html_url
			: 'https://github.com/AdguardTeam/AdGuardHome/releases/tag/' + data.tag_name;
		const entry = { tag: data.tag_name, url: url, time: now };
		storageSet(cacheKey, JSON.stringify(entry));
		return entry;
	} catch (e) {
		storageSet(cacheKey, JSON.stringify({ failed: true, time: now }));
		throw e;
	}
}

// Hint appended to the "Current Version" row; onUpdate runs when "Update" is clicked.
// Built from DOM nodes only (no HTML strings).
function buildVersionHint(release, onUpdate) {
	return E('span', { 'id': 'agh-version-hint', 'style': 'margin-left: 12px;' }, [
		E('strong', { 'style': 'color: var(--warn-color-high, #d9822b);' },
			'→ ' + _('New version %s available').replace('%s', release.tag)),
		' ',
		E('a', { 'href': release.url, 'target': '_blank', 'rel': 'noopener noreferrer' }, _('Release notes')),
		' | ',
		E('a', {
			'href': '#',
			'click': function(ev) {
				ev.preventDefault();
				onUpdate();
			}
		}, _('Update'))
	]);
}

// Tighter spacing for the "Current Version" / "Service Status" rows. The themes
// give every row a lot of padding; !important is needed to win over them.
const STATUS_COMPACT_CSS =
	'.agh-status-row { margin: 0 !important; padding-top: 2px !important; padding-bottom: 2px !important; min-height: 0 !important; }' +
	'.agh-status-row .cbi-value-title, .agh-status-row .cbi-value-field { margin: 0 !important; padding-top: 0 !important; padding-bottom: 0 !important; min-height: 0 !important; line-height: 1.5 !important; }';

function findCoreUpdateTabLink(root) {
	return root.querySelector('a[href="#cbi-tab-adguardhome-core_update"]') ||
	       root.querySelector('a[href="#core_update"]') ||
	       root.querySelector('[data-tab="core_update"]');
}

// The Core Update tab only exists while "Core Update" is ticked in General Settings.
function isCoreUpdateTabEnabled(root) {
	const boxes = root.querySelectorAll('input[type="checkbox"]');
	for (let i = 0; i < boxes.length; i++) {
		if (boxes[i].id && boxes[i].id.endsWith('.enable_core_update')) {
			return boxes[i].checked;
		}
	}
	return false;
}

// Show the Core Update tab. If the tab is already available just switch to it;
// otherwise switch the toggle on (it lives in sessionStorage) and reload, so the
// tab is created and selected on the next load.
function goToCoreUpdateTab(root) {
	if (isCoreUpdateTabEnabled(root)) {
		const link = findCoreUpdateTabLink(root);
		if (link) {
			link.click();
			return;
		}
	}
	try {
		sessionStorage.setItem(STORAGE_KEY_CORE, '1');
		sessionStorage.setItem('agh_active_tab', 'core_update');
	} catch (e) {}
	window.location.reload();
}
// ---- END new-release notice --------------------------------------------------

function getServiceInfo(name) {
	const fn = rpc.declare({
		object: 'service',
		method: 'list',
		params: ['name'],
		expect: { [name]: { instances: { [name]: {} }}},
	});
	return function() {
		return fn(name);
	};
}

const getAGHServiceInfo = getServiceInfo('adguardhome');

async function getStatus() {
	try {
		const res = await getAGHServiceInfo();
		const isRunning = res && res.instances && res.instances.adguardhome && res.instances.adguardhome.running;
		return isRunning ? isRunning : false;
	} catch (e) {
		console.error(e);
		return false;
	}
}

function getStatusValue(isRunning) {
	return isRunning ? RUNNING_SPAN : NOT_RUNNING_SPAN;
}

async function getVersion() {
	try {
		const res = await fs.exec('/usr/bin/AdGuardHome', ['--version']);
		const version = res.stdout
			? (res.stdout.match(/version\s+(.*)/) || [null, res.stdout.trim()])[1]
			: '';
		return version;
	} catch (e) {
		console.error(e);
		return '';
	}
}

function updateStatus(node) {
	const output = node ? node.querySelector('output') : null;
	return output
		? async function() {
			const isRunning = await getStatus();
			dom.content(output, getStatusValue(isRunning));
		}
		: function() {};
}

function validateAbsolutePath(value) {
	if (!value.startsWith('/')) {
		return _('Path must be absolute.');
	}
	if (hasControlChars(value)) {
		return _('Path contains invalid characters.');
	}
	if (hasDotDotSegment(value)) {
		return _('Path must not contain "..".');
	}
	return true;
}

function validateConfigFile(_unused, value) {
	if (value == null || value === '') {
		return true;
	}
	const abs = validateAbsolutePath(value);
	if (abs !== true) {
		return abs;
	}
	if (value.endsWith('/')) {
		return _('Path must not end with a slash.');
	}
	if (PATH_REGEX.test(value)) {
		return _('Configuration file must be stored in its own directory, and not in \'/etc\'.');
	}
	return true;
}

function validateWorkDir(_unused, value) {
	if (value == null || value === '') {
		return true;
	}
	return validateAbsolutePath(value);
}

function normalizePath(value) {
	const p = value.replace(/\/+/g, '/');
	return (p.length > 1 && p.endsWith('/')) ? p.slice(0, -1) : p;
}

function validateJailMount(_unused, value) {
	if (value == null || value === '') {
		return true;
	}
	const abs = validateAbsolutePath(value);
	if (abs !== true) {
		return abs;
	}
	if (normalizePath(value) === '/') {
		return _('Mounting the whole root filesystem is not allowed.');
	}
	return true;
}

function validateJailMountRw(_unused, value) {
	const base = validateJailMount(_unused, value);
	if (base !== true || value == null || value === '') {
		return base;
	}
	if (DANGEROUS_RW_PATHS.indexOf(normalizePath(value)) !== -1) {
		return _('This directory must not be mounted read-write.');
	}
	return true;
}

function validateHashedPassword(_unused, value) {
	if (value == null || value === '') {
		return true;
	}
	if (!BCRYPT_REGEX.test(value)) {
		return _('The password has not been hashed yet. Click the calculate button first, then save.');
	}
	return true;
}

// Returns {host, port} that are safe to put into a URL, or null.
function parseListenAddress(address) {
	if (typeof address !== 'string') {
		return null;
	}
	const idx = address.lastIndexOf(':');
	if (idx < 0) {
		return null;
	}
	let host = address.slice(0, idx).replace(/^\[|\]$/g, '');
	const port = address.slice(idx + 1);

	if (!/^[0-9]{1,5}$/.test(port) || +port < 1 || +port > 65535) {
		return null;
	}
	if (host !== '' && !/^[A-Za-z0-9.\-]+$/.test(host) && !/^[0-9A-Fa-f:]+$/.test(host)) {
		return null;
	}
	return { host: host, port: port };
}

function formatUrlHost(host) {
	return host.indexOf(':') !== -1 ? '[' + host + ']' : host;
}

return view.extend({
	load: function() {
		return Promise.all([
			getStatus(),
			getVersion(),
			uci.load('adguardhome').then(function() {
				const sections = uci.sections('adguardhome', 'adguardhome');
				const sec = sections.length > 0 ? sections[0] : {};
				const configFile = sec.config_file || DEFAULT_CONFIG_FILE;
				return fs.read(configFile).catch(function() { return null; });
			})
		]);
	},

	render: async function(data) {
		const isRunning = data[0];
		const version = data[1];
		const yamlContent = data[2];

		const coreExists = Boolean(version);
		const installed = parseVersion(version);
		let dnsPort = '53';
		if (yamlContent) {
			const portMatches = yamlContent.match(/port:\s*(\d+)/g);
			if (portMatches && portMatches.length >= 2) {
				const actualPort = portMatches[1].match(/\d+/);
				if (actualPort) {
					dnsPort = actualPort[0];
				}
			}
		}

		const sections = uci.sections('adguardhome', 'adguardhome');
		const savedChannel = (sections.length > 0 && sections[0].core_version === 'beta') ? 'beta' : 'latest';

		const map = new form.Map('adguardhome', _('AdGuard Home'));

		const statusSect = map.section(form.TypedSection, 'status');
		statusSect.anonymous = true;
		statusSect.cfgsections = function() { return ['status_section']; };

		const versionOpt = statusSect.option(form.DummyValue, '_version', _('Current Version'));
		versionOpt.cfgvalue = function() {
			return version
				? esc(version)
				: '<span style="color: var(--error-color-high); font-weight: bold;">' + esc(_('Not installed')) + '</span>';
		};
		versionOpt.rawhtml = true;

		const statusOpt = statusSect.option(form.DummyValue, '_status', _('Service Status'));
		statusOpt.rawhtml = true;
		statusOpt.cfgvalue = function() { return getStatusValue(isRunning); };

		const mainSect = map.section(form.TypedSection, 'adguardhome');
		mainSect.anonymous = true;

		mainSect.tab('general', _('General Settings'));
		mainSect.tab('jail', _('File System Access'), _('Files and directories that AdGuard Home should have read-only or read-write access to.'));
		mainSect.tab('dns_redirect', _('Services Settings'));
		mainSect.tab('core_update', _('Core Update'), _('Settings and operations for updating the AdGuardHome core binary.'));
		mainSect.tab('advanced', _('Advanced Settings'), _('Go environment variables that tune garbage collector and memory management.') + ' ' + _('Modify at your own risk.'));

		const enabledOpt = mainSect.taboption('general', form.Flag, 'enabled', _('Enable'));
		enabledOpt.default = '0';
		enabledOpt.rmempty = false;
		if (!coreExists) {
			enabledOpt.description = '<span style="color: var(--error-color-high); font-weight: bold;">' + esc(_('Core binary not found. Enable the service to trigger an automatic download.')) + '</span>';
		}

		const configFileOpt = mainSect.taboption('general', form.Value, 'config_file', _('Configuration file'));
		configFileOpt.placeholder = DEFAULT_CONFIG_FILE;
		configFileOpt.validate = validateConfigFile;

		const workDirOpt = mainSect.taboption('general', form.Value, 'work_dir', _('Working directory'));
		workDirOpt.placeholder = DEFAULT_WORK_DIR;
		workDirOpt.validate = validateWorkDir;

		const userOpt = mainSect.taboption('general', form.Value, 'user', _('Service user'));
		userOpt.placeholder = DEFAULT_USER;

		const groupOpt = mainSect.taboption('general', form.Value, 'group', _('Service group'));
		groupOpt.placeholder = DEFAULT_GROUP;

		const verboseOpt = mainSect.taboption('general', form.Flag, 'verbose', _('Verbose logging'));
		verboseOpt.default = '0';

		const advSettingsOpt = mainSect.taboption('general', form.Flag, 'advanced_settings', _('Advanced Settings'));
		advSettingsOpt.default = '0';
		advSettingsOpt.rmempty = false;
		advSettingsOpt.load = function() { return sessionStorage.getItem(STORAGE_KEY) || '0'; };
		advSettingsOpt.remove = function() {};
		advSettingsOpt.write = function(_, value) { sessionStorage.setItem(STORAGE_KEY, value); };

		const coreUpdateToggleOpt = mainSect.taboption('general', form.Flag, 'enable_core_update', _('Core Update'), _('Show the tab and settings for updating the AdGuardHome core binary.'));
		coreUpdateToggleOpt.default = '0';
		coreUpdateToggleOpt.rmempty = false;
		coreUpdateToggleOpt.load = function() {
			if (sessionStorage.getItem('agh_active_tab') === 'core_update') {
				sessionStorage.setItem(STORAGE_KEY_CORE, '1');
			}
			return sessionStorage.getItem(STORAGE_KEY_CORE) || '0';
		};
		coreUpdateToggleOpt.remove = function() {};
		coreUpdateToggleOpt.write = function(_, value) { sessionStorage.setItem(STORAGE_KEY_CORE, value); };

		const jailRoOpt = mainSect.taboption('jail', form.DynamicList, 'jail_mount', _('Read-only access'));
		jailRoOpt.validate = validateJailMount;
		const jailRwOpt = mainSect.taboption('jail', form.DynamicList, 'jail_mount_rw', _('Read-write access'));
		jailRwOpt.validate = validateJailMountRw;

		const gcOpt = mainSect.taboption('advanced', form.Value, 'gc', 'GOGC');
		gcOpt.datatype = 'uinteger';
		gcOpt.depends('advanced_settings', '1');
		gcOpt.placeholder = DEFAULT_GOGC;
		gcOpt.retain = true;

		const maxProcsOpt = mainSect.taboption('advanced', form.Value, 'maxprocs', 'GOMAXPROCS');
		maxProcsOpt.datatype = 'uinteger';
		maxProcsOpt.depends('advanced_settings', '1');
		maxProcsOpt.placeholder = DEFAULT_GOMAXPROCS;
		maxProcsOpt.retain = true;

		const memLimitOpt = mainSect.taboption('advanced', form.Value, 'memlimit', 'GOMEMLIMIT');
		memLimitOpt.datatype = 'uinteger';
		memLimitOpt.depends('advanced_settings', '1');
		memLimitOpt.placeholder = DEFAULT_GOMEMLIMIT;
		memLimitOpt.retain = true;

		// ---- WebUI address / link ------------------------------------------
		let realHttpAddress = '0.0.0.0:3008';
		if (yamlContent) {
			const addrMatch = yamlContent.match(/address:\s*([^\s]+)/);
			if (addrMatch && addrMatch[1]) realHttpAddress = addrMatch[1];
		}

		// Everything that ends up in the link is validated; fall back to safe defaults.
		let linkHost = window.location.hostname;
		let linkPort = '3008';
		const parsedAddr = parseListenAddress(realHttpAddress);
		if (parsedAddr) {
			linkPort = parsedAddr.port;
			if (parsedAddr.host !== '' && parsedAddr.host !== '0.0.0.0' && parsedAddr.host !== '::') {
				linkHost = parsedAddr.host;
			}
		}
		const webuiUrl = 'http://' + formatUrlHost(linkHost) + ':' + linkPort;

		const isServiceEnabled = sections.length > 0 && sections[0].enabled === '1';
		const disabledHint = _('Service is disabled. Please go to "General Settings" to enable it.');

		const webuiBtnHtml = isServiceEnabled
			? '<a class="btn cbi-button cbi-button-link" style="font-weight:bold; display:inline-block; margin-top:5px;" href="' + esc(webuiUrl) + '" target="_blank" rel="noopener noreferrer">' + esc(_('Open AdGuardHome WebUI')) + '</a>'
			: '<span title="' + esc(disabledHint) + '" style="display:inline-block; margin-top:5px; cursor:not-allowed;">' +
					'<a class="btn cbi-button cbi-button-link" style="font-weight:bold; pointer-events:none; opacity:0.5; margin-top:0;" href="javascript:void(0);">' + esc(_('Open AdGuardHome WebUI')) + '</a>' +
			  '</span>';

		const listensOnAll = /^(0\.0\.0\.0|\[?::\]?):/.test(realHttpAddress);
		const exposureWarning = listensOnAll
			? '<br /><span style="color: var(--warn-color-high, #c60); font-weight: bold;">' +
				esc(_('The WebUI is served over plain HTTP and listens on all interfaces. Consider binding it to the LAN address.')) + '</span>'
			: '';

		const httpAddressOpt = mainSect.taboption('dns_redirect', form.Value, 'http_address', _('WebUI listener (address:port)'), '<br />' + webuiBtnHtml + exposureWarning);
		httpAddressOpt.placeholder = '0.0.0.0:3008';
		httpAddressOpt.default = '0.0.0.0:3008';
		httpAddressOpt.datatype = 'hostport';
		httpAddressOpt.rmempty = false;
		httpAddressOpt.cfgvalue = function() { return realHttpAddress; };

		// ---- password -------------------------------------------------------
		const isPasswordEmpty = yamlContent ? /password:[ \t]*(\r?\n|$)/.test(yamlContent) : false;
		const hashPassOpt = mainSect.taboption('dns_redirect', form.Value, 'hashpass', _('Change password'), esc(_('Enter the password here. Click the Load calculate Module button below and go on.')) + '<br /><button class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-calc-hash" style="display:inline-block; margin-top:5px;">' + esc(_(' ... Load calculate Module ... ')) + '</button>');
		hashPassOpt.default = '';
		hashPassOpt.datatype = 'string';
		hashPassOpt.password = true;
		hashPassOpt.rmempty = true;
		hashPassOpt.placeholder = isPasswordEmpty ? _('Please create a new password.') : '';
		hashPassOpt.cfgvalue = function() { return ''; };
		// Refuse to save anything that is not a bcrypt hash, so a plaintext
		// password can never end up in the UCI config.
		hashPassOpt.validate = validateHashedPassword;

		const redirectOpt = mainSect.taboption('dns_redirect', form.ListValue, 'redirect', dnsPort + ' ' + _('Redirect'), _('AdGuardHome redirect mode'));
		redirectOpt.value('none', _('No redirect'));
		redirectOpt.value('dnsmasq-upstream', _('As the upstream server of dnsmasq'));
		redirectOpt.value('redirect', _('Redirect port 53 to AdGuardHome'));
		redirectOpt.value('exchange', _('Use port 53 to replace dnsmasq'));
		redirectOpt.default = 'none';
		redirectOpt.rmempty = false;

		// ---- core update ----------------------------------------------------
		const coreVersionOpt = mainSect.taboption('core_update', form.ListValue, 'core_version', _('Core Branch'), _('Select the branch for the core binary update.'));
		coreVersionOpt.value('latest', _('Latest Version'));
		coreVersionOpt.value('beta', _('Beta Version'));
		coreVersionOpt.default = 'latest';
		coreVersionOpt.depends('enable_core_update', '1');
		coreVersionOpt.retain = true;

		// The option stores a fixed key; update_core.sh maps it to the real URL.
		const coreUrlOpt = mainSect.taboption('core_update', form.ListValue, 'update_source', _('Update URL'), _('Select the download source for the core update. Downloads are verified against the SHA-256 checksums published with the GitHub release.'));
		coreUrlOpt.value('official', _('Official Mirror (AdTidy - Recommended)'));
		coreUrlOpt.value('github', _('GitHub Releases (Original)'));
		coreUrlOpt.default = 'official';
		coreUrlOpt.rmempty = false;
		coreUrlOpt.depends('enable_core_update', '1');
		coreUrlOpt.retain = true;
		// Show the right entry for configs written by older versions (which stored a full URL).
		coreUrlOpt.cfgvalue = function(section_id) {
			const cur = uci.get('adguardhome', section_id, 'update_source');
			if (UPDATE_SOURCES.indexOf(cur) !== -1) {
				return cur;
			}
			return isLegacyGithubUrl(uci.get('adguardhome', section_id, 'update_url')) ? 'github' : 'official';
		};
		coreUrlOpt.write = function(section_id, value) {
			if (UPDATE_SOURCES.indexOf(value) === -1) {
				value = 'official';
			}
			uci.set('adguardhome', section_id, 'update_source', value);
			uci.unset('adguardhome', section_id, 'update_url');
		};

		const updateActionOpt = mainSect.taboption('core_update', form.DummyValue, '_update_action', _('Action'));
		updateActionOpt.rawhtml = true;
		updateActionOpt.cfgvalue = function() {
			return '<div class="cbi-value-description" style="display: flex; align-items: center; flex-wrap: wrap; gap: 8px;">' +
				'<input class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-action" value="' + esc(_('Check update')) + '" />' +
				'<input class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-force" value="' + esc(_('Force update')) + '" style="display: none;" />' +
				'<span id="btn-agh-detail" style="font-weight: bold;"></span>' +
			'</div>';
		};
		updateActionOpt.depends('enable_core_update', '1');

		const rendered = await map.render();

		// Look elements up inside our own tree: it may not be attached to the document
		// yet when the background release check finishes.
		const byId = function(id) {
			return rendered.querySelector('#' + id);
		};

		if (sessionStorage.getItem('agh_active_tab') === 'core_update') {
			sessionStorage.removeItem('agh_active_tab');
			window.location.hash = 'core_update';
			window.setTimeout(function() {
				const tabLink = findCoreUpdateTabLink(rendered);
				if (tabLink) tabLink.click();
			}, 50);
		}

		// Compact "Current Version" / "Service Status" rows.
		const versionRow = map.findElement('data-field', versionOpt.cbid('status_section'));
		const statusRow = map.findElement('data-field', statusOpt.cbid('status_section'));
		if (versionRow) versionRow.classList.add('agh-status-row');
		if (statusRow) statusRow.classList.add('agh-status-row');
		rendered.appendChild(E('style', {}, STATUS_COMPACT_CSS));

		const statusNode = map.findElement('data-field', statusOpt.cbid('status_section'));
		poll.add(updateStatus(statusNode), POLL_INTERVAL);

		let updatePollId = null;
		let currentState = 'init';

		// Channel ('latest' or 'beta') the Action button / version hint currently refer to.
		let detectedChannel = savedChannel;

		function setDetail(node) {
			const detail = byId('btn-agh-detail');
			if (detail) {
				dom.content(detail, node || '');
			}
		}

		// The channel selected in the Core Branch dropdown right now (saved one as fallback).
		function currentChannel() {
			try {
				const secId = sections.length > 0 ? sections[0]['.name'] : null;
				const v = secId ? coreVersionOpt.formvalue(secId) : null;
				if (CORE_VERSIONS.indexOf(v) !== -1) {
					return v;
				}
			} catch (err) {}
			return savedChannel;
		}

		// "Click to update" state, shared by the manual and the background check.
		// release.url is always a github.com/AdguardTeam/AdGuardHome/releases URL (see getLatestRelease).
		function showUpdatable(release) {
			const btnAction = byId('btn-agh-action');
			const btnForce = byId('btn-agh-force');

			currentState = 'updatable';
			if (btnAction) {
				btnAction.value = _('Click to update');
				btnAction.disabled = false;
			}
			if (btnForce) {
				btnForce.style.display = 'none';
			}
			setDetail(E('a', { 'href': release.url, 'target': '_blank', 'rel': 'noopener noreferrer' },
				E('em', { 'style': 'color: red;' }, release.tag)));
		}

		// Back to the initial "Check update" state.
		function resetToCheck() {
			const btnAction = byId('btn-agh-action');
			const btnForce = byId('btn-agh-force');

			currentState = 'init';
			if (btnAction) {
				btnAction.value = _('Check update');
				btnAction.disabled = false;
			}
			if (btnForce) {
				btnForce.style.display = 'none';
			}
			setDetail('');
		}

		// Show (release) or remove (null) the new-version hint after the version number.
		function setVersionHint(release) {
			const field = versionRow
				? (versionRow.querySelector('output') || versionRow.querySelector('.cbi-value-field'))
				: null;
			if (!field) {
				return;
			}
			const old = field.querySelector('#agh-version-hint');
			if (old) {
				old.remove();
			}
			if (release) {
				field.appendChild(buildVersionHint(release, function() {
					goToCoreUpdateTab(rendered);
				}));
			}
		}

		// Background check: if a newer release exists, show the hint and, while the Action
		// button is still untouched, go straight to "Click to update".
		function detectNewRelease(channel) {
			if (!coreExists || !installed) {
				return;
			}
			getLatestRelease(channel).then(function(release) {
				if (channel !== detectedChannel) {
					return;
				}
				const latest = parseVersion(release.tag);
				if (!latest || compareVersions(latest, installed) <= 0) {
					setVersionHint(null);
					return;
				}
				setVersionHint(release);
				if (currentState === 'init') {
					showUpdatable(release);
				}
			}).catch(function() {});
		}

		function startLogPolling() {
			if (updatePollId) clearInterval(updatePollId);

			window.onbeforeunload = function() {
				return _('Updating, are you sure to close?');
			};

			let displayPercent = 0;
			let targetPercent = 0;

			const pollAction = function() {
				const btnAction = byId('btn-agh-action');
				const btnForce = byId('btn-agh-force');

				if (currentState === 'updating') {
					if (displayPercent < targetPercent) {
						displayPercent = Math.min(targetPercent, displayPercent + Math.max(1, Math.ceil((targetPercent - displayPercent) / 3)));
					} else if (displayPercent < 95) {
						targetPercent = Math.min(95, targetPercent + 2);
						displayPercent = Math.min(targetPercent, displayPercent + 1);
					}
					if (btnAction) {
						btnAction.value = _('Updating...') + ' ' + displayPercent + '%';
					}
				}

				fs.read('/tmp/AdGuardHome_update.log').then(function(txt) {
					if (txt && currentState === 'updating') {
						// curl's progress bar redraws with \r, so split on both \r and \n.
						const lines = txt.split(/[\r\n]+/);
						let foundPercent = null;
						for (let i = lines.length - 1; i >= 0; i--) {
							const line = lines[i];
							const pctMatch = line.match(/(\d{1,3})(?:\.\d+)?\s*%/);
							if (pctMatch) {
								const p = parseInt(pctMatch[1], 10);
								if (p >= 0 && p <= 100) {
									foundPercent = p;
									break;
								}
							}
						}

						if (foundPercent !== null && foundPercent > targetPercent) {
							targetPercent = foundPercent;
						}
					}
				}).catch(function() {});

				Promise.all([
					fs.stat('/var/run/update_core').catch(function() { return null; }),
					fs.stat('/var/run/update_core_done').catch(function() { return null; }),
					fs.stat('/var/run/update_core_error').catch(function() { return null; })
				]).then(function(results) {
					const isDone = results[1];
					const isError = results[2];

					if (isDone) {
						clearInterval(updatePollId);
						fs.remove('/var/run/update_core_done').catch(function() {});
						window.onbeforeunload = undefined;
						currentState = 'success';

						displayPercent = 100;
						if (btnAction) {
							btnAction.value = _('Updating...') + ' 100%';
							btnAction.disabled = true;
						}

						window.setTimeout(function() {
							if (btnAction) {
								btnAction.value = _('Update successful');
							}
							if (btnForce) btnForce.style.display = 'none';
							setDetail('');

							sessionStorage.setItem('agh_active_tab', 'core_update');
							sessionStorage.setItem(STORAGE_KEY_CORE, '1');
							window.location.hash = 'core_update';

							window.setTimeout(function() {
								window.location.reload();
							}, 800);
						}, 300);

					} else if (isError) {
						clearInterval(updatePollId);
						window.onbeforeunload = undefined;
						currentState = 'failed';
						if (btnAction) {
							btnAction.value = _('Retry');
							btnAction.disabled = false;
						}
						if (btnForce) {
							btnForce.style.display = 'inline-block';
							btnForce.disabled = false;
						}
						setDetail(E('span', { 'style': 'color: red;' }, _('Update failed')));
					}
				});
			};

			pollAction();
			updatePollId = setInterval(pollAction, 250);
		}

		function triggerCheck() {
			const btnAction = byId('btn-agh-action');
			const btnForce = byId('btn-agh-force');

			currentState = 'checking';
			if (btnAction) {
				btnAction.value = _('Checking...');
				btnAction.disabled = true;
			}
			setDetail('');

			const channel = currentChannel();
			getLatestRelease(channel, true).then(function(release) {
				detectedChannel = channel;
				const latest = parseVersion(release.tag);

				if (!coreExists || !installed || !latest || compareVersions(latest, installed) > 0) {
					showUpdatable(release);
					setVersionHint(coreExists ? release : null);
				} else {
					currentState = 'latest';
					if (btnAction) {
						btnAction.value = _('It is the latest version');
						btnAction.disabled = true;
					}
					if (btnForce) {
						btnForce.style.display = 'inline-block';
						btnForce.disabled = false;
					}
					setDetail('');
					setVersionHint(null);
				}
			}).catch(function() {
				currentState = 'check_failed';
				if (btnAction) {
					btnAction.value = _('Retry');
					btnAction.disabled = false;
				}
				if (btnForce) {
					btnForce.style.display = 'none';
				}
				setDetail(E('em', { 'style': 'color: red;' }, _('Check failed')));
			});
		}

		function triggerUpdate(isForce) {
			const btnAction = byId('btn-agh-action');
			const btnForce = byId('btn-agh-force');

			currentState = 'updating';
			if (btnAction) {
				btnAction.disabled = true;
				btnAction.value = _('Updating...') + ' 0%';
			}
			if (btnForce) btnForce.disabled = true;

			// Pass the currently selected branch/source to the script as arguments
			// instead of staging them in UCI, so no "unsaved changes" are left behind.
			// Only whitelisted values are sent; the script validates them again.
			let wantVersion = '';
			let wantSource = '';
			try {
				const adguardSections = uci.sections('adguardhome', 'adguardhome');
				const secId = adguardSections.length > 0 ? adguardSections[0]['.name'] : null;
				if (secId) {
					const v = coreVersionOpt.formvalue(secId);
					const s = coreUrlOpt.formvalue(secId);
					if (CORE_VERSIONS.indexOf(v) !== -1) wantVersion = v;
					if (UPDATE_SOURCES.indexOf(s) !== -1) wantSource = s;
				}
			} catch (err) {
				console.error('Reading the selected update options failed:', err);
			}

			fs.exec('/usr/share/AdGuardHome/update_core.sh', [isForce ? 'force' : '', wantVersion, wantSource]).catch(function(err) {
				console.error('Failed to trigger update script:', err);
			});
			startLogPolling();
		}

		rendered.addEventListener('click', function(e) {
			if (e.target && (e.target.id === 'btn-agh-action' || e.target.id === 'btn-agh-force')) {
				e.preventDefault();
				e.stopPropagation();
				e.stopImmediatePropagation();

				if (e.target.id === 'btn-agh-action') {
					if (currentState === 'init' || currentState === 'check_failed') {
						triggerCheck();
					} else if (currentState === 'updatable' || currentState === 'failed') {
						triggerUpdate(false);
					}
				} else if (e.target.id === 'btn-agh-force') {
					triggerUpdate(true);
				}
			} else if (e.target && e.target.id === 'btn-agh-calc-hash') {
				e.preventDefault();
				e.stopPropagation();
				e.stopImmediatePropagation();

				const btn = e.target;
				const inputs = rendered.querySelectorAll('input[type="text"], input[type="password"]');
				let passInput = null;
				for (let i = 0; i < inputs.length; i++) {
					if (inputs[i].id && inputs[i].id.endsWith('.hashpass')) {
						passInput = inputs[i];
						break;
					}
				}
				if (!passInput) return;

				if (typeof window.TwinBcrypt === 'undefined') {
					btn.disabled = true;
					btn.textContent = _('Loading...');
					const script = document.createElement('script');
					script.src = L.resource('view/adguardhome/twin-bcrypt.min.js');
					script.type = 'text/javascript';
					script.onload = function() {
						btn.textContent = _('Click here to Calculate');
						btn.disabled = false;
					};
					script.onerror = function() {
						btn.textContent = _(' ... Load Error ... ');
						btn.disabled = false;
					};
					document.head.appendChild(script);
				} else {
					if (passInput.value) {
						// Only a complete, well-formed bcrypt hash counts as "already done".
						if (BCRYPT_REGEX.test(passInput.value)) {
							btn.textContent = _('Calculation already DONE !');
							return;
						}
						const hash = window.TwinBcrypt.hashSync(passInput.value);
						passInput.value = hash;
						passInput.dispatchEvent(new Event('input', { bubbles: true }));
						passInput.dispatchEvent(new Event('change', { bubbles: true }));
						btn.textContent = _(' ... Click Save/Apply ↘️ ... ');
					} else {
						btn.textContent = _(' ... Nothing inputted yet ... ');
					}
				}
			}
		});

		Promise.all([
			fs.stat('/var/run/update_core').catch(function() { return null; }),
			fs.stat('/var/run/update_core_error').catch(function() { return null; })
		]).then(function(results) {
			const isCore = results[0];
			const isError = results[1];
			if (isCore || isError) {
				const btnAction = byId('btn-agh-action');
				currentState = 'updating';
				if (btnAction) {
					btnAction.value = _('Updating...') + ' 0%';
					btnAction.disabled = true;
				}
				startLogPolling();
			}
		});

		// Background check for a newer release: it runs after the page is shown, never
		// delays it, and stays silent if GitHub cannot be reached.
		detectNewRelease(detectedChannel);

		// Changing the Core Branch dropdown invalidates what the Action button shows.
		rendered.addEventListener('change', function() {
			if (['init', 'updatable', 'latest', 'check_failed'].indexOf(currentState) === -1) {
				return;
			}
			const channel = currentChannel();
			if (channel === detectedChannel) {
				return;
			}
			detectedChannel = channel;
			resetToCheck();
			setVersionHint(null);
			detectNewRelease(channel);
		});

		return rendered;
	}
});
