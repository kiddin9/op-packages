'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { environment, loadModule, backend, renderLoadedPage } = require('./helpers/runtime');

const mac = 'AA:BB:CC:11:22:33';
const saved = { '.type': 'device', '.name': 'saved', mac, name: 'TV' };
function context() {
    const mocks = backend([saved]);
    const env = environment(mocks), modules = new Map();
    return Object.assign({ env, load: name => loadModule(name, env, modules) }, mocks);
}
function runTimer(env, delay) {
    const timer = Array.from(env.timeouts).find(([, value]) => value.delay === delay);
    assert.ok(timer, 'expected scheduled timer');
    env.timeouts.delete(timer[0]);
    return timer[1].callback();
}

test('reopening uses a snapshot immediately and refreshes device data after rendering', async () => {
    const ctx = context(), page = ctx.load('view.device-manager.devices');
    const first = await page.load();
    assert.equal(first.cached, false);
    const firstNode = page.render(first);
    assert.match(firstNode.querySelector('#device_manager_tbody').textContent, /Loading list/);
    await runTimer(ctx.env, 0);
    const calls = ctx.state.calls.length;
    ctx.state.saved[0].name = 'Updated outside LuCI';
    const cached = await page.load();
    assert.equal(cached.cached, true);
    assert.equal(ctx.state.calls.length, calls);
    const node = page.render(cached);
    assert.equal(page.devices[0].customName, 'TV');
    assert.equal(node.querySelector('#dm-cache-status').textContent, '');
    assert.equal(node.querySelector('#dm-cache-status').style.display, 'none');
    assert.equal(ctx.state.calls.length, calls);
    await runTimer(ctx.env, 0);
    assert.equal(page.devices[0].customName, 'Updated outside LuCI');
    assert.equal(node.querySelector('#dm-cache-status').style.display, 'none');
    assert.ok(ctx.state.calls.length > calls);
});

test('cache expires after five minutes and rejects future timestamps and malformed entries', async () => {
    const ctx = context();
    let now = 1000000;
    ctx.env.Date = class extends Date { static now() { return now; } };
    const service = ctx.load('device-manager.service'), cache = ctx.load('device-manager.snapshot-cache');
    await service.load();
    now += 299999;
    assert.ok(await cache.load());
    now += 1;
    assert.equal(await cache.load(), null);
    now = 999999;
    assert.equal(await cache.load(), null);
    for (const raw of ['{broken', '{}', '[]', JSON.stringify({ time: now, snapshot: {} })]) {
        ctx.env.window.sessionStorage.getItem = () => raw;
        assert.equal(await cache.load(), null);
    }
});

test('browser storage failure falls back to live loading and never breaks editing', async () => {
    const ctx = context();
    ctx.env.window.sessionStorage = {
        getItem() { throw Error('storage blocked'); },
        setItem() { throw Error('storage full'); },
        removeItem() { throw Error('storage blocked'); }
    };
    const service = ctx.load('device-manager.service');
    assert.equal((await service.loadCached()).cached, false);
    await service.saveDevice(mac, 'Changed', '', 'ungrouped');
    assert.equal(ctx.state.saved[0].name, 'Changed');
});

test('snapshots are isolated between LuCI sessions and read/write permissions', async () => {
    const ctx = context(), service = ctx.load('device-manager.service'), cache = ctx.load('device-manager.snapshot-cache');
    await service.load();
    assert.ok(await cache.load());
    ctx.state.session = 'another-session';
    assert.equal(await cache.load(), null);
    ctx.state.session = 'test-session';
    ctx.env.L.hasViewPermission = () => false;
    assert.equal(await cache.load(), null);
});

test('manual refresh reads live data and edits or scans invalidate the earlier snapshot', async () => {
    const ctx = context(), service = ctx.load('device-manager.service'), cache = ctx.load('device-manager.snapshot-cache');
    await service.load();
    ctx.state.saved[0].name = 'External change';
    assert.equal((await service.load()).devices[0].name, 'External change');
    await service.saveDevice(mac, 'New edit', '', 'ungrouped');
    assert.equal(await cache.load(), null);
    await service.load();
    await service.scanDevices();
    assert.equal(await cache.load(), null);
});

test('failed background refresh retains cached data and clearly labels it', async () => {
    const ctx = context(), page = ctx.load('view.device-manager.devices');
    await renderLoadedPage(page);
    const node = page.render(await page.load());
    ctx.uci.load = () => Promise.reject(Error('router unavailable'));
    await runTimer(ctx.env, 0);
    assert.equal(page.devices[0].customName, 'TV');
    assert.match(node.querySelector('#dm-cache-status').textContent, /cached.*retry/);
    assert.match(ctx.env.notifications[0].content.textContent, /router unavailable/);
    runTimer(ctx.env, 12000);
    assert.equal(ctx.env.notifications[0].node.removed, true);
});

test('source errors close manually or after twelve seconds and stay closed during filtering', async () => {
    const ctx = context(), page = ctx.load('view.device-manager.devices');
    ctx.replies['luci-rpc.getHostHints'] = Error('hints unavailable');
    const node = await renderLoadedPage(page), warning = node.querySelector('#dm-source-warning');
    assert.equal(warning.style.display, 'flex');
    assert.equal(page.devices[0].status, 'unknown');
    await warning.querySelector('button').click();
    assert.equal(warning.style.display, 'none');
    page.filterText = 'tv'; page.updateView();
    assert.equal(warning.style.display, 'none');
    assert.ok(!Array.from(ctx.env.timeouts.values()).some(timer => timer.delay === 12000));
    page.sourceErrors = ['new failure']; page.updateView();
    assert.equal(warning.style.display, 'flex');
    runTimer(ctx.env, 12000);
    assert.equal(warning.style.display, 'none');
    assert.equal(page.devices[0].status, 'unknown');
    assert.deepEqual(page.sourceErrors, ['new failure']);
    page.updateView();
    assert.equal(warning.style.display, 'none');
    page.sourceErrors = []; page.updateView();
    page.sourceErrors = ['new failure']; page.updateView();
    assert.equal(warning.style.display, 'flex');
});

test('warning messages render untrusted errors as text', () => {
    const ctx = context(), feedback = ctx.load('device-manager.feedback');
    const warning = feedback.createWarning();
    warning.update(['<img src=x onerror=alert(1)>']);
    assert.ok(warning.node.textContent.includes('<img src=x onerror=alert(1)>'));
    assert.deepEqual(ctx.env.htmlSinks, []);
    warning.destroy();
    assert.equal(ctx.env.timeouts.size, 0);
});
