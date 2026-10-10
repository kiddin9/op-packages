#!/bin/sh
# Regression guard for bounded background polling while preserving wake latency.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/root/usr/libexec/smartsafehub-activity-sync"
sh -n "$SCRIPT"
# Idle loop shall never call UCI/JSON state readers before the 60-second gate.
python3 - "$SCRIPT" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text()
loop=s.split('daemon_loop() {',1)[1].split('\nusage() {',1)[0]
assert 'DAEMON_SCHEDULE_CHECK_S=60' in s
assert 'DAEMON_TICK_S=15' in s
assert loop.index('[ ! -e "$WAKE_FILE" ]') < loop.index('DAEMON_SCHEDULE_CHECK_S')
assert loop.index('DAEMON_SCHEDULE_CHECK_S') < loop.index('cloud_sync_enabled')
assert loop.index('cloud_sync_enabled') < loop.index("previous_state_number '@.nextSyncAt'")
assert 'retry_backoff_active' in loop
assert 'consume_wake_marker || true' in loop
assert 'ssh_runtime_execute sync-once sync_once' in loop
print('activity idle polling contract: OK')
PY
