#!/bin/sh
# zerotier-remote.sh -- manage ZeroTier roles on a REMOTE host over SSH.
#
# The mechanical layer behind the LuCI "Remote" page. Same split as
# zerotier-sync.sh: rpcd shapes JSON, this script owns SSH/curl, so every path
# is testable straight from a shell.
#
# ---------------------------------------------------------------------------
# Why SSH and nothing else
# ---------------------------------------------------------------------------
# The controller control plane has no TLS (verified: an https request to the
# control port never completes) and gates non-loopback callers on
# `allowManagementFrom` in local.conf, which is EMPTY by default -- so every
# remote request gets 401 regardless of a correct token. Widening that to
# 0.0.0.0/0 to make LuCI work would put the admin token on the wire in
# cleartext on every call.
#
# So we forward a loopback port over SSH:
#
#     127.0.0.1:<local_port> --SSH--> 127.0.0.1:<controller_port>
#
# The daemon sees a LOOPBACK peer, which OneService.cpp short-circuits to
# allowed. The controller therefore needs NO configuration change and stays
# firewalled to localhost. Verified end to end: a direct request to the public
# address is refused; the same request through the tunnel returns 200.
#
# Two consequences that shape this file:
#   * The controller authtoken is read on demand over the SSH channel and is
#     never stored on the router -- there is no long-lived admin credential
#     here to leak, back up, or render into a page.
#   * Controller API calls run curl LOCALLY against the forwarded port, so no
#     browser-supplied data is ever concatenated into a remote shell command.
#     The far side is a dumb TCP pipe. The only remote command construction is
#     the fixed moon script in moon_apply, which is shipped as a file and
#     takes no free-text input.
#
# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
# This runs as root, so anything reaching an ssh command line is a potential
# argument-injection vector. Every operator-supplied value is validated against
# a strict character class and rejected outright rather than escaped.

ZT_UCI_CONFIG="zerotier"

# --- output helpers --------------------------------------------------------

# Collapse to a single line, then escape the two characters that can break out
# of a JSON string. Values reaching here are hostnames, versions and short
# error strings; none legitimately contain newlines.
r_esc() {
	printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

r_die() {
	printf '{"code":1,"error":"%s"}\n' "$(r_esc "$1")"
	exit 1
}

# --- validation ------------------------------------------------------------

# Hostname or IP literal. Excludes shell metacharacters, whitespace, and '@'
# (which would let a `user@host` value override the real destination).
r_valid_host() {
	case "$1" in
		''|*[!A-Za-z0-9.:_-]*) return 1 ;;
	esac
	case "$1" in
		*[!0-9A-Za-z]*) return 0 ;;
		*) return 1 ;;
	esac
}

r_valid_user() {
	case "$1" in
		[a-zA-Z_]*) ;;
		*) return 1 ;;
	esac
	case "$1" in
		*[!a-zA-Z0-9_-]*) return 1 ;;
	esac
	return 0
}

r_valid_port() {
	case "$1" in
		''|*[!0-9]*) return 1 ;;
	esac
	[ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

# Absolute path, no traversal, safe charset. Guards the key and known_hosts
# paths, which are handed to ssh -i / -o.
r_valid_path() {
	case "$1" in
		/*) ;;
		*) return 1 ;;
	esac
	case "$1" in
		*..*|*[!A-Za-z0-9._/-]*) return 1 ;;
	esac
	return 0
}

# Exactly $2 hex digits. Network ids are 16, node/root addresses 10. The zero
# address is never meaningful.
r_valid_hex() {
	[ "${#1}" -eq "$2" ] || return 1
	case "$1" in
		*[!0-9a-fA-F]*) return 1 ;;
	esac
	[ "$1" != "0000000000" ] || return 1
	return 0
}

# --- config access ---------------------------------------------------------

# rget <section> <option> [default]
rget() {
	_v=$(uci -q get "$ZT_UCI_CONFIG.$1.$2" 2>/dev/null)
	[ -n "$_v" ] || _v="$3"
	printf '%s' "$_v"
}

# Load and validate everything needed to reach a host, into r_* globals.
# Returns non-zero after printing a JSON error, so no caller can forget to
# check.
r_load() {
	r_sect="$1"
	[ -n "$r_sect" ] || r_die "missing host section"
	case "$r_sect" in
		*[!A-Za-z0-9_]*) r_die "invalid host section name" ;;
	esac

	r_name=$(rget "$r_sect" name "$r_sect")
	r_host=$(rget "$r_sect" host)
	r_user=$(rget "$r_sect" user root)
	r_sport=$(rget "$r_sect" port 22)
	r_lport=$(rget "$r_sect" local_port 19993)
	r_cport=$(rget "$r_sect" controller_port 9993)
	r_key=$(rget "$r_sect" key_path "/etc/zerotier/remote/$r_sect.key")

	r_valid_host "$r_host" || r_die "invalid or empty host"
	r_valid_user "$r_user" || r_die "invalid ssh user"
	r_valid_port "$r_sport" || r_die "invalid ssh port"
	r_valid_port "$r_lport" || r_die "invalid local_port"
	r_valid_port "$r_cport" || r_die "invalid controller_port"
	r_valid_path "$r_key" || r_die "invalid key_path"

	# Without an explicit key, ssh would fall back to an agent and then to
	# password prompts, which would hang the rpcd call instead of failing it.
	[ -f "$r_key" ] || r_die "ssh key not found at $r_key"

	r_dest="$r_user@$r_host"
}

# --- ssh -------------------------------------------------------------------
#
# Option set restricted to what dropbear's client actually honours, verified
# on-device: it accepts BatchMode, StrictHostKeyChecking and
# ExitOnForwardFailure, but SILENTLY IGNORES ConnectTimeout, LogLevel,
# IdentitiesOnly and UserKnownHostsFile. Ignored options are not fatal -- ssh
# prints a warning to stderr and continues -- so an unsupported one corrupts
# every value this script parses rather than causing a clean failure.
#
# Host key checking is therefore TOFU via the client's own store, and the
# `known_hosts` UCI option is NOT plumbed through: passing it looked correct
# and did nothing. IdentitiesOnly being unavailable is why the key is pinned
# with -i instead, and BatchMode is what stops ssh falling through to an
# interactive password prompt and hanging the RPC instead of failing it.
R_SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new"

# With ConnectTimeout unsupported and this image carrying no `timeout` applet,
# an unreachable host leaves ssh running forever and wedges the rpcd call.
# Bound every invocation ourselves: run it in the background, poll for exit,
# and kill at a deadline.
R_SSH_TIMEOUT=25

# rssh <command string> -- run one command string on the remote, with a hard
# deadline. The string is a single argv entry, so ssh hands it to the remote
# login shell without this script re-splitting it.
#
# stderr is captured to a SEPARATE file and never mixed into stdout: ssh emits
# advisory warnings there (unsupported options, host key notices) while
# exit-code-0, and merging the streams silently corrupts every value the
# callers parse. Exit 124 means the deadline was hit.
rssh() {
	_o=$(mktemp /tmp/zt_rssh_o_XXXXXX) || return 1
	_e=$(mktemp /tmp/zt_rssh_e_XXXXXX) || { rm -f "$_o"; return 1; }
	ssh -i "$r_key" $R_SSH_OPTS \
		-p "$r_sport" "$r_dest" "$1" >"$_o" 2>"$_e" &
	_p=$!
	_i=0
	while kill -0 "$_p" 2>/dev/null; do
		if [ "$_i" -ge "$R_SSH_TIMEOUT" ]; then
			kill "$_p" 2>/dev/null
			wait "$_p" 2>/dev/null
			rm -f "$_o" "$_e"
			return 124
		fi
		_i=$((_i + 1))
		sleep 1
	done
	wait "$_p" 2>/dev/null
	_rc=$?
	# ssh's own warnings are only interesting when it failed.
	if [ "$_rc" -ne 0 ] && [ ! -s "$_o" ]; then
		cat "$_e"
	else
		cat "$_o"
	fi
	rm -f "$_o" "$_e"
	return $_rc
}

# Run as root on the remote. The documented precondition is passwordless sudo;
# -n keeps it non-interactive so a misconfigured host fails instead of hanging.
rrsh() {
	rssh "sudo -n $*"
}

# rssh_stdin <file> <command string> -- bounded ssh that feeds <file> to the
# remote command's stdin. Used to ship the moon script to `sh -s` without
# putting it on the remote command line. stderr kept separate, as in rssh.
rssh_stdin() {
	_o=$(mktemp /tmp/zt_rssh_o_XXXXXX) || return 1
	_e=$(mktemp /tmp/zt_rssh_e_XXXXXX) || { rm -f "$_o"; return 1; }
	ssh -i "$r_key" $R_SSH_OPTS \
		-p "$r_sport" "$r_dest" "$2" <"$1" >"$_o" 2>"$_e" &
	_p=$!
	_i=0
	while kill -0 "$_p" 2>/dev/null; do
		if [ "$_i" -ge "$R_SSH_TIMEOUT" ]; then
			kill "$_p" 2>/dev/null
			wait "$_p" 2>/dev/null
			rm -f "$_o" "$_e"
			return 124
		fi
		_i=$((_i + 1))
		sleep 1
	done
	wait "$_p" 2>/dev/null
	_rc=$?
	if [ "$_rc" -ne 0 ] && [ ! -s "$_o" ]; then
		cat "$_e"
	else
		cat "$_o"
	fi
	rm -f "$_o" "$_e"
	return $_rc
}

# --- tunnel ----------------------------------------------------------------

r_tunnel_down() {
	if [ -n "$r_tpid" ]; then
		kill "$r_tpid" 2>/dev/null
		wait "$r_tpid" 2>/dev/null
		r_tpid=""
	fi
	return 0
}

# Forward 127.0.0.1:<lport> to the remote's loopback control plane. Bound
# explicitly to loopback so the forwarded port is never reachable from the LAN.
r_tunnel_up() {
	( exec ssh -i "$r_key" -N $R_SSH_OPTS -o ExitOnForwardFailure=yes \
		-L "127.0.0.1:$r_lport:127.0.0.1:$r_cport" \
		-p "$r_sport" "$r_dest" ) >/dev/null 2>&1 &
	r_tpid=$!

	# Wait for the forward to accept. curl exit 7 is "couldn't connect", the
	# expected state mid-handshake; any other status means the forward is up
	# and the API itself answered (or refused on its own terms, which is a
	# real answer, not a tunnel failure).
	_i=0
	while [ "$_i" -lt 12 ]; do
		curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$r_lport/controller" 2>/dev/null
		[ "$?" -eq 7 ] || return 0
		kill -0 "$r_tpid" 2>/dev/null || return 1
		_i=$((_i + 1))
		sleep 1
	done
	return 1
}

# rctl <method> <path> [body] -- authenticated controller call through the
# tunnel. Results land in the globals r_ctl_code (HTTP status) and r_ctl_body
# (raw response) rather than on stdout, because every caller needs the status
# alongside the body and a command substitution would run this in a subshell
# where a variable assignment cannot escape.
rctl() {
	_tok=$(rrsh cat /var/lib/zerotier-one/authtoken.secret 2>/dev/null)
	[ -n "$_tok" ] || r_die "could not read the remote controller token over ssh"

	if [ -n "$3" ]; then
		_out=$(curl -s --max-time 20 -X "$1" \
			-H "X-ZT1-Auth: $_tok" -H "Content-Type: application/json" \
			--data-binary "$3" -w '\n%{http_code}' \
			"http://127.0.0.1:$r_lport$2" 2>/dev/null)
	else
		_out=$(curl -s --max-time 20 -X "$1" \
			-H "X-ZT1-Auth: $_tok" -w '\n%{http_code}' \
			"http://127.0.0.1:$r_lport$2" 2>/dev/null)
	fi
	r_ctl_code=$(printf '%s' "$_out" | tail -n1 | tr -dc '0-9')
	r_ctl_body=$(printf '%s' "$_out" | sed '$d')
}

# rctl_tok -- the controller authtoken, read over the ssh channel. rctl
# performs this same read internally on every call, which costs one ssh
# handshake each; member-list needs the token for one map request plus N
# member requests and pays that handshake exactly once, not N+1 times. Kept
# as a separate helper instead of refactoring rctl to share it, so the
# ctl-get path that shipped in r33 stays byte-for-byte what was proven.
rctl_tok() {
	rrsh cat /var/lib/zerotier-one/authtoken.secret 2>/dev/null
}

# rfetch <path> -- one authenticated GET through the ALREADY-OPEN tunnel,
# using the token the caller holds in _tok. Same wire format and same
# result-globals convention as rctl (status in r_fetch_code, body in
# r_fetch_body), because the same trade-off applies: a command substitution
# would run this in a subshell the assignments cannot escape. The method is
# pinned to GET on purpose -- this exists so member-list can batch reads
# without re-reading the token per request, and it must never grow into a
# write path.
rfetch() {
	_out=$(curl -s --max-time 20 -X GET \
		-H "X-ZT1-Auth: $_tok" -w '\n%{http_code}' \
		"http://127.0.0.1:$r_lport$1" 2>/dev/null)
	r_fetch_code=$(printf '%s' "$_out" | tail -n1 | tr -dc '0-9')
	r_fetch_body=$(printf '%s' "$_out" | sed '$d')
}

# r_json_ok -- is $1 one COMPLETE JSON object? No JSON parser is guaranteed
# in a root helper's environment (no jq on OpenWrt; jsonfilter belongs to
# rpcd's process, not to this script), yet member-list embeds controller
# bodies raw into a larger array, where one bad body would make every OTHER
# member unreadable. So completeness is checked mechanically, which a plain
# first/last-character shape test cannot do: exactly one top-level object,
# whose containers close in TYPE and in ORDER -- a '}' inside a string must
# not counterfeit an ending, a ']' must not close a '{' the way a mere
# running depth count would allow, a body truncated mid-array must not pass
# as whole, and nothing but whitespace may follow the brace that closes the
# object -- with no string or escape left open at EOF. Only ASCII structural
# bytes are inspected, so multibyte names pass through untouched.
r_json_ok() {
	printf '%s' "$1" | awk '
		{
			for (i = 1; i <= length($0); i++) {
				c = substr($0, i, 1)
				if (e) { e = 0; continue }
				if (s) {
					if (c == "\\") e = 1
					else if (c == "\"") s = 0
					continue
				}
				if (done) {
					if (c != " " && c != "\t") { bad = 1; exit }
					continue
				}
				if (c == "\"") { s = 1; continue }
				if (c == "{" || c == "[") {
					if (st == "") {
						if (c != "{") { bad = 1; exit }
						ob_seen = 1
					}
					st = st c
				} else if (c == "}" || c == "]") {
					l = substr(st, length(st), 1)
					if (l == "" || (c == "}" && l != "{") || (c == "]" && l != "[")) { bad = 1; exit }
					st = substr(st, 1, length(st) - 1)
					if (st == "") done = 1
				}
			}
		}
		END { if (bad == 1 || ob_seen != 1 || st != "" || s == 1 || e == 1) exit 1 }
	'
}

# Wrap a raw JSON body alongside a status code. The body is already JSON, so it
# is embedded as a value rather than escaped into a string -- no re-quoting,
# no mangling of embedded quotes or newlines.
r_emit() {
	_b="$1"
	[ -n "$_b" ] || _b=null
	printf '{"code":%s,"body":%s}\n' "${2:-0}" "$_b"
}

# --- moon provisioning script ---------------------------------------------
#
# Defined ONCE, as a quoted heredoc, for two reasons that both bit during
# development:
#
#   * The digest that gates execution must be computed from the same text that
#     actually runs. Two copies of the command (one shown in the plan, one
#     executed) can drift, and then the confirmation would gate the wrong thing.
#   * Quoting the heredoc delimiter leaves every $ for the REMOTE shell, so no
#     nested substitution needs escaping anywhere. The script is shipped over
#     stdin to `sh -s`, which keeps it off the remote command line entirely.
r_moon_script() {
	cat <<'MOONSCRIPT'
set -e
Z=/var/lib/zerotier-one
W=/root
zerotier-idtool initmoon "$(cat $Z/identity.public)" > $W/moon.json
cd $W
zerotier-idtool genmoon moon.json > /dev/null
f=$(ls $W/*.moon 2>/dev/null | head -1)
[ -n "$f" ] || { echo NO_MOON; exit 1; }
cp $W/moon.json $Z/moon.json
cp "$f" $Z/
echo "MOON_FILE=$(basename "$f")"
base64 "$f" | tr -d '\n'
MOONSCRIPT
}

r_moon_digest() {
	_s=$(r_moon_script | md5sum 2>/dev/null | cut -d' ' -f1)
	[ -n "$_s" ] || _s=$(r_moon_script | cksum | cut -d' ' -f1)
	printf '%s' "$_s"
}

# ---------------------------------------------------------------------------

case "$1" in

# diagnose -- read-only survey. Never writes, so it is safe against production.
diagnose)
	r_load "$2"

	# One round trip, not one per probe: the bounded-wait wrapper polls at 1s
	# granularity, so eight separate ssh calls cost ~11s. A single script
	# returning key=value lines costs one handshake.
	_script=$(mktemp /tmp/zt_diag_XXXXXX) || r_die "cannot stage the diagnostic script"
	cat > "$_script" <<'DIAGSCRIPT'
p() { echo "ZT_$1=$2"; }
p os "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
# `command` is a shell builtin, so it must be evaluated inside this shell
# rather than handed to sudo as a binary name.
if command -v zerotier-one >/dev/null 2>&1; then
	p ztbin yes
	p ztver "$(zerotier-one -v 2>/dev/null | head -1)"
else
	p ztbin no
	p ztver ""
fi
p ztsvc "$(systemctl is-active zerotier-one 2>/dev/null || echo inactive)"
# -j info is pretty-printed, so there is a space after the colon.
p ztaddr "$(zerotier-cli -j info 2>/dev/null | sed -n 's/.*"address"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*/\1/p' | head -1)"
p ctrl "$(test -d /var/lib/zerotier-one/controller.d && echo yes || echo no)"
p moonjson "$(test -f /var/lib/zerotier-one/moon.json && echo yes || echo no)"
p moonfiles "$(ls -1 /var/lib/zerotier-one/*.moon 2>/dev/null | wc -l | tr -d ' ')"
p uid "$(id -u)"
DIAGSCRIPT
	_res=$(rssh_stdin "$_script" "sudo -n sh -s")
	rm -f "$_script"

	# A host that cannot be reached must still return valid JSON, so an
	# unreachable section is a normal result, not a parse failure.
	r_field() { printf '%s\n' "$_res" | sed -n "s/^ZT_$1=//p" | head -1; }
	_os=$(r_field os)
	_bin=$(r_field ztbin)
	_ver=$(r_field ztver)
	_run=$(r_field ztsvc)
	_id=$(r_field ztaddr)
	_hasctl=$(r_field ctrl)
	_hasmoon=$(r_field moonjson)
	_moons=$(r_field moonfiles)
	_uid=$(r_field uid)

	# Passwordless sudo is the documented precondition -- test it directly
	# rather than inferring it from uid 0.
	if [ -n "$_uid" ]; then _sudo=true; else _sudo=false; fi

	# The check that actually predicts whether LuCI can manage this host.
	if r_tunnel_up; then
		_reach=true
		r_tunnel_down
	else
		_reach=false
		r_tunnel_down
	fi

	_inst=false
	[ -n "$_bin" ] && [ "$_bin" != "none" ] && _inst=true

	printf '{"code":0'
	printf ',"section":"%s","name":"%s","host":"%s","user":"%s"' \
		"$(r_esc "$r_sect")" "$(r_esc "$r_name")" \
		"$(r_esc "$r_host")" "$(r_esc "$r_user")"
	printf ',"ssh":true,"sudo":%s,"uid":%s' "$_sudo" "${_uid:-0}"
	printf ',"os":"%s"' "$(r_esc "$_os")"
	printf ',"zerotier_installed":%s' "$_inst"
	printf ',"zerotier_version":"%s"' "$(r_esc "$_ver")"
	printf ',"zerotier_service":"%s"' "$(r_esc "$_run")"
	printf ',"identity":"%s"' "$(r_esc "$_id")"
	printf ',"controller_state":%s' "$([ "$_hasctl" = "yes" ] && echo true || echo false)"
	printf ',"controller_reachable":%s' "$_reach"
	printf ',"moon_json_present":%s' "$([ "$_hasmoon" = "yes" ] && echo true || echo false)"
	printf ',"moon_files":%s' "${_moons:-0}"
	printf '}\n'
	;;

# ctl-get <section> <path> -- authenticated read through the tunnel. The path
# is confined to the controller API surface, and '..' plus encoded separators
# are rejected so nothing can walk out of the forwarded prefix.
ctl-get)
	r_load "$2"
	_p="$3"
	case "$_p" in
		/controller*|/unstable/controller*) ;;
		*) r_die "path must be under /controller" ;;
	esac
	case "$_p" in
		*..*|*%2f*|*%2F*) r_die "invalid path" ;;
	esac
	r_tunnel_up || { r_tunnel_down; r_die "could not open the ssh tunnel to $r_dest"; }
	rctl GET "$_p"
	_b=$r_ctl_body
	_c=$r_ctl_code
	r_tunnel_down
	r_emit "$_b" "${_c:-0}"
	;;

# peer-list <section> -- the controller's /peer endpoint, verbatim.
#
# A dedicated subcommand with a hardcoded path, NOT a widening of ctl-get:
# /peer does not live under /controller, and ctl-get's allowlist exists
# precisely so a generic passthrough cannot grow new endpoints one request
# at a time. One fixed read-only GET is narrower than opening the front door.
peer-list)
	r_load "$2"
	r_tunnel_up || { r_tunnel_down; r_die "could not open the ssh tunnel to $r_dest"; }
	rctl GET /peer
	_b=$r_ctl_body
	_c=$r_ctl_code
	r_tunnel_down
	r_emit "$_b" "${_c:-0}"
	;;

# member-list <section> <nwid> -- every member of one network in TWO ssh
# round trips, not two per member.
#
# The members table needs the member id map AND each member's full record;
# the map carries only {id: revision} (measured on the live 1.14.2
# controller, as the Remote page already records). Composed from existing
# pieces that is one ctl-get for the map plus one PER MEMBER, and every rpcd
# call opens its own tunnel and reads its own token -- two ssh handshakes of
# 1-3s each per member. The production network has 29 members, so drawing
# one table costs 30-90s of handshakes. This subcommand instead reads the
# token once, opens the tunnel once, then curls the map and every member
# LOCALLY through the forwarded port: two ssh connections total, and N cheap
# loopback requests.
#
# Read-only by construction: every request issued below is a GET.
member-list)
	r_load "$2"
	r_valid_hex "$3" 16 || r_die "network id must be 16 hex digits"
	r_tunnel_up || { r_tunnel_down; r_die "could not open the ssh tunnel to $r_dest"; }
	_tok=$(rctl_tok)
	[ -n "$_tok" ] || { r_tunnel_down; r_die "could not read the remote controller token over ssh"; }
	rfetch "/controller/network/$3/member"
	_code=$r_fetch_code
	_map=$r_fetch_body
	case "$_map" in '{'*'}') ;; *) _map="" ;; esac
	if [ -z "$_map" ] || [ "$_code" != "200" ]; then
		# Without the map the member set is unknown. Emit the upstream
		# status with a null body rather than an empty array -- "[]"
		# would read as a network with no members, not as a failure.
		r_tunnel_down
		r_emit "" "${_code:-0}"
	else
		# The map is one JSON object keyed by member id. No JSON parser
		# is available to this script, so keys are picked out textually:
		# in JSON a colon can only follow a key, so a quoted 10-hex
		# token followed by ':' cannot be a value however the response
		# is packed onto lines, and grep -o (supported by busybox grep)
		# yields every match.
		_mids=$(printf '%s' "$_map" | grep -oE '"[0-9a-fA-F]{10}"[[:space:]]*:' \
			| sed -e 's/^"//' -e 's/"[[:space:]]*:$//')

		# Every candidate is re-validated with r_valid_hex before it is
		# placed in a URL. This script runs as root and the extraction
		# above is textual: URL safety rests on this validation, not on
		# the regex upstream of it.
		_arr=""
		for _mid in $_mids; do
			r_valid_hex "$_mid" 10 || continue
			rfetch "/controller/network/$3/member/$_mid"
			# A failed member fetch is SKIPPED, not embedded: an error
			# body or a truncated read would make the whole array
			# unparseable and cost every other member its row. A
			# missing row is recoverable; a broken table is not.
			_ok=false
			case "$r_fetch_body" in
				'{'*'}')
					[ "$r_fetch_code" = "200" ] && r_json_ok "$r_fetch_body" && _ok=true
					;;
			esac
			if [ "$_ok" = "true" ]; then
				# Joined, never blindly concatenated: a comma goes
				# between two ACCEPTED elements only, so no path
				# yields a leading, trailing or doubled comma.
				# Elements are embedded raw for the same reason
				# r_emit embeds bodies raw -- each has passed the
				# complete-object check, and a complete JSON
				# value is self-delimiting: a '}' inside a
				# string ends no object here any more than it
				# does in the controller's own output.
				if [ -n "$_arr" ]; then
					_arr="$_arr,$r_fetch_body"
				else
					_arr="$r_fetch_body"
				fi
			fi
		done
		r_tunnel_down
		r_emit "[$_arr]" "$_code"
	fi
	;;

# ctl-network-set <section> <nwid|new> <json-body>
# Creates (nwid=new) or updates a network. The body is opaque here: it goes
# straight into curl as one argument, never through a shell, never onto the
# remote host.
ctl-network-set)
	r_load "$2"
	if [ "$3" = "new" ]; then
		# The modern create route derives the nwid from the controller's own
		# address. The documented /controller/network/<10hex>______ route is
		# registered in the 1.14.2 source as `createNewNetworkOldAndBusted`
		# and answers 400.
		_path="/controller/network"
	else
		r_valid_hex "$3" 16 || r_die "network id must be 16 hex digits"
		_path="/controller/network/$3"
	fi
	case "$4" in
		'{'*'}') ;;
		*) r_die "network body must be a JSON object" ;;
	esac
	r_tunnel_up || { r_tunnel_down; r_die "could not open the ssh tunnel to $r_dest"; }
	rctl POST "$_path" "$4"
	_b=$r_ctl_body
	_c=$r_ctl_code
	r_tunnel_down
	[ "$_c" = "200" ] || r_die "controller rejected the network (http $_c): $(r_esc "$_b")"
	r_emit "$_b" "$_c"
	;;

# ctl-network-del <section> <nwid>
ctl-network-del)
	r_load "$2"
	r_valid_hex "$3" 16 || r_die "network id must be 16 hex digits"
	r_tunnel_up || { r_tunnel_down; r_die "could not open the ssh tunnel to $r_dest"; }
	rctl DELETE "/controller/network/$3"
	_c=$r_ctl_code
	r_tunnel_down
	[ "$_c" = "200" ] || r_die "delete failed with http $_c"
	printf '{"code":0}\n'
	;;

# ctl-member-set <section> <nwid> <member-id> <json-body>
# Authorize or deauthorize a member -- the operation that replaces ztncui's
# member management.
ctl-member-set)
	r_load "$2"
	r_valid_hex "$3" 16 || r_die "network id must be 16 hex digits"
	r_valid_hex "$4" 10 || r_die "member id must be 10 hex digits"
	case "$5" in
		'{'*'}') ;;
		*) r_die "member body must be a JSON object" ;;
	esac
	r_tunnel_up || { r_tunnel_down; r_die "could not open the ssh tunnel to $r_dest"; }
	rctl POST "/controller/network/$3/member/$4" "$5"
	_c=$r_ctl_code
	r_tunnel_down
	[ "$_c" = "200" ] || r_die "member update failed with http $_c"
	printf '{"code":0}\n'
	;;

# ---------------------------------------------------------------------------
# Moon provisioning
# ---------------------------------------------------------------------------
# Three behaviours were established by running the commands, not by reading
# docs, and all three contradict the obvious implementation:
#
#   * `zerotier-idtool initmoon <identity.public>` writes the world definition
#     to STDOUT. It does not create a file, so it must be redirected.
#   * `zerotier-idtool genmoon moon.json` writes the signed world to the
#     CURRENT WORKING DIRECTORY as <16-hex>.moon. The artifact is BINARY, not
#     JSON, and it is not placed next to moon.json.
#   * `zerotier-cli orbit <world> <seed>` takes a ROOT ADDRESS as the seed --
#     not a file. Passing a path is a silent no-op. So it cannot bootstrap a
#     brand-new moon, where no root exists to fetch from yet; the file has to
#     be shipped instead.
#
# moon.json holds signingKey_SECRET, so it is created, signed and LEFT on the
# root host. Only the secret-free signed .moon is read back, and only because
# a member cannot join a moon without it.
#
# Scope: the remote host is the moon's single root. Additional roots would mean
# rewriting the roots array on the remote, and a half-working multi-root path
# is worse than none -- so that is refused explicitly rather than attempted.

moon-plan)
	r_load "$2"
	[ "$#" -eq 2 ] || r_die "extra moon roots are not supported yet: the remote host is the single root"
	_sum=$(r_moon_digest)
	printf '{"code":0,"confirm":"%s"\n' "$_sum"
	printf ',"script":"%s"\n' "$(r_esc "$(r_moon_script)")"
	printf ',"notes":"moon.json holds signingKey_SECRET and is created, signed and kept on the remote host; only the secret-free signed .moon is read back"}\n'
	;;

moon-apply)
	r_load "$2"
	_confirm="$3"
	[ -n "$_confirm" ] || r_die "missing confirmation digest; run moon-plan first"
	[ "$#" -eq 3 ] || r_die "extra moon roots are not supported yet: the remote host is the single root"
	_sum=$(r_moon_digest)
	# Digest comes from the same text that runs below, so a match proves the
	# operator confirmed this exact operation.
	[ "$_confirm" = "$_sum" ] || r_die "confirmation does not match the current plan; re-read the plan and confirm again"

	rrsh true >/dev/null 2>&1 || r_die "passwordless sudo is required on $r_dest"
	_pub=$(rrsh 'cat /var/lib/zerotier-one/identity.public' 2>/dev/null | tr -d '\r\n')
	[ -n "$_pub" ] || r_die "could not read the remote ZeroTier identity"
	_addr=$(printf '%s' "$_pub" | cut -d: -f1)
	r_valid_hex "$_addr" 10 || r_die "unexpected remote identity format"

	_script=$(mktemp /tmp/zt_moon_XXXXXX) || r_die "cannot stage the moon script locally"
	r_moon_script > "$_script"
	_res=$(rssh_stdin "$_script" "sudo -n sh -s")
	_st=$?
	rm -f "$_script"
	[ "$_st" -eq 124 ] && r_die "the remote did not finish the moon operation within ${R_SSH_TIMEOUT}s"

	case "$_res" in
		*NO_MOON*) r_die "genmoon produced no .moon artifact on the remote" ;;
	esac

	_b64=$(printf '%s' "$_res" | grep -v '^MOON_FILE=' | tr -d '\r\n')
	[ -n "$_b64" ] || r_die "could not read the signed .moon back from the remote (remote said: $(r_esc "$_res"))"

	# A signed world begins with the 4-byte magic 7f 00 00 00, which base64
	# encodes to a fixed "fwAA" prefix. Checking it rejects an error string
	# that happened to survive the pipeline.
	case "$_b64" in
		fwAA*) ;;
		*) r_die "remote returned something that is not a signed world" ;;
	esac

	_file=$(printf '%s' "$_res" | sed -n 's/^MOON_FILE=//p' | head -1)
	_id=$(printf '%s' "$_file" | sed -n 's/^[0]*\([0-9a-fA-F]\{10\}\)\.moon$/\1/p')
	[ -n "$_id" ] || _id="$_addr"

	printf '{"code":0,"moon_id":"%s","moon_file":"%s","moon_b64":"%s"}\n' \
		"$_id" "$(r_esc "$_file")" "$_b64"
	;;

*)
	printf '{"code":1,"error":"unknown subcommand"}\n'
	exit 1
	;;
esac
