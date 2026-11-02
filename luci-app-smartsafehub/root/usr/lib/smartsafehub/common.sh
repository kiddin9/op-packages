#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

# Escape a shell string for use inside a JSON string literal.
# SmartSafeHub state/event payloads are single-line JSON, so CR/LF are
# normalized to spaces before escaping backslashes and double quotes.
json_escape() {
	printf '%s' "${1:-}" | tr '\r\n' '  ' | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g'
}

# BusyBox tr builds used by some OpenWrt targets do not expand POSIX character
# classes such as [:lower:] / [:upper:] and can treat them as literal bytes.
# Use explicit ASCII alphabets for protocol/status tokens so, for example,
# `pro` always normalizes to `PRO` on every supported router.
ascii_upper() {
	printf '%s' "${1:-}" | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
}

ascii_lower() {
	printf '%s' "${1:-}" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

# A mkdir directory is the mutex; the pid is an advisory owner marker. A
# missing pid is NOT evidence of a stale mutex (mkdir -> pid write is a race).
# All of these helpers operate on /tmp locks; no persistent flash writes.
ssh_lock_owner() {
	local owner
	owner="$(cat "$1/pid" 2>/dev/null || true)"
	case "$owner" in ''|0*|*[!0-9]*) return 1 ;; esac
	printf '%s' "$owner"
}

ssh_lock_try() {
	local lock_dir="$1"
	mkdir "$lock_dir" 2>/dev/null || return 1
	if ! printf '%s\n' "$$" > "$lock_dir/pid" 2>/dev/null; then
		rm -rf "$lock_dir" 2>/dev/null || true
		return 1
	fi
	return 0
}

ssh_lock_reclaim() {
	local lock_dir="$1" guard="$2" allow_pidless="$3" owner
	[ -d "$lock_dir" ] || return 0
	# Only one contender may inspect/remove a stale directory at a time.
	mkdir "$guard" 2>/dev/null || return 1
	owner="$(ssh_lock_owner "$lock_dir" || true)"
	if [ -n "$owner" ]; then
		if ! kill -0 "$owner" 2>/dev/null; then
			# Recheck before deleting: another contender may have replaced the lock.
			[ "$(ssh_lock_owner "$lock_dir" || true)" = "$owner" ] &&
				rm -rf "$lock_dir" 2>/dev/null || true
		fi
	elif [ "$allow_pidless" = 1 ]; then
		# Missing or malformed markers are reclaimed only after bounded grace.
		# Recheck under the guard: the initializing owner may have just published.
		if [ -z "$(ssh_lock_owner "$lock_dir" || true)" ]; then
			rm -rf "$lock_dir" 2>/dev/null || true
		fi
	fi
	rmdir "$guard" 2>/dev/null || true
	return 0
}

# ssh_lock_acquire DIR RETRIES DELAY SLEEP_BIN [FAIL_FAST_LIVE]
# A live owner's mutex can be fail-fast for jobs that must return BUSY (75),
# while event writers wait briefly to avoid dropping event records.
ssh_lock_acquire() {
	local lock_dir="$1" attempts=0 max_attempts="${2:-40}" delay="${3:-0.05}"
	local sleep_bin="${4:-sleep}" fail_fast_live="${5:-0}" owner guard
	guard="${lock_dir}.reclaim"
	case "$max_attempts" in ''|*[!0-9]*) max_attempts=40 ;; esac
	if [ "$max_attempts" -lt 1 ] || [ "$max_attempts" -gt 200 ]; then max_attempts=40; fi
	[ -n "$delay" ] || delay=0.05
	while [ "$attempts" -lt "$max_attempts" ]; do
		ssh_lock_try "$lock_dir" && return 0
		owner="$(ssh_lock_owner "$lock_dir" || true)"
		if [ -n "$owner" ]; then
			if kill -0 "$owner" 2>/dev/null; then
				[ "$fail_fast_live" = 1 ] && return 1
			else
				ssh_lock_reclaim "$lock_dir" "$guard" 0 || true
			fi
		fi
		attempts=$((attempts + 1))
		[ "$attempts" -lt "$max_attempts" ] || break
		"$sleep_bin" "$delay" 2>/dev/null || true
	done
	ssh_lock_reclaim "$lock_dir" "$guard" 1 || true
	ssh_lock_try "$lock_dir"
}

ssh_lock_release() {
	local owner
	owner="$(ssh_lock_owner "$1" || true)"
	[ "$owner" = "$$" ] || return 0
	rm -rf "$1" 2>/dev/null || true
}

ssh_uci_get() {
	local bin="$1" key="$2"
	"$bin" -q get "$key" 2>/dev/null || true
}

# No jsonfilter is launched when the input does not exist. Optional 'nonempty'
# keeps activity-sync's previous requirement for nonempty credential files.
ssh_json_value() {
	local bin="$1" file="$2" expression="$3" policy="${4:-exists}"
	if [ "$policy" = nonempty ]; then
		[ -s "$file" ] || return 0
	else
		[ -f "$file" ] || return 0
	fi
	"$bin" -i "$file" -e "$expression" 2>/dev/null || true
}
