# shellcheck shell=sh
#
# gitbackup -- restore: gb_restore. Needs lib.sh and gitio.sh; GB_URL from
# the environment. Applies manifest mode/uid/gid/symlinks, which git does not
# store: a plain checkout would leave /etc/shadow world-readable. Not
# `sysupgrade -r`, which is not atomic. The device comes from the argument (a
# bare router has no device_id yet): gb_subst_device, never gb_expand.
#
# VERIFY: Path 0 (LuCI upload -> stock `sysupgrade -r`) is not this code and
# was never clicked through.

GB_ROOT="${GB_ROOT:-}"

# gb_restore <device> <commit-or-empty> [--dry-run] [--force] [--yes] [--with-packages]
# Returns 0 ok, 1 failure, 2 bad argument, 3 network/auth, 4 refused (board
# mismatch without --force, or an unusable manifest).
gb_restore() {
	_gb_device="$1"
	_gb_commit="${2:-}"
	shift 2

	_gb_dry=0
	_gb_force=0
	_gb_yes=0
	_gb_wp=0
	for _gb_flag in "$@"; do
		case "$_gb_flag" in
			--dry-run) _gb_dry=1 ;;
			--force) _gb_force=1 ;;
			--yes) _gb_yes=1 ;;
			--with-packages) _gb_wp=1 ;;
		esac
	done

	[ -n "$_gb_device" ] || { gb_log err 'gb_restore: device is required'; return 2; }
	: "${GB_URL:?gb_restore: GB_URL is not set}"

	_gb_branch=$(gb_subst_device "$(gb_uci_get gitbackup.origin.branch 'device/{device}')" "$_gb_device")
	_gb_prefix=$(gb_subst_device "$(gb_uci_get gitbackup.main.path_prefix 'devices/{device}')" "$_gb_device")

	# Under /tmp, never flash.
	_gb_work=$(mktemp -d "${TMPDIR:-/tmp}/gitbackup-restore.XXXXXX") ||
		{ gb_log err 'gb_restore: cannot create a work directory under /tmp'; return 1; }
	trap 'rm -rf "$_gb_work"' EXIT INT TERM
	_gb_repodir="$_gb_work/repo"

	if [ -z "$_gb_commit" ] || [ "$_gb_commit" = HEAD ]; then
		_gb_tip=$(gb_remote_head "$_gb_branch")
		_gb_tip_rc=$?
		[ "$_gb_tip_rc" -eq 0 ] || return 3
		if [ -z "$_gb_tip" ]; then
			gb_log err "gb_restore: $_gb_branch does not exist on $GB_URL yet -- nothing to restore"
			return 1
		fi
		gb_fetch_meta "$_gb_branch" "$_gb_repodir" || return 3
		_gb_target="$_gb_tip"
	else
		# A past commit needs full branch history (still one branch).
		gb_fetch_meta "$_gb_branch" "$_gb_repodir" '' || return 3
		_gb_target="$_gb_commit"
	fi

	if ! git -C "$_gb_repodir" cat-file -e "$_gb_target^{commit}" 2>/dev/null; then
		gb_log err "gb_restore: commit $_gb_target was not found on $_gb_branch at $GB_URL"
		return 1
	fi

	# Pathspec checkout lazily fetches just these blobs (promisor remote).
	_gb_co_err=$(git -C "$_gb_repodir" checkout -q "$_gb_target" -- "$_gb_prefix" 2>&1)
	_gb_co_rc=$?
	if [ "$_gb_co_rc" -ne 0 ] || [ ! -d "$_gb_repodir/$_gb_prefix" ]; then
		gb_log err "gb_restore: could not read $_gb_prefix from $_gb_target on $_gb_branch: $_gb_co_err"
		return 1
	fi

	_gb_srcroot="$_gb_repodir/$_gb_prefix"
	_gb_manifest="$_gb_srcroot/manifest.json"
	if [ ! -r "$_gb_manifest" ]; then
		gb_log err "gb_restore: $_gb_prefix/manifest.json missing at $_gb_target -- nothing to restore"
		return 1
	fi

	# The manifest comes from the remote and is untrusted: validate every
	# field before it picks a destination or becomes chmod/chown argv.
	_gb_restore_check_entries "$_gb_manifest" || {
		gb_log err "gb_restore: $_gb_prefix/manifest.json at $_gb_target has unusable entries, nothing was written:$_gb_entries_bad"
		return 4
	}

	_gb_restore_check_board "$_gb_srcroot/meta/board.json" "$_gb_force"
	_gb_board_rc=$?
	[ "$_gb_board_rc" -eq 0 ] || return "$_gb_board_rc"

	_gb_restore_check_release "$_gb_srcroot/meta/os-release.txt"

	# Not one byte is written until every file's sha256 is proven.
	_gb_restore_verify_sha "$_gb_srcroot/files" "$_gb_manifest" || return 1

	# Unreplaceable paths are skipped and reported instead of failing in cp
	# with busybox's misleading "File exists".
	_gb_restore_check_writable "$_gb_manifest"

	if [ "$_gb_dry" -eq 1 ]; then
		_gb_restore_print_plan "$_gb_manifest"
		return 0
	fi

	if [ "$_gb_yes" -ne 1 ]; then
		_gb_restore_print_plan "$_gb_manifest" >&2
		printf 'Restore %s from %s onto this router? [y/N] ' "$_gb_device" "$_gb_target" >&2
		IFS= read -r _gb_ans
		case "$_gb_ans" in
			y|Y|yes|YES) ;;
			*) gb_log notice 'gb_restore: declined by the operator'; return 1 ;;
		esac
	fi

	_gb_restore_write_files "$_gb_srcroot/files" "$_gb_manifest"
	_gb_write_rc=$?

	# Always apply perms, even after a partial write: otherwise /etc/shadow
	# could stay world-readable.
	_gb_restore_apply_perms "$_gb_manifest"

	_gb_restore_print_scrubbed "$_gb_manifest"

	[ "$_gb_wp" -eq 1 ] && _gb_restore_packages "$_gb_srcroot/meta"

	if [ "$_gb_write_rc" -ne 0 ]; then
		gb_log err "gb_restore: the following paths were NOT written:$_gb_write_bad"
		printf 'restore of %s from %s finished, but some paths were NOT written -- see above for which and why\n' \
			"$_gb_device" "$_gb_target" >&2
		return 1
	fi

	gb_log notice "gb_restore: restored $_gb_device from $_gb_target on $_gb_branch"
	printf 'restored %s from %s\n' "$_gb_device" "$_gb_target"
	return 0
}

# "model" is absent on generic/armsr; "release.target" catches
# generic-to-generic hardware changes.
_gb_restore_check_board() {
	_gb_old_board="$1"
	_gb_force="$2"
	if [ ! -r "$_gb_old_board" ]; then
		gb_log warning 'gb_restore: no meta/board.json in this backup, skipping the board check'
		return 0
	fi
	_gb_old_json=$(cat "$_gb_old_board")
	_gb_new_json=$(ubus call system board 2>/dev/null)
	_gb_old_model=$(printf '%s' "$_gb_old_json" | jsonfilter -e '@.model' 2>/dev/null)
	_gb_new_model=$(printf '%s' "$_gb_new_json" | jsonfilter -e '@.model' 2>/dev/null)
	_gb_old_target=$(printf '%s' "$_gb_old_json" | jsonfilter -e '@.release.target' 2>/dev/null)
	_gb_new_target=$(printf '%s' "$_gb_new_json" | jsonfilter -e '@.release.target' 2>/dev/null)

	if [ "$_gb_old_model" = "$_gb_new_model" ] && [ "$_gb_old_target" = "$_gb_new_target" ]; then
		return 0
	fi
	if [ "$_gb_force" -eq 1 ]; then
		gb_log notice "gb_restore: board mismatch (model '$_gb_old_model' -> '$_gb_new_model', target '$_gb_old_target' -> '$_gb_new_target'), proceeding: --force"
		return 0
	fi
	gb_log err "gb_restore: this backup was taken on a different board (model '$_gb_old_model' vs '$_gb_new_model', target '$_gb_old_target' vs '$_gb_new_target') -- interface names and wireless radios from that hardware will not match this one; pass --force to restore anyway"
	return 4
}

# Major-version mismatch warns only. The backup is untrusted: VERSION_ID is
# read with sed, the file is never sourced.
_gb_restore_check_release() {
	_gb_old_rel="$1"
	[ -r "$_gb_old_rel" ] || return 0
	_gb_old_ver=$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$_gb_old_rel" | head -n 1)
	_gb_new_ver=''
	[ -r "${GB_ROOT:-}/etc/os-release" ] &&
		_gb_new_ver=$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${GB_ROOT:-}/etc/os-release" | head -n 1)
	[ -n "$_gb_old_ver" ] && [ -n "$_gb_new_ver" ] || return 0
	_gb_old_major="${_gb_old_ver%%.*}"
	_gb_new_major="${_gb_new_ver%%.*}"
	if [ "$_gb_old_major" != "$_gb_new_major" ]; then
		gb_log warning "gb_restore: this backup was taken on OpenWrt $_gb_old_ver, this router runs $_gb_new_ver -- config options from a different major release may not apply cleanly"
	fi
	return 0
}

# Hard gate: any mismatch refuses the whole restore.
_gb_restore_verify_sha() {
	_gb_srcfiles="$1"
	_gb_manifest="$2"
	_gb_sha_bad=''
	gb_manifest_each "$_gb_manifest" entries _gb_restore_verify_sha_one
	if [ -n "$_gb_sha_bad" ]; then
		gb_log err "gb_restore: sha256 mismatch, refusing to write anything to disk:$_gb_sha_bad"
		return 1
	fi
	return 0
}

_gb_restore_verify_sha_one() {
	_gb_obj="$1"
	case "$_gb_obj" in
		*'"type":"file"'*) ;;
		*) return 0 ;;
	esac
	_gb_path=$(gb_manifest_field "$_gb_obj" path)
	_gb_want=$(gb_manifest_field "$_gb_obj" sha256)
	_gb_got=$(sha256sum "$_gb_srcfiles$_gb_path" 2>/dev/null | awk '{print $1}')
	[ -n "$_gb_got" ] && [ "$_gb_got" = "$_gb_want" ] || _gb_sha_bad="$_gb_sha_bad $_gb_path"
}

# Offenders go to _gb_entries_bad. No path allowlist: restoring the set
# wherever it lived is the point.
_gb_restore_check_entries() {
	_gb_manifest="$1"
	_gb_entries_bad=''
	gb_manifest_each "$_gb_manifest" entries _gb_restore_check_entries_one
	[ -z "$_gb_entries_bad" ]
}

_gb_restore_entry_reject() {
	_gb_entries_bad="$_gb_entries_bad
  $1: $2"
}

_gb_restore_check_entries_one() {
	_gb_obj="$1"
	_gb_ce_path=$(gb_manifest_field "$_gb_obj" path)
	_gb_ce_type=$(gb_manifest_field "$_gb_obj" type)
	_gb_ce_mode=$(gb_manifest_field "$_gb_obj" mode)
	_gb_ce_uid=$(gb_manifest_field "$_gb_obj" uid)
	_gb_ce_gid=$(gb_manifest_field "$_gb_obj" gid)

	_gb_ce_shown="$_gb_ce_path"
	[ -n "$_gb_ce_shown" ] || _gb_ce_shown='(entry with no path)'

	case "$_gb_ce_path" in
		/*) ;;
		*)
			_gb_restore_entry_reject "$_gb_ce_shown" 'not an absolute path'
			return 0
			;;
	esac

	if [ "$(gb_path_canon "$_gb_ce_path")" != "$_gb_ce_path" ]; then
		_gb_restore_entry_reject "$_gb_ce_shown" 'not a canonical path'
		return 0
	fi

	case "$_gb_ce_type" in
		file | dir | symlink) ;;
		*)
			_gb_restore_entry_reject "$_gb_ce_shown" "unknown entry type '$_gb_ce_type'"
			return 0
			;;
	esac

	if [ -n "$_gb_ce_mode" ]; then
		case "$_gb_ce_mode" in
			[0-7][0-7][0-7] | [0-7][0-7][0-7][0-7]) ;;
			*)
				_gb_restore_entry_reject "$_gb_ce_shown" "mode '$_gb_ce_mode' is not 3 or 4 octal digits"
				return 0
				;;
		esac
	fi

	for _gb_ce_id in "$_gb_ce_uid" "$_gb_ce_gid"; do
		[ -n "$_gb_ce_id" ] || continue
		case "$_gb_ce_id" in
			*[!0-9]*)
				_gb_restore_entry_reject "$_gb_ce_shown" "owner id '$_gb_ce_id' is not numeric"
				return 0
				;;
		esac
	done
}

# Sets _gb_precheck_bad: unwritable directory (read-only mount too), or the
# path is its own mount point (e.g. a bind mount over /etc/hosts).
_gb_restore_check_writable() {
	_gb_manifest="$1"
	_gb_precheck_bad=''
	gb_manifest_each "$_gb_manifest" entries _gb_restore_check_writable_one
}

_gb_restore_check_writable_one() {
	_gb_obj="$1"
	case "$_gb_obj" in
		*'"type":"file"'*) ;;
		*) return 0 ;;
	esac
	_gb_path=$(gb_manifest_field "$_gb_obj" path)
	_gb_dest="${GB_ROOT:-}$_gb_path"
	[ -e "$_gb_dest" ] || return 0
	_gb_wdir=$(dirname "$_gb_dest")

	if [ ! -w "$_gb_wdir" ]; then
		_gb_precheck_bad="$_gb_precheck_bad $_gb_path"
		return 0
	fi

	_gb_dest_dev=$(stat -c %d "$_gb_dest" 2>/dev/null)
	_gb_wdir_dev=$(stat -c %d "$_gb_wdir" 2>/dev/null)
	if [ -n "$_gb_dest_dev" ] && [ -n "$_gb_wdir_dev" ] && [ "$_gb_dest_dev" != "$_gb_wdir_dev" ]; then
		_gb_precheck_bad="$_gb_precheck_bad $_gb_path"
	fi
}

_gb_restore_print_plan() {
	_gb_manifest="$1"
	printf 'The following paths will be written:\n'
	gb_manifest_each "$_gb_manifest" entries _gb_restore_plan_one
}

_gb_restore_plan_one() {
	_gb_obj="$1"
	_gb_type=$(gb_manifest_field "$_gb_obj" type)
	_gb_path=$(gb_manifest_field "$_gb_obj" path)
	_gb_dest="${GB_ROOT:-}$_gb_path"
	if [ -e "$_gb_dest" ] || [ -L "$_gb_dest" ]; then
		printf '  overwrite %s (%s)\n' "$_gb_path" "$_gb_type"
	else
		printf '  create    %s (%s)\n' "$_gb_path" "$_gb_type"
	fi
}

# Pass 1, content only; failures collect in _gb_write_bad.
_gb_restore_write_files() {
	_gb_srcfiles="$1"
	_gb_manifest="$2"
	_gb_write_bad=''
	gb_manifest_each "$_gb_manifest" entries _gb_restore_write_one
	[ -z "$_gb_write_bad" ]
}

_gb_restore_write_one() {
	_gb_obj="$1"
	case "$_gb_obj" in
		*'"type":"file"'*) ;;
		*) return 0 ;;
	esac
	_gb_path=$(gb_manifest_field "$_gb_obj" path)

	case " $_gb_precheck_bad " in
		*" $_gb_path "*)
			_gb_write_bad="$_gb_write_bad
  $_gb_path: destination cannot be replaced (not writable, or a distinct mount point sits exactly on this path) -- skipped, not attempted"
			return 0
			;;
	esac

	_gb_dest="${GB_ROOT:-}$_gb_path"
	_gb_mkdir_err=$(mkdir -p "$(dirname "$_gb_dest")" 2>&1) || {
		_gb_write_bad="$_gb_write_bad
  $_gb_path: $_gb_mkdir_err"
		return 0
	}
	# Never write through a symlink: cp -f follows it to a path the manifest
	# never named.
	[ -L "$_gb_dest" ] && rm -f "$_gb_dest" 2>/dev/null
	# -f: busybox cp refuses an existing destination without it.
	_gb_cp_err=$(cp -f "$_gb_srcfiles$_gb_path" "$_gb_dest" 2>&1) || {
		_gb_write_bad="$_gb_write_bad
  $_gb_path: $_gb_cp_err"
		return 0
	}
}

# Pass 2: mode/uid/gid, empty dirs, symlinks.
_gb_restore_apply_perms() {
	_gb_manifest="$1"
	gb_manifest_each "$_gb_manifest" entries _gb_restore_perm_one
}

_gb_restore_perm_one() {
	_gb_obj="$1"
	_gb_type=$(gb_manifest_field "$_gb_obj" type)
	_gb_path=$(gb_manifest_field "$_gb_obj" path)
	_gb_mode=$(gb_manifest_field "$_gb_obj" mode)
	_gb_uid=$(gb_manifest_field "$_gb_obj" uid)
	_gb_gid=$(gb_manifest_field "$_gb_obj" gid)
	_gb_dest="${GB_ROOT:-}$_gb_path"

	case "$_gb_type" in
		dir)
			mkdir -p "$_gb_dest" 2>/dev/null
			[ -n "$_gb_mode" ] && chmod "$_gb_mode" "$_gb_dest" 2>/dev/null
			[ -n "$_gb_uid" ] && [ -n "$_gb_gid" ] && chown "$_gb_uid:$_gb_gid" "$_gb_dest" 2>/dev/null
			;;
		symlink)
			# Not _gb_target: gb_restore keeps the commit sha there (no locals).
			_gb_symtarget=$(gb_manifest_field "$_gb_obj" target)
			mkdir -p "$(dirname "$_gb_dest")" 2>/dev/null
			rm -f "$_gb_dest" 2>/dev/null
			ln -s -- "$_gb_symtarget" "$_gb_dest" 2>/dev/null
			# -h: chown the link itself, not a possibly dangling target. No
			# chmod: Linux symlinks are always 0777.
			[ -n "$_gb_uid" ] && [ -n "$_gb_gid" ] && chown -h "$_gb_uid:$_gb_gid" "$_gb_dest" 2>/dev/null
			;;
		file)
			[ -n "$_gb_mode" ] && chmod "$_gb_mode" "$_gb_dest" 2>/dev/null
			[ -n "$_gb_uid" ] && [ -n "$_gb_gid" ] && chown "$_gb_uid:$_gb_gid" "$_gb_dest" 2>/dev/null
			;;
	esac
}

# Redacted options on stderr, so the operator re-enters them.
_gb_restore_print_scrubbed() {
	_gb_manifest="$1"
	_gb_scrub_any=0
	gb_manifest_each "$_gb_manifest" scrubbed _gb_restore_scrubbed_one
	return 0
}

_gb_restore_scrubbed_one() {
	_gb_obj="$1"
	_gb_opt=$(gb_manifest_field "$_gb_obj" option)
	[ -n "$_gb_opt" ] || return 0
	if [ "$_gb_scrub_any" -eq 0 ]; then
		printf 'The following values were redacted before this backup was pushed -- enter them by hand:\n' >&2
		_gb_scrub_any=1
	fi
	printf '  %s\n' "$_gb_opt" >&2
}

# Best effort. Names come from the {origin} group of `apk list --installed`:
# splitting "name-version" is ambiguous.
_gb_restore_packages() {
	_gb_meta="$1"
	_gb_repos="$_gb_meta/repositories.txt"
	if [ -s "$_gb_repos" ]; then
		mkdir -p "${GB_ROOT:-}/etc/apk/repositories.d" 2>/dev/null
		cp "$_gb_repos" "${GB_ROOT:-}/etc/apk/repositories.d/gitbackup-restored.list" 2>/dev/null
	fi

	_gb_installed="$_gb_meta/installed_packages.txt"
	[ -r "$_gb_installed" ] || return 0

	_gb_pkg_failed=''
	while IFS= read -r _gb_line || [ -n "$_gb_line" ]; do
		_gb_pkg=$(printf '%s\n' "$_gb_line" | sed -n 's/.*{\([^}]*\)}.*/\1/p')
		[ -n "$_gb_pkg" ] || continue
		apk add "$_gb_pkg" >/dev/null 2>&1 || _gb_pkg_failed="$_gb_pkg_failed $_gb_pkg"
	done <"$_gb_installed"

	if [ -n "$_gb_pkg_failed" ]; then
		printf 'the following packages could not be reinstalled automatically, add them by hand:%s\n' "$_gb_pkg_failed"
	fi
	return 0
}
