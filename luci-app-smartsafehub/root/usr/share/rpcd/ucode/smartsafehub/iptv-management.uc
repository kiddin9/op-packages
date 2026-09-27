// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import {
	emit_activity_event,
	failure,
	new_uci_cursor,
	run_command,
	string_value,
	success
} from './core.uc';

const IPTV_UPDATE_LOCK = '/tmp/smartsafehub/iptv-update.lock';
const IPTV_UPDATE_LOCK_STALE_SECONDS = 120;
const IPTV_CONFIG_FILE = '/etc/config/smartsafehub';
const NETWORK_CONFIG_FILE = '/etc/config/network';
const IGMPPROXY_CONFIG_FILE = '/etc/config/igmpproxy';
const IGMPPROXY_INIT = '/etc/init.d/igmpproxy';
const PREVIOUS_UNSET = '__unset__';
const SUPPORTED_PROVIDERS = [ 'skb', 'lgu' ];

function integer_value(value, fallback) {
	const parsed = int(value);
	const parsed_type = type(parsed);

	return parsed_type == 'int' || parsed_type == 'double' ? parsed : fallback;
}

function provider_supported(provider) {
	for (let candidate in SUPPORTED_PROVIDERS) {
		if (candidate == provider) {
			return true;
		}
	}

	return false;
}

function acquire_iptv_update_lock() {
	const lock = fs.stat(IPTV_UPDATE_LOCK);

	if (lock) {
		if (time() - integer_value(lock.mtime, 0) < IPTV_UPDATE_LOCK_STALE_SECONDS) {
			return false;
		}

		fs.rmdir(IPTV_UPDATE_LOCK);
	}

	return fs.mkdir(IPTV_UPDATE_LOCK) == true;
}

function release_iptv_update_lock() {
	fs.rmdir(IPTV_UPDATE_LOCK);
}

function service_available() {
	const stat = fs.stat(IGMPPROXY_INIT);
	return stat != null && stat.type == 'file';
}

function service_running() {
	return service_available() && run_command([ IGMPPROXY_INIT, 'running' ], 3000);
}

function service_enabled() {
	return service_available() && run_command([ IGMPPROXY_INIT, 'enabled' ], 3000);
}

function iptv_config(ctx) {
	const section = ctx?.get_all('smartsafehub', 'iptv');
	const enabled = string_value(section?.enabled, '0') == '1';
	const configured_provider = string_value(section?.provider, 'skb');

	return {
		enabled: enabled,
		provider: provider_supported(configured_provider) ? configured_provider : 'skb',
		managedBridgeSection: string_value(section?.managed_bridge_section, null),
		previousIgmpSnooping: string_value(section?.previous_igmp_snooping, null),
	};
}

function lan_bridge(ctx) {
	const lan = ctx?.get_all('network', 'lan');
	if (lan == null || lan?.['.type'] != 'interface') {
		return null;
	}

	const device_name = string_value(lan?.device, '');
	let target = null;

	if (length(device_name)) {
		ctx.foreach('network', 'device', function(section) {
			if (
			target == null &&
			string_value(section?.name, '') == device_name &&
			string_value(section?.type, '') == 'bridge'
			) {
				target = {
					section: section?.['.name'],
					device: device_name,
					igmpSnooping: section?.igmp_snooping,
				};
			}
		});
	}

	if (target != null) {
		return target;
	}

	if (string_value(lan?.type, '') == 'bridge') {
		return {
			section: 'lan',
			device: device_name || 'lan',
			igmpSnooping: lan?.igmp_snooping,
		};
	}

	return null;
}

function igmpproxy_layout(ctx) {
	let main_section = null;
	let upstream_section = null;
	let upstream_count = 0;
	let downstream_section = null;

	ctx.foreach('igmpproxy', 'igmpproxy', function(section) {
		if (main_section == null) {
			main_section = section?.['.name'];
		}
	});

	ctx.foreach('igmpproxy', 'phyint', function(section) {
		const direction = string_value(section?.direction, '');
		const network = string_value(section?.network, '');

		if (direction == 'upstream') {
			upstream_count += 1;
			if (upstream_section == null) {
				upstream_section = {
					section: section?.['.name'],
					network: network,
				};
			}
		}
		else if (direction == 'downstream' && network == 'lan' && downstream_section == null) {
			downstream_section = section?.['.name'];
		}
	});

	return {
		mainSection: main_section,
		upstreamSection: upstream_section,
		upstreamCount: upstream_count,
		downstreamSection: downstream_section,
	};
}

function configure_igmpproxy(ctx) {
	const layout = igmpproxy_layout(ctx);

	if (layout.upstreamCount > 1) {
		return failure(
			'IPTV_IGMPPROXY_CONFLICT',
			'기존 IGMP Proxy 설정에 upstream 인터페이스가 여러 개 있어 SmartSafeHub가 안전하게 변경할 수 없습니다.'
		);
	}
	if (
		layout.upstreamSection != null &&
		length(layout.upstreamSection.network) &&
		layout.upstreamSection.network != 'wan'
	) {
		return failure(
			'IPTV_IGMPPROXY_CONFLICT',
			'기존 IGMP Proxy upstream이 WAN이 아니어서 SmartSafeHub IPTV 설정을 적용할 수 없습니다.'
		);
	}

	const main_section = layout.mainSection ?? 'smartsafehub_iptv';
	const upstream_section = layout.upstreamSection?.section ?? 'smartsafehub_iptv_upstream';
	const downstream_section = layout.downstreamSection ?? 'smartsafehub_iptv_downstream';

	if (layout.mainSection == null && ctx.set('igmpproxy', main_section, 'igmpproxy') != true) {
		return failure('IPTV_IGMPPROXY_WRITE_FAILED', 'IGMP Proxy 기본 설정을 만들지 못했습니다.');
	}
	if (
		layout.upstreamSection == null &&
		ctx.set('igmpproxy', upstream_section, 'phyint') != true
	) {
		return failure('IPTV_IGMPPROXY_WRITE_FAILED', 'IGMP Proxy WAN 설정을 만들지 못했습니다.');
	}
	if (
		layout.downstreamSection == null &&
		ctx.set('igmpproxy', downstream_section, 'phyint') != true
	) {
		return failure('IPTV_IGMPPROXY_WRITE_FAILED', 'IGMP Proxy LAN 설정을 만들지 못했습니다.');
	}

	const written =
		ctx.set('igmpproxy', main_section, 'quickleave', '1') == true &&
		ctx.set('igmpproxy', upstream_section, 'network', 'wan') == true &&
		ctx.set('igmpproxy', upstream_section, 'zone', 'wan') == true &&
		ctx.set('igmpproxy', upstream_section, 'direction', 'upstream') == true &&
		ctx.set('igmpproxy', upstream_section, 'altnet', [ '0.0.0.0/0' ]) == true &&
		ctx.set('igmpproxy', downstream_section, 'network', 'lan') == true &&
		ctx.set('igmpproxy', downstream_section, 'zone', 'lan') == true &&
		ctx.set('igmpproxy', downstream_section, 'direction', 'downstream') == true;

	return written
		? null
		: failure('IPTV_IGMPPROXY_WRITE_FAILED', 'IGMP Proxy 설정을 저장하지 못했습니다.');
}

function capture_file(path) {
	return fs.readfile(path);
}

function restore_file(path, content) {
	if (content == null) {
		return false;
	}

	const written = fs.writefile(path, content);
	return type(written) == 'int' && written == length(content);
}

function restore_runtime(snapshot) {
	const files_restored =
		restore_file(IPTV_CONFIG_FILE, snapshot.smartsafehub) &&
		restore_file(NETWORK_CONFIG_FILE, snapshot.network) &&
		restore_file(IGMPPROXY_CONFIG_FILE, snapshot.igmpproxy);

	if (!files_restored) {
		return false;
	}

	run_command([ '/sbin/reload_config' ], 10000);

	if (snapshot.serviceEnabled) {
		run_command([ IGMPPROXY_INIT, 'enable' ], 3000);
	}
	else {
		run_command([ IGMPPROXY_INIT, 'disable' ], 3000);
	}

	if (snapshot.serviceRunning) {
		run_command([ IGMPPROXY_INIT, 'restart' ], 10000);
	}
	else {
		run_command([ IGMPPROXY_INIT, 'stop' ], 10000);
	}

	return true;
}

function runtime_snapshot() {
	return {
		smartsafehub: capture_file(IPTV_CONFIG_FILE),
		network: capture_file(NETWORK_CONFIG_FILE),
		igmpproxy: capture_file(IGMPPROXY_CONFIG_FILE),
		serviceEnabled: service_enabled(),
		serviceRunning: service_running(),
	};
}

function set_iptv_section(ctx, enabled, provider) {
	if (ctx.get_all('smartsafehub', 'iptv') == null) {
		if (ctx.set('smartsafehub', 'iptv', 'iptv') != true) {
			return false;
		}
	}

	return ctx.set('smartsafehub', 'iptv', 'enabled', enabled ? '1' : '0') == true &&
		ctx.set('smartsafehub', 'iptv', 'provider', provider) == true;
}

function remember_bridge_state(ctx, config, bridge) {
	if (config.enabled || config.managedBridgeSection != null) {
		return true;
	}

	const previous = bridge.igmpSnooping == null
		? PREVIOUS_UNSET
		: string_value(bridge.igmpSnooping, '0');

	return ctx.set('smartsafehub', 'iptv', 'managed_bridge_section', bridge.section) == true &&
		ctx.set('smartsafehub', 'iptv', 'previous_igmp_snooping', previous) == true;
}

function restore_bridge_state(ctx, config) {
	const section = config.managedBridgeSection;
	const previous = config.previousIgmpSnooping;

	if (section == null || previous == null) {
		return true;
	}

	const restored = previous == PREVIOUS_UNSET
		? (ctx.get('network', section, 'igmp_snooping') == null ||
			ctx.delete('network', section, 'igmp_snooping') == true)
		: ctx.set('network', section, 'igmp_snooping', previous) == true;

	return restored &&
		(ctx.get('smartsafehub', 'iptv', 'managed_bridge_section') == null ||
			ctx.delete('smartsafehub', 'iptv', 'managed_bridge_section') == true) &&
		(ctx.get('smartsafehub', 'iptv', 'previous_igmp_snooping') == null ||
			ctx.delete('smartsafehub', 'iptv', 'previous_igmp_snooping') == true);
}

function apply_runtime(enabled) {
	if (!run_command([ '/sbin/reload_config' ], 10000)) {
		return false;
	}

	if (enabled) {
		return run_command([ IGMPPROXY_INIT, 'enable' ], 3000) &&
			run_command([ IGMPPROXY_INIT, 'restart' ], 10000) &&
			service_running();
	}

	run_command([ IGMPPROXY_INIT, 'stop' ], 10000);
	const disabled = run_command([ IGMPPROXY_INIT, 'disable' ], 3000);
	return disabled && !service_running();
}

function status_payload() {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return null;
	}

	const config = iptv_config(ctx);
	const bridge = lan_bridge(ctx);

	return {
		enabled: config.enabled,
		provider: config.provider,
		beta: true,
		available: service_available(),
		running: service_running(),
		upstreamNetwork: 'wan',
		downstreamNetwork: 'lan',
		lanBridge: bridge?.device ?? null,
		igmpSnooping: string_value(bridge?.igmpSnooping, '0') == '1',
	};
}

export function read_iptv_settings() {
	const settings = status_payload();
	return settings != null
		? success(settings)
		: failure('IPTV_CONFIG_READ_FAILED', 'IPTV 설정을 읽지 못했습니다.');
};

export function update_iptv_settings(request) {
	if (request.args.confirm != 'apply') {
		return failure('IPTV_UPDATE_CONFIRMATION_REQUIRED', 'IPTV 설정 변경 확인 값이 올바르지 않습니다.');
	}
	if (type(request.args.enabled) != 'bool') {
		return failure('IPTV_ENABLED_INVALID', 'IPTV 사용 상태가 올바르지 않습니다.');
	}
	if (!provider_supported(request.args.provider)) {
		return failure('IPTV_PROVIDER_UNSUPPORTED', '현재는 SK Broadband와 LG U+ IPTV만 지원합니다.');
	}
	if (!service_available()) {
		return failure('IPTV_IGMPPROXY_UNAVAILABLE', 'IGMP Proxy 패키지를 찾지 못했습니다.');
	}
	if (!acquire_iptv_update_lock()) {
		return failure('IPTV_UPDATE_BUSY', '다른 IPTV 설정 변경이 진행 중입니다. 잠시 후 다시 시도해 주세요.');
	}

	const snapshot = runtime_snapshot();
	if (snapshot.smartsafehub == null || snapshot.network == null || snapshot.igmpproxy == null) {
		release_iptv_update_lock();
		return failure('IPTV_CONFIG_SNAPSHOT_FAILED', 'IPTV 적용 전 네트워크 설정을 백업하지 못했습니다.');
	}

	const ctx = new_uci_cursor();
	if (!ctx) {
		release_iptv_update_lock();
		return failure('IPTV_CONFIG_READ_FAILED', 'IPTV 설정을 읽지 못했습니다.');
	}

	const current = iptv_config(ctx);
	const requested_enabled = request.args.enabled;
	const requested_provider = request.args.provider;
	const bridge = lan_bridge(ctx);

	if (requested_enabled && bridge == null) {
		release_iptv_update_lock();
		return failure('IPTV_LAN_BRIDGE_UNAVAILABLE', 'LAN bridge를 찾지 못해 IGMP snooping을 적용할 수 없습니다.');
	}

	let write_error = null;
	if (!set_iptv_section(ctx, requested_enabled, requested_provider)) {
		write_error = failure('IPTV_CONFIG_WRITE_FAILED', 'SmartSafeHub IPTV 설정을 저장하지 못했습니다.');
	}
	else if (requested_enabled) {
		if (!remember_bridge_state(ctx, current, bridge)) {
			write_error = failure('IPTV_CONFIG_WRITE_FAILED', '기존 IGMP snooping 상태를 보존하지 못했습니다.');
		}
		else if (ctx.set('network', bridge.section, 'igmp_snooping', '1') != true) {
			write_error = failure('IPTV_SNOOPING_WRITE_FAILED', 'LAN IGMP snooping 설정을 저장하지 못했습니다.');
		}
		else {
			write_error = configure_igmpproxy(ctx);
		}
	}
	else if (!restore_bridge_state(ctx, current)) {
		write_error = failure('IPTV_SNOOPING_RESTORE_FAILED', 'IPTV 사용 전 IGMP snooping 설정을 복원하지 못했습니다.');
	}

	if (write_error != null) {
		release_iptv_update_lock();
		return write_error;
	}

	const committed =
		ctx.commit('smartsafehub') == true &&
		ctx.commit('network') == true &&
		(!requested_enabled || ctx.commit('igmpproxy') == true);

	if (!committed || !apply_runtime(requested_enabled)) {
		restore_runtime(snapshot);
		release_iptv_update_lock();
		return failure(
			'IPTV_APPLY_FAILED',
			'IPTV 설정을 적용하지 못해 이전 네트워크 설정으로 복구했습니다.'
		);
	}

	const settings = status_payload();
	const changed = current.enabled != requested_enabled || current.provider != requested_provider;
	release_iptv_update_lock();

	if (changed && settings != null) {
		emit_activity_event('network', 'settings.iptv.updated', 'info', {
			origin: 'direct',
			enabled: requested_enabled,
			provider: requested_provider,
		});
	}

	return settings != null
		? success({ changed: changed, settings: settings })
		: failure('IPTV_CONFIG_READ_FAILED', 'IPTV 설정은 적용했지만 최신 상태를 다시 읽지 못했습니다.');
};
