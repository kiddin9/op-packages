// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

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
