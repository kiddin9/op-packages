const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const path = require('node:path');

function preview(shunt, firewall, nodes = []) {
    const sections = { hijpass: { ip_proxy: '/rules/proxy' }, firewall, shunt, dns: {} };
    const context = vm.createContext({ exports: {}, require(name) {
        if (name === 'uci') return {
            get_first: (_, type) => sections[type],
            sections: () => [{ enabled: '1', dns_node: 'dns', proxy_node: 'other' }]
        };
        if (name.endsWith('/hijpass')) return {
            LuciFlied: { CONF_NAME: 'hijpass', GLOBAL_SECTION_TYPE: 'hijpass',
                FIREWALL_SECTION_TYPE: 'firewall', DNS_SECTION_TYPE: 'dns', SHUNT_SECTION_TYPE: 'shunt' },
            FIREWALL_DNS_FORWARD: { NONE: 'none' }, PROXY_TYPE: { LOAD_BALANCE: 'load_balance' }
        };
        if (name.endsWith('/dns-forward')) return { FirewallDnsForwardUtils: { getSource: () => 'none' } };
        if (name.endsWith('/chain')) return { ProxyChainUtils: {
            getProxySectionMap: () => new Map(nodes.map(node => [node.name, node])),
            getProxyCore: node => node.core,
            collectProxyChain: name => ({ chain: [name] })
        } };
        throw new Error(name);
    } });
    vm.runInContext("String.prototype.format = function (...args) { let i = 0; return this.replace(/%s/g, () => args[i++]); }; function _(text) { return text; }", context);
    const source = readFileSync(path.join(__dirname, '../utils/feature/overview/flow-model.ts'), 'utf8');
    vm.runInContext(ts.transpileModule(source, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true }
    }).outputText, context);
    return context.exports.buildConfigurationFlowPreview().diagrams[1];
}

for (const type of ['sing-box', 'xray']) {
    for (const config_type of ['tmpl', 'custom']) {
        test(`${type} ${config_type}: show port and routing resource without internal outbounds`, () => {
            const diagram = preview({ enabled: '1', shunt_listen_port: '18081', type, config_type }, { shunt_port: '18081' });
            for (const branch of diagram.branches) {
                assert.equal(branch.steps.length, 2);
                assert.equal(branch.steps[0].title, 'Default shunt port: 18081');
                assert.equal(branch.steps[0].detail, undefined);
                assert.equal(branch.steps[1].title, 'Default shunt');
                assert.equal(branch.steps[0].page, 'firewall');
                assert.equal(branch.steps[1].page, 'shunt');
                assert.equal(branch.steps[1].detail, type === 'xray' ? 'Xray' : type);
            }
        });
    }
}

test('both default and proxy ports show the actual node resource', () => {
    const diagram = preview({ shunt_listen_port: '18081' }, { shunt_port: '7890', proxy_port: '7890' },
        [{ enabled: '1', name: 'node', listen_port: '7890', core: 'sing-box' }]);
    assert.equal(diagram.branches[0].steps.length, 2);
    assert.equal(diagram.branches[0].steps[0].title, 'Proxy port: 7890');
    assert.equal(diagram.branches.at(-1).steps[0].title, 'Default shunt port: 7890');
    for (const branch of diagram.branches) {
        assert.equal(branch.steps.length, 2);
        assert.equal(branch.steps[1].title, 'Proxy node: node');
        assert.equal(branch.steps[0].page, 'firewall');
        assert.equal(branch.steps[1].page, 'proxy');
        assert.equal(branch.steps[1].detail, 'sing-box');
    }
});

test('disabled routing service retains warning', () => {
    const diagram = preview({ enabled: '0', shunt_listen_port: '18081' }, { shunt_port: '18081' });
    assert.equal(diagram.branches.at(-1).steps[0].tone, 'warning');
});
