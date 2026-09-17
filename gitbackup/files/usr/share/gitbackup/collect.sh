# shellcheck shell=sh
#
# gitbackup -- backup-set collection and manifest.json (spec "Сбор и
# manifest.json").
#
# Exposes gb_collect, gb_manifest_path and gb_manifest_equal; every
# _gb_collect_-prefixed helper below is private and namespaced by module
# (not just "_gb_") because every *.sh here ends up sourced into the same
# process by usr/sbin/gitbackup -- a same-named helper in a sibling module
# would silently shadow this one otherwise. Sourced, never executed:
# nothing here runs at load time.
#
# Depends on lib.sh (gb_log, gb_json_esc/str, ...) already being sourced by
# the caller, same convention device.sh uses. It does NOT depend on
# device.sh: the device name is read from $GB_DEVICE, which
# usr/sbin/gitbackup's gb_validate_config already resolves once via
# gb_device_id and exports for every subcommand (same contract as GB_URL
# and GB_SCRUB) -- collecting would otherwise resolve the device a second
# time and could disagree with the CLI's own answer.
#
# GB_ROOT overrides the filesystem root every real-path read goes through
# (default '', meaning the actual '/'). GB_EXCLUDE_LIST overrides where the
# hard-exclude patterns live (default GB_SHARE/exclude.list, GB_SHARE
# itself defaulting like the CLI's own). Neither is set by the router --
# both exist so tests/run.sh can point collect.sh at a fixture tree instead
# of the host filesystem, the same seam GB_SYSFS_NET gives device.sh.

GB_ROOT="${GB_ROOT:-}"
GB_EXCLUDE_LIST="${GB_EXCLUDE_LIST:-${GB_SHARE:-/usr/share/gitbackup}/exclude.list}"

# gb_manifest_path <outdir>
gb_manifest_path() {
	printf '%s/manifest.json\n' "$1"
}

# gb_manifest_equal <manifest-a> <manifest-b>
#
# True when two manifest.json files describe the same backup set. Compares
# only entries[] and scrubbed[] (spec: "generated не участвует в сравнении
# манифестов, иначе изменения были бы каждый прогон") -- and, by the same
# reasoning, neither do version/hostname/device/openwrt/board: none of them
# describe what restore actually writes back, and comparing them would turn
# an unrelated hostname change into a spurious commit on the next run.
#
# gb_manifest_tail (lib.sh) is the shared reader now: this used to be its
# own private sed range here, one of three near-identical readers of the
# same flat manifest.json format that scrub.sh and restore.sh had each
# grown independently (ticket 18) -- one reader, not three.
gb_manifest_equal() {
	[ -r "$1" ] && [ -r "$2" ] || return 1
	[ "$(gb_manifest_tail "$1")" = "$(gb_manifest_tail "$2")" ]
}

# gb_collect <outdir>
#
# Builds outdir/files (backup-set tree, paths preserved), outdir/meta (five
# files) and outdir/manifest.json. The path list is `sysupgrade -l` and
# nothing else (R29) -- collect.sh never walks /etc on its own to decide
# what belongs in the set, only to find the empty directories `sysupgrade
# -l` can never report (see _gb_collect_empty_dirs) and to concatenate
# /etc/apk/repositories.d/* for meta/repositories.txt.
gb_collect() {
	_gb_outdir="$1"
	[ -n "$_gb_outdir" ] || { gb_log err 'gb_collect: outdir is required'; return 1; }

	mkdir -p "$_gb_outdir/files" "$_gb_outdir/meta" ||
		{ gb_log err "gb_collect: cannot create $_gb_outdir"; return 1; }

	_gb_scratch=$(mktemp -d "${TMPDIR:-/tmp}/gitbackup-collect.XXXXXX") || return 1
	: >"$_gb_scratch/entries"

	_gb_collect_files "$_gb_outdir" "$_gb_scratch/entries"
	_gb_collect_empty_dirs "$_gb_outdir" "$_gb_scratch/entries"
	_gb_collect_meta "$_gb_outdir"
	_gb_collect_write_manifest "$_gb_outdir" "$_gb_scratch/entries"

	rm -rf "$_gb_scratch"
}

# _gb_collect_is_excluded <path> -- true when <path> matches a pattern in
# GB_EXCLUDE_LIST. A pattern ending in "/**" matches the path itself and
# everything under it; anything else is matched with plain `case` glob
# rules. Re-reads the file on every call rather than caching it in a
# variable: the list is a handful of lines, and this keeps the match logic
# free of the quoting/IFS games a cached multi-line variable would need.
#
# Matched on the canonical spelling of <path>, never the raw one: `case`
# globbing is textual, so "//etc/gitbackup/token" and
# "/etc/./gitbackup/token" match no pattern that names /etc/gitbackup even
# though find(1), cp(1) and the kernel all agree they are that file. This
# is the second half of the same fix gb_paths_validate carries -- that one
# stops such an entry being accepted into sysupgrade.conf at all, this one
# holds even for a path that never went through it, since `sysupgrade -l`
# unions in /lib/upgrade/keep.d/* and changed conffiles that this package
# does not own. exclude.list's own R76 ("must never end up inside its own
# backup, no matter how the router is configured") is only true with both.
_gb_collect_is_excluded() {
	# Own variable name, deliberately not the _gb_path every caller loop
	# here already uses: POSIX sh has no locals, and canonicalizing into
	# that name would silently rewrite the caller's loop variable too.
	_gb_ie_path=$(gb_path_canon "$1")
	[ -r "$GB_EXCLUDE_LIST" ] || return 1
	while IFS= read -r _gb_pat || [ -n "$_gb_pat" ]; do
		case "$_gb_pat" in
			''|'#'*) continue ;;
		esac
		case "$_gb_pat" in
			*/'**')
				_gb_prefix=${_gb_pat%/\*\*}
				case "$_gb_ie_path" in
					"$_gb_prefix"|"$_gb_prefix"/*) return 0 ;;
				esac
				;;
			*)
				# shellcheck disable=SC2254  # unquoted on purpose: this is a case glob, not a literal
				case "$_gb_ie_path" in
					$_gb_pat) return 0 ;;
				esac
				;;
		esac
	done <"$GB_EXCLUDE_LIST"
	return 1
}

# _gb_collect_files <outdir> <entries-file>
#
# Copies every file and symlink `sysupgrade -l` reports, minus hard-exclude,
# into outdir/files with its path preserved, and appends one manifest entry
# line per item to <entries-file>. Runs the loop body on the read side of a
# pipe (a subshell in POSIX sh), so it only ever accumulates state by
# appending to <entries-file> -- a real file survives the subshell boundary,
# a shell variable set in there would not.
_gb_collect_files() {
	_gb_outdir="$1"
	_gb_entries="$2"
	sysupgrade -l 2>/dev/null | while IFS= read -r _gb_path || [ -n "$_gb_path" ]; do
		[ -n "$_gb_path" ] || continue
		# One spelling per file from here down, so the staged tree, the
		# manifest entry and the exclude decision cannot disagree about
		# what "this path" is: "/etc/./config/network" and
		# "/etc/config/network" are one file to the kernel but two
		# distinct manifest entries (and two distinct restore targets)
		# if the raw string is carried through.
		_gb_path=$(gb_path_canon "$_gb_path")
		_gb_collect_is_excluded "$_gb_path" && continue

		_gb_src="$GB_ROOT$_gb_path"
		_gb_dest="$_gb_outdir/files$_gb_path"
		mkdir -p "$(dirname "$_gb_dest")" || continue

		if [ -L "$_gb_src" ]; then
			# Never dereferenced (R24.1): the target string is copied as-is,
			# and mode/uid/gid come from `stat` without -L, i.e. the link
			# itself, not what it points to.
			_gb_target=$(readlink "$_gb_src") || continue
			ln -s "$_gb_target" "$_gb_dest" || continue
			_gb_mug=$(stat -c '%a %u %g' "$_gb_src" 2>/dev/null) || _gb_mug='0 0 0'
			# shellcheck disable=SC2086  # word-splitting is the point: unpacking "mode uid gid"
			set -- $_gb_mug
			_gb_collect_entry_symlink "$_gb_path" "$1" "$2" "$3" "$_gb_target" >>"$_gb_entries"
		elif [ -f "$_gb_src" ]; then
			cp "$_gb_src" "$_gb_dest" || continue
			_gb_mug=$(stat -c '%a %u %g' "$_gb_src" 2>/dev/null) || _gb_mug='0 0 0'
			# shellcheck disable=SC2086
			set -- $_gb_mug
			_gb_sha=$(sha256sum "$_gb_dest" 2>/dev/null | awk '{print $1}')
			_gb_collect_entry_file "$_gb_path" "$1" "$2" "$3" "$_gb_sha" >>"$_gb_entries"
		else
			gb_log warning "gb_collect: sysupgrade -l listed '$_gb_path' but it is not there anymore"
		fi
	done
}

# _gb_collect_empty_dirs <outdir> <entries-file>
#
# `sysupgrade -l` never reports a directory (spec: it flattens every source
# through `find ... -type f -o -type l`), so an empty directory anywhere in
# the backup set would silently vanish from the tree and from git, which
# does not store empty directories either. This walks the same sources
# sysupgrade.conf feeds that `find` -- /etc/sysupgrade.conf and every file
# under /lib/upgrade/keep.d/ -- and records, as a `dir` entry, every
# directory under a directory-type line that turns out to have zero
# children. A directory that has children (even only other empty
# directories) is not itself empty and gets no entry of its own: restore
# recreates it implicitly by recreating what it contains.
_gb_collect_empty_dirs() {
	_gb_outdir="$1"
	_gb_entries="$2"
	{
		[ -r "$GB_ROOT/etc/sysupgrade.conf" ] && cat "$GB_ROOT/etc/sysupgrade.conf"
		for _gb_f in "$GB_ROOT/lib/upgrade/keep.d/"*; do
			[ -r "$_gb_f" ] && cat "$_gb_f"
		done
	} 2>/dev/null | while IFS= read -r _gb_line || [ -n "$_gb_line" ]; do
		case "$_gb_line" in
			/*) ;;
			*) continue ;;  # blank, comment, or a relative line -- not a source we can resolve
		esac
		# keep.d lines end directories in "/" (measured on the 25.12.4 stand,
		# e.g. "/etc/config/"); stripped here so `find`'s own top-level match
		# does not echo it back into the manifest path.
		_gb_line="${_gb_line%/}"
		[ -n "$_gb_line" ] && [ -d "$GB_ROOT$_gb_line" ] || continue

		find "$GB_ROOT$_gb_line" -type d 2>/dev/null | while IFS= read -r _gb_realdir; do
			_gb_relpath="${_gb_realdir#"$GB_ROOT"}"
			_gb_collect_is_excluded "$_gb_relpath" && continue
			[ -z "$(find "$_gb_realdir" -mindepth 1 -maxdepth 1 2>/dev/null)" ] || continue
			_gb_mug=$(stat -c '%a %u %g' "$_gb_realdir" 2>/dev/null) || _gb_mug='0 0 0'
			# shellcheck disable=SC2086
			set -- $_gb_mug
			_gb_collect_entry_dir "$_gb_relpath" "$1" "$2" "$3" >>"$_gb_entries"
		done
	done
}

# _gb_collect_meta <outdir> -- the five meta/ files R17-R21 ask for.
_gb_collect_meta() {
	_gb_outdir="$1"

	# board.json: `ubus call system board` (R17), read back by
	# _gb_collect_write_manifest instead of calling ubus a second time.
	ubus call system board 2>/dev/null >"$_gb_outdir/meta/board.json"

	# installed_packages.txt: full "name-version" lines, not bare names --
	# --with-packages (a later ticket) reads names from `apk info` instead
	# (spec, "apk"). R18.
	apk list --installed 2>/dev/null >"$_gb_outdir/meta/installed_packages.txt"

	# repositories.txt: /etc/apk/repositories.d/*, concatenated -- 25.12 has
	# no /etc/apk/repositories at all (measured on stand), so that path is
	# never read. R19.
	: >"$_gb_outdir/meta/repositories.txt"
	for _gb_f in "$GB_ROOT/etc/apk/repositories.d/"*; do
		[ -r "$_gb_f" ] && cat "$_gb_f" >>"$_gb_outdir/meta/repositories.txt"
	done

	# sysupgrade.conf: a copy of the extra-paths file as it stood at
	# collection time (R20).
	if [ -r "$GB_ROOT/etc/sysupgrade.conf" ]; then
		cp "$GB_ROOT/etc/sysupgrade.conf" "$_gb_outdir/meta/sysupgrade.conf"
	else
		: >"$_gb_outdir/meta/sysupgrade.conf"
	fi

	# os-release.txt: a copy of /etc/os-release (R21). Confirmed on the
	# owlab 25.12.4 stand: the file exists and VERSION_ID="25.12.4" is
	# exactly the field manifest.openwrt below reads out of it.
	if [ -r "$GB_ROOT/etc/os-release" ]; then
		cp "$GB_ROOT/etc/os-release" "$_gb_outdir/meta/os-release.txt"
	else
		: >"$_gb_outdir/meta/os-release.txt"
	fi
}

# _gb_collect_write_manifest <outdir> <entries-file>
_gb_collect_write_manifest() {
	_gb_outdir="$1"
	_gb_entries="$2"
	_gb_manifest=$(gb_manifest_path "$_gb_outdir")

	_gb_board=$(cat "$_gb_outdir/meta/board.json" 2>/dev/null)
	_gb_hostname=$(printf '%s' "$_gb_board" | jsonfilter -e '@.hostname' 2>/dev/null)
	_gb_model=$(printf '%s' "$_gb_board" | jsonfilter -e '@.model' 2>/dev/null)
	_gb_openwrt=$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' \
		"$_gb_outdir/meta/os-release.txt" 2>/dev/null | head -n 1)
	_gb_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

	# sort -u both dedupes (an empty directory reachable from two sources in
	# sysupgrade.conf would otherwise get two identical entries) and makes
	# two collections of an unchanged router byte-identical apart from
	# "generated" -- gb_manifest_equal does not depend on this, but it means
	# `diff` on two manifests is actually readable.
	_gb_sorted=$(sort -u "$_gb_entries")

	{
		printf '{\n'
		printf '  "version": "1",\n'
		printf '  "generated": %s,\n' "$(gb_json_str "$_gb_now")"
		printf '  "hostname": %s,\n' "$(gb_json_str "$_gb_hostname")"
		printf '  "device": %s,\n' "$(gb_json_str "${GB_DEVICE:-}")"
		printf '  "openwrt": %s,\n' "$(gb_json_str "$_gb_openwrt")"
		printf '  "board": %s,\n' "$(gb_json_str "$_gb_model")"
		printf '  "entries": [\n'
		_gb_collect_join "$_gb_sorted"
		printf '  ],\n'
		printf '  "scrubbed": [\n'
		# Always empty here: scrub only runs at visibility=public and edits
		# outdir/files in place after gb_collect has already run (ticket 05
		# owns that step and, with it, the entries/scrubbed this manifest
		# needs once scrubbing has happened -- not this function's concern,
		# see collect.sh's own header comment on ownership).
		printf '  ]\n'
		printf '}\n'
	} >"$_gb_manifest"
}

# _gb_collect_join <text> -- <text>'s non-empty lines, each indented 4
# spaces and comma-joined, with no trailing comma on the last one -- the
# shape a JSON array's body needs. <text> is a whole variable, not a file:
# the values it holds already went through sort -u in the one caller that
# exists today.
_gb_collect_join() {
	_gb_first=1
	printf '%s\n' "$1" | while IFS= read -r _gb_line || [ -n "$_gb_line" ]; do
		[ -n "$_gb_line" ] || continue
		if [ "$_gb_first" -eq 1 ]; then _gb_first=0; else printf ',\n'; fi
		printf '    %s' "$_gb_line"
	done
	[ -z "$1" ] || printf '\n'
}

# _gb_collect_json_num <value> -- <value> if it is all digits, else "0".
#
# Guards mode/uid/gid against a failed `stat` leaving them empty: an
# unquoted empty field would make the manifest invalid JSON, and "0" is a
# safe, obviously-wrong value a human reviewing the manifest will notice
# rather than a parser choking on it.
_gb_collect_json_num() {
	case "${1:-}" in
		''|*[!0-9]*) printf '0' ;;
		*) printf '%s' "$1" ;;
	esac
}

# _gb_collect_entry_file <path> <mode> <uid> <gid> <sha256>
_gb_collect_entry_file() {
	printf '{"path":%s,"type":"file","mode":%s,"uid":%s,"gid":%s,"sha256":%s}\n' \
		"$(gb_json_str "$1")" "$(_gb_collect_json_num "$2")" \
		"$(_gb_collect_json_num "$3")" "$(_gb_collect_json_num "$4")" "$(gb_json_str "$5")"
}

# _gb_collect_entry_symlink <path> <mode> <uid> <gid> <target>
_gb_collect_entry_symlink() {
	printf '{"path":%s,"type":"symlink","mode":%s,"uid":%s,"gid":%s,"target":%s}\n' \
		"$(gb_json_str "$1")" "$(_gb_collect_json_num "$2")" \
		"$(_gb_collect_json_num "$3")" "$(_gb_collect_json_num "$4")" "$(gb_json_str "$5")"
}

# _gb_collect_entry_dir <path> <mode> <uid> <gid>
_gb_collect_entry_dir() {
	printf '{"path":%s,"type":"dir","mode":%s,"uid":%s,"gid":%s}\n' \
		"$(gb_json_str "$1")" "$(_gb_collect_json_num "$2")" \
		"$(_gb_collect_json_num "$3")" "$(_gb_collect_json_num "$4")"
}
