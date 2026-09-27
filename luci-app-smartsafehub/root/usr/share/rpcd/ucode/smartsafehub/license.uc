// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';

import {
	failure,
	number_value,
	run_command,
	success
} from './core.uc';

const RUNTIME_DIR = '/tmp/smartsafehub';
const LICENSE_HELPER = '/usr/libexec/smartsafehub-license';
const LICENSE_STATE_FILE = RUNTIME_DIR + '/license.json';
const ACTIVATION_REQUEST_FILE = RUNTIME_DIR + '/license-activate.request.json';
const ACTIVATION_LOCK = RUNTIME_DIR + '/license-activate.lock';
const ACTIVATION_STALE_S = 60;

function read_json_file(path) {
	const raw = fs.readfile(path);
	if (raw == null || length(raw) == 0) {
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

function default_state() {
	return {
		schema: 1,
		component: 'license',
		phase: 'unknown',
		lastResult: 'never',
		lastErrorCode: null,
		lastAttemptAt: 0,
		lastCheckedAt: 0,
		lastActivatedAt: 0,
		nextCheckAt: 0,
		plan: null,
		licenseStatus: null,
		activationStatus: null,
		deviceAction: null,
	};
}

function license_state() {
	return read_json_file(LICENSE_STATE_FILE) ?? default_state();
}

function cleanup_activation_request() {
	run_command([ '/bin/rm', '-f', ACTIVATION_REQUEST_FILE ], 1000);
	run_command([ '/bin/rmdir', ACTIVATION_LOCK ], 1000);
}

function write_private_request(license_key) {
	if (!run_command([ '/bin/mkdir', '-p', RUNTIME_DIR ], 1000)) {
		return false;
	}
	if (!run_command([ '/bin/sh', '-c', 'umask 077; : > ' + ACTIVATION_REQUEST_FILE ], 1000)) {
		return false;
	}

	try {
		fs.writefile(ACTIVATION_REQUEST_FILE, sprintf('%J\n', { license_key: license_key }));
	}
	catch (e) {
		return false;
	}

	return fs.readfile(ACTIVATION_REQUEST_FILE) != null;
}

function start_activation_helper() {
	// The helper resolves SafeShield identity, performs HTTPS I/O, and applies
	// the local key. Run it detached so rpcd never waits on a nested ubus call.
	return run_command([
		'/bin/sh',
		'-c',
		LICENSE_HELPER + ' activate --request-file ' + ACTIVATION_REQUEST_FILE +
			' >/dev/null 2>&1 </dev/null &',
	], 2000);
}

export function read_license_status(request) {
	return success(license_state());
};

function acquire_activation_lock() {
	if (run_command([ '/bin/mkdir', ACTIVATION_LOCK ], 1000)) {
		return true;
	}

	const state = license_state();
	const started_at = number_value(state?.lastAttemptAt);
	const now = time();
	if (state?.phase == 'activating' && started_at > 0 && now >= started_at &&
		now - started_at < ACTIVATION_STALE_S) {
		return false;
	}

	cleanup_activation_request();
	return run_command([ '/bin/mkdir', ACTIVATION_LOCK ], 1000);
}

export function activate_license(request) {
	const raw_key = request.args.license_key;
	if (type(raw_key) != 'string') {
		return failure('LICENSE_KEY_INVALID', '라이선스 키를 입력해 주세요.');
	}
	const license_key = trim(raw_key);
	if (!length(license_key) || length(license_key) > 128) {
		return failure('LICENSE_KEY_INVALID', '라이선스 키를 확인해 주세요.');
	}
	if (!run_command([ '/bin/mkdir', '-p', RUNTIME_DIR ], 1000)) {
		return failure(
			'LICENSE_RUNTIME_UNAVAILABLE',
			'라이선스 작업 디렉터리를 준비하지 못했습니다.'
		);
	}

	// mkdir is used as an atomic single-flight lock. This keeps one canonical
	// request file without exposing the license key in a process command line.
	if (!acquire_activation_lock()) {
		return failure(
			'LICENSE_ACTIVATION_BUSY',
			'다른 라이선스 등록 작업이 진행 중입니다.'
		);
	}

	// rpcd must not synchronously call SafeShield from inside this RPC. The
	// detached helper resolves authoritative device identity after this method
	// returns, avoiding a nested ubus/rpcd wait on low-resource routers.
	if (!write_private_request(license_key)) {
		cleanup_activation_request();
		return failure(
			'LICENSE_ACTIVATION_REQUEST_WRITE_FAILED',
			'라이선스 등록 요청을 준비하지 못했습니다.'
		);
	}

	const started_at = time();
	try {
		fs.writefile(LICENSE_STATE_FILE, sprintf('%J\n', {
			schema: 1,
			component: 'license',
			phase: 'activating',
			lastResult: 'activating',
			lastErrorCode: null,
			lastAttemptAt: started_at,
			lastCheckedAt: 0,
			lastActivatedAt: 0,
			nextCheckAt: 0,
			plan: null,
			licenseStatus: null,
			activationStatus: null,
			deviceAction: null,
		}));
	}
	catch (e) {
		cleanup_activation_request();
		return failure(
			'LICENSE_STATE_WRITE_FAILED',
			'라이선스 등록 상태를 기록하지 못했습니다.'
		);
	}

	if (!start_activation_helper()) {
		cleanup_activation_request();
		return failure(
			'LICENSE_ACTIVATION_START_FAILED',
			'라이선스 등록 작업을 시작하지 못했습니다.'
		);
	}

	return success({
		accepted: true,
		startedAt: started_at,
		status: license_state(),
	});
};
