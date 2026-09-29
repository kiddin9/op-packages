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

# hp_restore_known_good_uci <good-dir>
# Re-apply the UCI snapshot written by hp_promote_known_good (the keys that
# steer the firewall / dnsmasq / nft layer - see HP_INTERCEPT_SCALARS in
# runtime/service.sh). Returns 0 on success, 1 when the snapshot is missing -
# the rollback path logs and continues, since a missing snapshot just means
# the install is older than the snapshot feature (best-effort).
#
# Two passes over the file, because the snapshot carries two shapes:
#
#   homeproxy.<section>.<option>=<value>   scalar, replayed with `uci set`
#   list homeproxy.<section>.<option>=a,b  UCI list, replayed with
#                                         `uci delete` + `uci add_list`
#
# A list replayed through `uci set` becomes a *string*, and the firewall
# validators (ipv4_to_nftarr / iface_to_nftarr) reject a non-array by
# returning null - so the ACL rules reading it would silently disappear and
# the rollback would come back with the wrong clients exempted.
#
# The commit below is what makes this safe: every write is staged and only
# becomes visible when uci commit succeeds.  A partial failure leaves UCI
# unchanged; the rollback caller logs and the next reload path will see the
# same failing configuration it just rolled back from, so the failure mode
# stays bounded (no new corruption).
hp_restore_known_good_uci() {
	local good_dir="$1"
	local snap="$good_dir/uci-snapshot.txt"

	[ -s "$snap" ] || return 1

	local key value lkey el saved=0

	# Pass 1: scalars. `uci set key=` with an empty value is how UCI spells
	# "the option was not set", so a key that was absent in the known-good
	# state is removed again here rather than surviving as a failing value.
	# stdin is closed for every uci call so none of them can swallow the
	# file the loop is reading.
	while IFS='=' read -r key value; do
		case "$key" in
		""|list\ *|"#"*) continue ;;
		esac
		uci set "$key=$value" </dev/null || return 1
		saved=1
	done < "$snap"

	# Pass 2: list options. `uci delete` on an option that is not there is
	# expected - the known-good state may simply never have had this list -
	# so its exit status is deliberately ignored.  An empty recorded value
	# therefore means "absent or empty", and the delete is the whole
	# operation: a list the failing configuration added does not survive.
	while IFS='=' read -r key value; do
		case "$key" in
		list\ *) lkey="${key#list }" ;;
		*) continue ;;
		esac
		uci delete "$lkey" >/dev/null 2>&1 </dev/null
		saved=1
		[ -n "$value" ] || continue
		while :; do
			case "$value" in
			*,*) el="${value%%,*}"; value="${value#*,}" ;;
			*) el="$value"; value="" ;;
			esac
			uci add_list "$lkey=$el" </dev/null || return 1
			[ -n "$value" ] || break
		done
	done < "$snap"

	[ "$saved" = "1" ] && uci commit homeproxy </dev/null || return 1
	return 0
}
