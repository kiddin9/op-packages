'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { environment, loadModule, backend, renderLoadedPage } = require('./helpers/runtime');

const mac = 'AA:BB:CC:11:22:33', other = 'AA:BB:CC:44:55:66';
function context() {
    const mocks = backend(), env = environment(mocks), cache = new Map();
    mocks.replies['luci-rpc.getHostHints'] = { [mac]: { ipaddrs: ['192.168.1.20'] } };
    mocks.replies['luci.device-manager.get_online_status'] = { ok: true, neighbors: [{ mac, ip: '192.168.1.20', state: 'STALE' }] };
    return Object.assign({ env, load: name => loadModule(name, env, cache) }, mocks);
}
function runTimer(env) {
    const timer = Array.from(env.timeouts).find(([, value]) => value.delay === 0);
    assert.ok(timer);
    env.timeouts.delete(timer[0]);
    return timer[1].callback();
}

test('unknown devices are checked after rendering and a Ping reply updates online rows and tab counts', async () => {
    const ctx = context(), page = ctx.load('view.device-manager.devices');
    const node = await renderLoadedPage(page);
    assert.equal(page.devices[0].status, 'unknown');
    assert.equal(ctx.state.calls.filter(call => call.key.endsWith('.ping_device')).length, 0);
    await runTimer(ctx.env);
    assert.equal(page.devices[0].status, 'online');
    assert.equal(page.devices[0].statusDetail, 'Online · Ping replied');
    assert.equal(node.querySelector('#dm-tabs-container').children[0].textContent, 'Online devices1');
    assert.equal(node.querySelectorAll('.dm-status-dot-online').length, 1);
    assert.equal(ctx.state.commits, 0);
});

test('unanswered, failed and malformed Pings leave unknown devices unchanged', async () => {
    for (const reply of [
        { ok: true, reachable: false, ip: '192.168.1.20', output: 'timeout' },
        { ok: false, error: 'Another device is being probed. Please retry.' },
        Error('RPC unavailable'), { ok: true }
    ]) {
        const ctx = context(), page = ctx.load('view.device-manager.devices');
        ctx.replies['luci.device-manager.ping_device'] = reply;
        await renderLoadedPage(page);
        await runTimer(ctx.env);
        assert.equal(page.devices[0].status, 'unknown');
        assert.equal(ctx.env.notifications.length, 0);
    }
});

test('automatic detection skips online, offline and addressless devices and supports IPv6', async () => {
    const env = environment(), check = loadModule('device-manager.online-check', env), checked = [];
    await check.run([
        { mac: 'online', status: 'online', ipv4: '192.168.1.1' },
        { mac: 'offline', status: 'offline', ipv4: '192.168.1.2' },
        { mac: 'addressless', status: 'unknown' },
        { mac: 'ipv6', status: 'unknown', ipv6: 'fd00::20' }
    ], device => { checked.push(device.mac); return Promise.resolve(); }, () => true);
    assert.deepEqual(checked, ['ipv6']);
});

test('successful manual detail Ping also confirms an unknown device', async () => {
    const ctx = context(), page = ctx.load('view.device-manager.devices');
    await renderLoadedPage(page);
    await page.showDetailModal(page.devices[0]);
    assert.equal(page.devices[0].status, 'online');
    assert.equal(ctx.env.ui.modal.querySelector('.dm-ping-status').textContent, 'Online · Ping replied');
    assert.equal(ctx.env.ui.modal.querySelector('.dm-dialog-status').textContent, 'Online');
});

test('late Ping replies cannot promote a device from a newer snapshot and old batches stop', async () => {
    const ctx = context(), page = ctx.load('view.device-manager.devices'), service = ctx.load('device-manager.service');
    await renderLoadedPage(page);
    page.devices.push(Object.assign({}, page.devices[0], { mac: other }));
    const old = page.devices[0];
    let release, started;
    const signal = new Promise(resolve => { started = resolve; });
    service.pingDevice = () => { started(); return new Promise(resolve => { release = resolve; }); };
    const pending = page.confirmUnknownDevices();
    await signal;
    page.acceptData(await service.load());
    release({ reachable: true });
    await pending;
    assert.equal(old.status, 'unknown');
    assert.equal(page.devices[0].status, 'unknown');
});

test('cached lists wait for live refresh before probing and old Ping success is not reused', async () => {
    const ctx = context(), page = ctx.load('view.device-manager.devices');
    await renderLoadedPage(page);
    const cached = await page.load();
    assert.equal(cached.cached, true);
    page.render(cached);
    await page.confirmUnknownDevices();
    assert.equal(ctx.state.calls.filter(call => call.key.endsWith('.ping_device')).length, 0);
    await runTimer(ctx.env);
    await runTimer(ctx.env);
    assert.equal(page.devices[0].status, 'online');
    ctx.replies['luci.device-manager.ping_device'] = { ok: true, reachable: false, ip: '192.168.1.20', output: 'timeout' };
    await page.refresh();
    assert.equal(page.devices[0].status, 'unknown');
    await runTimer(ctx.env);
    assert.equal(page.devices[0].status, 'unknown');
});

test('detection uses one request at a time, caps each pass and continues with remaining devices', async () => {
    const env = environment(), check = loadModule('device-manager.online-check', env), checked = [];
    const devices = Array.from({ length: 40 }, (_, index) => ({ mac: index, status: 'unknown', ipv4: '192.168.1.20' }));
    let active = 0, maximum = 0;
    const ping = async device => {
        active++; maximum = Math.max(active, maximum);
        await Promise.resolve();
        active--; checked.push(device.mac);
    };
    await Promise.all([check.run(devices, ping, () => true), check.run(devices, ping, () => true)]);
    assert.equal(maximum, 1);
    assert.deepEqual(checked, Array.from({ length: 32 }, (_, index) => index));
});

test('time budget stops slow probes and a cancelled snapshot starts no further requests', async () => {
    const env = environment();
    let now = 0, current = true;
    env.Date = class extends Date { static now() { return now; } };
    const check = loadModule('device-manager.online-check', env), checked = [];
    const devices = Array.from({ length: 20 }, (_, index) => ({ mac: index, status: 'unknown', ipv4: '192.168.1.20' }));
    await check.run(devices, async device => { checked.push(device.mac); now += 3000; }, () => current);
    assert.deepEqual(checked, [0, 1, 2, 3]);
    await check.run(devices, async device => { checked.push(device.mac); current = false; }, () => current);
    assert.deepEqual(checked, [0, 1, 2, 3, 4]);
});
