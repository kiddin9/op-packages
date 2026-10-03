'use strict';

'require ui';

'require podman.rpc as podmanRPC';
'require podman.ui as podmanUI';
'require podman.model.Container as Container';

return podmanUI.Modal.extend({
	title: _('Auto Update'),
	containers: [],
	buttons: [],

	getContent() {
		if (!this.containers || this.containers.length === 0) {
			this.buttons = [ this.getCloseButton() ];
			return [
				E('p', {}, _('No containers with auto-update label found.')),
				E('p', { class: 'mt-sm' },
					_('To enable auto-update for a container, add the label: io.containers.autoupdate=registry')
				),
			];
		}

		this.buttons = [
			this.getCloseButton(),
			new podmanUI.ButtonNew(_('Check'), {
				click: ui.createHandlerFn(this, 'handleCheckUpdate'),
				type: 'positive',
			}).render()
		];

		return [
			E('p', {}, _('Check %d containers for updates?').format(this.containers.length))
		];
	},

	setContainers(containers) {
		this.containers = containers ?? [];
		return this;
	},

	getButtons() {
		return this.buttons;
	},

	getCloseButton() {
		return new podmanUI.ButtonNew(_('Close'), {
			click: () => ui.hideModal(),
			type: 'remove',
		}).render();
	},

	async handleCheckUpdate() {
		const containersWithUpdates = [];
		const checkErrors = [];

		for (const [index, container] of this.containers.entries()) {
			podmanUI.showSpinningModal(null, _('Check for updates: %s/%s').format(index + 1, this.containers.length));

			const updateState = await container.checkImageUpdate();
			if (updateState.hasUpdate) {
				containersWithUpdates.push(container);
			} else if (updateState.error) {
				checkErrors.push({ name: container.getName(), error: updateState.error });
			}
		}

		if (containersWithUpdates.length === 0) {
			const content = [ E('p', {}, _('No new updates available.')) ];
			if (checkErrors.length > 0) {
				content.push(E('p', { class: 'mt-sm' }, _('%d check(s) failed:').format(checkErrors.length)));
				checkErrors.forEach((e) => content.push(E('p', { class: 'text-error' }, `${e.name}: ${e.error}`)));
			}
			const modal = new podmanUI.Modal(_('Check Complete'), content);
			modal.getButtons = () => [ this.getCloseButton() ];
			modal.render();
			return;
		}

		const updateContent = [
			E('p', {}, _('Select containers to update')),
		];

		const checkboxes = {};
		containersWithUpdates.forEach((container) => {
			const skipReason = container.getUpdateSkipReason();
			const checkbox = new ui.Checkbox(0);
			const checkboxNode = checkbox.render();
			const checkboxInputNode = checkboxNode.querySelector('input[type="checkbox"]');
			const checkboxId = checkboxInputNode.id;

			if (skipReason) {
				checkboxInputNode.disabled = true;
			} else {
				checkboxes[container.getID()] = { container, checkbox };
			}

			const inner = skipReason
				? new podmanUI.Tooltip(checkboxNode, skipReason).render()
				: checkboxNode;

			updateContent.push(E('div', { class: 'd-flex align-center checkbox-with-label mb-xs' }, [
				inner,
				E('label', { for: checkboxId }, container.getName()),
			]));
		});

		const modal = new podmanUI.Modal(_('Apply Updates'), updateContent);
		modal.getButtons = () => [
			this.getCloseButton(),
			new podmanUI.ButtonNew(_('Update'), {
				click: async () => {
					const selectedUpdates = Object.values(checkboxes)
						.filter(({ checkbox }) => checkbox.isChecked())
						.map(({ container }) => container);

					if (selectedUpdates.length === 0) {
						return;
					}

					await this.handleUpdate(selectedUpdates);
				},
				type: 'positive',
			}).render()
		];
		modal.render();
	},

	async handleUpdate(containers) {
		const failures = [];
		const oldImages = [];

		const counterEl = E('strong', {}, '');
		const spinnerEl = E('div', { class: 'spinning' });
		const headerEl  = E('div', { class: 'd-flex align-center mb-sm gap-5' }, [
			counterEl,
			spinnerEl,
		]);
		const log = new podmanUI.StreamLog();

		const finalize = () => {
			ui.hideModal();
			if (failures.length === 0 && imageWarnings.length === 0) {
				podmanUI.alert(_('Containers updated successfully'), 'success', true);
				return;
			}
			const lines = [];
			if (failures.length > 0) {
				const succeeded = containers.length - failures.length;
				lines.push(E('p', {}, _('%d updated, %d failed:').format(succeeded, failures.length)));
				failures.forEach(f => lines.push(E('p', {}, `${f.name}: ${f.error}`)));
			} else {
				lines.push(E('p', {}, _('Containers updated successfully.')));
			}
			imageWarnings.forEach(w => lines.push(E('p', { class: 'mt-sm' }, w)));
			podmanUI.alert(lines, failures.length > 0 ? 'warning' : 'info');
		};

		const closeBtn = new podmanUI.ButtonNew(_('Close'), {
			click: () => finalize(),
			type: 'negative',
		}).render();
		closeBtn.disabled = true;

		const modal = new podmanUI.Modal(_('Apply Updates'), [ headerEl, log.render() ]);
		modal.getButtons = () => [ closeBtn ];
		modal.render();

		let imageWarnings = [];

		for (const [i, container] of containers.entries()) {
			counterEl.textContent = _('Update image: %d/%d - %s').format(i + 1, containers.length, container.getName());
			log.append('━━ ' + container.getName() + ' ━━\n');
			try {
				const inspected = Container.getSingleton(await container.inspect());
				const result = await inspected.updateImage((line) => log.append(line));
				if (result?.oldImage) oldImages.push({ image: result.oldImage });
			} catch (err) {
				const msg = err.message || String(err);
				log.append('✗ ' + msg + '\n');
				failures.push({ name: container.getName(), error: msg });
			}
			log.append('\n');
		}

		if (oldImages.length > 0) {
			counterEl.textContent = _('Cleaning up old images...');
			log.append('━━ ' + _('Cleaning up old images...') + ' ━━\n');

			const allContainers = await podmanRPC.containers.list('all=true').catch(() => []);
			const normalize = id => (id || '').replace(/^sha256:/, '').toLowerCase();
			const usedIds = new Set(allContainers.map(c => normalize(c.ImageID)));

			const seen = new Set();
			for (const { image } of oldImages) {
				const id = normalize(image.getID());
				if (seen.has(id)) continue;
				seen.add(id);

				if (usedIds.has(id)) {
					const warning = _('Old image still used by other containers');
					imageWarnings.push(warning);
					log.append('! ' + warning + '\n');
				} else {
					await image.remove();
					log.append('✓ ' + _('Removed old image %s').format(image.getID().substring(0, 12)) + '\n');
				}
			}
		}

		counterEl.textContent = _('Done.');
		spinnerEl.classList.remove('spinning');
		closeBtn.disabled = false;
	},
});
