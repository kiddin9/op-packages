const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('htdocs/luci-static/resources/view/tailscale/setting.js', 'utf8');

function assert(condition, message) {
	if (!condition)
		throw new Error(message);
}

const loadMatch = source.match(/load\(\)\s*\{([\s\S]*?)\n\t\},\n\n\trender/);
assert(loadMatch, 'expected setting view to define a load() method');

assert(
	!loadMatch[1].includes('tailscale_adguard_dns_switch'),
	'setting load() must not block first render on AdGuard DNS preflight'
);

assert(
	source.includes('refreshAdguardPreflightStatus'),
	'setting view should refresh AdGuard DNS preflight status after initial render'
);

assert(source.includes("method: 'secret_status'"), 'setting view must load credential presence through a dedicated RPC');
assert(source.includes("method: 'set_secrets'"), 'setting view must atomically write all changed credentials through one RPC');
assert(source.includes("params: ['authkey_set', 'authkey', 'adguard_password_set', 'adguard_password', 'api_url', 'username', 'base_ref']"), 'credential staging must identify the secret version it extends');
assert(
	/load\(\)\s*\{\s*return callSecretStatus\(\)\.then/.test(source),
	'setting view must finish credential migration before loading the readable UCI configuration'
);
assert(!source.includes("uci.get('tailscale', 'settings', 'adguard_password')"), 'browser must never read the persisted AdGuard password');
assert(!source.includes("uci.get('tailscale', 'settings', 'authkey')"), 'browser must never read the persisted auth key');
assert(!source.includes("uci.set('tailscale', section_id, 'adguard_password'"), 'browser must not persist AdGuard passwords in readable UCI');
assert(!source.includes("uci.set('tailscale', section_id, 'authkey'"), 'browser must not persist auth keys in readable UCI');

const helperSource = source.split('return view.extend({')[0];

const candidateValues = {
	apiUrl: 'http://127.0.0.1:3001',
	username: 'candidate-user',
	password: 'candidate-password',
	keepPassword: false,
	defaultUpstreams: ['1.1.1.1', '8.8.8.8'],
	tailnetUpstreams: ['[/example.test/]100.100.100.100'],
	healthDomain: 'health.example.test',
	expectedIps: ['10.23.0.15', '10.23.0.16']
};

async function testEnablementWrite({ persistedEnabled, value, preflightResult, preflightError, candidateRequest, persistedRequest }) {
	const calls = [];
	const context = {
		module: { exports: {} },
		console,
		_: value => value,
		rpc: {
			declare: spec => {
				if (spec.object !== 'luci.tailscale')
					return function() {};
				return async (...args) => {
					calls.push({ type: 'rpc', object: spec.object, method: spec.method, args });
					if (preflightError)
						throw preflightError;
					return preflightResult || {};
				};
			}
		},
		fs: {},
		uci: {
			get: (config, section, option) => {
				calls.push({ type: 'get', config, section, option });
				return persistedEnabled ? '1' : '0';
			},
			set: (config, section, option, nextValue) => {
				calls.push({ type: 'set', config, section, option, value: nextValue });
				return 'set-result';
		}
	}
	};

	vm.runInNewContext(
		`${helperSource}\nmodule.exports = { buildAdguardPreflightRequest, writeAdguardDnsSwitchEnabled };`,
		context
	);

	const builtCandidateRequest = context.module.exports.buildAdguardPreflightRequest(
		persistedEnabled
			? { ...candidateValues, password: '', keepPassword: true }
			: candidateValues
	);

	let result;
	let error;
	try {
		result = await context.module.exports.writeAdguardDnsSwitchEnabled(
			'settings',
			value,
			candidateRequest || builtCandidateRequest,
			persistedRequest || Object.assign({}, builtCandidateRequest, { enabled: persistedEnabled ? '1' : '0' })
		);
	} catch (e) {
		error = e;
	}

	return { calls, result, error };
}

(async () => {
	let outcome = await testEnablementWrite({
		persistedEnabled: false,
		value: '1',
		preflightResult: { adguard_process: 'pass', health_check: 'fail', ready: 'fail' }
	});
	assert(outcome.calls.filter(call => call.type === 'rpc').length === 1, '0 -> 1 must run one fresh preflight RPC');
	const preflightCall = outcome.calls.find(call => call.type === 'rpc');
	assert(preflightCall.object === 'luci.tailscale' && preflightCall.method === 'adguard_preflight', 'preflight must use the dedicated Tailscale RPC method');
	assert(preflightCall.args[0] === '1', 'preflight RPC must opt into candidate configuration');
	assert(preflightCall.args[1] === candidateValues.apiUrl, 'preflight RPC must receive the candidate API URL');
	assert(preflightCall.args[4] === candidateValues.password, 'preflight RPC must receive a newly entered candidate password');
	assert(preflightCall.args[5] === '1.1.1.1\n8.8.8.8', 'preflight RPC must preserve candidate upstream list boundaries');
	assert(preflightCall.args[8] === '10.23.0.15\n10.23.0.16', 'preflight RPC must receive candidate expected IPs');
	assert(outcome.calls.every(call => call.type !== 'set'), 'failed initial enablement must not write the flag');
	assert(outcome.error && /status checks/i.test(outcome.error.message), 'failed initial enablement must reject save with a useful error');

	outcome = await testEnablementWrite({
		persistedEnabled: false,
		value: '1',
		preflightResult: { adguard_process: 'pass', health_check: 'pass', ready: 'pass' }
	});
	assert(outcome.calls.filter(call => call.type === 'rpc').length === 1, 'passing 0 -> 1 must still use a fresh preflight');
	assert(outcome.calls.some(call => call.type === 'set' && call.value === '1'), 'passing initial enablement must write the flag');
	assert(outcome.result === 'set-result', 'write hook must preserve the Promise-capable UCI write result');

	outcome = await testEnablementWrite({
		persistedEnabled: true,
		value: '1',
		preflightError: new Error('transient health failure')
	});
	assert(outcome.calls.every(call => call.type !== 'rpc'), 'unchanged already-enabled saves must not rerun or gate on preflight');
	assert(outcome.calls.some(call => call.type === 'set' && call.value === '1'), 'already-enabled saves must remain writable');

	const persistedRequest = Object.assign({}, vm.runInNewContext(
		`${helperSource}\nbuildAdguardPreflightRequest(${JSON.stringify({ ...candidateValues, password: '', keepPassword: true })})`,
		{
			module: { exports: {} },
			console,
			_: value => value,
			rpc: { declare: () => function() {} },
			fs: {},
			uci: {}
		}
	), { enabled: '1' });

	const changedEndpointWithoutPassword = Object.assign({}, persistedRequest, {
		api_url: 'http://changed.example:3000'
	});
	outcome = await testEnablementWrite({
		persistedEnabled: true,
		value: '1',
		candidateRequest: changedEndpointWithoutPassword,
		persistedRequest
	});
	assert(outcome.error && /password/i.test(outcome.error.message), 'changing a bound AdGuard endpoint must require the password again');
	assert(outcome.calls.every(call => call.type !== 'rpc' && call.type !== 'set'), 'missing replacement password must fail before preflight or UCI mutation');

	const changedEndpointWithPassword = Object.assign({}, changedEndpointWithoutPassword, {
		password_set: '1',
		password: 'replacement-password'
	});
	outcome = await testEnablementWrite({
		persistedEnabled: true,
		value: '1',
		candidateRequest: changedEndpointWithPassword,
		persistedRequest,
		preflightResult: { ready: 'pass' }
	});
	assert(outcome.calls.filter(call => call.type === 'rpc').length === 1, 'changed AdGuard endpoint with a replacement password must rerun preflight');
	assert(outcome.calls.some(call => call.type === 'set' && call.value === '1'), 'passing changed-endpoint preflight must save the enabled flag');

	const changedHealthDomain = Object.assign({}, persistedRequest, {
		health_domain: 'changed-health.example.test'
	});
	outcome = await testEnablementWrite({
		persistedEnabled: true,
		value: '1',
		candidateRequest: changedHealthDomain,
		persistedRequest,
		preflightResult: { ready: 'pass' }
	});
	assert(outcome.calls.filter(call => call.type === 'rpc').length === 1, 'changed AdGuard health configuration must rerun preflight');

	outcome = await testEnablementWrite({
		persistedEnabled: false,
		value: '0',
		preflightError: new Error('AdGuard unavailable')
	});
	assert(outcome.calls.every(call => call.type !== 'rpc'), 'disabled saves must not run preflight');
	assert(outcome.calls.some(call => call.type === 'set' && call.value === '0'), 'disabled saves must remain writable');

	const keepPasswordRequest = vm.runInNewContext(
		`${helperSource}\nbuildAdguardPreflightRequest(${JSON.stringify({ ...candidateValues, password: '', keepPassword: true })})`,
		{
			module: { exports: {} },
			console,
			_: value => value,
			rpc: { declare: () => function() {} },
			fs: {},
			uci: {}
		}
	);
	assert(keepPasswordRequest.password_set === '0', 'blank password must tell preflight to retain the persisted secret');
	assert(keepPasswordRequest.password === '', 'persisted password must not be copied into the browser RPC request');

	assert(
		source.includes('buildAdguardPreflightRequest({') && source.includes('writeAdguardDnsSwitchEnabled(section_id, value, candidateRequest, persistedAdguardConfig)'),
		'the AdGuard flag write hook must build candidate values from the live form before preflight'
	);

	const atomicContext = {
		module: { exports: {} },
		console,
		_: value => value,
		rpc: { declare: () => function() {} },
		fs: {},
		ui: { showModal: () => {} },
		uci: {},
		E: () => ({})
	};
	vm.runInNewContext(
		`${helperSource}\nmodule.exports = { buildSecretUpdateRequest, saveMapWithSecrets };`,
		atomicContext
	);
	const secretRequest = atomicContext.module.exports.buildSecretUpdateRequest({
		authkey: 'new-auth-key',
		adguardPassword: 'new-adguard-password',
		adguardApiUrl: 'https://adguard.example:3000',
		adguardUsername: 'root'
	});
	assert(secretRequest.authkey_set === '1' && secretRequest.adguard_password_set === '1', 'one atomic request must carry both changed credentials');
	const spacedPasswordRequest = atomicContext.module.exports.buildSecretUpdateRequest({
		adguardPassword: '  password with spaces  '
	});
	assert(spacedPasswordRequest.adguard_password === '  password with spaces  ', 'AdGuard passwords must preserve leading and trailing spaces');
	assert(!source.includes("String(adguardPasswordOption.formvalue(section_id) || '').trim()"), 'live AdGuard password input must not be trimmed before preflight');
	assert(source.includes("uci.set('tailscale', 'settings', 'secrets_ref'"), 'staged credentials must be activated through a UCI-managed version reference');
	assert(source.includes('saveInFlight'), 'concurrent Save and Save & Apply actions must share one in-flight save transaction');

	const saveCalls = [];
	const map = {
		checkDepends: () => saveCalls.push('depends'),
		parse: async () => saveCalls.push('parse'),
		data: { save: async () => saveCalls.push('uci-save') },
		load: async () => saveCalls.push('load'),
		renderContents: async () => saveCalls.push('render')
	};
	await atomicContext.module.exports.saveMapWithSecrets(
		map,
		undefined,
		true,
		async () => { saveCalls.push('stage'); return { ref: 'staged-ref' }; },
		async staged => saveCalls.push(`after:${staged.ref}`)
	);
	assert(saveCalls.join(',') === 'depends,parse,stage,uci-save,load,after:staged-ref,render', 'credentials must be staged before the UCI reference is saved and remain inactive until apply');

	let afterSaveCalled = false;
	const failingMap = {
		checkDepends: () => {},
		parse: async () => {},
		data: { save: async () => { throw new Error('uci save failed'); } },
		load: async () => {},
		renderContents: async () => {}
	};
	try {
		await atomicContext.module.exports.saveMapWithSecrets(
			failingMap,
			undefined,
			true,
			async () => ({ ref: 'orphaned-but-inactive-ref' }),
			async () => { afterSaveCalled = true; }
		);
	} catch (e) {}
	assert(!afterSaveCalled, 'failed UCI persistence must not report the staged credential reference as saved');

	let uciSaveCalled = false;
	const stageFailingMap = {
		checkDepends: () => {},
		parse: async () => {},
		data: { save: async () => { uciSaveCalled = true; } },
		load: async () => {},
		renderContents: async () => {}
	};
	try {
		await atomicContext.module.exports.saveMapWithSecrets(
			stageFailingMap,
			undefined,
			true,
			async () => { throw new Error('secret staging failed'); },
			async () => {}
		);
	} catch (e) {}
	assert(!uciSaveCalled, 'failed secret staging must not save a UCI reference or any other form changes');

	console.log('setting preflight tests passed');
})().catch(error => {
	console.error(error);
	process.exit(1);
});
