# shellcheck shell=sh
#
# gitbackup -- recovery card (spec "Recovery card и RECOVERY.md", ticket 09).
#
# Exposes gb_card; every _gb_card_-prefixed helper below is private, same
# per-module namespacing convention every sibling file here uses. Sourced,
# never executed: nothing here runs at load time.
#
# Depends on lib.sh (gb_log, gb_uci_get) and remoteurl.sh (gb_parse_url,
# gb_provider) already being sourced by the caller -- same convention
# visibility.sh/restore.sh use. Reads GB_URL and GB_DEVICE from the
# environment rather than taking them as arguments: usr/sbin/gitbackup's
# _gb_run_backup already has both resolved (by gb_validate_config, before
# _gb_run_backup even starts) at the one call site this module is actually
# reached from today (step 11b, "the recovery card"), same convention
# gitio.sh/restore.sh already use for config context the CLI resolved once.
# A future LuCI "Download recovery card" button (ticket 11) goes through
# `gitbackup card`, which resolves the same two through gb_validate_config
# first, so this module never has to.
#
# gb_card is deliberately built to never die and never fail loudly: it is
# called from the middle of a real backup run (usr/sbin/gitbackup's
# `gb_card "$_gb_outdir/RECOVERY.md" 2>/dev/null`), and a bug in a recovery
# document must not be able to abort the backup it rides along with. Every
# helper below degrades to a shorter card instead of calling gb_die, and
# gb_card itself always returns 0.

# gb_card <outfile>
#
# Writes one recovery document to <outfile> -- the same content LuCI's
# "Download recovery card" button (ticket 11) offers for offline storage and
# `gitbackup run` commits to devices/<id>/RECOVERY.md (spec: "Оба генерирует
# gb_card; различаются только назначением и местом"). Contains a ready-made
# bootstrap one-liner with --repo/--device already filled in, a link to the
# repository's own web UI, a reminder that a token or deploy key still has
# to be supplied by hand, and a short Path 0 fallback for when there is no
# network to run bootstrap.sh over at all. Never the secret itself: neither
# the token nor the deploy key's private half ever passes through this
# module (interfaces.md: "Секрета в карточке нет").
gb_card() {
	_gb_c_out="$1"
	_gb_c_dev="${GB_DEVICE:-}"
	[ -n "$_gb_c_dev" ] || _gb_c_dev='<device>'
	_gb_c_url="${GB_URL:-}"
	[ -n "$_gb_c_url" ] || _gb_c_url=$(gb_uci_get gitbackup.origin.url)

	_gb_c_authflag='--token <TOKEN>'
	_gb_c_weblink=''

	# GB_SCRUB is this run's EFFECTIVE scrub decision, already resolved
	# once by gb_validate_config (usr/sbin/gitbackup) and exported for
	# every subcommand -- the same seam collect.sh reads GB_DEVICE
	# through, and the reason this file does not re-derive it from
	# gitbackup.security.scrub itself: visibility=public forces scrub on
	# regardless of what that option says, and a card that missed the
	# override would promise a Path 0 that does not exist.
	_gb_c_scrub=0
	[ "$(gb_json_bool "${GB_SCRUB:-0}")" = true ] && _gb_c_scrub=1
	_gb_c_archive=0
	if [ "$(gb_json_bool "$(gb_uci_get gitbackup.main.archive 1)")" = true ] && [ "$_gb_c_scrub" = 0 ]; then
		_gb_c_archive=1
	fi

	if [ -n "$_gb_c_url" ]; then
		_gb_c_parsed=$(gb_parse_url "$_gb_c_url" 2>/dev/null)
		if [ -n "$_gb_c_parsed" ]; then
			# shellcheck disable=SC2086  # word-splitting is the point: five fields from one line
			set -- $_gb_c_parsed
			_gb_c_scheme="$1"
			_gb_c_host="$2"
			_gb_c_owner="$4"
			_gb_c_repo="$5"
			[ "$_gb_c_scheme" = ssh ] && _gb_c_authflag='--ssh-key <PATH-TO-DEPLOY-KEY>'
			# No port here, same known limitation as gb_deeplink
			# (remoteurl.sh): every provider this package recognizes serves
			# its web UI on the default https port, so this has never
			# needed one -- a self-hosted instance on a nonstandard port
			# would need it added here too, at the same time.
			_gb_c_weblink="https://$_gb_c_host/$_gb_c_owner/$_gb_c_repo"
		fi
	fi
	[ -n "$_gb_c_url" ] || _gb_c_url='<REPO-URL>'

	{
		printf '# gitbackup recovery card -- %s\n\n' "$_gb_c_dev"
		printf 'Generated: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf 'This router backs itself up to a private git repository. If it dies, a\n'
		printf 'freshly flashed replacement can be brought back to the same configuration\n'
		printf 'with one command, run over ssh once the replacement has booted and has\n'
		printf 'network access.\n\n'
		printf 'This card does NOT contain a secret. You still have to bring one: either a\n'
		printf 'personal access token with read access to the repository below (HTTPS\n'
		printf 'remotes), or the path to the SSH deploy key already registered on it (SSH\n'
		printf 'remotes).\n\n'
		printf '## Path 1 -- one command\n\n'
		printf '```sh\n'
		printf 'uclient-fetch -qO- https://raw.githubusercontent.com/VizzleTF/luci-app-gitbackup/main/bootstrap.sh \\\n'
		printf '  | sh -s -- --repo %s --device %s %s\n' "$_gb_c_url" "$_gb_c_dev" "$_gb_c_authflag"
		printf '```\n\n'
		if [ -n "$_gb_c_weblink" ]; then
			printf 'Repository: %s\n\n' "$_gb_c_weblink"
		fi
		# Path 0 is printed only when there is actually an archive in the
		# repository to open it with. `gitbackup run` writes
		# backup.tar.gz when main.archive is on AND this run does not
		# scrub (usr/sbin/gitbackup's own step 11a -- sysupgrade -b reads
		# the live filesystem, so pushing its output would undo the scrub
		# the same run was just asked to perform). A recovery card is
		# read exactly once, by someone whose router is already broken;
		# sending them after a file that was never pushed is worse than
		# telling them this path is unavailable, and why.
		if [ "$_gb_c_archive" = 1 ]; then
			printf '## Path 0 -- no network, or bootstrap.sh will not run\n\n'
			printf '1. Open the repository above from any other device and download\n'
			# shellcheck disable=SC2016  # backticks are markdown code spans in the
			# generated document, not an attempted command substitution here
			printf '   `devices/%s/backup.tar.gz` from the latest commit on branch\n' "$_gb_c_dev"
			# shellcheck disable=SC2016
			printf '   `device/%s` (or the branch your `gitbackup.origin.branch` template\n' "$_gb_c_dev"
			printf '   resolves to).\n'
			printf '2. On the router: LuCI -> System -> Backup / Flash Firmware -> Restore\n'
			printf '   configuration, and upload that file. Over ssh instead:\n'
			# shellcheck disable=SC2016
			printf '   `sysupgrade -r backup.tar.gz` after copying it onto the router.\n'
			printf '3. Reboot. This restores the raw sysupgrade archive, not the package own\n'
			printf '   sha256-verified restore -- see docs/RESTORE.md for the difference.\n'
		elif [ "$_gb_c_scrub" = 1 ]; then
			printf '## Path 0 -- not available on this router\n\n'
			# shellcheck disable=SC2016
			printf 'No `backup.tar.gz` is pushed while config scrubbing is on:\n'
			# shellcheck disable=SC2016
			printf '`sysupgrade -b` reads the live filesystem, so its archive would carry\n'
			printf 'exactly the secrets scrubbing keeps out of the commit. Use Path 1\n'
			# shellcheck disable=SC2016
			printf 'above, or `gitbackup restore` -- see docs/RESTORE.md.\n'
		else
			printf '## Path 0 -- not available on this router\n\n'
			# shellcheck disable=SC2016
			printf 'No `backup.tar.gz` is pushed (`gitbackup.main.archive` is off). Use\n'
			# shellcheck disable=SC2016
			printf 'Path 1 above, or `gitbackup restore` -- see docs/RESTORE.md.\n'
		fi
	} >"$_gb_c_out" 2>/dev/null
	return 0
}
