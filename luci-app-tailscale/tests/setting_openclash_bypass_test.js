const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('htdocs/luci-static/resources/view/tailscale/setting.js', 'utf8');

function assert(value, message) {
	if (!value)
		throw new Error(message);
}

assert(source.includes("uci.load('tailscale_openclash')"), 'setting view must load the isolated OpenClash UCI package');
assert(source.includes("method: 'openclash_bypass_status'"), 'setting view must use the read-only status RPC');
assert(source.includes("uci.set('tailscale_openclash', 'settings', 'enabled'"), 'toggle must write only the isolated UCI package');
assert(!source.includes("uci.set('tailscale', section_id, 'openclash"), 'toggle must not write the core Tailscale UCI package');
assert(source.includes("_('Protect Tailscale Traffic (Bypass OpenClash)')"), 'toggle must explain that it protects Tailscale traffic');
assert(source.includes("_('Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash.')"), 'description must name the protected traffic and disabled impact');
assert(source.includes("_('Enabled; 4 bypass rules are active')"), 'active status must report the concrete rule state');
assert(source.includes("_('Disabled; Tailscale traffic is handled by OpenClash')"), 'disabled status must state the traffic impact');
assert(!source.includes("_('Enable OpenClash Bypass')"), 'old implementation-only toggle copy must be removed');
assert(!source.includes("_('Bypass OpenClash for Tailscale marked host traffic and traffic entering from tailscale0. This feature does not reload firewall4 or manage the OpenClash service.')"), 'old implementation-only description must be removed');

const loadMatch = source.match(/load\(\)\s*\{([\s\S]*?)\n\t\},\n\n\trender/);
assert(loadMatch, 'expected setting view to define a load() method');
assert(!loadMatch[1].includes('callOpenclashBypassStatus('), 'OpenClash status must not block initial page rendering');
assert(source.includes('refreshOpenclashBypassStatus'), 'status must refresh after render');

function createRuntime(openclashState = 'active') {
	const rpcDeclarations = [];
	const rpcCalls = [];
	const uciLoads = [];
	const uciSets = [];
	const scheduled = [];
	const maps = [];
	const lifecycle = [];
	const nodes = new Map();
	const statusNodes = [];
	const openclashUci = { enabled: '1' };
	const luciString = value => String(value);
	luciString.format = (format, ...values) => format.replace(/%s/g, () => values.shift());

	function textFrom(value) {
		if (Array.isArray(value))
			return value.map(textFrom).join('');
		if (value == null)
			return '';
		if (typeof value === 'object')
			return textFrom(value.children);
		return String(value);
	}

	function E(tag, attrs, children) {
		return {
			tag,
			attrs: attrs || {},
			children,
			textContent: textFrom(children)
		};
	}

	function registerNode(value) {
		if (Array.isArray(value)) {
			value.forEach(registerNode);
			return;
		}
		if (!value || typeof value !== 'object')
			return;

		const id = value.attrs && value.attrs.id;
		if (id) {
			nodes.set(id, value);
			if (id === 'openclash_bypass_status')
				statusNodes.push(value);
		}
		registerNode(value.children);
	}

	function Option(option) {
		this.option = option;
	}

	Option.prototype.depends = function() {};
	Option.prototype.value = function() {};
	Option.prototype.formvalue = function() {
		return this.map && this.map.formValues[this.option] || '';
	};
	Option.prototype.cbid = function(sectionId) { return sectionId + '.' + this.option; };

	function Section(map) {
		this.map = map;
		this.tabs = [];
		this.options = [];
	}

	Section.prototype.tab = function(tab) {
		this.tabs.push(tab);
	};

	Section.prototype.taboption = function(tab, Type, option, title, description) {
		const value = new Type(option);
		value.map = this.map;
		value.tab = tab;
		value.title = title;
		value.description = description;
		this.options.push(value);
		return value;
	};

	Section.prototype.option = function(Type, option) {
		const value = new Type(option);
		value.map = this.map;
		this.options.push(value);
		return value;
	};

	function FormMap(config) {
		this.config = config;
		this.sections = [];
		this.formValues = {};
		this.data = {
			save: async () => lifecycle.push('uci-save'),
			load: async () => lifecycle.push('uci-load')
		};
		maps.push(this);
	}

	FormMap.prototype.section = function() {
		const section = new Section(this);
		this.sections.push(section);
		return section;
	};

	FormMap.prototype.options = function() {
		return this.sections.flatMap(section => section.options);
	};

	FormMap.prototype.checkDepends = function() {
		lifecycle.push('depends');
	};

	FormMap.prototype.parse = async function() {
		lifecycle.push('parse');
		for (const option of this.options()) {
			if (Object.prototype.hasOwnProperty.call(this.formValues, option.option) && typeof option.write === 'function')
				await option.write('settings', this.formValues[option.option]);
		}
	};

	FormMap.prototype.load = async function() {
		lifecycle.push('load');
	};

	FormMap.prototype.renderContents = async function() {
		lifecycle.push('renderContents');
		nodes.clear();
		this.options().forEach(option => {
			if (typeof option.renderWidget === 'function')
				registerNode(option.renderWidget('settings', option.option));
		});
		return { map: this };
	};

	FormMap.prototype.render = function() {
		lifecycle.push('render');
		return this.renderContents();
	};

	const form = {
		Map: FormMap,
		TypedSection: Option,
		NamedSection: Option,
		Flag: Option,
		DummyValue: Option,
		Value: Option,
		ListValue: Option,
		DynamicList: Option,
		MultiValue: Option
	};
	form.Value.extend = properties => {
		function ExtendedOption(option) {
			Option.call(this, option);
		}
		ExtendedOption.prototype = Object.assign(Object.create(Option.prototype), properties);
		return ExtendedOption;
	};

	const context = {
		module: { exports: {} },
		console,
		Promise,
		Object,
		String: luciString,
		Array,
		Set,
		Error,
		_: value => value,
		E,
		form,
		fs: {},
		network: { getNetworks: async () => [] },
		poll: { add: () => {} },
		rpc: {
			declare: spec => {
				rpcDeclarations.push(spec);
				return async (...args) => {
					rpcCalls.push({ method: spec.method, args });
					if (spec.method === 'secret_status')
						return { authkey_set: '0', adguard_password_set: '0' };
					if (spec.method === 'openclash_bypass_status')
						return { state: openclashState };
					return {};
				};
			}
		},
		uci: {
			load: async config => {
				uciLoads.push(config);
			},
			get: (config, section, option) => {
				if (config === 'tailscale_openclash' && section === 'settings' && option === 'enabled')
					return openclashUci.enabled;
				return '';
			},
			set: (config, section, option, value) => {
				uciSets.push({ config, section, option, value });
				if (config === 'tailscale_openclash' && section === 'settings' && option === 'enabled')
					openclashUci.enabled = value;
				return Promise.resolve('uci-set');
			},
			sections: () => []
		},
		ui: { showModal: () => {}, hideModal: () => {} },
		document: {
			getElementById: id => nodes.get(id) || null
		},
		window: {
			setTimeout: (callback, delay) => {
				scheduled.push({ callback, delay });
				return scheduled.length;
			}
		}
	};

	const viewObject = vm.runInNewContext(`(function() {\n${source}\n})()`, Object.assign(context, {
		view: { extend: value => value }
	}));

	return {
		viewObject,
		rpcDeclarations,
		rpcCalls,
		uciLoads,
		uciSets,
		scheduled,
		maps,
		lifecycle,
		statusNodes,
		currentStatusNode: () => nodes.get('openclash_bypass_status')
	};
}

function scheduledOpenclashRefresh(runtime) {
	return runtime.scheduled.find(entry => entry.callback.name === 'refreshOpenclashBypassStatus');
}

(async () => {
	const runtime = createRuntime();
	const openclashStatusDeclaration = runtime.rpcDeclarations.find(spec => spec.method === 'openclash_bypass_status');
	assert(openclashStatusDeclaration, 'view must declare the OpenClash status RPC');
	assert(!openclashStatusDeclaration.params, 'OpenClash status RPC must not accept caller-controlled command arguments');

	const data = await runtime.viewObject.load();
	assert(runtime.uciLoads.includes('tailscale_openclash'), 'load() must read the isolated OpenClash UCI package');
	assert(!runtime.rpcCalls.some(call => call.method === 'openclash_bypass_status'), 'load() must not call OpenClash status RPC');

	await runtime.viewObject.render(data);
	assert(!runtime.rpcCalls.some(call => call.method === 'openclash_bypass_status'), 'render() must schedule, not await, OpenClash status RPC');
	const initialRefresh = scheduledOpenclashRefresh(runtime);
	const initialNode = runtime.currentStatusNode();
	assert(initialRefresh && initialRefresh.delay === 0, 'render() must queue the OpenClash status refresh immediately after rendering');
	assert(initialNode && initialNode.textContent === 'Checking ...', 'render() must create the initial OpenClash status node');
	await initialRefresh.callback();
	assert(initialNode.textContent === 'Enabled; 4 bypass rules are active', 'async status refresh must update the rendered status node');

	const map = runtime.maps.find(candidate => candidate.config === 'tailscale');
	const openclashOption = map.options().find(option => option.tab === 'openclash' && option.option === 'openclash_bypass_enabled');
	assert(openclashOption, 'render() must create the OpenClash bypass toggle in its own tab');
	assert(openclashOption.title === 'Protect Tailscale Traffic (Bypass OpenClash)', 'toggle must render the protection-focused title');
	assert(
		openclashOption.description === 'Keep Tailscale control connections, direct connections, Tailnet DNS, and subnet traffic outside OpenClash. When disabled, this traffic is handled by OpenClash; node connectivity, direct paths, subnet access, and internal DNS are no longer protected by this feature. Keep this enabled while using OpenClash.',
		'toggle must render the complete disabled-impact description'
	);
	assert(openclashOption.cfgvalue() === '1', 'toggle must read the isolated enabled value');

	const expectedStatuses = {
		active: 'Enabled; 4 bypass rules are active',
		waiting: 'Enabled; waiting for OpenClash nftables chains',
		disabled: 'Disabled; Tailscale traffic is handled by OpenClash',
		absent: 'OpenClash is not installed; bypass is not required',
		unsupported: 'Unsupported; firewall4/nftables is required',
		error: 'Configuration error'
	};
	for (const [state, expected] of Object.entries(expectedStatuses)) {
		const statusRuntime = createRuntime(state);
		const statusData = await statusRuntime.viewObject.load();
		await statusRuntime.viewObject.render(statusData);
		const refresh = scheduledOpenclashRefresh(statusRuntime);
		const node = statusRuntime.currentStatusNode();
		assert(refresh && node, `status ${state} must schedule a rendered refresh`);
		await refresh.callback();
		assert(node.textContent === expected, `status ${state} must render as: ${expected}`);
	}

	runtime.scheduled.length = 0;
	map.formValues.openclash_bypass_enabled = '0';
	await map.save(undefined, true);
	assert(runtime.lifecycle.includes('parse') && runtime.lifecycle.includes('uci-save') && runtime.lifecycle.includes('load') && runtime.lifecycle.includes('renderContents'), 'save() must run the form parse, UCI save, reload, and content render lifecycle');
	assert(
		runtime.uciSets.length === 1 && runtime.uciSets.every(call =>
			call.config === 'tailscale_openclash' &&
			call.section === 'settings' &&
			call.option === 'enabled' &&
			call.value === '0'
		),
		'actual map.save() must only write tailscale_openclash.settings.enabled'
	);

	const savedNode = runtime.currentStatusNode();
	const savedRefresh = scheduledOpenclashRefresh(runtime);
	assert(savedNode && savedNode !== initialNode && runtime.statusNodes.length === 2, 'save() must replace the status node during renderContents()');
	assert(savedNode.textContent === 'Checking ...', 'the replacement status node must start in checking state');
	assert(savedRefresh && savedRefresh.delay === 0, 'successful save() must queue a status refresh after renderContents()');
	await savedRefresh.callback();
	assert(savedNode.textContent === 'Enabled; 4 bypass rules are active', 'post-save refresh must update the replacement status node');

	console.log('setting OpenClash bypass tests passed');
})().catch(error => {
	console.error(error);
	process.exit(1);
});
