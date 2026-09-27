# shellcheck shell=ash

# This file defines globals consumed by other sourced scripts.
# shellcheck disable=SC2034

ss_enabled="0"
ss_verbosity="2"
ss_license_key=""
ss_device_vendor=""
ss_device_model=""
ss_device_arch=""
ss_device_memory_mb=""
ss_apply_local_overrides="1"
ss_max_blocklist_file_size_kb="30000"
ss_min_valid_line_count="3000"
ss_compress_blocklist="0"
ss_initial_dnsmasq_restart="0"
ss_download_timeout="10"
ss_download_retry="3"
ss_pause_timeout="20"
ss_boot_start_delay_s="30"
ss_dnsmasq_sanity_check="1"
ss_statistics_enabled="1"
ss_statistics_snapshot_interval_s="60"
ss_statistics_retention_hours="168"

ss_valid_line_count="0"

ss_config_get() {
	local section="$1"
	local option="$2"
	local default="$3"
	local value

	config_get value "$section" "$option"
	if [ -n "$value" ]; then
		printf '%s' "$value"
	else
		printf '%s' "$default"
	fi
}

ss_validate_bool() {
	local var_name="$1"
	local default="$2"
	local warning_code="$3"
	local value

	eval "value=\${$var_name}"

	case "$value" in
		0 | 1) return 0 ;;
	esac

	log_warn "Invalid ${var_name} '${value}', using default ${default}"
	ss_status_add_warning "$warning_code"
	eval "$var_name=\$default"
}

ss_validate_int() {
	local var_name="$1"
	local default="$2"
	local warning_code="$3"
	local value

	eval "value=\${$var_name}"

	if ! is_valid_integer "$value"; then
		log_warn "Invalid ${var_name} '${value}', using default ${default}"
		ss_status_add_warning "$warning_code"
		eval "$var_name=\$default"
	fi
}

ss_validate_config() {
	ss_validate_int ss_download_timeout 10 invalid_download_timeout
	ss_validate_int ss_download_retry 3 invalid_download_retry
	ss_validate_int ss_max_blocklist_file_size_kb 30000 invalid_max_blocklist_file_size_kb
	ss_validate_int ss_min_valid_line_count 3000 invalid_min_valid_line_count
	ss_validate_int ss_pause_timeout 20 invalid_pause_timeout
	ss_validate_int ss_boot_start_delay_s 30 invalid_boot_start_delay_s
	ss_validate_int ss_statistics_snapshot_interval_s 60 invalid_statistics_snapshot_interval_s
	ss_validate_int ss_statistics_retention_hours 168 invalid_statistics_retention_hours

	ss_validate_bool ss_compress_blocklist 0 invalid_compress_blocklist
	ss_validate_bool ss_initial_dnsmasq_restart 0 invalid_initial_dnsmasq_restart
	ss_validate_bool ss_dnsmasq_sanity_check 1 invalid_dnsmasq_sanity_check
	ss_validate_bool ss_apply_local_overrides 1 invalid_apply_local_overrides
	ss_validate_bool ss_statistics_enabled 1 invalid_statistics_enabled

	if [ "$ss_statistics_snapshot_interval_s" -lt 10 ] 2>/dev/null || [ "$ss_statistics_snapshot_interval_s" -gt 3600 ] 2>/dev/null; then
		log_warn "statistics_snapshot_interval_s must be between 10 and 3600 seconds, using 60"
		ss_status_add_warning "invalid_statistics_snapshot_interval_s"
		ss_statistics_snapshot_interval_s=60
	fi
	if [ "$ss_statistics_retention_hours" -lt 1 ] 2>/dev/null || [ "$ss_statistics_retention_hours" -gt 168 ] 2>/dev/null; then
		log_warn "statistics_retention_hours must be between 1 and 168, using 168"
		ss_status_add_warning "invalid_statistics_retention_hours"
		ss_statistics_retention_hours=168
	fi
}

ss_load_config() {
	config_load safeshield || return 1

	ss_enabled="$(ss_config_get config enabled 0)"
	ss_verbosity="$(ss_config_get config verbosity 2)"
	ss_license_key="$(ss_config_get config license_key '')"
	ss_device_vendor="$(ss_config_get config device_vendor '')"
	ss_device_model="$(ss_config_get config device_model '')"
	ss_device_arch="$(ss_config_get config device_arch '')"
	ss_device_memory_mb="$(ss_config_get config device_memory_mb '')"
	ss_apply_local_overrides="$(ss_config_get config apply_local_overrides 1)"
	ss_max_blocklist_file_size_kb="$(ss_config_get config max_blocklist_file_size_kb 30000)"
	ss_min_valid_line_count="$(ss_config_get config min_valid_line_count 3000)"
	ss_compress_blocklist="$(ss_config_get config compress_blocklist 0)"
	ss_initial_dnsmasq_restart="$(ss_config_get config initial_dnsmasq_restart 0)"
	ss_download_timeout="$(ss_config_get config download_timeout 10)"
	ss_download_retry="$(ss_config_get config download_retry 3)"
	ss_pause_timeout="$(ss_config_get config pause_timeout 20)"
	ss_boot_start_delay_s="$(ss_config_get config boot_start_delay_s 30)"
	ss_dnsmasq_sanity_check="$(ss_config_get config dnsmasq_sanity_check 1)"
	ss_statistics_enabled="$(ss_config_get config statistics_enabled 1)"
	ss_statistics_snapshot_interval_s="$(ss_config_get config statistics_snapshot_interval_s 60)"
	ss_statistics_retention_hours="$(ss_config_get config statistics_retention_hours 168)"

	ss_validate_config
}
