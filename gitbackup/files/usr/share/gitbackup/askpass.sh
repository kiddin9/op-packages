#!/bin/sh
# shellcheck shell=sh
#
# gitbackup -- GIT_ASKPASS helper (spec "Аутентификация").
#
# Not sourced like the rest of usr/share/gitbackup/*.sh -- git execs this
# directly (GIT_ASKPASS=/usr/share/gitbackup/askpass.sh, set by
# auth.sh's gb_git_env) once per missing credential component, with the
# prompt text as $1 ("Username for '...': ", "Password for '...': ", the
# exact wording is git's own and varies by version), and reads exactly one
# line back from this script's stdout.
#
# This is the only place gitbackup.origin.token_file is ever read for a
# push: the token reaches git through this pipe, never through argv, a URL,
# or a log line.
#
# The username prompt is answered with a fixed, non-secret placeholder --
# NEVER the token -- and only the password prompt gets the token. This is
# not the obvious design: an earlier version answered both prompts with the
# token (a fine-grained PAT works as either field on GitHub, per its own
# docs), on the reasoning that a value read from a file and only ever
# piped to git's stdin cannot show up in `ps` because it was never a
# command-line argument. That reasoning was wrong, caught only by actually
# tracing a live request on the owlab stand (GIT_TRACE=1): git treats
# whatever the username prompt returns as the credential's username, and
# builds the URL for its *next* prompt -- "Password for
# 'http://<username>@host:port': " -- with that value inline, then execs
# this script again with that whole string as $1. A token answered as the
# username therefore reappears as a literal substring of argv on the very
# next invocation, which is precisely what this package must never do
# (spec: "Токен... никогда в argv"). Answering the username with a fixed
# placeholder instead means the value that could ever leak into an argv or
# a URL is never the secret. Re-verified after the fix, same live trace:
# the second prompt now reads "Password for
# 'http://gitbackup@host:port': " -- the token appears nowhere in argv, at
# any point, confirmed by sampling `ps` throughout the whole exchange.
#
# VERIFY: the placeholder username plus token-as-password shape is
# confirmed against GitHub's own docs (a fine-grained PAT as the password
# with any non-empty username); not confirmed live against GitLab/
# Bitbucket/self-hosted Gitea, which needs a real hosted remote and real
# credentials neither of which exist on this dev stand (spec.md, "Открытые
# места": "push на живой GitHub/GitLab -- нет учётных данных на стенде").
set -u

GB_SHARE="${GB_SHARE:-/usr/share/gitbackup}"
# shellcheck disable=SC1091  # GB_SHARE is a runtime path, not resolvable statically
. "$GB_SHARE/lib.sh"

case "${1:-}" in
	*sername*)
		# Never the token: see this file's header. The exact string is
		# arbitrary -- git only requires it to be non-empty -- "gitbackup"
		# just makes a stray log line or trace recognizable as this
		# package's own request rather than a real account name.
		printf 'gitbackup\n'
		;;
	*)
		_gb_token_file=$(gb_uci_get gitbackup.origin.token_file /etc/gitbackup/token)
		if [ ! -r "$_gb_token_file" ]; then
			gb_log err "askpass: no readable token at $_gb_token_file (gitbackup.origin.token_file)"
			exit 1
		fi
		# head -n 1, not cat: a trailing blank line or a second line in the
		# token file (a stray newline from how it was pasted in) must not
		# become part of what git sends as the credential.
		head -n 1 "$_gb_token_file"
		;;
esac
