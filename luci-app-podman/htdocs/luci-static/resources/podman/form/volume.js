'use strict';

'require baseclass';
'require form';

'require podman.rpc as podmanRPC';
'require podman.view as podmanView';

/**
 * Create podman volume
 */
const PodmanFormVolume = podmanView.form.extend({
	__name__: 'Podman.Form.Volume',

	sectionName: 'volume',

	makeData() {
		return {
			volume: {
				name: null,
				driver: 'local',
				options: null,
				labels: null,
			}
		};
	},

	createForm() {
		let field;

		field = this.section.option(form.Value, 'name', _('Volume Name'));
		field.placeholder = 'my-volume';
		field.optional = true;
		field.datatype = 'maxlength(253)';
		field.description = _('Volume name. Leave empty to auto-generate.');

		field = this.section.option(form.ListValue, 'driver', _('Driver'));
		field.value('local', 'local');
		field.value('image', 'image');
		field.description = _('Volume driver to use');

		field = this.section.option(form.Value, 'options', _('Mount Options'));
		field.placeholder = 'type=tmpfs,device=tmpfs,o=size=100m';
		field.optional = true;
		field.description = _('Driver-specific options (comma-separated, e.g., type=tmpfs,o=size=100m)');

		field = this.section.option(form.TextValue, 'labels', _('Labels'));
		field.placeholder = 'key1=value1\nkey2=value2';
		field.rows = 3;
		field.optional = true;
		field.description = _('Labels in key=value format, one per line');
	},

	async handleCreate() {
		if (!this.isValid()) {
			return this.scrollToInvalid();
		}

		await this.save();

		const data = this.getFieldValues();
		const payload = {
			Name: data.name,
			Driver: data.driver,
		};

		if (data.options) {
			payload.Options = {};
			data.options.split(',').forEach((opt) => {
				const parts = opt.split('=');
				if (parts.length >= 2) {
					payload.Options[parts[0].trim()] = parts.slice(1).join('=').trim();
				}
			});
		}

		if (data.labels) {
			payload.Labels = {};
			data.labels.split('\n').forEach((line) => {
				const parts = line.split('=');
				if (parts.length >= 2) {
					const key = parts[0].trim();
					const value = parts.slice(1).join('=').trim();
					if (key) payload.Labels[key] = value;
				}
			});
		}

		const createFn = () => podmanRPC.volumes.create(payload);

		return this.super('handleCreate', [ createFn, _('Volume') ]);
	},
});

return baseclass.extend({
	init: PodmanFormVolume,
});
