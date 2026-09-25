# shellcheck shell=sh
#
# gitbackup -- secret redaction: gb_scrub. Needs lib.sh. Works only on the
# collected copy, never the live config. Whether to run is the CLI's call
# (GB_SCRUB); whole-file secrets are excluded by collect.sh instead.

GB_SCRUB_LIST="${GB_SCRUB_LIST:-${GB_SHARE:-/usr/share/gitbackup}/scrub.list}"

# Fixed placeholder, no hash: a short PSK is brute-forceable from its hash.
GB_SCRUB_PLACEHOLDER='<gitbackup:redacted>'

# gb_scrub <outdir> -- redacts via `uci -c ... -t <savedir>`, never sed
# (multi-line lists break line-based edits silently), re-hashes, fills
# scrubbed[], prints "<path>\t<option>" per redacted option.
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

	[ -d "$_gb_confdir" ] && _gb_scrub_options "$_gb_confdir" "$_gb_scratch"

	cat "$_gb_scratch/records"

	[ -r "$_gb_manifest" ] && _gb_scrub_write_manifest "$_gb_manifest" \
		"$_gb_scratch/records" "$_gb_scratch/rehash"

	rm -rf "$_gb_scratch"
}

# Grouped by config, so each file is shown and committed once.
_gb_scrub_options() {
	_gb_confdir="$1"
	_gb_scratch="$2"
	_gb_savedir="$_gb_scratch/save"

	# sort -u: the shipped scrub_option default duplicates a scrub.list line.
	_gb_scrub_load_patterns | sort -u >"$_gb_scratch/patterns"
	[ -s "$_gb_scratch/patterns" ] || return 0

	_gb_configs=$(awk '{print $1}' "$_gb_scratch/patterns" | sort -u)
	for _gb_cfg in $_gb_configs; do
		[ -f "$_gb_confdir/$_gb_cfg" ] || continue

		_gb_sections="$_gb_scratch/sections.$_gb_cfg"
		: >"$_gb_sections"
		# Section declarations only ("cfg.ref=type" -> ref TAB type); option
		# lines have a second dot.
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
				# Unquoted: a trailing "*" prefix-matches (wireguard_<ifname>).
				# shellcheck disable=SC2254
				case "$_gb_type" in
					$_gb_ptype) ;;
					*) continue ;;
				esac
				_gb_path="$_gb_cfg.$_gb_ref.$_gb_popt"
				# `uci set` on a missing option would create it.
				uci -c "$_gb_confdir" get "$_gb_path" >/dev/null 2>&1 || continue
				uci -c "$_gb_confdir" -t "$_gb_savedir" set \
					"$_gb_path=$GB_SCRUB_PLACEHOLDER" >/dev/null 2>&1 || continue
				printf '/etc/config/%s\t%s\n' "$_gb_cfg" "$_gb_path" >>"$_gb_scratch/records"
				: >"$_gb_touched"
			done <"$_gb_sections"
		done <"$_gb_scratch/patterns"

		if [ -f "$_gb_touched" ]; then
			# -t, not -P: -P also sets no-commit, so commit would silently
			# no-op. -t keeps set/commit on a private savedir, off /tmp/.uci.
			uci -c "$_gb_confdir" -t "$_gb_savedir" commit "$_gb_cfg" >/dev/null 2>&1
			_gb_sha=$(sha256sum "$_gb_confdir/$_gb_cfg" 2>/dev/null | awk '{print $1}')
			[ -n "$_gb_sha" ] && printf '/etc/config/%s\t%s\n' "$_gb_cfg" "$_gb_sha" >>"$_gb_scratch/rehash"
		fi
	done
}

# scrub.list plus gitbackup.security.scrub_option (space-joined UCI list).
_gb_scrub_load_patterns() {
	if [ -r "$GB_SCRUB_LIST" ]; then
		while IFS= read -r _gb_l || [ -n "$_gb_l" ]; do
			_gb_scrub_parse_pattern "$_gb_l"
		done <"$GB_SCRUB_LIST"
	fi
	# noglob: "[*]" is a valid glob bracket expression.
	# shellcheck disable=SC2046  # word-splitting is the point: one pattern per word
	set -f
	for _gb_p in $(gb_uci_get gitbackup.security.scrub_option); do
		_gb_scrub_parse_pattern "$_gb_p"
	done
	set +f
}

# "<config>.@<type>[*].<option>" -> "<config> <type> <option>"; anything
# unrecognized warns, never a guessed result.
_gb_scrub_parse_pattern() {
	_gb_raw="${1%%#*}"
	# noglob: "[*]" would otherwise pathname-expand.
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

# Never a value or hash in the manifest.
_gb_scrub_records_json() {
	[ -s "$1" ] || return 0
	while IFS='	' read -r _gb_rp _gb_ro || [ -n "$_gb_rp" ]; do
		[ -n "$_gb_rp" ] || continue
		printf '{"path":%s,"option":%s}\n' "$(gb_json_str "$_gb_rp")" "$(gb_json_str "$_gb_ro")"
	done <"$1"
}

# _gb_scrub_write_manifest <manifest.json> <records> <rehash> -- relies on our
# own manifest having one entry per line.
_gb_scrub_write_manifest() {
	_gb_tmp="$1.tmp.$$"
	_gb_scrub_records_json "$2" | gb_manifest_join >"$_gb_tmp.scrubbed"
	cp "$1" "$_gb_tmp"
	while IFS='	' read -r _gb_rp _gb_rs || [ -n "$_gb_rp" ]; do
		[ -n "$_gb_rp" ] || continue
		_gb_needle="\"path\":$(gb_json_str "$_gb_rp"),"
		awk -v n="$_gb_needle" -v sha="$_gb_rs" '
			index($0, n) { sub(/"sha256":"[^"]*"/, "\"sha256\":\"" sha "\"") } { print }
		' "$_gb_tmp" >"$_gb_tmp.new" && mv "$_gb_tmp.new" "$_gb_tmp"
	done <"$3"
	awk -v f="$_gb_tmp.scrubbed" '
		{ print }
		/^  "scrubbed": \[/ { while ((getline l < f) > 0) print l }
	' "$_gb_tmp" >"$1"
	rm -f "$_gb_tmp" "$_gb_tmp.scrubbed"
}
