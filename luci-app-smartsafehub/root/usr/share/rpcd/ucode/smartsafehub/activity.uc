// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';

import {
	emit_activity_event,
	failure,
	new_uci_cursor,
	run_command,
	success
} from './core.uc';

const ACTIVITY_HISTORY_FILE = '/tmp/smartsafehub/activity-history.jsonl';
const LEGACY_EVENTS_FILE = '/tmp/smartsafehub/events.jsonl';
const ACTIVITY_SYNC_STATE_FILE = '/tmp/smartsafehub/activity-sync.json';
const LICENSE_STATE_FILE = '/tmp/smartsafehub/license.json';
const ACTIVITY_SYNC_HELPER = '/usr/libexec/smartsafehub-activity-sync';
const ACTIVITY_SYNC_INIT = '/etc/init.d/smartsafehub-activity-sync';
const MAX_ACTIVITY_EVENTS = 128;
const MAX_ACTIVITY_FILE_BYTES = 1048576;

function integer_value(value, fallback) {
	const parsed = int(value);
	const parsed_type = type(parsed);

	return (parsed_type == 'int' || parsed_type == 'double') && parsed == parsed
		? parsed
		: fallback;
}

function valid_severity(value) {
	return value == 'info' || value == 'success' || value == 'warning' || value == 'error';
}

function valid_metadata(value) {
	return type(value) == 'object' && type(value) != 'array';
}

function normalize_event(document) {
	if (
		type(document) != 'object' ||
		document?.schema != 1 ||
		type(document?.event_id) != 'string' ||
		!length(document.event_id) ||
		type(document?.event_type) != 'string' ||
		!length(document.event_type) ||
		!valid_severity(document?.severity) ||
		type(document?.source) != 'string' ||
		!length(document.source) ||
		!valid_metadata(document?.metadata)
	) {
		return null;
	}

	const occurred_at = integer_value(document?.occurred_at, 0);
	if (occurred_at <= 0) {
		return null;
	}

	return {
		schema: 1,
		eventId: document.event_id,
		eventType: document.event_type,
		severity: document.severity,
		occurredAt: occurred_at,
		deviceUuid: type(document?.device_uuid) == 'string' && length(document.device_uuid)
			? document.device_uuid
			: null,
		source: document.source,
		metadata: document.metadata,
	};
}


function read_json_document(path) {
	const raw = fs.readfile(path);
	if (type(raw) != 'string' || !length(raw)) {
		return null;
	}

	try {
		const document = json(raw);
		return type(document) == 'object' && type(document) != 'array' ? document : null;
	}
	catch (e) {
		return null;
	}
}

function bool_config(value, fallback) {
	if (value == null || value == '') {
		return fallback;
	}
	return value == '1' || value == 'true' || value == 'on' || value == 'yes';
}

function cloud_sync_enabled() {
	const ctx = new_uci_cursor();
	if (ctx == null) {
		return true;
	}

	// Releases before r19 had no explicit toggle and always uploaded when paid.
	// Treat a missing option as enabled for upgrade compatibility, while fresh
	// r19 installations ship cloud_sync_enabled=0.
	return bool_config(ctx.get('smartsafehub', 'activity', 'cloud_sync_enabled'), true);
}

function license_cloud_entitlement() {
	const state = read_json_document(LICENSE_STATE_FILE);
	if (state == null) {
		return { eligible: null, plan: null };
	}

	const plan = type(state?.plan) == 'string' && length(state.plan) ? state.plan : null;
	if (state?.phase == 'active' && state?.deviceAction == 'none' &&
		(plan == 'pro' || plan == 'ultimate')) {
		return { eligible: true, plan: plan };
	}
	if (state?.phase == 'unconfigured' || state?.phase == 'cleared' || plan == 'free') {
		return { eligible: false, plan: plan };
	}

	return { eligible: null, plan: plan };
}

function invalid_cloud_sync_state() {
	return {
		phase: 'unknown',
		eligible: null,
		plan: null,
		retentionDays: 0,
		pendingEvents: 0,
		lastAttemptAt: 0,
		lastSuccessAt: 0,
		lastUploadedCount: 0,
		lastErrorCode: 'ACTIVITY_SYNC_STATE_INVALID',
		nextSyncAt: 0,
	};
}

function read_cloud_sync() {
	const enabled = cloud_sync_enabled();
	const entitlement = license_cloud_entitlement();
	const raw = fs.readfile(ACTIVITY_SYNC_STATE_FILE);
	let cloud;

	if (type(raw) != 'string' || !length(raw)) {
		cloud = {
			phase: enabled ? 'preparing' : 'disabled',
			eligible: entitlement.eligible,
			plan: entitlement.plan,
			retentionDays: 0,
			pendingEvents: 0,
			lastAttemptAt: 0,
			lastSuccessAt: 0,
			lastUploadedCount: 0,
			lastErrorCode: null,
			nextSyncAt: 0,
		};
	}
	else {
		try {
			const document = json(raw);
			if (type(document) != 'object' || document?.schema != 1) {
				cloud = invalid_cloud_sync_state();
			}
			else {
				cloud = {
					phase: type(document?.phase) == 'string' ? document.phase : 'unknown',
					eligible: type(document?.eligible) == 'bool' ? document.eligible : entitlement.eligible,
					plan: type(document?.plan) == 'string' && length(document.plan)
						? document.plan
						: entitlement.plan,
					retentionDays: integer_value(document?.retentionDays, 0),
					pendingEvents: integer_value(document?.pendingEvents, 0),
					lastAttemptAt: integer_value(document?.lastAttemptAt, 0),
					lastSuccessAt: integer_value(document?.lastSuccessAt, 0),
					lastUploadedCount: integer_value(document?.lastUploadedCount, 0),
					lastErrorCode: type(document?.lastErrorCode) == 'string' && length(document.lastErrorCode)
						? document.lastErrorCode
						: null,
					nextSyncAt: integer_value(document?.nextSyncAt, 0),
				};
			}
		}
		catch (e) {
			cloud = invalid_cloud_sync_state();
		}
	}

	cloud.enabled = enabled;
	if (!enabled) {
		cloud.phase = 'disabled';
		cloud.pendingEvents = 0;
		cloud.lastErrorCode = null;
		cloud.nextSyncAt = 0;
		if (cloud.eligible == null) {
			cloud.eligible = entitlement.eligible;
		}
		if (cloud.plan == null) {
			cloud.plan = entitlement.plan;
		}
	}

	return cloud;
}

function read_history_file() {
	let raw = fs.readfile(ACTIVITY_HISTORY_FILE);
	if (raw == null) {
		// 0.2.19-r8 used events.jsonl as both the future Cloud outbox and the
		// only local history. Keep those already collected events visible after
		// upgrading, while new events are written to the dedicated history file.
		raw = fs.readfile(LEGACY_EVENTS_FILE);
	}

	if (raw == null || length(raw) == 0) {
		return [];
	}
	if (length(raw) > MAX_ACTIVITY_FILE_BYTES) {
		return null;
	}

	const events = [];
	for (let line in split(raw, '\n')) {
		if (!length(line)) {
			continue;
		}

		try {
			const normalized = normalize_event(json(line));
			if (normalized != null) {
				push(events, normalized);
			}
		}
		catch (e) {
			// A partially written/corrupt record must not hide the remaining
			// valid local activity history from the UI.
		}
	}

	return events;
}

export function read_activity_history() {
	const history = read_history_file();
	if (history == null) {
		return failure(
			'ACTIVITY_HISTORY_TOO_LARGE',
			'최근 활동 기록의 크기가 허용 범위를 초과했습니다.'
		);
	}

	// status RPC has no activity limit argument. Always return the bounded local
	// history instead of coercing an omitted argument and accidentally clamping
	// the response to a single event on the target ucode runtime.
	const events = [];
	for (let index = length(history) - 1; index >= 0 && length(events) < MAX_ACTIVITY_EVENTS; index--) {
		push(events, history[index]);
	}

	return success({
		schema: 1,
		scope: 'current_boot',
		volatile: true,
		maxEvents: MAX_ACTIVITY_EVENTS,
		cloud: read_cloud_sync(),
		events: events,
	});
};

export function update_activity_cloud_sync(request) {
	const enabled = request.args.enabled;
	if (type(enabled) != 'bool') {
		return failure(
			'ACTIVITY_CLOUD_SYNC_ARGUMENT_INVALID',
			'Cloud 활동 기록 사용 여부가 올바르지 않습니다.'
		);
	}

	const current_enabled = cloud_sync_enabled();
	if (enabled) {
		const entitlement = license_cloud_entitlement();
		if (entitlement.eligible != true) {
			return failure(
				'ACTIVITY_CLOUD_SYNC_NOT_ELIGIBLE',
				'Cloud 활동 기록은 활성 Pro 또는 Ultimate 멤버십에서 사용할 수 있습니다.'
			);
		}
	}

	const ctx = new_uci_cursor();
	if (ctx == null || ctx.get_all('smartsafehub', 'activity') == null) {
		return failure(
			'ACTIVITY_CLOUD_SYNC_CONFIG_UNAVAILABLE',
			'Cloud 활동 기록 설정을 읽지 못했습니다.'
		);
	}

	if (
		ctx.set('smartsafehub', 'activity', 'cloud_sync_enabled', enabled ? '1' : '0') != true ||
		ctx.commit('smartsafehub') != true
	) {
		return failure(
			'ACTIVITY_CLOUD_SYNC_SAVE_FAILED',
			'Cloud 활동 기록 설정을 저장하지 못했습니다.'
		);
	}

	// Stop the daemon before applying the new runtime policy so an in-flight
	// uploader cannot race an explicit opt-out. The helper clears Cloud-only
	// outbox/credential state when disabled and preserves local history.
	run_command([ ACTIVITY_SYNC_INIT, 'stop' ], 20000);
	const applied = run_command([ ACTIVITY_SYNC_HELPER, 'apply-config' ], 5000);
	run_command([ ACTIVITY_SYNC_INIT, 'start' ], 5000);

	if (!applied) {
		return failure(
			'ACTIVITY_CLOUD_SYNC_APPLY_FAILED',
			'Cloud 활동 기록 실행 상태를 반영하지 못했습니다.'
		);
	}

	if (enabled) {
		// Prime entitlement/credential state immediately instead of making the
		// user wait for the normal daemon startup delay. This remains detached
		// from rpcd because license status-sync performs HTTPS I/O.
		run_command([
			'/bin/sh',
			'-c',
			ACTIVITY_SYNC_HELPER + ' sync-once >/dev/null 2>&1 </dev/null &',
		], 2000);
	}

	if (current_enabled != enabled) {
		emit_activity_event(
			'activity',
			enabled ? 'settings.activity_cloud_sync.enabled' : 'settings.activity_cloud_sync.disabled',
			'info',
			{ origin: 'direct' }
		);
	}

	return read_activity_history();
};
