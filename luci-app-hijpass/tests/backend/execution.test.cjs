const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawn, spawnSync } = require('node:child_process');
const { root, interpreter, shellRuntime, withConfig } = require('./helpers.cjs');

// 只在安装副本中替换系统路径，生产代码不增加测试开关或模拟逻辑。
function fixture(t) {
    const directory = fs.mkdtempSync('/tmp/hijpass-execution-test-');
    const runtime = path.join(directory, 'runtime');
    const sourceRuntime = shellRuntime();
    fs.cpSync(sourceRuntime, runtime, { recursive: true });
    // 各场景使用独立的安装副本，避免路径仍指向共享测试目录。
    for (const file of fs.readdirSync(runtime, { recursive: true })) if (file.endsWith('.sh') || file.endsWith('.uc') || file === 'testbin/ucode') {
        const target = path.join(runtime, file);
        fs.writeFileSync(target, fs.readFileSync(target, 'utf8').replaceAll(sourceRuntime, runtime));
    }
    for (const service of ['hijpass', 'hijserver'])
        fs.writeFileSync(path.join(runtime, 'init-' + service + '.sh'),
            fs.readFileSync(path.join(root, 'root/etc/init.d', service), 'utf8').replaceAll('/usr/lib/hijpass', runtime));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    function patch(file, before, after) {
        const target = path.join(runtime, file);
        fs.writeFileSync(target, fs.readFileSync(target, 'utf8').replaceAll(before, after));
    }
    function script(name, body) {
        fs.writeFileSync(path.join(directory, name), '#!/bin/sh\n' + body + '\n', { mode: 0o755 });
    }
    function run(file, args, extra = {}) {
        return spawnSync('/usr/bin/busybox', ['ash', path.join(runtime, file), ...args], {
            encoding: 'utf8', env: { ...process.env, ...extra,
                PATH: `${directory}:${runtime}/testbin:${process.env.PATH}` },
        });
    }
    function data(file, args, extra = {}) {
        return spawnSync(interpreter, ['-S', '-L', path.join(runtime, 'ucode'), '--', path.join(runtime, file), ...args],
            { encoding: 'utf8', env: { ...process.env, ...extra, PATH: `${directory}:${runtime}/testbin:${process.env.PATH}` } });
    }
    patch('ucode/hijpass/config/paths.uc', '/tmp/hijpass/log', directory + '/logs');
    patch('service/cron.sh', '/etc/crontabs/root', directory + '/crontab');
    patch('firewall/firewall.sh', '/etc/hijpass/fw4-rules.nft', directory + '/rules.nft');
    patch('testbin/ucode', 'exec ', `has_config=0
for arg in "$@"; do [ "$arg" != --configdir ] || has_config=1; done
if [ -n "$HIJPASS_TEST_CONFIG" ] && [ "$has_config" = 0 ]; then set -- "$@" --configdir "$HIJPASS_TEST_CONFIG"; fi
exec `);
    function launch(file, args, extra = {}) {
        const child = spawn('/usr/bin/busybox', ['ash', path.join(runtime, file), ...args], {
            env: { ...process.env, ...extra, PATH: `${directory}:${runtime}/testbin:${process.env.PATH}` },
        });
        let stdout = '', stderr = '';
        child.stdout.on('data', data => { stdout += data; });
        child.stderr.on('data', data => { stderr += data; });
        const result = new Promise((resolve, reject) => {
            child.on('error', reject);
            child.on('close', (status, signal) => resolve({ status, signal, stdout, stderr }));
        });
        return { child, result };
    }
    function init(service, action, config, extra = {}) {
        const driver = 'init-callback.sh';
        const quoted = value => "'" + value.replaceAll("'", "'\\''") + "'";
        fs.writeFileSync(path.join(runtime, driver), `#!/bin/sh
. ${quoted(path.join(runtime, 'init-' + service + '.sh'))}
config_directory=${quoted(config)}
instances=1
cron_log=\${CRON_LOG:-0}
uci() { command uci -c "$config_directory" "$@"; }
# 此处仅测回调内的真实功能脚本；原生 stop/kill 链路由 lifecycle.test.cjs 覆盖。
stop() { :; }
"$1" "\${CRON_ACTION:-}"
`);
        return run(driver, [action], { ...extra, HIJPASS_TEST_CONFIG: config });
    }
    return { directory, runtime, patch, script, run, data, launch, init };
}

async function until(condition) {
    for (let i = 0; i < 300; i++) {
        if (condition()) return;
        await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert.fail('timed out waiting for execution fixture');
}

test('主日志按配置级别筛选，保留多行上下文并脱敏 URL 和凭据', t => {
    const f = fixture(t), log = path.join(f.directory, 'logs/hijpass.log');
    withConfig([{ '.type': 'hijpass', log_level: 'WARN' }], config => {
        const args = ['--configdir', config];
        assert.equal(f.run('maintenance/logs.sh', ['append', 'INFO', 'hidden', ...args]).status, 0);
        const result = f.run('maintenance/logs.sh', ['append', 'WARN',
            '[test] failed https://user:private@example.org/file?token=private\npassword=another-private\ncontinuation', ...args]);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout, '');
        assert.equal(result.stderr, '');
    });
    const content = fs.readFileSync(log, 'utf8');
    assert.match(content, /WARN\s+\[test\]\s+failed \[URL redacted\]\n +password=\[redacted\]\n +continuation/);
    assert.doesNotMatch(content, /hidden|private|https:\/\//);
});

for (const level of ['DEBUG', 'INFO', 'WARN', 'ERROR']) test(`服务端准备与迁移日志遵循主日志配置：${level}`, t => {
    const f = fixture(t), logFile = path.join(f.directory, 'logs/hijpass.log');
    withConfig([{ '.type': 'hijpass', log_level: level, schema_version: '4', nft: '/legacy/template.nft' }], config => {
        fs.writeFileSync(config + '/hijserver', "config hijserver\n option enabled '0'\n");
        for (const action of ['configs', 'prepare']) {
            const result = f.data('service/preparecli.uc', ['server', action, '--configdir', config]);
            assert.equal(result.status, 0, result.stderr);
        }
        const migrated = f.data('install/migrate.uc', ['--configdir', config]);
        assert.equal(migrated.status, 0, migrated.stderr);
        assert.match(migrated.stderr, /requires manual migration/);
    });
    const content = fs.existsSync(logFile) ? fs.readFileSync(logFile, 'utf8') : '';
    if (level === 'DEBUG' || level === 'INFO') {
        assert.match(content, /Wrote 0 hijserver core JSON configuration files/);
        assert.match(content, /Prepared 0 hijserver process instance\(s\)/);
        assert.match(content, /Schema migration started/);
        assert.match(content, /Schema migration completed/);
    } else assert.doesNotMatch(content, /INFO|Wrote|Prepared|Schema migration/);
    if (level !== 'ERROR') assert.match(content, /WARN.*Legacy firewall template requires manual migration/);
    else assert.equal(content, '');
    if (level === 'DEBUG') {
        for (const line of content.trim().split('\n'))
            assert.match(line, /(?:service\/prepare|install\/migrate)\.uc:\d+\s+\S/);
    } else assert.doesNotMatch(content, /\.uc:\d+/);
});

test('日志目录不可写或磁盘写入失败时回退系统日志，追加命令保持成功', t => {
    const f = fixture(t), fallback = path.join(f.directory, 'fallback');
    f.script('logger', 'printf "%s\\n" "$@" >>"$TEST_FALLBACK"');
    fs.writeFileSync(path.join(f.directory, 'logs'), 'not a directory');
    const args = ['append', 'ERROR', '[test] diagnostic https://user:private@example.org/?token=private'];
    for (const full of [false, true]) {
        if (full) f.patch('maintenance/logs.uc', "path = logPath({ '.type': 'hijpass' })", "path = '/dev/full'");
        const result = f.run('maintenance/logs.sh', args, { TEST_FALLBACK: fallback });
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout, '');
        assert.equal(result.stderr, '');
    }
    const content = fs.readFileSync(fallback, 'utf8');
    assert.equal(content.split('ERROR [test] diagnostic').length - 1, 2);
    assert.doesNotMatch(content, /private|https:\/\//);
});

test('规则更新主日志记录备用来源、合并数量和结果，stdout 仍为单个 JSON', t => {
    const f = fixture(t);
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', f.directory + '/rules');
    f.script('curl', `while [ "$1" != -o ]; do shift; done
output=$2
case "$*" in *unavailable*) echo 'curl: unavailable' >&2; exit 28 ;; esac
i=0; while [ "$i" -lt 10 ]; do echo server=/example.org/1.1.1.1; i=$((i+1)); done >"$output"`);
    withConfig([{ '.type': 'hijpass', enabled: '0' }, { '.type': 'rule', retry_count: '1',
        chn_domain_list: ['https://example.org/unavailable', 'https://example.org/valid'] }], config => {
        const result = f.run('rules/update.sh', ['chnlist', '--configdir', config]);
        assert.equal(result.status, 0, result.stderr);
        assert.deepEqual(JSON.parse(result.stdout), { success: true });
    });
    const content = fs.readFileSync(path.join(f.directory, 'logs/hijpass.log'), 'utf8');
    assert.match(content, /WARN\s+chn_domain_list: source 1 unavailable/);
    assert.match(content, /sources=1\/2, bytes=12, entries=1/);
    assert.match(content, /Rule update finished: installed=1, failed=0, elapsed=\d+s/);
});

test('直接启动服务时成功 Hook 的 stderr 也保留为告警，不改变激活结果', t => {
    const f = fixture(t), hook = path.join(f.directory, 'dns-hook');
    f.script('dns-hook', "echo 'Warning: optional DNS service unavailable' >&2\nexit 0");
    for (const file of ['firewall/route.sh'])
        fs.writeFileSync(path.join(f.runtime, file), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    f.script('fw4', 'exit 0');
    f.script('cron-init', 'exit 0');
    f.patch('init-hijpass.sh', '/etc/init.d/cron', path.join(f.directory, 'cron-init'));
    f.patch('service/cron.sh', '/etc/crontabs/root', path.join(f.directory, 'crontab'));
    f.patch('init-hijpass.sh', '/etc/hijpass/hook/dns-hook.sh', hook);
    withConfig([{ '.type': 'hijpass', enabled: '1' }], config => {
        const result = f.init('hijpass', 'service_started', config);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout, '');
        assert.equal(result.stderr, '');
    });
    const content = fs.readFileSync(path.join(f.directory, 'logs/hijpass.log'), 'utf8');
    assert.match(content, /WARN\s+DNS Hook start: Warning:/);
    assert.match(content, /optional DNS service unavailable/);
    assert.doesNotMatch(content, /Service started/);
});

test('第三方普通输出只在 DEBUG 显示，告警和失败详情保留且不改变退出状态', t => {
    const f = fixture(t), entry = path.join(f.runtime, 'step-test.sh');
    fs.writeFileSync(entry, `#!/bin/sh
. '${f.runtime}/common.sh'
config_directory=$1
hijpass_run_logged 'command phase' '${f.directory}/diagnostic-command'
`);
    f.script('diagnostic-command', 'printf "%s\\n" "$TEST_DIAGNOSTIC" >&2\nexit "$TEST_STATUS"');
    const cases = [['[I] firewall feature enabled', '0', null, 'INFO'],
        ['normal output', '0', null, 'INFO'],
        ['[I] firewall feature enabled', '0', 'DEBUG', 'DEBUG'],
        ['[I] informational\nWarning: hook failed', '0', 'WARN', 'INFO'],
        ['[W] optional feature unavailable', '0', 'WARN', 'INFO'],
        ['[E] optional operation failed', '0', 'ERROR', 'INFO'],
        ['[I] firewall feature enabled', '7', 'ERROR', 'INFO'],
        ['failed operation', '7', 'ERROR', 'INFO']];
    const logFile = path.join(f.directory, 'logs/hijpass.log');
    for (const [message, code, level, mode] of cases) {
        withConfig([{ '.type': 'hijpass', log_level: mode }], config => {
            const result = f.run('step-test.sh', [config], { TEST_DIAGNOSTIC: message, TEST_STATUS: code });
            assert.equal(result.status, Number(code), result.stderr);
            assert.equal(result.stdout, '');
            assert.equal(result.stderr, code === '0' ? '' : 'command phase failed; see main log\n');
        });
        const content = fs.existsSync(logFile) ? fs.readFileSync(logFile, 'utf8') : '';
        if (level) assert.match(content, new RegExp(`${level}.*command phase:`));
        else assert.equal(content, '');
        assert.doesNotMatch(content, /\[I\]|\[W\]|\[E\]|diagnostic output/);
        if (code !== '0') assert.match(content, new RegExp(`ERROR.*command phase failed: exit=${code}`));
        else if (mode !== 'DEBUG') assert.doesNotMatch(content, /exit=|informational/);
        assert.equal(content.split('firewall feature enabled').length - 1,
            level && message.includes('firewall feature enabled') ? 1 : 0);
        fs.rmSync(logFile, { force: true });
    }
});

test('DEBUG 显示 Shell 脚本路径和自动获取的 ucode 调用位置，普通模式只显示正文', t => {
    const f = fixture(t), entry = path.join(f.runtime, 'debug-call.sh');
    fs.writeFileSync(entry, `. '${f.runtime}/common.sh'\nconfig_directory=$1\nhijpass_log INFO 'shell location'\n`);
    withConfig([{ '.type': 'hijpass', log_level: 'DEBUG' }], config => {
        assert.equal(f.run('debug-call.sh', [config], {
            HIJPASS_TASK_ID: 'Test1234', HIJPASS_LOG_SOURCE: '/etc/init.d/parent',
        }).status, 0);
    });
    const native = path.join(f.runtime, 'debug-call.uc');
    fs.writeFileSync(native, `import { logger } from './maintenance/logs.uc';
let log = logger([{ '.type': 'hijpass', log_level: 'DEBUG' }]);
function business() {
    log('WARN', 'ucode location');
}
business();\n`);
    assert.equal(f.data('debug-call.uc', []).status, 0);
    const log = path.join(f.directory, 'logs/hijpass.log');
    let content = fs.readFileSync(log, 'utf8');
    assert.doesNotMatch(content, /task=|Test1234|debug-call\.sh:\d|\[test\]/);
    assert.ok(content.includes(`${entry} `) && /debug-call\.sh\s+shell location/.test(content), content);
    assert.ok(content.includes(`${native}:4`) && /:4\s+ucode location/.test(content), content);
    fs.writeFileSync(log, '');
    withConfig([{ '.type': 'hijpass', log_level: 'INFO' }], config => {
        assert.equal(f.run('debug-call.sh', [config], { HIJPASS_TASK_ID: 'Test1234' }).status, 0);
    });
    content = fs.readFileSync(log, 'utf8');
    assert.match(content, /INFO\s+shell location/);
    assert.doesNotMatch(content, /debug-call|task=/);
});

test('配置提交失败后继续恢复其余文件，同时保留原错误和回滚失败原因', t => {
    const f = fixture(t), first = path.join(f.directory, 'first.json'), second = path.join(f.directory, 'second.json');
    const blocked = path.join(f.directory, 'blocked');
    fs.writeFileSync(first, 'first-original'); fs.writeFileSync(second, 'second-original'); fs.mkdirSync(blocked);
    f.patch('service/prepare.uc', "import { atomic, command, temporary, renderTemplate } from 'hijpass.common';",
        `import { atomic as writeAtomic, command, temporary, renderTemplate } from 'hijpass.common';
function atomic(path, data, mode) {
    if (path == '${second}' && data == 'second-original') die('restore second failed');
    return writeAtomic(path, data, mode);
}`);
    fs.writeFileSync(path.join(f.runtime, 'write-test.uc'), `import { writeConfigs } from './service/prepare.uc';
writeConfigs([{ path: '${first}', data: 'first-new' }, { path: '${second}', data: 'second-new' }, { path: '${blocked}', data: 'blocked' }]);`);
    const result = f.data('write-test.uc', []);
    assert.notEqual(result.status, 0, result.stderr);
    assert.match(result.stderr, /cannot replace .*blocked; rollback incomplete: restore second failed/);
    assert.equal(fs.readFileSync(first, 'utf8'), 'first-original');
    assert.equal(fs.readFileSync(second, 'utf8'), 'second-new');
    assert.equal(fs.readdirSync(f.directory).some(name => name.includes('.new-')), false);
});

test('Geo 更新验证下载内容，失败保留旧库，有效备用来源才替换', t => {
    const f = fixture(t), target = path.join(f.directory, 'v2ray');
    fs.mkdirSync(target);
    f.patch('rules/rules.uc', '/usr/share/v2ray', target);
    for (const database of ['geoip', 'geosite']) fs.writeFileSync(path.join(target, database + '.dat'), 'old-' + database);
    const invalid = path.join(f.directory, 'invalid'), valid = path.join(f.directory, 'valid');
    fs.writeFileSync(invalid, '<html>' + 'error'.repeat(50) + '</html>');
    fs.writeFileSync(valid, 'verified-database'.repeat(20));
    f.script('curl', `while [ "$1" != -o ]; do shift; done
output=$2
shift 2
[ "$1" != -- ] || shift
case "$1" in
    *invalid) cp "$INVALID_DOWNLOAD" "$output" ;;
    *valid) cp "$VALID_DOWNLOAD" "$output" ;;
    *) exit 22 ;;
esac`);
    f.script('geoview', `while [ "$1" != -input ]; do shift; done
cmp -s "$2" "$VALID_DOWNLOAD"`);
    const sections = [{ '.type': 'hijpass', enabled: '0' },
        { '.type': 'rule', retry_count: '1', geoip: ['https://example.org/invalid'], geosite: ['https://example.org/invalid'] }];
    const env = { INVALID_DOWNLOAD: invalid, VALID_DOWNLOAD: valid };
    withConfig(sections, config => {
        const failed = f.run('rules/update.sh', ['geo', '--configdir', config], env);
        assert.equal(failed.status, 1, failed.stderr);
        assert.deepEqual(JSON.parse(failed.stdout), { success: false, failed: ['geosite'] });
        for (const database of ['geoip', 'geosite']) assert.equal(fs.readFileSync(path.join(target, database + '.dat'), 'utf8'), 'old-' + database);
    });
    sections[1].geoip.push('https://example.org/valid');
    sections[1].geosite.push('https://example.org/valid');
    withConfig(sections, config => {
        const updated = f.run('rules/update.sh', ['geo', '--configdir', config], env);
        assert.equal(updated.status, 0, updated.stderr);
        assert.deepEqual(JSON.parse(updated.stdout), { success: true });
        for (const database of ['geoip', 'geosite']) {
            const file = path.join(target, database + '.dat');
            assert.equal(fs.readFileSync(file, 'utf8'), fs.readFileSync(valid, 'utf8'));
            assert.equal(fs.statSync(file).mode & 0o777, 0o644);
        }
        assert.deepEqual(fs.readdirSync(target).sort(), ['geoip.dat', 'geosite.dat']);
    });
});

test('规则下载超时是整次传输时限，默认允许大文件下载并保留用户显式设置', t => {
    const f = fixture(t), calls = path.join(f.directory, 'curl-calls');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', f.directory + '/rules');
    f.script('curl', `while [ "$#" -gt 0 ]; do
case "$1" in
--connect-timeout) connect=$2; shift ;;
--max-time) total=$2; shift ;;
-o) output=$2; shift ;;
esac
shift
done
printf '%s %s\\n' "$connect" "$total" >>"$RULE_TEST_CALLS"
i=0; while [ "$i" -lt 10 ]; do echo server=/example.org/1.1.1.1; i=$((i+1)); done >"$output"`);
    for (const timeout of [undefined, '3', '90']) {
        const sections = [{ '.type': 'hijpass', enabled: '0' },
            { '.type': 'rule', retry_count: '1', chn_domain_list: ['https://example.org/domains'],
                ...(timeout ? { download_timeout: timeout } : {}) }];
        withConfig(sections, config => {
            const result = f.run('rules/update.sh', ['chnlist', '--configdir', config], { RULE_TEST_CALLS: calls });
            assert.equal(result.status, 0, result.stderr);
        });
    }
    assert.deepEqual(fs.readFileSync(calls, 'utf8').trim().split('\n'), ['10 120', '3 3', '10 90']);
});

test('规则下载重试成功不残留错误，全部重试失败只报告最后一次错误', t => {
    const f = fixture(t), calls = path.join(f.directory, 'attempts');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', f.directory + '/rules');
    f.script('sleep', 'exit 0');
    f.script('curl', `attempt=$(cat "$RULE_TEST_CALLS" 2>/dev/null || echo 0)
attempt=$((attempt + 1)); printf '%s' "$attempt" >"$RULE_TEST_CALLS"
if [ "$attempt" -eq 1 ] || [ "$RULE_TEST_FAIL_ALL" = 1 ]; then echo "curl: (28) timed out, attempt $attempt" >&2; exit 28; fi
while [ "$1" != -o ]; do shift; done
output=$2
i=0; while [ "$i" -lt 10 ]; do echo server=/example.org/1.1.1.1; i=$((i+1)); done >"$output"`);
    const sections = [{ '.type': 'hijpass', enabled: '0' },
        { '.type': 'rule', retry_count: '3', chn_domain_list: ['https://example.org/domains'] }];
    withConfig(sections, config => {
        const success = f.run('rules/update.sh', ['chnlist', '--configdir', config], { RULE_TEST_CALLS: calls });
        assert.equal(success.status, 0, success.stderr);
        assert.equal(success.stderr, '');
        assert.equal(fs.readFileSync(calls, 'utf8'), '2');
        fs.unlinkSync(calls);
        const failed = f.run('rules/update.sh', ['chnlist', '--configdir', config], { RULE_TEST_CALLS: calls, RULE_TEST_FAIL_ALL: '1' });
        assert.equal(failed.status, 1);
        assert.equal(failed.stderr, '');
        const log = fs.readFileSync(path.join(f.directory, 'logs/hijpass.log'), 'utf8');
        assert.match(log, /attempt 3/);
    });
});

test('规则全部下载失败时保留运行服务，不执行重启或 DNS Hook', t => {
    const f = fixture(t), calls = path.join(f.directory, 'restart-calls');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', f.directory + '/rules');
    f.patch('rules/rules.uc', '/usr/share/v2ray', f.directory + '/v2ray');
    f.patch('rules/update-files.sh', '/etc/init.d/hijpass', f.directory + '/hijpass-init');
    f.script('curl', 'echo "curl: (28) timed out" >&2\nexit 28');
    f.script('hijpass-init', 'printf restart >>"$RULE_TEST_CALLS"');
    const sections = [{ '.type': 'hijpass', enabled: '1' }, { '.type': 'rule', retry_count: '1',
        ...Object.fromEntries(['gfw_list', 'chn_domain_list', 'chn_v4_route', 'chn_v6_route', 'geoip', 'geosite']
            .map(key => [key, 'https://example.org/unavailable'])) }];
    withConfig(sections, config => {
        const result = f.run('rules/update.sh', ['update', '--configdir', config], { RULE_TEST_CALLS: calls });
        assert.equal(result.status, 1, result.stderr);
        assert.deepEqual(JSON.parse(result.stdout).failed, ['gfw_list']);
        assert.equal(fs.existsSync(calls), false);
    });
});

test('防火墙只绕过 WAN 区域，查询、生成、写入或校验失败保留旧规则并停止重载', t => {
    const f = fixture(t), rules = path.join(f.directory, 'rules with spaces.nft'), calls = path.join(f.directory, 'calls');
    f.patch('firewall/firewall.sh', `rules=${f.directory}/rules.nft`, `rules='${rules}'`);
    fs.writeFileSync(f.runtime + '/firewall/route.sh', '#!/bin/sh\nexit 0\n');
    f.script('dns-hook', 'exit 0');
    f.script('cron-init', 'exit 0');
    f.patch('init-hijpass.sh', '/etc/hijpass/hook/dns-hook.sh', f.directory + '/dns-hook');
    f.patch('init-hijpass.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.patch('service/cron.sh', '/etc/crontabs/root', f.directory + '/crontab');
    // 大于单参数长度上限的查询结果，直接从管道读取；VPN 设备不进入 WAN 绕过列表。
    fs.writeFileSync(f.directory + '/addresses', JSON.stringify([
        { ifname: 'wg0', addr_info: [{ family: 'inet', local: '192.168.1.1', prefixlen: 24 }] },
        { ifname: 'tun0', addr_info: [], padding: 'x'.repeat(150000) },
    ]));
    f.script('ip', `if [ "$BAD_NETWORK_JSON" = 1 ]; then echo invalid; else cat '${f.directory}/addresses'; fi
[ "$IP_FAIL" != 1 ]`);
    f.script('ubus', 'echo unexpected-query >>"$TEST_CALLS"; exit 1');
    f.script('fw4', `if [ "$1" = zone ]; then
[ "$2" = wan ] || exit 1
[ "$ZONE_FAIL" != 1 ] || exit 1
[ "$EMPTY_WAN" = 1 ] || echo wan0
exit 0
else echo reload >>"$TEST_CALLS"; fi`);
    f.script('nft', '[ "$NFT_FAIL" != 1 ]');
    const template = path.join(f.directory, 'firewall.ut');
    fs.copyFileSync(path.join(root, 'root/etc/hijpass/firewall.ut'), template);
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/firewall.ut', template);
    const sections = [{ '.type': 'hijpass' },
        { '.type': 'firewall', shunt_port: '18081', tproxy_proto: 'tcp,udp', acl_default_allow: '1' },
        { '.type': 'dns', dns_service: 'custom' }];
    withConfig(sections, config => {
        fs.writeFileSync(path.join(config, 'dhcp'), "config dnsmasq\n");
        fs.writeFileSync(rules, 'old rules');
        const apply = (extra = {}) => f.init('hijpass', 'service_started', config, { TEST_CALLS: calls, ...extra });
        const unchanged = result => {
            assert.equal(result.status, 0, result.stderr);
            assert.match(result.stderr, /Generate hijpass firewall rules failed/);
            assert.equal(fs.readFileSync(rules, 'utf8'), 'old rules');
            assert.equal(fs.existsSync(calls), false);
            assert.equal(fs.readdirSync(f.directory).some(name => name.startsWith('rules with spaces.nft.new-')), false);
        };
        for (const failure of [{ BAD_NETWORK_JSON: '1' }, { NFT_FAIL: '1' }, { IP_FAIL: '1' }, { ZONE_FAIL: '1' }])
            unchanged(apply(failure));
        const original = fs.readFileSync(template, 'utf8');
        for (const invalid of [null, '', '{# empty rules #}', '{% if (: %}']) {
            if (invalid === null) fs.unlinkSync(template); else fs.writeFileSync(template, invalid);
            unchanged(apply());
            fs.writeFileSync(template, original);
        }
        // 故障只注入安装副本，生产代码不添加测试路径。
        f.patch('firewall/generate.uc', "fs.open(temp, 'wx', 0o600)", "fs.open('/dev/full', 'w')");
        unchanged(apply());
        f.patch('firewall/generate.uc', "fs.open('/dev/full', 'w')", "fs.open(temp, 'wx', 0o600)");
        f.patch('firewall/generate.uc', 'fs.rename(temp, path)', 'false');
        unchanged(apply());
        f.patch('firewall/generate.uc', 'if (!false)', 'if (!fs.rename(temp, path))');
        const applied = apply();
        assert.equal(applied.status, 0, applied.stderr);
        let content = fs.readFileSync(rules, 'utf8');
        assert.match(content, /192\.168\.1\.1\/24/);
        assert.match(content, /iifname \{ "wan0" \} counter return/);
        assert.doesNotMatch(content, /wg0|tun0/);
        assert.equal(fs.readFileSync(calls, 'utf8'), 'reload\n');
        assert.equal(apply({ EMPTY_WAN: '1' }).status, 0);
        content = fs.readFileSync(rules, 'utf8');
        assert.doesNotMatch(content, /wan0|wg0|tun0|iifname \{\s*\}/);
    });
    withConfig([{ '.type': 'hijpass' }], config => {
        for (const args of [[], [''], [rules, 'extra']]) {
            const invalid = f.data('firewall/generatecli.uc', [...args, '--configdir', config]);
            assert.notEqual(invalid.status, 0);
            assert.match(invalid.stderr, /usage: generatecli.uc/);
            assert.equal(fs.existsSync(rules), true);
        }
        const disabled = f.data('firewall/generatecli.uc', [rules, '--configdir', config], { ZONE_FAIL: '1', IP_FAIL: '1' });
        assert.equal(disabled.status, 0, disabled.stderr);
        assert.equal(fs.existsSync(rules), false);
    });
});

for (const fail of ['', 'delete', 'apply', 'hook']) test(`fw4 include 只加载规则和 Hook，${fail || '正常'}分支保持顺序`, t => {
    const f = fixture(t), rules = f.directory + '/rules.nft', events = f.directory + '/events';
    f.patch('firewall/fw4.sh', '/etc/hijpass/fw4-rules.nft', rules);
    f.patch('firewall/fw4.sh', '/etc/hijpass/hook/nft-hook.sh', f.directory + '/nft-hook');
    fs.writeFileSync(rules, 'rules');
    f.script('nft', `case "$1" in list) exit 0 ;; delete) stage=delete ;; -f) stage=apply ;; *) exit 2 ;; esac
echo "$stage" >>"$EVENTS"
[ "$FAIL_STAGE" != "$stage" ]`);
    f.script('nft-hook', 'echo hook >>"$EVENTS"; [ "$FAIL_STAGE" != hook ]');
    f.script('fw4', 'echo unexpected-reload >>"$EVENTS"; exit 1');
    const result = f.run('firewall/fw4.sh', [], { EVENTS: events, FAIL_STAGE: fail });
    assert.equal(result.status, fail ? 1 : 0, result.stderr);
    const expected = ['delete', 'apply', 'hook'];
    assert.deepEqual(fs.readFileSync(events, 'utf8').trim().split('\n'), fail ? expected.slice(0, expected.indexOf(fail) + 1) : expected);
    if (!fail) {
        fs.unlinkSync(rules);
        fs.writeFileSync(events, '');
        assert.equal(f.run('firewall/fw4.sh', [], { EVENTS: events }).status, 0);
        assert.equal(fs.readFileSync(events, 'utf8'), 'delete\n');
    }
});

test('fw4 通过 sh -c source 加载时，日志保留 include 路径且不显示行号', t => {
    const f = fixture(t), entry = f.runtime + '/firewall/fw4.sh';
    f.patch('firewall/fw4.sh', '/etc/hijpass/fw4-rules.nft', f.directory + '/rules.nft');
    f.patch('firewall/fw4.sh', '/etc/hijpass/hook/nft-hook.sh', f.directory + '/nft-hook');
    fs.writeFileSync(f.directory + '/rules.nft', 'rules');
    f.script('nft', 'exit 0');
    f.script('nft-hook', 'exit 0');
    withConfig([{ '.type': 'hijpass', log_level: 'DEBUG' }], config => {
        const result = spawnSync('/usr/bin/busybox', ['ash', '-c', `. '${entry}'`], {
            encoding: 'utf8', env: { ...process.env, HIJPASS_TEST_CONFIG: config,
                PATH: `${f.directory}:${f.runtime}/testbin:${process.env.PATH}` },
        });
        assert.equal(result.status, 0, result.stderr);
    });
    const log = fs.readFileSync(f.directory + '/logs/hijpass.log', 'utf8');
    for (const message of ['Remove hijpass nft table', 'Apply hijpass nft rules', 'Run hijpass NFT Hook', 'Applied hijpass client nft rules']) {
        assert.ok(log.split('\n').some(line => line.includes(`${entry} `) && line.includes(message)), log);
    }
    assert.doesNotMatch(log, /\s(?:sh|ash):\d+|fw4\.sh:\d+|\[firewall\]/);
});

test('Chinadns 模板保留列表开关、默认 tag、上游和自定义域名的组合行为', t => {
    const f = fixture(t), configFile = path.join(f.directory, 'chinadns.conf');
    f.patch('service/dns.uc', '/etc/hijpass/chinadns-ng.conf', configFile);
    f.patch('service/dns.uc', '/tmp/hijpass/', f.directory + '/');
    f.patch('rules/rules.uc', '/tmp/hijpass/', f.directory + '/');
    const domain = path.join(f.directory, 'domains');
    fs.writeFileSync(domain, 'Example.ORG\nfull:example.net\ninvalid\n');
    for (const key of ['direct', 'proxy']) f.patch('ucode/hijpass/config/paths.uc', `/etc/hijpass/rules/domain-${key}.txt`, domain);
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules/chn-list.txt', '/rules/china');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules/gfw-list.txt', '/rules/proxy');
    const base = [{ '.type': 'hijpass', '.name': 'global', enabled: '1' },
        { '.type': 'dns', '.name': 'dns', dns_service: 'chinadns-ng', cdg_port: '53653',
            direct_dns: 'custom', direct_dns_custom: '223.5.5.5#53', proxy_dns: '1.1.1.1#53' }];
    for (const [china, proxy, tag] of [['0', '0', null], ['1', '0', 'gfw'], ['0', '1', 'chn'], ['1', '1', null]]) {
        const sections = [base[0], { ...base[1], use_chn: china, use_gfw: proxy }];
        withConfig(sections, config => {
            const prepared = f.run('service/prepare.sh', ['--configdir', config]);
            assert.equal(prepared.status, 0, prepared.stderr);
            assert.equal(JSON.parse(prepared.stdout).instances[0].name, 'chinadns-ng');
            const text = fs.readFileSync(configFile, 'utf8');
            assert.match(text, /^bind-port 53653$/m);
            assert.match(text, /^china-dns 223\.5\.5\.5#53$/m);
            assert.match(text, /^trust-dns 1\.1\.1\.1#53$/m);
            assert.equal(text.includes('chnlist-file /rules/china'), china === '1');
            assert.equal(text.includes('gfwlist-file /rules/proxy'), proxy === '1');
            assert.deepEqual(text.match(/^default-tag .*$/gm), tag ? ['default-tag ' + tag] : null);
            assert.match(text, /^group-upstream 223\.5\.5\.5#53$/m);
            assert.match(text, /^group-upstream 1\.1\.1\.1#53$/m);
            assert.match(text, /^verdict-cache 4096\n$/m);
            assert.equal(fs.readFileSync(path.join(f.directory, 'domain-direct.txt'), 'utf8'), 'example.org\nexample.net\n');
            assert.equal(fs.readFileSync(path.join(f.directory, 'domain-proxy.txt'), 'utf8'), 'example.org\nexample.net\n');
        });
    }
    withConfig([base[0], { ...base[1], direct_dns: 'dnsmasq' }], config => {
        fs.writeFileSync(path.join(config, 'dhcp'), "config dnsmasq\n option port '1053'\n");
        const prepared = f.run('service/prepare.sh', ['--configdir', config]);
        assert.equal(prepared.status, 0, prepared.stderr);
        assert.match(fs.readFileSync(configFile, 'utf8'), /^china-dns 127\.0\.0\.1#1053$/m);
    });
});

test('准备链式代理配置不修改生成对象，也不提前写入文件', t => {
    const f = fixture(t), fixtures = require('./testdata/compatibility.json');
    f.patch('service/prepare.uc', "import { resolve } from '../network/network.uc';",
        "function resolve(host) { return '192.0.2.10'; }");
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/client', f.directory);
    fs.writeFileSync(path.join(f.runtime, 'prepare-test.uc'), `import * as fs from 'fs';
import { generate } from 'hijpass.config.generate';
import { prepareConfigFiles } from './service/prepare.uc';
let sections = json(fs.stdin.read('all')), generated = generate(sections);
let before = sprintf('%J', generated);
let files = prepareConfigFiles(sections, generated);
assert(sprintf('%J', generated) == before, 'generated configuration was modified');
printf('%J\\n', { files, generated });
`);
    for (const core of ['sing-box', 'xray']) {
        const sections = structuredClone(fixtures.find(f => f.name === 'sing-box-chain').sections);
        for (const section of sections.slice(1)) section.core = core;
        sections[2].tls_server_name = 'tls.example.org';
        const result = spawnSync(interpreter, ['-S', '-L', path.join(f.runtime, 'ucode'), '--', path.join(f.runtime, 'prepare-test.uc')],
            { encoding: 'utf8', input: JSON.stringify(sections) });
        assert.equal(result.status, 0, result.stderr);
        const { files, generated } = JSON.parse(result.stdout);
        const file = files.find(file => file.path.endsWith('/downstream-downstream.json'));
        assert.equal(fs.existsSync(file.path), false);
        const original = generated.nodes.downstream.outbounds[0], resolved = JSON.parse(file.data).outbounds[0];
        if (core === 'sing-box') {
            assert.equal(original.server, sections[2].server);
            assert.equal(resolved.server, '192.0.2.10');
            assert.equal(resolved.tls.server_name, 'tls.example.org');
        } else {
            assert.equal(original.settings.address, sections[2].server);
            assert.equal(resolved.settings.address, '192.0.2.10');
            assert.equal(resolved.streamSettings.tlsSettings.serverName, 'tls.example.org');
        }
    }
});

test('服务端模板仅开放选中的端口，错误保留旧规则，没有允许端口时删除旧 include', t => {
    const f = fixture(t), table = path.join(f.directory, 'server rules.nft'), chain = path.join(f.directory, 'chain rules.nft');
    withConfig([], config => {
        const configFile = path.join(config, 'hijserver');
        const source = "config hijserver\n option enabled '1'\nconfig server_node 'a'\n option enabled '1'\n option name 'a'\n option type 'shadowsocks'\n option method 'aes-128-gcm'\n option password 'test'\n option allow_firewall '1'\n option listen_port '443'\n";
        fs.writeFileSync(configFile, source);
        for (const paths of [[], [table], [table, '']]) {
            const invalid = f.data('service/preparecli.uc', ['server', 'server-files', ...paths, '--configdir', config]);
            assert.equal(invalid.status, 1);
            assert.match(invalid.stderr, /requires table and chain paths/);
            assert.equal(fs.existsSync(table), false);
        }
        const result = f.data('service/preparecli.uc', ['server', 'server-files', table, chain, '--configdir', config]);
        assert.equal(result.status, 0, result.stderr);
        const original = fs.readFileSync(table, 'utf8');
        assert.equal(original, 'chain hijserver {\n    tcp dport { 443 } counter accept\n    udp dport { 443 } counter accept\n    return\n}\n');
        assert.equal(fs.readFileSync(chain, 'utf8'), 'jump hijserver comment "hijserver rule"\n');
        fs.writeFileSync(configFile, source.replace("'443'", "'0'"));
        assert.equal(f.data('service/preparecli.uc', ['server', 'server-files', table, chain, '--configdir', config]).status, 1);
        assert.equal(fs.readFileSync(table, 'utf8'), original);
        fs.writeFileSync(configFile, source.replace("allow_firewall '1'", "allow_firewall '0'"));
        assert.equal(f.data('service/preparecli.uc', ['server', 'server-files', table, chain, '--configdir', config]).status, 0);
        assert.equal(fs.existsSync(table), false);
        assert.equal(fs.existsSync(chain), false);
        fs.mkdirSync(table);
        const failedRemoval = f.data('service/preparecli.uc', ['server', 'server-files', table, chain, '--configdir', config]);
        assert.equal(failedRemoval.status, 1);
        assert.match(failedRemoval.stderr, /cannot remove/);
    });
});

for (const core of ['xray', 'sing-box']) {
    test(`${core} 安装校验摘要与版本，失败保留旧核心，成功后原子替换`, t => {
        const f = fixture(t), destination = path.join(f.directory, 'bin');
        fs.mkdirSync(destination);
        f.patch('core/release.uc', '/usr/bin/', destination + '/');
        f.patch('core/update.sh', '/usr/bin/$core', destination + '/$core');
        // uname 是外部命令，固定架构以覆盖资产选择，归档提取仍执行真实工具。
        f.script('uname', 'echo x86_64');
        const installed = path.join(destination, core);
        fs.writeFileSync(installed, 'old-core');
        const name = core === 'xray' ? 'Xray-linux-64.zip' : 'sing-box-1.2.3-linux-amd64-musl.tar.gz';
        const archive = path.join(f.directory, name), release = path.join(f.directory, 'release.json');
        f.script('curl', `case "$*" in
    *api.github.com*) [ "$TEST_CURL_FAIL" != metadata ] || exit 28; cat "$TEST_RELEASE" ;;
    *) [ "$TEST_CURL_FAIL" != download ] || exit 28; while [ "$1" != -o ]; do shift; done; cp "$TEST_ARCHIVE" "$2" ;;
esac`);
        function makeArchive(version) {
            const member = core === 'xray' ? 'xray' : 'sing-box-1.2.3-linux-amd64/sing-box';
            const binary = path.join(f.directory, member);
            fs.mkdirSync(path.dirname(binary), { recursive: true });
            fs.writeFileSync(binary, `#!/bin/sh\necho '${core === 'xray' ? 'Xray ' : 'sing-box version '}${version}'\n`, { mode: 0o755 });
            fs.rmSync(archive, { force: true });
            const packed = spawnSync(core === 'xray' ? '/usr/bin/zip' : '/bin/tar', core === 'xray' ? ['-q', archive, member] : ['-czf', archive, member], { cwd: f.directory, encoding: 'utf8' });
            assert.equal(packed.status, 0, packed.stderr);
            return createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
        }
        function update(digest, extra = {}) {
            const repo = core === 'xray' ? 'XTLS/Xray-core' : 'SagerNet/sing-box';
            fs.writeFileSync(release, JSON.stringify({ tag_name: 'v1.2.3', assets: [{ name, state: 'uploaded', digest: 'sha256:' + digest,
                browser_download_url: `https://github.com/${repo}/releases/download/v1.2.3/${name}` }] }));
            return f.run('core/update.sh', ['update', core], { TEST_RELEASE: release, TEST_ARCHIVE: archive, ...extra });
        }
        makeArchive('1.2.3');
        const checksumFailure = update('0'.repeat(64));
        assert.equal(checksumFailure.status, 1);
        assert.match(JSON.parse(checksumFailure.stdout).error, /checksum/);
        assert.equal(fs.readFileSync(installed, 'utf8'), 'old-core');
        const versionFailure = update(makeArchive('9.9.9'));
        assert.equal(versionFailure.status, 1);
        assert.match(JSON.parse(versionFailure.stdout).error, /binary verification/);
        assert.equal(fs.readFileSync(installed, 'utf8'), 'old-core');
        const validDigest = makeArchive('1.2.3');
        for (const failure of ['metadata', 'download']) {
            const failed = update(validDigest, { TEST_CURL_FAIL: failure });
            assert.equal(failed.status, 1, failed.stderr);
            assert.equal(JSON.parse(failed.stdout).success, false);
            assert.equal(fs.readFileSync(installed, 'utf8'), 'old-core');
        }
        for (const [command, body, message] of [
            ['cp "$binary" "$temp"', 'printf partial >"$2"; echo "copy failed" >&2; exit 1', /save staged/],
            ['chmod 755 "$temp"', 'echo "chmod failed" >&2; exit 1', /permissions/],
            ['mv -f "$temp" "$destination"', 'echo "rename failed" >&2; exit 1', /replace installed/],
        ]) {
            f.script('install-failure', body);
            const replacement = `'${f.directory}/install-failure' ` + command.slice(command.indexOf(' ') + 1);
            f.patch('core/update.sh', command, replacement);
            const failed = update(validDigest);
            assert.equal(failed.status, 1, failed.stderr);
            assert.match(JSON.parse(failed.stdout).error, message);
            assert.equal(fs.readFileSync(installed, 'utf8'), 'old-core');
            assert.deepEqual(fs.readdirSync(destination), [core]);
            f.patch('core/update.sh', replacement, command);
        }
        const success = update(validDigest);
        assert.equal(success.status, 0, success.stderr);
        assert.deepEqual(JSON.parse(success.stdout), { success: true, version: 'v1.2.3' });
        assert.equal(fs.statSync(installed).mode & 0o777, 0o755);
        assert.deepEqual(fs.readdirSync(destination), [core]);
        const version = f.run('core/update.sh', ['version', core]);
        assert.deepEqual(JSON.parse(version.stdout), { core, version: '1.2.3' });
    });
}

test('服务准备通过原生 UCI 读取并生成配置，禁用时不调用 Geo 工具', t => {
    const f = fixture(t), client = path.join(f.directory, 'client'), calls = path.join(f.directory, 'calls');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/client', client);
    f.script('sing-box', 'exit 0');
    f.script('geoview', 'echo unexpected >>"$TEST_CALLS"; exit 1');
    const sections = [{ '.type': 'hijpass', '.name': 'global', enabled: '1' },
        { '.type': 'proxy_node', '.name': 'ss', enabled: '1', name: 'test', type: 'shadowsocks', core: 'sing-box',
            server: '192.0.2.10', server_port: '443', listen_port: '10001', socks_port: '10002', method: 'aes-128-gcm', password: 'test' }];
    withConfig(sections, config => {
        const prepared = f.run('service/prepare.sh', ['--configdir', config], { TEST_CALLS: calls });
        assert.equal(prepared.status, 0, prepared.stderr);
        assert.deepEqual(JSON.parse(prepared.stdout).instances[0].command, ['sing-box', '-c', client + '/test-ss.json', 'run']);
        assert.equal(JSON.parse(fs.readFileSync(client + '/test-ss.json', 'utf8')).outbounds[0].type, 'shadowsocks');
    });
    const original = fs.readFileSync(client + '/test-ss.json', 'utf8');
    sections[1].password = 'changed';
    sections.push({ '.type': 'proxy_node', '.name': 'custom', enabled: '1', name: 'custom', config_type: 'custom', type: 'custom' });
    withConfig(sections, config => {
        const failed = f.run('service/prepare.sh', ['--configdir', config], { TEST_CALLS: calls });
        assert.equal(failed.status, 1);
        assert.match(failed.stderr, /has no command/);
        assert.equal(fs.readFileSync(client + '/test-ss.json', 'utf8'), original);
    });
    sections[0].enabled = '0';
    withConfig(sections, config => {
        const disabled = f.run('service/prepare.sh', ['--configdir', config], { TEST_CALLS: calls });
        assert.equal(disabled.status, 0, disabled.stderr);
        assert.deepEqual(JSON.parse(disabled.stdout), { instances: [] });
        assert.equal(fs.existsSync(calls), false);
    });
});

test('原生 UCI 中缺省核心的 VLESS 生成并启动 sing-box，自定义命令不生成或覆盖配置', t => {
    const f = fixture(t), client = path.join(f.directory, 'client');
    f.script('sing-box', 'exit 0');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/client', client);
    fs.mkdirSync(client);
    const customFile = path.join(client, 'manual-custom.json');
    fs.writeFileSync(customFile, 'user maintained content');
    const command = 'printf "%s\\n" "custom command"';
    const sections = [{ '.type': 'hijpass', '.name': 'global', enabled: '1' },
        { '.type': 'proxy_node', '.name': 'vless', enabled: '1', name: 'vless', type: 'vless',
            server: '192.0.2.10', server_port: '443', listen_port: '10001', socks_port: '10002',
            uuid: '11111111-1111-4111-8111-111111111111' },
        { '.type': 'proxy_node', '.name': 'custom', enabled: '1', name: 'manual', config_type: 'custom',
            command, listen_port: '10003', socks_port: '10004' }];
    withConfig(sections, directory => {
        const result = f.run('service/prepare.sh', ['--configdir', directory]);
        assert.equal(result.status, 0, result.stderr);
        const plan = JSON.parse(result.stdout);
        assert.deepEqual(plan.instances[0].command, ['sing-box', '-c', client + '/vless-vless.json', 'run']);
        assert.equal(JSON.parse(fs.readFileSync(client + '/vless-vless.json', 'utf8')).outbounds[0].type, 'vless');
        assert.deepEqual(plan.instances[1].command, ['/bin/sh', '-c', command]);
        assert.equal(fs.readFileSync(customFile, 'utf8'), 'user maintained content');
    });
});

test('uci-defaults 首次安装自动迁移并注册防火墙，重复安装不重新转换配置', t => {
    const f = fixture(t), directory = path.join(f.directory, 'config'), accounts = path.join(f.directory, 'accounts');
    fs.mkdirSync(directory); fs.mkdirSync(accounts);
    for (const file of ['group', 'passwd', 'shadow']) fs.writeFileSync(path.join(accounts, file), 'existing:x:1:');
    fs.writeFileSync(path.join(directory, 'hijpass'), "config hijpass 'global'\nconfig proxy_node 'manual'\n option core 'custom'\n option type 'custom'\n option command 'program'\n");
    fs.writeFileSync(path.join(directory, 'firewall'), '');
    f.patch('install/setup.sh', '/etc/$file', accounts + '/$file');
    f.patch('install/setup.sh', '/etc/hijpass', f.directory + '/data');
    f.patch('install/setup.sh', '/tmp/hijpass/log', f.directory + '/logs');
    f.patch('install/setup.sh', '/tmp/hijserver/log', f.directory + '/server-logs');
    f.patch('install/setup.sh', '/tmp/luci-*cache', f.directory + '/cache');
    f.script('cron-restart', 'printf "%s\\n" "$1" >>"$CRON_TEST_CALLS"');
    f.patch('install/setup.sh', '/etc/init.d/cron', path.join(f.directory, 'cron-restart'));
    f.patch('install/setup.sh', '"$HIJPASS_LIB/install/migrate.uc"', '"$HIJPASS_LIB/install/migrate.uc" --configdir "$TEST_CONFIG_DIRECTORY"');
    const uci = spawnSync('/bin/sh', ['-c', 'command -v uci'], { encoding: 'utf8' }).stdout.trim();
    assert.ok(uci, 'native UCI CLI is required for the installation test');
    f.script('uci', "exec '" + uci.replaceAll("'", "'\\''") + "' -c \"$TEST_CONFIG_DIRECTORY\" \"$@\"");
    fs.writeFileSync(path.join(f.runtime, 'install/firstboot.sh'),
        fs.readFileSync(path.join(root, 'root/etc/uci-defaults/luci-app-hijpass'), 'utf8').replaceAll('/usr/lib/hijpass', f.runtime));
    const env = { TEST_CONFIG_DIRECTORY: directory, CRON_TEST_CALLS: path.join(f.directory, 'cron-calls') };
    const first = f.run('install/firstboot.sh', [], env);
    assert.equal(first.status, 0, first.stderr);
    const migrated = fs.readFileSync(path.join(directory, 'hijpass'), 'utf8');
    assert.match(migrated, /schema_version '5'/);
    assert.match(migrated, /config_type 'custom'/);
    assert.doesNotMatch(migrated, /option (core|type) /);
    assert.match(fs.readFileSync(path.join(directory, 'firewall'), 'utf8'), /option type 'script'/);
    const modified = migrated + "\nconfig proxy_node 'later'\n option core 'singbox'\n";
    fs.writeFileSync(path.join(directory, 'hijpass'), modified);
    const again = f.run('install/firstboot.sh', [], env);
    assert.equal(again.status, 0, again.stderr);
    assert.equal(fs.readFileSync(path.join(directory, 'hijpass'), 'utf8'), modified);
    assert.equal(fs.readFileSync(env.CRON_TEST_CALLS, 'utf8'), 'restart\nrestart\n');
    for (const file of ['group', 'passwd', 'shadow'])
        assert.equal(fs.readFileSync(path.join(accounts, file), 'utf8').split('\n').filter(line => line.startsWith('hijpass:')).length, 1);
});

test('服务 cron 只管理当前脚本，客户端与服务端互不删除，不在启动时清理旧任务', t => {
    const f = fixture(t), cron = path.join(f.directory, 'crontab');
    f.script('cron-init', 'exit 0');
    for (const service of ['hijpass', 'hijserver']) f.patch('init-' + service + '.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.patch('service/cron.sh', '/etc/crontabs/root', cron);
    const legacy = `0 * * * * ${f.runtime}/rules.sh update\n`;
    const mentioned = `0 * * * * echo ${f.runtime}/rules/update.sh\n`;
    fs.writeFileSync(cron, legacy + mentioned + `0 * * * * ${f.runtime}/rules/update.sh update\n*/10 * * * * ${f.runtime}/maintenance/logs.sh hijpass\n`);
    withConfig([{ '.type': 'hijpass', '.name': 'global', enabled: '1' },
        { '.type': 'rule', '.name': 'rules', update_schedule: '0 5 * * 1' }], directory => {
        fs.writeFileSync(path.join(directory, 'hijserver'), `config hijserver 'global'\n option enabled '1'\nconfig server_node 'a'\n option enabled '1'\n option command 'program'\n option log_enabled '1'\n`);
        for (const service of ['hijpass', 'hijpass', 'hijserver', 'hijserver']) {
            const result = f.init(service, 'update_cron', directory, { CRON_ACTION: 'enable', CRON_LOG: '1' });
            assert.equal(result.status, 0, result.stderr);
        }
        let contents = fs.readFileSync(cron, 'utf8');
        assert.ok(contents.includes(legacy));
        assert.ok(contents.includes(mentioned));
        assert.equal(contents.split('\n').filter(line => line.includes(`0 5 * * 1 ${f.runtime}/rules/update.sh`)).length, 1);
        for (const kind of ['hijpass', 'hijserver'])
            assert.equal(contents.split('\n').filter(line => line.endsWith('/maintenance/logs.sh ' + kind)).length, 1);
        const stopped = f.init('hijpass', 'update_cron', directory, { CRON_ACTION: 'disable' });
        assert.equal(stopped.status, 0, stopped.stderr);
        contents = fs.readFileSync(cron, 'utf8');
        assert.ok(contents.includes(legacy));
        assert.ok(contents.includes(mentioned));
        assert.ok(contents.includes('/maintenance/logs.sh hijserver'));
        assert.equal(contents.includes('/maintenance/logs.sh hijpass'), false);
        assert.equal(contents.includes(`0 5 * * 1 ${f.runtime}/rules/update.sh`), true);
        // 手动停止不改变配置；只有配置禁用时才移除规则更新任务。
        const configFile = path.join(directory, 'hijpass');
        fs.writeFileSync(configFile, fs.readFileSync(configFile, 'utf8').replace("'1'", "'0'"));
        assert.equal(f.init('hijpass', 'update_cron', directory, { CRON_ACTION: 'disable' }).status, 0);
        assert.equal(fs.readFileSync(cron, 'utf8').includes(`0 5 * * 1 ${f.runtime}/rules/update.sh`), false);
    });
});

test('服务端 cron 复用日志标记，停用时不依赖配置文件是否有效', t => {
    const f = fixture(t), cron = f.directory + '/crontab';
    f.patch('init-hijserver.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.script('cron-init', 'exit 0');
    withConfig([], config => {
        fs.writeFileSync(config + '/hijserver', 'invalid configuration');
        for (const [action, logs] of [['enable', '1'], ['enable', '0'], ['disable', '1']]) {
            assert.equal(f.init('hijserver', 'update_cron', config, { CRON_ACTION: action, CRON_LOG: logs }).status, 0);
            assert.equal(fs.readFileSync(cron, 'utf8').includes('/maintenance/logs.sh hijserver'), action === 'enable' && logs === '1');
        }
    });
});


test('页面、定时和命令行更新共用任务状态与执行锁，完成结果可供多个观察者读取', async t => {
    const f = fixture(t), started = path.join(f.directory, 'started'), release = path.join(f.directory, 'release');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', f.directory + '/rules');
    f.script('curl', `printf 'download\\n' >>'${started}'
i=0; while [ ! -f '${release}' ] && [ "$i" -lt 300 ]; do sleep 0.01; i=$((i+1)); done
while [ "$1" != -o ]; do shift; done
output=$2
i=0; while [ "$i" -lt 10 ]; do echo server=/example.org/1.1.1.1; i=$((i+1)); done >"$output"`);
    await withConfig([{ '.type': 'hijpass', enabled: '0' }, { '.type': 'rule', retry_count: '1',
        chn_domain_list: ['https://example.org/domains'] }], async config => {
        const original = f.launch('rules/update.sh', ['chnlist', '--configdir', config]);
        await until(() => fs.existsSync(started));
        const active = JSON.parse(f.run('rpc/jobs.sh', ['current', 'rules']).stdout);
        assert.match(active.id, /^[A-Za-z0-9]{8}$/);
        const progress = JSON.parse(f.run('rpc/jobs.sh', ['status', active.id]).stdout);
        assert.equal(progress.running, true);
        assert.equal(progress.progress.phase, 'download');
        assert.equal(progress.progress.resource, 'chn_domain_list');
        assert.equal(progress.progress.attempt, 1);
        assert.equal('file' in progress.progress, false);

        for (const args of [['chnlist', '--configdir', config], ['update', '--scheduled', '--configdir', config]]) {
            const duplicate = f.run('rules/update.sh', args);
            assert.equal(duplicate.status, 75, duplicate.stderr);
            assert.equal(JSON.parse(duplicate.stdout).code, 'UPDATE_BUSY');
        }
        const starts = Array.from({ length: 6 }, () => f.launch('rpc/jobs.sh', ['start', 'rules']));
        const replies = await Promise.all(starts.map(task => task.result));
        for (const reply of replies) {
            assert.equal(reply.status, 0, reply.stderr);
            assert.equal(JSON.parse(reply.stdout).id, active.id);
            assert.equal(JSON.parse(reply.stdout).code, 'UPDATE_BUSY');
            assert.equal(JSON.parse(reply.stdout).success, false);
        }
        assert.equal(fs.readFileSync(started, 'utf8'), 'download\n');
        fs.writeFileSync(release, '');
        const completed = await original.result;
        assert.equal(completed.status, 0, completed.stderr);
        assert.equal(JSON.parse(completed.stdout).success, true);
        assert.equal(JSON.parse(f.run('rpc/jobs.sh', ['current', 'rules']).stdout).id, null);
        for (let i = 0; i < 2; i++) {
            assert.equal(JSON.parse(f.run('rpc/jobs.sh', ['status', active.id]).stdout).code, 0);
        }
        assert.equal(f.run('rules/update.sh', ['chnlist', '--configdir', config]).status, 0);
        assert.equal(fs.readFileSync(started, 'utf8'), 'download\ndownload\n');
    });
});

test('协调进程意外退出时，仍运行的下载进程继续持锁，不能重复下载', async t => {
    const f = fixture(t), started = path.join(f.directory, 'started'), release = path.join(f.directory, 'release');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', f.directory + '/rules');
    f.script('curl', `echo download >>'${started}'
i=0; while [ ! -f '${release}' ] && [ "$i" -lt 300 ]; do sleep 0.01; i=$((i+1)); done
while [ "$1" != -o ]; do shift; done
output=$2
i=0; while [ "$i" -lt 10 ]; do echo server=/example.org/1.1.1.1; i=$((i+1)); done >"$output"`);
    await withConfig([{ '.type': 'hijpass', enabled: '0' }, { '.type': 'rule', retry_count: '1',
        chn_domain_list: ['https://example.org/domains'] }], async config => {
        const original = f.launch('rules/update.sh', ['chnlist', '--configdir', config]);
        await until(() => fs.existsSync(started));
        original.child.kill('SIGKILL');
        await original.result;
        const blocked = f.run('rules/update.sh', ['chnlist', '--configdir', config]);
        assert.equal(blocked.status, 75, blocked.stderr);
        assert.equal(JSON.parse(blocked.stdout).code, 'UPDATE_BUSY');
        assert.equal(fs.readFileSync(started, 'utf8'), 'download\n');
        fs.writeFileSync(release, '');
        await until(() => spawnSync('flock', ['-n', path.join(f.runtime, 'jobs/updates.lock'), 'true']).status === 0);
        const retry = f.run('rules/update.sh', ['chnlist', '--configdir', config]);
        assert.equal(retry.status, 0, retry.stderr);
        assert.equal(fs.readFileSync(started, 'utf8'), 'download\ndownload\n');
    });
});

test('部分资源更新后遇到失败立即停止后续下载且不重启，失败文件仍保留旧版', t => {
    const f = fixture(t), calls = path.join(f.directory, 'calls'), rules = path.join(f.directory, 'rules');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', rules);
    f.patch('rules/update-files.sh', '/etc/init.d/hijpass', path.join(f.directory, 'hijpass-init'));
    fs.mkdirSync(rules);
    fs.writeFileSync(path.join(rules, 'gfw-list.txt'), 'old gfw');
    fs.writeFileSync(path.join(rules, 'chn-list.txt'), 'old china');
    f.script('hijpass-init', `echo restart >>'${calls}'`);
    f.script('curl', `echo download >>'${calls}'
case "$*" in *unavailable*) echo 'curl: (28) timed out' >&2; exit 28 ;; esac
while [ "$1" != -o ]; do shift; done
output=$2
i=0; while [ "$i" -lt 10 ]; do echo server=/example.org/1.1.1.1; i=$((i+1)); done >"$output"`);
    withConfig([{ '.type': 'hijpass', enabled: '1' }, { '.type': 'rule', retry_count: '1',
        gfw_list: ['https://example.org/valid'], chn_domain_list: ['https://example.org/unavailable'],
        chn_v4_route: ['https://example.org/should-not-run'] }], config => {
        const result = f.run('rules/update.sh', ['update', '--configdir', config]);
        assert.equal(result.status, 1, result.stderr);
        assert.deepEqual(JSON.parse(result.stdout), { success: false, failed: ['chn_domain_list'] });
        assert.equal(result.stderr, '');
    });
    assert.equal(fs.readFileSync(calls, 'utf8'), 'download\ndownload\n');
    assert.equal(fs.readFileSync(path.join(rules, 'gfw-list.txt'), 'utf8'), 'example.org\n');
    assert.equal(fs.readFileSync(path.join(rules, 'chn-list.txt'), 'utf8'), 'old china');
    assert.equal(fs.existsSync(path.join(rules, 'chn-route.txt')), false);
});

test('同时首次发起多个后台更新请求只创建一个任务和一个执行进程', async t => {
    const f = fixture(t), started = path.join(f.directory, 'started'), release = path.join(f.directory, 'release');
    fs.writeFileSync(path.join(f.runtime, 'rules/update-files.sh'), `#!/bin/sh
echo worker >>'${started}'
i=0; while [ ! -f '${release}' ] && [ "$i" -lt 300 ]; do sleep 0.01; i=$((i+1)); done
printf '{"success":true}\\n'
`, { mode: 0o755 });
    const requests = Array.from({ length: 8 }, () => f.launch('rpc/jobs.sh', ['start', 'rules']));
    const replies = await Promise.all(requests.map(task => task.result));
    const ids = replies.map(reply => {
        assert.equal(reply.status, 0, reply.stderr);
        return JSON.parse(reply.stdout).id;
    });
    assert.equal(new Set(ids).size, 1);
    await until(() => fs.existsSync(started));
    assert.equal(fs.readFileSync(started, 'utf8'), 'worker\n');
    fs.writeFileSync(release, '');
    await until(() => !JSON.parse(f.run('rpc/jobs.sh', ['status', ids[0]]).stdout).running);
    const completed = JSON.parse(f.run('rpc/jobs.sh', ['status', ids[0]]).stdout);
    assert.equal(completed.code, 0, completed.stderr);
    assert.equal(JSON.parse(completed.stdout).success, true);
});

test('下载全部成功但应用失败时，仅返回重启阶段失败，底层原文只记录在主日志', t => {
    const f = fixture(t), calls = path.join(f.directory, 'restart-calls');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', f.directory + '/rules');
    f.patch('rules/rules.uc', '/usr/share/v2ray', f.directory + '/v2ray');
    f.patch('rules/update-files.sh', '/etc/init.d/hijpass', f.directory + '/hijpass-init');
    f.script('geoview', 'exit 0');
    f.script('hijpass-init', `echo restart >>'${calls}'\necho '[E] underlying service failure' >&2\nexit 7`);
    f.script('curl', `case "$*" in
*ip4*) line='192.0.2.0/24' ;;
*ip6*) line='2001:db8::/32' ;;
*) line='server=/example.org/1.1.1.1' ;;
esac
while [ "$1" != -o ]; do shift; done
output=$2
i=0; while [ "$i" -lt 12 ]; do echo "$line"; i=$((i+1)); done >"$output"`);
    withConfig([{ '.type': 'hijpass', enabled: '1' }, { '.type': 'rule', retry_count: '1',
        gfw_list: ['https://example.org/gfw'], chn_domain_list: ['https://example.org/china'],
        chn_v4_route: ['https://example.org/ip4'], chn_v6_route: ['https://example.org/ip6'],
        geoip: ['https://example.org/geoip'], geosite: ['https://example.org/geosite'] }], config => {
        const result = f.run('rules/update.sh', ['update', '--configdir', config]);
        assert.equal(result.status, 1, result.stderr);
        assert.deepEqual(JSON.parse(result.stdout), { success: false, failed: ['restart'] });
        assert.equal(result.stderr, 'Restart hijpass after rule update failed; see main log\n');
    });
    assert.equal(fs.readFileSync(calls, 'utf8'), 'restart\n');
    const log = fs.readFileSync(path.join(f.directory, 'logs/hijpass.log'), 'utf8');
    assert.equal((log.match(/installed, sources=/g) || []).length, 6);
    assert.equal((log.match(/underlying service failure/g) || []).length, 1);
    assert.doesNotMatch(log, /diagnostic output|\[job\]/);
});

test('Geo 查询使用 Shell 转小写，保留换行和命令失败状态', t => {
    const f = fixture(t);
    f.script('geoview', `printf 'EXAMPLE.COM\\nCN\\n'; exit "\${GEO_EXIT:-0}"`);
    for (const action of ['-l', '-e']) {
        const result = f.run('rules/geoview.sh', [action, 'geosite', 'CN']);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout, 'example.com\ncn\n');
        const failed = f.run('rules/geoview.sh', [action, 'geosite', 'CN'], { GEO_EXIT: '7' });
        assert.notEqual(failed.status, 0);
        assert.equal(failed.stdout, '');
    }
});

test('来源使用固定列宽，正文和续行对齐，不再单独解析模块标签', t => {
    const f = fixture(t), log = path.join(f.directory, 'logs/hijpass.log');
    for (const level of ['DEBUG', 'INFO']) {
        withConfig([{ '.type': 'hijpass', log_level: level }], config => {
            for (const [source, message] of [['/usr/lib/hijpass/a.sh', 'First operation\ncontinuation'],
                ['/usr/lib/hijpass/maintenance/cleanup.sh', 'Second operation'],
                ['/usr/lib/hijpass/install/migrate.uc:123', '[literal] ordinary message']]) {
                const result = f.run('maintenance/logs.sh', ['source', 'INFO', source, message, '--configdir', config]);
                assert.equal(result.status, 0, result.stderr);
            }
        });
        const lines = fs.readFileSync(log, 'utf8').trimEnd().split('\n');
        const messageColumn = level === 'DEBUG' ? 98 : 32;
        for (const [index, body] of [[0, 'First operation'], [1, 'continuation'], [2, 'Second operation'], [3, '[literal] ordinary message']])
            assert.equal(lines[index].indexOf(body), messageColumn);
        if (level === 'DEBUG') {
            assert.ok(lines[0].includes('/usr/lib/hijpass/a.sh'));
            assert.ok(lines[2].includes('/usr/lib/hijpass/maintenance/cleanup.sh'));
        } else assert.doesNotMatch(lines.join('\n'), /\/usr\/lib\/hijpass/);
        fs.unlinkSync(log);
    }
});

test('CLI 字符串和 JSON 输出写入满盘均以非零退出，Shell 可据此停止后续步骤', t => {
    const f = fixture(t), file = path.join(f.runtime, 'output-test.uc');
    fs.writeFileSync(file, `import { run } from 'hijpass.command.runtime';
run(ARGV, args => args[0] == 'string' ? 'example.org\\n' : { success: true }, ARGV[1] == 'json-errors');`);
    for (const args of [['string'], ['object'], ['object', 'json-errors']]) {
        const full = fs.openSync('/dev/full', 'w');
        try {
            const result = spawnSync(interpreter, ['-S', '-L', path.join(f.runtime, 'ucode'), '--', file, ...args], {
                encoding: 'utf8', env: process.env, stdio: ['ignore', full, 'pipe'],
            });
            assert.equal(result.status, 1, result.stderr);
            if (!args.includes('json-errors')) assert.match(result.stderr, /cannot write command output/);
        } finally { fs.closeSync(full); }
    }
});

function downloadFixture(t) {
    const f = fixture(t), rules = path.join(f.directory, 'rules'), calls = path.join(f.directory, 'calls');
    fs.mkdirSync(rules);
    fs.writeFileSync(path.join(rules, 'gfw-list.txt'), 'old rules');
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', rules);
    f.patch('rules/rules.uc', '/usr/share/v2ray', f.directory + '/v2ray');
    f.patch('rules/update-files.sh', '/etc/init.d/hijpass', f.directory + '/hijpass-init');
    f.script('hijpass-init', `echo restart >>'${calls}'`);
    f.script('geoview', 'exit 0');
    f.script('curl', `echo download >>'${calls}'
case "$*" in *ip4*) line='192.0.2.0/24' ;; *ip6*) line='2001:db8::/32' ;; *) line='server=/example.org/1.1.1.1' ;; esac
while [ "$1" != -o ]; do shift; done
output=$2
if [ "$TEST_WRITE_ERROR" = 1 ]; then echo partial >"$output"; echo 'curl: (23) write failed' >&2; exit 23; fi
i=0; while [ "$i" -lt 12 ]; do echo "$line"; i=$((i+1)); done >"$output"`);
    const sections = [{ '.type': 'hijpass', enabled: '1' }, { '.type': 'rule', retry_count: '3',
        gfw_list: ['https://example.org/source1', 'https://example.org/source2', 'https://example.org/source3'],
        chn_domain_list: ['https://example.org/china'], chn_v4_route: ['https://example.org/ip4'],
        chn_v6_route: ['https://example.org/ip6'], geoip: ['https://example.org/geoip'], geosite: ['https://example.org/geosite'] }];
    return { ...f, rules, calls, sections };
}

for (const fault of ['download-write', 'normalize', 'save', 'permissions', 'replace']) {
    test(`规则 ${fault} 失败直接退出，不尝试后续来源或资源，不触发重启`, t => {
        const f = downloadFixture(t);
        if (fault === 'normalize') {
            f.script('normalize-failure', `count=$(cat '${f.directory}/normalize-count' 2>/dev/null || echo 0)
count=$((count+1)); echo "$count" >'${f.directory}/normalize-count'
if [ "$count" -eq 2 ]; then echo partial; echo 'local processing failed' >&2; exit 1; fi
exec '${interpreter}' -S -L '${f.runtime}/ucode' -- '${f.runtime}/rules/rulescli.uc' normalize "$@"`);
            f.patch('rules/update-files.sh', 'hijpass_run_ucode "$data" normalize', `'${f.directory}/normalize-failure'`);
        }
        const command = { save: 'hijpass_run_ucode "$data" merge', permissions: 'chmod 644 "$staged"', replace: 'mv -f "$staged" "$path"' }[fault];
        if (command) {
            f.script('save-failure', (fault === 'save' ? 'echo partial; ' : '') + 'echo "local file update failed" >&2; exit 1');
            f.patch('rules/update-files.sh', command, `'${f.directory}/save-failure'`);
        }
        withConfig(f.sections, config => {
            const result = f.run('rules/update.sh', ['update', '--configdir', config], { TEST_WRITE_ERROR: fault === 'download-write' ? '1' : '0' });
            assert.equal(result.status, 1, result.stderr);
            assert.deepEqual(JSON.parse(result.stdout), { success: false, failed: ['gfw_list'] });
        });
        assert.equal(fs.readFileSync(path.join(f.rules, 'gfw-list.txt'), 'utf8'), 'old rules');
        const calls = fs.readFileSync(f.calls, 'utf8').trim().split('\n');
        assert.ok(!calls.includes('restart'));
        assert.equal(calls.length, fault === 'download-write' ? 1 : fault === 'normalize' ? 2 : 3);
        assert.deepEqual(fs.readdirSync(f.rules), ['gfw-list.txt']);
    });
}

for (const mode of ['convert', 'dns']) for (const fault of ['tool', 'replace']) {
    test(`Geo ${mode} 的 ${fault} 失败保留旧文件并返回非零，不继续下一项`, t => {
        const f = fixture(t), calls = path.join(f.directory, 'calls');
        const target = mode === 'convert' ? path.join(f.directory, 'ruleset/geoip-cn.srs') : path.join(f.directory, 'domain-proxy-geo.txt');
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, 'old geo data');
        f.patch('rules/rules.uc', '/etc/hijpass/ruleset', f.directory + '/ruleset');
        f.patch('rules/rules.uc', '/tmp/hijpass/', f.directory + '/');
        const input = path.join(f.directory, 'domains');
        fs.writeFileSync(input, 'geosite:cn\n');
        for (const kind of ['direct', 'proxy']) f.patch('ucode/hijpass/config/paths.uc', `/etc/hijpass/rules/domain-${kind}.txt`, input);
        f.script('geoview', `echo convert >>'${calls}'
case "$*" in *-output*) while [ "$1" != -output ]; do shift; done; printf partial >"$2" ;; *) echo partial.example.org ;; esac
if [ "$GEO_TOOL_FAIL" = 1 ]; then echo 'cannot write Geo output' >&2; exit 1; fi`);
        if (fault === 'replace') {
            f.script('geo-replace-failure', 'echo "cannot replace Geo output" >&2; exit 1');
            f.patch('rules/geoview.sh', 'mv -f "$staged" "$output"', `'${f.directory}/geo-replace-failure'`);
        }
        withConfig([{ '.type': 'hijpass', enabled: '1' }, { '.type': 'dns', dns_service: 'chinadns-ng' },
            { '.type': 'shunt_route_rule', enabled: '1', ip_list: 'geoip:cn', domain_list: 'geosite:cn' }], config => {
            const result = f.run('rules/geoview.sh', [mode === 'convert' ? '--convert' : 'dns', '--configdir', config], {
                GEO_TOOL_FAIL: fault === 'tool' ? '1' : '0',
            });
            assert.equal(result.status, 1, result.stderr);
        });
        assert.equal(fs.readFileSync(target, 'utf8'), 'old geo data');
        assert.equal(fs.readFileSync(calls, 'utf8'), 'convert\n');
        assert.ok(!fs.readdirSync(path.dirname(target)).some(name => name.startsWith(path.basename(target) + '.new.')));
    });
}

test('配置 CLI 的 JSON 列表和渲染结果重定向保存失败也返回非零', t => {
    const f = fixture(t), file = path.join(f.runtime, 'config-output-test.uc');
    fs.writeFileSync(file, `import { main } from 'hijpass.command.config'; main(ARGV);`);
    for (const args of [['list'], ['render', '--stdin']]) {
        const full = fs.openSync('/dev/full', 'w');
        try {
            const result = spawnSync(interpreter, ['-S', '-L', path.join(f.runtime, 'ucode'), '--', file, ...args], {
                encoding: 'utf8', env: process.env, stdio: ['pipe', full, 'pipe'], input: JSON.stringify([{ '.name': 'global', '.type': 'hijpass' }]),
            });
            assert.notEqual(result.status, 0, result.stderr);
            assert.match(result.stderr, /cannot write command output/);
        } finally { fs.closeSync(full); }
    }
});

test('任务在查询存活状态期间完成时，保留已发布的真实结果', t => {
    const f = fixture(t), id = 'Test1234', job = path.join(f.runtime, 'jobs', id);
    fs.mkdirSync(job, { recursive: true });
    fs.writeFileSync(path.join(job, 'pid'), '2147483647\n');
    fs.writeFileSync(path.join(job, 'stdout'), '{"success":true}\n');
    fs.writeFileSync(path.join(job, 'stderr'), '');
    // 仅在安装副本模拟 worker 恰好于存活检查期间发布结果并退出。
    f.patch('rpc/jobs.sh', 'recover_job() {', `kill() {
    printf '0\\n' >'${job}/exit'
    return 1
}
recover_job() {`);
    const result = f.run('rpc/jobs.sh', ['status', id]);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), { running: false, code: 0, stdout: '{"success":true}', stderr: '' });
    assert.equal(fs.readFileSync(path.join(job, 'exit'), 'utf8'), '0\n');
});

for (const fail of ['', 'route', 'generate', 'firewall', 'hook']) test(`客户端按路由、防火墙、DNS 顺序激活，${fail || '正常'}分支继续后续独立阶段`, t => {
    const f = fixture(t), events = f.directory + '/events';
    for (const [file, stage] of [['route.sh', 'route']])
        fs.writeFileSync(f.runtime + '/firewall/' + file,
            `#!/bin/sh\necho '${stage}' >>"$EVENTS"\n[ "$FAIL_STAGE" != '${stage}' ] || { echo '${stage} detail' >&2; exit 1; }\n`, { mode: 0o755 });
    fs.writeFileSync(f.runtime + '/firewall/generatecli.uc', `import * as fs from 'fs';
let file = fs.open(getenv('EVENTS'), 'a'); file.write('generate\\n'); file.close();
if (getenv('FAIL_STAGE') == 'generate') { warn('generate detail'); exit(1); }`);
    f.script('fw4', 'echo firewall >>"$EVENTS"\n[ "$FAIL_STAGE" != firewall ] || { echo "firewall detail" >&2; exit 1; }');
    f.script('dns-hook', 'echo hook >>"$EVENTS"\n[ "$FAIL_STAGE" != hook ] || { echo "hook detail" >&2; exit 1; }');
    f.script('cron-init', 'echo cron >>"$EVENTS"');
    f.patch('init-hijpass.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.patch('service/cron.sh', '/etc/crontabs/root', f.directory + '/crontab');
    f.patch('init-hijpass.sh', '/etc/hijpass/hook/dns-hook.sh', f.directory + '/dns-hook');
    withConfig([{ '.type': 'hijpass', enabled: '1' }], config => {
        const result = f.init('hijpass', 'service_started', config, { EVENTS: events, FAIL_STAGE: fail });
        assert.equal(result.status, 0, result.stderr);
    });
    if (fail) {
        const phase = { route: 'Reset policy routes', generate: 'Generate hijpass firewall rules', firewall: 'Reload firewall for hijpass', hook: 'DNS Hook start' }[fail];
        const log = fs.readFileSync(f.directory + '/logs/hijpass.log', 'utf8');
        assert.match(log, new RegExp(`${phase}: ${fail} detail`));
        assert.match(log, new RegExp(`ERROR.*${phase} failed: exit=1`));
    }
    const expected = ['route', 'generate', 'firewall', 'hook', 'cron'];
    assert.deepEqual(fs.readFileSync(events, 'utf8').trim().split('\n'), fail === 'generate' ? expected.filter(stage => stage !== 'firewall') : expected);
});

test('客户端防火墙撤流失败仍继续清理路由和 cron', t => {
    const f = fixture(t), events = f.directory + '/events';
    f.script('fw4', 'echo firewall >>"$EVENTS"\nexit 1');
    fs.writeFileSync(f.runtime + '/firewall/route.sh', '#!/bin/sh\necho route >>"$EVENTS"\n', { mode: 0o755 });
    f.patch('init-hijpass.sh', '/etc/hijpass/hook/dns-hook.sh', f.directory + '/dns-hook');
    f.script('dns-hook', 'echo hook >>"$EVENTS"');
    f.script('cron-init', 'echo cron >>"$EVENTS"');
    f.patch('init-hijpass.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.patch('service/cron.sh', '/etc/crontabs/root', f.directory + '/crontab');
    withConfig([{ '.type': 'hijpass', enabled: '1' }], config => {
        const result = f.init('hijpass', 'stop_service', config, { EVENTS: events });
        assert.equal(result.status, 0);
    });
    assert.deepEqual(fs.readFileSync(events, 'utf8').trim().split('\n'), ['hook', 'firewall', 'route', 'cron']);
});

test('服务端生成标准配置后，激活只写端口规则和日志任务，不生成客户端数据', t => {
    const f = fixture(t), events = f.directory + '/events', table = f.directory + '/server rules.nft', chain = f.directory + '/chain rules.nft';
    f.patch('init-hijserver.sh', '/usr/share/nftables.d/table-post/hijserver.nft', table);
    f.patch('init-hijserver.sh', '/usr/share/nftables.d/chain-pre/input_wan/hijserver.nft', chain);
    f.patch('service/cron.sh', '/etc/crontabs/root', f.directory + '/crontab');
    f.patch('init-hijserver.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.script('fw4', 'echo firewall >>"$EVENTS"');
    f.script('cron-init', 'echo cron >>"$EVENTS"');
    for (const file of ['firewall/route.sh', 'rules/geoview.sh'])
        fs.writeFileSync(f.runtime + '/' + file, '#!/bin/sh\necho unexpected >>"$EVENTS"\nexit 1\n', { mode: 0o755 });
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/server', f.directory + '/server');
    withConfig([], config => {
        fs.writeFileSync(config + '/hijserver', "config hijserver\n option enabled '1'\nconfig server_node 'server'\n option enabled '1'\n option name 'server'\n option type 'shadowsocks'\n option core 'xray'\n option method 'aes-128-gcm'\n option password 'test'\n option allow_firewall '1'\n option listen_port '8443'\n");
        const prepared = f.run('service/prepare.sh', ['server', '--configdir', config], { EVENTS: events });
        assert.equal(prepared.status, 0, prepared.stderr);
        assert.deepEqual(JSON.parse(prepared.stdout).instances[0].command,
            ['xray', 'run', '-c', f.directory + '/server/server-server.json']);
        assert.equal(JSON.parse(fs.readFileSync(f.directory + '/server/server-server.json')).inbounds[0].protocol, 'shadowsocks');
        assert.equal(fs.existsSync(table), false);
        assert.equal(fs.existsSync(events), false);
        const activated = f.init('hijserver', 'service_started', config, { EVENTS: events });
        assert.equal(activated.status, 0, activated.stderr);
        assert.match(fs.readFileSync(table, 'utf8'), /8443/);
        assert.deepEqual(fs.readFileSync(events, 'utf8').trim().split('\n'), ['firewall', 'cron']);
        assert.equal(f.init('hijserver', 'stop_service', config, { EVENTS: events }).status, 0);
        assert.equal(fs.existsSync(table), false);
        assert.equal(fs.existsSync(chain), false);
    });
});

for (const fail of ['hook', 'route', 'cron']) test(`客户端停止时各阶段失败仍继续后续清理：${fail}`, t => {
    const f = fixture(t), events = f.directory + '/events';
    for (const [file, stage] of [['route.sh', 'route']])
        fs.writeFileSync(f.runtime + '/firewall/' + file,
            `#!/bin/sh\necho '${stage}' >>"$EVENTS"\n[ "$FAIL_STAGE" != '${stage}' ]\n`, { mode: 0o755 });
    f.script('fw4', 'echo firewall >>"$EVENTS"\n[ "$FAIL_STAGE" != firewall ]');
    f.script('dns-hook', 'echo hook >>"$EVENTS"\n[ "$FAIL_STAGE" != hook ]');
    f.script('cron-init', 'echo cron >>"$EVENTS"\n[ "$FAIL_STAGE" != cron ]');
    f.patch('init-hijpass.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.patch('service/cron.sh', '/etc/crontabs/root', f.directory + '/crontab');
    f.patch('init-hijpass.sh', '/etc/hijpass/hook/dns-hook.sh', f.directory + '/dns-hook');
    const generated = ['/etc/hijpass/chinadns-ng.conf', '/tmp/hijpass/domain-proxy-geo.txt', '/tmp/hijpass/domain-direct-geo.txt'];
    for (const file of generated) {
        const target = f.directory + '/' + path.basename(file);
        fs.writeFileSync(target, 'prepared DNS configuration');
        f.patch('init-hijpass.sh', file, target);
    }
    withConfig([{ '.type': 'hijpass', enabled: '1' }], config => {
        const result = f.init('hijpass', 'stop_service', config, { EVENTS: events, FAIL_STAGE: fail });
        assert.equal(result.status, fail === 'cron' ? 1 : 0, result.stderr);
    });
    assert.deepEqual(fs.readFileSync(events, 'utf8').trim().split('\n'), ['hook', 'firewall', 'route', 'cron']);
    for (const file of generated) assert.equal(fs.readFileSync(f.directory + '/' + path.basename(file), 'utf8'), 'prepared DNS configuration');
    assert.match(fs.readFileSync(f.directory + '/logs/hijpass.log', 'utf8'), /ERROR.*failed: exit=1/);
});

for (const fail of ['firewall', 'cron']) test(`服务端停止时各阶段失败仍继续后续清理：${fail}`, t => {
    const f = fixture(t), events = f.directory + '/events';
    f.patch('init-hijserver.sh', '/usr/share/nftables.d/table-post/hijserver.nft', f.directory + '/server.nft');
    f.patch('init-hijserver.sh', '/usr/share/nftables.d/chain-pre/input_wan/hijserver.nft', f.directory + '/chain.nft');
    f.patch('service/cron.sh', '/etc/crontabs/root', f.directory + '/crontab');
    f.patch('init-hijserver.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.script('fw4', 'echo firewall >>"$EVENTS"\n[ "$FAIL_STAGE" != firewall ]');
    f.script('cron-init', 'echo cron >>"$EVENTS"\n[ "$FAIL_STAGE" != cron ]');
    withConfig([], config => {
        fs.writeFileSync(config + '/hijserver', "config hijserver\n option enabled '1'\n");
        const result = f.init('hijserver', 'stop_service', config, { EVENTS: events, FAIL_STAGE: fail });
        assert.equal(result.status, fail === 'cron' ? 1 : 0, result.stderr);
    });
    assert.deepEqual(fs.readFileSync(events, 'utf8').trim().split('\n'), ['firewall', 'cron']);
});

for (const core of ['xray', 'sing-box']) test(`配置准备仅生成 ${core} 检查命令，检查留给逐实例注册`, t => {
    const f = fixture(t), client = f.directory + '/client files', args = f.directory + '/check-args';
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/client', client);
    f.script(core, `printf '%s\\n' "$CHECK_ENV" "$@" >"$CHECK_ARGS"
[ "$FAIL_CHECK" != 1 ]`);
    const sections = [{ '.type': 'hijpass', enabled: '1' },
        { '.type': 'proxy_node', '.name': 'ss', enabled: '1', name: 'test node', type: 'shadowsocks', core,
            server: '192.0.2.10', server_port: '443', listen_port: '10001', socks_port: '10002',
            method: 'aes-128-gcm', password: 'test', procd_env: ['CHECK_ENV=value with spaces'] }];
    withConfig(sections, config => {
        const check = core === 'xray' ? ['run', '-test', '-c'] : ['check', '-c'];
        const result = f.run('service/prepare.sh', ['--configdir', config], { CHECK_ARGS: args });
        assert.equal(result.status, 0, result.stderr);
        const plan = JSON.parse(result.stdout), filename = client + '/test node-ss.json';
        assert.deepEqual(plan.instances[0].check, [core, ...check, filename]);
        assert.deepEqual(plan.instances[0].env, ['CHECK_ENV=value with spaces']);
        assert.equal(fs.existsSync(args), false);
    });
});

test('防火墙脚本统一删除和重载，删除失败记录原因并停止重载', t => {
    const f = fixture(t), rules = f.directory + '/rules.nft', calls = f.directory + '/calls';
    f.script('fw4', `echo "$1" >>'${calls}'`);
    fs.mkdirSync(rules);
    let result = f.run('firewall/firewall.sh', ['remove']);
    assert.equal(result.status, 1);
    assert.equal(fs.existsSync(calls), false);
    const log = fs.readFileSync(f.directory + '/logs/hijpass.log', 'utf8');
    assert.match(log, /ERROR.*Remove hijpass firewall rules: .*rules\.nft/);
    assert.match(log, /ERROR.*Remove hijpass firewall rules failed: exit=1/);
    fs.rmdirSync(rules);
    fs.writeFileSync(rules, 'old rules');
    result = f.run('firewall/firewall.sh', ['remove']);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.existsSync(rules), false);
    assert.equal(fs.readFileSync(calls, 'utf8'), 'reload\n');
    assert.equal(f.run('firewall/firewall.sh', ['invalid']).status, 1);
    assert.equal(fs.readFileSync(calls, 'utf8'), 'reload\n');
});

for (const failure of ['write', 'reload']) test(`cron ${failure} 失败时普通日志包含阶段、原因和退出码`, t => {
    const f = fixture(t), crontab = f.directory + '/crontab', calls = f.directory + '/calls';
    f.patch('service/cron.sh', '/etc/crontabs/root', crontab);
    f.patch('init-hijpass.sh', '/etc/init.d/cron', f.directory + '/cron-init');
    f.script('cron-init', `echo reload >>'${calls}'; echo 'cron reload detail' >&2; exit 7`);
    if (failure === 'write') fs.mkdirSync(crontab);
    withConfig([{ '.type': 'hijpass', enabled: '1', log_level: 'INFO' }], config => {
        const result = f.init('hijpass', 'update_cron', config);
        assert.equal(result.status, failure === 'write' ? 1 : 7, result.stderr);
    });
    const log = fs.readFileSync(f.directory + '/logs/hijpass.log', 'utf8');
    if (failure === 'write') {
        assert.match(log, /ERROR.*Write hijpass cron entries: .*crontab/);
        assert.match(log, /ERROR.*Write hijpass cron entries failed: exit=1/);
        assert.equal(fs.existsSync(calls), false);
    } else {
        assert.match(log, /ERROR.*Reload cron for hijpass: cron reload detail/);
        assert.match(log, /ERROR.*Reload cron for hijpass failed: exit=7/);
    }
});

test('规则提交完成后释放更新锁再重启，保留重启失败的退出状态', t => {
    const f = fixture(t), calls = f.directory + '/restart';
    f.patch('ucode/hijpass/config/paths.uc', '/etc/hijpass/rules', f.directory + '/rules');
    f.patch('rules/rules.uc', '/usr/share/v2ray/', f.directory + '/geo/');
    f.patch('rules/update-files.sh', '/etc/init.d/hijpass', f.directory + '/hijpass-init');
    f.script('curl', `while [ "$1" != -o ]; do shift; done
printf '%s\\n' 'example.org' 'another-example.org' 'yet-another-example.org' 'domain-one.example.org' 'domain-two.example.org' 'domain-three.example.org' >"$2"`);
    f.script('geoview', 'exit 0');
    f.script('hijpass-init', `exec 7>'${f.runtime}/jobs/updates.lock'
flock -n 7 || exit 9
[ ! -d '${f.runtime}/jobs/work' ] || exit 8
echo restart >>'${calls}'
exit "\${RESTART_EXIT:-0}"`);
    const urls = ['https://example.org/rules'];
    withConfig([{ '.type': 'hijpass', enabled: '1' }, { '.type': 'rule', retry_count: '1',
        chn_domain_list: urls, gfw_list: urls, chn_v4_route: urls, chn_v6_route: urls, geoip: urls, geosite: urls }], config => {
        // 用真实 Geo 资源选择，但替换文本规范化，避免把本测试变成规则格式测试。
        f.patch('rules/rules.uc', "if (action == 'normalize') {", "if (action == 'normalize') { return text(args[1]);");
        for (const code of [0, 7]) {
            const result = f.run('rules/update-files.sh', ['update', '--configdir', config], { RESTART_EXIT: String(code) });
            assert.equal(result.status, code ? 1 : 0, result.stderr);
            assert.equal(JSON.parse(result.stdout).success, code === 0);
        }
    });
    assert.equal(fs.readFileSync(calls, 'utf8'), 'restart\nrestart\n');
});

test('核心更新与规则更新共用锁，旧锁文件存在但无人持有时不阻止新操作', t => {
    const f = fixture(t);
    f.script('curl', 'echo contacted >>"$CALLS"; exit 28');
    const lock = f.runtime + '/jobs/updates.lock';
    fs.mkdirSync(path.dirname(lock), { recursive: true });
    fs.writeFileSync(lock, 'old state');
    f.script('run-locked', `. '${f.runtime}/common.sh'
hijpass_lock_updates || exit 1
'${f.runtime}/core/update.sh' update xray`);
    const busy = f.run('../run-locked', [], { CALLS: f.directory + '/calls' });
    assert.equal(busy.status, 75, busy.stderr);
    assert.match(JSON.parse(busy.stdout).error, /running/);
    assert.equal(fs.existsSync(f.directory + '/calls'), false);
    const retry = f.run('core/update.sh', ['update', 'xray'], { CALLS: f.directory + '/calls' });
    assert.equal(retry.status, 1, retry.stderr);
    assert.match(JSON.parse(retry.stdout).error, /fetch core release/);
    assert.equal(fs.readFileSync(f.directory + '/calls', 'utf8'), 'contacted\n');
});

test('启动回收已结束及 PID 被复用的任务，保留仍运行任务和锁文件', async t => {
    const f = fixture(t), jobs = f.runtime + '/jobs', release = f.directory + '/release';
    fs.mkdirSync(jobs, { recursive: true });
    for (const [id, pid] of [['Dead1234', '2147483647'], ['Reuse123', String(process.pid)]]) {
        const dir = jobs + '/' + id;
        fs.mkdirSync(dir);
        fs.writeFileSync(dir + '/pid', pid);
        fs.writeFileSync(dir + '/kind', 'rules');
    }
    fs.writeFileSync(jobs + '/rules.active', 'Dead1234');
    fs.mkdirSync(jobs + '/work');
    fs.writeFileSync(jobs + '/work/download', 'unfinished');
    fs.writeFileSync(f.runtime + '/core/update.sh', `#!/usr/bin/busybox ash
while [ ! -f '${release}' ]; do sleep 0.05; done
printf '{"success":true}\\n'
`);
    const created = f.run('rpc/jobs.sh', ['start', 'xray']);
    const id = JSON.parse(created.stdout).id;
    const inode = fs.statSync(jobs + '/registry.lock').ino;
    try {
        assert.equal(f.run('rpc/jobs.sh', ['clear']).status, 0);
        assert.equal(fs.existsSync(jobs + '/Dead1234'), false);
        assert.equal(fs.existsSync(jobs + '/Reuse123'), false);
        assert.equal(fs.existsSync(jobs + '/rules.active'), false);
        assert.equal(fs.existsSync(jobs + '/work'), false);
        assert.equal(fs.existsSync(jobs + '/' + id), true);
        assert.equal(fs.statSync(jobs + '/registry.lock').ino, inode);
    } finally { fs.writeFileSync(release, ''); }
    await until(() => fs.existsSync(jobs + '/' + id + '/exit'));
    assert.equal(f.run('rpc/jobs.sh', ['clear']).status, 0);
    assert.equal(fs.existsSync(jobs + '/' + id), false);
});

for (const core of ['xray', 'sing-box']) test(`${core} 刷新恢复活动任务，下载大小实时读取且重复点击不会启动第二个任务`, async t => {
    const f = fixture(t), release = f.directory + '/release', started = f.directory + '/started', download = f.directory + '/download';
    fs.writeFileSync(f.runtime + '/core/update.sh', `#!/usr/bin/busybox ash
. '${f.runtime}/common.sh'
printf started >>'${started}'
printf 1234 >'${download}'
hijpass_progress download archive '${download}'
while [ ! -f '${release}' ]; do sleep 0.05; done
hijpass_progress install "$2"
printf '{"success":true}\\n'
`);
    const first = JSON.parse(f.run('rpc/jobs.sh', ['start', core]).stdout);
    try {
        await until(() => fs.existsSync(download));
        await until(() => JSON.parse(f.run('rpc/jobs.sh', ['status', first.id]).stdout).progress?.phase === 'download');
        assert.equal(JSON.parse(f.run('rpc/jobs.sh', ['current', core]).stdout).id, first.id);
        assert.equal(JSON.parse(f.run('rpc/jobs.sh', ['start', core]).stdout).id, first.id);
        assert.equal(fs.readFileSync(started, 'utf8'), 'started');
        assert.equal(JSON.parse(f.run('rpc/jobs.sh', ['status', first.id]).stdout).progress.bytes, 4);
        fs.appendFileSync(download, '5678');
        assert.equal(JSON.parse(f.run('rpc/jobs.sh', ['status', first.id]).stdout).progress.bytes, 8);
    } finally { fs.writeFileSync(release, ''); }
    await until(() => !JSON.parse(f.run('rpc/jobs.sh', ['status', first.id]).stdout).running);
    assert.equal(JSON.parse(f.run('rpc/jobs.sh', ['current', core]).stdout).id, null);
    assert.equal(JSON.parse(f.run('rpc/jobs.sh', ['status', first.id]).stdout).code, 0);
});
