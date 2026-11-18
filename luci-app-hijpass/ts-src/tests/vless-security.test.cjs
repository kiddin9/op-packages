const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
function load(file) {
    const exports = {};
    vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    }).outputText, { exports, URLSearchParams, _: text => text,
        require: name => load(path.resolve(path.dirname(file), name + '.ts')) });
    return exports;
}
const { ProxyShareLinkUtils: links } = load(path.resolve(__dirname, '../utils/feature/proxy/share-link.ts'));
const base = { type: 'vless', uuid: '11111111-1111-4111-8111-111111111111', server: 'example.org', server_port: '443' };
test('VLESS share links preserve explicit security with empty SNI and default TCP', () => {
    for (const core of ['sing-box', 'xray']) for (const security of ['none', 'tls', 'reality']) {
        const section = { ...base, core, security, tls_reality_public_key: 'test-key' };
        const link = links.generate(section);
        const imported = links.parse(link, core).values;
        assert.equal(imported.security, security);
        assert.equal(imported.transport_type, '');
        assert.equal(imported.tls_server_name, '');
        assert.equal(imported.tls_reality_public_key, security === 'reality' ? 'test-key' : '');
    }
    const link = links.generate({ ...base, security: 'none', tls_server_name: 'stale.example', tls_reality_enabled: '1', tls_insecure: '1' });
    assert.ok(!link.includes('sni=') && !link.includes('allowInsecure=') && !link.includes('pbk='));
});
test('VLESS legacy links reflect actual core behavior; missing link security means none', () => {
    assert.equal(links.parse(links.generate({ ...base, core: 'sing-box' }), 'sing-box').values.security, 'tls');
    assert.equal(links.parse(links.generate({ ...base, core: 'xray' }), 'xray').values.security, 'none');
    assert.equal(links.parse('vless://' + base.uuid + '@example.org:443', 'sing-box').values.security, 'none');
    assert.throws(() => links.parse('vless://' + base.uuid + '@example.org:443?security=invalid', 'xray'), /Invalid VLESS/);
});
