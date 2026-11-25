// SPDX-License-Identifier: GPL-3.0-or-later
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hasRecentSensorMqttReading, isSensorWakeRequired } from '../../frontend/src/utils/shellySensor.ts';

const page = readFileSync(new URL('../../frontend/src/pages/SmartHomePage.tsx', import.meta.url), 'utf8');
const id = 'shelly_shellyhtg3_083af2d1329c';
const now = 1795406000;
const state = { id, observed: true, source: 'mqtt', temperatureC: 24.3, humidityPercent: 54,
  batteryPercent: 100, lastSeen: now - 420 };

test('MQTT 측정값이 있는 절전 센서는 실패로 표시하지 않는다', () => {
  assert.equal(isSensorWakeRequired({ code: 'WAKE_REQUIRED', message: '센서가 절전 중입니다.' }), true);
  assert.equal(hasRecentSensorMqttReading(state, id, now), true);
  assert.match(page, /if \(isSensorWakeRequired\(cause\)\)/);
  assert.match(page, /getJarbisSensorState\(id, 'normal'\)/);
  assert.match(page, /setMessage\('센서의 온습도 측정값이 정상적으로 수신되고 있습니다/);
  assert.match(page, /setSensorNotice\(old => old\?\.id === id \? null : old\)/);
});

test('오래된 값·HTTP 값·다른 기기·잘못된 값은 MQTT 연결 증거가 아니다', () => {
  assert.equal(hasRecentSensorMqttReading({ ...state, source: 'http' }, id, now), false);
  assert.equal(hasRecentSensorMqttReading({ ...state, lastSeen: now - 10801 }, id, now), false);
  assert.equal(hasRecentSensorMqttReading({ ...state, lastSeen: now + 120 }, id, now), false);
  assert.equal(hasRecentSensorMqttReading({ ...state, id: 'other' }, id, now), false);
  assert.equal(hasRecentSensorMqttReading({ ...state, observed: false }, id, now), false);
  assert.equal(hasRecentSensorMqttReading({ ...state, temperatureC: null, humidityPercent: null, batteryPercent: null }, id, now), false);
});

test('다른 연결 오류와 절전 안내는 구분하며 절전 중인 경우 빨간 오류를 표시하지 않는다', () => {
  assert.equal(isSensorWakeRequired({ code: 'BROKER_CONFLICT', message: 'another server' }), false);
  assert.equal(isSensorWakeRequired({ code: 'HTTP_CONFIG_FAILED', message: 'failed' }), false);
  assert.equal(isSensorWakeRequired(new Error('센서가 절전 중입니다.')), false);
  assert.equal(isSensorWakeRequired(null), false);
  assert.match(page, /setSensorNotice\(\{ id, text: '센서가 절전 중이라/);
  assert.match(page, /sensorNotice && sensors\.some/);
  assert.match(page, /role="status" aria-live="polite" class="flex items-start gap-2 rounded-xl border border-amber/);
  assert.match(page, /setError\(explanation\)/);
});
