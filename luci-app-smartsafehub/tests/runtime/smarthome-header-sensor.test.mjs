// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { featuredSensorView, selectFeaturedSensor } from '../../frontend/src/utils/featuredSensor.ts';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const sensor = (id, enabled = true) => ({ id, enabled, name: id, protocol: 'shelly_htg3' });
const bulb = { id: 'light', enabled: true, name: '전구', protocol: 'tasmota' };
const a = sensor('shelly_a');
const b = sensor('shelly_b');
const now = 1_800_000_000;
const reading = { id: a.id, observed: true, lastSeen: now - 60,
  temperatureC: 24.3, humidityPercent: 54, batteryPercent: 85 };

test('센서 0대에서는 대표 센서가 없고, 1대는 자동 선택한다', () => {
  assert.equal(selectFeaturedSensor([], null), null);
  assert.equal(selectFeaturedSensor([bulb], 'light'), null);
  assert.equal(selectFeaturedSensor([sensor('disabled', false)], null), null);
  assert.equal(selectFeaturedSensor([bulb, a], null)?.id, a.id);
});

test('저장된 대표 센서를 우선 사용하고 삭제·중지 후 활성 센서로 대체한다', () => {
  assert.equal(selectFeaturedSensor([a, b], b.id)?.id, b.id);
  assert.equal(selectFeaturedSensor([a], b.id)?.id, a.id);
  assert.equal(selectFeaturedSensor([a, sensor(b.id, false)], b.id)?.id, a.id);
  assert.equal(selectFeaturedSensor([sensor(a.id, false), b], a.id)?.id, b.id);
  assert.equal(selectFeaturedSensor([sensor(a.id, false), sensor(b.id, false)], b.id), null);
});

test('신뢰 가능한 측정값만 표시하며 3시간 지난 값은 오래됨으로 구분한다', () => {
  const view = featuredSensorView(a, reading, now);
  assert.equal(view?.temperature, '24.3 °C');
  assert.equal(view?.humidity, '54 %');
  assert.equal(view?.stale, false);
  assert.equal(featuredSensorView(a, { ...reading, lastSeen: now - 11_000 }, now)?.stale, true);
  assert.equal(featuredSensorView(a, { ...reading, id: b.id }, now), null);
  assert.equal(featuredSensorView(a, { ...reading, observed: false }, now), null);
  assert.equal(featuredSensorView(a, { ...reading, lastSeen: now + 90 }, now), null);
  assert.equal(featuredSensorView(a, { ...reading, temperatureC: 400, humidityPercent: -1 }, now), null);
  assert.equal(featuredSensorView(a, null, now), null);
});

test('헤더는 첫 기기 목록만 확인하고 센서가 없는 경우 후속 RPC나 반복 타이머가 없다', () => {
  const app = read('frontend/src/app/App.tsx');
  const hook = read('frontend/src/hooks/useFeaturedSensor.ts');
  const indicator = read('frontend/src/components/FeaturedSensorIndicator.tsx');
  assert.match(app, /active: true, \/\/ One small list fetch/);
  assert.match(app, /previousSmartHomeRoute\.current !== 'smarthome'/);
  assert.match(hook, /active: fallback !== null/);
  assert.match(hook, /if \(!selectedId \|\| smartHomeVisible\) return/);
  assert.match(hook, /SENSOR_CACHE_POLL_MS = 300_000/);
  assert.match(hook, /document\.visibilityState === 'hidden'/);
  assert.match(hook, /getJarbisSensorState\(selectedId, 'low'\)/);
  assert.doesNotMatch(indicator, /getJarbisSensorState|callApi|fetch\(/);
  assert.match(indicator, /href="#smarthome"/);
  assert.match(indicator, /data-stale=\{value\.stale/);
});

test('대표 선택은 공유기 UCI에 저장하며 선택 옵션은 센서 관리 메뉴에만 제공된다', () => {
  const page = read('frontend/src/pages/SmartHomePage.tsx');
  const card = read('frontend/src/components/SmartHomeSensorCard.tsx');
  const ucode = read('root/usr/share/rpcd/ucode/smartsafehub/smarthome.uc');
  const rpc = read('root/usr/share/rpcd/ucode/smartsafehub.uc');
  const acl = JSON.parse(read('root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json'))['luci-app-smartsafehub'];
  assert.match(page, /onSensorReading\?\.\(result\)/);
  assert.match(card, /대표 센서로 지정/);
  assert.match(card, /헤더에 표시 중/);
  assert.match(ucode, /'smartsafehub', 'smarthome', 'featured_sensor'/);
  assert.match(ucode, /\^\[A-Za-z0-9_-\]\*\$/);
  assert.match(rpc, /smarthome_featured_sensor_set/);
  assert.ok(acl.read.ubus.smartsafehub.includes('smarthome_featured_sensor'));
  assert.ok(acl.write.ubus.smartsafehub.includes('smarthome_featured_sensor_set'));
  assert.ok(!acl.read.ubus.smartsafehub.includes('smarthome_featured_sensor_set'));
});

test('대표 센서 ucode export 함수는 OpenWrt 컴파일러가 요구하는 세미콜론으로 끝난다', () => {
  const source = read('root/usr/share/rpcd/ucode/smartsafehub/smarthome.uc');
  assert.match(source, /return success\(\{ sensorId: valid_sensor_id\(value\)[^\n]+\}\);\s*\n\};\s*\n\s*export function update_featured_sensor\(request\)/);
  assert.match(source, /return success\(\{ sensorId: sensor_id \}\);\s*\n\};\s*$/);
});

test('데모 헤더는 가상 센서 값만 공유하고 실제 API를 요청하지 않는다', () => {
  const demo = read('frontend/src/demo/main.tsx');
  const header = read('frontend/src/components/ProductHeader.tsx');
  const shell = read('frontend/src/components/AppShell.tsx');
  const css = read('frontend/src/styles/app.css');
  assert.match(demo, /demoFeaturedReading = featuredSensorView/);
  assert.match(demo, /featuredSensor=\{demoFeaturedReading\}/);
  assert.doesNotMatch(demo, /from ['"]\.\.\/api\//);
  assert.match(shell, /featuredSensor=\{featuredSensor\}/);
  assert.match(header, /<FeaturedSensorIndicator value=\{featuredSensor\}/);
  assert.match(css, /\.ssh-app\[data-theme='dark'\] \.ssh-header-sensor/);
  assert.match(css, /@media \(min-width: 768px\) \{ \.ssh-header-sensor/);
});
