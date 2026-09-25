# shellcheck shell=sh
#
# gitbackup -- remote access: gb_git_env, gb_keygen, gb_keygen_forget_old,
# gb_pubkey, gb_accept_hostkey, gb_hostkey_show, gb_hostkey_accept. Needs lib.sh.
GB_ETC_DIR="${GB_ETC_DIR:-/etc/gitbackup}"

# gb_git_env -- "export KEY='VALUE'" lines for `eval "$(gb_git_env)"`.
# ConnectTimeout: BatchMode does not cover the TCP handshake, and a host that
# drops packets would hang ssh for minutes.
#
# Must be OpenSSH `ssh`, not dbclient: git's ssh-variant probe fails on it and
# falls back to "simple", dropping every -o option, host-key checking included.
#
# TLS verification can never be turned off; ca_file is the only way to trust
# a private CA. The token is never printed: askpass.sh reads it on demand.
gb_git_env() {
	_gb_key=$(gb_uci_get gitbackup.origin.key_file /etc/gitbackup/id_ed25519)
	_gb_known="$GB_ETC_DIR/known_hosts"
	_gb_ssh_cmd="ssh -i $(_gb_auth_shquote "$_gb_key") -o UserKnownHostsFile=$(_gb_auth_shquote "$_gb_known") -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=15"

	printf 'export GIT_SSH_COMMAND=%s\n' "$(_gb_auth_shquote "$_gb_ssh_cmd")"
	printf 'export GIT_ASKPASS=%s\n' "$(_gb_auth_shquote "${GB_SHARE:-/usr/share/gitbackup}/askpass.sh")"
	printf 'export GIT_TERMINAL_PROMPT=%s\n' "$(_gb_auth_shquote 0)"

	_gb_ca=$(gb_uci_get gitbackup.origin.ca_file)
	[ -n "$_gb_ca" ] && printf 'export GIT_SSL_CAINFO=%s\n' "$(_gb_auth_shquote "$_gb_ca")"
	return 0
}

_gb_auth_shquote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

_gb_auth_key_fingerprint() {
	_gb_akf_key="$1"
	if [ -r "$_gb_akf_key.pub" ]; then
		ssh-keygen -lf "$_gb_akf_key.pub" 2>/dev/null
	elif [ -r "$_gb_akf_key" ]; then
		ssh-keygen -lf "$_gb_akf_key" 2>/dev/null
	fi
}

# gb_keygen [force] [confirm-fingerprint] -- no passphrase: BatchMode=yes
# would make an encrypted key hang every push.
#
# Replacing a key cuts off every remote it is registered with, so it takes
# force AND the current fingerprint named back:
#   key, no force             -- refuse, 1
#   key, force, no/wrong fp   -- print "confirm-required <fp>", destroy
#                                nothing, 4
#   key, force, matching fp   -- keep <key>.old(.pub) for manual rollback,
#                                regenerate, 0
gb_keygen() {
	_gb_force="${1:-}"
	_gb_confirm="${2:-}"
	_gb_key=$(gb_uci_get gitbackup.origin.key_file /etc/gitbackup/id_ed25519)
	if [ -z "$_gb_key" ]; then
		gb_log err 'gb_keygen: gitbackup.origin.key_file is empty'
		return 1
	fi

	if [ -e "$_gb_key" ]; then
		if [ -z "$_gb_force" ]; then
			gb_log err "gb_keygen: $_gb_key already exists; pass a non-empty force argument to replace it"
			return 1
		fi

		_gb_fp=$(_gb_auth_key_fingerprint "$_gb_key")
		if [ -z "$_gb_confirm" ] || [ "$_gb_confirm" != "$_gb_fp" ]; then
			if [ -n "$_gb_confirm" ]; then
				gb_log err "gb_keygen: confirmation fingerprint does not match the key currently at $_gb_key; refusing"
			fi
			printf 'confirm-required %s\n' "$_gb_fp"
			return 4
		fi

		# Best effort: must not block a confirmed regeneration.
		cp -f "$_gb_key" "$_gb_key.old" 2>/dev/null && chmod 0600 "$_gb_key.old" 2>/dev/null
		[ -e "$_gb_key.pub" ] && cp -f "$_gb_key.pub" "$_gb_key.old.pub" 2>/dev/null
	fi

	_gb_dir=$(dirname "$_gb_key")
	mkdir -p "$_gb_dir" || { gb_log err "gb_keygen: cannot create $_gb_dir"; return 1; }
	chmod 0700 "$_gb_dir" || return 1

	rm -f "$_gb_key" "$_gb_key.pub"
	if ! ssh-keygen -t ed25519 -N '' -C gitbackup -f "$_gb_key" >/dev/null; then
		gb_log err "gb_keygen: ssh-keygen failed for $_gb_key"
		return 1
	fi
	chmod 0600 "$_gb_key" || return 1
	[ -e "$_gb_key.pub" ] && chmod 0644 "$_gb_key.pub"
	gb_log notice "gb_keygen: generated $_gb_key"
	return 0
}

# Called once `gitbackup test` has proven the current key works.
gb_keygen_forget_old() {
	_gb_key=$(gb_uci_get gitbackup.origin.key_file /etc/gitbackup/id_ed25519)
	rm -f "$_gb_key.old" "$_gb_key.old.pub"
}

gb_pubkey() {
	_gb_key=$(gb_uci_get gitbackup.origin.key_file /etc/gitbackup/id_ed25519)
	if [ -r "$_gb_key.pub" ]; then
		cat "$_gb_key.pub"
		return 0
	fi
	if [ -r "$_gb_key" ]; then
		ssh-keygen -y -f "$_gb_key"
		return $?
	fi
	gb_log err "gb_pubkey: no key at $_gb_key; run 'gitbackup keygen' first"
	return 1
}

# _gb_auth_dial_hostkey <host> <port> <out-file> -- no ssh-keyscan in
# openssh-client: key exchange precedes auth, so accept-new against an empty
# scratch known_hosts records the key even though auth fails. 2 unreachable.
_gb_auth_dial_hostkey() {
	_gb_adh_host="$1"
	_gb_adh_port="$2"
	_gb_adh_out="$3"
	rm -f "$_gb_adh_out"

	ssh -o UserKnownHostsFile="$_gb_adh_out" -o StrictHostKeyChecking=accept-new \
		-o BatchMode=yes -o ConnectTimeout=15 -p "$_gb_adh_port" "git@$_gb_adh_host" exit >/dev/null 2>&1

	if [ ! -s "$_gb_adh_out" ]; then
		rm -f "$_gb_adh_out"
		return 2
	fi
	return 0
}

# gb_hostkey_accept commits exactly the bytes gb_hostkey_show fetched, never
# a fresh dial, so what the operator confirmed is what gets trusted.
_gb_hostkey_pending_file() {
	printf '%s/hostkey_pending' "$GB_ETC_DIR"
}

# Sets _gb_host, _gb_port, _gb_known; true when already in known_hosts.
_gb_hostkey_init() {
	_gb_host="$1"
	_gb_port="${2:-22}"
	[ "$_gb_port" != 0 ] || _gb_port=22
	mkdir -p "$GB_ETC_DIR" 2>/dev/null
	_gb_known="$GB_ETC_DIR/known_hosts"
	[ -r "$_gb_known" ] && ssh-keygen -F "$_gb_host" -f "$_gb_known" >/dev/null 2>&1
}

_gb_hostkey_record() {
	cat "$1" >>"$_gb_known"
	chmod 0600 "$_gb_known"
	rm -f "$1"
	gb_log notice "$2: $_gb_host:$_gb_port accepted and recorded in $_gb_known"
}

# gb_accept_hostkey <host> [port] -- terminal prompt; never trusts silently.
# 0 trusted, 1 declined, 2 unreachable, 3 no stdin (web uses show/accept).
gb_accept_hostkey() {
	_gb_hostkey_init "$1" "${2:-}" && return 0

	_gb_scratch=$(mktemp "${TMPDIR:-/tmp}/gitbackup-hostkey.XXXXXX") || return 2
	if ! _gb_auth_dial_hostkey "$_gb_host" "$_gb_port" "$_gb_scratch"; then
		gb_log err "gb_accept_hostkey: could not reach $_gb_host:$_gb_port to obtain its host key"
		return 2
	fi

	_gb_fp=$(ssh-keygen -lf "$_gb_scratch" 2>/dev/null)
	printf 'Host key for %s:%s --\n  %s\nAccept and remember it? [y/N] ' "$_gb_host" "$_gb_port" "$_gb_fp" >&2

	if ! IFS= read -r _gb_ans; then
		rm -f "$_gb_scratch"
		gb_log err "gb_accept_hostkey: $_gb_host:$_gb_port could not ask for confirmation -- no interactive input is available here. Run 'gitbackup test' from a terminal with a real stdin, or accept the host key from the LuCI web UI (Settings -> Connection test), which uses 'gitbackup hostkey show'/'hostkey accept' for exactly this case."
		return 3
	fi
	case "$_gb_ans" in
		y|Y|yes|YES) ;;
		*)
			rm -f "$_gb_scratch"
			gb_log notice "gb_accept_hostkey: $_gb_host:$_gb_port declined by the operator"
			return 1
			;;
	esac

	_gb_hostkey_record "$_gb_scratch" gb_accept_hostkey
}

# gb_hostkey_show <host> [port] -- "trusted <host> <port>" or
# "pending <host> <port> <fp>". Records nothing. 2 when unreachable.
gb_hostkey_show() {
	if _gb_hostkey_init "$1" "${2:-}"; then
		printf 'trusted %s %s\n' "$_gb_host" "$_gb_port"
		return 0
	fi

	_gb_pending=$(_gb_hostkey_pending_file)
	if ! _gb_auth_dial_hostkey "$_gb_host" "$_gb_port" "$_gb_pending"; then
		gb_log err "gb_hostkey_show: could not reach $_gb_host:$_gb_port to obtain its host key"
		return 2
	fi
	chmod 0600 "$_gb_pending"

	_gb_fp=$(ssh-keygen -lf "$_gb_pending" 2>/dev/null)
	printf 'pending %s %s %s\n' "$_gb_host" "$_gb_port" "$_gb_fp"
	return 0
}

# gb_hostkey_accept <host> <port> <fp> -- only on an exact fingerprint match.
# 1 nothing pending, 4 mismatch.
gb_hostkey_accept() {
	_gb_hostkey_init "$1" "${2:-}"
	_gb_want_fp="$3"

	_gb_pending=$(_gb_hostkey_pending_file)
	if [ ! -s "$_gb_pending" ]; then
		gb_log err "gb_hostkey_accept: no pending host key for $_gb_host:$_gb_port -- run 'gitbackup hostkey show' first"
		return 1
	fi

	_gb_have_fp=$(ssh-keygen -lf "$_gb_pending" 2>/dev/null)
	if [ -z "$_gb_want_fp" ] || [ "$_gb_have_fp" != "$_gb_want_fp" ]; then
		gb_log err "gb_hostkey_accept: fingerprint for $_gb_host:$_gb_port does not match the pending host key -- refusing"
		return 4
	fi

	_gb_hostkey_record "$_gb_pending" gb_hostkey_accept
}
