'use strict';

'require ui';
'require fs';

'require podman.utils as utils';
'require podman.rpc as podmanRPC';
'require podman.ui as podmanUI';
'require podman.form as podmanForm';
'require podman.view as podmanView';
'require podman.form.volume as PodmanFormVolume';
'require podman.form.volumeImport as PodmanFormVolumeImport';

const VOLUME_MOUNT_TRUNCATE_LEN = 30;

return podmanView.list.extend({
	sectionName: 'volumes',

	title: _('Volumes'),
	titleSingle: _('Volume'),

	async load() {
		return podmanRPC.volumes.list();
	},

	async updateSection() {
		this.section.selectKey = 'Name';
		this.section.createForm = PodmanFormVolume;
		this.section.toolbarExtraButtons = [
			new podmanUI.ButtonNew(_('Import'), {
				click: ui.createHandlerFn(this, 'handleImport'),
			}).render(),
			new podmanUI.ButtonNew(_('Export'), {
				click: ui.createHandlerFn(this, 'handleExport'),
			}).render(),
		];

		let o;

		o = this.section.option(podmanForm.field.LinkDummyValue, 'VolumeName', _('Name'));
		o.cfgdatavalue = (volume) => utils.truncate(volume.getName(), 20);
		o.cfgtt = (_cfg, volume) => volume.getName().length > 20 ? volume.getName() : '';
		o.click = (_cfg, volume) => this.section.handleInspect(volume);

		o = this.section.option(podmanForm.field.DummyValue, 'Driver', _('Driver'));
		o.width = '10%';

		o = this.section.option(podmanForm.field.DummyValue, 'Mountpoint', _('Mountpoint'));
		o.cfgformatter = (mountpoint) => utils.truncate(mountpoint, VOLUME_MOUNT_TRUNCATE_LEN);
		o.cfgtt = (mountpoint) => mountpoint.length > VOLUME_MOUNT_TRUNCATE_LEN ? mountpoint : '';
		o.width = '35%';

		o = this.section.option(podmanForm.field.DateDummyValue, 'CreatedAt', _('Created'));
		o.width = '20%';
	},

	handleImport() {
		const fileInput = E('input', {
			type: 'file',
			accept: '.tar,.tar.gz,.tgz',
			class: 'hidden'
		});

		fileInput.addEventListener('change', async (ev) => {
			document.body.removeChild(fileInput);
			const file = ev.target.files[0];
			if (!file) return;

			const importForm = new PodmanFormVolumeImport.init();
			const formContent = await importForm.render(file);
			const title = _('Import from archive: %s').format(file.name);
			const modal = new podmanUI.Modal(title, [ formContent ]);
			modal.getButtons = () => [
				modal.getCloseButton(),
				new podmanUI.ButtonNew(_('Import'), {
					click: async () => {
						await importForm.handleCreate();
						await this.section.handleRefresh();
					},
					type: 'positive',
				}).render(),
			];
			modal.render();
		});

		document.body.appendChild(fileInput);
		fileInput.click();
	},

	async handleExport() {
		const selected = this.section.getSelectedData();

		if (selected.length === 0) {
			return this.section.showNoneSelectedWarning();
		}

		let errors = 0;
		for (const [index, volume] of selected.entries()) {
			this.loading(_('Exporting selected volumes: %d/%d').format(index + 1, selected.length));

			const volumeName = volume.getName();
			try {
				const blob = await fs.exec_direct('/usr/libexec/podman-api', ['volume_export', volumeName], 'blob');

				const url = URL.createObjectURL(blob);
				const a = E('a', { href: url, download: `${volumeName}.tar` });
				document.body.appendChild(a);
				a.click();
				document.body.removeChild(a);
				setTimeout(() => URL.revokeObjectURL(url), 100);
			} catch (err) {
				podmanUI.alert(_('Error: %s').format(err.message), 'error');
				errors++;
			}
		}

		ui.hideModal();

		if (errors === 0)
			this.success(_('All volumes exported successfully'));
	},
});
