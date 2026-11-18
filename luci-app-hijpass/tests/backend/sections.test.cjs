const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { run, config, root } = require('./helpers.cjs');

function execute(t, source, input) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hijpass-sections-'));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const file = path.join(directory, 'check.uc');
    fs.writeFileSync(file, source);
    return run(file, [], input);
}
function modulePath(relative) { return JSON.stringify(path.join(root, 'root', relative)); }

test('section queries preserve order and references, and return null when absent', t => {
    const result = execute(t, `import { filterSectionsByType, findFirstSectionByType } from ${modulePath('usr/share/ucode/hijpass/config/sections.uc')};
let sections = [{ '.type': 'rule', '.name': 'rule' }, { '.type': 'dns', '.name': 'first' }, { '.type': 'dns', '.name': 'second' }];
let found = findFirstSectionByType(sections, 'dns');
found.marker = 'same object';
printf('%J', { found, original: sections[1], matches: filterSectionsByType(sections, 'dns'),
    missing: findFirstSectionByType(sections, 'missing'), empty: findFirstSectionByType([], 'dns'),
    noMatches: filterSectionsByType(sections, 'missing') });`);
    assert.equal(result.status, 0, result.stderr);
    const value = JSON.parse(result.stdout);
    assert.equal(value.found['.name'], 'first');
    assert.equal(value.original.marker, 'same object');
    assert.deepEqual(value.matches.map(s => s['.name']), ['first', 'second']);
    assert.equal(value.missing, null);
    assert.equal(value.empty, null);
    assert.deepEqual(value.noMatches, []);
});

test('typed section queries preserve their discriminator, original references and absence semantics', t => {
    const singles = { findHijpassSection: 'hijpass', findHijserverSection: 'hijserver', findShuntSection: 'shunt',
        findDnsSection: 'dns', findFirewallSection: 'firewall', findRuleSection: 'rule', findDnsmasqSection: 'dnsmasq' };
    const multiples = { filterProxyNodeSections: 'proxy_node', filterServerNodeSections: 'server_node',
        filterShuntRouteRuleSections: 'shunt_route_rule', filterShuntDnsNodeSections: 'shunt_dns_node' };
    const names = Object.keys({ ...singles, ...multiples });
    const sections = Object.values({ ...singles, ...multiples }).flatMap(type => [
        { '.type': type, '.name': type + '-first', enabled: '1' },
        { '.type': type, '.name': type + '-second', enabled: '0' },
    ]);
    const calls = [
        ...Object.entries(singles).map(([name, type]) => `{
            let found = ${name}(sections);
            found.marker = ${JSON.stringify(type)};
            push(results, { type: found['.type'], id: found['.name'], missing: ${name}([]),
                original: filter(sections, section => section['.name'] == found['.name'])[0].marker });
        }`),
        ...Object.entries(multiples).map(([name, type]) => `{
            let matches = ${name}(sections);
            matches[0].marker = ${JSON.stringify(type)};
            push(results, { ids: map(matches, section => section['.name']), empty: ${name}([]),
                original: filter(sections, section => section['.name'] == matches[0]['.name'])[0].marker });
        }`),
    ];
    const result = execute(t, `import { ${names.join(', ')} } from ${modulePath('usr/share/ucode/hijpass/config/sections.uc')};
let sections = ${JSON.stringify(sections)}, results = [];
${calls.join('\n')}
printf('%J', results);`);
    assert.equal(result.status, 0, result.stderr);
    const results = JSON.parse(result.stdout);
    Object.values(singles).forEach((type, index) => assert.deepEqual(results[index], {
        type, id: type + '-first', missing: null, original: type,
    }));
    Object.values(multiples).forEach((type, index) => assert.deepEqual(results[index + Object.keys(singles).length], {
        ids: [type + '-first', type + '-second'], empty: [], original: type,
    }));
});

test('absent optional services produce no instances, DNS settings or firewall rules', () => {
    for (const [action, expected] of [['plan', { instances: [] }], ['server-plan', { instances: [], ports: { tcp: [], udp: [] } }],
        ['dns-options', null], ['firewall', '']]) {
        const result = run('tests/backend/runtime.uc', [], { action, sections: [], dnsmasq: null });
        assert.equal(result.status, 0, result.stderr);
        assert.deepEqual(JSON.parse(result.stdout), expected);
    }
});

test('a missing shunt is optional for rendering but a missing target ID fails explicitly', () => {
    const sections = [{ '.type': 'hijpass', '.name': 'global', enabled: '1' }];
    const all = config(['render', '--stdin'], sections);
    assert.equal(all.status, 0, all.stderr);
    assert.deepEqual(JSON.parse(all.stdout), { nodes: {} });
    const preview = config(['render', '--stdin', '--target', 'cfg123456'], sections);
    assert.notEqual(preview.status, 0);
    assert.match(preview.stderr, /target section not found/);
});

test('a missing DNS section does not enable DNS-maintained firewall sets', () => {
    const result = run('tests/backend/runtime.uc', [], { action: 'firewall',
        sections: [{ '.type': 'firewall', '.name': 'firewall', proxy_port: '10001', tproxy_proto: 'tcp,udp' }],
        state: { wan: [], local4: [], local6: [], dns4: [], dns6: [] } },
    { paths: { '/etc/hijpass/firewall.ut': path.join(root, 'root/etc/hijpass/firewall.ut') } });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /table inet hijpass/);
    assert.doesNotMatch(result.stdout, /set dns(?:proxy|bypass)[46]list/);
});

test('explicit rule updates reject a missing rule section, DNS extraction remains optional', t => {
    const result = execute(t, `import { updatePlan, dnsPlan } from ${modulePath('usr/lib/hijpass/rules/rules.uc')};
let message;
try { updatePlan([], 'all'); } catch (e) { message = e.message; }
printf('%J', { message, dns: dnsPlan([]) });`);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), { message: 'rule section is missing', dns: { jobs: [] } });
});

test('chinadns uses its default dnsmasq port when the optional section is absent', () => {
    const result = run('tests/backend/runtime.uc', [], { action: 'dns-options', dnsmasq: null,
        sections: [{ '.type': 'dns', '.name': 'dns', dns_service: 'chinadns-ng', cdg_port: '5353',
            direct_dns: 'dnsmasq', proxy_dns: '1.1.1.1' }] });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).direct, '127.0.0.1#53');
});

test('Xray routing rejects a missing default outbound before building its config', t => {
    const result = execute(t, `import { build } from ${modulePath('usr/share/ucode/hijpass/coreconfig/xray/routing.uc')};
build({ final: 'missing' }, { nodes: [] });`);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /default outbound "missing" is missing/);
});
