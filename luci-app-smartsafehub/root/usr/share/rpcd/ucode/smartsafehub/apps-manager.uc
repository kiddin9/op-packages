// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import { failure, run_command, safe_call, success } from './core.uc';
import { from_system_root, from_statvfs } from './apps-storage.uc';
import { ensure_job, job_state, request_job } from './rpc-jobs.uc';

const MANAGER = '/usr/libexec/smartsafehub-apps-manager';
const STATE = '/tmp/smartsafehub/apps-operation.state';
const STATUS = '/tmp/smartsafehub/apps-status.tsv';
const SIZES = '/tmp/smartsafehub/apps-size.tsv';
const RESTORE_STATE = '/tmp/smartsafehub/apps-restore.state';

// OpenWrt procd already reports the writable root filesystem in system.info.
// Those counters are KiB, unlike ucode fs.statvfs() which returns blocks.
// Prefer the existing ubus connection, then fall back to statvfs without
// spawning df or allowing optional metrics to affect core Apps status.
function writable_storage() {
	const info = safe_call('system', 'info', {});
	const root_storage = from_system_root(info?.root);
	if (root_storage != null)
		return root_storage;

	// Do not assume /overlay is present (e.g. ext4 or extroot installs).
	// Both paths are fixed trusted paths. Each call is inexpensive.
	for (let mount in [ '/overlay', '/' ]) {
		let stats = null;
		try {
			stats = fs.statvfs(mount);
		}
		catch (e) {
			continue;
		}
		const storage = from_statvfs(stats, mount);
		if (storage != null)
			return storage;
	}
	return null;
}

function job() {
	const state = { phase: 'idle', action: '', appId: '', code: '', operationId: '' };
	const raw = fs.readfile(STATE);
	if (type(raw) != 'string' || length(raw) > 4096) return state;
	for (let line in split(type(raw) == 'string' ? raw : '', /\r?\n/)) {
		const fields = split(line, /\t/);
		if (length(fields) != 2) continue;
		const key = fields[0];
		const value = fields[1];
		if (key == 'phase' && match(value, /^(idle|starting|running|success|failed)$/) != null)
			state.phase = value;
		else if (key == 'action' && (value == 'install' || value == 'update' || value == 'remove'))
			state.action = value;
		else if (key == 'app_id' && match(value, /^[a-z0-9][a-z0-9-]{0,79}$/) != null)
			state.appId = value;
		else if (key == 'code' && match(value, /^(NONE|LAUNCH|E[0-9]{1,3})$/) != null)
			state.code = value;
		else if (key == 'operation_id' && match(value, /^[0-9]{1,12}-[0-9]{1,12}(-[0-9a-f]{16})?$/) != null)
			state.operationId = value;
	}
	return state;
}

function restore_status() {
	const result = { phase: 'idle', appId: '', code: '' };
	const raw = fs.readfile(RESTORE_STATE);
	if (type(raw) != 'string' || length(raw) > 4096) return result;
	for (let line in split(raw, /\r?\n/)) {
		const fields = split(line, /\t/);
		if (length(fields) != 2) continue;
		if (fields[0] == 'phase' && match(fields[1], /^(idle|starting|running|success|failed)$/) != null)
			result.phase = fields[1];
		else if (fields[0] == 'app_id' && (fields[1] == '' || match(fields[1], /^[a-z0-9][a-z0-9-]{0,79}$/) != null))
			result.appId = fields[1];
		else if (fields[0] == 'code' && match(fields[1], /^(NONE|BUSY|TIMEOUT|INCOMPLETE|INVALID_MANIFEST|UNKNOWN|E[0-9]{1,3})$/) != null)
			result.code = fields[1];
	}
	return result;
}

export function read_apps_status(request) {
	if (request?.args?.refresh == true) request_job('status');
	else ensure_job('status');
	const scan = job_state('status');
	const raw = fs.readfile(STATUS);
	if (type(raw) != 'string' || length(raw) > 16384)
		return failure('APPS_STATUS_INVALID', '설치 상태 데이터가 올바르지 않습니다.');
	const installed = {};
	for (let line in split(raw, /\r?\n/)) {
		const fields = split(line, /\t/);
		if ((length(fields) != 4 && length(fields) != 5 && length(fields) != 6 && length(fields) != 7 && length(fields) != 8) ||
			match(fields[0], /^[a-z0-9][a-z0-9-]{0,79}$/) == null)
			continue;
		installed[fields[0]] = {
			installed: fields[1] == '1',
			partial: fields[2] == '1',
			managed: fields[3] == '1',
			// Only the local manifest scanner can mark a removed approval as retired.
			retired: length(fields) == 8 && fields[7] == '1',
			webUiReady: length(fields) >= 5 && fields[4] == '1',
			updateAvailable: length(fields) >= 6 && fields[5] == '1',
			// This is a representative installed APK version, not the Hub's
			// approved app/catalog version. Never guess when missing.
			installedVersion: length(fields) >= 7 && fields[1] == '1' &&
				match(fields[6], /^[a-zA-Z0-9_][a-zA-Z0-9._+~-]{0,99}$/) != null
				? fields[6] : null,
		};
	}
	return success({ job: job(), restore: restore_status(), installed: installed,
		ready: type(raw) == 'string',
		refreshing: scan.phase == 'starting' || scan.phase == 'running',
		refreshFailed: scan.phase == 'failed' });
};

// Optional data lives behind an independent RPC. A slow APK database lookup
// or filesystem error must never prevent installation/removal status checks.
export function read_apps_metrics(request) {
	let storage = null;
	try {
		storage = writable_storage();
	}
	catch (e) {
		// Older/broken filesystem modules cannot disable core Apps operations.
		warn('smartsafehub: Apps storage statistics unavailable\n');
	}

	const installedSizes = {};
	// Disk accounting is optional and runs outside rpcd. Parse only the
	// last atomically committed snapshot; it may be empty on first load.
	if (request?.args?.refresh == true) request_job('sizes');
	else ensure_job('sizes');
	const sizesScan = job_state('sizes');
	const raw = fs.readfile(SIZES);
	if (type(raw) == 'string' && length(raw) <= 8192) {
		for (let line in split(raw, /\r?\n/)) {
			const fields = split(line, /\t/);
			if (length(fields) != 2 ||
				match(fields[0], /^[a-z0-9][a-z0-9-]{0,79}$/) == null ||
				match(fields[1], /^(0|[1-9][0-9]{0,12})$/) == null)
				continue;
			installedSizes[fields[0]] = int(fields[1]);
		}
	}
	return success({ storage: storage, installedSizes: installedSizes,
		ready: type(raw) == 'string',
		refreshing: sizesScan.phase == 'starting' || sizesScan.phase == 'running' });
};

function start_apps_operation(request, action) {
	// rpcd passes declared method parameters in request.args, not request itself.
	const app_id = request?.args?.app_id;
	if (type(app_id) != 'string' || match(app_id, /^[a-z0-9][a-z0-9-]{0,79}$/) == null)
		return failure('APPS_INVALID_ID', '올바르지 않은 앱입니다.');
	if (!run_command([ MANAGER, 'start', action, app_id ], 5000))
		return failure('APPS_OPERATION_REJECTED', '다른 작업이 진행 중이거나 요청을 시작하지 못했습니다.');
	return success({ accepted: true, appId: app_id, action: action });
}

export function install_app(request) { return start_apps_operation(request, 'install'); };
export function update_app(request) { return start_apps_operation(request, 'update'); };
export function remove_app(request) { return start_apps_operation(request, 'remove'); };
