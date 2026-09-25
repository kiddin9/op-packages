# shellcheck shell=sh
#
# gitbackup -- shared primitives: gb_log, gb_die, gb_uci_get, gb_path_canon,
# gb_json_esc/str/bool, gb_manifest_field/tail/each/join, gb_free_kb,
# gb_have_net, gb_subst_device, gb_join_lines.
#
# No side effects at load time. _gb_ prefix instead of `local` (not POSIX).

# gb_log <syslog-level> <message>... -- syslog is the log (`gitbackup log`
# reads it back with logread).
gb_log() {
	_gb_level="$1"
	shift
	logger -t gitbackup -p "daemon.$_gb_level" -- "$*" 2>/dev/null
	case "$_gb_level" in
		notice|warning|err) printf '%s: %s\n' "$_gb_level" "$*" >&2 ;;
	esac
}

# gb_die <exit-code> <message>...
# Exit codes: 0 ok, 1 general error, 2 invalid config, 3 network/auth, 4 refused for safety.
gb_die() {
	_gb_code="$1"
	shift
	gb_log err "$*"
	exit "$_gb_code"
}

# gb_uci_get <config.section.option> [default] -- empty yields the default
# too: LuCI writes `option x ''` for a cleared field.
gb_uci_get() {
	_gb_value=$(uci -q get "$1") || _gb_value=''
	[ -n "$_gb_value" ] || _gb_value="${2-}"
	printf '%s\n' "$_gb_value"
}

# gb_path_canon <path> -- lexical canonical spelling (no realpath on the
# image; readlink -f would follow symlinks, which are backed up as symlinks).
# Exclusion checks are textual `case` matches: without this "//etc/gitbackup"
# slips past them and the deploy key and token get pushed.
gb_path_canon() {
	_gb_pc_rest="${1-}"
	case "$_gb_pc_rest" in
		/*) ;;
		*) printf '%s\n' "$_gb_pc_rest"; return 0 ;;
	esac

	_gb_pc_out=''
	while [ -n "$_gb_pc_rest" ]; do
		_gb_pc_comp="${_gb_pc_rest%%/*}"
		case "$_gb_pc_rest" in
			*/*) _gb_pc_rest="${_gb_pc_rest#*/}" ;;
			*) _gb_pc_rest='' ;;
		esac
		case "$_gb_pc_comp" in
			''|.) ;;
			..) _gb_pc_out="${_gb_pc_out%/*}" ;;
			*) _gb_pc_out="$_gb_pc_out/$_gb_pc_comp" ;;
		esac
	done

	printf '%s\n' "${_gb_pc_out:-/}"
}

# The base image has no JSON writer; only ", \, newline, tab and CR can reach us.
gb_json_esc() {
	_gb_rest="${1-}"
	_gb_out=''
	_gb_nl='
'
	_gb_tab=$(printf '\t')
	_gb_cr=$(printf '\r')
	while [ -n "$_gb_rest" ]; do
		_gb_ch="${_gb_rest%"${_gb_rest#?}"}"
		_gb_rest="${_gb_rest#?}"
		# shellcheck disable=SC1003  # the '\' branch matches a literal backslash, not an escaped quote
		case "$_gb_ch" in
			'"') _gb_out="$_gb_out\\\"" ;;
			'\') _gb_out="$_gb_out\\\\" ;;
			"$_gb_nl") _gb_out="$_gb_out\\n" ;;
			"$_gb_tab") _gb_out="$_gb_out\\t" ;;
			"$_gb_cr") _gb_out="$_gb_out\\r" ;;
			*) _gb_out="$_gb_out$_gb_ch" ;;
		esac
	done
	printf '%s' "$_gb_out"
}

# Quoted JSON string, or null when empty.
gb_json_str() {
	if [ -z "${1-}" ]; then
		printf 'null'
	else
		printf '"%s"' "$(gb_json_esc "$1")"
	fi
}

gb_json_bool() {
	case "${1-}" in
		1|on|true|yes|enabled) printf 'true' ;;
		*) printf 'false' ;;
	esac
}

# gb_manifest_field <object> <field> -- one single-line manifest item; empty
# when absent or null. Walks char by char so an escaped \" inside a path does
# not end the value early.
gb_manifest_field() {
	_gb_mf_obj="$1"
	_gb_mf_field="$2"
	case "$_gb_mf_obj" in
		*'"'"$_gb_mf_field"'":"'*)
			_gb_mf_rest="${_gb_mf_obj#*\""$_gb_mf_field"\":\"}"
			_gb_mf_v=''
			_gb_mf_bs=0
			while [ -n "$_gb_mf_rest" ]; do
				_gb_mf_ch="${_gb_mf_rest%"${_gb_mf_rest#?}"}"
				_gb_mf_rest="${_gb_mf_rest#?}"
				if [ "$_gb_mf_bs" -eq 1 ]; then
					_gb_mf_v="$_gb_mf_v$_gb_mf_ch"
					_gb_mf_bs=0
					continue
				fi
				# shellcheck disable=SC1003  # the '\' branch matches a literal backslash, not an escaped quote
				case "$_gb_mf_ch" in
					'\') _gb_mf_bs=1 ;;
					'"') break ;;
					*) _gb_mf_v="$_gb_mf_v$_gb_mf_ch" ;;
				esac
			done
			printf '%s' "$_gb_mf_v"
			;;
		*'"'"$_gb_mf_field"'":'*)
			_gb_mf_v="${_gb_mf_obj#*\""$_gb_mf_field"\":}"
			_gb_mf_v="${_gb_mf_v%%[,\}]*}"
			[ "$_gb_mf_v" = null ] && _gb_mf_v=''
			printf '%s' "$_gb_mf_v"
			;;
		*) printf '' ;;
	esac
}

# gb_manifest_tail <manifest.json> [section] -- section key to EOF. Relies on
# gb_collect keeping "entries" and "scrubbed" last, so comparing tails
# ignores "generated".
gb_manifest_tail() {
	sed -n '/^  "'"${2:-entries}"'": \[/,$p' "$1"
}

# gb_manifest_each <manifest.json> <section> <callback> -- one call per item.
# Redirect, not a pipe, so the callback's globals survive the loop.
gb_manifest_each() {
	_gb_me_manifest="$1"
	_gb_me_section="$2"
	_gb_me_cb="$3"
	_gb_me_in=0
	while IFS= read -r _gb_me_line || [ -n "$_gb_me_line" ]; do
		case "$_gb_me_line" in
			'  "'"$_gb_me_section"'": ['*) _gb_me_in=1; continue ;;
			'  ],' | '  ]')
				[ "$_gb_me_in" -eq 1 ] && _gb_me_in=0
				continue
				;;
		esac
		[ "$_gb_me_in" -eq 1 ] || continue
		_gb_me_obj="${_gb_me_line%,}"
		_gb_me_obj="${_gb_me_obj#    }"
		[ -n "$_gb_me_obj" ] || continue
		"$_gb_me_cb" "$_gb_me_obj"
	done <"$_gb_me_manifest"
}

# -P keeps long device names from wrapping onto their own line.
gb_free_kb() {
	df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}'
}

# gb_have_net <host> [port] -- TCP connect within ~5s. busybox nc takes no
# -w/-z and there is no `timeout`, so nc's pid is polled. No `sleep; kill`
# watchdog: its orphaned sleep kept run's flock fd open after exit.
gb_have_net() {
	_gb_hn_host="$1"
	_gb_hn_port="${2:-443}"
	nc "$_gb_hn_host" "$_gb_hn_port" </dev/null >/dev/null 2>&1 &
	_gb_hn_pid=$!
	_gb_hn_waited=0
	while kill -0 "$_gb_hn_pid" 2>/dev/null; do
		if [ "$_gb_hn_waited" -ge 5 ]; then
			kill "$_gb_hn_pid" 2>/dev/null
			wait "$_gb_hn_pid" 2>/dev/null
			return 1
		fi
		sleep 1
		_gb_hn_waited=$((_gb_hn_waited + 1))
	done
	wait "$_gb_hn_pid" 2>/dev/null
	return $?
}

# Device comes from the caller: restore has no device_id config yet.
gb_subst_device() {
	_gb_sd_out=''
	_gb_sd_rest="$1"
	while true; do
		case "$_gb_sd_rest" in
			*'{device}'*)
				_gb_sd_out="$_gb_sd_out${_gb_sd_rest%%\{device\}*}$2"
				_gb_sd_rest="${_gb_sd_rest#*\{device\}}"
				;;
			*)
				printf '%s\n' "$_gb_sd_out$_gb_sd_rest"
				return 0
				;;
		esac
	done
}

gb_join_lines() {
	awk -v sep="$1" '$0 != "" { printf "%s%s", s, $0; s = sep }'
}

# stdin lines as a manifest JSON array body.
gb_manifest_join() {
	grep . | sed 's/^/    /; $!s/$/,/'
}
