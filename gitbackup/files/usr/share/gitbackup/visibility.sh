# shellcheck shell=sh
#
# gitbackup -- the visibility gate (spec "Гейт видимости").
#
# There is no encryption anywhere in this project, so this is the only thing
# standing between a public repository and the root password hash, private
# dropbear host keys, WPA PSK and WireGuard keys it would carry. A public
# repository is exit 4 with no way to override it -- not a warning.
#
# Sourced, never executed: nothing here runs at load time. gb_visibility_ok
# calls gb_uci_get, gb_log, gb_die and gb_json_bool (lib.sh) and gb_parse_url/
# gb_provider (remoteurl.sh), so a caller must source both first, same
# convention as device.sh.
#
# GB_STATE_DIR overrides the cache directory (default /var/run/gitbackup),
# the same variable usr/sbin/gitbackup already uses -- tests point it at a
# tmp directory, the router never sets it.

# gb_visibility_ok <url>
#
# Anonymously asks the provider's API whether <url>'s repository is visible
# to a passer-by, and returns:
#   0  not visible anonymously (404) or the operator explicitly accepted the
#      risk for a provider that cannot be checked at all -- proceed.
#   3  inconclusive: the network is down, the API answered 5xx, or answered
#      with an HTTP status this gate does not recognize. Deliberately NOT 0:
#      a caller that cannot tell "verified private" from "could not check"
#      apart would push on a repository nobody actually confirmed is closed
#      to the world. Reuses the shared network/auth exit code (interfaces.md,
#      "Коды выхода") rather than inventing a fifth one.
#   4  visible anonymously (HTTP 200) -- refused, unconditionally.
# Dies with exit 2 -- invalid configuration, same as every other config
# check in this package -- when <url> does not parse, or when the remote is
# provider=generic without gitbackup.origin.acknowledged=1 (nothing there
# can ever be checked, so silence would mean "assume private" on zero
# evidence, exactly the failure mode this whole gate exists to prevent).
gb_visibility_ok() {
	_gb_url="$1"
	_gb_parsed=$(gb_parse_url "$_gb_url") ||
		gb_die 2 "gitbackup.origin.url: '$_gb_url' does not match any supported remote URL form"
	# shellcheck disable=SC2086  # word-splitting is the point: five fields from one line
	set -- $_gb_parsed
	_gb_scheme="$1"
	_gb_host="$2"
	_gb_port="$3"
	_gb_owner="$4"
	_gb_repo="$5"

	_gb_provider=$(gb_provider "$_gb_host")

	if [ "$_gb_provider" = generic ]; then
		_gb_ack=$(gb_uci_get gitbackup.origin.acknowledged 0)
		if [ "$(gb_json_bool "$_gb_ack")" != true ]; then
			gb_die 2 "gitbackup.origin.provider=generic: visibility cannot be checked automatically; a public repository here would expose /etc/shadow, dropbear private host keys, authorized_keys, WPA PSK, WireGuard private keys, PPPoE credentials and uhttpd.key -- set gitbackup.origin.acknowledged=1 only after confirming the repository is actually private"
		fi
		gb_log notice "gitbackup.origin.provider=generic: visibility cannot be verified automatically, proceeding on the operator's acknowledgement (gitbackup.origin.acknowledged=1)"
		return 0
	fi

	_gb_state="${GB_STATE_DIR:-/var/run/gitbackup}"
	_gb_cache="$_gb_state/visibility"
	_gb_now=$(date +%s)
	if [ -r "$_gb_cache" ]; then
		_gb_cached_url=$(sed -n '1p' "$_gb_cache" 2>/dev/null)
		_gb_cached_ts=$(sed -n '2p' "$_gb_cache" 2>/dev/null)
		_gb_cached_code=$(sed -n '3p' "$_gb_cache" 2>/dev/null)
		case "$_gb_cached_ts" in
			''|*[!0-9]*) _gb_cached_ts='' ;;
		esac
		if [ "$_gb_cached_url" = "$_gb_url" ] && [ -n "$_gb_cached_ts" ] &&
			[ $((_gb_now - _gb_cached_ts)) -lt 86400 ] && [ $((_gb_now - _gb_cached_ts)) -ge 0 ]; then
			return "$_gb_cached_code"
		fi
	fi

	_gb_api_url=$(_gb_visibility_api_url "$_gb_provider" "$_gb_scheme" "$_gb_host" "$_gb_port" "$_gb_owner" "$_gb_repo") ||
		gb_die 1 "gitbackup: no anonymous visibility API is known for provider '$_gb_provider'"

	_gb_visibility_probe "$_gb_api_url"
	case $? in
		0)
			_gb_result=4
			gb_log warning "$_gb_url is visible to an anonymous request ($_gb_api_url -> HTTP 200); push refused"
			;;
		1)
			_gb_result=0
			;;
		*)
			# Inconclusive: never cache a guess, so the very next call (this run
			# or the next) tries the network again instead of trusting a stale
			# "could not tell" for a whole day.
			return 3
			;;
	esac

	mkdir -p "$_gb_state" 2>/dev/null
	printf '%s\n%s\n%s\n' "$_gb_url" "$_gb_now" "$_gb_result" >"$_gb_cache" 2>/dev/null
	return "$_gb_result"
}

# _gb_visibility_api_url <provider> <scheme> <host> <port> <owner> <repo>
#
# The anonymous, unauthenticated read-only endpoint each provider answers
# with 200 (visible) or 404 (not visible/does not exist) for -- spec
# "Гейт видимости" and "Проверенные факты 25.12.4 → Провайдеры", each row
# measured against the real API, not guessed. Always https: git access may
# be over ssh, but every one of these platforms serves its API over https on
# the same host. Returns 1 for a provider with no known API (generic, or
# anything gitbackup.origin.provider names that this gate does not recognize).
_gb_visibility_api_url() {
	case "$1" in
		github)
			printf 'https://api.github.com/repos/%s/%s\n' "$5" "$6"
			;;
		bitbucket)
			printf 'https://api.bitbucket.org/2.0/repositories/%s/%s\n' "$5" "$6"
			;;
		gitlab)
			printf 'https://%s/api/v4/projects/%s%%2F%s\n' "$(_gb_hostport_for_api "$2" "$3" "$4")" "$5" "$6"
			;;
		gitea)
			printf 'https://%s/api/v1/repos/%s/%s\n' "$(_gb_hostport_for_api "$2" "$3" "$4")" "$5" "$6"
			;;
		*)
			return 1
			;;
	esac
}

# _gb_hostport_for_api <scheme> <host> <port> -- host[:port] for the same
# server's HTTPS API.
#
# Only a port that was itself already on an https:// remote is trustworthy
# here. A scp-like or ssh:// remote's port is dropbear/openssh's, which a
# self-hosted Gitea/Forgejo/GitLab install commonly runs on a different port
# than its web UI (e.g. ssh on 2222, https on the default 443) -- carrying
# it over would probe the wrong port.
_gb_hostport_for_api() {
	if [ "$1" = https ] && [ "${3:-0}" != 0 ]; then
		printf '%s:%s\n' "$2" "$3"
	else
		printf '%s\n' "$2"
	fi
}

# _gb_visibility_probe <api-url>
#
# Returns 0 when the repository is visible anonymously (HTTP 200), 1 when it
# is not (HTTP 404 -- private and nonexistent are the same answer here on
# purpose, spec: "приватный анонимно неотличим от несуществующего"), 2 for
# anything else: another HTTP status, a timeout, a refused connection, a TLS
# failure, or offline. -q is deliberately not passed to uclient-fetch: the
# only place it prints "HTTP error <code>" is to stderr, and only when not
# quiet -- verified against uclient/uclient-fetch.c (header_done_cb's default
# case; net/error branches for connection/timeout/TLS return non-8 codes and
# are folded into the same "inconclusive" outcome here as any other network
# failure).
_gb_visibility_probe() {
	_gb_probe_msg=$(uclient-fetch --timeout=10 -O /dev/null "$1" 2>&1 >/dev/null)
	_gb_probe_rc=$?
	case "$_gb_probe_rc" in
		0) return 0 ;;
		8)
			case "$_gb_probe_msg" in
				*'HTTP error 404'*) return 1 ;;
				*)
					gb_log info "gitbackup visibility check: $1 -> $_gb_probe_msg"
					return 2
					;;
			esac
			;;
		*)
			gb_log info "gitbackup visibility check: $1 unreachable ($_gb_probe_msg)"
			return 2
			;;
	esac
}
