'use strict';

'require dom';
'require ui';

'require podman.constants as constant';
'require podman.rpc as podmanRPC';
'require podman.utils as utils';
'require podman.ui as podmanUI';
'require podman.form as podmanForm';
'require podman.view as podmanView';
'require podman.form.container as PodmanFormContainer';

/**
 * Manage podman containers
 */
return podmanView.list.extend({
	sectionName: 'containers',

	title: _('Containers'),
	titleSingle: _('Container'),

	async load() {
		return podmanRPC.containers.list('all=true');
	},

	/**
	 * Update list section
	 */
	async updateSection() {
		this.section.selectKey = 'Id';
		this.section.createForm = PodmanFormContainer;
		this.section.handleRefreshCb = () => this.checkInitScripts();
		this.section.toolbarExtraButtons = [
			new podmanUI.Button(constant.ICON.START, ui.createHandlerFn(this, 'handleStart')).render(),
			new podmanUI.Button(constant.ICON.STOP, ui.createHandlerFn(this, 'handleStop')).render(),
			new podmanUI.Button(constant.ICON.RESTART, ui.createHandlerFn(this, 'handleRestart')).render(),
			new podmanUI.Button(constant.ICON.PAUSE, ui.createHandlerFn(this, 'handlePause')).render(),
		];

		let o;

		o = this.section.option(podmanForm.field.DummyValue, 'Names', _('Name'));

		o = this.section.option(podmanForm.field.DummyValue, 'Id', _('ID'));
		o.cfgdatavalue = (container) => container.getDetailLink(utils.truncate(container.getID(), 10));
		o.width = '12%';

		o = this.section.option(podmanForm.field.DummyValue, 'Image', _('Image'));
		o.cfgdatavalue = (container) => container.getImageName();
		o.width = '25%';

		o = this.section.option(podmanForm.field.DummyValue, 'ImageTag', _('Tag'));
		o.cfgdatavalue = (container) => container.getImageTag();
		o.cfgformatter = (imageTag) => utils.truncate(imageTag, 10);
		o.cfgtt = (imageTag) => imageTag.length > 10 ? imageTag : '';
		o.width = '11%';

		o = this.section.option(podmanForm.field.DummyValue, 'State', _('Status'));
		o.cfgdatavalue = (container) => container.getStateBadge();
		o.width = '8%';

		o = this.section.option(podmanForm.field.TimestampDummyValue, 'StartedAt', _('Started At'));
		o.width = '17%';

		o = this.section.option(podmanForm.field.DummyValue, 'InitScript', _('Boot'));
		o.cfgvalue = () => E('span', { class: 'autostart-status autostart-' }, '...');
		o.width = '6%';
	},

	transformMap(map) {
		this.checkInitScripts(map);
		return map;
	},

	async checkInitScripts(renderedTable) {
		const data = this.map.data.data;

		for (const [key, container] of Object.entries(data)) {
			const iconEl = (renderedTable || document)
				.querySelector(`tr[data-sid="${key}"] td[data-name="InitScript"] .autostart-status`);

			container.checkInitScript().then((initScriptStatus) => {
				let initScriptIcon = container.getAutoStartStatusIcon(initScriptStatus);

				if (initScriptStatus === 'missing') {
					initScriptIcon = new podmanUI.Tooltip(
						initScriptIcon,
						_('Start script missing\n\nClick to generate'),
						{
							class: 'border-0',
							click: ui.createHandlerFn(this, 'handleGenerateInitScript')
						}
					).render();
				} else if (initScriptStatus === 'disabled') {
					initScriptIcon = new podmanUI.Tooltip(initScriptIcon, _('Start script disabled'), { class: 'border-0' }).render();
				} else if (initScriptStatus === 'enabled') {
					initScriptIcon = new podmanUI.Tooltip(initScriptIcon, _('Start on boot'), { class: 'border-0' }).render();
				}

				if (iconEl) iconEl.replaceWith(initScriptIcon);
			}).catch(() => {});
		}
	},

	async handleGenerateInitScript(event) {
		const clickedIcon = event.target;
		const recordRow = dom.parent(clickedIcon, 'tr');
		const container = this.map.data.data[recordRow.getAttribute('data-sid')];

		await container.generateInitScript();
		await container.enableInitScript();

		this.section.handleRefresh();
	},

	handleStart() {
		return this.updateContainersStatus(
			(container) => container.isPaused() ? container.unpause() : container.start(),
			_('Start container')
		);
	},

	handleStop() {
		return this.updateContainersStatus((container) => container.stop(), _('Stop container'));
	},

	handleRestart() {
		return this.updateContainersStatus((container) => container.restart(), _('Restart container'));
	},

	handlePause() {
		return this.updateContainersStatus((container) => container.pause(), _('Pause container'));
	},

	async updateContainersStatus(statusFunction, textLoad) {
		const section = this.getSection();
		const selected = section.getSelectedData();
		if (selected.length === 0) {
			return section.showNoneSelectedWarning();
		}

		for (const [i, container] of selected.entries()) {
			this.loading(_('%s: %d/%d').format(textLoad, i + 1, selected.length));
			await statusFunction(container);
		}

		ui.hideModal();
		section.handleRefresh();
	},
});
