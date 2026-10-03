'use strict';

'require ui';

'require podman.ui as podmanUI';
'require podman.form as podmanForm';
'require podman.view as podmanView';
'require podman.rpc as podmanRPC';
'require podman.utils as utils';

'require podman.model.Container as Container';

const CENSORED_VALUE = '••••••••';

return podmanView.tabContent.extend({
	tab: 'info',

	container: null,
	initScriptStatus: '',

	async render(container) {
		this.container = container;

		const sections = await Promise.all([
			this.basicSection(),
			this.configSection(),
			this.networkSection(),
			this.envSection(),
			this.mountSection(),
		]);

		this.updateInitScriptIcon(sections[0]);

		return sections;
	},

	basicSection() {
		const basicTable = new podmanUI.TableList();

		const editableNameField = new ui.Textfield(this.container.getName(), { name: 'container-name' }).render();
		const editableName = new podmanForm.EditableField('container-name', editableNameField);
		editableName.onSubmit = (value) => this.handleUpdateName(value);

		const policies = {
			'no': _('No'),
			'always': _('Always'),
			'on-failure': _('On Failure'),
			'unless-stopped': _('Unless Stopped')
		};
		const currentPolicy = this.container.getRestartPolicyName();
		const editableRestartField = new ui.Select(currentPolicy, policies, { name: 'container-restart' }).render();
		const editableRestart = new podmanForm.EditableField('container-restart', editableRestartField);
		editableRestart.onSubmit = (value) => this.handleUpdateRestartPolicy(value);

		basicTable
			.addRow(_('Name'), editableName.render())
			.addRow(_('ID'), this.container.getID().substring(0, 64))
			.addRow(_('Image'), new podmanUI.Tooltip(this.container.getImageName(), this.container.Image, { class: 'tooltip' }).render())
			.addRow(_('Tag'), this.container.getImageTag())
			.addRow(_('Status'), this.container.getStateBadge())
			.addRow(_('Created'), this.container.getCreated(true))
			.addRow(_('Started'), this.container.getStartedAt(true))
			.addRow(_('Restart Policy'), editableRestart.render())
			.addRow(_('Auto Update'), this.container.getAutoUpdateLabel() || _('Disabled'))
			.addRow(_('Init Script'), E('div', {
				class: `init-script-form align-center ${this.container.getRestartPolicyName() === 'no' ? 'd-none' : 'd-flex'}`
			}, [
				new podmanUI.Tooltip(
					new podmanUI.ButtonNew(
						this.container.getAutoStartStatusIcon(),
						{
							click: ui.createHandlerFn(this, 'handleToggleInitScript'),
						}
					 ).render(),
					 _('Click to enable/disable'),
					 {
						class: 'cursor-pointer',
					 }
				).render(),

				new podmanUI.ButtonNew(_('Show'), {
					type: 'none',
					click: ui.createHandlerFn(this, 'handleShowInitScript'),
				}).render(),
				new podmanUI.ButtonNew(_('Generate'), {
					type: 'none',
					click: ui.createHandlerFn(this, 'handleGenerateInitScript'),
				}).render(),
			]))
		;

		return E('div', {}, [
			E('h4', {}, _('Basic Information')),
			basicTable.render(),
		]);
	},

	configSection() {
		const configTable = new podmanUI.TableList();
		const cmd = this.container.getCmdString() || '-';
		const entrypoint = this.container.getEntrypointString() || '-';
		const createCommand = this.container.getCreateCommandString() || '-';
		const createCommandField = new podmanUI.SecretText(createCommand, CENSORED_VALUE);

		configTable
			.addRow(_('Create Command'), createCommandField.render())
			.addRow(_('Command'), cmd)
			.addRow(_('Entrypoint'), entrypoint)
			.addRow(_('Working Directory'), this.container.getWorkingDir())
			.addRow(_('User'), this.container.getUser())
			.addRow(_('Hostname'), this.container.getHostname())
			.addRow(_('Privileged'), this.container.getPrivileged() ? _('Yes') : _('No'))
			.addRow(_('TTY'), this.container.getTty() ? _('Yes') : _('No'))
			.addRow(_('Interactive'), this.container.getInteractive() ? _('Yes') : _('No'))
		;

		return E('div', {}, [
			E('h4', {}, _('Configuration')),
			configTable.render(),
		]);
	},

	async networkSection () {
		const table = new podmanUI.TableList();
		const { NetworkMode, Links } = this.container.getHostConfig();
		const { Networks, IPAddress } = this.container.getNetworkSettings();

		table.addRow(_('Network Mode'), NetworkMode || _('default'));

		const systemNetworks = ['bridge', 'host', 'none', 'container', 'slirp4netns'];
		let userNetworks = [];

		if (Networks && Object.keys(Networks).length > 0) {
			userNetworks = Object.keys(Networks).filter((netName) => !systemNetworks.includes(netName));

			userNetworks.forEach((netName) => {
				const net = Networks[netName];
				const tooltip = (() => {
					if (!this.container.isRunning()) {
						return _('Container is not running');
					}

					const parts = [];
					if (net.IPAddress) parts.push(`IPv4: ${net.IPAddress}`);
					if (net.GlobalIPv6Address) parts.push(`IPv6: ${net.GlobalIPv6Address}`);
					else parts.push('IPv6: disabled');
					if (net.Gateway) parts.push(`Gateway: ${net.Gateway}`);
					if (net.MacAddress) parts.push(`MAC: ${net.MacAddress}`);
					return parts.join('\n');
				})();

				const ipContent = net.GlobalIPv6Address
					? [net.IPAddress || '-', E('br'), net.GlobalIPv6Address]
					: net.IPAddress || '-';

				table.addRow(
					new podmanUI.Tooltip(E('span', { class: 'tooltip' }, netName), tooltip).render(),
					E('div', { class: 'd-flex align-center' }, [
						E('span', {}, ipContent),
						new podmanUI.Tooltip('✖', _('Click to disconnect'), {
							class: 'text-error cursor-pointer container-icon-disconnect ml-sm border-0',
							click: () => this.handleNetworkDisconnect(netName),
						}).render(),
					])
				);
			});
		}

		if (IPAddress && userNetworks.length === 0) {
			table.addRow(_('IP Address'), IPAddress);
		}

		const podmanNetworks = await podmanRPC.networks.list();
		const networkOptions = Object.fromEntries(podmanNetworks.map(item => [item.name, item.name]));

		const networkSelectWidget = new ui.Select([''], networkOptions, { name: 'container-connect-network', optional: false });
		const ipTextWidget = new ui.Textfield('', { name: 'container-connect-ip', placeholder: '192.168.1.100', datatype: 'ip4addr' });

		table.addRow(_('Connect to'), [
			E('div', { class: 'd-flex align-center container-connect' }, [
				networkSelectWidget.render(),
				ipTextWidget.render(),
				new podmanUI.Button(_('Connect'), () => {
					const selectedNetwork = networkSelectWidget.getValue();
					const selectedIp = ipTextWidget.getValue();

					networkSelectWidget.triggerValidation();
					ipTextWidget.triggerValidation();

					if (!selectedNetwork || !ipTextWidget.isValid()) {
						return;
					}

					this.handleNetworkConnect(selectedNetwork, selectedIp);
				}).render(),
			]),
		]);

		table.addRow(_('Ports'), E('div', {},
			this.container.getPorts().map((port) => E('div', {}, port.string)),
		));

		if (Links && Links.length > 0) {
			const linkNodes = Links.reduce((nodes, link, i) => {
				if (i > 0) nodes.push(E('br'));
				nodes.push(link);
				return nodes;
			}, []);
			table.addRow(_('Links'), linkNodes);
		}

		return E('div', { class: 'networks' }, [
			E('h4', {}, _('Network')),
			table.render(),
		]);
	},

	envSection() {
		const table = new podmanUI.Table();
		table
			.addHeader(_('Variable'), { style: 'width: 50%;' })
			.addHeader(_('Value'), { style: 'width: 50%;' });

		this.container.getEnvironmentVars().forEach((env) => {
			const parts = env.split('=');
			const varName = parts[0];
			const varValue = parts.slice(1).join('=');
			const valueField = new podmanUI.SecretText(varValue, CENSORED_VALUE);

			table.addRow([{
					inner: varName
				},
				{
					inner: valueField.render(),
				},
			]);
		});

		return E('div', {}, [
			E('h4', {}, _('Environment Variables')),
			table.render(),
		]);
	},

	mountSection() {
		const table = new podmanUI.Table();
		table
			.addHeader(_('Type'), { style: 'width: 10%;' })
			.addHeader(_('Source'), { style: 'width: 35%;' })
			.addHeader(_('Destination'), { style: 'width: 35%;' })
			.addHeader(_('Mode'), { style: 'width: 10%;' })
		;

		const truncatedField = (value) => {
			const v = value || '-';
			return v.length > 50 ? new podmanUI.Tooltip(utils.truncate(v, 50), v).render() : v;
		};

		this.container.getMounts().forEach((mount) => {
			const mountSourceField = truncatedField(mount.Source);
			const mountDestField = truncatedField(mount.Destination);

			table.addRow([
				{ inner: mount.Type || '-' },
				{ inner: mountSourceField },
				{ inner: mountDestField },
				{ inner: mount.RW ? 'rw' : 'ro' },
			]);
		})

		return E('div', {}, [
			E('h4', {}, _('Mounts')),
			table.render(),
		]);
	},

	async _refreshContainer() {
		const inspectData = await this.container.inspect();
		this.container = Container.getSingleton(inspectData);
	},

	async _refreshNetworkSection() {
		const networkSection = await this.networkSection();
		document.querySelector('.networks').replaceWith(networkSection);
	},

	async updateInitScriptIcon(infoSection) {
		this.initScriptStatus = await this.container.checkInitScript();
		const initScriptIconElement = (infoSection || document).querySelector('.autostart-status');
		const initScriptIcon = this.container.getAutoStartStatusIcon(this.initScriptStatus);
		initScriptIconElement.replaceWith(initScriptIcon);
	},

	async handleUpdateName(name) {
		if (!name || this.container.Name === name) {
			return;
		}

		this.loading(_('Update name'));

		await this.container.updateName(name);

		document.querySelector('.container-toolbar h2').textContent = name;
		this.success(_('Name updated successfully'));
	},

	async handleUpdateRestartPolicy(policy) {
		this.loading(_('Update restart policy'));

		const updateData = { RestartPolicy: policy };
		if (policy === 'on-failure') updateData.RestartRetries = 5;

		await this.container.update(updateData);
		await this._refreshContainer();

		const initScriptForm = document.querySelector('.init-script-form');
		if (policy === 'no') {
			initScriptForm.classList.replace('d-flex', 'd-none');
		} else {
			initScriptForm.classList.replace('d-none', 'd-flex');
		}

		this.updateInitScriptIcon();

		this.success(_('Restart policy updated successfully'));
	},

	async handleNetworkConnect(networkName, ip) {
		this.loading(_('Connecting container to network'));

		const params = {};
		if (ip) params.static_ips = [ip];

		await this.container.connect(networkName, params);
		await this._refreshContainer();
		this.success(_('Connected successfully to %s').format(networkName));
		await this._refreshNetworkSection();
	},

	async handleNetworkDisconnect(networkName) {
		this.loading(_('Disconnect container from network'));

		await this.container.disconnect(networkName);
		await this._refreshContainer();
		this.success(_('Disconnected from %s').format(networkName));
		await this._refreshNetworkSection();
	},

	async handleGenerateInitScript() {
		this.loading(_('Creating auto-start configuration for %s').format(this.container.getName()));

		await this.container.generateInitScript();
		await this.container.enableInitScript();
		ui.hideModal();
		window.location.reload();
	},

	async handleShowInitScript() {
		this.loading(_('Loading init script'));

		const result = await this.container.showInitScript();
		ui.hideModal();

		if (!result || !result.path || !result.content) return;

		const modal = new podmanUI.Modal(result.path, [
			new podmanUI.BashCodeArea(result.content.replace(/\\n/g, '\n')).render()
		]);
		modal.handleSubmit = undefined;
		modal.render();
	},

	async handleToggleInitScript() {
		if (this.initScriptStatus === 'missing') {
			return this.handleGenerateInitScript();
		} else if (this.initScriptStatus === 'enabled') {
			this.loading(_('Disabling init script'));
			await this.container.disableInitScript();
			ui.hideModal();
			window.location.reload();
		} else if (this.initScriptStatus === 'disabled') {
			this.loading(_('Enabling init script'));
			await this.container.enableInitScript();
			ui.hideModal();
			window.location.reload();
		}
	},
});
