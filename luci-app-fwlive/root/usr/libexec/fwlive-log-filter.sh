#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2025-2026 Lucas Albers <lucas.b.albers@gmail.com>
#
# Filter log.read JSON to firewall-only entries (isFirewallEvent parity).
# Log messages are treated as data (jsonfilter + awk stdin); never interpolated
# into shell command strings. Usage: ubus call log read '...' | fwlive-log-filter.sh
#
# Performance: one jsonfilter for @.log[*] plus one awk classify. The same
# awk pass counts enumerated entries for messages_received; process count is
# constant per poll, not O(entries).
#
# Entry point (pipeline). The classifier sibling is sourced and must not set
# strict mode itself.
set -eu

if ! command -v jsonfilter >/dev/null 2>&1; then
	command -v logger >/dev/null 2>&1 && logger -t fwlive "jsonfilter not found; cannot filter firewall logs"
	printf '%s' '{"log":[],"error":"jsonfilter_missing"}'
	exit 1
fi

FILTER_DIR="$(cd "$(dirname "$0")" && pwd)"
FILTER_TMP_DIR='/tmp'
[ "$#" -gt 0 ] && FILTER_TMP_DIR="$1"
# shellcheck disable=SC1091 # classifier is a sibling file next to this script
. "$FILTER_DIR/fwlive-is-firewall-event.sh"

# The classifier is a package asset, not generated at request time. Fail
# closed if an incomplete install or a damaged package removed it.
if [ ! -r "$CLASSIFY_AWK" ]; then
	printf '%s' '{"log":[],"error":"classifier_missing"}'
	exit 1
fi

# Prefer stdin over -s: Linux MAX_ARG_STRLEN is 128KiB; a raised logd ring
# (or paused FETCH_LINES_MAX poll) can exceed that and make jsonfilter fail
# while this script still returns a valid empty result.
# A valid input with no log entries is not fatal; the classifier closes JSON
# and reports messages_received:0. A jsonfilter failure is different:
# it must remain an error so rpcd does not record a fast healthy sample. Keep
# jsonfilter output in a secure temporary file before classification so a
# partial pipeline cannot produce malformed JSON on failure.
# This script runs from rpcd as root and reopens the path for classification.
# Match _fwlive_mktemp: only use a verified, sticky dump directory. The
# production rpcd caller passes /tmp; the explicit argument lets host tests
# exercise the directory guard without changing the host's /tmp.
# shellcheck disable=SC3065 # OpenWrt BusyBox test supports -k; match rpcd helper.
if [ ! -d "$FILTER_TMP_DIR" ] || [ -L "$FILTER_TMP_DIR" ] || ! [ -k "$FILTER_TMP_DIR" ]; then
	printf '%s' '{"log":[],"error":"filter_tempfile_failed"}'
	exit 1
fi
_filter_tmp=$(mktemp "$FILTER_TMP_DIR/fwlive-filter.XXXXXX") || {
	printf '%s' '{"log":[],"error":"filter_tempfile_failed"}'
	exit 1
}
trap 'rm -f "$_filter_tmp"' 0 1 2 3 15
if ! jsonfilter -e '@.log[*]' >"$_filter_tmp" 2>/dev/null; then
	printf '%s' '{"log":[],"error":"filter_failed"}'
	exit 1
fi
_fwlive_filter_json_reply <"$_filter_tmp"
