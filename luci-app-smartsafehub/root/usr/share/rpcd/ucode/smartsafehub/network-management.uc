// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import {
	emit_activity_event,
	failure,
	new_uci_cursor,
	run_command,
	safe_call,
	string_value,
	success
} from './core.uc';

const LAN_UPDATE_LOCK = '/tmp/smartsafehub/lan-update.lock';
const LAN_UPDATE_LOCK_STALE_SECONDS = 120;
const DEFAULT_PREFIX_LENGTH = 24;
const DEFAULT_LEASE_TIME = '12h';

const SAFE_LAN_CANDIDATES = [
	'192.168.10.1',
	'192.168.20.1',
	'192.168.30.1',
	'192.168.50.1',
	'192.168.100.1',
	'192.168.200.1',
	'172.16.10.1',
	'172.16.20.1',
	'10.10.10.1',
	'10.20.20.1',
];

function integer_value(value, fallback) {
	const parsed = int(value);
	const parsed_type = type(parsed);

	return parsed_type == 'int' || parsed_type == 'double' ? parsed : fallback;
}

function pow2(exponent) {
	let value = 1;

	for (let i = 0; i < exponent; i++) {
		value *= 2;
	}

	return value;
}

function parse_ipv4(value) {
	if (type(value) != 'string') {
		return null;
	}

	const parts = split(trim(value), '.');
	if (length(parts) != 4) {
		return null;
	}

	let numeric = 0;
	let normalized = [];

	for (let part in parts) {
		if (match(part, /^(0|[1-9][0-9]{0,2})$/) == null) {
			return null;
		}

		const octet = int(part);
		if (octet < 0 || octet > 255) {
			return null;
		}

		numeric = numeric * 256 + octet;
		push(normalized, sprintf('%d', octet));
	}

	return {
		address: join('.', normalized),
		value: numeric,
	};
}

function ipv4_from_number(value) {
	let remaining = value;
	const first = int(remaining / 16777216);
	remaining -= first * 16777216;
	const second = int(remaining / 65536);
	remaining -= second * 65536;
	const third = int(remaining / 256);
	remaining -= third * 256;

	return sprintf('%d.%d.%d.%d', first, second, third, remaining);
}

function valid_prefix_length(value) {
	const prefix = integer_value(value, -1);

	return prefix >= 8 && prefix <= 30 ? prefix : null;
}

function netmask_from_prefix(prefix) {
	let bits = prefix;
	let octets = [];

	for (let i = 0; i < 4; i++) {
		let octet = 0;
		if (bits >= 8) {
			octet = 255;
			bits -= 8;
		}
		else if (bits > 0) {
			octet = 256 - pow2(8 - bits);
			bits = 0;
		}
		push(octets, sprintf('%d', octet));
	}

	return join('.', octets);
}

function prefix_from_netmask(value) {
	const parsed = parse_ipv4(value);
	if (parsed == null) {
		return null;
	}

	for (let prefix = 8; prefix <= 30; prefix++) {
		if (netmask_from_prefix(prefix) == parsed.address) {
			return prefix;
		}
	}

	return null;
}

function subnet_for(ip, prefix) {
	const block_size = pow2(32 - prefix);
	const network = ip.value - (ip.value % block_size);

	return {
		prefixLength: prefix,
		networkValue: network,
		broadcastValue: network + block_size - 1,
		networkAddress: ipv4_from_number(network),
		broadcastAddress: ipv4_from_number(network + block_size - 1),
		cidr: sprintf('%s/%d', ipv4_from_number(network), prefix),
	};
}

function subnets_overlap(first, second) {
	return first.networkValue <= second.broadcastValue &&
		second.networkValue <= first.broadcastValue;
}

function private_ipv4(ip) {
	return (
		(ip.value >= 167772160 && ip.value <= 184549375) ||
		(ip.value >= 2886729728 && ip.value <= 2887778303) ||
		(ip.value >= 3232235520 && ip.value <= 3232301055)
	);
}

function private_subnet(subnet) {
	return (
		(subnet.networkValue >= 167772160 && subnet.broadcastValue <= 184549375) ||
		(subnet.networkValue >= 2886729728 && subnet.broadcastValue <= 2887778303) ||
		(subnet.networkValue >= 3232235520 && subnet.broadcastValue <= 3232301055)
	);
}

function valid_host_address(ip, subnet) {
	return ip.value > subnet.networkValue && ip.value < subnet.broadcastValue;
}

function string_values(value) {
	if (type(value) == 'string') {
		return length(value) ? [ value ] : [];
	}
	if (type(value) != 'array') {
		return [];
	}

	let values = [];
	for (let item in value) {
		if (type(item) == 'string' && length(item)) {
			push(values, item);
		}
	}

	return values;
}

function parse_lan_ipaddr(value, netmask) {
	const legacy_prefix = prefix_from_netmask(string_value(netmask, '255.255.255.0'));

	for (let candidate in string_values(value)) {
		let raw_address = candidate;
		let prefix = legacy_prefix;

		if (match(candidate, /\//) != null) {
			const parts = split(candidate, '/');
			if (length(parts) != 2) {
				continue;
			}

			raw_address = parts[0];
			prefix = valid_prefix_length(parts[1]);
		}

		const ip = parse_ipv4(raw_address);
		if (ip == null || prefix == null) {
			continue;
		}

		const subnet = subnet_for(ip, prefix);
		if (!valid_host_address(ip, subnet)) {
			continue;
		}

		return {
			ip: ip,
			prefixLength: prefix,
			netmask: netmask_from_prefix(prefix),
			subnet: subnet,
		};
	}

	return null;
}

function lan_network_config(ctx) {
	const section = ctx?.get_all('network', 'lan');
	if (section == null || section?.['.type'] != 'interface') {
		return null;
	}

	const address = parse_lan_ipaddr(section?.ipaddr, section?.netmask);
	if (address == null) {
		return null;
	}

	return {
		section: section,
		ip: address.ip,
		prefixLength: address.prefixLength,
		netmask: address.netmask,
		subnet: address.subnet,
	};
}

function ipaddr_entry_is_ipv4(value) {
	if (type(value) != 'string') {
		return false;
	}

	const parts = split(value, '/');
	return parse_ipv4(parts?.[0]) != null;
}

function target_lan_address(current_ipaddr, validated) {
	const cidr = sprintf('%s/%d', validated.ip.address, validated.prefixLength);

	if (type(current_ipaddr) == 'array') {
		let values = [];
		let replaced = false;

		for (let item in current_ipaddr) {
			if (!replaced && ipaddr_entry_is_ipv4(item)) {
				push(values, cidr);
				replaced = true;
			}
			else {
				push(values, item);
			}
		}

		if (!replaced) {
			let prefixed = [ cidr ];
			for (let item in values) {
				push(prefixed, item);
			}
			values = prefixed;
		}

		return {
			ipaddr: values,
			netmask: null,
		};
	}

	if (type(current_ipaddr) == 'string' && match(current_ipaddr, /\//) != null) {
		return {
			ipaddr: cidr,
			netmask: null,
		};
	}

	return {
		ipaddr: validated.ip.address,
		netmask: validated.netmask,
	};
}

function dhcp_address_from_start(value, subnet) {
	const parsed_ip = parse_ipv4(string_value(value, ''));
	if (parsed_ip != null) {
		return parsed_ip;
	}

	const offset = integer_value(value, -1);
	if (offset < 1) {
		return null;
	}

	return parse_ipv4(ipv4_from_number(subnet.networkValue + offset));
}

function lan_dhcp_config(ctx, lan) {
	const section = ctx?.get_all('dhcp', 'lan');
	if (section == null || section?.['.type'] != 'dhcp') {
		return null;
	}

	const start = dhcp_address_from_start(section?.start, lan.subnet);
	const limit = integer_value(section?.limit, 0);
	const end = start != null && limit > 0
		? parse_ipv4(ipv4_from_number(start.value + limit - 1))
		: null;
	const lease_time = string_value(section?.leasetime, DEFAULT_LEASE_TIME);

	return {
		section: section,
		enabled: string_value(section?.ignore, '0') != '1',
		start: start,
		end: end,
		leaseTime: lease_time,
	};
}

function active_ipv4_networks() {
	const dump = safe_call('network.interface', 'dump', {});
	let networks = [];

	for (let item in dump?.interface ?? []) {
		if (item?.interface == 'lan' || item?.up != true) {
			continue;
		}

		for (let address in item?.['ipv4-address'] ?? []) {
			const ip = parse_ipv4(address?.address);
			const prefix = valid_prefix_length(address?.mask);
			if (ip == null || prefix == null) {
				continue;
			}

			push(networks, {
				interface: string_value(item?.interface, 'unknown'),
				address: ip.address,
				prefixLength: prefix,
				subnet: subnet_for(ip, prefix),
			});
		}
	}

	return networks;
}

function wan_networks() {
	const status = safe_call('network.interface.wan', 'status', {});
	let networks = [];

	for (let address in status?.['ipv4-address'] ?? []) {
		const ip = parse_ipv4(address?.address);
		const prefix = valid_prefix_length(address?.mask);
		if (ip == null || prefix == null) {
			continue;
		}

		push(networks, {
			address: ip.address,
			prefixLength: prefix,
			subnet: subnet_for(ip, prefix),
		});
	}

	return {
		connected: status?.up == true,
		protocol: string_value(status?.proto, null),
		networks: networks,
	};
}

function first_conflicting_wan(lan_subnet, wan) {
	for (let network in wan.networks) {
		if (subnets_overlap(lan_subnet, network.subnet)) {
			return network;
		}
	}

	return null;
}

function candidate_conflicts(candidate_subnet, occupied_networks) {
	for (let occupied in occupied_networks) {
		if (subnets_overlap(candidate_subnet, occupied.subnet)) {
			return true;
		}
	}

	return false;
}

function recommended_lan(occupied_networks) {
	for (let candidate in SAFE_LAN_CANDIDATES) {
		const ip = parse_ipv4(candidate);
		const subnet = subnet_for(ip, DEFAULT_PREFIX_LENGTH);
		if (candidate_conflicts(subnet, occupied_networks)) {
			continue;
		}

		return {
			address: ip.address,
			prefixLength: DEFAULT_PREFIX_LENGTH,
			netmask: netmask_from_prefix(DEFAULT_PREFIX_LENGTH),
			subnet: subnet.cidr,
			dhcpStart: ipv4_from_number(subnet.networkValue + 100),
			dhcpEnd: ipv4_from_number(subnet.networkValue + 249),
		};
	}

	return null;
}

function settings_payload() {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return null;
	}

	const lan = lan_network_config(ctx);
	if (lan == null) {
		return null;
	}

	const dhcp = lan_dhcp_config(ctx, lan);
	if (dhcp == null) {
		return null;
	}

	const wan = wan_networks();
	const conflict = first_conflicting_wan(lan.subnet, wan);
	const occupied = active_ipv4_networks();
	const recommendation = conflict != null ? recommended_lan(occupied) : null;
	const primary_wan = length(wan.networks) ? wan.networks[0] : null;

	return {
		lan: {
			address: lan.ip.address,
			prefixLength: lan.prefixLength,
			netmask: lan.netmask,
			subnet: lan.subnet.cidr,
		},
		dhcp: {
			enabled: dhcp.enabled,
			start: dhcp.start?.address ?? null,
			end: dhcp.end?.address ?? null,
			leaseTime: dhcp.leaseTime,
		},
		wan: {
			connected: wan.connected,
			protocol: wan.protocol,
			address: primary_wan?.address ?? null,
			prefixLength: primary_wan?.prefixLength ?? null,
			subnet: primary_wan?.subnet?.cidr ?? null,
		},
		conflict: {
			detected: conflict != null,
			wanSubnet: conflict?.subnet?.cidr ?? null,
		},
		recommendation: recommendation,
	};
}

function valid_lease_time(value) {
	return type(value) == 'string' && (
		value == 'infinite' || match(value, /^[1-9][0-9]{0,4}[mhdw]$/) != null
	);
}

function validate_requested_settings(request) {
	const ip = parse_ipv4(request.args.ip_address);
	const prefix = valid_prefix_length(request.args.prefix_length);
	const dhcp_start = parse_ipv4(request.args.dhcp_start);
	const dhcp_end = parse_ipv4(request.args.dhcp_end);
	const dhcp_enabled = request.args.dhcp_enabled;
	const lease_time = request.args.lease_time;

	if (request.args.confirm != 'apply') {
		return {
			error: failure(
				'LAN_UPDATE_CONFIRMATION_REQUIRED',
				'내부 네트워크 설정 변경 확인 값이 올바르지 않습니다.'
			),
		};
	}
	if (ip == null || !private_ipv4(ip)) {
		return {
			error: failure(
				'LAN_ADDRESS_INVALID',
				'공유기 주소는 사설 IPv4 주소로 입력해 주세요.'
			),
		};
	}
	if (prefix == null) {
		return {
			error: failure('LAN_PREFIX_INVALID', '서브넷 마스크는 /8~30 범위에서 선택해 주세요.'),
		};
	}
	if (type(dhcp_enabled) != 'bool') {
		return {
			error: failure('LAN_DHCP_ENABLED_INVALID', 'DHCP 서버 사용 상태가 올바르지 않습니다.'),
		};
	}
	if (dhcp_start == null || dhcp_end == null) {
		return {
			error: failure('LAN_DHCP_RANGE_INVALID', 'DHCP 시작/종료 주소를 올바르게 입력해 주세요.'),
		};
	}
	if (!valid_lease_time(lease_time)) {
		return {
			error: failure('LAN_DHCP_LEASE_INVALID', 'DHCP 임대 시간을 올바르게 선택해 주세요.'),
		};
	}

	const subnet = subnet_for(ip, prefix);
	if (!private_subnet(subnet)) {
		return {
			error: failure(
				'LAN_SUBNET_PRIVATE_INVALID',
				'LAN 대역 전체가 RFC1918 사설 IPv4 범위 안에 있어야 합니다.'
			),
		};
	}
	if (!valid_host_address(ip, subnet)) {
		return {
			error: failure('LAN_ADDRESS_HOST_INVALID', '네트워크/브로드캐스트 주소는 공유기 주소로 사용할 수 없습니다.'),
		};
	}
	if (
		!valid_host_address(dhcp_start, subnet) ||
		!valid_host_address(dhcp_end, subnet) ||
		dhcp_start.value > dhcp_end.value
	) {
		return {
			error: failure('LAN_DHCP_RANGE_SUBNET_INVALID', 'DHCP 주소 범위는 선택한 LAN 대역 안에 있어야 합니다.'),
		};
	}
	if (dhcp_start.value <= ip.value && ip.value <= dhcp_end.value) {
		return {
			error: failure('LAN_DHCP_RANGE_ROUTER_CONFLICT', 'DHCP 주소 범위에 공유기 주소를 포함할 수 없습니다.'),
		};
	}

	const conflict = first_conflicting_wan(subnet, wan_networks());
	if (conflict != null) {
		return {
			error: failure(
				'LAN_WAN_SUBNET_CONFLICT',
				sprintf('상위 네트워크 %s와 겹치지 않는 LAN 대역을 사용해 주세요.', conflict.subnet.cidr)
			),
		};
	}

	return {
		ip: ip,
		prefixLength: prefix,
		netmask: netmask_from_prefix(prefix),
		subnet: subnet,
		dhcpEnabled: dhcp_enabled,
		dhcpStart: dhcp_start,
		dhcpEnd: dhcp_end,
		leaseTime: lease_time,
	};
}

function acquire_lan_update_lock() {
	const lock = fs.stat(LAN_UPDATE_LOCK);

	if (lock) {
		if (time() - integer_value(lock.mtime, 0) < LAN_UPDATE_LOCK_STALE_SECONDS) {
			return false;
		}

		fs.rmdir(LAN_UPDATE_LOCK);
	}

	return fs.mkdir(LAN_UPDATE_LOCK) == true;
}

function release_lan_update_lock() {
	fs.rmdir(LAN_UPDATE_LOCK);
}

function restore_option(ctx, package_name, section, option, value) {
	if (value == null) {
		return ctx.get(package_name, section, option) == null ||
			ctx.delete(package_name, section, option) == true;
	}

	return ctx.set(package_name, section, option, value) == true;
}

function restore_snapshot(snapshot) {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return false;
	}

	const restored =
		restore_option(ctx, 'network', 'lan', 'ipaddr', snapshot.ipaddr) &&
		restore_option(ctx, 'network', 'lan', 'netmask', snapshot.netmask) &&
		restore_option(ctx, 'dhcp', 'lan', 'start', snapshot.start) &&
		restore_option(ctx, 'dhcp', 'lan', 'limit', snapshot.limit) &&
		restore_option(ctx, 'dhcp', 'lan', 'leasetime', snapshot.leasetime) &&
		restore_option(ctx, 'dhcp', 'lan', 'ignore', snapshot.ignore);

	return restored && ctx.commit('network') == true && ctx.commit('dhcp') == true;
}

function schedule_runtime_reload() {
	return run_command([
		'/bin/sh',
		'-c',
		'( sleep 2; /sbin/reload_config ) >/dev/null 2>&1 </dev/null &',
	], 2000);
}

function apply_validated_settings(validated) {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return failure('LAN_CONFIG_READ_FAILED', '내부 네트워크 설정을 읽지 못했습니다.');
	}

	const current_lan = lan_network_config(ctx);
	const network_section = current_lan?.section;
	const current_dhcp = current_lan != null ? lan_dhcp_config(ctx, current_lan) : null;
	const dhcp_section = current_dhcp?.section;
	if (current_lan == null || current_dhcp == null) {
		return failure('LAN_CONFIG_UNAVAILABLE', 'LAN 또는 DHCP 기본 설정을 찾지 못했습니다.');
	}
	if (string_value(network_section?.proto, 'static') != 'static') {
		return failure('LAN_PROTOCOL_UNSUPPORTED', 'SmartSafeHub는 정적 LAN 인터페이스만 관리합니다.');
	}

	const snapshot = {
		ipaddr: network_section?.ipaddr,
		netmask: network_section?.netmask,
		start: dhcp_section?.start,
		limit: dhcp_section?.limit,
		leasetime: dhcp_section?.leasetime,
		ignore: dhcp_section?.ignore,
	};
	const target_address = target_lan_address(snapshot.ipaddr, validated);
	const start_offset = validated.dhcpStart.value - validated.subnet.networkValue;
	const limit = validated.dhcpEnd.value - validated.dhcpStart.value + 1;
	const target_ignore = validated.dhcpEnabled ? null : '1';
	const address_changed = current_lan.ip.address != validated.ip.address;
	const changed =
		address_changed ||
		current_lan.prefixLength != validated.prefixLength ||
		current_dhcp.start?.value != validated.dhcpStart.value ||
		current_dhcp.end?.value != validated.dhcpEnd.value ||
		current_dhcp.leaseTime != validated.leaseTime ||
		current_dhcp.enabled != validated.dhcpEnabled;

	if (!changed) {
		return success({
			changed: false,
			reloadScheduled: false,
			addressChanged: false,
			settings: settings_payload(),
		});
	}

	const updated =
		ctx.set('network', 'lan', 'ipaddr', target_address.ipaddr) == true &&
		restore_option(ctx, 'network', 'lan', 'netmask', target_address.netmask) &&
		ctx.set('dhcp', 'lan', 'start', sprintf('%d', start_offset)) == true &&
		ctx.set('dhcp', 'lan', 'limit', sprintf('%d', limit)) == true &&
		ctx.set('dhcp', 'lan', 'leasetime', validated.leaseTime) == true &&
		(target_ignore == null
			? ctx.get('dhcp', 'lan', 'ignore') == null || ctx.delete('dhcp', 'lan', 'ignore') == true
			: ctx.set('dhcp', 'lan', 'ignore', target_ignore) == true);

	if (!updated || ctx.commit('network') != true || ctx.commit('dhcp') != true) {
		restore_snapshot(snapshot);
		return failure('LAN_CONFIG_COMMIT_FAILED', '내부 네트워크 설정을 저장하지 못했습니다.');
	}

	if (!schedule_runtime_reload()) {
		const restored = restore_snapshot(snapshot);
		return restored
			? failure('LAN_RUNTIME_RELOAD_FAILED', '네트워크 재적용을 시작하지 못해 이전 설정으로 되돌렸습니다.')
			: failure('LAN_ROLLBACK_FAILED', '네트워크 설정 적용과 복구에 실패했습니다. 기존 LuCI에서 LAN 설정을 확인해 주세요.');
	}

	emit_activity_event('network', 'settings.lan.updated', 'info', {
		origin: 'direct',
		address_changed: address_changed,
		prefix_length: validated.prefixLength,
		dhcp_enabled: validated.dhcpEnabled,
	});

	return success({
		changed: true,
		reloadScheduled: true,
		addressChanged: address_changed,
		previousAddress: current_lan.ip.address,
		newAddress: validated.ip.address,
		settings: settings_payload(),
	});
}

function with_lan_update_lock(callback) {
	if (!acquire_lan_update_lock()) {
		return failure('LAN_UPDATE_RUNNING', '다른 내부 네트워크 설정 변경이 진행 중입니다. 잠시 후 다시 시도해 주세요.');
	}

	let result;
	try {
		result = callback();
	}
	catch (e) {
		result = failure('LAN_UPDATE_FAILED', '내부 네트워크 설정을 처리하는 중 예기치 않은 오류가 발생했습니다.');
	}

	release_lan_update_lock();
	return result;
}

export function read_lan_settings() {
	const payload = settings_payload();

	return payload == null
		? failure('LAN_CONFIG_READ_FAILED', '내부 네트워크 설정을 읽지 못했습니다.')
		: success(payload);
};

export function update_lan_settings(request) {
	return with_lan_update_lock(function() {
		const validated = validate_requested_settings(request);
		if (validated?.error != null) {
			return validated.error;
		}

		return apply_validated_settings(validated);
	});
};

export function apply_recommended_lan(request) {
	return with_lan_update_lock(function() {
		if (request.args.confirm != 'apply') {
			return failure(
				'LAN_UPDATE_CONFIRMATION_REQUIRED',
				'추천 내부 네트워크 적용 확인 값이 올바르지 않습니다.'
			);
		}

		const current = settings_payload();
		if (current == null) {
			return failure('LAN_CONFIG_READ_FAILED', '내부 네트워크 설정을 읽지 못했습니다.');
		}
		if (!current.conflict.detected) {
			return failure('LAN_AUTO_SUBNET_NOT_REQUIRED', '현재 LAN과 상위 네트워크의 주소 대역이 겹치지 않습니다.');
		}
		if (current.recommendation == null) {
			return failure('LAN_RECOMMENDATION_UNAVAILABLE', '자동으로 사용할 수 있는 안전한 LAN 대역을 찾지 못했습니다.');
		}

		const synthetic_request = {
			args: {
				confirm: 'apply',
				ip_address: current.recommendation.address,
				prefix_length: current.recommendation.prefixLength,
				dhcp_enabled: current.dhcp.enabled,
				dhcp_start: current.recommendation.dhcpStart,
				dhcp_end: current.recommendation.dhcpEnd,
				lease_time: current.dhcp.leaseTime,
			},
		};
		const validated = validate_requested_settings(synthetic_request);
		if (validated?.error != null) {
			return validated.error;
		}

		return apply_validated_settings(validated);
	});
};
