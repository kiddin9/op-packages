'use strict';

'require baseclass';
'require form';

'require podman.form as podmanForm';
'require podman.utils as podmanUtil';
'require podman.rpc as podmanRPC';
'require podman.view as podmanView';

const PodmanFormPod = podmanView.form.extend({
	__name__: 'Podman.Form.Pod',

	makeData() {
		return {
			pod: {
				name: '',
				hostname: null,
				share: ['cgroup', 'ipc', 'net', 'uts'],
				infra: '1',
				infra_image: null,
				network: 'bridge',
				dns_server: null,
				dns_search: null,
				cpus: null,
				cpuset_cpus: null,
				memory: null,
				labels: null,
			}
		};
	},

	async createForm() {
		const networks = await podmanRPC.networks.list();

		let field;

		field = this.section.option(form.Value, 'name', _('Pod Name'));
		field.placeholder = 'my-pod';
		field.optional = true;
		field.datatype = 'and(uciname,maxlength(63))';
		field.description = _('Leave empty to auto-generate');

		field = this.section.option(form.Value, 'hostname', _('Hostname'));
		field.placeholder = 'pod-host';
		field.optional = true;
		field.datatype = 'hostname';
		field.description = _('Hostname for the pod (defaults to pod name)');

		field = this.section.option(form.MultiValue, 'share', _('Shared Namespaces'));
		field.value('cgroup', 'cgroup');
		field.value('ipc', 'ipc');
		field.value('net', 'net');
		field.value('pid', 'pid');
		field.value('uts', 'uts');
		field.description = _('Linux namespaces shared between containers in the pod. Default matches `podman pod create`.');

		field = this.section.option(form.Flag, 'infra', _('Create Infra Container'));
		field.description = _('Required for shared network namespace. Disable only if you know you do not need it.');

		field = this.section.option(form.Value, 'infra_image', _('Infra Image'));
		field.depends('infra', '1');
		field.placeholder = 'k8s.gcr.io/pause:3.5';
		field.optional = true;
		field.description = _('Override the image used for the infra container');

		field = this.section.option(form.ListValue, 'network', _('Network'));
		field.depends('infra', '1');
		field.value('bridge', 'bridge (default)');
		field.value('host', 'host');
		field.value('none', 'none');
		networks.forEach((net) => {
			const name = net.getName();
			if (name && name !== 'bridge' && name !== 'host' && name !== 'none') {
				field.value(name, name);
			}
		});
		field.description = _('Network namespace for the pod. Containers in the pod share this network.');

		field = this.section.option(form.DynamicList, 'dns_server', _('DNS Servers'));
		field.depends('infra', '1');
		field.datatype = 'ipaddr';
		field.optional = true;
		field.description = _('DNS servers for the infra container (shared with all pod containers)');

		field = this.section.option(form.DynamicList, 'dns_search', _('DNS Search Domains'));
		field.depends('infra', '1');
		field.optional = true;
		field.description = _('DNS search domains for the infra container');

		field = this.section.option(form.Value, 'cpus', _('CPU Limit'));
		field.placeholder = '1.0';
		field.optional = true;
		field.datatype = 'ufloat';
		field.description = _('Number of CPUs available to the pod (e.g., 0.5, 1.0, 2.0)');

		field = this.section.option(form.Value, 'cpuset_cpus', _('CPU Set'));
		field.placeholder = '0-3';
		field.optional = true;
		field.description = _('CPUs the pod is allowed to run on (e.g., "0-3" or "0,2")');

		field = this.section.option(podmanForm.field.MemoryValue, 'memory', _('Memory Limit'));
		field.optional = true;
		field.description = _('Memory limit for the pod (e.g., 512m, 1g)');

		field = this.section.option(form.TextValue, 'labels', _('Labels'));
		field.placeholder = 'key1=value1\nkey2=value2';
		field.rows = 3;
		field.optional = true;
		field.description = _('One per line, format: key=value');
	},

	async handleCreate() {
		if (!this.isValid()) {
			return this.scrollToInvalid();
		}

		await this.save();

		const data = this.getFieldValues();
		const spec = {};

		if (data.name) spec.name = data.name;
		if (data.hostname) spec.hostname = data.hostname;

		const shareRaw = data.share;
		spec.share = Array.isArray(shareRaw)
			? shareRaw
			: (typeof shareRaw === 'string' && shareRaw.trim() ? shareRaw.trim().split(/\s+/) : []);

		const hasInfra = data.infra === '1';
		spec.infra = hasInfra;
		if (hasInfra && data.infra_image) spec.infra_image = data.infra_image;

		if (hasInfra) {
			if (data.network === 'host') {
				spec.netns = { nsmode: 'host' };
			} else if (data.network === 'none') {
				spec.netns = { nsmode: 'none' };
			} else if (data.network && data.network !== 'bridge') {
				spec.Networks = { [data.network]: {} };
			}

			if (data.dns_server && data.dns_server.length) spec.dns_server = data.dns_server;
			if (data.dns_search && data.dns_search.length) spec.dns_search = data.dns_search;
		}

		if (data.cpus) spec.cpus = parseFloat(data.cpus);
		if (data.cpuset_cpus) spec.cpuset_cpus = data.cpuset_cpus;

		if (data.memory) {
			const memBytes = podmanUtil.format.parseMemory(data.memory);
			if (memBytes > 0) {
				spec.resource_limits = { memory: { limit: memBytes } };
			}
		}

		if (data.labels) {
			spec.labels = {};
			data.labels.split('\n').forEach((line) => {
				const parts = line.split('=');
				if (parts.length >= 2) {
					const key = parts[0].trim();
					const value = parts.slice(1).join('=').trim();
					if (key) spec.labels[key] = value;
				}
			});
		}

		const createFn = () => podmanRPC.pods.create(spec);

		return this.super('handleCreate', [ createFn, _('Pod') ]);
	},
});

return baseclass.extend({
	init: PodmanFormPod
});
