# shellcheck shell=ash

# This file defines globals consumed by other sourced scripts.
# shellcheck disable=SC2034

# Variables below are populated by sourced helpers and ss_load_config()
# shellcheck disable=SC2154

IPKG_INSTROOT="${IPKG_INSTROOT:-}"
export IPKG_INSTROOT
if [ -z "${PKG_NAME:-}" ]; then
	PKG_NAME='safeshield'
fi
export PKG_NAME

# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/share/libubox/jshn.sh"
# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/lib/safeshield/utils.sh"
# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/lib/safeshield/status.sh"
# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/lib/safeshield/log.sh"
# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/lib/safeshield/config.sh"
# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/lib/safeshield/identity.sh"
# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/lib/safeshield/dns.sh"
# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/lib/safeshield/blocklist.sh"

readonly SS_TMP_DIR="/tmp/safeshield"
readonly SS_DNSMASQ_DIR="/tmp/dnsmasq.d"
readonly SS_BLOCKLIST_FILE="${SS_DNSMASQ_DIR}/safeshield.blocklist"
readonly SS_INACTIVE_BLOCKLIST_FILE="${SS_TMP_DIR}/inactive.blocklist"
readonly SS_LOCAL_ALLOWLIST_FILE="/etc/safeshield/allowlist"
readonly SS_LOCAL_BLOCKLIST_FILE="/etc/safeshield/blocklist"
readonly SS_IDENTITY_DIR="/etc/safeshield"
readonly SS_IDENTITY_FILE="${SS_IDENTITY_DIR}/identity.env"
readonly SS_API_PAYLOAD="${SS_TMP_DIR}/resolve-request.json"
readonly SS_API_RESPONSE="${SS_TMP_DIR}/resolve-response.json"
readonly SS_RESOLVED_SOURCES="${SS_TMP_DIR}/resolved-sources.tsv"
readonly SS_ARTIFACT_CACHE_STATE="${SS_TMP_DIR}/artifact-sources.state"
readonly SS_MAX_ARTIFACT_SOURCES=16
readonly SS_PREV_BLOCKLIST_GZ="/tmp/safeshield.prev.blocklist.gz"
readonly SS_RUNTIME_OUT="${SS_TMP_DIR}/runtime.out"
readonly SS_REFRESH_LOCK='/var/lock/safeshield-refresh.lock'
readonly SS_REFRESH_LOCK_FD=307
readonly SS_LOCAL_APPLY_STATE="${SS_TMP_DIR}/local-apply.state"
readonly SS_STATISTICS_DIR="${SS_TMP_DIR}/statistics"
readonly SS_STATISTICS_STATE_FILE="${SS_STATISTICS_DIR}/state.tsv"
readonly SS_STATISTICS_JSON_FILE="${SS_STATISTICS_DIR}/statistics.json"
readonly SS_STATISTICS_UPLOAD_JSON_FILE="${SS_STATISTICS_DIR}/upload.json"
readonly SS_STATISTICS_UPLOAD_CREDENTIALS_FILE="${SS_STATISTICS_DIR}/upload.credentials"
readonly SS_STATISTICS_UPLOAD_ENTITLEMENT_FILE="${SS_STATISTICS_DIR}/upload.entitlement"
readonly SS_STATISTICS_UPLOAD_PENDING_FILE="${SS_STATISTICS_DIR}/upload.pending.json"
readonly SS_STATISTICS_UPLOAD_PENDING_META_FILE="${SS_STATISTICS_DIR}/upload.pending.meta"
readonly SS_STATISTICS_UPLOAD_STATE_FILE="${SS_STATISTICS_DIR}/upload.state"
readonly SS_STATISTICS_DNSMASQ_CONF="${SS_DNSMASQ_DIR}/safeshield.statistics.conf"

# shellcheck disable=SC1091
. "${IPKG_INSTROOT}/usr/lib/safeshield/statistics.sh"

ss_should_terminate="${ss_should_terminate:-0}"

ss_should_stop() {
	[ "${ss_should_terminate:-0}" -eq 1 ]
}

ss_abort_refresh() {
	log_warn "Termination requested, aborting current refresh"
	ss_status_add_warning "refresh_terminated"
	ss_status_set last_result "terminated"
	ss_refresh_lock_close
	return 130
}

ss_restore_and_restart() {
	ss_restore_previous_blocklist >/dev/null 2>&1 || true
	dnsmasq_restart >/dev/null 2>&1 || true
}

ss_ensure_dnsmasq_confdir() {
	local changed=0

	mkdir -p "${SS_DNSMASQ_DIR}" || {
		log_error "Failed to create dnsmasq confdir: ${SS_DNSMASQ_DIR}"
		return 1
	}

	if ss_check_dnsmasq_confdir; then
		return 0
	fi

	uci -q get dhcp.@dnsmasq[0] >/dev/null || {
		log_error "dnsmasq UCI section not found: dhcp.@dnsmasq[0]"
		return 1
	}

	log_warn "dnsmasq confdir is not set to ${SS_DNSMASQ_DIR}, attempting automatic setup"

	if ! uci show dhcp | grep -Fq ".confdir='${SS_DNSMASQ_DIR}'"; then
		uci add_list dhcp.@dnsmasq[0].confdir="${SS_DNSMASQ_DIR}" || {
			log_error "Failed to add dhcp.@dnsmasq[0].confdir=${SS_DNSMASQ_DIR}"
			return 1
		}
		changed=1
	fi

	if [ "${changed}" -eq 1 ]; then
		uci commit dhcp || {
			log_error "Failed to commit dhcp config"
			return 1
		}

		log_info "Restarting dnsmasq after updating confdir"
		dnsmasq_restart || {
			log_error "Failed to restart dnsmasq after configuring confdir"
			return 1
		}
	fi

	ss_check_dnsmasq_confdir || {
		log_error "dnsmasq confdir verification failed after automatic setup"
		return 1
	}

	return 0
}

ss_sync_blocklist_status() {
	local file_size_kb valid_line_count

	if [ ! -f "${SS_BLOCKLIST_FILE}" ]; then
		ss_status_set blocklist_installed "0"
		ss_status_set blocklist_file_size_kb "0"
		ss_status_set valid_line_count "0"
		ss_status_set blocklist_verification_ok "0"
		ss_status_set health_blocklist_verify ""
		return 0
	fi

	file_size_kb="$(du -k "${SS_BLOCKLIST_FILE}" 2>/dev/null | awk '{print $1}')"
	valid_line_count="$(grep -c . "${SS_BLOCKLIST_FILE}" 2>/dev/null)"

	[ -n "$file_size_kb" ] || file_size_kb="0"
	[ -n "$valid_line_count" ] || valid_line_count="0"

	ss_status_set blocklist_installed "1"
	ss_status_set blocklist_file_size_kb "$file_size_kb"
	ss_status_set valid_line_count "$valid_line_count"
}

ss_stage_active_blocklist() {
	[ -f "${SS_BLOCKLIST_FILE}" ] || return 0

	rm -f "${SS_INACTIVE_BLOCKLIST_FILE}"
	ss_sync_path "${SS_BLOCKLIST_FILE}"
	mv -f "${SS_BLOCKLIST_FILE}" "${SS_INACTIVE_BLOCKLIST_FILE}" || return 1
	ss_sync_path "${SS_DNSMASQ_DIR}"
	ss_sync_path "${SS_TMP_DIR}"
	return 0
}

ss_restore_staged_blocklist() {
	[ -f "${SS_INACTIVE_BLOCKLIST_FILE}" ] || return 1

	mv -f "${SS_INACTIVE_BLOCKLIST_FILE}" "${SS_BLOCKLIST_FILE}" || return 1
	ss_sync_path "${SS_DNSMASQ_DIR}"
	return 0
}

ss_runtime_deactivate_blocklist() {
	local rc

	ss_mkdirs || return 1

	if [ ! -f "${SS_BLOCKLIST_FILE}" ]; then
		ss_sync_blocklist_status
		return 0
	fi

	log_info "Deactivating SafeShield blocklist"
	ss_stage_active_blocklist || {
		log_error "Failed to stage active blocklist for deactivation"
		return 1
	}

	dnsmasq_restart
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log_error "dnsmasq restart failed while deactivating SafeShield; restoring blocklist"
		ss_restore_staged_blocklist >/dev/null 2>&1 || true
		dnsmasq_restart >/dev/null 2>&1 || true
		ss_sync_blocklist_status
		return "$rc"
	fi

	ss_sync_blocklist_status
	ss_status_set health_dnsmasq_final_restart "1"
	log_ok "SafeShield blocklist deactivated"
	return 0
}

ss_runtime_activate_blocklist() {
	local rc

	ss_mkdirs || return 1

	if [ ! -f "${SS_BLOCKLIST_FILE}" ] && [ -f "${SS_INACTIVE_BLOCKLIST_FILE}" ]; then
		log_info "Restoring staged SafeShield blocklist"
		ss_restore_staged_blocklist || {
			log_error "Failed to restore staged SafeShield blocklist"
			return 1
		}
	fi

	if [ ! -f "${SS_BLOCKLIST_FILE}" ]; then
		ss_sync_blocklist_status
		return 0
	fi

	ss_ensure_dnsmasq_confdir || {
		log_error "dnsmasq confdir is unavailable while activating SafeShield"
		ss_stage_active_blocklist >/dev/null 2>&1 || true
		ss_sync_blocklist_status
		return 1
	}

	dnsmasq_restart
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log_error "dnsmasq restart failed while activating SafeShield"
		ss_stage_active_blocklist >/dev/null 2>&1 || true
		dnsmasq_restart >/dev/null 2>&1 || true
		ss_sync_blocklist_status
		return "$rc"
	fi

	check_blocklist_applied_multi_with_stats 5 3
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log_error "SafeShield blocklist is not active in dnsmasq"
		ss_status_set health_blocklist_verify "0"
		ss_status_set blocklist_verification_ok "0"
		ss_stage_active_blocklist >/dev/null 2>&1 || true
		dnsmasq_restart >/dev/null 2>&1 || true
		ss_sync_blocklist_status
		return "$rc"
	fi

	rm -f "${SS_INACTIVE_BLOCKLIST_FILE}"
	ss_sync_blocklist_status
	ss_status_set health_dnsmasq_final_restart "1"
	ss_status_set health_blocklist_verify "1"
	ss_status_set blocklist_verification_ok "1"
	log_ok "SafeShield blocklist active in dnsmasq"
	return 0
}

ss_local_rules_fingerprint_from_tmp() {
	{
		printf '%s\n' '[allow]'
		[ -f "${SS_TMP_DIR}/local.allow.txt" ] && cat "${SS_TMP_DIR}/local.allow.txt"
		printf '%s\n' '[block]'
		[ -f "${SS_TMP_DIR}/local.block.txt" ] && cat "${SS_TMP_DIR}/local.block.txt"
	} | cksum | awk '{ print $1 ":" $2 }'
}

ss_local_rules_state_read() {
	[ -s "${SS_LOCAL_APPLY_STATE}" ] || return 1
	head -n 1 "${SS_LOCAL_APPLY_STATE}" 2>/dev/null
}

ss_local_rules_state_write() {
	local fingerprint="$1"
	local tmp="${SS_LOCAL_APPLY_STATE}.tmp.$$"

	[ -n "$fingerprint" ] || return 1
	printf '%s\n' "$fingerprint" >"$tmp" || return 1
	ss_sync_path "$tmp"
	mv -f "$tmp" "${SS_LOCAL_APPLY_STATE}" || {
		rm -f "$tmp"
		return 1
	}
	ss_sync_path "${SS_TMP_DIR}"
	return 0
}

ss_prepare_local_rule_files() {
	if [ "${ss_apply_local_overrides}" = "1" ]; then
		ss_build_local_allowlist || return 1
		ss_build_local_blocklist || return 1
	else
		: >"${SS_TMP_DIR}/local.allow.txt" || return 1
		: >"${SS_TMP_DIR}/local.block.txt" || return 1
	fi

}

ss_mark_local_apply_failure() {
	local code="$1"

	ss_status_set status "error"
	ss_status_set stage "local_apply_failed"
	ss_status_set_now last_local_apply_failure
	ss_status_set last_result "error"
	ss_status_set last_error_code "$code"
	ss_status_add_error "$code"
}

ss_mark_local_apply_success() {
	ss_status_set status "ready"
	ss_status_set stage "done"
	ss_status_set_now last_local_apply
	ss_status_set last_result "success"
	ss_status_set last_error_code ""
}

safeshield_apply_local_rules() {
	local rc fingerprint applied_fingerprint
	local wait_timeout=120

	ss_load_config || return 1
	ss_mkdirs || return 1

	if [ "${ss_enabled}" != "1" ]; then
		log_warn "Local rule apply skipped because SafeShield is disabled"
		return 0
	fi

	if [ "${ss_apply_local_overrides}" != "1" ]; then
		log_warn "Local rule apply skipped because apply_local_overrides is disabled"
		return 0
	fi

	# Short engine-side debounce lets rapid rule edits converge before the first
	# worker acquires the shared refresh lock. Later workers will fingerprint the
	# same normalized state and exit without another dnsmasq restart.
	sleep 1

	log_info "Waiting for SafeShield refresh lock before applying local rules"
	ss_refresh_lock_open_wait "$wait_timeout"
	rc=$?
	case "$rc" in
		0) ;;
		130) return 130 ;;
		*)
			log_error "Timed out waiting for SafeShield refresh lock"
			ss_mark_local_apply_failure "local_apply_lock_timeout"
			return 1
			;;
	esac

	# Configuration may have changed while waiting for a full refresh.
	ss_load_config || {
		ss_mark_local_apply_failure "config_load_failed"
		ss_refresh_lock_close
		return 1
	}

	if [ "${ss_enabled}" != "1" ]; then
		ss_refresh_lock_close
		return 0
	fi

	if [ "${ss_apply_local_overrides}" != "1" ]; then
		ss_refresh_lock_close
		return 0
	fi

	# Normalized Hub sources are retained after a successful refresh. If the
	# complete cached source set is unavailable (for example after reboot), fall
	# back to one full refresh rather than reconstructing the Hub/local boundary
	# from the active dnsmasq file.
	if ! ss_cached_api_sources_available; then
		log_warn "Cached Hub artifact is unavailable; falling back to full refresh"
		ss_refresh_lock_close
		safeshield_force_download
		rc=$?
		if [ "$rc" -ne 0 ]; then
			ss_status_set_now last_local_apply_failure
		fi
		return "$rc"
	fi

	ss_status_set status "running"
	ss_status_set stage "local_apply"
	ss_status_set last_result "running"
	ss_status_set last_error_code ""

	ss_prepare_local_rule_files || {
		log_error "Failed to normalize local SafeShield rules"
		ss_mark_local_apply_failure "local_rules_build_failed"
		ss_refresh_lock_close
		return 1
	}

	fingerprint="$(ss_local_rules_fingerprint_from_tmp)"
	applied_fingerprint="$(ss_local_rules_state_read 2>/dev/null || true)"

	# Multiple rapid rule mutations may spawn several background apply workers.
	# Once the newest normalized local state is active, later workers can exit
	# without another dnsmasq restart.
	if [ -n "$fingerprint" ] && [ "$fingerprint" = "$applied_fingerprint" ] && [ -f "${SS_BLOCKLIST_FILE}" ]; then
		log_info "Local SafeShield rules are already applied; skipping duplicate apply"
		ss_status_set status "ready"
		ss_status_set stage "done"
		ss_status_set last_result "success"
		ss_status_set last_error_code ""
		ss_refresh_lock_close
		return 0
	fi

	ss_require_supported_dnsmasq || {
		ss_mark_local_apply_failure "$(ss_dnsmasq_check_error)"
		ss_refresh_lock_close
		return 1
	}

	ss_ensure_dnsmasq_confdir || {
		ss_status_set health_dnsmasq_confdir "0"
		ss_mark_local_apply_failure "dnsmasq_confdir_not_set"
		ss_refresh_lock_close
		return 1
	}
	ss_status_set health_dnsmasq_confdir "1"

	ss_export_existing_blocklist >/dev/null 2>&1 || true
	if [ -f "${SS_PREV_BLOCKLIST_GZ}" ]; then
		ss_status_set blocklist_backup_available "1"
	fi

	ss_status_set stage "local_merge"
	ss_merge_lists
	rc=$?
	case "$rc" in
		0) ;;
		130)
			ss_refresh_lock_close
			return 130
			;;
		*)
			log_error "Failed to merge cached Hub artifact with local rules"
			ss_mark_local_apply_failure "local_merge_failed"
			ss_restore_and_restart
			ss_refresh_lock_close
			return 1
			;;
	esac

	ss_status_set stage "local_restart_dnsmasq"
	dnsmasq_restart
	rc=$?
	case "$rc" in
		0)
			ss_status_set health_dnsmasq_final_restart "1"
			;;
		130)
			ss_refresh_lock_close
			return 130
			;;
		*)
			log_error "dnsmasq restart failed after local rule merge"
			ss_status_set health_dnsmasq_final_restart "0"
			ss_mark_local_apply_failure "local_dnsmasq_restart_failed"
			ss_restore_and_restart
			ss_refresh_lock_close
			return 1
			;;
	esac

	ss_status_set stage "local_runtime_check"
	check_dns_runtime
	rc=$?
	case "$rc" in
		0)
			ss_status_set health_dns_runtime "1"
			;;
		130)
			ss_refresh_lock_close
			return 130
			;;
		*)
			log_error "DNS runtime check failed after local rule merge"
			ss_status_set health_dns_runtime "0"
			ss_mark_local_apply_failure "local_dns_runtime_check_failed"
			ss_restore_and_restart
			ss_refresh_lock_close
			return 1
			;;
	esac

	ss_status_set stage "local_blocklist_verify"
	check_blocklist_applied_multi_with_stats 5 3
	rc=$?
	case "$rc" in
		0)
			ss_status_set health_blocklist_verify "1"
			ss_status_set blocklist_verification_ok "1"
			ss_local_rules_state_write "$fingerprint" || true
			ss_mark_local_apply_success
			rm -f "${SS_PREV_BLOCKLIST_GZ}" "${SS_INACTIVE_BLOCKLIST_FILE}"
			ss_status_set blocklist_backup_available "0"
			ss_refresh_lock_close
			log_ok "Local SafeShield rules applied using cached Hub artifact"
			return 0
			;;
		130)
			ss_refresh_lock_close
			return 130
			;;
		*)
			log_error "Local blocklist verification failed; restoring previous blocklist"
			ss_status_set health_blocklist_verify "0"
			ss_status_set blocklist_verification_ok "0"
			ss_mark_local_apply_failure "local_blocklist_verification_failed"
			ss_restore_and_restart
			ss_refresh_lock_close
			return 1
			;;
	esac
}

safeshield_force_download() {
	local rc refresh_interval failure_code

	if ! ss_refresh_lock_open; then
		log_warn "Another refresh is already running, skipping"
		return 0
	fi

	ss_status_prepare_refresh
	ss_status_set status "running"
	ss_status_set stage "init"
	ss_status_set_now last_attempt
	ss_status_set last_result "running"
	ss_status_set last_error_code ""

	ss_load_config || {
		ss_status_mark_failure "config_load_failed"
		ss_refresh_lock_close
		return 1
	}

	refresh_interval="$(ss_config_get config refresh_interval_s 28800)"
	if ! is_valid_integer "$refresh_interval" || [ "$refresh_interval" -le 0 ] 2>/dev/null; then
		refresh_interval=28800
	fi

	if [ "${ss_enabled}" != "1" ]; then
		log_warn "SafeShield refresh skipped because the service is disabled"
		ss_status_set status "disabled"
		ss_status_set stage "disabled"
		ss_status_set last_result "disabled"
		ss_status_set next_refresh_at "0"
		ss_refresh_lock_close
		return 0
	fi

	ss_sync_detected_device_config || true

	ss_identity_ensure "$(ss_detect_device_model 2>/dev/null || echo OpenWrt)" "$(ss_detect_device_arch 2>/dev/null || echo unknown)" || {
		ss_status_mark_failure "identity_init_failed"
		ss_refresh_lock_close
		return 1
	}

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_mkdirs || {
		ss_status_mark_failure "mkdir_failed"
		ss_refresh_lock_close
		return 1
	}

	ss_clean_tmp

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_require_supported_dnsmasq || {
		ss_status_mark_failure "$(ss_dnsmasq_check_error)"
		ss_refresh_lock_close
		return 1
	}

	ss_ensure_dnsmasq_confdir || {
		log_error "dnsmasq confdir could not be configured automatically for ${SS_DNSMASQ_DIR}"
		ss_status_set health_dnsmasq_confdir "0"
		ss_status_mark_failure "dnsmasq_confdir_not_set"
		ss_refresh_lock_close
		return 1
	}
	ss_status_set health_dnsmasq_confdir "1"

	ss_export_existing_blocklist >/dev/null 2>&1 || true
	if [ -f "${SS_PREV_BLOCKLIST_GZ}" ]; then
		ss_status_set blocklist_backup_available "1"
	else
		ss_status_set blocklist_backup_available "0"
	fi

	if [ "${ss_initial_dnsmasq_restart}" = "1" ]; then
		dnsmasq_restart
		rc=$?
		case "$rc" in
			0)
				ss_status_set health_dnsmasq_initial_restart "1"
				;;
			130)
				ss_abort_refresh
				return $?
				;;
			*)
				log_error "Initial dnsmasq restart failed"
				ss_status_set health_dnsmasq_initial_restart "0"
				ss_status_mark_failure "initial_dnsmasq_restart_failed"
				ss_refresh_lock_close
				return 1
				;;
		esac
	else
		ss_status_set health_dnsmasq_initial_restart ""
	fi

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_status_set stage "resolve_api"
	ss_resolve_artifact
	rc=$?
	case "$rc" in
		0) ;;
		130)
			ss_abort_refresh
			return $?
			;;
		*)
			failure_code="$(ss_resolve_error_code)"
			ss_status_mark_failure "$failure_code"
			if [ "$failure_code" != "safeshield_upgrade_required" ]; then
				ss_restore_and_restart
			fi
			ss_refresh_lock_close
			return 1
			;;
	esac

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_status_set stage "download_artifact"
	ss_download_api_artifacts
	rc=$?
	case "$rc" in
		0) ;;
		130)
			ss_abort_refresh
			return $?
			;;
		*)
			failure_code="$(ss_artifact_download_error_code)"
			ss_status_mark_failure "$failure_code"
			if [ "$failure_code" != "safeshield_upgrade_required" ]; then
				ss_restore_and_restart
			fi
			ss_refresh_lock_close
			return 1
			;;
	esac

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_status_set stage "local_overrides"
	ss_prepare_local_rule_files || {
		log_error "Failed to build allowlist"
		ss_status_mark_failure "allowlist_build_failed"
		ss_restore_and_restart
		ss_refresh_lock_close
		return 1
	}

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_status_set stage "merge"
	ss_merge_lists
	rc=$?
	case "$rc" in
		0) ;;
		130)
			ss_abort_refresh
			return $?
			;;
		*)
			log_error "Failed to merge API artifact with local overrides"
			ss_status_mark_failure "merge_failed"
			ss_restore_and_restart
			ss_refresh_lock_close
			return 1
			;;
	esac

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_status_set stage "install"
	ss_install_blocklist || {
		log_error "Failed to install blocklist"
		ss_status_mark_failure "install_failed"
		ss_restore_and_restart
		ss_refresh_lock_close
		return 1
	}

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_status_set stage "restart_dnsmasq"
	dnsmasq_restart
	rc=$?
	case "$rc" in
		0)
			ss_status_set health_dnsmasq_final_restart "1"
			;;
		130)
			ss_abort_refresh
			return $?
			;;
		*)
			log_error "dnsmasq restart failed"
			ss_status_set health_dnsmasq_final_restart "0"
			ss_status_mark_failure "dnsmasq_restart_failed"
			ss_restore_and_restart
			ss_refresh_lock_close
			return 1
			;;
	esac

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_status_set stage "runtime_check"
	check_dns_runtime
	rc=$?
	case "$rc" in
		0)
			ss_status_set health_dns_runtime "1"
			;;
		130)
			ss_abort_refresh
			return $?
			;;
		*)
			log_error "DNS runtime check failed, restoring previous blocklist"
			ss_status_set health_dns_runtime "0"
			ss_status_mark_failure "dns_runtime_check_failed"
			ss_restore_and_restart
			ss_refresh_lock_close
			return 1
			;;
	esac

	if ss_should_stop; then
		ss_abort_refresh
		return $?
	fi

	ss_status_set stage "blocklist_verify"
	check_blocklist_applied_multi_with_stats 5 3
	rc=$?

	case "$rc" in
		0)
			log_ok "SafeShield applied successfully"
			ss_status_set health_blocklist_verify "1"
			ss_status_set blocklist_verification_ok "1"
			ss_local_rules_state_write "$(ss_local_rules_fingerprint_from_tmp)" || true
			ss_status_set_now last_local_apply
			ss_status_mark_success "$refresh_interval"
			rm -f "${SS_PREV_BLOCKLIST_GZ}" "${SS_INACTIVE_BLOCKLIST_FILE}"
			ss_status_set blocklist_backup_available "0"
			ss_refresh_lock_close
			return 0
			;;
		130)
			ss_abort_refresh
			return $?
			;;
		*)
			log_error "Blocklist verification failed, restoring previous blocklist"
			ss_status_set health_blocklist_verify "0"
			ss_status_set blocklist_verification_ok "0"
			ss_status_mark_failure "blocklist_verification_failed"
			ss_restore_and_restart
			ss_refresh_lock_close
			return 1
			;;
	esac
}
