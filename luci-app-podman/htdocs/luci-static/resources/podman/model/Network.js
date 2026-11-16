'use strict';

'require baseclass';
'require network';
'require firewall';
'require uci';
'require ui';

'require podman.model.Model as Model';

const NetworkRPC = {
	inspect: Model.declareRPC({
		object: 'podman',
		method: 'network_inspect',
		params: ['name']
	}),

	remove: Model.declareRPC({
		object: 'podman',
		method: 'network_remove',
		params: ['name', 'force']
	}),

	connect: Model.declareRPC({
		object: 'podman',
		method: 'network_connect',
		params: ['name', 'data']
	}),

	disconnect: Model.declareRPC({
		object: 'podman',
		method: 'network_disconnect',
		params: ['name', 'data']
	}),
};

const Network = Model.base.extend({
	__name__: 'Podman.Model.Network',

	getID() {
		return this.ID;
	},

	getName() {
		return this.name || _('Unknown');
	},

	getDriver() {
		return this.driver;
	},

	getSubnetIP4() {
		if (this.subnets?.length > 0) {
			return this.subnets[0].subnet || '';
		}
		if (this.IPAM?.Config?.length > 0) {
			return this.IPAM.Config[0].Subnet || '';
		}
		return '';
	},

	getSubnetIP6() {
		if (this.ipv6_enabled && this.subnets?.length > 1) {
			return this.subnets[1].subnet || '';
		}
		return '';
	},

	getGatewayIP4() {
		if (this.subnets?.length > 0) {
			return this.subnets[0].gateway || '';
		}
		if (this.IPAM?.Config?.length > 0) {
			return this.IPAM.Config[0].Gateway || '';
		}
		return '';
	},

	getGatewayIP6() {
		if (this.ipv6_enabled && this.subnets?.length > 1) {
			return this.subnets[1].gateway || '';
		}
		return '';
	},

	isBridge() {
		return this.getDriver() === 'bridge';
	},

	async inspect() {
		return NetworkRPC.inspect(this.getName());
	},

	async remove(force) {
		return NetworkRPC.remove(this.getName(), force ?? false);
	},

	async connect(data) {
		return NetworkRPC.connect(this.getName(), data || {});
	},

	async disconnect(data) {
		return NetworkRPC.disconnect(this.getName(), data || {});
	},

	async integrationCheck() {
		const check = {
			hasInterface: false,
			hasDevice: false,
			hasDnsmasqExclusion: false,
		};

		const networkObj = await network.getNetwork(this.getName());
		let deviceObj;

		if (networkObj) {
			check.hasInterface = true;
			deviceObj = networkObj.getDevice();

			if (deviceObj) {
				check.hasDevice = true;
			}
		}

		if (!deviceObj) {
			const devices = (await network.getDevices()).map((device) => device.device);

			if (devices.includes(this.network_interface)) {
				check.hasDevice = true;
			}
		}

		await uci.load('dhcp');
		const mainSection = await this.hasDnsmasq() ? this._getDnsmasqSection() : null;
		if (mainSection) {
			const notInterfaces = uci.get('dhcp', mainSection, 'notinterface');

			if ([].concat(notInterfaces ?? []).includes(this.getName())) {
				check.hasDnsmasqExclusion = true;
			}
		} else {
			check.hasDnsmasqExclusion = true;
		}

		return check;
	},

	async integrationRepair() {
		await uci.load('dhcp');
		const status = await this.integrationCheck();
		if (status.hasInterface && status.hasDevice && status.hasDnsmasqExclusion) {
			return;
		}

		let deviceName;
		let changes = false;

		if (status.hasDevice === false && this.isBridge()) {
			deviceName = await this.integrationCreateDevice();
			changes = true;

			if (status.hasInterface === true) {
				const net = await network.getNetwork(this.getName());
				net.addDevice(deviceName);
			}
		}

		if (status.hasInterface === false) {
			if (status.hasDevice === true) {
				deviceName = this.network_interface;
			}

			await this.integrationCreateNetwork(deviceName);
			changes = true;
		}

		if (await this.hasDnsmasq() && status.hasDnsmasqExclusion === false) {
			await this.integrationAddDnsmasqExclusion();
			changes = true;
		}

		if (changes === false) {
			return;
		}

		await uci.save();
		ui.changes.apply();
		await network.flushCache();
	},

	async integrationRemove() {
		await uci.load('dhcp');
		const status = await this.integrationCheck();
		let changes = false;

		// Check device shared status BEFORE deleting the interface to avoid stale network cache
		let removeDevice = false;
		if (status.hasDevice === true && this.isBridge()) {
			const device = await network.getDevice(this.network_interface);
			removeDevice = device?.getNetworks().length === 1;
		}

		if (status.hasInterface === true) {
			const zone = await firewall.getZoneByNetwork(this.getName());
			if (zone) await zone.deleteNetwork(this.getName());
			await network.deleteNetwork(this.getName());
			changes = true;
		}

		if (removeDevice) {
			uci.remove('network', this.network_interface + '_device');
			changes = true;
		}

		if (await this.hasDnsmasq() && status.hasDnsmasqExclusion === true) {
			const mainSection = this._getDnsmasqSection();
			if (mainSection) {
				const notInterfaces = [].concat(uci.get('dhcp', mainSection, 'notinterface') || [])
					.filter(iface => iface !== this.getName());
				if (notInterfaces.length > 0)
					uci.set('dhcp', mainSection, 'notinterface', notInterfaces);
				else
					uci.unset('dhcp', mainSection, 'notinterface');
				changes = true;
			}
		}

		if (changes === false) {
			return;
		}

		await uci.save();
		ui.changes.apply();
		await network.flushCache();
	},

	async integrationCreateNetwork(deviceName) {
		const networkName = this.getName();

		if (this.subnets?.length === 0 && this.ipam_options?.driver === 'dhcp') {
			uci.add('network', 'interface', networkName);
			uci.set('network', networkName, 'proto', 'dhcp');
			return;
		}

		const subnet = this.getSubnetIP4();
		if (!subnet) return;

		const prefix = parseInt(subnet.split('/')[1], 10);
		const netmask = network.prefixToMask(prefix);

		const sid = `${networkName}`;
		uci.add('network', 'interface', sid);
		uci.set('network', sid, 'proto', 'static');
		if (deviceName) uci.set('network', sid, 'device', deviceName);
		uci.set('network', sid, 'ipaddr', this.getGatewayIP4());
		uci.set('network', sid, 'netmask', netmask);

		if (this.ipv6_enabled) {
			uci.set('network', sid, 'ip6addr', this.getGatewayIP6() + '/64');
		}
	},

	async integrationCreateDevice() {
		const devices = (await network.getDevices()).map((device) => device.device);

		const baseName = this.network_interface || this.getName();
		let i = 0;
		let deviceName = baseName;

		while (devices.includes(deviceName)) {
			i++;
			deviceName = `${baseName}${i}`;
		}

		const sid = `${deviceName}_device`;
		uci.add('network', 'device', sid);
		uci.set('network', sid, 'type', 'bridge');
		uci.set('network', sid, 'name', deviceName);
		uci.set('network', sid, 'bridge_empty', '1');
		uci.set('network', sid, 'ipv6', this.ipv6_enabled ? '1' : '0');

		if (this.ipv6_enabled) {
			uci.set('network', sid, 'ip6assign', '64');
		}

		return deviceName;
	},

	_getDnsmasqSection() {
		const sections = uci.sections('dhcp', 'dnsmasq');
		return sections.length > 0 ? sections[0]['.name'] : null;
	},

	async hasDnsmasq() {
		return L.hasSystemFeature('dnsmasq');
	},

	async integrationAddDnsmasqExclusion() {
		const mainSection = this._getDnsmasqSection();
		if (mainSection) {
			const notInterfaces = [].concat(uci.get('dhcp', mainSection, 'notinterface') || []);
			if (!notInterfaces.includes(this.getName())) {
				notInterfaces.push(this.getName());
				uci.set('dhcp', mainSection, 'notinterface', notInterfaces);
			}
		}
	},
});

return baseclass.extend({
	__name__: 'Podman.Model.Network',
	getSingleton(data) {
		return Network.extend(data).instantiate([]);
	},
});
