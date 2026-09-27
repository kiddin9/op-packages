#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-events"
INIT_SCRIPT="$ROOT_DIR/root/etc/init.d/smartsafehub-events"
CORE_RPC="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/core.uc"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -x "$HELPER" ] || fail 'event helper가 실행 가능해야 합니다.'
[ -x "$INIT_SCRIPT" ] || fail 'event boot init script가 실행 가능해야 합니다.'
[ -f "$CORE_RPC" ] || fail 'core RPC module이 존재해야 합니다.'
sh -n "$HELPER" || fail 'event helper가 POSIX shell 문법 검사를 통과해야 합니다.'
sh -n "$INIT_SCRIPT" || fail 'event init script가 POSIX shell 문법 검사를 통과해야 합니다.'

mkdir -p "$TMP/bin" "$TMP/runtime"
printf '%s\n' '11111111-2222-3333-4444-555555555555' > "$TMP/boot_id"

cat > "$TMP/bin/jsonfilter" <<'EOF_JSONFILTER'
#!/bin/sh
set -eu
file=''
expr='@'
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) file="$2"; shift 2 ;;
		-e) expr="$2"; shift 2 ;;
		*) shift ;;
	esac
done
if [ "$expr" = '@' ]; then
	jq -e . "$file" >/dev/null
else
	jq_expr="${expr#@}"
	jq -r "$jq_expr // empty" "$file"
fi
EOF_JSONFILTER
chmod +x "$TMP/bin/jsonfilter"

cat > "$TMP/bin/date" <<'EOF_DATE'
#!/bin/sh
[ "${1:-}" = '+%s' ] || exit 1
printf '%s\n' "${MOCK_EVENT_EPOCH:-1800000000}"
EOF_DATE
chmod +x "$TMP/bin/date"

cat > "$TMP/bin/logger" <<'EOF_LOGGER'
#!/bin/sh
exit 0
EOF_LOGGER
chmod +x "$TMP/bin/logger"

cat > "$TMP/bin/ubus" <<'EOF_UBUS'
#!/bin/sh
set -eu
[ "${1:-}" = call ] && [ "${2:-}" = safeshield ] && [ "${3:-}" = status ] || exit 1
cat "$MOCK_SAFESHIELD_STATUS"
EOF_UBUS
chmod +x "$TMP/bin/ubus"

run_events() {
	SMARTSAFEHUB_EVENTS_RUNTIME_DIR="$TMP/runtime" \
	SMARTSAFEHUB_EVENTS_FILE="$TMP/runtime/events.jsonl" \
	SMARTSAFEHUB_EVENTS_HISTORY_FILE="$TMP/runtime/activity-history.jsonl" \
	SMARTSAFEHUB_EVENTS_LOCK_DIR="$TMP/runtime/events.lock" \
	SMARTSAFEHUB_EVENTS_SEQ_FILE="$TMP/runtime/events.seq" \
	SMARTSAFEHUB_EVENTS_BOOT_MARKER_FILE="$TMP/runtime/events.boot-id" \
	SMARTSAFEHUB_EVENTS_BOOT_ID_FILE="$TMP/boot_id" \
	SMARTSAFEHUB_EVENTS_JSONFILTER_BIN="$TMP/bin/jsonfilter" \
	SMARTSAFEHUB_EVENTS_DATE_BIN="$TMP/bin/date" \
	SMARTSAFEHUB_EVENTS_LOGGER_BIN="$TMP/bin/logger" \
	SMARTSAFEHUB_ACTIVITY_CLOUD_SYNC_ENABLED="${MOCK_CLOUD_SYNC_ENABLED:-1}" \
	SMARTSAFEHUB_EVENTS_MAX_EVENTS=8 \
	SMARTSAFEHUB_EVENTS_SAFESHIELD_UBUS_BIN="$TMP/bin/ubus" \
	SMARTSAFEHUB_EVENTS_SAFESHIELD_JSONFILTER_BIN="$TMP/bin/jsonfilter" \
	MOCK_SAFESHIELD_STATUS="$TMP/safeshield-status.json" \
	PATH="$TMP/bin:$PATH" \
	"$HELPER" "$@"
}

first_id="$(MOCK_EVENT_EPOCH=1800000001 run_events emit safeshield safeshield.blocklist.updated success '{"domain_count":33818}' 1800000001)"
[ -n "$first_id" ] || fail '정규화 event emit은 event_id를 반환해야 합니다.'
run_events list > "$TMP/list.json"
jq -e --arg id "$first_id" '.schema == 1 and (.events | length) == 1 and .events[0].event_id == $id and .events[0].event_type == "safeshield.blocklist.updated" and .events[0].severity == "success" and .events[0].occurred_at == 1800000001 and .events[0].device_uuid == null and .events[0].source == "safeshield" and .events[0].metadata.domain_count == 33818' "$TMP/list.json" >/dev/null || \
	fail 'event queue는 schema v1 정규화 레코드를 보존해야 합니다.'

run_events history > "$TMP/history.json"
jq -e --arg id "$first_id" '.schema == 1 and (.events | length) == 1 and .events[0].event_id == $id' "$TMP/history.json" >/dev/null || \
	fail 'local activity history는 outbox와 별도로 동일한 정규화 이벤트를 보존해야 합니다.'

# Cloud opt-out keeps local history but must not create an upload outbox or wake marker.
rm -f "$TMP/runtime/events.jsonl" "$TMP/runtime/activity-history.jsonl" "$TMP/runtime/events.seq" "$TMP/runtime/activity-sync.wake"
local_only_id="$(MOCK_CLOUD_SYNC_ENABLED=0 MOCK_EVENT_EPOCH=1800000003 run_events emit activity settings.activity_cloud_sync.disabled info '{"origin":"direct"}' 1800000003)"
run_events history > "$TMP/history-cloud-off.json"
MOCK_CLOUD_SYNC_ENABLED=0 run_events list > "$TMP/list-cloud-off.json"
jq -e --arg id "$local_only_id" '(.events | length) == 1 and .events[0].event_id == $id' "$TMP/history-cloud-off.json" >/dev/null || \
	fail 'Cloud 전송 OFF에서도 local recent activity는 계속 기록되어야 합니다.'
jq -e '(.events | length) == 0' "$TMP/list-cloud-off.json" >/dev/null || \
	fail 'Cloud 전송 OFF에서는 새 이벤트를 upload outbox에 추가하면 안 됩니다.'
[ ! -e "$TMP/runtime/activity-sync.wake" ] || fail 'Cloud 전송 OFF에서는 activity sync wake marker를 만들면 안 됩니다.'

# r8 -> r9 migration must be tested with an actual legacy r8 outbox fixture.
# Do not create the fixture through the current emit path: r19 intentionally
# changes Cloud outbox creation based on cloud_sync_enabled, while an r8 device
# already has events.jsonl on disk before that setting exists.
rm -f "$TMP/runtime/events.jsonl" "$TMP/runtime/activity-history.jsonl" "$TMP/runtime/events.seq"
legacy_id='11111111-2222-3333-4444-555555555555-1800000001-1'
printf '%s\n' \
	'{"schema":1,"event_id":"11111111-2222-3333-4444-555555555555-1800000001-1","event_type":"safeshield.blocklist.updated","severity":"success","occurred_at":1800000001,"device_uuid":null,"source":"safeshield","metadata":{"domain_count":33818}}' \
	> "$TMP/runtime/events.jsonl"

# Before the dedicated history exists, history reads must expose the already
# collected r8 outbox regardless of the current Cloud toggle.
MOCK_CLOUD_SYNC_ENABLED=0 run_events history > "$TMP/history-r8-fallback.json"
jq -e --arg id "$legacy_id" '(.events | length) == 1 and .events[0].event_id == $id' "$TMP/history-r8-fallback.json" >/dev/null || \
	fail '전용 history가 없으면 r8 outbox를 최근 활동 fallback으로 읽어야 합니다.'

# The first new event after upgrade must seed dedicated local history from the
# legacy outbox even when Cloud transfer is currently OFF. The new event stays
# local-only, while the pre-existing r8 outbox remains untouched until the
# Cloud toggle policy explicitly clears it.
second_id="$(MOCK_CLOUD_SYNC_ENABLED=0 MOCK_EVENT_EPOCH=1800000002 run_events emit network network.internet.recovered success '{"downtime_seconds":48}' 1800000002)"
MOCK_CLOUD_SYNC_ENABLED=0 run_events history > "$TMP/history-r9-seeded.json"
jq -e --arg first "$legacy_id" --arg second "$second_id" '(.events | length) == 2 and .events[0].event_id == $first and .events[1].event_id == $second' "$TMP/history-r9-seeded.json" >/dev/null || \
	fail '첫 r9 이벤트는 기존 r8 outbox를 local history에 승계한 뒤 새 이벤트를 추가해야 합니다.'

if run_events emit safeshield bad.event notice '{}' >/dev/null 2>&1; then
	fail 'severity는 info/success/warning/error 외 값을 허용하면 안 됩니다.'
fi
if run_events emit safeshield bad.event info '[1,2,3]' >/dev/null 2>&1; then
	fail 'metadata는 JSON object만 허용해야 합니다.'
fi
if run_events emit safeshield bad.event info '{broken' >/dev/null 2>&1; then
	fail '잘못된 JSON metadata를 큐에 기록하면 안 됩니다.'
fi

# Queue growth is bounded; oldest lines are dropped first. Keep this fixture
# independent from the preceding legacy migration / Cloud opt-out scenarios.
# In particular, do not inherit a legacy outbox, dedicated history, sequence,
# wake marker or a shell-specific temporary Cloud toggle value.
rm -f "$TMP/runtime/events.jsonl" "$TMP/runtime/activity-history.jsonl" \
	"$TMP/runtime/events.seq" "$TMP/runtime/activity-sync.wake"

i=0
while [ "$i" -lt 10 ]; do
	i=$((i + 1))
	MOCK_CLOUD_SYNC_ENABLED=1 run_events emit system "test.event.$i" info "{\"index\":$i}" "$((1800000100 + i))" >/dev/null
done
MOCK_CLOUD_SYNC_ENABLED=1 run_events list > "$TMP/list.json"
queue_count="$(jq '.events | length' "$TMP/list.json")"
[ "$queue_count" -eq 8 ] || fail "event queue는 설정된 최대 개수를 초과하면 안 됩니다. (actual=$queue_count expected=8)"
[ "$(jq -r '.events[0].metadata.index' "$TMP/list.json")" = '3' ] || fail 'queue 초과 시 가장 오래된 event부터 제거해야 합니다.'
MOCK_CLOUD_SYNC_ENABLED=1 run_events history > "$TMP/history.json"
history_count="$(jq '.events | length' "$TMP/history.json")"
[ "$history_count" -eq 8 ] || fail "local activity history도 설정된 최대 개수를 초과하면 안 됩니다. (actual=$history_count expected=8)"
[ "$(jq -r '.events[0].metadata.index' "$TMP/history.json")" = '3' ] || fail 'history 초과 시 가장 오래된 event부터 제거해야 합니다.'

ack_id="$(jq -r '.events[3].event_id' "$TMP/list.json")"
run_events ack "$ack_id"
run_events list > "$TMP/list-after-ack.json"
jq -e --arg id "$ack_id" 'all(.events[]; .event_id != $id)' "$TMP/list-after-ack.json" >/dev/null || \
	fail 'ack된 event는 local queue에서 제거되어야 합니다.'
run_events history > "$TMP/history-after-ack.json"
jq -e --arg id "$ack_id" 'any(.events[]; .event_id == $id)' "$TMP/history-after-ack.json" >/dev/null || \
	fail 'Cloud outbox ack가 공유기 웹사이트용 local history를 삭제하면 안 됩니다.'

# Event writes are best-effort callers in production, so the helper itself must
# absorb short lock contention instead of dropping activity records. Simulate a
# live owner that releases the lock shortly after a new event arrives.
rm -f "$TMP/runtime/events.jsonl" "$TMP/runtime/activity-history.jsonl" "$TMP/runtime/events.seq"
rm -rf "$TMP/runtime/events.lock"
sleep 2 & lock_owner=$!
mkdir "$TMP/runtime/events.lock"
printf '%s\n' "$lock_owner" > "$TMP/runtime/events.lock/pid"
(
	sleep 0.15
	rm -rf "$TMP/runtime/events.lock"
) & lock_releaser=$!
contended_id="$(SMARTSAFEHUB_EVENTS_LOCK_RETRY_COUNT=80 SMARTSAFEHUB_EVENTS_LOCK_RETRY_DELAY_S=0.02 run_events emit system settings.test.contended info '{"origin":"direct"}' 1800000900)" || \
	fail 'short-lived event store lock contention must not drop a new event'
wait "$lock_releaser" 2>/dev/null || true
kill "$lock_owner" 2>/dev/null || true
wait "$lock_owner" 2>/dev/null || true
run_events history > "$TMP/contended-history.json"
jq -e --arg id "$contended_id" '(.events | length) == 1 and .events[0].event_id == $id and .events[0].event_type == "settings.test.contended"' "$TMP/contended-history.json" >/dev/null || \
	fail 'event emitted during short lock contention must remain in local history'

# A freshly created mkdir lock may exist briefly before its owner pid file is
# written. That window is not a stale lock. The previous implementation removed
# such a directory immediately, allowing multiple writers into the read-modify-
# replace critical section and silently collapsing history to only a few events.
rm -f "$TMP/runtime/events.jsonl" "$TMP/runtime/activity-history.jsonl" "$TMP/runtime/events.seq"
rm -rf "$TMP/runtime/events.lock" "$TMP/runtime/events.lock.reclaim"
mkdir "$TMP/runtime/events.lock"
(
	SMARTSAFEHUB_EVENTS_LOCK_RETRY_COUNT=100 SMARTSAFEHUB_EVENTS_LOCK_RETRY_DELAY_S=0.02 \
		run_events emit system settings.test.initializing_lock info '{"origin":"direct"}' 1800000901 > "$TMP/initializing-lock-id"
) & initializing_writer=$!
sleep 0.10
[ -d "$TMP/runtime/events.lock" ] || \
	fail 'a contender must not remove a pid-less lock that may still be initializing'
[ ! -e "$TMP/runtime/events.lock/pid" ] || \
	fail 'a contender must not take ownership of a pid-less lock that may still be initializing'
rm -rf "$TMP/runtime/events.lock"
wait "$initializing_writer" || fail 'writer must continue after the initializing lock is released'
run_events history > "$TMP/initializing-lock-history.json"
jq -e '(.events | length) == 1 and .events[0].event_type == "settings.test.initializing_lock"' "$TMP/initializing-lock-history.json" >/dev/null || \
	fail 'an event waiting behind an initializing lock must be retained'

# Concurrent direct producers must serialize through the same bounded writer
# lock instead of returning 75 and silently losing all but one record.
rm -f "$TMP/runtime/events.jsonl" "$TMP/runtime/activity-history.jsonl" "$TMP/runtime/events.seq"
rm -rf "$TMP/runtime/events.lock"
pids=''
i=0
while [ "$i" -lt 8 ]; do
	i=$((i + 1))
	(
		SMARTSAFEHUB_EVENTS_LOCK_RETRY_COUNT=100 SMARTSAFEHUB_EVENTS_LOCK_RETRY_DELAY_S=0.02 \
			run_events emit system "settings.test.parallel.$i" info "{\"index\":$i}" "$((1800000900 + i))" > "$TMP/parallel-id.$i"
	) &
	pids="$pids $!"
done
for pid in $pids; do
	wait "$pid" || fail 'parallel event producer lost an event while waiting for the writer lock'
done
run_events history > "$TMP/parallel-history.json"
[ "$(jq '.events | length' "$TMP/parallel-history.json")" -eq 8 ] || fail 'all concurrent events must be retained when the bounded history has capacity'
jq -e '[.events[].metadata.index] | sort == [1,2,3,4,5,6,7,8]' "$TMP/parallel-history.json" >/dev/null || \
	fail 'parallel event producers must not lose any record to writer lock contention'

# Boot event is one-per-kernel-boot even if the init service is restarted.
rm -f "$TMP/runtime/events.jsonl" "$TMP/runtime/activity-history.jsonl" "$TMP/runtime/events.seq" "$TMP/runtime/events.boot-id"
MOCK_EVENT_EPOCH=1800001000 run_events boot
MOCK_EVENT_EPOCH=1800001001 run_events boot
run_events list > "$TMP/boot-list.json"
jq -e '.events | length == 1 and .[0].event_type == "system.booted" and .[0].source == "system" and .[0].metadata.boot_id == "11111111-2222-3333-4444-555555555555"' "$TMP/boot-list.json" >/dev/null || \
	fail '같은 boot_id에서는 system.booted 이벤트가 중복되면 안 됩니다.'

printf '%s\n' 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' > "$TMP/boot_id"
MOCK_EVENT_EPOCH=1800002000 run_events boot
run_events list > "$TMP/boot-list.json"
[ "$(jq '.events | length' "$TMP/boot-list.json")" -eq 2 ] || fail '새 boot_id에서는 새 system.booted 이벤트를 기록해야 합니다.'

# The unified daemon owns SafeShield async refresh observation. The first
# successful observation is baseline-only; a later terminal timestamp emits one
# observer event and persists the timestamp so the same result is not replayed.
rm -f "$TMP/runtime/events.jsonl" "$TMP/runtime/activity-history.jsonl" "$TMP/runtime/events.seq" \
	"$TMP/runtime/safeshield-events.state"
cat > "$TMP/safeshield-status.json" <<'EOF_SAFE_BASELINE'
{"timestamps":{"last_success":1800003000,"last_failure":0},"artifact":{"version":"2026.09.21","unique_domains":33818},"runtime":{"last_error_code":""}}
EOF_SAFE_BASELINE
run_events observe-once || fail 'unified event daemon must baseline the current SafeShield refresh timestamps'
run_events list > "$TMP/safeshield-baseline-list.json"
[ "$(jq '.events | length' "$TMP/safeshield-baseline-list.json")" -eq 0 ] || \
	fail 'first SafeShield observer cycle must establish a baseline without fabricating history'
cat > "$TMP/safeshield-status.json" <<'EOF_SAFE_UPDATED'
{"timestamps":{"last_success":1800003060,"last_failure":0},"artifact":{"version":"2026.09.21.1","unique_domains":33901},"runtime":{"last_error_code":""}}
EOF_SAFE_UPDATED
run_events observe-once || fail 'unified event daemon must observe a later SafeShield refresh result'
run_events observe-once || fail 're-observing the same SafeShield timestamp must remain idempotent'
run_events list > "$TMP/safeshield-updated-list.json"
jq -e '(.events | length) == 1 and .events[0].event_type == "safeshield.blocklist.updated" and .events[0].occurred_at == 1800003060 and .events[0].metadata.origin == "observer" and .events[0].metadata.artifact_version == "2026.09.21.1" and .events[0].metadata.domain_count == 33901' "$TMP/safeshield-updated-list.json" >/dev/null || \
	fail 'unified SafeShield observer must emit exactly one normalized completion event'

grep -Fq 'procd_set_param command "$PROG" daemon' "$INIT_SCRIPT" || \
	fail 'smartsafehub-events init must keep the unified observer alive as a procd daemon'

grep -Fq 'activity event emit failed: source=%s event_type=%s' "$CORE_RPC" || \
	fail 'direct event producer failures must be visible in rpcd logs instead of remaining silent'
grep -Fq '], 5000);' "$CORE_RPC" || \
	fail 'direct event producer timeout must cover the bounded writer-lock wait'

# Production sources must emit normalized raw events rather than localized title/description strings.
for contract in \
	'root/usr/libexec/smartsafehub-updater:software.update.completed' \
	'root/usr/libexec/smartsafehub-updater:software.update.failed' \
	'root/usr/libexec/smartsafehub-firmware:firmware.update.started' \
	'root/usr/libexec/smartsafehub-firmware:firmware.update.failed' \
	'root/usr/libexec/smartsafehub-license:license.activated' \
	'root/usr/libexec/smartsafehub-license:license.changed' \
	'root/usr/libexec/smartsafehub-license:license.cleared' \
	'root/usr/libexec/smartsafehub-health:network.internet.disconnected' \
	'root/usr/libexec/smartsafehub-health:network.internet.recovered' \
	'root/usr/libexec/smartsafehub-events:safeshield.blocklist.updated' \
	'root/usr/libexec/smartsafehub-events:safeshield.blocklist.update_failed' \
	'root/usr/share/rpcd/ucode/smartsafehub/safeshield-management.uc:safeshield.protection.enabled' \
	'root/usr/share/rpcd/ucode/smartsafehub/safeshield-management.uc:safeshield.protection.disabled' \
	'root/usr/libexec/smartsafehub-health:health.issue.started' \
	'root/usr/libexec/smartsafehub-health:health.issue.resolved'; do
	file="${contract%%:*}"
	event_type="${contract#*:}"
	grep -Fq "$event_type" "$ROOT_DIR/$file" || fail "production event source가 누락되었습니다: $event_type"
done

printf 'PASS: SmartSafeHub normalized event outbox/history, boot deduplication, bounded retention and production event source contracts are valid\n'
