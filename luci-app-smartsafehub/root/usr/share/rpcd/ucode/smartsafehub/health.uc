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

const HEALTH_FILE = '/tmp/smartsafehub/health.json';
const REPORT_STATE_FILE = '/tmp/smartsafehub/health-reporter.state';
const HEALTH_HELPER = '/usr/libexec/smartsafehub-health';

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

function state_map(path) {
	const result = {};
	const raw = fs.readfile(path) ?? '';

	for (let line in split(raw, '\n')) {
		const fields = split(line, '\t', 2);
		if (length(fields) == 2 && length(fields[0])) {
			result[fields[0]] = fields[1];
		}
	}

	return result;
}

function integer_value(value) {
	const parsed = int(value);
	return parsed == null ? 0 : parsed;
}

function bool_state(value) {
	return value == '1' || value == 'true';
}

function read_reporter_enabled() {
	const ctx = new_uci_cursor();
	if (ctx == null) {
		return false;
	}

	return bool_state(ctx.get('smartsafehub', 'health', 'reporter_enabled'));
}

function start_health_action(action) {
	if (action != 'run-once' && action != 'run-cycle') {
		return false;
	}

	// The helper itself calls other ubus objects. It must not run synchronously
	// inside rpcd, otherwise a nested ubus call can block the rpcd event loop.
	return run_command([
		'/bin/sh',
		'-c',
		HEALTH_HELPER + ' ' + action + ' >/dev/null 2>&1 </dev/null &',
	], 2000);
}

function empty_health_document() {
	return {
		schema: 1,
		generatedAt: 0,
		overall: 'unknown',
		summary: {
			message: '장치 상태 진단을 준비하고 있습니다.',
			total: 0,
			ok: 0,
			warning: 0,
			critical: 0,
			unknown: 0,
		},
		metrics: {
			memoryAvailablePercent: 0,
			load1m: 0,
			overlayAvailablePercent: 0,
		},
		checks: [],
	};
}

function attach_reporter(document) {
	const reporter = state_map(REPORT_STATE_FILE);
	document.reporter = {
		enabled: read_reporter_enabled(),
		eligible: bool_state(reporter.eligible),
		plan: string_value(reporter.plan, null),
		licenseStatus: string_value(reporter.license_status, null),
		lastReportAt: integer_value(reporter.last_report_at),
		nextReportAt: integer_value(reporter.next_report_at),
		lastResult: string_value(reporter.last_result, 'never'),
		lastErrorCode: string_value(reporter.last_error_code, null),
	};

	return document;
}

function health_payload() {
	let document = read_json_file(HEALTH_FILE);

	if (document == null) {
		// Return a stable pending document immediately, then populate the cache in
		// a detached process after this rpcd request has returned.
		start_health_action('run-once');
		document = empty_health_document();
	}

	return success(attach_reporter(document));
}

export function read_health_status(request) {
	return health_payload();
};

export function run_health_diagnostic(request) {
	if (!start_health_action('run-once')) {
		return failure(
			'HEALTH_DIAGNOSTIC_START_FAILED',
			'장치 상태 진단을 시작하지 못했습니다.'
		);
	}

	return success({ accepted: true });
};

export function update_health_reporter(request) {
	const enabled = request.args.enabled;
	const previous_enabled = read_reporter_enabled();
	if (type(enabled) != 'bool') {
		return failure(
			'HEALTH_REPORTER_ARGUMENT_INVALID',
			'원격 상태 보고 사용 여부가 올바르지 않습니다.'
		);
	}

	const reporter = state_map(REPORT_STATE_FILE);
	if (enabled && !bool_state(reporter.eligible)) {
		return failure(
			'HEALTH_REPORTER_NOT_ELIGIBLE',
			'원격 상태 보고는 유료 멤버십 또는 체험 기간에 사용할 수 있습니다.'
		);
	}

	const ctx = new_uci_cursor();
	if (ctx == null || ctx.get_all('smartsafehub', 'health') == null) {
		return failure(
			'HEALTH_REPORTER_CONFIG_UNAVAILABLE',
			'원격 상태 보고 설정을 읽지 못했습니다.'
		);
	}

	if (
		ctx.set('smartsafehub', 'health', 'reporter_enabled', enabled ? '1' : '0') != true ||
		ctx.commit('smartsafehub') != true
	) {
		return failure(
			'HEALTH_REPORTER_SAVE_FAILED',
			'원격 상태 보고 설정을 저장하지 못했습니다.'
		);
	}

	// Enabling performs the first report in a detached cycle. Disabling only
	// refreshes the local state and never performs a remote report.
	start_health_action(enabled ? 'run-cycle' : 'run-once');

	if (previous_enabled != enabled) {
		emit_activity_event(
			'health',
			enabled ? 'settings.health_reporter.enabled' : 'settings.health_reporter.disabled',
			'info',
			{ origin: 'direct' }
		);
	}

	return health_payload();
};
