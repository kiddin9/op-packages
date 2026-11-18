const assert = require('node:assert/strict');
const { readFileSync, writeFileSync, mkdtempSync, cpSync, readdirSync, chmodSync, rmSync, existsSync, mkdirSync, statSync } = require('node:fs');
const { execFileSync, spawnSync, spawn } = require('node:child_process');
const { test } = require('node:test');
const vm = require('node:vm');
const path = require('node:path');
const ts = require('typescript');

const root = path.resolve(__dirname, '../..');
const { interpreter } = require('../../tests/backend/helpers.cjs');
const shellQuote = value => "'" + value.replaceAll("'", "'\\''") + "'";
const defaults = {
    mode: 'client', clientIp: '192.168.1.100', protocol: 'all', port: '',
    url: '', method: 'HEAD', timeout: '30', tcpdump: false, tcpdumpInterface: 'any', verbose: false,
};

function loadPanel(fs, clock = { now: 0 }) {
    const source = readFileSync(path.join(root, 'ts-src/utils/feature/log/panel.ts'), 'utf8');
    const context = vm.createContext({
        exports: {}, require: name => name.endsWith('/backend') ? { Backend: {
            startTrace: args => fs.exec('trace', ['start', ...args]),
            traceStatus: id => fs.exec_direct('trace', ['status', id]),
            releaseTrace: id => fs.exec('trace', ['release', id]),
        } } : {}, _: value => value, console,
        Date: class extends Date { static now() { return clock.now; } },
        window: { setTimeout(fn, ms) { clock.now += ms; fn(); } },
    });
    vm.runInContext(ts.transpileModule(source, {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true },
    }).outputText, context);
    return context;
}

test('client capture requires no URL or HTTP method and sends protocol/port filters', () => {
    const panel = loadPanel({});
    assert.deepEqual(Array.from(panel.buildTraceArgs({ ...defaults, url: 'invalid', method: 'invalid' })),
        ['-t', '30', '-c', '192.168.1.100', '-n', 'all', '-P', 'all']);
    assert.deepEqual(Array.from(panel.buildTraceArgs({ ...defaults, protocol: 'udp', port: '443' })),
        ['-t', '30', '-c', '192.168.1.100', '-n', 'udp', '-P', '443']);
    for (const port of ['0', '65536', '443;id', '-1']) {
        assert.throws(() => panel.buildTraceArgs({ ...defaults, port }), /destination port/);
    }
    assert.throws(() => panel.buildTraceArgs({ ...defaults, protocol: 'udp;id' }), /transport protocol/);
    assert.throws(() => panel.buildTraceArgs({ ...defaults, timeout: '121' }), /between 1 and 120/);
    const router = Array.from(panel.buildTraceArgs({ ...defaults, mode: 'router', url: 'https://example.com', method: 'GET' }));
    assert.deepEqual(router, ['-t', '30', '-X', 'GET', 'https://example.com']);
});

for (const seconds of [30, 120]) {
    test(`${seconds}s capture survives the 20s RPC limit and releases its result`, async () => {
        const clock = { now: 0 };
        const calls = [];
        const fs = {
            async exec(command, args) {
                calls.push([command, ...args]);
                // Reproduces the previous fs.exec(trace-url.uc) failure.
                if (command.endsWith('/trace-url.uc')) throw new Error('XHR request timed out');
                if (args[0] === 'start') return { code: 0, stdout: 'ABcd1234\n', stderr: '' };
                return { code: 0, stdout: '', stderr: '' };
            },
            async exec_direct(command, args) {
                assert.equal(command, 'trace');
                assert.deepEqual(Array.from(args), ['status', 'ABcd1234']);
                const running = clock.now < seconds * 1000;
                return { running, code: running ? null : 0, stdout: running ? 'Trace is active' : 'capture complete', stderr: '' };
            },
        };
        const panel = loadPanel(fs, clock);
        const status = { style: {} }, output = {}, button = {};
        await panel.runTraceDiagnostics({ ...defaults, timeout: String(seconds) }, status, output, button);
        assert.match(status.textContent, /^Trace Completed/);
        assert.match(output.innerHTML, /capture complete/);
        assert.equal(clock.now, seconds * 1000);
        assert.equal(button.disabled, false);
        assert.equal(calls.length, 2);
        assert.equal(calls[1][1], 'release');
    });
}

test('worker errors retain diagnostics and restore the run button', async () => {
    const panel = loadPanel({
        async exec() { return { code: 0, stdout: 'ABcd1234', stderr: '' }; },
        async exec_direct() { return { running: false, code: 1, stdout: 'setup report', stderr: 'tcpdump is required' }; },
    });
    const status = { style: {} }, output = {}, button = {};
    await panel.runTraceDiagnostics(defaults, status, output, button);
    assert.match(status.textContent, /Trace Failed.*tcpdump is required/);
    assert.match(output.innerHTML, /setup report/);
    assert.match(output.innerHTML, /tcpdump is required/);
    assert.equal(button.disabled, false);
});

function fixture(t) {
    const dir = mkdtempSync('/tmp/hijpass-trace-test-');
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    const env = { ...process.env, PATH: `${dir}:${process.env.PATH}`, TRACE_TEST_LOG: path.join(dir, 'commands') };
    function script(name, body) {
        const file = path.join(dir, name);
        writeFileSync(file, '#!/bin/sh\n' + body + '\n');
        chmodSync(file, 0o755);
    }
    // 按真实安装结构运行 Shell 与数据模块；宿主机使用 OpenWrt 同款 ash。
    const runtime = path.join(dir, 'runtime');
    cpSync(path.join(root, 'root/usr/lib/hijpass'), runtime, { recursive: true });
    for (const folder of readdirSync(runtime, { withFileTypes: true })) {
        const files = folder.isDirectory() ? readdirSync(path.join(runtime, folder.name)).map(name => path.join(runtime, folder.name, name)) : [path.join(runtime, folder.name)];
        for (const file of files) if (file.endsWith('.sh') || file.endsWith('.uc'))
            writeFileSync(file, readFileSync(file, 'utf8')
                .replace('#!/bin/sh', '#!/usr/bin/busybox ash')
                .replaceAll('/usr/lib/hijpass', runtime)
                .replaceAll('/tmp/hijpass-trace-tasks', path.join(dir, 'tasks'))
                .replaceAll('/tmp/hijpass-jobs', path.join(dir, 'jobs')));
    }
    const capture = path.join(runtime, 'diagnostics/capture.sh');
    writeFileSync(capture, readFileSync(capture, 'utf8').replaceAll('sleep ', shellQuote(path.join(dir, 'sleep')) + ' ').replace('$(id -u)', '$(' + shellQuote(path.join(dir, 'id')) + ' -u)'));
    const common = path.join(runtime, 'common.sh');
    writeFileSync(common, readFileSync(common, 'utf8').replace('/usr/share/libubox/jshn.sh', process.env.JSHN_SH || '/usr/share/libubox/jshn.sh'));
    script('ucode', `exec ${shellQuote(interpreter)} -L ${shellQuote(path.join(root, 'root/usr/share/ucode'))} "$@"`);
    script('start-stop-daemon', 'exec /usr/bin/busybox start-stop-daemon \"$@\"');
    script('id', 'echo 0');
    script('uci', 'exit 0');
    script('nslookup', 'echo unexpected-nslookup >>"$TRACE_TEST_LOG"; exit 1');
    script('curl', 'echo curl >>"$TRACE_TEST_LOG"');
    script('logread', 'exec /bin/sleep 180');
    script('sleep', 'case "$1" in ""|*[!0-9]*) echo "sleep: invalid number" >&2; exit 1 ;; esac\n[ "$TRACE_REAL_SLEEP" = 1 ] && exec /bin/sleep "$@"; exec /bin/sleep 0.01');
    script('nft', `printf 'nft %s\\n' "$*" >>"$TRACE_TEST_LOG"
if [ "$1" = -f ]; then
    sed 's/"//g; s/^/nft /' "$2" >>"$TRACE_TEST_LOG"
fi
case "$*" in
    'monitor trace')
        trace_pid="$(sed -n 's/.*add chain inet hijpass trace-\\([0-9]*\\).*/\\1/p' "$TRACE_TEST_LOG" | tail -n 1)"
        printf 'trace id 123 inet hijpass trace-%s packet: ip saddr 192.168.1.100 ip daddr 8.8.8.8 udp sport 12345 udp dport 53\\n' \"$trace_pid\"
        if [ \"$TRACE_UNKNOWN_RULE\" = 1 ]; then
            printf 'trace id 123 inet hijpass trace-%s unknown rule handle 6 (verdict continue)\\n' \"$trace_pid\"
        else
            printf 'trace id 123 inet hijpass trace-%s rule meta nftrace set 1 comment \"hijpass-trace-%s\" (verdict continue)\\n' \"$trace_pid\" \"$trace_pid\"
        fi
        printf 'trace id 999 inet hijpass other packet: ip saddr 192.168.1.200 ip daddr 1.1.1.1\\n'
        exec /bin/sleep 180 ;;
    '-a list chain inet hijpass pre-filter')
        comment="$(sed -n 's/.*comment \\(hijpass-trace-[0-9]*\\).*/\\1/p' "$TRACE_TEST_LOG" | tail -n 1)"
        printf 'meta nftrace set 1 comment "%s" # handle 42\\n' "$comment" ;;
esac`);
    script('tcpdump', `printf 'tcpdump %s\\n' "$*" >>"$TRACE_TEST_LOG"
# Model libpcap buffering: no delivery during a short capture without immediate mode.
case " $* " in *' --immediate-mode '*)
printf '1.0 br-lan In IP 192.168.1.100.12345 > 8.8.8.8.53: UDP, length 20\\n'
;; esac
exec /bin/sleep 180`);
    return { dir, env, trace: path.join(runtime, 'diagnostics/capture.sh'), task: path.join(runtime, 'diagnostics/task.sh') };
}

test('router and client capture support integer-only sleep without diagnostic warnings', t => {
    const f = fixture(t);
    for (const args of [['-c', '192.168.1.100', '-t', '1'], ['-t', '1', 'https://example.com/']]) {
        const result = spawnSync(f.trace, args, { env: f.env, encoding: 'utf8' });
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stderr, '');
        assert.match(result.stdout, /Trace is active/);
    }
});

test('Shell capture with ucode parsing filters all/TCP/UDP and cleans its nft rule without DNS or curl', t => {
    const f = fixture(t);
    for (const [protocol, port, expr, filter] of [
        ['all', 'all', 'ip saddr 192.168.1.100 meta nftrace', 'host 192.168.1.100'],
        ['all', '53', 'meta l4proto { tcp, udp } th dport 53', '((src host 192.168.1.100 and dst port 53) or (dst host 192.168.1.100 and src port 53)) and (tcp or udp)'],
        ['tcp', '443', 'meta l4proto tcp th dport 443', '((src host 192.168.1.100 and dst port 443) or (dst host 192.168.1.100 and src port 443)) and tcp'],
        ['udp', 'all', 'meta l4proto udp meta nftrace', 'host 192.168.1.100 and udp'],
    ]) {
        writeFileSync(f.env.TRACE_TEST_LOG, '');
        const out = execFileSync(f.trace, ['-c', '192.168.1.100', '-t', '30', '-n', protocol, '-P', port, '-p'], { env: f.env, encoding: 'utf8' });
        const calls = readFileSync(f.env.TRACE_TEST_LOG, 'utf8');
        assert.ok(calls.includes(expr), calls);
        assert.ok(calls.includes(filter), calls);
        assert.match(calls, /delete chain inet hijpass trace-/);
        assert.doesNotMatch(calls, /unexpected-nslookup|curl/);
        assert.doesNotMatch(out, /request: HEAD|target:|other_same_port_packets:/);
        assert.match(out, /udp: packets=1/);
        assert.match(out, /trace=123 udp \[192\.168\.1\.100\]:12345 -> \[8\.8\.8\.8\]:53/);
        assert.match(out, /payload_packets=0/);
        assert.doesNotMatch(out, /192\.168\.1\.200/);
        assert.match(calls, /priority -301/);
    }
    f.env.TRACE_UNKNOWN_RULE = '1';
    const out = execFileSync(f.trace, ['-c', '2001:db8::123', '-t', '1'], { env: f.env, encoding: 'utf8' });
    assert.match(readFileSync(f.env.TRACE_TEST_LOG, 'utf8'), /ip6 saddr 2001:db8::123/);
    assert.match(out, /client=2001:db8::123/);
    assert.match(out, /client_flows_total: 1/);
    assert.throws(() => execFileSync(f.trace, ['-c', '::1;flush ruleset', '-t', '1'], { env: f.env, stdio: 'pipe' }));
});

test('capture preserves files only with -K while always removing temporary nft rules', t => {
    const f = fixture(t);
    for (const keep of [false, true]) {
        writeFileSync(f.env.TRACE_TEST_LOG, '');
        const output = execFileSync(f.trace, ['-c', '192.168.1.100', '-t', '1', ...(keep ? ['-K'] : [])],
            { env: f.env, encoding: 'utf8' });
        const calls = readFileSync(f.env.TRACE_TEST_LOG, 'utf8');
        const pid = calls.match(/add chain inet hijpass trace-(\d+)/)[1];
        const directory = '/tmp/hijpass-trace.' + pid;
        t.after(() => rmSync(directory, { recursive: true, force: true }));
        assert.match(calls, /delete chain inet hijpass trace-/);
        assert.match(calls, /delete rule inet hijpass pre-filter handle 42/);
        assert.equal(existsSync(directory), keep);
        assert.equal(output.includes('Temporary files kept:'), keep);
    }
});

test('detached worker returns immediately, reports a real 30s capture, and cleans up', { timeout: 45000 }, async t => {
    const f = fixture(t);
    f.env.TRACE_REAL_SLEEP = '1';
    const startTime = Date.now();
    // Emulate an inherited duplicate RPC pipe, as encountered with BusyBox ash.
    const id = execFileSync('/bin/sh', ['-c', 'exec 3>&1; exec "$@"', 'test', f.task,
        'start', '-c', '192.168.1.100', '-t', '30'], { env: f.env, encoding: 'utf8', timeout: 3000 }).trim();
    assert.match(id, /^[A-Za-z0-9]{8}$/);
    const taskDir = `${f.dir}/tasks/${id}`;
    t.after(() => rmSync(taskDir, { recursive: true, force: true }));
    assert.ok(Date.now() - startTime < 3000);
    let result;
    let sawActive = false;
    do {
        result = JSON.parse(execFileSync(f.task, ['status', id], { env: f.env, encoding: 'utf8', timeout: 3000 }));
        sawActive ||= result.stdout.includes('Trace is active');
        if (result.running) await new Promise(resolve => setTimeout(resolve, 500));
    } while (result.running);
    assert.ok(sawActive);
    assert.ok(Date.now() - startTime >= 30000);
    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /duration=30s/);
    assert.match(readFileSync(f.env.TRACE_TEST_LOG, 'utf8'), /delete chain inet hijpass trace-/);
    execFileSync(f.task, ['release', id], { env: f.env });
    assert.equal(existsSync(taskDir), false);
});

test('failed background capture exposes its exit status and task IDs reject traversal', async t => {
    const f = fixture(t);
    const id = execFileSync(f.task, ['start', '-c', '192.168.1.100', '-t', '121'], { env: f.env, encoding: 'utf8' }).trim();
    let result;
    do {
        result = JSON.parse(execFileSync(f.task, ['status', id], { env: f.env, encoding: 'utf8' }));
        if (result.running) await new Promise(resolve => setTimeout(resolve, 20));
    } while (result.running);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /timeout must be <= 120/);
    execFileSync(f.task, ['release', id], { env: f.env });
    assert.throws(() => execFileSync(f.task, ['status', '../../etc'], { env: f.env, stdio: 'pipe' }));
});

test('startup cleanup stops active diagnostics, removes retained captures and preserves update locks', { timeout: 15000 }, async t => {
    const f = fixture(t);
    // Limit cleanup to captures created by this test, never other host captures.
    const captures = path.join(f.dir, 'captures');
    writeFileSync(captures, '');
    writeFileSync(f.task, readFileSync(f.task, 'utf8').replace('/tmp/hijpass-trace.[0-9]*', `$(cat '${captures}')`));
    const run = (...args) => execFileSync(f.task, args, { env: f.env, encoding: 'utf8', timeout: 8000 });
    execFileSync(f.trace, ['-c', '192.168.1.100', '-t', '1', '-K'], { env: f.env });
    const keptPid = readFileSync(f.env.TRACE_TEST_LOG, 'utf8').match(/add chain inet hijpass trace-(\d+)/)[1];
    const kept = '/tmp/hijpass-trace.' + keptPid;
    writeFileSync(captures, kept + '\n');
    t.after(() => rmSync(kept, { recursive: true, force: true }));
    f.env.TRACE_REAL_SLEEP = '1';

    const jobs = path.join(f.dir, 'jobs');
    mkdirSync(jobs);
    const updater = spawn('/bin/sh', ['-c', 'exec 9>"$1/updates.lock"; flock -x 9; echo running >"$1/state"; exec sleep 120', 'test', jobs]);
    t.after(() => updater.kill());
    const deadline = Date.now() + 3000;
    while (!existsSync(jobs + '/state') && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 20));
    assert.equal(readFileSync(jobs + '/state', 'utf8'), 'running\n');
    const lockInode = statSync(jobs + '/updates.lock').ino;

    try {
        const id = run('start', '-c', '192.168.1.100', '-t', '120', '-p').trim();
        let status;
        const readyDeadline = Date.now() + 4000;
        do {
            status = JSON.parse(run('status', id));
            if (status.stdout.includes('Trace is active')) break;
            await new Promise(resolve => setTimeout(resolve, 50));
        } while (Date.now() < readyDeadline);
        assert.match(status.stdout, /Trace is active/);
        const workerPid = readFileSync(`${f.dir}/tasks/${id}/pid`, 'utf8').trim();
        const activePid = [...readFileSync(f.env.TRACE_TEST_LOG, 'utf8').matchAll(/add chain inet hijpass trace-(\d+)/g)].at(-1)[1];
        const active = '/tmp/hijpass-trace.' + activePid;
        writeFileSync(captures, kept + '\n' + active + '\n');
        const children = readFileSync(`/proc/${activePid}/task/${activePid}/children`, 'utf8').trim().split(/\s+/);
        const stale = `${f.dir}/tasks/Stale123`;
        mkdirSync(stale);
        // Reused PID points to an unrelated live process: it must not be killed.
        writeFileSync(stale + '/pid', String(updater.pid));
        writeFileSync(stale + '/stdout', 'old result');
        const registryInode = statSync(f.dir + '/tasks/registry.lock').ino;

        run('clear');
        assert.deepEqual(readdirSync(f.dir + '/tasks'), ['registry.lock']);
        assert.equal(statSync(f.dir + '/tasks/registry.lock').ino, registryInode);
        for (const directory of [kept, active]) assert.equal(existsSync(directory), false, directory);
        for (const pid of [workerPid, activePid, ...children]) {
            const cmdline = `/proc/${pid}/cmdline`;
            assert.ok(!existsSync(cmdline) || readFileSync(cmdline).length === 0, `diagnostic process ${pid} is still alive`);
        }
        assert.match(readFileSync(f.env.TRACE_TEST_LOG, 'utf8'), /delete rule inet hijpass pre-filter handle 42/);
        assert.equal(readFileSync(jobs + '/state', 'utf8'), 'running\n');
        assert.equal(statSync(jobs + '/updates.lock').ino, lockInode);
        assert.equal(spawnSync('flock', ['-n', jobs + '/updates.lock', 'true']).status, 1);
        assert.doesNotThrow(() => process.kill(updater.pid, 0));
        // Clearing again is safe; a subsequent diagnostic can still be registered.
        for (let attempt = 0; attempt < 3; attempt++) {
            assert.match(run('start', '-c', '192.168.1.100', '-t', '121').trim(), /^[A-Za-z0-9]{8}$/);
            run('clear');
            assert.deepEqual(readdirSync(f.dir + '/tasks'), ['registry.lock']);
        }
    } finally {
        run('clear');
    }
});

for (const capability of [true, false, 'error']) {
    test(`diagnostics only offers tcpdump when dependency detection succeeds: ${capability}`, async () => {
        const options = new Map();
        let submitted;
        const section = {
            tab() {},
            taboption(tab, type, name) {
                const option = { value() {}, depends() {}, formvalue() { return this.default; } };
                options.set(name, option);
                return option;
            },
        };
        const context = vm.createContext({ exports: {}, _: value => value, URLSearchParams,
            window: { location: { search: '?tab=trace' } },
            require(name) {
                if (name === 'view') return { extend: value => value };
                if (name === 'uci') return { load: async () => {} };
                if (name === 'form') return { Map: class {
                    section() { return section; }
                    render() { options.get('_trace_output').render(); }
                } };
                if (name.endsWith('/enum/hijpass')) return { LuciFlied: {} };
                if (name.endsWith('/backend')) return { Backend: { async traceCapabilities() {
                    if (capability === 'error') throw new Error('RPC unavailable');
                    return { tcpdump: capability };
                } } };
                if (name.endsWith('/log/panel')) return { LogPanelUtils: {
                    createTraceOutputPanel: () => ({ statusElement: {}, outputElement: {}, node: {} }),
                    runTraceDiagnostics: values => { submitted = values; },
                } };
                return {};
            },
        });
        vm.runInContext(ts.transpileModule(readFileSync(path.join(root, 'ts-src/views/log.ts'), 'utf8'), {
            compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true },
        }).outputText, context);
        const view = context.exports.default;
        view.render(await view.load());
        assert.equal(options.has('_trace_tcpdump'), capability === true);
        assert.equal(options.has('_trace_tcpdump_iface'), capability === true);
        if (capability === true) options.get('_trace_tcpdump').default = '1';
        options.get('_trace_run').onclick({ currentTarget: {} }, 'global');
        assert.equal(submitted.tcpdump, capability === true);
        assert.equal(submitted.tcpdumpInterface, 'any');
    });
}
