#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Functional health probes (runtime/health.sh).
#
# The process/listener gate answers "is the instance up and does it own its
# ports?".  It cannot answer "does it actually serve?", and the probes that do
# are on the same code path a rollback is decided on - so the one property that
# must not regress is that they only *report* by default.  A probe that fails
# because the uplink is down, or because this target has no nslookup/nc, must
# never be able to fail the gate: a rollback loop is worse than the condition
# being probed for.
#
# `health_probe_strict` (UCI) is the opt-in that turns a probe failure into a
# gate failure.  "Cannot probe here" stays non-fatal even then - there is
# nothing to conclude from a missing tool.
#
# The probes take explicit ports and shell out to nslookup/nc, so this runs
# anywhere without ucode, procd or a router.
#
# Usage: sh tests/runtime/test_health_probe.sh <repo-root>

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
RUNTIME="$ROOT/root/etc/homeproxy/scripts/runtime"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-probes.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM

FAILED=0
CHECKS=0
FAILURES=0

expect() {
	# expect <name> <actual> <expected>
	CHECKS=$((CHECKS + 1))
	if [ "$2" = "$3" ]; then
		echo "PASS: $1"
	else
		echo "FAIL: $1 (expected '$3', got '$2')"
		FAILED=1
		FAILURES=$((FAILURES + 1))
	fi
}

if [ ! -f "$RUNTIME/health.sh" ]; then
	echo "FAIL: runtime/health.sh is missing under $RUNTIME"
	exit 1
fi

# log() comes from init.d on a router; the probes only call it to report, so
# the test records the lines and asserts on them.
PROBE_LOG="$WORK/probe.log"
: > "$PROBE_LOG"
log() { printf '%s\n' "$*" >> "$PROBE_LOG"; }

# shellcheck source=/dev/null
. "$RUNTIME/health.sh"

# --- stub PATH -------------------------------------------------------------
# The probes are written against `command -v nslookup` / `command -v nc`, so
# the sandbox decides what exists. Each stub's behaviour follows a marker file,
# which keeps the call sites readable.
BIN_OK="$WORK/bin-ok"
BIN_NONE="$WORK/bin-none"
mkdir -p "$BIN_OK" "$BIN_NONE"

cat > "$BIN_OK/nslookup" <<'EOF'
#!/bin/sh
[ -f "$HP_PROBE_STUB_DIR/dns_ok" ] || exit 1
exit 0
EOF
cat > "$BIN_OK/nc" <<'EOF'
#!/bin/sh
[ -f "$HP_PROBE_STUB_DIR/tcp_ok" ] || exit 1
exit 0
EOF
chmod +x "$BIN_OK/nslookup" "$BIN_OK/nc"

HP_PROBE_STUB_DIR="$WORK"
export HP_PROBE_STUB_DIR

PATH="$BIN_OK:$PATH"
export PATH

echo "== hp_probe_dns =="
: > "$WORK/dns_ok"
hp_probe_dns 5333 example.com
expect "dns: an answering inbound is 0" "$?" "0"

rm -f "$WORK/dns_ok"
hp_probe_dns 5333 example.com
expect "dns: a silent inbound is 1" "$?" "1"

hp_probe_dns "" example.com
expect "dns: no port means cannot-probe (2), not failure" "$?" "2"

echo "== hp_probe_tcp =="
: > "$WORK/tcp_ok"
hp_probe_tcp 5330
expect "tcp: an accepting listener is 0" "$?" "0"

rm -f "$WORK/tcp_ok"
hp_probe_tcp 5330
expect "tcp: a refusing listener is 1" "$?" "1"

hp_probe_tcp ""
expect "tcp: no port means cannot-probe (2), not failure" "$?" "2"

echo "== missing tooling is 'cannot probe', not 'failed' =="
# PATH is replaced, not prepended to: the host this runs on may well have its
# own nslookup/nc (macOS ships both), and a prepended empty directory would
# still find them behind `command -v`.
SAVED_PATH="$PATH"
PATH="$BIN_NONE"
hp_probe_dns 5333 example.com
rc_dns_missing=$?
hp_probe_tcp 5330
rc_tcp_missing=$?
PATH="$SAVED_PATH"
expect "dns: no nslookup is 2" "$rc_dns_missing" "2"
expect "tcp: no nc is 2" "$rc_tcp_missing" "2"
export PATH

echo "== hp_run_probes: reporting is the default =="
: > "$PROBE_LOG"
rm -f "$WORK/dns_ok" "$WORK/tcp_ok"
HP_PROBE_STRICT=0
export HP_PROBE_STRICT
hp_run_probes "client" 5333 5330
expect "reporting: both probes failing still returns 0" "$?" "0"
expect "reporting: the DNS failure is logged" \
	"$(grep -c 'the client DNS inbound (127.0.0.1:5333) did not answer' "$PROBE_LOG")" "1"
expect "reporting: the TCP failure is logged" \
	"$(grep -c 'nothing accepted a connection on the client mixed inbound (127.0.0.1:5330)' "$PROBE_LOG")" "1"

echo "== hp_run_probes: strict turns a failure into a gate failure =="
: > "$PROBE_LOG"
HP_PROBE_STRICT=1
export HP_PROBE_STRICT
hp_run_probes "client" 5333 5330
expect "strict: a failed probe returns 1" "$?" "1"
expect "strict: the strict path is named in the log" \
	"$(grep -c 'health_probe_strict is on' "$PROBE_LOG")" "1"

echo "== hp_run_probes: strict does not fire on a healthy service =="
: > "$WORK/dns_ok"
: > "$WORK/tcp_ok"
: > "$PROBE_LOG"
hp_run_probes "client" 5333 5330
expect "strict: a passing probe returns 0" "$?" "0"
expect "strict: a passing probe logs nothing" "$(wc -l < "$PROBE_LOG" | tr -d ' ')" "0"

echo "== hp_run_probes: 'cannot probe' never fails the gate =="
rm -f "$WORK/dns_ok" "$WORK/tcp_ok"
: > "$PROBE_LOG"
HP_PROBE_STRICT=1
export HP_PROBE_STRICT
PATH="$BIN_NONE"
hp_run_probes "client" 5333 5330
rc_no_tools=$?
PATH="$SAVED_PATH"
export PATH
expect "strict: a probe that cannot run still returns 0" "$rc_no_tools" "0"
expect "strict: the missing tooling is reported" \
	"$(grep -c 'cannot probe the client' "$PROBE_LOG")" "2"

echo "== hp_config_port_for_tag =="
# The generator writes one field per line (%.J); the sed in the helper also has
# to accept the compact shape, because a config that came from anywhere else
# (or a fixture) must not silently yield "no port" - that is how the probes
# would end up probing nothing at all.
cat > "$WORK/pretty.json" <<'EOF'
{
	"inbounds": [
		{
			"tag": "dns-in",
			"listen": "127.0.0.1",
			"listen_port": 5333
		},
		{
			"tag": "mixed-in",
			"listen": "::",
			"listen_port": 5330
		},
		{
			"tag": "tproxy-in",
			"listen_port": 5332
		}
	],
	"outbounds": [
		{
			"tag": "direct-out",
			"type": "direct"
		}
	]
}
EOF
cat > "$WORK/compact.json" <<'EOF'
{"inbounds":[{"tag":"dns-in","listen_port":5333},{"tag":"mixed-in","listen_port":5330}],"outbounds":[{"tag":"direct-out","type":"direct"}]}
EOF

expect "port_for_tag: dns-in from a pretty config" \
	"$(hp_config_port_for_tag "$WORK/pretty.json" 'dns-in')" "5333"
expect "port_for_tag: mixed-in from a pretty config" \
	"$(hp_config_port_for_tag "$WORK/pretty.json" 'mixed-in')" "5330"
expect "port_for_tag: a third inbound is not confused with the first" \
	"$(hp_config_port_for_tag "$WORK/pretty.json" 'tproxy-in')" "5332"
expect "port_for_tag: an outbound tag is not read as a listener" \
	"$(hp_config_port_for_tag "$WORK/pretty.json" 'direct-out')" ""
expect "port_for_tag: an absent tag yields nothing" \
	"$(hp_config_port_for_tag "$WORK/pretty.json" 'nope-in')" ""
expect "port_for_tag: compact JSON yields the same port" \
	"$(hp_config_port_for_tag "$WORK/compact.json" 'dns-in')" "5333"

expect "config_ports: both listeners are reported" \
	"$(hp_config_ports "$WORK/pretty.json" | tr '\n' ' ' | sed 's/ $//')" "5333 5330 5332"

printf '%d checks, %d failures\n' "$CHECKS" "$FAILURES"
[ "$FAILED" = 0 ] && echo "HEALTH PROBE TESTS PASSED"
exit "$FAILED"
