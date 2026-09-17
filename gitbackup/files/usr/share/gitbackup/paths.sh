# shellcheck shell=sh
#
# gitbackup -- Paths: the /etc/sysupgrade.conf editor (ticket 17, spec
# "Paths", "Сбор и manifest.json", "Проверенные факты 25.12.4 -> sysupgrade").
#
# The whole point (spec, verbatim): "Расширение списка -- редактирование
# /etc/sysupgrade.conf, а не отдельный UCI-список. То, что пользователь
# добавил ради бэкапа, автоматически переживёт реальный sysupgrade." This
# module owns that file, its blacklist, and the effective-set size
# estimate; usr/sbin/gitbackup's `paths` subcommand is its only caller
# today, but nothing here assumes that -- a future rpcd method could call
# these same functions instead of re-deriving the blacklist a second time.
#
# GB_SYSUPGRADE_CONF overrides the file this module reads/writes (default
# /etc/sysupgrade.conf) -- the same override name
# usr/libexec/rpcd/luci.gitbackup's own gbrpc_set_paths already uses for
# the identical file. GB_ROOT overrides the filesystem root existence
# checks resolve against, same convention collect.sh/restore.sh already
# use, so tests can point this at a fixture tree instead of the host
# filesystem.
#
# Depends on lib.sh (gb_log) already being sourced by the caller, same
# convention every sibling module here uses. Sourced, never executed:
# nothing here runs at load time -- both variable defaults below are cheap
# parameter expansions, not commands.

GB_SYSUPGRADE_CONF="${GB_SYSUPGRADE_CONF:-/etc/sysupgrade.conf}"
GB_ROOT="${GB_ROOT:-}"

# gb_paths_list -- the raw content of GB_SYSUPGRADE_CONF, one line per
# call. This is deliberately NOT sysupgrade -l's own wider effective set
# (spec: that is GB_SYSUPGRADE_CONF union /lib/upgrade/keep.d/* union
# changed conffiles) -- a package's own paths editor has nothing to add or
# remove from the other two sources, so listing them here would be lines
# `paths del` could never actually delete. gb_paths_size_kb below is the
# one place the wider effective set matters.
gb_paths_list() {
	[ -r "$GB_SYSUPGRADE_CONF" ] && cat "$GB_SYSUPGRADE_CONF"
	return 0
}

# _gb_paths_is_comment_or_blank <line> -- true (0) when <line> is not a real
# path entry: empty, or a sysupgrade.conf comment. sysupgrade.conf's own
# comment syntax is "first character is '#'" -- nothing past that character
# is ever inspected, so "# /etc/openvpn/" is a commented-out EXAMPLE line,
# not a disabled entry for /etc/openvpn/, and backs up nothing at all
# (ticket 26). This is the one and only place that decides what counts as
# "not an entry" -- gb_paths_entries (what gets listed) and
# gb_paths_replace_entries (what gets preserved on a full-list write) both
# call it, so the two can never quietly disagree about the same line.
_gb_paths_is_comment_or_blank() {
	case "$1" in
		'' | '#'*) return 0 ;;
		*) return 1 ;;
	esac
}

# gb_paths_entries -- gb_paths_list, filtered down to genuine path entries:
# blank lines and comments (see _gb_paths_is_comment_or_blank) are dropped.
# gb_paths_list itself is left alone and stays raw -- ticket 26 chose two
# functions with two distinct meanings ("what the file literally contains"
# vs. "what a human's own path list looks like") over one function whose
# answer would depend on which caller was asking. This is what the LuCI
# view and `paths list --json`'s new "entries" field are built on: a stock
# /etc/sysupgrade.conf's four header/example lines are comments, contain
# zero real entries, and must render as an empty, unremovable list.
gb_paths_entries() {
	gb_paths_list | while IFS= read -r _gb_pe_l || [ -n "$_gb_pe_l" ]; do
		_gb_paths_is_comment_or_blank "$_gb_pe_l" && continue
		printf '%s\n' "$_gb_pe_l"
	done
	return 0
}

# gb_paths_size_kb -- kilobytes of everything `sysupgrade -l` would
# actually collect (the full effective set: GB_SYSUPGRADE_CONF union
# keep.d union changed conffiles -- the union sysupgrade itself computes,
# not just this file's own lines), read straight off the filesystem with
# no copy made. Moved here from usr/sbin/gitbackup's own former
# _gb_run_estimate_kb (ticket 07) so `run`'s pre-flight space check and
# `paths`'s own 2 MB warning threshold (spec "LuCI -> Paths": "Счётчик
# суммарного размера набора с предупреждением на 2 MB") can never quietly
# disagree about what "the size of the backup set" means. Symlinks are
# skipped (their own size is a few bytes and does not matter to either
# caller's headroom math); a path sysupgrade -l names that is no longer
# there contributes 0, same tolerance gb_collect already has for that
# case.
gb_paths_size_kb() {
	sysupgrade -l 2>/dev/null | while IFS= read -r _gb_pkb_p || [ -n "$_gb_pkb_p" ]; do
		[ -n "$_gb_pkb_p" ] || continue
		[ -f "$GB_ROOT$_gb_pkb_p" ] || continue
		wc -c <"$GB_ROOT$_gb_pkb_p" 2>/dev/null
	done | awk '{s += $1} END {printf "%d", (s + 1023) / 1024}'
}

# gb_paths_validate <path>
#
# 0 when <path> may be added to GB_SYSUPGRADE_CONF; on refusal, prints one
# human-readable reason to stderr and returns a code from this package's
# own shared contract (interfaces.md "Коды выхода") -- 2 for a plain bad
# argument (not absolute, contains a space, not canonically spelled, does
# not exist), 4 for a refusal on safety grounds (the fixed blacklist) --
# so a caller can pass the return value straight to gb_die without having
# to reclassify it.
#
# Checked in the order a human would want to hear about it: absolute
# first (everything below assumes that), then the one syntactic limit
# `sysupgrade -l`'s own `find` invocation imposes (spec "Проверенные
# факты 25.12.4 -> sysupgrade": "пути с пробелами не поддерживаются
# конструктивно"), then the one spelling every textual check below (and
# collect.sh's own hard-exclude) is able to reason about, then the fixed
# blacklist (never configurable -- ticket 17's own brief: "запрет на
# /etc/gitbackup/**, /proc, /sys, /tmp"), and
# only last whether the path actually exists -- there is no point telling
# an operator their entry is missing from disk before telling them it was
# never going to be accepted at all.
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

	# The blacklist below is `case` glob matching, i.e. purely textual, so
	# it only holds for one spelling of each path. "//etc/gitbackup",
	# "/etc/./gitbackup" and "/etc/../etc/gitbackup" all name the reserved
	# directory to find(1) -- which is what a sysupgrade.conf line becomes
	# -- while matching none of the patterns that reserve it, and
	# collect.sh's own hard-exclude of that directory is textual in the
	# same way. An entry spelled like that therefore used to sail past
	# both and put /etc/gitbackup/token and the deploy private key into
	# the backup repository itself.
	#
	# Refused rather than silently rewritten to the canonical spelling:
	# what lands in sysupgrade.conf is what the operator (or the LuCI
	# Paths view) asked for, verbatim, everywhere else in this file --
	# gb_paths_add's idempotence and gb_paths_del's exact-line removal
	# both depend on that -- and quietly editing an entry on the way in
	# would break the "add what I typed, remove what I see" contract for
	# the sake of one accepted keystroke. The canonical spelling is named
	# in the message instead, and reaches the Paths view as the rejection
	# reason gbrpc_set_paths already reports per entry.
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

	# -e alone misses a dangling symlink (lstat vs stat) -- and this
	# backup set is full of legitimate ones, /etc/resolv.conf being the
	# standard example (collect.sh's own R24.1 comment) -- so -L is
	# checked too before refusing.
	if [ ! -e "$GB_ROOT$_gb_pv_path" ] && [ ! -L "$GB_ROOT$_gb_pv_path" ]; then
		printf '%s: no such file or directory\n' "$_gb_pv_path" >&2
		return 2
	fi

	return 0
}

# gb_paths_add <path> -- appends <path> to GB_SYSUPGRADE_CONF unless
# gb_paths_validate refuses it (its own reason already on stderr by then,
# its return code propagated unchanged) or it is already there verbatim
# (idempotent: spec/ticket 17 "add/del правят именно его, идемпотентно" --
# running add twice must not duplicate the line).
gb_paths_add() {
	_gb_pa_path="$1"
	gb_paths_validate "$_gb_pa_path" || return $?

	if [ -r "$GB_SYSUPGRADE_CONF" ] && grep -qxF "$_gb_pa_path" "$GB_SYSUPGRADE_CONF" 2>/dev/null; then
		return 0
	fi
	mkdir -p "$(dirname "$GB_SYSUPGRADE_CONF")" 2>/dev/null
	printf '%s\n' "$_gb_pa_path" >>"$GB_SYSUPGRADE_CONF"
}

# gb_paths_del <path> -- removes every line equal to <path>, verbatim.
# Silently succeeds when it was not there to begin with -- same
# idempotence gb_paths_add already provides, in the other direction.
#
# Deliberately NOT routed through gb_paths_validate (ticket 26 checked
# this): an exact-line removal of something that is not a valid entry is
# harmless -- there is nothing to protect against by refusing to delete a
# line that was never going to be backed up in the first place -- and a
# human running this subcommand by hand is trusted the way `rm` is. This
# does mean `gitbackup paths del '## some comment'` will happily strip
# that exact comment line the same way it would any other line; that is
# an accepted property of a deliberately unvalidated CLI subcommand, not a
# defect. The actual bug ticket 26 fixed lived one layer up: the LuCI view
# never called this function at all for its own "Remove" button (it always
# went through `set_paths`'s full-list replace, see gbrpc_set_paths in
# usr/libexec/rpcd/luci.gitbackup), and gb_paths_entries below is what
# stops that button from ever being offered for a comment line again.
gb_paths_del() {
	_gb_pd_path="$1"
	[ -r "$GB_SYSUPGRADE_CONF" ] || return 0

	_gb_pd_tmp="${GB_SYSUPGRADE_CONF}.tmp.$$"
	grep -vxF "$_gb_pd_path" "$GB_SYSUPGRADE_CONF" >"$_gb_pd_tmp" 2>/dev/null
	mv "$_gb_pd_tmp" "$GB_SYSUPGRADE_CONF"
}

# gb_paths_replace_entries <entries> -- rewrites GB_SYSUPGRADE_CONF as:
# every comment/blank line gb_paths_list already contains, in its original
# order and wording, completely unchanged -- followed by <entries>
# (newline-separated, blank lines ignored), one per line, exactly as
# given. Ticket 13's decision that a full-list write (`set_paths`, the
# rpcd plugin's only way to persist the LuCI Paths view's edits) writes
# back VERBATIM what it was handed stays -- a directory entry is still
# never expanded here. What changes is what "the file" means during that
# rewrite: it used to mean "only what the caller sent", so the very first
# save from the Paths view against a stock /etc/sysupgrade.conf silently
# erased its own header comments and the two commented-out example lines,
# because the caller (the LuCI view, then `gbrpc_set_paths`) never saw
# them in the first place -- gb_paths_entries (this same module) is what
# the view lists and edits, and comments are excluded from it by design.
# Losing someone else's lines on a save they never touched is not
# acceptable (ticket 26's own brief), so this function -- the one place a
# full-list write happens -- re-reads the comments straight from disk
# and keeps them, unconditionally, regardless of what the caller sent.
gb_paths_replace_entries() {
	_gb_pre_tmp="${GB_SYSUPGRADE_CONF}.tmp.$$"
	mkdir -p "$(dirname "$GB_SYSUPGRADE_CONF")" 2>/dev/null

	{
		gb_paths_list | while IFS= read -r _gb_pre_l || [ -n "$_gb_pre_l" ]; do
			_gb_paths_is_comment_or_blank "$_gb_pre_l" && printf '%s\n' "$_gb_pre_l"
		done
		printf '%s\n' "$1" | while IFS= read -r _gb_pre_e || [ -n "$_gb_pre_e" ]; do
			[ -n "$_gb_pre_e" ] || continue
			printf '%s\n' "$_gb_pre_e"
		done
	} >"$_gb_pre_tmp"

	mv "$_gb_pre_tmp" "$GB_SYSUPGRADE_CONF"
}
