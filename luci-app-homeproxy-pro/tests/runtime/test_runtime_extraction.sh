#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Runtime orchestration trace test.
#
# Drives root/etc/init.d/homeproxy-pro through a stubbed environment and records
# exactly what the orchestration does: which commands run, in what order, with
# which arguments, and which files end up where.  The trace is compared against
# tests/fixtures/runtime/trace.golden.txt.
#
# Two baselines live in tests/fixtures/runtime/:
#
#   trace.pre-pr05.txt  captured from the 517-line init script before PHASE 7
#                       moved the dnsmasq/fw4/net/service plumbing out of it.
#                       It is the record that the extraction itself was
#                       behaviour-preserving (360 identical lines across three
#                       scenarios, commit c2aeac5).
#   trace.golden.txt    the baseline after the health-gate fix.  The
#                       difference between the two files IS the intentional
#                       change: start_service now waits for hp_wait_service
#                       before logging "started", records known-good only
#                       after that gate passed, and reload_service rolls back
#                       through start instead of duplicating the gate.
#                       `diff trace.pre-pr05.txt trace.golden.txt` is the
#                       review artifact.
#
# Scenario D is the regression test for the P0: a candidate configuration whose
# mixed_port is already taken must NOT be recorded as known-good, and a reload
# must roll back to the previous configuration.
#
# Usage: sh tests/runtime/test_runtime_extraction.sh <repo-root> [work-dir]
#
#   HP_INITD=<path>       drive another init script
#   HP_GOLDEN=<path>      compare against another baseline
#   HP_UPDATE_GOLDEN=1    rewrite the baseline instead of comparing
#
# The baseline is a Linux artifact, and refreshing it from macOS writes
# platform noise into it.  The `uname` stub (line ~217) traces every call, and
# something in the sandbox asks for `uname -s` only on Darwin: a macOS run
# produces 21 extra "uname -s" lines and the comparison then fails for a
# reason that has nothing to do with the code.  Verified 2026-09-29: deleting
# the `uname -s` lines from a macOS trace reproduces this file byte for byte,
# so the fix when a macOS run is the only way to produce a trace is
#
#   HP_UPDATE_GOLDEN=1 HP_GOLDEN=/tmp/trace.txt sh tests/runtime/test_runtime_extraction.sh .
#   grep -v '^uname -s$' /tmp/trace.txt > tests/fixtures/runtime/trace.golden.txt
#
# .github/workflows/golden-refresh.yml does this on Linux, which is the path
# that should be preferred.

ROOT="${1:-.}"
# Per-run by default rather than a fixed /tmp path. This script has two
# callers (tests/run.sh and tests/ucode/run.sh) and one of them passed no work
# dir, so two concurrent suite runs shared /tmp/hp-runtime-trace and deleted
# each other's sandbox mid-test - the reproducible symptom was "could not
# sandbox ... missing anchor". tests/runtime/test_config_transaction.sh already
# defaults to mktemp -d.
WORK="${2:-$(mktemp -d "${TMPDIR:-/tmp}/hp-runtime-trace.XXXXXX")}"
OWN_WORK=0
[ -n "${2:-}" ] || OWN_WORK=1

# The dnsmasq conf path is the one shared resource left: it must stay at
# /tmp/etc/dnsmasq.conf.hp_test because the payload is what derives the section
# name, so it cannot move into $WORK. Concurrent runs therefore take turns on
# it, via mkdir (atomic everywhere, no flock dependency), with a bounded wait.
#
# The lock records the owner PID and its start time.  A fixed mkdir lock with
# no owner information left the directory behind whenever a run was SIGKILLed,
# and the next run then burned the full two-minute timeout and failed - a
# "flaky" test whose real cause was a stale artifact.  Now a lock whose holder
# is gone, or that is older than the stale threshold, is reclaimed instead of
# waited out.  The pid is written immediately after mkdir; a crash in that
# microsecond-wide window is covered by the short no-pid grace below.
DNSMASQ_LOCK="/tmp/etc/.hp-runtime-trace.lock"
LOCK_TIMEOUT=120
# Reclaim a lock held longer than this before the full timeout: a live but
# wedged holder should not cost the next run two minutes.  Well above the
# few seconds this test needs, so a healthy run is never stolen.
LOCK_STALE=90
mkdir -p "$(dirname "$DNSMASQ_LOCK")"
_lock_tries=0
while ! mkdir "$DNSMASQ_LOCK" 2>/dev/null; do
	owner="$(cat "$DNSMASQ_LOCK/pid" 2>/dev/null || true)"
	started="$(cat "$DNSMASQ_LOCK/started" 2>/dev/null || true)"
	now="$(date +%s)"
	case "$owner" in ''|*[!0-9]*) owner="" ;; esac
	case "$started" in ''|*[!0-9]*) started="" ;; esac

	if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
		echo "WARN: reclaiming stale lock $DNSMASQ_LOCK (holder pid $owner is gone)" >&2
		rm -rf "$DNSMASQ_LOCK"
		continue
	fi
	if [ -n "$started" ] && [ "$((now - started))" -gt "$LOCK_STALE" ]; then
		echo "WARN: reclaiming lock $DNSMASQ_LOCK (held for $((now - started))s)" >&2
		rm -rf "$DNSMASQ_LOCK"
		continue
	fi
	if [ -z "$owner" ] && [ "$_lock_tries" -ge 5 ]; then
		echo "WARN: reclaiming lock $DNSMASQ_LOCK (no owner pid was ever written)" >&2
		rm -rf "$DNSMASQ_LOCK"
		continue
	fi

	_lock_tries=$((_lock_tries + 1))
	if [ "$_lock_tries" -gt "$LOCK_TIMEOUT" ]; then
		echo "FAIL: another run has held $DNSMASQ_LOCK for over $LOCK_TIMEOUT seconds"
		exit 1
	fi
	sleep 1
done
printf '%s\n' "$$" > "$DNSMASQ_LOCK/pid"
date +%s > "$DNSMASQ_LOCK/started"

# A trap rather than a line at the end: this script exits early on several
# failure paths, and the first version of this cleanup was inserted into the
# middle of one of them.  Release only if this run still owns the lock (the
# pid/started files make that check possible), so a reclaimed lock is never
# removed out from under its new owner.
cleanup() {
	if [ "$(cat "$DNSMASQ_LOCK/pid" 2>/dev/null || true)" = "$$" ]; then
		rm -rf "$DNSMASQ_LOCK"
	fi
	[ "$OWN_WORK" = 1 ] && rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

ROOT="$(cd "$ROOT" && pwd)"
SCRIPTS="$ROOT/root/etc/homeproxy-pro/scripts"
GOLDEN="${HP_GOLDEN:-$ROOT/tests/fixtures/runtime/trace.golden.txt}"
INITD="${HP_INITD:-$ROOT/root/etc/init.d/homeproxy-pro}"

TRACE="$WORK/trace.txt"
SANDBOX="$WORK/box"
BIN="$WORK/bin"
# The dnsmasq conf-dir path is absolute in the payload; the section-name
# lookup is keyed off this file name.
DNSMASQ_CONF="/tmp/etc/dnsmasq.conf.hp_test"

rm -rf "$WORK"
mkdir -p "$SANDBOX/etc/homeproxy-pro/scripts/runtime" \
         "$SANDBOX/etc/homeproxy-pro/resources" \
         "$SANDBOX/var/run/homeproxy-pro" \
         "$SANDBOX/dnsmasq" \
         "$SANDBOX/sbin" \
         "$SANDBOX/init.d" \
         "$SANDBOX/etc/crontabs" \
         "$BIN"

# The auto-update entry is installed by editing the crontab in place, so the
# file has to exist in the sandbox: on a laptop /etc/crontabs/root does not, the
# `sed -i` fails and the run logs a warning the target never produces.  Seeded
# with a stale entry so the delete path is actually exercised.
printf '# existing entry\n0 2 * * * /etc/init.d/acme renew\n0 2 * * * /x #homeproxy_autosetup\n' \
	> "$SANDBOX/etc/crontabs/root"

# Stand-ins for the absolute init scripts the runtime calls.  They record the
# call and succeed, so the trace is the same everywhere and the "Warning: failed
# to restart ..." lines a laptop produced cannot leak into the golden.
for initd in dnsmasq cron miniupnpd; do
	cat > "$SANDBOX/init.d/$initd" <<'EOF'
#!/bin/sh
printf 'init.d/%s %s\n' "$(basename "$0")" "$*" >> "$TRACE"
exit 0
EOF
	chmod +x "$SANDBOX/init.d/$initd"
done

# --- the payload the init script expects ---------------------------------
cp "$SCRIPTS/runtime/"*.sh "$SANDBOX/etc/homeproxy-pro/scripts/runtime/"
cp "$SCRIPTS/fw4_names.sh" "$SANDBOX/etc/homeproxy-pro/scripts/fw4_names.sh"
# One line each is enough: the snippet generator rewrites these lists, it
# does not parse them.
printf 'example.com\nfoo.example.org\n' > "$SANDBOX/etc/homeproxy-pro/resources/gfw_list.txt"
printf 'example.cn\n' > "$SANDBOX/etc/homeproxy-pro/resources/china_list.txt"
printf 'proxy.example.net\n' > "$SANDBOX/etc/homeproxy-pro/resources/proxy_list.txt"
# Makes the conf-dir resolver take its success path.
mkdir -p "$(dirname "$DNSMASQ_CONF")"
printf 'conf-dir=%s\n' "$SANDBOX/dnsmasq" > "$DNSMASQ_CONF"
# Makes the ujail branches reachable off-target.
: > "$SANDBOX/sbin/ujail"
chmod +x "$SANDBOX/sbin/ujail"

# --- stubs: every external command the orchestration can reach -----------
stub() {
	cat > "$BIN/$1" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TRACE"
exit 0
EOF
	chmod +x "$BIN/$1"
}

# C2: the functional health probes run `nslookup` and `nc` after the
# process/listener gate, so both have to exist in the sandbox PATH - otherwise
# the host's own binaries would answer and the trace would depend on the host
# (which is the one thing this test exists to prevent).  The generic stub
# reports success, so a healthy scenario stays quiet: the probes only log when
# they fail or cannot run.

for cmd in nft fw4 utpl pgrep chown chmod nslookup nc; do
	stub "$cmd"
done

# `ip` is the one command whose exit status drives control flow: teardown
# drains duplicate rules with `while ip rule del ...; do :; done`, which only
# terminates because deleting a non-existent rule fails.  A stub that always
# succeeds would spin forever.
cat > "$BIN/ip" <<'EOF'
#!/bin/sh
printf 'ip %s\n' "$*" >> "$TRACE"
case "$*" in
*"rule del"*) exit 1 ;;
esac
exit 0
EOF
chmod +x "$BIN/ip"

# The conf-dir resolver derives the dnsmasq section name from `uci show`.
cat > "$BIN/uci" <<'EOF'
#!/bin/sh
printf '%s %s\n' uci "$*" >> "$TRACE"
case "$*" in
*"show dhcp.@dnsmasq[0]"*) echo "dhcp.hp_test= dnsmasq" ;;
esac
exit 0
EOF
chmod +x "$BIN/uci"

# `uname -r` decides the GSO workaround; pin it so traces agree.
cat > "$BIN/uname" <<'EOF'
#!/bin/sh
printf '%s %s\n' uname "$*" >> "$TRACE"
[ "$1" = "-r" ] && echo "6.12.94" || echo "Linux"
EOF
chmod +x "$BIN/uname"

# `sing-box version -n` feeds the version gate and the "started" log line.
cat > "$BIN/sing-box" <<'EOF'
#!/bin/sh
printf '%s %s\n' sing-box "$*" >> "$TRACE"
[ "$1" = "version" ] && echo "1.14.0"
exit 0
EOF
chmod +x "$BIN/sing-box"

# dnsmasq --version decides whether the DNS snippets may carry nftset=.  The
# stand-in reports the dnsmasq-full feature set, which is what a device able to
# run this package has; runtime/dns.sh's hp_dnsmasq_has_nftset() reads it.  Not
# traced: it is a feature probe, not part of the orchestration under test.
cat > "$BIN/dnsmasq" <<'EOF'
#!/bin/sh
[ "$1" = "--version" ] && {
	echo "Dnsmasq version 2.93  Copyright (c) 2000-2024 Simon Kelley"
	echo "Compile time options: IPv6 GNU-getopt no-DBus UBus no-i18n no-IDN DHCP DHCPv6 no-Lua TFTP conntrack no-ipset nftset auth DNSSEC no-ID loop-detect inotify dumpfile"
}
exit 0
EOF
chmod +x "$BIN/dnsmasq"

# `ucode -S generate_*.uc` is where the live configuration comes from.  The
# stub writes whichever mixed_port the fixture currently declares; whether that
# configuration can actually run is decided from its content by
# `hp_test_broken` below, so the answer follows the live file rather than a
# sticky marker (the rollback copies the old file over the live one without
# regenerating, and the gate has to see that as healthy).
cat > "$BIN/ucode" <<'EOF'
#!/bin/sh
printf 'ucode %s\n' "$*" >> "$TRACE"
for arg in "$@"; do
	case "$arg" in
	*generate_client.uc)
		# One field per line, like the generator's own `%.J` output: the
		# runtime reads this file (hp_config_ports, hp_config_port_for_tag), so
		# a compact fixture would test a shape production never writes.
		printf '{\n\t"log": {},\n\t"inbounds": [\n\t\t{\n\t\t\t"tag": "dns-in",\n\t\t\t"listen_port": %s\n\t\t},\n\t\t{\n\t\t\t"tag": "mixed-in",\n\t\t\t"listen_port": %s\n\t\t}\n\t],\n\t"outbounds": []\n}\n' \
			"${HP_CFG_dns_port:-5333}" "${HP_CFG_mixed_port:-5330}" > "$HP_TEST_RUN_DIR/sing-box-c.json"
		;;
	*generate_server.uc)
		printf '{\n\t"log": {},\n\t"inbounds": [],\n\t"outbounds": []\n}\n' > "$HP_TEST_RUN_DIR/sing-box-s.json"
		;;
	esac
done
exit 0
EOF
chmod +x "$BIN/ucode"

# The fault model: a configuration that declares the port the fixture pretends
# is already taken cannot come up.  Keyed on the live file's content, so it
# stays correct when the rollback replaces that file without regenerating.
cat > "$BIN/hp_test_broken" <<'EOF'
#!/bin/sh
side="$1"
[ -n "${HP_TEST_OCCUPIED_PORT:-}" ] || exit 1
[ -f "$HP_TEST_RUN_DIR/sing-box-$side.json" ] || exit 1
# The pattern has to accept the generator's own `%.J` shape, which is
# `"listen_port": 5399` - with a space. The first version hardcoded the compact
# form, so it only injected the fault because the fixture happened to be
# compact; the moment the fixture was made faithful, the gate stopped seeing a
# broken configuration. The trailing (`[^0-9]`|end) keeps 5399 from matching
# 53990.
grep -qE "\"listen_port\"[[:space:]]*:[[:space:]]*$HP_TEST_OCCUPIED_PORT([^0-9]|$)" "$HP_TEST_RUN_DIR/sing-box-$side.json" || exit 1
exit 0
EOF
chmod +x "$BIN/hp_test_broken"

# `ubus call service list` output is not parsed; `jsonfilter` answers from the
# fixture state instead, which keeps the stub independent of jsonfilter's real
# expression language.  ubus does not write to the trace itself: its output
# always goes through a pipe, so a second writer would race the trace order.
cat > "$BIN/ubus" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$BIN/ubus"

# procd's view of the instance.  Down + exit_code 1 whenever the live
# configuration for that side cannot bind - which is what procd reports while
# it restarts a crashing instance.
cat > "$BIN/jsonfilter" <<'EOF'
#!/bin/sh
printf 'jsonfilter %s\n' "$*" >> "$TRACE"
side="c"
case "$*" in
*"sing-box-s"*) side="s" ;;
esac
down=no
hp_test_broken "$side" && down=yes
case "$*" in
*".instances["*)
	if [ "$down" = "yes" ]; then
		printf '{"running":false,"exit_code":1}\n'
	else
		printf '{"running":true}\n'
	fi
	;;
*"@.running"*)
	[ "$down" = "yes" ] && echo "false" || echo "true"
	;;
*"@.exit_code"*)
	[ "$down" = "yes" ] && echo "1"
	;;
esac
exit 0
EOF
chmod +x "$BIN/jsonfilter"

# The listen table.  The ports are taken from the LIVE configuration, the way
# the real gate derives them, and the occupied port is held by the process that
# took it - the case that makes a naive "is the port in the table?" check
# useless.
cat > "$BIN/netstat" <<'EOF'
#!/bin/sh
printf 'netstat %s\n' "$*" >> "$TRACE"
echo "Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name"
live="$HP_TEST_RUN_DIR/sing-box-c.json"
ports=$(grep -o '"listen_port"[^0-9]*[0-9]*' "$live" 2>/dev/null | grep -o '[0-9]*$' | tr '\n' ' ')
[ -n "$ports" ] || ports="${HP_CFG_mixed_port:-5330} ${HP_CFG_dns_port:-5333}"
for p in $ports; do
	if [ -n "${HP_TEST_OCCUPIED_PORT:-}" ] && [ "$p" = "$HP_TEST_OCCUPIED_PORT" ]; then
		printf 'tcp        0      0 :::%s                 :::*                    LISTEN      77/socat\n' "$p"
	else
		printf 'tcp        0      0 :::%s                 :::*                    LISTEN      4242/sing-box\n' "$p"
	fi
done
exit 0
EOF
chmod +x "$BIN/netstat"

# The WAN wait polls `ip route show default`, `ip -6 route show default` and
# `ifstatus wan`; the first two produce no output through the generic stub, so
# ifstatus has to report the interface up or every scenario would spin for a
# minute.  `sleep` is neutralised for the same reason: the 15-sample health
# budget must not cost 15 real seconds.
cat > "$BIN/ifstatus" <<'EOF'
#!/bin/sh
printf 'ifstatus %s\n' "$*" >> "$TRACE"
echo '{ "up": true }'
exit 0
EOF
chmod +x "$BIN/ifstatus"

cat > "$BIN/sleep" <<'EOF'
#!/bin/sh
printf 'sleep %s\n' "$*" >> "$TRACE"
exit 0
EOF
chmod +x "$BIN/sleep"

# --- harness: UCI + procd + the log sink ---------------------------------
# Sourced *into* the same shell as the init script, exactly like rc.common
# does, so the init script's globals and functions resolve as on a router.
cat > "$WORK/harness.sh" <<'EOF'
# Fixture UCI values.  config_get assigns through its first argument - an
# OpenWrt config_get is a variable-setting function, not a getter.
HP_CFG_routing_mode="bypass_mainland_china"
HP_CFG_proxy_mode="tun"
HP_CFG_main_node="n1"
HP_CFG_main_udp_node="nil"
HP_CFG_default_outbound="direct-out"
HP_CFG_ipv6_support="0"
HP_CFG_auto_update="0"
HP_CFG_auto_update_time="2"
HP_CFG_server_enabled="0"
HP_CFG_table_mark="100"
HP_CFG_tproxy_mark="101"
HP_CFG_tun_mark="102"
HP_CFG_tun_name="singtun0"
HP_CFG_dns_port="5333"
HP_CFG_mixed_port="5330"

config_load() { printf 'config_load %s\n' "$*" >> "$TRACE"; }

# The fixture is keyed by "<section>_<option>" (server_enabled, mixed_port, ...)
# while config_get/config_get_bool receive section and option separately.  The
# lookup has to try the section-qualified name first: reading only the bare
# option name meant `server_enabled=1` on a scenario was silently ignored -
# scenario B's "with server" registered no server instance at all - which is a
# coverage hole, not a fixture convenience.
config_get() {
	__cg_var="$1"; __cg_sec="$2"; __cg_opt="$3"; __cg_def="$4"
	eval "__cg_val=\"\${HP_CFG_${__cg_sec}_${__cg_opt}:-}\""
	[ -n "$__cg_val" ] || eval "__cg_val=\"\${HP_CFG_${__cg_opt}:-}\""
	[ -n "$__cg_val" ] || __cg_val="$__cg_def"
	eval "$__cg_var=\"\$__cg_val\""
}

config_get_bool() {
	__cg_var="$1"; __cg_sec="$2"; __cg_opt="$3"; __cg_def="$4"
	eval "__cg_val=\"\${HP_CFG_${__cg_sec}_${__cg_opt}:-}\""
	[ -n "$__cg_val" ] || eval "__cg_val=\"\${HP_CFG_${__cg_opt}:-}\""
	[ -n "$__cg_val" ] || __cg_val="$__cg_def"
	eval "$__cg_var=\"\$__cg_val\""
}

# procd is not available off-target; record the calls instead, so a lost or
# reordered instance parameter shows up as a trace diff.
procd_open_instance() { printf 'procd_open_instance %s\n' "$*" >> "$TRACE"; }
procd_close_instance() { printf 'procd_close_instance\n' >> "$TRACE"; }
procd_set_param() { printf 'procd_set_param %s\n' "$*" >> "$TRACE"; }
procd_append_param() { printf 'procd_append_param %s\n' "$*" >> "$TRACE"; }
procd_add_jail() { printf 'procd_add_jail %s\n' "$*" >> "$TRACE"; }
procd_add_jail_mount() { printf 'procd_add_jail_mount %s\n' "$*" >> "$TRACE"; }
procd_add_jail_mount_rw() { printf 'procd_add_jail_mount_rw %s\n' "$*" >> "$TRACE"; }
procd_add_reload_trigger() { printf 'procd_add_reload_trigger %s\n' "$*" >> "$TRACE"; }
procd_add_interface_trigger() { printf 'procd_add_interface_trigger %s\n' "$*" >> "$TRACE"; }

# rc.common's lifecycle, modelled faithfully:
#
#   start() { rc_procd start_service "$@"; service_started; }
#   stop()  { stop_service "$@"; procd_kill ...; service_stopped; }
#
# start_service only *registers* the procd instances; procd runs them when the
# service is closed.  That is why the health gate lives in service_started()
# and why this harness has to call it - a harness that reported the instances
# healthy as soon as they were registered hid exactly that bug once.
start() { start_service; service_started; }
stop() { stop_service; service_stopped; }

# The real log() stamps a timestamp and appends to a file, which would make
# the trace nondeterministic.
hp_trace_log() { printf 'log %s\n' "$*" >> "$TRACE"; }
EOF

# --- run one scenario ----------------------------------------------------
# $1 scenario name, $2 the action (start|reload), then the HP_CFG_* overrides.
run_scenario() {
	scenario="$1"; shift
	action="$1"; shift

	rm -rf "$SANDBOX/var/run/homeproxy-pro" "$SANDBOX/dnsmasq/dnsmasq-homeproxy-pro.d" \
	       "$SANDBOX/dnsmasq/dnsmasq-homeproxy-pro.conf" "$SANDBOX/etc/homeproxy-pro/cache.db" \
	       "$SANDBOX/etc/homeproxy-pro/ruleset" "$SANDBOX/etc/homeproxy-pro/certs"
	mkdir -p "$SANDBOX/var/run/homeproxy-pro" "$SANDBOX/dnsmasq"

	printf '\n===== scenario: %s (%s) =====\n' "$scenario" "$action" >> "$TRACE"

	(
		PATH="$BIN:$PATH"; export PATH
		TRACE="$TRACE"; export TRACE
		HP_TEST_RUN_DIR="$SANDBOX/var/run/homeproxy-pro"; export HP_TEST_RUN_DIR

		# harness.sh assigns the fixture defaults, so it has to be sourced
		# BEFORE the per-scenario overrides - the other order silently
		# resets every override and makes all scenarios run the same
		# configuration.
		. "$WORK/harness.sh"

		for kv in "$@"; do
			eval "HP_CFG_${kv%%=*}=\"${kv#*=}\""
			export "HP_CFG_${kv%%=*}"
		done
		export HP_CFG_routing_mode HP_CFG_proxy_mode HP_CFG_main_node \
			HP_CFG_main_udp_node HP_CFG_default_outbound HP_CFG_ipv6_support \
			HP_CFG_auto_update HP_CFG_auto_update_time HP_CFG_server_enabled \
			HP_CFG_table_mark HP_CFG_tproxy_mark HP_CFG_tun_mark \
			HP_CFG_tun_name HP_CFG_dns_port HP_CFG_mixed_port \
			HP_TEST_OCCUPIED_PORT HP_TEST_DOWN

		# A certificate on disk makes the per-file chown/chmod in
		# hp_prepare_runtime_files() visible in the trace: an uploaded key
		# lands as root:0600 and the jailed server needs it handed to the
		# sing-box user, or it cannot start.
		if [ "$HP_CFG_server_enabled" = "1" ]; then
			mkdir -p "$SANDBOX/etc/homeproxy-pro/certs"
			printf '%s\n' '-----BEGIN PRIVATE KEY-----' \
				> "$SANDBOX/etc/homeproxy-pro/certs/server_privatekey.pem"
		fi

		. "$WORK/initd.sh"

		# Override the log sink the init script just defined.
		log() { hp_trace_log "$*"; }

		# Scenario D needs a good configuration in place first, so that the
		# rollback has a real target to restore.  The candidate is switched
		# to the already-taken port only for the reload.
		if [ "$action" = "reload" ]; then
			unset HP_TEST_OCCUPIED_PORT
			start
			printf 'prime start rc=%d\n' "$?" >> "$TRACE"
			if [ "${HP_TEST_DISABLE_CLIENT_AFTER:-0}" = "1" ]; then
				# The second phase turns the client off instead of breaking
				# its port (scenario H).
				HP_CFG_main_node=nil
				export HP_CFG_main_node
			else
				HP_CFG_mixed_port="${HP_TEST_OCCUPIED_AFTER:-5399}"
				HP_TEST_OCCUPIED_PORT="${HP_TEST_OCCUPIED_AFTER:-5399}"
				export HP_CFG_mixed_port HP_TEST_OCCUPIED_PORT
			fi
			reload_service
			printf 'reload_service rc=%d\n' "$?" >> "$TRACE"
		elif [ "$action" = "start-twice" ]; then
			# Scenario I: two plain starts in a row, with the client switched
			# off in between.  This is LuCI's Start button on a router whose
			# node was just removed - a *start*, not a reload, which is the
			# path that has no rollback.
			start
			printf 'prime start rc=%d\n' "$?" >> "$TRACE"
			HP_CFG_main_node=nil
			export HP_CFG_main_node
			start
			printf 'start rc=%d\n' "$?" >> "$TRACE"
		else
			start
			printf 'start rc=%d\n' "$?" >> "$TRACE"
		fi

		stop
		printf 'stop rc=%d\n' "$?" >> "$TRACE"
	) >/dev/null 2>&1

	# Record the files that ended up in the output directories, with
	# contents, so a changed snippet or a lost known-good copy is visible.
	for f in "$SANDBOX/var/run/homeproxy-pro"/* \
	         "$SANDBOX/var/run/homeproxy-pro/known-good"/* \
	         "$SANDBOX/etc/homeproxy-pro/cache.db" \
	         "$SANDBOX/dnsmasq"/* \
	         "$SANDBOX/dnsmasq/dnsmasq-homeproxy-pro.d"/*; do
		[ -f "$f" ] || continue
		printf 'file %s: ' "${f#"$SANDBOX"/}" >> "$TRACE"
		tr '\n' '|' < "$f" >> "$TRACE"
		printf '\n' >> "$TRACE"
	done
}

# --- stage the init script under test ------------------------------------
# Rewrite the absolute paths to the sandbox.  Anchor guards: a silent no-op
# rewrite would make this test compare two unsandboxed runs and pass for the
# wrong reason.
#
# `/sbin/ujail` lives in init.d before PR-05 and in runtime/service.sh after
# it, so the rewrite has to cover both.
# The runtime modules talk to a few ABSOLUTE paths, and those are the test's
# only host dependence: `/etc/init.d/dnsmasq` exists on a router (so the real
# script runs, with its own side effects) and not on a laptop, and `/sbin/ujail`
# likewise.  Rewriting them into the sandbox is what makes the trace identical
# on macOS, on the CI runner and on the target - the first on-target run differed
# from line 11 purely because dnsmasq's init script was there to run.
sandbox_paths() {
	sed -e "s#-x \"/sbin/ujail\"#-x \"$SANDBOX/sbin/ujail\"#g" \
	    -e "s#/etc/init.d/dnsmasq#$SANDBOX/init.d/dnsmasq#g" \
	    -e "s#/etc/init.d/cron#$SANDBOX/init.d/cron#g" \
	    -e "s#/etc/init.d/miniupnpd#$SANDBOX/init.d/miniupnpd#g" \
	    -e "s#/etc/crontabs/root#$SANDBOX/etc/crontabs/root#g" \
	    "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

sed -e "s#^HP_DIR=\"/etc/homeproxy-pro\"#HP_DIR=\"$SANDBOX/etc/homeproxy-pro\"#" \
    -e "s#^RUN_DIR=\"/var/run/homeproxy-pro\"#RUN_DIR=\"$SANDBOX/var/run/homeproxy-pro\"#" \
    "$INITD" > "$WORK/initd.sh"
sandbox_paths "$WORK/initd.sh"

for module in "$SANDBOX/etc/homeproxy-pro/scripts/runtime"/*.sh; do
	sandbox_paths "$module"
done

for anchor in "HP_DIR=\"$SANDBOX/etc/homeproxy-pro\"" \
              "RUN_DIR=\"$SANDBOX/var/run/homeproxy-pro\""; do
	if ! grep -qF "$anchor" "$WORK/initd.sh"; then
		echo "FAIL: could not sandbox $INITD - missing anchor: $anchor"
		
rm -f "$DNSMASQ_CONF"
		exit 1
	fi
done

for anchor in "$SANDBOX/sbin/ujail" "$SANDBOX/init.d/dnsmasq" "$SANDBOX/init.d/cron" \
              "$SANDBOX/etc/crontabs/root"; do
	if ! grep -qF "$anchor" "$WORK/initd.sh" "$SANDBOX/etc/homeproxy-pro/scripts/runtime"/*.sh; then
		echo "FAIL: could not sandbox $anchor - the trace would depend on the host"
		rm -f "$DNSMASQ_CONF"
		exit 1
	fi
done

# Scenario A: TUN client, bypass_mainland_china, no server, no ipv6.
run_scenario "A-tun-bypass-client-only" start \
	proxy_mode=tun routing_mode=bypass_mainland_china \
	main_node=n1 main_udp_node=nil server_enabled=0 ipv6_support=0

# Scenario B: tproxy client with a UDP node + ipv6, gfwlist, server enabled,
# auto-update cron on.
run_scenario "B-tproxy-gfwlist-ipv6-with-server" start \
	proxy_mode=redirect_tproxy routing_mode=gfwlist \
	main_node=n1 main_udp_node=u1 server_enabled=1 ipv6_support=1 \
	auto_update=1 auto_update_time=3

# Scenario C: neither side configured -> the early return must stay early.
run_scenario "C-nothing-configured" start \
	proxy_mode=tun routing_mode=bypass_mainland_china \
	main_node=nil main_udp_node=nil server_enabled=0 ipv6_support=0

# Scenario D: the P0 regression.  A healthy configuration is started and
# recorded, then a candidate whose mixed_port is already taken is reloaded.
# The gate must reject it, the previous known-good must survive, and the
# rollback must bring the service back on the old configuration.
run_scenario "D-health-gate-rollback" reload \
	proxy_mode=tun routing_mode=bypass_mainland_china \
	main_node=n1 main_udp_node=nil server_enabled=0 ipv6_support=0 \
	HP_TEST_OCCUPIED_AFTER=5399

# Scenario E: custom routing mode.  It is the mode whose start path has to
# prepare both runtime files - the ruleset directory and the shared cache.db -
# and whose client jail has to carry HP_DIR, because a local rule-set may point
# anywhere under it.  The trace records all three, so this scenario fails if the
# custom client stops being jailed or stops getting its runtime files.
run_scenario "E-custom-routing-runtime-files" start \
	proxy_mode=tun routing_mode=custom \
	main_node=n1 main_udp_node=nil default_outbound=direct-out \
	server_enabled=0 ipv6_support=0

# Scenario F: custom routing with no default outbound.  The client's "main node"
# reference is mode-dependent (config.main_node vs routing.default_outbound), and
# a regression that reads the wrong UCI key in this mode makes an unconfigured
# router look configured: it starts a client whose generated route block has no
# `final`, so every intercepted connection leaves through sing-box's built-in
# direct outbound instead of the proxy.  The service must refuse to start.
run_scenario "F-custom-routing-nothing-configured" start \
	proxy_mode=tun routing_mode=custom \
	main_node=n1 main_udp_node=nil default_outbound=nil \
	server_enabled=0 ipv6_support=0

# Scenario G: a plain `start` whose configuration cannot come up.  The
# intercept rules are installed *before* the health gate runs, and the start
# path has no rollback (that is reload-only) - so the gate failure has to
# release them itself.  Otherwise the router's own clients keep being
# redirected to a listener that is not there: the LAN loses DNS and TCP, not
# just the proxy.  HP_TEST_OCCUPIED_PORT makes the generated configuration
# unbindable, and the env-prefix assignment is how it reaches the scenario
# (run_scenario's key=value arguments are HP_CFG_* overrides).
HP_TEST_OCCUPIED_PORT=5399 run_scenario "G-start-health-gate-failure" start \
	proxy_mode=redirect_tproxy routing_mode=bypass_mainland_china \
	main_node=n1 main_udp_node=nil server_enabled=0 ipv6_support=0 \
	mixed_port=5399

# Scenario H: two plain starts, the second with the client switched off but the
# server still enabled (the node was removed, the server side stayed).  LuCI's
# Start button takes this path, not reload, and it has no rollback - so the
# intercept layer the first start installed has to be released by the start
# itself.  The "neither side is configured" branch does not cover this case:
# with the server still on, the run gets past it and would leave the LAN
# pointed at the client's dead redirect port.  This is also what makes the
# reload path's "keep the DNS layer across the stop" safe: without it,
# disabling the client would leave the snippets installed forever.
# Scenario I: the DNS snippet writer fails (an unusable infra.dns_port).  The
# snippets are half of the intercept layer - without them the LAN keeps
# resolving through the ISP while the nft rules still send its DNS to sing-box's
# dns-in - and the writer returns non-zero for exactly this case rather than
# installing an empty snippet.  A start must say so and must not promote the
# configuration to known-good, which is the same rule a failed firewall apply
# already follows.
run_scenario "I-dns-snippet-write-failure" start \
	proxy_mode=tun routing_mode=bypass_mainland_china \
	main_node=n1 main_udp_node=nil server_enabled=0 ipv6_support=0 \
	mixed_port=5398 dns_port="70000"

run_scenario "H-start-disables-client" start-twice \
	proxy_mode=redirect_tproxy routing_mode=bypass_mainland_china \
	main_node=n1 main_udp_node=nil server_enabled=1 ipv6_support=0

rm -f "$DNSMASQ_CONF"

# Strip the sandbox prefix so the trace is portable.
sed "s#$SANDBOX/##g" "$TRACE" > "$TRACE.norm"

if [ "${HP_UPDATE_GOLDEN:-0}" = "1" ]; then
	mkdir -p "$(dirname "$GOLDEN")"
	cp "$TRACE.norm" "$GOLDEN"
	echo "PASS: golden trace written to $GOLDEN ($(wc -l < "$GOLDEN") lines)"
	exit 0
fi

if [ ! -f "$GOLDEN" ]; then
	echo "FAIL: golden trace $GOLDEN is missing"
	exit 1
fi

# The decision must not depend on `diff`.  This test also runs on the target
# (tests/ucode/run.sh stages it there), and busybox has `cmp` but often no
# `diff` - the first on-target run failed with "diff: not found" and looked
# exactly like an orchestration change.  The golden snapshot tests already do
# it this way: `cmp` decides, `diff` only formats the diagnosis.
# Scenario E specifically: the golden comparison above would report a difference
# without saying which scenario caused it, and this is the one whose whole point
# is the absence of a warning. It has to run after TRACE.norm is built - the
# first version of this check read the file before it existed and therefore
# always passed.
if awk '/^===== scenario: E-custom-routing-runtime-files/,0' "$TRACE.norm" \
	| grep -q "failed to change the ownership of the runtime files"; then
	echo "FAIL: custom mode reports a chown failure for a runtime file it should have created"
	awk '/^===== scenario: E-custom-routing-runtime-files/,0' "$TRACE.norm" \
		| grep -n "failed to change the ownership" | head -2
	exit 1
fi

# Scenario F pins the mode-dependent read itself.  It has to assert on the
# "not configured" log rather than on the generated file, because the failure
# mode is a client that starts and produces a config with no route.final - it
# looks healthy from every other angle (process up, ports bound).
if awk '/^===== scenario: F-custom-routing-nothing-configured/,0' "$TRACE.norm" \
	| grep -q "^log Neither client nor server is configured\. Service not started\.$"; then
	echo "PASS: custom mode with no default outbound does not start a client"
else
	echo "FAIL: custom mode with default_outbound=nil still started a client"
	awk '/^===== scenario: F-custom-routing-nothing-configured/,0' "$TRACE.norm" | head -25
	exit 1
fi

# A3: a reload generates each enabled side exactly once, and activates that
# artifact. Before the candidate staging this scenario ran the client generator
# twice per reload - once as the preflight, once again from start_service after
# stop_service() had deleted the validated file - so the bytes that ran were not
# the bytes that were checked. Counted inside the reload rather than over the
# whole scenario, because the priming start legitimately generates once itself.
reload_generates=$(awk '/^log Reloading service\.\.\.$/,/^reload_service rc=/' "$TRACE.norm" \
	| grep -c '^ucode -S etc/homeproxy-pro/scripts/generate_client\.uc$')
if [ "$reload_generates" = "1" ]; then
	echo "PASS: a reload generates the client configuration exactly once"
else
	echo "FAIL: a reload ran the client generator $reload_generates time(s), expected 1"
	awk '/^log Reloading service\.\.\.$/,/^reload_service rc=/' "$TRACE.norm" \
		| grep -n 'ucode -S\|Activating the' | head -5
	exit 1
fi

if awk '/^log Reloading service\.\.\.$/,/^reload_service rc=/' "$TRACE.norm" \
	| grep -q '^log Activating the client configuration validated by the reload preflight\.$'; then
	echo "PASS: the reload activates the configuration it validated"
else
	echo "FAIL: the reload did not activate its validated candidate"
	exit 1
fi

# Scenario G asserts the behaviour, not just its trace: a start whose client
# cannot come up must release the intercept layer (otherwise the LAN keeps
# being redirected into it), and a healthy start must not pay for that.
if awk '/^===== scenario: G-start-health-gate-failure/,/^===== scenario: H-/' "$TRACE.norm" \
	| grep -q "^log Reverting the intercept layer"; then
	echo "PASS: a failed start releases the intercept layer"
else
	echo "FAIL: a failed start left the redirect rules and the DNS snippets installed"
	awk '/^===== scenario: G-start-health-gate-failure/,/^===== scenario: H-/' "$TRACE.norm" | head -40
	exit 1
fi

if awk '/^===== scenario: G-start-health-gate-failure/,/^===== scenario: H-/' "$TRACE.norm" \
	| grep -q "^file var/run/homeproxy-pro/known-good/"; then
	echo "FAIL: a start that failed the health gate recorded a known-good configuration"
	exit 1
else
	echo "PASS: a failed start records no known-good configuration"
fi

# Scenario I: a failed snippet install must be reported and must not promote the
# configuration.  The DNS layer is half the intercept, and the writer returns
# non-zero instead of installing an empty snippet - so the start has to notice.
SCEN_I="/^===== scenario: I-dns-snippet-write-failure/"
if awk "$SCEN_I,0" "$TRACE.norm" | grep -q "^log Error: the dnsmasq snippets were not installed"; then
	echo "PASS: a failed DNS snippet install is reported by the start"
else
	echo "FAIL: a failed DNS snippet install was silently ignored"
	awk "$SCEN_I,0" "$TRACE.norm" | head -30
	exit 1
fi

# The known-good pair persists across scenarios, so the dump shows whatever the
# last successful start recorded.  Scenario I generates a configuration nothing
# else does (mixed_port 5398), so the copy is identifiable by content: if the
# dump holds 5398 the failed start promoted over it, if it holds anything else
# the previous known-good survived - which is the required behaviour.
if awk "$SCEN_I,0" "$TRACE.norm" \
	| grep '^file var/run/homeproxy-pro/known-good/sing-box-c.json:' \
	| grep -q '5398'; then
	echo "FAIL: a start whose DNS snippets did not install recorded a known-good configuration"
	exit 1
else
	echo "PASS: a start whose DNS snippets did not install records no known-good"
fi

if awk '/^===== scenario: A-tun-bypass-client-only/,/^===== scenario: B-/' "$TRACE.norm" \
	| grep -q "^log Reverting the intercept layer"; then
	echo "FAIL: a healthy start released the intercept layer it had just installed"
	exit 1
else
	echo "PASS: a healthy start does not release the intercept layer"
fi

# P1-8: a reload must leave the DNS layer alone.  Its stop used to remove the
# snippets and restart dnsmasq, then start put them back and restarted it again
# - a plaintext DNS window and a full cache flush for a configuration that did
# not change.  The writer's content comparison is what makes keeping them safe:
# the re-render below has to report that nothing changed.
if awk '/^===== scenario: D-health-gate-rollback/,/^===== scenario: E-/' "$TRACE.norm" \
	| grep -q "^log dnsmasq snippets unchanged, skipping the restart\.$"; then
	echo "PASS: a reload keeps the DNS snippets and does not restart dnsmasq for them"
else
	echo "FAIL: a reload re-rendered the DNS layer instead of keeping it"
	awk '/^===== scenario: D-health-gate-rollback/,/^===== scenario: E-/' "$TRACE.norm" \
		| grep -n "dnsmasq" | head -8
	exit 1
fi

# Scenario H: the client was switched off and the start has to take the
# intercept layer down with it (LuCI's Start button, no rollback involved).
if awk '/^===== scenario: H-start-disables-client/,0' "$TRACE.norm" \
	| grep -q "^log Reverting the intercept layer"; then
	echo "PASS: a start that finds the client switched off releases the intercept layer"
else
	echo "FAIL: switching the client off left the redirect rules and DNS snippets in place"
	awk '/^===== scenario: H-start-disables-client/,0' "$TRACE.norm" | tail -40
	exit 1
fi

if awk '/^===== scenario: H-start-disables-client/,0' "$TRACE.norm" \
	| grep -q "^file dnsmasq/dnsmasq-homeproxy-pro"; then
	echo "FAIL: the dnsmasq snippets survived the client being switched off"
	awk '/^===== scenario: H-start-disables-client/,0' "$TRACE.norm" | grep "^file dnsmasq"
	exit 1
else
	echo "PASS: the dnsmasq snippets are gone after the client is switched off"
fi

if cmp -s "$GOLDEN" "$TRACE.norm"; then
	echo "PASS: runtime orchestration matches $(basename "$GOLDEN")"
	# Counted from the golden rather than hardcoded: a scenario added without
	# this line would quietly claim the old number.
	echo "      ($(wc -l < "$GOLDEN") trace lines across $(grep -c '^===== scenario: ' "$GOLDEN") scenarios)"
	exit 0
fi

echo "FAIL: the orchestration changed:"
if command -v diff > "/dev/null" 2>&1; then
	diff -u "$GOLDEN" "$TRACE.norm" | head -80
else
	# No diff here: name the first differing lines and show both sides, which
	# is enough to diagnose without the tool.
	awk '
		NR == FNR { golden[FNR] = $0; n = FNR; next }
		{
			if ($0 != golden[FNR] && shown < 20) {
				printf "  line %d\n    golden: %s\n    actual: %s\n", FNR, golden[FNR], $0;
				shown++;
			}
		}
		END {
			if (n > FNR)
				printf "  (golden has %d more lines than the trace)\n", n - FNR;
		}
	' "$GOLDEN" "$TRACE.norm"
fi

exit 1

exit 0
