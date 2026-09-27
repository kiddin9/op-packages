// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import {
	emit_activity_event,
	failure,
	new_uci_cursor,
	number_value,
	run_command,
	string_value,
	success
} from './core.uc';
import {
	wifi_is_managed_section,
	wifi_security,
	wifi_security_requires_key,
	wifi_summary_payload
} from './wifi.uc';

const WIFI_UPDATE_LOCK = '/tmp/smartsafehub/wifi-update.lock';
const WIFI_UPDATE_LOCK_STALE_SECONDS = 120;

export function read_wifi_summary() {
	const payload = wifi_summary_payload();

	return payload == null
		? failure('WIFI_CONFIG_READ_FAILED', 'Wi-Fi 설정을 읽지 못했습니다.')
		: success(payload);
};

function valid_wifi_ssid(value) {
	if (type(value) != 'string') {
		return null;
	}

	const ssid = trim(value);
	if (!length(ssid) || length(ssid) > 32 || match(ssid, /[\r\n]/) != null) {
		return null;
	}

	return ssid;
}

function valid_wifi_password(value) {
	if (type(value) != 'string') {
		return false;
	}

	return (
		(length(value) >= 8 && length(value) <= 63) ||
		(length(value) == 64 && match(value, /^[0-9a-fA-F]{64}$/) != null)
	);
}

function valid_wifi_security(value) {
	return (
		value == 'keep' ||
		value == 'none' ||
		value == 'psk2' ||
		value == 'sae-mixed' ||
		value == 'sae'
	);
}

function acquire_wifi_update_lock() {
	const lock = fs.stat(WIFI_UPDATE_LOCK);

	if (lock) {
		if (time() - number_value(lock.mtime) < WIFI_UPDATE_LOCK_STALE_SECONDS) {
			return false;
		}

		fs.rmdir(WIFI_UPDATE_LOCK);
	}

	return fs.mkdir(WIFI_UPDATE_LOCK) == true;
}

function release_wifi_update_lock() {
	fs.rmdir(WIFI_UPDATE_LOCK);
}

function restore_wifi_option(ctx, section, option, value) {
	if (value == null) {
		return ctx.get('wireless', section, option) == null ||
			ctx.delete('wireless', section, option) == true;
	}

	return ctx.set('wireless', section, option, value) == true;
}

function restore_wifi_snapshot(snapshot) {
	const ctx = new_uci_cursor();
	if (!ctx) {
		return false;
	}

	const restored =
		restore_wifi_option(ctx, snapshot.section, 'ssid', snapshot.ssid) &&
		restore_wifi_option(ctx, snapshot.section, 'encryption', snapshot.encryption) &&
		restore_wifi_option(ctx, snapshot.section, 'key', snapshot.key) &&
		restore_wifi_option(ctx, snapshot.section, 'disabled', snapshot.disabled) &&
		restore_wifi_option(ctx, snapshot.device, 'disabled', snapshot.deviceDisabled);

	return restored && ctx.commit('wireless') == true;
}

function apply_wifi_update(request) {
	const section_name = request.args.section;
	const ssid = valid_wifi_ssid(request.args.ssid);
	const security = request.args.security;
	const password = request.args.password;
	const enabled = request.args.enabled;

	if (type(section_name) != 'string' || !length(section_name)) {
		return failure('WIFI_SECTION_INVALID', '관리할 Wi-Fi 항목이 올바르지 않습니다.');
	}
	if (ssid == null) {
		return failure('WIFI_SSID_INVALID', 'SSID는 1~32바이트로 입력해 주세요.');
	}
	if (!valid_wifi_security(security)) {
		return failure('WIFI_SECURITY_INVALID', '지원하지 않는 Wi-Fi 보안 방식입니다.');
	}
	if (type(password) != 'string') {
		return failure('WIFI_PASSWORD_INVALID', 'Wi-Fi 비밀번호가 올바르지 않습니다.');
	}
	if (type(enabled) != 'bool') {
		return failure('WIFI_ENABLED_INVALID', 'Wi-Fi 사용 상태가 올바르지 않습니다.');
	}

	const ctx = new_uci_cursor();
	if (!ctx) {
		return failure('WIFI_CONFIG_READ_FAILED', 'Wi-Fi 설정을 읽지 못했습니다.');
	}

	const current = ctx.get_all('wireless', section_name);
	if (current == null || current?.['.type'] != 'wifi-iface' || current?.mode != 'ap') {
		return failure('WIFI_SECTION_NOT_FOUND', '관리할 AP 모드 Wi-Fi를 찾지 못했습니다.');
	}

	const device = string_value(current?.device, null);
	if (device == null || ctx.get_all('wireless', device)?.['.type'] != 'wifi-device') {
		return failure('WIFI_DEVICE_NOT_FOUND', 'Wi-Fi 무선 장치를 찾지 못했습니다.');
	}

	if (!wifi_is_managed_section(ctx, section_name, device)) {
		return failure(
			'WIFI_SECTION_NOT_MANAGED',
			'기본 Wi-Fi 항목만 SmartSafeHub에서 관리할 수 있습니다.'
		);
	}

	const current_encryption = string_value(current?.encryption, 'none');
	const target_encryption = security == 'keep' || wifi_security(current_encryption) == security
		? current_encryption
		: security;
	const current_key = string_value(current?.key, '');
	const target_requires_key = wifi_security_requires_key(target_encryption);

	if (security == 'keep' && wifi_security(current_encryption) == 'custom' && length(password)) {
		return failure(
			'WIFI_SECURITY_ADVANCED',
			'현재 고급 보안 방식의 비밀번호는 기존 LuCI에서 변경해 주세요.'
		);
	}
	if (target_requires_key && !length(password) && !valid_wifi_password(current_key)) {
		return failure(
			'WIFI_PASSWORD_REQUIRED',
			'현재 저장된 비밀번호를 사용할 수 없습니다. 새 비밀번호를 입력해 주세요.'
		);
	}
	if (target_requires_key && length(password) && !valid_wifi_password(password)) {
		return failure(
			'WIFI_PASSWORD_INVALID',
			'비밀번호는 8~63자 또는 64자리 16진수여야 합니다.'
		);
	}

	const snapshot = {
		section: section_name,
		device: device,
		ssid: current?.ssid,
		encryption: current?.encryption,
		key: current?.key,
		disabled: current?.disabled,
		deviceDisabled: ctx.get('wireless', device, 'disabled'),
	};
	const target_disabled = enabled ? '0' : '1';
	const target_device_disabled = enabled ? '0' : snapshot.deviceDisabled;
	const target_key = target_encryption == 'none'
		? null
		: length(password)
			? password
			: snapshot.key;
	const changed =
		string_value(snapshot.ssid, '') != ssid ||
		current_encryption != target_encryption ||
		string_value(snapshot.disabled, '0') != target_disabled ||
		(enabled && string_value(snapshot.deviceDisabled, '0') != '0') ||
		(target_encryption == 'none' && snapshot.key != null) ||
		(length(password) && current_key != password);

	if (!changed) {
		return success({
			changed: false,
			reloaded: false,
			summary: wifi_summary_payload() ?? { networks: [], totalClients: 0 },
		});
	}

	const updated =
		ctx.set('wireless', section_name, 'ssid', ssid) == true &&
		ctx.set('wireless', section_name, 'encryption', target_encryption) == true &&
		ctx.set('wireless', section_name, 'disabled', target_disabled) == true &&
		(target_key == null
			? ctx.get('wireless', section_name, 'key') == null ||
				ctx.delete('wireless', section_name, 'key') == true
			: ctx.set('wireless', section_name, 'key', target_key) == true) &&
		(target_device_disabled == null ||
			ctx.set('wireless', device, 'disabled', target_device_disabled) == true);

	if (!updated || ctx.commit('wireless') != true) {
		return failure('WIFI_CONFIG_COMMIT_FAILED', 'Wi-Fi 설정을 저장하지 못했습니다.');
	}

	if (!run_command([ '/sbin/wifi', 'reload' ], 20000)) {
		const restored = restore_wifi_snapshot(snapshot);
		if (restored) {
			run_command([ '/sbin/wifi', 'reload' ], 20000);
		}

		return restored
			? failure(
				'WIFI_RUNTIME_APPLY_FAILED',
				'Wi-Fi 실행 상태를 적용하지 못해 이전 설정으로 되돌렸습니다.'
			)
			: failure(
				'WIFI_ROLLBACK_FAILED',
				'Wi-Fi 적용과 설정 복구에 실패했습니다. 기존 LuCI에서 무선 설정을 확인해 주세요.'
			);
	}

	return success({
		changed: true,
		reloaded: true,
		summary: wifi_summary_payload() ?? { networks: [], totalClients: 0 },
	});
};

export function update_wifi(request) {
	if (!acquire_wifi_update_lock()) {
		return failure(
			'WIFI_UPDATE_RUNNING',
			'다른 Wi-Fi 설정 변경이 진행 중입니다. 잠시 후 다시 시도해 주세요.'
		);
	}

	let result;

	try {
		result = apply_wifi_update(request);
	}
	catch (e) {
		result = failure(
			'WIFI_UPDATE_FAILED',
			'Wi-Fi 설정을 처리하는 중 예기치 않은 오류가 발생했습니다.'
		);
	}

	release_wifi_update_lock();
	if (result?.ok == true && result?.data?.changed == true) {
		emit_activity_event('network', 'settings.wifi.updated', 'info', {
			origin: 'direct',
			enabled: request.args.enabled,
			security: request.args.security,
			section: request.args.section,
		});
	}
	return result;
};
