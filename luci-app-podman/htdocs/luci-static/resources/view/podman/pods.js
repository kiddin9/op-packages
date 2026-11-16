'use strict';

'require ui';

'require podman.rpc as podmanRPC';
'require podman.utils as utils';
'require podman.ui as podmanUI';
'require podman.form as podmanForm';
'require podman.view as podmanView';
'require podman.form.pod as PodmanFormPod';
'require podman.model.Container as Container';

return podmanView.list.extend({
	sectionName: 'pods',

	title: _('Pods'),
	titleSingle: _('Pod'),

	async load() {
		return podmanRPC.pods.list();
	},

	async updateSection() {
		this.section.selectKey = 'Id';
		this.section.createForm = PodmanFormPod;
		this.section.toolbarExtraButtons = [
			new podmanUI.Button('&#9658;', ui.createHandlerFn(this, 'handleStart')).render(),
			new podmanUI.Button('&#9724;', ui.createHandlerFn(this, 'handleStop')).render(),
			new podmanUI.Button('&#8635;', ui.createHandlerFn(this, 'handleRestart')).render(),
			new podmanUI.Button('&#10074;&#10074;', ui.createHandlerFn(this, 'handlePause')).render(),
		];

		let o;

		o = this.section.option(podmanForm.field.DummyValue, 'Name', _('Name'));

		o = this.section.option(podmanForm.field.DummyValue, 'Id', _('ID'));
		o.cfgdatavalue = (pod) => pod.getDetailLink(utils.truncate(pod.getID(), 16));
		o.width = '20%';

		o = this.section.option(podmanForm.field.DummyValue, 'Status', _('Status'));
		o.cfgdatavalue = (pod) => pod.getStatusBadge();
		o.width = '10%';

		o = this.section.option(podmanForm.field.DummyValue, 'Containers', _('Containers'));
		o.cfgdatavalue = (pod) => this.renderContainersCell(pod);
		o.width = '12%';

		o = this.section.option(podmanForm.field.DummyValue, 'Networks', _('Networks'));
		o.cfgdatavalue = (pod) => {
			const nets = pod.getNetworks();
			return nets.length > 0 ? nets.join(', ') : '-';
		};
		o.width = '15%';

		o = this.section.option(podmanForm.field.DateDummyValue, 'Created', _('Created'));
		o.width = '20%';
	},

	renderContainersCell(pod) {
		const count = pod.getContainers().length;
		if (count === 0) {
			return E('span', {}, '0');
		}

		return E('a', {
			href: '#',
			class: 'text-bold',
			click: (ev) => {
				ev.preventDefault();
				this.handleShowContainers(pod);
			}
		}, `${count} ▸`);
	},

	handleShowContainers(pod) {
		const containers = pod.getContainers();

		const headerRow = E('tr', {}, [
			E('th', {}, _('Name')),
			E('th', {}, _('ID')),
			E('th', {}, _('Status')),
		]);

		const rows = containers.map((c) => {
			const container = Container.getSingleton(c);
			const idShort = utils.truncate(container.getID(), 10);
			const idCell = container.getDetailLink(idShort);

			return E('tr', {}, [
				E('td', {}, container.getName()),
				E('td', {}, idCell),
				E('td', {}, container.getStateBadge()),
			]);
		});

		// @todo: create table with helpers or show a simpler list
		const table = E('table', {
			class: 'table cbi-section-table'
		}, [
			E('thead', {}, headerRow),
			E('tbody', {}, rows.length > 0 ? rows : [
				E('tr', {}, E('td', {
					colspan: 3,
					class: 'text-center'
				}, _('No containers in this pod'))),
			]),
		]);

		const title = _('Containers in pod %s').format(pod.getName());
		const modal = new podmanUI.Modal(title, [table]);
		modal.render();
	},

	handleStart() {
		return this.runOnSelected(
			(pod) => pod.isPaused() ? pod.unpause() : pod.start(),
			_('Starting pod')
		);
	},

	handleStop() {
		return this.runOnSelected((pod) => pod.stop(), _('Stopping pod'));
	},

	handleRestart() {
		return this.runOnSelected((pod) => pod.restart(), _('Restarting pod'));
	},

	handlePause() {
		return this.runOnSelected((pod) => pod.pause(), _('Pausing pod'));
	},

	async runOnSelected(action, textLoad) {
		const section = this.getSection();
		const selected = section.getSelectedData();
		if (selected.length === 0) {
			return section.showNoneSelectedWarning();
		}

		const failures = [];
		for (const [i, pod] of selected.entries()) {
			this.loading(_('%s: %d/%d').format(textLoad, i + 1, selected.length));
			const result = await action(pod);
			if (result?.Errs?.length > 0) {
				failures.push({
					name: pod.getName(),
					errs: result.Errs
				});
			}
		}

		ui.hideModal();

		if (failures.length > 0) {
			const blocks = failures.map(({
				name,
				errs
			}) => E('div', {
				class: 'mb-sm'
			}, [
				E('strong', {}, name + ':'),
				E('ul', {
					class: 'm-0'
				}, errs.map((e) => E('li', {}, e))),
			]));
			podmanUI.alert(blocks, 'error');
		}

		section.handleRefresh();
	},
});
