// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import {
	new_uci_cursor,
	safe_call,
	string_value,
	success
} from './core.uc';
import { wifi_band } from './wifi.uc';

function connected_device_mac(value) {
	const mac = lc(string_value(value, ''));

	return match(mac, /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/) != null ? mac : null;
}

function connected_device_number(value) {
	const parsed = int(value);
	const parsed_type = type(parsed);

	return (
		(parsed_type == 'int' || parsed_type == 'double') &&
		parsed == parsed
	) ? parsed : null;
}

function connected_device_hostname(value) {
	const hostname = string_value(value, null);

	return hostname == null || hostname == '*' ? null : hostname;
}

function connected_device_ensure(index, order, mac) {
	if (index[mac] == null) {
		index[mac] = {
			mac: mac,
			hostname: null,
			ipv4Address: null,
			connection: 'unknown',
			online: false,
			leaseActive: false,
			leaseExpiresAt: null,
			interface: null,
			ssid: null,
			radio: null,
			band: null,
			bandLabel: null,
			signalDbm: null,
			inactiveMs: null,
			connectedSeconds: null,
		};
		push(order, mac);
	}

	return index[mac];
}

function connected_device_lease_file() {
	const ctx = new_uci_cursor();
	let lease_file = '/tmp/dhcp.leases';

	if (!ctx) {
		return lease_file;
	}

	ctx.foreach('dhcp', 'dnsmasq', function(section) {
		const configured = string_value(section?.leasefile, null);

		if (configured != null) {
			lease_file = configured;
		}
	});

	return lease_file;
}

function connected_device_read_leases(index, order, now) {
	const raw = fs.readfile(connected_device_lease_file()) ?? '';

	for (let line in split(raw, /\r?\n/)) {
		const value = trim(line);
		if (!length(value)) {
			continue;
		}

		const parts = split(value, /\s+/, 5);
		if (length(parts) < 4) {
			continue;
		}

		const mac = connected_device_mac(parts[1]);
		if (mac == null) {
			continue;
		}

		const device = connected_device_ensure(index, order, mac);
		const expires_at = connected_device_number(parts[0]);
		const ip = string_value(parts[2], null);
		const hostname = connected_device_hostname(parts[3]);

		if (ip != null) {
			device.ipv4Address = ip;
		}
		if (hostname != null) {
			device.hostname = hostname;
		}
		if (expires_at != null) {
			device.leaseExpiresAt = expires_at > 0 ? expires_at : null;
			device.leaseActive = expires_at == 0 || expires_at > now;
		}
	}
}

function connected_device_read_arp(index, order) {
	const raw = fs.readfile('/proc/net/arp') ?? '';
	let first = true;

	for (let line in split(raw, /\r?\n/)) {
		if (first) {
			first = false;
			continue;
		}

		const value = trim(line);
		if (!length(value)) {
			continue;
		}

		const parts = split(value, /\s+/);
		if (length(parts) < 6 || parts[2] == '0x0') {
			continue;
		}

		const mac = connected_device_mac(parts[3]);
		if (mac == null) {
			continue;
		}

		const device = connected_device_ensure(index, order, mac);
		const ip = string_value(parts[0], null);

		if (device.ipv4Address == null && ip != null) {
			device.ipv4Address = ip;
		}
		device.connection = 'ethernet';
		device.interface = string_value(parts[5], null);
		device.online = true;
	}
}

function connected_device_apply_station(index, order, mac_value, station, metadata) {
	const mac = connected_device_mac(mac_value);
	if (mac == null) {
		return false;
	}

	const device = connected_device_ensure(index, order, mac);
	const signal = connected_device_number(station?.signal ?? station?.rssi);
	const inactive = connected_device_number(station?.inactive ?? station?.inactive_ms);
	const connected = connected_device_number(
		station?.connected_time ?? station?.connectedTime
	);
	const hostname = connected_device_hostname(station?.hostname);
	const ip = string_value(
		station?.ipaddr ?? station?.ip ?? station?.ipv4Address,
		null
	);

	if (device.hostname == null && hostname != null) {
		device.hostname = hostname;
	}
	if (device.ipv4Address == null && ip != null) {
		device.ipv4Address = ip;
	}
	if (signal != null) {
		device.signalDbm = signal;
	}
	if (inactive != null) {
		device.inactiveMs = inactive;
	}
	if (connected != null) {
		device.connectedSeconds = connected;
	}

	device.connection = 'wifi';
	device.online = true;
	device.interface = metadata.ifname;
	device.ssid = metadata.ssid;
	device.radio = metadata.radio;
	device.band = metadata.band;
	device.bandLabel = metadata.bandLabel;
	return true;
}

function connected_device_merge_stations(index, order, stations, metadata) {
	let merged = 0;

	if (type(stations) == 'object') {
		for (let mac in keys(stations)) {
			if (connected_device_apply_station(
				index,
				order,
				mac,
				stations[mac] ?? {},
				metadata
			)) {
				merged++;
			}
		}
	}
	else if (type(stations) == 'array') {
		for (let station in stations) {
			if (connected_device_apply_station(
				index,
				order,
				station?.mac ?? station?.address ?? station?.['mac-address'],
				station ?? {},
				metadata
			)) {
				merged++;
			}
		}
	}

	return merged;
}

function connected_device_read_wifi(index, order) {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return;
	}

	const runtime = safe_call('network.wireless', 'status', {});
	if (type(runtime) != 'object') {
		return;
	}

	for (let radio in keys(runtime)) {
		const runtime_device = runtime[radio] ?? {};
		const band = wifi_band(ctx, radio);

		for (let runtime_interface in runtime_device?.interfaces ?? []) {
			const section_name = string_value(runtime_interface?.section, null);
			const configured = section_name != null
				? ctx.get_all('wireless', section_name)
				: null;

			if (configured != null && configured?.mode != 'ap') {
				continue;
			}

			const ifname = string_value(runtime_interface?.ifname, null);
			const metadata = {
				ifname: ifname,
				ssid: string_value(
					configured?.ssid ?? runtime_interface?.config?.ssid,
					null
				),
				radio: radio,
				band: band.value,
				bandLabel: band.label,
			};

			const embedded_stations = connected_device_merge_stations(
				index,
				order,
				runtime_interface?.stations,
				metadata
			);

			// Newer network.wireless responses already embed station details.
			// Query hostapd only as a fallback to avoid duplicate ubus work on
			// every 15-second device refresh.
			if (ifname != null && embedded_stations == 0) {
				const hostapd = safe_call(
					sprintf('hostapd.%s', ifname),
					'get_clients',
					{}
				);
				connected_device_merge_stations(
					index,
					order,
					hostapd?.clients,
					metadata
				);
			}
		}
	}
}

function connected_devices_payload() {
	const index = {};
	const order = [];
	const now = time();
	const devices = [];
	const totals = {
		known: 0,
		online: 0,
		wireless: 0,
		ethernet: 0,
		offline: 0,
	};

	try {
		connected_device_read_leases(index, order, now);
	}
	catch (e) {
		warn(sprintf('smartsafehub: connected devices DHCP leases failed: %s\n', e));
	}

	try {
		connected_device_read_arp(index, order);
	}
	catch (e) {
		warn(sprintf('smartsafehub: connected devices ARP table failed: %s\n', e));
	}

	try {
		connected_device_read_wifi(index, order);
	}
	catch (e) {
		warn(sprintf('smartsafehub: connected devices Wi-Fi clients failed: %s\n', e));
	}

	for (let mac in order) {
		const device = index[mac];
		if (device == null) {
			continue;
		}

		push(devices, {
			id: mac,
			hostname: device.hostname,
			mac: mac,
			ipv4Address: device.ipv4Address,
			connection: device.connection,
			online: device.online,
			leaseActive: device.leaseActive,
			leaseExpiresAt: device.leaseExpiresAt,
			interface: device.interface,
			ssid: device.ssid,
			radio: device.radio,
			band: device.band,
			bandLabel: device.bandLabel,
			signalDbm: device.signalDbm,
			inactiveMs: device.inactiveMs,
			connectedSeconds: device.connectedSeconds,
		});

		totals.known++;
		if (device.online) {
			totals.online++;
			if (device.connection == 'wifi') {
				totals.wireless++;
			}
			else if (device.connection == 'ethernet') {
				totals.ethernet++;
			}
		}
		else {
			totals.offline++;
		}
	}

	return {
		generatedAt: now,
		devices: devices,
		totals: totals,
	};
}

export function read_connected_devices() {
	return success(connected_devices_payload());
};
