// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import {
	new_uci_cursor,
	safe_call,
	string_value
} from './core.uc';

function wifi_array_value(value) {
	if (type(value) == 'array') {
		return value;
	}

	return type(value) == 'string' && length(value) ? [ value ] : [];
}

function wifi_disabled(value) {
	return value != null && sprintf('%s', value) == '1';
}

function wifi_collection_length(value) {
	if (type(value) == 'array') {
		return length(value);
	}
	if (type(value) == 'object') {
		return length(keys(value));
	}

	return 0;
}

export function wifi_band(ctx, device) {
	const configured = string_value(ctx.get('wireless', device, 'band'), '');
	const hwmode = string_value(ctx.get('wireless', device, 'hwmode'), '');

	if (configured == '6g') {
		return { value: '6g', label: '6 GHz' };
	}
	if (configured == '2g' || match(hwmode, /11g/) != null) {
		return { value: '2g', label: '2.4 GHz' };
	}
	if (configured == '5g' || match(hwmode, /11a/) != null) {
		return { value: '5g', label: '5 GHz' };
	}

	return { value: 'unknown', label: device };
};

export function wifi_security(value) {
	const encryption = string_value(value, 'none');

	if (encryption == 'none') {
		return 'none';
	}
	if (match(encryption, /^psk2([+].*)?$/) != null) {
		return 'psk2';
	}
	if (match(encryption, /^sae-mixed([+].*)?$/) != null) {
		return 'sae-mixed';
	}
	if (match(encryption, /^sae([+].*)?$/) != null) {
		return 'sae';
	}

	return 'custom';
};

export function wifi_security_requires_key(value) {
	const security = wifi_security(value);

	return security == 'psk2' || security == 'sae-mixed' || security == 'sae';
};

function find_wifi_runtime_interface(runtime_device, section_name) {
	for (let item in runtime_device?.interfaces ?? []) {
		if (item?.section == section_name) {
			return item;
		}
	}

	return null;
}

function wifi_client_count(runtime_interface) {
	const embedded = wifi_collection_length(runtime_interface?.stations);
	if (embedded > 0) {
		return embedded;
	}

	const ifname = string_value(runtime_interface?.ifname, null);
	if (ifname == null) {
		return 0;
	}

	const clients = safe_call(sprintf('hostapd.%s', ifname), 'get_clients', {})?.clients;
	return wifi_collection_length(clients);
}

function wifi_network_contains(value, expected) {
	for (let network in wifi_array_value(value)) {
		if (network == expected) {
			return true;
		}
	}

	return false;
}

function wifi_primary_score(section) {
	let score = wifi_network_contains(section?.network, 'lan') ? 100 : 0;

	if (!wifi_disabled(section?.disabled)) {
		score += 10;
	}
	if (!wifi_disabled(section?.isolate)) {
		score += 1;
	}

	return score;
}

function select_managed_wifi_sections(ctx) {
	const selected = {};
	const device_order = [];
	const iterated = ctx.foreach('wireless', 'wifi-iface', function(section) {
		if (section?.mode != 'ap') {
			return;
		}

		const device = string_value(section?.device, null);
		const section_name = string_value(section?.['.name'], null);
		if (device == null || section_name == null) {
			return;
		}

		const candidate = {
			section: section,
			score: wifi_primary_score(section),
		};

		if (selected[device] == null) {
			selected[device] = candidate;
			push(device_order, device);
		}
		else if (candidate.score > selected[device].score) {
			selected[device] = candidate;
		}
	});

	return iterated == null
		? null
		: { selected: selected, deviceOrder: device_order };
}

export function wifi_is_managed_section(ctx, section_name, device) {
	const managed = select_managed_wifi_sections(ctx);
	const selected_name = managed?.selected?.[device]?.section?.['.name'];

	return selected_name == section_name;
};

export function wifi_summary_payload() {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return null;
	}

	const managed = select_managed_wifi_sections(ctx);
	if (managed == null) {
		return null;
	}

	const runtime = safe_call('network.wireless', 'status', {});
	const networks = [];
	let total_clients = 0;

	for (let device in managed.deviceOrder) {
		const section = managed.selected[device]?.section;
		const section_name = string_value(section?.['.name'], null);
		if (section_name == null) {
			continue;
		}

		// Prefer the LAN AP on each radio. Additional BSS, guest networks,
		// VLANs and mesh interfaces remain in advanced LuCI.
		const runtime_device = runtime?.[device] ?? {};
		const runtime_interface = find_wifi_runtime_interface(runtime_device, section_name);
		const client_count = wifi_client_count(runtime_interface);
		const band = wifi_band(ctx, device);
		const encryption = string_value(section?.encryption, 'none');
		const key = string_value(section?.key, '');
		const device_disabled = wifi_disabled(ctx.get('wireless', device, 'disabled'));
		const interface_disabled = wifi_disabled(section?.disabled);
		const runtime_channel = runtime_device?.config?.channel;
		const configured_channel = ctx.get('wireless', device, 'channel');

		total_clients += client_count;
		push(networks, {
			section: section_name,
			device: device,
			band: band.value,
			bandLabel: band.label,
			ssid: string_value(section?.ssid, ''),
			enabled: !device_disabled && !interface_disabled,
			runtimeUp: runtime_device?.up == true && runtime_interface != null,
			security: wifi_security(encryption),
			securityRaw: encryption,
			passwordConfigured: length(key) > 0,
			channel: runtime_channel != null
				? sprintf('%s', runtime_channel)
				: configured_channel != null
					? sprintf('%s', configured_channel)
					: null,
			networks: wifi_array_value(section?.network),
			clientCount: client_count,
		});
	}

	return {
		networks: networks,
		totalClients: total_clients,
	};
};
