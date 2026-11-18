const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('typescript');

function panel(active, backend = {}) {
    const calls = [], frames = [], nodes = [], pane = new EventTarget();
    pane.getAttribute = name => name === 'data-tab-active' ? String(active) : null;
    const context = vm.createContext({ exports: {}, _: value => value,
        E: (tag, attributes, children) => { const node = { tag, attributes, children, isConnected: true,
            closest(selector) { assert.equal(selector, '[data-tab="runtime"]'); return pane; } }; nodes.push(node); return node; },
        window: { requestAnimationFrame: fn => frames.push(fn) },
        require(name) {
            if (name.endsWith('/backend')) return { Backend: {
                coreUpdateStatus: async () => ({ id: null }),
                coreAction: async (action, core) => { calls.push([action, core]); return { version: 'test' }; },
                ...backend,
            } };
            if (name.endsWith('/enum/hijpass')) return { HijpassValues: { DUAL_CORES: [{ value: 'sing-box', label: 'sing-box' }, { value: 'xray', label: 'xray' }] } };
            if (name === './progress') return { formatUpdateProgress: progress => progress.phase + ': ' + progress.resource };
            return { NotificationUtils: { success() {}, error() {} } };
        },
    });
    vm.runInContext('String.prototype.format = function(value) { return this.replace("%s", value); };', context);
    const source = fs.readFileSync(path.join(__dirname, '../utils/feature/rule/runtime.ts'), 'utf8');
    vm.runInContext(ts.transpileModule(source, { compilerOptions: {
        module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true,
    } }).outputText, context);
    const node = context.exports.RuntimePanelUtils.createCoreVersionPanel();
    return { calls, node, nodes, mounted: () => frames.shift()(),
        activate() { active = true; pane.dispatchEvent(new Event('cbi-tab-active')); } };
}

for (const active of [false, true]) test(`core versions load once when the runtime tab ${active ? 'is restored as active' : 'is first opened'}`, async () => {
    const f = panel(active);
    assert.deepEqual(f.calls, []);
    f.mounted();
    if (!active) {
        assert.deepEqual(f.calls, [], 'hidden runtime tab must not contact the backend');
        f.activate();
    }
    await new Promise(setImmediate);
    assert.deepEqual(f.calls, [['version', 'sing-box'], ['latest', 'sing-box'], ['version', 'xray'], ['latest', 'xray']]);
    f.activate();
    assert.equal(f.calls.length, 4, 'switching tabs again must not repeat version lookups');
});

test('a panel removed before its mount callback does not start version requests', () => {
    const f = panel(true);
    f.node.isConnected = false;
    f.mounted();
    assert.deepEqual(f.calls, []);
});

test('opening runtime after refresh resumes the core task and shows live progress', async () => {
    let finish, resumes = 0;
    const f = panel(true, {
        coreUpdateStatus: async core => ({ id: core === 'xray' ? 'Task1234' : null }),
        resumeCoreUpdate: (id, progress) => {
            assert.equal(id, 'Task1234'); resumes++;
            progress({ phase: 'download', resource: 'Xray-linux-64.zip', bytes: 4096 });
            return new Promise(resolve => { finish = resolve; });
        },
    });
    f.mounted();await new Promise(setImmediate);
    const button = f.nodes.filter(node => node.tag === 'button')[1];
    const status = f.nodes.filter(node => node.attributes.role === 'status')[1];
    assert.equal(resumes, 1);
    assert.equal(button.disabled, true);
    assert.equal(status.textContent, 'download: Xray-linux-64.zip');
    button.attributes.click({ preventDefault() {}, currentTarget: button });
    assert.equal(f.calls.some(([action]) => action === 'update'), false);
    finish({ success: true, version: 'v1.2.3' });await new Promise(setImmediate);
    assert.equal(button.disabled, false);
    assert.match(status.textContent, /v1.2.3/);
});
