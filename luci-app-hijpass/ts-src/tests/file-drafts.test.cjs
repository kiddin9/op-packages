const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const { IDBFactory, IDBKeyRange } = require('fake-indexeddb');

function load(file, globals, modules = {}) {
    const context = vm.createContext({ exports: {}, console, structuredClone, Blob, FormData, ...globals,
        require: name => { if (!(name in modules)) throw new Error('Unexpected import: ' + name); return modules[name]; },
    });
    vm.runInContext('String.prototype.format = function(v) { return this.replace(/%[sd]/, v); };', context);
    vm.runInContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '..', file), 'utf8'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true },
    }).outputText, context);
    return context.exports;
}
function fixture({ indexedDB = new IDBFactory(), sid = 'session-one', files = new Map([['domain_proxy', 'original']]) } = {}) {
    const globals = { indexedDB, IDBKeyRange };
    const storage = load('utils/feature/config/drafts.ts', globals);
    const store = new storage.DraftStore(sid), events = [], document = new EventTarget();
    const state = { authorized: true, failWrite: false, failRead: false, deniedSessions: new Set() };
    const sections = { dns: { '.type': 'dns' }, node: { '.type': 'proxy_node', name: 'renamed' } };
    const resources = { '/etc/hijpass/rules/domain-proxy.txt': 'domain_proxy', '/etc/hijpass/hook/dns-hook.sh': 'dns_hook' };
    const key = filename => resources[filename] || 'proxy_config:node:' + filename.split('/').pop().replace(/-node\.json$/, '');
    const request = { request: async (url, options) => {
        if (!url.endsWith('/cgi-upload')) { events.push(['apply', url]); return { status: 200 }; }
        assert.ok(options.content instanceof FormData);
        const data = options.content;
        assert.ok(data.get('filedata').size > 0, 'native upload rejects zero-byte files');
        assert.equal(data.get('sessionid'), sid);
        events.push(['write', data.get('filename')]);
        if (state.failWrite) return { ok: true, json: () => ({ failure: [5], message: 'write failed' }) };
        if (!state.authorized) return { ok: false, json: () => ({ failure: [13], message: 'session expired' }) };
        files.set(key(data.get('filename')), (await data.get('filedata').text()).trim());
        return { ok: true, json: () => ({ size: data.get('filedata').size }) };
    } };
    const node = (tag, attrs, ...children) => ({ tag, attrs, children,
        appendChild(child) { this.children.push(child); }, classList: { add() {} } });
    const fields = new Map();
    document.querySelectorAll = () => [{}];
    document.createTextNode = text => text;
    const ui = { changes: { apply() {} }, addNotification: (_, value) => events.push(['error', value]),
        showIndicator(_id, _label, handler) { this.open = handler; }, hideIndicator() {},
        ComboButton: class { render() { return node('combo'); } },
        showModal(_title, children) { return this.modal = node('modal', {}, ...children); },
        hideModal() { this.modal = null; } };
    const api = load('modules/drafts.ts', { ...globals, document, location: { reload() { events.push(['reload']); } },
        L: { env: { sessionid: sid }, url: s => '/' + s, loaded: false, dom: { callClassMethod: (_map, _method, field) => fields.has(field) ? [fields.get(field)] : null } },
        _: s => s, E: node,

    }, {
        baseclass: { extend: value => value },
        uci: { unload() {}, load: async () => {}, get: (_, id, field) => field ? sections[id]?.[field] : sections[id],
            set: (...args) => events.push(['hash', ...args]), save: async () => events.push(['uci-save']) },
        ui,
        fs: { read_direct: async filename => {
            events.push(['read', filename]);
            if (!state.authorized) throw Object.assign(new Error('session expired'), { name: 'PermissionError' });
            if (state.failRead) throw new Error('read failed');
            if (!files.has(key(filename))) throw Object.assign(new Error('not found'), { name: 'NotFoundError' });
            return files.get(key(filename));
        } },
        rpc: { declare: spec => async (...args) => {
            if (spec.object === 'session' && spec.method === 'access') {
                if (state.accessError) throw state.accessError;
                return state.authorized;
            }
            assert.equal(spec.method, 'editor_sessions');
            return { sessions: args[0].filter(id => !state.deniedSessions.has(id)) };
        } },
        request, session: { getLocalData: () => [], setLocalData() {} },
        '../utils/feature/config/drafts': storage,
        '../utils/feature/config/diff': { fileDiff: () => ({ lines: [], truncated: false }) },
    }).default;
    return { api, store, events, files, indexedDB, document, request, state, sections, ui, fields };
}
const editor = { resource: 'domain_proxy' };
const tick = () => new Promise(resolve => setTimeout(resolve, 15));
async function eventually(check) {
    const deadline = Date.now() + 2000;
    for (;;) {
        try { await check(); return; }
        catch (error) {
            if (Date.now() >= deadline) throw error;
            await tick();
        }
    }
}

test('Save persists draft across pages in the same session without file or UCI writes', async () => {
    const f = fixture();
    await f.api.save(editor, ' new\r\ncontent ', 'dns', 'domain_proxy_hash');
    assert.equal(f.files.get('domain_proxy'), 'original');
    assert.equal(f.events.some(([kind]) => ['write', 'hash', 'uci-save', 'apply'].includes(kind)), false);
    const next = fixture(f);
    assert.equal(await next.api.read(editor), 'new\ncontent');
    const other = fixture({ ...f, sid: 'session-two' });
    assert.equal(await other.api.read(editor), 'original');
    assert.equal((await other.store.list()).length, 0);
});

test('unchanged files need no draft; reverting edits removes the draft', async () => {
    const f = fixture();
    await f.api.save(editor, 'original\n', 'dns', 'hash');
    assert.equal((await f.store.list()).length, 0);
    await f.api.save(editor, 'new', 'dns', 'hash');
    await f.api.save(editor, 'original', 'dns', 'hash');
    assert.equal((await f.store.list()).length, 0);
});

test('global Apply writes files then hashes then native request; confirmation clears drafts', async () => {
    const f = fixture();
    await f.api.save(editor, 'new', 'dns', 'hash');
    await f.request.request('/admin/uci/apply_rollback', { method: 'post' });
    assert.equal(f.files.get('domain_proxy'), 'new');
    assert.deepEqual(f.events.filter(([kind]) => ['write', 'hash', 'uci-save', 'apply'].includes(kind)).map(([kind]) => kind),
        ['write', 'hash', 'uci-save', 'apply']);
    assert.equal((await f.store.list()).length, 1);
    f.document.dispatchEvent(new Event('uci-applied'));
    await tick();
    assert.equal((await f.store.list()).length, 0);
});

test('failed upload retains drafts; retry overwrites external edits without a conflict check', async () => {
    const f = fixture();
    await f.api.save(editor, 'new', 'dns', 'hash');
    f.state.failWrite = true;
    assert.equal((await f.request.request('/admin/uci/apply_unchecked', { method: 'post' })).status, 409);
    assert.equal(f.events.some(([kind]) => ['hash', 'apply'].includes(kind)), false);
    assert.equal((await f.store.list()).length, 1);
    f.state.failWrite = false;
    f.files.set('domain_proxy', 'edited outside browser');
    assert.equal((await f.request.request('/admin/uci/apply_unchecked', { method: 'post' })).status, 200);
    assert.equal(f.files.get('domain_proxy'), 'new');
    assert.equal(f.events.some(([kind]) => kind === 'apply'), true);
});

test('native Revert clears drafts; unrelated requests never upload', async () => {
    const f = fixture();
    await f.api.save(editor, 'new', 'dns', 'hash');
    await f.request.request('/admin/status/overview', { method: 'get' });
    assert.equal(f.files.get('domain_proxy'), 'original');
    f.document.dispatchEvent(new Event('uci-reverted'));
    await tick();
    assert.equal((await f.store.list()).length, 0);
});

test('expired session cannot read or apply a cached draft and clears its data', async () => {
    const f = fixture();
    await f.api.save(editor, 'new', 'dns', 'hash');
    f.state.authorized = false;
    await assert.rejects(f.api.read(editor), /session expired/i);
    assert.equal((await f.store.list()).length, 0);
    assert.equal(f.files.get('domain_proxy'), 'original');
});

test('a new login preserves live RPC sessions and cleans expired sessions without reusing drafts', async () => {
    const f = fixture();
    await f.api.save(editor, 'new', 'dns', 'hash');
    const next = fixture({ ...f, sid: 'new-login' });
    await tick();
    assert.equal((await f.store.list()).length, 1);
    assert.equal(await next.api.read(editor), 'original');
    const expired = fixture({ ...f, sid: 'another-login' });
    expired.state.deniedSessions.add('session-one');
    await eventually(async () => assert.equal((await f.store.list()).length, 0));
});

test('apply confirmation preserves a draft edited in another tab during apply', async () => {
    const f = fixture();
    await f.api.save(editor, 'first', 'dns', 'hash');
    await f.request.request('/admin/uci/apply_rollback', { method: 'post' });
    const tab = fixture(f);
    await tab.api.save(editor, 'second', 'dns', 'hash');
    f.document.dispatchEvent(new Event('uci-applied'));
    await tick();
    assert.equal(await tab.api.read(editor), 'second');
    assert.equal((await tab.store.list()).length, 1);
    assert.equal((await tab.request.request('/admin/uci/apply_rollback', { method: 'post' })).status, 200);
    assert.equal(f.files.get('domain_proxy'), 'second');
});

test('deleted sections discard their drafts instead of recreating files', async () => {
    const f = fixture();
    await f.api.save(editor, 'new', 'dns', 'hash');
    delete f.sections.dns;
    await f.request.request('/admin/uci/apply_rollback', { method: 'post' });
    assert.equal(f.files.get('domain_proxy'), 'original');
    assert.equal((await f.store.list()).length, 0);
});

test('5 MiB draft survives reload and uploads without the ubus message limit', async () => {
    const f = fixture(), content = '#'.repeat(5 * 1024 * 1024);
    await f.api.save(editor, content, 'dns', 'hash');
    const next = fixture(f);
    assert.equal((await next.api.read(editor)).length, content.length);
    await next.request.request('/admin/uci/apply_unchecked', { method: 'post' });
    assert.equal(next.files.get('domain_proxy'), content);
});

test('IndexedDB failure cannot report a successful Save or mutate UCI', async () => {
    const f = fixture({ indexedDB: { open() { const request = {}; queueMicrotask(() => {
        request.error = new Error('storage unavailable'); request.onerror();
    }); return request; } } });
    await assert.rejects(f.api.save(editor, 'new', 'dns', 'hash'), /storage unavailable/);
    assert.equal(f.events.some(([kind]) => ['write', 'hash'].includes(kind)), false);
});


test('switching a custom node back to a template discards its draft on Apply', async () => {
    const f = fixture();
    await f.api.save({ resource: 'proxy_config', section: 'node', name: 'renamed' }, '{}', 'node', 'custom_conf_hash');
    f.sections.node.config_type = 'tmpl';
    await f.request.request('/admin/uci/apply_rollback', { method: 'post' });
    assert.equal((await f.store.list()).length, 0);
    assert.equal(f.events.some(([kind]) => kind === 'write'), false);
});

function findRevert(node) {
    if (node?.attrs?.class?.includes('cbi-button-reset')) return node.attrs.click;
    for (const child of [node?.children || []].flat(Infinity)) {
        const result = typeof child === 'object' && findRevert(child);
        if (result) return result;
    }
}

test('file Revert updates editor and its saved baseline without page reload or UCI writes', async () => {
    const f = fixture();
    await f.api.save(editor, 'draft', 'dns', 'hash');
    let baseline = 'draft', input = 'draft';
    f.fields.set('hash', { cfgvalue: (_section, value) => baseline = value,
        getUIElement: () => ({ setValue: value => input = value }) });
    f.files.set('domain_proxy', 'current file');
    await f.ui.open();
    const button = {};
    await findRevert(f.ui.modal)({ currentTarget: button });
    assert.equal(input, 'current file');
    assert.equal(baseline, input);
    assert.equal((await f.store.list()).length, 0);
    assert.equal(f.ui.modal, null);
    assert.equal(button.disabled, false);
    assert.equal(f.events.some(([kind]) => ['reload', 'write', 'hash', 'uci-save', 'apply'].includes(kind)), false);
    await f.api.save(editor, input, 'dns', 'hash');
    assert.equal((await f.store.list()).length, 0);
});

test('failed file Revert keeps drafts and inputs and allows retry', async () => {
    const f = fixture();
    await f.api.save(editor, 'draft', 'dns', 'hash');
    f.fields.set('hash', { cfgvalue: () => assert.fail('must not alter editor baseline') });
    await f.ui.open();
    f.state.failRead = true;
    const button = {};
    await findRevert(f.ui.modal)({ currentTarget: button });
    assert.equal((await f.store.list()).length, 1);
    assert.ok(f.ui.modal);
    assert.equal(button.disabled, false);
    assert.equal(f.events.filter(([kind]) => kind === 'error').length, 1);
    assert.equal(f.events.some(([kind]) => kind === 'reload'), false);
});


test('empty content uses native upload with a trailing newline', async () => {
    const f = fixture();
    await f.api.save(editor, '', 'dns', 'hash');
    await f.request.request('/admin/uci/apply_unchecked', { method: 'post' });
    assert.equal(f.files.get('domain_proxy'), '');
});

test('node reads use UCI names and apply uploads directly to the renamed destination', async () => {
    const f = fixture();
    f.files.set('proxy_config:node:renamed', 'old');
    const node = { resource: 'proxy_config', section: 'node' };
    assert.equal(await f.api.read(node), 'old');
    await f.api.save({ ...node, name: 'renamed' }, '{}', 'node', 'hash');
    f.sections.node.name = 'new name';
    await f.request.request('/admin/uci/apply_unchecked', { method: 'post' });
    assert.equal(f.files.get('proxy_config:node:new name'), '{}');
    assert.equal(f.files.get('proxy_config:node:renamed'), 'old');
});

test('missing fixed files fail; new nodes are empty; invalid node paths and server writes are rejected', async () => {
    const f = fixture();
    await assert.rejects(f.api.read({ resource: 'dns_hook' }), /not found/);
    assert.equal(await f.api.read({ resource: 'proxy_config', section: 'node' }), '');
    for (const name of ['../outside', 'x/y', 'x\\y', 'x\0y'])
        await assert.rejects(f.api.read({ resource: 'proxy_config', section: 'node', name }), /Invalid node/);
    await f.api.save({ resource: 'server_config', section: 'node', name: 'server' }, '{}', 'node', 'hash');
    assert.equal((await f.request.request('/admin/uci/apply_unchecked', { method: 'post' })).status, 409);
    assert.equal(f.events.some(([kind]) => kind === 'write'), false);
});


test('native expired-session errors clear drafts, but network failures preserve them', async () => {
    for (const error of [new Error('network unavailable'), Object.assign(new Error('Login session is expired'), { name: 'SessionError' }),
        Object.assign(new Error('RPC call to session/access failed with error -32002: Access denied'), { name: 'RPCError' })]) {
        const f = fixture();
        await f.api.save(editor, 'draft', 'dns', 'hash');
        f.state.accessError = error;
        await assert.rejects(f.api.read(editor));
        assert.equal((await f.store.list()).length, error.name === 'Error' ? 1 : 0);
    }
});
