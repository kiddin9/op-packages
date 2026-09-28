#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/sbin/tailscale_policy_routing"
HOTPLUG="$ROOT_DIR/root/etc/hotplug.d/iface/98-tailscale-policy-routing"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [ -x "$1" ] || fail "missing executable: $1"; }
assert_contains() { grep -F -- "$1" "$2" >/dev/null || fail "$2 should contain: $1"; }
assert_not_contains() { grep -F -- "$1" "$2" >/dev/null && fail "$2 should not contain: $1" || true; }
assert_line_count() {
	expected="$1"
	needle="$2"
	file="$3"
	actual="$(grep -F -- "$needle" "$file" | wc -l | tr -d ' ')"
	[ "$actual" = "$expected" ] || fail "$file expected $expected occurrences of: $needle, got $actual"
}

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/uci" "$TMP_DIR/state"

cat >"$TMP_DIR/bin/uci" <<'SH'
#!/bin/sh
set -eu
state_dir="${UCI_STATE_DIR:?}"
[ "${1:-}" = '-q' ] && shift
command="${1:?}"
shift
key_file() { printf '%s/%s' "$state_dir" "$(printf '%s' "$1" | tr '/' '_')"; }
case "$command" in
	get)
		case "${1:?}" in
		mwan3.globals) printf '%s' 'globals' ;;
		mwan3.globals.mmx_mask)
			file="$(key_file "$1")"
			if [ -f "$file" ]; then
				cat "$file"
			else
				printf '%s' '0x3f00'
			fi
			;;
		*)
			file="$(key_file "$1")"
			[ -f "$file" ] || exit 1
			cat "$file"
			;;
		esac
	;;
set)
	assignment="${1:?}"
	key="${assignment%%=*}"
	value="${assignment#*=}"
	printf '%s' "$value" >"$(key_file "$key")"
	;;
delete)
	file="$(key_file "${1:?}")"
	rm -f "$file" "$file".*
	;;
commit)
	printf '%s\n' "${1:?}" >>"${UCI_LOG:?}"
	;;
*)
	exit 2
	;;
esac
SH
chmod +x "$TMP_DIR/bin/uci"

cat >"$TMP_DIR/bin/ip" <<'SH'
#!/bin/sh
set -eu
rules="${IP_RULES_FILE:?}"
routes="${IP_ROUTES_FILE:?}"
log="${IP_LOG:?}"
[ "${1:-}" = '-4' ] || exit 2
shift
case "$*" in
'rule show') cat "$rules" ;;
'route show table 52') cat "$routes" ;;
'rule add priority 1000 lookup 52')
	grep -q '^1000:' "$rules" && exit 2
	printf '%s\n' '1000: from all lookup 52' >>"$rules"
	printf '%s\n' 'add priority 1000 lookup 52' >>"$log"
	;;
'rule del priority 1000 lookup 52')
	[ "${IP_FAIL_DELETE:-0}" != 1 ] || exit 1
	tmp="$rules.tmp"
	grep -v '^1000: from all lookup 52$' "$rules" >"$tmp" || true
	mv "$tmp" "$rules"
	printf '%s\n' 'del priority 1000 lookup 52' >>"$log"
	;;
*) exit 2 ;;
esac
SH
chmod +x "$TMP_DIR/bin/ip"

cat >"$TMP_DIR/bin/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${LOGGER_LOG:?}"
SH
chmod +x "$TMP_DIR/bin/logger"

cat >"$TMP_DIR/bin/flock" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP_DIR/bin/flock"

cat >"$TMP_DIR/bin/sleep" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$TMP_DIR/bin/sleep"

write_uci() { printf '%s' "$2" >"$TMP_DIR/uci/$1"; }
read_uci() { cat "$TMP_DIR/uci/$1"; }

reset_state() {
	rm -f "$TMP_DIR/uci"/* "$TMP_DIR/state"/*
	: >"$TMP_DIR/uci.log"
	: >"$TMP_DIR/ip.log"
	: >"$TMP_DIR/logger.log"
	printf '%s\n' '0: from all lookup local' '2001: from all fwmark 0x100/0x3f00 lookup 1' '2002: from all fwmark 0x200/0x3f00 lookup 2' '5270: from all lookup 52' '32766: from all lookup main' >"$TMP_DIR/rules"
	printf '%s\n' '10.10.6.128/25 dev tailscale0' '100.64.2.0/24 dev tailscale0' >"$TMP_DIR/routes"
	write_uci 'tailscale_policy_routing.settings.enabled' '1'
}

run_helper() {
	UCI_BIN="$TMP_DIR/bin/uci" IP_BIN="$TMP_DIR/bin/ip" LOGGER_CMD="$TMP_DIR/bin/logger" FLOCK_BIN="$TMP_DIR/bin/flock" MWAN3_INIT="$TMP_DIR/mwan3-init" LOCK_FILE="$TMP_DIR/state/tailscale-policy-routing.lock" UCI_STATE_DIR="$TMP_DIR/uci" UCI_LOG="$TMP_DIR/uci.log" IP_RULES_FILE="$TMP_DIR/rules" IP_ROUTES_FILE="$TMP_DIR/routes" IP_LOG="$TMP_DIR/ip.log" LOGGER_LOG="$TMP_DIR/logger.log" IP_FAIL_DELETE="${IP_FAIL_DELETE:-0}" "$HELPER" "$@"
}

run_hotplug() {
	ACTION="$1" POLICY_HELPER="$HELPER" UCI_BIN="$TMP_DIR/bin/uci" IP_BIN="$TMP_DIR/bin/ip" LOGGER_CMD="$TMP_DIR/bin/logger" FLOCK_BIN="$TMP_DIR/bin/flock" MWAN3_INIT="$TMP_DIR/mwan3-init" LOCK_FILE="$TMP_DIR/state/tailscale-policy-routing.lock" UCI_STATE_DIR="$TMP_DIR/uci" UCI_LOG="$TMP_DIR/uci.log" IP_RULES_FILE="$TMP_DIR/rules" IP_ROUTES_FILE="$TMP_DIR/routes" IP_LOG="$TMP_DIR/ip.log" LOGGER_LOG="$TMP_DIR/logger.log" "$HOTPLUG"
}

touch "$TMP_DIR/mwan3-init"
chmod +x "$TMP_DIR/mwan3-init"

assert_file "$HELPER"
assert_file "$HOTPLUG"

reset_state
run_helper sync
[ "$(read_uci 'network.ts_mwan3_table52')" = 'rule' ] || fail 'sync must create the owned network rule section'
[ "$(read_uci 'network.ts_mwan3_table52.family')" = 'ipv4' ] || fail 'sync must persist IPv4-only rule family'
[ "$(read_uci 'network.ts_mwan3_table52.priority')" = '1000' ] || fail 'sync must persist priority 1000'
[ "$(read_uci 'network.ts_mwan3_table52.lookup')" = '52' ] || fail 'sync must persist Tailscale table 52 lookup'
assert_contains 'network' "$TMP_DIR/uci.log"
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"
assert_line_count 1 'add priority 1000 lookup 52' "$TMP_DIR/ip.log"

run_helper sync
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"
assert_line_count 1 'add priority 1000 lookup 52' "$TMP_DIR/ip.log"

printf '%s\n' '2001: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
run_hotplug ifup
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"
assert_line_count 2 'add priority 1000 lookup 52' "$TMP_DIR/ip.log"

write_uci 'tailscale_policy_routing.settings.enabled' '0'
run_helper sync
[ ! -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'disabled sync must remove the owned UCI network rule'
assert_line_count 0 '1000: from all lookup 52' "$TMP_DIR/rules"
assert_contains 'del priority 1000 lookup 52' "$TMP_DIR/ip.log"
: >"$TMP_DIR/logger.log"
run_hotplug ifup
[ ! -s "$TMP_DIR/logger.log" ] || fail 'disabled hotplug must not report a policy-routing restore failure'

reset_state
run_helper sync
write_uci 'tailscale_policy_routing.settings.enabled' '0'
if IP_FAIL_DELETE=1 run_helper sync; then fail 'disabled sync must fail when the runtime rule cannot be deleted'; fi
[ -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'failed runtime cleanup must retain the owned UCI rule for a safe retry'
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"
IP_FAIL_DELETE=0
run_helper sync
[ ! -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'a later successful cleanup must remove the owned UCI rule'
assert_line_count 0 '1000: from all lookup 52' "$TMP_DIR/rules"

reset_state
printf '%s\n' '1000: from all lookup 52' '2001: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
write_uci 'tailscale_policy_routing.settings.enabled' '0'
run_helper sync
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"
[ ! -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'disabled sync must not adopt a manually-created exact rule'

reset_state
run_helper sync
printf '%s\n' '1000: from 10.10.10.0/24 lookup 52' '2001: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
write_uci 'tailscale_policy_routing.settings.enabled' '0'
if run_helper sync; then fail 'disabled sync must refuse to delete a constrained table 52 rule'; fi
[ -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'constrained-rule cleanup failure must retain UCI ownership for retry'
assert_line_count 1 '1000: from 10.10.10.0/24 lookup 52' "$TMP_DIR/rules"

reset_state
printf '%s\n' '1000: from all lookup 1' '2001: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
if run_helper sync; then fail 'sync must reject an occupied priority 1000'; fi
[ ! -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'priority conflict must not create an owned UCI rule'

reset_state
printf '%s\n' '1000: from all lookup 52' '2001: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
if run_helper sync; then fail 'sync must reject an unowned pre-existing table 52 priority rule'; fi
[ ! -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'unowned runtime rule must not be adopted'

reset_state
run_helper sync
printf '%s\n' '1000: from all lookup 1' '2001: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
if run_helper sync; then fail 'sync must reject a priority conflict introduced after enablement'; fi
[ -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'priority conflict must retain the app-owned UCI rule for safe recovery'
assert_line_count 1 '1000: from all lookup 1' "$TMP_DIR/rules"
printf '%s\n' '2001: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
run_helper sync
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"

reset_state
printf '%s\n' 'default dev tailscale0' >"$TMP_DIR/routes"
run_helper sync
[ ! -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'default route in table 52 must prevent persistent precedence rule creation'
assert_line_count 0 '1000: from all lookup 52' "$TMP_DIR/rules"
status="$(run_helper status)"
printf '%s' "$status" | jq -e '.state == "blocked_default_route" and .enabled == true and .mwan3_present == true and .mwan3_earlier_mark_rule == false' >/dev/null || fail 'status must identify the exit-node default route block without treating later mwan3 rules as earlier than priority 1000'

reset_state
run_helper sync
printf '%s\n' 'default dev tailscale0' >"$TMP_DIR/routes"
run_hotplug ifupdate
[ -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'hotplug default-route protection must retain the owned UCI declaration for recovery'
assert_line_count 0 '1000: from all lookup 52' "$TMP_DIR/rules" # route-only ifupdate must remove the runtime rule
printf '%s\n' '10.10.6.128/25 dev tailscale0' '100.64.2.0/24 dev tailscale0' >"$TMP_DIR/routes"
run_hotplug ifup
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"
printf '%s\n' 'default dev tailscale0' >"$TMP_DIR/routes"
run_helper sync
[ ! -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'main sync must remove the persistent rule after an exit-node default route appears'
assert_line_count 0 '1000: from all lookup 52' "$TMP_DIR/rules"

reset_state
run_helper sync
printf '%s\n' '500: from all fwmark 0x100/0x3f00 lookup 1' '1000: from all lookup 52' '2001: from all fwmark 0x200/0x3f00 lookup 2' '5270: from all lookup 52' >"$TMP_DIR/rules"
run_helper ensure
[ -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'earlier mwan3 priority must retain UCI ownership for recovery'
assert_line_count 0 '1000: from all lookup 52' "$TMP_DIR/rules"
status="$(run_helper status)"
printf '%s' "$status" | jq -e '.state == "blocked_mwan3_priority" and .mwan3_earlier_mark_rule == true' >/dev/null || fail 'status must block when mwan3 precedes priority 1000'

reset_state
write_uci 'mwan3.globals.mmx_mask' '0x3F00'
printf '%s\n' '500: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
run_helper sync
[ ! -e "$TMP_DIR/uci/network.ts_mwan3_table52" ] || fail 'uppercase mwan3 mask must still block priority 1000 creation'
assert_line_count 0 '1000: from all lookup 52' "$TMP_DIR/rules"

reset_state
printf '%s\n' '1000: from all lookup 52' '2001: from all fwmark 0x100/0x3f00 lookup 1' '5270: from all lookup 52' >"$TMP_DIR/rules"
rm -f "$TMP_DIR/uci/network.ts_mwan3_table52" "$TMP_DIR/uci/network.ts_mwan3_table52".*
if run_helper cleanup; then fail 'package cleanup must refuse to leave an unowned exact runtime rule'; fi
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"

reset_state
run_helper sync
printf '%s\n' '2001: from all fwmark 0x100/0x3f00 lookup 1' '2002: from all fwmark 0x200/0x3f00 lookup 2' '5270: from all lookup 52' >"$TMP_DIR/rules"
SLEEP_BIN="$TMP_DIR/bin/sleep"
export SLEEP_BIN
run_helper monitor
unset SLEEP_BIN
assert_line_count 1 '1000: from all lookup 52' "$TMP_DIR/rules"

assert_not_contains '/etc/init.d/network' "$HELPER"
assert_not_contains 'firewall' "$HELPER"
assert_not_contains 'openclash' "$HELPER"
assert_not_contains 'mwan3 restart' "$HELPER"

echo 'tailscale policy routing tests passed'
