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

const POLL_INTERVAL = 5;

const RUNNING_SPAN = `<span style="color: green; font-weight: bold">${_('Running')}</span>`;
const NOT_RUNNING_SPAN = `<span style="color: red; font-weight: bold">${_('Not running')}</span>`;

const STORAGE_KEY = 'luci-app-adguardhome';
const STORAGE_KEY_CORE = 'luci-app-adguardhome_core_update';

function getServiceInfo(name) {
	const fn = rpc.declare({
		object: 'service',
		method: 'list',
		params: ['name'],
		expect: { [name]: { instances: { [name]: {} }}},
	});
	return () => fn(name);
}

const getAGHServiceInfo = getServiceInfo('adguardhome');

async function getStatus() {
	try {
		const res = await getAGHServiceInfo();
		const isRunning = res?.instances?.adguardhome?.running;
		return isRunning ?? false;
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
	const output = node?.querySelector('output');
	return output
		? async () => {
			const isRunning = await getStatus();
			dom.content(output, getStatusValue(isRunning));
		}
		: () => {};
}

function validateConfigFile(_unused, value) {
	if (value == null || value === '') {
		return true;
	}
	if (!value.startsWith('/')) {
		return _('Path must be absolute.');
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
	if (!value.startsWith('/')) {
		return _('Path must be absolute.');
	}
	return true;
}

return view.extend({
	load() {
		return Promise.all([
			getStatus(),
			getVersion(),
			uci.load('adguardhome').then(() => {
				const sections = uci.sections('adguardhome', 'adguardhome');
				const sec = sections.length > 0 ? sections[0] : {};
				const configFile = sec.config_file || DEFAULT_CONFIG_FILE;
				return fs.read(configFile).catch(() => null);
			})
		]);
	},

	async render([isRunning, version, yamlContent]) {
		// If there is a version number, it means that the kernel exists. If there is no version number, it does not exist.
		const coreExists = Boolean(version);
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

		// 💡 Dynamic security value: UI rendering requires httpport to generate jump links
		const sections = uci.sections('adguardhome', 'adguardhome');
		const savedHttpPort = (sections.length > 0 && sections[0].httpport) ? sections[0].httpport : '3008';

		const map = new form.Map('adguardhome', _('AdGuard Home'));

		const statusSect = map.section(form.TypedSection, 'status');
		statusSect.anonymous = true;
		statusSect.cfgsections = () => ['status_section'];

		const versionOpt = statusSect.option(form.DummyValue, '_version', _('Version'));
		versionOpt.cfgvalue = () => version || `<span style="color: var(--error-color-high); font-weight: bold;">${_('Not installed')}</span>`;
        versionOpt.rawhtml = true;

		const statusOpt = statusSect.option(form.DummyValue, '_status', _('Service Status'));
		statusOpt.rawhtml = true;
		statusOpt.cfgvalue = () => getStatusValue(isRunning);

		const mainSect = map.section(form.TypedSection, 'adguardhome');
		mainSect.anonymous = true;

		mainSect.tab('general', _('General Settings'));
		mainSect.tab(
			'jail',
			_('File System Access'),
			_('Files and directories that AdGuard Home should have read-only or read-write access to.'),
		);
		mainSect.tab('dns_redirect', _('Services Settings'));
		mainSect.tab(
			'core_update',
			_('Core Update'),
			_('Settings and operations for updating the AdGuardHome core binary.')
		);
		mainSect.tab(
			'advanced',
			_('Advanced Settings'),
			_('Go environment variables that tune garbage collector and memory management.') +
				' ' + _('Modify at your own risk.'),
		);

		// ==== Move here: global switch ====
		const enabledOpt = mainSect.taboption(
			'general',
			form.Flag,
			'enabled',
			_('Enable')
		);
		enabledOpt.default = '0';
		enabledOpt.rmempty = false;
		// If the kernel does not exist, additional warning prompts will guide users to turn on the service to download automatically.
		if (!coreExists) {
			enabledOpt.description = `<span style="color: var(--error-color-high); font-weight: bold;">${_('Core binary not found. Enable the service to trigger an automatic download.')}</span>`;
		}

		const configFileOpt = mainSect.taboption(
			'general',
			form.Value,
			'config_file',
			_('Configuration file'),
			_('Configuration file must be stored in its own directory, and not in \'/etc\'.') +
				'<br />' + _('Parent directory will be owned by the service user.') +
				'<br />' + _('If empty, defaults to') + ` '${DEFAULT_CONFIG_FILE}'.`,
		);
		configFileOpt.placeholder = DEFAULT_CONFIG_FILE;
		configFileOpt.validate = validateConfigFile;

		const workDirOpt = mainSect.taboption(
			'general',
			form.Value,
			'work_dir',
			_('Working directory'),
			_('Directory where filters, logs, and statistics are stored.') +
				'<br />' + _('Will be owned by the service user.') +
				'<br />' + _('If empty, defaults to') + ` '${DEFAULT_WORK_DIR}'.`,
		);
		workDirOpt.placeholder = DEFAULT_WORK_DIR;
		workDirOpt.validate = validateWorkDir;

		const userOpt = mainSect.taboption(
			'general',
			form.Value,
			'user',
			_('Service user'),
			_('User the service runs under.') + ' ' + _('If empty, defaults to') +
				` '${DEFAULT_USER}'.`,
		);
		userOpt.placeholder = DEFAULT_USER;

		const groupOpt = mainSect.taboption(
			'general',
			form.Value,
			'group',
			_('Service group'),
			_('Group the service runs under.') + ' ' + _('If empty, defaults to') +
				` '${DEFAULT_GROUP}'.`,

		);
		groupOpt.placeholder = DEFAULT_GROUP;

		const verboseOpt = mainSect.taboption(
			'general',
			form.Flag,
			'verbose',
			_('Verbose logging'),
		);
		verboseOpt.default = '0';

		const advSettingsOpt = mainSect.taboption(
			'general',
			form.Flag,
			'advanced_settings',
			_('Advanced Settings'),
		);
		advSettingsOpt.default = '0';
		advSettingsOpt.rmempty = false;
		advSettingsOpt.load = () => sessionStorage.getItem(STORAGE_KEY) || '0';
		advSettingsOpt.remove = () => {};
		advSettingsOpt.write = (_, value) => sessionStorage.setItem(STORAGE_KEY, value);

		// ==== New: The switch of Core Update on General tab ====
		const coreUpdateToggleOpt = mainSect.taboption(
			'general',
			form.Flag,
			'enable_core_update',
			_('Core Update'),
			_('Show the tab and settings for updating the AdGuardHome core binary.')
		);
		coreUpdateToggleOpt.default = '0';
		coreUpdateToggleOpt.rmempty = false;
		coreUpdateToggleOpt.load = () => sessionStorage.getItem(STORAGE_KEY_CORE) || '0';
		coreUpdateToggleOpt.remove = () => {};
		coreUpdateToggleOpt.write = (_, value) => sessionStorage.setItem(STORAGE_KEY_CORE, value);
		// ==========================================

		mainSect.taboption('jail', form.DynamicList, 'jail_mount', _('Read-only access'));
		mainSect.taboption('jail', form.DynamicList, 'jail_mount_rw', _('Read-write access'));

		const gcOpt = mainSect.taboption(
			'advanced',
			form.Value,
			'gc',
			'GOGC',
			_('Tunes the garbage collector\'s aggressiveness by setting the percentage of heap ' +
				'growth allowed before the next collection cycle triggers.') + '<br />' +
				_('If empty, defaults to') + ' ' + _('unset and 100') + '.',
				'<a href="https://go.dev/doc/gc-guide#GOGC" target="_blank">https://go.dev/doc/gc-guide#GOGC</a>'
		);
		gcOpt.datatype = 'uinteger';
		gcOpt.depends('advanced_settings', '1');
		gcOpt.placeholder = DEFAULT_GOGC;
		gcOpt.retain = true;

		const maxProcsOpt = mainSect.taboption(
			'advanced',
			form.Value,
			'maxprocs',
			'GOMAXPROCS',
			_('The maximum number of operating system threads that can execute user-level Go code' +
				' simultaneously.') + '<br />' +
				_('If empty, defaults to') + ' ' + _('unset and matching the number of CPUs') + '.',
		);
		maxProcsOpt.datatype = 'uinteger';
		maxProcsOpt.depends('advanced_settings', '1');
		maxProcsOpt.placeholder = DEFAULT_GOMAXPROCS;
		maxProcsOpt.retain = true;

		const memLimitOpt = mainSect.taboption(
			'advanced',
			form.Value,
			'memlimit',
			'GOMEMLIMIT',
			_('A soft memory cap for the Go runtime, allowing the garbage collector to run more ' +
				'frequently as usage approaches the limit to prevent Out-of-Memory (OOM) kills.') +
				'<br />' +
				_('If empty, defaults to') + ' ' + _('unset') + '.',
		);
		memLimitOpt.datatype = 'uinteger';
		memLimitOpt.depends('advanced_settings', '1');
		memLimitOpt.placeholder = DEFAULT_GOMEMLIMIT;
		memLimitOpt.retain = true;

		// 💡 1. Extract the real listening address and port directly from YAML
		let realHttpAddress = '0.0.0.0:3008';
		if (yamlContent) {
			// Match the address: field below http: in YAML
			const addrMatch = yamlContent.match(/address:\s*([^\s]+)/);
			if (addrMatch && addrMatch[1]) {
				realHttpAddress = addrMatch[1];
			}
		}

		// 💡 2. Analyze the real IP and port used by the jump button
		let linkIp = window.location.hostname;
		let linkPort = '3008';
		const addrParts = realHttpAddress.split(':');
		if (addrParts.length >= 2) {
			linkPort = addrParts.pop();
			let ipPart = addrParts.join(':').replace(/\[|\]/g, '');
			// If the binding is a full zero address, the IP accessed by the current router will be returned.
			if (ipPart !== '0.0.0.0' && ipPart !== '') {
				linkIp = ipPart;
			}
		}

		// 💡 3. Upgrade the original httpport to http_address
		const isServiceEnabled = sections.length > 0 && sections[0].enabled === '1';
		const disabledHint = _('Service is disabled. Please go to "General Settings" to enable it.');

		// 💡 4. WebUI button HTML to construct intelligent state
		const webuiBtnHtml = isServiceEnabled
			? `<a class="btn cbi-button cbi-button-link" style="font-weight:bold; display:inline-block; margin-top:5px;" href="http://${linkIp}:${linkPort}" target="_blank">${_('Open AdGuardHome WebUI')}</a>`
			: `<span title='${disabledHint}' style="display:inline-block; margin-top:5px; cursor:not-allowed;">
					<a class="btn cbi-button cbi-button-link" style="font-weight:bold; pointer-events:none; opacity:0.5; margin-top:0;" href="javascript:void(0);">${_('Open AdGuardHome WebUI')}</a>
			   </span>`;

		// 💡 5. Rendering components
		const httpAddressOpt = mainSect.taboption(
			'dns_redirect',
			form.Value,
			'http_address',
			_('WebUI listener (address:port)'),
			_('Bind to specific interface:port (e.g., 0.0.0.0:3008). Leave as 0.0.0.0 to listen on all interfaces.') + 
			`<br />${webuiBtnHtml}`
		);
		httpAddressOpt.placeholder = '0.0.0.0:3008';
		httpAddressOpt.default = '0.0.0.0:3008';
		httpAddressOpt.datatype = 'hostport';
		httpAddressOpt.rmempty = false;

		// 🎯 Overwrite the default reading UCI behavior and forcibly echo the real value in YAML
		httpAddressOpt.cfgvalue = function(section_id) {
			return realHttpAddress;
		};

		// ==== Add the password modification function below the WebUI port ====
		const isPasswordEmpty = yamlContent ? /password:[ \t]*(\r?\n|$)/.test(yamlContent) : false;
		const hashPassOpt = mainSect.taboption(
			'dns_redirect',
			form.Value,
			'hashpass',
			_('Change password'),
			_('Enter the password here. Click the Load calculate Module button below and go on.') + 
			'<br /><button class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-calc-hash" style="display:inline-block; margin-top:5px;">' +
				_(' ... Load calculate Module ... ') + 
			'</button>'
		);
		hashPassOpt.default = '';
		hashPassOpt.datatype = 'string';
		hashPassOpt.password = true;
		hashPassOpt.rmempty = true;
		hashPassOpt.placeholder = isPasswordEmpty ? _('Please create a new password.') : '';
		hashPassOpt.cfgvalue = function(section_id) {
			return '';
		};

		const redirectOpt = mainSect.taboption(
			'dns_redirect',
			form.ListValue,
			'redirect',
			`${dnsPort} ` + _('Redirect'),
			_('AdGuardHome redirect mode')
		);
		redirectOpt.value('none', _('No redirect'));
		redirectOpt.value('dnsmasq-upstream', _('As the upstream server of dnsmasq'));
		redirectOpt.value('redirect', _('Redirect port 53 to AdGuardHome'));
		redirectOpt.value('exchange', _('Use port 53 to replace dnsmasq'));
		redirectOpt.default = 'none';
		redirectOpt.rmempty = false;
		// ==========================================

		// ======== Core Update Control content ========
		const coreVersionOpt = mainSect.taboption(
			'core_update',
			form.ListValue,
			'core_version',
			_('Core Branch'),
			_('Select the branch for the core binary update.')
		);
		coreVersionOpt.value('latest', _('Latest Version'));
		coreVersionOpt.value('beta', _('Beta Version'));
		coreVersionOpt.default = 'latest';
		coreVersionOpt.depends('enable_core_update', '1');
		coreVersionOpt.retain = true;

		const coreUrlOpt = mainSect.taboption(
			'core_update',
			form.ListValue,
			'update_url',
			_('Update URL'),
			_('Select the download link for the core update.')
		);
		coreUrlOpt.value('https://static.adtidy.org/adguardhome/release/AdGuardHome_linux_${Arch}.tar.gz', _('Official Mirror (AdTidy - Recommended)'));
		coreUrlOpt.value('https://github.com/AdguardTeam/AdGuardHome/releases/download/${Cloud_Version}/AdGuardHome_linux_${Arch}.tar.gz', _('GitHub Releases (Original)'));
		coreUrlOpt.default = 'https://static.adtidy.org/adguardhome/release/AdGuardHome_linux_${Arch}.tar.gz';
		coreUrlOpt.rmempty = false;
		coreUrlOpt.depends('enable_core_update', '1');
		coreUrlOpt.retain = true;

		const updateActionOpt = mainSect.taboption(
			'core_update',
			form.DummyValue,
			'_update_action',
			_('Action')
		);
		updateActionOpt.rawhtml = true;
		updateActionOpt.cfgvalue = () => `
			<div id="agh-update-controls" style="display: flex; gap: 10px; margin-bottom: 10px;">
				<button class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-update">${_('Update core version')}</button>
				<button class="btn cbi-button cbi-button-apply" type="button" id="btn-agh-force" style="display: none;">${_('Force update')}</button>
			</div>
			<div id="agh-update-log-container" style="display: none;">
				<textarea id="agh-update-log" class="cbi-input-textarea" style="width: 100%; display: block; font-family: monospace;" rows="10" readonly="readonly"></textarea>
			</div>
		`;
		updateActionOpt.depends('enable_core_update', '1');
		// ==========================================

		const rendered = await map.render();

		const statusNode = map.findElement('data-field', statusOpt.cbid('status_section'));
		poll.add(updateStatus(statusNode), POLL_INTERVAL);

		// ========== Update the status and polling logic =========
		let updatePollId = null;

		function startLogPolling() {
			if (updatePollId) clearInterval(updatePollId);
			const pollAction = () => {
				const btnU = document.getElementById('btn-agh-update');
				const btnF = document.getElementById('btn-agh-force');
				const logC = document.getElementById('agh-update-log-container');
				const logT = document.getElementById('agh-update-log');

				if (btnU) btnU.disabled = true;
				if (btnF) btnF.style.display = 'inline-block';
				if (logC) logC.style.display = 'block';

				fs.read('/tmp/AdGuardHome_update.log').then((txt) => {
					if (txt && logT) {
						logT.value = txt;
						logT.scrollTop = logT.scrollHeight;
					}
				}).catch(() => {});

				Promise.all([
					fs.stat('/var/run/update_core').catch(() => null),
					fs.stat('/var/run/update_core_done').catch(() => null),
					fs.stat('/var/run/update_core_error').catch(() => null)
				]).then(([isCore, isDone, isError]) => {
					if (isDone) {
						clearInterval(updatePollId);
						fs.remove('/var/run/update_core_done').catch(() => {});
						if (btnU) {
							btnU.disabled = false;
							btnU.textContent = _('Updated');
						}
					} else if (isError) {
						clearInterval(updatePollId);
						if (btnU) {
							btnU.disabled = false;
							btnU.textContent = _('Failed');
						}
					} else if (!isCore && !isDone && !isError) {
						clearInterval(updatePollId);
						if (btnU) {
							btnU.disabled = false;
							btnU.textContent = _('Already up-to-date');
						}
					}
				});
			};

			pollAction();
			updatePollId = setInterval(pollAction, 1500);
		}

		function applyUpdate(isForce) {
			const btnU = document.getElementById('btn-agh-update');
			const logC = document.getElementById('agh-update-log-container');
			const logT = document.getElementById('agh-update-log');
			if (btnU) {
				btnU.textContent = _('Checking...');
				btnU.disabled = true;
			}
			
			if (logC) logC.style.display = 'block';
			if (logT) logT.value = _('Checking and preparing...\n');
			
			map.save().then(() => {
				const arg = isForce ? 'force' : '';
				fs.exec('/usr/share/AdGuardHome/update_core.sh', [arg]).catch((err) => {
					console.error('Failed to trigger update script:', err);
				});
				startLogPolling();
			}).catch((err) => {
				console.error('Config save failed:', err);
				if (btnU) {
					btnU.textContent = _('Save Failed');
					btnU.disabled = false;
				}
			});
		}

		rendered.addEventListener('click', (e) => {
			if (e.target && e.target.id === 'btn-agh-update') {
				e.preventDefault();
				applyUpdate(false);
			} else if (e.target && e.target.id === 'btn-agh-force') {
				e.preventDefault();
				applyUpdate(true);
			} 
			// ==== Handle front-end hash encryption logic ====
			else if (e.target && e.target.id === 'btn-agh-calc-hash') {
				e.preventDefault();
				const btn = e.target;

				// Dynamically find the password input box on the page (matching elements with the suffix .hashpass)
				const inputs = rendered.querySelectorAll('input[type="text"], input[type="password"]');
				let passInput = null;
				for (const el of inputs) {
					if (el.id && el.id.endsWith('.hashpass')) {
						passInput = el;
						break;
					}
				}

				if (!passInput) return;

				// 1. If JS has not been loaded, it will be loaded dynamically.
				if (typeof window.TwinBcrypt === 'undefined') {
					btn.disabled = true;
					btn.textContent = _('Loading...');
					
					const script = document.createElement('script');
					script.src = L.resource('view/adguardhome/twin-bcrypt.min.js');
					script.type = 'text/javascript';
					
					script.onload = () => {
						btn.textContent = _('Click here to Calculate');
						btn.disabled = false;
					};
					script.onerror = () => {
						btn.textContent = _(' ... Load Error ... ');
						btn.disabled = false;
					};
					document.head.appendChild(script);
				} 
				// 2. If JS has been loaded, the calculation will be executed.
				else {
					if (passInput.value) {
						// Prevent repeated hashing of hashed strings (starting with $2a$ or $2y$)
						if (passInput.value.startsWith('$2a$') || passInput.value.startsWith('$2y$')) {
							btn.textContent = _('Calculation already DONE !');
							return;
						}
						
						const hash = window.TwinBcrypt.hashSync(passInput.value);
						passInput.value = hash;
						
						// Manually trigger native input and change events
						passInput.dispatchEvent(new Event('input', { bubbles: true }));
						passInput.dispatchEvent(new Event('change', { bubbles: true }));
						
						btn.textContent = _(' ... Click Save/Apply ↘️ ... ');
					} else {
						btn.textContent = _(' ... Nothing inputted yet ... ');
					}
				}
			}
			// ==========================================
		});

		Promise.all([
			fs.stat('/var/run/update_core').catch(() => null),
			fs.stat('/var/run/update_core_error').catch(() => null)
		]).then(([isCore, isError]) => {
			if (isCore || isError) {
				const btnU = document.getElementById('btn-agh-update');
				if (btnU) btnU.textContent = _('Checking...');
				startLogPolling();
			}
		});
		// ==========================================

		return rendered;
	},
});
