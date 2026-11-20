'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { chromium } = require('playwright');
const { transform } = require('esbuild');

const ROOT = path.resolve(__dirname, '../..');
const SHOTS = path.join(ROOT, '.cache/screenshots');
const fixture = (name) => fs.readFileSync(path.join(ROOT, 'tests/fixtures/luci-realtime', name), 'utf8');
let server, base, browser;

test.before(async () => {
	fs.mkdirSync(SHOTS, { recursive: true });
	const source = fs.readFileSync(path.join(ROOT, 'htdocs/luci-static/carbon/carbon.js'), 'utf8');
	const css = fs.readFileSync(path.join(ROOT, 'htdocs/luci-static/carbon/carbon.css'), 'utf8');
	const minified = (await transform(source, { minify: true, loader: 'js' })).code;
	server = http.createServer((req, res) => {
		const url = new URL(req.url, 'http://localhost');
		if (url.pathname.endsWith('.js')) {
			res.setHeader('content-type', 'text/javascript');
			res.end(url.pathname === '/min.js' ? minified : source);
		}
		else {
			res.setHeader('content-type', 'text/html');
			res.end(`<!doctype html><html lang="en"><head><style>${css}</style>
				<script src="/${url.searchParams.has('min') ? 'min' : 'source'}.js"></script></head>
				<body data-page="${url.searchParams.has('outside') ? 'admin-status-overview' : 'admin-status-realtime-load'}"><div class="cb-app">
				<aside class="cb-sidebar"><button id="cb-collapse"></button></aside>
				<main class="cb-main"><div id="maincontent" class="cb-content"><div id="view"></div></div></main>
				</div><script>Carbon.initShell();</script></body></html>`);
		}
	});
	await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
	base = 'http://127.0.0.1:' + server.address().port;
	browser = await chromium.launch({ executablePath: process.env.CARBON_TEST_BROWSER || undefined });
});

test.after(async () => {
	if (browser) await browser.close();
	if (server) await new Promise((resolve) => server.close(resolve));
});

async function mount(page, kind, count = 1) {
	await page.evaluate(({ source, svg, kind, count }) => {
		const ticks = [];
		let timestamp = 1000;
		window.rpcCalls = 0;
		const rpc = { declare: (spec) => () => {
			if (spec.method !== 'getRealtimeStats') return Promise.resolve([]);
			window.rpcCalls++;
			const start = timestamp;
			timestamp += 60;
			return Promise.resolve(Array.from({ length: 60 }, (_, i) =>
				[start + i, 10000 + i * 100, 20000 + i * 80, 30 + i % 5]));
		} };
		const L = { bind: (fn, ctx) => fn.bind(ctx), resolveDefault: (p, value) => Promise.resolve(p).catch(() => value) };
		const view = new Function('view', 'poll', 'request', 'rpc', 'L', source)(
			{ extend: (v) => v }, { add: (fn) => ticks.push(fn) }, {}, rpc, L);
		// The connection table is independent of the SVG plot under test.
		view.updateConntrack = () => {};
		const ids = { load: ['load01', 'load05', 'load15'], bandwidth: ['rx', 'tx'], connections: ['tcp', 'udp', 'other'] }[kind];
		window.graphs = [];
		for (let i = 0; i < count; i++) {
			const container = document.createElement('div');
			container.style.cssText = 'width:100%;height:300px;border:1px solid #000;background:#fff';
			container.innerHTML = svg.slice(svg.indexOf('<svg'));
			document.querySelector('#view').appendChild(container);
			const lines = ids.map((line) => ({ line, counter: kind === 'bandwidth' }));
			if (kind === 'bandwidth') view.updateGraph('eth' + i, container, lines);
			else view.updateGraph(container, lines);
			graphs.push(container);
		}
		view.pollData();
		window.tick = () => Promise.all(ticks.map((fn) => fn()));
	}, { source: fixture(kind + '.js'), svg: fixture(kind + '.svg'), kind, count });
	await page.evaluate(() => tick());
}

async function settle(page) {
	await page.waitForFunction(() => !document.querySelector('.cb-main').getAnimations().length);
	await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

async function geometry(page, index = 0) {
	return page.evaluate((index) => {
		const svg = graphs[index].firstElementChild;
		const edge = svg.getBoundingClientRect().right;
		const lines = [...svg.querySelectorAll('polyline')];
		const end = (line) => {
			const p = line.points.getItem(line.points.numberOfItems - 1);
			return new DOMPoint(p.x, p.y).matrixTransform(line.getScreenCTM()).x;
		};
		return {
			gaps: lines.map((line) => edge - end(line)),
			points: lines.map((line) => line.getAttribute('points')),
			labels: [...svg.querySelectorAll('text')].map((el) => {
				const m = el.getScreenCTM();
				return { scaleX: m.a, scaleY: m.d };
			}),
			grid: [...svg.querySelectorAll('line')].filter((el) => el.getAttribute('x1') === el.getAttribute('x2')).map((el) => {
				const p = new DOMPoint(el.x1.baseVal.value, 0).matrixTransform(el.getScreenCTM());
				return (edge - p.x) / svg.clientWidth;
			})
		};
	}, index);
}

function fillsPlot(result) {
	for (const gap of result.gaps) assert(Math.abs(gap) < 1, 'curve must reach the right edge; gap=' + gap);
	for (const label of result.labels) assert.deepEqual(label, { scaleX: 1, scaleY: 1 }, 'labels must not stretch');
}

for (const kind of ['load', 'bandwidth', 'connections']) {
	for (const min of [false, true]) {
		test(`${kind} fills the plot after sidebar and viewport changes (${min ? 'minified' : 'source'})`, async () => {
			const page = await browser.newPage({ viewport: { width: 1280, height: 850 } });
			const errors = [];
			page.on('pageerror', (error) => errors.push(error.message));
			try {
				await page.goto(base + (min ? '/?min' : '/'));
				await mount(page, kind);
				await settle(page);
				const initial = await geometry(page);
				fillsPlot(initial);
				const calls = await page.evaluate(() => rpcCalls);
				await page.locator('#cb-collapse').click();
				await settle(page);
				const collapsed = await geometry(page);
				fillsPlot(collapsed);
				if (kind === 'load' && !min) await page.screenshot({ path: path.join(SHOTS, 'realtime-load-collapsed.png') });
				assert.deepEqual(collapsed.points, initial.points, 'resizing preserves samples');
				initial.grid.forEach((v, i) => assert(Math.abs(v - collapsed.grid[i]) < 0.001, 'time grid stays aligned'));
				assert.equal(await page.evaluate(() => rpcCalls), calls, 'resizing does not fetch new data');
				await page.evaluate(() => tick());
				await settle(page);
				fillsPlot(await geometry(page));
				assert.notDeepEqual((await geometry(page)).points, initial.points, 'native polling still updates samples');
				await page.locator('#cb-collapse').click();
				await settle(page);
				fillsPlot(await geometry(page));
				for (const width of [1600, 1100, 390, 1280]) {
					await page.setViewportSize({ width, height: 850 });
					await settle(page);
					fillsPlot(await geometry(page));
					if (kind === 'load' && !min && width === 390) await page.screenshot({ path: path.join(SHOTS, 'realtime-load-mobile.png') });
				}
				assert.deepEqual(errors, []);
			}
			finally { await page.close(); }
		});
	}
}

test('hidden interface charts resize when revealed; unrelated SVGs are untouched', async () => {
	const page = await browser.newPage({ viewport: { width: 1280, height: 850 } });
	try {
		await page.goto(base);
		await mount(page, 'bandwidth', 2);
		await page.evaluate(() => {
			graphs[1].hidden = true;
			document.querySelector('#view').insertAdjacentHTML('beforeend', '<svg id="unrelated" viewBox="0 0 100 100"><polyline points="0,100 100,0 100,100"/></svg>');
			const modern = graphs[0].firstElementChild.cloneNode(true);
			modern.id = 'modern';
			modern.setAttribute('viewBox', '0 0 934 298');
			modern.querySelectorAll('[transform]').forEach((el) => el.removeAttribute('transform'));
			document.querySelector('#view').appendChild(modern);
		});
		await page.locator('#cb-collapse').click();
		await settle(page);
		await page.evaluate(() => { graphs[1].hidden = false; });
		await settle(page);
		fillsPlot(await geometry(page, 1));
		assert.equal(await page.locator('#unrelated polyline').getAttribute('transform'), null);
		assert.equal(await page.locator('#modern polyline').first().getAttribute('transform'), null);
	}
	finally { await page.close(); }
});

test('legacy resize fallback handles sidebar changes with and without motion', async () => {
	const page = await browser.newPage({ viewport: { width: 1280, height: 850 } });
	try {
		await page.addInitScript(() => { window.ResizeObserver = undefined; });
		await page.goto(base);
		await mount(page, 'load');
		for (const reducedMotion of ['no-preference', 'reduce']) {
			await page.emulateMedia({ reducedMotion });
			await page.locator('#cb-collapse').click();
			await settle(page);
			fillsPlot(await geometry(page));
		}
		const resized = page.evaluate(() => new Promise((resolve) => window.addEventListener('resize', resolve, { once: true })));
		await page.setViewportSize({ width: 1600, height: 850 });
		await resized;
		await settle(page);
		fillsPlot(await geometry(page));
	}
	finally { await page.close(); }
});

test('the adapter does not modify matching SVGs outside realtime pages', async () => {
	const page = await browser.newPage();
	try {
		await page.goto(base + '/?outside');
		await mount(page, 'load');
		await page.locator('#cb-collapse').click();
		await settle(page);
		assert.equal(await page.locator('#load01').getAttribute('transform'), null);
	}
	finally { await page.close(); }
});
