'use strict';

'require ui';
'require dom';

'require podman.constants as constant';
'require podman.ui as podmanUI';
'require podman.view as podmanView';
'require podman.model.Container as Container';
'require podman.form.resource as PodmanFormResource';

'require view.podman.container-tab.info as ContainerInfoTab';
'require view.podman.container-tab.stats as ContainerStatsTab';
'require view.podman.container-tab.processes as ContainerProcessesTab';
'require view.podman.container-tab.logs as ContainerLogsTab';

/**
 * Container detail view with tabbed interface
 */
return podmanView.container.extend({
	container: null,
	data: null,
	listUrl: L.url('admin/podman/containers'),

	async load() {
		// Extract container ID from URL path
		// URL format: /cgi-bin/luci/admin/podman/container/<id>
		const path = L.location();
		const matches = path.match(/container\/([a-f0-9]+)/i);

		if (!matches || !matches[1]) {
			this.redirectToList();
			return;
		}

		const containerId = matches[1];
		const container = Container.getSingleton({ Id: containerId });

		const inspectData = await container.inspect();
		this.data = inspectData;
		return Container.getSingleton(inspectData);
	},

	async render(container) {
		if (!container) {
			this.redirectToList();
			return;
		}

		this.container = container;
		this.tabs
			.addTab('info', _('Info'))
			.addTab('resources', _('Resources'))
			.addTab('stats', _('Stats'))
			.addTab('ps', _('Processes'))
			.addTab('logs', _('Logs'))
			// .addTab('health', _('Health'))
			.addTab('inspect', _('Inspect'))
			// .addTab('console', _('Console'))
		;

		requestAnimationFrame(() => {
			this.renderInfoTab();
			this.renderResourcesTab();
			this.renderStatsTab();
			this.renderProcessesTab();
			this.renderLogsTab();
			this.renderInspectTab();
		});

		return this.super('render', []);
	},

	createHeader() {
		return this.super('createHeader', [
			this.container.getName(),
			this.container.isRunning(),
			this.container.isStopped(),
			this.container.isPaused(),
		]);
	},

	stopStreams() {
		this.getTabInstance('stats')?.onTabInactive();
		this.getTabInstance('ps')?.onTabInactive();
		this.getTabInstance('logs')?.onTabInactive();
	},

	async renderInfoTab() {
		const content = await ContainerInfoTab.render(this.container);
		this.renderTab('info', content);
	},

	async renderResourcesTab() {
		const resourceForm = await new PodmanFormResource.init().render(this.container);
		this.renderTab('resources', resourceForm, _('Configure resource limits for this container.'));
	},

	async renderStatsTab() {
		const content = await ContainerStatsTab.render(this.container);
		this.renderTab('stats', content);
	},

	async renderProcessesTab() {
		const content = await ContainerProcessesTab.render(this.container);
		this.renderTab('ps', content);
	},

	async renderLogsTab() {
		const content = await ContainerLogsTab.render(this.container);
		this.renderTab('logs', content);
	},

	renderInspectTab() {
		this.renderTab('inspect', new podmanUI.JsonArea(this.data).render());
	},

	async handleStart() {
		if (this.container.isRunning()) {
			return;
		}

		this.loading(_('Start container'));

		if (this.container.isPaused()) {
			this.container.unpause().then(() => window.location.reload());
			return;
		}

		this.container.start().then(() => window.location.reload());
	},

	async handleStop() {
		if (this.container.isStopped()) {
			return;
		}

		this.loading(_('Stop container'));
		this.stopStreams();
		this.container.stop().then(() => window.location.reload());
	},

	async handleRestart() {
		this.loading(_('Restart container'));
		this.stopStreams();
		this.container.restart().then(() => window.location.reload());
	},

	async handlePause() {
		if (!this.container.isRunning()) {
			return;
		}

		this.loading(_('Pause container'));
		this.stopStreams();
		this.container.pause().then(() => window.location.reload());
	},

	async handleRemove() {
		this.confirm([
			E('p', {}, _('Are you sure to remove container?')),
		], async () => {
			this.loading(_('Remove container'));
			this.container.remove().then(() => this.redirectToList());
		});
	},
});
