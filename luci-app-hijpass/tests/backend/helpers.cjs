const path = require('node:path');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const root = path.resolve(__dirname, '../..');
const interpreter = process.env.UCODE || 'ucode';
let shellDirectory;

function shellRuntime() {
    if (shellDirectory) return shellDirectory;
    shellDirectory = fs.mkdtempSync('/tmp/hijpass-shell-runtime-');
    fs.cpSync(path.join(root, 'root/usr/lib/hijpass'), shellDirectory, { recursive: true });
    fs.copyFileSync(path.join(root, 'root/etc/hijpass/firewall.ut'), path.join(shellDirectory, 'firewall/default.ut'));
    for (const folder of fs.readdirSync(shellDirectory, { withFileTypes: true })) {
        const files = folder.isDirectory() ? fs.readdirSync(path.join(shellDirectory, folder.name)).map(name => path.join(shellDirectory, folder.name, name)) : [path.join(shellDirectory, folder.name)];
        // 在测试安装副本中映射固定路径，生产脚本无需支持可变安装目录。
        for (const file of files) if (file.endsWith('.sh') || file.endsWith('.uc'))
            fs.writeFileSync(file, fs.readFileSync(file, 'utf8')
                .replace('#!/bin/sh', '#!/usr/bin/busybox ash')
                .replaceAll('/usr/lib/hijpass', shellDirectory)
                .replaceAll('/tmp/hijpass-jobs', shellDirectory + '/jobs'));
    }
    fs.cpSync(path.join(root, 'root/usr/share/ucode'), path.join(shellDirectory, 'ucode'), { recursive: true });
    const common = path.join(shellDirectory, 'common.sh');
    fs.writeFileSync(common, fs.readFileSync(common, 'utf8').replace('/usr/share/libubox/jshn.sh',
        process.env.JSHN_SH || '/usr/share/libubox/jshn.sh'));
    const bin = path.join(shellDirectory, 'testbin');
    fs.mkdirSync(bin);
    const quote = text => "'" + text.replaceAll("'", "'\\''") + "'";
    fs.writeFileSync(path.join(bin, 'ucode'), '#!/bin/sh\nexec ' + quote(interpreter) +
        ' -L "${HIJPASS_TEST_LIBRARY:-' + shellDirectory + '/ucode}"' + ' "$@"\n', { mode: 0o755 });
    process.on('exit', () => fs.rmSync(shellDirectory, { recursive: true, force: true }));
    return shellDirectory;
}

function runShell(script, args = [], extra = {}) {
    const directory = shellRuntime();
    const { paths, ...options } = extra;
    const library = paths ? mappedLibrary(paths) : null;
    const env = { ...process.env, ...(options.env || {}) };
    if (library) env.HIJPASS_TEST_LIBRARY = library;
    env.PATH = path.join(directory, 'testbin') + ':' + env.PATH;
    const target = path.join(directory, script.replace('root/usr/lib/hijpass/', ''));
    // OpenWrt 的 /bin/sh 是 BusyBox ash；jshn 使用 ash 的 export -n。
    try { return spawnSync('/usr/bin/busybox', ['ash', target, ...args], { encoding: 'utf8', ...options, env }); }
    finally { if (library) fs.rmSync(library, { recursive: true, force: true }); }
}

// 将快照写成真实 UCI 文件，系统操作测试通过公开 Shell 入口读取它。
function withConfig(sections, callback) {
    const directory = fs.mkdtempSync('/tmp/hijpass-test-config-');
    const quote = text => "'" + String(text).replaceAll("'", "'\\''") + "'";
    let source = '';
    for (const section of sections) {
        source += 'config ' + section['.type'] + (section['.name'] ? ' ' + quote(section['.name']) : '') + '\n';
        for (const [key, value] of Object.entries(section)) {
            if (key.startsWith('.')) continue;
            if (Array.isArray(value)) for (const item of value) source += ` list ${key} ${quote(item)}\n`;
            else source += ` option ${key} ${quote(value)}\n`;
        }
    }
    fs.writeFileSync(path.join(directory, 'hijpass'), source);
    const cleanup = () => fs.rmSync(directory, { recursive: true, force: true });
    let result;
    try { result = callback(directory); }
    catch (error) { cleanup(); throw error; }
    if (result && typeof result.then === 'function') return result.finally(cleanup);
    cleanup();
    return result;
}

function mappedLibrary(paths) {
    const directory = fs.mkdtempSync('/tmp/hijpass-test-library-');
    fs.cpSync(path.join(shellRuntime(), 'ucode'), directory, { recursive: true });
    const file = path.join(directory, 'hijpass/config/paths.uc');
    let source = fs.readFileSync(file, 'utf8');
    for (const [before, after] of Object.entries(paths)) source = source.replaceAll(before, after);
    fs.writeFileSync(file, source);
    return directory;
}

function run(script, args = [], input, extra = {}) {
    if (script.endsWith('.sh')) return runShell(script, args, extra);
    if (script === 'tests/backend/runtime.uc') {
        const directory = shellRuntime();
        const driver = fs.readFileSync(path.join(root, script), 'utf8')
            .replaceAll('../../root/usr/lib/hijpass', directory)
            .replaceAll('../../root/', path.join(root, 'root') + '/');
        script = path.join(directory, 'runtime-test.uc');
        fs.writeFileSync(script, driver);
    }
    // Older ucode builds use getopt(), which can consume script flags such as --stdin on glibc hosts.
    const { paths, ...options } = extra;
    const library = paths ? mappedLibrary(paths) : path.join(shellRuntime(), 'ucode');
    try { return spawnSync(interpreter, ['-S', '-L', library, '--', path.resolve(root, script), ...args], {
        encoding: 'utf8', input: input === undefined ? undefined : JSON.stringify(input), ...options,
    }); } finally { if (paths) fs.rmSync(library, { recursive: true, force: true }); }
}
function config(args, input, extra) {
    return run('root/usr/bin/hijpass-config', args, input, extra);
}
module.exports = { root, interpreter, run, config, runShell, shellRuntime, withConfig };
