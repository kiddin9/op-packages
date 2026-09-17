# shellcheck shell=sh
#
# gitbackup -- secret redaction for visibility=public (spec "Scrub").
#
# Exposes gb_scrub; every _gb_scrub_-prefixed helper below is private,
# namespaced the same way collect.sh explains its own helpers are (every
# *.sh here ends up sourced into one process by usr/sbin/gitbackup, so a
# same-named helper in a sibling module would silently shadow this one
# otherwise). Sourced, never executed: nothing here runs at load time --
# t_scrub_no_side_effect_on_source in tests/run.sh asserts this directly by
# sourcing the module over a tree that still has its secrets and checking
# nothing changed.
#
# Depends on lib.sh (gb_log, gb_json_str, gb_uci_get, gb_manifest_field) already being sourced
# by the caller, same convention every other module here uses. Does NOT
# depend on collect.sh: gb_scrub computes manifest.json's path itself
# (outdir/manifest.json, the one fixed shape gb_collect ever writes) rather
# than calling collect.sh's gb_manifest_path, so this module has no load-order
# requirement on it and the two stay testable apart.
#
# Who calls this and when is not this module's concern (spec: "Только при
# visibility=public, где он принудителен" is a decision usr/sbin/gitbackup's
# gb_validate_config/_gb_effective_scrub already makes and exposes as
# GB_SCRUB -- see tests/run.sh's t_cli_public_forces_scrub). gb_scrub itself
# has no opinion on visibility and no config lookup for whether to run: it
# scrubs whatever tree it is given, unconditionally, the same way gb_collect
# has no opinion on what to do with the tree it builds.
#
# GB_SCRUB_LIST/GB_EXCLUDE_LIST override where the static pattern files live
# (defaulting under GB_SHARE, same convention collect.sh's GB_EXCLUDE_LIST
# uses) so tests/run.sh can point this at a fixture instead of the real
# package data. Neither is set by the router.

GB_SCRUB_LIST="${GB_SCRUB_LIST:-${GB_SHARE:-/usr/share/gitbackup}/scrub.list}"
GB_EXCLUDE_LIST="${GB_EXCLUDE_LIST:-${GB_SHARE:-/usr/share/gitbackup}/exclude.list}"

# The placeholder every redacted value becomes. No hash: spec "Scrub" --
# "Хеша не остаётся: короткий PSK по хешу подбирается, и хеш сам по себе
# был бы утечкой." A fixed constant, not overridable -- unlike the two
# above, there is no legitimate reason a caller would want a different one.
GB_SCRUB_PLACEHOLDER='<gitbackup:redacted>'

# gb_scrub <outdir>
#
# Mutates outdir/files/etc/config/* in place via `uci -c`, never sed (spec:
# "многострочные list ломают любой построчный разбор, и молча"), removes the
# files exclude.list's public-only block names entirely, rewrites
# outdir/manifest.json's scrubbed[] array and re-hashes/drops the affected
# entries[] lines, and prints one "<path>\t<uci-option-path>" line per
# redacted option to stdout for the caller's own logging. A tree with no
# etc/config directory at all (a stripped-down fixture, or a router with
# nothing there) is a no-op, not an error.
gb_scrub() {
	_gb_outdir="$1"
	[ -n "$_gb_outdir" ] || { gb_log err 'gb_scrub: outdir is required'; return 1; }
	_gb_confdir="$_gb_outdir/files/etc/config"
	_gb_manifest="$_gb_outdir/manifest.json"

	_gb_scratch=$(mktemp -d "${TMPDIR:-/tmp}/gitbackup-scrub.XXXXXX") || return 1
	_gb_savedir="$_gb_scratch/save"
	mkdir -p "$_gb_savedir"
	: >"$_gb_scratch/records"
	: >"$_gb_scratch/rehash"
	: >"$_gb_scratch/removed"

	[ -d "$_gb_confdir" ] && _gb_scrub_options "$_gb_confdir" "$_gb_scratch"
	_gb_scrub_hard_exclude "$_gb_outdir" "$_gb_scratch"

	cat "$_gb_scratch/records"

	[ -r "$_gb_manifest" ] && _gb_scrub_write_manifest "$_gb_manifest" \
		"$_gb_scratch/records" "$_gb_scratch/rehash" "$_gb_scratch/removed"

	rm -rf "$_gb_scratch"
}

# _gb_scrub_options <confdir> <scratch> -- the UCI-editing half of gb_scrub.
# Walks scrub.list (+ the UCI-configurable list scrub_option) grouped by
# config file, so each touched file is `uci show`n and committed exactly
# once regardless of how many patterns target it.
_gb_scrub_options() {
	_gb_confdir="$1"
	_gb_scratch="$2"
	_gb_savedir="$_gb_scratch/save"

	# sort -u: gitbackup.security's own shipped default
	# (list scrub_option 'wireless.@wifi-iface[*].key', ticket 01) is the
	# same line scrub.list already carries -- found live on the owlab
	# stand, where an unfiltered run redacted the one real option correctly
	# but printed and recorded it twice. One pattern, one record, however
	# many sources agreed on it.
	_gb_scrub_load_patterns | sort -u >"$_gb_scratch/patterns"
	[ -s "$_gb_scratch/patterns" ] || return 0

	_gb_configs=$(awk '{print $1}' "$_gb_scratch/patterns" | sort -u)
	for _gb_cfg in $_gb_configs; do
		[ -f "$_gb_confdir/$_gb_cfg" ] || continue

		_gb_sections="$_gb_scratch/sections.$_gb_cfg"
		: >"$_gb_sections"
		# One line per section DECLARATION ("cfg.ref=type"), ref TAB type.
		# A declaration line has exactly one dot after the config name; an
		# option line ("cfg.ref.option=value") has two, so the ".*" guard
		# tells them apart without needing to know option names in advance.
		uci -c "$_gb_confdir" show "$_gb_cfg" 2>/dev/null | \
		while IFS= read -r _gb_l; do
			case "$_gb_l" in
				"$_gb_cfg".*=*)
					_gb_rest=${_gb_l#"$_gb_cfg".}
					case "$_gb_rest" in
						*.*) continue ;;
					esac
					printf '%s\t%s\n' "${_gb_rest%%=*}" "${_gb_rest#*=}" >>"$_gb_sections"
					;;
			esac
		done

		_gb_touched="$_gb_scratch/touched.$_gb_cfg"
		rm -f "$_gb_touched"

		while IFS=' ' read -r _gb_pc _gb_ptype _gb_popt; do
			[ "$_gb_pc" = "$_gb_cfg" ] || continue
			while IFS='	' read -r _gb_ref _gb_type; do
				[ -n "$_gb_ref" ] || continue
				# Unquoted on the right on purpose: a scrub.list type may end
				# in "*" to prefix-match a dynamically-named type family
				# (WireGuard peers, "wireguard_<ifname>") -- see scrub.list's
				# own header. A plain type name has no glob metacharacters,
				# so this is an exact match for every pattern that is not
				# using the prefix form.
				# shellcheck disable=SC2254
				case "$_gb_type" in
					$_gb_ptype) ;;
					*) continue ;;
				esac
				_gb_path="$_gb_cfg.$_gb_ref.$_gb_popt"
				# Existence check first: `uci set` on a nonexistent option
				# CREATES it (verified against openwrt/uci's list.c uci_set,
				# the "!ptr->o && ptr->option" branch), and fabricating an
				# option the user never set is not this module's job to do,
				# ever -- scrub redacts what is there, it does not invent
				# config the restored router would then apply.
				uci -c "$_gb_confdir" get "$_gb_path" >/dev/null 2>&1 || continue
				uci -c "$_gb_confdir" -t "$_gb_savedir" set \
					"$_gb_path=$GB_SCRUB_PLACEHOLDER" >/dev/null 2>&1 || continue
				printf '/etc/config/%s\t%s\n' "$_gb_cfg" "$_gb_path" >>"$_gb_scratch/records"
				: >"$_gb_touched"
			done <"$_gb_sections"
		done <"$_gb_scratch/patterns"

		if [ -f "$_gb_touched" ]; then
			# -t, not -P: -P also sets CLI_FLAG_NOCOMMIT (verified live on
			# the owlab stand -- a `commit` issued with -P silently no-ops,
			# ret=0, file untouched), which would make this commit do
			# nothing. -t sets the same custom save directory without that
			# flag, so `set` and `commit` agree on where the pending delta
			# lives without ever touching the router's own default savedir
			# (/tmp/.uci) -- needed since two gb_scrub calls (or two test
			# cases) touching a config of the same name must not collide
			# through a savedir keyed only by that name.
			uci -c "$_gb_confdir" -t "$_gb_savedir" commit "$_gb_cfg" >/dev/null 2>&1
			_gb_sha=$(sha256sum "$_gb_confdir/$_gb_cfg" 2>/dev/null | awk '{print $1}')
			[ -n "$_gb_sha" ] && printf '/etc/config/%s\t%s\n' "$_gb_cfg" "$_gb_sha" >>"$_gb_scratch/rehash"
		fi
	done
}

# _gb_scrub_load_patterns -- prints "config type option" (space separated)
# for every recognized scrub.list line plus every gitbackup.security's list
# scrub_option entry, same format, spec "Расширяется через list scrub_option
# в UCI". gb_uci_get (lib.sh) already returns a UCI list option's values
# space-joined on one line -- the same shape `uci get` itself prints -- so
# splitting it with a plain for loop needs no extra parsing.
_gb_scrub_load_patterns() {
	if [ -r "$GB_SCRUB_LIST" ]; then
		while IFS= read -r _gb_l || [ -n "$_gb_l" ]; do
			_gb_scrub_parse_pattern "$_gb_l"
		done <"$GB_SCRUB_LIST"
	fi
	# set -f: same reasoning as _gb_scrub_parse_pattern's own -- a pattern's
	# "[*]" is a valid glob bracket expression, so splitting this on words
	# must not also pathname-expand it.
	# shellcheck disable=SC2046  # word-splitting is the point: one pattern per word
	set -f
	for _gb_p in $(gb_uci_get gitbackup.security.scrub_option); do
		_gb_scrub_parse_pattern "$_gb_p"
	done
	set +f
}

# _gb_scrub_parse_pattern <line> -- parses one "<config>.@<type>[*].<option>"
# line (comment and surrounding blanks already allowed in <line>) and prints
# "<config> <type> <option>", or nothing for a blank/comment-only line, or a
# warning (never a partial/guessed result) for anything else.
_gb_scrub_parse_pattern() {
	_gb_raw="${1%%#*}"
	# set -f: a pattern's own "[*]" wildcard marker is a syntactically valid
	# glob bracket expression (matches one literal "*"), so plain word
	# splitting here could also pathname-expand against the working
	# directory -- the exact live bug _gb_scrub_hard_exclude's own comment
	# describes, guarded against here for the same reason even though no
	# fixture has hit it yet.
	set -f
	# shellcheck disable=SC2086  # word-splitting trims surrounding blanks; a pattern itself has none
	set -- $_gb_raw
	set +f
	_gb_raw="${1:-}"
	[ -n "$_gb_raw" ] || return 0

	_gb_cfg="${_gb_raw%%.*}"
	_gb_rest="${_gb_raw#*.}"
	case "$_gb_rest" in
		'@'*'[*].'*)
			_gb_type="${_gb_rest#@}"
			_gb_type="${_gb_type%%\[\*\]*}"
			_gb_opt="${_gb_rest##*\].}"
			printf '%s %s %s\n' "$_gb_cfg" "$_gb_type" "$_gb_opt"
			;;
		*)
			gb_log warning "gitbackup scrub: unrecognized scrub.list pattern '$_gb_raw', ignored"
			;;
	esac
}

# _gb_scrub_hard_exclude <outdir> <scratch> -- removes exclude.list's
# public-only lines (every "#public: <pattern>" line -- a plain comment to
# collect.sh, see exclude.list's own header on why) from outdir/files,
# recording each removed absolute path (one per line, matching
# manifest.json's own path format) to scratch/removed so
# _gb_scrub_write_manifest drops it from entries[] too. Same glob rules as
# collect.sh's own hard-exclude ("/**" suffix = itself and everything under
# it, else a plain case/shell glob) -- reimplemented here rather than
# calling collect.sh's private _gb_collect_is_excluded, which is not this
# module's to reach into (see this file's header on cross-module coupling).
_gb_scrub_hard_exclude() {
	_gb_outdir="$1"
	_gb_scratch="$2"
	_gb_files="$_gb_outdir/files"
	[ -r "$GB_EXCLUDE_LIST" ] || return 0
	while IFS= read -r _gb_pat || [ -n "$_gb_pat" ]; do
		case "$_gb_pat" in
			'#public:'*) _gb_pat="${_gb_pat#'#public:'}" ;;
			*) continue ;;
		esac
		# set -f around this: found live on the owlab stand -- with globbing
		# on, this bare `set --` doesn't just trim the mandatory space after
		# "#public:", it pathname-expands the pattern against the CURRENT
		# working directory right then, and an absolute pattern like
		# "/etc/dropbear/*_host_key*" glob-matches the ROUTER'S OWN real
		# /etc/dropbear -- not outdir/files -- silently replacing the
		# pattern with whatever real host keys exist on the box running the
		# test. The intended glob (against "$_gb_files$_gb_pat" below) never
		# ran on the right string, and the real host key was never removed.
		set -f
		# shellcheck disable=SC2086
		set -- $_gb_pat
		set +f
		_gb_pat="${1:-}"
		[ -n "$_gb_pat" ] || continue
		case "$_gb_pat" in
			*/'**')
				_gb_prefix=${_gb_pat%/\*\*}
				find "$_gb_files$_gb_prefix" -mindepth 0 2>/dev/null | \
				while IFS= read -r _gb_found; do
					_gb_relpath="${_gb_found#"$_gb_files"}"
					printf '%s\n' "$_gb_relpath" >>"$_gb_scratch/removed"
				done
				rm -rf "${_gb_files:?}$_gb_prefix"
				;;
			*)
				# Unquoted glob on purpose: real filesystem expansion against
				# outdir/files is exactly what a hard-exclude pattern like
				# "/etc/dropbear/*_host_key*" needs. No match leaves the
				# literal pattern string, which -e then rejects -- ash and
				# every POSIX sh here run with nullglob off, same as a bare
				# `for f in *.nosuchext` on an empty match.
				# shellcheck disable=SC2086,SC2231
				for _gb_found in "$_gb_files"$_gb_pat; do
					[ -e "$_gb_found" ] || continue
					_gb_relpath="${_gb_found#"$_gb_files"}"
					printf '%s\n' "$_gb_relpath" >>"$_gb_scratch/removed"
					rm -f "$_gb_found"
				done
				;;
		esac
	done <"$GB_EXCLUDE_LIST"
}

# _gb_scrub_join -- reads raw (unindented, comma-free) object-body lines on
# stdin and writes them 4-space-indented and comma-joined (no trailing comma
# on the last one), the exact array-body shape collect.sh's own
# _gb_collect_join produces -- reimplemented locally rather than called
# (collect.sh's version is private to it, see this file's header). Empty
# input produces empty output, matching what collect.sh itself writes for an
# empty array.
_gb_scrub_join() {
	_gb_first=1
	while IFS= read -r _gb_b || [ -n "$_gb_b" ]; do
		[ -n "$_gb_b" ] || continue
		if [ "$_gb_first" -eq 1 ]; then _gb_first=0; else printf ',\n'; fi
		printf '    %s' "$_gb_b"
	done
	[ "$_gb_first" -eq 1 ] || printf '\n'
}

# _gb_scrub_records_json <records> -- <records> is "<path>\t<option>" lines;
# prints one {"path":...,"option":...} object per line. No value and no hash
# ever appears here (spec: "значений в нём нет") -- only the two fields the
# records file itself carries.
_gb_scrub_records_json() {
	[ -s "$1" ] || return 0
	while IFS='	' read -r _gb_rp _gb_ro || [ -n "$_gb_rp" ]; do
		[ -n "$_gb_rp" ] || continue
		printf '{"path":%s,"option":%s}\n' "$(gb_json_str "$_gb_rp")" "$(gb_json_str "$_gb_ro")"
	done <"$1"
}

# _gb_scrub_write_manifest <manifest.json> <records> <rehash> <removed>
#
# Line-oriented, same technique collect.sh's own gb_manifest_equal already
# relies on (gb_collect emits exactly one JSON object per array item, no
# nested newlines) -- this is editing gitbackup's OWN manifest format, not
# UCI config text, so the "no sed on multi-line list" rule this module
# exists for does not apply to it. Rewrites entries[] (dropping the paths in
# <removed>, re-hashing the ones in <rehash>) and scrubbed[] (built fresh
# from <records>) in one pass; everything else in the file is copied
# unchanged.
_gb_scrub_write_manifest() {
	_gb_manifest="$1"
	_gb_records="$2"
	_gb_rehash="$3"
	_gb_removed="$4"
	_gb_tmp="$_gb_manifest.tmp.$$"
	_gb_ent="$_gb_manifest.entries.$$"
	: >"$_gb_tmp"
	: >"$_gb_ent"
	_gb_in_entries=0
	_gb_in_scrubbed=0

	while IFS= read -r _gb_line || [ -n "$_gb_line" ]; do
		if [ "$_gb_in_entries" -eq 1 ]; then
			case "$_gb_line" in
				'  ],')
					_gb_scrub_join <"$_gb_ent" >>"$_gb_tmp"
					printf '%s\n' "$_gb_line" >>"$_gb_tmp"
					_gb_in_entries=0
					;;
				*)
					# Strip the trailing "," (absent only on the last item)
					# and the fixed 4-space indent collect.sh always writes,
					# so _gb_scrub_join can re-add both consistently once the
					# surviving set is known.
					_gb_obj="${_gb_line%,}"
					_gb_obj="${_gb_obj#    }"
					_gb_p=$(gb_manifest_field "$_gb_obj" path)
					if [ -s "$_gb_removed" ] && grep -qxF "$_gb_p" "$_gb_removed"; then
						: # dropped -- hard-excluded, no longer in the tree
					else
						_gb_newsha=''
						if [ -s "$_gb_rehash" ]; then
							_gb_newsha=$(awk -F'\t' -v p="$_gb_p" '$1==p{print $2; exit}' "$_gb_rehash")
						fi
						if [ -n "$_gb_newsha" ]; then
							_gb_obj=$(printf '%s' "$_gb_obj" | sed 's/"sha256":"[^"]*"/"sha256":"'"$_gb_newsha"'"/')
						fi
						printf '%s\n' "$_gb_obj" >>"$_gb_ent"
					fi
					;;
			esac
			continue
		fi

		case "$_gb_line" in
			'  "entries": ['*)
				printf '%s\n' "$_gb_line" >>"$_gb_tmp"
				_gb_in_entries=1
				continue
				;;
			'  "scrubbed": ['*)
				printf '%s\n' "$_gb_line" >>"$_gb_tmp"
				_gb_scrub_records_json "$_gb_records" | _gb_scrub_join >>"$_gb_tmp"
				_gb_in_scrubbed=1
				continue
				;;
			'  ]')
				[ "$_gb_in_scrubbed" -eq 1 ] && _gb_in_scrubbed=0
				;;
		esac
		printf '%s\n' "$_gb_line" >>"$_gb_tmp"
	done <"$_gb_manifest"

	rm -f "$_gb_ent"
	mv "$_gb_tmp" "$_gb_manifest"
}
