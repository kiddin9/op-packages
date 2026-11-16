'use strict';

'require baseclass';
'require form';
'require ui';
'require uci';
'require network';
'require firewall';

'require podman.utils as utils';
'require podman.rpc as podmanRPC';
'require podman.view as podmanView';
'require podman.model.Network as Network';

/**
 * Create podman network
 */
const PodmanFormNetwork = podmanView.form.extend({
	__name__: 'Podman.Form.Network',

	existingZones: null,
	parentDevices: null,

	makeData() {
		return {
			network: {
				name: null,
				driver: 'bridge',
				subnet: null,
				gateway: null,
				ip_range: null,
				ipv6: '0',
				internal: '0',
				labels: null,
				setup_openwrt: '1',
				firewall_zone: '_create_new_',
			}
		};
	},

	async render() {
		const [zones, parentDevices] = await Promise.all([
			firewall.getZones().then((zones) =>
				zones
				.filter(zone => zone.data.name?.startsWith('podman'))
				.map(zone => zone.data.name)
			),
			network.getDevices().then((devices) =>
				devices.filter(this.isValidParentDevice)
			),
		]);

		this.existingZones = zones;
		this.parentDevices = parentDevices;

		return this.super('render', []);
	},

	createForm: function () {
		let field;

		field = this.section.option(form.Value, 'name', _('Network Name'));
		field.placeholder = 'my-network';
		field.datatype = 'and(uciname,maxlength(15))';
		field.description = _('Name for the network');
		field.rmempty = false;

		field = this.section.option(form.ListValue, 'driver', _('Driver'));
		field.value('bridge', 'bridge');
		field.value('macvlan', 'macvlan');
		field.value('ipvlan', 'ipvlan');
		field.description = _('Network driver');

		field = this.section.option(form.ListValue, 'parent', _('Parent Interface'));
		field.depends('driver', 'macvlan');
		field.depends('driver', 'ipvlan');
		field.description = _(
			'Existing physical interface to use as parent. Required for macvlan/ipvlan networks.'
			);
		if (this.parentDevices.length > 0) {
			this.parentDevices.forEach((device) => {
				const name = device.getName();
				field.value(name, name + ' (' + device.getType() + ')');
			});
		} else {
			field.value('', _('No suitable interfaces found'));
		}

		field = this.section.option(form.Value, 'subnet', _('IPv4 Subnet (CIDR)'));
		field.placeholder = '10.89.0.0/24';
		field.datatype = 'cidr4';
		field.description = _('IPv4 subnet in CIDR notation');
		// field.rmempty = false;

		field = this.section.option(form.Value, 'gateway', _('IPv4 Gateway'));
		field.placeholder = '10.89.0.1';
		field.optional = true;
		field.datatype = 'ip4addr';
		field.description = _('IPv4 gateway address');

		field = this.section.option(form.Value, 'ip_range', _('IP Range (CIDR)'));
		field.placeholder = '10.89.0.0/28';
		field.optional = true;
		field.datatype = 'cidr4';
		field.description = _('Allocate container IP from this range');

		field = this.section.option(form.Flag, 'ipv6', _('Enable IPv6'));
		field.description = _('Enable IPv6 networking');

		field = this.section.option(form.Flag, 'internal', _('Internal Network'));
		field.description = _('Restrict external access to the network');

		field = this.section.option(form.Flag, 'setup_openwrt', _('Setup OpenWrt Integration'));
		field.description = _(
			'Automatically configure OpenWrt network interface, bridge, and firewall zone. <strong>Highly recommended</strong> for proper container networking on OpenWrt.'
		);

		field = this.section.option(form.Value, 'bridge_name', _('Bridge Interface Name'));
		field.placeholder = _('Leave empty to auto-generate');
		field.optional = true;
		field.datatype = 'netdevname';
		field.depends({
			'setup_openwrt': '1',
			'driver': 'bridge'
		});
		field.description = _(
			'Name of the bridge interface (e.g., podman0, mynet0). Leave empty to use: &lt;network-name&gt;0. Note: If the generated name conflicts with an existing interface, OpenWrt will auto-increment it.'
		);

		field = this.section.option(form.ListValue, 'firewall_zone', _('Firewall Zone'));
		field.value('_create_new_', _('Create new zone (will be named: podman_<network-name>)'));
		if (this.existingZones.length > 0) {
			this.existingZones.forEach((zoneName) => {
				field.value(zoneName, zoneName);
			});
		}
		field.depends('setup_openwrt', '1');
		field.description = _(
			'Choose firewall zone for this network.'
		);

		field = this.section.option(form.TextValue, 'labels', _('Labels'));
		field.placeholder = 'key1=value1\nkey2=value2';
		field.rows = 3;
		field.optional = true;
		field.description = _('Labels in key=value format, one per line');
	},

	async handleCreate() {
		if (!this.isValid()) {
			return this.scrollToInvalid();
		}

		await this.save();
		await uci.load(['network', 'firewall', 'dhcp']);
		const ulaPrefix = uci.get('network', 'globals', 'ula_prefix');

		const podnetwork = this.getFieldValues();

		const setupOpenwrt = podnetwork.setup_openwrt === '1';
		const driver = podnetwork.driver || 'bridge';
		const requestedZone = podnetwork.firewall_zone || '_create_new_';
		const zoneName = requestedZone === '_create_new_' ? 'podman_' + podnetwork.name :
			requestedZone;
		const baseBridgeName = podnetwork.bridge_name || podnetwork.name;

		let bridgeName = baseBridgeName;
		let i = 1;
		while (await network.getDevice(bridgeName)) {
			bridgeName = `${baseBridgeName}${i}`;
			i++;
		}

		if ((driver === 'macvlan' || driver === 'ipvlan') && !podnetwork.parent) {
			this.error(_('Parent interface is required for macvlan/ipvlan networks'));
			return;
		}

		// if (setupOpenwrt && !podnetwork.subnet) {
		// 	this.error(_('OpenWrt integration requires subnet to be specified'));
		// 	return;
		// }

		if (!podnetwork.gateway && podnetwork.subnet) {
			podnetwork.gateway = utils.ipv4.firstHost(podnetwork.subnet);
		}

		const payload = {
			name: podnetwork.name,
			driver: driver
		};

		if (driver === 'bridge') {
			payload.network_interface = bridgeName;
		} else if (driver === 'macvlan' || driver === 'ipvlan') {
			payload.network_interface = podnetwork.parent;
		}

		if (podnetwork.subnet) {
			payload.subnets = [{
				subnet: podnetwork.subnet
			}];
			if (podnetwork.gateway) payload.subnets[0].gateway = podnetwork.gateway;

			if (podnetwork.ip_range) {
				const range = utils.ipv4.cidrToRange(podnetwork.ip_range);
				if (range) payload.subnets[0].lease_range = range;
			}
		}

		payload.ipv6_enabled = false;
		if (podnetwork.ipv6 === '1') {
			const ipv6obj = utils.ipv6.deriveUlaFromIpv4(podnetwork.subnet, ulaPrefix);
			payload.ipv6_enabled = true;

			if (podnetwork.subnet) {
				payload.subnets.push({
					subnet: ipv6obj.ipv6subnet
				});

				if (podnetwork.gateway)
					payload.subnets[1].gateway = ipv6obj.ipv6gateway;
			}
		}

		payload.internal = podnetwork.internal === '1';
		if (podnetwork.labels) {
			payload.labels = {};
			podnetwork.labels.split('\n').forEach((line) => {
				const parts = line.split('=');
				if (parts.length >= 2) {
					const key = parts[0].trim();
					const value = parts.slice(1).join('=').trim();
					if (key) payload.labels[key] = value;
				}
			});
		}

		const createFn = async () => {
			const newNetwork = await podmanRPC.networks.create(payload);

			if (!setupOpenwrt) return;

			const inspectData = await Network.getSingleton({
				name: podnetwork.name
			}).inspect();
			const NetworkModel = Network.getSingleton(inspectData);
			const deviceName = await NetworkModel.integrationCreateDevice();
			await NetworkModel.integrationCreateNetwork(deviceName);

			if (await NetworkModel.hasDnsmasq()) {
				await NetworkModel.integrationAddDnsmasqExclusion();
			}

			if (await firewall.getZone(zoneName)) {
				const currentNetworks = uci.get('firewall', zoneName, 'network');
				const networkList = Array.isArray(currentNetworks) ? currentNetworks :
					currentNetworks ? [currentNetworks] : [];
				if (!networkList.includes(podnetwork.name)) {
					networkList.push(podnetwork.name);
					uci.set('firewall', zoneName, 'network', networkList);
				}
			} else {
				const zoneId = uci.add('firewall', 'zone');
				uci.set('firewall', zoneId, 'name', zoneName);
				uci.set('firewall', zoneId, 'input', 'DROP');
				uci.set('firewall', zoneId, 'output', 'ACCEPT');
				uci.set('firewall', zoneId, 'forward', 'REJECT');
				uci.set('firewall', zoneId, 'network', [podnetwork.name]);
			}

			const dnsRuleName = 'Allow-' + zoneName + '-DNS';
			const existingDnsRule = uci.sections('firewall', 'rule').find((s) =>
				uci.get('firewall', s['.name'], 'name') === dnsRuleName
			);

			if (!existingDnsRule) {
				const ruleId = uci.add('firewall', 'rule');
				uci.set('firewall', ruleId, 'name', dnsRuleName);
				uci.set('firewall', ruleId, 'src', zoneName);
				uci.set('firewall', ruleId, 'dest_port', '53');
				uci.set('firewall', ruleId, 'target', 'ACCEPT');
			}

			await uci.save();
			ui.changes.apply();
			await network.flushCache();
		};

		return this.super('handleCreate', [createFn, _('Network')]);
	},

	isValidParentDevice(device) {
		const type = device.getType();
		const name = device.getName();
		return ['ethernet', 'bridge', 'vlan'].includes(type) &&
			name !== 'lo' &&
			!name.match(/^(podman|cni-|docker|veth)/);
	}
});

return baseclass.extend({
	init: PodmanFormNetwork
});
