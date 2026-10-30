import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname, extname } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../frontend/src');
const visited = new Set();

function inspectImports(path) {
  if (visited.has(path)) return;
  visited.add(path);
  const source = readFileSync(path, 'utf8');
  // Follow executable imports only; TypeScript `import type` never reaches JS.
  const regex = /^\s*import\s+(?!type\b)(?:[^;]*?\bfrom\s+)?["'](\.[^"']+)["']/gm;
  for (const [, local] of source.matchAll(regex)) {
    const base = resolve(dirname(path), local);
    const target = extname(base) ? base : `${base}.tsx`;
    let resolved = target;
    try { readFileSync(resolved); } catch { resolved = `${base}.ts`; }
    assert.ok(!resolved.includes('/api/'), `API dependency in demo: ${resolved}`);
    assert.ok(!resolved.includes('/auth/'), `Authentication dependency in demo: ${resolved}`);
    inspectImports(resolved);
  }
}

test('standalone demo has no executable RPC/auth dependency', () => {
  inspectImports(resolve(root, 'demo/main.tsx'));
  assert.ok(visited.size > 10, 'Presentational components must be traversed');
});

test('fictional MAC addresses and documentation IP ranges are used', () => {
  const fixtures = readFileSync(resolve(root, 'demo/data.ts'), 'utf8');
  assert.match(fixtures, /02:00:00:00:00:01/);
  assert.match(fixtures, /198\.51\.100\.20/);
  assert.doesNotMatch(fixtures, /172\.16\.3\./);
});

test('public demo routes and fixture-backed pages match navigation', () => {
  const routes = readFileSync(resolve(root, 'app/routes.ts'), 'utf8');
  const app = readFileSync(resolve(root, 'demo/main.tsx'), 'utf8');
  const sidebar = readFileSync(resolve(root, 'components/ProductNavigation.tsx'), 'utf8');
  const required = ['home', 'activity', 'network', 'wifi', 'devices', 'safeshield', 'rules', 'system'];
  for (const route of required) {
    assert.match(routes, new RegExp(`'${route}'`));
    if (route !== 'home') assert.ok(app.includes(`case '${route}':`), `missing demo route ${route}`);
  }
  for (const component of ['ActivityPage', 'WanPage', 'LanPage', 'WifiPage', 'SafeShieldRulesPage', 'UpdatePage']) {
    assert.ok(app.includes(`<${component}`), `missing real page ${component}`);
  }
  assert.ok(sidebar.includes('DEMO_ROUTES.includes(name)'), 'navigation must share allowed demo routes');
  assert.match(app, /text-teal-800/, 'dark theme must map the notice text color');
  assert.doesNotMatch(app, /text-teal-900/, 'notice would become illegible in dark mode');
});

test('demo actions never call RPC and Wi-Fi credentials are injected', () => {
  const app = readFileSync(resolve(root, 'demo/main.tsx'), 'utf8');
  const qr = readFileSync(resolve(root, 'components/WifiQrDialog.tsx'), 'utf8');
  const data = readFileSync(resolve(root, 'demo/data.ts'), 'utf8');
  assert.match(app, /const disabledAction = async \(\): Promise<boolean> => \{/);
  assert.match(app, /return false;/);
  for (const prop of ['onSave', 'onUpdate', 'onUpdateGuest', 'onAddRule', 'onDeleteRule', 'onSaveSettings', 'onUpload']) {
    assert.ok(app.includes(`${prop}={disabledAction}`) || (prop === 'onUpload' && app.includes('upload: disabledAction')), `unsafe demo action: ${prop}`);
  }
  assert.doesNotMatch(qr, /from ['"]\.\.\/api\//);
  assert.match(qr, /void load\(\)\.then/);
  assert.match(data, /demoWifiQr = async/);
  assert.match(data, /demoGuestWifiQr = async/);
});

// The shared rules page must remain presentational: only the authenticated
// app supplies the status reader, never the fixture-backed public demo.
test('추천 규칙 API 조회는 실제 공유기 앱에서만 주입된다', () => {
  const page = readFileSync(resolve(root, 'pages/SafeShieldRulesPage.tsx'), 'utf8');
  const app = readFileSync(resolve(root, 'app/App.tsx'), 'utf8');
  const demo = readFileSync(resolve(root, 'demo/main.tsx'), 'utf8');
  assert.doesNotMatch(page, /from ['"]\.\.\/api\//);
  assert.match(page, /if \(!onLoadRecommendedRulesStatus\) return;/);
  assert.match(app, /onLoadRecommendedRulesStatus=\{fetchRecommendedRulesStatus\}/);
  assert.doesNotMatch(demo, /onLoadRecommendedRulesStatus=/);
});


test('SmartSafeHub Account and Apps use fictional fixtures, not live APIs', () => {
  const routes = readFileSync(resolve(root, 'app/routes.ts'), 'utf8');
  const app = readFileSync(resolve(root, 'demo/main.tsx'), 'utf8');
  const fixtures = readFileSync(resolve(root, 'demo/data.ts'), 'utf8');
  assert.match(routes, /'rules', 'account', 'apps', 'system'/);
  for (const [route, component] of [['account', 'SmartSafeHubAccountPage'], ['apps', 'AppsPage']]) {
    assert.match(app, new RegExp(`case '${route}':`));
    assert.ok(app.includes(`<${component}`), `${component} not reused by demo`);
    assert.match(app, new RegExp(`<${component}[^;]*?demo`, 's'));
  }
  for (const fixture of ['demoAccount', 'demoApps', 'demoAppsStatus', 'demoAppsMetrics']) {
    assert.ok(fixtures.includes(`export const ${fixture}:`), `missing ${fixture}`);
    assert.ok(app.includes(fixture), `unused ${fixture}`);
  }
  assert.match(fixtures, /accountRegistered: true/);
  assert.match(fixtures, /pairingCode: null/);
  assert.match(fixtures, /id: 'network-usage-monitor'/);
  assert.match(fixtures, /id: 'retro-arcade'/);
  assert.match(fixtures, /id: 'wake-on-lan'/);
  assert.match(fixtures, /category: 'entertainment'/);
  const newFixtures = fixtures.slice(fixtures.indexOf('export const demoAccount:'), fixtures.indexOf('export const demoDevices:'));
  assert.doesNotMatch(newFixtures, /https?:\/\/|\/cgi-bin\/|password|token|api_key/i);
  assert.match(app, /accountRegistered=\{demoAccount\.accountRegistered\}/);
});

test('demo showcases verified Apps versions, upgrade badge, and installed sizes without changing router state', () => {
  const fixtures = readFileSync(resolve(root, 'demo/data.ts'), 'utf8');
  const catalog = fixtures.split('export const demoApps: AppsCatalog = {')[1].split('export const demoAppsStatus:')[0];
  const status = fixtures.split('export const demoAppsStatus: AppsInstallStatus = {')[1].split('export const demoAppsMetrics:')[0];
  const metrics = fixtures.split('export const demoAppsMetrics: AppsMetrics = {')[1].split('export const demoDevices:')[0];

  assert.ok(catalog.indexOf("id: 'retro-arcade'") < catalog.indexOf("id: 'network-usage-monitor'"),
    'demo card ordering should match the actual Apps page');
  assert.match(catalog, /id: 'retro-arcade',[\s\S]*?version: '1\.1\.0-r5'/);
  assert.match(catalog, /id: 'network-usage-monitor',[\s\S]*?version: '2025\.06\.02~29236be6-r1'/);
  assert.match(catalog, /id: 'wake-on-lan',[\s\S]*?category: 'utilities',[\s\S]*?version: '26\.288\.56989~75a306d'/);
  assert.ok(catalog.indexOf("id: 'network-usage-monitor'") < catalog.indexOf("id: 'wake-on-lan'"));
  assert.match(status, /'wake-on-lan': \{\s*installed: false,\s*partial: false,\s*managed: false/);

  assert.match(status, /'retro-arcade': \{\s*installed: true,\s*partial: false,\s*managed: true,\s*updateAvailable: true,\s*installedVersion: '1\.0\.0-r1'/);
  assert.match(status, /'network-usage-monitor': \{\s*installed: true,\s*partial: false,\s*managed: true,\s*updateAvailable: false,\s*installedVersion: '2025\.06\.02~29236be6-r1'/);
  assert.match(metrics, /'retro-arcade': 1394688/);
  assert.match(metrics, /'network-usage-monitor': 117760/);
  assert.match(fixtures, /storage: demoAppsMetrics\.storage/,
    'dashboard disk and Apps donut must share the same fictional storage');

  const demo = readFileSync(resolve(root, 'demo/main.tsx'), 'utf8');
  assert.match(demo, /installStatus=\{demoAppsStatus\} metrics=\{demoAppsMetrics\}/);
  assert.match(demo, /onUpdate=\{async \(\) => \{ readonlyNotice\(\); \}\}/);
});

test('Apps 카테고리 아이콘은 공유기와 데모에서 동일하고 도구와 기타가 구분된다', () => {
  const page = readFileSync(resolve(root, 'pages/AppsPage.tsx'), 'utf8');
  const category = readFileSync(resolve(root, 'components/AppsCategoryIcon.tsx'), 'utf8');
  const icons = readFileSync(resolve(root, 'components/Icons.tsx'), 'utf8');
  const demo = readFileSync(resolve(root, 'demo/main.tsx'), 'utf8');
  assert.match(demo, /<AppsPage data=\{demoApps\}/);
  assert.match(page, /<AppsCategoryIcon category=\{tab\.id\}/);
  assert.match(page, /<AppsCategoryIcon category=\{appsCategoryOf\(app\.category\)\}/);
  assert.match(page, /\{ id: 'utilities', label: '도구' \}/);
  assert.match(page, /\{ id: 'other', label: '기타' \}/);
  assert.match(category, /case 'utilities': return <WrenchIcon/);
  assert.match(category, /case 'other': return <CircleEllipsisIcon/);
  assert.match(category, /default: return 'other'/);
  assert.match(category, /default: return <CircleEllipsisIcon/);
  assert.match(icons, /export function WrenchIcon/);
  assert.match(icons, /export function CircleEllipsisIcon/);
  assert.match(icons, /export function NetworkNodesIcon/);
  assert.doesNotMatch(category, /PowerIcon|PuzzleIcon/);
});

test('public demo actions never install APKs, pair an account, or open a live app', () => {
  const demo = readFileSync(resolve(root, 'demo/main.tsx'), 'utf8');
  const apps = readFileSync(resolve(root, 'pages/AppsPage.tsx'), 'utf8');
  const account = readFileSync(resolve(root, 'pages/SmartSafeHubAccountPage.tsx'), 'utf8');
  assert.match(demo, /onDemoAction=\{readonlyNotice\}/);
  assert.match(demo, /onRequestPairing=\{async \(\) => \{ readonlyNotice\(\); return null; \}\}/);
  for (const action of ['onInstall', 'onRemove', 'onUpdate']) {
    assert.ok(demo.includes(`${action}={async () => { readonlyNotice(); }}`), `${action} must be a no-op`);
  }
  assert.match(apps, /if \(demo\) \{/);
  assert.match(apps, /if \(action === 'remove'\) closeRemoveDialog\(\)/);
  assert.match(apps, /onDemoAction\?\.\(\);/);
  assert.match(apps, /launchPath \? \(demo \?/);
  assert.match(apps, /onClick=\{onDemoAction\} type="button">열기/);
  assert.match(account, /demo \? \(/);
  assert.match(account, /onClick=\{onDemoAction\}/);
  assert.match(account, /href=\{DEVICE_CONSOLE_URL\}/);
  assert.doesNotMatch(demo, /import .*from ['"]\.\.\/api\//);
});

test('README links to the public router demo', () => {
  const readme = readFileSync(resolve(root, '../../README.md'), 'utf8');
  assert.match(readme, /https:\/\/www\.smartsafehub\.com\/router-demo\//);
});
