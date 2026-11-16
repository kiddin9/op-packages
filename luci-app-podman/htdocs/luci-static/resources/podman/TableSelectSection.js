'use strict';

'require baseclass';
'require dom';
'require form';
'require ui';
'require podman.form as podmanForm';
'require podman.ui as podmanUI';
'require podman.utils as podmanUtil';

const FormTableSelectSection = form.TableSection.extend({
	__name__: 'Podman.Form.TableSelectSection',

	checkboxColumn: null,
	view: null,
	toolbarExtraButtons: [],
	modalCreateBtnText: null,
	modalCreateTitle: null,
	handleRefreshCb: null,

	render() {
		if (!this.checkboxColumn) {
			this.checkboxColumn = this.option(
				podmanForm.field.SelectDummyValue,
				this.selectKey,
				new ui.Checkbox(0, { hiddenname: 'all' }).render()
			);
			this.checkboxColumn.width = 30;

			podmanUtil.moveArrayItem(this.children, this.children.length - 1, 0);
		}

		return this.super('render', []);
	},

	renderContents(cfgsections, nodes) {
		const config_name = this.uciconfig ?? this.map.config;
		const max_cols = this.children.length;

		if (this.footer === true) {
			this.footer = [
				`${_('Total')}&nbsp;${nodes.length}`,
			];
		}

		const sectionEl = E('div', {
			id: 'cbi-%s-%s'.format(config_name, this.sectiontype),
			class: 'cbi-section cbi-tblsection',
		});

		const tableEl = E('table', { class: 'table cbi-section-table cbi-section-table-select' });
		const theadEl = E('thead', { class: 'thead cbi-section-thead' });
		const tbodyEl = E('tbody', { class: 'tbody cbi-section-tbody' });
		const tfootEl = E('tfoot', { class: 'tfoot cbi-section-tfoot' });

		if (this.description != null && this.description !== '') {
			sectionEl.appendChild(E('div', { class: 'cbi-section-descr' }, this.description));
		}

		sectionEl.appendChild(E('div', { class: 'cbi-section-actions' }, this.renderToolbar()));

		theadEl.appendChild(this.renderHeaderRows(false));

		if (theadEl.hasChildNodes())
			tableEl.appendChild(theadEl);

		for (let i = 0; i < nodes.length; i++) {
			const trEl = E('tr', {
				id: 'cbi-%s-%s'.format(config_name, cfgsections[i]),
				class: 'tr cbi-section-table-row',
				'data-sid': cfgsections[i],
				'data-section-id': cfgsections[i]
			});

			for (let j = 0; j < max_cols && nodes[i].firstChild; j++) {
				trEl.appendChild(nodes[i].firstChild);
			}

			tbodyEl.appendChild(trEl);
		}

		if (nodes.length === 0)
			tbodyEl.appendChild(E('tr', { class: 'tr cbi-section-table-row' },
				E('td', { class: 'td text-center', colspan: max_cols }, this.renderSectionPlaceholder())));

		tableEl.appendChild(tbodyEl);

		tfootEl.appendChild(this.renderFooterRows(false));

		if (tfootEl.hasChildNodes()) {
			tableEl.appendChild(tfootEl);
		}

		this.registerCheckboxEvents(theadEl, tableEl);

		sectionEl.appendChild(tableEl);

		dom.bindClassInstance(sectionEl, this);

		return sectionEl;
	},

	renderToolbar() {
		return E('div', { class: 'list-toolbar mb-sm d-flex justify-center gap-xs' }, this.getToolbarButtons());
	},

	getToolbarButtons() {
		const buttons = [];

		if (this.handleCreate) {
			buttons.push(this.getCreateButton());
		}
		if (this.handleRemove) {
			buttons.push(this.getRemoveButton());
		}

		if (this.handleRefresh) {
			buttons.push(this.getReloadButton());
		}

		if (this.toolbarExtraButtons.length > 0) {
			buttons.push(...this.toolbarExtraButtons);
		}

		return buttons;
	},

	getCreateButton() {
		return new podmanUI.ButtonNew(_('Create'), {
			click: ui.createHandlerFn(this, 'handleCreate'),
			type: 'add',
		}).render();
	},

	getRemoveButton() {
		return new podmanUI.ButtonNew(_('Delete'), {
			click: ui.createHandlerFn(this, 'handleRemove'),
			type: 'remove',
		}).render();
	},

	getReloadButton() {
		return new podmanUI.ButtonNew(_('Reload'), {
			click: ui.createHandlerFn(this, 'handleRefresh'),
			type: 'apply',
		}).render();
	},

	async handleCreate() {
		const createForm = new this.createForm.init();
		const formElement = await createForm.render();
		const title = this.modalCreateTitle || _('Create %s').format(this.view.titleSingle || '').trim();

		const modal = new podmanUI.Modal(title, [ formElement ]);
		modal.getButtons = () => [
			modal.getCloseButton(),
			new podmanUI.ButtonNew(this.modalCreateBtnText || _('Create'), {
				click: () => {
					createForm.handleCreate().then(() => this.handleRefresh());
				},
				type: 'positive',
			}).render(),
		];
		modal.render();
	},

	async handleRemove() {
		const selected = this.getSelectedData();

		if (selected.length === 0) {
			return this.showNoneSelectedWarning();
		}

		this.view.confirm([
			E('p', {}, _('Are you sure to delete the records?')),
		], async () => {
			let i = 1;
			for (const item of selected) {
				this.view.loading(_('Deleting records: %d/%d').format(i, selected.length));

				await item.remove();

				i++;
			}

			ui.hideModal();
			this.handleRefresh();
		});
	},

	async handleRefresh() {
		const indicatorId = 'podman-refresh-' + this.sectiontype;
		ui.showIndicator(indicatorId, _('Refreshing %s...').format(this.sectiontype));

		const data = await this.view.load();

		if (this.footer) {
			const count = Array.isArray(data) ? data.length : 0;
			this.footer = [`${_('Total')}&nbsp;${count}`];
		}

		const obj = {};
		obj[this.sectiontype] = data;

		this.map.data.__init__(obj);

		this.map.root
			.querySelector('input[type="hidden"][name="all"] ~ input[type=checkbox]').checked = false;

		await this.map.save(null, false);
		await this.map.load();
		await this.map.reset();

		if (this.handleRefreshCb) await this.handleRefreshCb();

		ui.hideIndicator(indicatorId);
	},

	handleInspect(item, hiddenFields) {
		this.view.loading(_('Fetching information...'));

		item.inspect().then((data) => {
			ui.hideModal();
			this.showInspectModal(data, hiddenFields);
		});
	},

	showInspectModal(data, hiddenFields) {
		const displayData = JSON.parse(JSON.stringify(data));

		if (hiddenFields && hiddenFields.length > 0) {
			hiddenFields.forEach((field) => {
				if (displayData[field]) {
					displayData[field] = '***HIDDEN***';
				}
			});
		}

		const content = [
			new podmanUI.JsonArea(displayData).render(),
		];

		if (hiddenFields && hiddenFields.length > 0) {
			content.unshift(E('p', { class: 'mb-sm text-error' }, [
				E('strong', {}, _('Security Notice:')), ' ', _('Sensitive data is hidden for security reasons.')
			]));
		}

		const modal = new podmanUI.Modal('', content);
		modal.handleSubmit = undefined;
		modal.render();
	},

	showNoneSelectedWarning() {
		this.view.warning(_('No %s selected').format(this.sectiontype));
	},

	registerCheckboxEvents(theadEl, tableEl) {
		const checkboxSelectAll = theadEl.querySelector('input[name="all"] + input[type="checkbox"]');
		const rows = tableEl.querySelectorAll('tbody tr');
		let lastClickedIndex = -1;

		if (!checkboxSelectAll) {
			return;
		}

		checkboxSelectAll.addEventListener('click', (event) => {
			const checked = event.target.checked;
			tableEl.querySelectorAll('tbody tr input[type="checkbox"]').forEach((checkbox) => {
				checkbox.checked = checked;
			});
		});

		rows.forEach((row, index) => {
			const checkbox = row.querySelector('input[type=checkbox]');

			if (!checkbox) {
				return;
			}

			row.addEventListener('click', (ev) => {
				const clickedInteractiveElement = ev.target.closest('button, a, input, .cbi-tooltip-container');

				// If the click was inside an interactive element, ignore it and exit.
				if (clickedInteractiveElement) {
					return;
				}

				checkbox.click();
			});

			checkbox.addEventListener('click', (ev) => {
				// Handle shift+click for range selection
				if (ev.shiftKey && lastClickedIndex !== -1 &&
					lastClickedIndex !== index) {
					const start = Math.min(lastClickedIndex, index);
					const end = Math.max(lastClickedIndex, index);
					const targetState = checkbox.checked;

					// Select/deselect all checkboxes in range
					for (let i = start; i <= end; i++) {
						rows[i].querySelector('input[type=checkbox]').checked = targetState;
					}
				}

				// Update last clicked index
				lastClickedIndex = index;
			});
		});
	},

	getSelectedCheckboxes() {
		return this.map.root.querySelectorAll('tbody tr input[type=checkbox]:checked');
	},

	getSelectedData() {
		return [...this.getSelectedCheckboxes()].map((checkbox) => {
			const sectionId = checkbox.previousSibling.name;
			return this.map.data.data[sectionId];
		});
	}
});

return baseclass.extend({
	TableSelectSection: FormTableSelectSection
});
