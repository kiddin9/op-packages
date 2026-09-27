#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SYNC_BIN="$ROOT_DIR/root/usr/libexec/smartsafehub-activity-sync"
EVENTS_BIN="$ROOT_DIR/root/usr/libexec/smartsafehub-events"
LICENSE_BIN="$ROOT_DIR/root/usr/libexec/smartsafehub-license"
SAFE_ADAPTER="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/safeshield-management.uc"
HEALTH_BIN="$ROOT_DIR/root/usr/libexec/smartsafehub-health"
CONFIG="$ROOT_DIR/root/etc/config/smartsafehub"
INIT_SYNC="$ROOT_DIR/root/etc/init.d/smartsafehub-activity-sync"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for file in "$SYNC_BIN" "$EVENTS_BIN" "$LICENSE_BIN" "$SAFE_ADAPTER" "$CONFIG" "$INIT_SYNC"; do
  [ -f "$file" ] || fail "missing activity producer/sync component: $file"
done

# Direct vs observer ownership contracts: explicit SafeShield mutations are
# emitted at the mutation call site, while Health owns only external state
# transitions. Async blocklist completion is observed by the unified event daemon.
grep -Fq 'safeshield.protection.enabled' "$SAFE_ADAPTER" || fail 'SafeShield enable must emit directly from the mutation adapter'
grep -Fq 'safeshield.protection.disabled' "$SAFE_ADAPTER" || fail 'SafeShield disable must emit directly from the mutation adapter'
grep -Fq 'watch-refresh-detached' "$SAFE_ADAPTER" || fail 'manual refresh must start a completion watcher after SafeShield accepts the request'
grep -Fq 'safeshield.blocklist.updated' "$EVENTS_BIN" || fail 'unified event daemon must record each observed SafeShield refresh completion'
grep -Fq 'safeshield.blocklist.update_failed' "$EVENTS_BIN" || fail 'unified event daemon must record SafeShield refresh failures'
grep -Fq 'safeshield_observe_once' "$EVENTS_BIN" || fail 'SafeShield refresh observer must live in smartsafehub-events'
[ ! -e "$ROOT_DIR/root/usr/libexec/smartsafehub-safeshield-events" ] || fail 'standalone SafeShield event daemon must be removed'
[ ! -e "$ROOT_DIR/root/etc/init.d/smartsafehub-safeshield-events" ] || fail 'standalone SafeShield event init service must be removed'
if grep -Fq 'safeshield.protection.enabled' "$HEALTH_BIN" || grep -Fq 'safeshield.blocklist.updated' "$HEALTH_BIN"; then
  fail 'Health observer must not duplicate SafeShield mutation/refresh events'
fi
grep -Fq 'network.internet.disconnected' "$HEALTH_BIN" || fail 'Health observer must keep WAN transition events'
grep -Fq 'health.issue.started' "$HEALTH_BIN" || fail 'Health observer must keep diagnostic transition events'
grep -Fq 'consume_wake_marker' "$SYNC_BIN" || fail 'activity sync daemon must consume wake markers so backend failures do not retry every daemon tick'
grep -Fq 'mv "$WAKE_FILE" "$consumed"' "$SYNC_BIN" || fail 'wake marker consumption must use atomic rename so events emitted during sync create a fresh marker'
grep -Fq 'RETRY_INITIAL_S=900' "$SYNC_BIN" || fail 'Cloud activity status failures must start with a 15-minute retry backoff'
grep -Fq 'RETRY_MAX_S=3600' "$SYNC_BIN" || fail 'Cloud activity retry backoff must be capped at one hour'
grep -Fq 'retry_backoff_active' "$SYNC_BIN" || fail 'new event wake markers must respect an active Cloud failure backoff'
grep -Fq 'cloud_sync_enabled' "$SYNC_BIN" || fail 'activity sync must honor the user Cloud transfer preference before any network work'
grep -Fq 'apply-config' "$SYNC_BIN" || fail 'activity sync must expose a runtime apply command for immediate toggle cleanup'
grep -Fq 'activity_cloud_sync_enabled' "$LICENSE_BIN" || fail 'license status must not retain an activity credential while Cloud transfer is disabled'
grep -Fq "option cloud_sync_enabled '0'" "$CONFIG" || fail 'fresh installs must default Cloud activity transfer to OFF'
grep -Fq 'activity-cloud-sync-upgrade-enable' "$ROOT_DIR/Makefile" || fail 'package upgrade must preserve pre-r19 implicit Cloud sync'
grep -Fq "smartsafehub.activity.cloud_sync_enabled='1'" "$ROOT_DIR/Makefile" || fail 'postinst must restore Cloud sync for pre-r19 upgrades'
grep -Fq "set smartsafehub.activity.cloud_sync_enabled='0'" "$INIT_SYNC" || fail 'dynamically created activity sections must default Cloud activity transfer to OFF'
grep -Fq "1|true|on|yes|'') return 0" "$SYNC_BIN" || fail 'missing pre-r19 Cloud preference must preserve legacy enabled behavior on upgrade'
if grep -Fq '$base/licenses/status' "$SYNC_BIN" || grep -Fq '$base/licenses/resolve' "$SYNC_BIN" || grep -Fq 'post_json()' "$SYNC_BIN"; then
  fail 'activity sync must not duplicate license API calls; smartsafehub-license owns license status and activity credential acquisition'
fi
grep -Fq 'SMARTSAFEHUB_ACTIVITY_LICENSE_BIN' "$SYNC_BIN" || fail 'activity sync must consume the dedicated license helper boundary'
grep -Fq '"$LICENSE_BIN" status-sync' "$SYNC_BIN" || fail 'missing/expired activity credentials must be refreshed through smartsafehub-license status-sync'
grep -Fq 'store_activity_credential_from_status' "$LICENSE_BIN" || fail 'license helper must cache activity_history credentials from its authoritative status response'
grep -Fq '$base/licenses/status' "$LICENSE_BIN" || fail 'license helper must remain the single owner of /licenses/status'
grep -Fq '[ -e "$WAKE_FILE" ] && ! retry_backoff_active' "$SYNC_BIN" || fail 'event wake must not bypass Cloud failure backoff'

for contract in \
  'root/usr/share/rpcd/ucode/smartsafehub/system.uc:settings.scheduled_reboot.updated' \
  'root/usr/share/rpcd/ucode/smartsafehub/system.uc:settings.timezone.updated' \
  'root/usr/share/rpcd/ucode/smartsafehub/updates.uc:settings.software_updates.updated' \
  'root/usr/share/rpcd/ucode/smartsafehub/health.uc:settings.health_reporter.enabled' \
  'root/usr/share/rpcd/ucode/smartsafehub/wifi-management.uc:settings.wifi.updated' \
  'root/usr/share/rpcd/ucode/smartsafehub/network-management.uc:settings.lan.updated' \
  'root/usr/share/rpcd/ucode/smartsafehub/iptv-management.uc:settings.iptv.updated'; do
  file="${contract%%:*}"
  event="${contract#*:}"
  grep -Fq "$event" "$ROOT_DIR/$file" || fail "direct settings event missing: $event"
done

MOCK_BIN="$TMP_DIR/bin"
RUNTIME="$TMP_DIR/runtime"
OUTBOX="$TMP_DIR/outbox.jsonl"
ACK_LOG="$TMP_DIR/ack.log"
CLEAR_LOG="$TMP_DIR/clear.log"
FETCH_LOG="$TMP_DIR/fetch.log"
LICENSE_CALL_LOG="$TMP_DIR/license-calls.log"
LICENSE_STATUS_FILE="$TMP_DIR/license-status.json"
mkdir -p "$MOCK_BIN" "$RUNTIME"
: > "$ACK_LOG"
: > "$CLEAR_LOG"
: > "$FETCH_LOG"
: > "$LICENSE_CALL_LOG"

cat > "$MOCK_BIN/events" <<'EOF_EVENTS'
#!/bin/sh
set -eu
case "${1:-}" in
  list)
    printf '{"schema":1,"events":['
    first=1
    if [ -s "$MOCK_OUTBOX" ]; then
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        [ "$first" -eq 1 ] || printf ','
        printf '%s' "$line"
        first=0
      done < "$MOCK_OUTBOX"
    fi
    printf ']}\n'
    ;;
  ack)
    id="${2:-}"
    printf '%s\n' "$id" >> "$MOCK_ACK_LOG"
    tmp="${MOCK_OUTBOX}.tmp.$$"
    awk -v needle="\"event_id\":\"$id\"" 'index($0, needle) == 0 { print }' "$MOCK_OUTBOX" > "$tmp"
    mv "$tmp" "$MOCK_OUTBOX"
    ;;
  clear-outbox)
    : > "$MOCK_OUTBOX"
    printf 'clear\n' >> "$MOCK_CLEAR_LOG"
    ;;
  *) exit 2 ;;
esac
EOF_EVENTS
chmod +x "$MOCK_BIN/events"

cat > "$MOCK_BIN/uci" <<'EOF_UCI'
#!/bin/sh
case "$*" in
  *smartsafehub.activity.cloud_sync_enabled*) printf '%s\n' "${MOCK_CLOUD_SYNC_ENABLED:-1}" ;;
  *smartsafehub.activity.sync_interval_s*) printf '300\n' ;;
  *smartsafehub.activity.startup_delay_s*) printf '0\n' ;;
  *smartsafehub.activity.api_base_url*) printf 'https://www.smartsafehub.com/api/v1\n' ;;
esac
EOF_UCI
chmod +x "$MOCK_BIN/uci"

cat > "$MOCK_BIN/jsonfilter" <<'EOF_JSONFILTER'
#!/bin/sh
set -eu
file=''
expr=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -i) file="$2"; shift 2 ;;
    -e) expr="$2"; shift 2 ;;
    *) shift ;;
  esac
done
jq_expr="$(printf '%s' "$expr" | sed -e 's/^@//' -e 's/\[\*\]/[]/g')"
jq -r "$jq_expr | if . == null then empty else . end" "$file"
EOF_JSONFILTER
chmod +x "$MOCK_BIN/jsonfilter"

cat > "$MOCK_BIN/date" <<'EOF_DATE'
#!/bin/sh
printf '1800000000\n'
EOF_DATE
chmod +x "$MOCK_BIN/date"

cat > "$MOCK_BIN/logger" <<'EOF_LOGGER'
#!/bin/sh
exit 0
EOF_LOGGER
chmod +x "$MOCK_BIN/logger"

cat > "$MOCK_BIN/uclient-fetch" <<'EOF_FETCH'
#!/bin/sh
set -eu
output=''
body=''
url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -O) output="$2"; shift 2 ;;
    --body-file=*) body="${1#--body-file=}"; shift ;;
    --body-file) body="$2"; shift 2 ;;
    --header=*|-q) shift ;;
    --header|-T|--method) shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  */activity/events)
    printf '%s
' "$url" >> "$MOCK_FETCH_LOG"
    count="$(jq '.events | length' "$body")"
    printf '{"status":"accepted","received":%s,"accepted":%s,"duplicates":0,"expired":0}
' "$count" "$count" > "$output"
    ;;
  */licenses/status|*/licenses/resolve)
    echo 'activity sync must not call license APIs directly' >&2
    exit 99
    ;;
  *) exit 1 ;;
esac
EOF_FETCH
chmod +x "$MOCK_BIN/uclient-fetch"

cat > "$MOCK_BIN/license" <<'EOF_LICENSE'
#!/bin/sh
set -eu
command="${1:-}"
printf '%s
' "$command" >> "$MOCK_LICENSE_CALL_LOG"
case "$command" in
  status-sync)
    case "${MOCK_STATUS_MODE:-paid}" in
      paid)
        cat > "$MOCK_ACTIVITY_CREDENTIAL_FILE" <<EOF_CREDENTIAL
{"schema":1,"token":"activity-token","upload_url":"https://www.smartsafehub.com/api/v1/activity/events","expires_at":1800172800,"retention_days":90,"plan":"pro"}
EOF_CREDENTIAL
        printf '%s
' '{"schema":1,"component":"license","phase":"active","plan":"pro","licenseStatus":"active","activationStatus":"active","deviceAction":"none"}' > "$MOCK_LICENSE_STATUS_FILE"
        exit 0
        ;;
      paid-missing|paid-null)
        rm -f "$MOCK_ACTIVITY_CREDENTIAL_FILE"
        printf '%s
' '{"schema":1,"component":"license","phase":"active","plan":"pro","licenseStatus":"active","activationStatus":"active","deviceAction":"none"}' > "$MOCK_LICENSE_STATUS_FILE"
        exit 0
        ;;
      revoked)
        rm -f "$MOCK_ACTIVITY_CREDENTIAL_FILE"
        printf '%s
' '{"schema":1,"component":"license","phase":"cleared","plan":"pro","licenseStatus":"active","activationStatus":"revoked","deviceAction":"clear_license"}' > "$MOCK_LICENSE_STATUS_FILE"
        exit 0
        ;;
      free)
        rm -f "$MOCK_ACTIVITY_CREDENTIAL_FILE"
        printf '%s
' '{"schema":1,"component":"license","phase":"unconfigured","plan":null,"licenseStatus":"unlicensed","activationStatus":"not_found","deviceAction":"none"}' > "$MOCK_LICENSE_STATUS_FILE"
        exit 0
        ;;
      unknown)
        rm -f "$MOCK_ACTIVITY_CREDENTIAL_FILE"
        printf '%s
' '{"schema":1,"component":"license","phase":"error","plan":"pro","licenseStatus":"active","activationStatus":"active","deviceAction":"none"}' > "$MOCK_LICENSE_STATUS_FILE"
        exit 0
        ;;
      unavailable) exit 1 ;;
      *) exit 1 ;;
    esac
    ;;
  status)
    cat "$MOCK_LICENSE_STATUS_FILE"
    ;;
  *) exit 2 ;;
esac
EOF_LICENSE
chmod +x "$MOCK_BIN/license"

cat > "$MOCK_BIN/sleep" <<'EOF_SLEEP'
#!/bin/sh
exit 0
EOF_SLEEP
chmod +x "$MOCK_BIN/sleep"

write_outbox() {
  cat > "$OUTBOX" <<'EOF_OUTBOX'
{"schema":1,"event_id":"evt-1","event_type":"settings.wifi.updated","severity":"info","occurred_at":1799999900,"device_uuid":null,"source":"network","metadata":{"origin":"direct"}}
{"schema":1,"event_id":"evt-2","event_type":"network.internet.recovered","severity":"success","occurred_at":1799999950,"device_uuid":null,"source":"network","metadata":{"origin":"observer","downtime_seconds":10}}
EOF_OUTBOX
}

run_sync() {
  cloud_sync_enabled="${2:-1}"
  env \
    SMARTSAFEHUB_COMMON_LIB="$ROOT_DIR/root/usr/lib/smartsafehub/common.sh" \
    SMARTSAFEHUB_ACTIVITY_RUNTIME_DIR="$RUNTIME" \
    SMARTSAFEHUB_ACTIVITY_EVENTS_BIN="$MOCK_BIN/events" \
    SMARTSAFEHUB_ACTIVITY_UCI_BIN="$MOCK_BIN/uci" \
        SMARTSAFEHUB_ACTIVITY_JSONFILTER_BIN="$MOCK_BIN/jsonfilter" \
    SMARTSAFEHUB_ACTIVITY_UCLIENT_FETCH_BIN="$MOCK_BIN/uclient-fetch" \
    SMARTSAFEHUB_ACTIVITY_LICENSE_BIN="$MOCK_BIN/license" \
    SMARTSAFEHUB_ACTIVITY_DATE_BIN="$MOCK_BIN/date" \
    SMARTSAFEHUB_ACTIVITY_SLEEP_BIN="$MOCK_BIN/sleep" \
    SMARTSAFEHUB_ACTIVITY_LOGGER_BIN="$MOCK_BIN/logger" \
    MOCK_OUTBOX="$OUTBOX" MOCK_ACK_LOG="$ACK_LOG" MOCK_CLEAR_LOG="$CLEAR_LOG" \
    MOCK_FETCH_LOG="$FETCH_LOG" MOCK_LICENSE_CALL_LOG="$LICENSE_CALL_LOG" \
    MOCK_LICENSE_STATUS_FILE="$LICENSE_STATUS_FILE" MOCK_ACTIVITY_CREDENTIAL_FILE="$RUNTIME/activity-sync-credential.json" \
    MOCK_STATUS_MODE="$1" MOCK_CLOUD_SYNC_ENABLED="$cloud_sync_enabled" \
    "$SYNC_BIN" sync-once
}

# Explicit opt-out must be fully local: no license status refresh, no upload, no
# retained Cloud credential, and the bounded Cloud-only outbox is discarded.
rm -f "$RUNTIME/activity-sync-credential.json" "$RUNTIME/activity-sync.json"
: > "$ACK_LOG"
: > "$CLEAR_LOG"
: > "$FETCH_LOG"
: > "$LICENSE_CALL_LOG"
write_outbox
run_sync unavailable 0 || fail 'disabled Cloud activity sync must settle successfully without network access'
[ ! -s "$OUTBOX" ] || fail 'disabling Cloud activity sync must clear the Cloud-only outbox'
grep -Fq 'clear' "$CLEAR_LOG" || fail 'disabled Cloud activity sync must explicitly clear only the Cloud outbox'
[ ! -e "$RUNTIME/activity-sync-credential.json" ] || fail 'disabled Cloud activity sync must remove the runtime upload credential'
[ ! -s "$LICENSE_CALL_LOG" ] || fail 'disabled Cloud activity sync must not call license status-sync'
[ ! -s "$FETCH_LOG" ] || fail 'disabled Cloud activity sync must not perform Cloud HTTP requests'
jq -e '.phase == "disabled" and .pendingEvents == 0 and .lastErrorCode == null' "$RUNTIME/activity-sync.json" >/dev/null || \
  fail 'disabled Cloud activity state must be explicit and non-error'

write_outbox
run_sync paid || fail 'paid activity batch must synchronize successfully'
[ ! -s "$OUTBOX" ] || fail 'successful upload must ack only the snapshotted outbox events'
[ "$(wc -l < "$ACK_LOG" | tr -d ' ')" -eq 2 ] || fail 'successful two-event upload must ack both event IDs'
jq -e '.eligible == true and .plan == "pro" and .retentionDays == 90 and .pendingEvents == 0 and .lastUploadedCount == 2 and .lastSuccessAt == 1800000000' "$RUNTIME/activity-sync.json" >/dev/null || \
  fail 'paid synchronization state must expose entitlement, retention, pending count and success metadata'
grep -Fxq 'status-sync' "$LICENSE_CALL_LOG" || fail 'missing credential must be refreshed through smartsafehub-license status-sync'
if grep -Eq '/licenses/(status|resolve)' "$FETCH_LOG"; then
  fail 'activity sync must never call license APIs directly'
fi

# Credentials issued by the previous /licenses/resolve implementation use the
# same activity upload token format. A still-valid cached credential must remain
# usable after upgrading the router and must not force an immediate status call.
: > "$FETCH_LOG"
: > "$ACK_LOG"
: > "$LICENSE_CALL_LOG"
write_outbox
run_sync unavailable || fail 'a still-valid cached activity credential must survive the status-endpoint migration'
[ ! -s "$OUTBOX" ] || fail 'cached credential upload must ack the snapshotted events'
if [ -s "$LICENSE_CALL_LOG" ]; then
  fail 'valid cached activity credential must not trigger an unnecessary license status refresh'
fi
grep -Fq '/activity/events' "$FETCH_LOG" || fail 'valid cached credential must continue uploading activity events'

rm -f "$RUNTIME/activity-sync-credential.json"
: > "$ACK_LOG"
: > "$CLEAR_LOG"
: > "$LICENSE_CALL_LOG"
write_outbox
if run_sync paid-missing >/dev/null 2>&1; then
  fail 'paid status without an activity credential must be retried as an error'
fi
[ -s "$OUTBOX" ] || fail 'paid events must never be discarded when the backend omits the activity credential'
[ ! -s "$CLEAR_LOG" ] || fail 'paid missing-credential response must not clear the Cloud outbox'
jq -e '.phase == "error" and .lastErrorCode == "ACTIVITY_CREDENTIAL_UNAVAILABLE"' "$RUNTIME/activity-sync.json" >/dev/null || \
  fail 'paid missing-credential response must surface a rollout-safe status error'

rm -f "$RUNTIME/activity-sync-credential.json"
: > "$ACK_LOG"
: > "$CLEAR_LOG"
: > "$LICENSE_CALL_LOG"
write_outbox
if run_sync paid-null >/dev/null 2>&1; then
  fail 'older paid status without activity credentials must remain retryable until the Hub activity API is deployed'
fi
[ -s "$OUTBOX" ] || fail 'older paid status must preserve the bounded Cloud outbox'
[ ! -s "$CLEAR_LOG" ] || fail 'older paid status must never clear Cloud events before the activity API rollout'

rm -f "$RUNTIME/activity-sync-credential.json"
: > "$ACK_LOG"
: > "$CLEAR_LOG"
: > "$LICENSE_CALL_LOG"
write_outbox
if run_sync unknown >/dev/null 2>&1; then
  fail 'status responses with unknown entitlement must be retryable rather than treated as Free'
fi
[ -s "$OUTBOX" ] || fail 'unknown/partial status response must preserve Cloud events'
[ ! -s "$CLEAR_LOG" ] || fail 'unknown/partial status response must not clear the Cloud outbox'

rm -f "$RUNTIME/activity-sync-credential.json" "$RUNTIME/activity-sync.json"
: > "$ACK_LOG"
: > "$CLEAR_LOG"
: > "$LICENSE_CALL_LOG"
write_outbox
if run_sync unavailable >/dev/null 2>&1; then
  fail 'unreachable Hub license status API must surface a retryable synchronization error'
fi
[ -s "$OUTBOX" ] || fail 'Hub status API communication failure must preserve Cloud events for a later retry'
[ ! -s "$CLEAR_LOG" ] || fail 'Hub status API communication failure must not clear the Cloud outbox'
jq -e '.lastErrorCode == "ACTIVITY_LICENSE_STATUS_FAILED" and .nextSyncAt == 1800000900' "$RUNTIME/activity-sync.json" >/dev/null || \
  fail 'first Cloud status failure must back off for 15 minutes instead of retrying after five minutes'
if run_sync unavailable >/dev/null 2>&1; then
  fail 'repeated unavailable Hub status must remain retryable'
fi
jq -e '.nextSyncAt == 1800001800' "$RUNTIME/activity-sync.json" >/dev/null || \
  fail 'second consecutive Cloud status failure must back off for 30 minutes'
if run_sync unavailable >/dev/null 2>&1; then
  fail 'third unavailable Hub status must remain retryable'
fi
jq -e '.nextSyncAt == 1800003600' "$RUNTIME/activity-sync.json" >/dev/null || \
  fail 'Cloud status retry backoff must grow to the one-hour cap'
if run_sync unavailable >/dev/null 2>&1; then
  fail 'capped unavailable Hub status must remain retryable'
fi
jq -e '.nextSyncAt == 1800003600' "$RUNTIME/activity-sync.json" >/dev/null || \
  fail 'Cloud status retry backoff must remain capped at one hour'

rm -f "$RUNTIME/activity-sync-credential.json"
: > "$ACK_LOG"
: > "$CLEAR_LOG"
: > "$LICENSE_CALL_LOG"
write_outbox
run_sync revoked || fail 'revoked paid activation must settle as ineligible without a daemon failure'
[ ! -s "$OUTBOX" ] || fail 'revoked paid activation must not retain a Cloud-only outbox indefinitely'
grep -Fq 'clear' "$CLEAR_LOG" || fail 'revoked paid activation must explicitly clear only the Cloud outbox'

rm -f "$RUNTIME/activity-sync-credential.json"
: > "$ACK_LOG"
: > "$CLEAR_LOG"
: > "$LICENSE_CALL_LOG"
write_outbox
run_sync free || fail 'ineligible activity sync must settle without a daemon failure'
[ ! -s "$OUTBOX" ] || fail 'Free/ineligible device must not retain a Cloud-only outbox indefinitely'
grep -Fq 'clear' "$CLEAR_LOG" || fail 'ineligible status must explicitly clear only the Cloud outbox'
jq -e '.phase == "ineligible" and .eligible == false and .pendingEvents == 0' "$RUNTIME/activity-sync.json" >/dev/null || \
  fail 'Free/ineligible synchronization state must be exposed to the router UI'

printf '%s\n' 'PASS: paid Cloud activity batching/ack, lightweight status credentials, rollout-safe retries, entitlement handling and direct-vs-observer event ownership are valid'
