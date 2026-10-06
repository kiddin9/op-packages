const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const installerPath = path.join(root, 'scripts/install.sh');
const source = fs.readFileSync(installerPath, 'utf8');
const sourceInstaller = fs.readFileSync(path.join(root, 'install.sh'), 'utf8');
const sourceDependencyFunctions = sourceInstaller.slice(
    sourceInstaller.indexOf('dependency_ready()'),
    sourceInstaller.indexOf('\n# 检测包管理器')
);
const functions = source.slice(source.indexOf('info()'), source.lastIndexOf('\nmain "$@"'));
const program = source.slice(0, source.lastIndexOf('\nmain "$@"'));
const currentVersion = fs.readFileSync(path.join(root, 'Makefile'), 'utf8').match(/^PKG_VERSION:=(.+)$/m)[1];

function shell(body, env = {}) {
    return spawnSync('/bin/sh', ['-c', body], {
        encoding: 'utf8',
        env: { ...process.env, ...env }
    });
}

test('online installer is valid POSIX shell and uses the fixed repository', () => {
    const result = spawnSync('/bin/sh', ['-n', installerPath], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.match(source, /^REPOSITORY="tpxcer\/minigate"$/m);
    assert.match(source, /releases\/latest\/download/);
});

test('source installer skips package installation when a working OpenSSL CLI already exists', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-source-deps-'));
    const calls = path.join(tempDir, 'apk-calls');
    const openssl = path.join(tempDir, 'openssl');
    const apk = path.join(tempDir, 'apk');
    fs.writeFileSync(openssl, '#!/bin/sh\n[ "$1" = version ]\n', { mode: 0o755 });
    fs.writeFileSync(apk, `#!/bin/sh\nprintf '%s\\n' "$*" >> ${JSON.stringify(calls)}\n[ "$1" = info ] && [ "$3" != openssl-util ]\n`, { mode: 0o755 });

    const result = shell(`${sourceDependencyFunctions}\ninstall_dependencies`, { PATH: tempDir });
    assert.equal(result.status, 0, result.stderr);
    const log = fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8') : '';
    assert.doesNotMatch(log, /openssl-util/);
});

test('source installer installs openssl-util when OpenSSL CLI is unavailable', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-source-deps-'));
    const calls = path.join(tempDir, 'apk-calls');
    const apk = path.join(tempDir, 'apk');
    fs.writeFileSync(apk, `#!/bin/sh\nprintf '%s\\n' "$*" >> ${JSON.stringify(calls)}\nif [ "$1" = info ]; then [ "$3" != openssl-util ]; else exit 0; fi\n`, { mode: 0o755 });

    const result = shell(`${sourceDependencyFunctions}\ninstall_dependencies`, { PATH: tempDir });
    assert.equal(result.status, 0, result.stderr);
    assert.match(fs.readFileSync(calls, 'utf8'), /add openssl-util/);
});

test('release manifest selects one valid minigate source asset', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-install-test-'));
    const sumsPath = path.join(tempDir, 'SHA256SUMS');
    const hash = 'a'.repeat(64);
    fs.writeFileSync(sumsPath, [
        `${'b'.repeat(64)}  minigate_2026.9.14-3_all.ipk`,
        `${hash}  minigate-v2026.9.14-3-src.tar.gz`,
        `${hash}  luci-app-minigate-v2026.9.14-3-src.tar.gz`
    ].join('\n'));

    const result = shell(`${functions}\nread_release "$SUMS" && printf '%s|%s|%s' "$RELEASE_VERSION" "$SOURCE_NAME" "$EXPECTED_HASH"`, { SUMS: sumsPath });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, `2026.9.14-3|minigate-v2026.9.14-3-src.tar.gz|${hash}`);
});

test('release manifest rejects duplicate or malformed source entries', () => {
    for (const entries of [
        [`${'a'.repeat(64)}  minigate-v2026.9.14-3-src.tar.gz`, `${'b'.repeat(64)}  minigate-v2026.9.14-4-src.tar.gz`],
        [`${'a'.repeat(64)}  minigate-v2026.9.14-0-src.tar.gz`],
        [`not-a-hash  minigate-v2026.9.14-3-src.tar.gz`]
    ]) {
        const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-install-test-'));
        const sumsPath = path.join(tempDir, 'SHA256SUMS');
        fs.writeFileSync(sumsPath, entries.join('\n'));
        const result = shell(`${functions}\nread_release "$SUMS"`, { SUMS: sumsPath });
        assert.notEqual(result.status, 0, entries.join(','));
    }
});

test('source metadata must match the selected release version', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-install-test-'));
    fs.mkdirSync(path.join(tempDir, 'scripts'), { recursive: true });
    fs.mkdirSync(path.join(tempDir, 'root/usr/lib/minigate'), { recursive: true });
    fs.writeFileSync(path.join(tempDir, 'Makefile'), 'PKG_VERSION:=2026.9.14-3\n');
    fs.writeFileSync(path.join(tempDir, 'scripts/build-ipk.sh'), 'PKG_VERSION="2026.9.14-3"\n');
    fs.writeFileSync(path.join(tempDir, 'root/usr/lib/minigate/update.sh'), 'CURRENT_VERSION="2026.9.14-3"\n');
    fs.writeFileSync(path.join(tempDir, 'install.sh'), '#!/bin/sh\n');

    const valid = shell(`${functions}\nRELEASE_VERSION=2026.9.14-3; verify_metadata "$SOURCE_DIR"`, { SOURCE_DIR: tempDir });
    assert.equal(valid.status, 0, valid.stderr);
    const invalid = shell(`${functions}\nRELEASE_VERSION=2026.9.14-4; verify_metadata "$SOURCE_DIR"`, { SOURCE_DIR: tempDir });
    assert.notEqual(invalid.status, 0);
});

test('online installer verifies and installs a mocked latest release end to end', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-install-test-'));
    const sourceDir = path.join(tempDir, 'source');
    const archivePath = path.join(tempDir, `minigate-v${currentVersion}-src.tar.gz`);
    const sumsPath = path.join(tempDir, 'SHA256SUMS');
    const markerPath = path.join(tempDir, 'installed');
    fs.mkdirSync(path.join(sourceDir, 'scripts'), { recursive: true });
    fs.mkdirSync(path.join(sourceDir, 'root/usr/lib/minigate'), { recursive: true });
    fs.writeFileSync(path.join(sourceDir, 'Makefile'), `PKG_VERSION:=${currentVersion}\n`);
    fs.writeFileSync(path.join(sourceDir, 'scripts/build-ipk.sh'), `PKG_VERSION="${currentVersion}"\n`);
    fs.writeFileSync(path.join(sourceDir, 'root/usr/lib/minigate/update.sh'), `CURRENT_VERSION="${currentVersion}"\n`);
    fs.writeFileSync(path.join(sourceDir, 'install.sh'), '#!/bin/sh\nprintf installed > "$INSTALL_MARKER"\n');
    const tar = spawnSync('tar', ['-czf', archivePath, '-C', sourceDir, '.'], { encoding: 'utf8' });
    assert.equal(tar.status, 0, tar.stderr);
    const digest = spawnSync('shasum', ['-a', '256', archivePath], { encoding: 'utf8' }).stdout.split(/\s+/)[0];
    fs.writeFileSync(sumsPath, `${digest}  ${path.basename(archivePath)}\n`);

    const result = shell(`${program}
        check_system() { :; }
        detect_downloader() { DOWNLOADER=test; }
        fetch_to_file() {
            case "$1" in
                */SHA256SUMS) cp "$TEST_SUMS" "$2" ;;
                */minigate-v*-src.tar.gz) cp "$TEST_ARCHIVE" "$2" ;;
                *) return 1 ;;
            esac
        }
        restart_luci() { printf restarted >> "$INSTALL_MARKER"; }
        main
    `, { TEST_SUMS: sumsPath, TEST_ARCHIVE: archivePath, INSTALL_MARKER: markerPath });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(markerPath, 'utf8'), 'installedrestarted');
    assert.match(result.stdout, new RegExp(`minigate v${currentVersion.replaceAll('.', '\\.')} 安装完成`));
});

test('online installer stops before installation when SHA-256 does not match', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-install-test-'));
    const archivePath = path.join(tempDir, 'source.tar.gz');
    fs.writeFileSync(archivePath, 'not an archive');
    const result = shell(`${functions}\nEXPECTED_HASH=${'0'.repeat(64)}; verify_source "$ARCHIVE"`, { ARCHIVE: archivePath });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /SHA-256/);
});

test('README exposes the short command and keeps a fixed-version fallback', () => {
    const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
    assert.match(readme, /curl -fsSL https:\/\/raw\.githubusercontent\.com\/tpxcer\/minigate\/main\/scripts\/install\.sh \| sh/);
    assert.ok(readme.includes(`releases/download/v${currentVersion}/minigate-v${currentVersion}-src.tar.gz`));
});
