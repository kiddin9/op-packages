'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { environment, loadModule, backend, renderLoadedPage } = require('./helpers/runtime');
const mac = 'AA:BB:CC:11:22:33', other = 'AA:BB:CC:44:55:66';
const model = loadModule('device-manager.model', environment());
const device = { '.type': 'device', '.name': 'dev_aabbcc112233', mac, name: 'TV', remark: 'Living room' };
const group = { '.type': 'group', '.name': 'home', name: 'Home' };
const data = overrides => Object.assign({ hints: {}, leases: {}, neighbors: { neighbors: [] }, wifi: [], arp: [], devices: [], discoveryComplete: true }, overrides);
const parse = input => model.parseDevices(data(input), model.parseGroups(input.groups || []));
function service(initial) {
    const mocks = backend(initial);
    const env = environment(mocks);
    return Object.assign({ env, service: loadModule('device-manager.service', env) }, mocks);
}

test('MAC normalization, stable section ID and control-character removal', () => {
    for (const value of ['aa:bb:cc:11:22:33', 'aa-bb-cc-11-22-33', 'aabbcc112233']) assert.equal(model.normalizeMac(value), mac);
    for (const value of [null, 123, 'not-a-mac', '00:00:00:00:00:00', 'FF:FF:FF:FF:FF:FF']) assert.equal(model.normalizeMac(value), null);
    assert.equal(model.getSectionId(mac), 'dev_aabbcc112233');
    assert.equal(model.sanitizeInput(' hi\nthere\x01 '), 'hi there');
});

test('empty group configuration remains empty', () => assert.deepEqual(model.parseGroups([]), []));
test('Wi-Fi-only, neighbor-only and ARP-only devices are discovered', () => {
    assert.equal(parse({ wifi: [mac] })[0].status, 'online');
    const neighbor = parse({ neighbors: { neighbors: [{ mac, ip: '192.168.1.10', state: 'REACHABLE' }] } });
    assert.equal(neighbor[0].status, 'online'); assert.equal(neighbor[0].ipv4, '192.168.1.10');
    assert.equal(parse({ arp: [{ mac, ip: '192.168.1.10', flags: '0x2' }] })[0].status, 'unknown');
});
test('multiple evidence sources deduplicate a MAC and preserve user metadata', () => {
    const result = parse({ hints: { [mac.toLowerCase()]: { name: 'hostname', ipaddrs: ['192.168.1.20'] } },
        wifi: [mac], devices: [Object.assign({}, device, { group: 'deleted' })] });
    assert.equal(result.length, 1); assert.equal(result[0].customName, 'TV');
    assert.equal(result[0].remark, 'Living room'); assert.equal(result[0].group, 'ungrouped');
});
test('active neighbor evidence outranks FAILED and STALE in every input order', () => {
    for (const active of ['REACHABLE', 'DELAY', 'PROBE']) {
        for (const states of [['FAILED', active], [active, 'FAILED'], ['STALE', active], [active, 'STALE']]) {
            assert.equal(parse({ neighbors: { neighbors: states.map(state => ({ mac, state })) } })[0].status, 'online');
        }
    }
});
test('FAILED neighbors without MAC are associated to a unique known IP', () => {
    const result = parse({ hints: { [mac]: { ipaddrs: ['192.168.1.20'] } },
        neighbors: { neighbors: [{ ip: '192.168.1.20', dev: 'br-lan', state: 'FAILED' }] } });
    assert.equal(result[0].status, 'offline');
});
test('ambiguous IP ownership never assigns a failure to either device', () => {
    const result = parse({ hints: { [mac]: { ipaddrs: ['192.168.1.20'] }, [other]: { ipaddrs: ['192.168.1.20'] } },
        neighbors: { neighbors: [{ ip: '192.168.1.20', state: 'FAILED' }] } });
    assert.ok(result.every(item => item.status === 'unknown'));
});
test('STALE, PERMANENT and unresolved discovery failures are unknown', () => {
    for (const state of ['STALE', 'PERMANENT', 'INCOMPLETE']) assert.equal(parse({ neighbors: { neighbors: [{ mac, state }] } })[0].status, 'unknown');
    assert.equal(parse({ devices: [device], discoveryComplete: false })[0].status, 'unknown');
    assert.equal(parse({ devices: [device] })[0].status, 'offline');
    assert.equal(parse({ devices: [device], discoveryComplete: false, wifi: [mac] })[0].status, 'online');
});
test('current active IP and DHCP leases take precedence over stale hints', () => {
    const result = parse({ hints: { [mac]: { ipaddrs: ['192.168.1.20'] } }, leases: { dhcp_leases: [{ macaddr: mac, ipaddr: '192.168.1.90' }] } });
    assert.equal(result[0].ipv4, '192.168.1.90');
    assert.equal(parse({ hints: { [mac]: { ipaddrs: ['192.168.1.20'] } }, neighbors: { neighbors: [{ mac, ip: '192.168.1.91', state: 'REACHABLE' }] } })[0].ipv4, '192.168.1.91');
});
test('IPv6 leases and all addresses participate in failed neighbor matching', () => {
    const result = parse({ leases: { dhcp6_leases: [{ macaddr: mac, ip6addrs: ['fd00::2/64', 'fd00::3'] }] },
        neighbors: { neighbors: [{ ip: 'fd00::3', state: 'FAILED' }] } });
    assert.equal(result[0].ipv6, 'fd00::2'); assert.equal(result[0].status, 'offline');
});
test('combined group and text filtering uses names, remarks and addresses', () => {
    const result = parse({ devices: [Object.assign({}, device, { group: 'home' })], groups: [group] });
    assert.ok(model.matchesDevice(result[0], model.parseGroups([group]), 'home', 'living'));
    assert.ok(model.matchesDevice(result[0], model.parseGroups([group]), 'home', 'home'));
    assert.equal(model.matchesDevice(result[0], [], 'ungrouped', ''), false);
});
test('legacy sections recover their MAC from the section ID', () => {
    assert.equal(parse({ devices: [{ '.name': 'dev_aabbcc112233', name: 'Legacy' }] })[0].mac, mac);
});

test('real service saves a MAC-only record and clearing metadata preserves it', async () => {
    const ctx = service([]);
    await ctx.service.saveDevice(mac, '', '', 'ungrouped');
    assert.equal(ctx.state.saved.length, 1); assert.equal(ctx.state.saved[0].mac, mac);
    await ctx.service.saveDevice(mac, 'TV', 'Room', 'ungrouped');
    await ctx.service.saveDevice(mac, '', '', 'ungrouped');
    assert.equal(ctx.state.saved.length, 1); assert.equal(ctx.state.saved[0].name, undefined);
});
test('group create, rename and delete preserve actual device name and remarks', async () => {
    const ctx = service([device]);
    await ctx.service.addGroup('Home');
    const created = ctx.state.saved.find(section => section['.type'] === 'group');
    await ctx.service.saveDevice(mac, 'TV', 'Living room', created['.name']);
    await ctx.service.renameGroup(created['.name'], 'Media');
    assert.equal(ctx.state.saved.find(section => section.mac === mac).group, created['.name']);
    await ctx.service.deleteGroup(created['.name']);
    assert.deepEqual(ctx.state.saved, [device]);
    assert.deepEqual((await ctx.service.load()).groups, []);
});
test('duplicate device sections are consolidated and deletion removes all matches', async () => {
    const ctx = service([device, Object.assign({}, device, { '.name': 'legacy' })]);
    await ctx.service.saveDevice(mac, 'Edited', '', 'ungrouped');
    assert.equal(ctx.state.saved.length, 1);
    await ctx.service.deleteDevice({ mac }); assert.equal(ctx.state.saved.length, 0);
});
test('commit failure rejects, reverts staged changes and permits a clean retry', async () => {
    const ctx = service([device]); ctx.state.failCommit = true;
    await assert.rejects(ctx.service.saveDevice(mac, 'Failed edit', '', 'ungrouped'), /commit failed/);
    assert.deepEqual(ctx.state.saved, [device]); assert.equal(ctx.state.staged, null); assert.equal(ctx.state.reverts, 1);
    assert.equal(ctx.state.declarations.find(options => options.method === 'commit').reject, true);
    ctx.state.failCommit = false;
    await ctx.service.saveDevice(other, 'Phone', '', 'ungrouped');
    assert.equal(ctx.state.saved.find(section => section.mac === mac).name, 'TV');
});
test('partial save failure also discards staged edits', async () => {
    const ctx = service([device]); ctx.state.failSave = true;
    await assert.rejects(ctx.service.saveDevice(mac, 'Failed edit', '', 'ungrouped'), /save failed/);
    assert.equal(ctx.state.staged, null); assert.equal(ctx.state.reverts, 1);
});
test('rollback failure is visible instead of reporting a successful save', async () => {
    const ctx = service([device]); ctx.state.failCommit = true; ctx.state.failRevert = true;
    await assert.rejects(ctx.service.saveDevice(mac, 'Failed edit', '', 'ungrouped'), /failed to discard pending changes/);
});
test('fresh UCI load observes external edits and validation rejects deleted groups', async () => {
    const ctx = service([group, device]); await ctx.service.load();
    ctx.state.saved[1].name = 'External edit';
    assert.equal((await ctx.service.load()).devices[0].name, 'External edit');
    await assert.rejects(ctx.service.saveDevice(mac, 'TV', '', 'missing'), /no longer exists/);
    assert.equal(ctx.state.commits, 0);
});
test('renaming into an existing group name and overlong inputs are rejected', async () => {
    const ctx = service([group, { '.type': 'group', '.name': 'other', name: 'Other' }]);
    await assert.rejects(ctx.service.renameGroup('other', 'Home'), /already exists/);
    await assert.rejects(ctx.service.saveDevice(mac, 'a'.repeat(65), '', 'ungrouped'), /too long/);
});
test('service refuses writes for read-only sessions', async () => {
    const ctx = service([device]); ctx.env.L.hasViewPermission = () => false;
    await assert.rejects(ctx.service.saveDevice(mac, 'Forbidden', '', 'ungrouped'), /Read-only/);
    assert.equal(ctx.state.reads, 0); assert.equal(ctx.state.commits, 0);
});
test('refresh is serialized after an in-flight write and does not unload it', async () => {
    const ctx = service([device]); let release, started;
    const signal = new Promise(resolve => { started = resolve; });
    const blocker = new Promise(resolve => { release = resolve; });
    const save = ctx.uci.save;
    ctx.uci.save = () => { started(); return blocker.then(save); };
    const writing = ctx.service.saveDevice(mac, 'New name', '', 'ungrouped');
    await signal;
    const reading = ctx.service.load();
    assert.equal(ctx.state.cached[0].name, 'New name');
    release(); await writing;
    assert.equal((await reading).devices[0].name, 'New name');
});
test('every refresh fetches current host hints without network library cache', async () => {
    const ctx = service([]);
    ctx.replies['luci-rpc.getHostHints'] = { [mac]: { ipaddrs: ['192.168.1.20'] } };
    await ctx.service.load();
    ctx.replies['luci-rpc.getHostHints'] = { [mac]: { ipaddrs: ['192.168.1.90'] } };
    assert.equal(model.parseDevices(await ctx.service.load(), [])[0].ipv4, '192.168.1.90');
});
test('discovery errors are reported and do not turn saved devices offline', async () => {
    const ctx = service([device]); ctx.replies['luci-rpc.getHostHints'] = new Error('access denied');
    const snapshot = await ctx.service.load();
    assert.equal(snapshot.discoveryComplete, false); assert.match(snapshot.errors.join(), /access denied/);
    assert.equal(model.parseDevices(snapshot, [])[0].status, 'unknown');
    ctx.replies['luci.device-manager.get_online_status'] = { ok: false, error: 'ip unavailable' };
    assert.match((await ctx.service.load()).errors.join(), /ip unavailable/);
});
test('partial Wi-Fi RPC failure preserves active stations and VLAN discovery', async () => {
    const ctx = service([]);
    ctx.replies['luci-rpc.getNetworkDevices'] = { wlan0: {}, wlan1: {}, 'wlan0.10': {} };
    ctx.replies['luci-rpc.getWirelessDevices'] = { radio0: { interfaces: [
        { ifname: 'wlan0', config: { mode: 'ap' }, vlans: [{ ifname: 'wlan0.10' }] },
        { ifname: 'wlan1', config: { mode: 'ap' } }, { ifname: 'uplink', config: { mode: 'sta' } }
    ] } };
    ctx.replies['iwinfo.assoclist'] = name => name === 'wlan1' ? new Error('radio unavailable') : { results: [{ mac }] };
    const snapshot = await ctx.service.load();
    assert.equal(snapshot.discoveryComplete, false); assert.equal(model.parseDevices(snapshot, [])[0].status, 'online');
    assert.ok(ctx.state.calls.some(call => call.key === 'iwinfo.assoclist' && call.args[0] === 'wlan0.10'));
    assert.ok(!ctx.state.calls.some(call => call.args[0] === 'uplink'));
});

test('stale wireless status does not query interfaces missing from the kernel', async () => {
    const ctx = service([device]);
    ctx.replies['luci-rpc.getWirelessDevices'] = { radio0: { up: true, disabled: false,
        interfaces: [{ ifname: 'wlan0', config: { mode: 'ap' } }] } };
    ctx.replies['luci-rpc.getNetworkDevices'] = { 'br-lan': {}, eth0: {} };
    ctx.replies['iwinfo.assoclist'] = new Error('ubus code 4: Not found');
    const snapshot = await ctx.service.load();
    assert.equal(snapshot.discoveryComplete, true);
    assert.deepEqual(snapshot.errors, []);
    assert.deepEqual(snapshot.wifi, []);
    assert.equal(model.parseDevices(snapshot, [])[0].status, 'offline');
    assert.ok(!ctx.state.calls.some(call => call.key === 'iwinfo.assoclist'));
});

test('only existing AP and VLAN interfaces are queried and each refresh rechecks them', async () => {
    const ctx = service([]);
    ctx.replies['luci-rpc.getWirelessDevices'] = { radio0: { interfaces: [
        { ifname: 'wlan0', config: { mode: 'ap' }, vlans: [{ ifname: 'wlan0.10' }, { ifname: 'wlan0.20' }] },
        { ifname: 'wlan1', config: { mode: 'ap' } }
    ] } };
    ctx.replies['luci-rpc.getNetworkDevices'] = { wlan0: {}, 'wlan0.10': {} };
    ctx.replies['iwinfo.assoclist'] = { results: [{ mac }] };
    const snapshot = await ctx.service.load();
    assert.deepEqual(snapshot.wifi, [{ mac, dev: 'wlan0' }, { mac, dev: 'wlan0.10' }]);
    assert.equal(snapshot.discoveryComplete, true);
    assert.deepEqual(ctx.state.calls.filter(call => call.key === 'iwinfo.assoclist').map(call => call.args[0]), ['wlan0', 'wlan0.10']);
    ctx.replies['luci-rpc.getNetworkDevices'] = {};
    assert.deepEqual((await ctx.service.load()).wifi, []);
    ctx.replies['luci-rpc.getNetworkDevices'] = { wlan1: {} };
    assert.deepEqual((await ctx.service.load()).wifi, [{ mac, dev: 'wlan1' }]);
});

test('failed or invalid kernel device discovery stays visible and keeps unconfirmed devices unknown', async () => {
    for (const response of [new Error('access denied'), 4, null, []]) {
        const ctx = service([device]);
        ctx.replies['luci-rpc.getNetworkDevices'] = response;
        const snapshot = await ctx.service.load();
        assert.equal(snapshot.discoveryComplete, false);
        assert.ok(snapshot.errors.length > 0);
        assert.equal(model.parseDevices(snapshot, [])[0].status, 'unknown');
        assert.ok(!ctx.state.calls.some(call => call.key === 'iwinfo.assoclist'));
    }
});

test('preference corruption and inaccessible storage safely fall back', async () => {
    for (const storage of [{ getItem: () => '{broken' }, { getItem() { throw Error('blocked'); } }]) {
        const env = environment({ window: { localStorage: storage } });
        const preferences = loadModule('device-manager.preferences', env);
        assert.deepEqual(await preferences.load(), { tab: 'online', group: 'all' });
        await preferences.save('online', 'home');
    }
});
test('preference storage contains only tab and group', async () => {
    let raw;
    const env = environment({ window: { localStorage: { getItem: () => raw, setItem: (key, value) => { raw = value; } } } });
    const preferences = loadModule('device-manager.preferences', env);
    await preferences.save('online', 'home');
    assert.deepEqual(JSON.parse(raw), { tab: 'online', group: 'home' });
    assert.deepEqual(await preferences.load(), { tab: 'online', group: 'home' });
});

function pageContext(initial = []) {
    const mocks = backend(initial);
    const env = environment(mocks);
    return Object.assign({ env, page: loadModule('view.device-manager.devices', env) }, mocks);
}
async function renderPage(ctx) {
    const node = await renderLoadedPage(ctx.page);
    return node;
}
function button(node, label) { return node.querySelectorAll('button').find(item => item.textContent === label); }
const attack = '<img src=x onerror="window.auditFlag=1">';

test('untrusted device/group text renders as text in rows, forms and confirmations', async () => {
    const ctx = pageContext([Object.assign({}, group, { name: attack }), Object.assign({}, device, { name: attack, remark: attack, group: 'home' })]);
    ctx.replies['luci-rpc.getHostHints'] = { [mac]: { name: attack, ipaddrs: ['192.168.1.20'] } };
    const node = await renderPage(ctx);
    assert.ok(node.textContent.includes(attack));
    ctx.page.showEditModal(ctx.page.devices[0]);
    assert.equal(ctx.env.ui.modal.attrs.title, 'Edit device');
    ctx.page.confirmDelete(ctx.page.devices[0]);
    ctx.page.showGroupModal(); ctx.page.promptRenameGroup(ctx.page.groups[0]);
    ctx.page.confirmDeleteGroup(ctx.page.groups[0], 1);
    assert.deepEqual(ctx.env.htmlSinks, []);
});
test('search empty-state messages safely display markup-like search text', async () => {
    const ctx = pageContext([]); const node = await renderPage(ctx);
    ctx.page.filterText = attack; ctx.page.updateView();
    assert.ok(node.textContent.includes(attack)); assert.deepEqual(ctx.env.htmlSinks, []);
});
test('actual save button recovers after event.currentTarget is cleared', async () => {
    const ctx = pageContext([]); await renderPage(ctx); ctx.page.showEditModal(null);
    const modal = ctx.env.ui.modal; modal.querySelectorAll('input')[0].value = mac;
    const save = button(modal, 'Save');
    await save.click();
    assert.equal(save.disabled, false); assert.equal(save.classes.has('spinning'), false);
    assert.equal(ctx.state.saved[0].mac, mac); assert.equal(ctx.env.notifications[0].level, 'info');
});
test('save failure leaves the modal open, restores button and never notifies success', async () => {
    const ctx = pageContext([]); await renderPage(ctx); ctx.page.showEditModal(null);
    const modal = ctx.env.ui.modal; modal.querySelectorAll('input')[0].value = mac;
    ctx.state.failCommit = true;
    const save = button(modal, 'Save'); await save.click();
    assert.equal(ctx.env.ui.modal, modal); assert.equal(save.disabled, false);
    assert.equal(ctx.env.notifications.length, 0); assert.match(modal.textContent, /commit failed/);
    assert.equal(ctx.state.saved.length, 0);
});
test('actual add, rename and delete group buttons restore their state', async () => {
    const ctx = pageContext([]); await renderPage(ctx); ctx.page.showGroupModal();
    const modal = ctx.env.ui.modal; modal.querySelector('input').value = 'Home';
    const add = button(modal, 'Add group'); await add.click(); assert.equal(add.disabled, false);
    ctx.page.promptRenameGroup(ctx.page.groups[0]);
    ctx.env.ui.modal.querySelector('input').value = 'Media';
    const rename = button(ctx.env.ui.modal, 'Save changes'); await rename.click(); assert.equal(rename.disabled, false);
    ctx.page.confirmDeleteGroup(ctx.page.groups[0], 0);
    const remove = button(ctx.env.ui.modal, 'Confirm delete'); await remove.click(); assert.equal(remove.disabled, false);
    assert.deepEqual(ctx.page.groups, []);
});
test('actual clear record button restores its state on failure and retry', async () => {
    const ctx = pageContext([device]); await renderPage(ctx); ctx.page.confirmDelete(ctx.page.devices[0]);
    const remove = button(ctx.env.ui.modal, 'Confirm clear'); ctx.state.failCommit = true;
    await remove.click(); assert.equal(remove.disabled, false); assert.equal(ctx.state.saved.length, 1);
    ctx.state.failCommit = false; ctx.page.confirmDelete(ctx.page.devices[0]);
    const retry = button(ctx.env.ui.modal, 'Confirm clear'); await retry.click();
    assert.equal(retry.disabled, false); assert.equal(ctx.state.saved.length, 0);
});
test('refresh button restores state and external group deletion resets the active filter', async () => {
    const ctx = pageContext([group]); const node = await renderPage(ctx);
    ctx.page.activeGroup = 'home'; ctx.state.saved = [];
    const refresh = button(node, 'Refresh list'); await refresh.click();
    assert.equal(refresh.disabled, false); assert.equal(ctx.page.activeGroup, 'all');
    assert.deepEqual(ctx.page.groups, []);
});
test('failed refresh preserves the last displayed snapshot and reports refresh failure', async () => {
    const ctx = pageContext([device]); const node = await renderPage(ctx);
    ctx.uci.load = () => Promise.reject(new Error('configuration unavailable'));
    await button(node, 'Refresh list').click();
    assert.equal(ctx.page.devices[0].customName, 'TV');
    assert.match(ctx.env.notifications[0].content.textContent, /Could not refresh/);
});
test('read-only views have no edit actions or writable dialogs and disable the toolbar', async () => {
    const ctx = pageContext([device]); ctx.env.L.hasViewPermission = () => false;
    const node = await renderPage(ctx);
    ctx.page.activeTab = 'all'; ctx.page.updateView();
    assert.equal(button(node, 'Edit'), undefined); assert.equal(button(node, 'Delete'), undefined);
    assert.equal(node.querySelectorAll('.dm-action-edit').length, 0);
    assert.equal(node.querySelectorAll('.dm-action-detail').length, 1);
    assert.equal(button(node, 'Add device').disabled, true); assert.equal(button(node, 'Manage groups').disabled, true);
    ctx.page.showEditModal(null); ctx.page.showGroupModal(); assert.equal(ctx.env.ui.modal, null);
    assert.equal(ctx.page.handleSave, null); assert.equal(ctx.page.handleSaveApply, null); assert.equal(ctx.page.handleReset, null);
});
test('rows offer edit/details links and saved records can only be cleared from the edit dialog', async () => {
    const ctx = pageContext([device]);
    ctx.replies['luci-rpc.getHostHints'] = { [other]: { name: 'New device' } };
    const node = await renderPage(ctx);
    ctx.page.activeTab = 'all'; ctx.page.updateView();
    const rows = node.querySelector('#device_manager_tbody').querySelectorAll('tr');
    const savedRow = rows.find(row => row.textContent.includes('TV'));
    const unsavedRow = rows.find(row => row.textContent.includes('New device'));
    assert.equal(node.querySelectorAll('.dm-action-delete').length, 0);
    assert.equal(unsavedRow.querySelectorAll('a').length, 2);
    assert.equal(savedRow.querySelectorAll('a').length, 2);
    const edit = savedRow.querySelector('.dm-action-edit');
    const detail = savedRow.querySelector('.dm-action-detail');
    assert.equal(edit.attrs.href, '#'); assert.equal(edit.attrs.role, 'button');
    const click = new Event('click', { cancelable: true });
    edit.dispatchEvent(click);
    assert.equal(click.defaultPrevented, true);
    assert.equal(ctx.env.ui.modal.attrs.title, 'Edit device');
    assert.equal(ctx.env.ui.modal.querySelector('input').value, 'TV');
    await button(ctx.env.ui.modal, 'Clear record').click();
    assert.equal(ctx.env.ui.modal.attrs.title, 'Clear record');
    await detail.click();
    assert.equal(ctx.env.ui.modal.attrs.title, 'Device details');
    const space = new Event('keydown', { cancelable: true });
    Object.defineProperty(space, 'key', { value: ' ' });
    edit.dispatchEvent(space);
    assert.equal(space.defaultPrevented, true);
    assert.equal(ctx.env.ui.modal.attrs.title, 'Edit device');
    await unsavedRow.querySelector('.dm-action-edit').click();
    assert.equal(button(ctx.env.ui.modal, 'Clear record'), undefined);
});
test('tab counts match group/search filters and tabs support keyboard activation', async () => {
    const ctx = pageContext([group, Object.assign({}, device, { group: 'home' })]);
    ctx.replies['iwinfo.assoclist'] = { results: [{ mac: other }] };
    ctx.replies['luci-rpc.getWirelessDevices'] = { radio0: { interfaces: [{ ifname: 'wlan0' }] } };
    ctx.replies['luci-rpc.getNetworkDevices'] = { wlan0: {} };
    const node = await renderPage(ctx);
    const tabs = node.querySelector('#dm-tabs-container').children;
    assert.equal(tabs[0].textContent, 'Online devices1'); assert.equal(tabs[1].textContent, 'All devices2');
    assert.ok(tabs.every(tab => tab.tag === 'button' && tab.attrs.role === 'tab'));
    ctx.page.activeGroup = 'home'; ctx.page.filterText = 'tv'; ctx.page.updateView();
    assert.equal(node.querySelector('#dm-tabs-container').children[0].textContent, 'Online devices0');
    assert.equal(node.querySelector('#dm-tabs-container').children[1].textContent, 'All devices1');
});

test('a failed rollback must recover before a later operation can commit', async () => {
    const ctx = service([device]); ctx.state.failCommit = true; ctx.state.failRevert = true;
    await assert.rejects(ctx.service.saveDevice(mac, 'Failed edit', '', 'ungrouped'));
    ctx.state.failCommit = false;
    await assert.rejects(ctx.service.saveDevice(other, 'Phone', '', 'ungrouped'), /revert failed/);
    assert.deepEqual(ctx.state.saved, [device]);
    ctx.state.failRevert = false;
    await ctx.service.saveDevice(other, 'Phone', '', 'ungrouped');
    assert.equal(ctx.state.saved.find(section => section.mac === mac).name, 'TV');
});
test('a write waits for the entire earlier refresh to finish, including slow discovery', async () => {
    const ctx = service([device]); let release, started;
    const signal = new Promise(resolve => { started = resolve; });
    const blocker = new Promise(resolve => { release = resolve; });
    ctx.fs.read = () => { started(); return blocker.then(() => ''); };
    const reading = ctx.service.load(); await signal;
    const writing = ctx.service.saveDevice(mac, 'New name', '', 'ungrouped');
    await Promise.resolve(); assert.equal(ctx.state.commits, 0);
    release(); assert.equal((await reading).devices[0].name, 'TV');
    await writing; assert.equal(ctx.state.saved[0].name, 'New name');
});

test('MAC-less failures on a different interface do not mark an ARP-known device offline', () => {
    const result = parse({ arp: [{ mac, ip: '192.168.1.20', flags: '0x2', dev: 'br-lan' }],
        neighbors: { neighbors: [{ ip: '192.168.1.20', dev: 'wan', state: 'FAILED' }] } });
    assert.equal(result[0].status, 'unknown');
});
test('switching a status tab preserves focus on the newly rendered tab', async () => {
    const ctx = pageContext([]); const node = await renderPage(ctx);
    await node.querySelector('#dm-tabs-container').children[1].click();
    assert.equal(ctx.page.activeTab, 'all');
    assert.equal(node.querySelector('#dm-tabs-container').children[1].focused, true);
});

test('writable toolbar actions remain enabled under LuCI boolean attribute semantics', async () => {
    const ctx = pageContext([]); const node = await renderPage(ctx);
    assert.equal(button(node, 'Add device').disabled, false);
    assert.equal(button(node, 'Manage groups').disabled, false);
    await button(node, 'Add device').click();
    assert.equal(ctx.env.ui.modal.attrs.title, 'Add device');
});
