#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2025-2026 Lucas Albers <lucas.b.albers@gmail.com>
#
# Filter log.read JSON to firewall-only entries (isFirewallEvent parity).
# Log messages are treated as data (jsonfilter + awk stdin); never interpolated
# into shell command strings. Usage: ubus call log read '...' | fwlive-log-filter.sh
#
# Perf (#219): one jsonfilter for @.log[*] plus one awk classify. Process
# count is constant per poll, not O(entries).
#
# Entry point (pipeline). The classifier sibling is sourced and must not set
# strict mode itself (#291 C3).
set -eu
# shellcheck disable=SC3040
(set -o pipefail) 2>/dev/null && set -o pipefail

if ! command -v jsonfilter >/dev/null 2>&1; then
	command -v logger >/dev/null 2>&1 && logger -t fwlive "jsonfilter not found; cannot filter firewall logs"
	printf '%s' '{"log":[],"error":"jsonfilter_missing"}'
	exit 1
fi

FILTER_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091 # classifier is a sibling file next to this script
. "$FILTER_DIR/fwlive-is-firewall-event.sh"

# The classifier is a package asset, not generated at request time. Fail
# closed if an incomplete install or a damaged package removed it (#321).
if [ ! -r "$CLASSIFY_AWK" ]; then
	printf '%s' '{"log":[],"error":"classifier_missing"}'
	exit 1
fi

printf '%s' '{"log":['
# Prefer stdin over -s: Linux MAX_ARG_STRLEN is 128KiB; a raised logd ring
# (or paused FETCH_LINES_MAX poll) can exceed that and make jsonfilter fail
# while this script still printed {"log":[]} and exited 0 (#234).
# jsonfilter miss / empty @.log is not fatal; must still close JSON (#220).
# set -e + pipefail cannot apply to this pipeline (#291 C3).
jsonfilter -e '@.log[*]' 2>/dev/null | _fwlive_filter_json_entries || true
printf '%s' ']}'
