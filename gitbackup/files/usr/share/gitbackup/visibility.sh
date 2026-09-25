# shellcheck shell=sh
#
# gitbackup -- the visibility gate: gb_visibility_ok. With no encryption, this
# is all that keeps /etc/shadow, host keys and PSKs out of a public repo:
# public is exit 4 with no override. Needs lib.sh and remoteurl.sh.

# gb_visibility_ok <url> -- anonymous provider API probe:
#   0  not visible anonymously (404) -- proceed.
#   3  inconclusive (offline, 5xx, unknown status). Never 0: "could not
#      check" must not be treated as "private".
#   4  visible anonymously (200) -- refused.
# Dies 2 on an unparsable URL, or on provider=generic without
# gitbackup.origin.acknowledged=1 (nothing to check; silence is not proof).
# Definite answers are cached for 24h.
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
			# Inconclusive: never cached, so the next call retries.
			return 3
			;;
	esac

	mkdir -p "$_gb_state" 2>/dev/null
	printf '%s\n%s\n%s\n' "$_gb_url" "$_gb_now" "$_gb_result" >"$_gb_cache" 2>/dev/null
	return "$_gb_result"
}

# Anonymous endpoint answering 200 (visible) / 404 (not); https even for ssh
# remotes. Returns 1 for a provider with no known API.
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

# Keeps the port only from an https remote; an ssh port is not the API port.
_gb_hostport_for_api() {
	if [ "$1" = https ] && [ "${3:-0}" != 0 ]; then
		printf '%s:%s\n' "$2" "$3"
	else
		printf '%s\n' "$2"
	fi
}

# 0 on 200, 1 on 404 (private and nonexistent look the same), 2 otherwise.
# No -q: uclient-fetch prints "HTTP error <code>" only when not quiet, and
# exit 8 alone does not tell 404 from other statuses.
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
