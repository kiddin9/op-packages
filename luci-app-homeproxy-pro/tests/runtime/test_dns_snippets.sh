#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# dnsmasq snippet-writer tests (review L6).
#
# hp_dnsmasq_write_snippets used to rewrite the snippet set and restart
# dnsmasq unconditionally.  A restart drops every client's DNS cache, and the
# list files it feeds on change once a day at most while the routing mode and
# the DNS port stay put - so an ordinary `reload` flushed the whole LAN's DNS
# cache for no reason.
#
# The writer now renders into a staging directory and compares with what is
# installed; the restart happens only when something actually changed.  These
# tests pin that contract from the outside, by counting restarts through a
# stub:
#
#   * an identical second call does not restart
#   * a changed resource list does restart
#   * a changed routing mode does restart, and drops the snippet the old
#     mode produced (a stale gfw_list.conf next to redirect-dns.conf would
#     have dnsmasq serve both)
#   * toggling ipv6_support does restart (the nftset suffix changes)
#   * removing the resource list does restart, and removes the snippet, so
#     the next call is stable again
#
# The stub is a stand-in for /etc/init.d/dnsmasq, wired in the same way
# tests/runtime/test_runtime_extraction.sh wires its init scripts: the copy of
# dns.sh under test is sed-rewritten so the absolute path points into the
# sandbox.
#
# Usage: sh tests/runtime/test_dns_snippets.sh <repo-root> [work-dir]

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
RUNTIME="$ROOT/root/etc/homeproxy-pro/scripts/runtime"

WORK="${2:-$(mktemp -d "${TMPDIR:-/tmp}/hp-dns-snippets.XXXXXX")}"
OWN_WORK=0
[ -n "${2:-}" ] || OWN_WORK=1
[ "$OWN_WORK" -eq 1 ] && trap 'rm -rf "$WORK"' EXIT INT TERM

FAILED=0
CHECKS=0
FAILURES=0

expect() {
	# expect <name> <actual> <expected>
	CHECKS=$((CHECKS + 1))
	if [ "$2" = "$3" ]; then
		echo "PASS: $1"
	else
		echo "FAIL: $1 (expected '$3', got '$2')"
		FAILED=1
		FAILURES=$((FAILURES + 1))
	fi
}

exists() {
	# exists <path> -> yes|no, so an assertion can compare it as a value.
	[ -e "$1" ] && echo yes || echo no
}

has_line() {
	# has_line <pattern> <file> -> yes|no.  A count would be brittle here:
	# each domain in a gfw/proxy snippet expands to a server= line *and* an
	# nftset= line, so the interesting question is presence, not multiplicity.
	grep -q -- "$1" "$2" 2>"/dev/null" && echo yes || echo no
}

if [ ! -f "$RUNTIME/dns.sh" ]; then
	echo "FAIL: $RUNTIME/dns.sh is missing"
	exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK/init.d" \
         "$WORK/hp/resources" \
         "$WORK/dnsmasq.d"

DNS_DIR="$WORK/dnsmasq.d/dnsmasq-homeproxy-pro.d"
INCLUDE="$WORK/dnsmasq.d/dnsmasq-homeproxy-pro.conf"
RESTARTS="$WORK/restarts"
LOG="$WORK/log"

# --- stubs --------------------------------------------------------------

# runtime/dns.sh probes `dnsmasq --version` for nftset support before emitting
# nftset= directives.  This suite stubs the init script, not the binary, so
# state the answer instead: nftset snippets are what a full dnsmasq emits, and
# that is what the cases below are about.
HP_DNSMASQ_NFTSET=1
export HP_DNSMASQ_NFTSET

# Stand-in for /etc/init.d/dnsmasq: counts restarts instead of running one.
cat > "$WORK/init.d/dnsmasq" <<EOF
#!/bin/sh
echo "\$*" >> "$RESTARTS"
exit 0
EOF
chmod +x "$WORK/init.d/dnsmasq"

# dnsmasq.sh is sourced, so the two ini.d paths inside it have to point at
# the stub.  Only the absolute path is rewritten - the same trick the runtime
# extraction test uses.
sed "s#/etc/init.d/dnsmasq#$WORK/init.d/dnsmasq#g" \
	"$RUNTIME/dns.sh" > "$WORK/dns.sh"

if ! grep -qF "$WORK/init.d/dnsmasq" "$WORK/dns.sh"; then
	echo "FAIL: could not rewrite the dnsmasq init path in the dns.sh copy"
	exit 1
fi

# The module calls log() and the two config readers; a device provides them
# via /lib/functions.sh and the init script.  Both are stubbed to read from
# this test's environment so a scenario is one variable assignment.
log() { echo "$*" >> "$LOG"; }
config_get_bool() { eval "$1=\"\${HP_IPV6:-0}\""; }
config_get()      { eval "$1=\"\${HP_DNS_PORT:-5333}\""; }

# shellcheck source=/dev/null
. "$WORK/dns.sh"

restart_count() { wc -l < "$RESTARTS" 2>/dev/null | tr -d ' '; }

# --- fixtures -----------------------------------------------------------

printf 'example.com\nfoo.example.org\n' > "$WORK/hp/resources/gfw_list.txt"
printf 'example.cn\n'                   > "$WORK/hp/resources/china_list.txt"
printf 'proxy.example.net\n'            > "$WORK/hp/resources/proxy_list.txt"

run() {
	# run <routing-mode>
	hp_dnsmasq_write_snippets "$DNS_DIR" "$WORK/hp" "$1"
}

: > "$RESTARTS"
: > "$LOG"

echo "== gfwlist: first write, then an identical re-run =="

run "gfwlist"
expect "first write restarts dnsmasq" "$(restart_count)" "1"
expect "gfw_list.conf installed" "$(exists "$DNS_DIR/gfw_list.conf")" "yes"
expect "proxy_list.conf installed" "$(exists "$DNS_DIR/proxy_list.conf")" "yes"
expect "include file points at the dir" "$(cat "$INCLUDE")" "conf-dir=$DNS_DIR"

# The whole point of L6: same inputs -> no restart.
run "gfwlist"
expect "identical re-run does not restart" "$(restart_count)" "1"
expect "identical re-run logs the skip" \
	"$(grep -c 'unchanged' "$LOG")" "1"

echo "== gfwlist: a changed resource list restarts =="

printf 'example.com\nfoo.example.org\nnew.example.net\n' > "$WORK/hp/resources/gfw_list.txt"
run "gfwlist"
expect "changed gfw_list.txt restarts dnsmasq" "$(restart_count)" "2"
expect "the new domain reached the snippet" \
	"$(has_line 'new.example.net' "$DNS_DIR/gfw_list.conf")" "yes"

# ...and is stable again straight after.
run "gfwlist"
expect "re-run after the change does not restart" "$(restart_count)" "2"

echo "== toggling ipv6_support restarts (the nftset suffix changes) =="

HP_IPV6=1 run "gfwlist"
expect "ipv6_support on restarts dnsmasq" "$(restart_count)" "3"
expect "the v6 nftset suffix reached the snippet" \
	"$(has_line 'homeproxy_gfw_list_v6' "$DNS_DIR/gfw_list.conf")" "yes"

HP_IPV6=1 run "gfwlist"
expect "re-run with ipv6 on does not restart" "$(restart_count)" "3"

HP_IPV6=0 run "gfwlist"
expect "ipv6_support off restarts again" "$(restart_count)" "4"

echo "== a changed routing mode restarts and drops the stale snippet =="

run "bypass_mainland_china"
expect "mode change restarts dnsmasq" "$(restart_count)" "5"
expect "redirect-dns.conf installed" "$(exists "$DNS_DIR/redirect-dns.conf")" "yes"
expect "the old gfw_list.conf is gone" "$(exists "$DNS_DIR/gfw_list.conf")" "no"
expect "redirect-dns.conf names the DNS port" \
	"$(has_line 'server=127.0.0.1#5333' "$DNS_DIR/redirect-dns.conf")" "yes"

run "bypass_mainland_china"
expect "same mode re-run does not restart" "$(restart_count)" "5"

echo "== a removed resource list restarts and removes its snippet =="

rm -f "$WORK/hp/resources/proxy_list.txt"
run "bypass_mainland_china"
expect "removing proxy_list.txt restarts" "$(restart_count)" "6"
expect "the stale proxy_list.conf is gone" "$(exists "$DNS_DIR/proxy_list.conf")" "no"

run "bypass_mainland_china"
expect "re-run after the removal does not restart" "$(restart_count)" "6"

echo "== removal leaves nothing to restart for =="

hp_dnsmasq_remove_snippets "$DNS_DIR"
expect "remove restarts dnsmasq once" "$(restart_count)" "7"
expect "the snippet dir is gone" "$(exists "$DNS_DIR")" "no"
expect "the include file is gone" "$(exists "$INCLUDE")" "no"

hp_dnsmasq_remove_snippets "$DNS_DIR"
expect "a second remove does not restart" "$(restart_count)" "7"

echo "== an unusable infra.dns_port cannot reach the snippet =="

# `infra` has no UI and no validator, and the value is interpolated into sed's
# replacement.  '5333\nlog-queries' is accepted by the generator - int() is
# strtoll-based, so it reads 5333 - and sed turns the `\n` into a real newline,
# which used to append a dnsmasq directive of the writer's choosing.  A value
# with a `/` made sed fail instead, and the `>`-truncated file was installed as
# a valid (empty) snippet.  Both have to be neutralised, and a value that is
# not a port at all has to leave the installed set alone.
run "bypass_mainland_china"
expect "the good snippet set is installed" "$(exists "$DNS_DIR/redirect-dns.conf")" "yes"
GOOD_CONF="$(cat "$DNS_DIR/redirect-dns.conf")"
GOOD_RESTARTS="$(restart_count)"

HP_DNS_PORT="$(printf '5333\nlog-queries')" run "bypass_mainland_china"
expect "a newline in dns_port cannot inject a directive" \
	"$(has_line 'log-queries' "$DNS_DIR/redirect-dns.conf")" "no"
expect "a newline in dns_port keeps the installed snippet" \
	"$(cat "$DNS_DIR/redirect-dns.conf")" "$GOOD_CONF"
expect "a newline in dns_port does not restart dnsmasq" "$(restart_count)" "$GOOD_RESTARTS"

HP_DNS_PORT='5333/evil' run "bypass_mainland_china"
expect "a slash in dns_port cannot break the snippet" \
	"$(has_line 'evil' "$DNS_DIR/redirect-dns.conf")" "no"
expect "a slash in dns_port keeps the installed snippet" \
	"$(cat "$DNS_DIR/redirect-dns.conf")" "$GOOD_CONF"
expect "a slash in dns_port does not restart dnsmasq" "$(restart_count)" "$GOOD_RESTARTS"

HP_DNS_PORT='not-a-port' run "bypass_mainland_china"
expect "an unusable dns_port leaves the snippet in place" \
	"$(cat "$DNS_DIR/redirect-dns.conf")" "$GOOD_CONF"
expect "an unusable dns_port does not restart dnsmasq" "$(restart_count)" "$GOOD_RESTARTS"
expect "an unusable dns_port is reported in the log" \
	"$(grep -c 'dns_port' "$LOG")" "1"

echo
printf '%s checks, %s failures\n' "$CHECKS" "$FAILURES"
if [ "$FAILED" != 0 ]; then
	echo "DNS SNIPPET TESTS FAILED"
	exit 1
fi

echo "DNS SNIPPET TESTS PASSED"
exit 0
