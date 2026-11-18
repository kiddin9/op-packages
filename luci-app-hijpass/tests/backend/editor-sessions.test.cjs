const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { shellRuntime, interpreter } = require('./helpers.cjs');

test('editor session cleanup reports only supplied live IDs without renewing old sessions', t => {
    const directory = fs.mkdtempSync('/tmp/hijpass-editor-sessions-');
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const runtime = shellRuntime(), script = path.join(directory, 'sessions.uc');
    fs.writeFileSync(script, fs.readFileSync(path.join(runtime, 'rpc/data.uc'), 'utf8')
        .replace("from 'ubus'", "from './bus.uc'")
        .replaceAll("from '../", "from '" + runtime + "/rpc/../")
        .replace("from './files.uc'", "from '" + runtime + "/rpc/files.uc'"));
    fs.writeFileSync(path.join(directory, 'bus.uc'), `export function connect() {
        return { call: (object, method, args, mode) => {
            if (object != 'session' || method != 'list' || length(args) || mode != 'multiple') die('must not renew sessions');
            return [{ ubus_rpc_session: '${'b'.repeat(32)}' }, { ubus_rpc_session: '${'d'.repeat(32)}' }];
        }, disconnect: () => null };
    };`);
    function call(sessions) {
        const result = spawnSync(interpreter, ['-S', '-L', path.join(runtime, 'ucode'), '--', script, 'call', 'editor_sessions'], {
            encoding: 'utf8', input: JSON.stringify({ sessions }),
        });
        assert.equal(result.status, 0, result.stderr);
        return JSON.parse(result.stdout);
    }
    assert.deepEqual(call(['b'.repeat(32), 'c'.repeat(32)]), { sessions: ['b'.repeat(32)] });
    assert.deepEqual(call([]), { sessions: [] });
    assert.match(call(['invalid']).error, /invalid session list/);
    assert.match(call(Array(65).fill('b'.repeat(32))).error, /invalid session list/);
});
