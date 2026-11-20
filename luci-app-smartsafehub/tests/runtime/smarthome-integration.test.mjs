// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { ROUTE_BY_NAME, DEMO_ROUTES } from '../../frontend/src/app/routes.ts';

const root = new URL('../../', import.meta.url);
const source = (p) => readFileSync(new URL(p, root), 'utf8');
const acl = JSON.parse(source('root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json'));
const app = source('frontend/src/app/App.tsx');
const login = source('root/usr/share/ucode/luci/template/smartsafehub/login.ut');
const nav = source('frontend/src/components/ProductNavigation.tsx');
const page = source('frontend/src/pages/SmartHomePage.tsx');
const api = source('frontend/src/api/jarbis.ts');

test('스마트홈 메뉴는 실제 공유기와 안전한 데모에 노출하고 Jarbis 미설치 시 안내한다', () => {
  assert.equal(ROUTE_BY_NAME.smarthome.hash, '#smarthome');
  assert.ok(DEMO_ROUTES.includes('smarthome'));
  assert.match(nav, /\{ label: 'Smart Home', routes: \['smarthome'\] \}/);
  assert.match(nav, /\{ label: 'Explore', routes: \['apps'\] \}/);
  assert.ok(nav.indexOf("{ label: 'Smart Home'") < nav.indexOf("{ label: 'Explore'"), '스마트홈은 Apps 앞에 독립 그룹으로 표시해야 합니다');
  assert.doesNotMatch(nav, /routes: \['smarthome', 'apps'\]/);
  assert.match(app, /case 'smarthome':[\s\S]*<SmartHomePage/);
  assert.match(page, /SmartHomeWelcome/);
  assert.match(source('frontend/src/components/SmartHomeWelcome.tsx'), /우리 집 조명을, 더 스마트하게/);
});

test('Jarbis RPC는 기존 세션 ACL로 전원·등록·검색·설정을 분리한다', () => {
  const group = acl['luci-app-smartsafehub'];
  const read = group.read.ubus.jarbis;
  const write = group.write.ubus.jarbis;
  assert.deepEqual(read, ['status', 'devices_list', 'light_state', 'discovery_list']);
  for (const method of ['settings_update','device_add','device_update','device_remove','device_pair','light_set','discovery_scan','broker_credentials']) {
    assert.ok(write.includes(method), `Jarbis write ACL missing: ${method}`);
    assert.ok(!read.includes(method), `Jarbis write leaked into read: ${method}`);
    assert.match(api, new RegExp(`'${method}'`));
  }
  assert.match(api, /scanJarbis = .*35000/);
});

test('명시적으로 승인한 기기만 등록하고 전원 명령을 실제 상태로 오인하지 않는다', () => {
  assert.match(page, /window\.confirm/);
  assert.match(page, /candidate\.registered/);
  assert.match(page, /candidate\.topic/);
  assert.match(page, /전구의 상태 응답에서 변경된 값을 확인했습니다/);
  assert.match(page, /확인되지 않은 값은 실제 상태로 표시하지 않습니다/);
  assert.match(page, /credentials \? '인증 정보 숨기기'/);
  assert.doesNotMatch(page, /localStorage|sessionStorage/);
  assert.doesNotMatch(api, /console\.log/);
});

test('스마트홈 MQTT 인증 정보는 컴포넌트 상태에 선언하고 화면을 떠나면 보관하지 않는다', () => {
  assert.match(page, /const \[credentials, setCredentials\] = useState<JarbisCredentials \| null>\(null\)/);
  assert.match(page, /setCredentials\(await getJarbisCredentials\(\)\)/);
  assert.match(page, /setCredentials\(null\)/);
  assert.doesNotMatch(app, /useAsyncResource<JarbisCredentials>/);
  assert.doesNotMatch(page, /localStorage|sessionStorage/);
});

test('MQTT 비밀번호는 Preact에서 허용하는 고정 input type으로 표시·숨기기를 전환한다', () => {
  assert.doesNotMatch(page, /type=\{reveal\s*\?/);
  assert.match(page, /\{reveal\s*\?\s*<input[^>]*type="text"[^>]*readOnly[^>]*aria-label="MQTT 비밀번호"/);
  assert.match(page, /:\s*<input[^>]*type="password"[^>]*readOnly[^>]*aria-label="MQTT 비밀번호"/);
  assert.match(page, /onClick=\{\(\) => setReveal\(!reveal\)\}/);
  assert.doesNotMatch(page, /<label[^>]*>MQTT 비밀번호/);
});


test('스마트 전구는 사용자 승인 후 자동 연결하고 관리자 암호를 저장하지 않는다', () => {
  assert.match(api, /pairJarbisDevice = /);
  assert.match(api, /'device_pair'/);
  assert.match(api, /replace_existing/);
  assert.match(page, /추가 및 자동 연결/);
  assert.match(page, /전구 웹 관리자 비밀번호/);
  assert.match(page, /기존 연결을 변경하는 데 동의/);
  assert.match(page, /mqttConfirmed/);
  assert.match(page, /setAdminPassword\(''\)/);
  assert.doesNotMatch(page, /localStorage|sessionStorage/);
  assert.doesNotMatch(api, /console\.log|console\.error/);
});


test('스마트홈은 공통 화면 제목과 서비스 토글, 등록 기기 중심의 반응형 카드로 표시한다', () => {
  assert.match(page, /<SectionHeading eyebrow="Smart Home" title="스마트 전구"/);
  assert.match(page, /aria-label="스마트홈 서비스 현황"/);
  assert.match(page, /role="switch" aria-checked=\{Boolean\(status\?\.enabled\)\}/);
  assert.match(page, /aria-label="등록된 전구"/);
  assert.match(page, /class="mt-4 grid grid-cols-1 gap-3 lg:grid-cols-2"/);
  assert.match(page, /type="range" min="0" max="100" step="5"/);
  assert.match(page, /aria-label="새 전구 찾기"/);
  assert.ok(page.indexOf('aria-label="등록된 전구"') < page.indexOf('aria-label="새 전구 찾기"'));
  assert.match(page, /availableCandidates = candidates.filter\(candidate => !candidate.registered\)/);
  assert.match(page, /aria-busy=\{busy === 'scan'\}/);
});

test('인증 비밀번호와 MQTT 비밀번호를 구분하고 실패할 때만 추가 옵션을 제안한다', () => {
  assert.match(page, /전구 웹 관리자 비밀번호 \(설정한 경우에만\)/);
  assert.match(page, /Configuration → Configure Other → Web Admin Password/);
  assert.match(page, /공유기 로그인 비밀번호나 MQTT 비밀번호가 아닙니다/);
  assert.match(page, /설정하지 않았다면 비워두세요/);
  assert.match(page, /pairOptionsVisible/);
  assert.match(page, /관리자 인증\|비밀번호\|기존 연결/);
  assert.match(page, /고급 설정 · 연결 진단/);
  assert.match(page, /이 비밀번호는 전구 웹 관리자 비밀번호와 다릅니다/);
  assert.match(page, /setAdminPassword\(''\)/);
  assert.doesNotMatch(page, /localStorage|sessionStorage|console\.(log|error)/);
});

test('MQTT 메시지 전송을 실제 전구 점등이나 연결 확정으로 표시하지 않는다', () => {
  assert.match(page, /전구 제어 연결/);
  assert.match(page, /연결 준비됨/);
  assert.match(page, /상태 응답 없음/);
  assert.match(page, /MQTT 응답이 없을 때는 검증된 내부망 HTTP 조회/);
  assert.match(page, /전구의 상태 응답에서 변경된 값을 확인했습니다/);
  assert.match(page, /mqttConfirmed/);
  assert.doesNotMatch(page, /'전구가 켜졌습니다'|'전구가 꺼졌습니다'/);
});

test('스마트홈 UI는 다른 화면과 동일한 다크 모드 토큰을 사용한다', () => {
  const css = source('frontend/src/styles/app.css');
  assert.match(page, /rounded-2xl border border-slate-200 bg-white/);
  assert.doesNotMatch(page, /bg-teal-50\/40|bg-slate-50\/60/);
  for (const token of ['bg-white','bg-slate-50','bg-teal-50','text-slate-900','border-slate-200']) {
    assert.ok(css.includes(`[class~='${token}']`), `${token}: 다크 모드 재정의가 필요합니다`);
  }
});


test('스마트홈 성공 알림은 5초 후 사라지고 직접 닫을 수 있으며 오류는 자동 삭제하지 않는다', () => {
  assert.match(page, /if \(!message\) return;/);
  assert.match(page, /window\.setTimeout\(\(\) => setMessage\(''\), 5000\)/);
  assert.match(page, /return \(\) => window\.clearTimeout\(timeout\)/);
  assert.match(page, /\}, \[message\]\)/);
  assert.match(page, /aria-label="성공 알림 닫기" onClick=\{\(\) => setMessage\(''\)\}/);
  assert.match(page, /role="status" aria-live="polite"/);
  assert.match(page, /role="status" aria-live="polite" class="flex w-full items-start/);
  assert.doesNotMatch(page, /sm:max-w-2xl/);
  assert.match(page, /role="alert" aria-live="assertive"/);
  assert.match(page, /onClick=\{\(\) => setError\(''\)\}/);
  assert.doesNotMatch(page, /setTimeout\(\(\) => setError/);
});

test('밝기 슬라이더는 조정값과 포인터를 놓았을 때만 명령을 적용한다', () => {
  assert.match(page, />밝기 조절<\/label>/);
  assert.match(page, /\{chosenBrightness\}%/);
  assert.match(page, /onPointerUp=\{event => void sendLight\(device, 'brightness', event\.currentTarget\.value\)\}/);
  assert.match(page, /전구에서 확인한 현재 밝기/);
});


test('스마트홈은 전구 상태 확인과 RGB·색온도를 제공하되 응답 없는 기기를 온라인으로 오인하지 않는다', () => {
  assert.match(api, /getJarbisLightState = .*'light_state'/);
  assert.match(page, /state\.observed/);
  assert.match(page, /전구에서 확인한 현재 밝기/);
  assert.match(page, /상태 응답 없음/);
  assert.match(page, /type="color"/);
  assert.match(page, /min="2700" max="6500" step="100"/);
  assert.match(page, /onPointerUp=/);
  assert.match(page, /document\.visibilityState === 'hidden'/);
  assert.match(page, /window\.setInterval\(poll, 30000\)/);
  assert.match(page, /class="mt-4 grid grid-cols-1 gap-3 lg:grid-cols-2"/);
});


test('전원은 단일 토글로 제어하고 상태 미확인 때도 요청값을 실제 상태로 표시하지 않는다', () => {
  assert.match(page, /role="switch" aria-checked=\{powerOn\}/);
  assert.match(page, /aria-label=\{`\$\{device\.name\} 전원`\}/);
  assert.match(page, /onClick=\{\(\) => void toggleBulbPower\(device, powerOn\)\}/);
  assert.match(page, /const powerOn = pendingPower \? pendingPower === 'ON' : confirmedPower === 'ON'/);
  assert.match(page, /if \(!sent\) \{/);
  assert.match(page, /전원 변경을 요청했습니다 · 실제 상태 확인 중/);
  assert.match(page, /실제 전원 상태 미확인/);
  assert.match(page, /응답 확인 · 전원 미확인/);
  assert.doesNotMatch(page, />전구 켜기<\/button>|>전구 끄기<\/button>/);
});

test('전원·RGB·밝기·색온도를 하나의 카드로 합쳐 조작 순서를 일관되게 유지한다', () => {
  const bulb = page.slice(page.indexOf('const controlsDisabled'));
  const power = bulb.indexOf('aria-label={`${device.name} 전원`}');
  const rgb = bulb.indexOf('for={`color-${device.id}`}');
  const brightness = bulb.indexOf('for={`brightness-${device.id}`}');
  const kelvin = bulb.indexOf('for={`kelvin-${device.id}`}');
  assert.ok(power > -1 && rgb > power && brightness > rgb && kelvin > brightness);
  assert.match(bulb, /aria-label="전구 조명 제어" class="mt-4 w-full min-w-0 space-y-3 rounded-xl bg-slate-50/);
  assert.match(bulb, /border-t border-slate-200 pt-3/);
});

test('성공 알림은 왼쪽에서 나타나고 관리 메뉴는 카드 배치를 밀지 않는다', () => {
  const notice = page.slice(page.indexOf('{message ?'), page.indexOf('aria-label="등록된 전구"'));
  assert.match(notice, /role="status" aria-live="polite"/);
  assert.doesNotMatch(notice, /justify-end/);
  assert.match(notice, /role="status" aria-live="polite" class="flex w-full items-start/);
  assert.doesNotMatch(notice, /sm:max-w-2xl/);
  assert.match(notice, /aria-label="성공 알림 닫기"/);
  assert.match(page, /<details ref=\{element => \{ manageMenus\.current\[device\.id\] = element; \}\}/);
  assert.match(page, /absolute left-0 top-full z-30/);
  assert.match(page, /<summary class=\{`\$\{secondaryButton\} cursor-pointer/);
  assert.match(page, /기기 사용 중지/);
  assert.match(page, /기기 삭제/);
});


test('전원 변경 중복 요청은 Promise<boolean> 계약을 지키고 실패로 처리한다', () => {
  const start = page.indexOf('const sendLight = async');
  const end = page.indexOf('const toggleBulbPower =', start);
  const sendLight = page.slice(start, end);
  assert.match(sendLight, /Promise<boolean>\s*=>/);
  assert.match(sendLight, /if \(busy\) return false;/);
  assert.match(sendLight, /return true;/);
  assert.doesNotMatch(sendLight, /\breturn\s*;/);
  assert.match(page, /if \(!sent\) \{/);
});


test('전구 조작은 중첩 배경 카드 없이 하나의 영역에 전원·색상·밝기·색온도를 표시한다', () => {
  const start = page.indexOf('aria-label="전구 조명 제어"');
  const end = page.indexOf('전구 연결 설정', start);
  assert.ok(start > -1 && end > start, '전구 제어 영역을 찾을 수 있어야 합니다');
  const controls = page.slice(start, end);
  const labels = ['전구 전원', 'RGB 색상', '밝기 조절', '색온도'];
  let offset = -1;
  for (const label of labels) {
    const found = controls.indexOf(label);
    assert.ok(found > offset, `${label}: 이전 조작 다음에 표시해야 합니다`);
    offset = found;
  }
  assert.equal((controls.match(/rounded-xl bg-slate-50 p-3 sm:p-4/g) || []).length, 1, '제어 배경 카드는 하나여야 합니다');
  assert.doesNotMatch(controls, /grid-cols-2|space-y-4 rounded-xl bg-slate-50/, '조작 항목을 별도의 좌우 카드로 분리하지 않습니다');
  assert.match(controls, /role="switch" aria-checked=\{powerOn\}/);
  assert.match(controls, /type="color"/);
  assert.match(controls, /type="range" min="0" max="100"/);
  assert.match(controls, /type="range" min="2700" max="6500"/);
});


test('알림은 전체 너비이고 등록 전구 카드만 PC에서 두 열로 표시한다', () => {
  const noticeStart = page.indexOf('{message ?');
  const noticeEnd = page.indexOf('aria-label="등록된 전구"', noticeStart);
  const notice = page.slice(noticeStart, noticeEnd);
  assert.match(notice, /role="status" aria-live="polite" class="flex w-full items-start/);
  assert.doesNotMatch(notice, /sm:max-w-2xl|max-w-\[760px\]|lg:grid-cols-2/, '성공 알림은 데스크톱에서도 전체 너비를 유지해야 합니다');

  const inventoryStart = page.indexOf('aria-label="등록된 전구"');
  const inventoryEnd = page.indexOf('devices.map(device =>', inventoryStart);
  const inventory = page.slice(inventoryStart, inventoryEnd);
  assert.match(inventory, /class="mt-4 grid grid-cols-1 gap-3 lg:grid-cols-2"/, '전구 한 대는 데스크톱에서 절반 너비, 모바일에서는 전체 너비로 표시해야 합니다');
  assert.doesNotMatch(inventory, /max-w-\[760px\]/, '개별 전구 너비는 그리드로 정하고 고정 폭을 사용하지 않아야 합니다');

  const controlsStart = page.indexOf('aria-label="전구 조명 제어"');
  const controlsEnd = page.indexOf('전구 연결 설정', controlsStart);
  const controls = page.slice(controlsStart, controlsEnd);
  assert.ok(controlsStart > inventoryEnd && controlsEnd > controlsStart, '전구 제어 영역이 등록 카드 안에 있어야 합니다');
  assert.match(controls, /class="mt-4 w-full min-w-0 /, '전구 내부 제어 영역은 카드 너비를 가득 사용해야 합니다');
  assert.doesNotMatch(controls, /max-w-\[760px\]|lg:grid-cols-2|sm:grid-cols-2/, '내부 제어 영역만 임의로 줄이거나 분리하면 안 됩니다');
  for (const label of ['전구 전원', 'RGB 색상', '밝기 조절', '색온도']) {
    assert.ok(controls.includes(label), `${label}: 통합 제어 항목을 유지해야 합니다`);
  }
});

test('관리 메뉴는 바깥 클릭과 Escape로 닫고 전구 카드 조작은 유지한다', () => {
  assert.match(page, /document\.addEventListener\('pointerdown', onOutside\)/);
  assert.match(page, /document\.removeEventListener\('pointerdown', onOutside\)/);
  assert.match(page, /document\.addEventListener\('keydown', onEscape\)/);
  assert.match(page, /event\.key === 'Escape'/);
  assert.match(page, /!menu\.contains\(target\)/);
  assert.match(page, /manageMenus\.current\[device\.id\]/);
});

test('스마트홈은 상태 응답이 없으면 실제 점등으로 오인하지 않고 검증된 HTTP 상태도 받아들인다', () => {
  const types = source('frontend/src/types/jarbis.ts');
  assert.match(types, /source\?: 'mqtt' \| 'http' \| null/);
  assert.match(page, /observed\?\.source === 'http'/);
  assert.match(page, /상태 응답 없음/);
  assert.match(page, /검증된 내부망 HTTP 조회/);
  assert.match(page, /const confirmedPower = observed\?\.observed === true/);
});


test('전구 상태 API는 HTTP 우선 결과와 실패 원인을 구분하고 지나치게 짧은 시간 제한을 사용하지 않는다', () => {
  const types = source('frontend/src/types/jarbis.ts');
  assert.match(types, /reason\?: 'HTTP_NO_CANDIDATE'/);
  assert.match(api, /'light_state', \{ id \}, 11500/);
  assert.match(page, /function statusFailureHint/);
  assert.match(page, /HTTP_FETCH_FAILED/);
  assert.match(page, /HTTP_INVALID_STATE/);
  assert.match(page, /statusFailureHint\(observed\?\.reason\)/);
});


test('스마트홈은 세 자원을 독립적으로 준비하고 재방문에서 기존 데이터를 즉시 재사용한다', () => {
  const resource = source('frontend/src/hooks/useAsyncResource.ts');
  for (const declaration of [
    'const jarbisStatus = useAsyncResource<JarbisStatus>',
    'const jarbisDevices = useAsyncResource<{ devices: JarbisDevice[] }>',
    'const jarbisCandidates = useAsyncResource<{ devices: JarbisCandidate[] }>',
  ]) {
    assert.ok(app.includes(declaration), declaration);
  }
  assert.equal((app.match(/active: route === 'smarthome'/g) ?? []).length, 3);
  assert.match(app, /<SmartHomePage statusResource=\{jarbisStatus\}/);
  assert.match(app, /devicesResource=\{jarbisDevices\} candidatesResource=\{jarbisCandidates\}/);
  assert.match(resource, /const fresh = state\.data !== null/);
  assert.match(resource, /if \(!fresh\) void load\(\);/);
  assert.doesNotMatch(page, /if \(loading\) return <LoadingPanel \/>/);
  assert.doesNotMatch(page, /getJarbisStatus\(\)\.then\(async fresh/);
});

test('스마트홈의 느린 검색 API는 등록 전구를 가리지 않고 비어 있다고 오인하지 않는다', () => {
  assert.match(page, /!deviceData \? <div aria-busy=\{devicesResource\.loading\}/);
  assert.match(page, /!candidateData \? <div role="status" aria-busy=\{candidatesResource\.loading\}/);
  assert.match(page, /deviceData \? devices\.length : '—'/);
  assert.match(page, /const \[fresh\] = await Promise\.all\(\[/);
  assert.match(page, /statusResource\.replaceData\(result\)/);
  assert.match(page, /devicesResource\.replaceData\(result\)/);
  assert.match(page, /candidatesResource\.replaceData\(result\)/);
  assert.match(page, /onRetry=\{\(\) => void retry\(\)\}/);
  assert.match(page, /smartHomeEntry\(status, statusResource.error, appsStatus, appsCatalog/);
});

test('사용자의 전구 명령이 느린 상태 폴링보다 먼저 처리되고 늦게 도착한 응답을 방지한다', () => {
  const resource = source('frontend/src/hooks/useAsyncResource.ts');
  assert.match(api, /getJarbisStatus = \(signal\?: AbortSignal\).*'normal', signal/);
  assert.match(api, /getJarbisDevices = \(signal\?: AbortSignal\).*'normal', signal/);
  assert.match(api, /getJarbisCandidates = \(signal\?: AbortSignal\).*'normal', signal/);
  assert.match(page, /getJarbisLightState\(id, background \? 'low' : 'high'\)/);
  assert.match(page, /map\(id => refreshLight\(id, true\)\)/);
  assert.match(page, /candidatesResource\.replaceData\(result\);/);
  assert.match(resource, /const replaceData = useCallback[\s\S]*generation\.current \+= 1;[\s\S]*controller\.current\?\.abort\(\)/);
});
