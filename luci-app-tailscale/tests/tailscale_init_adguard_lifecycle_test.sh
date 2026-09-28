#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INIT_SCRIPT="$ROOT_DIR/root/etc/init.d/tailscale"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-init-adguard-test.$$"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

mkdir -p "$TMP_DIR"

cat >"$TMP_DIR/fake-adguard" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${FAKE_ADGUARD_LOG:?}"
[ "${FAKE_ADGUARD_FAIL:-0}" = "0" ]
SH
chmod +x "$TMP_DIR/fake-adguard"

cat >"$TMP_DIR/fake-helper" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${FAKE_HELPER_LOG:?}"
[ -z "${FAKE_HELPER_FAIL_ARG:-}" ] || [ "$*" != "$FAKE_HELPER_FAIL_ARG" ] || exit 1
SH
chmod +x "$TMP_DIR/fake-helper"

cat >"$TMP_DIR/fake-secrets" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${FAKE_SECRETS_LOG:?}"
SH
chmod +x "$TMP_DIR/fake-secrets"

run_apply_down() {
	switch_enabled="$1"
	state_profile="${2:-}"
	fail_mode="${3:-0}"
	FAKE_ADGUARD_LOG="$TMP_DIR/adguard.log"
	ADGUARD_DNS_STATE_DIR="$TMP_DIR/state"
	: >"$FAKE_ADGUARD_LOG"
	rm -rf "$ADGUARD_DNS_STATE_DIR"
	if [ -n "$state_profile" ]; then
		mkdir -p "$ADGUARD_DNS_STATE_DIR"
		printf '%s\n' "$state_profile" >"$ADGUARD_DNS_STATE_DIR/current_profile"
	fi
	FAKE_ADGUARD_FAIL="$fail_mode"
	export FAKE_ADGUARD_LOG FAKE_ADGUARD_FAIL ADGUARD_DNS_STATE_DIR

	rc=0
	(
		. "$INIT_SCRIPT"
		PROGA="$TMP_DIR/fake-adguard"
		ADGUARD_DNS_STATE_DIR="$ADGUARD_DNS_STATE_DIR"

		config_get_bool() {
			case "$3" in
				adguard_dns_switch_enabled) eval "$1=$switch_enabled" ;;
				*) eval "$1=${4:-0}" ;;
			esac
		}

		config_get() {
			case "$3" in
				adguard_default_upstreams) eval "$1=9.9.9.9" ;;
				*) eval "$1=" ;;
			esac
		}

		tailscale_adguard_dns_apply_down settings
	) || rc=$?

	cat "$FAKE_ADGUARD_LOG"
	return "$rc"
}

run_reload_service() {
	start_result="${1:-0}"
	RELOAD_LOG="$TMP_DIR/reload.log"
	: >"$RELOAD_LOG"
	export RELOAD_LOG

	(
		. "$INIT_SCRIPT"
		stop() {
			printf 'stop:%s\n' "${TAILSCALE_INTERNAL_RELOAD:-0}" >>"$RELOAD_LOG"
		}
		start() {
			printf 'start\n' >>"$RELOAD_LOG"
			return "$start_result"
		}
		reload_service
	)
}

run_disabled_start() {
	FAKE_HELPER_LOG="$TMP_DIR/disabled-helper.log"
	FAKE_SECRETS_LOG="$TMP_DIR/disabled-secrets.log"
	CONFIG_DIR="$TMP_DIR/disabled-config"
	: >"$FAKE_HELPER_LOG"
	: >"$FAKE_SECRETS_LOG"
	mkdir -p "$CONFIG_DIR"
	export FAKE_HELPER_LOG FAKE_SECRETS_LOG CONFIG_DIR

	(
		. "$INIT_SCRIPT"
		PROG="$TMP_DIR/fake-helper"
		PROGS="$TMP_DIR/fake-secrets"
		CONFIG_PATH="$CONFIG_DIR"

		config_get_bool() {
			eval "$1=0"
		}
		config_get() {
			case "$3" in
				secrets_ref) eval "$1=disabled-secret-ref" ;;
				*) eval "$1=" ;;
			esac
		}

		start_instance settings >/dev/null 2>&1 || true
	)

	cat "$FAKE_HELPER_LOG"
}

run_stop_instance() {
	helper_fail_arg="${1:-}"
	reload_mode="${2:-0}"
	FAKE_ADGUARD_LOG="$TMP_DIR/stop-adguard.log"
	FAKE_HELPER_LOG="$TMP_DIR/helper.log"
	ADGUARD_DNS_STATE_DIR="$TMP_DIR/stop-state"
	CONFIG_DIR="$TMP_DIR/config"
	UCI_CHANGES_OUT="$TMP_DIR/uci-changes.out"
	UCI_DEL_LIST_LOG="$TMP_DIR/uci-del-list.log"
	UCI_DNSMASQ_ADDRESS_STATE="$TMP_DIR/dnsmasq-addresses"
	TAILSCALE_STATUS_OUT="$TMP_DIR/tailscale-status.out"
	TAILSCALED_CLEANUP_LOG="$TMP_DIR/tailscaled-cleanup.log"
	rm -rf "$ADGUARD_DNS_STATE_DIR" "$CONFIG_DIR"
	: >"$FAKE_ADGUARD_LOG"
	: >"$FAKE_HELPER_LOG"
	: >"$UCI_CHANGES_OUT"
	: >"$UCI_DEL_LIST_LOG"
	printf '%s\n' '/example.tailnet/100.100.100.100' '/example.tailnet/192.0.2.53' >"$UCI_DNSMASQ_ADDRESS_STATE"
	: >"$TAILSCALE_STATUS_OUT"
	: >"$TAILSCALED_CLEANUP_LOG"
	mkdir -p "$ADGUARD_DNS_STATE_DIR" "$CONFIG_DIR"
	printf 'up\n' >"$ADGUARD_DNS_STATE_DIR/current_profile"
	printf 'recovery-state\n' >"$CONFIG_DIR/exit_node_firewall_state"
	FAKE_HELPER_FAIL_ARG="$helper_fail_arg"
	FAKE_ADGUARD_FAIL=0
	export FAKE_ADGUARD_LOG FAKE_ADGUARD_FAIL FAKE_HELPER_LOG FAKE_HELPER_FAIL_ARG ADGUARD_DNS_STATE_DIR CONFIG_DIR UCI_CHANGES_OUT UCI_DEL_LIST_LOG UCI_DNSMASQ_ADDRESS_STATE TAILSCALE_STATUS_OUT TAILSCALED_CLEANUP_LOG

	(
		. "$INIT_SCRIPT"
		PROGA="$TMP_DIR/fake-adguard"
		PROG="$TMP_DIR/fake-helper"
		PROGD="$TMP_DIR/fake-tailscaled"
		CONFIG_PATH="$CONFIG_DIR"
		ADGUARD_DNS_STATE_DIR="$ADGUARD_DNS_STATE_DIR"
		TAILSCALE_INTERNAL_RELOAD="$reload_mode"

		config_get_bool() {
			case "$3" in
				adguard_dns_switch_enabled) eval "$1=0" ;;
				*) eval "$1=${4:-0}" ;;
			esac
		}

		config_get() {
			case "$3" in
				adguard_default_upstreams) eval "$1=9.9.9.9" ;;
				*) eval "$1=" ;;
			esac
		}

		tailscale() {
			case "$1" in
				status)
					printf '{"MagicDNSSuffix":"example.tailnet"}\n' >"$TAILSCALE_STATUS_OUT"
					printf '{"MagicDNSSuffix":"example.tailnet"}\n'
					;;
				*)
					return 1
					;;
			esac
		}

		uci() {
			case "$1" in
				show)
					if [ "${2:-}" = 'dhcp' ]; then
						printf '%s\n' 'dhcp.@dnsmasq[0]=dnsmasq'
					fi
					;;
				changes)
					cat "$UCI_CHANGES_OUT"
					;;
				commit)
					:
					;;
				-q)
					shift
					case "$1" in
						del_list)
							printf '%s\n' "${2:-}" >>"$UCI_DEL_LIST_LOG"
							[ "${2:-}" = 'dhcp.@dnsmasq[0].address=/example.tailnet/100.100.100.100' ]
							grep -vxF '/example.tailnet/100.100.100.100' "$UCI_DNSMASQ_ADDRESS_STATE" >"$UCI_DNSMASQ_ADDRESS_STATE.tmp"
							mv "$UCI_DNSMASQ_ADDRESS_STATE.tmp" "$UCI_DNSMASQ_ADDRESS_STATE"
							;;
						*)
							return 1
							;;
					esac
					;;
				*)
					return 1
					;;
			esac
		}

		rm() {
			command rm "$@"
		}

		stop_instance settings
	)
}

run_service_stopped() {
	FAKE_ADGUARD_LOG="$TMP_DIR/service-stopped-adguard.log"
	ADGUARD_DNS_STATE_DIR="$TMP_DIR/service-stopped-state"
	: >"$FAKE_ADGUARD_LOG"
	rm -rf "$ADGUARD_DNS_STATE_DIR"
	mkdir -p "$ADGUARD_DNS_STATE_DIR"
	printf 'up\n' >"$ADGUARD_DNS_STATE_DIR/current_profile"
	FAKE_ADGUARD_FAIL=0
	export FAKE_ADGUARD_LOG FAKE_ADGUARD_FAIL ADGUARD_DNS_STATE_DIR

	(
		. "$INIT_SCRIPT"
		PROGA="$TMP_DIR/fake-adguard"
		ADGUARD_DNS_STATE_DIR="$ADGUARD_DNS_STATE_DIR"

		config_load() { :; }
		config_foreach() {
			callback="$1"
			"$callback" settings
		}
		config_get_bool() {
			case "$3" in
				adguard_dns_switch_enabled) eval "$1=0" ;;
				*) eval "$1=${4:-0}" ;;
			esac
		}
		config_get() {
			case "$3" in
				adguard_default_upstreams) eval "$1=9.9.9.9" ;;
				*) eval "$1=" ;;
			esac
		}

		command -v service_stopped >/dev/null 2>&1 || fail "init script must define service_stopped"
		service_stopped
	)

	cat "$FAKE_ADGUARD_LOG"
}

capture_tailscale_snat_args() {
	disable_snat="$1"
	state_was_present="${2:-1}"
	PROCD_LOG="$TMP_DIR/procd-snat-$disable_snat.log"
	FAKE_SECRETS_LOG="$TMP_DIR/procd-secrets-$disable_snat.log"
	: >"$PROCD_LOG"
	: >"$FAKE_SECRETS_LOG"
	export PROCD_LOG FAKE_SECRETS_LOG
	(
		. "$INIT_SCRIPT"
		PROGS="$TMP_DIR/fake-secrets"
		config_get() {
			case "$3" in
				port) eval "$1=41641" ;;
				access) eval "$1=ts_ac_lan" ;;
				*) eval "$1=" ;;
			esac
		}
		config_get_bool() {
			case "$3" in
				disable_snat_subnet_routes) eval "$1=$disable_snat" ;;
				accept_dns) eval "$1=1" ;;
				*) eval "$1=0" ;;
			esac
		}
		config_list_foreach() { :; }
		procd_open_instance() { :; }
		procd_set_param() { printf 'set:%s\n' "$*" >>"$PROCD_LOG"; }
		procd_append_param() { printf 'append:%s\n' "$*" >>"$PROCD_LOG"; }
		procd_close_instance() { :; }
		tailscale_helper settings "$state_was_present"
	)
	[ ! -s "$FAKE_SECRETS_LOG" ] || fail "init must not retrieve the auth key while building the procd command"
	cat "$PROCD_LOG"
}

capture_start_state_flag() {
	with_state="$1"
	START_CONFIG_DIR="$TMP_DIR/start-config-$with_state"
	rm -rf "$START_CONFIG_DIR"
	mkdir -p "$START_CONFIG_DIR"
	if [ "$with_state" = "1" ]; then
		printf '%s\n' 'existing-machine-identity' >"$START_CONFIG_DIR/tailscaled.state"
	fi
	export START_CONFIG_DIR

	(
		. "$INIT_SCRIPT"
		PROG=true
		PROGS=true
		PROGD=true
		CONFIG_PATH="$START_CONFIG_DIR"

		config_get() {
			case "$3" in
				config_path) eval "$1=\$START_CONFIG_DIR" ;;
				port) eval "$1=41641" ;;
				*) eval "$1=" ;;
			esac
		}
		config_get_bool() {
			case "$3" in
				enabled) eval "$1=1" ;;
				*) eval "$1=${4:-0}" ;;
			esac
		}
		procd_open_instance() { :; }
		procd_set_param() { :; }
		procd_append_param() { :; }
		procd_close_instance() { :; }
		tailscale_helper() { printf '%s\n' "$2"; }
		tailscale_keepalive() { :; }
		tailscale_adguard_dns() { :; }

		start_instance settings
	)
}

cat >"$TMP_DIR/fake-tailscaled" <<'SH'
#!/bin/sh
[ "${1:-}" = "--cleanup" ] || exit 1
printf '%s\n' "$*" >>"${TAILSCALED_CLEANUP_LOG:?}"
SH
chmod +x "$TMP_DIR/fake-tailscaled"

disabled_output="$(run_apply_down 0)"
[ -z "$disabled_output" ] || fail "disabled AdGuard DNS switch must not apply down profile
actual: $disabled_output"

enabled_output="$(run_apply_down 1)"
[ "$enabled_output" = "--apply-profile down" ] || fail "enabled AdGuard DNS switch should apply down profile
actual: $enabled_output"

disabled_with_managed_profile_output="$(run_apply_down 0 up)"
[ "$disabled_with_managed_profile_output" = "--apply-profile down" ] || fail "disabling a managed AdGuard DNS switch should restore the down profile
actual: $disabled_with_managed_profile_output"

if run_apply_down 0 up 1 >/dev/null; then
	fail "failed AdGuard down-profile restoration must propagate through the stop lifecycle"
fi

run_reload_service 0
[ "$(cat "$TMP_DIR/reload.log")" = "stop:1
start" ] || fail "successful reload must use one internal stop followed by start"

if run_reload_service 1; then
	fail "reload must fail when restart fails"
fi
[ "$(cat "$TMP_DIR/reload.log")" = "stop:1
start
stop:0" ] || fail "failed reload start must execute a final stop that removes persistent firewall state
actual: $(cat "$TMP_DIR/reload.log")"

disabled_helper_output="$(run_disabled_start)"
[ "$disabled_helper_output" = "--cleanup-managed-firewall" ] || fail "disabled start should invoke complete managed firewall cleanup
actual: ${disabled_helper_output:-<empty>}"
[ "$(cat "$TMP_DIR/disabled-secrets.log")" = "activate disabled-secret-ref" ] || fail "every start, including a disabled service, must activate the credential version selected by UCI
actual: $(cat "$TMP_DIR/disabled-secrets.log")"

run_stop_instance

[ ! -s "$FAKE_ADGUARD_LOG" ] || fail "stop_instance must not switch AdGuard before procd terminates the watcher
actual: $(cat "$FAKE_ADGUARD_LOG")"

[ "$(cat "$UCI_DEL_LIST_LOG")" = 'dhcp.@dnsmasq[0].address=/example.tailnet/100.100.100.100' ] || fail "stop_instance must remove only the exact MagicDNS dnsmasq address
actual: $(cat "$UCI_DEL_LIST_LOG")"
[ "$(cat "$UCI_DNSMASQ_ADDRESS_STATE")" = '/example.tailnet/192.0.2.53' ] || fail "stop_instance must preserve a user-defined address with the same MagicDNS suffix
actual: $(cat "$UCI_DNSMASQ_ADDRESS_STATE")"

service_stopped_output="$(run_service_stopped)"
[ "$service_stopped_output" = "--apply-profile down" ] || fail "service_stopped should apply the down profile after procd terminates the watcher
actual: ${service_stopped_output:-<empty>}"

helper_output="$(cat "$TMP_DIR/helper.log")"
[ "$helper_output" = "--cleanup-managed-firewall" ] || fail "final stop_instance should remove every managed firewall rule
actual: ${helper_output:-<empty>}"

run_stop_instance "" 1
reload_helper_output="$(cat "$TMP_DIR/helper.log")"
[ "$reload_helper_output" = "--cleanup-exit-node-firewall" ] || fail "reload stop should retain persistent Tailscale zone, forwarding, and WAN-direct rules
actual: ${reload_helper_output:-<empty>}"
[ ! -e "$TMP_DIR/reloading" ] || fail "reload state must not be shared through a stale PID marker file"

if run_stop_instance "--cleanup-managed-firewall"; then
	fail "stop_instance should report a managed firewall cleanup failure"
fi
[ -f "$CONFIG_DIR/exit_node_firewall_state" ] || fail "stop_instance must preserve helper recovery state when cleanup fails"

snat_disabled_args="$(capture_tailscale_snat_args 1)"
printf '%s\n' "$snat_disabled_args" | grep -F 'set:command ' | grep -F -- ' --run' >/dev/null || \
	fail "Tailscale helper procd command must use the explicit --run mode"
if printf '%s\n' "$snat_disabled_args" | grep -F -- '--authkey=' >/dev/null; then
	fail "Tailscale auth key must not be included in the procd command"
fi
printf '%s\n' "$snat_disabled_args" | grep -F -- '--snat-subnet-routes=false' >/dev/null || \
	fail "site-to-site enable must pass --snat-subnet-routes=false"
printf '%s\n' "$snat_disabled_args" | grep -F 'DISABLE_SNAT_SUBNET_ROUTES=1' >/dev/null || \
	fail "site-to-site enable must pass no-SNAT state to the firewall helper"
printf '%s\n' "$snat_disabled_args" | grep -F 'TAILSCALE_STATE_WAS_PRESENT=1' >/dev/null || \
	fail "existing state detection must be passed to the helper without exposing the state file"

fresh_state_args="$(capture_tailscale_snat_args 0 0)"
printf '%s\n' "$fresh_state_args" | grep -F 'TAILSCALE_STATE_WAS_PRESENT=0' >/dev/null || \
	fail "first enrollment must tell the helper that no state existed before daemon startup"

[ "$(capture_start_state_flag 1)" = "1" ] || \
	fail "start_instance must detect a non-empty identity before starting tailscaled"
[ "$(capture_start_state_flag 0)" = "0" ] || \
	fail "start_instance must preserve first-enrollment intent before tailscaled can create state"

snat_enabled_args="$(capture_tailscale_snat_args 0)"
printf '%s\n' "$snat_enabled_args" | grep -F -- '--snat-subnet-routes=true' >/dev/null || \
	fail "site-to-site disable must pass --snat-subnet-routes=true"
printf '%s\n' "$snat_enabled_args" | grep -F 'DISABLE_SNAT_SUBNET_ROUTES=0' >/dev/null || \
	fail "site-to-site disable must pass SNAT state to the firewall helper"

normalized_default="$(
	. "$INIT_SCRIPT"
	normalize_tailscale_port ""
)"
[ "$normalized_default" = "41641" ] || fail "empty Tailscale port should normalize to 41641"

normalized_invalid="$(
	. "$INIT_SCRIPT"
	normalize_tailscale_port "invalid"
)"
[ "$normalized_invalid" = "41641" ] || fail "non-numeric Tailscale port should normalize to 41641"

normalized_out_of_range="$(
	. "$INIT_SCRIPT"
	normalize_tailscale_port "70000"
)"
[ "$normalized_out_of_range" = "41641" ] || fail "out-of-range Tailscale port should normalize to 41641"

normalized_custom="$(
	. "$INIT_SCRIPT"
	normalize_tailscale_port "42424"
)"
[ "$normalized_custom" = "42424" ] || fail "valid Tailscale port should be preserved"

echo "tailscale init AdGuard lifecycle tests passed"
