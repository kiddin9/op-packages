const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../..');
const init = path.join(root, 'packages/51ddns-agent/files/51ddns-agent.init');
const rpc = fs.readFileSync(path.join(root, 'luci-app-51ddns/root/usr/libexec/rpcd/luci.51ddns'), 'utf8');
const shell = process.env.DDNS_TEST_SH || (process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'sh');
const firstID = '00000000-0000-4000-8000-000000000001';
const secondID = '00000000-0000-4000-8000-000000000002';

function fixture(t, content) {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ddns-identity-'));
	t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
	if (content !== undefined) fs.writeFileSync(path.join(dir, 'device.id'), content);
	fs.writeFileSync(path.join(dir, 'device.token'), 'existing-fixture-token\n');
	return dir.replaceAll('\\', '/');
}

function start(dir, requested, running = false, enabled = true, verify = true, moveMode = '', syncFailOn = 0) {
	return spawnSync(shell, ['-c', `
. "$DDNS_INIT"
SECRET_DIR="$DDNS_DIR"
RUNTIME_DIR="$DDNS_DIR/runtime"
uci_validate_section() {
 enabled="$DDNS_ENABLED"; account_token='new-fixture-token'; device_id="$DDNS_ID"
 control_url='https://api.51ddns.com'; refresh_seconds=30
 start_delay_seconds=0; max_active_relays=0; oem_voucher_file=''
}
logger() { printf '%s\\n' "$*" >&2; }
verify_device_identity() { [ "$DDNS_VERIFY" = 'yes' ]; }
chown() { :; }
DDNS_SYNC_COUNT=0
sync() {
 DDNS_SYNC_COUNT=$((DDNS_SYNC_COUNT + 1))
 [ "$DDNS_SYNC_COUNT" != "$DDNS_SYNC_FAIL_ON" ]
}
mv() {
 if [ "$2" = "$SECRET_DIR/.identity-pending" ] && [ "$DDNS_MOVE_MODE" = 'stage-crash' ]; then
  kill -KILL "$$"
 fi
 if [ "$2" = "$SECRET_DIR/.identity-cleanup" ] && [ "$DDNS_MOVE_MODE" = 'cleanup-crash' ]; then
  command mv "$@" || return 1
  kill -KILL "$$"
 fi
 if [ "$3" = "$SECRET_DIR/device.id" ] && [ "$2" = "$SECRET_DIR/.identity-pending/new.id" ]; then
  [ "$DDNS_MOVE_MODE" = 'fail' ] && return 1
  [ "$DDNS_MOVE_MODE" = 'crash' ] && kill -KILL "$$"
 fi
 if [ "$3" = "$SECRET_DIR/device.id" ] && [ "$DDNS_MOVE_MODE" = 'recovery-crash' ]; then
  case "$2" in "$SECRET_DIR"/.identity-recover.*) kill -KILL "$$";; esac
 fi
 command mv "$@"
}
procd_open_instance() { printf 'started\\n'; }
procd_running() { [ "$DDNS_RUNNING" = 'yes' ]; }
procd_set_param() { :; }
procd_add_jail() { :; }
procd_add_jail_mount() { :; }
procd_add_jail_mount_rw() { :; }
procd_close_instance() { :; }
start_service
`], { encoding: 'utf8', env: { ...process.env, DDNS_INIT: init.replaceAll('\\', '/'), DDNS_DIR: dir, DDNS_ID: requested, DDNS_RUNNING: running ? 'yes' : 'no', DDNS_ENABLED: enabled ? '1' : '0', DDNS_VERIFY: verify ? 'yes' : 'no', DDNS_MOVE_MODE: moveMode, DDNS_SYNC_FAIL_ON: String(syncFailOn) } });
}

test('startup refuses an identity assigned after the page was loaded before writing token or ID', t => {
	const dir = fixture(t, firstID + '\n');
	const result = start(dir, secondID);
	assert.equal(result.status, 1, result.stderr);
	assert.match(result.stderr, /conflicts with saved identity/);
	assert.doesNotMatch(result.stderr, /fixture-token|00000000/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), firstID + '\n');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
	assert.equal(fs.existsSync(path.join(dir, 'runtime')), false);
});

test('startup permits the same saved ID and preserves its bytes', t => {
	const dir = fixture(t, firstID);
	const result = start(dir, firstID);
	assert.equal(result.status, 0, result.stderr);
	assert.match(result.stdout, /started/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), firstID);
});

test('disabled service preserves identity and token even with a conflicting configured ID', t => {
	const dir = fixture(t, firstID + '\n');
	const result = start(dir, secondID, true, false);
	assert.equal(result.status, 0, result.stderr);
	assert.equal(result.stdout, '');
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), firstID + '\n');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
	assert.equal(fs.existsSync(path.join(dir, 'runtime')), false);
});

test('first setup binds an exact ID only when the saved identity is absent or empty', t => {
	for (const old of [undefined, '']) {
		const dir = fixture(t, old);
		const result = start(dir, firstID);
		assert.equal(result.status, 0, result.stderr);
		assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), firstID + '\n');
	}
});

test('failed ownership verification leaves a first-bind token and identity unchanged', t => {
	const dir = fixture(t, '');
	const result = start(dir, firstID, false, true, false);
	assert.equal(result.status, 1, result.stderr);
	assert.match(result.stderr, /identity unchanged/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), '');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
	assert.equal(fs.existsSync(path.join(dir, 'runtime')), false);
});

test('failure between token and ID replacement restores both old files and never starts', t => {
	const dir = fixture(t, '');
	const result = start(dir, firstID, false, true, true, 'fail');
	assert.equal(result.status, 1, result.stderr);
	assert.doesNotMatch(result.stdout, /started/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), '');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
	assert.equal(fs.existsSync(path.join(dir, '.identity-pending')), false);
});

test('failed durability barrier before or after journaling preserves old identity', t => {
	for (const failOn of [1, 2]) {
		const dir = fixture(t, '');
		const result = start(dir, firstID, false, true, true, '', failOn);
		assert.equal(result.status, 1, `barrier ${failOn}: ${result.stderr}`);
		assert.doesNotMatch(result.stdout, /started/);
		assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), '');
		assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
		assert.equal(fs.existsSync(path.join(dir, '.identity-pending')), false);
	}
});

test('interrupted first-bind recovers the old pair before another ownership check', t => {
	const dir = fixture(t, '');
	const crashed = start(dir, firstID, false, true, true, 'crash');
	assert.notEqual(crashed.status, 0);
	assert.equal(fs.existsSync(path.join(dir, '.identity-pending')), true);
	const resumed = start(dir, firstID, false, true, false);
	assert.equal(resumed.status, 1, resumed.stderr);
	assert.match(resumed.stderr, /interrupted identity update recovered/);
	assert.doesNotMatch(resumed.stdout, /started/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), '');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
	assert.equal(fs.existsSync(path.join(dir, '.identity-pending')), false);
});

test('interrupted recovery can be resumed without starting with a mixed identity', t => {
	const dir = fixture(t, '');
	assert.notEqual(start(dir, firstID, false, true, true, 'crash').status, 0);
	const interrupted = start(dir, firstID, false, true, false, 'recovery-crash');
	assert.notEqual(interrupted.status, 0);
	assert.equal(fs.existsSync(path.join(dir, '.identity-pending')), true);
	const resumed = start(dir, firstID, false, true, false);
	assert.equal(resumed.status, 1, resumed.stderr);
	assert.doesNotMatch(resumed.stdout, /started/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), '');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
	assert.equal(fs.existsSync(path.join(dir, '.identity-pending')), false);
});

test('interrupted staging discards temporary copies before another ownership check', t => {
	const dir = fixture(t, '');
	const crashed = start(dir, firstID, false, true, true, 'stage-crash');
	assert.notEqual(crashed.status, 0);
	assert.ok(fs.readdirSync(dir).some(name => name.startsWith('.identity-stage.')));
	const resumed = start(dir, firstID, false, true, false);
	assert.equal(resumed.status, 1, resumed.stderr);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), '');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
	assert.equal(fs.readdirSync(dir).some(name => name.startsWith('.identity-stage.')), false);
});

test('interrupted journal cleanup keeps the committed identity and clears leftovers on restart', t => {
	const dir = fixture(t, '');
	const crashed = start(dir, firstID, false, true, true, 'cleanup-crash');
	assert.notEqual(crashed.status, 0);
	assert.equal(fs.existsSync(path.join(dir, '.identity-cleanup')), true);
	const resumed = start(dir, firstID);
	assert.equal(resumed.status, 0, resumed.stderr);
	assert.match(resumed.stdout, /started/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), firstID + '\n');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'new-fixture-token\n');
	assert.equal(fs.existsSync(path.join(dir, '.identity-cleanup')), false);
});

test('failed verification of a changed account token preserves an existing device', t => {
	const dir = fixture(t, firstID + '\n');
	const result = start(dir, firstID, false, true, false);
	assert.equal(result.status, 1, result.stderr);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), firstID + '\n');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
});

test('blank explicit ID keeps the automatic-registration and saved-identity paths', t => {
	for (const old of [undefined, '', firstID + '\n']) {
		const dir = fixture(t, old);
		const result = start(dir, '');
		assert.equal(result.status, 0, result.stderr);
		assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), old || '');
	}
});

test('invalid explicit ID is rejected before identity and token are written', t => {
	for (const invalid of ['invalid', firstID + '\nunexpected-content']) {
		const dir = fixture(t, '');
		const result = start(dir, invalid);
		assert.equal(result.status, 1, result.stderr);
		assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), '');
		assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
	}
});

test('non-regular identity path is rejected without changing token', t => {
	const dir = fixture(t);
	fs.mkdirSync(path.join(dir, 'device.id'));
	const result = start(dir, firstID);
	assert.equal(result.status, 1, result.stderr);
	assert.match(result.stderr, /not a regular file/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
});

test('a running automatic-registration process must be stopped before assigning an ID', t => {
	const dir = fixture(t, '');
	const result = start(dir, firstID, true);
	assert.equal(result.status, 1, result.stderr);
	assert.match(result.stderr, /stop the agent/);
	assert.equal(fs.readFileSync(path.join(dir, 'device.id'), 'utf8'), '');
	assert.equal(fs.readFileSync(path.join(dir, 'device.token'), 'utf8'), 'existing-fixture-token\n');
});

test('RPC exposes only a valid saved UUID and an explicit identity state', t => {
	const functionSource = rpc.slice(rpc.indexOf('read_device_identity()'), rpc.indexOf('\nprint_status()'));
	for (const [content, expected] of [
		[undefined, 'empty|'], ['', 'empty|'],
		[firstID + '\n', 'saved|' + firstID], ['not-an-identity', 'unavailable|'],
		[firstID + '\nunexpected-content', 'unavailable|'],
	]) {
		const dir = fixture(t, content);
		const script = functionSource.replaceAll('/etc/51ddns/device.id', '$DDNS_DIR/device.id') + '\nread_device_identity\nprintf "%s|%s" "$status_identity_state" "$status_device_id"';
		const result = spawnSync(shell, ['-c', script], { encoding: 'utf8', env: { ...process.env, DDNS_DIR: dir } });
		assert.equal(result.status, 0, result.stderr);
		assert.equal(result.stdout, expected);
	}
	assert.match(rpc, /json_add_string saved_device_id "\$status_device_id"/);
	assert.doesNotMatch(functionSource, /device\.token|account_token/);
});
