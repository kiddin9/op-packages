# shellcheck shell=sh
#
# gitbackup -- remote URL parsing: gb_parse_url, gb_provider. Needs lib.sh.

# gb_parse_url <url> -- accepts [user@]host:owner/repo, ssh://[user@]host[:port]/
# owner/repo, https://host[:port]/owner/repo (".git" optional). Prints
# "scheme host port owner repo", port 0 when absent. Anything else: return 1,
# no output -- never half-parses.
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
			return 1
			;;
		*:*)
			# git treats it as scp-like only with no '/' before the first ':'.
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

# Sets _gb_host, _gb_port, _gb_owner, _gb_repo.
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

# Exactly one '/': nested groups are refused, not guessed at.
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

_gb_charset_ok() {
	[ -n "$1" ] || return 1
	case "$1" in
		*[!A-Za-z0-9._-]*) return 1 ;;
	esac
	return 0
}

# gb_provider <host> -- a non-auto gitbackup.origin.provider wins (self-hosted
# escape hatch). codeberg.org is Forgejo, whose API is Gitea's.
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
