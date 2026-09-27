#!/bin/sh
# shellcheck shell=sh

ss_case_blocklist_format() (
	set -eu
	TMP_DIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
	SS_TMP_DIR="$TMP_DIR/tmp"
	SS_DNSMASQ_DIR="$TMP_DIR/dnsmasq.d"
	SS_BLOCKLIST_FILE="$SS_DNSMASQ_DIR/safeshield.blocklist"
	ss_min_valid_line_count=0
	ss_max_blocklist_file_size_kb=1024
	ss_dnsmasq_sanity_check=0
	ss_valid_line_count=0
	mkdir -p "$SS_TMP_DIR" "$SS_DNSMASQ_DIR"
	ss_should_stop() { return 1; }
	ss_status_set() { :; }
	ss_status_add_error() { :; }
	log_info() { :; }
	log_error() { :; }
	log_warn() { :; }
	ss_sync_path() { :; }
	ss_blocklist_tmp_path() { printf '%s/.safeshield.blocklist.tmp.%s\n' "$SS_DNSMASQ_DIR" "$$"; }
	ss_install_blocklist_atomic() { mv -f "$1" "$2"; }
	DNSMASQ_PATCHED=1
	ss_dnsmasq_safeshield_block_supported() { [ "$DNSMASQ_PATCHED" = '1' ]; }
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	ss_spec_assert_file_not_contains "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh" 'smartsafehub-block='

	normalized="$(printf '%s\n' \
		'address=/ads.example/#' \
		'address=/legacy-v4.example/0.0.0.0' \
		'address=/legacy-v6.example/::' \
		'safeshield-block=/native.example/' | ss_normalize_domains)"
	expected='ads.example
legacy-v4.example
legacy-v6.example
native.example'
	ss_spec_assert_eq "$normalized" "$expected"

	cat >"$SS_TMP_DIR/api.0.block.txt" <<'DATA'
ads.example
tracker.example
ads.example
DATA
	cat >"$SS_TMP_DIR/api.1.block.txt" <<'DATA'
phishing.example
tracker.example
DATA
	cat >"$SS_TMP_DIR/api.2.allow.txt" <<'DATA'
tracker.example
remote-allow.example
DATA
	cat >"$SS_TMP_DIR/local.block.txt" <<'DATA'
remote-allow.example
local-block.example
DATA
	cat >"$SS_TMP_DIR/local.allow.txt" <<'DATA'
local-block.example
DATA
	ss_merge_lists
	expected='safeshield-block=/ads.example/
safeshield-block=/phishing.example/
safeshield-block=/remote-allow.example/
server=/local-block.example/#
server=/tracker.example/#'
	ss_spec_assert_eq "$(cat "$SS_BLOCKLIST_FILE")" "$expected"
	ss_spec_assert_eq "$(grep -c . "$SS_BLOCKLIST_FILE")" '5'
	check_blocklist_rule_present 'ads.example'
	ss_spec_assert_eq "$(find_test_domains 1)" 'ads.example'

	rm -f "$SS_TMP_DIR"/api.*.block.txt "$SS_TMP_DIR"/api.*.allow.txt
	printf '%s\n' 'example.com' >"$SS_TMP_DIR/api.0.block.txt"
	printf '%s\n' 'good.example.com' >"$SS_TMP_DIR/api.1.allow.txt"
	printf '%s\n' 'blocked.good.example.com' >"$SS_TMP_DIR/local.block.txt"
	printf '%s\n' 'allowed.blocked.good.example.com' >"$SS_TMP_DIR/local.allow.txt"
	ss_merge_lists
	expected='safeshield-block=/blocked.good.example.com/
safeshield-block=/example.com/
server=/allowed.blocked.good.example.com/#
server=/good.example.com/#'
	ss_spec_assert_eq "$(cat "$SS_BLOCKLIST_FILE")" "$expected"

	cat >"$SS_BLOCKLIST_FILE" <<'DATA'
address=/migrate-one.example/#
address=/migrate-two.example/0.0.0.0
server=/allowed.example/#
DATA
	ss_reconcile_blocklist_file_for_dnsmasq "$SS_BLOCKLIST_FILE"
	expected='safeshield-block=/migrate-one.example/
safeshield-block=/migrate-two.example/
server=/allowed.example/#'
	ss_spec_assert_eq "$(cat "$SS_BLOCKLIST_FILE")" "$expected"

	DNSMASQ_PATCHED=0
	ss_reconcile_blocklist_file_for_dnsmasq "$SS_BLOCKLIST_FILE"
	expected='address=/migrate-one.example/#
address=/migrate-two.example/#
server=/allowed.example/#'
	ss_spec_assert_eq "$(cat "$SS_BLOCKLIST_FILE")" "$expected"

	rm -f \
		"$SS_TMP_DIR"/api.*.block.txt \
		"$SS_TMP_DIR"/api.*.allow.txt \
		"$SS_TMP_DIR"/local.block.txt \
		"$SS_TMP_DIR"/local.allow.txt
	printf '%s\n' 'fallback.example' >"$SS_TMP_DIR/api.0.block.txt"
	ss_merge_lists
	ss_spec_assert_eq "$(cat "$SS_BLOCKLIST_FILE")" 'address=/fallback.example/#'
	DNSMASQ_PATCHED=1

	cat >"$SS_BLOCKLIST_FILE" <<'DATA'
address=/legacy.example/0.0.0.0
address=/legacy.example/::
DATA
	check_blocklist_rule_present 'legacy.example'

	cat >"$SS_BLOCKLIST_FILE" <<'DATA'
address=/sample-one.example/#
address=/sample-two.example/#
address=/sample-three.example/#
DATA
	sampled="$(find_test_domains 2)"
	expected_sample='sample-one.example
sample-two.example'
	ss_spec_assert_eq "$sampled" "$expected_sample"
	RULE_CHECK_COUNT=0
	DNS_CHECK_COUNT=0
	check_blocklist_rule_present() {
		RULE_CHECK_COUNT=$((RULE_CHECK_COUNT + 1))
		return 1
	}
	check_domain_blocked() {
		DNS_CHECK_COUNT=$((DNS_CHECK_COUNT + 1))
		return 0
	}
	check_blocklist_applied_multi_with_stats 2 2
	ss_spec_assert_eq "$RULE_CHECK_COUNT" '0'
	ss_spec_assert_eq "$DNS_CHECK_COUNT" '2'
)

ss_case_multi_artifact() (
	set -eu
	TMP_DIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
	SS_TMP_DIR="$TMP_DIR/tmp"
	SS_API_PAYLOAD="$SS_TMP_DIR/resolve-request.json"
	SS_API_RESPONSE="$SS_TMP_DIR/resolve-response.json"
	SS_RESOLVED_SOURCES="$SS_TMP_DIR/resolved-sources.tsv"
	SS_ARTIFACT_CACHE_STATE="$SS_TMP_DIR/artifact-sources.state"
	SS_MAX_ARTIFACT_SOURCES=16
	ss_license_key='test-license'
	ss_download_retry=1
	ss_download_timeout=10
	ss_max_blocklist_file_size_kb=1024
	mkdir -p "$SS_TMP_DIR"
	ss_should_stop() { return 1; }
	ss_status_set() { :; }
	ss_status_add_error() { :; }
	log_info() { :; }
	log_error() { :; }
	log_ok() { :; }
	command_exists() { command -v "$1" >/dev/null 2>&1; }
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	ss_write_resolve_payload() { printf '{}\n' >"$1"; }
	ss_http_post_json() { printf '{}\n' >"$3"; }
	ss_json_get_file() {
		case "$2" in
			'@.artifact.sources[0].download_url') printf '%s\n' 'https://example.invalid/hagezi.txt' ;;
			'@.artifact.sources[0].action') printf '%s\n' 'block' ;;
			'@.artifact.sources[0].id') printf '%s\n' 'hagezi-pro' ;;
			'@.artifact.sources[0].sha256') printf '%s\n' "$HAGEZI_SHA" ;;
			'@.artifact.sources[1].download_url') printf '%s\n' 'https://example.invalid/smartsafehub-block.txt' ;;
			'@.artifact.sources[1].action') printf '%s\n' 'block' ;;
			'@.artifact.sources[1].id') printf '%s\n' 'smartsafehub-pro' ;;
			'@.artifact.sources[1].sha256') printf '%s\n' "$SMART_BLOCK_SHA" ;;
			'@.artifact.sources[2].download_url') printf '%s\n' 'https://example.invalid/smartsafehub-allow.txt' ;;
			'@.artifact.sources[2].action') printf '%s\n' 'allow' ;;
			'@.artifact.sources[2].id') printf '%s\n' 'smartsafehub-allow' ;;
			'@.artifact.sources[2].sha256') printf '%s\n' "$SMART_ALLOW_SHA" ;;
			'@.artifact.sources[3].download_url' | '@.artifact.sources[16].download_url' | '@.artifact.sha256') : ;;
			'@.artifact.tier') printf '%s\n' 'pro' ;;
			'@.artifact.version') printf '%s\n' '20260830T120000Z' ;;
			'@.artifact.unique_domains' | '@.artifact.rules') printf '%s\n' '4' ;;
			'@.license.plan') printf '%s\n' 'pro' ;;
			'@.license.status') printf '%s\n' 'active' ;;
			'@.device.profile') printf '%s\n' 'test-profile' ;;
			*) : ;;
		esac
	}
	cat >"$TMP_DIR/hagezi.txt" <<'DATA'
address=/ads.example/#
address=/shared.example/#
DATA
	cat >"$TMP_DIR/smartsafehub-block.txt" <<'DATA'
phishing.example
shared.example
DATA
	printf '%s\n' 'shared.example' >"$TMP_DIR/smartsafehub-allow.txt"
	HAGEZI_SHA="$(sha256sum "$TMP_DIR/hagezi.txt" | awk '{print $1}')"
	SMART_BLOCK_SHA="$(sha256sum "$TMP_DIR/smartsafehub-block.txt" | awk '{print $1}')"
	SMART_ALLOW_SHA="$(sha256sum "$TMP_DIR/smartsafehub-allow.txt" | awk '{print $1}')"
	export HAGEZI_SHA SMART_BLOCK_SHA SMART_ALLOW_SHA
	ss_resolve_artifact
	expected_sources="0|block|hagezi-pro|https://example.invalid/hagezi.txt|$HAGEZI_SHA
1|block|smartsafehub-pro|https://example.invalid/smartsafehub-block.txt|$SMART_BLOCK_SHA
2|allow|smartsafehub-allow|https://example.invalid/smartsafehub-allow.txt|$SMART_ALLOW_SHA"
	ss_spec_assert_eq "$(cat "$SS_RESOLVED_SOURCES")" "$expected_sources"
	ss_http_get_file() {
		case "$1" in
			'https://example.invalid/hagezi.txt') cp "$TMP_DIR/hagezi.txt" "$2" ;;
			'https://example.invalid/smartsafehub-block.txt') cp "$TMP_DIR/smartsafehub-block.txt" "$2" ;;
			'https://example.invalid/smartsafehub-allow.txt') cp "$TMP_DIR/smartsafehub-allow.txt" "$2" ;;
			*) return 1 ;;
		esac
	}
	ss_download_api_artifacts
	ss_cached_api_sources_available
	ss_spec_assert_eq "$(cat "$SS_TMP_DIR/api.0.block.txt")" 'ads.example
shared.example'
	ss_spec_assert_eq "$(cat "$SS_TMP_DIR/api.1.block.txt")" 'phishing.example
shared.example'
	ss_spec_assert_eq "$(cat "$SS_TMP_DIR/api.2.allow.txt")" 'shared.example'
	ss_json_get_file() {
		case "$2" in
			'@.artifact.sources[0].download_url') : ;;
			'@.artifact.download_url') printf '%s\n' 'https://example.invalid/legacy.txt' ;;
			'@.artifact.sha256') printf '%s\n' 'legacy-sha' ;;
			*) : ;;
		esac
	}
	ss_resolve_artifact_sources "$SS_API_RESPONSE"
	ss_spec_assert_eq "$(cat "$SS_RESOLVED_SOURCES")" '0|block|legacy|https://example.invalid/legacy.txt|legacy-sha'
)

ss_case_performance_paths() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	SS_TMP_DIR="$TMP"
	export SS_TMP_DIR
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	cat >"$TMP/api.0.block.txt" <<'EOF_BLOCK_0'
alpha.example
shared.example
EOF_BLOCK_0
	cat >"$TMP/api.1.block.txt" <<'EOF_BLOCK_1'
beta.example
shared.example
EOF_BLOCK_1
	ss_merge_sorted_api_sources block "$TMP/merged-blocks.txt"
	expected='alpha.example
beta.example
shared.example'
	ss_spec_assert_eq "$(cat "$TMP/merged-blocks.txt")" "$expected"
	rm -f "$TMP"/api.*.block.txt
	ss_merge_sorted_api_sources block "$TMP/empty-blocks.txt"
	[ ! -s "$TMP/empty-blocks.txt" ]
	BLOCKLIST="$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	STATISTICS_AGGREGATE="$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics/30-aggregate.awk"
	STATISTICS_OUTPUT="$SS_SPEC_ROOT/files/usr/lib/safeshield/statistics/50-output.awk"
	ss_spec_assert_file_contains "$BLOCKLIST" 'sort -m -u "$@" >"$out"'
	ss_spec_assert_file_contains "$STATISTICS_AGGREGATE" 'delete device_first_bucket[key]'
	ss_spec_assert_file_contains "$STATISTICS_OUTPUT" 'device_first_hour = device_first_bucket[key] + 0'
	ss_spec_assert_file_contains "$STATISTICS_OUTPUT" 'for (bucket = device_first_hour; bucket <= device_last_hour; bucket += 3600)'
)

ss_case_upgrade_required() (
	set -eu
	TMP_DIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
	SS_TMP_DIR="$TMP_DIR/tmp"
	SS_API_PAYLOAD="$SS_TMP_DIR/resolve-request.json"
	SS_API_RESPONSE="$SS_TMP_DIR/resolve-response.json"
	SS_RESOLVED_SOURCES="$SS_TMP_DIR/resolved-sources.tsv"
	SS_ARTIFACT_CACHE_STATE="$SS_TMP_DIR/artifact-sources.state"
	ss_license_key='test-license'
	ss_download_retry=3
	ss_download_timeout=10
	ss_max_blocklist_file_size_kb=1024
	mkdir -p "$SS_TMP_DIR"
	ss_should_stop() { return 1; }
	ss_status_set() { printf '%s=%s\n' "$1" "$2" >>"$TMP_DIR/status"; }
	ss_status_add_error() { :; }
	ss_status_add_warning() { :; }
	log_info() { :; }
	log_error() { :; }
	log_ok() { :; }
	command_exists() { return 1; }
	sleep() { printf 'sleep\n' >>"$TMP_DIR/sleep"; }
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	ss_write_resolve_payload() { printf '{}\n' >"$1"; }

	printf '%s\n' 'HTTP error 426' >"$TMP_DIR/uclient.log"
	ss_spec_assert_eq "$(ss_http_status_from_uclient_log "$TMP_DIR/uclient.log")" '426'

	command_exists() { [ "$1" = 'curl' ]; }
	curl() {
		out=''
		while [ "$#" -gt 0 ]; do
			if [ "$1" = '-o' ]; then
				shift
				out="$1"
			fi
			shift
		done
		[ -z "$out" ] || printf '%s\n' '{"code":"safeshield_upgrade_required"}' >"$out"
		printf '%s' '426'
		return 0
	}
	if ss_http_post_json 'https://example.invalid/resolve' "$SS_API_PAYLOAD" "$SS_API_RESPONSE"; then
		return 1
	fi
	ss_spec_assert_eq "$SS_HTTP_STATUS" '426'
	if ss_http_get_file 'https://example.invalid/artifact' "$SS_TMP_DIR/artifact.raw"; then
		return 1
	fi
	ss_spec_assert_eq "$SS_HTTP_STATUS" '426'

	command_exists() { return 1; }
	RESOLVE_CALLS=0
	ss_http_post_json() {
		RESOLVE_CALLS=$((RESOLVE_CALLS + 1))
		SS_HTTP_STATUS='426'
		return 1
	}
	if ss_resolve_artifact; then
		return 1
	fi
	ss_spec_assert_eq "$RESOLVE_CALLS" '1'
	ss_spec_assert_eq "$SS_RESOLVE_ERROR_CODE" 'safeshield_upgrade_required'
	ss_spec_assert_file_contains "$TMP_DIR/status" 'health_api_resolve=0'
	ss_spec_assert_not_exists "$TMP_DIR/sleep"

	printf '%s\n' '0|block|test-source|https://example.invalid/artifact.txt|' >"$SS_RESOLVED_SOURCES"
	DOWNLOAD_CALLS=0
	ss_http_get_file() {
		DOWNLOAD_CALLS=$((DOWNLOAD_CALLS + 1))
		SS_HTTP_STATUS='426'
		return 1
	}
	if ss_download_api_artifacts; then
		return 1
	fi
	ss_spec_assert_eq "$DOWNLOAD_CALLS" '1'
	ss_spec_assert_eq "$SS_ARTIFACT_DOWNLOAD_ERROR_CODE" 'safeshield_upgrade_required'
	ss_spec_assert_file_contains "$TMP_DIR/status" 'health_artifact_download=0'
	ss_spec_assert_not_exists "$TMP_DIR/sleep"
)

ss_case_artifact_integrity() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	SS_TMP_DIR="$TMP/runtime"
	SS_RESOLVED_SOURCES="$SS_TMP_DIR/resolved-sources.tsv"
	SS_ARTIFACT_CACHE_STATE="$SS_TMP_DIR/artifact-sources.state"
	ss_download_retry=2
	ss_download_timeout=10
	ss_max_blocklist_file_size_kb=1024
	mkdir -p "$SS_TMP_DIR"
	STATUS="$TMP/status"
	: >"$STATUS"
	ss_should_stop() { return 1; }
	ss_status_set() { printf 'set %s %s\n' "$1" "${2:-}" >>"$STATUS"; }
	ss_status_add_error() { printf 'error %s\n' "$1" >>"$STATUS"; }
	ss_status_add_warning() { printf 'warning %s\n' "$1" >>"$STATUS"; }
	log_info() { :; }
	log_error() { :; }
	log_ok() { :; }
	sleep() { :; }
	command_exists() { command -v "$1" >/dev/null 2>&1; }
	# shellcheck disable=SC1091
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"

	printf '%s\n' 'ads.example' 'shared.example' >"$TMP/source0.txt"
	printf '%s\n' 'shared.example' >"$TMP/source1.txt"
	SOURCE0_SHA="$(sha256sum "$TMP/source0.txt" | awk '{print $1}')"
	printf '0|block|source-0|https://example.invalid/source0|%s\n' "$SOURCE0_SHA" >"$SS_RESOLVED_SOURCES"
	printf '%s\n' '1|allow|source-1|https://example.invalid/source1|' >>"$SS_RESOLVED_SOURCES"

	GET_CALLS=0
	ss_http_get_file() {
		GET_CALLS=$((GET_CALLS + 1))
		SS_HTTP_STATUS=''
		case "$1" in
			https://example.invalid/source0)
				if [ "$GET_CALLS" -eq 1 ]; then
					return 1
				fi
				cp "$TMP/source0.txt" "$2"
				;;
			https://example.invalid/source1)
				cp "$TMP/source1.txt" "$2"
				;;
			*) return 1 ;;
		esac
	}
	ss_download_api_artifacts
	ss_spec_assert_eq "$GET_CALLS" '3'
	ss_cached_api_sources_available
	ss_spec_assert_file_line "$STATUS" 'set health_artifact_download 1'
	ss_spec_assert_file_line "$STATUS" 'set health_artifact_sha256 '
	ss_spec_assert_file_line "$STATUS" 'warning artifact_sha256_partial'
	ss_spec_assert_eq "$(cat "$SS_TMP_DIR/api.0.block.txt")" 'ads.example
shared.example'
	ss_spec_assert_eq "$(cat "$SS_TMP_DIR/api.1.allow.txt")" 'shared.example'

	: >"$STATUS"
	printf '%s\n' '0|block|bad-sha|https://example.invalid/source0|0000000000000000000000000000000000000000000000000000000000000000' >"$SS_RESOLVED_SOURCES"
	GET_CALLS=0
	ss_http_get_file() {
		GET_CALLS=$((GET_CALLS + 1))
		SS_HTTP_STATUS=''
		cp "$TMP/source0.txt" "$2"
	}
	! ss_download_api_artifacts
	ss_spec_assert_file_line "$STATUS" 'set health_artifact_sha256 0'
	ss_spec_assert_file_line "$STATUS" 'error artifact_sha256_mismatch'
	ss_spec_assert_not_exists "$SS_ARTIFACT_CACHE_STATE"

	: >"$STATUS"
	command_exists() { return 1; }
	! ss_verify_artifact_sha256 "$TMP/source0.txt" "$SOURCE0_SHA"
	ss_spec_assert_file_line "$STATUS" 'set health_artifact_sha256 0'
	ss_spec_assert_file_line "$STATUS" 'error sha256sum_not_found'
	command_exists() { command -v "$1" >/dev/null 2>&1; }

	: >"$STATUS"
	printf '%s\n' '0|block|too-large|https://example.invalid/source0|' >"$SS_RESOLVED_SOURCES"
	ss_max_blocklist_file_size_kb=1
	ss_http_get_file() {
		SS_HTTP_STATUS=''
		cp "$TMP/source0.txt" "$2"
	}
	du() { printf '2\t%s\n' "$2"; }
	! ss_download_api_artifacts
	ss_spec_assert_file_line "$STATUS" 'set health_artifact_download 0'
	ss_spec_assert_file_line "$STATUS" 'error artifact_too_large'
	ss_spec_assert_not_exists "$SS_ARTIFACT_CACHE_STATE"
)
