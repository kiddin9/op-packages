'use strict';

'require baseclass';
'require form';
'require ui';

'require podman.ui as podmanUI';
'require podman.view as podmanView';
'require podman.model.Image as Image';

/**
 * Pull podman image
 */
const PodmanFormImage = podmanView.form.extend({
	__name__: 'Podman.Form.Image',

	makeData() {
		return {
			image: {
				registry: '',
				image: '',
			}
		};
	},

	createForm() {
		let field;

		field = this.section.option(form.ListValue, 'registry', _('Registry'));
		field.value('', 'docker.io');
		field.value('quay.io/', 'quay.io');
		field.value('ghcr.io/', 'ghcr.io');
		field.value('gcr.io/', 'gcr.io');

		field = this.section.option(form.Value, 'image', _('Image'));
		field.placeholder = 'nginx:latest';
		field.rmempty = false;
	},

	async handleCreate() {
		if (!this.isValid()) {
			return this.scrollToInvalid();
		}

		await this.save();

		const registry = this.getFieldValue('registry');
		const image = this.getFieldValue('image');

		const imageName = this.buildImageName(registry, image);
		const imageModel = Image.getSingleton({ RepoTags: [imageName] });

		const progressEl = E('pre', { class: 'terminal-area' });
		const modal = new podmanUI.Modal(_('Pulling %s').format(imageName), [ progressEl ]);

		/** @type {HTMLElement} */
		const closeButton = modal.getCloseButton();
		closeButton.classList.add('d-none');

		modal.getButtons = () => [ closeButton ];
		modal.render();

		const append = (text) => {
			progressEl.appendChild(document.createTextNode(text));
			progressEl.scrollTop = progressEl.scrollHeight;
		};

		try {
			await imageModel.streamPull(append);
			closeButton.classList.remove('d-none');
			podmanUI.alert(_('Image pulled successfully'), 'success', true);
		} catch (error) {
			this.error(error);
		}
	},

	buildImageName(registry, image) {
		const reg = (registry || '').trim();
		const img = (image || '').trim();

		if (!reg) {
			return img.includes('/') ? 'docker.io/' + img : 'docker.io/library/' + img;
		}

		return reg.replace(/\/+$/, '') + '/' + img.replace(/^\/+/, '');
	},
});

return baseclass.extend({
	init: PodmanFormImage
});
