# shellcheck shell=sh
#
# gitbackup -- recovery card: gb_card. Needs lib.sh and remoteurl.sh; reads
# GB_URL/GB_DEVICE/GB_SCRUB as resolved by the CLI.
#
# gb_card <outfile> -- writes RECOVERY.md. Never contains a secret. Runs
# mid-backup, so it never dies and always returns 0.
gb_card() {
	_gb_c_out="$1"
	_gb_c_dev="${GB_DEVICE:-}"
	[ -n "$_gb_c_dev" ] || _gb_c_dev='<device>'
	_gb_c_url="${GB_URL:-}"
	[ -n "$_gb_c_url" ] || _gb_c_url=$(gb_uci_get gitbackup.origin.url)

	_gb_c_authflag='--token <TOKEN>'
	_gb_c_weblink=''

	# GB_SCRUB, not gitbackup.security.scrub: visibility=public forces scrub
	# on, and missing that would promise a Path 0 that does not exist.
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
			# No port: known provider web UIs are on the default https port.
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
		# Path 0 only when an archive is actually pushed (archive on, no
		# scrub); otherwise say why it is unavailable.
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
