'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { environment, loadModule, backend, root, renderLoadedPage } = require('./helpers/runtime');

function catalogue() {
    const messages = {};
    let key = '', value = '', field = '';
    for (const line of (fs.readFileSync(path.join(root, 'po/zh_Hans/device-manager.po'), 'utf8') + '\n\n').split('\n')) {
        if (line.startsWith('msgid ')) { key = JSON.parse(line.slice(6)); field = 'key'; }
        else if (line.startsWith('msgstr ')) { value = JSON.parse(line.slice(7)); field = 'value'; }
        else if (line.startsWith('"')) {
            if (field === 'key') key += JSON.parse(line);
            else if (field === 'value') value += JSON.parse(line);
        } else if (!line.trim()) {
            if (key && value) messages[key] = value;
            key = ''; value = ''; field = '';
        }
    }
    return messages;
}
function context(translate = text => text, initial = []) {
    const mocks = backend(initial);
    const env = environment(Object.assign({}, mocks, {
        _: translate,
        window: { navigator: { languages: ['zh-CN'] }, localStorage: { getItem: () => null, setItem() {} } }
    }));
    const page = loadModule('view.device-manager.devices', env);
    return { mocks, env, page };
}
async function render(ctx) { return await renderLoadedPage(ctx.page); }
function button(node, label) { return node.querySelectorAll('button').find(item => item.textContent === label); }

test('native LuCI catalogue translates the page, sort titles, types and dialogs', async () => {
    const messages = catalogue();
    const ctx = context(text => messages[text] || text, [
        { '.type': 'device', '.name': 'saved', mac: 'AA:BB:CC:11:22:33', name: '客厅电视', type: 'tv' }
    ]);
    const node = await render(ctx);
    assert.ok(button(node, messages['Refresh list']));
    assert.ok(button(node, messages['Add device']));
    assert.ok(button(node, messages['Hide info']));
    assert.ok(button(node, messages['Scan LAN']));
    const title = node.querySelectorAll('th').find(th => th.getAttribute('data-sort') === 'name').querySelector('button').attrs.title;
    assert.equal(title, messages['Click to sort by %s'].format(messages['Device name']));
    ctx.page.showEditModal(ctx.page.devices[0]);
    assert.equal(ctx.env.ui.modal.attrs.title, messages['Edit device']);
    assert.ok(button(ctx.env.ui.modal, messages.Save));
    assert.ok(ctx.env.ui.modal.querySelectorAll('option').some(option => option.textContent === messages.TV));
    assert.deepEqual(ctx.env.htmlSinks, []);
});
test('LuCI decides language without a browser override or custom language RPC', async () => {
    for (const translate of [text => text, text => 'DE:' + text, text => '繁體:' + text]) {
        const ctx = context(translate);
        const node = await render(ctx);
        assert.ok(button(node, translate('Refresh list')));
        assert.ok(node.textContent.includes(translate('LAN Device Management')));
        assert.ok(!ctx.mocks.state.calls.some(call => call.key.includes('get_language')));
    }
});
test('legacy default group labels translate while custom metadata remains literal', async () => {
    const initial = [
        { '.type': 'group', '.name': 'smart_home', name: '智能家居' },
        { '.type': 'group', '.name': 'phone', name: 'My phones' },
        { '.type': 'group', '.name': 'grp_custom', name: '办公设备' }
    ];
    const ctx = context(text => 'DE:' + text, initial);
    await render(ctx);
    assert.deepEqual(ctx.page.groups.map(group => group.name), ['DE:Smart home', 'My phones', '办公设备']);
    assert.deepEqual(ctx.mocks.state.saved, initial);
});
test('loading and refreshing never start active scans; the explicit button scans then refreshes', async () => {
    const ctx = context(); const node = await render(ctx);
    await ctx.page.refresh();
    assert.equal(ctx.mocks.state.calls.filter(call => call.key.endsWith('.scan_devices')).length, 0);
    await button(node, 'Scan LAN').click();
    const keys = ctx.mocks.state.calls.map(call => call.key);
    assert.equal(keys.filter(key => key.endsWith('.scan_devices')).length, 1);
    assert.ok(keys.lastIndexOf('luci.device-manager.get_online_status') > keys.indexOf('luci.device-manager.scan_devices'));
    assert.equal(button(node, 'Scan LAN').disabled, false);
});
test('read-only users cannot start scans and scan failures restore the control', async () => {
    const ctx = context();
    ctx.env.L.hasViewPermission = () => false;
    const node = await render(ctx);
    assert.equal(button(node, 'Scan LAN').disabled, true);
    await ctx.page.scan();
    assert.ok(!ctx.mocks.state.calls.some(call => call.key.endsWith('.scan_devices')));
    ctx.env.L.hasViewPermission = () => true;
    ctx.page.readonly = false;
    const writable = await renderLoadedPage(ctx.page);
    ctx.mocks.replies['luci.device-manager.scan_devices'] = { ok: false };
    await button(writable, 'Scan LAN').click();
    assert.equal(button(writable, 'Scan LAN').disabled, false);
    assert.match(ctx.env.notifications.at(-1).content.textContent, /Could not scan LAN devices/);
});
