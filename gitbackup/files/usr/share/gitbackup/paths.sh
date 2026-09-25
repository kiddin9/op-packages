# shellcheck shell=sh
#
# gitbackup -- editor for /etc/sysupgrade.conf, so paths added for backup also
# survive a real sysupgrade. Exposes gb_paths_list, gb_paths_entries,
# gb_paths_size_kb, gb_paths_validate, gb_paths_add, gb_paths_del,
# gb_paths_replace_entries. Path validation lives only here, not in JS.
# Needs lib.sh.

GB_SYSUPGRADE_CONF="${GB_SYSUPGRADE_CONF:-/etc/sysupgrade.conf}"
GB_ROOT="${GB_ROOT:-}"

# The file verbatim, comments included -- writes rely on it. Not the effective
# set (keep.d, conffiles): this editor cannot change those.
gb_paths_list() {
	[ -r "$GB_SYSUPGRADE_CONF" ] && cat "$GB_SYSUPGRADE_CONF"
	return 0
}

gb_paths_entries() {
	gb_paths_list | grep -v -e '^$' -e '^#'
	return 0
}

# KB of the full effective set (`sysupgrade -l`); symlinks count as 0.
gb_paths_size_kb() {
	sysupgrade -l 2>/dev/null | while IFS= read -r _gb_pkb_p || [ -n "$_gb_pkb_p" ]; do
		[ -n "$_gb_pkb_p" ] || continue
		[ -f "$GB_ROOT$_gb_pkb_p" ] || continue
		wc -c <"$GB_ROOT$_gb_pkb_p" 2>/dev/null
	done | awk '{s += $1} END {printf "%d", (s + 1023) / 1024}'
}

# gb_paths_validate <path> -- 0, or a reason on stderr and 2 (bad argument) /
# 4 (blacklisted). Spaces are refused: sysupgrade passes lines to find(1)
# unquoted.
gb_paths_validate() {
	_gb_pv_path="$1"

	case "$_gb_pv_path" in
		/*) ;;
		*)
			printf '%s: not an absolute path\n' "$_gb_pv_path" >&2
			return 2
			;;
	esac

	case "$_gb_pv_path" in
		*' '*)
			printf '%s: contains a space -- sysupgrade.conf lines become find(1) arguments and cannot quote one\n' "$_gb_pv_path" >&2
			return 2
			;;
	esac

	# The blacklist is textual, so only one spelling may pass; refused rather
	# than rewritten, since entries are stored exactly as given.
	_gb_pv_canon=$(gb_path_canon "$_gb_pv_path")
	if [ "$_gb_pv_canon" != "$_gb_pv_path" ]; then
		printf '%s: not a canonical path -- write it as %s\n' "$_gb_pv_path" "$_gb_pv_canon" >&2
		return 2
	fi

	case "$_gb_pv_path" in
		/etc/gitbackup | /etc/gitbackup/*)
			printf '%s: reserved for gitbackup itself\n' "$_gb_pv_path" >&2
			return 4
			;;
		/proc | /proc/*)
			printf '%s: not a real filesystem path\n' "$_gb_pv_path" >&2
			return 4
			;;
		/sys | /sys/*)
			printf '%s: not a real filesystem path\n' "$_gb_pv_path" >&2
			return 4
			;;
		/tmp | /tmp/*)
			printf '%s: cleared on every reboot\n' "$_gb_pv_path" >&2
			return 4
			;;
	esac

	# -L too: -e misses dangling symlinks such as /etc/resolv.conf.
	if [ ! -e "$GB_ROOT$_gb_pv_path" ] && [ ! -L "$GB_ROOT$_gb_pv_path" ]; then
		printf '%s: no such file or directory\n' "$_gb_pv_path" >&2
		return 2
	fi

	return 0
}

gb_paths_add() {
	_gb_pa_path="$1"
	gb_paths_validate "$_gb_pa_path" || return $?

	if [ -r "$GB_SYSUPGRADE_CONF" ] && grep -qxF "$_gb_pa_path" "$GB_SYSUPGRADE_CONF" 2>/dev/null; then
		return 0
	fi
	mkdir -p "$(dirname "$GB_SYSUPGRADE_CONF")" 2>/dev/null
	printf '%s\n' "$_gb_pa_path" >>"$GB_SYSUPGRADE_CONF"
}

# Deliberately unvalidated: must be able to remove any stale entry.
gb_paths_del() {
	_gb_pd_path="$1"
	[ -r "$GB_SYSUPGRADE_CONF" ] || return 0

	_gb_pd_tmp="${GB_SYSUPGRADE_CONF}.tmp.$$"
	grep -vxF "$_gb_pd_path" "$GB_SYSUPGRADE_CONF" >"$_gb_pd_tmp" 2>/dev/null
	mv "$_gb_pd_tmp" "$GB_SYSUPGRADE_CONF"
}

# Keeps the file's comment lines (a save must not erase the stock header),
# then <entries> verbatim. Never expand directories into the effective set:
# files created later would silently stop being backed up.
gb_paths_replace_entries() {
	_gb_pre_tmp="${GB_SYSUPGRADE_CONF}.tmp.$$"
	mkdir -p "$(dirname "$GB_SYSUPGRADE_CONF")" 2>/dev/null

	{
		gb_paths_list | grep -e '^$' -e '^#'
		printf '%s\n' "$1" | grep .
	} >"$_gb_pre_tmp"

	mv "$_gb_pre_tmp" "$GB_SYSUPGRADE_CONF"
}
