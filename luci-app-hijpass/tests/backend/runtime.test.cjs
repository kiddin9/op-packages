const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { root, run, runShell, withConfig, shellRuntime } = require('./helpers.cjs');

function invoke(request, env) {
    const extra = { paths: request.paths, ...(env ? { env: { ...process.env, ...env } } : {}) };
    if (request.templatePath) extra.paths = { ...extra.paths, '/etc/hijpass/firewall.ut': request.templatePath };
    if (request.action === 'migrate') {
        const migrated = run('root/usr/lib/hijpass/install/migrate.uc', ['--configdir', request.directory], undefined, extra);
        if (migrated.status !== 0) return migrated;
        return run('tests/backend/runtime.uc', [], { action: 'read', directory: request.directory });
    }
    if (request.action === 'connect') return runShell('root/usr/lib/hijpass/network/network.sh',
        ['connect', request.url, request.timeout || '5'], extra);
    if (request.action === 'update') return withConfig(request.sections, directory =>
        runShell('root/usr/lib/hijpass/rules/update.sh', [request.group, '--configdir', directory], extra));
    if (request.action === 'clean-log') return withConfig(request.sections, directory =>
        runShell('root/usr/lib/hijpass/maintenance/logs.sh', [request.operation, ...(request.path ? [request.path] : []), '--configdir', directory], extra));
    if (request.action === 'cleanup') return runShell('root/usr/lib/hijpass/maintenance/cleanup.sh',
        [request.kind, request.id, request.name || ''], extra);
    return run('tests/backend/runtime.uc', [], request, extra);
}
function value(request, env) {
    const result = invoke(request, env);
    if ((request.action === 'update' || request.action === 'connect') && result.stdout) {
        const report = JSON.parse(result.stdout);
        assert.equal(result.status, report.success ? 0 : report.exit_code || 1, result.stderr);
        return report;
    }
    assert.equal(result.status, 0, result.stderr);
    if (!result.stdout) return true;
    return JSON.parse(result.stdout);
}
function fixture(t) {
    const directory = fs.mkdtempSync('/tmp/hijpass-runtime-test-');
    t.after(() => fs.rmSync(directory, { force: true, recursive: true }));
    return directory;
}
function script(directory, name, body) {
    fs.writeFileSync(path.join(directory, name), '#!/bin/sh\n' + body + '\n', { mode: 0o755 });
}
function node(id, options = {}) {
    return { '.name': id, '.type': 'proxy_node', name: id, enabled: '1', core: 'sing-box', type: 'shadowsocks',
        server: '192.0.2.10', server_port: '443', listen_port: '10001', socks_port: '10002', ...options };
}
const global = { '.name': 'global', '.type': 'hijpass', enabled: '1' };

// 模拟内核路由状态，执行真实 route.sh；不触碰宿主机的路由或规则。
function routeFixture(t) {
    const directory = fixture(t), state = path.join(directory, 'state'), calls = path.join(directory, 'calls');
    fs.writeFileSync(path.join(directory, 'ip'), '#!' + process.execPath + '\n' + String.raw`
const fs = require('node:fs');
const [family, kind, action, ...args] = process.argv.slice(2);
fs.appendFileSync(process.env.ROUTE_TEST_CALLS, JSON.stringify(process.argv.slice(2)) + '\n');
if (process.env.ROUTE_TEST_FAIL === [family, kind, action].join(' ')) process.exit(5);
const state = JSON.parse(fs.readFileSync(process.env.ROUTE_TEST_STATE));
const entries = state[family]?.[kind];
if (!entries || !['add', 'del'].includes(action)) process.exit(2);
const key = args.join(' '), position = entries.indexOf(key);
if (action === 'del') {
    if (position < 0) process.exit(1);
    entries.splice(position, 1);
} else {
    if (position >= 0) process.exit(2);
    entries.push(key);
}
fs.writeFileSync(process.env.ROUTE_TEST_STATE, JSON.stringify(state));
`, { mode: 0o755 });
    const runtime = shellRuntime(), script = path.join(directory, 'route.sh');
    // 新公共入口按安装布局运行；显式调用 mock，避免 BusyBox 内置 ip 绕过 PATH。
    fs.writeFileSync(script, fs.readFileSync(path.join(runtime, 'firewall/route.sh'), 'utf8')
        .replaceAll('ip "', `'${directory}/ip' "`));
    const env = { ...process.env, PATH: directory + ':' + path.join(runtime, 'testbin') + ':' + process.env.PATH,
        ROUTE_TEST_STATE: state, ROUTE_TEST_CALLS: calls };
    return {
        write: value => fs.writeFileSync(state, JSON.stringify(value)),
        read: () => JSON.parse(fs.readFileSync(state)),
        calls: () => fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').trim().split('\n').map(JSON.parse) : [],
        run: (args, failure) => spawnSync('/usr/bin/busybox', ['ash', script, ...args],
            { encoding: 'utf8', env: { ...env, ROUTE_TEST_FAIL: failure || '' } }),
    };
}

test('路由脚本重复重置或移除时仅修改 Hijpass 的 IPv4/IPv6 路由', t => {
    const route = routeFixture(t), ownRule = 'fwmark 0x1 table 233', ownRoute = 'local default dev lo table 233';
    const foreignRule = 'fwmark 0x2 table 234', foreignRoute = 'local default dev lo table 234';
    route.write(Object.fromEntries(['-4', '-6'].map(family => [family,
        { rule: [foreignRule, ownRule, ownRule], route: [foreignRoute, ownRoute] }])));
    for (const action of ['reset', 'reset', 'remove', 'remove']) {
        const result = route.run([action]);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout, '');
        const expected = { rule: [foreignRule], route: [foreignRoute] };
        if (action === 'reset') { expected.rule.push(ownRule); expected.route.push(ownRoute); }
        assert.deepEqual(route.read(), { '-4': expected, '-6': expected });
    }
});

test('路由脚本拒绝无效动作，IPv4 设置失败即返回错误，不再操作 IPv6', t => {
    const route = routeFixture(t);
    route.write({ '-4': { rule: [], route: [] }, '-6': { rule: [], route: [] } });
    for (const args of [[], ['flush'], ['reset', '233']]) {
        assert.equal(route.run(args).status, 1);
        assert.deepEqual(route.calls(), []);
    }
    const result = route.run(['reset'], '-4 route add');
    assert.equal(result.status, 5);
    assert.deepEqual(route.read(), { '-4': { rule: [], route: [] },
        '-6': { rule: [], route: [] } });
    assert.equal(route.calls().some(args => args[0] === '-4' && args[1] === 'rule' && args[2] === 'add'), false);
    assert.equal(route.calls().some(args => args[0] === '-6'), false);
});

test('firewall handles shipped comma protocols, DNS/local toggles and removes dangling references', t => {
    const directory = fixture(t), ip = path.join(directory, 'ips');
    fs.writeFileSync(ip, '192.0.2.0/24\n2001:db8::/32\ninvalid\n192.0.2.0/99\n');
    const state = { wan: ['pppoe-wan'], local4: ['192.168.1.1/24'], local6: ['fe80::1/64'], dns4: ['1.1.1.1'], dns6: [] };
    const firewall = { '.name': 'fw', '.type': 'firewall', shunt_port: '18081', tproxy_proto: 'tcp,udp', proxy_local: '0', acl_default_allow: '1' };
    const dns = { '.name': 'dns', '.type': 'dns', dns_service: 'chinadns-ng', cdg_port: '53653' };
    for (const forward of ['none', 'pre-routing', 'routing']) for (const local of ['0', '1']) {
        const result = value({ action: 'firewall', templatePath: path.join(root, 'root/etc/hijpass/firewall.ut'), state,
            paths: { '/etc/hijpass/rules/ip-direct.txt': ip }, sections: [global, { ...firewall, dns_forward: forward, proxy_local: local }, dns,
                { '.type': 'shunt', enabled: '1', dns_listen_port: '10153' }] });
        assert.match(result, /meta l4proto != \{ tcp, udp \}/);
        assert.doesNotMatch(result, /\bdefine\b|\$[A-Z_]+/);
        assert.doesNotMatch(result, /^\s*#/m);
        assert.doesNotMatch(result, /elements = \{\s*\}/);
        assert.equal(result.includes('chain dns-forward {'), forward !== 'none');
        assert.equal(result.includes('chain dns-forward-output {'), forward !== 'none' && local === '1');
        assert.equal(result.includes('chain out-route {'), local === '1');
        assert.match(result, /192\.0\.2\.0\/24/);
        assert.doesNotMatch(result, /invalid|192\.0\.2\.0\/99/);
        const sets = new Set([...result.matchAll(/^[ \t]*set (\S+)/gm)].map(m => m[1]));
        for (const m of result.matchAll(/@(\w+)/g)) assert.ok(sets.has(m[1]), 'missing set ' + m[1]);
        fs.writeFileSync(path.join(directory, 'test.nft'), result);
        // nft parses without applying rules; hosts lacking netlink privileges still report grammar errors.
        const check = spawnSync('nft', ['-c', '-f', path.join(directory, 'test.nft')], { encoding: 'utf8' });
        if (!check.error) assert.doesNotMatch(check.stderr, /syntax error/);
    }
    const rejected = invoke({ action: 'firewall', templatePath: path.join(root, 'root/etc/hijpass/firewall.ut'), state,
        sections: [global, { ...firewall, proxy_iface_list: ['br-lan;flush ruleset'] }, dns] });
    assert.notEqual(rejected.status, 0);
});

test('Geo conversion derives unique tags from enabled rules without legacy metadata', () => {
    const rules = [
        { '.type': 'shunt_route_rule', enabled: '1', domain_list: 'geosite:cn\ngeosite:cn\nfull:example.org', ip_list: 'geoip:private' },
        { '.type': 'shunt_route_rule', enabled: '0', domain_list: 'geosite:disabled' },
    ];
    for (const metadata of [{}, { geosite_ruleset: ['stale'], geoip_ruleset: ['stale'] }]) {
        const result = value({ action: 'geo-plan', sections: [{ '.type': 'shunt', ...metadata }, ...rules] });
        assert.deepEqual(result.jobs.map(({ database, tag }) => [database, tag]), [['geoip', 'private'], ['geosite', 'cn']]);
    }
});

test('service plans preserve argv, custom config paths, environments and nesting users', t => {
    const directory = fixture(t);
    const sections = [{ ...global, client_dir: directory }, node('sb', { name: 'space name', procd_env: ['A=a b', 'B=two'] }),
        node('xr', { core: 'xray', listen_port: '10003', socks_port: '10004', nest_proxy: '1' }),
        node('custom', { config_type: 'custom', type: 'custom', command: 'program --conf {conf_path}' }),
        node('off', { enabled: '0' })];
    const result = value({ action: 'plan', sections });
    assert.equal(result.instances.length, 3);
    assert.deepEqual(result.instances[0].command, ['sing-box', '-c', '/etc/hijpass/client/space name-sb.json', 'run']);
    assert.deepEqual(result.instances[0].env, ['A=a b', 'B=two']);
    assert.equal(result.instances[0].user, 'hijpass');
    assert.equal(result.instances[1].user, 'root');
    assert.equal(result.instances[2].command[2], "program --conf '/etc/hijpass/client/custom-custom.json'");
    assert.deepEqual(value({ action: 'plan', sections: [{ ...global, enabled: '0' }] }), { instances: [] });
    assert.notEqual(invoke({ action: 'plan', sections: [global, node('bad', { name: '../file' })] }).status, 0);
    assert.notEqual(invoke({ action: 'plan', sections: [global, node('bad', { procd_env: ['bad entry'] })] }).status, 0);
});

test('服务启动和生成采用同一核心缺省值，自定义命令保持 Shell 语义', t => {
    const directory = fixture(t);
    for (const core of [undefined, '', 'sing-box', 'xray']) {
        const result = value({ action: 'plan', sections: [{ ...global, client_dir: directory },
            node('a', { core, type: 'vless' })] });
        assert.equal(result.instances[0].command[0], core === 'xray' ? 'xray' : 'sing-box');
    }
    const output = path.join(directory, 'command-output');
    const command = `value='a b'; printf '%s\\n' "$value" > '${output}'`;
    const result = value({ action: 'plan', sections: [global, node('custom', { config_type: 'custom', command })] });
    assert.deepEqual(result.instances[0].command, ['/bin/sh', '-c', command]);
    const executed = spawnSync(result.instances[0].command[0], result.instances[0].command.slice(1), { encoding: 'utf8' });
    assert.equal(executed.status, 0, executed.stderr);
    assert.equal(fs.readFileSync(output, 'utf8'), 'a b\n');
    for (const command of [undefined, '', ' \t\n ']) {
        const invalid = invoke({ action: 'plan', sections: [global, node('custom', { config_type: 'custom', command })] });
        assert.notEqual(invalid.status, 0);
        assert.match(invalid.stderr, /has no command/);
    }
    for (const core of ['singbox', 'custom']) {
        const invalid = invoke({ action: 'plan', sections: [global, node('a', { core })] });
        assert.notEqual(invalid.status, 0);
        assert.match(invalid.stderr, /unsupported core/);
    }
    const invalidMode = invoke({ action: 'plan', sections: [global, node('a', { config_type: 'invalid' })] });
    assert.notEqual(invalidMode.status, 0);
    assert.match(invalidMode.stderr, /unsupported config_type/);
});

test('custom client commands open configuration paths with unquoted, single and double quoted placeholders', t => {
    const directory = fixture(t);
    const name = 'space \' " $HOME `id`; & file';
    const filename = path.join(directory, name + '-custom.json');
    fs.writeFileSync(filename, 'configuration content');
    const commands = [
        'cat {conf_path}', 'cat "{conf_path}"', "cat '{conf_path}'",
        `printf '%s' "$(cat {conf_path})"`,
        `printf '%s' "$(cat "{conf_path}")"`,
        "# don't parse quotes in comments\ncat \"{conf_path}\"",
        'cat "{conf_path}"; cat {conf_path}',
    ];
    for (const command of commands) {
        const sections = [global, node('custom', { name, config_type: 'custom', command })];
        const result = value({ action: 'plan', sections,
            paths: { '/etc/hijpass/client': directory } });
        const [program, ...args] = result.instances[0].command;
        const executed = spawnSync(program, args, { encoding: 'utf8' });
        assert.equal(executed.status, 0, executed.stderr);
        assert.equal(executed.stdout, 'configuration content'.repeat(command.includes('; cat') ? 2 : 1));
    }
});


test('server plan validates protocol ports and does not write files', t => {
    const directory = fixture(t);
    const file = path.join(directory, 'server-a.json'); fs.writeFileSync(file, 'custom JSON');
    const sections = [{ '.type': 'hijserver', enabled: '1', server_dir: directory },
        { '.name': 'a', '.type': 'server_node', enabled: '1', name: 'server', type: 'shadowsocks', method: 'aes-128-gcm', password: 'test', allow_firewall: '1', listen_port: '443' }];
    const result = value({ action: 'server-plan', sections });
    assert.deepEqual(result.ports, { tcp: [443], udp: [443] });
    assert.equal(fs.readFileSync(file, 'utf8'), 'custom JSON');
    sections[1].listen_port = '0';
    assert.notEqual(invoke({ action: 'server-plan', sections }).status, 0);
});

test('native configuration writes are private and staging failure preserves every existing file', t => {
    const directory = fixture(t), client = path.join(directory, 'client'); fs.mkdirSync(client);
    const custom = path.join(client, 'manual-c.json'); fs.writeFileSync(custom, 'manual');
    const sections = [{ ...global, client_dir: client, shunt_conf: path.join(directory, 'shunt.json') }, node('a'),
        node('c', { name: 'manual', config_type: 'custom', command: 'program', listen_port: '10003', socks_port: '10004' })];
    const paths = { '/etc/hijpass/client': client, '/etc/hijpass/shunt.json': path.join(directory, 'shunt.json') };
    const result = value({ action: 'write', sections, paths });
    assert.equal(result.length, 1);
    const file = path.join(client, 'a-a.json'), original = fs.readFileSync(file, 'utf8');
    assert.equal(fs.statSync(file).mode & 0o777, 0o600);
    assert.equal(fs.readFileSync(custom, 'utf8'), 'manual');
    const generated = { nodes: { a: { changed: true } }, shunt: { outbounds: [] } };
    const failed = invoke({ action: 'write', paths: { ...paths, '/etc/hijpass/shunt.json': file + '/blocked.json' }, sections: [{ ...sections[0], shunt_conf: file + '/blocked.json' }, ...sections.slice(1)], generated });
    assert.notEqual(failed.status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), original);
    assert.equal(fs.readdirSync(client).some(name => name.includes('.new-')), false);
});

test('native UCI migration is idempotent and moves legacy balance references without resetting fields', t => {
    const directory = fixture(t);
    fs.writeFileSync(path.join(directory, 'hijpass'), `config hijpass 'global'\n option enabled '1'\n option nft '/etc/hijpass/fw4-template.nft'\nconfig proxy_node 'a'\n option name 'member'\n option core 'singbox'\n option listen_port '7890'\n option socks_port '7891'\nconfig shunt 's'\n option type 'singbox'\n list lb_node_list 'member'\n option default_proxy_node 'hijpass-slb'\n option lb_strategy 'urltest'\nconfig dns 'dns'\n option direct_dns 'system'\nconfig firewall 'fw'\n`);
    const result = value({ action: 'migrate', directory });
    assert.equal(result.find(s => s['.name'] === 'global').firewall_template, undefined);
    assert.equal(result.find(s => s['.name'] === 'global').nft, undefined);
    assert.equal(result.find(s => s['.name'] === 'global').legacy_firewall_template, '/etc/hijpass/fw4-template.nft');
    const balance = result.find(s => s.type === 'load_balance');
    assert.equal(balance.listen_port, '7892'); assert.equal(balance.socks_port, '7893');
    assert.deepEqual(balance.member_node, ['member']);
    assert.equal(result.find(s => s['.name'] === 's').default_proxy_node, balance.name);
    assert.equal(result.find(s => s['.name'] === 'a').core, 'sing-box');
    assert.equal(result.find(s => s['.name'] === 'a').config_type, 'generated');
    assert.equal(result.find(s => s['.name'] === 'global').schema_version, '5');
    assert.equal(result.find(s => s['.name'] === 'dns').direct_dns, 'dnsmasq');
    assert.equal(result.find(s => s['.name'] === 'fw').proxy_local, '0');
    const text = fs.readFileSync(path.join(directory, 'hijpass'), 'utf8');
    value({ action: 'migrate', directory });
    assert.equal(fs.readFileSync(path.join(directory, 'hijpass'), 'utf8'), text);
    fs.writeFileSync(path.join(directory, 'hijpass'), text.replace("option enabled '1'", "option enabled '0'"));
    assert.equal(value({ action: 'migrate', directory }).find(s => s['.name'] === 'global').enabled, '0');
});

test('独立迁移脚本转换旧自定义配置，保留用户命令并仅执行一次', t => {
    const directory = fixture(t), file = path.join(directory, 'hijpass');
    fs.writeFileSync(file, `config hijpass 'global'\nconfig proxy_node 'a'\n option core 'custom'\n option type 'vless'\n option command 'program --config {conf_path}'\nconfig proxy_node 'b'\n option type 'custom'\n option command 'other-program'\nconfig proxy_node 'c'\n option core 'xray'\n option type 'vless'\n`);
    const sections = value({ action: 'migrate', directory });
    for (const id of ['a', 'b']) {
        const section = sections.find(s => s['.name'] === id);
        assert.equal(section.config_type, 'custom');
        assert.equal(section.core, undefined);
        assert.equal(section.type, undefined);
    }
    assert.equal(sections.find(s => s['.name'] === 'a').command, 'program --config {conf_path}');
    assert.equal(sections.find(s => s['.name'] === 'c').core, 'xray');
    const modified = fs.readFileSync(file, 'utf8') + "\nconfig proxy_node 'later'\n option core 'singbox'\n";
    fs.writeFileSync(file, modified);
    value({ action: 'migrate', directory });
    assert.equal(fs.readFileSync(file, 'utf8'), modified);
});

test('迁移失败不写入完成标记，修复配置后可以重试', t => {
    const directory = fixture(t), file = path.join(directory, 'hijpass');
    const invalid = "config hijpass 'global'\n option broken 'unterminated\n";
    fs.writeFileSync(file, invalid);
    const failed = invoke({ action: 'migrate', directory });
    assert.notEqual(failed.status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), invalid);
    fs.writeFileSync(file, "config hijpass 'global'\n");
    assert.equal(value({ action: 'migrate', directory })[0].schema_version, '5');
});

test('schema 1 升级只迁移 Xray HTTP 和旧 cron，保留 sing-box、自定义配置及其他任务', t => {
    const directory = fixture(t), configDir = path.join(directory, 'etc/config'), cronDir = path.join(directory, 'etc/crontabs');
    fs.mkdirSync(configDir, { recursive: true }); fs.mkdirSync(cronDir);
    const file = path.join(configDir, 'hijpass'), cron = path.join(cronDir, 'root');
    fs.writeFileSync(file, `config hijpass 'global'
 option schema_version '1'
config proxy_node 'xr'
 option enabled '1'
 option config_type 'generated'
 option core 'xray'
 option type 'vless'
 option server '192.0.2.1'
 option server_port '443'
 option listen_port '10001'
 option socks_port '10002'
 option uuid '11111111-1111-4111-8111-111111111111'
 option transport_type 'http'
 option transport_http_host 'host.example.org'
 option transport_http_path '/kept'
 option transport_http_method 'PUT'
 option transport_http_idle_timeout '15s'
 option transport_xhttp_host 'unused.example.org'
config proxy_node 'sb'
 option core 'sing-box'
 option transport_type 'http'
 option transport_http_host 'kept.example.org'
config proxy_node 'manual'
 option config_type 'custom'
 option core 'xray'
 option type 'vless'
 option transport_type 'http'
 option command 'user-program'
`);
    const kept = '# /usr/lib/hijpass/rules.sh is mentioned here\n0 * * * * echo /usr/lib/hijpass/rules.uc\n0 * * * * /other/rules.sh\n0 * * * * /usr/lib/hijpass/rules/update.sh update\n';
    fs.writeFileSync(cron, kept + '0 * * * * /usr/lib/hijpass/rules.sh update\n0 * * * * /usr/lib/hijpass/rules.uc update\n@reboot /usr/lib/hijpass/clean-service-log.sh hijpass\n*/10 * * * * /usr/lib/hijpass/clean-service-log.uc hijserver\n', { mode: 0o600 });
    const sections = value({ action: 'migrate', directory: configDir });
    const node = sections.find(s => s['.name'] === 'xr');
    assert.equal(node.transport_type, 'xhttp');
    assert.equal(node.transport_xhttp_host, 'host.example.org');
    assert.equal(node.transport_xhttp_path, '/kept');
    assert.equal(node.transport_xhttp_method, 'PUT');
    assert.equal(node.transport_xhttp_mode, 'stream-one');
    assert.equal(Object.keys(node).some(key => key.startsWith('transport_http_')), false);
    assert.equal(sections.find(s => s['.name'] === 'sb').transport_type, 'http');
    assert.equal(sections.find(s => s['.name'] === 'manual').transport_type, 'http');
    assert.equal(sections.find(s => s['.name'] === 'global').schema_version, '5');
    const generated = run('root/usr/bin/hijpass-config', ['render', '--stdin'], sections);
    assert.equal(generated.status, 0, generated.stderr);
    assert.deepEqual(JSON.parse(generated.stdout).nodes.xr.outbounds[0].streamSettings.xhttpSettings,
        { host: 'host.example.org', path: '/kept', mode: 'stream-one', uplinkHTTPMethod: 'PUT' });
    assert.equal(fs.readFileSync(cron, 'utf8'), kept);
    assert.equal(fs.statSync(cron).mode & 0o777, 0o600);
    const migrated = fs.readFileSync(file, 'utf8');
    value({ action: 'migrate', directory: configDir });
    assert.equal(fs.readFileSync(file, 'utf8'), migrated);
    assert.equal(fs.readFileSync(cron, 'utf8'), kept);
});

test('cron 迁移失败时不提交新版本，修复后可以重试；未知版本不降级', t => {
    const directory = fixture(t), configDir = path.join(directory, 'config'), cronDir = path.join(directory, 'crontabs');
    fs.mkdirSync(configDir); fs.mkdirSync(cronDir);
    const file = path.join(configDir, 'hijpass'), cron = path.join(cronDir, 'root');
    const original = "config hijpass 'global'\n option schema_version '1'\n";
    fs.writeFileSync(file, original); fs.mkdirSync(cron);
    const failed = invoke({ action: 'migrate', directory: configDir });
    assert.notEqual(failed.status, 0);
    assert.match(failed.stderr, /cron path is not a file/);
    assert.equal(fs.readFileSync(file, 'utf8'), original);
    fs.rmdirSync(cron); fs.writeFileSync(cron, '0 * * * * /usr/lib/hijpass/rules.sh update\n');
    assert.equal(value({ action: 'migrate', directory: configDir })[0].schema_version, '5');
    assert.equal(fs.readFileSync(cron, 'utf8'), '');
    const future = "config hijpass 'global'\n option schema_version '6'\n";
    fs.writeFileSync(file, future);
    assert.notEqual(invoke({ action: 'migrate', directory: configDir }).status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), future);
});

test('domain/IP normalization and CIDR lookup use native address validation', () => {
    assert.deepEqual(value({ action: 'normalize', kind: 'domain', text: 'server=/Example.org/1.1.1.1\n+.example.net\n@@||allowed.org^\nfull:exact.com\n! comment\ninvalid\n' }), ['allowed.org', 'exact.com', 'example.net', 'example.org']);
    assert.deepEqual(value({ action: 'normalize', kind: 'ip6', text: '2001:db8::/32\n2001:db8::/129\ninvalid\n' }), ['2001:db8::/32']);
    assert.deepEqual(value({ action: 'contains', cases: [['192.0.2.5', '192.0.2.0/24'], ['192.0.3.1', '192.0.2.0/24'],
        ['2001:db8::123', '2001:db8::/32'], ['2001:db9::1', '2001:db8::/32'], ['::1', '::/invalid']] }), [true, false, true, false, false]);
});

const cidrCases = [
    { family: 4, host: '192.0.2.1', valid: ['192.0.2.1', '192.0.2.0/0', '192.0.2.0/024', '192.0.2.1/32'],
        invalid: ['192.0.2.0/24/garbage', '192.0.2.0/24/', '192.0.2.0//24', '192.0.2.0/', '192.0.2.0/33',
            '192.0.2.0/-1', '192.0.2.0/+24', '192.0.2.0/24.0', '192.0.2.0/0x18', '192.0.2.0/ 24',
            '192.0.2.0/65560', '192.0.2.0/18446744073709551616', '192.0.2.0/255.255.255.0',
            '192.0.2.256/24', '192.0.2.0\0junk/24', '192.0.2.0/24\0junk', '/24'] },
    { family: 6, host: '2001:db8::1', valid: ['2001:db8::1', '2001:db8::/0', '2001:db8::/032', '2001:db8::1/128'],
        invalid: ['2001:db8::/32/garbage', '2001:db8::/32/', '2001:db8:://32', '2001:db8::/', '2001:db8::/129',
            '2001:db8::/-1', '2001:db8::/+32', '2001:db8::/32.0', '2001:db8::/0x20', '2001:db8::/ 32',
            '2001:db8::/65568', '2001:db8::/18446744073709551616', '2001:db8::/ffff:ffff::',
            '2001:db8::g/32', '2001:db8::\0junk/32', '2001:db8::/32\0junk', 'fe80::1%lo/64', '/32'] },
];

test('CIDR 清洗保留合法地址和十进制前缀，拒绝多余分段、溢出和截断输入', () => {
    const text = cidrCases.flatMap(group => [...group.valid, ...group.invalid]).join('\n');
    for (const { family, valid } of cidrCases)
        assert.deepEqual(value({ action: 'normalize', kind: `ip${family}`, text }), [...valid].sort());
});

test('CIDR 匹配拒绝无效网段，正确处理地址族、单地址和非整字节前缀', () => {
    const cases = cidrCases.flatMap(({ host, invalid }) => invalid.map(cidr => [host, cidr, false]));
    cases.push(
        ['192.0.2.1', null, false], ['192.0.2.1', 24, false], [null, '192.0.2.0/24', false],
        ['192.0.2.1\0junk', '192.0.2.0/24', false], ['2001:db8::1\0junk', '2001:db8::/32', false],
        ['192.0.2.1/32', '192.0.2.0/24', false], ['192.0.2.1', '::/0', false], ['::1', '0.0.0.0/0', false],
        ['203.0.113.255', '192.0.2.1/0', true], ['ffff::1', '2001:db8::/0', true],
        ['192.0.2.1', '192.0.2.1', true], ['192.0.2.2', '192.0.2.1', false],
        ['192.0.2.1', '192.0.2.1/32', true], ['192.0.2.2', '192.0.2.1/32', false],
        ['192.0.2.1', '192.0.2.0/024', true], ['192.0.3.1', '192.0.2.0/024', false],
        ['192.0.2.127', '192.0.2.5/25', true], ['192.0.2.128', '192.0.2.5/25', false],
        ['2001:db8::1', '2001:db8::1', true], ['2001:db8::2', '2001:db8::1', false],
        ['2001:db8::1', '2001:db8::1/128', true], ['2001:db8::2', '2001:db8::1/128', false],
        ['2001:db8::1', '2001:db8::/032', true], ['2001:db9::1', '2001:db8::/032', false],
        ['2001:db8:0:0:7fff::1', '2001:db8::5/65', true], ['2001:db8:0:0:8000::', '2001:db8::5/65', false],
        ['::ffff:192.0.2.1', '::ffff:192.0.2.0/120', true], ['::ffff:192.0.3.1', '::ffff:192.0.2.0/120', false],
    );
    assert.deepEqual(value({ action: 'contains', cases: cases.map(([host, cidr]) => [host, cidr]) }), cases.map(([, , expected]) => expected));
});

test('防火墙各 IP 列表只输出共享 CIDR 校验通过的对应地址族', t => {
    const file = path.join(fixture(t), 'ips');
    fs.writeFileSync(file, cidrCases.flatMap(group => [...group.valid, ...group.invalid]).join('\n'));
    const paths = Object.fromEntries(['ip-direct', 'ip-proxy', 'chn-route', 'chn-route6'].map(name => [`/etc/hijpass/rules/${name}.txt`, file]));
    const result = value({ action: 'firewall', paths, templatePath: path.join(root, 'root/etc/hijpass/firewall.ut'),
        state: { wan: [], local4: [], local6: [], dns4: [], dns6: [] },
        sections: [global, { '.type': 'firewall', proxy_port: '10001', tproxy_proto: 'tcp', use_chnroute: '1' }] });
    for (const { family, valid } of cidrCases) for (const name of ['bypass', 'proxy', 'chnroute']) {
        const body = result.split(`set ${name}${family}list {`)[1]?.split(/\n[ \t]*\}/)[0];
        assert.ok(body, `missing ${name}${family}list`);
        const elements = body.match(/elements = \{([^}]*)\}/)?.[1].split(',').map(value => value.trim());
        assert.deepEqual(elements, valid);
    }
});

test('iptype 对 CIDR 使用相同校验，拒绝忽略非法前缀', () => {
    for (const { family, valid, invalid } of cidrCases) {
        for (const address of valid) {
            const result = run('root/usr/lib/hijpass/network/network.sh', ['iptype', address]);
            assert.equal(result.status, 0, result.stderr);
            assert.equal(result.stdout, `${family}\n`);
        }
        for (const address of invalid.filter(value => !value.includes('\0'))) {
            const result = run('root/usr/lib/hijpass/network/network.sh', ['iptype', address]);
            assert.equal(result.status, 1, address);
            assert.equal(result.stdout, '');
        }
    }
});

test('rule updates preserve old files on HTTP/format failure and merge valid sources', t => {
    const directory = fixture(t), file = path.join(directory, 'domains'); fs.writeFileSync(file, 'old.example.org\n');
    const env = { PATH: directory + ':' + process.env.PATH };
    script(directory, 'curl', 'exit 22');
    const sections = [{ ...global, enabled: '0' }, { '.type': 'rule', retry_count: '1', chn_domain_list: ['https://example.org/1', 'https://example.org/2'] }];
    assert.equal(value({ action: 'update', sections, paths: { '/etc/hijpass/rules/chn-list.txt': file }, group: 'chnlist' }, env).success, false);
    assert.equal(fs.readFileSync(file, 'utf8'), 'old.example.org\n');
    script(directory, 'curl', `while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then output=$2; shift; fi; shift; done\nprintf '%s\\n' 'not a domain' 'some HTML error text' >"$output"`);
    assert.equal(value({ action: 'update', sections, paths: { '/etc/hijpass/rules/chn-list.txt': file }, group: 'chnlist' }, env).success, false);
    assert.equal(fs.readFileSync(file, 'utf8'), 'old.example.org\n');
    script(directory, 'curl', `while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then output=$2; shift; fi; shift; done\ni=0; while [ "$i" -lt 10 ]; do echo server=/example.org/1.1.1.1; i=$((i+1)); done >"$output"`);
    assert.equal(value({ action: 'update', sections, paths: { '/etc/hijpass/rules/chn-list.txt': file }, group: 'chnlist' }, env).success, true);
    assert.equal(fs.readFileSync(file, 'utf8'), 'example.org\n');
});

test('subprocess arguments and connection JSON survive quotes and reject malformed timeouts', t => {
    const directory = fixture(t), valueWithQuotes = "a 'quote'; $(touch " + directory + "/injected)";
    const command = value({ action: 'command', args: ['printf', '%s', valueWithQuotes] });
    const quoted = spawnSync('/bin/sh', ['-c', command], { encoding: 'utf8' });
    assert.deepEqual({ code: quoted.status, stdout: quoted.stdout }, { code: 0, stdout: valueWithQuotes });
    assert.equal(fs.existsSync(path.join(directory, 'injected')), false);
    script(directory, 'curl', "printf '204\\n192.0.2.1\\n443\\n0.001\\n0.002\\n0.003\\n0.004\\n0.005\\n'");
    const result = value({ action: 'connect', url: 'https://example.org', timeout: '5' }, { PATH: directory + ':' + process.env.PATH });
    assert.equal(result.url, 'https://example.org');
    assert.equal(result.total_time_ms, 5); assert.equal(result.server_processing_time_ms, 4); assert.equal(result.success, true);
    assert.notEqual(invoke({ action: 'connect', url: 'https://example.org', timeout: '5oops' }).status, 0);
});

test('file cleanup matches exact section suffix and log truncation keeps the last 30000 lines', t => {
    const directory = fixture(t), keep = path.join(directory, 'new-a.json');
    for (const name of ['old-a.json', 'new-a.json', 'other-aa.json']) fs.writeFileSync(path.join(directory, name), name);
    value({ action: 'cleanup', sections: [global], paths: { '/etc/hijpass/client': directory }, kind: 'proxy', id: 'a', name: 'new' });
    assert.deepEqual(fs.readdirSync(directory).sort(), ['new-a.json', 'other-aa.json']);
    const log = path.join(directory, 'hijpass.log'); fs.writeFileSync(log, Array.from({ length: 30005 }, (_, i) => i + '\n').join(''));
    value({ action: 'clean-log', sections: [global], paths: { '/tmp/hijpass/log': directory }, operation: 'hijpass' });
    const contents = fs.readFileSync(log, 'utf8'); assert.ok(contents.startsWith('5\n')); assert.ok(contents.endsWith('30004\n'));
    assert.equal(contents.split('\n').length, 30001);
});

test('capture parsing rejects injected/invalid targets and counts TCP payload without counting UDP bytes', () => {
    const config = value({ action: 'trace-parse', args: ['https://[2001:db8::1]:8443/a?b=1'] });
    assert.equal(config.host, '2001:db8::1'); assert.equal(config.targetPort, 8443);
    for (const args of [['-c', '::1;id'], ['-c', '2001:::1'], ['-c', '192.0.2.1', '-P', '0'], ['https://bad;id'], ['https://example.org:65536']])
        assert.notEqual(invoke({ action: 'trace-parse', args }).status, 0);
    const summary = value({ action: 'packet-summary', packets: ['1.0 br-lan In IP 192.0.2.1.1 > 1.1.1.1.443: Flags [S], length 0',
        '1.1 br-lan In IP 192.0.2.1.1 > 1.1.1.1.443: Flags [P.], length 42', '1.2 br-lan In IP 192.0.2.1.1 > 1.1.1.1.53: UDP, length 20'] });
    assert.equal(summary.counts.syn, 1); assert.equal(summary.counts.payload_bytes, 42); assert.equal(summary.counts.udp, 1);
});

test('client report uses IP addresses when nft includes Ethernet headers and excludes foreign trace IDs', t => {
    const directory = fixture(t);
    fs.writeFileSync(path.join(directory, 'nft.trace'), 'trace id 123 inet hijpass trace-1 packet: ether saddr 02:00:00:00:00:01 ether daddr 02:00:00:00:00:02 ip saddr 192.0.2.10 ip daddr 8.8.8.8 udp sport 50000 udp dport 53\n' +
        'trace id 123 inet hijpass trace-1 rule meta nftrace set 1\ntrace id 999 inet hijpass other packet: ip saddr 192.0.2.99\n');
    const result = value({ action: 'trace-report', directory, capture: { mode: 'client', client: '192.0.2.10', chain: 'trace-1', comment: 'hijpass-trace-1', addresses: [], protocol: 'udp', port: '53', seconds: 2 } });
    assert.match(result, /udp \[192\.0\.2\.10\]:50000 -> \[8\.8\.8\.8\]:53/);
    assert.doesNotMatch(result, /02:00:00:00:00|192\.0\.2\.99/);
});

test('文本工具正常退出，参数错误保持 JSON 工具的错误契约', t => {
    for (const [address, family] of [['192.0.2.1', '4\n'], ['2001:db8::1/64', '6\n']]) {
        const result = run('root/usr/lib/hijpass/network/network.sh', ['iptype', address]);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout, family);
        assert.equal(result.stderr, '');
    }
    const invalid = run('root/usr/lib/hijpass/network/network.sh', ['iptype', 'example.org', '--configdir']);
    assert.equal(invalid.status, 1);
    assert.match(JSON.parse(invalid.stdout).error, /missing --configdir/);
    assert.equal(invalid.stderr, '');
});

test('CLI 参数和配置目录在同一进程的多次调用之间保持独立', t => {
    const file = path.join(fixture(t), 'cli.uc');
    fs.writeFileSync(file, `import { run } from 'hijpass.command.runtime';
let argv = ['plan', '--configdir', '/first'];
run(argv, (args, directory) => ({ args, directory }));
assert(length(argv) == 3 && argv[1] == '--configdir', 'input arguments were modified');
run(['plan'], (args, directory) => ({ args, directory: directory || null }));
run(['--configdir', '/second', 'plan'], (args, directory) => ({ args, directory }));
`);
    const result = run(file);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(result.stdout.trim().split('\n').map(JSON.parse), [
        { args: ['plan'], directory: '/first' }, { args: ['plan'], directory: null },
        { args: ['plan'], directory: '/second' },
    ]);
});

test('DNS 模板参数只使用显式传入的 dnsmasq 配置', () => {
    const sections = [{ '.type': 'dns', dns_service: 'chinadns-ng', cdg_port: '53653',
        direct_dns: 'dnsmasq', proxy_dns: 'custom', proxy_dns_custom: 'dnsmasq' }];
    for (const [dnsmasq, port] of [[{}, '53'], [{ port: '1053' }, '1053']]) {
        const options = value({ action: 'dns-options', sections, dnsmasq });
        assert.equal(options.direct, `127.0.0.1#${port}`);
        assert.equal(options.proxy, `127.0.0.1#${port}`);
    }
});

test('启用防火墙时，缺失模板不会生成缺少规则的配置', t => {
    const directory = fixture(t);
    const result = invoke({ action: 'firewall', templatePath: path.join(directory, 'missing'),
        state: { wan: [], local4: [], local6: [], dns4: [], dns6: [] },
        sections: [global, { '.type': 'firewall', proxy_port: '10001', tproxy_proto: 'tcp' }] });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /template/);
    assert.equal(result.stdout, '');
});

test('捕获元数据缺失或损坏时仍删除临时 nft 规则与任务目录', t => {
    const directory = fixture(t), commands = path.join(directory, 'commands');
    script(directory, 'nft', `printf '%s\\n' "$*" >>"$TRACE_TEST_LOG"
case "$*" in
    '-a list chain inet hijpass pre-filter')
        printf 'meta nftrace set 1 comment "hijpass-trace-%s" # handle 42\\n' "$TRACE_TEST_PID" ;;
esac`);
    for (const [i, metadata] of [undefined, '{broken', '{}'].entries()) {
        const pid = `${process.pid}99${i}`, capture = '/tmp/hijpass-trace.' + pid;
        fs.mkdirSync(capture, { mode: 0o700 });
        t.after(() => fs.rmSync(capture, { recursive: true, force: true }));
        if (metadata !== undefined) fs.writeFileSync(path.join(capture, 'metadata.json'), metadata);
        fs.writeFileSync(commands, '');
        const result = run('root/usr/lib/hijpass/diagnostics/capture.sh', ['finish', capture], undefined,
            { env: { ...process.env, PATH: directory + ':' + process.env.PATH, TRACE_TEST_LOG: commands, TRACE_TEST_PID: pid } });
        assert.equal(result.status, 1);
        assert.ok(result.stderr);
        const calls = fs.readFileSync(commands, 'utf8');
        assert.ok(calls.includes('delete chain inet hijpass trace-' + pid));
        assert.ok(calls.includes('delete rule inet hijpass pre-filter handle 42'));
        assert.equal(fs.existsSync(capture), false);
    }
});

test('核心版本查询将损坏的上游 JSON 转为带来源的错误', t => {
    const directory = fixture(t), env = { ...process.env, PATH: directory + ':' + process.env.PATH };
    for (const response of ['{broken', 'null', '[]', '{}']) {
        script(directory, 'curl', `printf '%s' '${response}'`);
        const result = run('root/usr/lib/hijpass/core/update.sh', ['latest', 'xray'], undefined, { env });
        assert.equal(result.status, 1);
        assert.match(JSON.parse(result.stdout).error, /invalid xray release response/);
        assert.equal(result.stderr, '');
    }
    script(directory, 'curl', `printf '%s' '{"tag_name":"v1.2.3","assets":[]}'`);
    const result = run('root/usr/lib/hijpass/core/update.sh', ['latest', 'xray'], undefined, { env });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), { core: 'xray', version: 'v1.2.3' });
});

test('规则下载拒绝非整数参数，校验失败时保留原文件且不执行 curl', t => {
    const directory = fixture(t), file = path.join(directory, 'domains'), calls = path.join(directory, 'curl-calls');
    fs.writeFileSync(file, 'old.example.org\n');
    script(directory, 'curl', 'printf called >>"$RULE_TEST_CALLS"\nexit 22');
    const env = { PATH: directory + ':' + process.env.PATH, RULE_TEST_CALLS: calls };
    const invalid = [
        { download_timeout: 'invalid' }, { download_timeout: '3oops' },
        { download_timeout: '1.5' }, { download_timeout: '0' }, { download_timeout: '601' },
        { retry_count: 'invalid' }, { retry_count: '1oops' },
        { retry_count: '-1' }, { retry_count: '11' },
    ];
    for (const options of invalid) {
        const sections = [{ ...global, enabled: '0', chn_list: file },
            { '.type': 'rule', download_timeout: '30', retry_count: '1',
                chn_domain_list: ['https://example.org/domains'], ...options }];
        const result = invoke({ action: 'update', sections, paths: { '/etc/hijpass/rules/chn-list.txt': file }, group: 'chnlist' }, env);
        assert.notEqual(result.status, 0, JSON.stringify(options));
        assert.match(result.stderr, /invalid download timeout or retry count/);
        assert.equal(fs.readFileSync(file, 'utf8'), 'old.example.org\n');
        assert.equal(fs.existsSync(calls), false);
    }
});

test('连接失败的 curl 输出仍转换为完整报告，核心与诊断命令拒绝缺失参数', t => {
    const directory = fixture(t);
    script(directory, 'curl', "printf '000\\n\\n0\\n0.001\\n0.002\\n0.003\\n0.004\\n0.005\\n'\nexit 28");
    const result = value({ action: 'connect', url: 'https://example.org', timeout: '5' },
        { PATH: directory + ':' + process.env.PATH });
    assert.equal(result.success, false);
    assert.equal(result.exit_code, 28);
    assert.equal(result.url, 'https://example.org');
    assert.equal(result.http_code, 0);
    assert.equal(result.remote_ip, '');
    assert.equal(result.total_time_ms, 5);
    for (const args of [[], ['latest']]) {
        const missing = run('root/usr/lib/hijpass/core/update.sh', args);
        assert.equal(missing.status, 1);
        assert.match(JSON.parse(missing.stdout).error, /core action and name are required/);
    }
    for (const args of [['prepare'], ['report']]) {
        const missing = run('root/usr/lib/hijpass/diagnostics/capturecli.uc', args);
        assert.equal(missing.status, 1);
        assert.match(missing.stderr, /invalid capture (PID|directory)/);
        assert.equal(missing.stdout, '');
    }
});

test('UCI 读取仅返回原生字段，业务类型和协议校验由生成阶段处理', t => {
    const directory = fixture(t);
    fs.writeFileSync(path.join(directory, 'hijpass'), `config hijpass
 option enabled '0'
 option description 'a name with spaces'
config proxy_node 'sample'
 option enabled '1'
 option type 'hysteria2'
 option core 'sing-box'
 option server 'example.org'
 option server_port 'not-a-port'
 option listen_port '10001'
 option socks_port '10002'
 list server_ports '443-445'
 list server_ports '8443'
 list server_ports '443-445'
`);
    const sections = value({ action: 'read', directory });
    assert.deepEqual(sections.map(s => s['.type']), ['hijpass', 'proxy_node']);
    assert.deepEqual(sections.map(s => s['.index']), [0, 1]);
    assert.equal(sections[0]['.anonymous'], true);
    assert.equal(typeof sections[0]['.name'], 'string');
    assert.equal(sections[0].enabled, '0');
    assert.equal(sections[0].description, 'a name with spaces');
    assert.equal(sections[1]['.name'], 'sample');
    assert.equal(sections[1]['.anonymous'], false);
    assert.equal(sections[1].server_port, 'not-a-port');
    assert.equal(sections[1].listen_port, '10001');
    assert.deepEqual(sections[1].server_ports, ['443-445', '8443', '443-445']);
    const rendered = run('root/usr/bin/hijpass-config', ['render', '--configdir', directory]);
    assert.equal(rendered.status, 1);
    assert.match(rendered.stderr, /invalid port/);
    assert.equal(rendered.stdout, '');
});

// 白名单为接口或 MAC 命中，不可因任一列表为空而放行所有客户端。
test('空静态列表省略集合与规则，ACL 空白名单明确返回，动态 DNS 集合继续保留', () => {
    const state = { wan: [], local4: [], local6: [], dns4: [], dns6: [] };
    for (const [interfaces, macs] of [[[], []], [['lo'], []], [[], ['02:00:00:00:00:01']], [['lo'], ['02:00:00:00:00:01']]]) {
        const result = value({ action: 'firewall', templatePath: path.join(root, 'root/etc/hijpass/firewall.ut'), state,
            sections: [global, { '.type': 'firewall', proxy_port: '10001', tproxy_proto: 'tcp', dns_forward: 'pre-routing',
                proxy_iface_list: interfaces, proxy_mac_list: macs, use_chnroute: '1' },
                { '.type': 'dns', dns_service: 'chinadns-ng', cdg_port: '53653', use_chn: '1', use_gfw: '1' }] });
        assert.doesNotMatch(result, /@(bypass|proxy)[46]list|set (bypass|proxy)[46]list|proxy_interface_list|proxy_mac_list/);
        for (const set of ['chnroute', 'chn', 'gfw', 'dnsproxy', 'dnsbypass'])
            for (const version of [4, 6]) assert.ok(result.includes('set ' + set + version + 'list {'));
        for (const name of ['pre-filter', 'dns-forward']) {
            const body = result.split('chain ' + name + ' {')[1].split(/\n[ \t]*\}/)[0];
            const rule = interfaces.length && macs.length ? /iif != \{ "lo" \} ether saddr != \{ 02:00:00:00:00:01 \} counter return/
                : interfaces.length ? /iif != \{ "lo" \} counter return/
                : macs.length ? /ether saddr != \{ 02:00:00:00:00:01 \} counter return/ : /^[ \t]*counter return$/m;
            assert.match(body, rule);
        }
    }
});

test('单文件模板完整控制表和链，空输出不能关闭已启用的防火墙', t => {
    const directory = fixture(t), template = path.join(directory, 'firewall.ut');
    const request = { action: 'firewall', templatePath: template,
        state: { wan: [], local4: [], local6: [], dns4: [], dns6: [] },
        sections: [global, { '.type': 'firewall', proxy_port: '10001', tproxy_proto: 'tcp', proxy_local: '0' }] };
    fs.writeFileSync(template, 'table inet hijpass { chain edited { tcp dport {{ options.proxyPort }} accept } }\n');
    const result = value(request);
    assert.match(result, /chain edited.*tcp dport 10001 accept/);
    assert.doesNotMatch(result, /chain pre-filter|chain out-route/);
    for (const empty of ['', '{# comment only #}']) {
        fs.writeFileSync(template, empty);
        const failed = invoke(request);
        assert.notEqual(failed.status, 0);
        assert.match(failed.stderr, /rendered no rules/);
    }
});

test('旧模板仅保留并提示手动迁移，不覆盖新格式模板', t => {
    const directory = fixture(t), template = path.join(directory, 'custom.ut');
    const legacy = 'table inet hijpass { chain custom { $TPROXY_SHUNT } }\n';
    const current = fs.readFileSync(path.join(root, 'root/etc/hijpass/firewall.ut'), 'utf8');
    fs.writeFileSync(template, legacy);
    fs.writeFileSync(path.join(directory, 'hijpass'), `config hijpass 'global'\n option nft '${template}'\n option firewall_rules '/custom/chains'\n`);
    const paths = { '/etc/hijpass/firewall.ut': path.join(directory, 'firewall.ut') };
    fs.writeFileSync(paths['/etc/hijpass/firewall.ut'], current);
    const migrated = run('root/usr/lib/hijpass/install/migrate.uc', ['--configdir', directory], undefined, { paths });
    assert.equal(migrated.status, 0, migrated.stderr);
    assert.match(migrated.stderr, /requires manual migration/);
    const sections = value({ action: 'migrate', directory, paths });
    assert.equal(sections[0].legacy_firewall_template, template);
    assert.equal(sections[0].firewall_template, undefined);
    assert.equal(sections[0].nft, undefined);
    assert.equal(sections[0].firewall_rules, undefined);
    assert.equal(fs.readFileSync(template, 'utf8'), legacy);
    assert.equal(fs.readFileSync(paths['/etc/hijpass/firewall.ut'], 'utf8'), current);
});

test('schema 3 补充旧默认模板提醒，重复安装保留用户确认，新装不提示', t => {
    const directory = fixture(t), file = path.join(directory, 'hijpass');
    const paths = { '/etc/hijpass/firewall.ut': path.join(directory, 'firewall.ut') };
    fs.writeFileSync(file, "config hijpass 'global'\n");
    assert.equal(value({ action: 'migrate', directory, paths })[0].legacy_firewall_template, undefined);
    fs.writeFileSync(file, "config hijpass 'global'\n option schema_version '3'\n");
    const legacy = path.join(directory, 'fw4-template.nft');
    fs.writeFileSync(legacy, '# user custom template\n');
    assert.equal(value({ action: 'migrate', directory, paths })[0].legacy_firewall_template, legacy);
    fs.appendFileSync(file, "\toption firewall_template_migration_ack '1'\n");
    const confirmed = fs.readFileSync(file, 'utf8');
    assert.equal(value({ action: 'migrate', directory, paths })[0].firewall_template_migration_ack, '1');
    assert.equal(fs.readFileSync(file, 'utf8'), confirmed);
    assert.equal(fs.readFileSync(legacy, 'utf8'), '# user custom template\n');
});

test('schema 2 路径迁移保留规则、模板、Hook、自定义配置和日志，前端只需日志开关', t => {
    const directory = fixture(t), old = path.join(directory, 'old'), target = path.join(directory, 'managed');
    fs.mkdirSync(old); fs.mkdirSync(target);
    const paths = { '/etc/hijpass': target, '/tmp/hijpass/log': path.join(target, 'logs'),
        '/tmp/hijserver/log': path.join(target, 'server-logs') };
    const resources = { ip_direct: 'rules/ip-direct.txt', ip_proxy: 'rules/ip-proxy.txt',
        domain_direct: 'rules/domain-direct.txt', domain_proxy: 'rules/domain-proxy.txt',
        gfw_list: 'rules/gfw-list.txt', chn_route: 'rules/chn-route.txt', chn_route6: 'rules/chn-route6.txt',
        chn_list: 'rules/chn-list.txt', firewall_template: 'firewall.ut',
        nft_hook: 'hook/nft-hook.sh', dns_hook: 'hook/dns-hook.sh', shunt_conf: 'shunt.json' };
    let source = `config hijpass 'global'\n option schema_version '2'\n option client_dir '${old}'\n option log_dir '${old}'\n option log_path '${old}/main.log'\n`;
    for (const [key] of Object.entries(resources)) {
        fs.writeFileSync(path.join(old, key), key + ' user content\n', { mode: key.endsWith('hook') ? 0o755 : 0o640 });
        source += ` option ${key} '${old}/${key}'\n`;
    }
    fs.writeFileSync(path.join(target, 'firewall.ut'), 'package default');
    for (const name of ['manual-a.json', 'server-b.json', 'main.log', 'node.log', 'shunt.log', 'server.log'])
        fs.writeFileSync(path.join(old, name), name + ' content');
    source += `config proxy_node 'a'\n option name 'manual'\n option config_type 'custom'\n option command 'program --config {conf_path}'\n option log_path '${old}/node.log'\nconfig proxy_node 'off'\n option log_enabled '0'\nconfig shunt 'shunt'\n option log_path '${old}/shunt.log'\nconfig rule 'rules'\n option gfw_list 'https://example.org/gfw.txt'\n`;
    fs.writeFileSync(path.join(directory, 'hijpass'), source);
    fs.writeFileSync(path.join(directory, 'hijserver'), `config hijserver 'global'\n option server_dir '${old}'\n option log_dir '${old}'\nconfig server_node 'b'\n option name 'server'\n option log_path '${old}/server.log'\n`);
    const sections = value({ action: 'migrate', directory, paths });
    assert.equal(sections[0].schema_version, '5');
    for (const [key, file] of Object.entries(resources)) {
        assert.equal(sections[0][key], undefined);
        assert.equal(fs.readFileSync(path.join(target, file), 'utf8'), key + ' user content\n');
    }
    assert.equal(fs.readFileSync(path.join(target, 'firewall.ut.before-path-migration'), 'utf8'), 'package default');
    assert.equal(fs.statSync(path.join(target, 'hook/nft-hook.sh')).mode & 0o777, 0o755);
    for (const [file, content] of [['client/manual-a.json', 'manual-a.json'], ['server/server-b.json', 'server-b.json'],
        ['logs/hijpass.log', 'main.log'], ['logs/manual-a.log', 'node.log'], ['logs/shunt.log', 'shunt.log'],
        ['server-logs/server-b.log', 'server.log']]) {
        const actual = fs.readFileSync(path.join(target, file), 'utf8');
        if (file === 'logs/hijpass.log') {
            assert.ok(actual.startsWith(content + ' content'));
            assert.match(actual.slice((content + ' content').length), /Schema migration completed: version=5/);
        } else assert.equal(actual, content + ' content');
    }
    assert.equal(sections.find(s => s['.name'] === 'a').command, 'program --config {conf_path}');
    assert.equal(sections.find(s => s['.name'] === 'a').log_enabled, '1');
    assert.equal(sections.find(s => s['.name'] === 'off').log_enabled, '0');
    assert.equal(sections.find(s => s['.name'] === 'rules').gfw_list, 'https://example.org/gfw.txt');
    for (const packageName of ['hijpass', 'hijserver']) {
        const text = fs.readFileSync(path.join(directory, packageName), 'utf8');
        assert.doesNotMatch(text, /option (log_path|log_dir|client_dir|server_dir|firewall_template|nft_hook|dns_hook|shunt_conf) /);
        value({ action: 'migrate', directory, paths });
        assert.equal(fs.readFileSync(path.join(directory, packageName), 'utf8'), text);
    }
    assert.equal(fs.readFileSync(path.join(old, 'manual-a.json'), 'utf8'), 'manual-a.json content');
});

test('路径迁移写入失败时保留旧 UCI，修复后可重试且备份不被覆盖', t => {
    const directory = fixture(t), source = path.join(directory, 'custom'), target = path.join(directory, 'blocked');
    fs.writeFileSync(source, 'custom template'); fs.writeFileSync(target, 'blocks directory');
    const original = `config hijpass 'global'\n option schema_version '2'\n option firewall_template '${source}'\n`;
    fs.writeFileSync(path.join(directory, 'hijpass'), original);
    const request = { action: 'migrate', directory, paths: { '/etc/hijpass/firewall.ut': target + '/template.ut' } };
    assert.notEqual(invoke(request).status, 0);
    assert.equal(fs.readFileSync(path.join(directory, 'hijpass'), 'utf8'), original);
    fs.unlinkSync(target);
    assert.equal(value(request)[0].schema_version, '5');
    assert.equal(fs.readFileSync(target + '/template.ut', 'utf8'), 'custom template');
});

test('schema 4 disables legacy custom servers and preserves their JSON before protocol reconfiguration', t => {
    const directory = fixture(t), server = path.join(directory, 'server');
    fs.mkdirSync(server);
    fs.writeFileSync(path.join(directory, 'hijpass'), "config hijpass 'global'\n option schema_version '4'\n");
    const file = path.join(server, 'legacy-old.json');
    fs.writeFileSync(file, '{"custom":"untouched"}\n', { mode: 0o600 });
    fs.writeFileSync(path.join(directory, 'hijserver'), "config hijserver 'global'\n option enabled '1'\nconfig server_node 'old'\n option name 'legacy'\n option enabled '1'\n option command 'custom --config {conf_path}'\n");
    const request = { action: 'migrate', directory, paths: { '/etc/hijpass/server': server } };
    assert.equal(value(request)[0].schema_version, '5');
    const migrated = fs.readFileSync(path.join(directory, 'hijserver'), 'utf8');
    assert.match(migrated, /config server_node 'old'[\s\S]*option enabled '0'/);
    assert.match(migrated, /legacy_custom '1'/);
    assert.match(migrated, /custom --config/);
    assert.equal(fs.readFileSync(file + '.legacy.json', 'utf8'), fs.readFileSync(file, 'utf8'));
    assert.equal(fs.statSync(file + '.legacy.json').mode & 0o777, 0o600);
    fs.writeFileSync(file, '{"new":"generated"}');
    value(request);
    assert.equal(fs.readFileSync(file + '.legacy.json', 'utf8'), '{"custom":"untouched"}\n');
    assert.equal(fs.readFileSync(path.join(directory, 'hijserver'), 'utf8'), migrated);
});
