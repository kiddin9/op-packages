# shellcheck shell=sh
#
# gitbackup -- remote URL parsing, provider detection, deploy-key deep links
# (spec "Парсер remote URL", brief §5.3).
#
# Sourced, never executed: nothing here runs at load time. gb_provider reads
# gitbackup.origin.provider through gb_uci_get (lib.sh), so a caller must
# source lib.sh first, same convention as device.sh.

# gb_parse_url <url>
#
# Parses one of the four remote URL forms the spec requires, with or without
# a trailing ".git":
#   git@host:owner/repo.git              scp-like (git's own alias syntax)
#   ssh://[user@]host[:port]/owner/repo.git
#   https://host[:port]/owner/repo.git
#
# Prints "scheme host port owner repo" on one line, so a caller does
# `set -- $(gb_parse_url "$url")`. port is "0" when the URL did not name
# one -- the parser does not guess a scheme's default port, because what
# that default even means differs by caller (auth.sh's ssh -p vs.
# visibility.sh's HTTPS API host, see visibility.sh's _gb_hostport_for_api).
#
# Returns 1 and prints nothing on anything that is not one of the three
# forms above, or where owner/repo fail the charset check -- a mangled URL
# must fail outright, never be parsed halfway into a wrong-but-plausible
# result (ticket 03 acceptance criterion).
gb_parse_url() {
	_gb_u="$1"
	_gb_scheme=''
	_gb_host=''
	_gb_port=''
	_gb_owner=''
	_gb_repo=''

	case "$_gb_u" in
		https://*)
			_gb_scheme=https
			_gb_rest="${_gb_u#https://}"
			_gb_parse_hostport_path "$_gb_rest" || return 1
			;;
		ssh://*)
			_gb_scheme=ssh
			_gb_rest="${_gb_u#ssh://}"
			case "$_gb_rest" in
				*@*) _gb_rest="${_gb_rest#*@}" ;;
			esac
			_gb_parse_hostport_path "$_gb_rest" || return 1
			;;
		*://*)
			# Some other scheme (git://, ftp://, ...) -- not one of the three
			# forms the spec names, refused rather than guessed at.
			return 1
			;;
		*:*)
			# scp-like alias syntax: "[user@]host:owner/repo(.git)?". Git itself
			# only accepts this when the part before the first ':' has no '/' --
			# that is what tells it apart from a local path or an already-handled
			# scheme above.
			_gb_scheme=ssh
			_gb_port=''
			_gb_userhost="${_gb_u%%:*}"
			case "$_gb_userhost" in
				*/*) return 1 ;;
			esac
			[ -n "$_gb_userhost" ] || return 1
			case "$_gb_userhost" in
				*@*) _gb_host="${_gb_userhost#*@}" ;;
				*) _gb_host="$_gb_userhost" ;;
			esac
			_gb_parse_ownerrepo "${_gb_u#*:}" || return 1
			;;
		*)
			return 1
			;;
	esac

	[ -n "$_gb_host" ] || return 1
	printf '%s %s %s %s %s\n' "$_gb_scheme" "$_gb_host" "${_gb_port:-0}" "$_gb_owner" "$_gb_repo"
}

# _gb_parse_hostport_path <host[:port]/owner/repo[.git]>
#
# Shared by the https:// and ssh:// branches once their scheme prefix (and,
# for ssh://, an optional user@) is already stripped. Sets _gb_host, _gb_port
# and, through _gb_parse_ownerrepo, _gb_owner/_gb_repo.
_gb_parse_hostport_path() {
	_gb_r="$1"
	case "$_gb_r" in
		*/*) ;;
		*) return 1 ;;
	esac
	_gb_hostport="${_gb_r%%/*}"
	_gb_path="${_gb_r#*/}"
	case "$_gb_hostport" in
		*:*)
			_gb_host="${_gb_hostport%%:*}"
			_gb_port="${_gb_hostport#*:}"
			case "$_gb_port" in
				''|*[!0-9]*) return 1 ;;
			esac
			;;
		*)
			_gb_host="$_gb_hostport"
			_gb_port=''
			;;
	esac
	[ -n "$_gb_host" ] || return 1
	_gb_parse_ownerrepo "$_gb_path"
}

# _gb_parse_ownerrepo <owner/repo[.git]> -- sets _gb_owner and _gb_repo.
#
# Exactly one '/' is allowed: nested groups ("group/subgroup/repo") are not
# one of the four supported forms and are refused, not guessed at.
_gb_parse_ownerrepo() {
	_gb_p="$1"
	case "$_gb_p" in
		*/*/*) return 1 ;;
		*/*) ;;
		*) return 1 ;;
	esac
	_gb_owner="${_gb_p%%/*}"
	_gb_repo="${_gb_p#*/}"
	_gb_repo="${_gb_repo%.git}"
	_gb_charset_ok "$_gb_owner" || return 1
	_gb_charset_ok "$_gb_repo" || return 1
	return 0
}

# _gb_charset_ok <string> -- non-empty and only [A-Za-z0-9._-].
_gb_charset_ok() {
	[ -n "$1" ] || return 1
	case "$1" in
		*[!A-Za-z0-9._-]*) return 1 ;;
	esac
	return 0
}

# gb_provider <host>
#
# github.com/gitlab.com/bitbucket.org/codeberg.org are recognized by host;
# anything else is "generic" unless gitbackup.origin.provider names one
# explicitly, which always wins over host detection (ticket 03 acceptance
# criterion) -- the one escape hatch for a self-hosted GitLab/Gitea/Forgejo
# instance, which cannot be told apart from an unknown host by name alone.
#
# codeberg.org maps to "gitea": Codeberg runs Forgejo, whose anonymous repo
# API is the same shape as Gitea's (spec, "Проверенные факты 25.12.4 →
# Провайдеры"), and gitbackup.origin.provider's enum has no separate
# "codeberg"/"forgejo" value to return instead.
gb_provider() {
	_gb_host="$1"
	_gb_opt=$(gb_uci_get gitbackup.origin.provider auto)
	case "$_gb_opt" in
		auto) ;;
		*) printf '%s\n' "$_gb_opt"; return 0 ;;
	esac
	case "$_gb_host" in
		github.com) printf 'github\n' ;;
		gitlab.com) printf 'gitlab\n' ;;
		bitbucket.org) printf 'bitbucket\n' ;;
		codeberg.org) printf 'gitea\n' ;;
		*) printf 'generic\n' ;;
	esac
}

# gb_deeplink <provider> <scheme> <host> <owner> <repo>
#
# A URL to the provider's "add deploy key" page, or -- for generic, which has
# no such page anywhere -- an instruction to add the key to authorized_keys
# by hand (brief §5.3).
#
# GitHub and Bitbucket are hardcoded to their one cloud host: gb_provider
# only ever returns "github"/"bitbucket" for github.com/bitbucket.org, so
# there is no self-hosted variant to build a different host for. GitLab and
# Gitea/Forgejo are commonly self-hosted, so their link is built from the
# remote's own host instead -- the brief's table shows a gitlab.com example,
# but GitLab's repository-settings page lives at the same path on every
# instance, not just gitlab.com. <scheme> is coerced to https: a deploy-key
# page is only ever reachable over the web, but the parsed scheme is often
# "ssh" (the git remote's own transport, from an scp-like or ssh:// URL),
# which is never a valid scheme for a browser link.
gb_deeplink() {
	_gb_p="$1"
	_gb_sch="$2"
	_gb_h="$3"
	_gb_o="$4"
	_gb_r="$5"
	case "$_gb_sch" in
		http|https) ;;
		*) _gb_sch=https ;;
	esac
	case "$_gb_p" in
		github)
			# VERIFY: an anonymous request to /settings/keys/new returns 404 for
			# both a real and a garbage owner/repo (spec, "Проверенные факты"),
			# so unlike the other three this exact path could not be confirmed
			# by the same probe -- it is GitHub's documented deploy-key URL, not
			# a measured one.
			printf 'https://github.com/%s/%s/settings/keys/new\n' "$_gb_o" "$_gb_r"
			;;
		gitlab)
			printf '%s://%s/%s/%s/-/settings/repository\n' "$_gb_sch" "$_gb_h" "$_gb_o" "$_gb_r"
			;;
		gitea)
			printf '%s://%s/%s/%s/settings/keys\n' "$_gb_sch" "$_gb_h" "$_gb_o" "$_gb_r"
			;;
		bitbucket)
			printf 'https://bitbucket.org/%s/%s/admin/access-keys/\n' "$_gb_o" "$_gb_r"
			;;
		*)
			printf 'No provider API to link to; add the deploy key to ~/.ssh/authorized_keys for the git user on %s, ideally with restrict,command="git-shell".\n' "$_gb_h"
			;;
	esac
}
