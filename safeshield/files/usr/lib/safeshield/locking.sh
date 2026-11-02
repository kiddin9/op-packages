# shellcheck shell=ash

# Directory locks work with the OpenWrt BusyBox base utilities; flock(1) is
# intentionally not required. A pid-less directory is treated as initializing
# (or abandoned) and must age before it can be reclaimed.
ss_lock_pid_alive() {
	case "${1:-}" in
		'' | *[!0-9]* | 0) return 1 ;;
	esac
	kill -0 "$1" 2>/dev/null
}

ss_lock_stale() {
	local path="$1" owner='' modified='' now=''

	[ -d "$path" ] || return 1
	if [ -r "$path/pid" ]; then
		IFS= read -r owner <"$path/pid" || true
		# A live owner always wins, even if the directory appears old.
		ss_lock_pid_alive "$owner" && return 1
		# Never reclaim an invalid pid that could be mid-write without a grace period.
		case "$owner" in
			'' | *[!0-9]* | 0) ;;
			*) return 0 ;;
		esac
	fi

	# stat is available in the supported BusyBox builds. If it is missing,
	# fail closed rather than destroying a possibly initializing lock.
	modified="$(stat -c %Y "$path" 2>/dev/null)" || return 1
	now="$(date +%s 2>/dev/null)" || return 1
	case "$modified:$now" in
		*[!0-9:]* | :* | *:) return 1 ;;
	esac
	[ "$((now - modified))" -ge 30 ] 2>/dev/null
}

ss_lock_reclaim() {
	local path="$1" guard="${1}.reclaim" owner=''

	# Only one contender may inspect/remove a stale directory at a time.
	mkdir "$guard" 2>/dev/null || return 1
	if ! ss_lock_stale "$path"; then
		rmdir "$guard" 2>/dev/null || true
		return 1
	fi
	if [ -r "$path/pid" ]; then
		IFS= read -r owner <"$path/pid" || true
	fi
	if ss_lock_pid_alive "$owner"; then
		rmdir "$guard" 2>/dev/null || true
		return 1
	fi
	# A foreign file makes this fail safely instead of deleting arbitrary data.
	rm -f "$path/pid" 2>/dev/null || true
	if ! rmdir "$path" 2>/dev/null; then
		rmdir "$guard" 2>/dev/null || true
		return 1
	fi
	rmdir "$guard" 2>/dev/null || true
	return 0
}

ss_lock_try() {
	local path="$1" attempt=0
	[ -n "$path" ] || return 1
	mkdir -p "${path%/*}" || return 1
	while [ "$attempt" -lt 2 ]; do
		# Prevent new acquisitions while stale-lock removal is in progress.
		if [ -d "${path}.reclaim" ]; then
			# A crashed reclaimer must not block all future acquisitions forever.
			# Refuse to touch a recent guard still owned by an active reclaimer.
			ss_lock_stale "${path}.reclaim" && rmdir "${path}.reclaim" 2>/dev/null || return 1
		fi
		if mkdir "$path" 2>/dev/null; then
			if ! printf '%s\n' "$$" >"$path/pid"; then
				rmdir "$path" 2>/dev/null || true
				return 1
			fi
			if [ -e "${path}.reclaim" ]; then
				ss_lock_release "$path"
				return 1
			fi
			return 0
		fi
		[ "$attempt" -eq 0 ] || break
		ss_lock_reclaim "$path" || return 1
		attempt=$((attempt + 1))
	done
	return 1
}

ss_lock_wait() {
	local path="$1" timeout="${2:-10}" stop_cb="${3:-}" waited=0
	case "$timeout" in
		'' | *[!0-9]*) timeout=10 ;;
	esac
	while ! ss_lock_try "$path"; do
		if [ "$waited" -ge "$timeout" ]; then
			return 1
		fi
		if [ -n "$stop_cb" ] && "$stop_cb"; then
			return 130
		fi
		sleep 1
		waited=$((waited + 1))
	done
	return 0
}

ss_lock_release() {
	local path="$1" owner=''
	[ -n "$path" ] && [ -r "$path/pid" ] || return 0
	IFS= read -r owner <"$path/pid" || true
	[ "$owner" = "$$" ] || return 1
	# Do not remove someone else's data even if the lock has extra contents.
	rm -f "$path/pid" || return 1
	rmdir "$path" 2>/dev/null
}
