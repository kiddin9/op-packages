'use strict';

'require form';
'require ui';

'require podman.rpc as podmanRPC';
'require podman.utils as utils';
'require podman.ui as podmanUI';
'require podman.form as podmanForm';
'require podman.view as podmanView';
'require podman.form.image as PodmanFormImage';

const IMAGE_ID_TRUNCATE_LEN = 12;
const IMAGE_TAG_TRUNCATE_LEN = 14;

/**
 * Manage podman images
 */
return podmanView.list.extend({
	sectionName: 'images',

	title: _('Images'),
	titleSingle: _('Image'),

	async load() {
		return podmanRPC.images.list();
	},

	/**
	 * Update list section
	 */
	async updateSection() {
		this.section.selectKey = 'Id';
		this.section.handleCreateText = _('Pull Image');
		this.section.getCreateButton = function() {
			return new podmanUI.ButtonNew(_('Pull Image'), {
				click: ui.createHandlerFn(this, 'handleCreate'),
				type: 'add',
			}).render();
		};
		this.section.modalCreateTitle = _('Pull Image');
		this.section.createForm = PodmanFormImage;
		this.section.toolbarExtraButtons = [
			new podmanUI.Button(_('Update'), ui.createHandlerFn(this, 'handlePullImages')).render(),
		];

		let o;

		o = this.section.option(podmanForm.field.DummyValue, 'Repository', _('Repository'));
		o.cfgdatavalue = async (image) => image.getRepository();

		o = this.section.option(podmanForm.field.DummyValue, 'Tag', _('Tag'));
		o.cfgdatavalue = async (image) => {
			const tagValue = image.getTag();

			if (tagValue.length > IMAGE_TAG_TRUNCATE_LEN) {
				return new podmanUI.Tooltip(utils.truncate(tagValue, IMAGE_TAG_TRUNCATE_LEN), tagValue).render();
			}

			return tagValue;
		};
		o.width = '17%';

		o = this.section.option(podmanForm.field.LinkDummyValue, 'ImageId', _('Image ID'));
		o.click = (_value, image) => this.section.handleInspect(image);
		o.cfgdatavalue = (image) => utils.truncate(image.getID(), IMAGE_ID_TRUNCATE_LEN);
		o.width = '15%';

		o = this.section.option(podmanForm.field.ByteDummyValue, 'Size', _('Size'));
		o.width = '12%';

		o = this.section.option(podmanForm.field.TimestampDummyValue, 'Created', _('Created'));
		o.width = '18%';

		return this.map.render();
	},

	handlePullImages: async function () {
		const selected = this.section.getSelectedData();

		if (selected.length === 0) {
			return this.section.showNoneSelectedWarning();
		}

		const progressEl = E('pre', { class: 'terminal-area' });
		const modal = new podmanUI.Modal(_('Updating Images'), [ progressEl ]);

		/** @type {HTMLElement} */
		const closeButton = modal.getCloseButton();
		closeButton.classList.add('d-none');

		modal.getButtons = () => [ closeButton ];
		modal.render();

		const append = (text) => {
			progressEl.textContent += text;
			progressEl.scrollTop = progressEl.scrollHeight;
		};

		let errors = 0;
		let first = true;
		for (const image of selected) {
			if (!first) append('\n');
			first = false;
			try {
				await image.streamPull((text) => append(text));
			} catch (err) {
				podmanUI.alert(`${_('Error')}: ${err.message}`);
				errors++;
			}
		}

		this.section.handleRefresh();
		closeButton.classList.remove('d-none');
		if (errors === 0)
			podmanUI.alert(_('All images updated successfully'), 'success', true);
	},
});
