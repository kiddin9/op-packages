// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';

import { connect } from 'ubus';
import { cursor } from 'uci';

// The ucode module loader caches this module, so all feature modules share one
// ubus connection for the lifetime of the rpcd plugin.
const ubus = connect();
const ACTIVITY_EVENTS_HELPER = '/usr/libexec/smartsafehub-events';

function call_result(object, method, args) {
	try {
		return {
			ok: true,
			data: ubus.call(object, method, args ?? {}) ?? {},
		};
	}
	catch (e) {
		return {
			ok: false,
			data: {},
		};
	}
}

export function safe_call(object, method, args) {
	return call_result(object, method, args).data;
};

export function defer_call(object, method, args, callback) {
	try {
		return ubus.defer(object, method, args ?? {}, callback);
	}
	catch (e) {
		return null;
	}
};

export function success(data) {
	return {
		ok: true,
		data: data,
		error: null,
	};
};

export function failure(code, message) {
	return {
		ok: false,
		data: null,
		error: {
			code: code,
			message: message,
		},
	};
};

export function string_value(value, fallback) {
	return type(value) == 'string' && length(value) ? value : fallback;
};

// Shared parser for RPC fields. Unlike number_value (already numeric-only),
// this accepts numeric UCI strings; invalid values and NaN use the fallback.
export function integer_value(value, fallback) {
	// int(null) and int('') may coerce to zero; absent values are not zero.
	if (value === null || (type(value) == 'string' && !length(value))) {
		return fallback;
	}
	const parsed = int(value);
	const kind = type(parsed);
	// ucode's loose equality coerces NaN, so use strict equality here.
	return (kind == 'int' || kind == 'double') && parsed === parsed
		? parsed
		: fallback;
};

// Small local JSON objects only. Callers choose an optional byte limit.
export function read_json_object(path, max_bytes) {
	const raw = fs.readfile(path);
	if (type(raw) != 'string' || !length(raw) ||
		(max_bytes != null && length(raw) > max_bytes)) {
		return null;
	}
	try {
		const document = json(raw);
		return type(document) == 'object' && type(document) != 'array' ? document : null;
	}
	catch (e) {
		return null;
	}
};

export function number_value(value) {
	const value_type = type(value);

	return value_type == 'int' || value_type == 'double' ? value : 0;
};

export function memory_value(memory, key) {
	return number_value(memory?.[key]);
};

export function new_uci_cursor() {
	const ctx = cursor();

	return ctx ?? null;
};

export function run_command(argv, timeout) {
	try {
		return system(argv, timeout ?? 10000) == 0;
	}
	catch (e) {
		return false;
	}
};

export function emit_activity_event(source, event_type, severity, metadata) {
	if (type(source) != 'string' || type(event_type) != 'string' || type(severity) != 'string') {
		return false;
	}

	const document = type(metadata) == 'object' && type(metadata) != 'array' ? metadata : {};
	const emitted = run_command([
		ACTIVITY_EVENTS_HELPER,
		'emit-quiet',
		source,
		event_type,
		severity,
		sprintf('%J', document),
	], 5000);

	if (!emitted) {
		warn(sprintf(
			'smartsafehub: activity event emit failed: source=%s event_type=%s\n',
			source,
			event_type
		));
	}

	return emitted;
};
