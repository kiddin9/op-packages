'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { environment, loadModule, backend, renderLoadedPage } = require('./helpers/runtime');
const mac = 'AA:BB:CC:11:22:33';
const attack = '<img src=x onerror="window.auditFlag=1">';

async function context() {
    const mocks = backend([
        { '.type': 'group', '.name': 'home', name: 'Home' },
        { '.type': 'device', '.name': 'saved', mac, name: 'Living room', remark: attack, group: 'home', type: 'tv' }
    ]);
    mocks.replies['luci-rpc.getHostHints'] = { [mac]: {
        name: 'television', ipaddrs: ['192.168.1.20', '192.168.1.21'],
        ip6addrs: ['fd00::20', 'fe80::20']
    } };
    mocks.replies['luci.device-manager.get_online_status'] = { ok: true, neighbors: [
        { mac, ip: '192.168.1.20', dev: 'br-lan', state: 'REACHABLE' },
        { mac, ip: 'fd00::20', dev: 'br-lan', state: 'STALE' }
    ] };
    const env = environment(mocks);
    const page = loadModule('view.device-manager.devices', env);
    const node = await renderLoadedPage(page);
    return Object.assign({ env, page, node, dev: page.devices[0] }, mocks);
}

test('details retain all known addresses and evidence and open with exactly one independent Ping', async () => {
    const ctx = await context();
    const scans = ctx.state.calls.filter(call => call.key === 'luci.device-manager.get_online_status').length;
    assert.deepEqual(ctx.dev.ipv4Addresses, ['192.168.1.20', '192.168.1.21']);
    assert.deepEqual(ctx.dev.ipv6Addresses, ['fd00::20', 'fe80::20']);
    assert.deepEqual(ctx.dev.interfaces, ['br-lan']);
    await ctx.node.querySelector('.dm-action-detail').click();
    const modal = ctx.env.ui.modal;
    assert.equal(modal.attrs.title, 'Device details');
    for (const value of ['Living room', 'television', '192.168.1.20', '192.168.1.21', 'fd00::20', 'fe80::20', mac, 'Home', attack, 'br-lan', 'REACHABLE', 'STALE']) {
        assert.ok(modal.textContent.includes(value), value);
    }
    assert.equal(modal.querySelector('.dm-ping-status').textContent, 'Online · Ping replied');
    const calls = ctx.state.calls.filter(call => call.key === 'luci.device-manager.ping_device');
    assert.equal(calls.length, 1); assert.deepEqual(calls[0].args, [mac]);
    assert.equal(ctx.state.calls.filter(call => call.key === 'luci.device-manager.get_online_status').length, scans);
    assert.equal(ctx.state.commits, 0); assert.deepEqual(ctx.env.htmlSinks, []);
});

test('unanswered Ping is distinct from offline and retry does not overlap an in-flight request', async () => {
    const ctx = await context();
    let release;
    ctx.page.handlePingDevice = () => new Promise(resolve => { release = resolve; });
    const pending = ctx.page.showDetailModal(ctx.dev);
    await Promise.resolve();
    const modal = ctx.env.ui.modal;
    const button = modal.querySelectorAll('button').find(node => node.textContent === 'Ping again');
    assert.equal(button.disabled, true);
    await button.click();
    release({ reachable: false, ip: '192.168.1.20', output: attack });
    await pending;
    assert.equal(modal.querySelector('.dm-ping-status').textContent, 'No Ping reply');
    assert.ok(modal.textContent.includes('does not confirm it is offline'));
    assert.equal(modal.querySelector('pre').textContent, attack);
    assert.equal(ctx.dev.status, 'online'); assert.equal(button.disabled, false);
    assert.deepEqual(ctx.env.htmlSinks, []);
    ctx.page.handlePingDevice = () => Promise.resolve({ reachable: true, ip: '192.168.1.20', output: 'reply' });
    await button.click();
    assert.equal(modal.querySelector('.dm-ping-status').textContent, 'Online · Ping replied');
});

test('missing addresses and RPC failures remain visible and restore the retry control', async () => {
    const ctx = await context();
    for (const response of [{ ok: false, error: 'No known IP address for this device' }, new Error('RPC unavailable'), { ok: true }]) {
        ctx.replies['luci.device-manager.ping_device'] = response;
        await ctx.page.showDetailModal(ctx.dev);
        const modal = ctx.env.ui.modal;
        assert.equal(modal.querySelector('.dm-ping-status').textContent, 'Probe unavailable');
        assert.equal(modal.querySelectorAll('button').find(node => node.textContent === 'Ping again').disabled, false);
        assert.equal(ctx.dev.status, 'online');
    }
});

test('late probe completion updates only its own content and never replaces a newer dialog', async () => {
    const ctx = await context();
    let release;
    ctx.page.handlePingDevice = () => new Promise(resolve => { release = resolve; });
    const pending = ctx.page.showDetailModal(ctx.dev);
    await Promise.resolve();
    ctx.page.showEditModal(ctx.dev);
    const editModal = ctx.env.ui.modal;
    release({ reachable: true, ip: '192.168.1.20', output: 'reply' });
    await pending;
    assert.equal(ctx.env.ui.modal, editModal); assert.equal(editModal.attrs.title, 'Edit device');
});

test('read-only sessions can view details and probe without getting editing or clearing controls', async () => {
    const ctx = await context();
    ctx.env.L.hasViewPermission = () => false;
    ctx.page.readonly = true;
    ctx.page.updateView();
    assert.equal(ctx.node.querySelector('.dm-action-edit'), null);
    await ctx.node.querySelector('.dm-action-detail').click();
    assert.equal(ctx.env.ui.modal.attrs.title, 'Device details');
    assert.ok(!ctx.env.ui.modal.textContent.includes('Clear record'));
    assert.equal(ctx.state.commits, 0);
});

test('clear record removes metadata after confirmation while discovered devices and groups remain', async () => {
    const ctx = await context();
    ctx.page.showEditModal(ctx.dev);
    const clear = ctx.env.ui.modal.querySelectorAll('button').find(node => node.textContent === 'Clear record');
    await clear.click();
    assert.equal(ctx.state.saved.length, 2, 'opening confirmation must not clear anything');
    await ctx.env.ui.modal.querySelectorAll('button').find(node => node.textContent === 'Confirm clear').click();
    assert.equal(ctx.state.saved.length, 1); assert.equal(ctx.state.saved[0]['.type'], 'group');
    const dev = ctx.page.devices.find(device => device.mac === mac);
    assert.equal(dev.isSaved, false); assert.equal(dev.customName, ''); assert.equal(dev.remark, '');
    assert.equal(dev.group, 'ungrouped'); assert.equal(dev.hostname, 'television'); assert.equal(dev.customType, undefined);
});
