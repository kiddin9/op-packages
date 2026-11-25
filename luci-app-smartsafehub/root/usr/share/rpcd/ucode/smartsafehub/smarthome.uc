// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';

import { failure, new_uci_cursor, success } from './core.uc';

// Only a reference to a Jarbis device, never an MQTT credential or sensor
// reading, is stored in SmartSafeHub configuration. No Jarbis RPC is needed.
function valid_sensor_id(value) {
	return type(value) == 'string' && length(value) <= 64 &&
		match(value, /^[A-Za-z0-9_-]*$/) != null;
}

export function read_featured_sensor() {
	const ctx = new_uci_cursor();
	if (ctx == null)
		return failure('SMARTHOME_CONFIG_UNAVAILABLE', '대표 센서 설정을 읽지 못했습니다.');

	const value = ctx.get('smartsafehub', 'smarthome', 'featured_sensor');
	return success({ sensorId: valid_sensor_id(value) ? (value ?? '') : '' });
};

export function update_featured_sensor(request) {
	const sensor_id = request?.args?.sensor_id;
	if (!valid_sensor_id(sensor_id))
		return failure('SMARTHOME_SENSOR_INVALID', '대표 센서 정보가 올바르지 않습니다.');

	const ctx = new_uci_cursor();
	if (ctx == null)
		return failure('SMARTHOME_CONFIG_UNAVAILABLE', '대표 센서 설정을 읽지 못했습니다.');

	const current = ctx.get('smartsafehub', 'smarthome', 'featured_sensor') ?? '';
	if (current === sensor_id) return success({ sensorId: sensor_id });

	if (ctx.get_all('smartsafehub', 'smarthome') == null &&
		ctx.set('smartsafehub', 'smarthome', 'smarthome') != true)
		return failure('SMARTHOME_SAVE_FAILED', '대표 센서를 저장하지 못했습니다.');

	if (ctx.set('smartsafehub', 'smarthome', 'featured_sensor', sensor_id) != true ||
		ctx.commit('smartsafehub') != true)
		return failure('SMARTHOME_SAVE_FAILED', '대표 센서를 저장하지 못했습니다.');

	return success({ sensorId: sensor_id });
};
