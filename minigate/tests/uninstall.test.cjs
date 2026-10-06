const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const script = path.join(root, 'root/usr/lib/minigate/uninstall.sh');

function write(base, relative, content = relative) {
    const target = path.join(base, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, content);
    return target;
}

function fixture() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-uninstall-test-'));
    write(dir, 'etc/config/minigate', 'config-data');
    write(dir, 'etc/minigate/certs/site.pem', 'certificate-data');
    write(dir, 'etc/minigate/login-guard/bans.txt', '198.51.100.4 9999999999');
    write(dir, 'etc/crontabs/root', '0 1 * * * /bin/other\n*/5 * * * * /bin/sh /usr/lib/minigate/ddns.sh\n');
    write(dir, 'etc/init.d/minigate');
    write(dir, 'usr/lib/minigate/update.sh');
    write(dir, 'usr/lib/minigate/uninstall.sh');
    write(dir, 'usr/lib/lua/luci/controller/minigate.lua');
    write(dir, 'usr/lib/lua/luci/model/cbi/minigate/general.lua');
    write(dir, 'usr/lib/lua/luci/view/minigate/log.htm');
    write(dir, 'usr/lib/lua/luci/i18n/minigate.zh-cn.lmo');
    write(dir, 'usr/lib/lua/luci/controller/keep.lua');
    write(dir, 'var/log/minigate-access.log', 'access-log');
    write(dir, 'var/run/minigate/socket');
    write(dir, 'var/run/minigate-nginx.pid', '123');
    write(dir, 'tmp/minigate-update-state.json', '{}');
    write(dir, 'tmp/minigate_proxy_443.tmp');
    write(dir, 'tmp/luci-indexcache');
    return dir;
}

function run(dir, purge) {
    return spawnSync('/bin/sh', [script, purge], {
        encoding: 'utf8',
        env: {
            ...process.env,
            MINIGATE_ROOT: dir,
            MINIGATE_SKIP_PACKAGES: '1',
            MINIGATE_SKIP_SERVICES: '1'
        }
    });
}

test('default uninstall removes the app but preserves configuration, certificates, bans and logs', () => {
    const dir = fixture();
    const result = run(dir, '0');
    assert.equal(result.status, 0, result.stderr);

    for (const relative of [
        'etc/init.d/minigate',
        'usr/lib/minigate',
        'usr/lib/lua/luci/controller/minigate.lua',
        'usr/lib/lua/luci/model/cbi/minigate',
        'usr/lib/lua/luci/view/minigate',
        'usr/lib/lua/luci/i18n/minigate.zh-cn.lmo',
        'var/run/minigate',
        'var/run/minigate-nginx.pid',
        'tmp/minigate-update-state.json',
        'tmp/minigate_proxy_443.tmp',
        'tmp/luci-indexcache'
    ]) assert.equal(fs.existsSync(path.join(dir, relative)), false, relative);

    assert.equal(fs.readFileSync(path.join(dir, 'etc/config/minigate'), 'utf8'), 'config-data');
    assert.equal(fs.readFileSync(path.join(dir, 'etc/minigate/certs/site.pem'), 'utf8'), 'certificate-data');
    assert.equal(fs.readFileSync(path.join(dir, 'etc/minigate/login-guard/bans.txt'), 'utf8'), '198.51.100.4 9999999999');
    assert.equal(fs.readFileSync(path.join(dir, 'var/log/minigate-access.log'), 'utf8'), 'access-log');
    assert.equal(fs.readFileSync(path.join(dir, 'etc/crontabs/root'), 'utf8'), '0 1 * * * /bin/other\n');
    assert.equal(fs.existsSync(path.join(dir, 'usr/lib/lua/luci/controller/keep.lua')), true);
});

test('purge uninstall also removes configuration, certificates, bans and logs', () => {
    const dir = fixture();
    const result = run(dir, '1');
    assert.equal(result.status, 0, result.stderr);
    for (const relative of ['etc/config/minigate', 'etc/minigate', 'var/log/minigate-access.log', 'usr/lib/minigate']) {
        assert.equal(fs.existsSync(path.join(dir, relative)), false, relative);
    }
    assert.equal(fs.existsSync(path.join(dir, 'usr/lib/lua/luci/controller/keep.lua')), true);
});

test('invalid purge mode is rejected before files are changed', () => {
    const dir = fixture();
    const result = run(dir, 'yes');
    assert.equal(result.status, 2);
    assert.equal(fs.existsSync(path.join(dir, 'usr/lib/minigate/update.sh')), true);
    assert.equal(fs.existsSync(path.join(dir, 'etc/config/minigate')), true);
});

test('LuCI exposes only a confirmed POST uninstall action and runs a temporary script copy', () => {
    const controller = fs.readFileSync(path.join(root, 'luasrc/controller/minigate.lua'), 'utf8');
    assert.match(controller, /\{"admin","services","minigate","uninstall"\}, post\("action_uninstall"\)/);
    assert.match(controller, /confirm ~= "uninstall-minigate"/);
    assert.match(controller, /purge ~= "0" and purge ~= "1"/);
    assert.match(controller, /mktemp \/tmp\/minigate-uninstall\.XXXXXX/);
    assert.match(controller, /sleep 1; \/bin\/sh/);
});

test('the package contains the uninstaller and supports both OpenWrt package managers', () => {
    const makefile = fs.readFileSync(path.join(root, 'Makefile'), 'utf8');
    const source = fs.readFileSync(script, 'utf8');
    assert.match(makefile, /root\/usr\/lib\/minigate\/uninstall\.sh/);
    assert.match(source, /opkg remove "\$package"/);
    assert.match(source, /apk del "\$package"/);
    assert.match(source, /for package in minigate luci-app-minigate/);
});
