#!/bin/sh
# shellcheck shell=sh

ss_case_refresh_state_machine() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	CORE="$SS_SPEC_ROOT/files/usr/lib/safeshield/core.sh"
	HARNESS="$TMP/core-state-machine.sh"
	sed -n '/^safeshield_apply_local_rules() {/,${p;}' "$CORE" >"$HARNESS"
	# shellcheck disable=SC1090
	. "$HARNESS"

	SS_TMP_DIR="$TMP/runtime"
	SS_DNSMASQ_DIR="$TMP/dnsmasq.d"
	SS_BLOCKLIST_FILE="$SS_DNSMASQ_DIR/safeshield.blocklist"
	SS_INACTIVE_BLOCKLIST_FILE="$SS_TMP_DIR/inactive.blocklist"
	SS_PREV_BLOCKLIST_GZ="$TMP/previous.gz"
	mkdir -p "$SS_TMP_DIR" "$SS_DNSMASQ_DIR"
	CALLS="$TMP/calls"
	: >"$CALLS"

	record() { printf '%s\n' "$*" >>"$CALLS"; }
	log_info() { :; }
	log_warn() { :; }
	log_error() { :; }
	log_ok() { :; }
	ss_status_prepare_refresh() { record status_prepare_refresh; }
	ss_status_set() { record "status_set $1 ${2:-}"; }
	ss_status_set_now() { record "status_set_now $1"; }
	ss_status_add_error() { record "status_error $1"; }
	ss_status_mark_failure() { record "failure $1"; }
	ss_status_mark_success() { record "success $1"; }
	ss_load_config() {
		ss_enabled=1
		export ss_initial_dnsmasq_restart=0
		ss_apply_local_overrides=1
		return 0
	}
	ss_config_get() {
		case "$2" in
			refresh_interval_s) printf '%s\n' '300' ;;
			*) printf '%s\n' "${3:-}" ;;
		esac
	}
	is_valid_integer() { case "$1" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }
	ss_sync_detected_device_config() { record sync_device_config; }
	ss_identity_ensure() {
		record identity_ensure
		[ "${FAIL_STAGE:-}" != 'identity' ]
	}
	ss_detect_device_model() { printf '%s\n' 'Test Router'; }
	ss_detect_device_arch() { printf '%s\n' 'test-arch'; }
	ss_should_stop() { return 1; }
	ss_mkdirs() {
		record mkdirs
		[ "${FAIL_STAGE:-}" != 'mkdir' ]
	}
	ss_clean_tmp() { record clean_tmp; }
	ss_require_supported_dnsmasq() {
		record require_dnsmasq
		[ "${FAIL_STAGE:-}" != 'dnsmasq_version' ]
	}
	ss_dnsmasq_check_error() { printf '%s\n' 'dnsmasq_version_unsupported'; }
	ss_ensure_dnsmasq_confdir() {
		record ensure_confdir
		[ "${FAIL_STAGE:-}" != 'confdir' ]
	}
	ss_export_existing_blocklist() {
		record export_blocklist
		printf '%s\n' 'backup' >"$SS_PREV_BLOCKLIST_GZ"
		return 0
	}
	DNSMASQ_CALL=0
	dnsmasq_restart() {
		DNSMASQ_CALL=$((DNSMASQ_CALL + 1))
		record "dnsmasq_restart $DNSMASQ_CALL"
		[ "${FAIL_STAGE:-}" != 'restart' ]
	}
	ss_resolve_artifact() {
		record resolve_artifact
		[ "${FAIL_STAGE:-}" != 'resolve' ]
	}
	ss_resolve_error_code() { printf '%s\n' "${RESOLVE_ERROR_CODE:-artifact_resolve_failed}"; }
	ss_download_api_artifacts() {
		record download_artifacts
		[ "${FAIL_STAGE:-}" != 'download' ]
	}
	ss_artifact_download_error_code() { printf '%s\n' "${DOWNLOAD_ERROR_CODE:-artifact_download_failed}"; }
	ss_prepare_local_rule_files() {
		record prepare_local_rules
		[ "${FAIL_STAGE:-}" != 'local_rules' ]
	}
	ss_merge_lists() {
		record merge_lists
		[ "${FAIL_STAGE:-}" != 'merge' ]
	}
	ss_install_blocklist() {
		record install_blocklist
		[ "${FAIL_STAGE:-}" != 'install' ]
	}
	check_dns_runtime() {
		record check_dns_runtime
		[ "${FAIL_STAGE:-}" != 'runtime' ]
	}
	check_blocklist_applied_multi_with_stats() {
		record "verify_blocklist $*"
		[ "${FAIL_STAGE:-}" != 'verify' ]
	}
	ss_restore_and_restart() { record restore_and_restart; }
	ss_refresh_lock_open() {
		record lock_open
		[ "${LOCK_AVAILABLE:-1}" = '1' ]
	}
	ss_refresh_lock_close() { record lock_close; }
	ss_local_rules_fingerprint_from_tmp() { printf '%s\n' 'fingerprint-new'; }
	ss_local_rules_state_write() { record "local_state_write $1"; }
	ss_abort_refresh() {
		record abort_refresh
		return 130
	}

	assert_refresh_failure() {
		stage="$1"
		code="$2"
		expect_restore="$3"
		FAIL_STAGE="$stage"
		RESOLVE_ERROR_CODE='artifact_resolve_failed'
		DOWNLOAD_ERROR_CODE='artifact_download_failed'
		DNSMASQ_CALL=0
		: >"$CALLS"
		if safeshield_force_download; then
			return 1
		fi
		ss_spec_assert_file_line "$CALLS" "failure $code"
		ss_spec_assert_file_line "$CALLS" 'lock_close'
		if [ "$expect_restore" = '1' ]; then
			ss_spec_assert_file_line "$CALLS" 'restore_and_restart'
		else
			! grep -Fx 'restore_and_restart' "$CALLS" >/dev/null
		fi
	}

	FAIL_STAGE=''
	LOCK_AVAILABLE=1
	: >"$CALLS"
	safeshield_force_download
	ss_spec_assert_file_line "$CALLS" 'status_set stage resolve_api'
	ss_spec_assert_file_line "$CALLS" 'status_set stage download_artifact'
	ss_spec_assert_file_line "$CALLS" 'status_set stage merge'
	ss_spec_assert_file_line "$CALLS" 'status_set stage install'
	ss_spec_assert_file_line "$CALLS" 'status_set stage restart_dnsmasq'
	ss_spec_assert_file_line "$CALLS" 'status_set stage runtime_check'
	ss_spec_assert_file_line "$CALLS" 'status_set stage blocklist_verify'
	ss_spec_assert_file_line "$CALLS" 'success 300'
	ss_spec_assert_file_line "$CALLS" 'local_state_write fingerprint-new'
	ss_spec_assert_file_line "$CALLS" 'lock_close'
	! grep -Fx 'restore_and_restart' "$CALLS" >/dev/null

	assert_refresh_failure merge merge_failed 1
	assert_refresh_failure install install_failed 1
	assert_refresh_failure restart dnsmasq_restart_failed 1
	assert_refresh_failure runtime dns_runtime_check_failed 1
	assert_refresh_failure verify blocklist_verification_failed 1

	FAIL_STAGE='resolve'
	RESOLVE_ERROR_CODE='safeshield_upgrade_required'
	: >"$CALLS"
	! safeshield_force_download
	ss_spec_assert_file_line "$CALLS" 'failure safeshield_upgrade_required'
	! grep -Fx 'restore_and_restart' "$CALLS" >/dev/null

	FAIL_STAGE='download'
	DOWNLOAD_ERROR_CODE='safeshield_upgrade_required'
	: >"$CALLS"
	! safeshield_force_download
	ss_spec_assert_file_line "$CALLS" 'failure safeshield_upgrade_required'
	! grep -Fx 'restore_and_restart' "$CALLS" >/dev/null

	FAIL_STAGE=''
	LOCK_AVAILABLE=0
	: >"$CALLS"
	safeshield_force_download
	ss_spec_assert_file_line "$CALLS" 'lock_open'
	! grep -F 'status_prepare_refresh' "$CALLS" >/dev/null
)

ss_case_local_apply_state_machine() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	CORE="$SS_SPEC_ROOT/files/usr/lib/safeshield/core.sh"
	HARNESS="$TMP/local-apply.sh"
	sed -n '/^safeshield_apply_local_rules() {/,/^safeshield_force_download() {/p' "$CORE" | sed '$d' >"$HARNESS"
	# shellcheck disable=SC1090
	. "$HARNESS"

	SS_TMP_DIR="$TMP/runtime"
	SS_DNSMASQ_DIR="$TMP/dnsmasq.d"
	SS_BLOCKLIST_FILE="$SS_DNSMASQ_DIR/safeshield.blocklist"
	SS_PREV_BLOCKLIST_GZ="$TMP/previous.gz"
	SS_INACTIVE_BLOCKLIST_FILE="$SS_TMP_DIR/inactive.blocklist"
	mkdir -p "$SS_TMP_DIR" "$SS_DNSMASQ_DIR"
	CALLS="$TMP/calls"
	: >"$CALLS"

	record() { printf '%s\n' "$*" >>"$CALLS"; }
	log_info() { :; }
	log_warn() { :; }
	log_error() { :; }
	log_ok() { :; }
	sleep() { :; }
	ss_load_config() {
		ss_enabled="${MOCK_ENABLED:-1}"
		export ss_apply_local_overrides="${MOCK_OVERRIDES:-1}"
		return 0
	}
	ss_mkdirs() { return 0; }
	ss_refresh_lock_open_wait() {
		record "lock_wait $1"
		return "${LOCK_RC:-0}"
	}
	ss_refresh_lock_close() { record lock_close; }
	ss_cached_api_sources_available() { [ "${CACHE_AVAILABLE:-1}" = '1' ]; }
	ss_status_set() { record "status_set $1 ${2:-}"; }
	ss_status_set_now() { record "status_set_now $1"; }
	ss_status_add_error() { record "status_error $1"; }
	ss_prepare_local_rule_files() {
		record prepare_local_rules
		[ "${LOCAL_FAIL:-}" != 'local_rules' ]
	}
	ss_local_rules_fingerprint_from_tmp() { printf '%s\n' "${NEW_FINGERPRINT:-fingerprint-new}"; }
	ss_local_rules_state_read() { [ -n "${APPLIED_FINGERPRINT:-}" ] && printf '%s\n' "$APPLIED_FINGERPRINT"; }
	ss_local_rules_state_write() { record "local_state_write $1"; }
	ss_require_supported_dnsmasq() { [ "${LOCAL_FAIL:-}" != 'dnsmasq_version' ]; }
	ss_dnsmasq_check_error() { printf '%s\n' 'dnsmasq_version_unsupported'; }
	ss_ensure_dnsmasq_confdir() {
		record ensure_confdir
		[ "${LOCAL_FAIL:-}" != 'confdir' ]
	}
	ss_export_existing_blocklist() {
		printf '%s\n' backup >"$SS_PREV_BLOCKLIST_GZ"
		return 0
	}
	ss_merge_lists() {
		record merge_lists
		[ "${LOCAL_FAIL:-}" != 'merge' ]
	}
	dnsmasq_restart() {
		record dnsmasq_restart
		[ "${LOCAL_FAIL:-}" != 'restart' ]
	}
	check_dns_runtime() {
		record check_dns_runtime
		[ "${LOCAL_FAIL:-}" != 'runtime' ]
	}
	check_blocklist_applied_multi_with_stats() {
		record "verify_blocklist $*"
		[ "${LOCAL_FAIL:-}" != 'verify' ]
	}
	ss_restore_and_restart() { record restore_and_restart; }
	ss_mark_local_apply_failure() { record "local_failure $1"; }
	ss_mark_local_apply_success() { record local_success; }
	FALLBACK_RC=0
	safeshield_force_download() {
		record fallback_refresh
		return "$FALLBACK_RC"
	}

	CACHE_AVAILABLE=0
	LOCK_RC=0
	LOCAL_FAIL=''
	: >"$CALLS"
	safeshield_apply_local_rules
	ss_spec_assert_file_line "$CALLS" 'fallback_refresh'
	ss_spec_assert_file_line "$CALLS" 'lock_close'

	CACHE_AVAILABLE=1
	LOCK_RC=1
	: >"$CALLS"
	! safeshield_apply_local_rules
	ss_spec_assert_file_line "$CALLS" 'local_failure local_apply_lock_timeout'

	LOCK_RC=130
	: >"$CALLS"
	set +e
	safeshield_apply_local_rules
	rc=$?
	set -e
	ss_spec_assert_eq "$rc" '130'
	! grep -F 'local_failure' "$CALLS" >/dev/null

	LOCK_RC=0
	APPLIED_FINGERPRINT='fingerprint-new'
	NEW_FINGERPRINT='fingerprint-new'
	printf '%s\n' 'safeshield-block=/cached.example/' >"$SS_BLOCKLIST_FILE"
	: >"$CALLS"
	safeshield_apply_local_rules
	ss_spec_assert_file_line "$CALLS" 'status_set stage done'
	! grep -Fx 'merge_lists' "$CALLS" >/dev/null
	! grep -Fx 'dnsmasq_restart' "$CALLS" >/dev/null

	APPLIED_FINGERPRINT='fingerprint-old'
	NEW_FINGERPRINT='fingerprint-new'
	for scenario in merge restart runtime verify; do
		LOCAL_FAIL="$scenario"
		: >"$CALLS"
		! safeshield_apply_local_rules
		case "$scenario" in
			merge) code='local_merge_failed' ;;
			restart) code='local_dnsmasq_restart_failed' ;;
			runtime) code='local_dns_runtime_check_failed' ;;
			verify) code='local_blocklist_verification_failed' ;;
		esac
		ss_spec_assert_file_line "$CALLS" "local_failure $code"
		ss_spec_assert_file_line "$CALLS" 'restore_and_restart'
		ss_spec_assert_file_line "$CALLS" 'lock_close'
	done

	LOCAL_FAIL=''
	: >"$CALLS"
	safeshield_apply_local_rules
	ss_spec_assert_file_line "$CALLS" 'merge_lists'
	ss_spec_assert_file_line "$CALLS" 'dnsmasq_restart'
	ss_spec_assert_file_line "$CALLS" 'check_dns_runtime'
	ss_spec_assert_file_line "$CALLS" 'verify_blocklist 5 3'
	ss_spec_assert_file_line "$CALLS" 'local_state_write fingerprint-new'
	ss_spec_assert_file_line "$CALLS" 'local_success'
	! grep -Fx 'restore_and_restart' "$CALLS" >/dev/null
)

ss_case_refresh_locking() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	RUNNING_STATUS_FILE="$TMP/status.json"
	SS_REFRESH_LOCK="$TMP/safeshield-refresh.lock"
	SS_REFRESH_LOCK_FD=9
	MOCK_FLOCK_DIR="$TMP/mock-flock.lock"

	# Keep this regression test portable on development hosts such as macOS,
	# where flock(1) is not installed by default. The production code still
	# invokes flock -n/-u; this shim emulates those operations with atomic
	# mkdir/rmdir so contention, release, timeout, and termination paths are
	# exercised without depending on a host-specific flock binary.
	flock() {
		case "${1:-}" in
			-n)
				mkdir "$MOCK_FLOCK_DIR" 2>/dev/null
				;;
			-u)
				rmdir "$MOCK_FLOCK_DIR" 2>/dev/null || true
				return 0
				;;
			*)
				return 2
				;;
		esac
	}

	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/status.sh"
	is_valid_integer() { case "$1" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }
	ss_should_stop() { return 1; }

	mkdir "$MOCK_FLOCK_DIR"
	! ss_refresh_lock_open
	! ss_refresh_lock_open_wait 0
	rmdir "$MOCK_FLOCK_DIR"

	ss_refresh_lock_open
	ss_spec_assert_exists "$MOCK_FLOCK_DIR"
	ss_refresh_lock_close
	ss_spec_assert_not_exists "$MOCK_FLOCK_DIR"

	mkdir "$MOCK_FLOCK_DIR"
	ss_should_stop() { return 0; }
	set +e
	ss_refresh_lock_open_wait 10
	rc=$?
	set -e
	rmdir "$MOCK_FLOCK_DIR"
	ss_spec_assert_eq "$rc" '130'
)

ss_case_service_lifecycle() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	INIT="$SS_SPEC_ROOT/files/etc/init.d/safeshield"
	HARNESS="$TMP/init-lifecycle.sh"
	sed -n '/^start_service() {/,/^reconcile_statistics() {/p' "$INIT" | sed '$d' >"$HARNESS"
	# shellcheck disable=SC1090
	. "$HARNESS"

	export PKG_NAME='safeshield'
	SS_BLOCKLIST_FILE="$TMP/dnsmasq.d/safeshield.blocklist"
	export SS_INACTIVE_BLOCKLIST_FILE="$TMP/inactive.blocklist"
	mkdir -p "${SS_BLOCKLIST_FILE%/*}"
	CALLS="$TMP/calls"
	: >"$CALLS"
	record() { printf '%s\n' "$*" >>"$CALLS"; }
	log_error() { :; }
	log_warn() { :; }
	ss_load_config() {
		export ss_enabled="${MOCK_ENABLED:-1}"
		export ss_statistics_enabled="${MOCK_STATISTICS:-1}"
		return "${LOAD_RC:-0}"
	}
	ss_identity_ensure() {
		record identity_ensure
		return 0
	}
	ss_detect_device_model() { printf '%s\n' 'Test Router'; }
	ss_detect_device_arch() { printf '%s\n' 'test-arch'; }
	ss_mkdirs() {
		record mkdirs
		return 0
	}
	ss_statistics_request_rebaseline() {
		record request_rebaseline
		return 0
	}
	ss_statistics_configure_dnsmasq() {
		record "statistics_configure $1"
		printf '%s\n' "${STATISTICS_CHANGED:-0}"
	}
	ss_runtime_deactivate_blocklist() {
		record deactivate_blocklist
		return "${DEACTIVATE_RC:-0}"
	}
	ss_runtime_activate_blocklist() {
		record activate_blocklist
		return "${ACTIVATE_RC:-0}"
	}
	ss_status_set() { record "status_set $1 ${2:-}"; }
	ss_status_mark_failure() { record "failure $1"; }
	ss_require_supported_dnsmasq() {
		record require_dnsmasq
		return 0
	}
	ss_dnsmasq_check_error() { printf '%s\n' 'dnsmasq_version_unsupported'; }
	ss_statistics_disable_if_dnsmasq_unpatched() {
		record statistics_guard
		return 0
	}
	ss_reconcile_installed_blocklists_for_dnsmasq() {
		record reconcile_blocklists
		return "${MIGRATION_RC:-0}"
	}
	ss_ensure_dnsmasq_confdir() {
		record ensure_confdir
		return 0
	}
	dnsmasq_restart() {
		record dnsmasq_restart
		return "${DNSMASQ_RC:-0}"
	}
	procd_open_instance() { record procd_open_instance; }
	procd_set_param() { record "procd_set_param $*"; }
	procd_close_instance() { record procd_close_instance; }
	ss_statistics_add_procd_instance() { record add_statistics_instance; }
	ss_statistics_add_upload_procd_instance() { record add_statistics_upload_instance; }

	MOCK_ENABLED=0
	MOCK_STATISTICS=1
	STATISTICS_CHANGED=1
	MIGRATION_RC=0
	DNSMASQ_RC=0
	: >"$CALLS"
	start_service
	ss_spec_assert_file_line "$CALLS" 'request_rebaseline'
	ss_spec_assert_file_line "$CALLS" 'statistics_configure 0'
	ss_spec_assert_file_line "$CALLS" 'deactivate_blocklist'
	ss_spec_assert_file_line "$CALLS" 'dnsmasq_restart'
	ss_spec_assert_file_line "$CALLS" 'status_set stage disabled'
	! grep -Fx 'procd_open_instance' "$CALLS" >/dev/null

	printf '%s\n' 'safeshield-block=/active.example/' >"$SS_BLOCKLIST_FILE"
	: >"$CALLS"
	start_service
	ss_spec_assert_file_line "$CALLS" 'deactivate_blocklist'
	! grep -Fx 'dnsmasq_restart' "$CALLS" >/dev/null
	rm -f "$SS_BLOCKLIST_FILE"

	MOCK_ENABLED=1
	MOCK_STATISTICS=1
	STATISTICS_CHANGED=0
	MIGRATION_RC=0
	: >"$CALLS"
	start_service
	ss_spec_assert_file_line "$CALLS" 'require_dnsmasq'
	ss_spec_assert_file_line "$CALLS" 'statistics_guard'
	ss_spec_assert_file_line "$CALLS" 'reconcile_blocklists'
	ss_spec_assert_file_line "$CALLS" 'statistics_configure 1'
	ss_spec_assert_file_line "$CALLS" 'activate_blocklist'
	ss_spec_assert_file_line "$CALLS" 'procd_set_param command /usr/libexec/safeshield-refreshd'
	ss_spec_assert_file_line "$CALLS" 'add_statistics_instance'
	ss_spec_assert_file_line "$CALLS" 'add_statistics_upload_instance'

	MIGRATION_RC=1
	: >"$CALLS"
	! start_service
	ss_spec_assert_file_line "$CALLS" 'failure blocklist_directive_migration_failed'
	! grep -Fx 'activate_blocklist' "$CALLS" >/dev/null
	MIGRATION_RC=0

	MOCK_ENABLED=1
	STATISTICS_CHANGED=1
	rm -f "$SS_BLOCKLIST_FILE"
	: >"$CALLS"
	stop_service
	ss_spec_assert_file_line "$CALLS" 'statistics_configure 0'
	ss_spec_assert_file_line "$CALLS" 'deactivate_blocklist'
	ss_spec_assert_file_line "$CALLS" 'dnsmasq_restart'
	ss_spec_assert_file_line "$CALLS" 'status_set stage stopped'

	printf '%s\n' 'safeshield-block=/active.example/' >"$SS_BLOCKLIST_FILE"
	: >"$CALLS"
	stop_service
	ss_spec_assert_file_line "$CALLS" 'deactivate_blocklist'
	! grep -Fx 'dnsmasq_restart' "$CALLS" >/dev/null
	rm -f "$SS_BLOCKLIST_FILE"

	MOCK_ENABLED=0
	STATISTICS_CHANGED=0
	: >"$CALLS"
	stop_service
	ss_spec_assert_file_line "$CALLS" 'status_set status disabled'
	ss_spec_assert_file_line "$CALLS" 'status_set last_result disabled'
)
