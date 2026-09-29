#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# The fw4 chain/set inventory in scripts/fw4_names.sh must stay in sync with
# the objects declared by scripts/firewall_post.ut: the first drives the
# cleanup in init.d/homeproxy, the second creates them. A drift means either a
# leftover object or a delete of something that never existed (which used to
# abort the whole cleanup batch).
#
# Usage: sh tests/ucode/test_fw4_names.sh <repo-root>

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

NAMES="$ROOT/root/etc/homeproxy/scripts/fw4_names.sh"
POST="$ROOT/root/etc/homeproxy/scripts/firewall_post.ut"
PRE="$ROOT/root/etc/homeproxy/scripts/firewall_pre.uc"

FAILED=0

# shellcheck source=/dev/null
. "$NAMES"

check_group() {
	group="$1"
	list="$(printf '%s\n' $2 | tr '\n' ' ')"
	declared="$(printf '%s\n' $3 | tr '\n' ' ')"
	missing=""
	extra=""

	for name in $declared; do
		case " $list " in
		*" $name "*) ;;
		*) missing="$missing $name" ;;
		esac
	done

	for name in $list; do
		case " $declared " in
		*" $name "*) ;;
		*) extra="$extra $name" ;;
		esac
	done

	if [ -z "$missing$extra" ]; then
		echo "PASS: $group inventory matches firewall_post.ut"
	else
		[ -n "$missing" ] && echo "FAIL: $group declared in firewall_post.ut but missing from fw4_names.sh:$missing"
		[ -n "$extra" ] && echo "FAIL: $group listed in fw4_names.sh but not declared in firewall_post.ut:$extra"
		FAILED=1
	fi
}

post_chains="$(grep -oE '^chain homeproxy_[a-z0-9_]+' "$POST" | awk '{print $2}' | sort -u)"
post_sets="$(grep -oE '^set homeproxy_[a-z0-9_]+' "$POST" | awk '{print $2}' | sort -u)"

check_group "chain" "$HP_FW4_CHAINS" "$post_chains"
check_group "set" "$HP_FW4_SETS" "$post_sets"

# firewall_pre.uc only writes forward/input accept rules; it must not own any
# chain/set of its own.
pre_refs="$(grep -oE 'homeproxy_[a-z0-9_]+' "$PRE" | sort -u)"
if [ -n "$pre_refs" ]; then
	echo "NOTE: firewall_pre.uc references fw4 objects:$pre_refs"
fi

exit $FAILED
