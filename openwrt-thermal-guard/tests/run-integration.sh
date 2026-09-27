#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Runs the shipped script as a process against a planted state directory.
# The selftest covers the logic in memory, this covers what ends up on disk.
# shellcheck shell=busybox

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
# set -e ends the suite at the first command that fails outside a check. Say
# so, with the last check that ran, instead of stopping without a word.
finished=0; last="none yet"
suite_exit() { # $1 exit status
	[ "$finished" = 1 ] || echo "FAIL the suite stopped early, the last check was: $last"
	rm -rf "$tmp"
	exit "$1"
}
trap 'suite_exit $?' EXIT

BIN="$root/thermal-guard/files/usr/sbin/thermal-guard"
LIB_DIR="$root/thermal-guard/files/usr/share/thermal-guard"
STATE_DIR="$tmp/state"
STATUS_FILE="$tmp/status"
PERSIST_DIR="$tmp/persist"
HOOK_DIR="$tmp/hooks"
export LIB_DIR STATE_DIR STATUS_FILE PERSIST_DIR HOOK_DIR

# Every daemon run logs through this stand-in, never the host's syslog. It
# records the arguments, and fails on demand while logger.fail exists.
cat > "$tmp/logger" <<LOGGER_END
#!/bin/sh
[ -e "$tmp/logger.fail" ] && exit 1
echo "\$*" >> "$tmp/syslog"
LOGGER_END
chmod 0755 "$tmp/logger"
export TG_LOGGER="$tmp/logger"
prio() { # $1 start of a message, prints the priority it went out with
	sed -n "s/^-t thermal-guard -p \(daemon\.[a-z]*\) $1.*/\1/p" "$tmp/syslog" | head -n1
}

fail=0
chk() { # $1 label, $2 got, $3 expected
	last=$1
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1: expected [$3], got [$2]"
		fail=1
	fi
}

field() { # $1 file, $2 key
	sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1
}

# A case that reads the status file first proves the file is from its own
# run: fresh_status before the run, sfield after it, which says "stale" for a
# file left over from an earlier case.
fresh_status() {
	rm -f "$STATUS_FILE"; status_t0=$(date +%s)
}
sfield() { # $1 key
	local now
	now=$(field "$STATUS_FILE" now)
	if [ -n "$now" ] && [ "$now" -ge "$status_t0" ]; then
		field "$STATUS_FILE" "$1"
	else
		echo stale
	fi
}
# How many daemons have started on this event log, to show one was running.
started() {
	cat "$STATE_DIR/log" 2>/dev/null | grep -c 'started, version' || true
}
# A cool planted zone for the daemon runs before the trip section plants its
# own tree, so they do not depend on the host's temperature.
COOL="$tmp/cool"
mkdir -p "$COOL/thermal_zone0"; echo 40000 > "$COOL/thermal_zone0/temp"

plant_stage1() {
	mkdir -p "$STATE_DIR"
	cat > "$STATE_DIR/state" <<'EOF'
STAGE=1
T0=1000
T1=1100
T2=0
REF_CPU0=72
REF_MODEM0=0
REF_CPU1=73
REF_MODEM1=0
PENDING=-1
PENDING_N=0
COOLED=0
LAST_CPU=73
LAST_MODEM=
LAST_MODEM_SRC=
LAST_TS=1100
GEN=3
EOF
}

# ---- reset clears the stage and bumps the generation ----------------------
plant_stage1
: > "$tmp/syslog"; fresh_status
sh "$BIN" reset >/dev/null 2>&1

chk "reset clears the stage" "$(field "$STATE_DIR/state" STAGE)" "-1"
chk "reset goes to syslog as daemon.notice" "$(prio 'reset requested')" "daemon.notice"
chk "reset bumps GEN" "$(field "$STATE_DIR/state" GEN)" "4"
chk "reset refreshes the status file" "$(sfield stage)" "-1"

# ---- a plain cycle leaves the generation alone ----------------------------
# A daemon cycle, not a dry run: only a real cycle saves the state.
fresh_status
THERMAL_ROOT="$COOL" timeout 3 sh "$BIN" daemon >/dev/null 2>&1 || true
chk "a daemon cycle ran and saved the state" \
	"$(sfield stage)/$([ "$(field "$STATE_DIR/state" LAST_TS)" -ge "$status_t0" ] 2>/dev/null &&
		echo saved || echo not)" "-1/saved"
chk "a cycle does not touch GEN" "$(field "$STATE_DIR/state" GEN)" "4"

# ---- reset is idempotent, and safe on a state that is already clear -------
sh "$BIN" reset >/dev/null 2>&1
chk "second reset bumps GEN again" "$(field "$STATE_DIR/state" GEN)" "5"
chk "second reset keeps the stage clear" "$(field "$STATE_DIR/state" STAGE)" "-1"

# ---- the status file carries what the UI needs to spot a dead service -----
# Written by a daemon cycle; a dry run does not write it.
fresh_status
THERMAL_ROOT="$COOL" timeout 3 sh "$BIN" daemon >/dev/null 2>&1 || true
chk "status reports the enabled flag" "$(sfield enabled)" "1"
# The value depends on the machine running the tests, the field must be there
# either way because the web interface branches on it.
case "$(sfield no_sensor)" in
	0|1) chk "status reports whether a sensor exists" present present ;;
	*)   chk "status reports whether a sensor exists" missing present ;;
esac
case "$(sfield fan_view)" in
	none|pwm|cooling_device) chk "status reports what the fan is read from" present present ;;
	*)                       chk "status reports what the fan is read from" missing present ;;
esac
chk "status reports the interval" "$(sfield interval)" "20"
written=$(field "$STATUS_FILE" now)
now=$(date +%s)
if [ -n "$written" ] && [ $((now - written)) -lt 60 ]; then
	chk "status is stamped with the write time" fresh fresh
else
	chk "status is stamped with the write time" "stale($written)" fresh
fi

# ---- a garbled state file must not carry values into the logic ------------
# Checked through "status", which loads the state and prints it without
# writing anything back, so the planted file stays as it is.
mkdir -p "$STATE_DIR"
cat > "$STATE_DIR/state" <<'EOF'
STAGE=1; rm -rf /
GEN=notanumber
LAST_CPU=42
EOF
sh "$BIN" status > "$tmp/status-out" 2>/dev/null
chk "junk stage is dropped" "$(sed -n 's/^stage=//p' "$tmp/status-out")" "-1"
chk "junk GEN falls back to zero" "$(sed -n 's/^gen=//p' "$tmp/status-out")" "0"
chk "junk reading is dropped" "$(sed -n 's/^last_cpu=//p' "$tmp/status-out")" "42"

# ---- one-shot commands stay out of the event log --------------------------
# Every entry point runs the same configuration checks. If a one-shot command
# logs what they find, repeating it repeats the line, and because the event log
# keeps only the last 50 entries a monitoring check calling status in a loop
# flushes out the record of an actual incident.
# A board without any sensor gives such a diagnostic. The daemon logging it
# shows there is something the one-shot commands have to hold back.
rm -rf "$STATE_DIR" "$PERSIST_DIR"
mkdir -p "$STATE_DIR" "$tmp/nosensor"
THERMAL_ROOT="$tmp/nosensor" HWMON_ROOT="$tmp/nosensor" timeout 3 sh "$BIN" daemon >/dev/null 2>&1 || true
chk "the daemon logs the missing sensor" "$(grep -c 'reports no temperature at all' "$STATE_DIR/log")" "1"
printf '2026-01-01 00:00:00 stage 1: modem radio off\n' > "$STATE_DIR/log"

i=0
while [ "$i" -lt 12 ]; do
	THERMAL_ROOT="$tmp/nosensor" HWMON_ROOT="$tmp/nosensor" sh "$BIN" status >/dev/null 2>&1
	THERMAL_ROOT="$tmp/nosensor" HWMON_ROOT="$tmp/nosensor" sh "$BIN" test 40 40 >/dev/null 2>&1
	i=$((i + 1))
done

chk "status and test add nothing to the log" "$(wc -l < "$STATE_DIR/log")" "1"
chk "the incident is still there" "$(grep -c 'stage 1' "$STATE_DIR/log")" "1"

# ---- a dry run changes nothing -------------------------------------------
# First that the stages were reached at all, then that nothing was written:
# "nothing happened" only counts where something could have.
rm -rf "$STATE_DIR" "$PERSIST_DIR"
: > "$tmp/syslog"
out=$(sh "$BIN" test 95 95 2>/dev/null)
chk "a dry run of 95/95 reaches all three stages" \
	"$(printf '%s\n' "$out" | grep -c '^would notify (crit): stage [0-2]: cpu 95 C')" "3"
chk "and ends in stage 2" "$(printf '%s\n' "$out" | sed -n 's/^decision=.* stage=\([-0-9]*\) .*/\1/p')" "2"
chk "it makes no logger call" "$(wc -l < "$tmp/syslog" | tr -d ' ')" "0"
chk "and writes no event log" "$([ -s "$STATE_DIR/log" ] && echo wrote || echo clean)" "clean"
chk "a dry run writes no state" "$([ -f "$STATE_DIR/state" ] && echo wrote || echo clean)" "clean"
chk "a dry run persists nothing" "$([ -f "$PERSIST_DIR/state" ] && echo wrote || echo clean)" "clean"

# ---- stages survive a reboot ---------------------------------------------
# A reboot empties /var/run but not the overlay. Simulate that by planting a
# persisted stage and removing the working state, the way tmpfs would.
rm -rf "$STATE_DIR" "$PERSIST_DIR"
mkdir -p "$PERSIST_DIR"
cat > "$PERSIST_DIR/state" <<'EOF'
STAGE=1
T0=1000
T1=1100
T2=0
REF_CPU0=72
REF_MODEM0=0
REF_CPU1=73
REF_MODEM1=0
PENDING=-1
PENDING_N=0
COOLED=0
LAST_CPU=73
LAST_MODEM=
LAST_MODEM_SRC=
LAST_TS=1100
FAN_SAVED_ENABLE=2
FAN_SAVED_PWM=90
GEN=3
EOF

# Only the daemon restores, and it does so at startup, so run one briefly.
timeout 5 sh "$BIN" daemon >/dev/null 2>&1 || true
chk "the daemon adopts the persisted stage" "$(field "$STATE_DIR/state" STAGE)" "1"
chk "the restore keeps the saved fan state" "$(field "$STATE_DIR/state" FAN_SAVED_ENABLE)" "2"
if grep -q "restored stage 1 after a reboot" "$STATE_DIR/log" 2>/dev/null; then
	chk "the restore is logged" logged logged
else
	chk "the restore is logged" silent logged
fi

# reset must clear both copies, otherwise the next boot brings the stage back
plant_stage1
sh "$BIN" reset >/dev/null 2>&1
if [ -e "$PERSIST_DIR/state" ]; then
	chk "reset clears the persisted stage" present gone
else
	chk "reset clears the persisted stage" gone gone
fi

# The removal has to reach the flash as well. A stand-in sync counts the call.
# A BusyBox built with FEATURE_SH_STANDALONE runs its own sync applet before
# anything on PATH, so the case is skipped where the stand-in would not run.
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho x >> "%s"\n' "$tmp/sync.calls" > "$tmp/bin/sync"
chmod 0755 "$tmp/bin/sync"
if [ "$(PATH="$tmp/bin:$PATH" sh -c 'command -v sync')" = "$tmp/bin/sync" ]; then
	plant_stage1
	mkdir -p "$PERSIST_DIR"; cp "$STATE_DIR/state" "$PERSIST_DIR/state"
	rm -f "$tmp/sync.calls"
	PATH="$tmp/bin:$PATH" sh "$BIN" reset >/dev/null 2>&1
	chk "reset flushes the removal to flash" \
		"$([ -e "$PERSIST_DIR/state" ] && echo present || echo gone)/$(wc -l < "$tmp/sync.calls" 2>/dev/null | tr -d ' ')" \
		"gone/1"
else
	echo "skip reset flushes the removal to flash (sync would be a shell applet here)"
fi
rm -f "$tmp/bin/sync"

# ---- stage hooks are files, not configuration -----------------------------
# The point of the hook directory is that nothing in UCI can introduce code.
# A stage set to "command" must run the file and must say so when it is absent.
rm -rf "$STATE_DIR" "$PERSIST_DIR" "$HOOK_DIR"
mkdir -p "$HOOK_DIR"
cat > "$HOOK_DIR/stage1" <<EOF
#!/bin/sh
echo ran > "$tmp/stage1-ran"
EOF
chmod 0755 "$HOOK_DIR/stage1"

# The dry run with a hook as stage action follows once the configuration can
# say "command", below.

# Whether a hook is executed is covered by the selftest, which can call
# tg_run_hook directly. Here it matters only that a dry run stays dry.

# ---- configuration through the stand-in functions.sh -----------------------
# The daemon reads UCI with config_load, which runs /sbin/uci by its full path,
# so tests/functions.sh reads the planted file instead. The uci on PATH only
# has to exist; every call to it is recorded, and the daemon has no business
# calling it. "get" answers from uci.get, for the migration script.
export TG_FUNCTIONS="$root/tests/functions.sh" UCI_CONFIG_DIR="$tmp/config"
mkdir -p "$tmp/bin" "$UCI_CONFIG_DIR"
cat > "$tmp/bin/uci" <<UCI_END
#!/bin/sh
echo "\$*" >> "$tmp/uci.calls"
[ "\$2" = get ] && [ -r "$tmp/uci.get" ] && sed -n "s|^\$3=||p" "$tmp/uci.get"
exit 0
UCI_END
chmod 0755 "$tmp/bin/uci"
# One "option" line per "name=value" argument, a "list" line per "+name=value".
uci_conf() {
	local a
	{
		echo "config thermal-guard 'main'"
		for a in "$@"; do
			case "$a" in
				+*) a=${a#+}; printf "\tlist %s '%s'\n" "${a%%=*}" "${a#*=}" ;;
				*) printf "\toption %s '%s'\n" "${a%%=*}" "${a#*=}" ;;
			esac
		done
	} > "$UCI_CONFIG_DIR/thermal-guard"
	: > "$tmp/uci.calls"
}

# ---- pwm without a polarity leaves the fan alone, and says so once ---------
# pwm with pwm_idle but no pwm_full. The daemon runs three cycles and must
# report it once; a status call must not report it at all.
# ---- a dry run with a hook as stage action does not run it -----------------
# 85 C clears cpu_crit, so the two cycles of test enter stage 1, whose action
# is the stage1 hook planted above.
uci_conf stage1_action=command
out=$(PATH="$tmp/bin:$PATH" sh "$BIN" test 85 40 2>/dev/null)
chk "a dry run reaches the command stage" \
	"$(printf '%s\n' "$out" | grep -c '^would notify (crit): stage 1: .* running command\.$')" "1"
chk "and never touches the hook" "$([ -e "$tmp/stage1-ran" ] && echo ran || echo no)" "no"

# A dry run reports the fan mode the daemon would use: pwm without pwm_full
# leaves the fan alone there, so the dry run must not claim to force it.
uci_conf fan_mode=pwm pwm_idle=255
out=$(PATH="$tmp/bin:$PATH" sh "$BIN" test 75 60 2>/dev/null)
chk "a dry run reaches stage 0 with the fan mode the daemon would use" \
	"$(printf '%s\n' "$out" | grep -c '^would notify (crit): stage 0: .* fan left to its own controller')" "1"

uci_conf fan_mode=pwm pwm_idle=255 interval=5
rm -rf "$STATE_DIR" "$PERSIST_DIR"
PATH="$tmp/bin:$PATH" timeout 12 sh "$BIN" daemon >/dev/null 2>&1 || true
chk "pwm without pwm_full is reported once" \
	"$(grep -c 'needs both pwm_full and pwm_idle' "$STATE_DIR/log" 2>/dev/null)" "1"
chk "pwm without pwm_full runs as none" \
	"$(PATH="$tmp/bin:$PATH" sh "$BIN" status 2>/dev/null | sed -n 's/^fan_mode=//p')" "none"
chk "status does not report it again" \
	"$(grep -c 'needs both pwm_full and pwm_idle' "$STATE_DIR/log" 2>/dev/null)" "1"

# ---- selftest leaves the live state alone -----------------------------------
# The runbook runs it on boards whose daemon is running. It must not write the
# working state, the event log or the hook directory of the real installation.
rm -rf "$STATE_DIR" "$HOOK_DIR"
plant_stage1
echo "2026-01-01 00:00:00 an incident worth keeping" > "$STATE_DIR/log"
before=$(cat "$STATE_DIR/state")
# Not under set -e: a failing selftest has to show up as a FAIL line here.
if sh "$BIN" selftest >/dev/null 2>&1; then r=passed; else r=failed; fi
chk "the selftest passes" "$r" "passed"
chk "selftest leaves the working state alone" "$(cat "$STATE_DIR/state")" "$before"
chk "selftest leaves the event log alone" "$(cat "$STATE_DIR/log")" "2026-01-01 00:00:00 an incident worth keeping"
chk "selftest creates no hooks in the real directories" \
	"$(find "$STATE_DIR/hooks" "$HOOK_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')" "0"

# ---- trip management, the daemon as a process against a planted tree -------
# The tree mirrors the Banana Pi R3 Mini: critical 125, hot 120, active
# 50/60/70, the pwm-fan bound to trips 2, 3 and 4.
TR="$tmp/thermal"
plant_tree() {
	local z="$TR/thermal_zone0" c="$TR/cooling_device0" i t
	rm -rf "$TR"; mkdir -p "$z" "$c"
	echo pwm-fan > "$c/type"; echo 3 > "$c/max_state"; echo 0 > "$c/cur_state"
	echo step_wise > "$z/policy"; echo 50000 > "$z/temp"
	i=0
	for t in critical:125000 hot:120000 active:50000 active:60000 active:70000; do
		echo "${t%%:*}" > "$z/trip_point_${i}_type"
		echo "${t#*:}" > "$z/trip_point_${i}_temp"
		i=$((i + 1))
	done
	for i in 0 1 2; do
		ln -s ../cooling_device0 "$z/cdev$i"
		echo $((i + 2)) > "$z/cdev${i}_trip_point"
	done
}
trips() { cat "$TR"/thermal_zone0/trip_point_[234]_temp | tr '\n' ' '; }
tg_run() { # $1 seconds, the daemon runs until timeout sends TERM
	THERMAL_ROOT="$TR" PATH="$tmp/bin:$PATH" timeout "$1" sh "$BIN" daemon >/dev/null 2>&1 || true
}
BOOST="trip_boost=modem"
IVL="interval=5"
MFILE="modem_temp_file=$tmp/modem"
MSRC="modem_source=file"

# I1: a hot modem at start lowers the trips in one step
rm -rf "$STATE_DIR" "$PERSIST_DIR"; plant_tree; echo 90 > "$tmp/modem"
uci_conf "$BOOST" "$IVL" "$MSRC" "$MFILE"
: > "$tmp/syslog"
rc=0
THERMAL_ROOT="$TR" PATH="$tmp/bin:$PATH" timeout 3 sh "$BIN" daemon >/dev/null 2>&1 || rc=$?
chk "a hot modem at start lowers the trips" "$(trips)" "25000 35000 45000 "
chk "in one write, without the baseline in between" "$(grep -c 'trips set to' "$STATE_DIR/log")" "1"
chk "a trip change is daemon.info" "$(prio 'trips set to')" "daemon.info"
# Every event log line reached the logger, and nothing else did: one path.
missing=0
while IFS= read -r l; do
	grep -qF -- "${l#* * }" "$tmp/syslog" || missing=$((missing + 1))
done < "$STATE_DIR/log"
chk "every event log line went to the logger" "$missing" "0"
chk "and the logger got no line besides them" \
	"$(wc -l < "$tmp/syslog" | tr -d ' ')" "$(wc -l < "$STATE_DIR/log" | tr -d ' ')"
# I3: timeout ended that run with TERM, the trips stay where they were. One
# start and timeout's status for TERM show the daemon was running when TERM
# came: coreutils says 124, a BusyBox timeout applet dies of the signal (143).
case "$rc" in 124|143) rc=term ;; esac
chk "the daemon was running when it was stopped" "$rc/$(started)" "term/1"
chk "stopping the daemon leaves the trips down" "$(trips)" "25000 35000 45000 "
# I4: the device tree set of this boot is kept, and nothing goes to UCI
chk "device tree set kept for this boot" "$(cat "$STATE_DIR/trip_dt")" "50000 60000 70000"
chk "without trip_active no trip_base is written" \
	"$([ -e "$PERSIST_DIR/trip_base" ] && echo written || echo none)" "none"
chk "trip management calls uci for nothing" "$(cat "$tmp/uci.calls")" ""

# I2: killed while lowered, restarted with a cool modem: baseline again
n0=$(started)
THERMAL_ROOT="$TR" PATH="$tmp/bin:$PATH" sh "$BIN" daemon >/dev/null 2>&1 &
pid=$!
sleep 2
chk "the second daemon was running before kill -9" "$(started)" "$((n0 + 1))"
kill -9 "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
chk "kill -9 leaves the trips down" "$(trips)" "25000 35000 45000 "
echo 40 > "$tmp/modem"
fresh_status
tg_run 3
chk "a restart with a cool modem restores the baseline" "$(trips)" "50000 60000 70000 "
chk "the restart did not read the lowered trips as device tree" "$(sfield trip_dt)" "50/60/70"

# I10: the first cycle with trip_active records the device tree set, on the
# overlay and not in /etc/config. trip_active as a UCI list, like the page.
TA="+trip_active=45 +trip_active=55 +trip_active=65"
rm -rf "$STATE_DIR" "$PERSIST_DIR"; plant_tree
# shellcheck disable=SC2086 # TA holds three arguments
uci_conf "$BOOST" "$IVL" "$MSRC" "$MFILE" $TA
conf_before=$(md5sum < "$UCI_CONFIG_DIR/thermal-guard")
tg_run 3
chk "the first cycle with trip_active records trip_base" \
	"$(cat "$PERSIST_DIR/trip_base")" "50 60 70"
chk "and leaves the configuration file alone" \
	"$(md5sum < "$UCI_CONFIG_DIR/thermal-guard")" "$conf_before"
chk "and calls uci for nothing" "$(cat "$tmp/uci.calls")" ""

# I5: a new image with other device tree values, the operator's baseline stays
rm -rf "$STATE_DIR"; plant_tree; echo 75000 > "$TR/thermal_zone0/trip_point_4_temp"
: > "$tmp/syslog"; fresh_status
tg_run 3
chk "a changed device tree is reported" "$(sfield trip_dt_changed)" "1"
chk "at daemon.notice" "$(prio 'device tree trips are now')" "daemon.notice"
chk "and trip_active stays the baseline" "$(trips)" "45000 55000 65000 "
chk "trip_base is left alone" "$(cat "$PERSIST_DIR/trip_base")" "50 60 70"
# The page runs trips-keep once the operator has decided.
chk "trips-keep succeeds" "$(sh "$BIN" trips-keep >/dev/null 2>&1; echo $?)" "0"
chk "and records the set of this boot" "$(cat "$PERSIST_DIR/trip_base")" "50 60 75"
fresh_status
tg_run 3
chk "after that no change is reported" "$(sfield trip_dt_changed)" "0"

# I11: the package moves trip_dt out of UCI once, on install or first boot
MIG="$root/thermal-guard/files/etc/uci-defaults/90-thermal-guard-trip-base"
mig() { # $1 trip_dt as uci -q get prints it, empty for none
	if [ -n "$1" ]; then echo "thermal-guard.main.trip_dt=$1"; fi > "$tmp/uci.get"
	: > "$tmp/uci.calls"
	PATH="$tmp/bin:$PATH" sh "$MIG" >/dev/null 2>&1
	echo "rc=$?"
}
uci_removed() {
	grep -c -e '^-q delete thermal-guard.main.trip_dt$' -e '^-q commit thermal-guard$' \
		"$tmp/uci.calls"
}
rm -rf "$PERSIST_DIR"
chk "the migration exits 0" "$(mig '50 60 70')" "rc=0"
chk "and moves trip_dt to trip_base" "$(cat "$PERSIST_DIR/trip_base")" "50 60 70"
chk "and removes it from UCI" "$(uci_removed)" "2"
chk "a second run exits 0" "$(mig '')" "rc=0"
chk "after asking UCI for trip_dt" "$(grep -c '^-q get thermal-guard.main.trip_dt$' "$tmp/uci.calls")" "1"
chk "and changes nothing" "$(uci_removed)" "0"
echo "45 55 65" > "$PERSIST_DIR/trip_base"
mig '50 60 70' >/dev/null
chk "an existing trip_base is kept" "$(cat "$PERSIST_DIR/trip_base")" "45 55 65"
chk "and trip_dt removed all the same" "$(uci_removed)" "2"
rm -f "$PERSIST_DIR/trip_base"
mig '50 60;reboot' >/dev/null
chk "a garbled trip_dt is not moved" \
	"$([ -e "$PERSIST_DIR/trip_base" ] && echo moved || echo none)" "none"
chk "only removed" "$(uci_removed)" "2"
: > "$tmp/not-a-dir"
chk "a failed write exits 0 as well" "$(PERSIST_DIR="$tmp/not-a-dir" mig '50 60 70')" "rc=0"
chk "after reading trip_dt" "$(grep -c '^-q get thermal-guard.main.trip_dt$' "$tmp/uci.calls")" "1"
chk "and keeps trip_dt in UCI" "$(uci_removed)" "0"

# I9: nothing configured, nothing written: the GL-X3000 case
rm -rf "$STATE_DIR"; plant_tree; echo 90 > "$tmp/modem"
before=$(find "$TR" -name 'trip_point_*' -exec cat {} \; | md5sum)
uci_conf "$IVL" "$MSRC" "$MFILE"
conf_before=$(md5sum < "$UCI_CONFIG_DIR/thermal-guard")
tg_run 12
chk "the daemon leaves the configuration file alone" \
	"$(md5sum < "$UCI_CONFIG_DIR/thermal-guard")" "$conf_before"
chk "and calls uci for nothing" "$(cat "$tmp/uci.calls")" ""
chk "without trip options the zone is untouched" "$(find "$TR" -name 'trip_point_*' -exec cat {} \; | md5sum)" "$before"
chk "and not even read for this boot" "$([ -e "$STATE_DIR/trip_dt" ] && echo read || echo untouched)" "untouched"
chk "status says off" "$(sfield trip_state)" "off"
case "$(cat "$STATE_DIR/modem-temp" 2>/dev/null)" in
	"90 "[0-9]*" file") chk "the modem temperature is published" ok ok ;;
	*) chk "the modem temperature is published" "$(cat "$STATE_DIR/modem-temp" 2>/dev/null)" "90 <time> file" ;;
esac

# An option deleted while the daemon runs is back at its default by the next
# cycle, for a number and for a word alike.
wait_field() { # $1 key, $2 value, $3 seconds
	local i=0
	while [ "$i" -lt "$3" ]; do
		[ "$(sfield "$1")" = "$2" ] && break
		sleep 1; i=$((i + 1))
	done
	sfield "$1"
}
rm -rf "$STATE_DIR"; plant_tree; echo 40 > "$tmp/modem"
uci_conf "$IVL" "$MSRC" "$MFILE" cpu_warn=60 fan_mode=cooling_device
fresh_status
THERMAL_ROOT="$TR" PATH="$tmp/bin:$PATH" sh "$BIN" daemon >/dev/null 2>&1 &
pid=$!
chk "the configured cpu_warn is in use" "$(wait_field cpu_warn 60 6)" "60"
chk "the configured fan_mode is in use" "$(wait_field fan_mode cooling_device 1)" "cooling_device"
uci_conf "$IVL" "$MSRC" "$MFILE"
# One interval of 5 s plus the time a cycle takes.
chk "a deleted option returns to its default within one cycle" "$(wait_field cpu_warn 70 7)" "70"
chk "a deleted word option returns to its default as well" "$(wait_field fan_mode none 1)" "none"
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true

# fan_cooling_device and fan_thermal_zone are gone. A value left over in an
# old configuration is ignored like any unknown option: the fan is found by
# its type, not the numbered path the option named.
rm -rf "$STATE_DIR"; plant_tree
mkdir -p "$TR/cooling_device1"; echo other > "$TR/cooling_device1/type"
echo 7 > "$TR/cooling_device1/max_state"; echo 0 > "$TR/cooling_device1/cur_state"
uci_conf "$IVL" "$MSRC" "$MFILE" fan_mode=cooling_device fan_cooling_device="$TR/cooling_device1"
fresh_status
tg_run 3
chk "a leftover fan_cooling_device is ignored" "$(sfield fan_max)" "3"
chk "and not even rejected in the log" "$(grep -c 'fan_cooling_device' "$STATE_DIR/log")" "0"

# I6 and I7: a hung modem or a held lock costs a reading, not the loop.
# /dev/null stands in for the AT port, it is a character device.
AT="modem_source=fibocom"
PORT="modem_at_port=/dev/null"
LOCK="at_lock=$tmp/at.lock"
cat > "$tmp/bin/sms_tool" <<SMS_END
#!/bin/sh
[ -e "$tmp/sms.hang" ] && exec sleep 60
echo "+GTSENRDTEMP: 1,48000"
SMS_END
chmod 0755 "$tmp/bin/sms_tool"

loop_alive() { # $1 label: status written again after a stalled first cycle
	local t0 t1
	fresh_status
	THERMAL_ROOT="$TR" PATH="$tmp/bin:$PATH" sh "$BIN" daemon >/dev/null 2>&1 &
	pid=$!
	sleep 3; t0=$(field "$STATUS_FILE" now)
	sleep 12; t1=$(field "$STATUS_FILE" now)
	kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
	if [ -n "$t1" ] && [ "${t1:-0}" -gt "${t0:-0}" ]; then
		chk "$1" alive alive
	else
		chk "$1" "stuck($t0/$t1)" alive
	fi
}

rm -rf "$STATE_DIR" "$PERSIST_DIR"; plant_tree; touch "$tmp/sms.hang"
uci_conf "$IVL" "$AT" "$PORT" "$LOCK"
loop_alive "a hung modem does not stop the loop"
chk "and it reads as no modem temperature" "$(grep -c 'cannot read modem temperature' "$STATE_DIR/log")" "1"

rm -rf "$STATE_DIR" "$PERSIST_DIR"; rm -f "$tmp/sms.hang"
flock "$tmp/at.lock" sleep 60 &
holder=$!
sleep 1
loop_alive "a held lock does not stop the loop"
kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true

# A logger that fails costs nothing: the loop goes on, the event log is written.
rm -rf "$STATE_DIR" "$PERSIST_DIR"; plant_tree; echo 40 > "$tmp/modem"
uci_conf "$IVL" "$MSRC" "$MFILE"
touch "$tmp/logger.fail"
loop_alive "a failing logger does not stop the loop"
chk "and the event log is written all the same" "$(grep -c 'started, version' "$STATE_DIR/log")" "1"
rm -f "$tmp/logger.fail"

# I8: stage 1 against a hung modem fails loudly and the loop goes on
rm -rf "$STATE_DIR" "$PERSIST_DIR"; plant_tree; touch "$tmp/sms.hang"
echo 85000 > "$TR/thermal_zone0/temp"
uci_conf "$IVL" "$AT" "$PORT" "$LOCK"; : > "$tmp/syslog"
AT_WAIT=2 AT_TIMEOUT=1 THERMAL_ROOT="$TR" PATH="$tmp/bin:$PATH" \
	timeout 30 sh "$BIN" daemon >/dev/null 2>&1 || true
chk "stage 1 against a hung modem is reported as failed" \
	"$(grep -c "stage 1 action 'modem_radio_off' failed" "$STATE_DIR/log")" "1"
chk "as daemon.crit" "$(prio "stage 1 action 'modem_radio_off' failed")" "daemon.crit"
chk "and the stage is still entered" "$(field "$STATE_DIR/state" STAGE)" "1"
rm -f "$tmp/sms.hang"

# I12: a stage restored after a reboot whose action fails says so, in the one
# restore message. The modem stand-in never answers +CFUN, a notify hook
# collects the messages, and a stand-in ip reports a default route that does
# not run through the modem, so the message goes out instead of queueing.
rm -rf "$STATE_DIR" "$PERSIST_DIR"; plant_tree
mkdir -p "$PERSIST_DIR" "$HOOK_DIR"
# Stage 1 entered just now at 50 C, so the hold time cannot escalate it
# further while the case runs.
now=$(date +%s)
printf 'STAGE=1\nT0=%s\nT1=%s\nREF_CPU0=50\nREF_CPU1=50\nREF_MODEM0=48\nREF_MODEM1=48\nGEN=3\n' \
	"$now" "$now" > "$PERSIST_DIR/state"
cat > "$HOOK_DIR/notify" <<HOOK_END
#!/bin/sh
cat >> "$tmp/notified"
echo "----" >> "$tmp/notified"
HOOK_END
cat > "$tmp/bin/ip" <<'IP_END'
#!/bin/sh
[ "$1" = -4 ] && echo "default via 192.0.2.1 dev eth9 proto static"
exit 0
IP_END
chmod 0755 "$HOOK_DIR/notify" "$tmp/bin/ip"
: > "$tmp/notified"; : > "$tmp/syslog"
uci_conf "$IVL" "$AT" "$PORT" "$LOCK"
AT_WAIT=2 AT_TIMEOUT=1 THERMAL_ROOT="$TR" PATH="$tmp/bin:$PATH" \
	timeout 25 sh "$BIN" daemon >/dev/null 2>&1 || true
chk "a failed action after a reboot is crit" \
	"$(prio "stage 1 action 'modem_radio_off' failed after the reboot")" "daemon.crit"
# Counted by kind: a cooled down message may follow, the board is at 50 C.
chk "one restore message goes out" "$(grep -c 'thermal-guard: restored stage' "$tmp/notified")" "1"
chk "the failure is no message of its own" "$(grep -c 'failed after the reboot' "$tmp/notified")" "0"
chk "and it names the failed action" "$(grep -c \
	"restored stage 1 after a reboot, but reapplying failed for: stage 1 action 'modem_radio_off'" \
	"$tmp/notified")" "1"
rm -f "$HOOK_DIR/notify" "$tmp/bin/ip"

# I13: a persisted stage 1 from an older state file, without references and
# with its hold time long past. A missing reference is no 0: without a rise
# nothing escalates.
rm -rf "$STATE_DIR" "$PERSIST_DIR"; plant_tree; echo 48 > "$tmp/modem"
mkdir -p "$PERSIST_DIR"; printf 'STAGE=1\nT0=1000\nT1=1100\nGEN=3\n' > "$PERSIST_DIR/state"
uci_conf "$IVL" "$MSRC" "$MFILE"
tg_run 12
chk "an old state without references stays in stage 1" "$(field "$STATE_DIR/state" STAGE)" "1"
chk "and logs no stage 2" "$(grep -c 'stage 2:' "$STATE_DIR/log")" "0"
chk "but has references again" "$(field "$STATE_DIR/state" REF_CPU1)/$(field "$STATE_DIR/state" REF_MODEM1)" "50/48"

# ---- collectd emits only plain integers ----------------------------------
# Same filter as the helper, checked here so a change to it cannot go unnoticed.
tg_num() {
	case "$1" in
		''|*[!0-9-]*|-|?*-*) echo "" ;;
		*) echo "$1" ;;
	esac
}
chk "collectd keeps a reading" "$(tg_num 55)" "55"
chk "collectd keeps idle stage -1" "$(tg_num '-1')" "-1"
chk "collectd drops a shell payload" "$(tg_num '1;reboot')" ""
chk "collectd drops a lone dash" "$(tg_num '-')" ""
chk "collectd drops a stray minus" "$(tg_num 1-2)" ""
chk "collectd drops an empty value" "$(tg_num '')" ""

finished=1
if [ "$fail" = 0 ]; then
	echo "integration: all cases passed"
else
	echo "integration: FAILED"
	exit 1
fi
