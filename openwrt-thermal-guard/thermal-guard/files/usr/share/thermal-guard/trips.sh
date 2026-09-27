# SPDX-License-Identifier: GPL-2.0-only
# Trip management for thermal-guard: lowers the active trips of the fan's thermal
# zone while the modem runs hotter than the CPU, so the kernel spins the fan up
# for a heat source it cannot see. Sourced by /usr/sbin/thermal-guard.
# shellcheck shell=busybox
# shellcheck disable=SC2034  # TRIP_* are read by the caller and the status file
#
# Trips only ever go below the baseline, never above it. A wrong modem reading
# can at worst make the box loud, and a dead daemon leaves the trips where they
# were, which is the same safe direction. hot and critical are never written.
#
# All temperatures in here are millidegrees, the unit sysfs uses. Only UCI and
# the log speak whole degrees.

# Readings the effective delta is the maximum of. Lowering acts on one reading,
# raising the trips again needs this many in a row.
TRIP_WINDOW_N=3
TRIP_DELTA_STEP=5000
TRIP_DELTA_MAX=40000

# Runtime state, rebuilt from sysfs by every daemon start.
TRIP_STATE=off; TRIP_REASON=""; TRIP_ZONE=""; TRIP_IDX=""; TRIP_LIMIT=""
TRIP_BASE=""; TRIP_DT=""; TRIP_NOW=""; TRIP_WIN=""; TRIP_DELTA=0
TRIP_WAS_ACTIVE=0; TRIP_DT_CHANGED=0
# What was last said per message, each cleared when its cause is gone.
TRIP_TOLD_FIND=""; TRIP_TOLD_VALID=""; TRIP_TOLD_DT=""; TRIP_TOLD_WRITE=""
# Set once a failed write of trip_base has been reported, until one succeeds.
TRIP_BASE_TOLD=0

# $1 cpu, $2 modem, $3 offset, all whole degrees. Prints the delta in
# millidegrees, or nothing when a reading is missing: no reading is not the same
# as a cool modem, and must not pull the trips back up.
tg_trip_delta() {
	local cpu modem off raw
	cpu=$(tg_int "$1"); modem=$(tg_int "$2"); off=$(tg_int "$3")
	[ -n "$cpu" ] && [ -n "$modem" ] && [ -n "$off" ] || return 0
	raw=$(( (modem - off - cpu) * 1000 ))
	if [ "$raw" -le 0 ]; then
		echo 0
		return 0
	fi
	raw=$(( (raw + TRIP_DELTA_STEP - 1) / TRIP_DELTA_STEP * TRIP_DELTA_STEP ))
	[ "$raw" -gt "$TRIP_DELTA_MAX" ] && raw=$TRIP_DELTA_MAX
	echo "$raw"
}

# Keep the last TRIP_WINDOW_N deltas in TRIP_WIN.
tg_trip_push() {
	local d out=""
	# shellcheck disable=SC2086  # word splitting of the window is intended
	set -- $TRIP_WIN "$1"
	while [ "$#" -gt "$TRIP_WINDOW_N" ]; do shift; done
	for d in "$@"; do
		out="$out${out:+ }$d"
	done
	TRIP_WIN=$out
}

tg_trip_window_max() {
	local d m=0
	for d in $TRIP_WIN; do [ "$d" -gt "$m" ] && m=$d; done
	echo "$m"
}

# $1 space separated list in whole degrees, $2 expected count, $3 limit in
# millidegrees (lowest hot or critical trip, empty if the zone has none).
tg_trip_valid() {
	local v prev="" n=0
	for v in $1; do
		[ -n "$(tg_int "$v")" ] || return 1
		[ "$v" -ge 20 ] && [ "$v" -le 95 ] || return 1
		[ -z "$prev" ] || [ "$v" -gt "$prev" ] || return 1
		[ -z "$3" ] || [ $((v * 1000)) -lt "$3" ] || return 1
		prev=$v; n=$((n + 1))
	done
	[ "$n" -gt 0 ] && [ "$n" -eq "$2" ]
}

# The fan's zone and the active trips its cooling device is bound to, ordered
# by temperature. Sets TRIP_ZONE, TRIP_IDX, TRIP_LIMIT or TRIP_REASON, a fixed
# code the web interface translates.
tg_trip_find() {
	local cdev z c idx t lim=""
	TRIP_ZONE=""; TRIP_IDX=""; TRIP_LIMIT=""
	cdev=$(tg_fan_find_cdev)
	[ -n "$cdev" ] || { TRIP_REASON=no_cdev; return 1; }

	z=$FAN_ZONE
	[ -n "$z" ] || z=$(tg_fan_find_zone "$cdev")
	[ -n "$z" ] || { TRIP_REASON=no_zone; return 1; }
	tg_path_thermal "$z" || { TRIP_REASON=zone_path; return 1; }

	# One "temp index" line per active trip bound to the fan, ordered by
	# temperature. This runs in a subshell, so nothing in it sets a global.
	TRIP_IDX=$(
		for c in "$z"/cdev*; do
			case "${c##*/}" in cdev*[!0-9]*) continue ;; esac
			[ "$(readlink -f "$c")" = "$(readlink -f "$cdev")" ] || continue
			idx=$(tg_int "$(cat "${c}_trip_point" 2>/dev/null)")
			[ -n "$idx" ] || continue
			[ "$(cat "$z/trip_point_${idx}_type" 2>/dev/null)" = active ] || continue
			t=$(tg_int "$(cat "$z/trip_point_${idx}_temp" 2>/dev/null)")
			[ -n "$t" ] || continue
			printf '%s %s\n' "$t" "$idx"
		done | sort -n | uniq | while read -r t idx; do printf '%s ' "$idx"; done
	)
	TRIP_IDX=${TRIP_IDX% }
	[ -n "$TRIP_IDX" ] || { TRIP_REASON=no_active_trip; return 1; }

	for idx in $TRIP_IDX; do
		[ -w "$z/trip_point_${idx}_temp" ] || { TRIP_REASON=not_writable; return 1; }
	done
	# hot and critical bound the baseline from above
	for c in "$z"/trip_point_*_type; do
		case "$(cat "$c" 2>/dev/null)" in
			hot|critical)
				t=$(tg_int "$(cat "${c%_type}_temp" 2>/dev/null)")
				[ -n "$t" ] && { [ -z "$lim" ] || [ "$t" -lt "$lim" ]; } && lim=$t
				;;
		esac
	done
	TRIP_ZONE=$z; TRIP_LIMIT=$lim
	return 0
}

tg_trip_read() { # prints the managed trips in millidegrees
	local idx out=""
	for idx in $TRIP_IDX; do
		out="$out${out:+ }$(tg_int "$(cat "$TRIP_ZONE/trip_point_${idx}_temp" 2>/dev/null)")"
	done
	echo "$out"
}

# $1 target list in millidegrees, same order as TRIP_IDX. Lowering writes the
# lowest trip first and raising the highest first, so the trips stay ascending
# at every point in between. Every write re-checks the type: a trip that is not
# active is never touched, whatever the index says.
tg_trip_write() {
	local want="$1" now p idx w got fail=0
	now=$(tg_trip_read)
	[ "$now" = "$want" ] && return 0
	for p in $(tg_trip_pairs "$want" "$now"); do
		idx=${p%%:*}; w=${p#*:}
		[ "$(cat "$TRIP_ZONE/trip_point_${idx}_type" 2>/dev/null)" = active ] || {
			tg_log "trip $idx is no longer active, not writing it" warning; fail=1; continue; }
		echo "$w" > "$TRIP_ZONE/trip_point_${idx}_temp" 2>/dev/null
		got=$(tg_int "$(cat "$TRIP_ZONE/trip_point_${idx}_temp" 2>/dev/null)")
		[ "$got" = "$w" ] || fail=1
	done
	TRIP_NOW=$(tg_trip_read)
	if [ "$fail" = 1 ]; then
		tg_trip_tell "write" "could not set trips to $(tg_trip_deg "$want") C, they read $(tg_trip_deg "$TRIP_NOW") C" warning
		return 1
	fi
	TRIP_TOLD_WRITE=""
	tg_log "trips set to $(tg_trip_deg "$want") C (delta $((TRIP_DELTA / 1000)) K)"
}

# $1 target, $2 current, both in TRIP_IDX order. Prints idx:value in the order
# they have to be written.
tg_trip_pairs() {
	local i=0 idx p pairs=""
	for idx in $TRIP_IDX; do
		i=$((i + 1))
		p="$idx:$(tg_trip_nth "$i" "$1")"
		if [ -n "$2" ] && [ "${1%% *}" -lt "${2%% *}" ]; then
			pairs="$pairs${pairs:+ }$p"
		else
			pairs="$p${pairs:+ }$pairs"
		fi
	done
	echo "$pairs"
}

tg_trip_nth() { # $1 position, $2 space separated list
	local n=0 v
	for v in $2; do
		n=$((n + 1))
		[ "$n" = "$1" ] && { echo "$v"; return 0; }
	done
}

tg_trip_count() { # number of words in $1
	local n=0 v
	for v in $1; do n=$((n + 1)); done
	echo "$n"
}

tg_trip_deg() { # millidegree list to whole degrees, for the log
	local v out=""
	for v in $1; do out="$out${out:+/}$((v / 1000))"; done
	echo "$out"
}

# Say a thing once until it changes, the daemon runs every interval.
tg_trip_tell() { # $1 find, valid, dt or write, $2 text, $3 priority as for tg_cfg_log
	local told
	case "$1" in
		find) told=$TRIP_TOLD_FIND ;;
		valid) told=$TRIP_TOLD_VALID ;;
		dt) told=$TRIP_TOLD_DT ;;
		write) told=$TRIP_TOLD_WRITE ;;
		*) return 0 ;;
	esac
	[ "$told" = "$2" ] && return 0
	case "$1" in
		find) TRIP_TOLD_FIND=$2 ;;
		valid) TRIP_TOLD_VALID=$2 ;;
		dt) TRIP_TOLD_DT=$2 ;;
		write) TRIP_TOLD_WRITE=$2 ;;
	esac
	tg_cfg_log "$2" "${3:-warning}"
}

# Device tree values of this boot: read once per boot, before anything wrote.
tg_trip_dt_load() {
	local f="$STATE_DIR/trip_dt"
	if [ -r "$f" ]; then
		TRIP_DT=$(cat "$f")
	else
		TRIP_DT=$(tg_trip_read)
		mkdir -p "$STATE_DIR"
		echo "$TRIP_DT" > "$f"
	fi
}

# trip_base holds the device tree set, in whole degrees, that the operator's
# trip_active was made for. It lives on the overlay because a sysupgrade is
# exactly when the device tree changes. Without trip_active it means nothing,
# so it is neither read nor written then.
tg_trip_base_save() { # $1 whole degrees, space separated
	local f="$PERSIST_DIR/trip_base"
	mkdir -p "$PERSIST_DIR" 2>/dev/null &&
		echo "$1" > "$f.tmp" 2>/dev/null && chmod 644 "$f.tmp" &&
		mv "$f.tmp" "$f" 2>/dev/null || return 1
	sync
}

tg_trip_base_read() {
	local v
	v=$(cat "$PERSIST_DIR/trip_base" 2>/dev/null)
	case "$v" in
		*[!0-9\ ]*) echo "" ;;
		*) echo "$v" ;;
	esac
}

# Sets TRIP_DT_CHANGED when the device tree set of this boot is not the one
# trip_base names. The first cycle with trip_active records it.
tg_trip_base_check() {
	local now base msg
	now=$(tg_trip_deg "$TRIP_DT" | tr '/' ' ')
	if [ ! -e "$PERSIST_DIR/trip_base" ]; then
		[ "$DRY" = 1 ] && return 0
		if tg_trip_base_save "$now"; then
			TRIP_BASE_TOLD=0
			return 0
		fi
		[ "$TRIP_BASE_TOLD" = 1 ] && return 0
		tg_cfg_log "could not write $PERSIST_DIR/trip_base, a new firmware will not be noticed"
		[ "$DAEMON" = 1 ] && TRIP_BASE_TOLD=1
		return 0
	fi
	base=$(tg_trip_base_read)
	[ -n "$base" ] && [ "$base" != "$now" ] || return 0
	TRIP_DT_CHANGED=1
	msg="device tree trips are now $(tg_trip_deg "$TRIP_DT") C,"
	tg_trip_tell dt "$msg trip_active was set for $(echo "$base" | tr ' ' '/') C" notice
}

# One cycle. $1 cpu, $2 modem in whole degrees.
tg_trip_cycle() {
	local cpu="$1" modem="$2" d want="" b
	if [ "$TRIP_BOOST" = off ] && [ -z "$TRIP_ACTIVE" ]; then
		TRIP_STATE=off; TRIP_REASON=""
		TRIP_TOLD_FIND=""; TRIP_TOLD_VALID=""; TRIP_TOLD_DT=""
		# Switched off while running: hand the zone back its device tree set
		# once, then leave it alone for good.
		if [ "$TRIP_WAS_ACTIVE" = 1 ] && [ -n "$TRIP_ZONE" ] && [ -n "$TRIP_DT" ]; then
			TRIP_DELTA=0
			tg_trip_write "$TRIP_DT"
			TRIP_WAS_ACTIVE=0; TRIP_WIN=""
		fi
		return 0
	fi

	if ! tg_trip_find; then
		TRIP_STATE=inactive
		tg_trip_tell find "trip management inactive ($TRIP_REASON), zone ${TRIP_ZONE:-none}"
		return 0
	fi
	TRIP_TOLD_FIND=""
	[ -n "$TRIP_DT" ] || tg_trip_dt_load
	TRIP_NOW=$(tg_trip_read)

	# Baseline: the operator's list when it holds up, the device tree otherwise
	if [ -n "$TRIP_ACTIVE" ] &&
		tg_trip_valid "$TRIP_ACTIVE" "$(tg_trip_count "$TRIP_IDX")" "$TRIP_LIMIT"; then
		TRIP_BASE=""
		for b in $TRIP_ACTIVE; do TRIP_BASE="$TRIP_BASE${TRIP_BASE:+ }$((b * 1000))"; done
		TRIP_TOLD_VALID=""
	else
		if [ -n "$TRIP_ACTIVE" ]; then
			tg_trip_tell valid "rejecting trip_active '$TRIP_ACTIVE', using the device tree values"
		else
			TRIP_TOLD_VALID=""
		fi
		TRIP_BASE=$TRIP_DT
	fi

	TRIP_DT_CHANGED=0
	[ -n "$TRIP_ACTIVE" ] && tg_trip_base_check
	[ "$TRIP_DT_CHANGED" = 1 ] || TRIP_TOLD_DT=""

	if [ "$TRIP_BOOST" = modem ]; then
		d=$(tg_trip_delta "$cpu" "$modem" "$TRIP_BOOST_OFFSET")
		[ -n "$d" ] && tg_trip_push "$d"
		d=$(tg_trip_window_max)
		# While a stage is in force the trips do not come back up
		[ "$STAGE" -ge 0 ] && [ "$d" -lt "$TRIP_DELTA" ] && d=$TRIP_DELTA
	else
		d=0; TRIP_WIN=""
	fi
	TRIP_DELTA=$d

	for b in $TRIP_BASE; do want="$want${want:+ }$((b - d))"; done
	TRIP_STATE=active; TRIP_REASON=""; TRIP_WAS_ACTIVE=1
	[ "$DRY" = 1 ] && return 0
	tg_trip_write "$want"
}

# cooling-levels of the pwm-fan from the device tree, for display only. The
# driver reads them once at probe and exposes no sysfs attribute for them.
# Big-endian 32 bit cells; BusyBox on the targets has hexdump but no od.
tg_fan_levels() {
	local f
	for f in "$DT_ROOT"/*/cooling-levels "$DT_ROOT"/*/*/cooling-levels; do
		[ -r "$f" ] || continue
		tr '\0' '\n' < "${f%/*}/compatible" 2>/dev/null | grep -qx pwm-fan || continue
		hexdump -v -e '4/1 "%u " "\n"' "$f" 2>/dev/null |
			awk 'NF == 4 { printf "%s%d", s, $1 * 16777216 + $2 * 65536 + $3 * 256 + $4; s = " " }'
		return 0
	done
}
