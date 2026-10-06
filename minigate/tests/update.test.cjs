const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'root/usr/lib/minigate/update.sh'), 'utf8');
const functions = source.slice(source.indexOf('json_escape()'), source.lastIndexOf('\ncase "${1:-status}"'));
const version = source.match(/^CURRENT_VERSION="([^"]+)"/m)[1];
const quote = value => "'" + value.replaceAll("'", "'\"'\"'") + "'";

function shell(body, env = {}) {
    const result = spawnSync('/bin/sh', ['-c', body], { encoding: 'utf8', env: { ...process.env, ...env } });
    assert.equal(result.error, undefined);
    return result;
}

function backend(body, options = {}) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-test-'));
    const fixture = { tag_name: `v${options.latest || version}`, name: 'minigate', body: 'Update notes' };
    fs.writeFileSync(path.join(dir, 'fixture.json'), JSON.stringify(fixture));
    fs.writeFileSync(path.join(dir, 'jsonfilter.cjs'), `
        const fs = require('node:fs');
        const args = process.argv.slice(2);
        try {
            const value = JSON.parse(fs.readFileSync(args[args.indexOf('-i')+1], 'utf8'));
            const result = value[args[args.indexOf('-e')+1].slice(2)];
            if (result !== undefined) console.log(result);
        } catch (_) { process.exitCode = 1; }
    `);
    const result = shell(`
        CURRENT_VERSION=${quote(version)}
        STATE_CURRENT="$CURRENT_VERSION"
        STATE_FILE="$TEST_DIR/state.json"
        RELEASE_FILE="$TEST_DIR/release.json"
        LAST_CHECK_FILE="$TEST_DIR/last-check"
        LOCK_FILE="$TEST_DIR/lock"
        TMP_ROOT="$TEST_DIR/work"
        RUN_LOG="$TEST_DIR/log"
        API_URL=https://example.invalid/latest
        ${functions}
        jsonfilter() { "$NODE" "$TEST_DIR/jsonfilter.cjs" "$@"; }
        flock() {
            printf '%s\n' "$*" >> "$TEST_DIR/flocks"
            [ "$1" = "-u" ] && return 0
            test "\${FLOCK_BUSY:-0}" = 0
        }
        download_file() {
            printf 'fetch\\n' >> "$TEST_DIR/fetches"
            test "\${FETCH_FAIL:-0}" = 0 || return 1
            cp "$TEST_DIR/fixture.json" "$2"
        }
        backup_program() { echo 'UNEXPECTED INSTALL' >&2; exit 99; }
        ${body}
    `, { TEST_DIR: dir, NODE: process.execPath, ...options.env });
    return {
        ...result,
        state: fs.existsSync(path.join(dir, 'state.json')) ? JSON.parse(fs.readFileSync(path.join(dir, 'state.json'))) : null,
        fetches: fs.existsSync(path.join(dir, 'fetches')) ? fs.readFileSync(path.join(dir, 'fetches'), 'utf8').trim().split('\n').length : 0,
        flocks: fs.existsSync(path.join(dir, 'flocks')) ? fs.readFileSync(path.join(dir, 'flocks'), 'utf8').trim().split('\n') : []
    };
}

test('date versions compare numeric day and same-day sequence, including legacy version', () => {
    for (const [left, right, newer] of [
        ['2026.9.14', '1.3.11', true], ['2026.9.14', '2026.9.14', false],
        ['2026.9.14-1', '2026.9.14', true], ['2026.9.14-10', '2026.9.14-2', true],
        ['2026.9.14-2', '2026.9.14-10', false], ['2026.9.15', '2026.9.14-99', true],
        ['2026.10.1', '2026.9.30-9', true], ['2027.1.1', '2026.12.31', true],
        ['1.3.11', '2026.9.14', false]
    ]) {
        assert.equal(shell(`${functions}\nversion_newer ${quote(left)} ${quote(right)}`).status, newer ? 0 : 1, `${left} > ${right}`);
    }
});

test('reject malformed versions and shell syntax in tags', () => {
    for (const value of ['2026.9.14', '2026.9.14-1', '2026.9.14-10']) {
        assert.equal(shell(`${functions}\nvalid_version ${quote(value)}`).status, 0, value);
    }
    for (const value of ['', 'latest', '1.3.11', '2026.13.14', '2026.9.0', '2026.9.14-0', '2026.9.14-01', '2026.9.14;id', '../2026.9.14']) {
        assert.equal(shell(`${functions}\nvalid_version ${quote(value)}`).status, 1, value);
    }
});

test('opening overview checks once then reuses a successful ten-minute cache', () => {
    const result = backend('run_auto_check >/dev/null; run_auto_check');
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.fetches, 1);
    assert.equal(result.state.status, 'up_to_date');
});

test('manual check, expired cache and changed installed version force a fresh check', () => {
    for (const next of ['run_check', 'echo 1 > "$LAST_CHECK_FILE"; run_auto_check', 'CURRENT_VERSION=2020.1.1; STATE_CURRENT=$CURRENT_VERSION; run_auto_check']) {
        const result = backend(`run_check >/dev/null; ${next}`);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.fetches, 2);
    }
});

test('success/error/running state is not reused as a successful check cache', () => {
    for (const state of ['success', 'error', 'installing']) {
        const result = backend(`run_check >/dev/null; write_state ${state} 100 "$CURRENT_VERSION" false false true done; run_auto_check`);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.state.status, 'up_to_date');
        assert.equal(result.fetches, 2);
    }
});

test('busy updater is reported without downloading or starting another update', () => {
    const result = backend('write_state installing 75 "2027.1.1" true true true busy; FLOCK_BUSY=1; run_auto_check');
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.state.status, 'installing');
    assert.equal(result.fetches, 0);
});

test('apply releases its lock even when the locked operation returns early', () => {
    const result = backend('run_apply_locked() { return 7; }; run_apply "$CURRENT_VERSION"');
    assert.equal(result.status, 7, result.stderr);
    assert.deepEqual(result.flocks, ['-n 9', '-u 9']);
});

test('long-running services are started with the update lock descriptor closed', () => {
    const installer = fs.readFileSync(path.join(root, 'install.sh'), 'utf8');
    assert.match(installer, /\/etc\/init\.d\/minigate start 9>&-/);
    assert.match(source, /\/etc\/init\.d\/minigate start >> "\$RUN_LOG" 2>&1 9>&-/);
    assert.equal((source.match(/\/etc\/init\.d\/uhttpd restart >> "\$RUN_LOG" 2>&1 9>&-/g) || []).length, 2);
});

test('network failure is recoverable and never starts installation', () => {
    const result = backend('run_auto_check', { env: { FETCH_FAIL: '1' } });
    assert.equal(result.status, 1);
    assert.equal(result.state.status, 'error');
    assert.equal(result.state.running, false);
});

test('install requires an explicitly confirmed version and rejects a changed release', () => {
    const missing = backend('run_apply ""');
    assert.equal(missing.status, 1);
    assert.equal(missing.fetches, 0);
    const changed = backend('run_apply "2027.1.1"', { latest: '2027.1.2' });
    assert.equal(changed.status, 1);
    assert.equal(changed.state.latest, '2027.1.2');
    assert.equal(changed.state.available, true);
    assert.equal(changed.state.running, false);
    assert.match(changed.state.message, /重新/);
});

function overview() {
    const lua = fs.readFileSync(path.join(root, 'luasrc/model/cbi/minigate/general.lua'), 'utf8');
    const js = lua.slice(lua.indexOf('var _updatePolling'), lua.indexOf('var limitSel')).replace(/\]\] \.\. (\w+) \.\. \[\[/g, '$1');
    const elements = new Map();
    const element = id => {
        if (!elements.has(id)) elements.set(id, { style: {}, className: '', textContent: '', disabled: false, checked: false, hidden: false, setAttribute() {}, focus() { document.activeElement = this; } });
        return elements.get(id);
    };
    const listeners = {};
    const document = {
        body: { style: { overflow: 'auto' } }, activeElement: null,
        getElementById: element, querySelector: () => null, addEventListener: (name, handler) => { listeners[name] = handler; }
    };
    const buttons = ['close', 'mg-update-modal-notes', 'cancel', 'mg-update-confirm'].map(element);
    const uninstallItems = ['mg-uninstall-close', 'mg-uninstall-purge', 'mg-uninstall-cancel', 'mg-uninstall-confirm'].map(element);
    element('mg-update-modal').querySelectorAll = () => buttons;
    element('mg-update-modal').contains = item => buttons.includes(item);
    element('mg-uninstall-modal').querySelectorAll = () => uninstallItems;
    element('mg-uninstall-modal').contains = item => uninstallItems.includes(item);
    const requests = [], timers = [];
    const context = vm.createContext({ document, mgColor: value => value, location: { reload() {} }, setTimeout: callback => timers.push(callback), XHR: {
        get: (url, data, callback) => requests.push({ method: 'GET', url, data, callback }),
        post: (url, data, callback) => requests.push({ method: 'POST', url, data, callback })
    } });
    vm.runInContext(js, context);
    const available = { status: 'available', current: version, latest: '2027.1.1', available: true, success: true, release_title: 'New release', release_notes: '<script>bad()</script>\n中文说明' };
    return { context, document, element, requests, timers, available, buttons, uninstallItems, listeners };
}

test('overview automatically checks but does not install', () => {
    const page = overview();
    const lua = fs.readFileSync(path.join(root, 'luasrc/model/cbi/minigate/general.lua'), 'utf8');
    assert.match(lua, /mgAutoCheckUpdate\(\);\s*<\/script>/);
    page.context.mgAutoCheckUpdate();
    assert.equal(page.requests.length, 1);
    assert.equal(page.requests[0].method, 'GET');
    assert.equal(page.requests[0].url, 'xu');
    page.requests[0].callback(null, page.available);
    page.context.mgApplyUpdate();
    assert.equal(page.requests.length, 1);
    assert.equal(page.element('mg-update-modal-notes').textContent, page.available.release_notes);
    page.context.mgCloseUpdateDialog();
    page.context.mgStartUpdate();
    assert.equal(page.requests.length, 1);
    assert.equal(page.document.body.style.overflow, 'auto');
});

test('confirm installs exactly the shown version, ignores double clicks and preserves retry notes', () => {
    const page = overview();
    page.context.mgRenderUpdate(page.available);
    page.context.mgApplyUpdate();
    page.context.mgRenderUpdate({ ...page.available, latest: '2027.1.2' });
    page.context.mgStartUpdate();
    page.context.mgStartUpdate();
    assert.equal(page.requests.length, 1);
    assert.equal(page.requests[0].method, 'POST');
    assert.equal(page.requests[0].data.version, '2027.1.1');
    page.requests[0].callback(null, { success: false, message: 'Retry' });
    page.context.mgApplyUpdate();
    assert.equal(page.element('mg-update-modal-notes').textContent, page.available.release_notes);
});

test('dialog traps keyboard focus and Escape cancels without installation', () => {
    const page = overview();
    page.context.mgRenderUpdate(page.available);
    page.context.mgApplyUpdate();
    page.buttons.at(-1).focus();
    page.listeners.keydown({ key: 'Tab', preventDefault() {} });
    assert.equal(page.document.activeElement, page.buttons[0]);
    page.listeners.keydown({ key: 'Tab', shiftKey: true, preventDefault() {} });
    assert.equal(page.document.activeElement, page.buttons.at(-1));
    page.listeners.keydown({ key: 'Escape', preventDefault() {} });
    assert.equal(page.element('mg-update-modal').className, 'mg-modal');
    assert.equal(page.requests.length, 0);
});

test('uninstall defaults to preserving data and cancel, Escape and backdrop never submit', () => {
    const page = overview();
    page.element('mg-uninstall-purge').checked = true;
    page.context.mgOpenUninstallDialog();
    assert.equal(page.element('mg-uninstall-purge').checked, false);
    assert.equal(page.element('mg-uninstall-modal').className, 'mg-modal is-open');
    assert.match(page.element('mg-uninstall-detail').textContent, /默认保留/);
    page.listeners.keydown({ key: 'Escape', preventDefault() {} });
    assert.equal(page.requests.length, 0);

    page.context.mgOpenUninstallDialog();
    page.element('mg-uninstall-modal').onclick({ target: page.element('mg-uninstall-modal') });
    assert.equal(page.requests.length, 0);
    page.context.mgOpenUninstallDialog();
    page.context.mgCloseUninstallDialog();
    assert.equal(page.requests.length, 0);
});

test('uninstall submits an explicit purge choice once and redirects only after acceptance', () => {
    const page = overview();
    page.context.mgOpenUninstallDialog();
    page.element('mg-uninstall-purge').checked = true;
    page.context.mgUpdateUninstallChoice();
    assert.equal(page.element('mg-uninstall-confirm').textContent, '彻底卸载');
    page.context.mgStartUninstall();
    page.context.mgStartUninstall();
    assert.equal(page.requests.length, 1);
    assert.equal(page.requests[0].method, 'POST');
    assert.equal(page.requests[0].url, 'du');
    assert.equal(page.requests[0].data.confirm, 'uninstall-minigate');
    assert.equal(page.requests[0].data.purge, '1');
    page.requests[0].callback(null, { success: true });
    assert.match(page.element('mg-uninstall-status').textContent, /返回服务页面/);
    assert.equal(page.timers.length, 1);
    page.timers[0]();
    assert.equal(page.context.location.href, 'services_url');
});

test('a rejected uninstall remains open and can be retried', () => {
    const page = overview();
    page.context.mgOpenUninstallDialog();
    page.context.mgStartUninstall();
    page.requests[0].callback(null, { success: false, message: 'busy' });
    assert.equal(page.element('mg-uninstall-modal').className, 'mg-modal is-open');
    assert.equal(page.element('mg-uninstall-confirm').disabled, false);
    assert.equal(page.element('mg-uninstall-status').textContent, 'busy');
    page.context.mgStartUninstall();
    assert.equal(page.requests.length, 2);
});

test('an old success state never reloads an overview that did not start the update', () => {
    const page = overview();
    page.context.mgRenderUpdate({ ...page.available, status: 'success', available: false });
    assert.equal(page.timers.length, 0);
});

test('build metadata has a consistent version and the actual minigate package identity', () => {
    const makefile = fs.readFileSync(path.join(root, 'Makefile'), 'utf8');
    const build = fs.readFileSync(path.join(root, 'scripts/build-ipk.sh'), 'utf8');
    assert.equal(makefile.match(/^PKG_VERSION:=(.+)$/m)[1], version);
    assert.equal(build.match(/^PKG_VERSION="(.+)"$/m)[1], version);
    assert.match(makefile, /^PKG_NAME:=minigate$/m);
    assert.match(build, /^PKG_NAME="minigate"$/m);
    assert.equal((build.match(/^Version:/gm) || []).length, 1);
    assert.ok(fs.existsSync(path.join(root, `releases/v${version}.md`)));
});
