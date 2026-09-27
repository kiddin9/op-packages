#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-health"
INIT_SCRIPT="$ROOT_DIR/root/etc/init.d/smartsafehub-health"
CONFIG="$ROOT_DIR/root/etc/config/smartsafehub"
HEALTH_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/health.uc"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
API="$ROOT_DIR/frontend/src/api/smartsafehub.ts"
HOOK="$ROOT_DIR/frontend/src/hooks/useHealth.ts"
SETTINGS_PAGE="$ROOT_DIR/frontend/src/pages/SettingsPage.tsx"
HEALTH_TYPES="$ROOT_DIR/frontend/src/types/health.ts"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$HELPER" "$INIT_SCRIPT" "$CONFIG" "$HEALTH_MODULE" "$RPC_ENTRY" "$ACL" "$API" "$HOOK" "$SETTINGS_PAGE" "$HEALTH_TYPES"; do
	[ -f "$file" ] || fail "Health 소스 파일이 없습니다: ${file#$ROOT_DIR/}"
done

sh -n "$HELPER" || fail 'Health helper가 POSIX shell 문법 검사를 통과해야 합니다.'
sh -n "$INIT_SCRIPT" || fail 'Health init script가 POSIX shell 문법 검사를 통과해야 합니다.'
if grep -Fq -- '-v load=' "$HELPER"; then
	fail 'GNU awk의 load 내장 이름을 -v 변수명으로 사용하면 안 됩니다.'
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin" "$TMP/runtime"
TAB="$(printf '\t')"

cat > "$TMP/bin/uci" <<'EOF_UCI'
#!/bin/sh
set -eu
STATE="${MOCK_UCI_STATE:?}"
[ -f "$STATE" ] || : > "$STATE"
if [ "${1:-}" = "-q" ]; then shift; fi
case "${1:-}" in
	get)
		key="${2:-}"
		value="$(awk -F '=' -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$STATE")"
		[ -n "$value" ] || exit 1
		printf '%s\n' "$value"
		;;
	set)
		assignment="${2:-}"
		key="${assignment%%=*}"
		value="${assignment#*=}"
		tmp="${STATE}.tmp"
		awk -F '=' -v key="$key" '$1 != key { print }' "$STATE" > "$tmp"
		printf '%s=%s\n' "$key" "$value" >> "$tmp"
		mv "$tmp" "$STATE"
		;;
	commit) exit 0 ;;
	*) exit 1 ;;
esac
EOF_UCI
chmod +x "$TMP/bin/uci"

cat > "$TMP/bin/jsonfilter" <<'EOF_JSONFILTER'
#!/bin/sh
set -eu
file=''
expression=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) file="$2"; shift 2 ;;
		-e) expression="$2"; shift 2 ;;
		*) shift ;;
	esac
done
jq_expression="$(printf '%s' "$expression" | sed 's/^@//')"
jq -r "($jq_expression) as \$value | if \$value == null then empty else \$value end" "$file"
EOF_JSONFILTER
chmod +x "$TMP/bin/jsonfilter"

cat > "$TMP/bin/ubus" <<'EOF_UBUS'
#!/bin/sh
set -eu
[ "${1:-}" = "call" ] || exit 1
case "${2:-}:${3:-}" in
	network.interface.wan:status)
		printf '{"up":%s}\n' "${MOCK_WAN_UP:-true}"
		;;
	safeshield:status)
		[ "${MOCK_SAFESHIELD_STATUS_EXIT:-0}" -eq 0 ] || exit "${MOCK_SAFESHIELD_STATUS_EXIT}"
		cat <<EOF_STATUS
{"enabled":${MOCK_SAFESHIELD_ENABLED:-true},"status":"${MOCK_SAFESHIELD_STATUS:-idle}","stage":"${MOCK_SAFESHIELD_STAGE:-}","runtime":{"dns_runtime_ok":${MOCK_DNS_RUNTIME_OK:-true},"last_error_code":"${MOCK_SAFESHIELD_ERROR:-}"},"blocklist":{"installed":${MOCK_BLOCKLIST_INSTALLED:-true}},"artifact":{"version":"${MOCK_SAFESHIELD_ARTIFACT_VERSION:-2026.09.21}","unique_domains":${MOCK_SAFESHIELD_DOMAIN_COUNT:-33818}},"timestamps":{"last_success":${MOCK_SAFESHIELD_LAST_SUCCESS:-0},"last_failure":${MOCK_SAFESHIELD_LAST_FAILURE:-0}},"license":{"configured":${MOCK_LICENSE_CONFIGURED:-true},"plan":"${MOCK_LICENSE_PLAN:-ULTIMATE}","status":"${MOCK_LICENSE_STATUS:-active}"}}
EOF_STATUS
		;;
	safeshield:license_get)
		printf '{"license":{"configured":true,"key":"%s"}}\n' "${MOCK_LICENSE_KEY:-secret-license-key}"
		;;
	*) exit 1 ;;
esac
EOF_UBUS
chmod +x "$TMP/bin/ubus"

cat > "$TMP/bin/df" <<'EOF_DF'
#!/bin/sh
cat <<EOF_OUTPUT
Filesystem           1024-blocks    Used Available Capacity Mounted on
/dev/mock                  100000   ${MOCK_STORAGE_USED:-20000}     80000  ${MOCK_STORAGE_PERCENT:-20}% /overlay
EOF_OUTPUT
EOF_DF
chmod +x "$TMP/bin/df"

cat > "$TMP/bin/dnsmasq-init" <<'EOF_DNSMASQ'
#!/bin/sh
[ "${1:-}" = "running" ] || exit 1

if [ -n "${MOCK_DNSMASQ_RUNNING_SEQUENCE:-}" ] && [ -n "${MOCK_DNSMASQ_CALL_STATE:-}" ]; then
	count=0
	[ ! -f "$MOCK_DNSMASQ_CALL_STATE" ] || count="$(cat "$MOCK_DNSMASQ_CALL_STATE" 2>/dev/null || printf '0')"
	case "$count" in ''|*[!0-9]*) count=0 ;; esac
	count=$((count + 1))
	printf '%s\n' "$count" > "$MOCK_DNSMASQ_CALL_STATE"
	result="$(printf '%s' "$MOCK_DNSMASQ_RUNNING_SEQUENCE" | cut -d, -f "$count")"
	[ -n "$result" ] || result="$(printf '%s' "$MOCK_DNSMASQ_RUNNING_SEQUENCE" | awk -F, '{ print $NF }')"
	[ "$result" = "1" ]
	exit $?
fi

[ "${MOCK_DNSMASQ_RUNNING:-1}" = "1" ]
EOF_DNSMASQ
chmod +x "$TMP/bin/dnsmasq-init"

cat > "$TMP/bin/sleep" <<'EOF_SLEEP'
#!/bin/sh
printf '%s\n' "${1:-}" >> "${MOCK_SLEEP_LOG:?}"
exit 0
EOF_SLEEP
chmod +x "$TMP/bin/sleep"

cat > "$TMP/bin/date" <<'EOF_DATE'
#!/bin/sh
[ "${1:-}" = "+%s" ] || exit 1
printf '%s\n' "${MOCK_EPOCH:-1800000000}"
EOF_DATE
chmod +x "$TMP/bin/date"

cat > "$TMP/bin/logger" <<'EOF_LOGGER'
#!/bin/sh
exit 0
EOF_LOGGER
chmod +x "$TMP/bin/logger"

cat > "$TMP/bin/events" <<'EOF_EVENTS'
#!/bin/sh
set -eu
printf '%s' "${1:-}" >> "${MOCK_EVENT_LOG:?}"
shift || true
for argument in "$@"; do
	printf '\t%s' "$argument" >> "$MOCK_EVENT_LOG"
done
printf '\n' >> "$MOCK_EVENT_LOG"
EOF_EVENTS
chmod +x "$TMP/bin/events"

cat > "$TMP/bin/uclient-fetch" <<'EOF_FETCH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${MOCK_FETCH_ARGS:?}"
body=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		--body-file=*) body="${1#*=}"; shift ;;
		--body-file) body="$2"; shift 2 ;;
		*) shift ;;
	esac
done
[ -n "$body" ] || exit 1
printf '%s\n' '---' >> "${MOCK_FETCH_BODIES:?}"
cat "$body" >> "${MOCK_FETCH_BODIES:?}"
printf '\n' >> "${MOCK_FETCH_BODIES:?}"
exit "${MOCK_FETCH_EXIT:-0}"
EOF_FETCH
chmod +x "$TMP/bin/uclient-fetch"

MEMINFO="$TMP/meminfo"
LOADAVG="$TMP/loadavg"
CPUINFO="$TMP/cpuinfo"
UPTIME="$TMP/uptime"
UCI_STATE="$TMP/uci.state"
FETCH_ARGS="$TMP/fetch.args"
FETCH_BODIES="$TMP/fetch.bodies"
HEALTH_FILE="$TMP/runtime/health.json"
REPORT_STATE="$TMP/runtime/health-reporter.state"
UPDATER_STATE="$TMP/runtime/updates.state"
FIRMWARE_STATE="$TMP/runtime/firmware.state"
EVENT_LOG="$TMP/events.log"
EVENT_STATE="$TMP/runtime/activity-observer.state"
DNSMASQ_CALL_STATE="$TMP/runtime/dnsmasq-running.calls"
SLEEP_LOG="$TMP/runtime/sleep.log"
: > "$FETCH_ARGS"
: > "$FETCH_BODIES"
: > "$EVENT_LOG"
: > "$SLEEP_LOG"
printf 'MemTotal:       100000 kB\nMemAvailable:    50000 kB\n' > "$MEMINFO"
printf '0.10 0.05 0.01 1/100 100\n' > "$LOADAVG"
printf 'processor\t: 0\nprocessor\t: 1\n' > "$CPUINFO"
printf '300.00 100.00\n' > "$UPTIME"
printf 'phase\tidle\n' > "$UPDATER_STATE"
printf 'phase\tidle\n' > "$FIRMWARE_STATE"
cat > "$UCI_STATE" <<'EOF_CONFIG'
smartsafehub.health.check_interval_s=300
smartsafehub.health.startup_grace_s=120
smartsafehub.health.reporter_enabled=0
smartsafehub.health.report_interval_s=1800
smartsafehub.health.api_base_url=https://www.smartsafehub.com/api/v1
EOF_CONFIG

run_health() {
	MOCK_UCI_STATE="$UCI_STATE" \
	MOCK_FETCH_ARGS="$FETCH_ARGS" \
	MOCK_LICENSE_PLAN="${MOCK_LICENSE_PLAN:-ULTIMATE}" \
	MOCK_LICENSE_STATUS="${MOCK_LICENSE_STATUS:-active}" \
	MOCK_LICENSE_CONFIGURED="${MOCK_LICENSE_CONFIGURED:-true}" \
	MOCK_LICENSE_KEY="${MOCK_LICENSE_KEY:-secret-license-key}" \
	MOCK_WAN_UP="${MOCK_WAN_UP:-true}" \
	MOCK_DNSMASQ_RUNNING="${MOCK_DNSMASQ_RUNNING:-1}" \
	MOCK_DNSMASQ_RUNNING_SEQUENCE="${MOCK_DNSMASQ_RUNNING_SEQUENCE:-}" \
	MOCK_DNSMASQ_CALL_STATE="$DNSMASQ_CALL_STATE" \
	MOCK_SLEEP_LOG="$SLEEP_LOG" \
	MOCK_SAFESHIELD_ENABLED="${MOCK_SAFESHIELD_ENABLED:-true}" \
	MOCK_SAFESHIELD_STATUS="${MOCK_SAFESHIELD_STATUS:-idle}" \
	MOCK_SAFESHIELD_STAGE="${MOCK_SAFESHIELD_STAGE:-}" \
	MOCK_SAFESHIELD_STATUS_EXIT="${MOCK_SAFESHIELD_STATUS_EXIT:-0}" \
	MOCK_DNS_RUNTIME_OK="${MOCK_DNS_RUNTIME_OK:-true}" \
	MOCK_BLOCKLIST_INSTALLED="${MOCK_BLOCKLIST_INSTALLED:-true}" \
	MOCK_SAFESHIELD_ERROR="${MOCK_SAFESHIELD_ERROR:-}" \
	MOCK_SAFESHIELD_LAST_SUCCESS="${MOCK_SAFESHIELD_LAST_SUCCESS:-0}" \
	MOCK_SAFESHIELD_LAST_FAILURE="${MOCK_SAFESHIELD_LAST_FAILURE:-0}" \
	MOCK_SAFESHIELD_DOMAIN_COUNT="${MOCK_SAFESHIELD_DOMAIN_COUNT:-33818}" \
	MOCK_SAFESHIELD_ARTIFACT_VERSION="${MOCK_SAFESHIELD_ARTIFACT_VERSION:-2026.09.21}" \
	MOCK_EVENT_LOG="$EVENT_LOG" \
	MOCK_EPOCH="${MOCK_EPOCH:-1800000000}" \
	MOCK_FETCH_BODIES="$FETCH_BODIES" \
	MOCK_FETCH_EXIT="${MOCK_FETCH_EXIT:-0}" \
	SMARTSAFEHUB_HEALTH_RUNTIME_DIR="$TMP/runtime" \
	SMARTSAFEHUB_HEALTH_FILE="$HEALTH_FILE" \
	SMARTSAFEHUB_HEALTH_REPORT_STATE_FILE="$REPORT_STATE" \
	SMARTSAFEHUB_HEALTH_MEMINFO_FILE="$MEMINFO" \
	SMARTSAFEHUB_HEALTH_LOADAVG_FILE="$LOADAVG" \
	SMARTSAFEHUB_HEALTH_CPUINFO_FILE="$CPUINFO" \
	SMARTSAFEHUB_HEALTH_UPTIME_FILE="$UPTIME" \
	SMARTSAFEHUB_HEALTH_UPDATER_STATE_FILE="$UPDATER_STATE" \
	SMARTSAFEHUB_HEALTH_FIRMWARE_STATE_FILE="$FIRMWARE_STATE" \
	SMARTSAFEHUB_HEALTH_DNSMASQ_INIT="$TMP/bin/dnsmasq-init" \
	SMARTSAFEHUB_HEALTH_SLEEP_BIN="$TMP/bin/sleep" \
	SMARTSAFEHUB_HEALTH_DNSMASQ_CONFIRM_ATTEMPTS="${MOCK_DNSMASQ_CONFIRM_ATTEMPTS:-3}" \
	SMARTSAFEHUB_HEALTH_DNSMASQ_CONFIRM_INTERVAL_S="${MOCK_DNSMASQ_CONFIRM_INTERVAL_S:-2}" \
	SMARTSAFEHUB_HEALTH_UCI_BIN="$TMP/bin/uci" \
	SMARTSAFEHUB_HEALTH_UBUS_BIN="$TMP/bin/ubus" \
	SMARTSAFEHUB_HEALTH_JSONFILTER_BIN="$TMP/bin/jsonfilter" \
	SMARTSAFEHUB_HEALTH_UCLIENT_FETCH_BIN="$TMP/bin/uclient-fetch" \
	SMARTSAFEHUB_HEALTH_DF_BIN="$TMP/bin/df" \
	SMARTSAFEHUB_HEALTH_DATE_BIN="$TMP/bin/date" \
	SMARTSAFEHUB_HEALTH_LOGGER_BIN="$TMP/bin/logger" \
	SMARTSAFEHUB_HEALTH_EVENTS_BIN="$TMP/bin/events" \
	SMARTSAFEHUB_HEALTH_EVENT_STATE_FILE="$EVENT_STATE" \
	PATH="$TMP/bin:$PATH" \
	"$HELPER" "$@"
}

run_health_case() (
	# Keep each scenario deterministic across /bin/sh implementations. Some shells
	# differ in how temporary VAR=value assignments around shell functions are
	# restored, so never let one mock scenario leak into the next one.
	MOCK_LICENSE_PLAN=ULTIMATE
	MOCK_LICENSE_STATUS=active
	MOCK_LICENSE_CONFIGURED=true
	MOCK_LICENSE_KEY=secret-license-key
	MOCK_WAN_UP=true
	MOCK_DNSMASQ_RUNNING=1
	MOCK_DNSMASQ_RUNNING_SEQUENCE=''
	MOCK_DNSMASQ_CONFIRM_ATTEMPTS=3
	MOCK_DNSMASQ_CONFIRM_INTERVAL_S=2
	MOCK_SAFESHIELD_ENABLED=true
	MOCK_SAFESHIELD_STATUS=idle
	MOCK_SAFESHIELD_STAGE=''
	MOCK_SAFESHIELD_STATUS_EXIT=0
	MOCK_DNS_RUNTIME_OK=true
	MOCK_BLOCKLIST_INSTALLED=true
	MOCK_SAFESHIELD_ERROR=''
	MOCK_SAFESHIELD_LAST_SUCCESS=0
	MOCK_SAFESHIELD_LAST_FAILURE=0
	MOCK_SAFESHIELD_DOMAIN_COUNT=33818
	MOCK_SAFESHIELD_ARTIFACT_VERSION=2026.09.21
	MOCK_EPOCH=1800000000
	MOCK_FETCH_EXIT=0
	export MOCK_LICENSE_PLAN MOCK_LICENSE_STATUS MOCK_LICENSE_CONFIGURED MOCK_LICENSE_KEY
	export MOCK_WAN_UP MOCK_DNSMASQ_RUNNING MOCK_DNSMASQ_RUNNING_SEQUENCE MOCK_DNSMASQ_CONFIRM_ATTEMPTS MOCK_DNSMASQ_CONFIRM_INTERVAL_S
	export MOCK_SAFESHIELD_ENABLED MOCK_SAFESHIELD_STATUS MOCK_SAFESHIELD_STAGE
	export MOCK_SAFESHIELD_STATUS_EXIT MOCK_DNS_RUNTIME_OK MOCK_BLOCKLIST_INSTALLED MOCK_SAFESHIELD_ERROR
	export MOCK_SAFESHIELD_LAST_SUCCESS MOCK_SAFESHIELD_LAST_FAILURE MOCK_SAFESHIELD_DOMAIN_COUNT MOCK_SAFESHIELD_ARTIFACT_VERSION
	export MOCK_EPOCH MOCK_FETCH_EXIT

	while [ "$#" -gt 0 ] && [ "$1" != '--' ]; do
		case "$1" in
			MOCK_*=*) export "$1" ;;
			*) fail "Health test mock override 형식이 올바르지 않습니다: $1" ;;
		esac
		shift
	done
	[ "${1:-}" = '--' ] || fail 'Health test case에는 -- 뒤에 helper 명령이 필요합니다.'
	shift
	[ "$#" -gt 0 ] || fail 'Health test case helper 명령이 비어 있습니다.'
	run_health "$@"
)

# 무료/유료 여부와 관계없이 로컬 진단은 동작하고 기본 원격 보고는 꺼져 있어야 한다.
run_health_case MOCK_LICENSE_PLAN=FREE MOCK_LICENSE_STATUS=active -- run-once
jq -e '.schema == 1 and .overall == "ok" and .summary.total >= 8' "$HEALTH_FILE" >/dev/null || \
	fail '정상 장치의 로컬 진단은 schema v1과 ok 상태를 생성해야 합니다.'
grep -Eq '^enabled[[:space:]]+0$' "$REPORT_STATE" || fail '원격 상태 보고는 opt-in 방식이며 기본값이 OFF여야 합니다.'
[ ! -s "$FETCH_ARGS" ] || fail '로컬 전용 진단은 서버 요청을 보내면 안 됩니다.'

# dnsmasq의 짧은 reload/restart 공백은 재확인으로 흡수하고, 연속 실패만 실제 장애로 판정한다.
rm -f "$DNSMASQ_CALL_STATE" "$EVENT_STATE"
: > "$SLEEP_LOG"
: > "$EVENT_LOG"
run_health_case MOCK_DNSMASQ_RUNNING_SEQUENCE=0,1 -- run-once
jq -e '.overall == "ok" and any(.checks[]; .id == "service.dnsmasq" and .status == "ok")' "$HEALTH_FILE" >/dev/null || \
	fail 'dnsmasq가 첫 확인 뒤 바로 복구되면 transient reload를 critical로 기록하면 안 됩니다.'
[ "$(cat "$DNSMASQ_CALL_STATE")" -eq 2 ] || fail 'dnsmasq transient 복구는 두 번째 확인에서 종료해야 합니다.'
[ "$(wc -l < "$SLEEP_LOG" | tr -d ' ')" -eq 1 ] || fail 'dnsmasq transient 복구는 재확인 전 한 번만 대기해야 합니다.'
[ ! -s "$EVENT_LOG" ] || fail 'dnsmasq transient 복구는 Health activity event를 만들면 안 됩니다.'

rm -f "$DNSMASQ_CALL_STATE"
: > "$SLEEP_LOG"
run_health_case MOCK_DNSMASQ_RUNNING_SEQUENCE=0,0,0 -- run-once
jq -e '.overall == "critical" and any(.checks[]; .id == "service.dnsmasq" and .code == "DNSMASQ_UNAVAILABLE" and .status == "critical")' "$HEALTH_FILE" >/dev/null || \
	fail 'dnsmasq가 3회 연속 확인에서 실행되지 않으면 실제 critical 장애로 판정해야 합니다.'
[ "$(cat "$DNSMASQ_CALL_STATE")" -eq 3 ] || fail 'dnsmasq 지속 장애는 설정된 3회 확인을 모두 수행해야 합니다.'
[ "$(wc -l < "$SLEEP_LOG" | tr -d ' ')" -eq 2 ] || fail 'dnsmasq 3회 확인 사이에는 두 번의 짧은 대기가 있어야 합니다.'
grep -Fq "emit${TAB}health${TAB}health.issue.started${TAB}error" "$EVENT_LOG" || \
	fail 'dnsmasq 지속 장애는 baseline 이후 health.issue.started event를 기록해야 합니다.'
grep -Fq 'DNSMASQ_UNAVAILABLE:critical' "$EVENT_LOG" || \
	fail 'dnsmasq 지속 장애 event metadata에는 실제 issue fingerprint가 포함되어야 합니다.'

# 이후 활동 기록 observer 시나리오는 dnsmasq 확인 상태와 무관하게 독립적으로 검증한다.
rm -f "$DNSMASQ_CALL_STATE" "$EVENT_STATE"
: > "$SLEEP_LOG"
: > "$EVENT_LOG"

# 활동 기록 observer는 첫 관측을 baseline으로만 저장하고 실제 상태 전이에만 event를 기록한다.
rm -f "$EVENT_STATE"
: > "$EVENT_LOG"
run_health_case MOCK_EPOCH=1800001000 MOCK_WAN_UP=true MOCK_SAFESHIELD_LAST_SUCCESS=1800000900 -- run-once
[ ! -s "$EVENT_LOG" ] || fail '첫 Health 관측은 기존 상태를 새 사건으로 오인하면 안 됩니다.'
run_health_case MOCK_EPOCH=1800001100 MOCK_WAN_UP=false MOCK_SAFESHIELD_LAST_SUCCESS=1800000900 -- run-once
grep -Fq "emit${TAB}network${TAB}network.internet.disconnected${TAB}error" "$EVENT_LOG" || \
	fail 'WAN up→down 전이에서 인터넷 연결 끊김 event를 한 번 기록해야 합니다.'
before_event_lines="$(wc -l < "$EVENT_LOG" | tr -d ' ')"
run_health_case MOCK_EPOCH=1800001150 MOCK_WAN_UP=false MOCK_SAFESHIELD_LAST_SUCCESS=1800000900 -- run-once
after_event_lines="$(wc -l < "$EVENT_LOG" | tr -d ' ')"
[ "$before_event_lines" -eq "$after_event_lines" ] || fail 'WAN down 상태의 반복 polling이 중복 event를 만들면 안 됩니다.'
run_health_case MOCK_EPOCH=1800001200 MOCK_WAN_UP=true MOCK_SAFESHIELD_LAST_SUCCESS=1800001190 MOCK_SAFESHIELD_DOMAIN_COUNT=34001 -- run-once
grep -Fq 'network.internet.recovered' "$EVENT_LOG" || fail 'WAN down→up 전이에서 복구 event를 기록해야 합니다.'
grep -Fq '"downtime_seconds":100' "$EVENT_LOG" || fail '인터넷 복구 event에는 관측된 중단 시간을 metadata로 기록해야 합니다.'
grep -Fq '"origin":"observer"' "$EVENT_LOG" || fail 'Health 상태 전이 event는 observer origin을 기록해야 합니다.'
if grep -Fq 'safeshield.blocklist.' "$EVENT_LOG" || grep -Fq 'safeshield.protection.' "$EVENT_LOG"; then
	fail 'Health observer는 SafeShield 명시적 mutation/refresh event를 생성하면 안 됩니다.'
fi

# 이후 Health 진단 시나리오는 event observer 상태와 무관하게 독립적으로 검증한다.
rm -f "$EVENT_STATE"
: > "$EVENT_LOG"

# 부팅 직후 SafeShield 첫 갱신은 장애로 기록하지 않고 준비 중 상태로 표시한다.
printf '30.00 10.00\n' > "$UPTIME"
run_health_case MOCK_LICENSE_PLAN=FREE MOCK_LICENSE_STATUS=active \
	MOCK_SAFESHIELD_STATUS=running MOCK_SAFESHIELD_STAGE=boot_refresh \
	MOCK_DNS_RUNTIME_OK=false MOCK_BLOCKLIST_INSTALLED=false -- run-once
jq -e '.overall == "initializing" and .summary.warning == 0 and .summary.critical == 0 and any(.checks[]; .id == "safeshield.runtime" and .status == "initializing" and .code == "SAFESHIELD_INITIALIZING")' "$HEALTH_FILE" >/dev/null || \
	fail '부팅 grace 동안 SafeShield 첫 갱신은 warning/critical이 아니라 준비 중으로 진단해야 합니다.'

# Grace가 끝났는데도 차단 목록이 준비되지 않으면 정상적인 이상 판정으로 승격한다.
printf '121.00 20.00\n' > "$UPTIME"
run_health_case MOCK_LICENSE_PLAN=FREE MOCK_LICENSE_STATUS=active \
	MOCK_SAFESHIELD_STATUS=running MOCK_SAFESHIELD_STAGE=boot_refresh \
	MOCK_DNS_RUNTIME_OK=true MOCK_BLOCKLIST_INSTALLED=false -- run-once
jq -e '.overall == "warning" and any(.checks[]; .code == "SAFESHIELD_BLOCKLIST_MISSING" and .status == "warning")' "$HEALTH_FILE" >/dev/null || \
	fail '부팅 grace가 끝난 뒤에도 차단 목록이 없으면 실제 주의 상태로 승격해야 합니다.'
# SafeShield ubus 객체 자체가 아직 올라오지 않은 경우도 grace 동안은 준비 중으로 취급한다.
printf '45.00 10.00\n' > "$UPTIME"
run_health_case MOCK_LICENSE_PLAN=FREE MOCK_LICENSE_STATUS=active MOCK_SAFESHIELD_STATUS_EXIT=4 -- run-once
jq -e '.overall == "initializing" and any(.checks[]; .code == "SAFESHIELD_INITIALIZING" and .status == "initializing")' "$HEALTH_FILE" >/dev/null || \
	fail '부팅 grace 동안 SafeShield 상태 API가 아직 준비되지 않아도 transient 장애로 기록하면 안 됩니다.'
printf '121.00 20.00\n' > "$UPTIME"
run_health_case MOCK_LICENSE_PLAN=FREE MOCK_LICENSE_STATUS=active MOCK_SAFESHIELD_STATUS_EXIT=4 -- run-once
jq -e '.overall == "warning" and any(.checks[]; .code == "SAFESHIELD_STATUS_UNAVAILABLE" and .status == "warning")' "$HEALTH_FILE" >/dev/null || \
	fail '부팅 grace가 끝난 뒤에도 SafeShield 상태 API가 없으면 실제 주의 상태로 승격해야 합니다.'
printf '300.00 100.00\n' > "$UPTIME"

# 낮은 가용 메모리는 로컬에서 critical 이상으로 판정한다.
printf 'MemTotal:       100000 kB\nMemAvailable:     5000 kB\n' > "$MEMINFO"
run_health_case MOCK_LICENSE_PLAN=FREE MOCK_LICENSE_STATUS=active -- run-once
jq -e '.overall == "critical" and any(.checks[]; .code == "MEMORY_PRESSURE" and .status == "critical")' "$HEALTH_FILE" >/dev/null || \
	fail '가용 메모리가 매우 낮으면 critical 메모리 압박으로 진단해야 합니다.'

# FREE 사용자는 원격 상태 보고를 켤 수 없어야 한다.
set +e
run_health_case MOCK_LICENSE_PLAN=FREE MOCK_LICENSE_STATUS=active -- set-reporter 1
free_status=$?
set -e
[ "$free_status" -eq 3 ] || fail 'FREE 사용자가 원격 상태 보고를 활성화하려는 요청은 거부해야 합니다.'
grep -Eq '^smartsafehub.health.reporter_enabled=0$' "$UCI_STATE" || fail 'FREE 사용자의 opt-in 거부 후 Reporter는 비활성 상태를 유지해야 합니다.'

# 유료 active 사용자는 명시적으로 opt-in 할 수 있고, 첫 cycle에서 최소 상태 payload만 전송한다.
printf 'MemTotal:       100000 kB\nMemAvailable:    50000 kB\n' > "$MEMINFO"
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active -- set-reporter 1
grep -Eq '^smartsafehub.health.reporter_enabled=1$' "$UCI_STATE" || fail '유료 사용자의 opt-in은 reporter_enabled=1로 저장해야 합니다.'
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active MOCK_EPOCH=1800000000 -- run-cycle
[ "$(wc -l < "$FETCH_ARGS" | tr -d ' ')" -eq 1 ] || fail '유료 사용자가 opt-in하면 첫 Health 보고를 전송해야 합니다.'

grep -Fq '/health/reports' "$FETCH_ARGS" || fail 'Health Reporter는 전용 Health 보고 endpoint를 사용해야 합니다.'
grep -Fq 'X-SafeShield-License-Key: secret-license-key' "$FETCH_ARGS" || fail 'Health Reporter는 등록된 SafeShield 라이선스로 인증해야 합니다.'

# 부팅 grace의 준비 중 상태는 서버 장애 이력에 transient issue를 만들지 않도록 보고를 보류한다.
printf '30.00 10.00\n' > "$UPTIME"
before_startup_report="$(wc -l < "$FETCH_ARGS" | tr -d ' ')"
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active MOCK_EPOCH=1800000030 \
	MOCK_SAFESHIELD_STATUS=running MOCK_SAFESHIELD_STAGE=boot_refresh \
	MOCK_DNS_RUNTIME_OK=false MOCK_BLOCKLIST_INSTALLED=false -- run-cycle
after_startup_report="$(wc -l < "$FETCH_ARGS" | tr -d ' ')"
[ "$before_startup_report" -eq "$after_startup_report" ] || fail 'SafeShield 준비 중 상태는 원격 Health 보고를 보내면 안 됩니다.'
grep -Eq '^last_result[[:space:]]+initializing$' "$REPORT_STATE" || fail 'Reporter 상태에 SafeShield 초기화 대기를 기록해야 합니다.'
printf '300.00 100.00\n' > "$UPTIME"
for forbidden in hostname wan_ip ipv4Address ssid mac dns_query logs password license_key secret-license-key; do
	if grep -Fiq "$forbidden" "$FETCH_BODIES"; then
		fail "Health 보고 payload에 개인정보 필드/값이 포함되면 안 됩니다: $forbidden"
	fi
done
jq -e '.schema == 1 and has("metrics") and has("issues") and (has("device") | not) and (has("wifi") | not)' \
	"$(awk 'BEGIN{p=0} /^---$/{p=1;next} p{print}' "$FETCH_BODIES" > "$TMP/last-report.json"; printf '%s' "$TMP/last-report.json")" >/dev/null || \
	fail 'Health 보고 payload는 개인정보를 최소화한 whitelist schema를 사용해야 합니다.'

# 같은 상태에서는 30분 주기 전까지 중복 보고하지 않는다.
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active MOCK_EPOCH=1800000060 -- run-cycle
[ "$(wc -l < "$FETCH_ARGS" | tr -d ' ')" -eq 1 ] || fail 'Health 상태가 바뀌지 않았으면 주기 전에는 중복 보고하면 안 됩니다.'

# 상태 fingerprint가 바뀌면 정기 주기 전이라도 한 번 즉시 보고한다.
printf 'MemTotal:       100000 kB\nMemAvailable:     5000 kB\n' > "$MEMINFO"
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active MOCK_EPOCH=1800000120 -- run-cycle
[ "$(wc -l < "$FETCH_ARGS" | tr -d ' ')" -eq 2 ] || fail 'Health 이상 상태가 바뀌면 즉시 한 번 보고해야 합니다.'

# 서버 전송이 실패하면 5분 backoff를 적용해 매 분 재시도하지 않는다.
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active MOCK_EPOCH=1800004000 MOCK_FETCH_EXIT=1 -- run-cycle
[ "$(wc -l < "$FETCH_ARGS" | tr -d ' ')" -eq 3 ] || fail '실패하는 Health 보고는 한 번의 업로드 시도만 수행해야 합니다.'
grep -Eq '^last_result[[:space:]]+failed$' "$REPORT_STATE" || fail 'Health 업로드 실패 상태를 로컬에 기록해야 합니다.'
grep -Eq '^next_retry_at[[:space:]]+1800004300$' "$REPORT_STATE" || fail 'Health 업로드 실패 후 5분 재시도 backoff를 예약해야 합니다.'
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active MOCK_EPOCH=1800004060 MOCK_FETCH_EXIT=0 -- run-cycle
[ "$(wc -l < "$FETCH_ARGS" | tr -d ' ')" -eq 3 ] || fail 'Health 업로드 실패 후 backoff 만료 전에는 재시도하면 안 됩니다.'
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active MOCK_EPOCH=1800004301 MOCK_FETCH_EXIT=0 -- run-cycle
[ "$(wc -l < "$FETCH_ARGS" | tr -d ' ')" -eq 4 ] || fail 'Health Reporter는 backoff가 만료되면 재시도해야 합니다.'

# 사용자가 끄면 설정이 즉시 OFF가 되고 그 이후 cycle에서는 네트워크 요청이 없어야 한다.
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active -- set-reporter 0
before="$(wc -l < "$FETCH_ARGS" | tr -d ' ')"
run_health_case MOCK_LICENSE_PLAN=ULTIMATE MOCK_LICENSE_STATUS=active MOCK_EPOCH=1800004000 -- run-cycle
after="$(wc -l < "$FETCH_ARGS" | tr -d ' ')"
[ "$before" -eq "$after" ] || fail '원격 상태 보고를 끄면 서버 요청을 보내면 안 됩니다.'
grep -Eq '^last_result[[:space:]]+disabled$' "$REPORT_STATE" || fail 'Reporter 비활성 상태를 로컬 상태에 명시해야 합니다.'

# rpcd handler는 다른 ubus 객체를 호출하는 health helper를 동기 실행하면 안 된다.
grep -Fq "HEALTH_HELPER + ' ' + action + ' >/dev/null 2>&1 </dev/null &'" "$HEALTH_MODULE" || \
	fail 'Health RPC는 helper를 분리된 프로세스로 시작해야 합니다.'
if grep -Fq "run_command([ HEALTH_HELPER, 'run-once' ]" "$HEALTH_MODULE"; then
	fail 'Health RPC는 중첩 ubus 호출을 수행하는 helper를 동기 실행하면 안 됩니다.'
fi

# RPC/UI 계약: 로컬 상태/실행 RPC와 Reporter 설정 변경 권한을 각각 검증한다.
for method in health_status; do
	jq -e --arg method "$method" '."luci-app-smartsafehub".read.ubus.smartsafehub | index($method) != null' "$ACL" >/dev/null || \
		fail "ACL이 읽기 RPC를 허용해야 합니다: $method"
done
for method in health_run health_reporter_update; do
	jq -e --arg method "$method" '."luci-app-smartsafehub".write.ubus.smartsafehub | index($method) != null' "$ACL" >/dev/null || \
		fail "ACL이 쓰기 RPC를 허용해야 합니다: $method"
done

grep -Fq "option reporter_enabled '0'" "$CONFIG" || fail 'UCI에서 원격 상태 보고 기본값은 OFF여야 합니다.'
grep -Fq "option check_interval_s '300'" "$CONFIG" || fail '로컬 Health 진단 기본 주기는 5분이어야 합니다.'
grep -Fq "option startup_grace_s '120'" "$CONFIG" || fail 'SafeShield 부팅 초기화 grace 기본값은 120초여야 합니다.'
grep -Fq "set smartsafehub.health.startup_grace_s='120'" "$INIT_SCRIPT" || fail 'Health 설정을 처음 만드는 장치에도 startup grace 기본값을 저장해야 합니다.'
grep -Fq 'last_check=0' "$HELPER" || fail 'SafeShield 준비 중에는 정규 5분 주기보다 빠른 daemon tick으로 다시 진단해야 합니다.'
grep -Fq "'initializing'" "$HEALTH_TYPES" || fail '프런트엔드 Health 타입이 초기화 중 상태를 지원해야 합니다.'
grep -Fq "label: '준비 중'" "$SETTINGS_PAGE" || fail '설정의 장치 진단이 초기화 중 상태를 준비 중으로 표시해야 합니다.'
grep -Fq "case 'initializing':" "$SETTINGS_PAGE" || fail 'Health Reporter UI가 초기화 대기 상태를 설명해야 합니다.'
grep -Fq "option report_interval_s '1800'" "$CONFIG" || fail 'Health Reporter heartbeat 기본 주기는 30분이어야 합니다.'
grep -Fq "fetchHealthStatus" "$API" || fail '프런트엔드 API가 로컬 Health 상태 조회를 제공해야 합니다.'
grep -Fq "updateHealthReporter" "$HOOK" || fail 'Health hook이 Reporter opt-in 변경을 제공해야 합니다.'
grep -Fq 'HEALTH_REPORTER_CONFIRM_DELAYS_MS' "$HOOK" || fail 'Reporter 토글 후 첫 서버 보고 결과를 빠르게 확인하는 짧은 polling 계약이 필요합니다.'
grep -Fq 'reporterMutationSequence' "$HOOK" || fail '연속 Reporter 토글의 이전 확인 작업이 최신 상태를 덮어쓰지 않도록 sequence guard가 필요합니다.'
grep -Fq "lastResult: enabled ? 'initializing' : 'disabled'" "$HOOK" || fail 'Reporter 토글은 RPC 완료 전에 사용자 입력 상태를 즉시 화면에 반영해야 합니다.'
grep -Fq 'resource.replaceData(previousData)' "$HOOK" || fail 'Reporter 설정 저장이 실패하면 optimistic UI를 이전 상태로 되돌려야 합니다.'
grep -Fq '원격 상태 보고가 켜져 있습니다.' "$SETTINGS_PAGE" || fail 'Reporter UI가 활성 상태를 명확한 문장으로 표시해야 합니다.'
grep -Fq "return '첫 보고 준비 중';" "$SETTINGS_PAGE" || fail '활성화 직후 stale disabled/never 상태를 꺼짐이 아니라 첫 보고 준비 중으로 표시해야 합니다.'
grep -Fq "return reporter.enabled ? '첫 보고 대기 중' : '보고 기록 없음';" "$SETTINGS_PAGE" || fail 'Reporter UI가 첫 서버 보고 전 상태를 명확하게 구분해야 합니다.'
grep -Fq '최근 전송 상태' "$SETTINGS_PAGE" || fail 'Reporter 결과는 토글 상태와 혼동되지 않도록 최근 전송 상태로 표시해야 합니다.'
grep -Fq '로컬 진단은 멤버십과 관계없이 사용할 수 있습니다.' "$SETTINGS_PAGE" || fail '설정 UI가 무료 로컬 진단을 설명해야 합니다.'
grep -Fq '기본값은 꺼짐이며 언제든지 다시 끌 수 있습니다.' "$SETTINGS_PAGE" || fail '설정 UI가 Reporter opt-in과 opt-out을 설명해야 합니다.'
grep -Fq '전송하지 않는 정보' "$SETTINGS_PAGE" || fail '설정 UI가 Health Reporter의 개인정보 제외 항목을 안내해야 합니다.'
grep -Fq "'@.license.key'" "$HELPER" || \
	fail 'Health Reporter는 SafeShield license_get의 실제 중첩 응답(.license.key)에서 라이선스 키를 읽어야 합니다.'

echo 'PASS: 무료 로컬 진단과 유료/Trial opt-in 원격 상태 보고 계약이 정상입니다.'
