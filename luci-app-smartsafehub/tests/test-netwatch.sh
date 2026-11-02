#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/root/usr/libexec/smartsafehub-netwatch"
COMMON="$ROOT/root/usr/lib/smartsafehub/common.sh"
PARSER="$ROOT/root/usr/lib/smartsafehub/netwatch.awk"
EVENTS_DAEMON="$ROOT/root/usr/libexec/smartsafehub-events"
RPC="$ROOT/root/usr/share/rpcd/ucode/smartsafehub.uc"
NETWATCH_RPC="$ROOT/root/usr/share/rpcd/ucode/smartsafehub/netwatch.uc"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -x "$HELPER" ] && [ -f "$PARSER" ] || fail 'Network Watch 실행 파일이 누락됨'
sh -n "$HELPER" || fail '실행 파일 POSIX 셸 오류'
mkdir -p "$TMP/bin" "$TMP/run"
cat > "$TMP/bin/uci" <<'SH'
#!/bin/sh
[ "$1" = '-q' ] && [ "$2" = 'get' ] || exit 1
[ "$3" = 'smartsafehub.netwatch.enabled' ] || exit 1
printf '%s\n' "${MOCK_ENABLED:-1}"
SH
cat > "$TMP/bin/date" <<'SH'
#!/bin/sh
[ "$1" = '+%s' ] || exit 1
printf '%s\n' "${MOCK_DATE:-1800000000}"
SH
cat > "$TMP/bin/event" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_EVENT_LOG"
SH
cat > "$TMP/bin/conntrack" <<'SH'
#!/bin/sh
[ "$1" = '-L' ] && [ "$2" = '-f' ] && [ "$3" = 'ipv4' ] || exit 1
cat "$MOCK_CONNTRACK_FILE"
SH
# Detect regressions even on hosts where flock happens to be installed.
cat > "$TMP/bin/flock" <<'SH'
#!/bin/sh
printf 'unexpected flock call\n' >> "$MOCK_FLOCK_LOG"
exit 127
SH
chmod +x "$TMP/bin/"*
export MOCK_FLOCK_LOG="$TMP/flock-calls.log"
export MOCK_EVENT_LOG="$TMP/events.log"
export MOCK_CONNTRACK_FILE="$TMP/source.txt"
: > "$MOCK_EVENT_LOG"
run() {
    SMARTSAFEHUB_NETWATCH_COMMON_LIB="$COMMON" \
    SMARTSAFEHUB_NETWATCH_RUNTIME_DIR="$TMP/run" \
    SMARTSAFEHUB_NETWATCH_PROC="${MOCK_SOURCE:-$MOCK_CONNTRACK_FILE}" \
    SMARTSAFEHUB_NETWATCH_PARSER="$PARSER" \
    SMARTSAFEHUB_NETWATCH_EVENTS="$TMP/bin/event" \
    SMARTSAFEHUB_NETWATCH_UCI="$TMP/bin/uci" \
    SMARTSAFEHUB_NETWATCH_DATE="$TMP/bin/date" \
    SMARTSAFEHUB_NETWATCH_CONNTRACK="$TMP/bin/conntrack" \
    PATH="$TMP/bin:$PATH" "$HELPER" sample
}

# Unrelated reverse flows and private LAN-to-LAN flows must be excluded.
cat > "$MOCK_CONNTRACK_FILE" <<'DATA'
ipv4 2 tcp 6 430 ESTABLISHED src=192.168.8.20 dst=8.8.8.8 sport=50000 dport=443 src=8.8.8.8 dst=192.168.8.20 sport=443 dport=50000 [ASSURED]
ipv4 2 tcp 6 430 ESTABLISHED src=8.8.8.8 dst=192.168.8.20 sport=443 dport=50000 src=192.168.8.20 dst=8.8.8.8 sport=50000 dport=443
ipv4 2 tcp 6 430 ESTABLISHED src=192.168.8.20 dst=192.168.8.1 sport=50000 dport=443
ipv6 2 tcp 6 430 ESTABLISHED src=fd00::2 dst=2001:4860:4860::8888 sport=50000 dport=443
DATA
run
jq -e '.phase=="ready" and .totalConnections==1 and .totalDevices==1 and .devices[0].ip=="192.168.8.20" and .devices[0].destinations==1 and .alert==null' "$TMP/run/status.json" >/dev/null || fail '사설→공인 IPv4만 정확히 관찰해야 함'
[ ! -s "$MOCK_EVENT_LOG" ] || fail '정상 통신에 오탐을 기록하면 안 됨'
[ ! -e "$MOCK_FLOCK_LOG" ] || fail 'flock 없는 기본 환경에서도 동작해야 함'
[ ! -e "$TMP/run/sample.lock.d" ] || fail '공통 잠금을 정상적으로 해제해야 함'
[ ! -e "$TMP/run/sample.lock" ] || fail '구버전 잠금을 새로 만들면 안 됨'

# A running shared-lock owner must never be preempted.
mkdir "$TMP/run/sample.lock.d"
printf '%s\n' "$$" > "$TMP/run/sample.lock.d/pid"
cp "$TMP/run/status.json" "$TMP/before-lock.json"
run
cmp -s "$TMP/before-lock.json" "$TMP/run/status.json" || fail '실행 중인 공통 잠금 상태를 덮어쓰면 안 됨'
[ "$(cat "$TMP/run/sample.lock.d/pid")" = "$$" ] || fail '공통 잠금의 현재 소유자를 보존해야 함'
rm -rf "$TMP/run/sample.lock.d"

# The shared library must recover a dead lock holder, including the legacy
# sample.lock.reclaim case that stalled the previous symlink implementation.
mkdir "$TMP/run/sample.lock.d"
printf '%s\n' '99999999' > "$TMP/run/sample.lock.d/pid"
mkdir "$TMP/run/sample.lock.reclaim"
ln -s 99999999 "$TMP/run/sample.lock"
run
[ ! -d "$TMP/run/sample.lock.d" ] || fail '공통 잠금의 죽은 소유자를 복구해야 함'
[ ! -e "$TMP/run/sample.lock" ] && [ ! -d "$TMP/run/sample.lock.reclaim" ] || fail '구버전 잔여 잠금도 정리해야 함'
jq -e '.phase=="ready" and .totalConnections==1' "$TMP/run/status.json" >/dev/null || fail '예전 reclaim 디렉터리가 있어도 수집되어야 함'

# Respect an active sampler from the previous release until it finishes.
rm -f "$TMP/run/sample.lock"
ln -s "$$" "$TMP/run/sample.lock"
cp "$TMP/run/status.json" "$TMP/before-lock.json"
run
cmp -s "$TMP/before-lock.json" "$TMP/run/status.json" || fail '구버전 실행 중인 관찰기를 방해하면 안 됨'
rm -f "$TMP/run/sample.lock"

# Interrupted runs may leave temporary files behind. Remove dead PID files,
# but never files owned by an active process.
printf stale > "$TMP/run/status.tmp.99999999"
printf stale > "$TMP/run/conntrack.tmp.99999999"
printf stale > "$TMP/run/conntrack-pid.tmp.99999999"
printf active > "$TMP/run/previous.tmp.$$"
run
[ ! -f "$TMP/run/status.tmp.99999999" ] || fail '죽은 작업의 status 임시 파일을 정리해야 함'
[ ! -f "$TMP/run/conntrack.tmp.99999999" ] || fail '죽은 작업의 conntrack 임시 파일을 정리해야 함'
[ ! -f "$TMP/run/conntrack-pid.tmp.99999999" ] || fail '죽은 작업의 conntrack PID 임시 파일을 정리해야 함'
[ -f "$TMP/run/previous.tmp.$$" ] || fail '실행 중인 프로세스의 임시 파일을 지우면 안 됨'
rm -f "$TMP/run/previous.tmp.$$"
[ ! -e "$MOCK_FLOCK_LOG" ] || fail '공통 잠금도 flock을 사용하면 안 됨'

# High counts need two consecutive scans; warning should be rate-limited.
: > "$MOCK_CONNTRACK_FILE"
i=1
while [ "$i" -le 125 ]; do
    printf 'ipv4 2 tcp 6 430 ESTABLISHED src=192.168.8.21 dst=8.8.4.4 sport=%s dport=443\n' "$((10000+i))" >> "$MOCK_CONNTRACK_FILE"
    i=$((i+1))
done
run
[ ! -s "$MOCK_EVENT_LOG" ] || fail '첫 관찰의 연결 급증에 바로 경보하면 안 됨'
run
[ "$(wc -l < "$MOCK_EVENT_LOG")" -eq 1 ] || fail '2회 연속 높은 연결 수에 한 번만 이벤트가 필요함'
jq -e '.alert.ip=="192.168.8.21" and .alert.connections==125 and .totalConnections==125' "$TMP/run/status.json" >/dev/null || fail '이상 연결 건수/기기가 올바르게 기록되어야 함'
grep -Fq 'network_watch.anomaly.warning warning' "$MOCK_EVENT_LOG" || fail '최근 활동 이벤트가 발행되어야 함'
run
[ "$(wc -l < "$MOCK_EVENT_LOG")" -eq 1 ] || fail '30분 안에는 중복 경보를 내지 않아야 함'
MOCK_DATE=1800001801 run
[ "$(wc -l < "$MOCK_EVENT_LOG")" -eq 2 ] || fail '30분 경과 시 재알림이 가능해야 함'

# Two different devices must not suppress one another for 30 minutes.
: > "$MOCK_CONNTRACK_FILE"
i=1
while [ "$i" -le 125 ]; do
    printf 'ipv4 2 tcp 6 430 ESTABLISHED src=192.168.8.21 dst=8.8.4.4 sport=%s dport=443\n' "$((10000+i))" >> "$MOCK_CONNTRACK_FILE"
    printf 'ipv4 2 tcp 6 430 ESTABLISHED src=192.168.8.23 dst=8.8.8.8 sport=%s dport=443\n' "$((10000+i))" >> "$MOCK_CONNTRACK_FILE"
    i=$((i+1))
done
MOCK_DATE=1800001802 run
MOCK_DATE=1800001802 run
[ "$(wc -l < "$MOCK_EVENT_LOG")" -eq 3 ] || fail '다른 기기는 기존 30분 제한과 독립적으로 경고해야 함'
grep -Fq '"source_ip":"192.168.8.23"' "$MOCK_EVENT_LOG" || fail '두 번째 기기의 경고 누락'
MOCK_DATE=1800001803 run
[ "$(wc -l < "$MOCK_EVENT_LOG")" -eq 3 ] || fail '각 기기의 30분 제한을 유지해야 함'
[ "$(wc -l < "$TMP/run/alerts.tsv")" -eq 2 ] || fail '기기별 경고 제한 상태를 저장해야 함'

# Restore a single high-count device for the fallback baseline checks.
: > "$MOCK_CONNTRACK_FILE"
i=1
while [ "$i" -le 125 ]; do
    printf 'ipv4 2 tcp 6 430 ESTABLISHED src=192.168.8.21 dst=8.8.4.4 sport=%s dport=443\n' "$((10000+i))" >> "$MOCK_CONNTRACK_FILE"
    i=$((i+1))
done

# Keep the disabled-mode fixture in a subshell: some /bin/sh variants retain
# assignments made before shell functions, which can pollute later tests.
(
    MOCK_ENABLED=0 run
    jq -e '.phase=="disabled" and .totalConnections==0' "$TMP/run/status.json" >/dev/null || fail '비활성 상태는 수집을 하지 않아야 함'
    [ ! -e "$TMP/run/previous.tsv" ] || fail '꺼진 뒤에는 이전 연결 기준선도 지워야 함'
)

# No procfs and no working conntrack must be reported, not a healthy empty snapshot.
cat > "$TMP/bin/conntrack" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$TMP/bin/conntrack"
# Force enabled=1 explicitly: the missing-source state must be independent
# of the preceding disabled-mode test even on macOS /bin/sh.
MOCK_ENABLED=1 MOCK_SOURCE="$TMP/no-proc" run
jq -e '.phase=="unavailable"' "$TMP/run/status.json" >/dev/null || \
    fail "소스를 읽을 수 없는 상황에서 정상으로 오인하면 안 됨 (실제 상태: $(cat "$TMP/run/status.json" 2>/dev/null || printf 'missing'))"

# A kernel without procfs can still read flows through the installed
# conntrack utility. The missing-source failure must have cleared baseline.
cat > "$TMP/bin/conntrack" <<'SH'
#!/bin/sh
[ "$1" = '-L' ] && [ "$2" = '-f' ] && [ "$3" = 'ipv4' ] || exit 1
cat "$MOCK_CONNTRACK_FILE"
SH
chmod +x "$TMP/bin/conntrack"
MOCK_ENABLED=1 MOCK_SOURCE="$TMP/no-proc" run
jq -e '.phase=="ready" and .totalConnections==125 and .alert==null' "$TMP/run/status.json" >/dev/null || fail 'procfs가 없어도 conntrack 명령으로 수집해야 함'
[ ! -e "$TMP/run/conntrack.tmp.$$" ] || fail '대체 조회의 임시 파일을 수집 후 남기면 안 됨'

# The userspace fallback must stop reading once the bounded parser input is
# full, rather than writing the entire unbounded conntrack dump to tmpfs.
# Ignore SIGPIPE to model a shell producer whose printf fails but whose loop
# continues; a consumer-side head alone is not a reliable stop mechanism.
cat > "$TMP/bin/conntrack" <<'SH'
#!/bin/sh
[ "$1" = '-L' ] && [ "$2" = '-f' ] && [ "$3" = 'ipv4' ] || exit 1
trap '' PIPE
i=0
while [ "$i" -lt 20000 ]; do
    i=$((i+1))
    printf 'ipv4 2 tcp 6 430 ESTABLISHED src=192.168.8.24 dst=8.8.8.8 sport=%s dport=443\n' "$i"
done
printf 'completed\n' > "$MOCK_FALLBACK_FINISHED"
SH
chmod +x "$TMP/bin/conntrack"
MOCK_FALLBACK_FINISHED="$TMP/producer-finished"; export MOCK_FALLBACK_FINISHED
MOCK_ENABLED=1 MOCK_SOURCE="$TMP/no-proc" run
jq -e '.phase=="ready" and .limited==true and .alert==null and .totalConnections<=2048' "$TMP/run/status.json" >/dev/null || fail 'conntrack 대체 조회에서 상한을 유지해야 함'
[ ! -e "$MOCK_FALLBACK_FINISHED" ] || fail '전체 20000개 연결을 끝까지 생성하면 안 됨'
[ ! -e "$TMP/run/conntrack.tmp.$$" ] || fail '대체 조회 후 파일 잔여물을 남기면 안 됨'

# Failed fallback must not silently become a valid empty snapshot.
cat > "$TMP/bin/conntrack" <<'SH'
#!/bin/sh
exit 7
SH
chmod +x "$TMP/bin/conntrack"
MOCK_SOURCE="$TMP/no-proc" run
jq -e '.phase=="unavailable"' "$TMP/run/status.json" >/dev/null || fail 'conntrack 실패를 정상 상태로 오인하면 안 됨'

# A stalled netlink reader must be terminated rather than hanging a worker.
cat > "$TMP/bin/conntrack" <<'SH'
#!/bin/sh
exec sleep 30
SH
chmod +x "$TMP/bin/conntrack"
MOCK_SOURCE="$TMP/no-proc" run
jq -e '.phase=="unavailable"' "$TMP/run/status.json" >/dev/null || fail '멈춘 conntrack 대체 조회를 제한 시간 후 중단해야 함'
[ ! -d "$TMP/run/sample.lock.d" ] || fail 'conntrack 시간 제한 후에도 공통 잠금을 해제해야 함'

# Restore the normal fixture for subsequent tests.
cat > "$TMP/bin/conntrack" <<'SH'
#!/bin/sh
[ "$1" = '-L' ] && [ "$2" = '-f' ] && [ "$3" = 'ipv4' ] || exit 1
cat "$MOCK_CONNTRACK_FILE"
SH
chmod +x "$TMP/bin/conntrack"

# Repeated contacts with 40 unique public destinations are only informational
# warning candidates, not evidence of a malware infection.
: > "$MOCK_CONNTRACK_FILE"
i=1
while [ "$i" -le 40 ]; do
    printf 'ipv4 2 udp 17 120 src=192.168.8.22 dst=8.8.1.%s sport=50000 dport=443\n' "$i" >> "$MOCK_CONNTRACK_FILE"
    i=$((i+1))
done
MOCK_DATE=1800003602 run
jq -e '.alert == null and .devices[0].destinations == 40' "$TMP/run/status.json" >/dev/null || fail '목적지 증가 첫 관찰은 경고하지 않아야 함'
MOCK_DATE=1800003602 run
jq -e '.alert.ip == "192.168.8.22" and .alert.destinations == 40' "$TMP/run/status.json" >/dev/null || fail '외부 목적지 수 증가를 2회 연속 확인해야 함'

# Explicitly cap large tables and avoid warnings on partial snapshots.
MOCK_SOURCE="$MOCK_CONNTRACK_FILE" run
: > "$MOCK_CONNTRACK_FILE"
i=1
while [ "$i" -le 2100 ]; do
    printf 'ipv4 2 tcp 6 430 ESTABLISHED src=192.168.8.21 dst=8.8.4.4 sport=%s dport=443\n' "$((10000+i))" >> "$MOCK_CONNTRACK_FILE"
    i=$((i+1))
done
MOCK_SOURCE="$MOCK_CONNTRACK_FILE" run
jq -e '.phase=="ready" and .limited==true and .alert==null and .totalConnections<=2048' "$TMP/run/status.json" >/dev/null || fail '연결 2048개 제한과 부분 관찰 안전성이 필요함'
[ ! -s "$TMP/run/previous.tsv" ] || fail '부분 관찰 결과를 다음 경고의 기준선으로 사용하면 안 됨'

# RPC/UI/demo and packaging contract.
grep -Fq 'ssh_lock_acquire' "$HELPER" || fail 'Network Watch는 공통 잠금 모듈을 사용해야 함'
grep -Fq 'netwatch_status:' "$RPC" || fail 'RPC 조회 누락'
grep -Fq 'netwatch_enabled_update:' "$RPC" || fail 'RPC 설정 누락'
grep -Fq "ctx.commit('smartsafehub')" "$NETWATCH_RPC" || fail 'UCI commit 누락'
grep -Fq 'NETWATCH_HELPER" sample' "$EVENTS_DAEMON" || fail '기존 이벤트 서비스 스케줄러와 연동 누락'
grep -Fq '+conntrack' "$ROOT/Makefile" || fail '25.12 procfs 대안의 패키지 의존성 누락'
grep -Fq 'smartsafehub.netwatch=netwatch' "$ROOT/Makefile" || fail '실시간 패키지 업그레이드 마이그레이션 누락'
grep -Fq 'uci -q set smartsafehub.netwatch=' "$ROOT/root/etc/uci-defaults/90-smartsafehub-system-defaults" || fail '펌웨어 업그레이드 마이그레이션 누락'
grep -Fq "'#netwatch': 'netwatch'" "$ROOT/frontend/src/hooks/useHashRoute.ts" || fail '화면 경로 누락'
grep -Fq "case 'netwatch':" "$ROOT/frontend/src/demo/main.tsx" || fail '데모 반영 누락'
grep -Fq "case 'network_watch.anomaly.warning':" "$ROOT/frontend/src/components/ActivityTimeline.tsx" || fail '최근 활동 표시 누락'
python3 -m json.tool "$ROOT/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json" >/dev/null || fail 'ACL JSON 문법 오류'
echo 'PASS: Network Watch collector/RPC/UI/demo/limits contract'
