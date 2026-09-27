#!/bin/sh
# shellcheck shell=sh

ss_case_utils() (
	set -eu
	PKG_NAME='safeshield-test'
	export PKG_NAME
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/utils.sh"

	command_exists sh
	! command_exists safeshield-command-that-does-not-exist
	ss_spec_assert_eq "$(ss_mask_secret '')" ''
	ss_spec_assert_eq "$(ss_mask_secret '12345678')" '********'
	ss_spec_assert_eq "$(ss_mask_secret 'abcd1234wxyz')" 'abcd****wxyz'
	is_valid_integer 0
	is_valid_integer 42
	for value in '' -1 1.5 12x; do
		! is_valid_integer "$value"
	done
	is_greater_equal 2.90 2.90
	is_greater_equal 2.91 2.90
	! is_greater_equal 2.79 2.80
)

ss_case_config_validation() (
	set -eu
	PKG_NAME='safeshield-test'
	export PKG_NAME
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/utils.sh"

	WARNINGS=''
	CONFIG_GET_VALUE=''
	log_warn() { :; }
	ss_status_add_warning() {
		WARNINGS="${WARNINGS}${WARNINGS:+ }$1"
	}
	config_get() {
		eval "$1='${CONFIG_GET_VALUE}'"
	}
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/config.sh"

	CONFIG_GET_VALUE='configured'
	ss_spec_assert_eq "$(ss_config_get config enabled default)" 'configured'
	CONFIG_GET_VALUE=''
	ss_spec_assert_eq "$(ss_config_get config enabled default)" 'default'

	ss_download_timeout='invalid'
	ss_download_retry='-1'
	ss_max_blocklist_file_size_kb='1.5'
	ss_min_valid_line_count=''
	ss_pause_timeout='invalid'
	ss_boot_start_delay_s='-5'
	ss_statistics_snapshot_interval_s='9'
	ss_statistics_retention_hours='169'
	ss_compress_blocklist='2'
	ss_initial_dnsmasq_restart='yes'
	ss_dnsmasq_sanity_check='no'
	ss_apply_local_overrides='2'
	ss_statistics_enabled='off'
	WARNINGS=''
	ss_validate_config

	ss_spec_assert_eq "$ss_download_timeout" '10'
	ss_spec_assert_eq "$ss_download_retry" '3'
	ss_spec_assert_eq "$ss_max_blocklist_file_size_kb" '30000'
	ss_spec_assert_eq "$ss_min_valid_line_count" '3000'
	ss_spec_assert_eq "$ss_pause_timeout" '20'
	ss_spec_assert_eq "$ss_boot_start_delay_s" '30'
	ss_spec_assert_eq "$ss_statistics_snapshot_interval_s" '60'
	ss_spec_assert_eq "$ss_statistics_retention_hours" '168'
	ss_spec_assert_eq "$ss_compress_blocklist" '0'
	ss_spec_assert_eq "$ss_initial_dnsmasq_restart" '0'
	ss_spec_assert_eq "$ss_dnsmasq_sanity_check" '1'
	ss_spec_assert_eq "$ss_apply_local_overrides" '1'
	ss_spec_assert_eq "$ss_statistics_enabled" '1'

	for code in \
		invalid_download_timeout \
		invalid_download_retry \
		invalid_max_blocklist_file_size_kb \
		invalid_min_valid_line_count \
		invalid_pause_timeout \
		invalid_boot_start_delay_s \
		invalid_statistics_snapshot_interval_s \
		invalid_statistics_retention_hours \
		invalid_compress_blocklist \
		invalid_initial_dnsmasq_restart \
		invalid_dnsmasq_sanity_check \
		invalid_apply_local_overrides \
		invalid_statistics_enabled; do
		case " $WARNINGS " in
			*" $code "*) ;;
			*) return 1 ;;
		esac
	done

	ss_download_timeout='1'
	ss_download_retry='0'
	ss_max_blocklist_file_size_kb='1'
	ss_min_valid_line_count='0'
	ss_pause_timeout='0'
	ss_boot_start_delay_s='0'
	ss_statistics_snapshot_interval_s='10'
	ss_statistics_retention_hours='168'
	ss_compress_blocklist='1'
	ss_initial_dnsmasq_restart='1'
	ss_dnsmasq_sanity_check='0'
	ss_apply_local_overrides='0'
	ss_statistics_enabled='0'
	WARNINGS=''
	ss_validate_config
	[ -z "$WARNINGS" ]
	ss_spec_assert_eq "$ss_statistics_snapshot_interval_s" '10'
	ss_spec_assert_eq "$ss_statistics_retention_hours" '168'
)

ss_case_dnsmasq_version() (
	set -eu
	TMP_DIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
	PKG_NAME='safeshield'
	export PKG_NAME
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/utils.sh"
	DNSMASQ_FEATURE_HEALTH=''
	ss_status_set() {
		[ "$1" = 'health_dnsmasq_features' ] && DNSMASQ_FEATURE_HEALTH="$2"
		return 0
	}
	log_error() { :; }
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/dns.sh"
	ss_spec_assert_file_not_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/dns.sh" 'smartsafehub'

	make_dnsmasq() {
		version="$1"
		feature_rc="${2:-0}"
		cat >"$TMP_DIR/dnsmasq" <<SCRIPT
#!/bin/sh
case "\${1:-}" in
	--version)
		printf '%s\n' 'Dnsmasq version ${version} Copyright (c) 2000-2026 Simon Kelley'
		exit 0
		;;
	--test)
		exit ${feature_rc}
		;;
esac
exit 0
SCRIPT
		chmod +x "$TMP_DIR/dnsmasq"
	}

	PATH="$TMP_DIR:$PATH"
	export PATH
	make_dnsmasq '2.93'
	ss_spec_assert_eq "$(ss_dnsmasq_version)" '2.93'
	ss_require_supported_dnsmasq
	make_dnsmasq '2.94'
	ss_require_supported_dnsmasq
	make_dnsmasq '2.93rc1'
	ss_spec_assert_eq "$(ss_dnsmasq_version)" '2.93'
	ss_require_supported_dnsmasq
	make_dnsmasq '2.92'
	! ss_require_supported_dnsmasq
	ss_spec_assert_eq "$(ss_dnsmasq_check_error)" 'dnsmasq_version_unsupported'
	make_dnsmasq '2.93' 1
	ss_require_supported_dnsmasq
	ss_spec_assert_eq "$(ss_dnsmasq_check_error)" ''
	ss_spec_assert_eq "$DNSMASQ_FEATURE_HEALTH" '0'
	cat >"$TMP_DIR/dnsmasq" <<'SCRIPT'
#!/bin/sh
printf '%s\n' 'unexpected version output'
SCRIPT
	chmod +x "$TMP_DIR/dnsmasq"
	! ss_require_supported_dnsmasq
	ss_spec_assert_eq "$(ss_dnsmasq_check_error)" 'dnsmasq_version_unknown'
	rm -f "$TMP_DIR/dnsmasq"
	ORIGINAL_PATH="$PATH"
	PATH="$TMP_DIR"
	! ss_require_supported_dnsmasq
	PATH="$ORIGINAL_PATH"
	ss_spec_assert_eq "$(ss_dnsmasq_check_error)" 'dnsmasq_binary_not_found'
)

ss_case_identity() (
	set -eu
	TMP_DIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
	SS_IDENTITY_DIR="$TMP_DIR/identity"
	SS_IDENTITY_FILE="$SS_IDENTITY_DIR/identity.env"
	export SS_IDENTITY_DIR SS_IDENTITY_FILE
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/identity.sh"

	ss_spec_assert_eq "$(ss_identity_normalize_mac 'MAC=AA:BB:CC:DD:EE:FF')" 'aa:bb:cc:dd:ee:ff'
	ss_identity_valid_mac 'aa:bb:cc:dd:ee:ff'
	for mac in '' '00:00:00:00:00:00' 'ff:ff:ff:ff:ff:ff' 'aa:bb:cc:dd:ee'; do
		! ss_identity_valid_mac "$mac"
	done
	ss_spec_assert_eq "$(ss_identity_hex_to_mac 'AABBCCDDEEFF')" 'aa:bb:cc:dd:ee:ff'
	ss_spec_assert_eq "$(ss_identity_profile_code 'iptime,ax3000sm')" 'iptime_ax3000sm'
	ss_spec_assert_eq "$(ss_identity_profile_code 'glinet,gl-mt300n-v2')" 'gl_mt300n_v2'
	ss_spec_assert_eq "$(ss_identity_profile_code 'xiaomi,mi-router-ax3000t')" 'xiaomi_mi_router_ax3000t'
	ss_spec_assert_eq "$(ss_identity_profile_code 'smartsafehub,router')" 'smartsafehub'
	ss_spec_assert_eq "$(ss_identity_device_code_from_board 'iptime,ax3000sm')" 'iptime-ax3000sm'
	ss_spec_assert_eq "$(ss_identity_device_code_from_board 'glinet,gl-mt300n-v2')" 'gl-mt300n-v2'
	ss_spec_assert_eq "$(ss_identity_device_code_from_board 'xiaomi,mi-router-ax3000t')" 'xiaomi-ax3000t'
	ss_spec_assert_eq "$(ss_identity_device_code_from_board 'xiaomi,mi-router-ax3000t-ubootmod')" 'xiaomi-ax3000t'
	! ss_identity_device_code_from_board 'vendor,unsupported-router'
	ss_identity_valid_device_code 'xiaomi-ax3000t'
	! ss_identity_valid_device_code 'Xiaomi AX3000T'

	SS_SMARTSAFEHUB_FIRMWARE_JSON="$TMP_DIR/firmware.json"
	export SS_SMARTSAFEHUB_FIRMWARE_JSON
	printf '%s\n' '{"device_code":"xiaomi-ax3000t"}' >"$SS_SMARTSAFEHUB_FIRMWARE_JSON"
	MOCK_DEVICE_CODE='xiaomi-ax3000t'
	jsonfilter() { printf '%s\n' "$MOCK_DEVICE_CODE"; }
	ss_identity_board_name() { printf '%s' 'iptime,ax3000sm'; }
	ss_identity_refresh_device_code
	ss_spec_assert_eq "$SS_DEVICE_CODE" 'xiaomi-ax3000t'
	ss_spec_assert_eq "$SS_DEVICE_CODE_SOURCE" 'smartsafehub_firmware'

	MOCK_DEVICE_CODE='invalid device code'
	ss_identity_refresh_device_code
	ss_spec_assert_eq "$SS_DEVICE_CODE" 'iptime-ax3000sm'
	ss_spec_assert_eq "$SS_DEVICE_CODE_SOURCE" 'board'

	rm -f "$SS_SMARTSAFEHUB_FIRMWARE_JSON"
	ss_identity_board_name() { printf '%s' 'vendor,unsupported-router'; }
	ss_identity_refresh_device_code
	ss_spec_assert_eq "$SS_DEVICE_CODE" ''
	ss_spec_assert_eq "$SS_DEVICE_CODE_SOURCE" 'unknown'

	ss_identity_board_name() { printf '%s' 'iptime,ax3000sm'; }
	ss_identity_try_mtd_factory_mac() { printf '%s' 'aa:bb:cc:dd:ee:ff|mtd:Factory:0x4:mac'; }
	ss_identity_detect_primary_mac() { return 1; }
	ss_identity_compute_physical 'ipTIME AX3000SM' 'aarch64'
	ss_spec_assert_eq "$SS_IDENTITY_PROVIDER" 'factory_mac'
	ss_spec_assert_eq "$SS_IDENTITY_SOURCE" 'mtd:Factory:0x4:mac'
	ss_spec_assert_eq "$SS_IDENTITY_STRENGTH" 'hardware_soft'
	ss_spec_assert_eq "$SS_IDENTITY_PROFILE" 'iptime_ax3000sm'
	ss_identity_valid_sha256 "$SS_IDENTITY_VALUE_SHA256"
	ss_identity_valid_sha256 "$SS_PHYSICAL_FINGERPRINT"

	SS_INSTALLATION_ID='11111111-2222-3333-4444-555555555555'
	SS_INSTALLATION_SECRET='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
	SS_IDENTITY_CREATED_AT='1788090000'
	SS_IDENTITY_UPDATED_AT='1788090001'
	ss_identity_write_env
	ss_spec_assert_nonempty "$SS_IDENTITY_FILE"
	identity_mode="$(LC_ALL=C ls -ld "$SS_IDENTITY_FILE" | awk '{ print substr($1, 2, 9) }')"
	ss_spec_assert_eq "$identity_mode" 'rw-------'
	expected_fingerprint="$SS_PHYSICAL_FINGERPRINT"
	SS_PHYSICAL_FINGERPRINT=''
	SS_IDENTITY_PROVIDER=''
	SS_IDENTITY_SOURCE=''
	SS_IDENTITY_STRENGTH=''
	SS_IDENTITY_PROFILE=''
	SS_INSTALLATION_ID=''
	ss_identity_load
	ss_spec_assert_eq "$SS_PHYSICAL_FINGERPRINT" "$expected_fingerprint"
	ss_spec_assert_eq "$SS_IDENTITY_PROVIDER" 'factory_mac'
	ss_spec_assert_eq "$SS_INSTALLATION_ID" '11111111-2222-3333-4444-555555555555'

	SYNCED=0
	STATUS_SYNCED=0
	ss_identity_sync_uci() { SYNCED=1; }
	ss_identity_status_set() { STATUS_SYNCED=1; }
	ss_identity_create() { return 97; }
	ss_identity_ensure 'ipTIME AX3000SM' 'aarch64'
	ss_spec_assert_eq "$SYNCED" '1'
	ss_spec_assert_eq "$STATUS_SYNCED" '1'
)

ss_case_resolve_payload() (
	set -eu
	TMP_DIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	ss_detect_device_model() { printf '%s' 'Test Router'; }
	ss_detect_device_vendor() { printf '%s' 'TestVendor'; }
	ss_detect_device_arch() { printf '%s' 'test_arch'; }
	ss_detect_device_memory_mb() { printf '%s' '128'; }
	SS_PHYSICAL_FINGERPRINT='test-fingerprint'
	SS_FINGERPRINT_VERSION='1'
	SS_IDENTITY_PROVIDER='factory_mac'
	SS_IDENTITY_SOURCE='test-source'
	SS_IDENTITY_STRENGTH='hardware_soft'
	SS_IDENTITY_PROFILE='test-profile'
	SS_DEVICE_CODE='test-router'
	SS_DEVICE_CODE_SOURCE='board'
	SS_INSTALLATION_ID='test-installation'
	ss_identity_ensure() { return 0; }
	is_valid_integer() {
		case "$1" in
			'' | *[!0-9]*) return 1 ;;
			*) return 0 ;;
		esac
	}
	ss_status_set() { :; }
	ss_license_key='test-license'
	SS_VERSION_FILE="$TMP_DIR/version"
	export SS_VERSION_FILE
	printf '%s\n' '0.3.18-r1' >"$SS_VERSION_FILE"
	payload="$TMP_DIR/resolve-request.json"
	ss_write_resolve_payload "$payload"
	ss_spec_assert_file_contains "$payload" '    "safeshield_version": "0.3.18-r1"'
	! grep -Eq '^  "safeshield_version"' "$payload"
	ss_spec_assert_file_contains "$payload" '"license_key": "test-license"'
	ss_spec_assert_file_contains "$payload" '"physical_fingerprint": "test-fingerprint"'
	ss_spec_assert_file_contains "$payload" '"fingerprint_version": 1'
	ss_spec_assert_file_contains "$payload" '"identity_provider": "factory_mac"'
	ss_spec_assert_file_contains "$payload" '"identity_source": "test-source"'
	ss_spec_assert_file_contains "$payload" '"identity_strength": "hardware_soft"'
	ss_spec_assert_file_contains "$payload" '"identity_profile": "test-profile"'
	ss_spec_assert_file_contains "$payload" '"device_code": "test-router"'
	ss_spec_assert_file_contains "$payload" '"device_code_source": "board"'
	ss_spec_assert_file_contains "$payload" '"installation_id": "test-installation"'
	ss_spec_assert_file_contains "$payload" '"vendor": "TestVendor"'
	ss_spec_assert_file_contains "$payload" '"model": "Test Router"'
	ss_spec_assert_file_contains "$payload" '"arch": "test_arch"'
	ss_spec_assert_file_contains "$payload" '"memory_mb": 128'

	ss_detect_device_memory_mb() { printf '%s' 'invalid-memory'; }
	invalid_memory_payload="$TMP_DIR/resolve-request-invalid-memory.json"
	ss_write_resolve_payload "$invalid_memory_payload"
	ss_spec_assert_file_contains "$invalid_memory_payload" '"memory_mb": 0'

	SS_VERSION_FILE="$TMP_DIR/missing-version"
	export SS_VERSION_FILE
	fallback_payload="$TMP_DIR/resolve-request-fallback.json"
	ss_write_resolve_payload "$fallback_payload"
	ss_spec_assert_file_contains "$fallback_payload" '    "safeshield_version": "unknown"'
	! grep -Eq '^  "safeshield_version"' "$fallback_payload"
)

ss_case_rpcd_contract() (
	set -eu
	ENTRY="$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield.uc"
	ACL="$SS_SPEC_ROOT/files/usr/share/rpcd/acl.d/safeshield.json"
	MAKEFILE="$SS_SPEC_ROOT/Makefile"
	STATISTICS_MODULE="$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield/statistics.uc"
	[ -f "$ENTRY" ]
	[ -f "$ACL" ]
	ss_spec_assert_file_contains "$ENTRY" "unshift(REQUIRE_SEARCH_PATH, '/usr/share/rpcd/ucode/safeshield/*.uc');"
	for module in status config refresh rules license statistics; do
		ss_spec_assert_file_contains "$ENTRY" "let $module = require('$module');"
	done
	for method in status config statistics config_update set_enabled refresh rules_list rule_add rule_delete license_get license_update; do
		ss_spec_assert_file_contains "$ENTRY" "        $method: {"
		ss_spec_assert_file_contains "$ACL" "\"$method\""
	done
	ss_spec_assert_file_contains "$MAKEFILE" './files/usr/share/rpcd/ucode/safeshield/*.uc'
	ss_spec_assert_file_contains "$MAKEFILE" './files/usr/share/rpcd/acl.d/safeshield.json'
	ss_spec_assert_file_contains "$STATISTICS_MODULE" 'effective_snapshot_interval_s: to_int(data.snapshot_interval_s, snapshot_interval_s)'
)

ss_case_status_state() (
	set -eu
	TMP_DIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
	RUNNING_STATUS_FILE="$TMP_DIR/status.json"
	SS_DNSMASQ_DIR="$TMP_DIR/dnsmasq.d"
	SS_BLOCKLIST_FILE="$SS_DNSMASQ_DIR/safeshield.blocklist"
	SS_PREV_BLOCKLIST_GZ="$TMP_DIR/previous.gz"
	export RUNNING_STATUS_FILE SS_DNSMASQ_DIR SS_BLOCKLIST_FILE SS_PREV_BLOCKLIST_GZ
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/status.sh"
	CALLS="$TMP_DIR/calls"
	: >"$CALLS"
	record() { printf '%s\t%s\t%s\n' "$1" "${2:-}" "${3:-}" >>"$CALLS"; }
	ss_status_set() { record set "$1" "$2"; }
	ss_status_add_error() { record error "$1"; }
	ss_status_apply() {
		record apply "$1" "${2:-}"
		return 0
	}
	ss_now() { printf '%s' '1000'; }
	is_valid_integer() {
		case "$1" in '' | *[!0-9]*) return 1 ;; esac
		[ "$1" -ge 0 ] 2>/dev/null
	}
	ss_status_mark_failure 'artifact_download_failed'
	grep -F "$(printf 'set\tstatus\terror')" "$CALLS" >/dev/null
	grep -F "$(printf 'set\tlast_failure\t1000')" "$CALLS" >/dev/null
	grep -F "$(printf 'set\tlast_result\terror')" "$CALLS" >/dev/null
	grep -F "$(printf 'set\tlast_error_code\tartifact_download_failed')" "$CALLS" >/dev/null
	grep -F "$(printf 'error\tartifact_download_failed')" "$CALLS" >/dev/null
	: >"$CALLS"
	ss_status_mark_success 300
	grep -F "$(printf 'apply\tclear_messages')" "$CALLS" >/dev/null
	grep -F "$(printf 'set\tstatus\tready')" "$CALLS" >/dev/null
	grep -F "$(printf 'set\tstage\tdone')" "$CALLS" >/dev/null
	grep -F "$(printf 'set\tlast_success\t1000')" "$CALLS" >/dev/null
	grep -F "$(printf 'set\tnext_refresh_at\t1300')" "$CALLS" >/dev/null
	: >"$CALLS"
	ss_status_mark_success invalid
	! grep -F "$(printf 'set\tnext_refresh_at')" "$CALLS" >/dev/null
	: >"$CALLS"
	ss_status_reset_health_fields
	for key in health_dnsmasq_binary health_dns_runtime health_artifact_download dnsmasq_min_version; do
		grep -F "$(printf 'set\t%s\t' "$key")" "$CALLS" >/dev/null
	done
	: >"$CALLS"
	ss_status_reset_blocklist_fields
	for key in blocklist_installed blocklist_file_size_kb blocklist_verification_ok blocklist_backup_available; do
		grep -F "$(printf 'set\t%s\t' "$key")" "$CALLS" >/dev/null
	done
	: >"$CALLS"
	ss_status_reset_artifact_fields
	for key in license_plan artifact_tier artifact_source_count artifact_allow_source_count; do
		grep -F "$(printf 'set\t%s\t' "$key")" "$CALLS" >/dev/null
	done
	mkdir -p "$SS_DNSMASQ_DIR"
	printf '%s\n' 'address=/ads.example/#' >"$TMP_DIR/new.blocklist"
	ss_sync_path() { :; }
	ss_install_blocklist_atomic "$TMP_DIR/new.blocklist" "$SS_BLOCKLIST_FILE"
	ss_spec_assert_eq "$(cat "$SS_BLOCKLIST_FILE")" 'address=/ads.example/#'
	command_exists() { command -v "$1" >/dev/null 2>&1; }
	ss_export_existing_blocklist
	ss_spec_assert_nonempty "$SS_PREV_BLOCKLIST_GZ"
	rm -f "$SS_BLOCKLIST_FILE"
	ss_restore_previous_blocklist
	ss_spec_assert_eq "$(cat "$SS_BLOCKLIST_FILE")" 'address=/ads.example/#'
)

ss_case_status_version() (
	set -eu
	make_version="$(sed -n 's/^PKG_VERSION:=//p' "$SS_SPEC_ROOT/Makefile")"
	make_release="$(sed -n 's/^PKG_RELEASE:=//p' "$SS_SPEC_ROOT/Makefile")"
	init_version="$(sed -n "s/^readonly PKG_VERSION='\([^']*\)'/\1/p" "$SS_SPEC_ROOT/files/etc/init.d/safeshield")"
	[ -n "$make_version" ]
	[ -n "$make_release" ]
	[ -n "$init_version" ]
	ss_spec_assert_eq "$init_version" "${make_version}-r${make_release}"
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/etc/init.d/safeshield" "printf '%s\\n' \"\$PKG_VERSION\""
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/Makefile" "echo '\$(PKG_VERSION)-r\$(PKG_RELEASE)' > \$(1)/usr/lib/safeshield/version"
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield/core.uc" 'fs.readfile(`/usr/lib/${PKG_NAME}/version`)'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield/status.uc" 'version: PKG_VERSION,'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/core.sh" 'safeshield_upgrade_required'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/core.sh" 'failure_code="$(ss_resolve_error_code)"'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/core.sh" 'failure_code="$(ss_artifact_download_error_code)"'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/core.sh" 'if [ "$failure_code" != "safeshield_upgrade_required" ]; then'
)
