# shellcheck shell=sh
#
# gitbackup -- Path 2 restore, applying a backup set straight back onto the
# filesystem (spec "Восстановление"). This is the module that makes
# manifest.json's mode/uid/gid/target fields matter: git stores none of
# them, so a plain checkout of files/ would hand back /etc/shadow at
# whatever mode git happens to give a new file (world-readable) and every
# dropbear host key owned by whoever ran the restore -- a router that
# LOOKS restored but that dropbear and login refuse to trust.
#
# Exposes gb_restore; every _gb_restore_-prefixed helper below is private
# and namespaced by module, same convention every other module here uses
# (all of *.sh end up sourced into one process by usr/sbin/gitbackup, so a
# bare _gb_ helper name could collide with a sibling module's). Sourced,
# never executed: nothing here runs at load time.
#
# Depends on lib.sh (gb_log, gb_uci_get, gb_manifest_field, gb_manifest_each
# -- gb_json_str is NOT used here, this module only ever reads manifest.json,
# never writes one) and gitio.sh (gb_remote_head, gb_fetch_meta) already
# being sourced by the caller -- restore reuses gitio.sh's own proven fetch
# machinery (a NAMED "origin" remote, a --filter=blob:none fetch, an
# optional depth) for both the common case and the specific-past-commit one
# instead of re-deriving either.
# Does NOT depend on collect.sh or device.sh: the device being restored is
# whatever the caller passes as an argument, never gb_device_id's own
# resolution -- a fresh/bare router calling `gitbackup restore --device D`
# has, by construction, no working device_id config yet (bootstrap's own
# Path 1 step 4 runs this before the restored gitbackup.main.device_id even
# exists on disk), so gb_expand's automatic gb_device_id() call cannot be
# reused here; _gb_restore_expand below is a deliberate, small duplicate of
# gb_expand's substitution loop that takes the device explicitly instead.
#
# GB_ROOT overrides the filesystem root every write and every real-path
# read goes through (default '', meaning the actual '/') -- the same seam
# collect.sh's GB_ROOT already is, so a test can point this at a fixture
# tree instead of the host filesystem and collect_fixture-shaped setups
# apply unchanged. GB_URL is read from the environment, not taken as an
# argument -- same convention gitio.sh/visibility.sh use for config context
# the CLI already resolved once.
#
# VERIFY: Path 0 ("uploaded devices/<d>/backup.tar.gz through LuCI's own
# stock Backup/Flash Firmware -> Restore configuration") is NOT this
# module's own code at all -- Path 0 is the router's stock `sysupgrade -r`
# reading a plain sysupgrade archive, gitbackup never runs in that path.
# What was actually confirmed live on the owlab owrt2512 25.12.4 stand:
# `sysupgrade -b` followed straight by `sysupgrade -r` on that same
# archive genuinely restores config (a changed system.hostname reverted
# correctly) with no error, AS LONG AS the archive excludes /etc/hosts --
# on THIS container-based stand /etc/hosts is a Docker/OrbStack bind
# mount, not a real file, so any tar restore that includes it hits `tar:
# can't remove old file etc/hosts: Resource busy`. That failure is
# confirmed to be the stand's own container artifact, not a router
# behavior: a real router has no such bind mount over /etc/hosts. What
# remains genuinely unverified: an actual click through LuCI's own
# Restore configuration upload widget (no browser available here), and
# the container limitation above itself was never worked around inside
# gitbackup's own code -- only demonstrated by hand-filtering the tar
# before feeding it to sysupgrade -r.

GB_ROOT="${GB_ROOT:-}"

# gb_restore <device> <commit-or-empty> [--dry-run] [--force] [--yes] [--with-packages]
#
# <commit-or-empty> is "" or "HEAD" for the branch's current tip (the
# common case, and the only one bootstrap's Path 1 ever uses); anything
# else is fetched as a specific historical commit, which needs the whole
# branch's history (not gb_fetch_meta's own --depth=1) to be reachable at
# all -- still only THIS device's one branch, never every branch in the
# repository, so "полного клона не появляется" holds either way.
#
# Returns 0 on success, 1 on a general failure (sha256 mismatch, missing
# manifest, declined confirmation), 2 on a bad argument, 3 on network/auth,
# 4 refused for safety (board mismatch without --force) -- the same
# four-code contract every other module here already answers to
# (interfaces.md, "Коды выхода"); usr/sbin/gitbackup's cmd_restore is what
# turns this into the process's actual exit code.
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

	_gb_branch=$(_gb_restore_expand "$(gb_uci_get gitbackup.origin.branch 'device/{device}')" "$_gb_device")
	_gb_prefix=$(_gb_restore_expand "$(gb_uci_get gitbackup.main.path_prefix 'devices/{device}')" "$_gb_device")

	# Everything from here lives under /tmp, same rule cmd_run's own WORK
	# follows (never flash, never USB) -- trap fires when THIS PROCESS (or
	# the caller's subshell, in a test) exits, not when this function
	# returns, so every early `return` below needs no manual cleanup of
	# its own, same convention cmd_run's scattered gb_die calls already
	# rely on.
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
		# A specific past commit needs the branch's full history to be
		# reachable at all -- gb_fetch_meta's own default depth of 1
		# (gitio.sh, tuned for `run`'s own "just the tip" need) cannot
		# reach it. Passing it an explicit empty depth skips --depth
		# entirely instead of this module repeating gb_fetch_meta's
		# init/remote-add/fetch sequence a second time (ticket 18: this
		# WAS that second copy, byte-for-byte, before gb_fetch_meta grew
		# a depth argument). Still one branch, not the repository:
		# "минимально: своя ветка, нужный коммит" (spec). Same mapping
		# to exit 3 on any failure as the tip-fetch branch above, whether
		# gb_fetch_meta failed at init or at the fetch itself.
		gb_fetch_meta "$_gb_branch" "$_gb_repodir" '' || return 3
		_gb_target="$_gb_commit"
	fi

	if ! git -C "$_gb_repodir" cat-file -e "$_gb_target^{commit}" 2>/dev/null; then
		gb_log err "gb_restore: commit $_gb_target was not found on $_gb_branch at $GB_URL"
		return 1
	fi

	# The one checkout call this whole module needs: a pathspec-scoped
	# `checkout <commit> -- <path>` reads only $_gb_prefix's own tree from
	# $_gb_target and lazily fetches only the blobs under it (the
	# --filter=blob:none fetch above already marked this remote a
	# promisor, same mechanism gitio.sh's own gb_fetch_meta comment
	# documents for `cat-file -p`) -- this is "sparse на devices/<D>/"
	# without needing git's separate sparse-checkout feature at all.
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

	# Before anything reads a field out of it: the manifest is remote
	# input. Everything else in this function already treats the CONTENT
	# of files/ as untrusted-until-hashed; this pass extends the same
	# suspicion to the entry metadata that decides WHERE that content
	# goes and what it ends up owned by. Refusing the whole manifest
	# rather than skipping the offending entry is deliberate -- a
	# manifest this package did not write is not a backup that was
	# partially applied, it is a backup that should not be applied.
	_gb_restore_check_entries "$_gb_manifest" || {
		gb_log err "gb_restore: $_gb_prefix/manifest.json at $_gb_target has unusable entries, nothing was written:$_gb_entries_bad"
		return 4
	}

	_gb_restore_check_board "$_gb_srcroot/meta/board.json" "$_gb_force"
	_gb_board_rc=$?
	[ "$_gb_board_rc" -eq 0 ] || return "$_gb_board_rc"

	_gb_restore_check_release "$_gb_srcroot/meta/os-release.txt"

	# The whole point of this module: not one byte reaches GB_ROOT until
	# every file's content is proven correct against the manifest.
	_gb_restore_verify_sha "$_gb_srcroot/files" "$_gb_manifest" || return 1

	# Ticket 19: a second read-only pass, same "сверили всё -> потом
	# пишем" principle as the sha256 one just above, run before the
	# dry-run branch for the same reason -- it finds out WHICH paths
	# cannot possibly be replaced before a single byte is written,
	# instead of finding out only when cp fails mid-restore.
	# _gb_precheck_bad is consumed below by _gb_restore_write_one, which
	# skips a doomed cp entirely for anything in it rather than let
	# busybox's own misleading "File exists" (produced by an unlink that
	# silently failed, then a create that hits EEXIST) stand in as the
	# reported reason.
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

	# Files first (content only), THEN mode/uid/gid/empty-dirs/symlinks in
	# a second pass (spec: "разложить файлы, затем применить mode/uid/gid,
	# создать пустые каталоги, пересоздать симлинки") -- content and
	# ownership are deliberately two passes, not interleaved per entry.
	_gb_restore_write_files "$_gb_srcroot/files" "$_gb_manifest"
	_gb_write_rc=$?

	# Ticket 19: this call used to be gated behind
	# `_gb_restore_write_files ... || { ...; return 1; }`, so ONE failed
	# write (one busy bind mount, one read-only path) skipped applying
	# rights to EVERY OTHER file. Found live on the owlab owrt2512 stand:
	# a restore that failed only on /etc/hosts (a Docker/OrbStack bind
	# mount there, but on a real router this is any path that is
	# mounted, busy, read-only, or immutable) left /etc/shadow 644
	# root:root -- world-readable -- because this line was never
	# reached, and dropbear separately refused its own restored host
	# keys for the same reason.
	#
	# Decision (spec explicitly leaves this to the implementer): a
	# partially-restored router with correct permissions on every path
	# that DID land is strictly safer than either extreme -- refusing
	# the WHOLE restore over one stubborn path throws away everything
	# else that would have worked (network, wireless, dropbear keys,
	# cron, ...) over a file that is present in literally every backup
	# (/etc/hosts is always in sysupgrade -l); silently reporting success
	# is worse still. So this module always writes what it can, always
	# applies rights to whatever got written, and always tells the
	# operator the truth (below) with a non-zero exit -- unconditionally,
	# not only under --force. --force here keeps meaning exactly what it
	# already means one check up (override a board mismatch); it is not
	# involved in this decision at all.
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

# _gb_restore_expand <template> <device> -- gb_expand's own substitution
# loop (device.sh), duplicated rather than reused: gb_expand always
# resolves {device} through gb_device_id() itself, which is exactly what
# this module must NOT do (see this file's header). Kept in lockstep with
# gb_expand by inspection -- the loop body is identical on purpose.
_gb_restore_expand() {
	_gb_tpl="$1"
	_gb_dev="$2"
	_gb_out=''
	_gb_rest="$_gb_tpl"
	while true; do
		case "$_gb_rest" in
			*'{device}'*)
				_gb_out="$_gb_out${_gb_rest%%\{device\}*}$_gb_dev"
				_gb_rest="${_gb_rest#*\{device\}}"
				;;
			*)
				_gb_out="$_gb_out$_gb_rest"
				break
				;;
		esac
	done
	printf '%s\n' "$_gb_out"
}

# _gb_restore_check_board <old-board.json> <force> -- 0 (match, or --force
# overrode a mismatch) or 4 (refused). Compares "model" (the field
# device.sh's own board strategy already reads, and the one confirmed
# `null` on generic/armsr targets -- spec: "Поле board бывает null...
# Это не дефект") and "release.target" (the actual build target, e.g.
# "mediatek/filogic" -- present even when model is not, so it is what
# actually catches a generic-target-to-generic-target restore across
# genuinely different hardware that model alone would wave through as
# "both null, must match").
#
# Confirmed live on the owlab 25.12.4 armsr/armv8 stand: `ubus call system
# board` there has no "model" key at all (this target's own real-world
# instance of "Поле board бывает null" -- not a fixture assumption) and
# does have "release": {"target": "armsr/armv8", ...}; the real jsonfilter
# parses that pretty-printed, multi-line, tab-indented object correctly
# with `-e '@.release.target'` -- confirmed against the real binary, not
# just this suite's flat-JSON test stub.
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

# _gb_restore_check_release <old-os-release.txt> -- a major-version
# mismatch is a warning, never a refusal (spec: "Расхождение os-release.txt
# в мажорной версии -> предупреждение, не отказ"). Missing/unparsable data
# on either side is silently skipped, not a warning of its own -- an old
# backup predating this field, or a target with no /etc/os-release at all,
# is not itself evidence of anything wrong.
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

# Field reads and entries[] iteration used to be this module's own private
# copies (a quoted-string extractor, a bare-numeric one, and a hand-rolled
# entries[] walker) -- ticket 18 moved all three to lib.sh as
# gb_manifest_field and gb_manifest_each, shared with collect.sh's
# gb_manifest_equal and scrub.sh's manifest rewriter instead of each
# module maintaining its own copy of the same one-object-per-line,
# no-nested-brackets parsing.

# gb_restore's own hard gate: computes _gb_sha_bad (space-separated bad
# paths) via _gb_restore_verify_sha_one, then refuses as a whole if
# anything mismatched. _gb_srcfiles is set right before the each_entry
# call and consumed only inside it -- a temporary, not a public seam.
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

# _gb_restore_check_writable <manifest.json> -- ticket 19's preflight: a
# second read-only pass, run alongside _gb_restore_verify_sha above (same
# "сверили всё -> потом пишем" principle applied to writability, not just
# content). Sets _gb_precheck_bad, a space-separated path list in the same
# shape as _gb_sha_bad above, to every "file" entry whose destination
# already exists and is, as far as metadata alone can predict, NOT going
# to survive cp's own unlink-then-recreate:
#
#   - its containing directory has no write permission. Also correctly
#     answers "no" when the directory's own FILESYSTEM is mounted
#     read-only, even for root -- access(2), which `[ -w ... ]` is built
#     on, checks the mount's own read-only flag regardless of permission
#     bits. The one half of this check reproducible from an
#     unprivileged host test (chmod 555 a directory).
#   - the destination's own device differs from its containing
#     directory's (`stat -c %d` on each). True only when the exact
#     destination PATH is itself a distinct mount point -- e.g. a
#     Docker/OrbStack bind mount of a single file over /etc/hosts.
#     Confirmed live on the owlab owrt2512 stand: `stat -c%d /etc/hosts`
#     there is 41, `stat -c%d /etc` is 1048628 -- while /etc/shadow and
#     /etc/config both report 1048628, same as /etc itself, so this does
#     NOT misfire on an ordinary file. This is exactly what made cp -f
#     fail there with a misleading "File exists" (busybox/coreutils cp's
#     own unlink-before-recreate silently failed the unlink, then hit
#     EEXIST on the create) -- also confirmed live: `cp -f /tmp/x
#     /etc/hosts` -> "cp: can't create '/etc/hosts': File exists". This
#     half cannot be fabricated from an unprivileged host test (that
#     would need a real mount of its own), so it is stand-verified only,
#     same as several other OS-level facts already in this file.
#
# Deliberately narrow: a permission-bit problem on the FILE itself, a
# read-only attribute, or an immutable flag are not caught here -- there
# is no metadata-only signal for those that would not also misfire on an
# ordinary read-only file elsewhere in the tree (mode 444 is common and
# perfectly overwritable by root). Those still only surface at actual
# write time, exactly as before this ticket; this preflight only removes
# the ONE failure mode the spec explicitly asks to catch ahead of time.
# _gb_restore_check_entries <manifest.json> -- read-only validation of
# every entry's METADATA, before any of it is used. Sets _gb_entries_bad
# (a multi-line "  <path>: <reason>" report, empty when everything is
# usable) and returns 0 iff it stayed empty.
#
# What this does NOT do is restrict WHICH paths may be restored. Writing
# back whatever the backup set contained, wherever it lived, is the whole
# point of this module -- there is no allowlist here and there should not
# be one. What it checks is that each entry says what it means, exactly
# once, in the one spelling every later pass will agree on:
#
#   - path is absolute and canonical (gb_path_canon, lib.sh). Two passes
#     read this field independently -- _gb_restore_check_writable_one
#     builds _gb_precheck_bad from it and _gb_restore_write_one looks
#     itself up in that list by string match -- so "/etc/./hosts" and
#     "/etc/hosts" naming the same file in two entries would make the
#     preflight and the write disagree about which one it decided on.
#   - type is one this module actually handles, so an unknown one is a
#     loud refusal instead of an entry silently skipped by all three
#     `case` statements below.
#   - mode is 3 or 4 octal digits, uid/gid are digits. These go straight
#     into `chmod`/`chown` argv (_gb_restore_perm_one), where a value
#     like "--reference=/etc/shadow" or a leading "-" would be read as an
#     option rather than as the mode it claims to be.
#
# A manifest that fails any of this was not written by this package's own
# collect.sh -- every field above is machine-generated there from stat(1)
# output -- so the honest response is to refuse the restore outright
# (gb_restore does, with exit 4), not to sanitize a hostile manifest into
# a plausible-looking one and apply it.
_gb_restore_check_entries() {
	_gb_manifest="$1"
	_gb_entries_bad=''
	gb_manifest_each "$_gb_manifest" entries _gb_restore_check_entries_one
	[ -z "$_gb_entries_bad" ]
}

# _gb_restore_entry_reject <shown-path> <reason> -- one line onto the report.
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
	# Nothing at $_gb_dest yet -- cp will just create it, no replace
	# involved, so there is nothing here that could go wrong this way.
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

# _gb_restore_print_plan <manifest.json> -- --dry-run's own output, and
# also what the interactive confirmation prompt shows before asking. Marks
# each path "overwrite" (something is already there at GB_ROOT) or
# "create" (nothing is), which is what "печатает, что будет перезаписано"
# actually needs to be useful, not just a bare path list.
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

# _gb_restore_write_files <srcfiles> <manifest.json> -- pass 1: file
# CONTENT only, no mode/uid/gid yet (_gb_restore_apply_perms is pass 2).
# Only reached after _gb_restore_verify_sha has already confirmed every
# file's hash, so a failure here is an I/O problem (disk full, a path
# collision with an existing directory, a mount that refuses to give up
# its own path), not a data-integrity one.
#
# Sets _gb_write_bad, a multi-line "  <path>: <reason>" report (empty
# when nothing failed), and returns 0 iff it stayed empty. The caller
# (gb_restore) deliberately does NOT gate _gb_restore_apply_perms on this
# return value (ticket 19) -- it only reads _gb_write_rc/_gb_write_bad
# afterward, to tell the operator the truth and end the call non-zero,
# once rights have already been applied to whatever DID get written.
# gb_manifest_each itself never stops iterating on a callback's own
# return code (lib.sh), so one failing entry here already does not
# prevent the REST of this same pass from running either -- only the
# call site one level up used to throw that away.
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

	# Already known doomed by _gb_restore_check_writable above -- skip
	# the attempt outright rather than let cp run into it and report its
	# own less useful message (see that function's own comment for why).
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
	# A symlink sitting where a "file" entry wants to land is removed
	# first, never written through. Two reasons, and the second is the
	# one that matters: a "file" entry must end up an actual file, which
	# is what the symlink branch of _gb_restore_perm_one already assumes
	# in the other direction (it rm -f's whatever is there before its own
	# ln -s); and `cp -f` disagrees with itself about this across the two
	# implementations this package runs on -- GNU cp opens the
	# destination O_TRUNC, which FOLLOWS the link and rewrites whatever
	# it points at, somewhere the manifest never named, while busybox cp
	# unlinks first (the -f comment below). Deciding it here makes both
	# behave the same, and makes the set of files a restore can touch
	# exactly the set of paths its manifest lists.
	[ -L "$_gb_dest" ] && rm -f "$_gb_dest" 2>/dev/null
	# -f: busybox cp (unlike GNU/BSD cp) refuses an existing destination
	# outright ("File exists") without it -- found live on the owlab
	# stand restoring over /etc/hosts, not caught by any host-side test
	# since macOS/GNU cp both overwrite by default with no flag at all.
	_gb_cp_err=$(cp -f "$_gb_srcfiles$_gb_path" "$_gb_dest" 2>&1) || {
		_gb_write_bad="$_gb_write_bad
  $_gb_path: $_gb_cp_err"
		return 0
	}
}

# _gb_restore_apply_perms <manifest.json> -- pass 2: mode/uid/gid for
# files and directories, empty directories created outright (they have no
# content of their own to have been written in pass 1), symlinks created
# from scratch (their "content" IS the target string, never copied as a
# file -- collect.sh's own R24.1 comment on the same asymmetry).
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
			# _gb_symtarget, NOT _gb_target: found live on the owlab stand --
			# gb_restore's own outer scope holds the commit sha being
			# restored in a variable of that exact name (no `local` anywhere
			# in this codebase, interfaces.md's own convention), and this
			# helper runs from inside gb_restore's own call chain
			# (_gb_restore_apply_perms -> gb_manifest_each -> here) --
			# reusing _gb_target here clobbered it, so the FINAL "restored
			# <device> from <commit>" message printed the last symlink's
			# target string instead of the commit sha whenever the backup
			# set contained even one symlink. The restore itself was
			# unaffected (this ran after every actual write), only the
			# closing report was wrong.
			_gb_symtarget=$(gb_manifest_field "$_gb_obj" target)
			mkdir -p "$(dirname "$_gb_dest")" 2>/dev/null
			rm -f "$_gb_dest" 2>/dev/null
			# `--`: the target string is the one manifest field with no
			# shape of its own to validate (any string is a legal symlink
			# target), so it is the one that can still arrive looking like
			# an option -- "-s", "--force". End-of-options settles it
			# without constraining what a symlink is allowed to point at.
			ln -s -- "$_gb_symtarget" "$_gb_dest" 2>/dev/null
			# -h: change the symlink's own ownership, not the (possibly
			# dangling, e.g. /etc/resolv.conf) target's -- busybox chown
			# documents -h for exactly this. Mode is never set on a
			# symlink: Linux always reports lstat mode 0777 for one
			# regardless of chmod, so a freshly `ln -s`'d link already
			# matches whatever collect.sh recorded (it read the same
			# lstat mode the same way). Confirmed live on the owlab
			# 25.12.4 stand: chown -h on this busybox actually changes
			# the symlink's own uid/gid, not a dangling target's.
			[ -n "$_gb_uid" ] && [ -n "$_gb_gid" ] && chown -h "$_gb_uid:$_gb_gid" "$_gb_dest" 2>/dev/null
			;;
		file)
			[ -n "$_gb_mode" ] && chmod "$_gb_mode" "$_gb_dest" 2>/dev/null
			[ -n "$_gb_uid" ] && [ -n "$_gb_gid" ] && chown "$_gb_uid:$_gb_gid" "$_gb_dest" 2>/dev/null
			;;
	esac
}

# _gb_restore_print_scrubbed <manifest.json> -- prints scrubbed[]'s option
# paths to stderr (informational for the operator, same stream
# gb_accept_hostkey's own prompts use), one per line, with a header only
# once and only if there is at least one. Silent when scrubbed[] is empty
# -- a private backup restoring cleanly should say nothing extra.
#
# gb_manifest_each (lib.sh) walks "scrubbed" the same way
# _gb_restore_apply_perms's own each-entry call above walks "entries" --
# this used to be its own hand-rolled entries/scrubbed-array walker,
# parallel to (and slightly different from) the one gb_restore's other
# helpers shared, before ticket 18 moved both to lib.sh.
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

# _gb_restore_packages <meta-dir> -- --with-packages, best-effort (spec:
# "apk add по installed_packages.txt best-effort, в конце напечатать
# список неустановившегося"). Package names come from the `{origin}`
# group `apk list --installed` itself prints (meta/installed_packages.txt
# is that command's own full-line output, per collect.sh's own comment) --
# not from splitting the leading "name-version" token, which is exactly
# the fragile parse the spec warns against (a version string can itself
# contain a dash where the name also could). Restores repositories.txt
# first so a custom feed's own packages have somewhere to come from.
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
