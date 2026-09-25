#!/bin/sh
# shellcheck shell=sh
#
# GIT_ASKPASS helper, executed by git with the prompt in $1. The only reader
# of the token file: the token reaches git through this pipe, never argv, a
# URL or a log.
#
# Only the password prompt gets the token. git embeds the username in the
# URL of its next prompt and passes that as argv here, so a token answered
# as username would leak into argv (seen with GIT_TRACE=1).
#
# VERIFY: placeholder-user + token-as-password is documented for GitHub PATs
# only; not tested against GitLab/Bitbucket/Gitea.

set -u

GB_SHARE="${GB_SHARE:-/usr/share/gitbackup}"
# shellcheck disable=SC1091  # GB_SHARE is a runtime path, not resolvable statically
. "$GB_SHARE/lib.sh"

case "${1:-}" in
	*sername*)
		# Any non-empty value works; never the token.
		printf 'gitbackup\n'
		;;
	*)
		_gb_token_file=$(gb_uci_get gitbackup.origin.token_file /etc/gitbackup/token)
		if [ ! -r "$_gb_token_file" ]; then
			gb_log err "askpass: no readable token at $_gb_token_file (gitbackup.origin.token_file)"
			exit 1
		fi
		# First line only: a stray trailing newline must not reach git.
		head -n 1 "$_gb_token_file"
		;;
esac
