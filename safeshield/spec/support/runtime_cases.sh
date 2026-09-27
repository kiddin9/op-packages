#!/bin/sh
# shellcheck shell=sh

ss_case_refreshd_wait() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	WAIT_PID=''
	trap 'if [ -n "$WAIT_PID" ]; then kill "$WAIT_PID" 2>/dev/null || true; wait "$WAIT_PID" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT HUP INT TERM
	REFRESHD="$SS_SPEC_ROOT/files/usr/libexec/safeshield-refreshd"
	HARNESS="$TMP/refreshd-wait.sh"
	mkdir -p "$TMP/bin"
	awk '
	    /^ss_should_terminate=0$/ { print }
	    /^ss_sleep_pid=/ { print }
	    /^handle_term\(\) \{$/, /^}$/ { print }
	    /^sleep_seconds\(\) \{$/, /^}$/ { print }
	' "$REFRESHD" >"$HARNESS"
	# shellcheck disable=SC1090
	. "$HARNESS"
	REAL_SLEEP="$(command -v sleep)"
	SLEEP_CALLS="$TMP/sleep.calls"
	SLEEP_PID_FILE="$TMP/sleep.pid"
	cat >"$TMP/bin/sleep" <<'EOF_SLEEP'
#!/bin/sh
printf '%s\n' "$*" >>"$SLEEP_CALLS"
printf '%s\n' "$$" >"$SLEEP_PID_FILE"
exec "$REAL_SLEEP" "$@"
EOF_SLEEP
	chmod 755 "$TMP/bin/sleep"
	export REAL_SLEEP SLEEP_CALLS SLEEP_PID_FILE
	(
		trap 'handle_term' TERM INT
		PATH="$TMP/bin:$PATH"
		export PATH
		sleep_seconds 30
	) &
	WAIT_PID=$!
	tries=0
	while [ ! -s "$SLEEP_PID_FILE" ]; do
		tries=$((tries + 1))
		[ "$tries" -lt 100 ] || return 1
		sleep 0.02
	done
	SLEEP_PID="$(cat "$SLEEP_PID_FILE")"
	kill -TERM "$WAIT_PID"
	tries=0
	while kill -0 "$WAIT_PID" 2>/dev/null; do
		tries=$((tries + 1))
		[ "$tries" -lt 100 ] || return 1
		sleep 0.02
	done
	wait "$WAIT_PID" 2>/dev/null || true
	WAIT_PID=''
	ss_spec_assert_eq "$(cat "$SLEEP_CALLS")" '30'
	tries=0
	while kill -0 "$SLEEP_PID" 2>/dev/null; do
		tries=$((tries + 1))
		[ "$tries" -lt 100 ] || return 1
		sleep 0.02
	done
)

ss_case_statistics_collector() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	STATSD_PID=''
	trap 'if [ -n "$STATSD_PID" ]; then kill "$STATSD_PID" 2>/dev/null || true; wait "$STATSD_PID" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT HUP INT TERM
	mkdir -p "$TMP/bin" "$TMP/statistics"
	cat >"$TMP/functions.sh" <<'EOF_FUNCTIONS'
# test stub
EOF_FUNCTIONS
	cat >"$TMP/core.sh" <<EOF_CORE
ss_enabled=1
ss_statistics_enabled=1
ss_statistics_snapshot_interval_s=60
ss_statistics_retention_hours=168
SS_STATISTICS_DIR='$TMP/statistics'
SS_STATISTICS_STATE_FILE='$TMP/statistics/state.tsv'
SS_STATISTICS_JSON_FILE='$TMP/statistics/statistics.json'
SS_STATISTICS_UPLOAD_JSON_FILE='$TMP/statistics/upload.json'
SS_IDENTITY_PROFILE='gl_mt300n_v2'
. '$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics.sh'
ss_load_config() { return 0; }
ss_dnsmasq_safeshield_block_supported() { return 0; }
command_exists() { command -v "\$1" >/dev/null 2>&1; }
log_info() { :; }
log_warn() { :; }
log_error() { printf '%s\n' "\$*" >&2; }
EOF_CORE
	cat >"$TMP/bin/stats-poll" <<'EOF_POLL'
#!/bin/sh
printf '%s\n' '1' >>"$POLL_COUNT_FILE"
printf '%s\n' 'snapshot	runtime-instance	udp	128	1	0	0	10	2'
printf '%s\n' 'client	192.168.1.2	10	2'
printf '%s\n' 'commit'
EOF_POLL
	cat >"$TMP/bin/awk" <<'EOF_AWK'
#!/bin/sh
printf '%s\n' "$$" >"$AWK_PID_FILE"
printf '%s\n' "$@" >"$AWK_ARGS_FILE"
while IFS= read -r line; do
	printf '%s\n' "$line" >>"$AWK_INPUT_FILE"
done
EOF_AWK
	cat >"$TMP/bin/ip" <<'EOF_IP'
#!/bin/sh
exit 0
EOF_IP
	chmod 755 "$TMP/bin/stats-poll" "$TMP/bin/awk" "$TMP/bin/ip"
	POLL_COUNT_FILE="$TMP/poll-count"
	AWK_PID_FILE="$TMP/awk.pid"
	AWK_ARGS_FILE="$TMP/awk.args"
	AWK_INPUT_FILE="$TMP/awk.input"
	export POLL_COUNT_FILE AWK_PID_FILE AWK_ARGS_FILE AWK_INPUT_FILE
	PATH="$TMP/bin:$PATH" \
		SS_STATSD_FUNCTIONS_LIB="$TMP/functions.sh" \
		SS_STATSD_CORE_LIB="$TMP/core.sh" \
		SS_STATSD_AWK_DIR="$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics" \
		SS_STATSD_POLL_COMMAND="$TMP/bin/stats-poll" \
		SS_STATSD_GENERATION_ID='runtime-generation' \
		SS_STATSD_PERSISTENT_STATE_FILE="$TMP/flash/statistics-state.tsv" \
		SS_STATSD_PERSISTENT_JOURNAL_FILE="$TMP/flash/statistics-journal.tsv" \
		sh "$SS_SPEC_ROOT/files/usr/libexec/safeshield-statsd" &
	STATSD_PID=$!
	tries=0
	while [ ! -s "$AWK_PID_FILE" ] || ! grep -Fx 'commit' "$AWK_INPUT_FILE" >/dev/null 2>&1; do
		tries=$((tries + 1))
		[ "$tries" -lt 100 ] || return 1
		sleep 0.02
	done
	AWK_PID="$(cat "$AWK_PID_FILE")"
	ss_spec_assert_file_line "$AWK_ARGS_FILE" 'snapshot_interval=300'
	ss_spec_assert_file_line "$AWK_ARGS_FILE" 'identity_cache_ttl=60'
	ss_spec_assert_file_line "$AWK_ARGS_FILE" 'generation_seed=runtime-generation'
	ss_spec_assert_file_line "$AWK_ARGS_FILE" 'force_rebaseline=0'
	ss_spec_assert_file_line "$AWK_ARGS_FILE" "rebaseline_file=$TMP/statistics/rebaseline"
	ss_spec_assert_file_line "$AWK_ARGS_FILE" 'ipv6_neigh_command=ip -6 neigh show 2>/dev/null'
	ss_spec_assert_file_line "$AWK_ARGS_FILE" "$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics/20-identity.awk"
	ss_spec_assert_file_line "$AWK_ARGS_FILE" "$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics/90-main.awk"
	ss_spec_assert_file_line "$AWK_ARGS_FILE" 'persistent_state_file='
	ss_spec_assert_file_line "$AWK_ARGS_FILE" 'persistent_journal_file='
	ss_spec_assert_file_line "$AWK_ARGS_FILE" "upload_json_file=$TMP/statistics/upload.json"
	ss_spec_assert_file_line "$AWK_ARGS_FILE" 'upload_window_hours=2'
	ss_spec_assert_file_line "$AWK_INPUT_FILE" 'snapshot	runtime-instance	udp	128	1	0	0	10	2'
	ss_spec_assert_file_line "$AWK_INPUT_FILE" 'client	192.168.1.2	10	2'
	ss_spec_assert_eq "$(cat "$POLL_COUNT_FILE")" '1'
	[ ! -e "$TMP/flash" ]
	kill -TERM "$STATSD_PID"
	wait "$STATSD_PID" 2>/dev/null || true
	STATSD_PID=''
	sleep 0.05
	! kill -0 "$AWK_PID" 2>/dev/null
	[ ! -e "$TMP/statistics/collector.lock" ]
	! find "$TMP/statistics" -maxdepth 1 -name 'events.*' | grep . >/dev/null
)

ss_case_statistics_reconcile() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	SS_DNSMASQ_DIR="$TMP/dnsmasq.d"
	SS_STATISTICS_DIR="$TMP/statistics"
	SS_STATISTICS_DNSMASQ_CONF="$SS_DNSMASQ_DIR/safeshield.statistics.conf"
	SS_STATISTICS_POLL_COMMAND="$TMP/stats-poll"
	SS_STATISTICS_REBASELINE_FILE="$SS_STATISTICS_DIR/rebaseline"
	PKG_NAME='safeshield'
	ss_enabled=1
	ss_statistics_enabled=0
	export SS_DNSMASQ_DIR SS_STATISTICS_DIR SS_STATISTICS_DNSMASQ_CONF SS_STATISTICS_POLL_COMMAND SS_STATISTICS_REBASELINE_FILE PKG_NAME
	export ss_enabled ss_statistics_enabled
	cat >"$SS_STATISTICS_POLL_COMMAND" <<'EOF_POLL'
#!/bin/sh
exit 0
EOF_POLL
	chmod 755 "$SS_STATISTICS_POLL_COMMAND"
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics.sh"
	CALLS="$TMP/calls"
	record_call() { printf '%s\n' "$*" >>"$CALLS"; }
	log_error() { :; }
	log_warn() { :; }
	ss_status_set() { :; }
	ss_status_add_warning() { :; }
	DNSMASQ_PATCHED=1
	ss_dnsmasq_safeshield_block_supported() { [ "$DNSMASQ_PATCHED" = '1' ]; }
	uci() {
		record_call "uci $*"
		return 0
	}
	ss_require_supported_dnsmasq() {
		record_call require_supported_dnsmasq
		return 0
	}
	dnsmasq_restart() {
		record_call dnsmasq_restart
		return 0
	}
	procd_kill() {
		record_call "procd_kill $*"
		return 0
	}
	procd_open_service() { record_call "procd_open_service $*"; }
	procd_open_instance() { record_call "procd_open_instance $*"; }
	procd_set_param() { record_call "procd_set_param $*"; }
	procd_close_instance() { record_call procd_close_instance; }
	procd_close_service() { record_call "procd_close_service $*"; }
	mkdir -p "$SS_DNSMASQ_DIR"
	cat >"$SS_STATISTICS_DNSMASQ_CONF" <<'CONFIG'
# Legacy SafeShield statistics logging
log-queries=extra
log-async=25
CONFIG
	: >"$CALLS"
	ss_statistics_reconcile_runtime
	[ ! -e "$SS_STATISTICS_DNSMASQ_CONF" ]
	[ -f "$SS_STATISTICS_REBASELINE_FILE" ]
	ss_spec_assert_file_line "$CALLS" 'procd_kill safeshield statistics'
	ss_spec_assert_file_line "$CALLS" 'procd_kill safeshield statistics-upload'
	ss_spec_assert_file_line "$CALLS" 'dnsmasq_restart'
	! grep -Fx 'procd_kill safeshield' "$CALLS" >/dev/null

	ss_statistics_enabled=1
	: >"$CALLS"
	ss_statistics_reconcile_runtime
	[ ! -e "$SS_STATISTICS_DNSMASQ_CONF" ]
	ss_spec_assert_file_line "$CALLS" 'require_supported_dnsmasq'
	ss_spec_assert_file_line "$CALLS" 'procd_open_service safeshield'
	ss_spec_assert_file_line "$CALLS" 'procd_open_instance statistics'
	ss_spec_assert_file_line "$CALLS" 'procd_open_instance statistics-upload'
	ss_spec_assert_file_line "$CALLS" 'procd_set_param command /usr/libexec/safeshield-statistics-uploader'
	ss_spec_assert_file_line "$CALLS" 'procd_close_service add'
	! grep -Fx 'dnsmasq_restart' "$CALLS" >/dev/null
	! grep -F 'procd_kill safeshield' "$CALLS" >/dev/null

	: >"$CALLS"
	ss_statistics_reconcile_runtime
	! grep -Fx 'dnsmasq_restart' "$CALLS" >/dev/null
	ss_spec_assert_file_line "$CALLS" 'procd_open_instance statistics'
	ss_spec_assert_file_line "$CALLS" 'procd_open_instance statistics-upload'

	DNSMASQ_PATCHED=0
	ss_statistics_enabled=1
	: >"$CALLS"
	ss_statistics_reconcile_runtime
	ss_spec_assert_eq "$ss_statistics_enabled" '0'
	[ -f "$SS_STATISTICS_REBASELINE_FILE" ]
	! grep -F 'uci ' "$CALLS" >/dev/null
	ss_spec_assert_file_line "$CALLS" 'procd_kill safeshield statistics'
	ss_spec_assert_file_line "$CALLS" 'procd_kill safeshield statistics-upload'
	! grep -F 'procd_open_instance statistics' "$CALLS" >/dev/null

	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield/config.uc" "changed_names[0] == 'statistics_enabled'"
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield/config.uc" "run_service_action('reconcile_statistics', 60000)"
)

ss_case_statistics_uploader() (
	set -eu
	UPLOADER="$SS_SPEC_ROOT/files/usr/libexec/safeshield-statistics-uploader"
	ss_spec_assert_file_contains "$UPLOADER" 'SS_STATS_UPLOAD_INTERVAL_S="${SS_STATS_UPLOAD_INTERVAL_S:-1800}"'
	ss_spec_assert_file_contains "$UPLOADER" 'SS_STATS_UPLOAD_FULL_EVERY="${SS_STATS_UPLOAD_FULL_EVERY:-23}"'
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	mkdir -p "$TMP/statistics"
	cat >"$TMP/functions.sh" <<'EOF_FUNCTIONS'
# test stub
EOF_FUNCTIONS
	cat >"$TMP/core.sh" <<'EOF_CORE'
SS_STATISTICS_DIR="$TMP/statistics"
SS_STATISTICS_JSON_FILE="$SS_STATISTICS_DIR/statistics.json"
SS_STATISTICS_UPLOAD_JSON_FILE="$SS_STATISTICS_DIR/upload.json"
SS_STATISTICS_UPLOAD_CREDENTIALS_FILE="$SS_STATISTICS_DIR/upload.credentials"
SS_STATISTICS_UPLOAD_ENTITLEMENT_FILE="$SS_STATISTICS_DIR/upload.entitlement"
SS_STATISTICS_UPLOAD_PENDING_FILE="$SS_STATISTICS_DIR/upload.pending.json"
SS_STATISTICS_UPLOAD_PENDING_META_FILE="$SS_STATISTICS_DIR/upload.pending.meta"
SS_STATISTICS_UPLOAD_STATE_FILE="$SS_STATISTICS_DIR/upload.state"
ss_enabled=1
ss_statistics_enabled=1
ss_download_retry=3
ss_download_timeout=10
SS_HTTP_STATUS=''
SS_STATISTICS_UPLOAD_URL='https://www.smartsafehub.com/api/v1/statistics'
SS_STATISTICS_UPLOAD_TOKEN='token-old'
SS_STATISTICS_UPLOAD_TOKEN_EXPIRES_IN_S=172800
MOCK_UPLOAD_ENTITLEMENT='allowed'
MOCK_REFRESH_RESULT='allowed'
MOCK_DENIED_RECHECK_DUE='0'

is_valid_integer() {
	case "$1" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -ge 0 ] 2>/dev/null
}
ss_load_config() { return 0; }
ss_status_set() { :; }
ss_status_set_now() { :; }
log_info() { :; }
log_warn() { :; }
log_error() { :; }
ss_statistics_upload_denied() {
	[ "$MOCK_UPLOAD_ENTITLEMENT" = 'denied' ]
}
ss_statistics_upload_denied_recheck_due() {
	[ "$MOCK_DENIED_RECHECK_DUE" = '1' ]
}
ss_statistics_set_upload_entitlement() {
	MOCK_UPLOAD_ENTITLEMENT="$1"
}
ss_statistics_load_upload_credentials() {
	ss_statistics_upload_denied && return 1
	[ -n "$SS_STATISTICS_UPLOAD_TOKEN" ]
}
ss_statistics_clear_upload_credentials() {
	SS_STATISTICS_UPLOAD_TOKEN=''
}
ss_statistics_disable_cloud_upload() {
	MOCK_UPLOAD_ENTITLEMENT='denied'
	SS_STATISTICS_UPLOAD_TOKEN=''
	rm -f "$SS_STATISTICS_UPLOAD_PENDING_FILE" "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$SS_STATISTICS_UPLOAD_STATE_FILE"
}
ss_statistics_refresh_upload_credentials() {
	printf '%s\n' "$MOCK_REFRESH_RESULT" >>"$REFRESH_CALLS"
	if [ "$MOCK_REFRESH_RESULT" = 'denied' ]; then
		MOCK_UPLOAD_ENTITLEMENT='denied'
		SS_STATISTICS_UPLOAD_TOKEN=''
		rm -f "$SS_STATISTICS_UPLOAD_PENDING_FILE" "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$SS_STATISTICS_UPLOAD_STATE_FILE"
		return 2
	fi
	MOCK_UPLOAD_ENTITLEMENT='allowed'
	SS_STATISTICS_UPLOAD_URL='https://www.smartsafehub.com/api/v1/statistics'
	SS_STATISTICS_UPLOAD_TOKEN='token-new'
	return 0
}
ss_json_get_file() {
	local file="$1"
	local expr="$2"
	case "$expr" in
		'@.schema.name') sed -n 's/.*"schema":{"name":"\([^"]*\)".*/\1/p' "$file" ;;
		'@.schema.version') sed -n 's/.*"schema":{"name":"[^"]*","version":\([0-9][0-9]*\)}.*/\1/p' "$file" ;;
		'@.generation_id') sed -n 's/.*"generation_id":"\([^"]*\)".*/\1/p' "$file" ;;
		'@.snapshot_seq') sed -n 's/.*"snapshot_seq":\([0-9][0-9]*\).*/\1/p' "$file" ;;
		'@.status') sed -n 's/.*"status":"\([^"]*\)".*/\1/p' "$file" ;;
		'@.last_snapshot_seq') sed -n 's/.*"last_snapshot_seq":\([0-9][0-9]*\).*/\1/p' "$file" ;;
		*) return 1 ;;
	esac
}
ss_http_post_json() {
	local url="$1"
	local payload="$2"
	local out="$3"
	local authorization="${4:-}"
	local call generation seq response_status
	call=0
	[ -s "$HTTP_CALLS" ] && call="$(wc -l <"$HTTP_CALLS" | tr -d ' ')"
	call=$((call + 1))
	printf '%s\n' "$call" >>"$HTTP_CALLS"
	cksum "$payload" | awk '{print $1 ":" $2}' >>"$HTTP_CHECKSUMS"
	printf '%s\n' "$authorization" >>"$HTTP_AUTH"

	case "$MOCK_HTTP_MODE" in
		fail-once)
			if [ "$call" -eq 1 ]; then
				SS_HTTP_STATUS='503'
				return 1
			fi
			;;
		always-fail)
			SS_HTTP_STATUS='503'
			return 1
			;;
		unauthorized-once)
			if [ "$call" -eq 1 ]; then
				SS_HTTP_STATUS='401'
				return 1
			fi
			;;
		bad-request)
			SS_HTTP_STATUS='400'
			return 1
			;;
	esac

	generation="$(ss_json_get_file "$payload" '@.generation_id')"
	seq="$(ss_json_get_file "$payload" '@.snapshot_seq')"
	case "$MOCK_HTTP_MODE" in
		stale) response_status='stale' ;;
		duplicate) response_status='duplicate' ;;
		*) response_status='applied' ;;
	esac
	printf '{"status":"%s","generation_id":"%s","last_snapshot_seq":%s}\n' "$response_status" "$generation" "$seq" >"$out"
	SS_HTTP_STATUS='200'
	return 0
}
EOF_CORE

	# Expand only the test-root path while preserving shell variables for runtime.
	sed -i.bak "s|\$TMP|$TMP|g" "$TMP/core.sh" 2>/dev/null || {
		sed "s|\$TMP|$TMP|g" "$TMP/core.sh" >"$TMP/core.expanded"
		mv "$TMP/core.expanded" "$TMP/core.sh"
	}
	rm -f "$TMP/core.sh.bak"

	HTTP_CALLS="$TMP/http.calls"
	HTTP_CHECKSUMS="$TMP/http.checksums"
	HTTP_AUTH="$TMP/http.auth"
	REFRESH_CALLS="$TMP/refresh.calls"
	MOCK_HTTP_MODE='success'
	export HTTP_CALLS HTTP_CHECKSUMS HTTP_AUTH REFRESH_CALLS MOCK_HTTP_MODE MOCK_DENIED_RECHECK_DUE
	: >"$HTTP_CALLS"
	: >"$HTTP_CHECKSUMS"
	: >"$HTTP_AUTH"
	: >"$REFRESH_CALLS"

	SS_STATS_UPLOAD_FUNCTIONS_LIB="$TMP/functions.sh"
	SS_STATS_UPLOAD_CORE_LIB="$TMP/core.sh"
	SS_STATS_UPLOAD_LIBRARY_ONLY=1
	SS_STATS_UPLOAD_RETRY_DELAY_S=0
	SS_STATS_UPLOAD_FULL_EVERY=23
	SS_STATS_UPLOAD_RESPONSE_FILE="$TMP/statistics/upload.response.json"
	export SS_STATS_UPLOAD_FUNCTIONS_LIB SS_STATS_UPLOAD_CORE_LIB SS_STATS_UPLOAD_LIBRARY_ONLY
	export SS_STATS_UPLOAD_RETRY_DELAY_S SS_STATS_UPLOAD_FULL_EVERY SS_STATS_UPLOAD_RESPONSE_FILE
	# shellcheck disable=SC1090
	. "$SS_SPEC_ROOT/files/usr/libexec/safeshield-statistics-uploader"

	write_payload() {
		path="$1"
		seq="$2"
		printf '{"schema":{"name":"safeshield.statistics","version":3},"generation_id":"generation-upload","snapshot_seq":%s}\n' "$seq" >"$path"
	}

	write_payload "$SS_STATISTICS_JSON_FILE" 1
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 1
	upload_pending_create
	ss_spec_assert_file_contains "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$(printf 'full\tgeneration-upload\t1')"

	MOCK_HTTP_MODE='fail-once'
	export MOCK_HTTP_MODE
	: >"$HTTP_CALLS"
	: >"$HTTP_CHECKSUMS"
	upload_send_pending
	ss_spec_assert_eq "$(wc -l <"$HTTP_CALLS" | tr -d ' ')" '2'
	ss_spec_assert_eq "$(sort -u "$HTTP_CHECKSUMS" | wc -l | tr -d ' ')" '1'
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]
	upload_state_load
	ss_spec_assert_eq "$upload_state_last_full_seq" '1'
	ss_spec_assert_eq "$upload_state_needs_full" '0'

	write_payload "$SS_STATISTICS_JSON_FILE" 2
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 1
	if upload_pending_create; then
		return 1
	fi
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 2
	upload_pending_create
	ss_spec_assert_file_contains "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$(printf 'recent\tgeneration-upload\t2')"
	MOCK_HTTP_MODE='always-fail'
	export MOCK_HTTP_MODE
	ss_download_retry=2
	: >"$HTTP_CALLS"
	if upload_send_pending; then
		return 1
	fi
	[ -s "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]
	upload_state_load
	ss_spec_assert_eq "$upload_state_needs_full" '1'

	MOCK_HTTP_MODE='success'
	export MOCK_HTTP_MODE
	: >"$HTTP_CALLS"
	upload_send_pending
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]
	upload_state_load
	ss_spec_assert_eq "$upload_state_needs_full" '1'

	write_payload "$SS_STATISTICS_JSON_FILE" 3
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 3
	upload_pending_create
	ss_spec_assert_file_contains "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$(printf 'full\tgeneration-upload\t3')"
	upload_pending_clear

	# A 401 refreshes credentials once and retries the exact pending snapshot.
	upload_state_needs_full=0
	upload_state_last_full_seq=1
	upload_state_last_success_seq=2
	upload_state_save
	write_payload "$SS_STATISTICS_JSON_FILE" 4
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 4
	upload_pending_create
	MOCK_HTTP_MODE='unauthorized-once'
	export MOCK_HTTP_MODE
	SS_STATISTICS_UPLOAD_TOKEN='token-old'
	ss_download_retry=3
	: >"$HTTP_CALLS"
	: >"$HTTP_AUTH"
	upload_send_pending
	ss_spec_assert_eq "$(sed -n '1p' "$HTTP_AUTH")" 'Bearer token-old'
	ss_spec_assert_eq "$(sed -n '2p' "$HTTP_AUTH")" 'Bearer token-new'
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]

	# A revoked/expired entitlement stops the 401 re-authentication loop and
	# discards only the pending cloud payload; local statistics remain untouched.
	write_payload "$SS_STATISTICS_JSON_FILE" 5
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 5
	upload_pending_create
	MOCK_HTTP_MODE='unauthorized-once'
	MOCK_REFRESH_RESULT='denied'
	MOCK_UPLOAD_ENTITLEMENT='allowed'
	SS_STATISTICS_UPLOAD_TOKEN='token-old'
	export MOCK_HTTP_MODE MOCK_REFRESH_RESULT MOCK_UPLOAD_ENTITLEMENT
	: >"$HTTP_CALLS"
	: >"$REFRESH_CALLS"
	DENIED_RC=0
	upload_send_pending || DENIED_RC=$?
	ss_spec_assert_eq "$DENIED_RC" '2'
	ss_spec_assert_eq "$(wc -l <"$HTTP_CALLS" | tr -d ' ')" '1'
	ss_spec_assert_eq "$(wc -l <"$REFRESH_CALLS" | tr -d ' ')" '1'
	ss_spec_assert_eq "$MOCK_UPLOAD_ENTITLEMENT" 'denied'
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]

	# Explicit denial prevents repeated credential resolves from the uploader.
	ENSURE_RC=0
	upload_ensure_credentials || ENSURE_RC=$?
	ss_spec_assert_eq "$ENSURE_RC" '2'
	ss_spec_assert_eq "$(wc -l <"$REFRESH_CALLS" | tr -d ' ')" '1'

	# Denied entitlement stays quiet until the 12-hour recheck becomes due.
	MOCK_UPLOAD_ENTITLEMENT='denied'
	MOCK_REFRESH_RESULT='allowed'
	MOCK_DENIED_RECHECK_DUE='0'
	SS_STATISTICS_UPLOAD_TOKEN=''
	ss_license_key='paid-license-key'
	ss_should_terminate=0
	: >"$REFRESH_CALLS"
	upload_sleep() {
		ss_should_terminate=1
		return 1
	}
	main
	ss_spec_assert_eq "$(wc -l <"$REFRESH_CALLS" | tr -d ' ')" '0'

	# Once the 12-hour check is due, re-resolve entitlement immediately. A newly
	# entitled device resumes with a full reconciliation because denial cleared
	# the previous upload state.
	MOCK_UPLOAD_ENTITLEMENT='denied'
	MOCK_DENIED_RECHECK_DUE='1'
	MOCK_HTTP_MODE='success'
	SS_STATISTICS_UPLOAD_TOKEN=''
	ss_should_terminate=0
	write_payload "$SS_STATISTICS_JSON_FILE" 6
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 6
	: >"$REFRESH_CALLS"
	: >"$HTTP_CALLS"
	main
	ss_spec_assert_eq "$(wc -l <"$REFRESH_CALLS" | tr -d ' ')" '1'
	ss_spec_assert_eq "$(wc -l <"$HTTP_CALLS" | tr -d ' ')" '1'
	ss_spec_assert_eq "$MOCK_UPLOAD_ENTITLEMENT" 'allowed'

	# Corrupted pending metadata must never be uploaded. It is discarded so the
	# next loop can rebuild a payload from an atomic collector snapshot.
	printf '%s\n' '{"schema":{"name":"safeshield.statistics","version":3},"generation_id":"generation-upload","snapshot_seq":7}' >"$SS_STATISTICS_UPLOAD_PENDING_FILE"
	printf '%s\n' 'invalid-mode\tgeneration-upload\t7' >"$SS_STATISTICS_UPLOAD_PENDING_META_FILE"
	if upload_pending_load; then
		return 1
	fi
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" ]

	# A stale ACK is successful transport-wise but forces the next upload to be a
	# full reconciliation. A duplicate full ACK can then clear that requirement.
	MOCK_UPLOAD_ENTITLEMENT='allowed'
	MOCK_REFRESH_RESULT='allowed'
	SS_STATISTICS_UPLOAD_TOKEN='token-current'
	upload_state_generation='generation-upload'
	upload_state_last_success_seq=6
	upload_state_last_full_seq=6
	upload_state_recent_successes=0
	upload_state_needs_full=0
	upload_state_save
	write_payload "$SS_STATISTICS_JSON_FILE" 7
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 7
	upload_pending_create
	ss_spec_assert_file_contains "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$(printf 'recent\tgeneration-upload\t7')"
	MOCK_HTTP_MODE='stale'
	export MOCK_HTTP_MODE
	upload_send_pending
	upload_state_load
	ss_spec_assert_eq "$upload_state_needs_full" '1'
	ss_spec_assert_eq "$upload_state_last_success_seq" '7'

	write_payload "$SS_STATISTICS_JSON_FILE" 8
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 8
	upload_pending_create
	ss_spec_assert_file_contains "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$(printf 'full\tgeneration-upload\t8')"
	MOCK_HTTP_MODE='duplicate'
	export MOCK_HTTP_MODE
	upload_send_pending
	upload_state_load
	ss_spec_assert_eq "$upload_state_needs_full" '0'
	ss_spec_assert_eq "$upload_state_last_full_seq" '8'

	# The 12-hour cadence threshold selects a full snapshot even when no failure
	# occurred, and a permanent 400 rejects/discards the payload while requiring
	# a later full reconciliation.
	upload_state_recent_successes="$SS_STATS_UPLOAD_FULL_EVERY"
	upload_state_save
	write_payload "$SS_STATISTICS_JSON_FILE" 9
	write_payload "$SS_STATISTICS_UPLOAD_JSON_FILE" 9
	upload_pending_create
	ss_spec_assert_file_contains "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$(printf 'full\tgeneration-upload\t9')"
	upload_pending_clear

	upload_state_recent_successes=0
	upload_state_needs_full=0
	upload_state_last_success_seq=8
	upload_state_save
	upload_pending_create
	ss_spec_assert_file_contains "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" "$(printf 'recent\tgeneration-upload\t9')"
	MOCK_HTTP_MODE='bad-request'
	export MOCK_HTTP_MODE
	BAD_REQUEST_RC=0
	upload_send_pending || BAD_REQUEST_RC=$?
	ss_spec_assert_eq "$BAD_REQUEST_RC" '2'
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]
	upload_state_load
	ss_spec_assert_eq "$upload_state_needs_full" '1'

	# An unlicensed device is blocked locally without asking the Hub for a
	# statistics credential. The long-lived uploader can remain idle so a later
	# license update can re-enable it without restarting the collector.
	MOCK_UPLOAD_ENTITLEMENT='allowed'
	MOCK_REFRESH_RESULT='allowed'
	MOCK_DENIED_RECHECK_DUE='1'
	SS_STATISTICS_UPLOAD_TOKEN='token-old'
	ss_license_key=''
	ss_should_terminate=0
	: >"$REFRESH_CALLS"
	upload_sleep() {
		ss_should_terminate=1
		return 1
	}
	main
	ss_spec_assert_eq "$MOCK_UPLOAD_ENTITLEMENT" 'denied'
	ss_spec_assert_eq "$(wc -l <"$REFRESH_CALLS" | tr -d ' ')" '0'
	ss_spec_assert_eq "$SS_STATISTICS_UPLOAD_TOKEN" ''
)

ss_case_statistics_upload_credentials() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	mkdir -p "$TMP/statistics"
	SS_STATISTICS_DIR="$TMP/statistics"
	SS_STATISTICS_UPLOAD_CREDENTIALS_FILE="$SS_STATISTICS_DIR/upload.credentials"
	SS_STATISTICS_UPLOAD_ENTITLEMENT_FILE="$SS_STATISTICS_DIR/upload.entitlement"
	SS_STATISTICS_UPLOAD_PENDING_FILE="$SS_STATISTICS_DIR/upload.pending.json"
	SS_STATISTICS_UPLOAD_PENDING_META_FILE="$SS_STATISTICS_DIR/upload.pending.meta"
	SS_STATISTICS_UPLOAD_STATE_FILE="$SS_STATISTICS_DIR/upload.state"
	SS_STATISTICS_POLL_COMMAND="$TMP/stats-poll"
	SS_STATISTICS_REBASELINE_FILE="$SS_STATISTICS_DIR/rebaseline"
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics.sh"

	is_valid_integer() {
		case "$1" in
			'' | *[!0-9]*) return 1 ;;
		esac
		[ "$1" -ge 0 ] 2>/dev/null
	}

	MOCK_NOW=1000
	date() {
		[ "${1:-}" = '+%s' ] || return 1
		printf '%s\n' "$MOCK_NOW"
	}

	RESPONSE="$TMP/resolve.json"
	printf '%s\n' '{}' >"$RESPONSE"
	MOCK_URL='https://www.smartsafehub.com/api/v1/statistics'
	MOCK_TOKEN='statistics-token'
	MOCK_TTL='172800'
	ss_json_get_file() {
		case "$2" in
			'@.statistics.upload_url') printf '%s\n' "$MOCK_URL" ;;
			'@.statistics.token') printf '%s\n' "$MOCK_TOKEN" ;;
			'@.statistics.token_expires_in_s') printf '%s\n' "$MOCK_TTL" ;;
			*) return 1 ;;
		esac
	}

	BEFORE_UMASK="$(umask)"
	ss_statistics_store_upload_credentials "$RESPONSE"
	ss_spec_assert_eq "$(umask)" "$BEFORE_UMASK"
	[ -s "$SS_STATISTICS_UPLOAD_CREDENTIALS_FILE" ]
	ss_spec_assert_eq "$(sed -n '1p' "$SS_STATISTICS_UPLOAD_CREDENTIALS_FILE")" "$MOCK_URL"
	ss_spec_assert_eq "$(sed -n '2p' "$SS_STATISTICS_UPLOAD_CREDENTIALS_FILE")" "$MOCK_TOKEN"
	ss_spec_assert_eq "$(sed -n '3p' "$SS_STATISTICS_UPLOAD_CREDENTIALS_FILE")" "$MOCK_TTL"
	MODE="$(stat -c '%a' "$SS_STATISTICS_UPLOAD_CREDENTIALS_FILE" 2>/dev/null || stat -f '%Lp' "$SS_STATISTICS_UPLOAD_CREDENTIALS_FILE")"
	ss_spec_assert_eq "$MODE" '600'

	SS_STATISTICS_UPLOAD_URL=''
	SS_STATISTICS_UPLOAD_TOKEN=''
	SS_STATISTICS_UPLOAD_TOKEN_EXPIRES_IN_S='0'
	ss_statistics_load_upload_credentials
	ss_spec_assert_eq "$SS_STATISTICS_UPLOAD_URL" "$MOCK_URL"
	ss_spec_assert_eq "$SS_STATISTICS_UPLOAD_TOKEN" "$MOCK_TOKEN"
	ss_spec_assert_eq "$SS_STATISTICS_UPLOAD_TOKEN_EXPIRES_IN_S" "$MOCK_TTL"
	ss_spec_assert_eq "$(ss_statistics_upload_entitlement)" 'allowed'

	# `statistics: null` is authoritative: clear secrets/pending cloud state and
	# remember the denial in tmpfs so the uploader does not re-resolve in a loop.
	printf '%s\n' pending >"$SS_STATISTICS_UPLOAD_PENDING_FILE"
	printf '%s\n' meta >"$SS_STATISTICS_UPLOAD_PENDING_META_FILE"
	printf '%s\n' state >"$SS_STATISTICS_UPLOAD_STATE_FILE"
	MOCK_URL=''
	MOCK_TOKEN=''
	DENIED_RC=0
	ss_statistics_sync_upload_entitlement "$RESPONSE" || DENIED_RC=$?
	ss_spec_assert_eq "$DENIED_RC" '2'
	ss_spec_assert_eq "$(ss_statistics_upload_entitlement)" 'denied'
	[ ! -e "$SS_STATISTICS_UPLOAD_CREDENTIALS_FILE" ]
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_FILE" ]
	[ ! -e "$SS_STATISTICS_UPLOAD_PENDING_META_FILE" ]
	[ ! -e "$SS_STATISTICS_UPLOAD_STATE_FILE" ]
	ss_spec_assert_eq "$(sed -n '2p' "$SS_STATISTICS_UPLOAD_ENTITLEMENT_FILE")" '1000'
	if ss_statistics_upload_denied_recheck_due 43200; then
		return 1
	fi
	MOCK_NOW=44199
	if ss_statistics_upload_denied_recheck_due 43200; then
		return 1
	fi
	MOCK_NOW=44200
	ss_statistics_upload_denied_recheck_due 43200
	MOCK_NOW=999
	ss_statistics_upload_denied_recheck_due 43200
	MOCK_NOW=44200
	if ss_statistics_load_upload_credentials; then
		return 1
	fi

	# A later entitled resolve restores upload without changing local collection.
	MOCK_URL='https://www.smartsafehub.com/api/v1/statistics'
	MOCK_TOKEN='statistics-token-renewed'
	ss_statistics_sync_upload_entitlement "$RESPONSE"
	ss_spec_assert_eq "$(ss_statistics_upload_entitlement)" 'allowed'
	ss_statistics_load_upload_credentials
	ss_spec_assert_eq "$SS_STATISTICS_UPLOAD_TOKEN" 'statistics-token-renewed'

	MOCK_URL='https://example.invalid/api/v1/statistics'
	if ss_statistics_store_upload_credentials "$RESPONSE"; then
		return 1
	fi
	MOCK_URL='https://www.smartsafehub.com/api/v1/statistics'
	MOCK_TOKEN='token with whitespace'
	if ss_statistics_store_upload_credentials "$RESPONSE"; then
		return 1
	fi
)

ss_case_statistics_http_auth() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	mkdir -p "$TMP/bin"
	PAYLOAD="$TMP/payload.json"
	OUTPUT="$TMP/response.json"
	CURL_ARGS="$TMP/curl.args"
	printf '%s\n' '{}' >"$PAYLOAD"

	cat >"$TMP/bin/curl" <<'EOF_CURL'
#!/bin/sh
out=''
prev=''
for arg in "$@"; do
	printf '%s\n' "$arg" >>"$CURL_ARGS"
	if [ "$prev" = '-o' ]; then
		out="$arg"
	fi
	prev="$arg"
done
[ -n "$out" ] && printf '%s\n' '{}' >"$out"
printf '%s' '200'
EOF_CURL
	chmod 755 "$TMP/bin/curl"
	export CURL_ARGS

	ss_download_timeout=10
	command_exists() { command -v "$1" >/dev/null 2>&1; }
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"

	PATH="$TMP/bin:$PATH"
	export PATH
	ss_http_post_json 'https://www.smartsafehub.com/api/v1/statistics' "$PAYLOAD" "$OUTPUT" 'Bearer statistics-token'
	ss_spec_assert_file_line "$CURL_ARGS" 'Authorization: Bearer statistics-token'
	ss_spec_assert_file_line "$CURL_ARGS" "@${PAYLOAD}"
	ss_spec_assert_eq "$SS_HTTP_STATUS" '200'
	[ -s "$OUTPUT" ]
)

ss_case_http_uclient_transport() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	mkdir -p "$TMP/bin"
	PAYLOAD="$TMP/payload.json"
	OUTPUT="$TMP/response.json"
	UCLIENT_ARGS="$TMP/uclient.args"
	UCLIENT_CALLS="$TMP/uclient.calls"
	printf '%s\n' '{"hello":"world"}' >"$PAYLOAD"
	: >"$UCLIENT_ARGS"
	: >"$UCLIENT_CALLS"

	cat >"$TMP/bin/uclient-fetch" <<'EOF_UCLIENT'
#!/bin/sh
if [ "${1:-}" = '--help' ]; then
	printf '%s\n' 'Usage: uclient-fetch [--post-file=FILE] [--header=HEADER]'
	exit 0
fi
printf '%s\n' 'call' >>"$UCLIENT_CALLS"
printf '%s\n' "$@" >>"$UCLIENT_ARGS"
out=''
prev=''
for arg in "$@"; do
	if [ "$prev" = '-O' ]; then
		out="$arg"
	fi
	prev="$arg"
done
case "${UCLIENT_MODE:-success}" in
	success)
		[ -n "$out" ] && printf '%s\n' '{}' >"$out"
		exit 0
		;;
	unauthorized)
		printf '%s\n' 'HTTP error 401' >&2
		exit 8
		;;
esac
exit 1
EOF_UCLIENT
	chmod 755 "$TMP/bin/uclient-fetch"
	export UCLIENT_ARGS UCLIENT_CALLS

	ss_download_timeout=10
	command_exists() {
		[ "$1" = 'uclient-fetch' ]
	}
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"

	PATH="$TMP/bin:$PATH"
	export PATH
	UCLIENT_MODE='success'
	export UCLIENT_MODE
	ss_http_post_json 'https://www.smartsafehub.com/api/v1/statistics' "$PAYLOAD" "$OUTPUT" 'Bearer statistics-token'
	ss_spec_assert_file_line "$UCLIENT_ARGS" '--header=Content-Type: application/json'
	ss_spec_assert_file_line "$UCLIENT_ARGS" '--header=Accept: application/json'
	ss_spec_assert_file_line "$UCLIENT_ARGS" '--header=Authorization: Bearer statistics-token'
	ss_spec_assert_file_line "$UCLIENT_ARGS" "--post-file=$PAYLOAD"
	ss_spec_assert_eq "$SS_HTTP_STATUS" ''
	[ -s "$OUTPUT" ]

	: >"$UCLIENT_ARGS"
	UCLIENT_MODE='unauthorized'
	export UCLIENT_MODE
	if ss_http_post_json 'https://www.smartsafehub.com/api/v1/statistics' "$PAYLOAD" "$OUTPUT" 'Bearer statistics-token' 2>/dev/null; then
		return 1
	fi
	ss_spec_assert_eq "$SS_HTTP_STATUS" '401'
	[ ! -e "${OUTPUT}.uclient.txt" ]

	cat >"$TMP/bin/uclient-fetch" <<'EOF_NO_HEADER'
#!/bin/sh
if [ "${1:-}" = '--help' ]; then
	printf '%s\n' 'Usage: uclient-fetch [--post-file=FILE]'
	exit 0
fi
printf '%s\n' 'network-call' >>"$UCLIENT_CALLS"
exit 0
EOF_NO_HEADER
	chmod 755 "$TMP/bin/uclient-fetch"
	: >"$UCLIENT_CALLS"
	if ss_http_post_json 'https://www.smartsafehub.com/api/v1/statistics' "$PAYLOAD" "$OUTPUT" 'Bearer statistics-token'; then
		return 1
	fi
	[ ! -s "$UCLIENT_CALLS" ]
)

ss_case_refreshd_scheduler() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	REFRESHD="$SS_SPEC_ROOT/files/usr/libexec/safeshield-refreshd"
	HARNESS="$TMP/refreshd-scheduler.sh"
	awk '
		/^ss_should_terminate=0$/ { capture=1 }
		capture && /^trap "handle_term"/ { exit }
		capture { print }
	' "$REFRESHD" >"$HARNESS"
	# shellcheck disable=SC1090
	. "$HARNESS"

	CALLS="$TMP/calls"
	: >"$CALLS"
	MOCK_LAST_SUCCESS=0
	MOCK_LAST_ATTEMPT=0
	NOW=1000
	json() {
		[ "${1:-}" = 'get' ] || return 1
		case "${2:-}" in
			last_success) printf '%s\n' "$MOCK_LAST_SUCCESS" ;;
			last_attempt) printf '%s\n' "$MOCK_LAST_ATTEMPT" ;;
			*) return 1 ;;
		esac
	}
	is_valid_integer() { case "$1" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }
	date() { [ "${1:-}" = '+%s' ] && printf '%s\n' "$NOW"; }
	ss_status_set() { printf '%s=%s\n' "$1" "${2:-}" >>"$CALLS"; }
	log_info() { :; }

	MOCK_LAST_SUCCESS=900
	MOCK_LAST_ATTEMPT=950
	ss_spec_assert_eq "$(schedule_base_epoch 1000)" '950'
	MOCK_LAST_ATTEMPT=1100
	ss_spec_assert_eq "$(schedule_base_epoch 1000)" '900'
	MOCK_LAST_SUCCESS='invalid'
	MOCK_LAST_ATTEMPT='invalid'
	ss_spec_assert_eq "$(schedule_base_epoch 1000)" '0'

	MOCK_LAST_SUCCESS=950
	NOW=1000
	has_recent_success 100
	MOCK_LAST_SUCCESS=900
	! has_recent_success 100
	MOCK_LAST_SUCCESS=1100
	! has_recent_success 100

	MOCK_LAST_SUCCESS=900
	MOCK_LAST_ATTEMPT=0
	NOW=950
	SLEEPS="$TMP/sleeps"
	: >"$SLEEPS"
	SLEEP_CALL=0
	sleep_seconds() {
		SLEEP_CALL=$((SLEEP_CALL + 1))
		printf '%s\n' "$1" >>"$SLEEPS"
		if [ "$SLEEP_CALL" -eq 1 ]; then
			MOCK_LAST_SUCCESS=970
			NOW=1000
			return 0
		fi
		return 1
	}
	: >"$CALLS"
	# Defined by the dynamically sourced refreshd harness above.
	# shellcheck disable=SC2218
	! wait_until_refresh_due 100 900
	ss_spec_assert_eq "$(cat "$SLEEPS")" '50
70'
	ss_spec_assert_file_line "$CALLS" 'next_refresh_at=1000'
	ss_spec_assert_file_line "$CALLS" 'next_refresh_at=1070'

	MOCK_LAST_SUCCESS=900
	MOCK_LAST_ATTEMPT=0
	NOW=1100
	: >"$CALLS"
	# Defined by the dynamically sourced refreshd harness above.
	# shellcheck disable=SC2218
	wait_until_refresh_due 100 900
	ss_spec_assert_file_line "$CALLS" 'next_refresh_at=0'

	REQUIRE_WAN=1
	ss_config_get() {
		case "$2" in
			require_wan) printf '%s\n' "$REQUIRE_WAN" ;;
			*) printf '%s\n' "${3:-}" ;;
		esac
	}
	ubus() {
		printf 'ubus %s\n' "$*" >>"$CALLS"
		return 0
	}
	: >"$CALLS"
	# Defined by the dynamically sourced refreshd harness above.
	# shellcheck disable=SC2218
	wait_for_wan_if_needed
	ss_spec_assert_file_line "$CALLS" 'ubus -t 30 wait_for network.interface.wan'
	REQUIRE_WAN=0
	: >"$CALLS"
	# Defined by the dynamically sourced refreshd harness above.
	# shellcheck disable=SC2218
	wait_for_wan_if_needed
	[ ! -s "$CALLS" ]

	refreshd_lock() { return 0; }
	refreshd_unlock() { :; }
	RUNNING_STATUS_FILE="$TMP/status.json"
	printf '%s\n' '{}' >"$RUNNING_STATUS_FILE"
	ss_status_reset() { printf '%s\n' status_reset >>"$CALLS"; }
	ss_sync_blocklist_status() { printf '%s\n' sync_blocklist >>"$CALLS"; }
	wait_for_wan_if_needed() { :; }
	wait_until_refresh_due() { return 1; }
	safeshield_force_download() { printf '%s\n' refresh >>"$CALLS"; }
	ss_load_config() {
		case "${MODE:-}" in
			disabled) ss_enabled=0 ;;
			*) ss_enabled=1 ;;
		esac
		return 0
	}
	ss_config_get() {
		case "$2" in
			refresh_interval_s) printf '%s\n' '100' ;;
			boot_start_delay_s) printf '%s\n' '0' ;;
			refresh_on_boot) printf '%s\n' '1' ;;
			require_wan) printf '%s\n' '0' ;;
			*) printf '%s\n' "${3:-}" ;;
		esac
	}
	has_recent_success() { return 0; }
	sleep_seconds() { return 0; }
	MODE='boot-skip'
	NOW=1000
	: >"$CALLS"
	main
	ss_spec_assert_file_line "$CALLS" 'stage=boot_refresh_skipped'
	ss_spec_assert_file_line "$CALLS" 'stage=scheduled_wait'
	! grep -Fx 'refresh' "$CALLS" >/dev/null

	MODE='disabled'
	SLEEP_CALL=0
	sleep_seconds() {
		SLEEP_CALL=$((SLEEP_CALL + 1))
		[ "$SLEEP_CALL" -eq 1 ]
	}
	: >"$CALLS"
	main
	ss_spec_assert_file_line "$CALLS" 'status=disabled'
	ss_spec_assert_file_line "$CALLS" 'stage=disabled'
	ss_spec_assert_file_line "$CALLS" 'next_refresh_at=0'
	! grep -Fx 'refresh' "$CALLS" >/dev/null
)
