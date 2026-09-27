# shellcheck shell=ash

readonly LOCK_FD=309
readonly RUNNING_STATUS_LOCK="/var/lock/${PKG_NAME}.lock"
readonly RUNNING_STATUS_FILE="/dev/shm/${PKG_NAME}.status.json"

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

ss_mask_secret() {
	local value="$1"
	local len

	[ -n "$value" ] || {
		printf '%s' ''
		return 0
	}

	len="${#value}"
	if [ "$len" -le 8 ] 2>/dev/null; then
		printf '%s' '********'
	else
		printf '%s****%s' "${value%${value#????}}" "${value#${value%????}}"
	fi
}

is_valid_integer() {
	case "$1" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -ge 0 ] 2>/dev/null
}

is_greater_equal() {
	[ "$#" -eq 2 ] || return 2
	[ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

json_lock_open() {
	mkdir -p "${RUNNING_STATUS_LOCK%/*}" || return 1
	eval "exec ${LOCK_FD}>\"${RUNNING_STATUS_LOCK}\"" || return 1
	flock -x "${LOCK_FD}" || {
		eval "exec ${LOCK_FD}>&-"
		return 1
	}
}

json_lock_close() {
	flock -u "${LOCK_FD}" 2>/dev/null || true
	eval "exec ${LOCK_FD}>&-" 2>/dev/null || true
}

_json_init_data_object() {
	mkdir -p "${RUNNING_STATUS_FILE%/*}" || return 1

	if ! json_load_file "$RUNNING_STATUS_FILE" 2>/dev/null; then
		json_init
	fi

	json_select data 2>/dev/null || {
		json_add_object data
		json_close_object
		json_select data 2>/dev/null
	}
}

_json_get() {
	local key="$1"
	local out=''

	json_get_var out "$key" 2>/dev/null || true
	printf '%s' "$out"
}

_json_set() {
	local key="$1"
	local value="$2"

	json_add_string "$key" "$value"
	json_select .. 2>/dev/null || true
	json_dump >"${RUNNING_STATUS_FILE}"
}

_json_add_message() {
	local kind="$1"
	local value="$2"
	local arr="${kind}s"

	json_select .. 2>/dev/null || true
	json_select "$arr" 2>/dev/null || {
		json_add_array "$arr"
		json_close_array
		json_select "$arr" 2>/dev/null || return 1
	}

	json_add_object ""
	json_add_string code "$value"
	json_add_string info "$value"
	json_close_object
	json_select .. 2>/dev/null || true
	json_dump >"${RUNNING_STATUS_FILE}"
}

json() {
	local action="$1"
	local key="$2"
	shift 2 2>/dev/null
	local value="$*"
	local rc=0

	json_lock_open || return 1

	_json_init_data_object || rc=1

	if [ "$rc" -eq 0 ]; then
		case "${action}:${key}" in
			get:*)
				_json_get "$key" || rc=1
				;;
			set:*)
				_json_set "$key" "$value" || rc=1
				;;
			add:error | add:warning)
				_json_add_message "$key" "$value" || rc=1
				;;
			*)
				rc=1
				;;
		esac
	fi

	json_cleanup 2>/dev/null || true
	json_lock_close

	return "$rc"
}
