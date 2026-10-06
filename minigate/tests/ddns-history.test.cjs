const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const ddnsScript = path.join(root, 'root/usr/lib/minigate/ddns.sh');
const controller = fs.readFileSync(path.join(root, 'luasrc/controller/minigate.lua'), 'utf8');
const model = fs.readFileSync(path.join(root, 'luasrc/model/cbi/minigate/ddns.lua'), 'utf8');
const view = fs.readFileSync(path.join(root, 'luasrc/view/minigate/ddns_history.htm'), 'utf8');

function runHistory(script, options = {}) {
    const historyDir = fs.mkdtempSync(path.join(os.tmpdir(), 'minigate-ddns-history-'));
    const command = [
        'set -eu',
        'export MINIGATE_DDNS_LIBRARY_ONLY=1',
        `export MINIGATE_HISTORY_DIR=${JSON.stringify(historyDir)}`,
        `export MINIGATE_HISTORY_WINDOW=${options.window || 86400}`,
        `. ${JSON.stringify(ddnsScript)}`,
        script
    ].join('\n');
    const result = spawnSync('/bin/sh', ['-c', command], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    return { historyDir, output: result.stdout.trim() };
}

function readRows(file) {
    return fs.readFileSync(file, 'utf8').trim().split('\n').filter(Boolean);
}

test('DDNS history records only actual IPv4 changes', () => {
    const { historyDir, output } = runHistory(`
        export MINIGATE_HISTORY_NOW=100000
        record_ip_history cfg01 ipv4 198.51.100.10
        printf sentinel > "$MINIGATE_HISTORY_DIR/cfg01.ipv4.tsv.lock"
        export MINIGATE_HISTORY_NOW=100060
        record_ip_history cfg01 ipv4 198.51.100.10
        cat "$MINIGATE_HISTORY_DIR/cfg01.ipv4.tsv.lock"
        export MINIGATE_HISTORY_NOW=100120
        record_ip_history cfg01 ipv4 198.51.100.11
    `);
    assert.equal(output, 'sentinel', 'unchanged IP must not reopen the history lock file');
    assert.deepEqual(readRows(path.join(historyDir, 'cfg01.ipv4.tsv')), [
        '100000\t198.51.100.10',
        '100120\t198.51.100.11'
    ]);
    assert.equal(fs.statSync(path.join(historyDir, 'cfg01.ipv4.tsv')).mode & 0o777, 0o600);
});

test('DDNS history keeps one anchor before the rolling window', () => {
    const { historyDir } = runHistory(`
        export MINIGATE_HISTORY_NOW=100
        record_ip_history cfg02 ipv4 192.0.2.1
        export MINIGATE_HISTORY_NOW=150
        record_ip_history cfg02 ipv4 192.0.2.2
        export MINIGATE_HISTORY_NOW=250
        record_ip_history cfg02 ipv4 192.0.2.3
        export MINIGATE_HISTORY_NOW=400
        record_ip_history cfg02 ipv4 192.0.2.4
    `, { window: 100 });
    assert.deepEqual(readRows(path.join(historyDir, 'cfg02.ipv4.tsv')), [
        '250\t192.0.2.3',
        '400\t192.0.2.4'
    ]);
});

test('IPv4 and IPv6 histories stay separate and domain names are safe', () => {
    const { historyDir } = runHistory(`
        export MINIGATE_HISTORY_NOW=200000
        record_ip_history '*.example.com' ipv4 203.0.113.7
        record_ip_history '*.example.com' ipv6 2001:db8::7
    `);
    assert.deepEqual(readRows(path.join(historyDir, '__example_com.ipv4.tsv')), ['200000\t203.0.113.7']);
    assert.deepEqual(readRows(path.join(historyDir, '__example_com.ipv6.tsv')), ['200000\t2001:db8::7']);
});

test('DDNS writer and controller both use the domain history key', () => {
    const shellKey = fs.readFileSync(ddnsScript, 'utf8');
    assert.match(shellKey, /record_ip_history "\$domain" "ipv4" "\$ip4"/);
    assert.match(shellKey, /record_ip_history "\$domain" "ipv6" "\$ip6"/);
    assert.match(controller, /history_section_name\(section\.domain\) \.\. "\." \.\. family \.\. "\.tsv"/);
    assert.doesNotMatch(controller, /history_section_name\(section\.name\)/);
});

test('controller exposes a read-only rolling 24-hour history endpoint', () => {
    assert.match(controller, /entry\(\{"admin","services","minigate","ddns_history"\}, call\("action_ddns_history"\)\)/);
    assert.match(controller, /local cutoff = now - 86400/);
    assert.match(controller, /if end_time > cutoff and event\.timestamp <= now then/);
    assert.match(controller, /duration=math\.max\(0, end_time - event\.timestamp\)/);
    assert.match(controller, /active=\(next_event == nil\)/);
    assert.doesNotMatch(controller, /ddns_history"\}, post\(/);
});

test('DDNS page includes responsive history controls and required columns', () => {
    assert.match(model, /s\.template="minigate\/ddns_history"/);
    for (const text of ['最近一天 IP 变化明细', 'IP 地址', '开始时间', '结束时间', '持续时间', '使用中']) {
        assert.match(view, new RegExp(text));
    }
    assert.match(view, /@media\(max-width:640px\)/);
    assert.match(view, /data-darkmode="true"/);
    assert.match(view, /refresh\.disabled=true/);
    assert.match(view, /textContent/);
});

test('DDNS page treats an empty JSON object as an empty array', () => {
    const match = view.match(/function asArray\(value\)\{([\s\S]*?)\n    \}/);
    assert.ok(match, 'asArray helper must exist');
    const asArray = Function('value', match[1]);
    assert.deepEqual(asArray([]), []);
    assert.deepEqual(asArray({}), []);
    assert.equal(asArray({ unexpected: true }), null);
    assert.equal(asArray(null), null);
    assert.match(view, /nextRecords===null/);
    assert.match(view, /records=nextRecords/);
});
