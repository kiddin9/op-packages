#!/bin/sh
# shellcheck shell=sh

ss_case_device_api_contract() (
	set -eu
	BLOCKLIST="$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	STATISTICS="$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics.sh"

	ss_spec_assert_file_not_contains "$BLOCKLIST" '/api/v1/devices/bootstrap'
	ss_spec_assert_file_contains "$BLOCKLIST" '/api/v1/devices/sync'
	ss_spec_assert_file_contains "$STATISTICS" '/api/v1/devices/sync'
	ss_spec_assert_file_contains "$BLOCKLIST" 'Authorization: ${authorization}'
	ss_spec_assert_file_contains "$BLOCKLIST" 'Device ${device_credential}'
	ss_spec_assert_file_not_contains "$BLOCKLIST" "url='https://www.smartsafehub.com/api/v1/licenses/resolve'"
	ss_spec_assert_file_not_contains "$STATISTICS" "resolve_url='https://www.smartsafehub.com/api/v1/licenses/resolve'"
	ss_spec_assert_file_not_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/config.sh" 'ss_license_key'
	ss_spec_assert_file_not_contains "$SS_SPEC_ROOT/files/usr/libexec/safeshield-statistics-uploader" 'ss_license_key'
	ss_spec_assert_file_not_contains "$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield.uc" 'license_update'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield/status.uc" 'entitlement: {'
	ss_spec_assert_file_not_contains "$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield/status.uc" 'license: {'
	ss_spec_assert_file_not_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/status.sh" 'license_plan'
	ss_spec_assert_file_not_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/status.sh" 'license_status'
)

ss_case_device_registration_pending() (
	set -eu
	TMP_DIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
	SS_TMP_DIR="$TMP_DIR/tmp"
	SS_API_PAYLOAD="$SS_TMP_DIR/resolve-request.json"
	SS_API_RESPONSE="$SS_TMP_DIR/resolve-response.json"
	ss_download_retry=1
	ss_download_timeout=10
	mkdir -p "$SS_TMP_DIR"

	ss_should_stop() { return 1; }
	ss_status_set() { printf '%s=%s\n' "$1" "$2" >>"$TMP_DIR/status"; }
	ss_status_add_error() { :; }
	log_info() { :; }
	log_warn() { :; }
	log_error() { :; }
	log_ok() { :; }
	command_exists() { return 1; }

	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	ss_write_resolve_payload() { printf '{}\n' >"$1"; }
	ss_device_credential_token() { return 1; }

	if ss_resolve_artifact; then
		return 1
	fi

	ss_spec_assert_eq "$SS_RESOLVE_ERROR_CODE" 'device_registration_pending'
	ss_spec_assert_file_contains "$TMP_DIR/status" 'device_registration_status=pending'
	ss_spec_assert_file_contains "$TMP_DIR/status" 'health_api_resolve=0'
)
