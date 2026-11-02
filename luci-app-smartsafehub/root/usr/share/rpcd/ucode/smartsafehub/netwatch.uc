// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import * as fs from 'fs';
import { emit_activity_event, failure, new_uci_cursor, success } from './core.uc';

const STATUS_FILE = '/tmp/smartsafehub/netwatch/status.json';
const MAX_STATUS_BYTES = 8192;

function empty_status(enabled) {
	return {
		schema: 1, enabled: enabled,
		phase: enabled ? 'preparing' : 'disabled',
		sampledAt: 0, intervalSeconds: 60, source: 'conntrack',
		ipv4Only: true, limited: false, totalConnections: 0,
		totalDevices: 0, devices: [], alert: null,
	};
}

function enabled_setting() {
	const ctx = new_uci_cursor();
	if (ctx == null) return false;
	return ctx.get('smartsafehub', 'netwatch', 'enabled') != '0';
}

export function read_netwatch_status(request) {
	const enabled = enabled_setting();
	const empty = empty_status(enabled);
	if (!enabled) return success(empty);
	const raw = fs.readfile(STATUS_FILE);
	if (type(raw) != 'string' || !length(raw) || length(raw) > MAX_STATUS_BYTES)
		return success(empty);
	try {
		const value = json(raw);
		if (type(value) != 'object' || value?.schema != 1 ||
			!match(value?.phase ?? '', /^(ready|unavailable|disabled)$/) ||
			type(value?.devices) != 'array' || length(value.devices) > 12) {
			empty.phase = 'unavailable';
			return success(empty);
		}
		if (value.phase == 'ready' &&
			(type(value.sampledAt) != 'int' || time() - value.sampledAt > 300 || value.sampledAt > time() + 30)) {
			empty.phase = 'unavailable';
			return success(empty);
		}
		value.enabled = true;
		if (value.phase == 'disabled') value.phase = 'preparing';
		return success(value);
	}
	catch (e) {
		empty.phase = 'unavailable';
		return success(empty);
	}
};

export function update_netwatch_enabled(request) {
	const enabled = request?.args?.enabled;
	if (type(enabled) != 'bool')
		return failure('NETWATCH_INVALID_SETTING', '네트워크 관찰 설정이 올바르지 않습니다.');
	const ctx = new_uci_cursor();
	if (ctx == null || ctx.get_all('smartsafehub', 'netwatch') == null)
		return failure('NETWATCH_CONFIG_UNAVAILABLE', 'Network Watch 설정을 읽지 못했습니다.');
	const previous = enabled_setting();
	if (ctx.set('smartsafehub', 'netwatch', 'enabled', enabled ? '1' : '0') != true ||
		ctx.commit('smartsafehub') != true)
		return failure('NETWATCH_SAVE_FAILED', 'Network Watch 설정을 저장하지 못했습니다.');
	if (previous != enabled)
		emit_activity_event('network_watch', enabled ? 'settings.netwatch.enabled' : 'settings.netwatch.disabled', 'info', { origin: 'direct' });
	return read_netwatch_status(request);
};
