const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const path = require('node:path');

const context = vm.createContext({
    exports: {}, require: () => ({}),
    L: { url: value => '/cgi-bin/luci/' + value },
    E: (tag, attrs, children) => ({ tag, attrs, children }),
});
vm.runInContext(ts.transpileModule(readFileSync(path.join(__dirname,
    '../utils/feature/overview/flow-preview.ts'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS },
}).outputText, context);

test('configuration cards use native links with correct LuCI paths', () => {
    for (const page of ['firewall', 'proxy', 'shunt', 'dns', 'dhcp']) {
        const card = context.renderStep({ title: page, page });
        assert.equal(card.tag, 'a');
        assert.equal(card.attrs.href, '/cgi-bin/luci/' +
            (page === 'dhcp' ? 'admin/network/dhcp' : 'admin/services/hijpass/' + page));
    }
    const result = context.renderStep({ title: 'Direct' });
    assert.equal(result.tag, 'div');
    assert.equal(result.attrs.href, undefined);
});

test('parallel and ordered configuration conditions support navigation', () => {
    for (const render of [context.renderParallelBranch, context.renderOrderedBranch]) {
        const branch = render({ condition: 'DNS list', page: 'dns', steps: [] });
        const card = branch.children.find(child => child.tag === 'a');
        assert.equal(card.attrs.href, '/cgi-bin/luci/admin/services/hijpass/dns');
    }
});
