'use strict';

'require ui';

'require podman.rpc as podmanRPC';
'require podman.utils as podmanUtil';
'require podman.ui as podmanUI';

return podmanUI.Modal.extend({
	title: _('Cleanup Unused Resources'),

	getContent() {
		this.checkboxPruneAll = new ui.Checkbox(1, {
			hiddenname: 'prune-all-images'
		});
		this.checkboxPruneVolumes = new ui.Checkbox(0, {
			hiddenname: 'prune-volumes'
		});

		const pruneAllNode = this.checkboxPruneAll.render();
		const pruneVolumesNode = this.checkboxPruneVolumes.render();
		const pruneAllId = pruneAllNode.querySelector('input[type="checkbox"]').id;
		const pruneVolumesId = pruneVolumesNode.querySelector('input[type="checkbox"]').id;

		return E('div', {}, [
			E('p', {}, _('Select what to clean up:')),

			E('div', {
				class: 'd-flex align-center checkbox-with-label',
				style: 'margin-bottom: 2px;'
			}, [
				pruneAllNode,
				E('label', {
					for: pruneAllId
				}, _('Remove all unused images (not just dangling)')),
			]),

			E('div', {
				class: 'd-flex align-center checkbox-with-label'
			}, [
				pruneVolumesNode,
				E('label', {
					for: pruneVolumesId
				}, _('Remove unused volumes')),
			]),
		]);
	},

	getButtons() {
		return [
			this.getCloseButton(),
			new podmanUI.ButtonNew(_('Clean Up Now'), {
				click: ui.createHandlerFn(this, 'handlePrune'),
				type: 'positive',
			}).render()
		];
	},

	async handlePrune() {
		const allImages = this.checkboxPruneAll.getValue() === '1';
		const volumes = this.checkboxPruneVolumes.getValue() === '1';
		podmanUI.showSpinningModal(_('Clean Up Now'), _(
			'Removing unused resources, please wait...'));

		const result = await podmanRPC.system.prune(allImages, volumes);
		let freedSpace = 0;
		const deletedItems = [];

		const reportTypes = [{
				key: 'ContainerPruneReports',
				label: _('Containers')
			},
			{
				key: 'ImagePruneReports',
				label: _('Images')
			},
			{
				key: 'VolumePruneReports',
				label: _('Volumes')
			}
		];

		reportTypes.forEach((type) => {
			const reports = result[type.key];
			if (reports && reports.length > 0) {
				reports.forEach((r) => {
					if (r.Size > 0) freedSpace += r.Size;
				});
				deletedItems.push('%d %s'.format(reports.length, type.label
				.toLowerCase()));
			}
		});

		const modal = new podmanUI.Modal(_('Cleanup Complete'));
		modal.handleClose = null;
		modal.handleSubmit = () => {
			ui.hideModal();
			window.location.reload();
		};
		modal.content = [
			E('p', {}, _('Cleanup successful!')),
		];

		if (deletedItems.length > 0) {
			modal.content.push(E('p', {
				class: 'mt-sm'
			}, _('Removed: %s').format(deletedItems.join(', '))));
		} else {
			modal.content.push(E('p', {
				class: 'mt-sm'
			}, _('No unused resources found')));
		}

		modal.content.push(E('p', {
			class: 'mt-sm text-success text-bold'
		}, _('Space freed: %s').format(podmanUtil.format.bytes(freedSpace))));

		modal.render();
	},
});
