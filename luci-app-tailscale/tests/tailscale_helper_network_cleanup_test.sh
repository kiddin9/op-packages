#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/root/usr/sbin/tailscale_helper"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-helper-test.$$"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains() {
	needle="$1"
	haystack="$2"
	message="$3"

	printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null || fail "$message
missing: $needle"
}

assert_not_contains() {
	needle="$1"
	haystack="$2"
	message="$3"

	if printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null; then
		fail "$message
unexpected: $needle"
	fi
}

body="$(cat "$SCRIPT")"

assert_contains "uci -q delete network.tailscale" "$body" "helper should remove the legacy LuCI network interface wrapper"
assert_contains "add_list firewall.tszone.device='tailscale0'" "$body" "firewall zone should bind directly to tailscale0"
assert_contains "apply_firewall_changes" "$body" "helper should apply committed firewall changes through one checked path"

assert_not_contains "set network.tailscale='interface'" "$body" "helper must not recreate a LuCI network interface for tailscale0"
assert_not_contains "set network.tailscale.proto" "$body" "helper must not configure a netifd protocol for tailscale0"
assert_not_contains "set network.ts_subnet" "$body" "helper must not create static netifd routes for Tailscale subnet routes"
assert_not_contains "add_list firewall.tszone.network='tailscale'" "$body" "firewall zone should not depend on a LuCI network interface"

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/state"

cat >"$TMP_DIR/uci_db" <<'EOF'
firewall.@defaults[0].forward=ACCEPT
firewall.@forwarding[0]=forwarding
firewall.@forwarding[0].src=lan
firewall.@forwarding[0].dest=wan
dhcp.@dnsmasq[0]=dnsmasq
dhcp.@dnsmasq[0].address=/example.tailnet/100.100.100.100 /example.tailnet/192.0.2.53
EOF

cat >"$TMP_DIR/bin/uci" <<'SH'
#!/bin/sh
set -eu

db="${UCI_DB:?}"
changes="${UCI_CHANGES_LOG:?}"
quiet=0

if [ "${1:-}" = "-q" ]; then
	quiet=1
	shift
fi

cmd="${1:-}"
[ -n "$cmd" ] || exit 1
shift || true

get_value() {
	key="$1"
	awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); found=1; exit } END { if (!found) exit 1 }' "$db"
}

has_key() {
	key="$1"
	awk -F= -v key="$key" '$1 == key { found=1; exit } END { exit(found ? 0 : 1) }' "$db"
}

set_value() {
	key="$1"
	value="$2"
	tmp="$db.tmp"
	awk -F= -v key="$key" -v value="$value" '
		BEGIN { replaced=0 }
		$1 == key {
			print key "=" value
			replaced=1
			next
		}
		{ print }
		END {
			if (!replaced) {
				print key "=" value
			}
		}
	' "$db" >"$tmp"
	mv "$tmp" "$db"
	printf 'set %s=%s\n' "$key" "$value" >>"$changes"
}

delete_value() {
	key="$1"
	tmp="$db.tmp"
	awk -F= -v key="$key" '$1 != key && index($1, key ".") != 1 { print }' "$db" >"$tmp"
	mv "$tmp" "$db"
	printf 'delete %s\n' "$key" >>"$changes"
}

show_prefix() {
	prefix="$1"
	awk -F= -v prefix="$prefix" '$1 ~ "^" prefix { print }' "$db"
}

case "$cmd" in
	get)
		get_value "$1"
		;;
	set)
		key="${1%%=*}"
		value="${1#*=}"
		set_value "$key" "$value"
		;;
	add_list)
		key="${1%%=*}"
		value="${1#*=}"
		set_value "$key" "$value"
		;;
	delete)
		[ "${UCI_FAIL_DELETE_KEY:-}" != "$1" ] || exit 1
		if has_key "$1"; then
			delete_value "$1"
		else
			[ "$quiet" -eq 1 ] || exit 1
		fi
		;;
	show)
		[ "${UCI_FAIL_SHOW_PACKAGE:-}" != "${1:-}" ] || exit 1
		show_prefix "${1:-}"
		;;
	changes)
		if [ -s "$changes" ]; then
			if [ -n "${1:-}" ]; then
				awk -v pkg="$1" '$2 ~ "^" pkg "\\." { print }' "$changes"
			else
				cat "$changes"
			fi
		fi
		;;
	commit)
		[ "${UCI_FAIL_COMMIT_PACKAGE:-}" != "${1:-}" ] || exit 1
		if [ -n "${1:-}" ]; then
			tmp="$changes.tmp"
			awk -v pkg="$1" '$2 !~ "^" pkg "\\." { print }' "$changes" >"$tmp"
			mv "$tmp" "$changes"
		else
			: >"$changes"
		fi
		printf 'commit %s\n' "${1:-}" >>"${UCI_COMMIT_LOG:?}"
		;;
	revert)
		printf 'revert %s\n' "${1:-}" >>"${UCI_REVERT_LOG:?}"
		;;
	*)
		echo "unsupported fake uci command: $cmd" >&2
		exit 1
		;;
esac
SH
chmod +x "$TMP_DIR/bin/uci"

cat >"$TMP_DIR/bin/flock" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP_DIR/bin/flock"

cat >"$TMP_DIR/bin/ifconfig" <<'SH'
#!/bin/sh
printf 'tailscale0 Link encap:Ethernet\n'
SH
chmod +x "$TMP_DIR/bin/ifconfig"

cat >"$TMP_DIR/bin/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${LOGGER_LOG:?}"
SH
chmod +x "$TMP_DIR/bin/logger"

cat >"$TMP_DIR/bin/tailscale" <<'SH'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>"${TAILSCALE_LOG:?}"

case "${1:-}" in
	up)
		[ "${TAILSCALE_UP_FAIL:-0}" != "1" ] || exit 1
		exit 0
		;;
	ip)
		[ "${2:-}" = "-4" ] || exit 1
		printf '100.64.0.10\n'
		;;
	status)
		if [ "${TAILSCALE_EMPTY_MAGIC_DNS:-0}" = "1" ]; then
			printf '{}\n'
		else
			printf '{"MagicDNSSuffix":"example.tailnet"}\n'
		fi
		;;
	*)
		echo "unsupported fake tailscale command: $*" >&2
		exit 1
		;;
esac
SH
chmod +x "$TMP_DIR/bin/tailscale"

cat >"$TMP_DIR/firewall-init" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${FIREWALL_LOG:?}"
case "${1:-}" in
	reload) [ "${FIREWALL_FAIL_RELOAD:-0}" != "1" ] ;;
	restart) [ "${FIREWALL_FAIL_RESTART:-0}" != "1" ] ;;
esac
SH
chmod +x "$TMP_DIR/firewall-init"

cat >"$TMP_DIR/tailscale-init" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${TAILSCALE_INIT_LOG:?}"
SH
chmod +x "$TMP_DIR/tailscale-init"

cat >"$TMP_DIR/dnsmasq-init" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${DNSMASQ_LOG:?}"
SH
chmod +x "$TMP_DIR/dnsmasq-init"

cat >"$TMP_DIR/tailscale-policy-routing" <<'SH'
#!/bin/sh
set -eu
[ "${1:-}" = 'sync' ] || exit 1
printf '%s\n' "$1" >>"${POLICY_ROUTING_LOG:?}"
SH
chmod +x "$TMP_DIR/tailscale-policy-routing"

run_helper() {
	exit_node="$1"
	allow_wan_direct="${2:-0}"
	tailscale_port="${3:-41641}"
	wan_direct_zones="${4:-wan}"
	access="${5:-}"
	disable_snat_subnet_routes="${6:-0}"
	accept_dns="${7:-0}"
	state_was_present="${8:-1}"
	authkey_pending="${9:-0}"
	has_authkey="${10:-1}"
	ACCESS="$access"
	ACCEPT_DNS="$accept_dns"
	DISABLE_SNAT_SUBNET_ROUTES="$disable_snat_subnet_routes"
	ALLOW_WAN_DIRECT="$allow_wan_direct"
	TAILSCALE_PORT="$tailscale_port"
	WAN_DIRECT_ZONES="$wan_direct_zones"
	UCI_DB="$TMP_DIR/uci_db"
	UCI_CHANGES_LOG="$TMP_DIR/uci_changes.log"
	UCI_COMMIT_LOG="$TMP_DIR/uci_commit.log"
	UCI_REVERT_LOG="$TMP_DIR/uci_revert.log"
	TAILSCALE_LOG="$TMP_DIR/tailscale.log"
	LOGGER_LOG="$TMP_DIR/logger.log"
	FIREWALL_LOG="$TMP_DIR/firewall.log"
	TAILSCALE_INIT_LOG="$TMP_DIR/tailscale-init.log"
	DNSMASQ_LOG="$TMP_DIR/dnsmasq.log"
	POLICY_ROUTING_LOG="$TMP_DIR/policy-routing.log"
	PATH="$TMP_DIR/bin:$PATH"
	TAILSCALE_BIN="$TMP_DIR/bin/tailscale"
	IFCONFIG_BIN="$TMP_DIR/bin/ifconfig"
	FLOCK_BIN="$TMP_DIR/bin/flock"
	LOCK_FILE="$TMP_DIR/tailscale.lock"
	LOGGER_CMD="$TMP_DIR/bin/logger"
	FIREWALL_INIT="$TMP_DIR/firewall-init"
	TAILSCALE_INIT="$TMP_DIR/tailscale-init"
	DNSMASQ_INIT="$TMP_DIR/dnsmasq-init"
	POLICY_ROUTING_HELPER="$TMP_DIR/tailscale-policy-routing"
	TAILSCALE_SECRETS_BIN="$TMP_DIR/tailscale-secrets"
	TAILSCALE_HELPER_STATE_DIR="$TMP_DIR/state"
	FIREWALL_PENDING_STATE_FILE="$TMP_DIR/firewall-pending"
	TAILSCALE_STATE_WAS_PRESENT="$state_was_present"
	SECRET_AUTHKEY_PENDING="$authkey_pending"
	SECRET_HAS_AUTHKEY="$has_authkey"
	SECRETS_LOG="$TMP_DIR/secrets.log"
	export ACCESS ACCEPT_DNS DISABLE_SNAT_SUBNET_ROUTES ALLOW_WAN_DIRECT TAILSCALE_PORT WAN_DIRECT_ZONES UCI_DB UCI_CHANGES_LOG UCI_COMMIT_LOG UCI_REVERT_LOG
	export TAILSCALE_LOG LOGGER_LOG FIREWALL_LOG TAILSCALE_INIT_LOG DNSMASQ_LOG POLICY_ROUTING_LOG TAILSCALE_EMPTY_MAGIC_DNS PATH
	export TAILSCALE_BIN IFCONFIG_BIN FLOCK_BIN LOCK_FILE LOGGER_CMD FIREWALL_INIT TAILSCALE_INIT DNSMASQ_INIT POLICY_ROUTING_HELPER TAILSCALE_SECRETS_BIN TAILSCALE_HELPER_STATE_DIR FIREWALL_PENDING_STATE_FILE
	export TAILSCALE_STATE_WAS_PRESENT SECRET_AUTHKEY_PENDING SECRET_HAS_AUTHKEY SECRETS_LOG
	export UCI_FAIL_DELETE_KEY UCI_FAIL_SHOW_PACKAGE UCI_FAIL_COMMIT_PACKAGE FIREWALL_FAIL_RELOAD FIREWALL_FAIL_RESTART TAILSCALE_UP_FAIL
	EXIT_NODE="$exit_node" export EXIT_NODE

	if ! "$SCRIPT" --run; then
		printf 'helper failed for EXIT_NODE=%s\n' "$exit_node" >&2
		[ -s "$LOGGER_LOG" ] && { printf 'logger:\n' >&2; cat "$LOGGER_LOG" >&2; }
		[ -s "$TAILSCALE_INIT_LOG" ] && { printf 'tailscale-init:\n' >&2; cat "$TAILSCALE_INIT_LOG" >&2; }
		[ -s "$UCI_REVERT_LOG" ] && { printf 'uci-revert:\n' >&2; cat "$UCI_REVERT_LOG" >&2; }
		return 1
	fi
}

cat >"$TMP_DIR/tailscale-secrets" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${SECRETS_LOG:?}"
case "${1:-}" in
	get)
		[ "${2:-}" = "authkey" ] || exit 1
		printf '%s\n' 'tskey-test-only'
		;;
	authkey-pending)
		[ "${SECRET_AUTHKEY_PENDING:-0}" = "1" ]
		;;
	has)
		[ "${2:-}" = "authkey" ] || exit 1
		[ "${SECRET_HAS_AUTHKEY:-1}" = "1" ]
		;;
	clear-authkey)
		exit 0
		;;
	*)
		exit 1
		;;
esac
SH
chmod +x "$TMP_DIR/tailscale-secrets"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/uci_commit.log"
: >"$TMP_DIR/uci_revert.log"
: >"$TMP_DIR/tailscale.log"
: >"$TMP_DIR/logger.log"
: >"$TMP_DIR/firewall.log"
: >"$TMP_DIR/tailscale-init.log"
: >"$TMP_DIR/dnsmasq.log"
: >"$TMP_DIR/policy-routing.log"
: >"$TMP_DIR/secrets.log"

: >"$TMP_DIR/tailscale.log"
: >"$TMP_DIR/secrets.log"
run_helper "" 0 41641 wan "" 0 0 1 0 1
assert_not_contains '--authkey=' "$(cat "$TMP_DIR/tailscale.log")" \
	"an existing node must ignore an unmarked auth key left by an older package"
assert_contains 'clear-authkey' "$(cat "$TMP_DIR/secrets.log")" \
	"a successful existing-node start must purge the stale stored auth key"

: >"$TMP_DIR/tailscale.log"
: >"$TMP_DIR/secrets.log"
run_helper "" 0 41641 wan "" 0 0 0 0 1
assert_contains '--authkey=tskey-test-only' "$(cat "$TMP_DIR/tailscale.log")" \
	"a first enrollment without pre-existing state must use the saved auth key"
assert_contains 'clear-authkey' "$(cat "$TMP_DIR/secrets.log")" \
	"a successful first enrollment must purge the auth key"

: >"$TMP_DIR/tailscale.log"
: >"$TMP_DIR/secrets.log"
run_helper "" 0 41641 wan "" 0 0 1 1 1
assert_contains '--authkey=tskey-test-only' "$(cat "$TMP_DIR/tailscale.log")" \
	"an explicitly replaced auth key must allow deliberate re-enrollment"
assert_contains 'clear-authkey' "$(cat "$TMP_DIR/secrets.log")" \
	"a successful explicit re-enrollment must purge the auth key"

run_helper "peer-exit-node"
assert_contains 'sync' "$(cat "$TMP_DIR/policy-routing.log")" "helper should synchronize policy-routing precedence after Tailscale configuration"

: >"$TMP_DIR/tailscale-init.log"
: >"$TMP_DIR/uci_revert.log"
TAILSCALE_UP_FAIL=1
export TAILSCALE_UP_FAIL
: >"$TMP_DIR/secrets.log"
if run_helper "" 0 41641 wan "" 0 0 0 0 1 >/dev/null 2>&1; then
	fail "helper must fail when tailscale up fails"
fi
unset TAILSCALE_UP_FAIL
[ "$(grep -c '^clear-authkey$' "$TMP_DIR/secrets.log" || true)" = "0" ] || \
	fail "a failed enrollment must retain its auth key for correction and retry"
[ ! -s "$TMP_DIR/tailscale-init.log" ] || fail "a tailscale up failure must not stop the Tailscale service"
assert_contains "dhcp" "$(cat "$TMP_DIR/uci_revert.log")" "helper failure should revert its pending DHCP changes"
assert_contains "network" "$(cat "$TMP_DIR/uci_revert.log")" "helper failure should revert its pending network changes"
assert_contains "firewall" "$(cat "$TMP_DIR/uci_revert.log")" "helper failure should revert its pending firewall changes"

: >"$TMP_DIR/tailscale.log"
: >"$TMP_DIR/tailscale-init.log"
: >"$TMP_DIR/uci_revert.log"
if "$SCRIPT" --unexpected-mode >/dev/null 2>&1; then
	fail "helper must reject an unsupported mode"
fi
[ ! -s "$TMP_DIR/tailscale.log" ] || fail "unsupported helper mode must not call tailscale up"
[ ! -s "$TMP_DIR/tailscale-init.log" ] || fail "unsupported helper mode must not stop the Tailscale service"
[ ! -s "$TMP_DIR/uci_revert.log" ] || fail "unsupported helper mode must not revert unrelated UCI changes"

enabled_forward="$(awk -F= '$1 == "firewall.@defaults[0].forward" { print $2 }' "$TMP_DIR/uci_db")"
[ "$enabled_forward" = "REJECT" ] || fail "exit node enable should force firewall default forward to REJECT
actual: $enabled_forward"

enabled_override="$(awk -F= '$1 == "firewall.@forwarding[0].enabled" { print $2 }' "$TMP_DIR/uci_db")"
[ "$enabled_override" = "0" ] || fail "exit node enable should disable the LAN to WAN forwarding rule
actual: ${enabled_override:-missing}"

[ -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "exit node enable should persist firewall restore state"

: >"$TMP_DIR/uci_changes.log"
run_helper "" 0 41641 wan "" 0 1
if grep -F 'set dhcp.@dnsmasq[0].address=' "$TMP_DIR/uci_changes.log" >/dev/null; then
	fail "MagicDNS setup must not duplicate its address when a dnsmasq list has additional user values"
fi

: >"$TMP_DIR/uci_changes.log"
TAILSCALE_EMPTY_MAGIC_DNS=1 run_helper "" 0 41641 wan "" 0 1
assert_not_contains 'set dhcp.@dnsmasq[0].address=//100.100.100.100' "$(cat "$TMP_DIR/uci_changes.log")" \
	"MagicDNS setup must not write an invalid address when the suffix is unavailable"

run_helper ""

restored_forward="$(awk -F= '$1 == "firewall.@defaults[0].forward" { print $2 }' "$TMP_DIR/uci_db")"
[ "$restored_forward" = "ACCEPT" ] || fail "non-exit-node helper run should restore the previous firewall forward policy
actual: $restored_forward"

if awk -F= '$1 == "firewall.@forwarding[0].enabled" { found=1 } END { exit(found ? 0 : 1) }' "$TMP_DIR/uci_db"; then
	fail "non-exit-node helper run should remove the temporary LAN to WAN enabled override"
fi

[ ! -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "helper should clear the exit-node firewall restore state after reconciliation"

assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" "helper should reload firewall after restoring exit-node changes"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641

assert_contains "firewall.ts_wan_direct_1_wan=rule" "$(cat "$TMP_DIR/uci_db")" "WAN direct enable should create a named firewall rule"
assert_contains "firewall.ts_wan_direct_1_wan.name=Allow-Tailscale-WAN-41641-wan" "$(cat "$TMP_DIR/uci_db")" "WAN direct rule should use the configured Tailscale listen port and zone in the rule name"
assert_contains "firewall.ts_wan_direct_1_wan.src=wan" "$(cat "$TMP_DIR/uci_db")" "WAN direct rule should come from the wan zone"
assert_contains "firewall.ts_wan_direct_1_wan.proto=udp" "$(cat "$TMP_DIR/uci_db")" "WAN direct rule should allow UDP"
assert_contains "firewall.ts_wan_direct_1_wan.dest_port=41641" "$(cat "$TMP_DIR/uci_db")" "WAN direct rule should target the configured listen port"
assert_contains "firewall.ts_wan_direct_1_wan.target=ACCEPT" "$(cat "$TMP_DIR/uci_db")" "WAN direct rule should accept matching packets"
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" "WAN direct rule changes should reload firewall"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641
wan_direct_count="$(awk -F= '$1 ~ /^firewall\.ts_wan_direct[^.]*$/ { count++ } END { print count + 0 }' "$TMP_DIR/uci_db")"
[ "$wan_direct_count" = "1" ] || fail "reapplying WAN direct should keep exactly one named firewall rule
actual: $wan_direct_count"
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "reapplying an unchanged WAN direct rule should not create UCI changes
actual: $(cat "$TMP_DIR/uci_changes.log")"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "reapplying an unchanged WAN direct rule should not reload firewall
actual: $(cat "$TMP_DIR/firewall.log")"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641
if grep -F 'firewall.ts_wan_direct' "$TMP_DIR/uci_db" >/dev/null; then
	fail "WAN direct disable should remove the named firewall rule"
fi

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641 "wan wan2"

assert_contains "firewall.ts_wan_direct_1_wan=rule" "$(cat "$TMP_DIR/uci_db")" "multi-zone WAN direct should create a rule for the wan zone"
assert_contains "firewall.ts_wan_direct_1_wan.name=Allow-Tailscale-WAN-41641-wan" "$(cat "$TMP_DIR/uci_db")" "multi-zone WAN direct rule should include the wan zone in the rule name"
assert_contains "firewall.ts_wan_direct_1_wan.src=wan" "$(cat "$TMP_DIR/uci_db")" "multi-zone WAN direct rule should target the wan zone"
assert_contains "firewall.ts_wan_direct_2_wan2=rule" "$(cat "$TMP_DIR/uci_db")" "multi-zone WAN direct should create a rule for the wan2 zone"
assert_contains "firewall.ts_wan_direct_2_wan2.name=Allow-Tailscale-WAN-41641-wan2" "$(cat "$TMP_DIR/uci_db")" "multi-zone WAN direct rule should include the wan2 zone in the rule name"
assert_contains "firewall.ts_wan_direct_2_wan2.src=wan2" "$(cat "$TMP_DIR/uci_db")" "multi-zone WAN direct rule should target the wan2 zone"
wan_direct_count="$(awk -F= '$1 ~ /^firewall\.ts_wan_direct[^.]*$/ { count++ } END { print count + 0 }' "$TMP_DIR/uci_db")"
[ "$wan_direct_count" = "2" ] || fail "multi-zone WAN direct should create exactly two named firewall rules
actual: $wan_direct_count"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641 "wan wan2"
wan_direct_count="$(awk -F= '$1 ~ /^firewall\.ts_wan_direct[^.]*$/ { count++ } END { print count + 0 }' "$TMP_DIR/uci_db")"
[ "$wan_direct_count" = "2" ] || fail "reapplying multi-zone WAN direct should keep exactly two named firewall rules
actual: $wan_direct_count"
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "reapplying unchanged multi-zone WAN direct rules should not create UCI changes
actual: $(cat "$TMP_DIR/uci_changes.log")"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "reapplying unchanged multi-zone WAN direct rules should not reload firewall
actual: $(cat "$TMP_DIR/firewall.log")"

printf '%s\n' 'firewall.ts_wan_direct_1_wan.enabled=0' >>"$TMP_DIR/uci_db"
: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641 "wan wan2"
if grep -F 'firewall.ts_wan_direct_1_wan.enabled=' "$TMP_DIR/uci_db" >/dev/null; then
	fail "WAN direct reconciliation should remove stale managed rule options"
fi
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" "removing stale WAN direct options should reload firewall"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 "wan wan2"
if grep -F 'firewall.ts_wan_direct' "$TMP_DIR/uci_db" >/dev/null; then
	fail "WAN direct disable should remove every named multi-zone firewall rule"
fi

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 "wan wan2"
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "reapplying disabled WAN direct should not create UCI changes
actual: $(cat "$TMP_DIR/uci_changes.log")"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "reapplying disabled WAN direct should not reload firewall
actual: $(cat "$TMP_DIR/firewall.log")"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts"
assert_contains "firewall.tszone=zone" "$(cat "$TMP_DIR/uci_db")" "ACCESS should create the Tailscale firewall zone"
assert_contains "firewall.ts_ac_lan=forwarding" "$(cat "$TMP_DIR/uci_db")" "ACCESS should create Tailscale-to-LAN forwarding"
assert_contains "firewall.lan_ac_ts=forwarding" "$(cat "$TMP_DIR/uci_db")" "ACCESS should create LAN-to-Tailscale forwarding"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts"
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "reapplying unchanged ACCESS firewall rules should not create UCI changes
actual: $(cat "$TMP_DIR/uci_changes.log")"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "reapplying unchanged ACCESS firewall rules should not reload firewall
actual: $(cat "$TMP_DIR/firewall.log")"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts" 1
assert_contains "firewall.tszone.masq=0" "$(cat "$TMP_DIR/uci_db")" \
	"site-to-site enable must disable masquerade in the app-owned Tailscale firewall zone"
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" \
	"changing site-to-site SNAT must reload firewall4 through the existing firewall flow"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts" 1
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "unchanged no-SNAT firewall state must be idempotent"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "unchanged no-SNAT firewall state must not reload firewall4"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts" 0
assert_contains "firewall.tszone.masq=1" "$(cat "$TMP_DIR/uci_db")" \
	"site-to-site disable must restore masquerade in the app-owned Tailscale firewall zone"
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" \
	"restoring site-to-site SNAT must reload firewall4 through the existing firewall flow"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts" 0
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "reapplying restored SNAT state must not create UCI changes"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "reapplying restored SNAT state must not reload firewall4"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "" 1
empty_access_db="$(cat "$TMP_DIR/uci_db")"
assert_contains "firewall.tszone=zone" "$empty_access_db" \
	"site-to-site no-SNAT must keep the Tailscale zone when ACCESS is empty"
assert_contains "firewall.tszone.masq=0" "$empty_access_db" \
	"site-to-site no-SNAT must disable masquerade when ACCESS is empty"
for forwarding in ts_ac_lan ts_ac_wan lan_ac_ts wan_ac_ts; do
	assert_not_contains "firewall.$forwarding=" "$empty_access_db" \
		"empty ACCESS must not create forwarding section $forwarding"
done

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "" 1
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "empty-access no-SNAT state must be idempotent"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "empty-access no-SNAT state must not reload firewall4 when unchanged"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "" 0
empty_access_disabled_db="$(cat "$TMP_DIR/uci_db")"
assert_not_contains "firewall.tszone=" "$empty_access_disabled_db" \
	"disabling no-SNAT with empty ACCESS must remove the Tailscale zone"
for forwarding in ts_ac_lan ts_ac_wan lan_ac_ts wan_ac_ts; do
	assert_not_contains "firewall.$forwarding=" "$empty_access_disabled_db" \
		"disabling no-SNAT with empty ACCESS must not retain forwarding section $forwarding"
done

run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts"
printf '%s\n' 'firewall.tszone.enabled=0' >>"$TMP_DIR/uci_db"
: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641 wan "ts_ac_lan lan_ac_ts"
if grep -F 'firewall.tszone.enabled=' "$TMP_DIR/uci_db" >/dev/null; then
	fail "ACCESS reconciliation should remove stale managed zone options"
fi

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641
UCI_FAIL_DELETE_KEY=firewall.ts_wan_direct_1_wan
if run_helper "" 0 41641 >/dev/null 2>&1; then
	fail "WAN direct cleanup should fail when UCI cannot delete a managed rule"
fi
unset UCI_FAIL_DELETE_KEY
run_helper "" 0 41641

UCI_FAIL_SHOW_PACKAGE=firewall
if run_helper "" 1 41641 >/dev/null 2>&1; then
	fail "WAN direct reconciliation should fail when UCI cannot enumerate firewall sections"
fi
unset UCI_FAIL_SHOW_PACKAGE
run_helper "" 0 41641

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641
: >"$TMP_DIR/tailscale.log"
: >"$TMP_DIR/firewall.log"
ALLOW_WAN_DIRECT=0 "$SCRIPT" --cleanup-wan-direct-firewall
if grep -F 'firewall.ts_wan_direct' "$TMP_DIR/uci_db" >/dev/null; then
	fail "standalone WAN direct cleanup should remove managed rules"
fi
[ ! -s "$TMP_DIR/tailscale.log" ] || fail "standalone WAN direct cleanup must not call tailscale up
actual: $(cat "$TMP_DIR/tailscale.log")"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
rm -f "$TMP_DIR/firewall-pending"
FIREWALL_FAIL_RELOAD=1
FIREWALL_FAIL_RESTART=1
if run_helper "" 1 41641 >/dev/null 2>&1; then
	fail "helper should fail when firewall reload and restart both fail"
fi
[ -f "$TMP_DIR/firewall-pending" ] || fail "failed firewall apply should leave a pending retry marker"
unset FIREWALL_FAIL_RELOAD FIREWALL_FAIL_RESTART

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" "a pending firewall apply should retry reload even without new UCI changes"
[ ! -e "$TMP_DIR/firewall-pending" ] || fail "successful firewall retry should clear the pending marker"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641
: >"$TMP_DIR/firewall-pending"
UCI_FAIL_COMMIT_PACKAGE=firewall
if run_helper "" 1 41641 >/dev/null 2>&1; then
	fail "helper should fail when a later firewall commit fails with an existing pending marker"
fi
[ -f "$TMP_DIR/firewall-pending" ] || fail "a pre-existing pending marker must survive a later UCI commit failure"
unset UCI_FAIL_COMMIT_PACKAGE
: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 1 41641
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" "a preserved pending marker should retry firewall apply after commit recovers"
[ ! -e "$TMP_DIR/firewall-pending" ] || fail "successful retry should clear the preserved pending marker"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
run_helper "" 0 41641
UCI_FAIL_COMMIT_PACKAGE=firewall
if run_helper "" 1 41641 >/dev/null 2>&1; then
	fail "helper should fail when the firewall UCI commit fails"
fi
[ ! -e "$TMP_DIR/firewall-pending" ] || fail "failed UCI commit should not leave an apply-only retry marker"
unset UCI_FAIL_COMMIT_PACKAGE

run_helper "" 0 41641

run_helper "peer-exit-node"
[ -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "exit-node durability test requires persisted restore state"
UCI_FAIL_COMMIT_PACKAGE=firewall
export UCI_FAIL_COMMIT_PACKAGE
if "$SCRIPT" --cleanup-exit-node-firewall >/dev/null 2>&1; then
	fail "exit-node cleanup should fail when its firewall commit fails"
fi
[ -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "exit-node restore state must survive a failed UCI commit"
unset UCI_FAIL_COMMIT_PACKAGE
: >"$TMP_DIR/firewall.log"
"$SCRIPT" --cleanup-exit-node-firewall
[ ! -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "successful retry should remove exit-node restore state after commit and reload"
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" "successful commit retry should reload the firewall"

run_helper "peer-exit-node"
[ -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "reload durability test requires persisted restore state"
FIREWALL_FAIL_RELOAD=1
FIREWALL_FAIL_RESTART=1
export FIREWALL_FAIL_RELOAD FIREWALL_FAIL_RESTART
if "$SCRIPT" --cleanup-exit-node-firewall >/dev/null 2>&1; then
	fail "exit-node cleanup should fail when firewall reload and restart fail"
fi
[ -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "exit-node restore state must survive failed firewall apply"
[ -f "$TMP_DIR/firewall-pending" ] || fail "failed exit-node firewall apply should preserve the pending retry marker"
unset FIREWALL_FAIL_RELOAD FIREWALL_FAIL_RESTART
: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
"$SCRIPT" --cleanup-exit-node-firewall
[ ! -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "pending-only successful retry should remove exit-node restore state"
[ ! -f "$TMP_DIR/firewall-pending" ] || fail "pending-only successful retry should clear the firewall marker"
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" "exit-node cleanup should retry an existing pending reload without a new UCI delta"

run_helper "peer-exit-node" 1 41641 wan "ts_ac_lan ts_ac_wan lan_ac_ts wan_ac_ts"
cat >>"$TMP_DIR/uci_db" <<'EOF'
firewall.user_rule=rule
firewall.user_rule.name=User-owned rule
firewall.user_rule.target=ACCEPT
EOF
: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
"$SCRIPT" --cleanup-managed-firewall

managed_cleanup_db="$(cat "$TMP_DIR/uci_db")"
for managed_section in tszone ts_ac_lan ts_ac_wan lan_ac_ts wan_ac_ts ts_wan_direct_1_wan; do
	assert_not_contains "firewall.$managed_section=" "$managed_cleanup_db" "managed cleanup should remove package-owned section $managed_section"
done
assert_contains "firewall.user_rule=rule" "$managed_cleanup_db" "managed cleanup must preserve unrelated user firewall sections"
assert_contains "firewall.@defaults[0].forward=ACCEPT" "$managed_cleanup_db" "managed cleanup should restore stale exit-node firewall state"
[ ! -f "$TMP_DIR/state/exit_node_firewall_state" ] || fail "managed cleanup should clear successfully restored exit-node state"
assert_contains "reload" "$(cat "$TMP_DIR/firewall.log")" "managed cleanup should apply firewall changes"

: >"$TMP_DIR/uci_changes.log"
: >"$TMP_DIR/firewall.log"
"$SCRIPT" --cleanup-managed-firewall
[ ! -s "$TMP_DIR/uci_changes.log" ] || fail "managed firewall cleanup should be idempotent
actual: $(cat "$TMP_DIR/uci_changes.log")"
[ ! -s "$TMP_DIR/firewall.log" ] || fail "idempotent managed firewall cleanup should not reload without changes or a pending marker
actual: $(cat "$TMP_DIR/firewall.log")"

echo "tailscale_helper network cleanup tests passed"
