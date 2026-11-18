const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { root, shellRuntime } = require('./helpers.cjs');

// testdata/rc.common 来自 OpenWrt base-files；执行原生 start/stop/restart 包装。
// https://github.com/openwrt/openwrt/blob/master/package/base-files/files/etc/rc.common
function fixture(t, service = 'hijpass') {
    const directory = fs.mkdtempSync('/tmp/hijpass-init-test-');
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const runtime = directory + '/runtime', original = shellRuntime(), events = directory + '/events';
    fs.cpSync(original, runtime, { recursive: true });
    for (const name of fs.readdirSync(runtime, { recursive: true })) {
        if (!/\.(uc|sh)$/.test(name) && name !== 'testbin/ucode') continue;
        const file = runtime + '/' + name;
        fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replaceAll(original, runtime));
    }
    const patch = (file, before, after) => fs.writeFileSync(runtime + '/' + file,
        fs.readFileSync(runtime + '/' + file, 'utf8').replaceAll(before, after));
    patch('ucode/hijpass/config/paths.uc', '/tmp/hijpass/log', directory + '/log');
    patch('firewall/firewall.sh', '/etc/hijpass/fw4-rules.nft', directory + '/rules.nft');
    const script = (file, text) => fs.writeFileSync(file, '#!/usr/bin/busybox ash\n' + text, { mode: 0o755 });
    script(runtime + '/diagnostics/task.sh', 'echo \"trace:$1\" >>\"$EVENTS\"\n[ \"$FAIL_PHASE\" != trace:clear ]');
    script(runtime + '/service/prepare.sh', `
service=hijpass
[ "$1" != server ] || { service=hijserver; shift; }
case "$1" in server-files) exec '${directory}/data-mock' "$@" ;; esac
echo "$service:prepare" >>"$EVENTS"
[ "$FAIL_PHASE" != prepare ] || exit 1
if [ "$DISABLED" = 1 ]; then echo '{"instances":[]}'; else cat "$PLAN"; fi
`);
    const plan = { instances: [{ id: 'node', name: 'test space', command: ['sing-box', 'run', '-c', directory + '/config space.json'],
        env: ['TEST_CORE_ENV=value with spaces'], user: 'root', log: null, shunt: false }] };
    const planPath = directory + '/plan.json';
    fs.writeFileSync(planPath, JSON.stringify(plan));
    fs.mkdirSync(directory + '/lib/functions', { recursive: true });
    fs.mkdirSync(directory + '/bin');
    fs.mkdirSync(directory + '/config');
    fs.writeFileSync(directory + '/config/hijpass', "config hijpass\n option delay_time '1'\n");
    const uci = spawnSync('sh', ['-c', 'command -v uci'], { encoding: 'utf8' }).stdout.trim();
    assert.ok(uci, 'native UCI CLI is required');
    script(directory + '/bin/uci', `exec '${uci}' -c '${directory}/config' "$@"`);
    fs.writeFileSync(directory + '/lib/functions.sh', `list_contains() { return 0; }\n`);
    fs.writeFileSync(directory + '/lib/functions/service.sh', `
procd_running() { echo unexpected-poll >>"$EVENTS"; return 1; }
`);
    for (const [file, stage] of [['firewall/route.sh', 'route']])
        script(runtime + '/' + file, `echo "${stage}:$1" >>"$EVENTS"\n[ "$FAIL_PHASE" != "${stage}:$1" ]`);
    script(directory + '/dns-hook', 'echo "hook:$1" >>"$EVENTS"\n[ "$FAIL_PHASE" != "hook:$1" ]');
    script(directory + '/bin/fw4', 'echo "fw4:$1" >>"$EVENTS"\n[ "$FAIL_PHASE" != fw4 ]');
    script(directory + '/cron-write', `echo "cron:write $1" >>"$EVENTS"
printf '%s\\n' "$@" >"$IPKG_INSTROOT/cron-args"
[ "$FAIL_PHASE" != "cron:write $1" ]`);
    script(directory + '/cron-init', 'echo "cron:$1" >>"$EVENTS"\n[ "$FAIL_PHASE" != "cron:$1" ]');
    script(directory + '/data-mock', `
[ "$1" != server ] || shift
echo "data:$1" >>"$EVENTS"
[ "$FAIL_PHASE" != "data:$1" ] || exit 1
`);
    // 只替换 procd/ubus 边界；JSON namespace 与原生 procd API 保持一致。
    fs.writeFileSync(directory + '/lib/functions/procd.sh', `
_procd_call() {
    local old_cb
    json_set_namespace procd old_cb
    "$@"
    json_set_namespace "$old_cb"
}
procd_open_service() { _procd_call open_service "$@"; }
open_service() { json_init; json_add_string name "$1"; json_add_object instances; }
procd_open_instance() { _procd_call json_add_object "$1"; }
procd_close_instance() { _procd_call json_close_object; }
procd_set_param() { _procd_call set_param "$@"; }
set_param() {
    local key="$1" value
    shift
    case "$key" in command|env)
        json_add_array "$key"
        for value in "$@"; do json_add_string '' "$value"; done
        json_close_array ;;
    esac
}
procd_close_service() { _procd_call close_service; }
close_service() {
    json_close_object
    json_get_var service name
    echo "$service:submit" >>"$EVENTS"
    json_dump >"$IPKG_INSTROOT/submitted.json"
    touch "$IPKG_INSTROOT/registered-$service"
    json_cleanup
}
procd_lock() { :; }
procd_kill() { echo "$1:kill" >>"$EVENTS"; rm -f "$IPKG_INSTROOT/registered-$1"; }
`);
    const init = directory + '/' + service;
    let source = fs.readFileSync(root + '/root/etc/init.d/' + service, 'utf8').replaceAll('/usr/lib/hijpass', runtime);
    source = source.replace('"$HIJPASS_LIB/service/cron.sh" ' + service, `'${directory}/cron-write' "$1" ${service}`);
    // reload_service 的自调用也经过同一份原生 rc.common。
    source = source.replace('/etc/init.d/' + service + ' restart',
        `/usr/bin/busybox ash '${root}/tests/backend/testdata/rc.common' '${init}' restart`);
    source = source.replace('/etc/hijpass/hook/dns-hook.sh', directory + '/dns-hook')
        .replace('/etc/init.d/cron', directory + '/cron-init')
        .replace('/usr/share/nftables.d/table-post/hijserver.nft', directory + '/server.nft')
        .replace('/usr/share/nftables.d/chain-pre/input_wan/hijserver.nft', directory + '/chain.nft');
    fs.writeFileSync(runtime + '/firewall/generatecli.uc', `import * as fs from 'fs';
let file = fs.open(getenv('EVENTS'), 'a'); file.write('firewall:generate\\n'); file.close();
exit(getenv('FAIL_PHASE') == 'firewall:generate' ? 1 : 0);
`);
    source += `\nsleep() { echo "delay:$1" >>"$EVENTS"; [ "$FAIL_PHASE" != sleep ]; }\n`;
    fs.writeFileSync(init, source);
    function run(action, fail = '', extra = {}) {
        fs.writeFileSync(events, '');
        return spawnSync('/usr/bin/busybox', ['ash', root + '/tests/backend/testdata/rc.common', init, action], {
            encoding: 'utf8', timeout: 10000, env: { ...process.env, IPKG_INSTROOT: directory, EVENTS: events, PLAN: planPath,
                FAIL_PHASE: fail, ...extra, PATH: directory + '/bin:' + runtime + '/testbin:' + process.env.PATH },
        });
    }
    return { directory, runtime, plan, planPath, patch, script, run,
        events: () => fs.readFileSync(events, 'utf8').trim().split('\n').filter(Boolean) };
}

for (const service of ['hijpass', 'hijserver']) {
    const preparation = [...(service === 'hijpass' ? ['trace:clear'] : []), service + ':prepare'];
    const setup = service === 'hijpass'
        ? ['route:reset', 'firewall:generate', 'fw4:reload', 'hook:start', 'cron:write enable', 'cron:restart']
        : ['data:server-files', 'fw4:reload', 'cron:write enable', 'cron:restart'];
    const cleanup = service === 'hijpass'
        ? ['hook:stop', 'fw4:reload', 'route:remove', 'cron:write disable', 'cron:restart']
        : ['fw4:reload', 'cron:write disable', 'cron:restart'];

    test(`${service}: init.d 在提交后直接按顺序设置辅助功能，不查询进程、不重复清理`, t => {
        const f = fixture(t, service);
        assert.equal(f.run('start').status, 0);
        assert.deepEqual(f.events(), [...preparation, service + ':submit', ...setup]);
        assert.equal(f.run('start').status, 0);
        assert.deepEqual(f.events(), [...preparation, service + ':submit', ...setup]);
        const log = fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8');
        assert.equal((log.match(service === 'hijpass' ? /Starting hijpass/g : /Starting hijserver/g) || []).length, 2);
        assert.doesNotMatch(log, /Service started|Service setup completed/);
    });
    test(`${service}: 准备失败不提交实例、不设置网络`, t => {
        const f = fixture(t, service);
        assert.notEqual(f.run('start', 'prepare').status, 0);
        assert.deepEqual(f.events(), [...preparation]);
    });
    test(`${service}: rc.common 加载的日志使用 init 脚本路径且无需显式行号`, t => {
        const f = fixture(t, service), init = f.directory + '/' + service;
        fs.appendFileSync(f.directory + '/config/hijpass', " option log_level 'DEBUG'\n");
        f.patch('testbin/ucode', 'exec ', `set -- "$@" --configdir '${f.directory}/config'\nexec `);
        assert.equal(f.run('start').status, 0);
        const log = fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8');
        for (const message of ['Starting ', `Prepare ${service} configurations`]) {
            assert.ok(log.split('\n').some(line => line.includes(`${init} `) && line.includes(message)), log);
        }
        assert.doesNotMatch(log, /rc\.common|hijpass:\d+|hijserver:\d+|\[(service|server)\]/);
    });
    for (const failure of setup) {
        test(`${service}: ${failure} 失败记录日志后继续独立阶段，不停止实例`, t => {
            const f = fixture(t, service);
            assert.equal(f.run('start', failure === 'fw4:reload' ? 'fw4' : failure).status,
                failure.startsWith('cron:') ? 1 : 0);
            const skipped = failure === 'firewall:generate' || failure === 'data:server-files' ? 'fw4:reload'
                : failure === 'cron:write enable' ? 'cron:restart' : '';
            assert.deepEqual(f.events(), [...preparation, service + ':submit', ...setup.filter(event => event !== skipped)]);
            const log = fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8');
            assert.match(log, /ERROR.*failed: exit=1/);
            assert.doesNotMatch(log, /Service setup completed with errors/);
            assert.doesNotMatch(log, /Service started/);
        });
    }
    test(`${service}: stop 先撤流再停实例，reload 只清理一次后重新启动`, t => {
        const f = fixture(t, service);
        assert.equal(f.run('stop').status, 0);
        assert.deepEqual(f.events(), [...cleanup, service + ':kill']);
        const log = fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8');
        assert.match(log, service === 'hijpass' ? /Stopping hijpass/ : /Stopping hijserver/);
        assert.doesNotMatch(log, /Service resources removed|Service cleanup completed/);
        assert.equal(f.run('reload').status, 0);
        assert.deepEqual(f.events(), [...cleanup, service + ':kill', ...preparation, service + ':submit', ...setup]);
    });
    for (const action of ['stop', 'restart', 'reload']) {
        for (const failure of cleanup) test(`${service}: ${action} 的 ${failure} 失败仍完成清理并交回框架`, t => {
            const f = fixture(t, service);
            const result = f.run(action, failure === 'fw4:reload' ? 'fw4' : failure);
            const expectedCleanup = cleanup.filter(event => failure !== 'cron:write disable' || event !== 'cron:restart');
            assert.deepEqual(f.events(), [...expectedCleanup, service + ':kill',
                ...(action === 'stop' ? [] : [...preparation, service + ':submit', ...setup])]);
            assert.equal(result.status, action !== 'stop' && failure === 'cron:restart' ? 1 : 0, result.stderr);
            const log = fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8');
            assert.match(log, /ERROR.*failed: exit=1/);
            assert.doesNotMatch(log, /Service cleanup completed with errors/);
        });
    }
    test(`${service}: 规则文件删除失败跳过 reload，仍完成其他清理并停止实例`, t => {
        const f = fixture(t, service);
        fs.mkdirSync(f.directory + (service === 'hijpass' ? '/rules.nft' : '/server.nft'));
        const result = f.run('stop');
        assert.equal(result.status, 0, result.stderr);
        assert.deepEqual(f.events(), [...cleanup.filter(event => event !== 'fw4:reload'), service + ':kill']);
        const log = fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8');
        assert.match(log, new RegExp(`Remove ${service} firewall rules failed: exit=1`));
        assert.doesNotMatch(log, /Service cleanup completed with errors/);
    });
    test(`${service}: 启动延时失败记日志并终止本次启动`, t => {
        const f = fixture(t, service);
        assert.equal(f.run('boot', 'sleep').status, 1);
        assert.deepEqual(f.events(), service === 'hijpass' ? ['delay:1'] : ['delay:10']);
        assert.match(fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8'), new RegExp(`Wait for ${service} startup delay failed: exit=1`));
    });
    if (service === 'hijpass') {
        for (const delay of ['invalid', '-1', '1.5']) test(`非法启动延时记录警告并使用默认十秒继续启动：${delay}`, t => {
            const f = fixture(t);
            fs.writeFileSync(f.directory + '/config/hijpass', `config hijpass\n option delay_time '${delay}'\n`);
            const result = f.run('boot');
            assert.equal(result.status, 0, result.stderr);
            assert.deepEqual(f.events(), ['delay:10', ...preparation, service + ':submit', ...setup]);
            assert.match(fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8'),
                /WARN\s+Invalid hijpass startup delay; using default 10 seconds/);
        });
        for (const [config, delay] of [
            ["config hijpass\n option delay_time '12'\n", '12'],
            ["config hijpass 'global'\n option delay_time '08'\n", '08'],
            ["config hijpass\n option delay_time '0'\n", null],
            ["config hijpass\n", '10'],
            ["config hijpass\n option delay_time ''\n", '10'],
            ["config firewall\n", '10'],
            [null, '10'],
            ["config hijpass\n option delay_time 'broken\n", '10'],
        ]) test(`boot 使用配置延时，读取失败或字段为空时默认十秒：${config}`, t => {
            const f = fixture(t);
            if (config == null) fs.unlinkSync(f.directory + '/config/hijpass');
            else fs.writeFileSync(f.directory + '/config/hijpass', config);
            const result = f.run('boot');
            assert.equal(result.status, 0, result.stderr);
            assert.deepEqual(f.events(), [...(delay ? ['delay:' + delay] : []), ...preparation, service + ':submit', ...setup]);
        });
    }
    for (const plan of ['', '{', '{}', '{"instances":{}}', '{"instances":null}']) {
        test(`${service}: 拒绝无效计划 ${plan || '(empty)'}，不当作禁用服务`, t => {
            const f = fixture(t, service);
            fs.writeFileSync(f.planPath, plan);
            assert.notEqual(f.run('start').status, 0);
            assert.deepEqual(f.events(), [...preparation]);
        });
    }
    test(`${service}: 空实例提交，不重新设置网络`, t => {
        const f = fixture(t, service);
        assert.equal(f.run('start', '', { DISABLED: '1' }).status, 0);
        assert.deepEqual(f.events(), [...preparation, service + ':submit']);
        assert.deepEqual(JSON.parse(fs.readFileSync(f.directory + '/submitted.json')).instances, {});
    });
}

test('自定义命令和带空格参数按原值交给 procd，不重拼 Shell 字符串', t => {
    const f = fixture(t);
    f.plan.instances[0].command = ['/bin/sh', '-c', "program -c '/etc/hijpass/client/custom.json'"];
    fs.writeFileSync(f.planPath, JSON.stringify(f.plan));
    const result = f.run('start');
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(fs.readFileSync(f.directory + '/submitted.json')).instances['node-test space'].command,
        [f.runtime + '/service/process.sh', '', ...f.plan.instances[0].command]);
});

test('多个实例全部声明后直接应用辅助配置', t => {
    const f = fixture(t);
    f.plan.instances.push({ ...f.plan.instances[0], id: 'second', name: 'node' });
    fs.writeFileSync(f.planPath, JSON.stringify(f.plan));
    assert.equal(f.run('start').status, 0);
    assert.deepEqual(Object.keys(JSON.parse(fs.readFileSync(f.directory + '/submitted.json')).instances),
        ['node-test space', 'second-node']);
    assert.ok(!f.events().includes('unexpected-poll'));
});

for (const service of ['hijpass', 'hijserver']) {
    test(`${service}: 单个实例无效时记录原因，继续提交前后有效实例`, t => {
        const f = fixture(t, service);
        f.plan.instances.push(null, { id: 'broken', name: 'broken', command: [] }, { ...f.plan.instances[0], id: 'last' });
        fs.writeFileSync(f.planPath, JSON.stringify(f.plan));
        assert.equal(f.run('start').status, 0);
        const instances = JSON.parse(fs.readFileSync(f.directory + '/submitted.json')).instances;
        assert.deepEqual(Object.keys(instances), ['node-test space', 'last-test space']);
        const log = fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8');
        assert.match(log, /Invalid (?:hijpass|hijserver) instance entry: index=2/);
        assert.match(log, /Prepare (?:hijpass|hijserver) instance broken \(broken\): Invalid service instance: empty command/);
        assert.match(log, /Prepare (?:hijpass|hijserver) instance broken \(broken\) failed: exit=1/);
        assert.ok(!f.events().some(event => /:kill$/.test(event)));
    });
    test(`${service}: 全部实例无效仍提交空列表，不重新激活辅助功能`, t => {
        const f = fixture(t, service);
        f.plan.instances = [null, { id: 'broken', name: 'broken', command: [] }];
        fs.writeFileSync(f.planPath, JSON.stringify(f.plan));
        assert.equal(f.run('start').status, 0);
        assert.deepEqual(JSON.parse(fs.readFileSync(f.directory + '/submitted.json')).instances, {});
        const events = f.events();
        assert.ok(events.includes(service + ':submit'));
        assert.equal(events.includes('cron:write disable'), false);
        assert.ok(!events.includes('cron:write enable'));
    });
    for (const core of ['xray', 'sing-box']) test(`${service}: ${core} 检查失败只跳过当前实例，记录详情并保留 argv 和环境变量`, t => {
        const f = fixture(t, service), check = f.directory + '/bin/' + core, args = f.directory + '/check-args';
        f.script(check, `printf '%s\\n' "$CHECK_ENV" "$@" >>'${args}'
if [ "$CHECK_FAIL" = 1 ]; then echo 'invalid core configuration' >&2; exit 7; fi`);
        const options = core === 'xray' ? ['run', '-test', '-c'] : ['check', '-c'];
        const valid = { ...f.plan.instances[0], check: [check, ...options, 'config with spaces.json'], env: ['CHECK_ENV=value with spaces'] };
        f.plan.instances = [{ ...valid, id: 'broken', env: [...valid.env, 'CHECK_FAIL=1'] }, valid];
        fs.writeFileSync(f.planPath, JSON.stringify(f.plan));
        assert.equal(f.run('start').status, 0);
        assert.deepEqual(fs.readFileSync(args, 'utf8').trim().split('\n'),
            Array(2).fill(['value with spaces', ...options, 'config with spaces.json']).flat());
        const instances = JSON.parse(fs.readFileSync(f.directory + '/submitted.json')).instances;
        assert.deepEqual(Object.keys(instances), ['node-test space']);
        assert.deepEqual(instances['node-test space'].command, [f.runtime + '/service/process.sh', '', ...valid.command]);
        assert.deepEqual(instances['node-test space'].env, valid.env);
        const log = fs.readFileSync(f.directory + '/log/hijpass.log', 'utf8');
        assert.match(log, /Prepare (?:hijpass|hijserver) instance broken \(test space\): invalid core configuration/);
        assert.match(log, /Prepare (?:hijpass|hijserver) instance broken \(test space\) failed: exit=7/);
    });
}

for (const log of [null, '/tmp/server.log']) test(`服务端 cron 使用启动计划中的日志开关：${log}`, t => {
    const f = fixture(t, 'hijserver');
    f.plan.instances[0].log = log;
    fs.writeFileSync(f.planPath, JSON.stringify(f.plan));
    assert.equal(f.run('start').status, 0);
    assert.deepEqual(fs.readFileSync(f.directory + '/cron-args', 'utf8').split('\n'),
        ['enable', 'hijserver', '', log ? '1' : '0', '']);
    assert.equal(f.events().filter(event => event === 'hijserver:prepare').length, 1);
});

for (const action of ['start', 'stop', 'restart', 'reload']) test(`hijpass: ${action} 在更新锁释放前不改变服务`, async t => {
    const { spawn } = require('node:child_process');
    const f = fixture(t), ready = f.directory + '/ready', release = f.directory + '/release';
    const holderFile = f.directory + '/hold-update';
    f.script(holderFile, `. '${f.runtime}/common.sh'
hijpass_lock_updates || exit 1
touch '${ready}'
while [ ! -f '${release}' ]; do sleep 0.02; done
`);
    const holder = spawn('/usr/bin/busybox', ['ash', holderFile], { env: process.env, stdio: 'ignore' });
    const held = new Promise(resolve => holder.on('exit', resolve));
    let child;
    try {
        for (let i = 0; i < 200 && !fs.existsSync(ready); i++) await new Promise(r => setTimeout(r, 10));
        assert.ok(fs.existsSync(ready), 'update acquired lock');
        child = spawn('/usr/bin/busybox', ['ash', root + '/tests/backend/testdata/rc.common', f.directory + '/hijpass', action], {
            env: { ...process.env, IPKG_INSTROOT: f.directory, EVENTS: f.directory + '/events', PLAN: f.planPath,
                PATH: f.directory + '/bin:' + f.runtime + '/testbin:' + process.env.PATH }, stdio: 'ignore',
        });
        const done = new Promise(resolve => child.on('exit', resolve));
        await new Promise(r => setTimeout(r, 150));
        assert.equal(child.exitCode, null);
        assert.equal(fs.existsSync(f.directory + '/events'), false, 'no preparation, firewall or stop before unlock');
        fs.writeFileSync(release, '');
        assert.equal(await held, 0);
        assert.equal(await done, 0);
        assert.ok(f.events().length > 0);
        assert.equal(spawnSync('flock', ['-n', f.runtime + '/jobs/updates.lock', 'true']).status, 0);
    } finally {
        fs.writeFileSync(release, '');
        if (child && child.exitCode === null) child.kill('SIGKILL');
        if (holder.exitCode === null) holder.kill('SIGTERM');
    }
});

test('hijpass: 等待更新超时直接退出，rc.common 不继续停止或启动实例', t => {
    const f = fixture(t), init = f.directory + '/hijpass';
    fs.writeFileSync(init, fs.readFileSync(init, 'utf8').replace('hijpass_lock_updates 300', 'hijpass_lock_updates 0'));
    fs.mkdirSync(f.runtime + '/jobs', { recursive: true });
    const driver = f.directory + '/locked';
    f.script(driver, `exec 9>'${f.runtime}/jobs/updates.lock'
flock -x 9
export IPKG_INSTROOT='${f.directory}' EVENTS='${f.directory}/events' PLAN='${f.planPath}'
export PATH='${f.directory}/bin:${f.runtime}/testbin':"$PATH"
/usr/bin/busybox ash '${root}/tests/backend/testdata/rc.common' '${init}' restart
`);
    const blocked = spawnSync('/usr/bin/busybox', ['ash', driver], { encoding: 'utf8', timeout: 5000 });
    assert.equal(blocked.status, 1, blocked.stderr);
    assert.equal(fs.existsSync(f.directory + '/events'), false);
});
