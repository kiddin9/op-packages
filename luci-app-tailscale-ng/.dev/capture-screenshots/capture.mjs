import { chromium } from 'playwright';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { rpcReply, menu, identity } from './fixtures.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const bash = process.env.BASH_PATH || (process.platform === 'win32' ? path.join(process.env.ProgramFiles || 'C:/Program Files', 'Git/bin/bash.exe') : 'bash');
const width = 1280;
const imageDir = path.join(root, 'docs/images');
const reportFile = path.join(here, 'report.json');
const sha = value => createHash('sha256').update(value).digest('hex');
const report = { width, screenshots: [], mockedCalls: {}, unexpected: [], pageErrors: [], blockedProbes: [] };
let probing = false;
const realHostLabels = new Set();
const captures = new Map();
let completed = false;

function router(script) {
  const res = spawnSync(bash, ['.dev/router-ssh/router-ssh.sh', 'exec-command'], {
    cwd: root, input: `${script}\n# End of input\n`, encoding: 'utf8', timeout: 30000, windowsHide: true
  });
  if (res.error || res.status !== 0) throw new Error('Router SSH operation failed');
  return res.stdout.trim();
}

const envResult = spawnSync(bash, ['-c', 'source .dev/router-ssh/target.env; printf "%s" "$ROUTER_HOST"'], {
  cwd: root, encoding: 'utf8', timeout: 10000, windowsHide: true
});
if (envResult.status !== 0 || !envResult.stdout.trim()) throw new Error('Cannot read router target');
const host = envResult.stdout.trim();
const base = process.env.LUCI_URL || `http://${host.includes(':') ? `[${host}]` : host}`;
const origin = new URL(base).origin;
if (new URL(base).protocol !== 'http:') throw new Error('Screenshot capture currently requires HTTP LuCI access');
const pagePath = '/cgi-bin/luci/admin/vpn/tailscale-ng';
const sourcePath = '/luci-static/resources/view/tailscale-ng/index.js';
const workingSource = await readFile(path.join(root, 'htdocs/luci-static/resources/view/tailscale-ng/index.js'), 'utf8');
const makefile = await readFile(path.join(root, 'Makefile'), 'utf8');
const version = /^PKG_VERSION:=(.+)$/m.exec(makefile)?.[1].trim();
if (!version) throw new Error('Missing package version');
const expectedSource = workingSource.replaceAll('@APP_VERSION@', version);
const configHashes = () => router('sha256sum /etc/config/luci /etc/config/tailscale /etc/config/luci-app-tailscale-ng');
const before = configHashes();
let session;
let browser;
let context;
let cleanupError;

try {
  // The real session only authorizes page rendering. No real ubus/file/uci rights are granted.
  const auth = JSON.parse(router(`ucode - <<'UCODE'
import { connect } from 'ubus';
let b = connect();
let s = b.call('session', 'create', { timeout: 300 });
if (!s?.ubus_rpc_session) die('Session creation failed');
let id = s.ubus_rpc_session;
b.call('session', 'set', { ubus_rpc_session: id, values: { username: 'root', token: id } });
b.call('session', 'grant', { ubus_rpc_session: id, scope: 'access-group', objects: [ ['luci-base', 'read'], ['luci-app-tailscale-ng', 'read'], ['luci-app-tailscale-ng', 'write'] ] });
let fileAccess = b.call('session', 'access', { ubus_rpc_session: id, scope: 'ubus', object: 'file', function: 'exec' });
let uciAccess = b.call('session', 'access', { ubus_rpc_session: id, scope: 'ubus', object: 'uci', function: 'set' });
print({ id, realRpcDenied: fileAccess?.access == false && uciAccess?.access == false });
UCODE`));
  session = auth.id;
  if (!/^[0-9a-f]{32}$/.test(session || '')) throw new Error('Invalid temporary session');
  if (!auth.realRpcDenied) throw new Error('Screenshot session unexpectedly permits real mutations');
  report.realRpcDenied = true;
  browser = await chromium.launch({ headless: true });
  report.browserVersion = browser.version();
  context = await browser.newContext({
    viewport: { width, height: 900 }, deviceScaleFactor: 1,
    locale: 'en-US', timezoneId: 'UTC', colorScheme: 'light', serviceWorkers: 'block'
  });
  await context.addCookies([{ name: 'sysauth_http', value: session, url: origin, httpOnly: true, sameSite: 'Strict' }]);
  await context.route('**/*', async route => {
    const req = route.request();
    const url = new URL(req.url());
    try {
      if (url.origin === origin && (url.pathname.startsWith('/cgi-bin/luci/admin/ubus') || url.pathname === '/ubus/')) {
        const body = req.postDataJSON();
        const reply = item => {
          if (item.method === 'list') return { jsonrpc: '2.0', id: item.id, result: [0, {}] };
          if (item.method !== 'call') throw new Error(`Unmapped RPC envelope: ${item.method}`);
          const [, object, method, args = {}] = item.params;
          const key = `${object}.${method}`;
          report.mockedCalls[key] = (report.mockedCalls[key] || 0) + 1;
          return { jsonrpc: '2.0', id: item.id, result: [0, rpcReply(object, method, args)] };
        };
        return await route.fulfill({ json: Array.isArray(body) ? body.map(reply) : reply(body) });
      }
      if (url.origin === 'https://api.github.com') {
        return await route.fulfill({ json: { tag_name: `v${version}`, draft: false, prerelease: false } });
      }
      if (url.origin === origin && url.pathname === '/cgi-bin/luci/admin/menu')
        return await route.fulfill({ json: { children: menu } });
      if (url.origin === origin && url.pathname === '/cgi-bin/luci/admin/translations/en' && req.method() === 'GET')
        return await route.fulfill({ response: await route.fetch() });
      if (url.origin === origin && url.pathname === pagePath && req.method() === 'GET') {
        const response = await route.fetch({ maxRedirects: 0 });
        if (response.status() !== 200) throw new Error(`LuCI document HTTP ${response.status()}`);
        const originalHtml = await response.text();
        const brandPattern = /(<a\b[^>]*\bclass=["'][^"']*\bbrand\b[^"']*["'][^>]*>)([\s\S]*?)(<\/a>)/gi;
        const html = originalHtml
          .replace(/<title>[\s\S]*?<\/title>/i, '<title>OpenWrt - Tailscale NG</title>')
          .replace(brandPattern, (_, open, label, close) => {
            if (label.trim() !== 'OpenWrt') realHostLabels.add(label.replace(/<[^>]*>/g, '').trim());
            return `${open}OpenWrt${close}`;
          });
        if (!html.includes('tailscale-ng/index')) throw new Error('Authenticated LuCI view missing');
        return await route.fulfill({ response, body: html });
      }
      if (url.origin === origin && url.pathname.startsWith('/luci-static/') && req.method() === 'GET') {
        if (url.pathname === sourcePath) {
          const response = await route.fetch();
          if (await response.text() !== expectedSource) throw new Error('Router JS differs from working tree: use Deploy Files first');
          report.sourceSha256 = sha(expectedSource);
          return await route.fulfill({ response });
        }
        return await route.fulfill({ response: await route.fetch() });
      }
      throw new Error(`Unmapped request: ${req.method()} ${url.pathname}`);
    } catch (error) {
      (probing ? report.blockedProbes : report.unexpected).push(error.message.replaceAll(session, '[session]').replaceAll(origin, '[router]'));
      await route.abort();
    }
  });
  const page = await context.newPage();
  report.consoleErrors = [];
  report.failedResponses = [];
  page.on('console', msg => {
    if (!probing && msg.type() === 'error') report.consoleErrors.push(msg.text().replaceAll(session, '[session]').replaceAll(origin, '[router]'));
  });
  page.on('response', res => {
    if (res.status() >= 400) report.failedResponses.push({ path: new URL(res.url()).pathname, status: res.status() });
  });
  page.on('pageerror', error => report.pageErrors.push(error.message.replaceAll(session, '[session]').replaceAll(origin, '[router]')));
  await page.clock.setFixedTime(new Date('2026-01-15T12:00:00Z'));
  await page.goto(`${origin}${pagePath}`, { waitUntil: 'domcontentloaded' });
  const waitReady = async () => {
    await page.locator('h2').filter({ hasText: 'Tailscale NG' }).waitFor({ timeout: 20000 });
    await page.getByText(identity.displayName, { exact: true }).waitFor({ state: 'attached', timeout: 20000 });
    await page.locator('#topmenu').getByText('VPN', { exact: true }).waitFor();
    await page.evaluate(() => document.fonts.ready);
    if (report.unexpected.length) throw new Error(report.unexpected.join('; '));
    if (report.pageErrors.length) throw new Error('Page JavaScript error');
  };
  await waitReady();
  // Explicit conditions, rather than networkidle: LuCI deliberately polls in the background.
  for (let pass = 1; pass <= 2; pass++) {
    for (const [tab, label] of [['auth', 'Authentication'], ['settings', 'Settings'], ['status', 'Status']]) {
      await page.locator(`.cbi-tabmenu li[data-tab="${tab}"] a`).click();
      await page.locator(`.cbi-tabmenu li.cbi-tab[data-tab="${tab}"]`).waitFor();
      if (tab === 'status') {
        await page.locator('#tailscale_status').filter({ hasText: identity.hostname }).waitFor();
        await page.locator('#tailscale_dns_status').filter({ hasText: identity.domain }).waitFor();
        await page.locator('#tailscale_netcheck').filter({ hasText: '203.0.113.10' }).waitFor();
      }
      await page.evaluate(() => { document.activeElement?.blur(); window.scrollTo(0, 0); });
      await page.mouse.move(0, 0);
      await page.evaluate(() => document.fonts.ready);
      const visible = await page.locator('body').innerText();
      if (await page.locator('a.brand').innerText() !== 'OpenWrt' || [...realHostLabels].some(label => label && visible.includes(label)))
        throw new Error('Router hostname was not replaced');
      if (await page.locator('html').evaluate(el => el.scrollWidth) > width)
        throw new Error('Horizontal overflow would change capture width');
      if (report.unexpected.length || report.pageErrors.length || report.consoleErrors.length || report.failedResponses.length)
        throw new Error('Capture blocked by unexpected request, failed resource or page error');
      const pixels = await page.screenshot({ fullPage: true, animations: 'disabled', caret: 'hide', scale: 'css' });
      const filename = `tailscale-ng-${tab}.png`;
      if (pass === 1) captures.set(filename, pixels);
      const entry = { file: filename, pass, label, width: pixels.readUInt32BE(16), height: pixels.readUInt32BE(20), sha256: sha(pixels) };
      if (entry.width !== width) throw new Error('Unexpected screenshot width');
      report.screenshots.push(entry);
    }
    if (pass === 1) {
      const callsBeforePoll = report.mockedCalls['file.exec'];
      const deadline = Date.now() + 20000;
      while (report.mockedCalls['file.exec'] < callsBeforePoll + 6) {
        if (Date.now() > deadline) throw new Error('Expected background status refresh did not occur');
        await new Promise(resolve => setTimeout(resolve, 250));
      }
      report.backgroundRefreshObserved = true;
    }
  }
  report.identicalRepeatedCaptures = ['auth', 'settings', 'status'].every(tab =>
    report.screenshots.find(s => s.file === `tailscale-ng-${tab}.png` && s.pass === 1).sha256 ===
    report.screenshots.find(s => s.file === `tailscale-ng-${tab}.png` && s.pass === 2).sha256);
  if (!report.identicalRepeatedCaptures) throw new Error('Repeated captures differ');
  probing = true;
  // These deliberately unmapped operations must fail before reaching the router.
  const blocked = await page.evaluate(async () => {
    const attempts = [
      ['/ubus/', { method: 'POST', body: JSON.stringify({ jsonrpc: '2.0', id: 9001, method: 'call', params: ['screenshot-probe', 'file', 'exec', { command: '/bin/false', params: [] }] }) }],
      ['/cgi-bin/luci/admin/screenshot-unmapped-probe', { method: 'GET' }]
    ];
    return await Promise.all(attempts.map(async ([url, options]) => {
      try { await fetch(url, options); return false; } catch { return true; }
    }));
  });
  report.unknownRequestsBlocked = blocked.every(Boolean) && report.blockedProbes.length === 2;
  if (!report.unknownRequestsBlocked) throw new Error('Unknown request was not blocked');
  report.hostnameReplaced = true;
  completed = true;
} finally {
  await context?.close().catch(() => {});
  await browser?.close().catch(() => {});
  if (session) {
    try {
      router(`ubus call session destroy '{"ubus_rpc_session":"${session}"}'`);
      const remaining = router(`ubus call session list '{"ubus_rpc_session":"${session}"}' 2>/dev/null || true`);
      if (remaining.includes(session)) throw new Error('Temporary session still exists');
      report.temporarySessionDestroyed = true;
    } catch { cleanupError = new Error('Temporary session cleanup failed'); }
  }
  report.configsUnchanged = before === configHashes();
  report.success = completed && report.configsUnchanged && report.temporarySessionDestroyed === true && !cleanupError;
  if (report.success) {
    await mkdir(imageDir, { recursive: true });
    for (const [filename, pixels] of captures) await writeFile(path.join(imageDir, filename), pixels);
  }
  await writeFile(reportFile, JSON.stringify(report, null, 2) + '\n');
  if (report.success) {
    for (const shot of report.screenshots.filter(shot => shot.pass === 1))
      console.log(`${shot.file}: ${shot.width} x ${shot.height}`);
    console.log(`Capture checks passed. Images: ${path.relative(root, imageDir)}; report: ${path.relative(root, reportFile)}`);
  } else {
    console.error(`Capture failed; previous PNGs were not replaced. See ${path.relative(root, reportFile)}`);
  }
  if (cleanupError) throw cleanupError;
  if (!report.configsUnchanged) throw new Error('Router configuration changed');
}
