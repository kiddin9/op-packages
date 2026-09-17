# shellcheck shell=sh
#
# gitbackup -- primitives shared by every module.
#
# Sourced, never executed: defining functions is all this file does, so a test
# can pull it in and call one function without a router underneath it.
#
# Variables are prefixed _gb_ instead of being declared `local`, because
# `local` is not in POSIX sh; busybox ash has it, the shells this suite also
# runs under do not all agree, and the prefix costs nothing.
#
# Nothing here runs at load time: sourcing this file defines functions and
# touches nothing else, which is what makes it testable off the router.

# gb_log <level> <message>...
#
# level is a syslog level -- debug, info, notice, warning, err -- so it can be
# handed to logger unchanged. Syslog is the log, because `gitbackup log` reads
# it back with logread and nothing else survives a reboot on a read-only root.
gb_log() {
	_gb_level="$1"
	shift
	logger -t gitbackup -p "daemon.$_gb_level" -- "$*" 2>/dev/null
	# Anything the operator has to act on also goes to stderr: a CLI run by
	# hand that answers only into syslog looks like it did nothing.
	case "$_gb_level" in
		notice|warning|err) printf '%s: %s\n' "$_gb_level" "$*" >&2 ;;
	esac
}

# gb_die <exit-code> <message>...
#
# Exit codes are the contract of the whole package: 0 ok, 1 general error,
# 2 invalid configuration, 3 network or authentication, 4 refused for safety.
gb_die() {
	_gb_code="$1"
	shift
	gb_log err "$*"
	exit "$_gb_code"
}

# gb_uci_get <config.section.option> [default]
#
# An unset option and an empty one are the same answer here on purpose: UCI
# writes `option x ''` for a field the user cleared in LuCI, and every caller
# wants the default in both cases.
gb_uci_get() {
	_gb_value=$(uci -q get "$1") || _gb_value=''
	[ -n "$_gb_value" ] || _gb_value="${2-}"
	printf '%s\n' "$_gb_value"
}

# gb_path_canon <path>
#
# Prints <path> in its one canonical spelling: repeated slashes collapsed,
# "." components dropped, ".." components resolved lexically, no trailing
# slash. A relative path is printed back unchanged -- there is nothing to
# resolve it against here, and every caller checks for absoluteness itself.
#
# Lexical, not filesystem-resolving: no realpath(1) on the base image, and
# `readlink -f` would additionally follow symlinks, which is exactly what
# this package must NOT do to a backup path (collect.sh's R24.1 -- a
# symlink is backed up as a symlink, never dereferenced).
#
# This exists because two separate decisions in this package are made by
# matching a path against a fixed pattern -- gb_paths_validate's blacklist
# and collect.sh's _gb_collect_is_excluded -- and `case` glob matching is
# purely textual. "/etc/gitbackup", "//etc/gitbackup", "/etc/./gitbackup"
# and "/etc/../etc/gitbackup" name the same directory to the kernel and to
# find(1), but only the first one matches a "/etc/gitbackup*" pattern. The
# package's own exclude.list calls its exclusion of that directory
# unconditional ("must never end up inside its own backup, no matter how
# the router is configured", R76); without canonicalization it was not,
# and an entry spelled "//etc/gitbackup" pushed the deploy private key and
# the git token into the very repository they authenticate to.
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

# gb_json_esc <string>
#
# Escapes a string for use inside JSON double quotes. Written out rather than
# delegated because the base image has no JSON writer, and "just interpolate
# it" breaks on the first quote in a path -- which is exactly the input this
# package handles.
#
# Only the five characters that can actually reach us are escaped: the values
# are UCI options, filesystem paths and error messages. A NUL cannot survive a
# shell variable in the first place.
gb_json_esc() {
	_gb_rest="${1-}"
	_gb_out=''
	_gb_nl='
'
	_gb_tab=$(printf '\t')
	_gb_cr=$(printf '\r')
	while [ -n "$_gb_rest" ]; do
		# The first character: strip everything after it, then strip it.
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

# gb_json_str <string>  -- an escaped, quoted JSON string, or null when empty.
gb_json_str() {
	if [ -z "${1-}" ]; then
		printf 'null'
	else
		printf '"%s"' "$(gb_json_esc "$1")"
	fi
}

# gb_json_bool <value>  -- true when the value is a UCI-style truth, else false.
gb_json_bool() {
	case "${1-}" in
		1|on|true|yes|enabled) printf 'true' ;;
		*) printf 'false' ;;
	esac
}

# gb_manifest_field <object> <field>
#
# <object> is one manifest.json array item -- exactly one line, no nested
# brackets, the shape gb_collect (collect.sh) writes and gb_manifest_each
# (below) hands to its own callback. Prints <field>'s value: unescaped and
# unquoted for a JSON string (gb_json_esc above is the only writer, and it
# only ever emits "\"" and "\\" for a filesystem path or symlink target --
# newlines/tabs/CR do not occur in either), or the raw text up to the next
# "," or "}" for a bare (numeric) field. Empty when the field is absent, or
# JSON null -- gb_json_str's own bare-word encoding of an empty string
# (above), which no caller here ever wants to see as the literal text
# "null".
#
# One reader for what used to be three (ticket 18): collect.sh compared
# whole manifests with a hand-rolled sed tail (gb_manifest_tail, below, is
# what that became), restore.sh had two near-identical field extractors of
# its own (a quoted-string one and a bare-numeric one), and scrub.sh
# reached for "path" with one more copy of the same parameter-expansion
# pair, unescaped. Same review finding, same fix, in one place instead of
# three that could each drift the moment the manifest format ever does.
#
# The quoted-string branch walks the value one character at a time instead
# of cutting at the first literal '"' with a parameter-expansion pattern:
# `${v%%\"*}` (the consolidation's first shape, inherited from ticket 08's
# _gb_restore_json_str) stops at the FIRST quote character in the string
# with no regard for whether a backslash precedes it, so a path containing
# a literal quote -- which gb_json_esc above escapes as `\"`, and which
# sysupgrade places no restriction against (only whitespace in a path is
# unsupported) -- truncates there instead of at its own closing quote. The
# writer can produce `\"`; the reader must be able to consume it. Walking
# character by character and tracking "the previous character was an
# unescaped backslash" finds the real closing quote and un-escapes `\"`/`\\`
# in the same pass, so the trailing `sed` cleanup this branch used to need
# is gone -- there is nothing left for it to fix up.
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
					# Whatever follows a backslash is emitted as itself:
					# gb_json_esc only ever escapes '"' and '\' into a
					# manifest string field, so this covers both cases
					# without needing to special-case which one it was.
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

# gb_manifest_tail <manifest.json> [section]
#
# Everything from '  "<section>": [' (default "entries") onward, i.e. that
# key's own array plus every key written after it, to end of file. Relies
# on gb_collect's fixed layout (collect.sh): "entries" and "scrubbed" are
# always the last two top-level keys, one object per line, so this one sed
# range captures both without a JSON parser this image does not have.
# gb_manifest_equal (collect.sh) is the one caller: comparing this tail
# between two manifests is exactly comparing entries[] and scrubbed[]
# together (spec: "generated не участвует в сравнении манифестов").
gb_manifest_tail() {
	sed -n '/^  "'"${2:-entries}"'": \[/,$p' "$1"
}

# gb_manifest_each <manifest.json> <section> <callback>
#
# Calls "<callback> <object>" once per <section>'s array item (e.g.
# "entries" or "scrubbed"), <object> already unindented and with its
# trailing comma (present on every item but the last) stripped -- the
# shape gb_manifest_field expects. Reads the file via a plain redirect, not
# a pipe: POSIX sh only forks a subshell for the pipe form, so a callback's
# own global-variable accumulation (no `local` anywhere in this codebase)
# survives the loop here.
#
# A section's own closing line is either '  ],' (something else follows it
# in the object, e.g. "entries" with "scrubbed" after) or '  ]' (it is the
# last key, e.g. "scrubbed" itself); both are accepted regardless of which
# section was asked for, because the two sections never overlap and each
# one's own opening line is what starts the count in the first place.
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

# gb_free_kb <directory>  -- free kilobytes on the filesystem holding it.
#
# -P because the default df output wraps long device names onto their own line
# and the awk below would then read the wrong row.
gb_free_kb() {
	df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}'
}

# gb_have_net <host> [port]
#
# True when a TCP connection opens. There is no curl in the base image, and
# -- D01, measured live on the owlab 25.12.4 stand -- this image's busybox
# nc (v1.37.0) is not the usual BSD/GNU nc at all: `nc --help` prints
# "Usage: nc [IPADDR PORT]" and nothing else. No `-w`, no `-z`, no flags of
# any kind; `nc -w 5 host port` (this function's previous body) prints that
# same usage banner and exits 1 for every host, reachable or not, which is
# exactly the bug ticket 01 flagged as D01 and interfaces.md warned every
# later module off relying on. The fix is simply never passing nc a flag it
# does not have: `nc host port` alone is accepted, connects, and exits 0/1
# correctly -- confirmed live for a real open port, a closed one (ECONNREFUSED)
# and a bad hostname.
#
# The remaining problem a flag-free nc leaves is a *hang*: an address that
# is filtered rather than refused (no RST, no reply at all) leaves a bare
# `nc host port` blocked on the kernel's own TCP connect timeout, which is
# well over a minute -- unacceptable for a check `run` is supposed to fail
# out of quickly. There is no `timeout` applet either (confirmed: absent
# from `busybox --list` and no separate binary on the stand), so the bound
# is hand-rolled by POLLING, not by a second background "watchdog" job that
# kills nc after 5s: an earlier version of this function did exactly that
# (`( sleep 5; kill $ncpid ) & watchpid=$!; ...; kill $watchpid`), and it
# leaked a process every time nc finished BEFORE the 5s elapsed (the common
# case) -- found live on the owlab stand, not in any unit test: killing the
# watchdog SUBSHELL does not kill the plain `sleep 5` still running inside
# it, which is a separate child process with its own pid; that orphaned
# sleep keeps running for whatever time was left, still holding every file
# descriptor it inherited at the moment it was forked -- including, when
# `run`'s own step 1 flock (fd 9 on /var/run/gitbackup.lock) was already
# held at the time gb_have_net was called, the lock file itself. Confirmed
# live: calling `run` twice back to back after a fast, successful
# gb_have_net check left the SECOND call seeing the lock as still busy for
# up to ~5s, purely from the first call's orphaned watchdog sleep -- despite
# the first `run` process having already exited outright. Polling for nc's
# own pid to disappear (`kill -0`, no signal sent, just an existence check)
# needs no second process at all, so there is nothing left over to leak.
# Measured live: an address that never answers (192.0.2.1, a TEST-NET-1
# address routed nowhere) returns in ~5s instead of hanging; a real open
# port and a real closed port both still return in well under a second.
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
