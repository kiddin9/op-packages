# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org
#
# Configuration transaction helpers for homeproxy.
#
# The generated sing-box configuration is the only thing standing between the
# router and a working service, so it is handled as a transaction:
#
#   generate            the generator writes atomically and only after
#                       `sing-box check` accepted the result, so a failed
#                       generation leaves the previous file in place
#     -> known-good     every accepted file is copied aside, so there is
#                       always something to fall back to
#     -> ensure-live    if generation produced nothing, restore the
#                       known-good copy instead of failing the start
#     -> rollback       a reload that comes up unhealthy puts the known-good
#                       copy back (see reload_service in init.d/homeproxy)
#
# Sourced by /etc/init.d/homeproxy.  The functions only take explicit paths
# and never call procd or ubus, so tests/runtime/test_config_transaction.sh
# can exercise them without a router.

# hp_known_good <live> <known-good>
# Record <live> as the new known-good copy.  Non-zero when <live> is missing
# or empty, in which case the previous known-good copy is left untouched.
hp_known_good() {
	local live="$1"
	local good="$2"

	[ -s "$live" ] || return 1

	mkdir -p "$(dirname "$good")" 2>/dev/null
	cp -f "$live" "$good" 2>/dev/null || return 1
	# The known-good copy holds the same credentials as the live file, so the
	# two have to stay in step: otherwise a rollback restores a copy that is
	# world-readable whenever the source was.
	chmod 600 "$good" 2>/dev/null

	return 0
}

# hp_ensure_live <live> <known-good>
# 0  <live> is present and usable
# 1  <live> was missing and the known-good copy was restored
# 2  nothing usable: neither file exists
hp_ensure_live() {
	local live="$1"
	local good="$2"

	[ -s "$live" ] && return 0

	if [ -s "$good" ]; then
		cp -f "$good" "$live" 2>/dev/null && return 1
	fi

	return 2
}

# hp_rollback <live> <known-good>
# Replace <live> with the known-good copy.  Non-zero when there is nothing to
# roll back to, so the caller can distinguish "restored" from "no fallback".
hp_rollback() {
	local live="$1"
	local good="$2"

	[ -s "$good" ] || return 1

	cp -f "$good" "$live" 2>/dev/null || return 1

	return 0
}

# hp_same_file <a> <b>
# 0 when both files exist and have identical content.  Used to skip the
# rollback when the failing configuration is already the known-good one.
hp_same_file() {
	[ -s "$1" ] && [ -s "$2" ] || return 1
	cmp -s "$1" "$2" 2>/dev/null
}
