#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/root/usr/sbin/tailscale_adguard_dns_switch"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-adguard-dns-test.$$"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_eq() {
	expected="$1"
	actual="$2"
	message="$3"

	[ "$expected" = "$actual" ] || fail "$message
expected: $expected
actual:   $actual"
}

assert_contains() {
	needle="$1"
	haystack="$2"
	message="$3"

	printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null || fail "$message
missing: $needle
actual:  $haystack"
}

assert_occurrences() {
	expected="$1"
	needle="$2"
	file="$3"
	message="$4"
	actual="$(grep -F -c -- "$needle" "$file" || true)"

	[ "$expected" = "$actual" ] || fail "$message
expected occurrences: $expected
actual occurrences:   $actual
needle: $needle"
}

make_fake_uci() {
	cat >"$TMP_DIR/uci" <<'SH'
#!/bin/sh
case "$*" in
	"-q get tailscale.settings.adguard_dns_switch_enabled") echo "${UCI_SWITCH_ENABLED:-1}" ;;
	"-q get tailscale.settings.accept_dns") echo "${UCI_ACCEPT_DNS:-1}" ;;
	"-q get tailscale.settings.adguard_api_url") echo "${UCI_API_URL:-http://127.0.0.1:3000}" ;;
	"-q get tailscale.settings.adguard_username") echo "${UCI_API_USER:-}" ;;
	"-q get tailscale.settings.adguard_password") echo "${UCI_API_PASS:-}" ;;
	"-q get tailscale.settings.adguard_health_domain") echo "${UCI_HEALTH_DOMAIN:-service.example.test}" ;;
	"-q get tailscale.settings.adguard_check_interval") echo "${UCI_CHECK_INTERVAL:-10}" ;;
	"-q get tailscale.settings.adguard_success_threshold") echo "${UCI_SUCCESS_THRESHOLD:-2}" ;;
	"-q get tailscale.settings.adguard_failure_threshold") echo "${UCI_FAILURE_THRESHOLD:-2}" ;;
	"-q get tailscale.settings.adguard_default_upstreams")
		[ "${UCI_EMPTY_DEFAULT_UPSTREAMS:-0}" = "1" ] && exit 1
		echo "[/lan/]127.0.0.1:5353 9.9.9.9 100.100.100.100 149.112.112.112 9.9.9.9"
		;;
	"-q get tailscale.settings.adguard_tailnet_upstreams")
		echo "[/example.ts.net/]100.100.100.100 [/internal.example/]100.100.100.100"
		;;
	"-q get tailscale.settings.adguard_health_expected_ips") echo "10.23.0.15" ;;
	"-q get network.lan.ipaddr") echo "${UCI_LAN_IP:-192.168.100.1}" ;;
	"-q get dhcp.lan.dhcp_option") echo "${UCI_DHCP_OPTIONS:-6,192.168.100.1}" ;;
	"show tailscale.settings.adguard_default_upstreams")
		[ "${UCI_EMPTY_DEFAULT_UPSTREAMS:-0}" = "1" ] && exit 0
		echo "tailscale.settings.adguard_default_upstreams='[/lan/]127.0.0.1:5353' '9.9.9.9' '100.100.100.100' '149.112.112.112' '9.9.9.9'"
		;;
	"show tailscale.settings.adguard_tailnet_upstreams")
		echo "tailscale.settings.adguard_tailnet_upstreams='[/example.ts.net/]100.100.100.100' '[/internal.example/]100.100.100.100'"
		;;
	"show tailscale.settings.adguard_health_expected_ips")
		echo "tailscale.settings.adguard_health_expected_ips='10.23.0.15'"
		;;
	*) exit 1 ;;
esac
SH
	chmod +x "$TMP_DIR/uci"
}

make_fake_commands() {
	make_fake_uci

	cat >"$TMP_DIR/secrets" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${SECRETS_LOG:?}"
case "${1:-}" in
	adguard-password-for)
		requested_url="${2:-}"
		requested_user="${3:-}"
		bound_url="${SECRET_BOUND_URL:-${UCI_API_URL:-http://127.0.0.1:3000}}"
		bound_url="${bound_url%/}"
		bound_user="${SECRET_BOUND_USER:-${UCI_API_USER:-}}"
		[ "$requested_url" = "$bound_url" ] && [ "$requested_user" = "$bound_user" ] || exit 1
		[ -n "${SECRET_PASSWORD:-}" ] || exit 1
		printf '%s\n' "$SECRET_PASSWORD"
		;;
	*) exit 1 ;;
esac
SH
	chmod +x "$TMP_DIR/secrets"

	cat >"$TMP_DIR/nslookup" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${NSLOOKUP_LOG:?}"
if [ "${NSLOOKUP_HEALTH:-ok}" = "ok" ]; then
	cat <<'OUT'
Server:		100.100.100.100
Address:	100.100.100.100:53
Name:	service.example.test
Address: 10.23.0.15
OUT
else
	cat <<'OUT'
Server:		100.100.100.100
Address:	100.100.100.100:53
** server can't find service.example.test: SERVFAIL
OUT
	exit 1
fi
SH
	chmod +x "$TMP_DIR/nslookup"

	cat >"$TMP_DIR/curl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${CURL_LOG:?}"
read_config=0
for arg in "$@"; do
	if [ "$read_config" = "1" ]; then
		cat "$arg" >>"${CURL_AUTH_LOG:?}"
		read_config=0
	elif [ "$arg" = "--config" ]; then
		read_config=1
	fi
done
case "$*" in
	*"/control/status"*) echo '{"running":true,"dns_port":53}' ;;
	*"/control/dns_info"*)
		[ "${CURL_DNS_INFO_FAIL:-0}" = "1" ] && exit 1
		cat "${DNS_INFO_JSON:?}"
		;;
	*"/control/dns_config"*)
		body=
		while [ "$#" -gt 0 ]; do
			if [ "$1" = "--data-binary" ]; then
				shift
				body="${1#@}"
			fi
			shift
		done
		[ "${CURL_DNS_CONFIG_FAIL:-0}" = "1" ] && exit 1
		[ -n "$body" ] && cat "$body" >"${POSTED_JSON:?}"
		echo OK
		;;
	*"/control/test_upstream_dns"*)
		body=
		while [ "$#" -gt 0 ]; do
			if [ "$1" = "--data-binary" ]; then
				shift
				body="${1#@}"
			fi
			shift
		done
		[ -n "$body" ] && cat "$body" >"${TEST_UPSTREAM_JSON:?}"
		[ "${CURL_TEST_UPSTREAM_FAIL:-0}" = "1" ] && exit 1
		if [ -n "${CURL_TEST_UPSTREAM_RESPONSE:-}" ]; then
			printf '%s\n' "$CURL_TEST_UPSTREAM_RESPONSE"
		else
			cat <<'JSON'
{"[/lan/]127.0.0.1:5353":"OK","9.9.9.9":"OK","149.112.112.112":"OK"}
JSON
		fi
		;;
	*"/control/cache_clear"*)
		[ "${CURL_CACHE_CLEAR_FAIL:-0}" = "1" ] && exit 1
		echo OK
		;;
	*) echo OK ;;
esac
SH
	chmod +x "$TMP_DIR/curl"

	cat >"$TMP_DIR/flock" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${FLOCK_LOG:?}"
[ "${FLOCK_FAIL:-0}" = "0" ]
SH
	chmod +x "$TMP_DIR/flock"

	cat >"$TMP_DIR/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${LOGGER_LOG:?}"
SH
	chmod +x "$TMP_DIR/logger"

cat >"$TMP_DIR/sleep" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${SLEEP_LOG:?}"
count_file="${SLEEP_COUNT_FILE:?}"
count="$(cat "$count_file" 2>/dev/null || echo 0)"
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [ "$count" -ge "${SLEEP_MAX_CALLS:-1}" ]; then
	kill -TERM "$PPID"
fi
exit 0
SH
	chmod +x "$TMP_DIR/sleep"

	cat >"$TMP_DIR/pgrep" <<'SH'
#!/bin/sh
[ "${PGREP_ADGUARD:-1}" = "1" ] && exit 0
exit 1
SH
	chmod +x "$TMP_DIR/pgrep"

	cat >"$TMP_DIR/netstat" <<'SH'
#!/bin/sh
if [ "${NETSTAT_ADGUARD_53:-1}" = "1" ]; then
	echo "udp        0      0 0.0.0.0:53              0.0.0.0:*                           1234/AdGuardHome"
else
	echo "udp        0      0 0.0.0.0:53              0.0.0.0:*                           1234/dnsmasq"
fi
SH
	chmod +x "$TMP_DIR/netstat"

	cat >"$TMP_DIR/ubus" <<'SH'
#!/bin/sh
cat <<'OUT'
{"ipv4-address":[{"address":"192.168.100.1","mask":24}]}
OUT
SH
	chmod +x "$TMP_DIR/ubus"

cat >"$TMP_DIR/jq" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${JQ_LOG:?}"
[ "${JQ_REPLACE_FAIL:-0}" = "1" ] && printf '%s\n' "$*" | grep -F -- '--rawfile upstreams' >/dev/null && exit 1
exec "${REAL_JQ:?}" "$@"
SH
	chmod +x "$TMP_DIR/jq"

	PATH="$TMP_DIR:$PATH"
	export PATH
}

prepare_api_json() {
	CURL_LOG="$TMP_DIR/curl.log"
	CURL_AUTH_LOG="$TMP_DIR/curl-auth.log"
	FLOCK_LOG="$TMP_DIR/flock.log"
	LOGGER_LOG="$TMP_DIR/logger.log"
	DNS_INFO_JSON="$TMP_DIR/dns-info.json"
	POSTED_JSON="$TMP_DIR/posted.json"
	TEST_UPSTREAM_JSON="$TMP_DIR/test-upstream.json"
	JQ_LOG="$TMP_DIR/jq.log"
	NSLOOKUP_LOG="$TMP_DIR/nslookup-call.log"
	SLEEP_LOG="$TMP_DIR/sleep.log"
	SLEEP_COUNT_FILE="$TMP_DIR/sleep.count"
	SECRETS_LOG="$TMP_DIR/secrets.log"
	REAL_JQ="${REAL_JQ:-$(command -v jq)}"
	STATE_DIR="$TMP_DIR/state"
	export CURL_LOG CURL_AUTH_LOG FLOCK_LOG LOGGER_LOG DNS_INFO_JSON POSTED_JSON TEST_UPSTREAM_JSON JQ_LOG NSLOOKUP_LOG SLEEP_LOG SLEEP_COUNT_FILE SECRETS_LOG REAL_JQ STATE_DIR
	: >"$CURL_AUTH_LOG"
	: >"$FLOCK_LOG"
	: >"$SECRETS_LOG"
	printf '0\n' >"$SLEEP_COUNT_FILE"

	cat >"$DNS_INFO_JSON" <<'JSON'
{"upstream_dns":["1.1.1.1"],"bootstrap_dns":["223.5.5.5"],"fallback_dns":["119.29.29.29"],"cache_enabled":false,"cache_size":4194304}
JSON
}

run_script() {
	UCI_CMD="$TMP_DIR/uci" \
	SECRETS_BIN="$TMP_DIR/secrets" \
	CURL_CMD="$TMP_DIR/curl" \
	FLOCK_CMD="$TMP_DIR/flock" \
	LOGGER_CMD="$TMP_DIR/logger" \
	NSLOOKUP_CMD="$TMP_DIR/nslookup" \
	PGREP_CMD="$TMP_DIR/pgrep" \
	NETSTAT_CMD="$TMP_DIR/netstat" \
	UBUS_CMD="$TMP_DIR/ubus" \
	JQ_CMD="$TMP_DIR/jq" \
	SLEEP_CMD="$TMP_DIR/sleep" \
	"$SCRIPT" "$@"
}

test_persisted_password_is_bound_to_saved_endpoint() {
	: >"$CURL_AUTH_LOG"
	: >"$SECRETS_LOG"
	UCI_API_URL='http://attacker.example:3000' \
	UCI_API_USER='saved-user' \
	UCI_API_PASS='legacy-readable-secret' \
	SECRET_BOUND_URL='http://saved.example:3000' \
	SECRET_BOUND_USER='saved-user' \
	SECRET_PASSWORD='protected-secret' \
		run_script --preflight >/dev/null || true

	if grep -F -- 'legacy-readable-secret' "$CURL_AUTH_LOG" >/dev/null || grep -F -- 'protected-secret' "$CURL_AUTH_LOG" >/dev/null; then
		fail "a changed AdGuard endpoint must not receive either legacy or protected saved passwords"
	fi
	assert_contains 'adguard-password-for http://attacker.example:3000 saved-user' "$(cat "$SECRETS_LOG")" "runtime must verify the endpoint binding before loading the protected password"
}

test_preflight_uses_candidate_configuration() {
	: >"$CURL_LOG"
	: >"$CURL_AUTH_LOG"
	: >"$NSLOOKUP_LOG"

	out="$(
		TAILSCALE_ADGUARD_PREFLIGHT_CANDIDATE=1 \
		TAILSCALE_ADGUARD_PREFLIGHT_API_URL='http://candidate.example:3000' \
		TAILSCALE_ADGUARD_PREFLIGHT_USERNAME='candidate-user' \
		TAILSCALE_ADGUARD_PREFLIGHT_PASSWORD_SET=1 \
		TAILSCALE_ADGUARD_PREFLIGHT_PASSWORD='candidate-secret' \
		TAILSCALE_ADGUARD_PREFLIGHT_DEFAULT_UPSTREAMS="$(printf '1.1.1.1\n8.8.8.8')" \
		TAILSCALE_ADGUARD_PREFLIGHT_TAILNET_UPSTREAMS='[/candidate.example/]100.100.100.100' \
		TAILSCALE_ADGUARD_PREFLIGHT_HEALTH_DOMAIN='candidate-health.example' \
		TAILSCALE_ADGUARD_PREFLIGHT_EXPECTED_IPS='10.23.0.15' \
		run_script --preflight
	)"

	assert_contains 'ready=pass' "$out" "candidate configuration should pass preflight"
	assert_eq '{"upstream_dns":["1.1.1.1","8.8.8.8"]}' "$(cat "$TEST_UPSTREAM_JSON")" "preflight API payload must use candidate upstreams instead of persisted UCI"
	assert_contains 'candidate-health.example 100.100.100.100' "$(cat "$NSLOOKUP_LOG")" "health check must use the candidate domain"
	assert_contains 'http://candidate.example:3000/control/status' "$(cat "$CURL_LOG")" "AdGuard API checks must use the candidate URL"
	assert_contains 'user = "candidate-user:candidate-secret"' "$(cat "$CURL_AUTH_LOG")" "curl must receive candidate credentials through a protected config"
	if grep -F -- 'candidate-secret' "$CURL_LOG" >/dev/null || grep -F -- '-u ' "$CURL_LOG" >/dev/null; then
		fail "AdGuard credentials must not appear in curl argv"
	fi
}

test_profile_generation() {
	up="$(run_script --profile up)"
	down="$(run_script --profile down)"

	assert_eq "[/lan/]127.0.0.1:5353
[/example.ts.net/]100.100.100.100
[/internal.example/]100.100.100.100
9.9.9.9
149.112.112.112
100.100.100.100" "$up" "up profile should place tailnet conditionals before public defaults"
	assert_eq "[/lan/]127.0.0.1:5353
9.9.9.9
149.112.112.112" "$down" "down profile should remove 100.100.100.100 and dedupe defaults"
}

test_health_check() {
	NSLOOKUP_HEALTH=ok run_script --check-health >/dev/null
	nslookup_call="$(cat "$TMP_DIR/nslookup-call.log")"
	assert_contains "service.example.test 100.100.100.100" "$nslookup_call" "health check must use hard-coded Tailscale DNS"
	if NSLOOKUP_HEALTH=fail run_script --check-health >/dev/null 2>&1; then
		fail "failed nslookup must make health check fail"
	fi
}

test_preflight_reports_failures() {
	out="$(NETSTAT_ADGUARD_53=0 run_script --preflight || true)"
	assert_contains "port_53_adguard=fail" "$out" "preflight should report port 53 ownership failure"
	assert_contains "ready=fail" "$out" "preflight should not be ready when a required check fails"
}

test_preflight_requires_api_post_test() {
	out="$(CURL_TEST_UPSTREAM_FAIL=1 run_script --preflight || true)"
	assert_contains "adguard_api=fail" "$out" "preflight should report AdGuard API test POST failure"
	assert_contains "ready=fail" "$out" "preflight should not be ready when AdGuard API test POST fails"

	if CURL_TEST_UPSTREAM_FAIL=1 run_script --preflight >/dev/null 2>&1; then
		fail "preflight should fail when AdGuard test_upstream_dns POST fails"
	fi
	if grep -F '/control/dns_config' "$CURL_LOG" >/dev/null; then
		fail "preflight must not POST to /control/dns_config"
	fi
	assert_contains "/control/test_upstream_dns" "$(cat "$CURL_LOG")" "preflight should POST to test_upstream_dns"
	assert_eq '{"upstream_dns":["[/lan/]127.0.0.1:5353","9.9.9.9","149.112.112.112"]}' "$(cat "$TEST_UPSTREAM_JSON")" "preflight API payload should come from configured default upstreams"
	assert_contains "--rawfile upstreams" "$(cat "$JQ_LOG")" "preflight API payload should be built from the validated upstream file with jq"
}

test_preflight_rejects_upstream_error_response() {
	out="$(CURL_TEST_UPSTREAM_RESPONSE='{"[/lan/]127.0.0.1:5353":"OK","9.9.9.9":"upstream timeout","149.112.112.112":"OK"}' run_script --preflight || true)"

	assert_contains "adguard_api=fail" "$out" "preflight should fail the AdGuard API check when an upstream test reports an error"
	assert_contains "ready=fail" "$out" "preflight should not be ready when an upstream test reports an error"
}

test_preflight_requires_configured_default_upstream() {
	: >"$LOGGER_LOG"
	out="$(UCI_EMPTY_DEFAULT_UPSTREAMS=1 run_script --preflight || true)"
	assert_contains "adguard_api=fail" "$out" "preflight should fail the API check when no default upstream is configured"
	assert_contains "ready=fail" "$out" "preflight should not be ready without a default upstream"
	assert_contains "requires at least one valid default upstream" "$(cat "$LOGGER_LOG")" "empty default upstream failure should be logged clearly"
}

test_preflight_does_not_require_accept_dns() {
	out="$(UCI_ACCEPT_DNS=0 run_script --preflight)"
	assert_contains "ready=pass" "$out" "preflight should pass when direct Tailscale DNS health checks work with accept_dns disabled"
	if printf '%s' "$out" | grep -F 'accept_dns=' >/dev/null; then
		fail "accept_dns should not be a blocking AdGuard DNS auto switch preflight check"
	fi
}

test_apply_profile_preserves_dns_info() {
	: >"$FLOCK_LOG"
	run_script --apply-profile up

	posted="$(cat "$POSTED_JSON")"
	assert_contains '"bootstrap_dns":["223.5.5.5"]' "$posted" "API payload should preserve bootstrap_dns"
	assert_contains '"fallback_dns":["119.29.29.29"]' "$posted" "API payload should preserve fallback_dns"
	assert_contains '"upstream_dns":["[/lan/]127.0.0.1:5353","[/example.ts.net/]100.100.100.100","[/internal.example/]100.100.100.100","9.9.9.9","149.112.112.112","100.100.100.100"]' "$posted" "API payload should replace upstream_dns"
	assert_contains "--rawfile upstreams" "$(cat "$JQ_LOG")" "profile application should use jq with raw upstream file input"
	assert_contains "--connect-timeout 3" "$(cat "$CURL_LOG")" "curl calls should include a connect timeout"
	assert_contains "--max-time 10" "$(cat "$CURL_LOG")" "curl calls should include a max time"
	assert_contains "/control/cache_clear" "$(cat "$CURL_LOG")" "profile application should always clear AdGuard cache after switching"
	assert_contains "-x 9" "$(cat "$FLOCK_LOG")" "profile application must acquire an exclusive lock"
}

test_down_profile_uses_saved_snapshot_when_config_is_cleared() {
	rm -rf "$STATE_DIR"
	mkdir -p "$STATE_DIR"
	run_script --apply-profile up

	[ -s "$STATE_DIR/down_profile" ] || fail "switching up must persist a recoverable down profile"
	: >"$CURL_LOG"
	rm -f "$POSTED_JSON"
	if ! UCI_EMPTY_DEFAULT_UPSTREAMS=1 run_script --apply-profile down; then
		fail "saved down-profile recovery failed
logger: $(cat "$LOGGER_LOG")
curl: $(cat "$CURL_LOG")"
	fi

	assert_contains '"upstream_dns":["[/lan/]127.0.0.1:5353","9.9.9.9","149.112.112.112"]' "$(cat "$POSTED_JSON")" "a saved down profile must restore public DNS after the new UCI defaults are cleared"
	assert_eq "down" "$(cat "$STATE_DIR/current_profile")" "successful recovery must record the down profile"
}

test_apply_profile_fails_when_lock_is_unavailable() {
	: >"$CURL_LOG"
	if FLOCK_FAIL=1 run_script --apply-profile up >/dev/null 2>&1; then
		fail "profile application must fail when the exclusive lock cannot be acquired"
	fi
	if grep -F '/control/dns_info' "$CURL_LOG" >/dev/null; then
		fail "profile application must not touch AdGuard before acquiring the lock"
	fi
}

test_symlink_state_directory_is_rejected() {
	evil_dir="$TMP_DIR/evil-state-target"
	rm -rf "$STATE_DIR" "$evil_dir"
	mkdir -p "$evil_dir"
	ln -s "$evil_dir" "$STATE_DIR"

	if run_script --apply-profile up >/dev/null 2>&1; then
		fail "a symlink state directory must be rejected"
	fi
	[ -z "$(find "$evil_dir" -mindepth 1 -print -quit)" ] || fail "a rejected symlink state directory must not receive root-written files"

	rm -f "$STATE_DIR"
	mkdir -p "$STATE_DIR"
}

test_empty_profile_does_not_write_dns_config() {
	: >"$CURL_LOG"
	rm -f "$POSTED_JSON"

	if UCI_EMPTY_DEFAULT_UPSTREAMS=1 run_script --apply-profile down >/dev/null 2>&1; then
		fail "empty down profile should make apply-profile fail"
	fi
	if [ -e "$POSTED_JSON" ]; then
		fail "empty profile must not write dns_config payload"
	fi
	if grep -F '/control/dns_config' "$CURL_LOG" >/dev/null; then
		fail "empty profile must not POST to /control/dns_config"
	fi
}

test_run_loop_applies_down_profile_when_initial_health_fails() {
	: >"$CURL_LOG"
	: >"$SLEEP_LOG"
	rm -f "$POSTED_JSON"
	mkdir -p "$STATE_DIR"
	printf 'up\n' >"$STATE_DIR/current_profile"
	printf '0\n' >"$SLEEP_COUNT_FILE"

	UCI_FAILURE_THRESHOLD=1 NSLOOKUP_HEALTH=fail UCI_CHECK_INTERVAL=1 run_script --run >/dev/null 2>&1 || true

	posted="$(cat "$POSTED_JSON")"
	assert_contains '"upstream_dns":["[/lan/]127.0.0.1:5353","9.9.9.9","149.112.112.112"]' "$posted" "run loop should apply down profile when health initially fails"
	assert_contains "1" "$(cat "$SLEEP_LOG")" "run loop should continue after applying the down profile"
}

test_run_loop_runs_static_preflight_once_before_health_polling() {
	rm -rf "$STATE_DIR"
	mkdir -p "$STATE_DIR"
	: >"$CURL_LOG"
	: >"$NSLOOKUP_LOG"
	: >"$SLEEP_LOG"
	printf 'up\n' >"$STATE_DIR/current_profile"
	printf '0\n' >"$SLEEP_COUNT_FILE"

	SLEEP_MAX_CALLS=3 UCI_CHECK_INTERVAL=1 run_script --run >/dev/null 2>&1 || true

	assert_occurrences 1 "/control/test_upstream_dns" "$CURL_LOG" "static AdGuard API preflight should run only once after it succeeds"
	assert_occurrences 3 "service.example.test 100.100.100.100" "$NSLOOKUP_LOG" "health polling should continue after static preflight succeeds"
}

test_run_loop_retries_static_preflight_failures_without_exit_churn() {
	rm -rf "$STATE_DIR"
	mkdir -p "$STATE_DIR"
	: >"$LOGGER_LOG"
	: >"$SLEEP_LOG"
	printf '0\n' >"$SLEEP_COUNT_FILE"

	SLEEP_MAX_CALLS=3 NETSTAT_ADGUARD_53=0 UCI_CHECK_INTERVAL=1 run_script --run >/dev/null 2>&1 || true

	assert_eq "3" "$(cat "$SLEEP_COUNT_FILE")" "static preflight failure should stay in the worker and retry internally"
	assert_occurrences 1 "static preflight failed: port_53_adguard" "$LOGGER_LOG" "identical static preflight failures should be rate-limited without hiding the first"

	printf '0\n' >"$SLEEP_COUNT_FILE"
	SLEEP_MAX_CALLS=1 PGREP_ADGUARD=0 UCI_CHECK_INTERVAL=1 run_script --run >/dev/null 2>&1 || true
	assert_occurrences 1 "static preflight failed: adguard_process" "$LOGGER_LOG" "a different static preflight failure should log immediately"
}

test_profile_failures_are_rate_limited_by_signature() {
	rm -rf "$STATE_DIR"
	mkdir -p "$STATE_DIR"
	: >"$LOGGER_LOG"

	CURL_DNS_INFO_FAIL=1 run_script --apply-profile up >/dev/null 2>&1 || true
	CURL_DNS_INFO_FAIL=1 run_script --apply-profile up >/dev/null 2>&1 || true
	assert_occurrences 1 "failed to read AdGuard DNS config" "$LOGGER_LOG" "repeated profile read failures should be rate-limited"

	JQ_REPLACE_FAIL=1 run_script --apply-profile up >/dev/null 2>&1 || true
	JQ_REPLACE_FAIL=1 run_script --apply-profile up >/dev/null 2>&1 || true
	assert_occurrences 1 "failed to build AdGuard DNS config payload" "$LOGGER_LOG" "repeated profile build failures should be rate-limited"

	CURL_DNS_CONFIG_FAIL=1 run_script --apply-profile up >/dev/null 2>&1 || true
	CURL_DNS_CONFIG_FAIL=1 run_script --apply-profile up >/dev/null 2>&1 || true
	assert_occurrences 1 "failed to write AdGuard DNS up profile" "$LOGGER_LOG" "repeated profile write failures should be rate-limited"

	CURL_CACHE_CLEAR_FAIL=1 run_script --apply-profile up >/dev/null 2>&1
	CURL_CACHE_CLEAR_FAIL=1 run_script --apply-profile up >/dev/null 2>&1
	assert_occurrences 1 "AdGuard cache clear failed after up profile switch" "$LOGGER_LOG" "repeated cache-clear failures should be rate-limited"
}

mkdir -p "$TMP_DIR"
REAL_JQ="${REAL_JQ:-$(command -v jq)}"
export REAL_JQ
make_fake_commands
prepare_api_json

test_profile_generation
test_health_check
test_preflight_reports_failures
test_preflight_requires_api_post_test
test_preflight_rejects_upstream_error_response
test_preflight_requires_configured_default_upstream
test_preflight_does_not_require_accept_dns
test_preflight_uses_candidate_configuration
test_persisted_password_is_bound_to_saved_endpoint
test_apply_profile_preserves_dns_info
test_down_profile_uses_saved_snapshot_when_config_is_cleared
test_apply_profile_fails_when_lock_is_unavailable
test_symlink_state_directory_is_rejected
test_empty_profile_does_not_write_dns_config
test_run_loop_applies_down_profile_when_initial_health_fails
test_run_loop_runs_static_preflight_once_before_health_polling
test_run_loop_retries_static_preflight_failures_without_exit_churn
test_profile_failures_are_rate_limited_by_signature

echo "tailscale_adguard_dns_switch tests passed"
