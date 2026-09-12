# SPDX-License-Identifier: Apache-2.0
# Copyright 2025-2026 Lucas Albers <lucas.b.albers@gmail.com>
#
# GENERATED FILE — do not edit. Run: ./scripts/gen-all.sh
# source: core/fwlive-log.js CLASSIFY_SPEC
# Shared isFirewallEvent parity logic (shell). Sourced by fwlive-log-filter.sh and tests.
# Sourced library: do not add set -euo here (callers own strict mode, #291 C3).
# One awk process classifies a batch (MODE=json) or one message (default).

# The caller sets FILTER_DIR when this file is sourced. Resolve the asset
# once, not once per classification call.
CLASSIFY_AWK="${FILTER_DIR:-${0%/*}}/fwlive-is-firewall-event.awk"

_fwlive_run_classify() {
	awk -v MODE="${1:-msg}" -f "$CLASSIFY_AWK"
}

is_firewall_event_msg() {
	_r=$(printf '%s' "$1" | _fwlive_run_classify msg)
	[ "$_r" = 1 ]
}

_fwlive_filter_json_entries() {
	_fwlive_run_classify json
}
