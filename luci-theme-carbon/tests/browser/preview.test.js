'use strict';

/*
 * Browser tests against the static preview (no router needed):
 *   npm install && npx playwright install chromium && npm run test:browser
 *
 * - tests/navigation.html regression page at phone width
 * - preview pages in zh/en × light/dark × desktop/phone: no script errors,
 *   screenshots written to .cache/screenshots for review
 * - dashboard data (devices, Wi‑Fi, IPv6, sensors, traffic picker)
 * - keyboard / touch / drawer accessibility
 * - the minified release build computes the same styles as the sources
 */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { execFileSync } = require('node:child_process');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '..', '..');
const SHOTS = path.join(ROOT, '.cache', 'screenshots');
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.json': 'application/json' };

let server, base, browser, minRoot;

function serve(roots) {
	return http.createServer((req, res) => {
		const url = new URL(req.url, 'http://x');
		const [, mount, ...rest] = url.pathname.split('/');
		const root = roots[mount];
		const file = root && path.resolve(root, decodeURIComponent(rest.join('/')));
		if (!file || !file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
			res.writeHead(404); res.end(); return;
		}
		res.writeHead(200, { 'content-type': (TYPES[path.extname(file)] || 'application/octet-stream') + '; charset=utf-8' });
		fs.createReadStream(file).pipe(res);
	});
}

test.before(async () => {
	minRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'carbon-min-'));
	for (const dir of ['htdocs', 'preview'])
		fs.cpSync(path.join(ROOT, dir), path.join(minRoot, dir), { recursive: true });
	execFileSync(process.execPath, [path.join(ROOT, 'scripts', 'minify.mjs'), minRoot], { stdio: 'pipe' });
	server = serve({ src: ROOT, min: minRoot });
	await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
	base = 'http://127.0.0.1:' + server.address().port;
	browser = await chromium.launch({ executablePath: process.env.CARBON_TEST_BROWSER || undefined });
	fs.mkdirSync(SHOTS, { recursive: true });
});

test.after(async () => {
	if (browser) await browser.close();
	if (server) server.close();
	if (minRoot) fs.rmSync(minRoot, { recursive: true, force: true });
});

async function open(url, { width = 1280, height = 900, appearance = 'light', storage = {}, touch = false } = {}) {
	const context = await browser.newContext({ viewport: { width, height }, hasTouch: touch, colorScheme: appearance === 'dark' ? 'dark' : 'light' });
	await context.addInitScript((items) => {
		for (const [k, v] of Object.entries(items)) localStorage.setItem(k, v);
	}, Object.assign({ 'carbon.appearance': appearance }, storage));
	const page = await context.newPage();
	const errors = [];
	page.on('pageerror', (e) => errors.push(e.message));
	page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
	await page.goto(base + url);
	return { page, context, errors };
}

/* every async source has rendered: leases, Wi‑Fi stations, sensors, CPU cores, languages */
const dashboardReady = (page) => page.waitForFunction(() =>
	document.querySelectorAll('.cb-clients .cb-list li').length >= 8 && document.querySelector('.cb-tag-wifi') &&
	document.querySelectorAll('.cb-kv li').length >= 2 && document.querySelector('.cb-load-badge') &&
	document.querySelector('.cb-lang .cb-lb'));

test('side-router discovery works without DHCP and distinguishes neighbours, gateways and lease records', async () => {
	const mock = fs.readFileSync(path.join(ROOT, 'preview', 'mock.js'), 'utf8');
	for (const scenario of [
		{ proto: 'static', leases: 'empty', lang: 'en' },
		{ proto: 'dhcp', leases: 'empty', lang: 'en' },
		{ proto: 'dhcp', leases: 'unavailable', lang: 'en' },
		{ proto: 'static', leases: 'retained', lang: 'en' },
		{ proto: 'dhcp', leases: 'empty', lang: 'zh-Hans' }
	]) {
		const context = await browser.newContext();
		const page = await context.newPage();
		const errors = [];
		page.on('pageerror', (e) => errors.push(e.message));
		try {
			await page.route('**/preview/mock.js', (route) => route.fulfill({
				contentType: 'text/javascript',
				body: mock + '\n(' + ((s) => {
					Object.assign(window.CarbonPreview.provider, {
						interfaces: async () => [
							{ interface: 'lan', up: true, proto: s.proto, device: 'br-lan', route: [{ target: '0.0.0.0', mask: 0, nexthop: '192.168.1.1' }] },
							{ interface: 'wan', up: true, proto: 'static', device: 'eth1', route: [{ target: '0.0.0.0', mask: 0, nexthop: '10.0.0.1' }] }
						],
						leases: async () => {
							if (s.leases === 'unavailable') throw new Error('DHCP RPC unavailable');
							return { dhcp_leases: s.leases === 'retained' ? [
								{ hostname: 'lease-only', ipaddr: '192.168.1.30', macaddr: '00:11:32:aa:bb:30', expires: 3600 }
							] : [], dhcp6_leases: [] };
						},
						wireless: async () => ({}),
						hostHints: async () => ({}),
						neighbors: async () => [
							'IP address HW type Flags HW address Mask Device',
							'192.168.1.1 0x1 0x2 00:11:32:aa:bb:01 * br-lan',
							'192.168.1.20 0x1 0x2 00:11:32:aa:bb:20 * br-lan',
							'10.0.0.1 0x1 0x2 00:11:32:aa:bb:91 * eth1',
							'10.0.0.20 0x1 0x2 00:11:32:aa:bb:92 * eth1'
						].join('\n')
					});
				}).toString() + ')(' + JSON.stringify(scenario) + ');'
			}));
			await page.goto(base + '/src/preview/index.html?lang=' + scenario.lang);
			const count = scenario.leases === 'retained' ? '3' : '2';
			await page.waitForFunction((n) => document.querySelector('.cb-count')?.textContent === n, count);
			const zh = scenario.lang === 'zh-Hans';
			const clients = await page.textContent('.cb-clients');
			assert.match(clients, zh ? /已发现设备/ : /Discovered devices/);
			assert.match(clients, zh ? /网关/ : /Gateway/);
			assert.match(clients, zh ? /邻居记录/ : /Neighbor entry/);
			assert.doesNotMatch(clients, /Fixed IP|固定 IP|10\.0\.0\./);
			if (scenario.leases === 'retained') assert.match(clients, /DHCP lease · 1h 0m left/);
			assert.equal(await page.textContent('.cb-tile-val'), count);
			assert.equal(await page.textContent('.cb-tile-sub'), zh ? '本机已知设备' : 'Known to this router');
			assert.equal(await page.getAttribute('.cb-tile-head span[title]', 'title'), zh ? '可能包含离线设备。' : 'May include offline devices.');
			assert.equal(await page.evaluate(() => document.querySelector('.cb-wireless').classList.contains('hidden')), true, 'no wireless radio hides the wireless card');
			assert.equal(await page.evaluate(() => document.querySelector('.cb-interfaces').classList.contains('span-12')), true, 'interfaces fills the row when wireless is absent');
			assert.deepEqual(errors, []);
		} finally { await context.close(); }
	}
});

test('device speeds preserve leases, handle missing data and pause when hidden', async () => {
	const mock = fs.readFileSync(path.join(ROOT, 'preview', 'mock.js'), 'utf8');
	const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
	const page = await context.newPage();
	try {
		await page.route('**/preview/mock.js', (route) => route.fulfill({ contentType: 'text/javascript', body: mock + '\n(' + (() => {
			window.trafficReads = 0;
			window.trafficFail = false;
			window.CarbonPreview.provider.deviceTraffic = async () => {
				window.trafficReads++;
				if (window.trafficFail) throw new Error('collector unavailable');
				return { source: 'nftables', interval: 5, columns: ['mac', 'rx_bytes', 'tx_bytes'], data: [
					['A6:83:E7:2C:91:0F', window.trafficReads * 10240, window.trafficReads * 5120],
					['00:11:22:33:44:99', 99999999, 99999999]
				] };
			};
		}).toString() + ')();' }));
		await page.clock.install();
		await page.goto(base + '/src/preview/index.html?lang=en');
		await dashboardReady(page);
		const phone = page.locator('.cb-clients li').filter({ hasText: 'iPhone-15-Pro' });
		const laptop = page.locator('.cb-clients li').filter({ hasText: 'MacBook-Air' });
		assert.match(await phone.textContent(), /DHCP lease · 10h 33m left/);
		assert.equal(await phone.locator('.cb-device-rates').textContent(), '↓ —↑ —');
		assert.equal(await page.textContent('.cb-device-rate-note'), 'Device speeds · nftables · Waiting for next sample');
		const count = await page.textContent('.cb-count');
		await page.clock.runFor(5100);
		assert.match(await phone.locator('.cb-device-rates').textContent(), /↓ [\d.]+ KB\/s↑ [\d.]+ [KB]+\/s/);
		assert.equal(await laptop.locator('.cb-device-rates').textContent(), '↓ —↑ —');
		assert.equal(await page.textContent('.cb-count'), count, 'historical traffic cannot create devices');
		assert.match(await phone.textContent(), /DHCP lease · 10h 33m left/);
		assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
		await page.screenshot({ path: path.join(SHOTS, 'device-speeds-phone.png'), fullPage: true });
		await page.evaluate(() => {
			Object.defineProperty(document, 'hidden', { configurable: true, value: true });
			document.dispatchEvent(new Event('visibilitychange'));
		});
		const reads = await page.evaluate(() => window.trafficReads);
		await page.clock.runFor(20000);
		assert.equal(await page.evaluate(() => window.trafficReads), reads);
		await page.evaluate(() => {
			Object.defineProperty(document, 'hidden', { configurable: true, value: false });
			document.dispatchEvent(new Event('visibilitychange'));
		});
		await page.clock.runFor(5000);
		assert.equal(await phone.locator('.cb-device-rates').textContent(), '↓ —↑ —', 'resume establishes a fresh baseline');
		await page.clock.runFor(5000);
		assert.match(await phone.locator('.cb-device-rates').textContent(), /KB\/s/);
		await page.evaluate(() => { window.trafficFail = true; });
		await page.clock.runFor(5000);
		assert.equal(await phone.locator('.cb-device-rates').textContent(), '↓ —↑ —');
		assert.equal(await page.textContent('.cb-device-rate-note'), 'Device speeds · nftables · Unavailable');
		const failedReads = await page.evaluate(() => window.trafficReads);
		await page.clock.runFor(55000);
		assert.equal(await page.evaluate(() => window.trafficReads), failedReads, 'failed sources back off for a minute');
		assert.match(await phone.textContent(), /DHCP lease/);
		await page.evaluate(() => { window.trafficFail = false; });
		await page.clock.runFor(5000);
		assert.equal(await phone.locator('.cb-device-rates').textContent(), '↓ —↑ —');
		await page.clock.runFor(5000);
		assert.match(await phone.locator('.cb-device-rates').textContent(), /KB\/s/);
		assert.match(await page.textContent('.cb-device-rate-note'), /^Device speeds · nftables · \d+ s average$/);
	} finally { await context.close(); }
});

test('default preview preserves the original device speed label', async () => {
	const { page, context, errors } = await open('/src/preview/index.html?lang=zh-Hans');
	try {
		await dashboardReady(page);
		await page.waitForFunction(() => document.querySelector('.cb-device-rate-note:not(.hidden)')?.textContent.startsWith('设备网速'));
		assert.match(await page.textContent('.cb-device-rate-note'), /^设备网速 · (?!nlbwmon|nftables)/);
		assert.deepEqual(errors, []);
	} finally { await context.close(); }
});

test('firmware without a traffic collector keeps the device list without misleading zero speeds', async () => {
	const mock = fs.readFileSync(path.join(ROOT, 'preview', 'mock.js'), 'utf8');
	const context = await browser.newContext();
	const page = await context.newPage();
	try {
		await page.route('**/preview/mock.js', (route) => route.fulfill({ contentType: 'text/javascript',
			body: mock + '\nwindow.CarbonPreview.provider.deviceTraffic = async () => { throw new Error("unsupported"); };' }));
		await page.goto(base + '/src/preview/index.html?lang=en');
		await dashboardReady(page);
		assert.equal(await page.locator('.cb-device-rate-note').isVisible(), false);
		assert.equal(await page.locator('.cb-device-rates:visible').count(), 0);
		assert.match(await page.textContent('.cb-clients'), /DHCP lease/);
	} finally { await context.close(); }
});

test('navigation regression page passes at phone width', async () => {
	const { page, context } = await open('/src/tests/navigation.html', { width: 390, height: 844 });
	await page.waitForFunction(() => /^(PASS|FAIL)/.test(document.title));
	const results = await page.textContent('#results');
	assert.match(await page.title(), /^PASS/, results);
	await context.close();
});

for (const lang of ['zh-Hans', 'en']) {
	for (const appearance of ['light', 'dark']) {
		for (const [device, width, height] of [['desktop', 1440, 1000], ['phone', 390, 844]]) {
			test(`preview ${lang} ${appearance} ${device} renders without errors`, async () => {
				const { page, context, errors } = await open(`/src/preview/index.html?lang=${lang}`, { width, height, appearance });
				await dashboardReady(page);
				assert.equal(await page.getAttribute('html', 'data-darkmode'), appearance === 'dark' ? 'true' : 'false');
				if (device === 'phone') {
					const widths = await page.$$eval('.cb-clients .cb-list-main', (els) => els.map((e) => e.getBoundingClientRect().width));
					assert.ok(widths.every((w) => w >= 90), 'lease labels and badges leave room for device names: ' + widths);
				}
				await page.screenshot({ path: path.join(SHOTS, `overview-${lang}-${appearance}-${device}.png`), fullPage: true });
				assert.deepEqual(errors, []);
				await context.close();
			});
		}
	}
}

test('dashboard shows merged devices, Wi-Fi details, IPv6, sensors and a traffic picker', async () => {
	const { page, context } = await open('/src/preview/index.html?lang=en');
	await dashboardReady(page);
	const info = await page.evaluate(() => ({
		count: document.querySelector('.cb-count').textContent,
		wifiTags: document.querySelectorAll('.cb-tag-wifi').length,
		nas: [...document.querySelectorAll('.cb-list-title')].some((e) => e.textContent === 'DiskStation'),
		gateway: document.body.textContent.includes('100.64.0.1') && [...document.querySelectorAll('.cb-list .cb-mono')].some((e) => e.textContent === '100.64.0.1'),
		ipv6: !document.querySelector('.cb-ip6').closest('.cb-meta').classList.contains('hidden') && document.querySelector('.cb-ip6').textContent,
		sensors: [...document.querySelectorAll('.cb-kv li')].map((li) => li.firstChild.textContent).filter((t) => t.startsWith('Temperature')),
		tile: document.querySelector('.cb-tile .cb-tile-sub').textContent
	}));
	assert.equal(info.count, '17');
	assert.ok(info.wifiTags >= 3, 'Wi-Fi tags among the first eight devices');
	assert.ok(info.nas, 'static-IP device from ARP named by host hints');
	assert.equal(info.gateway, false, 'upstream gateway is not a LAN device');
	assert.equal(info.ipv6, '240e:3a1:4c2:8f0::1');
	assert.deepEqual(info.sensors, ['Temperature']);
	assert.match(info.tile, /^\d+ on Wi-Fi$/);

	/* the traffic picker is a Carbon listbox (same control as the language switch), grouped like <optgroup> */
	const picker = '.cb-card.cb-traffic .cb-lb.cb-traffic-select';
	const listed = async () => {
		await page.click(picker);
		await page.waitForSelector('.cb-lb-list.show');
		return page.evaluate(() => {
			const ul = document.querySelector('.cb-lb-list');
			return {
				options: [...ul.querySelectorAll('[role="option"]')].map((li) => li.textContent),
				groups: [...ul.querySelectorAll('.cb-lb-group')].map((li) => li.textContent)
			};
		});
	};
	let list = await listed();
	assert.equal(list.options.length, 10);
	assert.match(list.options[0], /^Auto/);
	assert.deepEqual(list.groups, ['Interfaces', 'Network devices']);
	assert.ok(list.options.includes('LAN (br-lan)') || list.options.some((o) => o.endsWith('(br-lan)')));
	await page.click('.cb-lb-list li[role="option"]:has-text("(br-lan)")');
	assert.equal(await page.evaluate(() => localStorage.getItem('carbon.traffic')), 'br-lan');
	assert.match(await page.textContent(picker), /\(br-lan\)$/);
	/* a physical port (e.g. an xPON uplink) is selectable and survives the next refresh */
	list = await listed();
	await page.click('.cb-lb-list li[role="option"] >> text="wan"');
	assert.equal(await page.evaluate(() => localStorage.getItem('carbon.traffic')), 'wan');
	assert.equal(await page.textContent(picker), 'wan');
	/* keyboard: Escape closes and returns focus to the trigger */
	await page.focus(picker);
	await page.keyboard.press('ArrowDown');
	await page.waitForSelector('.cb-lb-list.show');
	await page.keyboard.press('Escape');
	assert.equal(await page.$('.cb-lb-list'), null);
	assert.equal(await page.evaluate(() => document.activeElement.classList.contains('cb-traffic-select')), true);
	/* a scroll that leaves the trigger in place (scroll anchoring while cards refresh) keeps the list open;
	   scrolling the page closes it */
	await page.click(picker);
	await page.waitForSelector('.cb-lb-list.show');
	await page.evaluate(() => document.dispatchEvent(new Event('scroll')));
	assert.notEqual(await page.$('.cb-lb-list'), null, 'a scroll that does not move the trigger keeps the list open');
	await page.evaluate(() => window.scrollBy(0, 120));
	await page.waitForFunction(() => !document.querySelector('.cb-lb-list'));
	await context.close();
});

test('dashboard customization supports presets, multiple traffic panels, Wi-Fi/temp tiles, cancel rollback, persistence and mobile layout', async () => {
	/* 1. Desktop: default spans, live preview, cancel rollback, presets, save & reload */
	const { page, context, errors } = await open('/src/preview/index.html?lang=zh-Hans', { width: 1440, height: 1000 });
	try {
		await dashboardReady(page);
		const defaultSpans = await page.evaluate(() => [...document.querySelectorAll('.cb-dash > .cb-card:not(.hidden)')].map((el) => {
			const span = (el.className.match(/span-\d+/) || [])[0];
			const role = (el.className.match(/cb-(hero|traffic|resources|tile-\w+|clients|wireless|interfaces)/) || [])[0];
			return role + ':' + span;
		}));
		assert.deepEqual(defaultSpans, [
			'cb-hero:span-12', 'cb-traffic:span-8', 'cb-resources:span-4',
			'cb-tile-devices:span-3', 'cb-tile-connections:span-3', 'cb-tile-load:span-3', 'cb-tile-uptime:span-3',
			'cb-clients:span-12', 'cb-wireless:span-6', 'cb-interfaces:span-6'
		]);

		/* Scroll down to the customize bar, open drawer, and verify edits keep the page scroll position */
		await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
		const scrollBefore = await page.evaluate(() => window.scrollY);
		assert.ok(scrollBefore > 200, 'page scrolled down before opening customizer: ' + scrollBefore);

		/* Open customizer drawer and switch to Multi-WAN preset */
		await page.click('.cb-customize-btn');
		await page.waitForSelector('.cb-sheet.show');
		await page.waitForTimeout(300);
		assert.equal(await page.$eval('.cb-app', (e) => e.hasAttribute('inert')), true, 'background shell is inert while customizer is open');
		assert.equal(await page.evaluate(() => window.scrollY), scrollBefore, 'opening customizer preserves page scroll');
		await page.click('.cb-sheet-presets .cb-seg-btn:has-text("多口监控")');
		await page.waitForFunction(() => document.querySelectorAll('.cb-traffic').length === 2);
		await page.waitForTimeout(150);
		const scrollAfterPreset = await page.evaluate(() => window.scrollY);
		assert.ok(scrollAfterPreset > 200, 'switching preset does not jump page to top: ' + scrollAfterPreset);
		/* Toggling a tile switch preserves scroll position and runs enter/exit animations cleanly */
		const tileToggle = '.cb-sheet-group:has-text("指标磁贴") .cb-sheet-row:has-text("已发现设备") .cbi-checkbox input';
		await page.click(tileToggle);
		const enterAnims = await page.evaluate(() => document.querySelector('.cb-tile-devices')?.getAnimations().length || 0);
		assert.ok(enterAnims > 0, 'adding a module triggers an entrance animation');
		await page.waitForFunction(() => (document.querySelector('.cb-tile-devices')?.getAnimations().length || 0) === 0, null, { timeout: 2000 });
		assert.equal(await page.evaluate(() => window.scrollY), scrollAfterPreset, 'toggling a tile keeps exact scroll position');
		await page.click(tileToggle);
		const exitGhost = await page.evaluate(() => document.querySelectorAll('.cb-dash-ghosts .cb-card-leaving').length);
		assert.equal(exitGhost, 1, 'closing a module renders an inert exit ghost animation');
		await page.waitForFunction(() => document.querySelectorAll('.cb-dash-ghosts').length === 0, null, { timeout: 2000 });
		assert.equal(await page.evaluate(() => document.querySelectorAll('.cb-dash-ghosts').length), 0, 'exit ghost layer cleans up after animation');
		assert.equal(await page.evaluate(() => window.scrollY), scrollAfterPreset, 'untoggling a tile keeps exact scroll position');
		/* Reset scroll to top before taking the hero/monitor/sheet reference screenshot */
		await page.evaluate(() => {
			window.scrollTo(0, 0);
			const sb = document.querySelector('.cb-sheet-body');
			if (sb) sb.scrollTop = 0;
		});
		const multiSpans = await page.evaluate(() => [...document.querySelectorAll('.cb-dash > .cb-card:not(.hidden)')].map((el) => {
			const span = (el.className.match(/span-\d+/) || [])[0];
			const role = (el.className.match(/cb-(hero|traffic|resources|tile-\w+|clients|wireless|interfaces)/) || [])[0];
			return role + ':' + span;
		}));
		assert.deepEqual(multiSpans, [
			'cb-hero:span-12', 'cb-traffic:span-6', 'cb-traffic:span-6', 'cb-resources:span-12',
			'cb-tile-connections:span-3', 'cb-tile-load:span-3', 'cb-tile-temp:span-3', 'cb-tile-uptime:span-3',
			'cb-interfaces:span-12', 'cb-clients:span-12'
		]);
		assert.match(await page.textContent('.cb-tile-temp .cb-tile-val'), /\d+\.\d°C/);
		const presetVis = await page.evaluate(() => {
			const b = document.querySelector('.cb-sheet-body').getBoundingClientRect();
			const lbl = document.querySelector('.cb-sheet-label').getBoundingClientRect();
			return lbl.height > 10 && lbl.top >= b.top - 1;
		});
		assert.equal(presetVis, true, 'preset heading is not squished or clipped');
		/* Drawer listbox remains interactive while .cb-app is inert */
		await page.click('.cb-sheet-select >> nth=1');
		await page.waitForSelector('.cb-lb-list.show');
		await page.keyboard.press('Escape');
		assert.equal(await page.$('.cb-lb-list'), null);
		await page.screenshot({ path: path.join(SHOTS, 'custom-drawer-desktop.png') });

		/* Collapse handle straddles the top-left border of the sheet on desktop (mirrors sidebar .cb-collapse) */
		const deskSheet = await page.locator('.cb-sheet').boundingBox();
		const deskHandle = await page.locator('.cb-sheet-collapse').boundingBox();
		assert.ok(deskHandle.x < deskSheet.x && deskHandle.x + deskHandle.width > deskSheet.x, 'desktop collapse handle straddles left border');
		assert.ok(deskHandle.y >= deskSheet.y && deskHandle.y <= deskSheet.y + 40, 'desktop collapse handle sits at top-left');

		/* Collapse panel to preview unobstructed dashboard, then expand again with draft intact */
		await page.click('.cb-sheet-collapse');
		await page.waitForSelector('.cb-sheet-dock.show');
		await page.waitForTimeout(320);
		assert.equal(await page.$eval('.cb-sheet', (e) => e.classList.contains('collapsed') && e.hasAttribute('inert')), true, 'collapsed sheet is inert and hidden');
		assert.equal(await page.$eval('.cb-app', (e) => e.hasAttribute('inert')), false, 'dashboard is interactive while collapsed');
		assert.equal(await page.locator('.cb-traffic').count(), 2, 'live draft stays applied while collapsed');
		const dockBox = await page.locator('.cb-sheet-dock').boundingBox();
		assert.ok(dockBox.x >= 0 && dockBox.x + dockBox.width <= 1440 && dockBox.y + dockBox.height <= 1000, 'collapsed dock fits inside desktop viewport');
		await page.screenshot({ path: path.join(SHOTS, 'custom-collapsed-desktop.png') });

		await page.click('.cb-sheet-expand');
		await page.waitForSelector('.cb-sheet.show');
		await page.waitForTimeout(300);
		assert.equal(await page.$eval('.cb-app', (e) => e.hasAttribute('inert')), true, 'expanding re-enables inert on background shell');
		assert.equal(await page.$eval('.cb-sheet-dock', (e) => !e.classList.contains('show') && e.hasAttribute('inert')), true, 'dock hides when expanded');
		assert.equal(await page.locator('.cb-traffic').count(), 2, 'draft preserved after expand');

		/* Clicking the scrim collapses non-destructively, and Cancel from the dock rolls back */
		await page.mouse.click(300, 300);
		await page.waitForSelector('.cb-sheet-dock.show');
		assert.equal(await page.locator('.cb-traffic').count(), 2, 'scrim click collapses instead of discarding');
		await page.click('.cb-sheet-dock button:has-text("取消")');
		await page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		assert.equal(await page.$eval('.cb-app', (e) => e.hasAttribute('inert')), false, 'closing customizer clears inert');
		assert.equal(await page.locator('.cb-traffic').count(), 1);
		assert.equal(await page.locator('.cb-wireless:not(.hidden)').count(), 1);

		/* Re-open, apply Home Wi-Fi preset, add a second traffic chart, collapse & save from dock, then reload */
		await page.click('.cb-customize-btn');
		await page.waitForSelector('.cb-sheet.show');
		await page.click('.cb-sheet-presets .cb-seg-btn:has-text("家用无线")');
		await page.waitForSelector('.cb-tile-wifi');
		assert.match(await page.textContent('.cb-tile-wifi .cb-tile-val'), /^\d+$/);
		assert.match(await page.textContent('.cb-tile-wifi .cb-tile-sub'), /GHz/);
		await page.click('.cb-sheet-add');
		assert.equal(await page.locator('.cb-traffic').count(), 2);
		await page.click('.cb-sheet-collapse');
		await page.waitForSelector('.cb-sheet-dock.show');
		await page.click('.cb-sheet-dock .cbi-button-save');
		await page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		await page.screenshot({ path: path.join(SHOTS, 'custom-multi-desktop.png'), fullPage: true });

		await page.reload();
		await page.waitForSelector('.cb-tile-wifi');
		assert.equal(await page.locator('.cb-traffic').count(), 2, 'custom layout persists across reload');
		assert.equal(await page.locator('.cb-tile-temp').count(), 1);
		assert.equal(await page.locator('.cb-tile-devices').count(), 0);
		assert.deepEqual(errors, []);
	} finally { await context.close(); }

	/* 2. Phone 390px: odd tile count fills full row cleanly + bottom sheet fits viewport without overflow */
	const phone = await open('/src/preview/index.html?lang=zh-Hans', {
		width: 390, height: 844,
		storage: { 'carbon.dashboard': 'hero=1;sections=monitor tiles details;monitor=traffic:auto traffic:br-lan resources;tiles=wifi temp uptime;details=clients wireless interfaces' }
	});
	try {
		await dashboardReady(phone.page);
		await phone.page.waitForFunction(() => /\d+\.\d°C/.test(document.querySelector('.cb-tile-temp .cb-tile-val')?.textContent || ''));
		const geom = await phone.page.evaluate(() => {
			const tiles = [...document.querySelectorAll('.cb-tile')].map((el) => ({
				cls: el.className,
				w: Math.round(el.getBoundingClientRect().width)
			}));
			const traffics = [...document.querySelectorAll('.cb-traffic')].map((el) => Math.round(el.getBoundingClientRect().width));
			return {
				overflow: document.documentElement.scrollWidth > innerWidth,
				tiles,
				traffics
			};
		});
		assert.equal(geom.overflow, false, 'no horizontal overflow on phone');
		assert.equal(geom.tiles.length, 3);
		assert.ok(geom.tiles[2].cls.includes('cb-tile-wide'), 'odd last tile is marked wide');
		assert.ok(geom.tiles[2].w > geom.tiles[0].w * 1.7, 'odd last tile spans full width on phone: ' + JSON.stringify(geom.tiles));
		assert.ok(geom.traffics[0] > 300 && geom.traffics[1] > 300, 'stacked traffic charts use full phone width: ' + JSON.stringify(geom.traffics));
		await phone.page.screenshot({ path: path.join(SHOTS, 'custom-odd-tiles-phone.png'), fullPage: true });

		await phone.page.click('.cb-customize-btn');
		await phone.page.waitForSelector('.cb-sheet.show');
		await phone.page.waitForTimeout(320);
		const sheetBox = await phone.page.locator('.cb-sheet').boundingBox();
		const phoneHandle = await phone.page.locator('.cb-sheet-collapse').boundingBox();
		const saveBox = await phone.page.locator('.cb-sheet-foot .cbi-button-save').boundingBox();
		assert.ok(sheetBox.x >= 0 && sheetBox.x + sheetBox.width <= 391, 'bottom sheet stays within phone viewport');
		assert.ok(sheetBox.height <= 844 * 0.9, 'bottom sheet leaves top margin');
		assert.ok(phoneHandle.y < sheetBox.y && phoneHandle.y + phoneHandle.height > sheetBox.y, 'phone collapse handle straddles top border');
		assert.ok(saveBox.bottom ? saveBox.bottom <= 844 : saveBox.y + saveBox.height <= 844.5, 'sticky save button stays visible inside phone viewport');
		await phone.page.screenshot({ path: path.join(SHOTS, 'custom-drawer-phone.png') });
		await phone.page.click('.cb-sheet-collapse');
		await phone.page.waitForSelector('.cb-sheet-dock.show');
		await phone.page.waitForTimeout(320);
		const phoneDock = await phone.page.locator('.cb-sheet-dock').boundingBox();
		assert.ok(phoneDock.x >= 0 && phoneDock.x + phoneDock.width <= 391 && phoneDock.y + phoneDock.height <= 844.5, 'collapsed dock fits phone viewport');
		assert.ok(phoneDock.height <= 64, 'collapsed dock buttons stay on a single row on phone: height=' + phoneDock.height);
		assert.equal(await phone.page.$eval('.cb-app', (e) => e.hasAttribute('inert')), false, 'phone dashboard interactive when collapsed');
		await phone.page.screenshot({ path: path.join(SHOTS, 'custom-collapsed-phone.png') });
		await phone.page.click('.cb-sheet-expand');
		await phone.page.waitForSelector('.cb-sheet.show');
		await phone.page.keyboard.press('Escape');
		await phone.page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		assert.deepEqual(phone.errors, []);
	} finally { await phone.context.close(); }

	/* 3. Standalone Wi-Fi tile (no clients card or devices tile) + dark-mode customizer drawer */
	const dark = await open('/src/preview/index.html?lang=zh-Hans', {
		width: 1440, height: 1000, appearance: 'dark',
		storage: { 'carbon.dashboard': 'hero=1;sections=tiles monitor details;monitor=none;tiles=wifi temp;details=none' }
	});
	try {
		await dark.page.waitForFunction(() => /^\d+$/.test(document.querySelector('.cb-tile-wifi .cb-tile-val')?.textContent || ''));
		assert.match(await dark.page.textContent('.cb-tile-wifi .cb-tile-sub'), /GHz/);
		await dark.page.click('.cb-customize-btn');
		await dark.page.waitForSelector('.cb-sheet.show');
		await dark.page.waitForTimeout(300);
		await dark.page.screenshot({ path: path.join(SHOTS, 'custom-drawer-dark.png') });
		assert.deepEqual(dark.errors, []);
	} finally { await dark.context.close(); }
});

test('simple menu customization supports search multi-select, reordering, cancel rollback, persistence, guardrails and mobile drawer handoff', async () => {
	/* 1. Desktop zh-Hans: live preview with unobstructed sidebar, search/multi-select, reorder, cancel rollback, save & reload, restore default */
	const { page, context, errors } = await open('/src/preview/index.html?lang=zh-Hans', { width: 1440, height: 1000 });
	try {
		await dashboardReady(page);
		const navLabels = () => page.$$eval('#topmenu .cb-nav-link .cb-nav-label', (els) => els.map((e) => e.textContent));
		const initial = await navLabels();
		assert.deepEqual(initial, ['概览', '上网与网络', 'Wi-Fi', '软件包', '管理密码', '备份与升级', '重启']);

		await page.click('.cb-nav-customize');
		await page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		await page.waitForTimeout(300);
		assert.equal(await page.$eval('.cb-app', (e) => e.hasAttribute('inert')), true, 'shell is inert while menu customizer is open');
		const geom = await page.evaluate(() => ({
			sideRight: document.getElementById('cb-sidebar').getBoundingClientRect().right,
			scrimLeft: document.querySelector('.cb-sheet-scrim-menu').getBoundingClientRect().left
		}));
		assert.ok(geom.scrimLeft >= geom.sideRight - 1, 'desktop menu scrim leaves sidebar unobstructed: ' + JSON.stringify(geom));
		await page.screenshot({ path: path.join(SHOTS, 'simple-menu-edit-desktop.png') });

		/* Open Add-page picker for Common */
		await page.click('.cb-sheet-group[data-group="common"] .cb-sheet-add');
		await page.waitForSelector('.cb-sheet-search-input:visible');
		assert.equal(await page.evaluate(() => document.activeElement.classList.contains('cb-sheet-search-input')), true, 'search input is focused on picker open');
		/* Items already in System are disabled with badge */
		const rebootItem = page.locator('.cb-picker-item[data-path="system/reboot"]');
		assert.equal(await rebootItem.isDisabled(), true);
		assert.match(await rebootItem.textContent(), /已在「系统」中/);

		/* Search & add System Log */
		await page.fill('.cb-sheet-search-input', '日志');
		assert.equal(await page.locator('.cb-picker-item').count(), 1);
		await page.click('.cb-picker-item[data-path="status/syslog"]');
		assert.match(await page.locator('.cb-picker-item[data-path="status/syslog"]').textContent(), /已添加/);
		assert.ok((await navLabels()).includes('系统日志'), 'live sidebar updates immediately on add');

		/* Clear search & multi-select two more pages in a row */
		await page.click('.cb-sheet-search-clear');
		await page.click('.cb-picker-item[data-path="network/dhcp"]');
		await page.click('.cb-picker-item[data-path="network/diagnostics"]');
		await page.screenshot({ path: path.join(SHOTS, 'simple-menu-picker-desktop.png') });

		/* Escape returns from picker to edit view without closing sheet */
		await page.keyboard.press('Escape');
		await page.waitForSelector('.cb-sheet-group[data-group="common"] .cb-sheet-add');
		assert.equal(await page.locator('.cb-sheet.cb-sheet-menu').isVisible(), true);

		/* Reorder System Log up & remove Password, verify live sidebar */
		await page.click('[data-row-key="common:status/syslog"] .cbi-button-up');
		await page.click('[data-row-key="system:system/admin"] .cbi-button-remove');
		const edited = await navLabels();
		assert.equal(edited.indexOf('系统日志') < edited.indexOf('Wi-Fi'), true, 'reordered item moves up in live sidebar');
		assert.equal(edited.includes('管理密码'), false, 'removed item disappears from live sidebar');

		/* Cancel rolls back completely and restores focus to .cb-nav-customize */
		await page.click('.cb-sheet-foot .cbi-button:has-text("取消")');
		await page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		assert.deepEqual(await navLabels(), initial, 'cancel restores previous simple menu');
		assert.equal(await page.evaluate(() => document.activeElement.classList.contains('cb-nav-customize')), true, 'desktop close restores focus to Customize menu button');

		/* Keyboard focus: Back focuses group Add button; IME Escape stays in Picker; keyboard reorder keeps focus in sheet */
		await page.click('.cb-nav-customize');
		await page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		await page.click('.cb-sheet-group[data-group="common"] .cb-sheet-add');
		await page.evaluate(() => {
			document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', isComposing: true, bubbles: true }));
		});
		assert.equal(await page.locator('.cb-sheet-search-input').isVisible(), true, 'IME Escape does not exit picker');
		await page.click('.cb-sheet-back');
		assert.equal(await page.evaluate(() => document.activeElement.classList.contains('cb-sheet-add')), true, 'Back moves focus to group Add button');
		await page.focus('[data-row-key="common:network/wireless"] .cbi-button-up');
		await page.keyboard.press('Enter');
		assert.equal(await page.evaluate(() => !!document.activeElement.closest('.cb-sheet-body')), true, 'keyboard reorder preserves focus inside drawer');
		await page.click('.cb-sheet-foot .cbi-button:has-text("取消")');
		await page.waitForFunction(() => !document.querySelector('.cb-sheet'));

		/* Re-open, add System Log + Connected Devices, remove Reboot, Save & reload */
		await page.click('.cb-nav-customize');
		await page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		await page.click('.cb-sheet-group[data-group="common"] .cb-sheet-add');
		await page.click('.cb-picker-item[data-path="status/syslog"]');
		await page.click('.cb-picker-item[data-path="network/dhcp"]');
		await page.click('.cb-sheet-back');
		await page.click('[data-row-key="system:system/reboot"] .cbi-button-remove');
		await page.click('.cb-sheet-foot .cbi-button-save');
		await page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		const savedAttr = await page.evaluate(() => localStorage.getItem('carbon.simpleMenu'));
		assert.match(savedAttr, /status\/syslog/);
		assert.match(savedAttr, /network\/dhcp/);
		assert.doesNotMatch(savedAttr, /system\/reboot/);

		await page.reload();
		await dashboardReady(page);
		const persisted = await navLabels();
		assert.ok(persisted.includes('系统日志') && persisted.includes('已连接设备') && !persisted.includes('重启'), 'custom menu persists after reload: ' + JSON.stringify(persisted));

		/* Restore default & save clears storage */
		await page.click('.cb-nav-customize');
		await page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		await page.click('.cb-sheet-foot .cbi-button-reset');
		await page.click('.cb-sheet-foot .cbi-button-save');
		await page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		assert.equal(await page.evaluate(() => localStorage.getItem('carbon.simpleMenu')), null, 'restoring default clears localStorage');
		assert.deepEqual(await navLabels(), initial);
		assert.deepEqual(errors, []);
	} finally { await context.close(); }

	/* 2. Guardrails & uninstalled saved path (en, dark) */
	const dark = await open('/src/preview/index.html?lang=en', {
		width: 1440, height: 1000, appearance: 'dark',
		storage: { 'carbon.simpleMenu': 'common=status/overview services/openclash;system=none' }
	});
	try {
		await dashboardReady(dark.page);
		const links = await dark.page.$$eval('#topmenu .cb-nav-link .cb-nav-label', (els) => els.map((e) => e.textContent));
		assert.deepEqual(links, ['Overview'], 'uninstalled saved plugin is skipped in sidebar');
		await dark.page.click('.cb-nav-customize');
		await dark.page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		await dark.page.waitForTimeout(300);
		assert.match(await dark.page.locator('[data-row-key="common:services/openclash"]').textContent(), /Not installed/);
		await dark.page.screenshot({ path: path.join(SHOTS, 'simple-menu-drawer-dark.png') });
		await dark.page.click('[data-row-key="common:services/openclash"] .cbi-button-remove');
		assert.equal(await dark.page.locator('[data-row-key="common:status/overview"] .cbi-button-remove').isDisabled(), true, 'cannot remove the last remaining menu item');
		assert.deepEqual(dark.errors, []);
	} finally { await dark.context.close(); }

	/* 3. Mobile 390px: sidebar drawer closes cleanly before bottom sheet opens, zero overflow */
	const phone = await open('/src/preview/index.html?lang=zh-Hans', { width: 390, height: 844 });
	try {
		await dashboardReady(phone.page);
		await phone.page.click('#cb-burger');
		await phone.page.waitForSelector('body.cb-nav-open');
		await phone.page.click('.cb-nav-customize');
		await phone.page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		await phone.page.waitForTimeout(320);
		assert.equal(await phone.page.evaluate(() => document.body.classList.contains('cb-nav-open')), false, 'mobile nav drawer closes when customizer opens');
		const sheetBox = await phone.page.locator('.cb-sheet.cb-sheet-menu').boundingBox();
		const saveBox = await phone.page.locator('.cb-sheet-foot .cbi-button-save').boundingBox();
		assert.ok(sheetBox.x >= 0 && sheetBox.x + sheetBox.width <= 391, 'phone bottom sheet stays within viewport');
		assert.ok(saveBox.y + saveBox.height <= 844.5, 'save button stays visible on phone');
		assert.equal(await phone.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, 'no horizontal overflow on phone');
		await phone.page.screenshot({ path: path.join(SHOTS, 'simple-menu-drawer-phone.png') });
		await phone.page.click('.cb-sheet-group[data-group="common"] .cb-sheet-add');
		await phone.page.click('.cb-picker-item[data-path="status/syslog"]');
		await phone.page.click('.cb-sheet-foot .cbi-button-save');
		await phone.page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		await phone.page.click('#cb-burger');
		await phone.page.waitForSelector('body.cb-nav-open');
		const phoneLabels = await phone.page.$$eval('#topmenu .cb-nav-link .cb-nav-label', (els) => els.map((e) => e.textContent));
		assert.ok(phoneLabels.includes('系统日志'), 'saved item appears in mobile drawer');
		assert.deepEqual(phone.errors, []);
	} finally { await phone.context.close(); }

	/* 4. Router UCI mode: live Save, Simple<->Pro toggle, setSimpleMenuAttr reset, resetSimpleMenu on default, permission denied, Pro-mode preview & all-uninstalled empty state */
	const uci = await open('/src/preview/index.html?lang=en', { width: 1440, height: 1000 });
	try {
		await dashboardReady(uci.page);
		await uci.page.evaluate(() => {
			const baseModel = window.Carbon._navModel;
			window.__uciCalls = [];
			window.__uciDeny = false;
			const routerModel = Object.assign({}, baseModel, {
				simpleMenuAttr: '',
				saveSimpleMenu: async (cfg) => {
					window.__uciCalls.push(['set', window.Carbon.simpleMenu.encodeAttr(cfg)]);
					if (window.__uciDeny) { const e = new Error('denied'); e.code = 'denied'; throw e; }
					document.querySelector('.cb-app').dataset.simpleMenu = window.Carbon.simpleMenu.encodeAttr(cfg);
					return { simple_menu_custom: true };
				},
				resetSimpleMenu: async () => {
					window.__uciCalls.push(['reset']);
					delete document.querySelector('.cb-app').dataset.simpleMenu;
					return { simple_menu_custom: false };
				}
			});
			window.Carbon.renderNav(routerModel);
		});
		const labels = () => uci.page.$$eval('#topmenu .cb-nav-link .cb-nav-label', (els) => els.map((e) => e.textContent));

		/* Save in UCI mode must keep updated sidebar without reverting to stale model.simpleMenuAttr */
		await uci.page.click('.cb-nav-customize');
		await uci.page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		await uci.page.click('.cb-sheet-group[data-group="common"] .cb-sheet-add');
		await uci.page.click('.cb-picker-item[data-path="status/syslog"]');
		await uci.page.click('.cb-sheet-foot .cbi-button-save');
		await uci.page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		assert.ok((await labels()).includes('System Log'), 'UCI Save keeps updated sidebar immediately');

		/* Switching to Pro and back to Simple preserves in-session saved menu */
		await uci.page.click('#cb-mode .cb-seg-btn:last-child');
		await uci.page.waitForSelector('#topmenu .cb-nav-group');
		await uci.page.click('#cb-mode .cb-seg-btn:first-child');
		await uci.page.waitForSelector('#topmenu .cb-nav-customize');
		assert.ok((await labels()).includes('System Log'), 'Simple <-> Pro toggle preserves UCI saved menu');

		/* Pro mode -> openSimpleMenuCustomizer -> temporary Simple preview -> Cancel restores Pro mode */
		await uci.page.click('#cb-mode .cb-seg-btn:last-child');
		await uci.page.waitForSelector('#topmenu .cb-nav-group');
		await uci.page.evaluate(() => window.Carbon.openSimpleMenuCustomizer(null));
		await uci.page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		assert.ok((await labels()).includes('System Log'), 'opening customizer from Pro mode shows live Simple preview');
		await uci.page.click('.cb-sheet-foot .cbi-button:has-text("Cancel")');
		await uci.page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		assert.ok(await uci.page.locator('#topmenu .cb-nav-group').count() > 0, 'closing customizer returns to Pro mode');

		/* Back to Simple: setSimpleMenuAttr("") resets live sidebar immediately (Settings page Restore default hook) */
		await uci.page.click('#cb-mode .cb-seg-btn:first-child');
		await uci.page.waitForSelector('#topmenu .cb-nav-customize');
		await uci.page.evaluate(() => window.Carbon.setSimpleMenuAttr(''));
		assert.equal((await labels()).includes('System Log'), false, 'setSimpleMenuAttr("") resets live sidebar immediately');

		/* Permission denied keeps drawer open with draft intact */
		await uci.page.evaluate(() => { window.__uciDeny = true; });
		await uci.page.click('.cb-nav-customize');
		await uci.page.waitForSelector('.cb-sheet.cb-sheet-menu.show');
		await uci.page.click('.cb-sheet-group[data-group="common"] .cb-sheet-add');
		await uci.page.click('.cb-picker-item[data-path="status/syslog"]');
		await uci.page.click('.cb-sheet-foot .cbi-button-save');
		await uci.page.waitForFunction(() => /Log out and log in again/.test(document.querySelector('.cb-sheet-status')?.textContent || ''));
		assert.equal(await uci.page.locator('.cb-sheet.cb-sheet-menu').isVisible(), true, 'denied error keeps drawer open');

		/* Restore default + Save invokes resetSimpleMenu */
		await uci.page.evaluate(() => { window.__uciDeny = false; window.__uciCalls = []; });
		await uci.page.click('.cb-sheet-foot .cbi-button-reset');
		await uci.page.click('.cb-sheet-foot .cbi-button-save');
		await uci.page.waitForFunction(() => !document.querySelector('.cb-sheet'));
		assert.deepEqual(await uci.page.evaluate(() => window.__uciCalls), [['reset']]);

		/* All saved items uninstalled -> renders empty-state notice above Customize menu button */
		await uci.page.evaluate(() => window.Carbon.setSimpleMenuAttr('common=services/missing_plugin;system=none'));
		assert.match(await uci.page.textContent('#topmenu .cb-nav-empty'), /No configured pages are currently installed/);
		assert.equal(await uci.page.locator('#topmenu .cb-nav-customize').isVisible(), true);
		assert.deepEqual(uci.errors, []);
	} finally { await uci.context.close(); }

	/* 5. Settings page Simple menu section: Restore default, event sync, and non-Carbon fallback */
	const settings = await open('/src/tests/fixtures/settings.html', { width: 1200, height: 900 });
	try {
		await settings.page.waitForSelector('body[data-ready]');
		const sec = settings.page.locator('section.cbi-section', { hasText: '简洁菜单' });
		assert.match(await sec.locator('.cb-update-note').textContent(), /自定义简洁菜单/);
		await sec.locator('.cbi-button-reset').click();
		await settings.page.waitForFunction(() => {
			const s = [...document.querySelectorAll('section.cbi-section')].find((el) => el.textContent.includes('简洁菜单'));
			return s && /已恢复默认简洁菜单/.test(s.querySelector('.cb-update-note')?.textContent || '');
		});
		assert.equal(await sec.locator('.cbi-button-reset').isDisabled(), true);
		await settings.page.evaluate(() => {
			document.dispatchEvent(new CustomEvent('carbon:simple-menu-change', { detail: { custom: true } }));
		});
		assert.equal(await sec.locator('.cbi-button-reset').isDisabled(), false, 'carbon:simple-menu-change re-enables Restore default');
		assert.match(await sec.locator('.cb-update-note').textContent(), /当前使用自定义简洁菜单/);
		assert.deepEqual(settings.errors, []);
	} finally { await settings.context.close(); }
});

test('dashboard clarifies load average status and shows multi-SSID wireless bands and client counts', async () => {
	/* 1. Default overview (en & zh-Hans): load 1-min + badge + tooltip, wireless card counts & bands */
	for (const lang of ['en', 'zh-Hans']) {
		const zh = lang === 'zh-Hans';
		const { page, context, errors } = await open(`/src/preview/index.html?lang=${lang}`, { width: 1440, height: 1000 });
		try {
			await dashboardReady(page);
			const data = await page.evaluate(() => {
				const loadLi = document.querySelector('.cb-kv li.cb-kv-help');
				const wirelessRows = [...document.querySelectorAll('.cb-wireless .cb-list > li')].map((li) => ({
					ssid: li.querySelector('.cb-wifi-ssid')?.textContent || '',
					band: li.querySelector('.cb-band')?.textContent || '',
					meta: li.querySelector('.cb-list-sub')?.textContent || '',
					clients: li.querySelector('.cb-wifi-clients')?.textContent || '',
					pill: li.querySelector('.cb-pill')?.textContent || ''
				}));
				return {
					loadVal: loadLi?.querySelector('.cb-load-val .cb-mono')?.textContent || '',
					loadBadge: loadLi?.querySelector('.cb-load-badge')?.textContent || '',
					loadBadgeOk: loadLi?.querySelector('.cb-load-badge')?.classList.contains('ok') || false,
					loadTitle: loadLi?.getAttribute('title') || '',
					loadTileTitle: document.querySelector('.cb-tile-load')?.getAttribute('title') || '',
					wirelessCount: document.querySelector('.cb-wireless .cb-count')?.textContent || '',
					wirelessRows
				};
			});
			assert.match(data.loadVal, /^\d+\.\d{2}$/, 'load row displays single 1-min value');
			assert.equal(data.loadBadge, zh ? '正常' : 'Normal');
			assert.equal(data.loadBadgeOk, true);
			assert.match(data.loadTitle, zh ? /1 \/ 5 \/ 15 分钟平均负载：\d+\.\d{2} · \d+\.\d{2} · \d+\.\d{2}（4 核 CPU）/ : /1 \/ 5 \/ 15 min load: \d+\.\d{2} · \d+\.\d{2} · \d+\.\d{2} \(4 cores\)/);
			assert.equal(data.loadTileTitle, data.loadTitle, 'Load tile tooltip matches Resources load row');
			assert.equal(data.wirelessCount, '8');
			assert.deepEqual(data.wirelessRows, [
				{ ssid: 'Carbon-Home', band: '2.4 GHz', meta: 'CH 6 · 40 MHz · WPA2', clients: zh ? '3 台设备' : '3 devices', pill: zh ? '已开启' : 'On' },
				{ ssid: 'Carbon-Guest', band: '2.4 GHz', meta: 'CH 6 · 40 MHz · WPA2', clients: '', pill: zh ? '已关闭' : 'Off' },
				{ ssid: 'Carbon-Home-5G', band: '5 GHz', meta: 'CH 149 · 160 MHz · WPA2/WPA3', clients: zh ? '5 台设备' : '5 devices', pill: zh ? '已开启' : 'On' }
			]);
			assert.deepEqual(errors, []);
		} finally { await context.close(); }
	}

	/* 2. Standalone Wireless card (no clients card, devices tile, or wifi tile) still fetches per-SSID counts */
	const solo = await open('/src/preview/index.html?lang=zh-Hans', {
		width: 1280, height: 900,
		storage: { 'carbon.dashboard': 'hero=0;sections=details monitor tiles;monitor=none;tiles=none;details=wireless' }
	});
	try {
		await solo.page.waitForFunction(() => document.querySelector('.cb-wireless .cb-count')?.textContent === '8');
		const counts = await solo.page.$$eval('.cb-wireless .cb-wifi-clients', (els) => els.map((e) => e.textContent));
		assert.deepEqual(counts, ['3 台设备', '5 台设备']);
		assert.deepEqual(solo.errors, []);
	} finally { await solo.context.close(); }

	/* 3. Wi-Fi tile with 4 active SSIDs (including duplicate SSID across bands) truncates cleanly with +N more and fits 390px phone */
	const mock = fs.readFileSync(path.join(ROOT, 'preview', 'mock.js'), 'utf8');
	const multi = await browser.newContext({ viewport: { width: 390, height: 844 } });
	await multi.addInitScript(() => {
		localStorage.setItem('carbon.dashboard', 'hero=1;sections=tiles details monitor;monitor=resources;tiles=wifi load;details=wireless');
	});
	const page = await multi.newPage();
	const errors = [];
	page.on('pageerror', (e) => errors.push(e.message));
	try {
		await page.route('**/preview/mock.js', (route) => route.fulfill({
			contentType: 'text/javascript',
			body: mock + '\n(' + (() => {
				window.CarbonPreview.provider.wireless = async () => ({
					radio0: { up: true, config: { band: '2g', channel: '6', htmode: 'HT40+' }, interfaces: [
						{ ifname: 'phy0-ap0', config: { mode: 'ap', ssid: 'MyHome-Long-Living-Room-Network', encryption: 'psk2' } },
						{ ifname: 'phy0-ap1', config: { mode: 'ap', ssid: 'MyHome-IoT', encryption: 'psk2' } }
					] },
					radio1: { up: true, config: { band: '5g', channel: '149', htmode: 'HE160' }, interfaces: [
						{ ifname: 'phy1-ap0', config: { mode: 'ap', ssid: 'MyHome', encryption: 'sae-mixed' } }
					] },
					radio2: { up: true, config: { band: '6g', channel: '37', htmode: 'EHT320' }, interfaces: [
						{ ifname: 'phy2-ap0', config: { mode: 'ap', ssid: 'MyHome-6E', encryption: 'sae' } }
					] }
				});
				window.CarbonPreview.provider.stations = async (ifnames) => [
					{ ifname: 'phy0-ap0', mac: 'aa:00:00:00:00:01', signal: -55 },
					{ ifname: 'phy0-ap1', mac: 'aa:00:00:00:00:02', signal: -61 },
					{ ifname: 'phy0-ap1', mac: 'aa:00:00:00:00:03', signal: -63 },
					{ ifname: 'phy1-ap0', mac: 'aa:00:00:00:00:04', signal: -49 },
					{ ifname: 'phy1-ap0', mac: 'aa:00:00:00:00:05', signal: -52 },
					{ ifname: 'phy1-ap0', mac: 'aa:00:00:00:00:06', signal: -54 }
				].filter((s) => ifnames.includes(s.ifname));
			}).toString() + ')();'
		}));
		await page.goto(base + '/src/preview/index.html?lang=zh-Hans');
		await page.waitForFunction(() => document.querySelector('.cb-tile-wifi .cb-tile-val')?.textContent === '6');
		const tile = await page.evaluate(() => ({
			head: document.querySelector('.cb-tile-wifi .cb-tile-head')?.textContent.trim() || '',
			val: document.querySelector('.cb-tile-wifi .cb-tile-val')?.textContent || '',
			rows: [...document.querySelectorAll('.cb-tile-wifi .cb-wifi-row:not(.cb-wifi-row-more)')].map((r) => [
				r.querySelector('.cb-wifi-row-ssid')?.textContent || '',
				r.querySelector('.cb-band.cb-wifi-row-band')?.textContent || '',
				r.querySelector('.cb-band.cb-wifi-row-band')?.classList.contains('cb-band-2g') || false,
				r.querySelector('.cb-wifi-row-count')?.textContent || ''
			]),
			more: document.querySelector('.cb-tile-wifi .cb-wifi-row-more')?.textContent || '',
			title: document.querySelector('.cb-tile-wifi')?.getAttribute('title') || '',
			wirelessBands: [...document.querySelectorAll('.cb-wireless .cb-band')].map((b) => b.textContent),
			wirelessClients: [...document.querySelectorAll('.cb-wireless .cb-wifi-clients')].map((c) => c.textContent),
			tileOverflow: (document.querySelector('.cb-tile-wifi')?.scrollWidth || 0) > (document.querySelector('.cb-tile-wifi')?.clientWidth || 0) + 1,
			overflow: document.documentElement.scrollWidth > innerWidth
		}));
		assert.equal(tile.head, 'Wi-Fi');
		assert.equal(tile.val, '6');
		assert.deepEqual(tile.rows, [['MyHome-Long-Living-Room-Network', '2.4 GHz', true, '1'], ['MyHome-IoT', '2.4 GHz', true, '2']]);
		assert.equal(tile.more, '还有 2 个');
		assert.match(tile.title, /MyHome \(5 GHz · CH 149 · 160 MHz · WPA2\/WPA3\) · 3 台设备/);
		assert.match(tile.title, /MyHome-6E \(6 GHz · CH 37 · 320 MHz · WPA3\) · 0 台设备/);
		assert.deepEqual(tile.wirelessBands, ['2.4 GHz', '2.4 GHz', '5 GHz', '6 GHz']);
		assert.deepEqual(tile.wirelessClients, ['1 台设备', '2 台设备', '3 台设备', '0 台设备']);
		assert.equal(tile.tileOverflow, false, 'long SSID truncates inside 390px half-width Wi-Fi tile without overflow');
		assert.equal(tile.overflow, false, '4-SSID Wi-Fi tile and wireless card fit 390px phone without overflow');
		await page.screenshot({ path: path.join(SHOTS, 'multi-ssid-phone.png'), fullPage: true });
		assert.deepEqual(errors, []);
	} finally { await multi.close(); }
});

/* every bundled catalogue loads, translates the shell and fits the sidebar */
const CATALOGUES = fs.readdirSync(path.join(ROOT, 'htdocs/luci-static/carbon/i18n')).map((f) => f.replace(/\.js$/, ''));
test('bundled catalogues translate the shell and fit the sidebar', async () => {
	assert.ok(CATALOGUES.length >= 12, CATALOGUES.join(','));
	for (const code of CATALOGUES) {
		const lang = { 'zh-cn': 'zh-Hans', 'zh-tw': 'zh-Hant', 'pt-br': 'pt-BR' }[code] || code;
		const { page, context, errors } = await open(`/src/preview/index.html?lang=${lang}`, { width: 1280 });
		await dashboardReady(page);
		const r = await page.evaluate(() => ({
			loaded: Object.keys(window.Carbon.I18N || {}).length,
			common: document.querySelector('.cb-nav-sect').textContent,
			expected: window.Carbon.I18N.Common,
			/* segmented labels must not overflow their buttons */
			clipped: [...document.querySelectorAll('.cb-mode .cb-seg-btn, .cb-lang .cb-seg-btn')].filter((b) => b.scrollWidth > b.clientWidth + 1).map((b) => b.textContent),
			navClipped: [...document.querySelectorAll('.cb-nav-label')].filter((l) => l.scrollWidth > l.clientWidth + 1 && getComputedStyle(l).textOverflow !== 'ellipsis').map((l) => l.textContent)
		}));
		assert.ok(r.loaded > 150, `${code}: catalogue loaded`);
		assert.equal(r.common, r.expected, `${code}: sidebar section translated`);
		assert.deepEqual(r.clipped, [], `${code}: segmented labels fit`);
		assert.deepEqual(r.navClipped, [], `${code}: menu labels fit or ellipsize`);
		assert.deepEqual(errors, [], code);
		if (code === 'de' || code === 'ja')
			await page.screenshot({ path: path.join(SHOTS, `overview-${code}-light-desktop.png`), fullPage: true });
		await context.close();
	}
});

test('a custom logo replaces the sidebar logo and the dashboard hero icon', async () => {
	/* the theme header marks an uploaded logo with data-custom */
	const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 900 } });
	await ctx2.route('**/preview/index.html*', async (route) => {
		const res = await route.fetch();
		const body = (await res.text()).replace('<img class="cb-brand-logo" src="../htdocs/luci-static/carbon/logo.svg" alt="">',
			'<img class="cb-brand-logo" src="../htdocs/luci-static/carbon/logo.svg?v=1" alt="" data-custom>');
		await route.fulfill({ response: res, body });
	});
	const p2 = await ctx2.newPage();
	await p2.goto(base + '/src/preview/index.html?lang=en');
	await dashboardReady(p2);
	const hero = await p2.evaluate(() => {
		const img = document.querySelector('.cb-hero-icon.custom img');
		const brand = document.querySelector('.cb-brand-logo');
		return { src: img && img.getAttribute('src'), fit: getComputedStyle(brand).objectFit, shadow: getComputedStyle(brand).boxShadow };
	});
	assert.equal(hero.src, '../htdocs/luci-static/carbon/logo.svg?v=1');
	assert.equal(hero.fit, 'contain');
	assert.equal(hero.shadow, 'none');
	await ctx2.close();
});

test('Open-Box channel radio dots stay inside their inputs', async () => {
	// Open-Box v0.1.457 main.js resets these inputs to position:static.
	// Its stylesheet is injected after the theme, as on the real LuCI page.
	for (const mount of ['src', 'min']) {
		for (const width of [390, 1280]) {
			for (const appearance of ['light', 'dark']) {
				const context = await browser.newContext({ viewport: { width, height: 800 } });
				const page = await context.newPage();
				try {
					await page.goto(base + '/src/preview/form.html');
					await page.setContent(`<!doctype html><html data-darkmode="${appearance === 'dark'}"><head>
					<link rel="stylesheet" href="/${mount}/htdocs/luci-static/carbon/carbon.css">
					<style>
					.ob-chan-radio{display:flex;align-items:center;gap:.5em;min-width:0;cursor:pointer}
					.ob-chan-row .ob-chan-radio input{flex:none;width:16px;height:16px;margin:0;padding:0;border:0;border-radius:50%;box-shadow:none;line-height:1;position:static;vertical-align:middle;cursor:pointer}
					</style></head><body data-page="admin-services-openbox">
					<main style="position:relative;height:700px"><div class="ob-chan-row">
					<label class="ob-chan-radio"><input type="radio" name="channel" checked>GitHub 直连</label>
					<label class="ob-chan-radio"><input type="radio" name="channel">镜像</label>
					</div></main></body></html>`, { waitUntil: 'load' });
					for (const index of [0, 1]) {
						if (index) await page.locator('.ob-chan-radio').nth(index).click();
						const dot = await page.locator('input:checked').evaluate((input) => {
							const style = getComputedStyle(input, '::after');
							return { width: parseFloat(style.width), height: parseFloat(style.height),
								position: getComputedStyle(input).position };
						});
						assert.equal(dot.position, 'relative', `${mount}/${width}/${appearance}: input anchors dot`);
						assert.equal(dot.width, 8, 'dot fits the 16px radio');
						assert.equal(dot.height, 8, 'dot stays circular');
					}
				} finally { await context.close(); }
			}
		}
	}
});

/* plugin adapters (styles/18-plugins.css) against markup copied from luci-app-diskman */
const DISKMAN_FIXTURE = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="/src/htdocs/luci-static/carbon/carbon.css">
</head><body data-page="admin-system-diskman-disks"><div id="maincontent">
<table class="table cbi-section-table"><tbody><tr><td>/dev/sda</td><td>2.38 GB</td></tr>
<tr width="100%" style="white-space:nowrap;"><td style="margin:0px; padding:0px; border:0px; white-space:nowrap;" colspan="15">
<div title="sda1 fat16 128.00 MB" style="color:#525F7F; display:inline-block; text-align:center; background-color:#fbbd00; width:8%">sda1 fat16 128.00 MB </div><div title="sda2 squashfs 256.00 MB" style="color:#525F7F; display:inline-block; text-align:center; background-color:#e97c30; width:8.4%">sda2 squashfs 256.00 MB </div><div title="sda3 ext4 2.00 GB" style="color:#525F7F; display:inline-block; text-align:center; background-color:#a0e0a0; width:83.6%">sda3 ext4 2.00 GB </div>
</td></tr></tbody></table></div></body></html>`;

test('DiskMan partition bar stays inside its card on desktop and phone', async () => {
	for (const width of [1280, 390]) {
		const context = await browser.newContext({ viewport: { width, height: 800 } });
		const page = await context.newPage();
		await page.goto(base + '/src/preview/form.html');
		await page.setContent(DISKMAN_FIXTURE, { waitUntil: 'load' });
		const r = await page.evaluate(() => {
			const td = document.querySelector('td[colspan]');
			const segs = [...td.children].map((d) => d.getBoundingClientRect());
			return {
				pageScroll: document.documentElement.scrollWidth - document.documentElement.clientWidth,
				inside: segs.every((b) => b.right <= td.getBoundingClientRect().right + 1),
				clipped: [...td.children].every((d) => getComputedStyle(d).textOverflow === 'ellipsis')
			};
		});
		assert.equal(r.pageScroll, 0, `${width}px: no sideways scroll`);
		assert.ok(r.inside, `${width}px: segments fit the row`);
		assert.ok(r.clipped, `${width}px: long labels ellipsize`);
		await context.close();
	}
});

/* Styling fixture for LuCI ui.Dropdown's closed/open DOM states. The menu
   stays inside its table cell, including plugins without .cbi-value-field. */
function tableDropdownFixture(mount, tag, field, appearance) {
	const row = tag === 'table' ? 'tr' : 'div';
	const cell = tag === 'table' ? 'td' : 'div';
	return `<!doctype html><html data-darkmode="${appearance === 'dark'}"><head><meta charset="utf-8">
		<link rel="stylesheet" href="/${mount}/htdocs/luci-static/carbon/carbon.css">
		</head><body data-page="admin-system-diskman-disks"><main id="maincontent" style="padding:24px">
		<div class="cbi-section"><${tag} class="table cbi-section-table">
		<${row} class="tr"><${cell} class="td">/dev/nvme0n1p1 · /boot</${cell}></${row}>
		<${row} class="tr"><${cell} class="td${field ? ' cbi-value-field' : ''}">
		<div id="mount-device" class="cbi-dropdown" tabindex="0"><ul>
		<li selected="" placeholder="" display="0" data-value="">-- Please choose --</li>
		<li data-value="/dev/sda1">/dev/sda1</li><li data-value="/dev/sdb1">/dev/sdb1</li>
		</ul><span class="open">▾</span></div>
		</${cell}></${row}></${tag}></div>
		<div class="cbi-section"><h3>Create</h3><div class="cbi-section-node">RAID</div></div>
		</main></body></html>`;
}

test('table dropdown options escape the last row and remain clickable', async () => {
	for (const mount of ['src', 'min']) {
		for (const width of [1280, 390]) {
			for (const appearance of ['light', 'dark']) {
				for (const [tag, field] of [['table', false], ['div', true]]) {
					const label = `${mount} ${width}px ${appearance} ${tag}`;
					const { page, context } = await open('/src/preview/index.html', { width, height: 800, appearance });
					try {
						await page.setContent(tableDropdownFixture(mount, tag, field, appearance), { waitUntil: 'load' });
						const closed = await page.locator('.table').boundingBox();
						await page.locator('#mount-device').evaluate((sb) => {
							const ul = sb.querySelector('ul');
							const preview = ul.cloneNode(true);
							preview.className = 'preview';
							const height = sb.offsetHeight;
							// These are the DOM changes made by LuCI's openDropdown().
							sb.setAttribute('open', '');
							sb.closest('.cbi-value-field')?.classList.add('cbi-dropdown-open');
							ul.className = 'dropdown';
							ul.style.top = height + 'px';
							ul.style.maxHeight = '300px';
							sb.insertBefore(preview, ul);
							ul.addEventListener('click', (event) => { sb.dataset.clicked = event.target.dataset.value; });
						});
						const options = await page.locator('ul.dropdown > li[data-value]:not([placeholder])').evaluateAll((items) => items.map((el) => {
							const rect = el.getBoundingClientRect();
							return {
								value: el.dataset.value,
								belowTable: rect.top > el.closest('.table').getBoundingClientRect().bottom,
								clickable: el.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2))
							};
						}));
						assert.equal(options.length, 2, label);
						for (const option of options) {
							assert.ok(option.belowTable, `${label}: ${option.value} exercises overflow beyond the table`);
							assert.ok(option.clickable, `${label}: ${option.value} must be visible and receive pointer events`);
						}
						await page.locator('ul.dropdown > li[data-value="/dev/sdb1"]').click({ timeout: 2000 });
						assert.equal(await page.locator('#mount-device').getAttribute('data-clicked'), '/dev/sdb1', label);
						if (mount === 'src' && tag === 'table')
							await page.screenshot({ path: path.join(SHOTS, `diskman-dropdown-${appearance}-${width}.png`) });
						await page.locator('#mount-device').evaluate((sb) => {
							sb.querySelector('.preview').remove();
							sb.removeAttribute('open');
							sb.closest('.cbi-value-field')?.classList.remove('cbi-dropdown-open');
							const ul = sb.querySelector('ul');
							ul.className = '';
							ul.removeAttribute('style');
						});
						assert.deepEqual(await page.locator('.table').boundingBox(), closed, `${label}: closing preserves the table layout`);
						assert.equal(await page.locator('.table').evaluate((el) => getComputedStyle(el).overflow), width > 760 ? 'hidden' : 'visible', `${label}: closed table keeps its original clipping`);
					} finally { await context.close(); }
				}
			}
		}
	}
});

/* Upstream luci-app-package-manager / luci-app-opkg inline stylesheet subset */
const PACKAGE_MANAGER_CSS = `
	.controls { display: flex; margin: .5em 0 1em 0; flex-wrap: wrap; justify-content: space-around; }
	.controls > * { padding: .25em; white-space: nowrap; flex: 1 1 33%; box-sizing: border-box; display: flex; flex-wrap: wrap; }
	.controls > *:first-child, .controls > * > label { flex-basis: 100%; min-width: 250px; }
	.controls > *:nth-child(2), .controls > *:nth-child(3) { flex-basis: 20%; }
	.controls > * > .btn { flex-basis: 20px; text-align: center; }
	.controls > * > * { flex-grow: 1; align-self: center; }
	.controls > div > input { width: auto; }
	.td.version, .td.size { white-space: nowrap; }
	#packages .td.cbi-section-actions { width: auto; }
`;

test('package manager controls align inputs and buttons on desktop and phone', async () => {
	const cases = [
		['src', 1440, 'light'], ['src', 1024, 'light'], ['src', 390, 'light'],
		['min', 1440, 'dark'], ['min', 390, 'dark']
	];
	for (const [mount, width, appearance] of cases) {
		const label = `${mount}/${width}/${appearance}`;
		const { page, context, errors } = await open('/src/preview/form.html', { width, height: 900, appearance });
		try {
			await page.setContent(`<!doctype html><html data-darkmode="${appearance === 'dark'}"><head><meta charset="utf-8">
				<link rel="stylesheet" href="/${mount}/htdocs/luci-static/carbon/carbon.css">
				<style>${PACKAGE_MANAGER_CSS}</style>
				</head><body data-page="admin-system-package-manager"><main id="maincontent" style="padding:24px"><div id="view">
				<div class="cbi-section"><div class="controls">
					<div><label>磁盘空间:</label><div class="cbi-progressbar" title="19% 已使用"><div style="width:19%">&nbsp;</div></div></div>
					<div id="filter-block"><label>筛选:</label><span class="control-group"><input type="text" name="filter" value="adg"><button class="btn cbi-button">清除</button></span></div>
					<div id="install-block"><label>下载并安装软件包:</label><span class="control-group"><input type="text" name="install" placeholder="软件包名称或 URL..."><button class="btn cbi-button cbi-button-action">确认</button></span></div>
					<div id="actions-block"><label>操作:</label> <span class="control-group"><button class="btn cbi-button-positive">更新列表...</button> <button class="btn cbi-button-action">上传软件包...</button> <button class="btn cbi-button-neutral">配置 opkg</button></span></div>
					<div id="check-block"><label>选项:</label><span class="control-group"><input type="checkbox" checked><button class="cbi-button">应用</button></span></div>
				</div></div>
				<div id="diag-group" style="margin-top:16px"><span class="control-group"><input type="text" value="openwrt.org"><button class="btn cbi-button cbi-button-action">IPv4 Ping</button></span></div>
				<div class="cbi-section-node" style="margin-top:16px">
					<div class="cbi-value"><label class="cbi-value-title">密码</label><div class="cbi-value-field"><div id="pw-group" class="control-group"><input type="password" value="secret"><button class="cbi-button cbi-button-neutral">*</button></div></div></div>
					<div class="cbi-value"><label class="cbi-value-title">本地时间</label><div class="cbi-value-field"><input type="text" readonly value="12:00"><div id="time-group" class="control-group"><button class="cbi-button">同步</button></div></div></div>
					<div class="cbi-value"><label class="cbi-value-title">列表</label><div class="cbi-value-field"><div class="cbi-dynlist"><div id="dyn-add" class="add-item"><input type="text" value="1.1.1.1"><button class="btn">+</button></div></div></div></div>
				</div>
				<div id="inline-pair" style="margin-top:16px"><input type="text" value="abc"> <button class="btn cbi-button">确定</button></div>
				<div id="btn-variants" style="margin-top:16px"><button id="btn-neutral" class="cbi-button cbi-button-neutral">N</button><button id="btn-up" class="cbi-button cbi-button-up">↑</button></div>
				</div></main></body></html>`, { waitUntil: 'load' });
			const geom = await page.evaluate(() => {
				const pair = (sel) => {
					const input = document.querySelector(sel + ' input').getBoundingClientRect();
					const btn = document.querySelector(sel + ' button').getBoundingClientRect();
					return {
						topDiff: Math.abs(input.top - btn.top),
						bottomDiff: Math.abs(input.bottom - btn.bottom),
						heightDiff: Math.abs(input.height - btn.height),
						gap: btn.left - input.right,
						btnWidth: btn.width
					};
				};
				const actionBtns = [...document.querySelectorAll('#actions-block button')].map((b) => b.getBoundingClientRect());
				return {
					overflow: document.documentElement.scrollWidth > window.innerWidth,
					filter: pair('#filter-block'),
					install: pair('#install-block'),
					diag: pair('#diag-group'),
					pw: pair('#pw-group'),
					pwMarginTop: parseFloat(getComputedStyle(document.getElementById('pw-group')).marginTop),
					timeMarginTop: parseFloat(getComputedStyle(document.getElementById('time-group')).marginTop),
					checkboxWidth: document.querySelector('#check-block input[type="checkbox"]').getBoundingClientRect().width,
					dyn: pair('#dyn-add'),
					inline: pair('#inline-pair'),
					neutralBg: getComputedStyle(document.getElementById('btn-neutral')).backgroundColor,
					upBg: getComputedStyle(document.getElementById('btn-up')).backgroundColor,
					actionBtns
				};
			});
			assert.equal(geom.overflow, false, `${label}: no horizontal overflow`);
			for (const name of ['filter', 'install', 'diag', 'pw', 'dyn']) {
				const p = geom[name];
				assert.ok(p.topDiff <= 0.5, `${label} ${name}: top aligned (${p.topDiff}px)`);
				assert.ok(p.bottomDiff <= 0.5, `${label} ${name}: bottom aligned (${p.bottomDiff}px)`);
				assert.ok(p.heightDiff <= 0.5, `${label} ${name}: equal height (${p.heightDiff}px)`);
				assert.ok(p.gap >= 4, `${label} ${name}: visible gap between input and button (${p.gap}px)`);
			}
			assert.equal(geom.pwMarginTop, 0, `${label}: first-child password control-group has no extra top margin`);
			assert.ok(geom.timeMarginTop >= 6, `${label}: follow-up control-group keeps top margin (${geom.timeMarginTop}px)`);
			assert.ok(geom.checkboxWidth <= 20, `${label}: checkbox in .controls .control-group is not stretched (${geom.checkboxWidth}px)`);
			assert.ok(geom.dyn.btnWidth < 60, `${label}: dynlist .btn add button is not stretched (${geom.dyn.btnWidth}px)`);
			assert.equal(geom.upBg, geom.neutralBg, `${label}: cbi-button-up matches cbi-button-neutral fill in ${appearance} mode`);
			for (let i = 1; i < geom.actionBtns.length; i++) {
				const prev = geom.actionBtns[i - 1], cur = geom.actionBtns[i];
				if (Math.abs(prev.top - cur.top) <= 1) {
					assert.ok(Math.abs(prev.bottom - cur.bottom) <= 0.5, `${label}: action buttons aligned`);
					assert.ok(cur.left - prev.right >= 4, `${label}: action buttons separated (${cur.left - prev.right}px)`);
				}
			}
			if (width > 760) {
				assert.ok(geom.inline.topDiff <= 0.5 && geom.inline.bottomDiff <= 0.5,
					`${label}: plain inline input + button aligned (top=${geom.inline.topDiff}, bottom=${geom.inline.bottomDiff})`);
			}
			assert.deepEqual(errors, []);
		} finally { await context.close(); }
	}
});

test('table action cells keep direct buttons compact and centred while preserving wrapped action groups', async () => {
	for (const mount of ['src', 'min']) {
		for (const width of [1440, 390]) {
			const label = `${mount}/${width}`;
			const { page, context, errors } = await open('/src/preview/form.html', { width, height: 900 });
			try {
				await page.setContent(`<!doctype html><html><head><meta charset="utf-8">
					<link rel="stylesheet" href="/${mount}/htdocs/luci-static/carbon/carbon.css">
					<style>${PACKAGE_MANAGER_CSS}</style>
					</head><body data-page="admin-system-package-manager"><main id="maincontent" style="padding:24px"><div id="view">
					<div class="cbi-section">
						<table id="packages" class="table">
							<tr class="tr cbi-section-table-titles">
								<th class="th col-2 left">软件包名称</th>
								<th class="th col-2 left version">版本</th>
								<th class="th col-1 center size">大小 (.ipk)</th>
								<th class="th col-10 left">描述</th>
								<th class="th right cbi-section-actions">&nbsp;</th>
							</tr>
							<tr class="tr">
								<td class="td col-2 left" data-title="软件包名称">luci-app-adguardhome</td>
								<td class="td col-2 left version" data-title="版本">27.320.76646~57f5dec</td>
								<td class="td col-1 center size" data-title="大小 (.ipk)">40.18 KiB</td>
								<td class="td col-10 left" data-title="描述">LuCI support for AdGuard Home</td>
								<td class="td right cbi-section-actions"><div id="pkg-install" class="btn cbi-button-action">安装...</div></td>
							</tr>
						</table>
					</div>
					<div class="cbi-section">
						<table id="actions-cases" class="table">
							<tr class="tr table-titles">
								<th class="th">名称</th>
								<th class="th cbi-section-actions">静态租约 / 操作</th>
							</tr>
							<tr class="tr">
								<td class="td" data-title="名称">direct-button</td>
								<td class="td cbi-section-actions"><button id="direct-btn" class="cbi-button cbi-button-apply">设为静态</button></td>
							</tr>
							<tr class="tr">
								<td class="td" data-title="名称">multi-direct</td>
								<td class="td cbi-section-actions"><button id="direct-a" class="cbi-button cbi-button-edit">编辑</button><button id="direct-b" class="cbi-button cbi-button-remove">删除</button></td>
							</tr>
							<tr class="tr">
								<td class="td" data-title="名称">combo-direct</td>
								<td class="td cbi-section-actions"><div id="direct-combo" class="cbi-dropdown btn cbi-button-action"><ul><li display="0">启动</li></ul><span class="open">▾</span></div></td>
							</tr>
							<tr class="tr">
								<td class="td" data-title="名称">wrapped-cbi</td>
								<td class="td cbi-section-actions" style="min-width:220px"><div id="wrapped-group"><button id="wrap-a" class="cbi-button cbi-button-edit">编辑</button><button id="wrap-b" class="cbi-button cbi-button-remove">删除</button></div></td>
							</tr>
						</table>
					</div>
					</div></main></body></html>`, { waitUntil: 'load' });

				const res = await page.evaluate(() => {
					const measureBtn = (id) => {
						const el = document.getElementById(id);
						const cs = getComputedStyle(el);
						const r = el.getBoundingClientRect();
						const td = el.closest('.td').getBoundingClientRect();
						const range = document.createRange();
						range.selectNodeContents(el);
						const tr = range.getBoundingClientRect();
						return {
							display: cs.display,
							justify: cs.justifyContent,
							width: r.width,
							height: r.height,
							tdWidth: td.width,
							leftInset: r.left - td.left,
							rightInset: td.right - r.right,
							centerDelta: Math.abs((tr.left - r.left) - (r.right - tr.right))
						};
					};
					const multiA = document.getElementById('direct-a').getBoundingClientRect();
					const multiB = document.getElementById('direct-b').getBoundingClientRect();
					const comboCs = getComputedStyle(document.getElementById('direct-combo'));
					const wrap = document.getElementById('wrapped-group');
					const wrapCs = getComputedStyle(wrap);
					const wrapR = wrap.getBoundingClientRect();
					const wrapA = document.getElementById('wrap-a').getBoundingClientRect();
					const wrapB = document.getElementById('wrap-b').getBoundingClientRect();
					return {
						pkg: measureBtn('pkg-install'),
						direct: measureBtn('direct-btn'),
						multiTopDiff: Math.abs(multiA.top - multiB.top),
						multiGap: multiB.left - multiA.right,
						combo: { display: comboCs.display, justify: comboCs.justifyContent },
						wrapped: {
							display: wrapCs.display,
							leftGap: wrapA.left - wrapR.left,
							rightGap: wrapR.right - wrapB.right,
							topDiff: Math.abs(wrapA.top - wrapB.top),
							gap: wrapB.left - wrapA.right
						}
					};
				});

				for (const [name, b] of [['pkg-install', res.pkg], ['direct-btn', res.direct]]) {
					assert.equal(b.display, 'inline-flex', `${label} ${name}: stays inline-flex`);
					assert.equal(b.justify, 'center', `${label} ${name}: centres label`);
					assert.ok(b.centerDelta <= 2, `${label} ${name}: text centred inside button (delta=${b.centerDelta})`);
					assert.ok(b.width < 120, `${label} ${name}: compact auto width (${b.width}px)`);
					assert.ok(b.height <= 30, `${label} ${name}: compact table action height (${b.height}px)`);
				}
				if (width > 760) {
					assert.ok(res.pkg.rightInset <= 20, `${label} pkg-install: aligned to right edge of action cell (${res.pkg.rightInset}px)`);
				} else {
					assert.ok(res.pkg.leftInset <= 16, `${label} pkg-install: aligned to left edge of mobile card (${res.pkg.leftInset}px)`);
				}
				assert.ok(res.multiTopDiff <= 1 && res.multiGap >= 3.5, `${label}: adjacent direct buttons keep gap without whitespace (${res.multiGap}px)`);
				assert.equal(res.combo.display, 'inline-flex', `${label}: direct combo button keeps inline-flex`);
				assert.equal(res.combo.justify, 'center', `${label}: direct combo button keeps button alignment`);
				assert.equal(res.wrapped.display, 'flex', `${label}: CBI wrapper div keeps flex`);
				if (width > 760) {
					assert.ok(res.wrapped.rightGap <= 1 && res.wrapped.leftGap >= 40,
						`${label}: CBI wrapper stays right-aligned on desktop (left=${res.wrapped.leftGap}, right=${res.wrapped.rightGap})`);
				} else {
					assert.ok(res.wrapped.leftGap <= 1 && res.wrapped.rightGap >= 40,
						`${label}: CBI wrapper stays left-aligned on phone (left=${res.wrapped.leftGap}, right=${res.wrapped.rightGap})`);
				}
				assert.ok(res.wrapped.topDiff <= 1 && res.wrapped.gap >= 3.5, `${label}: wrapped buttons keep row gap`);
				assert.deepEqual(errors, []);
			} finally { await context.close(); }
		}
	}
});

test('button variants stay consistent across <button> and <input> elements, destructive actions and hover states', async () => {
	const parseRgb = (s) => (s.match(/[\d.]+/g) || []).slice(0, 3).map(Number);
	const isReddish = (s) => { const [r, g, b] = parseRgb(s); return r > g + 40 && r > b + 40; };
	const isGreenish = (s) => { const [r, g, b] = parseRgb(s); return g > r + 25 && g > b + 10; };
	const isBluish = (s) => { const [r, g, b] = parseRgb(s); return b > r + 25; };

	for (const mount of ['src', 'min']) {
		for (const appearance of ['light', 'dark']) {
			const label = `${mount}/${appearance}`;
			const { page, context, errors } = await open('/src/preview/form.html', { width: 1280, height: 900, appearance });
			try {
				await page.setContent(`<!doctype html><html data-darkmode="${appearance === 'dark'}"><head><meta charset="utf-8">
					<link rel="icon" href="data:,">
					<link rel="stylesheet" href="/${mount}/htdocs/luci-static/carbon/carbon.css">
					<style>.demo-row{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:12px 0}</style>
					</head><body data-page="admin-services-passwall"><main id="maincontent" style="padding:24px"><div id="view">
					<section class="cbi-section"><div class="cbi-section-node">
						<div class="demo-row" id="ref-buttons">
							<button id="btn-base" class="btn cbi-button">取消</button>
							<button id="btn-neutral" class="cbi-button cbi-button-neutral">重启</button>
							<button id="btn-toggle" class="cbi-button cbi-button-neutral enable-disable">禁用</button>
							<button id="btn-iface-down" class="cbi-button cbi-button-neutral down">关闭</button>
							<button id="btn-add" class="cbi-button cbi-button-add">添加</button>
							<button id="btn-action" class="cbi-button cbi-button-action">调整</button>
							<button id="btn-remove" class="cbi-button cbi-button-remove">断开连接</button>
							<button id="btn-negative" class="cbi-button cbi-button-negative remove">删除</button>
							<button id="btn-reset" class="cbi-button cbi-button-reset">重置</button>
							<button id="btn-danger" class="btn danger">危险</button>
							<button id="btn-error" class="btn error">错误</button>
							<a id="link-danger" class="btn danger" href="#">危险链接</a>
							<button id="btn-success" class="btn success">成功</button>
							<button id="btn-primary" class="cbi-button cbi-button-apply">保存并应用</button>
							<button id="btn-neg-imp" class="btn cbi-button cbi-button-negative important">断开确认</button>
							<button id="btn-rem-imp" class="btn cbi-button cbi-button-remove important">强制删除</button>
							<button id="btn-rst-imp" class="btn cbi-button cbi-button-reset important">恢复出厂</button>
							<button id="btn-dng-imp" class="btn danger important">危险确认</button>
						</div>
						<div class="demo-row pw-toolbar" id="passwall-toolbar">
							<input id="inp-add" class="btn cbi-button cbi-button-add" type="button" value="添加" />
							<input id="inp-add-sub" class="btn cbi-button cbi-button-add" type="submit" value="添加节点" />
							<input id="inp-fieldadd" class="btn cbi-button cbi-button-fieldadd" type="submit" value="添加字段" />
							<input id="inp-clear" class="btn cbi-button cbi-button-remove" type="button" value="清空所有节点" />
							<input id="inp-del-sel" class="btn cbi-button cbi-button-remove" type="button" value="删除选择的节点" />
							<input id="inp-del-sub" class="btn cbi-button cbi-button-remove" type="submit" value="删除" />
							<input id="inp-group" class="btn cbi-button cbi-button-edit" type="button" value="调整分组" />
							<input id="inp-apply" class="btn cbi-button cbi-button-apply" type="submit" value="保存并应用" />
							<input id="inp-reset-btn" class="btn cbi-button cbi-button-reset" type="button" value="重置" />
							<input id="inp-reset-rst" class="btn cbi-button cbi-button-reset" type="reset" value="复位" />
							<input id="inp-neutral" class="btn cbi-button cbi-button-neutral" type="button" value="跳过" />
							<button id="pw-filter-reset" type="button" class="btn cbi-button" data-pw-reset="1">重置筛选</button>
						</div>
						<div class="cbi-section-remove right">
							<input id="sec-remove" type="submit" value="删除" class="btn cbi-button" />
						</div>
					</div></section>
					<table class="table cbi-section-table">
						<tr class="tr cbi-section-table-row">
							<td class="td">Singapore-01</td>
							<td class="td cbi-section-actions"><div>
								<input id="row-top" class="btn cbi-button cbi-button-edit" type="button" value="置顶" />
								<input id="row-use" class="btn cbi-button cbi-button-apply" type="button" value="使用" />
								<input id="row-copy" class="btn cbi-button cbi-button-add" type="button" value="复制" />
								<input id="row-edit" class="btn cbi-button cbi-button-edit" type="button" value="编辑" />
								<input id="row-del" class="btn cbi-button cbi-button-remove" type="button" value="删除" />
							</div></td>
						</tr>
					</table>
					<div class="cbi-page-actions" id="actions-apply">
						<input id="pa-apply" class="btn cbi-button cbi-button-apply" type="button" value="保存并应用" />
						<input id="pa-save-after-apply" class="btn cbi-button cbi-button-save" type="submit" value="保存" />
						<input id="pa-reset" class="btn cbi-button cbi-button-reset" type="button" value="重置" />
					</div>
					<div class="cbi-page-actions" id="actions-unchecked" style="position:static;margin-top:12px">
						<button id="pa-unchecked" class="btn cbi-button cbi-button-negative important">强制应用</button>
						<button id="pa-save-after-neg" class="cbi-button cbi-button-save">保存</button>
					</div>
					</div></main></body></html>`, { waitUntil: 'load' });

				const readStyles = (ids) => page.evaluate((list) => Object.fromEntries(list.map((id) => {
					const cs = getComputedStyle(document.getElementById(id));
					return [id, { bg: cs.backgroundColor, fg: cs.color, shadow: cs.boxShadow }];
				})), ids);

				const ids = [
					'btn-base', 'btn-neutral', 'btn-toggle', 'btn-iface-down', 'btn-add', 'btn-action',
					'btn-remove', 'btn-negative', 'btn-reset', 'btn-danger', 'btn-error', 'link-danger',
					'btn-success', 'btn-primary', 'btn-neg-imp', 'btn-rem-imp', 'btn-rst-imp', 'btn-dng-imp',
					'inp-add', 'inp-add-sub', 'inp-fieldadd', 'inp-clear', 'inp-del-sel', 'inp-del-sub',
					'inp-group', 'inp-apply', 'inp-reset-btn', 'inp-reset-rst', 'inp-neutral', 'pw-filter-reset',
					'sec-remove', 'row-top', 'row-use', 'row-copy', 'row-edit', 'row-del',
					'pa-apply', 'pa-save-after-apply', 'pa-reset', 'pa-unchecked', 'pa-save-after-neg'
				];
				const st = await readStyles(ids);

				/* Tinted red: every destructive/reset button matches regardless of <button> vs <input> */
				assert.ok(isReddish(st['btn-remove'].fg), `${label}: reference remove button is red (${st['btn-remove'].fg})`);
				assert.notEqual(st['btn-remove'].bg, st['btn-base'].bg, `${label}: tinted red differs from secondary bg`);
				for (const id of [
					'btn-negative', 'btn-reset', 'btn-iface-down', 'btn-danger', 'btn-error', 'link-danger',
					'inp-clear', 'inp-del-sel', 'inp-del-sub', 'inp-reset-btn', 'inp-reset-rst',
					'sec-remove', 'row-del', 'pa-reset'
				]) {
					assert.deepEqual(st[id], st['btn-remove'], `${label} #${id}: matches tinted red variant`);
				}

				/* Tinted green: <input> and .btn.success match <button class="cbi-button-add"> */
				assert.ok(isGreenish(st['btn-add'].fg), `${label}: reference add button is green (${st['btn-add'].fg})`);
				for (const id of ['btn-success', 'inp-add', 'inp-add-sub', 'inp-fieldadd', 'row-copy']) {
					assert.deepEqual(st[id], st['btn-add'], `${label} #${id}: matches tinted green variant`);
				}

				/* Tinted accent: outside .cbi-section-actions, <input class="cbi-button-edit"> matches action tint */
				assert.ok(isBluish(st['btn-action'].fg), `${label}: reference action button is accent (${st['btn-action'].fg})`);
				assert.deepEqual(st['inp-group'], st['btn-action'], `${label}: PassWall Reassign Group matches tinted accent`);

				/* Solid primary indigo: applies inside .cbi-section-actions .cbi-button-edit and .cbi-button-apply */
				assert.ok(isBluish(st['btn-primary'].bg), `${label}: primary button bg is indigo (${st['btn-primary'].bg})`);
				for (const id of ['inp-apply', 'row-top', 'row-use', 'row-edit', 'pa-apply']) {
					assert.deepEqual(st[id], st['btn-primary'], `${label} #${id}: matches solid primary indigo`);
				}

				/* Solid danger red: important destructive variants stay solid red, never solid indigo */
				assert.ok(isReddish(st['btn-neg-imp'].bg), `${label}: negative.important bg is solid red (${st['btn-neg-imp'].bg})`);
				assert.notEqual(st['btn-neg-imp'].bg, st['btn-remove'].bg, `${label}: solid danger differs from tinted red`);
				for (const id of ['btn-rem-imp', 'btn-rst-imp', 'btn-dng-imp', 'pa-unchecked']) {
					assert.deepEqual(st[id], st['btn-neg-imp'], `${label} #${id}: matches solid red danger`);
				}

				/* Neutral & secondary buttons stay untouched (no false positives) */
				assert.deepEqual(st['btn-toggle'], st['btn-neutral'], `${label}: enable-disable stays neutral`);
				assert.deepEqual(st['inp-neutral'], st['btn-neutral'], `${label}: <input class="cbi-button-neutral"> matches neutral`);
				assert.notEqual(st['btn-neutral'].bg, st['btn-remove'].bg, `${label}: neutral is not red`);
				assert.deepEqual(st['pw-filter-reset'], st['btn-base'], `${label}: PassWall filter reset stays secondary chip`);
				assert.deepEqual(st['pa-save-after-apply'], st['btn-base'], `${label}: Save after Apply stays secondary chip`);
				assert.deepEqual(st['pa-save-after-neg'], st['btn-base'], `${label}: Save after Apply-unchecked stays secondary chip`);
				if (mount === 'src')
					await page.screenshot({ path: path.join(SHOTS, `button-variants-${appearance}.png`), fullPage: true });

				/* Hover states: <input> variants keep their semantic hover color; solid danger never turns indigo */
				const hoverStyle = async (id) => {
					await page.hover('#' + id);
					await page.evaluate((elId) => Promise.all(document.getElementById(elId).getAnimations().map((a) => a.finished)), id);
					return (await readStyles([id]))[id];
				};

				const clearHover = await hoverStyle('inp-clear');
				assert.ok(isReddish(clearHover.fg), `${label}: hovered <input class="cbi-button-remove"> keeps red fg (${clearHover.fg})`);
				assert.ok(clearHover.shadow.includes(clearHover.fg), `${label}: hovered <input class="cbi-button-remove"> gets red ring (${clearHover.shadow})`);

				const addHover = await hoverStyle('inp-add');
				assert.ok(isGreenish(addHover.fg), `${label}: hovered <input class="cbi-button-add"> keeps green fg (${addHover.fg})`);
				assert.ok(addHover.shadow.includes(addHover.fg), `${label}: hovered <input class="cbi-button-add"> gets green ring (${addHover.shadow})`);

				const dangerHover = await hoverStyle('btn-danger');
				assert.ok(isReddish(dangerHover.fg), `${label}: hovered .btn.danger keeps red fg (${dangerHover.fg})`);
				assert.ok(dangerHover.shadow.includes(dangerHover.fg), `${label}: hovered .btn.danger gets red ring (${dangerHover.shadow})`);

				const negImpHover = await hoverStyle('btn-neg-imp');
				assert.ok(isReddish(negImpHover.bg), `${label}: hovered .cbi-button-negative.important stays solid red, never indigo (${negImpHover.bg})`);
				assert.notEqual(negImpHover.bg, st['btn-neg-imp'].bg, `${label}: hovered solid danger visibly shifts shade`);
				assert.equal(negImpHover.fg, 'rgb(255, 255, 255)', `${label}: hovered solid danger keeps white text`);

				const secSaveHover = await hoverStyle('pa-save-after-apply');
				assert.ok(isBluish(secSaveHover.fg), `${label}: hovered secondary Save shows accent hover feedback (${secSaveHover.fg})`);

				/* Clicking <input type="button"> does not trigger text-input focus ring (parity with <button>) */
				await page.click('#inp-apply');
				await page.evaluate(() => Promise.all(document.getElementById('inp-apply').getAnimations().map((a) => a.finished)));
				const clickedApply = (await readStyles(['inp-apply']))['inp-apply'];
				assert.equal(clickedApply.shadow, st['btn-primary'].shadow, `${label}: mouse-clicking <input type="submit"> keeps button shadow`);

				/* System -> Reboot page: Perform reboot button is solid red at rest and on hover */
				await page.setContent(`<!doctype html><html data-darkmode="${appearance === 'dark'}"><head><meta charset="utf-8">
					<link rel="icon" href="data:,">
					<link rel="stylesheet" href="/${mount}/htdocs/luci-static/carbon/carbon.css">
					</head><body data-page="admin-system-reboot"><main id="maincontent" style="padding:24px"><div id="view">
					<h2>重启</h2><p>重启设备的操作系统</p><hr>
					<button id="reboot-btn" class="cbi-button cbi-button-action important">执行重启</button>
					</div></main></body></html>`, { waitUntil: 'load' });
				const rebootRest = (await readStyles(['reboot-btn']))['reboot-btn'];
				assert.deepEqual(rebootRest, st['btn-neg-imp'], `${label}: System->Reboot button is solid danger red`);
				const rebootHover = await hoverStyle('reboot-btn');
				assert.ok(isReddish(rebootHover.bg), `${label}: hovered System->Reboot button stays red (${rebootHover.bg})`);

				assert.deepEqual(errors, []);
			} finally { await context.close(); }
		}
	}
});

test('lease table avatars stay in the hostname column when hostnames are IP addresses', async () => {
	for (const mount of ['src', 'min']) {
		const { page, context, errors } = await open('/src/preview/form.html', { width: 1280, height: 900 });
		try {
			await page.setContent(`<!doctype html><html><head><meta charset="utf-8">
				<link rel="stylesheet" href="/${mount}/htdocs/luci-static/carbon/carbon.css">
				<script src="/${mount}/htdocs/luci-static/carbon/carbon.js?v=test"></script>
				</head><body><div id="view">
				<table id="status_leases" class="table">
					<tr class="tr table-titles"><th class="th">状态</th><th class="th">主机名</th><th class="th">IPv4 地址</th><th class="th">MAC 地址</th><th class="th">剩余租期</th></tr>
					<tr class="tr" data-case="normal"><td class="td"><span class="dot"></span></td><td class="td">lwip0</td><td class="td">10.0.0.10</td><td class="td">02:11:22:33:44:01</td><td class="td">11h 59m</td></tr>
					<tr class="tr" data-case="ip-unknown"><td class="td"><span class="dot"></span></td><td class="td">10.0.0.194</td><td class="td">10.0.0.194</td><td class="td">02:11:22:33:44:55</td><td class="td">11h 57m</td></tr>
					<tr class="tr" data-case="ip-apple"><td class="td"><span class="dot"></span></td><td class="td">10.0.0.195</td><td class="td">10.0.0.195</td><td class="td">f0:ee:7a:66:0b:3e</td><td class="td">11h 56m</td></tr>
					<tr class="tr" data-case="dash-apple"><td class="td"><span class="dot"></span></td><td class="td">-</td><td class="td">10.0.0.196</td><td class="td">f0:ee:7a:66:0b:3f</td><td class="td">11h 55m</td></tr>
				</table>
				<table id="lease_status_table" class="table">
					<tr class="tr table-titles"><th class="th">接口</th><th class="th">主机名</th><th class="th">IPv4 地址</th><th class="th">MAC 地址</th><th class="th">剩余租期</th></tr>
					<tr class="tr" data-case="single-iface-ip"><td class="td">lan</td><td class="td">10.0.0.194</td><td class="td">10.0.0.194</td><td class="td">02:11:22:33:44:55</td><td class="td">11h 59m</td></tr>
				</table>
				<table id="status_leases6" class="table">
					<tr class="tr table-titles"><th class="th">状态</th><th class="th">主机</th><th class="th">IPv6 地址</th><th class="th">DUID</th><th class="th">剩余租期</th></tr>
					<tr class="tr" data-case="v6-dot-ip-hint"><td class="td"><span class="dot"></span></td><td class="td">10.0.0.194</td><td class="td">2001:db8::1/128<br>fd00::1/128</td><td class="td">000100012a3b4c5df0ee7a660b3e</td><td class="td">11h 59m</td></tr>
				</table>
				<table id="lease6_status_table" class="table">
					<tr class="tr table-titles"><th class="th">主机</th><th class="th">IPv6 地址</th><th class="th">DUID</th><th class="th">剩余租期</th></tr>
					<tr class="tr" data-case="v6-single-nolead"><td class="td">10.0.0.194</td><td class="td">fe80::1/128</td><td class="td">00030001021122334455</td><td class="td">11h 59m</td></tr>
				</table>
				</div></body></html>`, { waitUntil: 'load' });

			await page.evaluate(() => { window.Carbon.initLeaseAvatars(document.getElementById('view')); });
			await page.waitForFunction(() => document.querySelector('[data-case="normal"] .cb-host') && document.querySelector('[data-case="v6-dot-ip-hint"] .cb-host'));

			const inspect = (sel) => page.evaluate((s) => {
				const cells = [...document.querySelector(s).children].filter((c) => c.classList.contains('td'));
				return cells.map((c) => {
					const av = c.querySelector('.cb-avatar');
					const nm = c.querySelector('.cb-host-name');
					return {
						hosts: c.querySelectorAll('.cb-host').length,
						hasDotDirect: !!c.querySelector(':scope > .dot'),
						brand: av ? av.classList.contains('cb-avatar-brand') : false,
						brandTitle: av ? av.getAttribute('title') : null,
						avatarText: av ? av.textContent : null,
						hasSvg: av ? !!av.querySelector('svg') : false,
						hostName: nm ? nm.textContent : null
					};
				});
			}, sel);

			/* 1. Multi-row #status_leases with leading status-dot column */
			for (const name of ['normal', 'ip-unknown', 'ip-apple', 'dash-apple']) {
				const cols = await inspect(`[data-case="${name}"]`);
				assert.equal(cols[0].hosts, 0, `${mount} ${name}: status-dot cell stays undecorated`);
				assert.equal(cols[0].hasDotDirect, true, `${mount} ${name}: dot remains direct child of col 0`);
				assert.equal(cols[1].hosts, 1, `${mount} ${name}: hostname cell gets avatar`);
			}
			const ipUnknown = await inspect('[data-case="ip-unknown"]');
			assert.equal(ipUnknown[1].hostName, '10.0.0.194', `${mount}: IP hostname text preserved`);
			assert.equal(ipUnknown[1].hasSvg, true, `${mount}: IP hostname with unknown MAC uses laptop icon, not digit "1"`);
			assert.equal(ipUnknown[1].avatarText, '', `${mount}: no numeric monogram for IP hostname`);

			const ipApple = await inspect('[data-case="ip-apple"]');
			assert.equal(ipApple[1].brand, true, `${mount}: IP hostname with known OUI gets brand avatar`);
			assert.equal(ipApple[1].brandTitle, 'Apple');

			/* 2. Single-row table with leading Interface column and IP hostname */
			const singleIface = await inspect('[data-case="single-iface-ip"]');
			assert.equal(singleIface[0].hosts, 0, `${mount}: Interface column stays undecorated`);
			assert.equal(singleIface[1].hosts, 1, `${mount}: single IP-hostname row still decorated in col 1`);
			assert.equal(singleIface[1].hasSvg, true, `${mount}: single IP-hostname row uses laptop icon`);

			/* 3. DHCPv6 table with leading dot, IPv4 fallback hostname, <br>-joined IPv6 and DUID-LLT */
			const v6Dot = await inspect('[data-case="v6-dot-ip-hint"]');
			assert.equal(v6Dot[0].hosts, 0, `${mount} v6: status-dot cell stays undecorated`);
			assert.equal(v6Dot[1].hosts, 1, `${mount} v6: hostname cell decorated`);
			assert.equal(v6Dot[1].brandTitle, 'Apple', `${mount} v6: DUID-LLT MAC identifies Apple`);

			/* 4. Single-row DHCPv6 table without leading column and IPv4 fallback hostname */
			const v6NoLead = await inspect('[data-case="v6-single-nolead"]');
			assert.equal(v6NoLead[0].hosts, 1, `${mount} v6 no-lead: col 0 IP-hostname gets avatar`);
			assert.equal(v6NoLead[0].hasSvg, true, `${mount} v6 no-lead: uses laptop icon`);

			/* 5. Dynamic MutationObserver updates: append IP row, missing-IP row with MAC/time, single no-lead IPv4 row */
			await page.evaluate(() => {
				const t = document.getElementById('status_leases');
				const tr = document.createElement('tr');
				tr.className = 'tr';
				tr.setAttribute('data-case', 'appended-ip');
				tr.innerHTML = '<td class="td"><span class="dot"></span></td><td class="td">10.0.0.199</td><td class="td">10.0.0.199</td><td class="td">02:11:22:33:44:99</td><td class="td">11h 50m</td>';
				t.appendChild(tr);

				const t2 = document.getElementById('lease_status_table');
				t2.innerHTML = '<tr class="tr table-titles"><th class="th">主机名</th><th class="th">IPv4 地址</th><th class="th">MAC 地址</th><th class="th">剩余租期</th></tr>' +
					'<tr class="tr" data-case="missing-ip"><td class="td">host-no-ip</td><td class="td">-</td><td class="td">f0:ee:7a:66:0b:3e</td><td class="td">11:59:00</td></tr>';
			});
			await page.waitForFunction(() => document.querySelector('[data-case="appended-ip"] .cb-host'));
			const appended = await inspect('[data-case="appended-ip"]');
			assert.equal(appended[0].hosts, 0, `${mount} appended: col 0 untouched`);
			assert.equal(appended[1].hosts, 1, `${mount} appended: col 1 decorated`);
			assert.equal(appended[1].hasSvg, true, `${mount} appended: laptop icon`);
			const normalAfter = await inspect('[data-case="normal"]');
			assert.equal(normalAfter[1].hosts, 1, `${mount}: existing rows not double-wrapped`);

			const missingIp = await inspect('[data-case="missing-ip"]');
			assert.equal(missingIp[1].hosts, 0, `${mount}: MAC address is never mistaken for an IPv6 cell`);
			assert.equal(missingIp[2].hosts, 0, `${mount}: HH:MM:SS time is never mistaken for an IPv6 cell`);

			await page.evaluate(() => {
				const t2 = document.getElementById('lease_status_table');
				t2.innerHTML = '<tr class="tr table-titles"><th class="th">主机名</th><th class="th">IPv4 地址</th><th class="th">MAC 地址</th><th class="th">剩余租期</th></tr>' +
					'<tr class="tr" data-case="v4-single-nolead"><td class="td">10.0.0.194</td><td class="td">10.0.0.194</td><td class="td">02:11:22:33:44:55</td><td class="td">11h 59m</td></tr>';
			});
			await page.waitForFunction(() => document.querySelector('[data-case="v4-single-nolead"] .cb-host'));
			const v4NoLead = await inspect('[data-case="v4-single-nolead"]');
			assert.equal(v4NoLead[0].hosts, 1, `${mount} v4 no-lead: col 0 IP-hostname gets avatar`);
			assert.equal(v4NoLead[0].hasSvg, true, `${mount} v4 no-lead: uses laptop icon`);

			assert.deepEqual(errors, []);
		} finally { await context.close(); }
	}
});

test('settings page: buttons, links, fields and status text share one centre line', async () => {
	for (const width of [1200, 390]) {
		const { page, context, errors } = await open('/src/tests/fixtures/settings.html', { width });
		await page.waitForSelector('body[data-ready]');
		/* a status message next to the mirror field, as after saving */
		await page.evaluate(() => { document.querySelector('#carbon-mirror').closest('.cb-update-field').querySelector('.cb-update-note').textContent = '已保存。'; });
		const rows = await page.evaluate(() => [...document.querySelectorAll('.cb-update-actions, .cb-logo-actions, .cb-update-field')].map((row) => {
			const kids = [...row.children].filter((c) => c.offsetParent && c.getBoundingClientRect().width);
			/* compare items on the same line only (rows may wrap on phones) */
			const lines = {};
			kids.forEach((c) => {
				const r = c.getBoundingClientRect(), mid = r.top + r.height / 2;
				const key = Object.keys(lines).find((k) => Math.abs(k - mid) < 12) || mid;
				(lines[key] = lines[key] || []).push(mid);
			});
			return { row: row.className, spread: Math.max(...Object.values(lines).map((m) => Math.max(...m) - Math.min(...m))) };
		}));
		assert.equal(rows.length, 6, JSON.stringify(rows));
		const stray = await page.evaluate(() => [...document.querySelectorAll('#view *')].flatMap((el) => [...el.childNodes])
			.filter((n) => n.nodeType === 3 && /^(null|undefined)$/.test(n.textContent.trim())).length);
		assert.equal(stray, 0, 'no "null" / "undefined" text from absent children');
		/* release notes from the built-in renderer: structure, safe links, local scrolling */
		const notes = await page.evaluate(() => {
			const box = document.querySelector('.cb-release-notes');
			return {
				tags: ['h2', 'h3', 'ul', 'li', 'strong', 'table', 'pre', 'code'].filter((t) => box.querySelector(t)),
				links: [...box.querySelectorAll('a')].every((a) => a.target === '_blank' && a.rel === 'noopener noreferrer'),
				fits: box.scrollWidth <= box.clientWidth + 1 || getComputedStyle(box).overflowX !== 'visible'
			};
		});
		assert.deepEqual(notes.tags, ['h2', 'h3', 'ul', 'li', 'strong', 'table', 'pre', 'code']);
		assert.ok(notes.links && notes.fits);
		if (width === 1200) await page.screenshot({ path: path.join(SHOTS, 'settings-release-notes.png'), fullPage: true });
		rows.forEach((r) => assert.ok(r.spread <= 0.5, `${width}px ${r.row}: ${r.spread}px off centre`));
		assert.deepEqual(errors, []);
		await context.close();
	}
});

test('settings page: the mirror explanation lives in a ? toggletip', async () => {
	for (const width of [1200, 390]) {
		const { page, context, errors } = await open('/src/tests/fixtures/settings.html', { width, height: 900 });
		await page.waitForSelector('body[data-ready]');
		const section = page.locator('section.cbi-section', { has: page.locator('#carbon-mirror') });
		assert.equal(await section.locator('.cbi-section-descr').count(), 0, 'no long paragraph on the page');
		const btn = section.locator('h3 .cb-hint-btn'), bubble = section.locator('.cb-hint-bubble');
		const shown = () => bubble.evaluate((b) => getComputedStyle(b).visibility === 'visible');
		assert.equal(await btn.getAttribute('aria-describedby'), await bubble.getAttribute('id'));
		assert.match(await bubble.textContent(), /HTTPS/);
		assert.equal(await shown(), false, 'hidden by default');
		await btn.hover();
		await page.waitForTimeout(200);
		assert.equal(await shown(), true, 'hover shows it');
		await page.mouse.move(5, 5);
		await page.waitForTimeout(200);
		assert.equal(await shown(), false, 'leaving hides it');
		await btn.click();
		await page.mouse.move(5, 5);
		await page.waitForTimeout(200);
		assert.equal(await shown(), true, 'a click pins it');
		assert.equal(await btn.getAttribute('aria-expanded'), 'true');
		const box = await bubble.boundingBox();
		assert.ok(box.x >= 0 && box.x + box.width <= width, `${width}px: bubble inside the window`);
		await page.mouse.click(5, 5);
		await page.waitForTimeout(200);
		assert.equal(await shown(), false, 'a click elsewhere closes it');
		await btn.click();
		await page.keyboard.press('Escape');
		await page.waitForTimeout(200);
		assert.equal(await btn.getAttribute('aria-expanded'), 'false', 'Esc closes it');
		await page.keyboard.press('Tab');
		await page.keyboard.press('Shift+Tab');
		await page.waitForTimeout(200);
		assert.equal(await shown(), true, 'keyboard focus shows it');
		if (width === 1200) {
			await page.mouse.move(5, 5);
			await btn.hover();
			await page.waitForTimeout(200);
			await section.screenshot({ path: path.join(SHOTS, 'settings-mirror-hint.png') });
		}
		assert.deepEqual(errors, []);
		await context.close();
	}
});

test('language switch is a Carbon listbox with every bundled language', async () => {
	const { page, context } = await open('/src/preview/index.html?lang=en');
	await page.waitForSelector('.cb-lang .cb-lb');
	assert.equal(await page.$('.cb-lang select'), null, 'no native select');
	assert.equal(await page.textContent('.cb-lang .cb-lb'), 'English');
	await page.click('.cb-lang .cb-lb');
	const list = await page.evaluate(() => {
		const ul = document.querySelector('.cb-lb-list');
		const r = ul.getBoundingClientRect(), t = document.querySelector('.cb-lang .cb-lb').getBoundingClientRect();
		return {
			labels: [...ul.children].map((li) => li.textContent),
			selected: [...ul.querySelectorAll('[aria-selected="true"]')].map((li) => li.textContent),
			expanded: document.querySelector('.cb-lang .cb-lb').getAttribute('aria-expanded'),
			focus: document.activeElement === ul,
			opensUp: r.bottom <= t.top, inView: r.top >= 0 && r.bottom <= innerHeight,
			bg: getComputedStyle(ul).backgroundColor
		};
	});
	assert.deepEqual(list.labels, ['Auto', 'English', 'Deutsch', 'Español', 'Français', 'Italiano', '日本語', '한국어',
		'Português do Brasil', 'Русский', 'Türkçe', 'Tiếng Việt', '简体中文', '繁體中文']);
	assert.deepEqual(list.selected, ['English']);
	assert.equal(list.expanded, 'true');
	assert.ok(list.focus, 'the list takes focus');
	assert.ok(list.opensUp && list.inView, 'opens above the footer trigger, inside the window');
	await Promise.all([page.waitForURL(/lang=zh-Hant/), page.click('.cb-lb-list li:has-text("繁體中文")')]);
	await page.waitForSelector('.cb-dash');
	assert.equal(await page.textContent('.cb-card.cb-traffic h3'), await page.evaluate(() => window.Carbon.I18N['Live Traffic']));
	assert.equal(await page.textContent('.cb-lang .cb-lb'), '繁體中文');
	await context.close();
});

test('language listbox: keyboard, type-ahead and dismissal', async () => {
	const { page, context } = await open('/src/preview/index.html?lang=en');
	await page.waitForSelector('.cb-lang .cb-lb');
	await page.focus('.cb-lang .cb-lb');
	await page.keyboard.press('ArrowDown');
	const activeText = () => page.evaluate(() => document.querySelector('.cb-lb-list li.active').textContent);
	assert.equal(await activeText(), 'English', 'opens on the current language');
	assert.equal(await page.evaluate(() => document.querySelector('.cb-lb-list').getAttribute('aria-activedescendant') === document.querySelector('.cb-lb-list li.active').id), true);
	await page.keyboard.press('End');
	assert.equal(await activeText(), '繁體中文');
	await page.waitForTimeout(150);
	assert.notEqual(await page.$('.cb-lb-list'), null, 'scrolling inside the list keeps it open');
	await page.keyboard.press('Home');
	assert.equal(await activeText(), 'Auto');
	await page.keyboard.type('fr');
	assert.equal(await activeText(), 'Français', 'type-ahead');
	await page.keyboard.press('Escape');
	assert.equal(await page.$('.cb-lb-list'), null, 'Escape closes');
	assert.equal(await page.evaluate(() => document.activeElement.classList.contains('cb-lb')), true, 'focus returns to the trigger');
	assert.equal(new URL(page.url()).searchParams.get('lang'), 'en', 'nothing chosen yet');
	await page.click('.cb-lang .cb-lb');
	await page.mouse.click(700, 400);
	assert.equal(await page.$('.cb-lb-list'), null, 'an outside click closes');
	await page.focus('.cb-lang .cb-lb');
	await page.keyboard.press('Enter');
	await page.keyboard.press('ArrowDown');
	await Promise.all([page.waitForURL(/lang=de/), page.keyboard.press('Enter')]);
	await context.close();
});

test('language listbox opens beside the collapsed rail and returns focus to it', async () => {
	const { page, context } = await open('/src/preview/index.html?lang=en', { storage: { 'carbon.collapsed': '1' } });
	await page.waitForSelector('.cb-lang-mini');
	await page.click('.cb-lang-mini');
	const r = await page.evaluate(() => {
		const ul = document.querySelector('.cb-lb-list').getBoundingClientRect();
		return { left: ul.left, rail: document.getElementById('cb-sidebar').getBoundingClientRect().right, bottom: ul.bottom, h: innerHeight };
	});
	assert.ok(r.left >= r.rail, 'beside the rail');
	assert.ok(r.bottom <= r.h, 'inside the window');
	await page.keyboard.press('Escape');
	assert.equal(await page.evaluate(() => document.activeElement.classList.contains('cb-lang-mini')), true);
	await page.click('.cb-lang-mini');
	await page.click('.cb-lang-mini');
	assert.equal(await page.$('.cb-lb-list'), null, 'the rail button toggles');
	await context.close();
});

test('segmented controls follow the radio pattern', async () => {
	const { page, context } = await open('/src/preview/index.html?lang=en');
	await page.waitForSelector('#cb-appearance .cb-seg-btn');
	await page.focus('#cb-appearance .cb-seg-btn[aria-checked="true"]');
	await page.keyboard.press('ArrowRight');           // auto | light | dark: light → dark
	assert.equal(await page.getAttribute('html', 'data-appearance'), 'dark');
	assert.deepEqual(await page.$$eval('#cb-appearance .cb-seg-btn', (b) => b.map((x) => x.tabIndex)), [-1, -1, 0]);
	assert.equal(await page.evaluate(() => document.activeElement.getAttribute('aria-checked')), 'true');
	await context.close();
});

test('collapsed rail: keyboard opens and leaves the sub-menu, touch taps toggle it', async () => {
	const storage = { 'carbon.collapsed': '1', 'carbon.mode': 'pro' };
	let { page, context } = await open('/src/preview/index.html?lang=en', { storage });
	await page.waitForSelector('.cb-nav-head');
	await page.focus('.cb-nav-head');
	await page.keyboard.press('Enter');
	assert.equal(await page.evaluate(() => document.activeElement.closest('.cb-fly') !== null), true, 'focus moved into the flyout');
	await page.keyboard.press('Escape');
	assert.equal(await page.evaluate(() => document.activeElement.classList.contains('cb-nav-head')), true);
	assert.equal(await page.$eval('.cb-fly', (f) => f.classList.contains('show')), false);
	await context.close();

	({ page, context } = await open('/src/preview/index.html?lang=en', { storage, touch: true }));
	await page.waitForSelector('.cb-nav-head');
	const before = page.url();
	await page.tap('.cb-nav-head');
	assert.equal(await page.$eval('.cb-fly', (f) => f.classList.contains('show')), true, 'tap shows the sub-menu');
	assert.equal(page.url(), before, 'tap does not navigate');
	await page.tap('.cb-hero');
	assert.equal(await page.$eval('.cb-fly', (f) => f.classList.contains('show')), false, 'tapping elsewhere closes it');
	await context.close();
});

test('phone drawer traps the page behind it and restores focus', async () => {
	const { page, context } = await open('/src/preview/index.html?lang=en', { width: 390, height: 844 });
	await page.waitForSelector('.cb-nav a');
	assert.equal(await page.$eval('#cb-sidebar', (e) => e.hasAttribute('inert')), true);
	await page.click('#cb-burger');
	assert.equal(await page.getAttribute('#cb-burger', 'aria-expanded'), 'true');
	assert.equal(await page.$eval('.cb-main', (e) => e.hasAttribute('inert')), true);
	assert.equal(await page.evaluate(() => document.activeElement.closest('#cb-sidebar') !== null), true);
	await page.keyboard.press('Escape');
	assert.equal(await page.evaluate(() => document.activeElement.id), 'cb-burger');
	assert.equal(await page.$eval('.cb-main', (e) => e.hasAttribute('inert')), false);
	await context.close();
});

async function styleSnapshot(url, width) {
	const { page, context, errors } = await open(url, { width, height: 900 });
	if (url.includes('index.html')) await dashboardReady(page);
	else await page.waitForSelector('.cb-login-card');
	await page.waitForTimeout(300);
	const props = ['display', 'position', 'color', 'background-color', 'background-image', 'font-size', 'font-weight', 'line-height',
		'padding-top', 'padding-left', 'margin-top', 'margin-left', 'border-top-width', 'border-top-color', 'border-top-left-radius',
		'gap', 'opacity', 'visibility', 'box-shadow', 'backdrop-filter', 'grid-template-columns', 'flex-direction', 'transform', 'text-decoration-line'];
	const snapshot = await page.evaluate((list) => [...document.querySelectorAll('body *:not(svg *)')]
		.filter((el) => !el.closest('.cb-chart, .cb-spark, .cb-ring'))
		.map((el) => { const cs = getComputedStyle(el); return el.tagName + '.' + el.className + ' ' + list.map((p) => cs.getPropertyValue(p)).join('|'); }), props);
	await context.close();
	return { snapshot, errors };
}

for (const [name, url, width] of [['overview', 'preview/index.html?lang=en', 1440], ['overview phone', 'preview/index.html?lang=en', 390], ['login', 'preview/login.html?lang=en', 1280]]) {
	test(`minified build computes the same styles: ${name}`, async () => {
		const src = await styleSnapshot('/src/' + url, width);
		const min = await styleSnapshot('/min/' + url, width);
		assert.deepEqual(min.errors, []);
		assert.equal(min.snapshot.length, src.snapshot.length);
		const diff = src.snapshot.map((line, i) => line === min.snapshot[i] ? null : line + '\n  ≠ ' + min.snapshot[i]).filter(Boolean);
		assert.deepEqual(diff.slice(0, 5), []);
	});
}
