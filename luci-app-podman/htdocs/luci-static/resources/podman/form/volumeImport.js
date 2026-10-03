'use strict';

'require baseclass';
'require form';
'require request';

'require podman.rpc as podmanRPC';
'require podman.view as podmanView';

/**
 * Import podman volume
 */
const PodmanFormVolumeImport = podmanView.form.extend({
	__name__: 'Podman.Form.VolumeImport',

	sectionName: 'volume',

	isCompressed: false,
	file: null,

	makeData() {
		return {
			volume: {
				name: null,
			}
		};
	},

	async render(file) {
		this.file = file;

		return this.super('render', []);
	},

	createForm() {
		const isCompressed = this.file.name.endsWith('.tar.gz') || this.file.name.endsWith('.tgz');
		const volumeName = this.file.name.replace(/\.(tar\.gz|tgz|tar)$/, '');

		this.isCompressed = isCompressed;

		const field = this.section.option(form.Value, 'name', _('Volume Name'));
		field.placeholder = 'my-volume';
		field.rmempty = false;
		field.datatype = 'rangelength(1,253)';
		field.default = volumeName;
	},

	async handleCreate() {
		await this.save();

		const name = this.getFieldValue('name');

		this.loading(_('Uploading file...'));

		const formData = new FormData();
		formData.append('sessionid', L.env.sessionid);
		formData.append('filename', '/tmp/podman-import');
		formData.append('filedata', this.file);

		const response = await request.post(L.env.cgi_base + '/cgi-upload', formData);
		if (!response.ok) {
			this.error(_('Upload failed: %s').format(response.statusText));
			return;
		}

		this.loading(_('Importing volume...'));

		await podmanRPC.volumes.import(name, this.isCompressed);
		this.success(_('Volume imported successfully'));
	},
});

return baseclass.extend({
	init: PodmanFormVolumeImport,
});
