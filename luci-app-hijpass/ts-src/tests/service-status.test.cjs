const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');

test('service status does not cause its parent form to be saved twice', async () => {
    const source = readFileSync(new URL('../utils/base/luci/service.ts', `file://${__filename}`), 'utf8');
    const { outputText } = ts.transpileModule(source, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true }
    });
    function E(tag, attrs, children) {
        const node = { tag, attrs, children: Array.isArray(children) ? children : [children] };
        for (const child of node.children) {
            if (child && typeof child === 'object') child.parentNode = node;
        }
        return node;
    }
    const sandbox = {
        exports: {}, E, _: value => value,
        window: { setTimeout() {} },
        require(name) {
            if (name === 'rpc') return { declare: () => () => Promise.resolve({}) };
            if (name === 'poll') return { add() {} };
            return {};
        }
    };
    vm.runInNewContext(outputText, sandbox);
    const status = sandbox.exports.ServiceUtils.renderServiceStatus('dns')();
    const root = E('div', { class: 'cbi-map' }, status);
    let saves = 0;
    let deletes = 0;
    let customOptionExists = true;
    root.instance = { async save() {
        saves++;
        deletes++;
        assert.ok(customOptionExists, 'duplicate delete would return UCI not found');
        customOptionExists = false;
    } };
    const maps = [];
    function visit(node) {
        if (!node || typeof node !== 'object') return;
        if ((node.attrs.class || '').split(/\s+/).includes('cbi-map')) maps.push(node);
        node.children.forEach(visit);
    }
    visit(root);
    // LuCI handleSave scans .cbi-map; findClassInstance walks up to the owner.
    await Promise.all(maps.map(node => {
        while (!node.instance) node = node.parentNode;
        return node.instance.save();
    }));
    assert.equal(saves, 1);
    assert.equal(deletes, 1);
    assert.equal(status.children[0].attrs.class, 'cbi-section');
});
