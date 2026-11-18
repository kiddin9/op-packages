const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('typescript');

function panel(updateRules, ruleUpdateStatus = async () => ({ id: null }), resumeRuleUpdate = updateRules) {
    const nodes = [];
    function E(tag, attributes, children = []) {
        const node = { tag, attributes, style: {}, children: Array.isArray(children) ? children : [children],
            appendChild(child) { this.children.push(child); } };
        Object.defineProperty(node, 'textContent', {
            get() { return this.children.map(child => typeof child === 'string' ? child : child.textContent).join(''); },
            set(value) { this.children = [value]; },
        });
        nodes.push(node);
        return node;
    }
    const context = vm.createContext({ exports: {}, E, _: value => value,
        require: name => name === './progress' ? { formatUpdateProgress: progress => progress.phase + ': ' + progress.resource }
            : ({ Backend: { updateRules, ruleUpdateStatus, resumeRuleUpdate } }),
    });
    vm.runInContext('String.prototype.format = function(value) { return this.replace("%s", value); };', context);
    const source = fs.readFileSync(path.join(__dirname, '../utils/feature/rule/panel.ts'), 'utf8');
    vm.runInContext(ts.transpileModule(source, { compilerOptions: {
        module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true,
    } }).outputText, context);
    context.exports.RulePanelUtils.createUpdateButtons();
    return { status: nodes.find(node => node.attributes.role === 'status'),
        button: nodes.find(node => node.tag === 'button') };
}

test('rule update shows a concise failure without raw command output, then clears on success', async () => {
    const responses = [{ success: false, failed: ['geoip'], details: 'curl failure\ncustom hook warning' }, { success: true }];
    const f = panel(async () => responses.shift());
    assert.equal(f.button.disabled, true);
    assert.equal(f.button.textContent, 'Checking...');
    await new Promise(setImmediate);
    assert.equal(f.button.textContent, 'Update Rule Files');
    f.button.attributes.click({ preventDefault() {} });
    assert.equal(f.button.disabled, true);
    await new Promise(setImmediate);
    assert.equal(f.button.disabled, false);
    assert.equal(f.status.textContent, 'Rule File Update Failed: GeoIP');
    assert.equal(f.status.children.length, 1);
    f.button.attributes.click({ preventDefault() {} });
    await new Promise(setImmediate);
    assert.equal(f.status.textContent, 'Rule Files Updated');
    assert.equal(f.button.disabled, false);
});

test('page refresh resumes the existing update and disables repeated clicks', async () => {
    let starts = 0, resumes = 0, finish;
    const f = panel(async () => { starts++; return { success: true }; }, async () => ({ id: 'Task1234' }), id => {
        assert.equal(id, 'Task1234'); resumes++;
        return new Promise(resolve => { finish = resolve; });
    });
    await new Promise(setImmediate);
    assert.equal(f.button.disabled, true);
    assert.equal(f.status.textContent, 'Updating Rule Files');
    assert.equal(f.button.textContent, 'Update Rule Files');
    f.button.attributes.click({ preventDefault() {} });
    assert.equal(starts, 0);
    assert.equal(resumes, 1);
    finish({ success: true });
    await new Promise(setImmediate);
    assert.equal(f.button.disabled, false);
    assert.equal(f.status.textContent, 'Rule Files Updated');
});

test('checking status prevents premature clicks and a failed check restores the update button', async () => {
    let failCheck, starts = 0;
    const f = panel(async () => { starts++; return { success: true }; },
        () => new Promise((resolve, reject) => { failCheck = reject; }));
    await new Promise(setImmediate);
    assert.equal(f.button.textContent, 'Checking...');
    assert.equal(f.button.disabled, true);
    f.button.attributes.click({ preventDefault() {} });
    assert.equal(starts, 0);
    failCheck(new Error('status unavailable'));
    await new Promise(setImmediate);
    assert.equal(f.button.disabled, false);
    assert.equal(f.button.textContent, 'Update Rule Files');
    assert.equal(f.status.textContent, 'Failed to check update status: status unavailable');
    f.button.attributes.click({ preventDefault() {} });
    await new Promise(setImmediate);
    assert.equal(starts, 1);
    assert.equal(f.status.textContent, 'Rule Files Updated');
});

test('apply failure is distinguished from download failure', async () => {
    const f = panel(async () => ({ success: false, failed: ['restart'] }));
    await new Promise(setImmediate);
    f.button.attributes.click({ preventDefault() {} });
    await new Promise(setImmediate);
    assert.equal(f.status.textContent, 'Rule files updated, but service restart failed; see main log');
});

 test('refresh restores live resource progress before completion', async () => {
    let finish;
    const f = panel(() => assert.fail('must not start another update'), async () => ({ id: 'Task1234' }), (id, progress) => {
        progress({ phase: 'download', resource: 'geoip', bytes: 4096 });
        return new Promise(resolve => { finish = resolve; });
    });
    await new Promise(setImmediate);
    assert.equal(f.status.textContent, 'download: geoip');
    assert.equal(f.button.disabled, true);
    finish({ success: false, failed: ['geoip'] });
    await new Promise(setImmediate);
    assert.equal(f.status.textContent, 'Rule File Update Failed: GeoIP');
    assert.equal(f.button.disabled, false);
});
