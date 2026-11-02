# shellcheck shell=ash

# Variables below are populated by sourced helpers and ss_load_config()
# shellcheck disable=SC2154

readonly SS_STATUS_STORE='/usr/lib/safeshield/status-store.uc'

ss_status_exec() {
	ucode "${SS_STATUS_STORE}" "${RUNNING_STATUS_FILE}" "$@"
}

ss_status_apply() {
	local tmp="${RUNNING_STATUS_FILE}.tmp.$$" rc=0

	mkdir -p "${RUNNING_STATUS_FILE%/*}" || return 1
	json_lock_open || return 1

	ss_status_exec "$@" >"$tmp" || rc=1
	[ "$rc" -eq 0 ] && [ -s "$tmp" ] || rc=1
	if [ "$rc" -eq 0 ]; then
		mv -f "$tmp" "$RUNNING_STATUS_FILE" || rc=1
	fi
	[ "$rc" -eq 0 ] || rm -f "$tmp"
	json_lock_close
	return "$rc"
}

ss_now() {
	date +%s
}

ss_status_set_now() {
	ss_status_set "$1" "$(ss_now)"
}

# A single status-store invocation updates all pairs while holding the same
# JSON lock. This avoids spawning ucode once per field during a refresh reset.
ss_status_set_many() {
	[ "$#" -gt 0 ] || return 0
	ss_status_apply set_many "$@" >/dev/null 2>&1 || true
}

ss_status_reset_health_fields() {
	ss_status_set_many \
		health_dnsmasq_binary "" \
		health_dnsmasq_version "" \
		health_dnsmasq_features "" \
		health_dnsmasq_confdir "" \
		health_dnsmasq_initial_restart "" \
		health_dnsmasq_final_restart "" \
		health_dns_runtime "" \
		health_blocklist_verify "" \
		health_min_valid_line_count "" \
		health_max_file_size "" \
		health_api_resolve "" \
		health_artifact_download "" \
		health_artifact_sha256 "" \
		dnsmasq_version "" \
		dnsmasq_min_version "${SS_MIN_DNSMASQ_VERSION:-2.93}"
}

ss_status_reset_blocklist_fields() {
	ss_status_set_many \
		blocklist_installed "0" \
		blocklist_file_size_kb "0" \
		blocklist_verification_ok "0" \
		blocklist_test_domain "" \
		blocklist_test_domain_sample_count "0" \
		blocklist_test_domain_success_count "0" \
		blocklist_test_domains "" \
		blocklist_backup_available "0"
}

ss_status_reset_artifact_fields() {
	ss_status_set_many \
		entitlement_plan "" \
		entitlement_status "" \
		physical_fingerprint "" \
		fingerprint_version "" \
		identity_provider "" \
		identity_source "" \
		identity_strength "" \
		identity_profile "" \
		device_code "" \
		device_code_source "" \
		installation_id "" \
		device_profile "" \
		artifact_tier "" \
		artifact_version "" \
		artifact_sha256 "" \
		artifact_unique_domains "0" \
		artifact_rules "0" \
		artifact_download_url_present "0" \
		artifact_source_count "0" \
		artifact_block_source_count "0" \
		artifact_allow_source_count "0"
}

ss_status_mark_failure() {
	local code="$1"

	ss_status_set_many \
		status "error" \
		last_failure "$(ss_now)" \
		last_result "error" \
		last_error_code "$code"
	ss_status_add_error "$code"
}

ss_status_mark_success() {
	local interval="${1:-0}"
	local now

	now="$(ss_now)"
	ss_status_apply clear_messages >/dev/null 2>&1 || true
	if is_valid_integer "$interval" && [ "$interval" -gt 0 ] 2>/dev/null; then
		ss_status_set_many \
			status "ready" stage "done" last_success "$now" \
			last_result "success" last_error_code "" \
			next_refresh_at "$((now + interval))"
	else
		ss_status_set_many \
			status "ready" stage "done" last_success "$now" \
			last_result "success" last_error_code ""
	fi
}

ss_status_prepare_refresh() {
	local last_success last_local_apply last_local_apply_failure

	last_success="$(json get last_success 2>/dev/null)"
	last_local_apply="$(json get last_local_apply 2>/dev/null)"
	last_local_apply_failure="$(json get last_local_apply_failure 2>/dev/null)"
	is_valid_integer "$last_success" || last_success=0
	is_valid_integer "$last_local_apply" || last_local_apply=0
	is_valid_integer "$last_local_apply_failure" || last_local_apply_failure=0

	ss_status_reset
	ss_status_set_many \
		last_success "$last_success" \
		last_local_apply "$last_local_apply" \
		last_local_apply_failure "$last_local_apply_failure"
}

ss_status_set() {
	local key="$1"
	local value="$2"

	[ -n "$key" ] || return 0
	ss_status_apply set "$key" "$value" >/dev/null 2>&1 || true
}

ss_status_add_error() {
	local code="$1"

	[ -n "$code" ] || return 0
	ss_status_apply add_error "$code" >/dev/null 2>&1 || true
}

ss_status_add_warning() {
	local code="$1"

	[ -n "$code" ] || return 0
	ss_status_apply add_warning "$code" >/dev/null 2>&1 || true
}

ss_status_reset() {
	ss_status_apply reset >/dev/null 2>&1 || return 1

	ss_status_set_many \
		status "idle" stage "" valid_line_count "0" \
		last_result "idle" last_error_code "" \
		last_attempt "0" last_success "0" last_failure "0" \
		last_local_apply "0" last_local_apply_failure "0" \
		next_refresh_at "0"

	ss_status_reset_health_fields
	ss_status_reset_blocklist_fields
	ss_status_reset_artifact_fields
	ss_status_apply clear_messages >/dev/null 2>&1 || true
}

ss_blocklist_tmp_path() {
	printf '%s/.safeshield.blocklist.tmp.%s' "${SS_DNSMASQ_DIR}" "$$"
}

ss_backup_tmp_path() {
	printf '%s.tmp.%s' "${SS_PREV_BLOCKLIST_GZ}" "$$"
}

ss_sync_path() {
	local path="$1"

	[ -n "$path" ] || return 0

	sync -f "$path" 2>/dev/null && return 0
	sync "$path" 2>/dev/null && return 0
	sync 2>/dev/null || true
}

ss_install_blocklist_atomic() {
	local src="$1"
	local dst="$2"
	local dir

	[ -f "$src" ] || return 1
	[ -n "$dst" ] || return 1

	dir="${dst%/*}"

	ss_sync_path "$src"
	mv -f "$src" "$dst" || return 1
	ss_sync_path "$dir"

	return 0
}

ss_export_existing_blocklist() {
	local tmp

	[ -f "${SS_BLOCKLIST_FILE}" ] || return 1
	command_exists gzip || return 1

	tmp="$(ss_backup_tmp_path)" || return 1

	gzip -c "${SS_BLOCKLIST_FILE}" >"$tmp" || {
		rm -f "$tmp"
		return 1
	}

	ss_sync_path "$tmp"
	mv -f "$tmp" "${SS_PREV_BLOCKLIST_GZ}" || {
		rm -f "$tmp"
		return 1
	}
	ss_sync_path "${SS_PREV_BLOCKLIST_GZ%/*}"

	return 0
}

ss_restore_previous_blocklist() {
	local tmp

	[ -f "${SS_PREV_BLOCKLIST_GZ}" ] || return 1
	command_exists gunzip || return 1

	tmp="$(ss_blocklist_tmp_path)" || return 1

	gunzip -c "${SS_PREV_BLOCKLIST_GZ}" >"$tmp" || {
		rm -f "$tmp"
		return 1
	}

	ss_install_blocklist_atomic "$tmp" "${SS_BLOCKLIST_FILE}" || {
		rm -f "$tmp"
		return 1
	}

	return 0
}

ss_refresh_lock_open() {
	ss_lock_try "${SS_REFRESH_LOCK}.d"
}

ss_refresh_lock_open_wait() {
	local timeout="${1:-120}"
	is_valid_integer "$timeout" || timeout=120
	ss_lock_wait "${SS_REFRESH_LOCK}.d" "$timeout" ss_should_stop
}

ss_refresh_lock_close() {
	ss_lock_release "${SS_REFRESH_LOCK}.d"
}
