'use strict';

'require baseclass';
'require form';

'require podman.utils as podmanUtil';
'require podman.form as podmanForm';
'require podman.view as podmanView';

/**
 * Update podman container resources
 */
const PodmanFormResource = podmanView.form.extend({
	__name__: 'Podman.Form.Resource',

	container: null,

	makeData() {
		if (!this.container) {
			return { resources: { cpuLimit: '', cpuShares: '', memory: '', memorySwap: '' } };
		}

		const hostConfig = this.container.getHostConfig();
		return {
			resources: {
				cpuLimit: hostConfig.CpuQuota > 0 ? (hostConfig.CpuQuota / 100000).toFixed(2) : '',
				cpuShares: hostConfig.CpuShares || '',
				memory: hostConfig.Memory > 0 ? podmanUtil.format.bytes(hostConfig.Memory, 0) : '',
				memorySwap: hostConfig.MemorySwap > 0 ? podmanUtil.format.bytes(hostConfig.MemorySwap, 0) : '',
			}
		};
	},

	async render(container) {
		this.container = container;

		return this.super('render', []);
	},

	createForm() {
		let field;

		field = this.section.option(form.Value, 'cpuLimit', _('CPU Limit'));
		field.datatype = 'ufloat';
		field.placeholder = '0.5, 1.0, 2.0';
		field.description = _('Number of CPUs (e.g., 0.5, 1.0, 2.0). Leave empty for unlimited.');

		field = this.section.option(form.Value, 'cpuShares', _('CPU Shares Weight'));
		field.datatype = 'uinteger';
		field.placeholder = '1024';
		field.validate = (_section_id, value) => {
			if (value) {
				const n = parseInt(value);
				if (n < 0 || n > 262144) return _('Must be between 0 and 262144');
			}
			return true;
		};
		field.description = _('CPU shares (relative weight). 0 = use default.');

		field = this.section.option(podmanForm.field.MemoryValue, 'memory', _('Memory Limit'));
		field.description = _('Memory limit (e.g., 512m, 1g). -1 = unlimited, 0 = use default.');

		field = this.section.option(podmanForm.field.MemoryValue, 'memorySwap', _('Memory + Swap Limit'));
		field.description = _('Total memory limit (memory + swap). -1 = unlimited, 0 = use default.');

		field = this.section.option(form.Button, '_update', ' ');
		field.inputtitle = _('Update Resources');
		field.inputstyle = 'save';
		field.onclick = () => this.handleUpdate();
	},

	async handleUpdate() {
		if (!this.isValid()) {
			return this.scrollToInvalid();
		}

		await this.save();

		const data = this.getFieldValues();
		const updateData = {
			cpu: {
				quota: 0,
				period: 0,
				shares: parseInt(data.cpuShares) || 0,
			},
		};

		const parseMemory = (val) =>
			(!val || val === '-1' || val === '0') ? -1 : podmanUtil.format.parseMemory(val);

		const memory = parseMemory(data.memory);
		const memorySwap = parseMemory(data.memorySwap);

		if (data.cpuLimit) {
			const period = 100000;
			updateData.cpu.quota = Math.floor(parseFloat(data.cpuLimit) * period);
			updateData.cpu.period = period;
		}

		updateData.memory = { limit: memory };
		if (memory === -1 || memorySwap === -1) {
			updateData.memory.swap = -1;
		} else if (memorySwap > 0) {
			updateData.memory.swap = memorySwap;
		} else {
			updateData.memory.swap = null;
		}

		const createFn = () => this.container.update(updateData);

		return this.super('handleCreate', [ createFn, _('Saving resource'), _('Updating container'), _('Container updated successfully') ]);
	},
});

return baseclass.extend({
	init: PodmanFormResource
});
