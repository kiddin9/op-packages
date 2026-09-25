# shellcheck shell=sh
#
# gitbackup -- backup-set collection: gb_collect, gb_manifest_path,
# gb_manifest_equal. Needs lib.sh; reads GB_DEVICE and GB_SCRUB set by the CLI.

GB_ROOT="${GB_ROOT:-}"
GB_EXCLUDE_LIST="${GB_EXCLUDE_LIST:-${GB_SHARE:-/usr/share/gitbackup}/exclude.list}"

gb_manifest_path() {
	printf '%s/manifest.json\n' "$1"
}

# Only entries[] and scrubbed[]: "generated" and host metadata would
# otherwise produce a commit every run.
gb_manifest_equal() {
	[ -r "$1" ] && [ -r "$2" ] || return 1
	[ "$(gb_manifest_tail "$1")" = "$(gb_manifest_tail "$2")" ]
}

# gb_collect <outdir> -- outdir/files, meta/, manifest.json. The path list is
# `sysupgrade -l` only; sources are walked just for empty dirs.
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

_gb_collect_is_excluded() {
	# Canonical: case globs are textual. Own variable name: callers loop over
	# _gb_path and sh has no locals.
	_gb_ie_path=$(gb_path_canon "$1")
	[ -r "$GB_EXCLUDE_LIST" ] || return 1
	while IFS= read -r _gb_pat || [ -n "$_gb_pat" ]; do
		case "$_gb_pat" in
			# Whole-file secrets: excluded only when this run scrubs.
			'#public: '*)
				[ "$(gb_json_bool "${GB_SCRUB:-0}")" = true ] || continue
				_gb_pat="${_gb_pat#'#public: '}"
				;;
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

# Pipe subshell: state goes to <entries-file>, not variables.
_gb_collect_files() {
	_gb_outdir="$1"
	_gb_entries="$2"
	sysupgrade -l 2>/dev/null | while IFS= read -r _gb_path || [ -n "$_gb_path" ]; do
		[ -n "$_gb_path" ] || continue
		_gb_path=$(gb_path_canon "$_gb_path")
		_gb_collect_is_excluded "$_gb_path" && continue

		_gb_src="$GB_ROOT$_gb_path"
		_gb_dest="$_gb_outdir/files$_gb_path"
		mkdir -p "$(dirname "$_gb_dest")" || continue

		if [ -L "$_gb_src" ]; then
			# Never dereferenced: stat without -L reports the link itself.
			_gb_target=$(readlink "$_gb_src") || continue
			ln -s "$_gb_target" "$_gb_dest" || continue
			_gb_mug=$(stat -c '%a %u %g' "$_gb_src" 2>/dev/null) || _gb_mug='0 0 0'
			# shellcheck disable=SC2086  # word-splitting is the point: unpacking "mode uid gid"
			set -- $_gb_mug
			_gb_collect_entry symlink "$_gb_path" "$1" "$2" "$3" target "$_gb_target" >>"$_gb_entries"
		elif [ -f "$_gb_src" ]; then
			cp "$_gb_src" "$_gb_dest" || continue
			_gb_mug=$(stat -c '%a %u %g' "$_gb_src" 2>/dev/null) || _gb_mug='0 0 0'
			# shellcheck disable=SC2086
			set -- $_gb_mug
			_gb_sha=$(sha256sum "$_gb_dest" 2>/dev/null | awk '{print $1}')
			_gb_collect_entry file "$_gb_path" "$1" "$2" "$3" sha256 "$_gb_sha" >>"$_gb_entries"
		else
			gb_log warning "gb_collect: sysupgrade -l listed '$_gb_path' but it is not there anymore"
		fi
	done
}

# `sysupgrade -l` never lists directories and git stores none, so empty dirs
# get explicit `dir` entries.
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
		# keep.d lines end directories in "/"; strip it.
		_gb_line="${_gb_line%/}"
		[ -n "$_gb_line" ] && [ -d "$GB_ROOT$_gb_line" ] || continue

		find "$GB_ROOT$_gb_line" -type d 2>/dev/null | while IFS= read -r _gb_realdir; do
			_gb_relpath="${_gb_realdir#"$GB_ROOT"}"
			_gb_collect_is_excluded "$_gb_relpath" && continue
			[ -z "$(find "$_gb_realdir" -mindepth 1 -maxdepth 1 2>/dev/null)" ] || continue
			_gb_mug=$(stat -c '%a %u %g' "$_gb_realdir" 2>/dev/null) || _gb_mug='0 0 0'
			# shellcheck disable=SC2086
			set -- $_gb_mug
			_gb_collect_entry dir "$_gb_relpath" "$1" "$2" "$3" >>"$_gb_entries"
		done
	done
}

_gb_collect_meta() {
	_gb_outdir="$1"

	ubus call system board 2>/dev/null >"$_gb_outdir/meta/board.json"

	apk list --installed 2>/dev/null >"$_gb_outdir/meta/installed_packages.txt"

	# 25.12 has no /etc/apk/repositories, only repositories.d/*.
	: >"$_gb_outdir/meta/repositories.txt"
	for _gb_f in "$GB_ROOT/etc/apk/repositories.d/"*; do
		[ -r "$_gb_f" ] && cat "$_gb_f" >>"$_gb_outdir/meta/repositories.txt"
	done

	if [ -r "$GB_ROOT/etc/sysupgrade.conf" ]; then
		cp "$GB_ROOT/etc/sysupgrade.conf" "$_gb_outdir/meta/sysupgrade.conf"
	else
		: >"$_gb_outdir/meta/sysupgrade.conf"
	fi

	if [ -r "$GB_ROOT/etc/os-release" ]; then
		cp "$GB_ROOT/etc/os-release" "$_gb_outdir/meta/os-release.txt"
	else
		: >"$_gb_outdir/meta/os-release.txt"
	fi
}

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

	# Stable order across runs.
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
		printf '%s\n' "$_gb_sorted" | gb_manifest_join
		printf '  ],\n'
		printf '  "scrubbed": [\n'
		# Filled later by gb_scrub.
		printf '  ]\n'
		printf '}\n'
	} >"$_gb_manifest"
}

# A failed stat must not produce invalid JSON.
_gb_collect_json_num() {
	case "${1:-}" in
		''|*[!0-9]*) printf '0' ;;
		*) printf '%s' "$1" ;;
	esac
}

# _gb_collect_entry <type> <path> <mode> <uid> <gid> [<key> <value>]
_gb_collect_entry() {
	printf '{"path":%s,"type":"%s","mode":%s,"uid":%s,"gid":%s%s}\n' \
		"$(gb_json_str "$2")" "$1" "$(_gb_collect_json_num "$3")" \
		"$(_gb_collect_json_num "$4")" "$(_gb_collect_json_num "$5")" \
		"${6:+,\"$6\":$(gb_json_str "$7")}"
}
