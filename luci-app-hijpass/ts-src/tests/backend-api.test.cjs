const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('typescript');

function backend(handler, clock = { now: 0 }) {
    const source = fs.readFileSync(path.join(__dirname, '../utils/backend.ts'), 'utf8');
    const calls = [];
    const context = vm.createContext({ exports: {}, console, _: value => value,
        Date: class extends Date { static now() { return clock.now; } },
        window: { setTimeout(fn, ms) { clock.now += ms; fn(); } },
        require(name) {
            if (name === 'hijpass.drafts') return { read: async editor => {
                calls.push(['draft_read', [editor.resource, editor.section || '', editor.name || '']]);
                const result = handler('draft_read', [editor]);
                if (result.error) throw new Error(result.error);
                return result.content;
            } };
            assert.equal(name, 'rpc');
            return { declare: options => async (...args) => {
                assert.equal(options.object, 'hijpass');
                assert.equal(options.reject, true);
                calls.push([options.method, args]);
                return handler(options.method, args, options);
            } };
        },
    });
    vm.runInContext(ts.transpileModule(source, { compilerOptions: {
        module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true,
    } }).outputText, context);
    return { api: context.exports.Backend, calls };
}

test('editor reads use the shared draft module and expose no immediate file write', async () => {
    const f = backend(() => ({ content: 'draft template' }));
    assert.equal(await f.api.readEditor({ resource: 'firewall_template' }), 'draft template');
    assert.deepEqual(Array.from(f.calls[0][1]), ['firewall_template', '', '']);
    assert.equal(f.api.writeEditor, undefined);
    const failed = backend(() => ({ error: 'read failed' }));
    await assert.rejects(failed.api.readEditor({ resource: 'proxy_config' }), /read failed/);
});

test('configuration preview and validation share the hijpass RPC object without a file-writing API', async () => {
    const f = backend(method => method === 'config_render' ? { config: { outbounds: [] } } : { ok: true });
    const snapshot = '[{".name":"global",".type":"hijpass"}]';
    assert.deepEqual((await f.api.renderConfigs(snapshot, 'node')).config, { outbounds: [] });
    await f.api.validateConfigs(snapshot);
    assert.equal(f.api.writeConfigs, undefined);
    assert.deepEqual(f.calls.map(([method]) => method), ['config_render', 'config_validate']);
    assert.deepEqual(Array.from(f.calls[0][1]), [snapshot, 'node']);
});

for (const code of [0, 7]) test(`long updates poll beyond the RPC limit, report exit ${code} without an extra release request`, async () => {
    const clock = { now: 0 };
    const f = backend(method => {
        if (method === 'rule_update') return { id: 'Abcd1234' };
        assert.equal(method, 'job_status');
        if (clock.now < 120000) return { running: true };
        return { running: false, code, stdout: code ? '' : '{"success":true}', stderr: code ? 'download failed' : '' };
    }, clock);
    if (code) await assert.rejects(f.api.updateRules(), /Backend operation failed; see main log/);
    else assert.equal((await f.api.updateRules()).success, true);
    assert.equal(clock.now, 120000);
    assert.equal(f.calls.at(-1)[0], 'job_status');
});

test('structured update failures retain resource names without exposing combined command output', async () => {
    const f = backend(method => {
        if (method === 'rule_update') return { id: 'Abcd1234' };
        return { running: false, code: 1, stdout: '{"success":false,"failed":["geoip","geosite"]}',
            stderr: 'curl: (28) timed out\ncustom hook warning' };
    });
    const result = await f.api.updateRules();
    assert.equal(result.success, false);
    assert.deepEqual(Array.from(result.failed), ['geoip', 'geosite']);
    assert.equal(result.details, undefined);
    assert.equal(f.calls.at(-1)[0], 'job_status');
});

test('a nonzero script exit cannot be hidden by a success JSON body', async () => {
    const f = backend(method => {
        if (method === 'rule_update') return { id: 'Abcd1234' };
        assert.equal(method, 'job_status');
        return { running: false, code: 1, stdout: '{"success":true}', stderr: 'write failed' };
    });
    await assert.rejects(f.api.updateRules(), /Backend operation failed; see main log/);
    assert.equal(f.calls.at(-1)[0], 'job_status');
});

test('resuming an existing update polls it without starting another job', async () => {
    const f = backend(method => {
        if (method === 'rule_update_status') return { id: 'Abcd1234' };
        assert.equal(method, 'job_status');
        return { running: false, code: 0, stdout: '{"success":true}', stderr: '[I] informational' };
    });
    assert.equal((await f.api.ruleUpdateStatus()).id, 'Abcd1234');
    assert.equal((await f.api.resumeRuleUpdate('Abcd1234')).success, true);
    assert.deepEqual(f.calls.map(([method]) => method), ['rule_update_status', 'job_status']);
});

test('a pending core version lookup does not hold the rule update status response in its RPC batch', async () => {
    let finishLatest;
    const latest = new Promise(resolve => { finishLatest = resolve; });
    const f = backend((method, args, options) => {
        if (method === 'core_latest') {
            assert.equal(options.nobatch, true);
            return latest;
        }
        assert.equal(method, 'rule_update_status');
        return options.nobatch ? { id: null } : latest.then(() => ({ id: null }));
    });
    const core = f.api.coreAction('latest', 'xray');
    let received = false;
    const status = f.api.ruleUpdateStatus().then(result => { received = true; return result; });
    try {
        await new Promise(setImmediate);
        assert.equal(received, true, 'idle status should arrive while the core lookup is still pending');
    } finally {
        finishLatest({ version: 'test' });
        await core;
    }
    assert.equal((await status).id, null);
});

test('an active partial update is reported as busy instead of claiming a full update succeeded', async () => {
    const f = backend(method => {
        assert.equal(method, 'rule_update');
        return { id: 'Abcd1234', success: false, code: 'UPDATE_BUSY' };
    });
    const result = await f.api.updateRules();
    assert.equal(result.code, 'UPDATE_BUSY');
    assert.equal(f.calls.length, 1);
});

test('runtime TypeScript has no device filesystem paths or direct fs access', () => {
    const base = path.join(__dirname, '..');
    for (const folder of ['views', 'utils']) for (const name of fs.readdirSync(path.join(base, folder), { recursive: true })) {
        if (!name.endsWith('.ts')) continue;
        const source = fs.readFileSync(path.join(base, folder, name), 'utf8');
        assert.doesNotMatch(source, /from\s+['"]fs['"]|\/(?:etc|usr|tmp)\//, folder + '/' + name);
    }
});

test('rule-set references remain visible to form prechecks without parsing filenames', () => {
    function load(file, require) {
        const context = vm.createContext({ exports: {}, require });
        const source = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
        vm.runInContext(ts.transpileModule(source, { compilerOptions: {
            module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true,
        } }).outputText, context);
        return context.exports;
    }
    const model = load('module/luci.ts', () => ({}));
    const { ShuntUtils } = load('utils/feature/shunt/section.ts', name => name.endsWith('/module/luci') ? model : {});
    const reference = 'rule-set:remote:https://example.org/list.srs';
    const parsed = ShuntUtils.parseRuleList({ domainList: reference, ipList: '' });
    assert.equal(parsed.containRuleSet(), true);
    assert.equal(parsed.isEmpty('set'), false);
    assert.deepEqual(Array.from(parsed.ruleSet), [reference]);
});

for (const kind of ['rules', 'xray', 'sing-box']) test(`resume ${kind} exposes progress without launching a new download`, async () => {
    let polls = 0;
    const f = backend((method, args) => {
        if (method === 'core_update_status' || method === 'rule_update_status') return { id: 'Abcd1234' };
        assert.equal(method, 'job_status');
        if (++polls === 1) return { running: true, progress: { phase: 'download', resource: kind, bytes: 4096 } };
        return { running: false, code: 0, stdout: '{"success":true}', stderr: '' };
    });
    const { id } = kind === 'rules' ? await f.api.ruleUpdateStatus() : await f.api.coreUpdateStatus(kind);
    const updates = [];
    const result = await (kind === 'rules' ? f.api.resumeRuleUpdate : f.api.resumeCoreUpdate)(id, value => updates.push(value));
    assert.equal(result.success, true);
    assert.equal(updates[0].bytes, 4096);
    assert.equal(updates[0].resource, kind);
    assert.equal(f.calls.some(([method]) => method === 'core_update' || method === 'rule_update'), false);
});
