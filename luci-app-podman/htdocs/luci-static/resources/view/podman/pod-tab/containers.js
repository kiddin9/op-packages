'use strict';

'require dom';
'require form';

'require podman.ui as podmanUI';
'require podman.view as podmanView';
'require podman.form as podmanForm';
'require podman.model.Container as Container';
'require podman.utils as podmanUtil';
'require podman.TableSelectSection as TableSelectSection';

return podmanView.tabContent.extend({
	tab: 'ps',
	pod: null,

	async render(pod) {
		this.pod = pod;

		const containers = [];

		for (const podContainer of this.pod.getContainers()) {
			const containerInspect = await Container.getSingleton(podContainer).inspect();
			const container = Container.getSingleton(containerInspect);
			containers.push(container);
		}

		this.map = new form.JSONMap({ containers }, '');

		this.section = this.map.section(
			TableSelectSection.TableSelectSection,
			'containers',
			'',
			''
		);
		this.section.view = this;
		this.section.anonymous = true;
		this.section.footer = true;

		this.section.selectKey = 'Id';
		// this.section.createForm = PodmanFormContainer;
		this.section.handleCreate = null;
		this.section.handleRemove = null;
		this.section.handleRefresh = null;

		// this.section.handleRefreshCb = () => this.checkInitScripts();
		// this.section.handleRefreshCb = null;
		// this.section.toolbarExtraButtons = [
		// 	new podmanUI.Button('&#9658;', ui.createHandlerFn(this, 'handleStart')).render(),
		// 	new podmanUI.Button('&#9724;', ui.createHandlerFn(this, 'handleStop')).render(),
		// 	new podmanUI.Button('&#8635;', ui.createHandlerFn(this, 'handleRestart')).render(),
		// ];

		let o;

		o = this.section.option(podmanForm.field.DummyValue, 'Names', _('Name'));
		o.cfgdatavalue = (container) => container.getName();

		o = this.section.option(podmanForm.field.DummyValue, 'Id', _('ID'));
		o.cfgdatavalue = (container) => container.getDetailLink(podmanUtil.truncate(container.getID(), 10));
		o.width = '12%';

		o = this.section.option(podmanForm.field.DummyValue, 'Image', _('Image'));
		o.cfgdatavalue = (container) => container.getImageName();
		o.width = '25%';

		o = this.section.option(podmanForm.field.DummyValue, 'ImageTag', _('Tag'));
		o.cfgdatavalue = (container) => container.getImageTag();
		o.cfgformatter = (imageTag) => podmanUtil.truncate(imageTag, 10);
		o.cfgtt = (imageTag) => imageTag.length > 10 ? imageTag : '';
		o.width = '11%';

		o = this.section.option(podmanForm.field.DummyValue, 'State', _('Status'));
		o.cfgdatavalue = (container) => container.getStateBadge();
		o.width = '8%';

		o = this.section.option(podmanForm.field.DummyValue, 'StartedAt', _('Started At'));
		o.cfgdatavalue = (container) => container.getStartedAt(true);
		o.width = '17%';

		o = this.section.option(podmanForm.field.DummyValue, 'InitScript', _('Boot'));
		o.cfgvalue = () => E('span', { class: 'autostart-status autostart-' }, '...');
		o.width = '6%';

		return this.map.render();
	},
});
