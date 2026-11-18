const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { config, root, interpreter, run, withConfig } = require('./helpers.cjs');
const fixtures = require('./testdata/compatibility.json');

function rpc(method, sections, target) {
    const result = config(['call', method], { sections: JSON.stringify(sections), target });
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
}
for (const fixture of fixtures) {
    test(`配置兼容：${fixture.name}`, () => {
        let sections = fixture.sections;
        if (sections.some(s => s.core === 'xray' && s.transport_type === 'http')) {
            // 历史 TS 样本保持原始输入；先调用真实安装迁移，再比较生成结果。
            sections = withConfig(sections, directory => {
                const migrated = run('root/usr/lib/hijpass/install/migrate.uc', ['--configdir', directory]);
                assert.equal(migrated.status, 0, migrated.stderr);
                const read = run('tests/backend/runtime.uc', [], { action: 'read', directory });
                assert.equal(read.status, 0, read.stderr);
                return JSON.parse(read.stdout);
            });
        }
        const result = config(['render', '--stdin'], sections);
        assert.equal(result.status, 0, result.stderr);
        const generated = JSON.parse(result.stdout);
        // 样本直接来自迁移前的 TS；严格比较默认值、数组、时长和规则顺序。
        assert.deepEqual(generated, fixture.expected);
        assert.deepEqual(rpc('render', sections), generated);
        assert.deepEqual(rpc('validate', sections), { ok: true });
        const shuntID = sections.find(section => section['.type'] === 'shunt')?.['.name'];
        for (const [id, expected] of [...Object.entries(generated.nodes), ...(generated.shunt ? [[shuntID, generated.shunt]] : [])]) {
            assert.deepEqual(rpc('render', sections, id), { config: expected });
            const preview = config(['render', '--stdin', '--target', id], sections);
            assert.equal(preview.status, 0, preview.stderr);
            assert.deepEqual(JSON.parse(preview.stdout), expected);
        }
    });
}

function node(id, options = {}) {
    return { '.name': id, '.type': 'proxy_node', name: id, enabled: '1', core: 'sing-box', type: 'shadowsocks',
        server: 'example.org', server_port: '443', listen_port: '10001', socks_port: '10002', ...options };
}

test('分流预览使用实际 section ID，并解析全部启用的代理出口', () => {
    for (const core of ['sing-box', 'xray']) {
        const sections = structuredClone(fixtures.find(f => f.name === `${core}-shunt-default`).sections);
        const shunt = sections.find(section => section['.type'] === 'shunt');
        shunt['.name'] = 'cfg123456';
        shunt.default_proxy_node = '出口 A';
        sections.push(node('proxy-id', { name: '出口 A' }));
        const generated = rpc('render', sections);
        assert.equal(generated.error, undefined);
        assert.deepEqual(rpc('render', sections, shunt['.name']), { config: generated.shunt });
        const preview = config(['render', '--stdin', '--target', shunt['.name']], sections);
        assert.equal(preview.status, 0, preview.stderr);
        assert.deepEqual(JSON.parse(preview.stdout), generated.shunt);
        assert.match(rpc('render', sections, 'shunt').error, /not found/);

        shunt.enabled = '0';
        assert.equal(rpc('render', sections).shunt, undefined);
        assert.deepEqual(rpc('render', sections, shunt['.name']), { config: generated.shunt });
    }
});

test('指定分流 ID 使用该 section，不会读取第一个分流的设置', () => {
    const first = structuredClone(fixtures.find(f => f.name === 'sing-box-shunt-default').sections);
    const second = fixtures.find(f => f.name === 'xray-shunt-default');
    const selected = { ...second.sections.find(section => section['.type'] === 'shunt'), '.name': 'second-shunt' };
    assert.deepEqual(rpc('render', [...first, selected], selected['.name']), { config: second.expected.shunt });
});

test('target 只表示 ID，名为 shunt 的关闭代理仍可独立预览', () => {
    const sections = [node('shunt', { name: 'display-name', enabled: '0' }), node('broken', { type: 'invalid' }),
        { '.name': 'global', '.type': 'hijpass', enabled: '1' }];
    const preview = rpc('render', sections, 'shunt');
    assert.equal(preview.error, undefined);
    assert.equal(preview.config.outbounds[0].type, 'shadowsocks');
    assert.match(rpc('render', sections, 'display-name').error, /not found/);
    assert.match(rpc('render', sections, 'global').error, /unsupported target section type.*hijpass/);
});

test('CLI 按原生 UCI 生成的匿名 section ID 预览分流', () => {
    const fixture = fixtures.find(f => f.name === 'sing-box-shunt-default');
    const sections = structuredClone(fixture.sections);
    delete sections.find(section => section['.type'] === 'shunt')['.name'];
    withConfig(sections, directory => {
        const read = run('tests/backend/runtime.uc', [], { action: 'read', directory });
        assert.equal(read.status, 0, read.stderr);
        const id = JSON.parse(read.stdout).find(section => section['.type'] === 'shunt')['.name'];
        const preview = config(['render', '--configdir', directory, '--target', id]);
        assert.equal(preview.status, 0, preview.stderr);
        assert.deepEqual(JSON.parse(preview.stdout), fixture.expected.shunt);
    });
});

test('核心选择与协议独立，缺省 VLESS 使用 sing-box，显式 Xray 保持不变', () => {
    for (const core of [undefined, '', 'sing-box', 'xray']) {
        const section = node('a', { core, type: 'vless', uuid: '11111111-1111-4111-8111-111111111111' });
        const generated = rpc('render', [section]).nodes.a.outbounds[0];
        if (core === 'xray') assert.equal(generated.protocol, 'vless');
        else assert.equal(generated.type, 'vless');
    }
    for (const core of [undefined, '', 'sing-box', 'xray'])
        assert.match(rpc('render', [node('a', { core, type: 'custom', command: 'program' })]).error, /unsupported proxy type/);
});

test('自定义配置只读取命令和公共字段，不解释残留核心、协议及其依赖', () => {
    for (const type of [undefined, 'custom', 'vless', 'load_balance']) {
        const section = node('a', { config_type: 'custom', core: 'unused', type, command: 'program --config {conf_path}',
            server_port: 'invalid', transport_grpc_idle_timeout: 'invalid', member_node: ['missing'], upstream_proxy_node: 'missing' });
        assert.deepEqual(rpc('render', [section]), { nodes: {} });
        assert.deepEqual(rpc('validate', [section]), { ok: true });
    }
    for (const command of [undefined, '', ' \t\n '])
        assert.match(rpc('render', [node('a', { config_type: 'custom', command })]).error, /has no command/);
});

test('业务转换不再识别旧核心名称或根据旧 custom 字段推断配置类型', () => {
    for (const core of ['singbox', 'custom'])
        assert.match(rpc('render', [node('a', { core, command: 'program' })]).error, /unsupported core/);
    assert.match(rpc('render', [node('a', { config_type: 'invalid' })]).error, /unsupported config_type/);
    assert.match(rpc('render', [node('a', { core: 'xray', type: 'vless', transport_type: 'http' })]).error,
        /unsupported Xray transport "http"/);
});

test('自定义命令节点仍可通过其本地 SOCKS 端口接入上游和负载均衡', () => {
    const custom = node('custom', { config_type: 'custom', type: 'load_balance', command: 'program',
        member_node: ['missing'], upstream_proxy_node: 'missing' });
    for (const type of ['shadowsocks', 'load_balance']) {
        const generated = rpc('render', [custom, node('a', { type, listen_port: '10003', socks_port: '10004',
            upstream_proxy_node: type === 'shadowsocks' ? 'custom' : undefined, member_node: ['custom'] })]);
        assert.deepEqual(Object.keys(generated.nodes), ['a']);
        assert.ok(generated.nodes.a.outbounds.some(outbound => outbound.type === 'socks' && outbound.server_port === 10002));
    }
});

test('预检拒绝缺失引用、重复名称、循环、过长代理链及监听端口冲突', () => {
    const cases = [
        [[node('a', { upstream_proxy_node: 'missing' })], /missing/],
        [[node('a', { upstream_proxy_node: 'a' })], /cycle/],
        [[node('a'), node('b', { name: 'a', listen_port: '10003', socks_port: '10004' })], /duplicate proxy name/],
        [[node('a'), node('b')], /shared/],
        [[node('a', { server_port: '65536' })], /invalid port/],
        [[node('a', { multiplex_enabled: 'true' })], /invalid UCI boolean/],
        [[node('a', { multiplex_max_streams: '2147483648' })], /range/],
        [Array.from({ length: 4 }, (_, i) => node(String(i), {
            listen_port: String(10001 + i * 2), socks_port: String(10002 + i * 2),
            ...(i < 3 ? { upstream_proxy_node: String(i + 1) } : {}),
        })), /three nodes/],
        [[node('a', { type: 'load_balance' })], /no members/],
        [[node('a', { type: 'load_balance', member_node: ['b', 'b'] }), node('b', { listen_port: '10003', socks_port: '10004' })], /duplicate load balancing member/],
    ];
    for (const [sections, pattern] of cases) {
        assert.match(rpc('render', sections).error, pattern);
        const result = config(['render', '--stdin'], sections);
        assert.notEqual(result.status, 0);
        assert.equal(result.stdout, '');
        assert.match(result.stderr, pattern);
    }
});

test('最新版 Xray 不再支持 Shadowsocks UDP-over-TCP', () => {
    assert.match(rpc('render', [node('a', { core: 'xray', udp_over_tcp: '1' })]).error,
        /no longer supports.*udp_over_tcp/);
});
test('单节点预览只校验可达依赖，关闭服务仍可保存未完成配置', () => {
    const sections = [node('a'), node('broken', { type: 'invalid' })];
    assert.ok(rpc('render', sections, 'a').config);
    assert.match(rpc('render', sections).error, /unsupported proxy type/);
    sections.unshift({ '.name': 'global', '.type': 'hijpass', enabled: '0' });
    assert.deepEqual(rpc('validate', sections), { ok: true });
    sections[1].listen_port = 10001;
    assert.match(rpc('validate', sections).error, /string/);
});
test('原生 UCI 可独立读取，保留匿名配置段与 list 顺序', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hijpass-uci-'));
    try {
        fs.writeFileSync(path.join(dir, 'hijpass'), `config hijpass\n option enabled '1'\nconfig proxy_node 'a'\n option enabled '1'\n option core 'sing-box'\n option type 'shadowsocks'\n option server 'example.org'\n option server_port '443'\n option listen_port '10001'\n option socks_port '10002'\n`);
        const result = config(['render', '--configdir', dir]);
        assert.equal(result.status, 0, result.stderr);
        assert.ok(JSON.parse(result.stdout).nodes.a);
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
test('RPC 保持契约，非法显式快照不会退回本机 UCI', () => {
    assert.deepEqual(JSON.parse(config(['list']).stdout), { render: { sections: '', target: '' }, validate: { sections: '' } });
    assert.match(rpc('generate', []).error, /unknown method/);
    assert.ok(JSON.parse(config(['call', 'render'], { sections: '' }).stdout).error);
    assert.match(rpc('render', {}).error, /unmarshal/);
    assert.match(rpc('render', [node('a')], 'missing').error, /not found/);
    assert.match(rpc('render', [node('a', { config_type: 'custom', command: 'program' })], 'a').error, /custom/);
});

test('输入读取与 JSON 解析失败保留 RPC/CLI 错误格式，并限制输入大小', () => {
    for (const input of ['', '{broken', 'null', '[]', JSON.stringify({ sections: '{}' }), JSON.stringify({ sections: 1 })]) {
        const result = config(['call', 'render'], undefined, { input });
        assert.equal(result.status, 0, result.stderr);
        assert.equal(typeof JSON.parse(result.stdout).error, 'string');
        assert.equal(result.stderr, '');
    }
    const invalid = config(['render', '--stdin'], undefined, { input: '{broken' });
    assert.equal(invalid.status, 1);
    assert.equal(invalid.stdout, '');
    assert.ok(invalid.stderr);

    const limit = 4 * 1024 * 1024;
    const input = JSON.stringify([{ '.name': 'global', '.type': 'hijpass', enabled: '0' }]);
    const accepted = config(['validate', '--stdin'], undefined, { input: input.padEnd(limit), maxBuffer: limit });
    assert.equal(accepted.status, 0, accepted.stderr);
    assert.deepEqual(JSON.parse(accepted.stdout), { ok: true });
    const oversized = config(['call', 'render'], undefined, { input: ' '.repeat(limit + 1), maxBuffer: limit });
    assert.match(JSON.parse(oversized.stdout).error, /exceeds 4 MiB/);

    // 关闭 stdin，验证读取失败不会被当成空快照，也不会绕过 RPC 错误边界。
    const closed = spawnSync('/bin/sh', ['-c', 'exec "$@" <&-', 'sh', interpreter,
        '-S', '-L', path.join(root, 'root/usr/share/ucode'), '--', path.join(root, 'root/usr/bin/hijpass-config'), 'call', 'render'],
        { encoding: 'utf8' });
    assert.equal(closed.status, 0, closed.stderr);
    assert.match(JSON.parse(closed.stdout).error, /cannot read input/);
});

test('VLESS 显式安全选项覆盖旧字段，TLS 可省略 SNI，旧节点保持原行为', () => {
    for (const core of ['sing-box', 'xray']) {
        const base = node('a', { core, type: 'vless', uuid: '11111111-1111-4111-8111-111111111111' });
        const outbound = extra => rpc('render', [{ ...base, ...extra }]).nodes.a.outbounds[0];
        const mode = out => core === 'xray' ? out.streamSettings.security : out.tls?.reality ? 'reality' : out.tls ? 'tls' : 'none';
        assert.equal(mode(outbound({})), core === 'xray' ? 'none' : 'tls');
        assert.equal(mode(outbound({ tls_server_name: 'example.org' })), 'tls');
        const none = outbound({ security: 'none', tls_server_name: 'stale.example', tls_reality_enabled: '1' });
        assert.equal(mode(none), 'none');
        const tls = outbound({ security: 'tls', tls_reality_enabled: '1' });
        assert.equal(mode(tls), 'tls');
        assert.equal(core === 'xray' ? tls.streamSettings.tlsSettings.serverName : tls.tls.server_name, 'example.org');
        for (const security of [undefined, 'reality']) {
            assert.equal(mode(outbound({ security, tls_reality_enabled: '1', tls_reality_public_key: 'test-key' })), 'reality');
        }
        assert.match(rpc('render', [{ ...base, security: 'invalid' }]).error, /unsupported VLESS security/);
    }
});

test('Xray SS and VLESS emit native Mux settings independently of sing-box multiplex', () => {
    for (const type of ['shadowsocks', 'vless']) {
        const proxy = node('mux', { core: 'xray', type, security: 'none', method: 'aes-128-gcm',
            password: 'test', uuid: '11111111-1111-4111-8111-111111111111' });
        const render = options => rpc('render', [{ ...proxy, ...options }], 'mux');
        assert.equal(render({ multiplex_enabled: '1' }).config.outbounds[0].mux, undefined);
        assert.deepEqual(render({ mux_enabled: '1' }).config.outbounds[0].mux,
            { enabled: true, concurrency: 8, xudpConcurrency: 16, xudpProxyUDP443: 'reject' });
        for (const value of ['-1', '0', '128']) for (const policy of ['reject', 'allow', 'skip']) {
            assert.deepEqual(render({ mux_enabled: '1', mux_concurrency: value,
                mux_xudp_concurrency: '1024', mux_udp443: policy }).config.outbounds[0].mux,
                { enabled: true, concurrency: Number(value), xudpConcurrency: 1024, xudpProxyUDP443: policy });
        }
        for (const options of [{ mux_concurrency: '1.5' }, { mux_concurrency: '-2' }, { mux_concurrency: '129' },
            { mux_xudp_concurrency: '1025' }, { mux_udp443: 'invalid' }]) {
            assert.ok(render({ mux_enabled: '1', ...options }).error);
            assert.equal(render({ mux_enabled: '0', ...options }).config.outbounds[0].mux, undefined);
        }
        const sing = render({ core: 'sing-box', mux_enabled: '1', mux_concurrency: 'invalid', multiplex_enabled: '1' });
        assert.equal(sing.config.outbounds[0].mux, undefined);
        assert.equal(sing.config.outbounds[0].multiplex.enabled, true);
    }
});

test('Xray Vision permits XUDP with TCP Mux disabled, and rejects TCP Mux', () => {
    const proxy = node('vision', { core: 'xray', type: 'vless', security: 'tls',
        uuid: '11111111-1111-4111-8111-111111111111', flow: 'xtls-rprx-vision', mux_enabled: '1' });
    assert.match(rpc('render', [proxy], 'vision').error, /Vision requires/);
    assert.deepEqual(rpc('render', [{ ...proxy, mux_concurrency: '-1', mux_xudp_concurrency: '16' }], 'vision').config.outbounds[0].mux,
        { enabled: true, concurrency: -1, xudpConcurrency: 16, xudpProxyUDP443: 'reject' });
});

test('sing-box client padding is emitted only when enabled', () => {
    const proxy = node('padding', { method: 'aes-128-gcm', password: 'test', multiplex_enabled: '1' });
    assert.equal(rpc('render', [proxy], 'padding').config.outbounds[0].multiplex.padding, undefined);
    assert.equal(rpc('render', [{ ...proxy, multiplex_padding: '1' }], 'padding').config.outbounds[0].multiplex.padding, true);
});
