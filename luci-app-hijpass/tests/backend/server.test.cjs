const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { run } = require('./helpers.cjs');
const uuid = 'b837b692-739d-4c1c-8901-637b957295fb';
const global = { '.name': 'global', '.type': 'hijserver', enabled: '1' };
const node = (type, core, overrides = {}) => ({ '.name': 'node', '.type': 'server_node', name: 'test',
    type, core, enabled: '1', allow_firewall: '1', listen: '127.0.0.1', listen_port: '16443',
    method: 'aes-128-gcm', password: 'test-password', uuid, certificate_path: '/tmp/test-cert.pem',
    key_path: '/tmp/test-key.pem', ...overrides });
function invoke(action, values, extra) { return run('tests/backend/runtime.uc', [], { action, ...values }, extra); }
function result(action, values) {
    const process = invoke(action, values);
    assert.equal(process.status, 0, process.stderr);
    return JSON.parse(process.stdout);
}
for (const core of ['sing-box', 'xray']) for (const type of ['shadowsocks', 'hysteria2', 'vless']) {
    test(`${core} ${type}: generate inbound, credentials, direct outbound and standard core argv`, () => {
        const section = node(type, core);
        const config = result('server-render', { section });
        const inbound = config.inbounds[0];
        assert.equal(inbound.listen, '127.0.0.1');
        assert.equal(core === 'xray' ? inbound.port : inbound.listen_port, 16443);
        assert.equal(core === 'xray' ? inbound.protocol : inbound.type, core === 'xray' && type === 'hysteria2' ? 'hysteria' : type);
        if (type === 'shadowsocks') assert.equal((inbound.settings || inbound).password, section.password);
        else if (type === 'hysteria2') {
            assert.equal(core === 'xray' ? inbound.settings.clients[0].auth : inbound.users[0].password, section.password);
            assert.equal(core === 'xray' ? inbound.streamSettings.tlsSettings.certificates[0].certificateFile : inbound.tls.certificate_path, section.certificate_path);
        } else assert.equal(core === 'xray' ? inbound.settings.clients[0].id : inbound.users[0].uuid, uuid);
        const plan = result('server-plan', { sections: [global, section] });
        assert.deepEqual(plan.instances[0].command, [core, 'run', '-c', '/etc/hijpass/server/test-node.json']);
        assert.equal(plan.instances[0].check[0], core);
        assert.deepEqual(plan.instances[0].env, []);
        assert.deepEqual(plan.ports, { tcp: type === 'hysteria2' ? [] : [16443], udp: type === 'vless' ? [] : [16443] });
    });
}
for (const core of ['sing-box', 'xray']) test(`${core}: VLESS transports and REALITY use inbound credentials`, () => {
    for (const transport of ['ws', 'grpc']) {
        const config = result('server-render', { section: node('vless', core, { transport, ws_path: '/test', grpc_service_name: 'test' }) });
        const inbound = config.inbounds[0];
        assert.equal(core === 'xray' ? inbound.streamSettings.network : inbound.transport.type, transport);
    }
    const section = node('vless', core, { security: 'reality', flow: 'xtls-rprx-vision', reality_server: 'example.com',
        server_name: 'example.com', reality_private_key: 'A'.repeat(43), reality_short_id: 'ab0123' });
    const inbound = result('server-render', { section }).inbounds[0];
    const reality = core === 'xray' ? inbound.streamSettings.realitySettings : inbound.tls.reality;
    assert.equal(core === 'xray' ? reality.privateKey : reality.private_key, section.reality_private_key);
    assert.deepEqual(core === 'xray' ? reality.shortIds : reality.short_id, ['ab0123']);
});

test('server validation rejects incomplete or incompatible settings without echoing secrets', () => {
    const cases = [
        [node('custom', 'xray', { command: 'touch /tmp/should-not-run' }), /select a server protocol/],
        [node('shadowsocks', 'bad-core'), /unsupported server core/],
        [node('shadowsocks', 'sing-box', { password: '' }), /password is required/],
        [node('shadowsocks', 'sing-box', { method: '2022-blake3-aes-128-gcm' }), /16-byte key/],
        [node('shadowsocks', 'sing-box', { listen_port: '0' }), /invalid port/],
        [node('hysteria2', 'sing-box', { certificate_path: '' }), /certificate_path/],
        [node('vless', 'xray', { uuid: 'invalid' }), /UUID/],
        [node('vless', 'sing-box', { security: 'none', flow: 'xtls-rprx-vision' }), /Vision requires/],
        [node('vless', 'xray', { security: 'reality', transport: 'ws' }), /Xray REALITY only supports RAW, XHTTP and gRPC/],
    ];
    for (const [section, expected] of cases) {
        const process = invoke('server-render', { section });
        assert.notEqual(process.status, 0);
        assert.match(process.stderr, expected);
        assert.ok(!process.stderr.includes('test-password'));
    }
    const valid = node('shadowsocks', 'sing-box', { method: '2022-blake3-aes-128-gcm', password: Buffer.alloc(16, 1).toString('base64') });
    assert.equal(result('server-render', { section: valid }).inbounds[0].password, valid.password);
});

test('server generation skips disabled nodes, validates duplicates and writes generated JSON privately', t => {
    const directory = fs.mkdtempSync('/tmp/hijpass-server-test-');
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const section = node('shadowsocks', 'sing-box', { command: 'false', procd_env: ['UNUSED=value'] });
    const sections = [global, section, node('custom', 'xray', { '.name': 'old', enabled: '0' })];
    const write = invoke('server-write', { sections }, { paths: { '/etc/hijpass/server': directory } });
    assert.equal(write.status, 0, write.stderr);
    const file = path.join(directory, 'test-node.json');
    assert.equal(JSON.parse(fs.readFileSync(file)).inbounds[0].type, 'shadowsocks');
    assert.equal(fs.statSync(file).mode & 0o777, 0o600);
    assert.equal(fs.readdirSync(directory).length, 1);
    assert.deepEqual(result('server-generate', { sections: [{ ...global, enabled: '0' }, section] }), []);
    const duplicate = invoke('server-generate', { sections: [global, section, { ...section, '.name': 'another' }] });
    assert.notEqual(duplicate.status, 0);
    assert.match(duplicate.stderr, /duplicate listen port/);
});

test('server RPC validates hijserver independently and rejects custom JSON writes', () => {
    const sections = [global, node('shadowsocks', 'xray')];
    const validate = request => JSON.parse(run('root/usr/lib/hijpass/rpc/data.uc', ['call', 'server_validate'], request).stdout);
    assert.deepEqual(validate({ sections: JSON.stringify(sections) }), { ok: true });
    assert.match(validate({ sections: JSON.stringify([global, node('custom', 'xray')]) }).error, /select a server protocol/);
    const write = run('root/usr/lib/hijpass/rpc/data.uc', ['call', 'editor_write'], { resource: 'server_config', section: 'node', content: '{}' });
    assert.match(JSON.parse(write.stdout).error, /unknown RPC method/);
});

test('Xray XHTTP servers generate all modes with TLS or REALITY and keep matching HTTP fields', () => {
    for (const security of ['none', 'tls', 'reality']) for (const mode of ['auto', 'packet-up', 'stream-up', 'stream-one']) {
        const section = node('vless', 'xray', { transport: 'xhttp', security, xhttp_mode: mode,
            xhttp_host: 'server.example', xhttp_path: '/proxy', xhttp_method: 'PUT',
            reality_server: 'server.example', server_name: 'server.example', reality_private_key: 'A'.repeat(43) });
        const stream = result('server-render', { section }).inbounds[0].streamSettings;
        assert.equal(stream.network, 'xhttp');
        assert.equal(stream.security, security);
        assert.deepEqual(stream.xhttpSettings, { host: 'server.example', path: '/proxy', mode, uplinkHTTPMethod: 'PUT' });
        assert.deepEqual(result('server-plan', { sections: [global, section] }).ports, { tcp: [16443], udp: [] });
    }
    const stream = result('server-render', { section: node('vless', 'xray', { transport: 'xhttp' }) }).inbounds[0].streamSettings;
    assert.deepEqual(stream.xhttpSettings, { host: '', path: '/', mode: 'auto' });
    const grpc = result('server-render', { section: node('vless', 'xray', { transport: 'grpc', grpc_service_name: 'test',
        security: 'reality', reality_server: 'server.example', server_name: 'server.example', reality_private_key: 'A'.repeat(43) }) });
    assert.equal(grpc.inbounds[0].streamSettings.security, 'reality');
});

test('XHTTP rejects unsupported core, invalid options and Vision instead of generating unusable configurations', () => {
    const cases = [
        [node('vless', 'sing-box', { transport: 'xhttp' }), /only supported by Xray/],
        [node('vless', 'xray', { transport: 'xhttp', xhttp_mode: 'unsupported' }), /invalid XHTTP mode/],
        [node('vless', 'xray', { transport: 'xhttp', xhttp_path: 'proxy' }), /path must start/],
        [node('vless', 'xray', { transport: 'xhttp', xhttp_method: 'PUT\r\nheader' }), /invalid HTTP method/],
        [node('vless', 'xray', { transport: 'xhttp', xhttp_host: 'host\r\nheader' }), /invalid XHTTP Host/],
        [node('vless', 'xray', { transport: 'xhttp', flow: 'xtls-rprx-vision' }), /Vision requires TCP/],
    ];
    for (const [section, message] of cases) {
        const process = invoke('server-render', { section });
        assert.notEqual(process.status, 0);
        assert.match(process.stderr, message);
    }
});

test('VLESS omitted or empty transport uses TCP for both cores', () => {
    for (const core of ['sing-box', 'xray']) {
        const generate = transport => result('server-render', { section: node('vless', core, { transport }) });
        assert.deepEqual(generate(''), generate('tcp'));
        assert.deepEqual(generate(undefined), generate('tcp'));
    }
});

test('sing-box HTTP server preserves host lists, path, method and server idle timeout', () => {
    for (const security of ['none', 'tls']) {
        const section = node('vless', 'sing-box', { transport: 'http', security,
            http_host: ['one.example', 'two.example'], http_path: '/proxy', http_method: 'PUT', http_idle_timeout: '1m30s' });
        const inbound = result('server-render', { section }).inbounds[0];
        assert.deepEqual(inbound.transport, { type: 'http', host: ['one.example', 'two.example'],
            path: '/proxy', method: 'PUT', idle_timeout: '1m30s' });
        assert.equal(!!inbound.tls, security === 'tls');
        assert.deepEqual(result('server-plan', { sections: [global, section] }).ports, { tcp: [16443], udp: [] });
    }
    const defaults = result('server-render', { section: node('vless', 'sing-box', { transport: 'http' }) });
    assert.deepEqual(defaults.inbounds[0].transport, { type: 'http', host: [], path: '/' });
    const single = result('server-render', { section: node('vless', 'sing-box', { transport: 'http', http_host: 'one.example' }) });
    assert.deepEqual(single.inbounds[0].transport.host, ['one.example']);
});

test('HTTPUpgrade server supports both cores with optional Host verification and TLS', () => {
    for (const core of ['sing-box', 'xray']) for (const security of ['none', 'tls']) {
        const section = node('vless', core, { transport: 'httpupgrade', security,
            httpupgrade_host: 'server.example', httpupgrade_path: '/upgrade' });
        const inbound = result('server-render', { section }).inbounds[0];
        if (core === 'xray') {
            assert.equal(inbound.streamSettings.network, 'httpupgrade');
            assert.equal(inbound.streamSettings.security, security);
            assert.deepEqual(inbound.streamSettings.httpupgradeSettings, { host: 'server.example', path: '/upgrade' });
        } else {
            assert.equal(!!inbound.tls, security === 'tls');
            assert.deepEqual(inbound.transport, { type: 'httpupgrade', host: 'server.example', path: '/upgrade' });
        }
        assert.deepEqual(result('server-plan', { sections: [global, section] }).ports, { tcp: [16443], udp: [] });
        const defaults = result('server-render', { section: node('vless', core, { transport: 'httpupgrade' }) }).inbounds[0];
        const transport = core === 'xray' ? defaults.streamSettings.httpupgradeSettings : defaults.transport;
        assert.equal(transport.path, '/');
        assert.equal(transport.host, '');
    }
});

test('HTTP transports reject unsupported cores, REALITY, Vision and malformed matching fields', () => {
    const cases = [
        ['xray', { transport: 'http' }, /only supported by sing-box/],
        ['sing-box', { transport: 'http', security: 'reality' }, /REALITY requires TCP/],
        ['sing-box', { transport: 'httpupgrade', security: 'reality' }, /REALITY requires TCP/],
        ['xray', { transport: 'httpupgrade', security: 'reality' }, /REALITY only supports/],
        ['sing-box', { transport: 'http', flow: 'xtls-rprx-vision' }, /Vision requires TCP/],
        ['xray', { transport: 'httpupgrade', flow: 'xtls-rprx-vision' }, /Vision requires TCP/],
        ['sing-box', { transport: 'http', http_path: 'proxy' }, /HTTP path/],
        ['xray', { transport: 'httpupgrade', httpupgrade_path: '/bad\r\npath' }, /HTTP path/],
        ['sing-box', { transport: 'http', http_host: ['valid.example', 123] }, /invalid HTTP Host/],
        ['sing-box', { transport: 'http', http_host: 'bad\nHost' }, /invalid HTTP Host/],
        ['xray', { transport: 'httpupgrade', httpupgrade_host: 'bad host' }, /invalid HTTPUpgrade Host/],
        ['sing-box', { transport: 'http', http_method: 'bad method' }, /invalid HTTP method/],
        ['sing-box', { transport: 'http', http_idle_timeout: '-1s' }, /invalid duration/],
    ];
    for (const [core, overrides, message] of cases) {
        const process = invoke('server-render', { section: node('vless', core, overrides) });
        assert.notEqual(process.status, 0);
        assert.match(process.stderr, message);
    }
});

for (const type of ['shadowsocks', 'vless']) test(`sing-box ${type}: inbound multiplex options and disabled defaults`, () => {
    const section = node(type, 'sing-box');
    const render = options => result('server-render', { section: { ...section, ...options } }).inbounds[0];
    assert.equal(render({}).multiplex, undefined);
    assert.deepEqual(render({ multiplex_enabled: '1' }).multiplex, { enabled: true, padding: false });
    assert.deepEqual(render({ multiplex_enabled: '1', multiplex_padding: '1', multiplex_brutal_enabled: '1',
        multiplex_brutal_up_mbps: '100', multiplex_brutal_down_mbps: '200', multiplex_protocol: 'invalid' }).multiplex,
        { enabled: true, padding: true, brutal: { enabled: true, up_mbps: 100, down_mbps: 200 } });
    assert.equal(render({ multiplex_enabled: '0', multiplex_brutal_up_mbps: 'invalid' }).multiplex, undefined);
    assert.equal(render({ core: 'xray', multiplex_enabled: '1', multiplex_brutal_up_mbps: 'invalid' }).multiplex, undefined);
    for (const bandwidth of ['', '0', '-1', '1.5']) {
        const response = invoke('server-render', { section: { ...section, multiplex_enabled: '1',
            multiplex_brutal_enabled: '1', multiplex_brutal_up_mbps: bandwidth, multiplex_brutal_down_mbps: '100' } });
        assert.notEqual(response.status, 0);
    }
});

test('Hysteria2 ignores stale sing-box multiplex options', () => {
    const inbound = result('server-render', { section: node('hysteria2', 'sing-box', {
        multiplex_enabled: '1', multiplex_brutal_up_mbps: 'invalid' }) }).inbounds[0];
    assert.equal(inbound.multiplex, undefined);
});
