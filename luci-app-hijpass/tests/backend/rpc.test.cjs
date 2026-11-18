const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');
const { root, shellRuntime } = require('./helpers.cjs');

// 在独立安装副本中映射路径与 UCI 目录，不给生产 RPC 增加测试参数。
function fixture(t) {
    const directory = fs.mkdtempSync('/tmp/hijpass-rpc-test-');
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const runtime = path.join(directory, 'runtime'), config = path.join(directory, 'config');
    const original = shellRuntime();
    fs.cpSync(original, runtime, { recursive: true });
    fs.mkdirSync(config);
    for (const name of fs.readdirSync(runtime, { recursive: true })) if (/\.(sh|uc)$/.test(name) || name === 'testbin/ucode') {
        const file = path.join(runtime, name);
        fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replaceAll(original, runtime));
    }
    for (const name of ['rpc/files.uc', 'rpc/data.uc']) {
        const file = path.join(runtime, name);
        fs.writeFileSync(file, fs.readFileSync(file, 'utf8')
            .replace("import { read } from 'hijpass.uci.read';", `import { read as readConfig } from 'hijpass.uci.read';
function read(packageName) { return readConfig(packageName, '${config}'); }`));
    }
    const common = path.join(runtime, 'common.sh');
    fs.writeFileSync(common, fs.readFileSync(common, 'utf8').replaceAll(runtime + '/jobs', path.join(directory, 'jobs')));
    const rules = path.join(directory, 'firewall.ut');
    fs.copyFileSync(path.join(root, 'root/etc/hijpass/firewall.ut'), rules);
    const editor = path.join(directory, 'direct.txt'), log = path.join(directory, 'original-node.log');
    const pathsFile = path.join(runtime, 'ucode/hijpass/config/paths.uc');
    fs.writeFileSync(pathsFile, fs.readFileSync(pathsFile, 'utf8')
        .replaceAll('/etc/hijpass/client', directory).replaceAll('/etc/hijpass/firewall.ut', rules)
        .replaceAll('/etc/hijpass/rules/ip-direct.txt', editor)
        .replaceAll('/etc/hijpass/shunt.json', directory + '/shunt.json')
        .replaceAll('/tmp/hijpass/log', directory)
        .replaceAll('/tmp/hijserver/log', directory + '/server-logs'));
    fs.writeFileSync(editor, 'original\n');
    fs.writeFileSync(log, 'first\nsecond\nthird\n');
    fs.writeFileSync(path.join(config, 'hijpass'), `config hijpass 'global'
 option client_dir '/untrusted/client'
 option firewall_template '/untrusted/template'
 option ip_direct '/untrusted/rules'
 option shunt_conf '/untrusted/shunt'
config proxy_node 'node'
 option name 'original'
 option log_enabled '1'
 option log_path '/untrusted/log'
`);
    fs.writeFileSync(path.join(config, 'hijserver'), "config hijserver 'global'\n");
    const entry = path.join(runtime, 'rpc/entry.sh');
    fs.writeFileSync(entry, fs.readFileSync(path.join(root, 'root/usr/libexec/rpcd/hijpass'), 'utf8')
        .replaceAll('/usr/lib/hijpass', runtime));
    function invoke(method, request = {}) {
        const result = spawnSync('/usr/bin/busybox', ['ash', entry, ...(method === 'list' ? ['list'] : ['call', method])], {
            encoding: 'utf8', input: JSON.stringify(request),
            env: { ...process.env, PATH: path.join(runtime, 'testbin') + ':' + process.env.PATH },
        });
        assert.equal(result.status, 0, result.stderr);
        return JSON.parse(result.stdout);
    }
    return { invoke, directory, runtime, rules, editor, log };
}

test('RPC serves an immutable default and no longer transports editor content', t => {
    const f = fixture(t), schema = f.invoke('list');
    assert.ok(schema.firewall_template_default);
    assert.equal(schema.editor_read, undefined);
    assert.equal(schema.editor_write, undefined);
    const original = fs.readFileSync(f.rules, 'utf8');
    fs.writeFileSync(f.rules, 'changed template');
    assert.equal(f.invoke('firewall_template_default').content, original);
    fs.unlinkSync(path.join(f.runtime, 'firewall/default.ut'));
    assert.match(f.invoke('firewall_template_default').error, /cannot read/);
    assert.equal(f.invoke('not_a_method').error, 'unknown RPC method');
});

test('one RPC object exposes configuration preview and validation with matching ACLs', t => {
    const f = fixture(t), schema = f.invoke('list');
    assert.deepEqual(schema.config_render, { sections: '', target: '' });
    assert.deepEqual(schema.config_validate, { sections: '' });
    assert.equal(schema.config_write, undefined);
    assert.equal(schema.service_apply_status, undefined);
    assert.throws(() => fs.lstatSync(path.join(root, 'root/usr/libexec/rpcd/hijpass-config')), { code: 'ENOENT' });
    const acl = JSON.parse(fs.readFileSync(path.join(root, 'root/usr/share/rpcd/acl.d/luci-app-hijpass.json'), 'utf8'))['luci-app-hijpass'];
    assert.equal(acl.write.ubus['hijpass-config'], undefined);
    for (const method of ['config_render', 'config_validate']) assert.ok(acl.write.ubus.hijpass.includes(method));

    const sections = require('./testdata/compatibility.json').find(f => f.name === 'sing-box-chain').sections;
    const snapshot = JSON.stringify(sections);
    const full = f.invoke('config_render', { sections: snapshot });
    assert.equal(full.error, undefined, full.error);
    assert.deepEqual(f.invoke('config_render', { sections: snapshot, target: 'downstream' }).config, full.nodes.downstream);
    const routing = require('./testdata/compatibility.json').find(f => f.name === 'sing-box-shunt-default');
    const routingSections = structuredClone(routing.sections);
    routingSections.find(section => section['.type'] === 'shunt')['.name'] = 'cfg123456';
    assert.deepEqual(f.invoke('config_render', { sections: JSON.stringify(routingSections), target: 'cfg123456' }),
        { config: routing.expected.shunt });
    assert.deepEqual(f.invoke('config_validate', { sections: snapshot }), { ok: true });
    assert.equal(fs.existsSync(path.join(f.directory, 'downstream-downstream.json')), false);
    assert.match(f.invoke('config_render', { sections: snapshot, target: 'missing' }).error, /not found/);
    assert.ok(f.invoke('config_validate', { sections: '' }).error);
    assert.ok(f.invoke('config_render', { sections: '{}' }).error);
    assert.match(f.invoke('config_render', { sections: 1 }).error, /invalid RPC argument/);

    fs.writeFileSync(path.join(f.directory, 'config/hijpass'), "config hijpass 'global'\n option enabled '0'\n");
    assert.deepEqual(f.invoke('config_validate'), { ok: true });
    assert.ok(f.invoke('config_validate', { sections: '' }).error);
});

test('RPC logs use section identities and preserve tail, download and clear behavior', t => {
    const f = fixture(t), id = 'hijpass:node';
    assert.deepEqual(f.invoke('log_list').logs, [{ id: 'hijpass:global', name: 'global', kind: 'main' }, { id, name: 'original', kind: 'proxy' }]);
    assert.equal(f.invoke('log_read', { id, action: 'read', lines: '2' }).content, 'second\nthird\n');
    assert.deepEqual(f.invoke('log_read', { id, action: 'download' }), { content: 'first\nsecond\nthird\n', name: 'original-node.log' });
    for (const request of [{ id: '/etc/shadow', action: 'read', lines: '2' }, { id, action: 'read', lines: '-1' }])
        assert.ok(f.invoke('log_read', request).error);
    assert.ok(f.invoke('log_read', { id, action: 'clear' }).error);
    assert.equal(fs.readFileSync(f.log, 'utf8'), 'first\nsecond\nthird\n');
    assert.equal(f.invoke('log_clear', { id }).ok, true);
    assert.equal(fs.readFileSync(f.log, 'utf8'), '');
});

for (const packageName of ['hijpass', 'hijserver']) test(`RPC ${packageName} treats missing logs as empty and reads newly created logs on refresh`, t => {
    const f = fixture(t), id = packageName + ':node';
    const log = packageName === 'hijpass' ? f.log : path.join(f.directory, 'server-logs/original-node.log');
    if (packageName === 'hijserver') {
        fs.appendFileSync(path.join(f.directory, 'config/hijserver'), "config server_node 'node'\n option name 'original'\n option log_enabled '1'\n");
    } else {
        fs.unlinkSync(log);
    }
    const request = { id, action: 'read', lines: '200' };
    assert.deepEqual(f.invoke('log_read', request), { content: '' });
    assert.equal(fs.existsSync(log), false);
    assert.ok(f.invoke('log_read', { ...request, lines: '-1' }).error);
    assert.ok(f.invoke('log_read', { ...request, id: packageName + ':unknown' }).error);
    assert.ok(f.invoke('log_read', { id, action: 'download' }).error);
    fs.mkdirSync(path.dirname(log), { recursive: true });
    fs.writeFileSync(log, 'new log after startup\n');
    assert.equal(f.invoke('log_read', request).content, 'new log after startup\n');
    // 无法打开的文件不能被误当作“暂无日志”。
    fs.unlinkSync(log);
    fs.symlinkSync(log, log);
    assert.match(f.invoke('log_read', request).error, /cannot open log:/);
});

test('Shell RPC keeps arguments separate and returns real command failures', t => {
    const f = fixture(t);
    fs.writeFileSync(path.join(f.runtime, 'rules/geoview.sh'), '#!/bin/sh\nprintf "%s\\n" "$@"\nprintf "failure" >&2\nexit 7\n', { mode: 0o755 });
    const keyword = "a b;$(touch /tmp/hijpass-never-created)";
    const response = f.invoke('geo_lookup', { type: 'geosite', mode: 'expand', keyword });
    assert.deepEqual(response, { code: 7, stdout: '-e\ngeosite\n' + keyword, stderr: 'failure' });
    assert.ok(f.invoke('geo_lookup', { type: 'file', mode: 'expand', keyword }).error);
    assert.ok(f.invoke('core_version', { core: 'xray;id' }).error);
    assert.ok(f.invoke('trace_start', { args: ['-t', {}] }).error);
});

test('RPC encodes large command output from files and removes its capture directory', t => {
    const f = fixture(t), entry = path.join(f.runtime, 'rpc/entry.sh');
    fs.writeFileSync(entry, fs.readFileSync(entry, 'utf8')
        .replace('/tmp/hijpass-rpc.XXXXXX', path.join(f.directory, 'capture.XXXXXX')));
    const stdout = 'rule "quoted" \\ 规则\tvalue\n'.repeat(8000) + 'tail \n\n';
    const stderr = 'failure "quoted" \\ 失败\n'.repeat(8000) + '\n';
    fs.writeFileSync(path.join(f.runtime, 'testbin/nft'), `#!/bin/sh
cat '${f.directory}/stdout'
cat '${f.directory}/stderr' >&2
exit "$(cat '${f.directory}/code')"
`, { mode: 0o755 });
    for (const [out, err, code] of [[stdout, '', 0], ['', stderr, 7], [stdout, stderr, 9]]) {
        fs.writeFileSync(path.join(f.directory, 'stdout'), out);
        fs.writeFileSync(path.join(f.directory, 'stderr'), err);
        fs.writeFileSync(path.join(f.directory, 'code'), String(code));
        const response = f.invoke('firewall_show');
        assert.equal(response.code, code);
        assert.equal(response.stdout, out.replace(/\n+$/, ''));
        assert.equal(response.stderr, err.replace(/\n+$/, ''));
        assert.equal(fs.readdirSync(f.directory).some(name => name.startsWith('capture.')), false);
    }
});

test('RPC returns large stderr when a structured command produces no response', t => {
    const f = fixture(t), stderr = 'upstream failure "quoted" \\ 失败\n'.repeat(8000);
    fs.writeFileSync(path.join(f.directory, 'failure'), stderr);
    fs.writeFileSync(path.join(f.runtime, 'network/network.sh'), `#!/bin/sh
cat '${f.directory}/failure' >&2
exit 1
`);
    const response = f.invoke('network_connect', { url: 'https://example.org', timeout: '5' });
    assert.equal(response.success, false);
    assert.equal(response.error, stderr.replace(/\n+$/, ''));
});

test('completed jobs return large stdout and stderr without environment-variable limits', t => {
    const f = fixture(t), id = 'Large123', job = path.join(f.directory, 'jobs', id);
    fs.mkdirSync(job, { recursive: true });
    const stdout = 'updated "rule" \\ 规则\n'.repeat(8000);
    const stderr = 'warning "quoted" \\ 警告\n'.repeat(8000);
    fs.writeFileSync(path.join(job, 'stdout'), stdout);
    fs.writeFileSync(path.join(job, 'stderr'), stderr);
    fs.writeFileSync(path.join(job, 'exit'), '7\n');
    const response = f.invoke('job_status', { id });
    assert.equal(response.running, false);
    assert.equal(response.code, 7);
    assert.equal(response.stdout, stdout.replace(/\n+$/, ''));
    assert.equal(response.stderr, stderr.replace(/\n+$/, ''));
    assert.equal(fs.existsSync(job), true);
    assert.equal(f.invoke('job_status', { id }).code, 7);
});

test('jobs whose worker exits before producing output still return the recorded failure', t => {
    const f = fixture(t), daemon = path.join(f.runtime, 'testbin/start-stop-daemon');
    fs.writeFileSync(daemon, `#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = -p ]; then printf '2147483647\\n' >"$2"; exit 0; fi
    shift
done
exit 1
`, { mode: 0o755 });
    // BusyBox ash 优先使用内置 applet，在安装副本中显式指定测试命令。
    const jobs = path.join(f.runtime, 'rpc/jobs.sh');
    fs.writeFileSync(jobs, fs.readFileSync(jobs, 'utf8').replace('exec start-stop-daemon ', `exec '${daemon}' `));
    const start = f.invoke('core_update', { core: 'xray' });
    assert.deepEqual(f.invoke('job_status', { id: start.id }), {
        running: false, code: 1, stdout: '', stderr: 'job exited without a result',
    });
});

test('backend writes preserve TLS while resolving chains and reject snapshot storage paths', t => {
    const fixtures = require('./testdata/compatibility.json');
    for (const core of ['xray', 'sing-box']) {
        const f = fixture(t);
        const prepare = path.join(f.runtime, 'service/prepare.uc');
        fs.writeFileSync(prepare, fs.readFileSync(prepare, 'utf8').replace("import { resolve } from '../network/network.uc';",
            "function resolve(host) { if (host == 'fail.example.org') die('DNS failed'); return '192.0.2.10'; }"));
        const sections = structuredClone(fixtures.find(f => f.name === 'sing-box-chain').sections);
        sections[0].client_dir = path.join(f.directory, 'untrusted');
        for (const node of sections.slice(1)) node.core = core;
        const downstream = sections[2];
        downstream.tls_server_name = 'tls.example.org';
        const input = path.join(f.directory, 'sections.json');
        const entry = path.join(f.runtime, 'write-test.uc');
        fs.writeFileSync(entry, "import { generateAndWriteConfigs } from './service/prepare.uc'; import * as fs from 'fs'; generateAndWriteConfigs(json(fs.readfile(ARGV[0])));");
        function write() {
            fs.writeFileSync(input, JSON.stringify(sections));
            return spawnSync(path.join(f.runtime, 'testbin/ucode'), ['-S', '--', entry, input], { encoding: 'utf8' });
        }
        const result = write();
        assert.equal(result.status, 0, result.stderr);
        assert.equal(fs.existsSync(sections[0].client_dir), false);
        const target = path.join(f.directory, 'downstream-downstream.json');
        const content = fs.readFileSync(target, 'utf8'), outbound = JSON.parse(content).outbounds[0];
        if (core === 'sing-box') {
            assert.equal(outbound.server, '192.0.2.10');
            assert.equal(outbound.tls.server_name, 'tls.example.org');
        } else {
            assert.equal(outbound.settings.address, '192.0.2.10');
            assert.equal(outbound.streamSettings.tlsSettings.serverName, 'tls.example.org');
        }
        downstream.server = 'fail.example.org';
        assert.match(write().stderr, /DNS failed/);
        assert.equal(fs.readFileSync(target, 'utf8'), content);
    }
});

test('download jobs return immediately, publish results for repeated reads', async t => {
    const f = fixture(t);
    fs.writeFileSync(path.join(f.runtime, 'core/update.sh'), `#!/bin/sh
. '${f.runtime}/common.sh'
sleep 0.1
download() {
    echo 'Warning: optional hook unavailable: https://user:private@example.org/path?token=private' >&2
    printf '{"success":true,"version":"test"}\\n'
}
hijpass_run_logged 'Download' download
`, { mode: 0o755 });
    const start = f.invoke('core_update', { core: 'xray' });
    assert.match(start.id, /^[A-Za-z0-9]{8}$/);
    let status;
    for (let i = 0; i < 40; i++) {
        status = f.invoke('job_status', { id: start.id });
        if (!status.running) break;
        await new Promise(resolve => setTimeout(resolve, 50));
    }
    assert.equal(status.running, false);
    assert.equal(status.code, 0, status.stderr);
    assert.equal(JSON.parse(status.stdout).version, 'test');
    assert.equal(status.stderr, '');
    assert.equal(f.invoke('job_status', { id: start.id }).code, 0);
    const log = fs.readFileSync(path.join(f.directory, 'hijpass.log'), 'utf8');
    assert.match(log, /WARN\s+Download: Warning:/);
    assert.match(log, /optional hook unavailable/);
    assert.doesNotMatch(log, /\[job\]|task=|diagnostic output/);
    assert.doesNotMatch(log, /private|https:\/\//);
});

for (const fail of ['', 'generate', 'reload']) test(`firewall_reset RPC 在生成成功后重载并返回真实状态：${fail || '正常'}`, t => {
    const f = fixture(t), events = f.directory + '/events';
    fs.writeFileSync(f.runtime + '/firewall/generatecli.uc', `import * as fs from 'fs';
let file = fs.open('${events}', 'a'); file.write('generate\\n'); file.close();
${fail === 'generate' ? "warn('generation failed'); exit(1);" : ''}
`);
    fs.writeFileSync(f.runtime + '/testbin/fw4', `#!/bin/sh
echo "$1" >>'${events}'
exit ${fail === 'reload' ? 7 : 0}
`, { mode: 0o755 });
    const response = f.invoke('firewall_reset');
    assert.equal(response.code, fail === 'generate' ? 1 : fail === 'reload' ? 7 : 0);
    assert.equal(response.stdout, '');
    assert.deepEqual(fs.readFileSync(events, 'utf8').trim().split('\n'), fail === 'generate' ? ['generate'] : ['generate', 'reload']);
    if (fail) assert.match(response.stderr, /failed; see main log/);
    else assert.equal(response.stderr, '');
});
