const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test, after } = require('node:test');
const { run, config } = require('./helpers.cjs');
const fixtures = require('./testdata/compatibility.json');

const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hijpass-generation-'));
after(() => fs.rmSync(directory, { recursive: true, force: true }));
const driver = path.join(directory, 'render.uc');
fs.writeFileSync(driver, `import * as fs from 'fs';
import { render } from 'hijpass.coreconfig.render';
let input = json(fs.stdin.read('all')), before = sprintf('%J', input);
let generated = render(input);
assert(sprintf('%J', input) == before, 'generation modified its input');
printf('%J\\n', generated);
`);

function render(input) {
    const result = run(driver, [], input);
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
}
function generate(sections, target) {
    const result = config(['call', 'render'], { sections: JSON.stringify(sections), target });
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
}
function inputFor(sections) {
    const proxies = sections.filter(section => section['.type'] === 'proxy_node');
    const shunt = sections.find(section => section['.type'] === 'shunt');
    return {
        rootProxies: proxies,
        availableProxies: proxies,
        routing: shunt ? {
            shunt,
            dnsNodes: sections.filter(section => section['.type'] === 'shunt_dns_node'),
            rules: sections.filter(section => section['.type'] === 'shunt_route_rule'),
        } : null,
    };
}

for (const core of ['sing-box', 'xray']) {
    test(`${core}: generation follows explicit roots and candidates regardless of enabled flags`, () => {
        const fixture = fixtures.find(f => f.name === `${core}-chain`);
        const input = inputFor(structuredClone(fixture.sections));
        input.rootProxies = input.rootProxies.filter(section => section['.name'] === 'downstream');
        for (const proxy of input.availableProxies) proxy.enabled = '0';
        assert.deepEqual(render(input), fixture.expected);
        input.rootProxies = [];
        assert.deepEqual(render(input), { nodes: {} });
    });

    test(`${core}: generation consumes the supplied shunt, DNS nodes and rules without enable policy`, () => {
        const fixture = fixtures.find(f => f.name === `${core}-shunt-rules`);
        const sections = structuredClone(fixture.sections);
        for (const section of sections) section.enabled = '0';
        const input = inputFor(sections);
        input.routing.shunt.config_type = 'custom';
        assert.deepEqual(render(input), fixture.expected);
        const invalid = structuredClone(input);
        invalid.routing.rules[0].proxy_node = 'missing';
        const result = run(driver, [], invalid);
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /missing/);
    });

    test(`${core}: entry points exclude disabled rules and DNS nodes for generation and preview`, () => {
        const fixture = fixtures.find(f => f.name === `${core}-shunt-default`);
        const sections = structuredClone(fixture.sections);
        sections.push(
            { '.name': 'disabled-dns', '.type': 'shunt_dns_node', enabled: '0', tag: 'dns', port: 'invalid' },
            { '.name': 'disabled-rule', '.type': 'shunt_route_rule', enabled: '0', proxy_node: 'missing' },
        );
        const shunt = sections.find(section => section['.type'] === 'shunt');
        assert.deepEqual(generate(sections), fixture.expected);
        shunt.enabled = '0';
        assert.deepEqual(generate(sections), { nodes: {} });
        assert.deepEqual(generate(sections, shunt['.name']), { config: fixture.expected.shunt });
    });
}

test('entry points allow a disabled preview root but exclude disabled dependency candidates', () => {
    const fixture = fixtures.find(f => f.name === 'sing-box-chain');
    for (const type of ['vless', 'load_balance']) {
        const sections = structuredClone(fixture.sections);
        const upstream = sections.find(section => section['.name'] === 'member');
        const root = sections.find(section => section['.name'] === 'downstream');
        root.enabled = '0';
        root.type = type;
        if (type === 'load_balance') {
            delete root.upstream_proxy_node;
            root.member_node = ['member'];
        }
        assert.ok(generate(sections, root['.name']).config);
        upstream.enabled = '0';
        assert.match(generate(sections, root['.name']).error, /member.*missing/);
        assert.deepEqual(generate(sections), { nodes: {} });
    }
});

test('generation rejects duplicate root names even when roots are not dependency candidates', () => {
    const fixture = fixtures.find(f => f.name === 'sing-box-chain');
    const input = inputFor(structuredClone(fixture.sections));
    for (const root of input.rootProxies) {
        root.name = 'same-name';
        root.enabled = '0';
        delete root.upstream_proxy_node;
    }
    input.availableProxies = [];
    const result = run(driver, [], input);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /duplicate proxy name/);
});
