'use strict';

'require network';
'require ui';

'require podman.rpc as podmanRPC';
'require podman.ui as podmanUI';
'require podman.view as podmanView';
'require podman.form as podmanForm';
'require podman.form.network as PodmanFormNetwork';

/**
 * Manage podman networks
 */
return podmanView.list.extend({
	sectionName: 'networks',

	title: _('Networks'),
	titleSingle: _('Network'),

	async load() {
		return podmanRPC.networks.list();
	},

	/**
	 * Update list section
	 */
	async updateSection() {
		this.section.selectKey = 'ID';
		this.section.createForm = PodmanFormNetwork;
		this.section.handleRemove = async () => this.removeNetworks();

		let o;

		o = this.section.option(podmanForm.field.LinkDummyValue, 'name', _('Name'));
		o.click = (_value, net) => this.section.handleInspect(net);

		o = this.section.option(podmanForm.field.DummyValue, 'Int', _('Int'));
		o.cfgdatavalue = (net) => this.getIntegrationIcon(net);
		o.width = '5%';

		o = this.section.option(podmanForm.field.DummyValue, 'driver', _('Driver'));
		o.width = '10%';

		const ipPairCell = (getV4, getV6) => (net) => E('div', {}, [
			E('span', {}, getV4(net) || '-'),
			E('br'),
			E('span', {}, getV6(net) || '-'),
		]);

		o = this.section.option(podmanForm.field.DummyValue, 'Subnet', _('Subnet'));
		o.cfgdatavalue = ipPairCell(n => n.getSubnetIP4(), n => n.getSubnetIP6());
		o.width = '20%';

		o = this.section.option(podmanForm.field.DummyValue, 'Gateway', _('Gateway'));
		o.cfgdatavalue = ipPairCell(n => n.getGatewayIP4(), n => n.getGatewayIP6());
		o.width = '20%';

		o = this.section.option(podmanForm.field.DateDummyValue, 'created', _('Created'));
		o.width = '20%';

		await network.flushCache();
	},

	async removeNetworks() {
		const selected = this.section.getSelectedData();
		if (selected.length === 0) {
			return this.section.showNoneSelectedWarning();
		}

		const checkboxRemoveIntegration = new ui.Checkbox('1', { hiddenname: 'remove-integration' });
		const checkboxNode = checkboxRemoveIntegration.render();
		const checkboxId = checkboxNode.querySelector('input[type="checkbox"]').id;

		this.confirm([
			E('p', {}, _('Are you sure to delete the records?')),
			E('div', { class: 'd-flex align-center checkbox-with-label' }, [
				checkboxNode,
				E('label', { for: checkboxId }, _('Remove OpenWrt integration')),
			]),
		], async () => {
			for (const [i, item] of selected.entries()) {
				this.loading(_('Deleting records: %s/%s').format(i + 1, selected.length));

				await item.remove();
				if (checkboxRemoveIntegration.getValue() === '1') {
					await item.integrationRemove();
				}
			}

			ui.hideModal();
			this.section.handleRefresh();
		});
	},

	async getIntegrationIcon(net) {
		const { hasInterface, hasDevice, hasDnsmasqExclusion } = await net.integrationCheck();

		if (hasInterface && hasDevice && hasDnsmasqExclusion) {
			return new podmanUI.Tooltip('✅', _('OpenWrt integration exists\n\nClick to remove'), {
				click: () => {
					this.confirm([
						E('p', {}, _('Are you sure to remove integration?')),
					], async () => {
						await net.integrationRemove();
						this.section.handleRefresh();
					});
				},
			}).render();
		}

		const tooltip = [];
		tooltip.push(_('OpenWrt integration incomplete'));
		tooltip.push('');
		tooltip.push(`${_('Interface')}: ${String(hasInterface)}`);
		tooltip.push(`${_('Device')}: ${String(hasDevice)}`);
		if (await net.hasDnsmasq()) {
			tooltip.push(`${_('Dnsmasq')}: ${String(hasDnsmasqExclusion)}`);
		}
		tooltip.push('');
		tooltip.push(_('Click icon to repair'));

		return new podmanUI.Tooltip('❌', tooltip.join('\n'), {
			click: () =>
				net.integrationRepair().then(() => this.section.handleRefresh()),
		}).render();
	}
});
