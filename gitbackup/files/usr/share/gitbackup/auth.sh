# shellcheck shell=sh
#
# gitbackup -- access to the remote (spec "Аутентификация").
#
# Exposes gb_git_env, gb_keygen, gb_pubkey and gb_accept_hostkey; every
# _gb_auth_-prefixed helper below is private and namespaced by module, same
# convention collect.sh uses (multiple *.sh here end up sourced into the
# same process by usr/sbin/gitbackup, so a bare _gb_ helper name could
# collide with a sibling module's). Sourced, never executed: nothing here
# runs at load time -- GB_ETC_DIR below is a variable assignment from an
# environment default, not a filesystem access.
#
# Depends on lib.sh (gb_log, gb_uci_get) already being sourced by the
# caller, same convention every other module here uses.
#
# GB_ETC_DIR overrides gitbackup's own secrets directory (default
# /etc/gitbackup). It is deliberately NOT a UCI option: gitbackup.origin.
# key_file and .token_file already give the operator a path for those two,
# but known_hosts has no such option in the shipped schema (spec:
# "known_hosts лежит в /etc/gitbackup/", a fixed location, not configurable)
# -- this exists only so tests/run.sh can point it at a tmp directory
# instead of the real /etc/gitbackup, the same seam GB_ROOT/GB_STATE_DIR/
# GB_SYSFS_NET give the other modules.
GB_ETC_DIR="${GB_ETC_DIR:-/etc/gitbackup}"

# gb_git_env
#
# Prints "export KEY='VALUE'" lines, one per line, quoted so a caller can
# safely `eval "$(gb_git_env)"` even though GIT_SSH_COMMAND's value itself
# contains spaces -- and so the assignments are exported into the calling
# shell's environment, where the `git` child process this whole thing
# exists for can actually see them.
#
# GIT_SSH_COMMAND and GIT_ASKPASS are both always printed, regardless of
# gitbackup.origin.auth: it is the git remote URL's own scheme (ssh:// vs
# https://), not this option, that decides which one a given `git`
# invocation actually uses -- ssh transport never calls GIT_ASKPASS for
# anything, and GIT_SSH_COMMAND is simply inert for an https transport. Not
# branching on .auth here means there is exactly one thing to keep in sync
# with the remote URL parser (remoteurl.sh) instead of two.
#
# GIT_SSH_COMMAND carries the four options the spec names by name: -i (the
# deploy key), UserKnownHostsFile (this package's own known_hosts, never
# the invoking user's ~/.ssh/known_hosts -- a stale entry there must not be
# able to either accept or block this package's own host-key decision),
# StrictHostKeyChecking=yes (an unknown or changed host key is refused,
# full stop -- gitbackup test is the only place that ever adds one) and
# BatchMode=yes (never fall back to an interactive passphrase/password
# prompt that would hang a cron job forever) -- plus ConnectTimeout=15, not
# named in the spec but added after a live failure on the owlab stand: a
# host that never answers at all (as opposed to actively refusing the
# connection) leaves `ssh` hanging with neither of those two safeguards to
# stop it, well past two minutes with no output. BatchMode only rules out
# an interactive *prompt*; it does nothing about the TCP handshake itself
# never completing, which is exactly what a firewalled or simply
# nonexistent host looks like.
#
# GIT_SSL_CAINFO is printed only when gitbackup.origin.ca_file is set, and
# is the only sanctioned way to talk to a self-signed/private-CA remote:
# GIT_SSL_NO_VERIFY and http.sslVerify=false are refused even as an option
# by this package, spec "Аутентификация" and "Границы и швы" -- there is no
# code path anywhere in this package that can turn certificate verification
# off, only one that can hand it an extra trusted certificate.
#
# _gb_ssh_cmd below is built as a plain `ssh ...` command, not busybox's
# `dbclient` -- and this StrictHostKeyChecking=yes option is exactly why.
# Measured on the 25.12.4 stand (dropbear 2025.89, git 2.50.1): with
# GIT_SSH_COMMAND set to a dbclient invocation, `GIT_TRACE=1 git fetch`
# shows git's ssh-variant probe (`dbclient -G ...`, used to detect whether
# the ssh command understands OpenSSH's own option syntax) failing, after
# which git silently falls back to its "simple" transport form and stops
# passing any `-o NAME=VALUE` pair at all -- not just this one, every
# option this function sets, including UserKnownHostsFile and BatchMode.
# The failure is invisible: git does not warn that it dropped them, fetch
# still succeeds against a reachable host, and the option only turns out
# to have been a no-op the day host-key checking was supposed to catch
# something. That silent downgrade, not merely dbclient's separate inability
# to read OpenSSH-format keys (see package/gitbackup/Makefile), is why this
# package depends on the real openssh-client instead.
#
# Never prints the token itself: GIT_ASKPASS names askpass.sh's path, and
# the token is read off disk by askpass.sh's own process, later, only once
# git has actually decided it needs credentials.
gb_git_env() {
	_gb_key=$(gb_uci_get gitbackup.origin.key_file /etc/gitbackup/id_ed25519)
	_gb_known="$GB_ETC_DIR/known_hosts"
	_gb_ssh_cmd="ssh -i $(_gb_auth_shquote "$_gb_key") -o UserKnownHostsFile=$(_gb_auth_shquote "$_gb_known") -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=15"

	printf 'export GIT_SSH_COMMAND=%s\n' "$(_gb_auth_shquote "$_gb_ssh_cmd")"
	printf 'export GIT_ASKPASS=%s\n' "$(_gb_auth_shquote "${GB_SHARE:-/usr/share/gitbackup}/askpass.sh")"
	# Never let git fall back to its own interactive prompt on a real tty --
	# askpass.sh is the only credential source this package allows.
	printf 'export GIT_TERMINAL_PROMPT=%s\n' "$(_gb_auth_shquote 0)"

	_gb_ca=$(gb_uci_get gitbackup.origin.ca_file)
	[ -n "$_gb_ca" ] && printf 'export GIT_SSL_CAINFO=%s\n' "$(_gb_auth_shquote "$_gb_ca")"
	return 0
}

# _gb_auth_shquote <string> -- <string> wrapped in single quotes, with any
# single quote inside it escaped, so the result can be eval'd back to the
# original value regardless of what it contains (a path with a space is the
# realistic case here, not an adversarial one, but the quoting is correct
# either way).
_gb_auth_shquote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# _gb_auth_key_fingerprint <key-path>
#
# ssh-keygen -lf's own fingerprint line for whichever half of the pair is
# actually readable, preferring the public half (same preference order
# gb_pubkey below already uses) -- unlike gb_pubkey, this never needs the
# `-y` derivation fallback: `ssh-keygen -lf` accepts either a private or a
# public key file directly and prints the identical fingerprint for
# either, since the fingerprint is a hash of the public half alone.
_gb_auth_key_fingerprint() {
	_gb_akf_key="$1"
	if [ -r "$_gb_akf_key.pub" ]; then
		ssh-keygen -lf "$_gb_akf_key.pub" 2>/dev/null
	elif [ -r "$_gb_akf_key" ]; then
		ssh-keygen -lf "$_gb_akf_key" 2>/dev/null
	fi
}

# gb_keygen [force] [confirm-fingerprint]
#
# Generates the deploy key at gitbackup.origin.key_file (default
# /etc/gitbackup/id_ed25519): ed25519, no passphrase. No passphrase is
# deliberate, not an oversight -- GIT_SSH_COMMAND always carries
# BatchMode=yes (gb_git_env), which refuses to prompt for one, so an
# encrypted key would simply make every push hang forever instead of
# failing loudly.
#
# Refuses to overwrite a key that already exists unless <force> is a
# non-empty argument: losing the only copy of a deploy key locks every
# remote it was already added to until the operator notices and re-adds
# the new public half everywhere (ticket 04 acceptance criterion). This
# part of the contract is unchanged by ticket 25 below: `gitbackup keygen`
# with no `force` at all on an existing key behaves exactly as before.
#
# Ticket 25: `force` alone used to be enough to destroy the working key on
# the spot, no warning, no way back -- reported live from a real router
# where `keygen --force`, run only to see where the operation writes,
# silently ate the key a working deploy relied on. The private half is
# gone the instant the `rm -f` below runs, and every remote it had been
# added to as a deploy key stops authenticating that same instant, with
# nothing on this router able to undo either side of that.
#
# gb_hostkey_show/gb_hostkey_accept above already solved the equivalent
# problem for a different irreversible decision -- "confirm by naming
# exactly what was shown", not a bare y/N -- and this reuses that same
# shape instead of adding a `read` prompt here: a `read`-based prompt
# would need a second, separate branch for "no controlling terminal at
# all" (ticket 20's own EOF-is-neither-yes-nor-no lesson, gb_accept_hostkey
# above), and that branch would need testing on its own. Requiring the
# caller to name the fingerprint back sidesteps the distinction entirely --
# an interactive operator and a non-interactive script take the identical
# path, and there is no `read` anywhere in this function to hang or
# misread an EOF as a decision nobody made:
#
#   force set, no existing key            -- generates immediately, exactly
#                                             as before (nothing to confirm)
#   force unset, existing key             -- refused, exit 1, unchanged
#   force set, existing key, confirm      -- prints "confirm-required
#     empty or not matching the current   <fingerprint>" to stdout (nothing
#     key's own fingerprint               destroyed) and returns 4
#   force set, existing key, confirm      -- proceeds: the old key is kept
#     matches the current fingerprint     aside (see below) and a fresh one
#     exactly                             is generated; returns 0
#
# A caller that never asks (only ever passes `force`) gets told what is
# missing on every single call -- it can never destroy anything by
# accident, and it is never met with a bare, unexplained refusal either.
#
# Decision (ticket 25 leaves this to the implementer, either answer
# acceptable if justified): the key about to be destroyed is copied aside
# as "<key>.old"/"<key>.old.pub" before anything is removed, left there
# until gb_keygen_forget_old below is called. Nothing on this router ever
# reads ".old" back automatically -- there is deliberately no "fall back
# to the old key if the new one fails" logic, which would make a failed
# push ambiguous about which key actually ran and silently reintroduce the
# very key this whole flow just told the operator to stop using. The
# reason to keep it anyway is narrower: the one step this flow cannot
# verify from the router is whether the operator actually went to the
# provider and added the NEW public key before the next push runs. If they
# forgot, or pasted the wrong key, the router itself becomes unreachable
# over the only channel this package uses, and the file this comment is
# justifying is then the difference between "cp it back and try again" and
# "nothing, the old private half is just gone" -- for the cost of one
# extra ~400-byte file that a successful `gitbackup test` (cmd_test,
# usr/sbin/gitbackup) removes on its own the first time the NEW key is
# actually proven to work. Deleting outright instead (the spec's other
# sanctioned answer) would not shorten the provider trip either way; it
# would only remove this one way an already-bad day gets worse.
#
# Creates the key's directory at 0700 if it does not exist yet (uci-
# defaults/99-gitbackup already does this for the default /etc/gitbackup,
# but gitbackup.origin.key_file can point anywhere), and leaves the
# private key at 0600 -- ssh-keygen's own default, asserted here rather
# than trusted, since a future ssh-keygen with a different umask-derived
# default would otherwise change this package's security posture with no
# code change on this side to catch it.
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

		# Confirmed: keep the outgoing key's own copy before touching
		# anything -- see this function's header comment for why. Best
		# effort on purpose (2>/dev/null): a failure to write the backup
		# copy must never block the regeneration the operator explicitly
		# confirmed, only mean there is nothing to roll back to.
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

# gb_keygen_forget_old
#
# Ticket 25's other half of the id_ed25519.old decision above (gb_keygen's
# own header comment): removes the pre-regeneration copy once something has
# actually proven the CURRENT key works end to end. Called from cmd_test's
# own success path (usr/sbin/gitbackup) -- a successful `git ls-remote`
# against the configured remote is the one signal this package already
# computes that means "the key at key_file is accepted by the provider
# right now", which is exactly the event this flow is waiting for. A no-op
# whenever there is nothing to forget (the overwhelming majority of
# successful `test` runs never followed a keygen at all), so this is safe
# to call unconditionally on every success rather than tracking anywhere
# whether a keygen happened first.
gb_keygen_forget_old() {
	_gb_key=$(gb_uci_get gitbackup.origin.key_file /etc/gitbackup/id_ed25519)
	rm -f "$_gb_key.old" "$_gb_key.old.pub"
}

# gb_pubkey
#
# Prints the deploy key's public half. Reads the already-generated .pub
# file when it is there (the common case, ssh-keygen always writes one),
# and falls back to deriving it from the private key with `ssh-keygen -y`
# only if that file is missing -- an operator could plausibly delete just
# the .pub half by hand and expect this to still work.
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

# _gb_auth_dial_hostkey <host> <port> <out-file>
#
# The dial step gb_accept_hostkey and gb_hostkey_show below both need,
# factored out so there is exactly one place that knows how to fetch a raw
# host key off the wire. There is no ssh-keyscan on this image without
# pulling in the separate openssh-client-utils package (measured on the
# 25.12.4 stand: `apk info -L openssh-client openssh-keygen` together
# provide neither ssh-keyscan nor any equivalent) -- rather than growing
# DEPENDS for one command, this reuses the `ssh` binary DEPENDS already
# carries. The SSH protocol completes its host-key exchange before user
# authentication even starts, so `ssh -o StrictHostKeyChecking=accept-new
# -o BatchMode=yes` against a scratch, empty known_hosts file writes the
# host's key into it regardless of whether the authentication that follows
# succeeds -- verified live on the owlab stand: `ssh -o
# UserKnownHostsFile=<scratch> -o StrictHostKeyChecking=accept-new -o
# BatchMode=yes git@github.com exit` still populates <scratch> with
# github.com's key even though the command itself exits 255 on "Permission
# denied (publickey)" right after, because no key for github.com had
# actually been added yet.
#
# Writes <out-file> and returns 0 when a key was obtained, or returns 2
# with <out-file> removed when nothing could be obtained at all (host
# unreachable, connection refused, DNS failure).
_gb_auth_dial_hostkey() {
	_gb_adh_host="$1"
	_gb_adh_port="$2"
	_gb_adh_out="$3"
	rm -f "$_gb_adh_out"

	# ConnectTimeout=15: same reasoning as gb_git_env's own copy of it -- a
	# host that never answers at all, rather than actively refusing,
	# otherwise leaves this hanging well past two minutes (measured live).
	ssh -o UserKnownHostsFile="$_gb_adh_out" -o StrictHostKeyChecking=accept-new \
		-o BatchMode=yes -o ConnectTimeout=15 -p "$_gb_adh_port" "git@$_gb_adh_host" exit >/dev/null 2>&1

	if [ ! -s "$_gb_adh_out" ]; then
		rm -f "$_gb_adh_out"
		return 2
	fi
	return 0
}

# _gb_hostkey_pending_file -- fixed path under GB_ETC_DIR, never part of
# known_hosts itself. Holds the raw known_hosts-format line(s) for the
# LAST host key gb_hostkey_show fetched, and nothing else: gb_hostkey_accept
# below commits exactly this file's bytes, never a fresh dial of its own
# (see gb_hostkey_accept's own header comment for why that distinction is
# the whole point of the two-step design).
_gb_hostkey_pending_file() {
	printf '%s/hostkey_pending' "$GB_ETC_DIR"
}

# gb_accept_hostkey <host> [port]
#
# Interactive, and only ever meant to be called from `gitbackup test`
# (spec: "Host key принимается только внутри gitbackup test"). Fetches the
# host's SSH key, shows its fingerprint on stderr, asks for a yes/no on
# stdin, and only on "yes" appends it to this package's own known_hosts
# (GB_ETC_DIR/known_hosts) -- never the invoking user's ~/.ssh/known_hosts.
#
# Returns 0 once the key is confirmed and recorded (or was already known --
# see the ssh-keygen -F check below, which makes this safe to call
# unconditionally from `gitbackup test` every time), 1 when the operator
# explicitly declines, 2 when no host key could be obtained at all (host
# unreachable, connection refused, DNS failure), 3 when there was no way to
# even ASK the operator (ticket 20: `read` hit EOF -- no controlling
# terminal at all, e.g. rpcd's own `gitbackup test </dev/null`). 3 used to
# be indistinguishable from 1 here: the old code fed `read`'s result
# straight into the `case` below without ever looking at `read`'s own exit
# status, so an EOF -- which busybox ash's `read` reports as a nonzero
# return with `_gb_ans` left empty -- fell into the same "not y" branch a
# real, typed "no" does, logging "declined by the operator" for an operator
# who was never actually asked. Reported live against a real GitHub deploy
# key on a real router: `gitbackup test` run from `gbrpc_test` (stdin
# `</dev/null` by construction, ticket 20) always produced that exact
# false accusation, and offered no way to accept the key from the web at
# all -- gb_hostkey_show/gb_hostkey_accept below are that way.
gb_accept_hostkey() {
	_gb_host="$1"
	_gb_port="${2:-22}"
	case "$_gb_port" in
		''|0) _gb_port=22 ;;
	esac

	mkdir -p "$GB_ETC_DIR" 2>/dev/null
	_gb_known="$GB_ETC_DIR/known_hosts"

	# Already trusted: nothing to accept. Asked of ssh-keygen itself, not a
	# raw grep, so a known_hosts entry hashed with -H (never written by this
	# package, but nothing stops an operator from hand-editing the file) is
	# still recognized correctly.
	if [ -r "$_gb_known" ] && ssh-keygen -F "$_gb_host" -f "$_gb_known" >/dev/null 2>&1; then
		return 0
	fi

	_gb_scratch=$(mktemp "${TMPDIR:-/tmp}/gitbackup-hostkey.XXXXXX") || return 2
	if ! _gb_auth_dial_hostkey "$_gb_host" "$_gb_port" "$_gb_scratch"; then
		gb_log err "gb_accept_hostkey: could not reach $_gb_host:$_gb_port to obtain its host key"
		return 2
	fi

	_gb_fp=$(ssh-keygen -lf "$_gb_scratch" 2>/dev/null)
	printf 'Host key for %s:%s --\n  %s\nAccept and remember it? [y/N] ' "$_gb_host" "$_gb_port" "$_gb_fp" >&2

	# See this function's own header comment: `read`'s exit status, not
	# just the string it captured, is what tells a real "no" (read
	# succeeded, the operator typed something other than y/yes) apart from
	# "could not ask at all" (read failed -- EOF, no stdin to read from).
	if IFS= read -r _gb_ans; then
		case "$_gb_ans" in
			y|Y|yes|YES) ;;
			*)
				rm -f "$_gb_scratch"
				gb_log notice "gb_accept_hostkey: $_gb_host:$_gb_port declined by the operator"
				return 1
				;;
		esac
	else
		rm -f "$_gb_scratch"
		gb_log err "gb_accept_hostkey: $_gb_host:$_gb_port could not ask for confirmation -- no interactive input is available here. Run 'gitbackup test' from a terminal with a real stdin, or accept the host key from the LuCI web UI (Settings -> Connection test), which uses 'gitbackup hostkey show'/'hostkey accept' for exactly this case."
		return 3
	fi

	cat "$_gb_scratch" >>"$_gb_known"
	chmod 0600 "$_gb_known"
	rm -f "$_gb_scratch"
	gb_log notice "gb_accept_hostkey: $_gb_host:$_gb_port accepted and recorded in $_gb_known"
	return 0
}

# gb_hostkey_show <host> [port]
#
# The non-interactive half of ticket 20's web flow: dials <host>, same as
# gb_accept_hostkey above, but never asks anything and never writes
# known_hosts. Instead it caches the exact bytes it fetched in
# _gb_hostkey_pending_file, so a later gb_hostkey_accept call can commit
# precisely THAT material -- not whatever a second, independent dial might
# return -- which is what keeps the show/confirm round trip from opening a
# window for a key swap in between (see gb_hostkey_accept's own comment).
#
# Prints exactly one line to stdout:
#   trusted <host> <port>                       -- nothing to show, already known
#   pending <host> <port> <fingerprint...>       -- ssh-keygen -lf's own text
# Deliberately plain, not JSON: usr/sbin/gitbackup's cmd_hostkey is the one
# JSON boundary here, same split gb_pubkey/`gitbackup pubkey` already uses.
#
# Returns 0 in both printed cases above, 2 when the host could not be
# reached at all (nothing printed, nothing cached).
gb_hostkey_show() {
	_gb_host="$1"
	_gb_port="${2:-22}"
	case "$_gb_port" in
		''|0) _gb_port=22 ;;
	esac

	mkdir -p "$GB_ETC_DIR" 2>/dev/null
	_gb_known="$GB_ETC_DIR/known_hosts"
	if [ -r "$_gb_known" ] && ssh-keygen -F "$_gb_host" -f "$_gb_known" >/dev/null 2>&1; then
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

# gb_hostkey_accept <host> [port] <fingerprint>
#
# Commits the key gb_hostkey_show cached, but ONLY when <fingerprint>
# matches ssh-keygen's own fingerprint of exactly that cached material.
# <fingerprint> is the text the operator was shown and clicked "accept"
# on, so this check is what stops a second, possibly different dial from
# silently substituting a different key between the moment the fingerprint
# was displayed and the moment it was confirmed (an active MITM that
# changed which key answers the connection the second time around, or a
# second concurrent gb_hostkey_show call from another tab overwriting the
# pending file first). This is exactly why this function never dials the
# network itself: re-fetching "to double check" would defeat the point --
# it would be confirming a NEW dial, not the one the operator actually
# saw.
#
# Returns 0 once accepted and recorded, 1 when there is nothing pending
# (gb_hostkey_show was never called, or its result already got
# consumed/replaced -- call it again), 4 when <fingerprint> does not match
# what is actually cached (exit-code contract: "4 отказ по безопасности" --
# this is refused, never silently accepted with a mismatch logged instead).
gb_hostkey_accept() {
	_gb_host="$1"
	_gb_port="${2:-22}"
	_gb_want_fp="$3"
	case "$_gb_port" in
		''|0) _gb_port=22 ;;
	esac

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

	mkdir -p "$GB_ETC_DIR" 2>/dev/null
	_gb_known="$GB_ETC_DIR/known_hosts"
	cat "$_gb_pending" >>"$_gb_known"
	chmod 0600 "$_gb_known"
	rm -f "$_gb_pending"
	gb_log notice "gb_hostkey_accept: $_gb_host:$_gb_port accepted and recorded in $_gb_known"
	return 0
}
