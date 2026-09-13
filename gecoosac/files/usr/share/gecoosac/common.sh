# Shared path policy for the service, configuration migration and LuCI RPC.

DEFAULT_DB_DIR=/etc/gecoosac
DEFAULT_UPLOAD_DIR=/tmp/gecoosac/upload
DEFAULT_CRT_FILE=/etc/gecoosac/tls/gecoosac.crt
DEFAULT_KEY_FILE=/etc/gecoosac/tls/gecoosac.key
DEFAULT_PID_DIR=/var/run

is_abs_path() {
	case "$1" in
		/*) return 0 ;;
		*) return 1 ;;
	esac
}

normalize_path() {
	local path="$1"
	local part normalized parent

	is_abs_path "$path" || return 1
	normalized="/"
	path="${path#/}"

	while [ -n "$path" ]; do
		part="${path%%/*}"
		if [ "$part" = "$path" ]; then
			path=""
		else
			path="${path#*/}"
		fi

		case "$part" in
			""|.) ;;
			..)
				if [ "$normalized" != "/" ]; then
					parent="${normalized%/*}"
					[ -n "$parent" ] || parent="/"
					normalized="$parent"
				fi
			;;
			*) normalized="${normalized%/}/$part" ;;
		esac
	done

	printf '%s\n' "$normalized"
}

managed_dir_path() {
	local role="$1" path anchor

	case "$role" in
		upload|db|pid|file|tls) ;;
		*) return 1 ;;
	esac
	path="$(normalize_path "$2")" || return 1
	case "$path" in
		/var/run|/var/run/*)
			anchor="$(readlink -f /var/run 2>/dev/null)" || return 1
			[ "$anchor" = "/tmp/run" ] || return 1
			printf '%s%s\n' "$anchor" "${path#/var/run}"
		;;
		/var|/var/*)
			anchor="$(readlink -f /var 2>/dev/null)" || return 1
			case "$anchor" in
				/var|/tmp) printf '%s%s\n' "$anchor" "${path#/var}" ;;
				*) return 1 ;;
			esac
		;;
		*) printf '%s\n' "$path" ;;
	esac
}

path_has_clear_stage_component() {
	local path="$1" part rest

	path="$(normalize_path "$path")" || return 1
	rest="${path#/}"
	while [ -n "$rest" ]; do
		part="${rest%%/*}"
		if [ "$part" = "$rest" ]; then
			rest=""
		else
			rest="${rest#*/}"
		fi
		case "$part" in
			.gecoosac-clear.*) return 0 ;;
		esac
	done

	return 1
}

path_uses_clear_stage() {
	local path="$1" resolved

	path_has_clear_stage_component "$path" && return 0
	if [ -e "$path" ] || [ -L "$path" ]; then
		resolved="$(readlink -f "$path" 2>/dev/null)" || return 1
		path_has_clear_stage_component "$resolved" && return 0
	fi

	return 1
}

is_supported_upload_path() {
	local path="$1" storage

	path="$(normalize_path "$path")" || return 1
	path_uses_clear_stage "$path" && return 1
	[ "$path" = "$DEFAULT_UPLOAD_DIR" ] && return 0

	case "$path" in
		/mnt/*/gecoosac/upload)
			storage="${path#/mnt/}"
			storage="${storage%/gecoosac/upload}"
			[ -n "$storage" ] && [ "${storage#*/}" = "$storage" ]
		;;
		*) return 1 ;;
	esac
}

is_safe_upload_dir() {
	local path physical

	path="$(normalize_path "$1")" || return 1
	physical="$(managed_dir_path upload "$path")" || return 1
	is_supported_upload_path "$path" || return 1
	is_supported_upload_path "$physical"
}

is_path_in_dir() {
	local path root

	path="$(normalize_path "$1")" || return 1
	root="$(normalize_path "$2")" || return 1

	[ "$root" != "/" ] || return 1
	[ "$path" = "$root" ] && return 0
	[ "${path#"$root"/}" != "$path" ]
}

is_secure_dir() {
	local allow_sticky="$2" owner permissions metadata

	[ -d "$1" ] && [ ! -L "$1" ] || return 1
	metadata="$(ls -ldn "$1" 2>/dev/null)" || return 1
	set -- $metadata
	permissions="$1"
	owner="$3"
	[ "$owner" = "0" ] || return 1
	case "$permissions" in
		d?????????) ;;
		*) return 1 ;;
	esac

	if [ "$(printf '%s' "$permissions" | cut -c6)" = "w" ] || \
		[ "$(printf '%s' "$permissions" | cut -c9)" = "w" ]; then
		[ "$allow_sticky" = "1" ] && [ "$(printf '%s' "$permissions" | cut -c10)" = "t" ] || return 1
	fi
}

is_secure_upload_dir() {
	local path current part rest

	path="$(normalize_path "$1")" || return 1
	[ -d "$path" ] && [ ! -L "$path" ] || return 1
	current="/"
	rest="${path#/}"

	while [ -n "$rest" ]; do
		part="${rest%%/*}"
		if [ "$part" = "$rest" ]; then
			rest=""
		else
			rest="${rest#*/}"
		fi
		current="${current%/}/$part"
		case "$current" in
			/tmp) is_secure_dir "$current" 1 || return 1 ;;
			*) is_secure_dir "$current" || return 1 ;;
		esac
	done
}

is_safe_db_dir() {
	local path upload_root physical physical_upload_root

	path="$(normalize_path "$1")" || return 1
	upload_root="$(normalize_path "${2:-$DEFAULT_UPLOAD_DIR}")" || return 1

	case "$path" in
		/etc/gecoosac|/etc/gecoosac/*|/tmp/gecoosac|/tmp/gecoosac/*|/var/lib/gecoosac|/var/lib/gecoosac/*) ;;
		*) return 1 ;;
	esac
	is_path_in_dir "$path" "$upload_root" && return 1
	physical="$(managed_dir_path db "$path")" || return 1
	physical_upload_root="$(managed_dir_path upload "$upload_root")" || return 1
	is_path_in_dir "$physical" "$physical_upload_root" && return 1

	return 0
}

is_safe_pid_dir() {
	local path upload_root physical physical_upload_root

	path="$(normalize_path "$1")" || return 1
	upload_root="$(normalize_path "${2:-$DEFAULT_UPLOAD_DIR}")" || return 1

	case "$path" in
		/var/run|/var/run/*|/tmp/gecoosac|/tmp/gecoosac/*) ;;
		*) return 1 ;;
	esac
	is_path_in_dir "$path" "$upload_root" && return 1
	physical="$(managed_dir_path pid "$path")" || return 1
	physical_upload_root="$(managed_dir_path upload "$upload_root")" || return 1
	is_path_in_dir "$physical" "$physical_upload_root" && return 1

	return 0
}

path_has_mount() {
	local root mount_id parent_id device mount_root mount_path rest

	root="$(normalize_path "$1")" || return 2
	[ -r /proc/self/mountinfo ] || return 2

	while IFS=' ' read -r mount_id parent_id device mount_root mount_path rest; do
		[ -n "$mount_path" ] && [ -n "$rest" ] || return 2
		mount_path="$(printf '%b\n' "$mount_path" 2>/dev/null)" || return 2
		mount_path="$(normalize_path "$mount_path")" || return 2
		is_path_in_dir "$mount_path" "$root" && return 0
	done < /proc/self/mountinfo

	return 1
}

# The checked root must be a resolved, validated directory. Return 0 for a
# protected path, 1 for an unrelated path, or 2 when validation is impossible.
# Keep the original spelling when resolving symlinks: link/../file and its
# lexical normalization can refer to different files.
protected_path_in_dir() {
	local raw_path="$1" role="$2" checked_root="$3"
	local live_logical="${4:-$3}" live_physical="${5:-$3}"
	local path="$1" physical real_path suffix mapped

	[ -n "$path" ] || return 1

	path="$(normalize_path "$path")" || return 2
	physical="$(managed_dir_path "$role" "$path")" || return 2
	checked_root="$(normalize_path "$checked_root")" || return 2
	live_logical="$(normalize_path "$live_logical")" || return 2
	live_physical="$(normalize_path "$live_physical")" || return 2

	is_path_in_dir "$path" "$checked_root" && return 0
	is_path_in_dir "$physical" "$checked_root" && return 0
	real_path="$(readlink -f "$raw_path" 2>/dev/null)" || return 2
	[ -n "$real_path" ] || return 2
	real_path="$(normalize_path "$real_path")" || return 2
	is_path_in_dir "$real_path" "$checked_root" && return 0

	[ "$checked_root" != "$live_physical" ] || {
		is_path_in_dir "$path" "$live_logical" && return 0
		is_path_in_dir "$physical" "$live_physical" && return 0
		if [ -n "$real_path" ] && is_path_in_dir "$real_path" "$live_physical"; then
			return 0
		fi
		return 1
	}

	suffix=
	if is_path_in_dir "$path" "$live_logical"; then
		suffix="${path#"$live_logical"}"
	elif is_path_in_dir "$physical" "$live_physical"; then
		suffix="${physical#"$live_physical"}"
	elif [ -n "$real_path" ] && is_path_in_dir "$real_path" "$live_physical"; then
		suffix="${real_path#"$live_physical"}"
	else
		return 1
	fi
	mapped="${checked_root%/}${suffix}"
	[ -e "$mapped" ] || [ -L "$mapped" ]
}
