#!/bin/sh
# shellcheck shell=sh
set -eu

spec_helper_precheck() {
	minimum_version "0.28.1"
}

SS_SPEC_ROOT="${SHELLSPEC_PROJECT_ROOT:-$(pwd)}"
export SS_SPEC_ROOT

# shellcheck disable=SC1091
. "$SS_SPEC_ROOT/spec/support/common.sh"
# shellcheck disable=SC1091
. "$SS_SPEC_ROOT/spec/support/core_cases.sh"
# shellcheck disable=SC1091
. "$SS_SPEC_ROOT/spec/support/lifecycle_cases.sh"
# shellcheck disable=SC1091
. "$SS_SPEC_ROOT/spec/support/blocklist_cases.sh"
# shellcheck disable=SC1091
. "$SS_SPEC_ROOT/spec/support/runtime_cases.sh"
# shellcheck disable=SC1091
. "$SS_SPEC_ROOT/spec/support/statistics_cases.sh"
# shellcheck disable=SC1091
. "$SS_SPEC_ROOT/spec/support/ucode_cases.sh"
# shellcheck disable=SC1091
. "$SS_SPEC_ROOT/spec/support/tooling_cases.sh"
