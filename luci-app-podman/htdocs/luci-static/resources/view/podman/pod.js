'use strict';

'require ui';
'require dom';

'require podman.ui as podmanUI';
'require podman.view as podmanView';
'require podman.model.Pod as Pod';

'require view.podman.pod-tab.info as PodInfoTab';
'require view.podman.pod-tab.containers as PodContainersTab';
'require view.podman.pod-tab.stats as PodStatsTab';
'require view.podman.pod-tab.processes as PodProcessesTab';

return podmanView.container.extend({
	pod: null,
	data: null,
	listUrl: L.url('admin/podman/pods'),

	async load() {
		const path = L.location();
		const matches = path.match(/pod\/([a-f0-9]+)/i);

		if (!matches || !matches[1]) {
			this.redirectToList();
			return;
		}

		const podId = matches[1];
		const pod = Pod.getSingleton({ Id: podId });

		const inspectData = await pod.inspect();
		this.data = inspectData;

		return Pod.getSingleton(inspectData);
	},

	async render(pod) {
		if (!pod) {
			this.redirectToList();
			return;
		}

		this.pod = pod;
		this.tabs
			.addTab('info', _('Info'))
			.addTab('containers', _('Containers'))
			.addTab('stats', _('Stats'))
			.addTab('ps', _('Processes'))
			.addTab('inspect', _('Inspect'));

		requestAnimationFrame(() => {
			this.renderInfoTab();
			this.renderContainersTab();
			this.renderStatsTab();
			this.renderProcessesTab();
			this.renderInspectTab();
		});

		return this.super('render', []);
	},

	createHeader() {
		return this.super('createHeader', [
			this.pod.getName(),
			this.pod.isRunning(),
			this.pod.isStopped(),
			this.pod.isPaused(),
		]);
	},

	stopStreams() {
		this.getTabInstance('stats')?.onTabInactive();
		this.getTabInstance('ps')?.onTabInactive();
	},

	async renderInfoTab() {
		const content = await PodInfoTab.render(this.pod);
		this.renderTab('info', content);
	},

	async renderContainersTab() {
		const content = await PodContainersTab.render(this.pod);
		this.renderTab('containers', content);
	},

	async renderStatsTab() {
		const content = await PodStatsTab.render(this.pod);
		this.renderTab('stats', content);
	},

	async renderProcessesTab() {
		const content = await PodProcessesTab.render(this.pod);
		this.renderTab('ps', content);
	},

	renderInspectTab() {
		this.renderTab('inspect', new podmanUI.JsonArea(this.data).render());
	},

	async handleStart() {
		if (this.pod.isRunning()) {
			return;
		}

		this.loading(_('Start pod'));

		if (this.pod.isPaused()) {
			this.pod.unpause().then(() => window.location.reload());
			return;
		}

		this.pod.start().then(() => window.location.reload());
	},

	async handleStop() {
		if (!this.pod.isRunning() && !this.pod.isPaused()) {
			return;
		}

		this.loading(_('Stop pod'));
		this.stopStreams();
		this.pod.stop().then(() => window.location.reload());
	},

	async handleRestart() {
		this.loading(_('Restart pod'));
		this.stopStreams();
		this.pod.restart().then(() => window.location.reload());
	},

	async handlePause() {
		if (!this.pod.isRunning()) {
			return;
		}

		this.loading(_('Pause pod'));
		this.stopStreams();
		this.pod.pause().then(() => window.location.reload());
	},

	async handleRemove() {
		this.confirm([
			E('p', {}, _('Are you sure to remove pod?')),
		], async () => {
			this.loading(_('Remove pod'));
			this.pod.remove().then(() => this.redirectToList());
		});
	},
});
