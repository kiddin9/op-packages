#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Runtime configuration-transaction tests.
#
# These cover the pieces init.d/homeproxy-pro relies on so that a bad
# configuration cannot leave the router without a working service:
#
#   * the known-good copy recorded after a configuration passed check
#   * the fallback to that copy when a regeneration produces nothing
#   * the rollback after a reload that comes up unhealthy
#   * the health probe that decides whether a rollback is needed
#
# The helpers are pure shell on purpose (see scripts/runtime/), so this runs
# anywhere, without ucode, procd or a router.
#
# Usage: sh tests/runtime/test_config_transaction.sh <repo-root>

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
RUNTIME="$ROOT/root/etc/homeproxy-pro/scripts/runtime"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-runtime.XXXXXX")" || exit 1
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

if [ ! -f "$RUNTIME/config.sh" ] || [ ! -f "$RUNTIME/health.sh" ]; then
	echo "FAIL: runtime helpers are missing under $RUNTIME"
	exit 1
fi

# shellcheck source=/dev/null
. "$RUNTIME/config.sh"
# shellcheck source=/dev/null
. "$RUNTIME/health.sh"

LIVE="$WORK/run/sing-box-c.json"
GOOD="$WORK/run/known-good/sing-box-c.json"

echo "== config transaction =="

# Nothing generated yet and no fallback: unusable.
hp_ensure_live "$LIVE" "$GOOD"
expect "ensure_live: nothing usable" "$?" "2"

# A configuration that passed check becomes the known-good copy.
mkdir -p "$WORK/run"
printf 'v1\n' > "$LIVE"
hp_known_good "$LIVE" "$GOOD"
expect "known_good: recorded" "$?" "0"
expect "known_good: content" "$(cat "$GOOD")" "v1"

# Live file present -> ensure_live leaves it alone.
hp_ensure_live "$LIVE" "$GOOD"
expect "ensure_live: keeps the live file" "$?" "0"

# Generation failed and removed the live file -> restore the fallback.  This
# is the start-up path: without it a failed generation left the router with
# no configuration at all.
rm -f "$LIVE"
hp_ensure_live "$LIVE" "$GOOD"
expect "ensure_live: restores the fallback" "$?" "1"
expect "ensure_live: restored content" "$(cat "$LIVE")" "v1"

# A new configuration that passes check but is not yet proven: the fallback
# still holds the previous one.
printf 'v2\n' > "$LIVE"
hp_same_file "$LIVE" "$GOOD"
expect "same_file: different configs" "$?" "1"
hp_rollback "$LIVE" "$GOOD"
expect "rollback: applied" "$?" "0"
expect "rollback: previous content restored" "$(cat "$LIVE")" "v1"
hp_same_file "$LIVE" "$GOOD"
expect "same_file: identical configs" "$?" "0"

# Nothing to roll back to must be reported, not silently ignored.
rm -f "$GOOD"
hp_rollback "$LIVE" "$GOOD"
expect "rollback: refuses without a fallback" "$?" "1"
hp_same_file "$LIVE" "$GOOD"
expect "same_file: missing file is not equal" "$?" "1"

# hp_restore_known_good_uci: the snapshot written by hp_promote_known_good.
# The init.d/homeproxy-pro rollback path reads $GOOD_DIR/uci-snapshot.txt
# BEFORE stop;start, otherwise start_service installs the failing layer
# on top of the rolled-back sing-box bytes (review P1-3, 2026-09-28).
# The helper itself is a uci loop; we drive it with a stub `uci` so the
# test does not depend on the device's uci-tools.
echo "== UCI snapshot restore (review P1-3) =="

SNAP_DIR="$WORK/run/known-good"
mkdir -p "$SNAP_DIR"
SNAP="$SNAP_DIR/uci-snapshot.txt"
BIN="$WORK/bin"
mkdir -p "$BIN"
HP_TEST_UCI_OUT="$WORK/uci.out"
: > "$HP_TEST_UCI_OUT"
export HP_TEST_UCI_OUT

# Stub `uci` so the helper can be driven without real uci-tools.  The
# stub records every call into $HP_TEST_UCI_OUT (passed via env, not a
# shell variable: the helper launches uci as a child process and shell
# variables of the parent do not reach it).
write_uci_stub() {
	cat > "$BIN/uci" <<STUB
#!/bin/sh
echo "\$@" >> "\$HP_TEST_UCI_OUT"
exit 0
STUB
	chmod +x "$BIN/uci"
}

# No snapshot at all -> 1 (best-effort caller logs and moves on).
rm -f "$SNAP"
PATH="$BIN:$PATH" hp_restore_known_good_uci "$SNAP_DIR" >/dev/null 2>&1
expect "uci restore: missing snapshot returns 1" "$?" "1"

# Happy path: snapshot present, all keys applied, commit called.
# The snapshot format carries the UCI type, because `uci set` on a list option
# stores a string and the firewall validators then reject it (review
# 2026-09-29 review): lists are replayed
# with `uci delete` + `uci add_list`.
: > "$HP_TEST_UCI_OUT"
write_uci_stub
printf 'homeproxy-pro.config.proxy_mode=tproxy\n' > "$SNAP"
printf 'homeproxy-pro.config.routing_mode=bypass_mainland_china\n' >> "$SNAP"
printf 'homeproxy-pro.infra.self_mark=100\n' >> "$SNAP"
printf 'homeproxy-pro.infra.tun_name=singtun0\n' >> "$SNAP"
printf 'homeproxy-pro.infra.tun_addr4=172.16.0.1/30\n' >> "$SNAP"
printf 'list homeproxy-pro.control.lan_proxy_ipv4_ips=192.168.1.10,192.168.1.11\n' >> "$SNAP"
printf 'list homeproxy-pro.control.wan_proxy_ipv4_ips=\n' >> "$SNAP"
PATH="$BIN:$PATH" hp_restore_known_good_uci "$SNAP_DIR"
expect "uci restore: happy path returns 0" "$?" "0"
expect "uci restore: 5 scalars applied" \
	"$(grep -c '^set homeproxy-pro\.' "$HP_TEST_UCI_OUT")" "5"
expect "uci restore: proxy_mode applied" \
	"$(grep -c '^set homeproxy-pro.config.proxy_mode=tproxy$' "$HP_TEST_UCI_OUT")" "1"
# The phantom key that used to be in the snapshot: nothing reads
# `infra.tun_address`, and arch-guard guard 43 now fails if it comes back.
expect "uci restore: tun_addr4 applied (not the phantom tun_address)" \
	"$(grep -c '^set homeproxy-pro.infra.tun_addr4=172.16.0.1/30$' "$HP_TEST_UCI_OUT")" "1"
# A list must never go through `uci set`: that would store a string and
# ipv4_to_nftarr() would return null, silently dropping the ACL rule.
expect "uci restore: list is deleted before it is re-added" \
	"$(grep -c '^delete homeproxy-pro.control.lan_proxy_ipv4_ips$' "$HP_TEST_UCI_OUT")" "1"
expect "uci restore: list elements re-added one by one" \
	"$(grep -c '^add_list homeproxy-pro.control.lan_proxy_ipv4_ips=' "$HP_TEST_UCI_OUT")" "2"
expect "uci restore: first list element" \
	"$(grep -c '^add_list homeproxy-pro.control.lan_proxy_ipv4_ips=192.168.1.10$' "$HP_TEST_UCI_OUT")" "1"
expect "uci restore: second list element" \
	"$(grep -c '^add_list homeproxy-pro.control.lan_proxy_ipv4_ips=192.168.1.11$' "$HP_TEST_UCI_OUT")" "1"
expect "uci restore: no list key is ever passed to uci set" \
	"$(grep -c '^set list ' "$HP_TEST_UCI_OUT")" "0"
# An empty recorded list means "absent or empty": the delete is the whole
# operation, so a list the failing configuration added does not survive.
expect "uci restore: empty list still dropped" \
	"$(grep -c '^delete homeproxy-pro.control.wan_proxy_ipv4_ips$' "$HP_TEST_UCI_OUT")" "1"
expect "uci restore: empty list adds no element" \
	"$(grep -c '^add_list homeproxy-pro.control.wan_proxy_ipv4_ips=' "$HP_TEST_UCI_OUT")" "0"
expect "uci restore: commit homeproxy-pro called" \
	"$(grep -c 'commit homeproxy-pro$' "$HP_TEST_UCI_OUT")" "1"

# Empty file: no sets, no commit -> 1.
: > "$HP_TEST_UCI_OUT"
: > "$SNAP"
PATH="$BIN:$PATH" hp_restore_known_good_uci "$SNAP_DIR"
expect "uci restore: empty snapshot returns 1" "$?" "1"
expect "uci restore: empty snapshot writes no writes" \
	"$(wc -l < "$HP_TEST_UCI_OUT" | tr -d ' ')" "0"

# Blank lines are skipped.
: > "$HP_TEST_UCI_OUT"
printf '\n# comment\n' > "$SNAP"
printf 'homeproxy-pro.config.proxy_mode=redirect_tproxy\n' >> "$SNAP"
printf '\n\n' >> "$SNAP"
PATH="$BIN:$PATH" hp_restore_known_good_uci "$SNAP_DIR"
expect "uci restore: blank lines skipped returns 0" "$?" "0"
expect "uci restore: only the real key applied" \
	"$(grep -c 'homeproxy-pro\.' "$HP_TEST_UCI_OUT")" "1"

# uci set succeeds, uci commit fails -> helper returns 1, no commit.
cat > "$BIN/uci" <<STUB
#!/bin/sh
echo "\$@" >> "\$HP_TEST_UCI_OUT"
case "\$1" in
	set) exit 0 ;;
	commit) exit 1 ;;
esac
STUB
chmod +x "$BIN/uci"
: > "$HP_TEST_UCI_OUT"
printf 'homeproxy-pro.config.proxy_mode=tproxy\n' > "$SNAP"
PATH="$BIN:$PATH" hp_restore_known_good_uci "$SNAP_DIR"
expect "uci restore: failed commit returns 1" "$?" "1"
# The stub still echoes the failed command (it writes first, then exits
# non-zero), so what we really want to assert is "the helper did not
# commit *despite* calling uci commit" - check that no UCI_OUT line shows
# a successful commit pattern by looking at the helper's exit code: 1
# already says "no commit happened".  The grep here is a sanity probe
# for the stub itself, not the helper - leave it informational.
expect "uci restore: stub recorded the failed commit attempt" \
	"$(grep -c 'commit homeproxy-pro$' "$HP_TEST_UCI_OUT")" "1"

rm -f "$BIN/uci"
echo "== health probe =="

# Deterministic stubs so the probe's control flow is tested rather than the
# host's process table or a real service.
#
# The gate asks procd first (ubus + jsonfilter) and only falls back to a
# process scan when procd cannot be asked at all.  That order is the fix for
# the P0: with the process scan
# first, a STALE sing-box process left over from an earlier run kept answering
# "alive" while procd restarted a crashing instance, so a dead service was
# accepted and recorded as the new known-good.  The first case below pins
# exactly that.
BIN="$WORK/bin"
mkdir -p "$BIN"

# One sample == one ubus call, so the counter indexes the health pattern.
cat > "$BIN/ubus" <<'STUB'
#!/bin/sh
n=$(cat "$HP_FAKE_COUNTER" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$HP_FAKE_COUNTER"
echo 'procd-state'
STUB
cat > "$BIN/pgrep" <<'STUB'
#!/bin/sh
[ "${HP_FAKE_STALE_PROC:-0}" = "1" ] && exit 0
exit 1
STUB
cat > "$BIN/jsonfilter" <<'STUB'
#!/bin/sh
# HP_FAKE_PATTERN is a string of 1/0, one character per sample.
n=$(cat "$HP_FAKE_COUNTER" 2>/dev/null || echo 1)
[ "$n" -ge 1 ] || n=1
ch=$(printf '%s' "${HP_FAKE_PATTERN:-1}" | cut -c "$n")
[ -n "$ch" ] || ch=$(printf '%s' "${HP_FAKE_PATTERN:-1}" | cut -c 1)
up=no
[ "$ch" = "1" ] && up=yes
case "$*" in
*".instances["*)
	if [ "$up" = "yes" ]; then
		printf '{"running":true}\n'
	else
		printf '{"running":false,"exit_code":1}\n'
	fi
	;;
*"@.running"*) [ "$up" = "yes" ] && echo true || echo false ;;
*"@.exit_code"*) [ "$up" = "yes" ] || echo 1 ;;
esac
exit 0
STUB
cat > "$BIN/netstat" <<'STUB'
#!/bin/sh
echo "Proto Recv-Q Send-Q Local Address  Foreign Address  State  PID/Program name"
if [ "${HP_FAKE_NO_OWNER:-0}" = "1" ]; then
	printf 'tcp 0 0 :::%s :::* LISTEN\n' "${HP_FAKE_PORT:-5330}"
elif [ -n "${HP_FAKE_PORT:-}" ]; then
	printf 'tcp 0 0 :::%s :::* LISTEN 42/%s\n' "$HP_FAKE_PORT" "${HP_FAKE_PORT_OWNER:-sing-box}"
fi
exit 0
STUB
# The health budget is measured in samples, not wall-clock seconds; sleeping
# for real would make each case take the whole budget in seconds.
cat > "$BIN/sleep" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$BIN/pgrep" "$BIN/ubus" "$BIN/jsonfilter" "$BIN/netstat" "$BIN/sleep"
PATH="$BIN:$PATH"
export PATH

CFG="$WORK/run/sing-box-c.json"
: > "$CFG"
COUNTER="$WORK/sample-count"
HP_FAKE_COUNTER="$COUNTER"
export HP_FAKE_COUNTER

reset_samples() {
	echo 0 > "$COUNTER"
}

# 1. procd says down while a stale process still matches the scan.
HP_FAKE_PATTERN=0 HP_FAKE_STALE_PROC=1
export HP_FAKE_PATTERN HP_FAKE_STALE_PROC
reset_samples
hp_instance_running "sing-box-c" "$CFG"
expect "instance_running: a stale process does not override procd" "$?" "1"

# 2. procd says running and reports no failed exit code.
HP_FAKE_PATTERN=1 HP_FAKE_STALE_PROC=0
export HP_FAKE_PATTERN HP_FAKE_STALE_PROC
reset_samples
hp_instance_running "sing-box-c" "$CFG"
expect "instance_running: reports up" "$?" "0"

# 3. hp_wait_service needs the instance healthy for several CONSECUTIVE
#    samples: one lucky poll must not be enough (that is what let a
#    crash-restart loop pass the old gate).
HP_FAKE_PATTERN=101010
export HP_FAKE_PATTERN
reset_samples
hp_wait_service "sing-box-c" "$CFG" 6 3
expect "wait_service: alternating samples never reach the stability window" "$?" "1"

# 4. A bad sample early in the window resets the count, and a later healthy run
#    still succeeds.
HP_FAKE_PATTERN=110111
export HP_FAKE_PATTERN
reset_samples
hp_wait_service "sing-box-c" "$CFG" 6 3
expect "wait_service: recovers after a bad sample" "$?" "0"

# 5. Listener attribution.  "The port is in the listen table" is not enough: in
#    the failure this gate exists for, the port was listening but owned by the
#    process that had taken it.
HP_FAKE_PORT=5330 HP_FAKE_PORT_OWNER=sing-box
export HP_FAKE_PORT HP_FAKE_PORT_OWNER
hp_listener_owned "sing-box" 5330
expect "listener: owned by sing-box" "$?" "0"

HP_FAKE_PORT_OWNER=socat
export HP_FAKE_PORT_OWNER
hp_listener_owned "sing-box" 5330
expect "listener: listening but owned by another process fails" "$?" "1"

HP_FAKE_NO_OWNER=1
export HP_FAKE_NO_OWNER
hp_listener_owned "sing-box" 5330
expect "listener: no owner column is reported as unavailable" "$?" "2"
unset HP_FAKE_NO_OWNER

HP_FAKE_PORT=5330 HP_FAKE_PORT_OWNER=sing-box
export HP_FAKE_PORT HP_FAKE_PORT_OWNER
hp_listener_owned "sing-box" 5330 5399
expect "listener: a missing port fails" "$?" "1"

# 6. The whole sample: procd up and the listeners owned.
HP_FAKE_PATTERN=1
export HP_FAKE_PATTERN
reset_samples
hp_service_healthy "sing-box-c" "$CFG" 5330
expect "service_healthy: procd up and listeners owned" "$?" "0"

HP_FAKE_PORT_OWNER=socat
export HP_FAKE_PORT_OWNER
reset_samples
hp_service_healthy "sing-box-c" "$CFG" 5330
expect "service_healthy: procd up but the listener was taken by another process" "$?" "1"

# 7. hp_wait_instance is kept for compatibility.
HP_FAKE_PORT_OWNER=sing-box HP_FAKE_PATTERN=1
export HP_FAKE_PORT_OWNER HP_FAKE_PATTERN
reset_samples
hp_wait_instance "sing-box-c" "$CFG" 1
expect "wait_instance (compat): succeeds while running" "$?" "0"

HP_FAKE_PATTERN=0
export HP_FAKE_PATTERN
reset_samples
hp_wait_instance "sing-box-c" "$CFG" 1
expect "wait_instance (compat): times out when down" "$?" "1"

# --- hp_reload_is_noop -----------------------------------------------------
# The reload short circuit.  Every case below is a reason the reload must NOT
# be skipped, which is the direction that matters: a wrong skip reports success
# over a dead or half-installed proxy, while a needless reload only costs the
# eight seconds it was going to cost anyway.
#
# The comparison is live vs known-good.  It is NOT candidate vs live: the
# generator writes straight to the live path and hp_capture_candidate copies
# that same file afterwards, so those two are identical by construction and
# comparing them reports "unchanged" for every reload - including one that
# switched the main node.  That was a real defect, caught on the device; the
# case below pins the difference so it cannot come back.
#
# The helper reads the filesystem and ubus.  ubus is stubbed on PATH so the "is
# the instance running" question has an answer off-target; the absence of that
# stub is itself one of the cases, because an environment where the state
# cannot be established has to fall through to a real reload.
CONF="$WORK/noop"
GOOD="$WORK/noop-known-good"
mkdir -p "$CONF/candidate" "$GOOD"
printf 'running bytes\n' > "$CONF/sing-box-c.json"
printf 'running bytes\n' > "$GOOD/sing-box-c.json"
# The candidate is deliberately identical to the live file: that is what a
# preflight leaves behind, and comparing against it must NOT produce a no-op.
printf 'running bytes\n' > "$CONF/candidate/sing-box-c.json"

mkdir -p "$WORK/noop-bin"
cat > "$WORK/noop-bin/ubus" <<'EOF'
#!/bin/sh
# The service list reply, in the shape the helper greps for.
cat <<JSON
{"homeproxy-pro":{"instances":{"sing-box-c":{"running":true,"pid":1234}}}}
JSON
EOF
chmod +x "$WORK/noop-bin/ubus"
# shellcheck source=/dev/null
. "$RUNTIME/service.sh"

PATH="$WORK/noop-bin:$PATH"
export PATH

hp_reload_is_noop "$CONF" "$GOOD" 1 0
expect "reload_is_noop: live matches known-good, client running, no released intercept" "$?" "0"

# The configuration changed - the one case where a reload is genuinely needed.
# This is the case the candidate-based version got wrong: the candidate is
# updated in lockstep with the live file, so only known-good tells the truth.
printf 'switched node\n' > "$CONF/sing-box-c.json"
printf 'switched node\n' > "$CONF/candidate/sing-box-c.json"
hp_reload_is_noop "$CONF" "$GOOD" 1 0
expect "reload_is_noop: live differs from known-good still reloads" "$?" "1"
expect "reload_is_noop: ...even though candidate matches live byte for byte" \
	"$(cmp -s "$CONF/candidate/sing-box-c.json" "$CONF/sing-box-c.json" && echo same)" "same"
printf 'running bytes\n' > "$CONF/sing-box-c.json"

# No known-good copy: the side has never come up healthy, or this is a fresh
# install.  "Cannot prove it is a no-op" has to mean reload.
mv "$GOOD/sing-box-c.json" "$GOOD/staged"
hp_reload_is_noop "$CONF" "$GOOD" 1 0
expect "reload_is_noop: no known-good copy still reloads" "$?" "1"
mv "$GOOD/staged" "$GOOD/sing-box-c.json"

# The intercept layer was released: sing-box is up but the LAN is not proxied.
# Skipping here is the silent state hp_rearm_intercept exists to undo.
: > "$CONF/intercept-released"
hp_reload_is_noop "$CONF" "$GOOD" 1 0
expect "reload_is_noop: a released intercept layer still reloads" "$?" "1"
rm -f "$CONF/intercept-released"

# An empty live file is not a running configuration.
: > "$CONF/sing-box-c.json"
hp_reload_is_noop "$CONF" "$GOOD" 1 0
expect "reload_is_noop: an empty live file still reloads" "$?" "1"
printf 'running bytes\n' > "$CONF/sing-box-c.json"

# The instance is not running.  A live file left behind by a crashed process is
# not a service, and skipping the restart would report success over a dead
# proxy - so the answer has to come from the running state, not the file.
cat > "$WORK/noop-bin/ubus" <<'EOF'
#!/bin/sh
echo '{"homeproxy-pro":{"instances":{"sing-box-c":{"running":false}}}}'
EOF
chmod +x "$WORK/noop-bin/ubus"
hp_reload_is_noop "$CONF" "$GOOD" 1 0
expect "reload_is_noop: an instance that is not running still reloads" "$?" "1"

# And with no ubus at all the state cannot be established, which has to fall
# through to a real reload rather than guess.
cat > "$WORK/noop-bin/ubus" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$WORK/noop-bin/ubus"
hp_reload_is_noop "$CONF" "$GOOD" 1 0
expect "reload_is_noop: an unusable ubus still reloads" "$?" "1"

# A server side is judged on its own: a client-only no-op must not let a
# changed server configuration slip through, and an enabled server with no
# known-good copy is a change, not a no-op.
cat > "$WORK/noop-bin/ubus" <<'EOF'
#!/bin/sh
cat <<JSON
{"homeproxy-pro":{"instances":{"sing-box-c":{"running":true},"sing-box-s":{"running":true}}}}
JSON
EOF
chmod +x "$WORK/noop-bin/ubus"
printf 'server v1\n' > "$CONF/sing-box-s.json"
printf 'server v2\n' > "$GOOD/sing-box-s.json"
hp_reload_is_noop "$CONF" "$GOOD" 1 1
expect "reload_is_noop: a changed server side still reloads" "$?" "1"
printf 'server v1\n' > "$GOOD/sing-box-s.json"
hp_reload_is_noop "$CONF" "$GOOD" 1 1
expect "reload_is_noop: both sides matching known-good is a no-op" "$?" "0"
rm -f "$GOOD/sing-box-s.json"
hp_reload_is_noop "$CONF" "$GOOD" 1 1
expect "reload_is_noop: an enabled server with no known-good copy still reloads" "$?" "1"

printf '%d checks, %d failures\n' "$CHECKS" "$FAILURES"
exit $FAILED