'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { environment, loadModule, backend } = require('./helpers/runtime');
const mac = 'AA:BB:CC:11:22:33';
const snapshot = {
    groups: [{ '.type': 'group', '.name': 'home', name: 'Home' }],
    devices: [{ '.type': 'device', '.name': 'tv', mac, name: 'TV', group: 'home' }],
    hints: { [mac]: { ipaddrs: ['192.168.1.20'] } },
    neighbors: { neighbors: [{ mac, ip: '192.168.1.20', state: 'REACHABLE' }] },
    errors: [], discoveryComplete: true
};
function context() {
    const mocks = backend(), env = environment(mocks), cache = new Map();
    return { env, mocks, load: name => loadModule(name, env, cache) };
}
function runTimer(env) {
    const [id, timer] = Array.from(env.timeouts).find(([, value]) => value.delay === 0);
    env.timeouts.delete(id);
    return timer.callback();
}

test('a cache miss renders the full page before discovery and only the list waits for slow data', async () => {
    const ctx = context(), service = ctx.load('device-manager.service');
    let release, loads = 0;
    service.load = () => { loads++; return new Promise(resolve => { release = resolve; }); };
    ctx.env.window.localStorage.getItem = () => JSON.stringify({ tab: 'all', group: 'home', maskInfo: true });
    const page = ctx.load('view.device-manager.devices');
    const initial = await page.load();
    assert.equal(initial.snapshot, null);
    assert.equal(loads, 0);
    assert.equal(ctx.mocks.state.calls.length, 0);
    const node = page.render(initial), list = node.querySelector('#device_manager_tbody');
    assert.ok(node.textContent.includes('LAN Device Management'));
    assert.ok(node.querySelector('#dm-search-input'));
    assert.equal(node.querySelectorAll('th').length, 8);
    assert.match(list.textContent, /Loading list/);
    assert.ok(!list.textContent.includes('No online devices'));
    assert.ok(node.querySelectorAll('.dm-requires-data').every(button => button.disabled));
    const pending = runTimer(ctx.env);
    assert.equal(loads, 1);
    assert.equal(page.refresh(), pending);
    page.filterText = 'tv'; page.updateView();
    assert.match(list.textContent, /Loading list/);
    release(snapshot); await pending;
    assert.ok(!list.textContent.includes('Loading list'));
    assert.ok(list.textContent.includes('TV'));
    assert.equal(page.activeGroup, 'home');
    assert.equal(page.maskInfo, true);
    assert.ok(node.querySelectorAll('.dm-requires-data').every(button => !button.disabled));
    assert.equal(node.querySelector('#dm-cache-status').style.display, 'none');
});

test('an initial loading failure becomes a retry row and a retry replaces it with the device list', async () => {
    const ctx = context(), service = ctx.load('device-manager.service');
    service.load = () => Promise.reject(Error('router unavailable'));
    const page = ctx.load('view.device-manager.devices'), node = page.render(await page.load());
    await runTimer(ctx.env);
    const list = node.querySelector('#device_manager_tbody');
    assert.match(list.textContent, /Could not load the device list/);
    const retry = list.querySelector('button');
    assert.equal(retry.textContent, 'Retry');
    service.load = () => Promise.resolve(snapshot);
    await retry.click();
    assert.equal(page.initialLoading, false);
    assert.equal(page.loadFailed, false);
    assert.ok(list.textContent.includes('TV'));
    assert.ok(!list.textContent.includes('Retry'));
});

test('an expired snapshot shows the shell without starting or awaiting live discovery', async () => {
    const ctx = context();
    let now = 1000000;
    ctx.env.Date = class extends Date { static now() { return now; } };
    await ctx.load('device-manager.snapshot-cache').save(snapshot);
    now += 300000;
    const page = ctx.load('view.device-manager.devices'), initial = await page.load();
    assert.equal(initial.snapshot, null);
    assert.equal(initial.cached, false);
    const node = page.render(initial);
    assert.match(node.querySelector('#device_manager_tbody').textContent, /Loading list/);
    assert.equal(ctx.mocks.state.calls.length, 0);
});

test('an empty cached online list stays loading until live discovery and Ping both finish', async () => {
    for (const reachable of [true, false]) {
        const ctx = context(), service = ctx.load('device-manager.service');
        await ctx.load('device-manager.snapshot-cache').save({ groups: [], devices: [], errors: [], discoveryComplete: true });
        let readDone, pingDone;
        service.load = () => new Promise(resolve => { readDone = resolve; });
        service.pingDevice = () => new Promise(resolve => { pingDone = resolve; });
        const page = ctx.load('view.device-manager.devices'), node = page.render(await page.load());
        const list = node.querySelector('#device_manager_tbody');
        assert.match(list.textContent, /Loading list/);
        assert.ok(!list.textContent.includes('No online devices'));
        const reading = runTimer(ctx.env);
        readDone(Object.assign({}, snapshot, { neighbors: { neighbors: [{ mac, ip: '192.168.1.20', state: 'STALE' }] } }));
        await reading;
        assert.match(list.textContent, /Loading list/);
        const checking = runTimer(ctx.env);
        await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
        assert.match(list.textContent, /Loading list/);
        pingDone({ reachable }); await checking;
        assert.ok(!list.textContent.includes('Loading list'));
        assert.ok(list.textContent.includes(reachable ? 'TV' : 'No online devices'));
    }
});

test('a completed empty discovery shows no online devices after its loading phase', async () => {
    const ctx = context(), service = ctx.load('device-manager.service');
    service.load = () => Promise.resolve({ groups: [], devices: [], errors: [], discoveryComplete: true });
    const page = ctx.load('view.device-manager.devices'), node = page.render(await page.load());
    const list = node.querySelector('#device_manager_tbody');
    assert.match(list.textContent, /Loading list/);
    await runTimer(ctx.env);
    assert.equal(list.textContent, 'No online devices');
});
