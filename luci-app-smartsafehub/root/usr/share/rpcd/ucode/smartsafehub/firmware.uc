// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import {
	failure,
	new_uci_cursor,
	run_command,
	string_value,
	success
} from './core.uc';

const FIRMWARE_STATE_FILE = '/tmp/smartsafehub/firmware.state';
const FIRMWARE_RESOLVE_FILE = '/tmp/smartsafehub/firmware-resolve.json';
const FIRMWARE_METADATA_FILE = '/usr/share/smartsafehub/firmware.json';
const ROM_FIRMWARE_METADATA_FILE = '/rom/usr/share/smartsafehub/firmware.json';
const BOARD_NAME_FILE = '/tmp/sysinfo/board_name';
const OPENWRT_RELEASE_FILE = '/etc/openwrt_release';
const FIRMWARE_HELPER = '/usr/libexec/smartsafehub-firmware';
const DEFAULT_API_BASE_URL = 'https://www.smartsafehub.com/api/v1';

function integer_value(value, fallback) {
	const parsed = int(value);
	const parsed_type = type(parsed);
	return parsed_type == 'int' || parsed_type == 'double' ? parsed : fallback;
}

function timestamp_value(value) {
	const parsed = integer_value(value, 0);
	return parsed > 0 ? parsed : null;
}

function limited_string(value, max_length) {
	if (type(value) != 'string' || !length(value)) {
		return null;
	}
	return substr(value, 0, max_length);
}

function read_json_file(path, max_bytes) {
	const raw = fs.readfile(path);
	if (type(raw) != 'string' || !length(raw) || length(raw) > max_bytes) {
		return null;
	}

	try {
		const document = json(raw);
		return type(document) == 'object' ? document : null;
	}
	catch (e) {
		return null;
	}
}

function read_firmware_metadata() {
	return read_json_file(ROM_FIRMWARE_METADATA_FILE, 65536) ??
		read_json_file(FIRMWARE_METADATA_FILE, 65536) ?? {};
}

function read_state() {
	const state = {
		phase: 'idle',
		source: null,
		lastCheckAt: null,
		lastPrepareAt: null,
		lastError: null,
		prepared: null,
	};
	const raw = fs.readfile(FIRMWARE_STATE_FILE);
	if (type(raw) != 'string' || !length(raw)) {
		return state;
	}

	let error_code = '';
	let error_message = '';
	let filename = null;
	let prepared_sha256 = null;
	let prepared_size = 0;
	let allow_backup = false;
	let target_build_id = null;

	for (let line in split(raw, /\r?\n/)) {
		if (!length(line)) {
			continue;
		}

		const parts = split(line, /\t/);
		const key = parts?.[0];
		const value = parts?.[1];

		switch (key) {
		case 'phase':
			if (
				value == 'idle' ||
				value == 'checking' ||
				value == 'downloading' ||
				value == 'verifying' ||
				value == 'ready' ||
				value == 'flashing' ||
				value == 'error'
			) {
				state.phase = value;
			}
			break;
		case 'source':
			if (value == 'online' || value == 'manual') {
				state.source = value;
			}
			break;
		case 'last_check_at':
			state.lastCheckAt = timestamp_value(value);
			break;
		case 'last_prepare_at':
			state.lastPrepareAt = timestamp_value(value);
			break;
		case 'error_code':
			error_code = string_value(value, '');
			break;
		case 'error_message':
			error_message = string_value(value, '');
			break;
		case 'filename':
			filename = limited_string(value, 160);
			break;
		case 'prepared_sha256':
			prepared_sha256 = limited_string(value, 80);
			break;
		case 'prepared_size':
			prepared_size = integer_value(value, 0);
			break;
		case 'allow_backup':
			allow_backup = value == '1';
			break;
		case 'target_build_id':
			target_build_id = limited_string(value, 80);
			break;
		}
	}

	if (length(error_code) || length(error_message)) {
		state.lastError = {
			code: length(error_code) ? error_code : 'FIRMWARE_FAILED',
			message: length(error_message) ? error_message : '펌웨어 작업에 실패했습니다.',
		};
	}

	if (state.phase == 'ready' || state.phase == 'flashing') {
		state.prepared = {
			source: state.source,
			filename: filename,
			sizeBytes: prepared_size > 0 ? prepared_size : null,
			sha256: prepared_sha256,
			allowBackup: allow_backup,
			targetBuildId: target_build_id,
		};
	}

	return state;
}

function read_firmware_channel() {
	const metadata = read_firmware_metadata();
	let channel = limited_string(metadata?.channel, 16);
	if (channel == 'stable' || channel == 'beta') {
		return channel;
	}

	const ctx = new_uci_cursor();
	channel = limited_string(ctx?.get('smartsafehub', 'firmware', 'channel'), 16);
	if (channel == 'stable' || channel == 'beta') {
		return channel;
	}

	return 'stable';
}

function supported_device_code(device_code) {
	switch (device_code) {
	case 'iptime-ax3000sm':
	case 'iptime-a3004t':
	case 'iptime-ax3000se':
	case 'gl-mt300n-v2':
	case 'xiaomi-ax3000t':
		return true;
	default:
		return false;
	}
}

function board_device_code(board_name) {
	switch (board_name) {
	case 'iptime,ax3000sm':
		return 'iptime-ax3000sm';
	case 'iptime,a3004t':
		return 'iptime-a3004t';
	case 'iptime,ax3000se':
		return 'iptime-ax3000se';
	case 'glinet,gl-mt300n-v2':
		return 'gl-mt300n-v2';
	case 'xiaomi,mi-router-ax3000t':
	case 'xiaomi,ax3000t':
		return 'xiaomi-ax3000t';
	default:
		return null;
	}
}

function read_openwrt_release() {
	const raw = fs.readfile(OPENWRT_RELEASE_FILE);
	if (type(raw) != 'string' || !length(raw)) {
		return null;
	}

	for (let line in split(raw, /\r?\n/)) {
		if (substr(line, 0, 16) != 'DISTRIB_RELEASE=') {
			continue;
		}
		let value = substr(line, 16);
		if (length(value) >= 2) {
			const first = substr(value, 0, 1);
			const last = substr(value, length(value) - 1, 1);
			if ((first == "'" && last == "'") || (first == '"' && last == '"')) {
				value = substr(value, 1, length(value) - 2);
			}
		}
		return limited_string(value, 80);
	}

	return null;
}

function read_current_firmware() {
	const metadata = read_firmware_metadata();
	const ctx = new_uci_cursor();
	const config = ctx?.get_all('smartsafehub', 'firmware') ?? {};
	const board_name = limited_string(trim(fs.readfile(BOARD_NAME_FILE) ?? ''), 120);
	let device_code = limited_string(metadata?.device_code, 80);
	let build_id = limited_string(metadata?.build_id, 80);

	if (!supported_device_code(device_code)) {
		device_code = limited_string(config?.device_code, 80);
	}
	if (!supported_device_code(device_code)) {
		device_code = board_device_code(board_name);
	}

	if (build_id == null) {
		build_id = limited_string(config?.current_build_id, 80);
	}

	return {
		deviceCode: device_code,
		boardName: board_name,
		buildId: build_id,
		openwrtVersion: limited_string(metadata?.openwrt_version, 80) ?? read_openwrt_release(),
		metadataAvailable: type(metadata?.build_id) == 'string' && length(metadata.build_id) > 0,
	};
}

function read_api_base_url() {
	const ctx = new_uci_cursor();
	const configured = string_value(ctx?.get('smartsafehub', 'firmware', 'api_base_url'), DEFAULT_API_BASE_URL);
	return match(configured, /^https:\/\//) != null ? configured : DEFAULT_API_BASE_URL;
}

function sanitize_release(document, current) {
	const resolved_build_id = limited_string(document?.current_build_id, 80);
	if (
		type(document) != 'object' ||
		document?.schema != 1 ||
		type(document?.update_available) != 'bool' ||
		document?.device_code != current.deviceCode ||
		document?.channel != read_firmware_channel() ||
		(current.buildId != null && resolved_build_id != current.buildId)
	) {
		return { currentVersion: null, updateAvailable: false, release: null };
	}

	const current_version = limited_string(document?.current_version, 32);
	if (document?.release == null) {
		return {
			currentVersion: current_version,
			updateAvailable: false,
			release: null,
		};
	}

	const release = document.release;
	const image = release?.sysupgrade;
	if (type(release) != 'object' || type(image) != 'object') {
		return { currentVersion: current_version, updateAvailable: false, release: null };
	}

	let notes = [];
	if (type(release?.release_notes) == 'array') {
		for (let note in release.release_notes) {
			const text = limited_string(note, 600);
			if (text != null && length(notes) < 24) {
				push(notes, text);
			}
		}
	}

	const size = integer_value(image?.size_bytes, 0);
	return {
		currentVersion: current_version,
		updateAvailable: document.update_available == true,
		release: {
			id: integer_value(release?.id, 0),
			buildId: limited_string(release?.build_id, 80),
			version: limited_string(release?.version, 32),
			deviceCode: limited_string(release?.device_code, 80),
			channel: limited_string(release?.channel, 16),
			target: limited_string(release?.target, 120),
			profile: limited_string(release?.profile, 120),
			openwrtVersion: limited_string(release?.openwrt_version, 80),
			publishedAt: limited_string(release?.published_at, 80),
			releaseNotes: notes,
			sysupgrade: {
				id: integer_value(image?.id, 0),
				filename: limited_string(image?.filename, 180),
				sizeBytes: size > 0 ? size : null,
				sha256: limited_string(image?.sha256, 80),
			},
		},
	};
}

export function read_firmware_status() {
	const current = read_current_firmware();
	const state = read_state();
	const resolved = sanitize_release(read_json_file(FIRMWARE_RESOLVE_FILE, 262144), current);

	current.releaseVersion = resolved.currentVersion;
	state.current = current;
	state.updateAvailable = resolved.updateAvailable;
	state.release = resolved.release;
	const ctx = new_uci_cursor();
	const firmware_config = ctx?.get_all('smartsafehub', 'firmware') ?? {};
	let check_interval = integer_value(firmware_config?.check_interval_s, 21600);
	if (check_interval < 900 || check_interval > 604800) {
		check_interval = 21600;
	}
	state.settings = {
		channel: read_firmware_channel(),
		apiBaseUrl: read_api_base_url(),
		checkIntervalSeconds: check_interval,
		autoInstall: false,
	};
	return success(state);
};

function operation_running() {
	const phase = read_state().phase;
	return phase == 'checking' || phase == 'downloading' || phase == 'verifying' || phase == 'flashing';
}

function start_background(command) {
	if (operation_running()) {
		return failure('FIRMWARE_BUSY', '다른 펌웨어 작업이 진행 중입니다. 잠시 후 다시 시도해 주세요.');
	}
	if (!run_command([ '/bin/sh', '-c', command ], 2000)) {
		return failure('FIRMWARE_START_FAILED', '펌웨어 작업을 시작하지 못했습니다.');
	}
	return success({ accepted: true });
}

export function check_firmware() {
	return start_background(FIRMWARE_HELPER + ' check >/dev/null 2>&1 </dev/null &');
};

export function prepare_firmware() {
	return start_background(FIRMWARE_HELPER + ' prepare >/dev/null 2>&1 </dev/null &');
};

export function validate_uploaded_firmware(request) {
	let filename = string_value(request.args.filename, 'firmware.bin');
	if (match(filename, /^[A-Za-z0-9._+-]{1,128}$/) == null) {
		filename = 'firmware.bin';
	}
	return start_background(
		FIRMWARE_HELPER + ' validate-upload ' + filename + ' >/dev/null 2>&1 </dev/null &'
	);
};

export function install_firmware(request) {
	if (request.args.confirm != 'install') {
		return failure('FIRMWARE_INSTALL_CONFIRMATION_REQUIRED', '펌웨어 설치 확인 값이 올바르지 않습니다.');
	}
	if (type(request.args.keep_settings) != 'bool') {
		return failure('FIRMWARE_INSTALL_ARGUMENT_INVALID', '설정 유지 옵션이 올바르지 않습니다.');
	}

	const keep = request.args.keep_settings ? '1' : '0';
	return start_background(
		FIRMWARE_HELPER + ' install ' + keep + ' >/dev/null 2>&1 </dev/null &'
	);
};

export function discard_firmware() {
	if (operation_running()) {
		return failure('FIRMWARE_BUSY', '진행 중인 펌웨어 작업이 끝난 뒤 취소해 주세요.');
	}
	if (!run_command([ FIRMWARE_HELPER, 'clean' ], 3000)) {
		return failure('FIRMWARE_DISCARD_FAILED', '준비된 펌웨어 파일을 정리하지 못했습니다.');
	}
	return success({ accepted: true });
};
