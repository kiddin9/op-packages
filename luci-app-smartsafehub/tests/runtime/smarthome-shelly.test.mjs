// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { sensorReading, sensorReportLabel } from '../../frontend/src/utils/shellySensor.ts';

const read = (p) => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8');
const page = read('frontend/src/pages/SmartHomePage.tsx');
const api = read('frontend/src/api/jarbis.ts');
const acl = JSON.parse(read('root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json'));
const demo = read('frontend/src/demo/jarbis.ts');

test('Shelly 센서는 등록 feature gate가 있고 MQTT 값 수신은 읽기 RPC로만 한다', () => {
  assert.match(page, /const supportsShelly = status\?\.features\?\.shellyHtg3 === true/);
  assert.match(page, /if \(isSensor && !supportsShelly\)/);
  assert.match(page, /\(candidate\.protocol === 'shelly_htg3' && !supportsShelly\)/);
  assert.match(page, /isShellyHtg3\(device\)/);
  assert.match(page, /온습도 센서 연결 안내/);
  assert.match(page, /현재 Jarbis는 Shelly 센서를 지원하지 않습니다/);
  assert.match(page, /!listed\.devices\.some\(device => device\.id === id && isShellyHtg3\(device\)\)/);
  assert.match(api, /'device_add', protocol[\s\S]*kind: 'sensor'/);
  assert.match(api, /'sensor_state', \{ id \}, 6500, priority/);
  assert.ok(acl['luci-app-smartsafehub'].read.ubus.jarbis.includes('sensor_state'));
  assert.ok(!acl['luci-app-smartsafehub'].write.ubus.jarbis.includes('sensor_state'));
});

test('전구 30초 조회와 달리 센서는 5분 간격으로만 캐시 조회한다', () => {
  assert.match(page, /const stateIds = lights\.filter/);
  assert.match(page, /const sensorIds = sensors\.filter/);
  assert.match(page, /setInterval\(poll, 30000\)/);
  assert.match(page, /largeHome \? 30000 : 300000/);
  assert.match(page, /nextHomePollBatch\(ids, cursor, largeHome \? 2 : ids.length\)/);
  assert.match(page, /getJarbisSensorState\(id, background \? 'low' : 'normal'\)/);
  assert.match(page, /if \(demo \|\| !status\?\.enabled \|\| !supportsShelly \|\| !sensorIds\) return/);
  assert.match(page, /if \(!background\) setError\(errorMessage\(cause\)\)/);
  assert.doesNotMatch(page, /localStorage|sessionStorage/);
});

test('데모는 외부 RPC 없이 로컬 측정값만 사용한다', () => {
  assert.match(demo, /getJarbisSensorState: async \(id\) => demoJarbisSensorStates\[id\]/);
  assert.match(demo, /getJarbisCredentials: blocked/);
  assert.match(read('frontend/src/demo/main.tsx'), /demoSensorStates=\{demoJarbisSensorStates\}/);
});

test('NaN, 비정상 온습도, 미래/오래된 보고를 측정값으로 꾸미지 않는다', () => {
  assert.equal(sensorReading(23.46, '°C', -40, 125), '23.5 °C');
  assert.equal(sensorReading(0, '%', 0, 100), '0 %');
  assert.equal(sensorReading(100, '%', 0, 100), '100 %');
  assert.equal(sensorReading(-2.5, '°C', -40, 125), '-2.5 °C');
  for (const n of [NaN, Infinity, -Infinity, 101, null]) {
    assert.equal(sensorReading(n, '%', 0, 100), '—');
  }
  const now = 1_800_000_000;
  assert.equal(sensorReportLabel(now - 60, now).stale, false);
  assert.equal(sensorReportLabel(now - 3 * 3600, now).stale, false);
  assert.equal(sensorReportLabel(now - 3 * 3600 - 1, now).stale, true);
  assert.equal(sensorReportLabel(now + 120, now).label, '측정 시각 미확인');
  assert.equal(sensorReportLabel(null, now).stale, true);
});
