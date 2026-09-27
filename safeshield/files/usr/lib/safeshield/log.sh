# shellcheck shell=ash

readonly __DOT__='[.]'
readonly __OK__='\033[0;32m[\xe2\x9c\x93]\033[0m'
readonly _ERROR_='\033[0;31m[ERROR]\033[0m'
readonly _WARNING_='\033[0;33m[WARN]\033[0m'

log_line() {
	[ -z "$ss_verbosity" ] && ss_verbosity="$(uci_get "$PKG_NAME" 'config' 'verbosity' '1')"

	if [ "$#" -gt 1 ]; then
		case "$1" in
			[0-9])
				[ $((ss_verbosity & $1)) -gt 0 ] || return 0
				shift
				;;
		esac
	fi

	local msg="$*"
	local queue="/dev/shm/${PKG_NAME}-output-$$"

	if [ -z "$_out_is_tty" ]; then
		if [ -t 1 ]; then
			_out_is_tty=1
		else
			_out_is_tty=0
		fi
	fi

	[ "$_out_is_tty" -eq 1 ] && printf '%b' "$msg"

	case "$msg" in
		*\\n*)
			if [ -s "$queue" ]; then
				msg="$(cat "$queue")$msg"
				rm -f "$queue"
			fi

			msg="$(printf '%b' "$msg" | sed 's/\x1b\[[0-9;]*m//g')"
			logger -t "$PKG_NAME [$$]" -- "$msg"
			;;
		*)
			printf '%b' "$msg" >>"$queue"
			;;
	esac
}

log_info() {
	log_line 1 "${__DOT__} $*\n"
}

log_ok() {
	log_line 1 "${__OK__} $*\n"
}

log_warn() {
	log_line 1 "${_WARNING_} $*\n"
}

log_error() {
	log_line 1 "${_ERROR_} $*\n"
}
