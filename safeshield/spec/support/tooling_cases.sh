#!/bin/sh
# shellcheck shell=sh

ss_case_tooling() (
	set -eu
	[ -f "$SS_SPEC_ROOT/.pre-commit-config.yaml" ]
	[ -f "$SS_SPEC_ROOT/.shellspec" ]
	[ -f "$SS_SPEC_ROOT/spec/spec_helper.sh" ]
	[ -f "$SS_SPEC_ROOT/spec/core_spec.sh" ]
	[ -f "$SS_SPEC_ROOT/spec/blocklist_spec.sh" ]
	[ -f "$SS_SPEC_ROOT/spec/runtime_spec.sh" ]
	[ -f "$SS_SPEC_ROOT/spec/statistics_spec.sh" ]
	[ -f "$SS_SPEC_ROOT/spec/ucode_spec.sh" ]
	[ -f "$SS_SPEC_ROOT/spec/tooling_spec.sh" ]
	[ -f "$SS_SPEC_ROOT/scripts/lint.sh" ]
	[ -f "$SS_SPEC_ROOT/.github/workflows/lint-shell.yml" ]
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/.pre-commit-config.yaml" 'entry: sh scripts/lint.sh'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/.pre-commit-config.yaml" 'always_run: true'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/.github/workflows/lint-shell.yml" 'sh scripts/lint.sh'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/.github/workflows/lint-shell.yml" 'SHELLSPEC_VERSION: 0.28.1'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/.github/workflows/lint-shell.yml" 'run: REQUIRE_UCODE=1 shellspec'
	[ ! -e "$SS_SPEC_ROOT/tests/run.sh" ]
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/scripts/lint.sh" 'spec/*_spec.sh)'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/scripts/lint.sh" 'shfmt -d -ci'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/scripts/lint.sh" 'shellcheck -x -S warning'
	ss_spec_assert_file_contains "$SS_SPEC_ROOT/scripts/lint.sh" 'sh -n "$file"'
	[ ! -e "$SS_SPEC_ROOT/spec/legacy_tests_spec.sh" ]
)

ss_case_dead_code_contract() (
	set -eu

	UTILS="$SS_SPEC_ROOT/files/usr/lib/safeshield/utils.sh"
	STATUS="$SS_SPEC_ROOT/files/usr/lib/safeshield/status.sh"
	LOG="$SS_SPEC_ROOT/files/usr/lib/safeshield/log.sh"
	DNS="$SS_SPEC_ROOT/files/usr/lib/safeshield/dns.sh"
	BLOCKLIST="$SS_SPEC_ROOT/files/usr/lib/safeshield/blocklist.sh"
	CONFIG="$SS_SPEC_ROOT/files/usr/lib/safeshield/config.sh"
	INIT="$SS_SPEC_ROOT/files/etc/init.d/safeshield"

	for symbol in \
		str_contains \
		str_contains_word \
		str_first_word \
		str_to_lower \
		str_to_upper \
		str_replace \
		is_greater; do
		! grep -Eq "^${symbol}\\(\\)[[:space:]]*\\{" "$UTILS"
	done

	for symbol in is_enabled is_active; do
		! grep -Eq "^${symbol}\\(\\)[[:space:]]*\\{" "$STATUS"
	done

	for symbol in log_fail log_debug; do
		! grep -Eq "^${symbol}\\(\\)[[:space:]]*\\{" "$LOG"
	done

	for symbol in ss_clear_active_blocklist dnsmasq_kill; do
		! grep -Eq "^${symbol}\\(\\)[[:space:]]*\\{" "$DNS"
	done

	! grep -Eq '^ss_detect_primary_mac\\(\\)[[:space:]]*\\{' "$BLOCKLIST"
	! grep -F 'ss_debug=' "$CONFIG"
	! grep -F '/lib/functions/network.sh' "$INIT"

	# Keep the replacement/runtime contracts that made the retired helpers obsolete.
	ss_spec_assert_file_contains "$BLOCKLIST" 'ss_identity_ensure "$model" "$arch"'
	ss_spec_assert_file_contains "$DNS" '/etc/init.d/dnsmasq restart'
	ss_spec_assert_file_contains "$INIT" "procd_add_reload_interface_trigger 'wan'"
)
