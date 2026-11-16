'use strict';

'require dom';
'require ui';

'require podman.rpc as podmanRPC';
'require podman.utils as podmanUtil';
'require podman.ui as podmanUI';
'require podman.view as podmanView';

'require view.podman.modal.prune as PruneModal';
'require view.podman.modal.autoUpdate as AutoUpdateModal';

/**
 * Podman Overview Dashboard View
 */
return podmanView.base.extend({
	async load() {
		return Promise.all([
			podmanRPC.system.version(),
			podmanRPC.system.info(),
		])
	},

	async render([version, info]) {
		const sections = await Promise.all([
			this.createToolbar(),
			this.createInfoSection(version, info),
			this.createDebugSection(),
			this.createResourcesSection(),
		]);

		this.loadAdditionalInformation();

		return E('div', {}, sections.filter(Boolean));
	},

	async loadAdditionalInformation() {
		const [containers, images, volumes, networks, pods] = await Promise.all([
			podmanRPC.containers.list('all=true'),
			podmanRPC.images.list(),
			podmanRPC.volumes.list(),
			podmanRPC.networks.list(),
			podmanRPC.pods.list()
		]);

		const runningContainers = containers.filter((container) => container.isRunning()).length;
		const runningPods = pods.filter((p) => p.Status === 'Running').length;

		if (this.resourceCardsEl) {
			dom.content(this.resourceCardsEl, [
				this.createResourceCards(containers, pods, images, networks, volumes,
					runningContainers, runningPods)
			]);
		}
	},

	createToolbar() {
		return E('div', { class: 'overview-actions mb-sm' }, [
			new podmanUI.Button(
				_('Check for Updates'),
				ui.createHandlerFn(this, 'handleAutoUpdate'),
				'positive'
			).render(),
			new podmanUI.Button(
				_('Cleanup / Prune'),
				ui.createHandlerFn(this, 'handlePrune'),
				'remove'
			).render()
		]);
	},

	createInfoSection(version, info) {
		const memTotal = podmanUtil.format.bytes(info.host?.memTotal);
		const memFree = podmanUtil.format.bytes(info.host?.memFree);

		const table = new podmanUI.TableList()
			.addRow(_('Podman Version'), version.Version || _('Unknown'))
			.addRow(_('API Version'), version.ApiVersion || _('Unknown'))
			.addRow(_('CPU'), info.host?.cpus?.toString() || _('Unknown'))
			.addRow(_('Memory'), memFree + ' / ' + memTotal)
			.addRow(_('Socket Path'), info.host?.remoteSocket?.path || '/run/podman/podman.sock')
			.addRow(_('Graph Root'), info.store?.graphRoot || _('Unknown'))
			.addRow(_('Run Root'), info.store?.runRoot || _('Unknown'))
			.addRow(_('Registries'), this.getRegistries(info))
		;

		return this.createSection(_('Information'), table.render());
	},

	createDebugSection() {
		this.systemDiagnosticsEl = E('div', { class: 'system-diagnostics', style: 'margin-bottom: 18px;' }, [
			new podmanUI.Button(
				_('Load'),
				ui.createHandlerFn(this, 'handleLoadSystemDiagnostics'),
				'positive'
			).render(),
		]);

		return this.createSection(_('System Diagnostics'), this.systemDiagnosticsEl);
	},

	createResourcesSection() {
		this.resourceCardsEl = E('div', { class: 'resources-cards' }, [
			E('div', { class: 'loading-placeholder' }, [
				E('em', { class: 'spinning' }, _('Loading...')),
			]),
		]);

		return this.createSection(_('Resources'), this.resourceCardsEl);
	},

	createSection(headline, content) {
		return E('div', {}, [
			E('h3', {}, headline),
			content,
		]);
	},

	getRegistries(info) {
		if (info.registries && info.registries.search) {
			return info.registries.search.join(', ');
		}
		return 'docker.io, registry.fedoraproject.org, registry.access.redhat.com';
	},

	createResourceCards(containers, pods, images, networks, volumes, runningContainers,
		runningPods) {

		return E('div', { class: 'overview-cards' }, [
			this.createCard('🐳', _('Containers'), 'containers', containers.length, runningContainers, 'admin/podman/containers'),
			this.createCard('🔗', _('Pods'), 'pods', pods.length, runningPods, 'admin/podman/pods'),
			this.createCard('💿', _('Images'), 'images', images.length, null, 'admin/podman/images'),
			this.createCard('🌐', _('Networks'), 'networks', networks.length, null, 'admin/podman/networks'),
			this.createCard('💾', _('Volumes'), 'volumes', volumes.length, null, 'admin/podman/volumes'),
		]);
	},

	createCard(icon, title, slug, total, running, url) {
		const statsText = running !== null ? running + ' / ' + total : total.toString();

		return E('a', {
			href: L.url(url),
			class: 'd-flex flex-column cursor-pointer align-center overview-card-link overview-card-' + slug,
		}, [
			E('div', { class: 'card-link-header d-flex align-center w-100' }, [
				E('span', { class: 'card-link-title text-bold' }, title),
				icon,
			]),
			E('div', { class: 'w-100' }, [
				E('div', { class: 'card-link-headline text-bold' }, statsText),
				running !== null
					? E('div', { class: 'card-link-text' }, _('running') + ' / ' + _('total'))
					: E('div', { class: 'card-link-text' }, _('total'))
			])
		]);
	},

	async handleLoadSystemDiagnostics() {
		this.loading(_('Load System diagnostics'));

		const debugData = await podmanRPC.system.debug();
		const statusIcons = { ok: '\u2713', warn: '\u26A0', error: '\u2717' };
		const statusColors = { ok: '#2ecc71', warn: '#e67e22', error: '#e74c3c' };

		const table = new podmanUI.TableList();

		(debugData.checks || []).forEach((check) => {
			const icon = statusIcons[check.status] || '?';
			const color = statusColors[check.status] || '#666';
			const detail = check.detail || '';
			const message = check.message ? ' \u2014 ' + check.message : '';

			table.addRow(
				_(check.label),
				E('span', { style: 'color:' + color }, [
					E('strong', {}, icon + ' '),
					E('span', { class: 'cli-value' }, detail),
					message
				])
			);
		});

		dom.content(this.systemDiagnosticsEl, [table.render()]);
		ui.hideModal();
	},

	handlePrune() {
		PruneModal.render();
	},

	handleAutoUpdate() {
		this.loading(_('Find updateable containers'));

		// @todo Use podman api filter
		return podmanRPC.containers.list('all=true').then((containers) => {
			AutoUpdateModal
				.setContainers(containers.filter((c) => c.getAutoUpdateLabel()))
				.render();
		});
	},
});
