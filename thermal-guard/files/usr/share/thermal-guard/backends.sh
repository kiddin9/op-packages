# SPDX-License-Identifier: GPL-2.0-only
# Hardware backends for thermal-guard: fan control, modem temperature, stage actions.
# Sourced by /usr/sbin/thermal-guard, never run on its own.
# shellcheck shell=busybox
# shellcheck disable=SC2034  # MODEM_VAL and MODEM_SRC are read by the caller

# ---- helpers ---------------------------------------------------------------

# Keep integers only so a garbled sysfs read or AT reply cannot reach the logic.
tg_int() {
	case "$1" in
		''|*[!0-9-]*|-|?*-*) echo "" ;;
		*) echo "$1" ;;
	esac
}

# Whether a program or function is there. The one place that asks, so the
# selftest can take a tool away without touching the host.
tg_have() {
	command -v "$1" >/dev/null 2>&1
}

# Absolute path, no .. and no wildcards. Stops UCI from pointing us at random files.
tg_path_ok() {
	case "$1" in
		''|*..*|*\**|*\?*|*\\*|*[!\ -~]*) return 1 ;;
		/*) return 0 ;;
		*) return 1 ;;
	esac
}

# $1 path, $2 prefix. The prefix ends in a slash, so a sibling like /tmpfoo
# cannot pass as /tmp/.
tg_path_under() {
	tg_path_ok "$1" || return 1
	case "$1" in
		"$2"*) return 0 ;;
		*) return 1 ;;
	esac
}

tg_path_thermal() { tg_path_under "$1" "$THERMAL_ROOT/"; }
tg_path_hwmon() {
	tg_path_under "$1" "$HWMON_ROOT/" || tg_path_under "$1" /sys/devices/
}
# Boards differ on where the SoC sensor lives: a thermal zone on most targets,
# a hwmon node on x86 with coretemp. Both have to stay reachable.
tg_path_sensor() {
	tg_path_thermal "$1" || tg_path_hwmon "$1"
}
tg_path_modem_file() {
	tg_path_under "$1" /var/run/ || tg_path_under "$1" /tmp/ || tg_path_under "$1" /sys/
}
tg_path_lock() {
	tg_path_under "$1" /var/lock/ || tg_path_under "$1" /var/run/ ||
		tg_path_under "$1" /tmp/
}
tg_path_dev() { tg_path_under "$1" /dev/; }

# ---- notification delivery -------------------------------------------------
#
# A message goes out over HTTP, which covers ntfy, Gotify, Matrix, Slack and the
# rest, and needs no shell command from the configuration to do it. curl is
# preferred where present because it can send a header; uclient-fetch ships in
# the OpenWrt base but has no way to set one.
tg_fetcher() {
	tg_have curl && { echo curl; return; }
	tg_have uclient-fetch && { echo uclient-fetch; return; }
	tg_have wget && { echo wget; return; }
}

# Curl reads its config file as directives, and one of them writes a file. A
# quote would end the value and turn the rest into more of them, a newline
# would start one outright. Neither belongs in a url or a header anyway, so
# reject both along with every other non-printable character rather than
# escaping and hoping the escaping is right.
tg_http_safe() {
	# The '\' alternative is a literal backslash and is meant to be one.
	# shellcheck disable=SC1003
	case "$1" in
		''|*'"'*|*'\'*|*[!\ -~]*) return 1 ;;
		*) return 0 ;;
	esac
}

# $1 message. The url and any header go through a config file rather than the
# command line: they routinely carry an access token, and /proc/*/cmdline is
# readable by every local process.
tg_notify_http() {
	local tool cfg rc
	[ -n "$NOTIFY_URL" ] || return 1

	case "$NOTIFY_URL" in
		http://?*|https://?*) ;;
		*) tg_log "notify_url is not an http or https address, not sending" warning; return 1 ;;
	esac
	if ! tg_http_safe "$NOTIFY_URL"; then
		tg_log "notify_url contains characters that are not allowed in one, not sending" warning
		return 1
	fi
	if [ -n "$NOTIFY_HEADER" ] && ! tg_http_safe "$NOTIFY_HEADER"; then
		tg_log "notify_header contains characters that are not allowed in one, not sending" warning
		return 1
	fi

	tool=$(tg_fetcher)
	[ -n "$tool" ] || {
		tg_log "no curl or wget available, cannot send notifications" warning
		return 1
	}

	if [ "$tool" = curl ]; then
		NOTIFY_HEADER_TOLD=""
		mkdir -p "$STATE_DIR"
		cfg="$STATE_DIR/notify.conf"
		: > "$cfg"
		chmod 600 "$cfg" 2>/dev/null
		printf 'url = "%s"\n' "$NOTIFY_URL" >> "$cfg"
		[ -n "$NOTIFY_HEADER" ] && printf 'header = "%s"\n' "$NOTIFY_HEADER" >> "$cfg"
		printf '%s\n' "$1" | curl -fsS -m 15 -K "$cfg" --data-binary @- >/dev/null 2>&1
		rc=$?
		rm -f "$cfg"
		return $rc
	fi

	# Said once per fetcher, not per message and not per retry of the outbox.
	if [ -z "$NOTIFY_HEADER" ]; then
		NOTIFY_HEADER_TOLD=""
	elif [ "$NOTIFY_HEADER_TOLD" != "$tool" ]; then
		tg_log "$tool cannot send a header, install curl for authenticated webhooks" warning
		NOTIFY_HEADER_TOLD=$tool
	fi
	# -T bounds the network wait only, the outer limit also covers a hung DNS lookup.
	timeout "$HTTP_TIMEOUT" "$tool" -q -T 15 -O /dev/null --post-data="$1" "$NOTIFY_URL" \
		>/dev/null 2>&1
}

# The escape hatch for anything HTTP cannot express, a local mailer for example.
# It is a file an administrator puts there over ssh, not a string from the
# configuration, so editing the config cannot introduce code that runs as root.
tg_notify_hook() {
	local hook="$HOOK_DIR/notify"
	[ -x "$hook" ] || return 1
	printf '%s\n' "$1" | timeout -k 5 "$HOOK_TIMEOUT" "$hook" >/dev/null 2>&1
}

# Run an AT command through a lock. Several daemons and LuCI apps share one port
# and the modem answers a collision with nothing at all. Both the wait for the
# lock and the query are bounded: a modem that hangs, or a program that sits on
# the lock, must not stop the whole loop. BusyBox flock has no -w, so the outer
# timeout covers the wait and the inner one the query.
# Without flock the query still runs, the modem reading matters more than the
# lock. But another program on the port can garble it now, so say so once.
tg_at_unlocked() {
	[ "$FLOCK_TOLD" = 1 ] && return 0
	tg_cfg_log "no flock command, AT queries run without the shared lock"
	[ "$DAEMON" = 1 ] && FLOCK_TOLD=1
	return 0
}

tg_at() {
	local port="$1" cmd="$2" lock=$AT_LOCK
	# Checked here as well as at load: the value goes to flock, which creates
	# the file it names.
	tg_path_lock "$lock" || lock=/var/lock/modem-at.lock
	[ -c "$port" ] || return 1
	tg_have sms_tool || return 1
	if ! tg_have timeout; then
		if [ "$AT_NO_TIMEOUT_TOLD" = 0 ]; then
			tg_cfg_log "no timeout command, AT queries run without a time limit"
			[ "$DAEMON" = 1 ] && AT_NO_TIMEOUT_TOLD=1
		fi
		if tg_have flock; then
			flock "$lock" sms_tool -d "$port" at "$cmd" 2>/dev/null
		else
			tg_at_unlocked
			sms_tool -d "$port" at "$cmd" 2>/dev/null
		fi
		return
	fi
	if tg_have flock; then
		timeout "$AT_WAIT" flock "$lock" timeout "$AT_TIMEOUT" sms_tool -d "$port" at "$cmd" 2>/dev/null
	else
		tg_at_unlocked
		timeout "$AT_TIMEOUT" sms_tool -d "$port" at "$cmd" 2>/dev/null
	fi
}

# Other programs read the modem temperature here instead of asking the modem
# themselves. Written after a good reading only, so its age shows an outage.
tg_modem_publish() {
	local f="$STATE_DIR/modem-temp"
	[ -n "$MODEM_VAL" ] || return 0
	mkdir -p "$STATE_DIR"
	printf '%s %s %s\n' "$MODEM_VAL" "$(date +%s)" "$MODEM_SRC" > "$f.tmp" || return 0
	chmod 644 "$f.tmp" 2>/dev/null
	mv "$f.tmp" "$f"
}

# ---- fan -------------------------------------------------------------------

tg_fan_detect() {
	tg_fan_pick
	tg_fan_pick_view
}

# Pick a backend. "auto" only ever means the cooling device, whose polarity the
# device tree carries; a raw pwm output needs pwm_full and pwm_idle from the
# operator, and without both this stays off the fan.
tg_fan_pick() {
	case "$FAN_MODE" in
		cooling_device|pwm|none) ;;
		*)
			if [ -n "$(tg_fan_find_cdev)" ]; then
				FAN_MODE=cooling_device
			else
				FAN_MODE=none
			fi
			;;
	esac

	if [ "$FAN_MODE" = pwm ]; then
		if ! tg_fan_polarity_known; then
			FAN_MODE=none
			[ "$FAN_POLARITY_TOLD" = 1 ] && return 0
			tg_cfg_log "fan_mode pwm needs both pwm_full and pwm_idle, leaving the fan alone"
			[ "$DAEMON" = 1 ] && FAN_POLARITY_TOLD=1
			return 0
		fi
		tg_fan_resolve_pwm
	fi

	if [ "$FAN_MODE" = cooling_device ]; then
		[ -n "$FAN_CDEV" ] || FAN_CDEV=$(tg_fan_find_cdev)
		[ -n "$FAN_CDEV" ] || { FAN_MODE=none; return; }
		if ! tg_path_thermal "$FAN_CDEV"; then
			tg_cfg_log "rejecting fan cooling device path: $FAN_CDEV"
			FAN_CDEV=""; FAN_MODE=none; return
		fi
		# A zone is optional. It is only needed to take the cooling device away
		# from a kernel governor, and plenty of boards ship a pwm-fan cooling
		# device that no zone binds. There the state can be written straight
		# out, and there is nothing to hand back either.
		[ -n "$FAN_ZONE" ] || FAN_ZONE=$(tg_fan_find_zone "$FAN_CDEV")
		if [ -n "$FAN_ZONE" ] && ! tg_path_thermal "$FAN_ZONE"; then
			tg_cfg_log "rejecting fan thermal zone path: $FAN_ZONE"
			FAN_ZONE=""
		fi
	fi
}

# What the fan is read from, which FAN_MODE does not decide when it is none: the
# fan then belongs to another program, and what it is doing is still the most
# useful thing on the page. The raw pwm output comes first where the polarity is
# known, because a cooling device's cur_state is derived from cooling-levels
# and reads full speed as stopped on a board whose levels descend.
tg_fan_pick_view() {
	local cdev
	if [ "$FAN_MODE" != none ]; then
		FAN_VIEW=$FAN_MODE
		return 0
	fi
	FAN_VIEW=none
	tg_fan_resolve_pwm
	if [ -n "$PWM_PATH" ] && [ -r "$PWM_PATH" ] && tg_fan_polarity_known; then
		FAN_VIEW=pwm
		return 0
	fi
	cdev=$(tg_fan_find_cdev)
	if [ -n "$cdev" ] && tg_path_thermal "$cdev"; then
		FAN_CDEV=$cdev; FAN_VIEW=cooling_device
		return 0
	fi
	[ -n "$PWM_PATH" ] && [ -r "$PWM_PATH" ] && FAN_VIEW=pwm
	return 0
}

tg_fan_polarity_known() {
	[ -n "$(tg_int "$PWM_FULL")" ] && [ -n "$(tg_int "$PWM_IDLE")" ]
}

# A cooling device whose max_state is 0 can cool by exactly nothing. Selecting
# it would have tg_fan_full write that 0 and report success, so stage 1 would
# announce a fan at full speed and change nothing at all.
tg_fan_find_cdev() {
	local d max
	for d in "$THERMAL_ROOT"/cooling_device*; do
		[ -r "$d/type" ] || continue
		case "$(cat "$d/type" 2>/dev/null)" in
			"$FAN_CDEV_TYPE") ;;
			*) continue ;;
		esac
		max=$(tg_int "$(cat "$d/max_state" 2>/dev/null)")
		[ -n "$max" ] && [ "$max" -gt 0 ] || continue
		echo "$d"
		return
	done
}

# Fill in the pwm paths from the detected chip. A configured path that works is
# left alone; one that stopped working is replaced, because a renumbered hwmon
# is the likely reason and running without a fan is not an option here.
tg_fan_resolve_pwm() {
	local h
	[ -n "$PWM_PATH" ] && [ -w "$PWM_PATH" ] && [ -n "$PWM_ENABLE_PATH" ] && return 0

	h=$(tg_fan_find_hwmon)
	[ -n "$h" ] || return 0
	tg_path_hwmon "$h" || return 0

	if [ -z "$PWM_PATH" ] || [ ! -w "$PWM_PATH" ]; then
		[ -w "$h/pwm1" ] && tg_fan_set_pwm_path "$h/pwm1"
	fi
	[ -n "$PWM_ENABLE_PATH" ] || [ ! -e "$h/pwm1_enable" ] || PWM_ENABLE_PATH="$h/pwm1_enable"
	return 0
}

tg_fan_set_pwm_path() {
	local old=$PWM_PATH
	[ "$1" = "$old" ] && return 0
	PWM_PATH="$1"
	[ "$PWM_PATH_TOLD" = "$old>$1" ] && return 0
	if [ -z "$old" ]; then
		tg_cfg_log "fan pwm output detected at '$1'" info
	else
		tg_cfg_log "fan pwm path '$old' unusable, using detected '$1'"
	fi
	[ "$DAEMON" = 1 ] && PWM_PATH_TOLD="$old>$1"
	return 0
}

# hwmon numbers are assigned in driver probe order, so hwmon2 today can be
# hwmon1 after adding an NVMe or a kernel update. Find the fan chip by its name
# instead: writing a duty cycle to whatever landed on that number is exactly the
# silent failure this daemon exists to prevent.
tg_fan_find_hwmon() {
	local h
	for h in "$HWMON_ROOT"/hwmon*; do
		[ -r "$h/name" ] || continue
		case "$(cat "$h/name" 2>/dev/null)" in
			pwmfan|pwm-fan|pwm_fan) echo "$h"; return ;;
		esac
	done
}

# The zone that drives this cooling device, so we know whose governor to switch.
tg_fan_find_zone() {
	local cdev="$1" z c
	for z in "$THERMAL_ROOT"/thermal_zone*; do
		for c in "$z"/cdev*; do
			[ -e "$c" ] || continue
			[ "$(readlink -f "$c")" = "$(readlink -f "$cdev")" ] && { echo "$z"; return; }
		done
	done
}

tg_fan_state() {
	case "$FAN_VIEW" in
		cooling_device)
			tg_path_thermal "$FAN_CDEV" || return
			cat "$FAN_CDEV/cur_state" 2>/dev/null
			;;
		pwm)
			tg_path_hwmon "$PWM_PATH" || return
			cat "$PWM_PATH" 2>/dev/null
			;;
	esac
}

tg_fan_max() {
	case "$FAN_VIEW" in
		cooling_device)
			tg_path_thermal "$FAN_CDEV" || return
			cat "$FAN_CDEV/max_state" 2>/dev/null
			;;
		pwm) tg_fan_polarity_known && echo "$PWM_FULL" ;;
	esac
}

# Fan speed as 0..100 regardless of how the raw scale runs. For pwm that is the
# span between PWM_IDLE and PWM_FULL, which may descend on an inverted board;
# for a cooling device it is cur_state against max_state, which always ascends.
# Without this the status page reports a fan at full speed as nearly stopped.
tg_fan_percent() { # $1 optional raw value, otherwise the live reading
	local cur max span pct
	cur=${1:-$(tg_fan_state)}
	cur=$(tg_int "$cur")
	[ -n "$cur" ] || return 0

	case "$FAN_VIEW" in
		pwm)
			tg_fan_polarity_known || return 0
			span=$((PWM_FULL - PWM_IDLE))
			[ "$span" -ne 0 ] || return 0
			pct=$(( (cur - PWM_IDLE) * 100 / span ))
			;;
		cooling_device)
			max=$(tg_int "$(tg_fan_max)")
			[ -n "$max" ] && [ "$max" -gt 0 ] || return 0
			pct=$((cur * 100 / max))
			;;
		*) return 0 ;;
	esac

	[ "$pct" -lt 0 ] && pct=0
	[ "$pct" -gt 100 ] && pct=100
	echo "$pct"
}

# We forced the fan when the stage was entered. If the value is gone the chip
# belongs to someone else, a second fan daemon or a governor we did not take
# over. Re-assert, because too much cooling is the safe direction, but say once
# what is happening instead of quietly fighting every cycle.
FAN_FOREIGN=0
tg_fan_check_owner() {
	local want have
	if [ "$STAGE" -lt 0 ]; then
		# Idle, so nothing of ours is in there to compare against. For a
		# cooling device the zone still tells: user_space means somebody took
		# it off its governor, and it was not this daemon. Worth knowing
		# before an incident rather than during one.
		FAN_FOREIGN=0
		[ "$FAN_MODE" = cooling_device ] && [ -n "$FAN_ZONE" ] || return 0
		tg_path_thermal "$FAN_ZONE" || return 0
		[ "$(cat "$FAN_ZONE/policy" 2>/dev/null)" = user_space ] || return 0
		FAN_FOREIGN=1
		tg_cfg_log "thermal zone is on user_space while no stage is active, another program drives this fan"
		return 0
	fi

	case "$FAN_MODE" in
		pwm) want=$PWM_FULL ;;
		cooling_device) want=$(tg_int "$(tg_fan_max)") ;;
		*) FAN_FOREIGN=0; return 0 ;;
	esac
	have=$(tg_int "$(tg_fan_state)")
	[ -n "$want" ] && [ -n "$have" ] || return 0

	if [ "$have" = "$want" ]; then
		FAN_FOREIGN=0
		return 0
	fi
	[ "$FAN_FOREIGN" = 1 ] || tg_log "fan was set to $want but reads $have, another controller owns it. Set fan_mode=none to leave it alone." warning
	FAN_FOREIGN=1
	tg_fan_full || tg_log "could not reassert the fan (mode $FAN_MODE)" crit
}

tg_fan_rpm() {
	local h
	for h in "$HWMON_ROOT"/hwmon*/fan1_input; do
		[ -r "$h" ] && { cat "$h"; return; }
	done
}

# Force full speed. cooling_device takes the zone away from the kernel governor,
# pwm writes the duty cycle after taking manual control of the chip.
tg_fan_full() {
	case "$FAN_MODE" in
		cooling_device)
			tg_path_thermal "$FAN_CDEV" || return 1
			# Take the zone off its governor first, where there is one, and
			# remember what it was on. Another program may already have taken
			# it, and handing it back to the configured default rather than to
			# what was actually there would cut that program's cooling short.
			if [ -n "$FAN_ZONE" ]; then
				tg_path_thermal "$FAN_ZONE" || return 1
				[ -n "$FAN_SAVED_POLICY" ] ||
					FAN_SAVED_POLICY=$(cat "$FAN_ZONE/policy" 2>/dev/null)
				echo user_space > "$FAN_ZONE/policy" 2>/dev/null || return 1
			fi
			# max_state means maximum cooling whichever way the cooling-levels
			# in the device tree run, so this mode needs no idea of polarity.
			tg_fan_max > "$FAN_CDEV/cur_state" 2>/dev/null
			;;
		pwm)
			# Remember what the chip was doing before we take it over. The
			# release writes this back, which beats asking the admin for a
			# shell command and survives a daemon restart via the state file.
			if [ -n "$PWM_ENABLE_PATH" ] && [ -z "$FAN_SAVED_ENABLE" ]; then
				FAN_SAVED_ENABLE=$(tg_int "$(cat "$PWM_ENABLE_PATH" 2>/dev/null)")
			fi
			if [ -n "$PWM_PATH" ] && [ -z "$FAN_SAVED_PWM" ]; then
				FAN_SAVED_PWM=$(tg_int "$(cat "$PWM_PATH" 2>/dev/null)")
			fi

			if [ -n "$PWM_ENABLE_PATH" ]; then
				tg_path_hwmon "$PWM_ENABLE_PATH" || return 1
				echo 1 > "$PWM_ENABLE_PATH" 2>/dev/null
			fi
			if [ -n "$PWM_PATH" ]; then
				tg_path_hwmon "$PWM_PATH" || return 1
				echo "$PWM_FULL" > "$PWM_PATH" 2>/dev/null
			fi
			;;
		none) return 1 ;;
	esac
}

# Hand the fan back. Only called on an explicit reset or a clean stop, never on
# the escalation path, so a crash leaves the fan running.
# Hands the zone to governor $1 and reads the policy back. The kernel refuses
# a governor it was built without, which would leave the zone on user_space
# and the fan at full speed with nobody told. step_wise is in every kernel
# with thermal support. Without available_policies the name is written as is.
tg_fan_zone_policy() {
	local want="$1" avail got
	avail=$(cat "$FAN_ZONE/available_policies" 2>/dev/null)
	if [ -n "$avail" ]; then
		case " $avail " in
			*" $want "*) ;;
			*)
				tg_log "governor '$want' is not available on this zone, handing it to step_wise" warning
				want=step_wise ;;
		esac
	fi
	# Braces, so a failed open is as quiet as a failed write.
	{ echo "$want" > "$FAN_ZONE/policy"; } 2>/dev/null
	got=$(cat "$FAN_ZONE/policy" 2>/dev/null)
	[ "$got" = "$want" ] && return 0
	tg_log "zone still reports policy '${got:-nothing}' after handing it back" crit
	return 1
}

# Writes $2 to $1 and reads it back; $3 names the value in the log.
tg_fan_write_back() {
	local got
	{ echo "$2" > "$1"; } 2>/dev/null
	got=$(tg_int "$(cat "$1" 2>/dev/null)")
	[ "$got" = "$2" ] && return 0
	tg_log "$3 reads '${got:-nothing}' after handing it back, wrote '$2'" crit
	return 1
}

tg_fan_release() {
	local mode=""
	case "$FAN_MODE" in
		cooling_device)
			# Nothing to hand back where no zone drives the cooling device.
			[ -n "$FAN_ZONE" ] || return 0
			tg_path_thermal "$FAN_ZONE" || return 0
			# Back to whatever held the zone before, which may be another
			# program's user_space rather than a kernel governor. Only where
			# nothing was recorded, because the state was lost, does the
			# configured default get used as the safety net.
			if [ -n "$FAN_SAVED_POLICY" ]; then
				tg_fan_zone_policy "$FAN_SAVED_POLICY"
			else
				tg_log "no saved fan policy, handing the zone to $FAN_GOVERNOR"
				tg_fan_zone_policy "$FAN_GOVERNOR"
			fi
			FAN_SAVED_POLICY=""
			;;
		pwm)
			# Put back what we found. The fallback 2 means "automatic" on the
			# usual pwm chips; 0 is never written, because on some of them that
			# stops the fan, which is the opposite of what a release should do.
			if [ -n "$PWM_ENABLE_PATH" ] && tg_path_hwmon "$PWM_ENABLE_PATH"; then
				mode=$FAN_SAVED_ENABLE
				if [ -z "$mode" ] || [ "$mode" = 0 ]; then
					tg_log "no saved fan control mode, handing the fan to automatic"
					mode=2
				fi
				tg_fan_write_back "$PWM_ENABLE_PATH" "$mode" "fan control mode"
			fi
			# The duty cycle only in manual mode, or where there is no mode to
			# set. In any other mode the chip drives it: the value saved before
			# the takeover means nothing, some drivers refuse it with EINVAL,
			# and reading it back would report the chip's own value as failure.
			case "$mode" in
				''|1)
					if [ -n "$FAN_SAVED_PWM" ] && [ -n "$PWM_PATH" ] && tg_path_hwmon "$PWM_PATH"; then
						tg_fan_write_back "$PWM_PATH" "$FAN_SAVED_PWM" "fan pwm"
					fi
					;;
			esac
			FAN_SAVED_ENABLE=""; FAN_SAVED_PWM=""
			;;
	esac
	return 0
}

# ---- temperatures ----------------------------------------------------------

# Where the SoC sensor lives differs per target: a thermal zone on mediatek and
# most ARM boards, a hwmon node on ramips (MT7628) and on x86 with coretemp.
# Called when the configured path does not read, so a board nobody configured
# still gets watched instead of running blind.
#
# Prefers a zone or chip whose name looks like the SoC, then falls back to the
# first thermal zone, which is the SoC on the boards that have only one.
tg_find_cpu_sensor() {
	local f name

	for f in "$THERMAL_ROOT"/thermal_zone*/temp; do
		[ -r "$f" ] || continue
		name=$(cat "${f%/*}/type" 2>/dev/null)
		case "$name" in
			*cpu*|*soc*|*tsens*|*pkg*) echo "$f"; return ;;
		esac
	done

	for f in "$HWMON_ROOT"/hwmon*/temp1_input; do
		[ -r "$f" ] || continue
		name=$(cat "${f%/*}/name" 2>/dev/null)
		case "$name" in
			*cpu*|*soc*|*thermal*|coretemp|*7620*|*7628*) echo "$f"; return ;;
		esac
	done

	for f in "$THERMAL_ROOT"/thermal_zone*/temp; do
		[ -r "$f" ] && { echo "$f"; return; }
	done
}

# True when the board reports no temperature at all. Distinguishes "this path is
# wrong" from "there is nothing to read here", which are different problems: the
# first is a typo, the second is a fact about the hardware. Several ramips
# boards, the GL-MT300N-V2 among them, expose neither a thermal zone nor a
# hwmon temperature input.
tg_has_any_sensor() {
	local f
	for f in "$THERMAL_ROOT"/thermal_zone*/temp "$HWMON_ROOT"/hwmon*/temp*_input; do
		[ -r "$f" ] && return 0
	done
	return 1
}

# Sysfs reports millidegrees, some drivers degrees. Anything above 1000 is mC.
tg_read_cpu() {
	local raw
	tg_path_sensor "$CPU_TEMP_PATH" || { echo ""; return; }
	raw=$(tg_int "$(cat "$CPU_TEMP_PATH" 2>/dev/null)")
	[ -n "$raw" ] || { echo ""; return; }
	[ "$raw" -gt 1000 ] && raw=$((raw / 1000))
	echo "$raw"
}

tg_modem_port() {
	local p
	if [ "$MODEM_AT_PORT" != auto ]; then
		tg_path_dev "$MODEM_AT_PORT" || return
		[ -c "$MODEM_AT_PORT" ] && echo "$MODEM_AT_PORT"
		return
	fi
	for p in /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB3 /dev/mhi_DUN /dev/cdc-wdm0; do
		[ -c "$p" ] && { echo "$p"; return; }
	done
}

# Quectel: AT+QTEMP lists named sensors in degrees. Take the hottest one and drop
# the -273 placeholders unpopulated sensors report.
tg_modem_quectel() {
	tg_at "$1" 'AT+QTEMP' \
		| sed -n 's/^+QTEMP:.*,"\(-\{0,1\}[0-9]\{1,3\}\)".*/\1/p' \
		| awk '$1 > -100 && $1 < 150 && $1 > m { m = $1 } END { if (m != "") print m }'
}

# Fibocom: AT+GTSENRDTEMP=0 answers "<id>,<millidegrees>" per sensor. Only the RF
# and modem sensors matter, the rest read 0 while idle.
tg_modem_fibocom() {
	tg_at "$1" 'AT+GTSENRDTEMP=0' | tr -d '\r' \
		| sed -n 's/^+GTSENRDTEMP: *\(1[01457]\),\([0-9]*\)$/\1 \2/p' \
		| awk '$2 > 0 && $2 > m { m = $2 } END { if (m > 0) printf "%d", m / 1000 }'
}

# Sets MODEM_VAL and MODEM_SRC. Empty value means "no reading", which the logic
# treats as "condition met" so a dead modem never blocks an escalation.
tg_read_modem() {
	local port v rc
	MODEM_VAL=""; MODEM_SRC=""

	case "$MODEM_SOURCE" in
		none) return 0 ;;
		file)
			tg_path_modem_file "$MODEM_TEMP_FILE" || return 0
			v=$(tg_int "$(cat "$MODEM_TEMP_FILE" 2>/dev/null)")
			[ -n "$v" ] && [ "$v" -gt 1000 ] && v=$((v / 1000))
			[ -n "$v" ] && { MODEM_VAL=$v; MODEM_SRC="file"; }
			return 0
			;;
		command)
			# An executable from the hook directory, not a string from UCI.
			[ -x "$HOOK_DIR/modem-temp" ] || return 0
			v=$({ timeout -k 5 "$AT_TIMEOUT" "$HOOK_DIR/modem-temp"; } 2>/dev/null)
			rc=$?
			# Stopped at its time limit: coreutils timeout says 124, or 137 for
			# the KILL a hook that ignored TERM gets; a BusyBox timeout dies of
			# the signal itself (143, 137). What such a hook printed before is
			# no reading.
			[ "$rc" -eq 124 ] || [ "$rc" -gt 128 ] && return 0
			v=$(tg_int "$v")
			[ -n "$v" ] && { MODEM_VAL=$v; MODEM_SRC="command"; }
			return 0
			;;
	esac

	port=$(tg_modem_port)
	[ -n "$port" ] || return 0

	case "$MODEM_SOURCE" in
		quectel) v=$(tg_modem_quectel "$port") ;;
		fibocom) v=$(tg_modem_fibocom "$port") ;;
		auto)
			v=$(tg_modem_quectel "$port")
			[ -n "$v" ] || v=$(tg_modem_fibocom "$port")
			;;
	esac

	v=$(tg_int "$v")
	[ -n "$v" ] && [ "$v" -ge 1 ] && [ "$v" -le 150 ] && { MODEM_VAL=$v; MODEM_SRC="at"; }
	return 0
}

# Everything else the board reports: Wi-Fi chips, ethernet phys, disks. Printed as
# "name=degrees" per line. The source of the processor reading is skipped so it does
# not show up twice, and hwmon entries win over thermal zones with the same name.
tg_read_extra_sensors() {
	local f name label raw seen=" " cpu_zone="" cpu_real="" cpu
	[ "$EXTRA_SENSORS" = 1 ] || return 0

	# The processor is shown on its own, so its sensor is skipped by path. A
	# thermal zone is also mirrored by the kernel as a hwmon node named after
	# the zone's type, which the path does not catch: that mirror is skipped
	# by name. Neither check makes the other redundant.
	# The loops walk class paths. A cpu_temp_path set by hand in its
	# /sys/devices form matches none of them, so only then is it resolved and
	# compared resolved: that costs a readlink per sensor, which the default
	# and every detected path, all in class form, do not need.
	case "$CPU_TEMP_PATH" in
		"$THERMAL_ROOT"/*|"$HWMON_ROOT"/*) ;;
		*) cpu_real=$(readlink -f "$CPU_TEMP_PATH" 2>/dev/null) ;;
	esac
	cpu=${cpu_real:-$CPU_TEMP_PATH}
	# The kernel names a zone's hwmon mirror after the zone type with "-" turned
	# into "_", hwmon names carry no hyphen: zone cpu-thermal, mirror
	# cpu_thermal. So the zone side is normalised, once, and compared as is.
	case "$cpu" in
		*/thermal_zone*/temp)
			cpu_zone=$(cat "${cpu%/temp}/type" 2>/dev/null | tr '-' '_') ;;
	esac

	for f in "$HWMON_ROOT"/hwmon*/temp*_input; do
		[ -r "$f" ] || continue
		[ "$f" = "$CPU_TEMP_PATH" ] && continue
		[ -n "$cpu_real" ] && [ "$(readlink -f "$f")" = "$cpu_real" ] && continue
		name=$(cat "${f%/*}/name" 2>/dev/null)
		[ -n "$name" ] || continue
		[ -n "$cpu_zone" ] && [ "$name" = "$cpu_zone" ] && continue
		# a chip with several sensors labels them, use that to tell them apart
		label=$(cat "${f%_input}_label" 2>/dev/null)
		[ -n "$label" ] && name="$name $label"
		case "$seen" in *" $name "*) continue ;; esac
		raw=$(tg_int "$(cat "$f" 2>/dev/null)")
		[ -n "$raw" ] || continue
		[ "$raw" -gt 1000 ] && raw=$((raw / 1000))
		[ "$raw" -gt -100 ] && [ "$raw" -lt 200 ] || continue
		seen="$seen$name "
		printf '%s=%s\n' "$name" "$raw"
	done

	for f in "$THERMAL_ROOT"/thermal_zone*/temp; do
		[ -r "$f" ] || continue
		[ "$f" = "$CPU_TEMP_PATH" ] && continue
		[ -n "$cpu_real" ] && [ "$(readlink -f "$f")" = "$cpu_real" ] && continue
		name=$(cat "${f%/*}/type" 2>/dev/null)
		[ -n "$name" ] || continue
		case "$seen" in *" $name "*) continue ;; esac
		raw=$(tg_int "$(cat "$f" 2>/dev/null)")
		[ -n "$raw" ] || continue
		[ "$raw" -gt 1000 ] && raw=$((raw / 1000))
		[ "$raw" -gt -100 ] && [ "$raw" -lt 200 ] || continue
		seen="$seen$name "
		printf '%s=%s\n' "$name" "$raw"
	done

	tg_read_mtwifi
}

# The proprietary MediaTek driver (mt_wifi) registers no hwmon sensor, its
# temperature is only reachable through a private ioctl. Same query as
# ImmortalWrt's autocore, and like it only for interfaces that are up.
# Numbered by position in the list, so a radio that is down leaves a gap
# instead of renaming the other one.
tg_read_mtwifi() {
	local ifname flags raw n=-1
	tg_have iwpriv || return 0
	for ifname in ra0 rax0 rai0 ray0 rae0 raz0; do
		n=$((n + 1))
		[ -r "$NET_ROOT/$ifname/flags" ] || continue
		flags=$(cat "$NET_ROOT/$ifname/flags" 2>/dev/null)
		case "$flags" in 0x[0-9a-fA-F]*) ;; *) continue ;; esac
		[ $((flags & 1)) -eq 1 ] || continue
		raw=$(tg_mtwifi_temp "$ifname")
		[ -n "$raw" ] || continue
		printf 'mtwifi_phy%s=%s\n' "$n" "$raw"
	done
}

tg_mtwifi_temp() { # $1 interface
	local out v
	if tg_have timeout; then
		out=$(timeout 3 iwpriv "$1" stat 2>/dev/null)
	else
		out=$(iwpriv "$1" stat 2>/dev/null)
	fi
	v=$(printf '%s\n' "$out" | sed -n 's/^CurrentTemperature *= *\(-\{0,1\}[0-9]\{1,3\}\) *$/\1/p' | head -n 1)
	v=$(tg_int "$v")
	[ -n "$v" ] && [ "$v" -gt -100 ] && [ "$v" -lt 200 ] && echo "$v"
	return 0
}

# ---- stage actions ---------------------------------------------------------

# CFUN=4 is flight mode and CFUN=0 minimum function, neither a reset: a reset
# while the PCIe link is up can wedge the host port on some boards.
tg_action_modem_radio_off() { tg_modem_cfun_set "${MODEM_RADIO_OFF_AT#AT+CFUN=}"; }
tg_action_modem_radio_on() { tg_modem_cfun_set 1; }

# Success is what the modem reports afterwards, not what the command returned:
# a collision on the port swallows the command and answers nothing. So the
# command is sent again on every attempt.
tg_modem_cfun_set() { # $1 level
	local port got="" i=0
	port=$(tg_modem_port)
	[ -n "$port" ] || return 1
	while [ "$i" -lt 3 ]; do
		[ "$i" -gt 0 ] && sleep "$CFUN_SETTLE"
		tg_at "$port" "AT+CFUN=$1" >/dev/null 2>&1
		got=$(tg_at "$port" 'AT+CFUN?' | tr -d '\r' | sed -n 's/^+CFUN: *\([0-9]\).*/\1/p' | head -n1)
		[ "$got" = "$1" ] && return 0
		i=$((i + 1))
	done
	tg_log "modem reports CFUN ${got:-nothing} after AT+CFUN=$1" crit
	return 1
}

# UCI section names only: the name ends up as an ifdown argument and in a ubus
# object path.
tg_iface_name_ok() {
	case "$1" in
		''|-*|*[!A-Za-z0-9_]*) return 1 ;;
	esac
}

# "true" or "false" as netifd reports it, empty for an interface it does not know.
tg_iface_up_state() {
	timeout "$UBUS_TIMEOUT" ubus call "network.interface.$1" status 2>/dev/null \
		| jsonfilter -e '@.up' 2>/dev/null
}

tg_action_interface_down() { tg_iface_set "${ACTION_INTERFACE:-$UPLINK_INTERFACE}" false; }
tg_action_interface_up() { tg_iface_set "${ACTION_INTERFACE:-$UPLINK_INTERFACE}" true; }

# ifdown and ifup return before netifd has acted, so wait for its report.
tg_iface_set() { # $1 interface, $2 true or false
	local i=0 got=""
	if ! tg_iface_name_ok "$1"; then
		tg_log "interface action has no usable interface, set action_interface or uplink_interface" warning
		return 1
	fi
	tg_have ifdown || return 1
	if [ "$2" = false ]; then
		timeout "$CMD_TIMEOUT" ifdown "$1" >/dev/null 2>&1
	else
		timeout "$CMD_TIMEOUT" ifup "$1" >/dev/null 2>&1
	fi
	while [ "$i" -lt 3 ]; do
		[ "$i" -gt 0 ] && sleep "$CFUN_SETTLE"
		got=$(tg_iface_up_state "$1")
		[ "$got" = "$2" ] && return 0
		i=$((i + 1))
	done
	tg_log "interface $1 reports up=${got:-unknown} after if$([ "$2" = false ] && echo down || echo up)" crit
	return 1
}

tg_action_wifi_off() { tg_wifi_set down; }
tg_action_wifi_on()  { tg_wifi_set up; }

# netifd's view of the radios that are not disabled, as "<radios> <up>",
# nothing when it does not answer. One filter for both counts, so they come
# from the same radios. Written as !(=true), because != does not match a radio
# without a "disabled" key at all.
tg_wifi_radios() {
	local json v radios=0 up=0
	json=$(timeout "$UBUS_TIMEOUT" ubus call network.wireless status 2>/dev/null) || return 0
	[ -n "$json" ] || return 0
	for v in $(printf '%s\n' "$json" | jsonfilter -e '@[!(@.disabled=true)].up' 2>/dev/null); do
		radios=$((radios + 1))
		[ "$v" = true ] && up=$((up + 1))
	done
	echo "$radios $up"
}

# Like the modem, the command goes out again on every attempt, and success is
# what netifd reports afterwards. Starting hostapd per radio takes longer than
# a modem answers, hence its own settle time and more attempts.
tg_wifi_set() { # $1 down or up
	local i=0 state radios="" up=""
	if ! tg_have wifi; then
		tg_log "no wifi command, cannot switch Wi-Fi $1" warning
		return 1
	fi
	while [ "$i" -lt "$WIFI_TRIES" ]; do
		timeout "$CMD_TIMEOUT" wifi "$1" >/dev/null 2>&1
		[ "$WIFI_SETTLE" -gt 0 ] && sleep "$WIFI_SETTLE"
		state=$(tg_wifi_radios)
		if [ -n "$state" ]; then
			radios=${state%% *}; up=${state#* }
			# Nothing to switch off is not a success: the stage would claim an
			# effect it never had. Nothing to bring back is fine, a reset must
			# not fail on it.
			if [ "$radios" -eq 0 ]; then
				[ "$1" = up ] && return 0
				tg_log "netifd manages no Wi-Fi radio, wifi_off switched nothing off" crit
				return 1
			fi
			[ "$1" = down ] && [ "$up" -eq 0 ] && return 0
			[ "$1" = up ] && [ "$up" -ge "$radios" ] && return 0
		fi
		i=$((i + 1))
	done
	if [ -z "$state" ]; then
		tg_log "netifd reports no Wi-Fi status after wifi $1" crit
	else
		tg_log "Wi-Fi reports $up of $radios radio(s) up after wifi $1" crit
	fi
	return 1
}

# ---- uplink ----------------------------------------------------------------

# l3 device of the modem interface, so notifications can tell "there is another
# way out" from "the only way out is the thing we are about to switch off".
tg_modem_l3dev() {
	[ -n "$UPLINK_INTERFACE" ] || return 0
	timeout "$UBUS_TIMEOUT" ubus call "network.interface.$UPLINK_INTERFACE" status 2>/dev/null \
		| jsonfilter -e '@.l3_device' 2>/dev/null
}

tg_default_devs() {
	tg_have ip || return 0
	{ ip -4 route show default; ip -6 route show default; } 2>/dev/null \
		| sed -n 's/.* dev \([^ ]*\).*/\1/p'
}

# 0 = there is a default route that does not run through the modem.
# Without ip nothing can tell whether a route exists, and a message that waits
# for one nobody can see is never sent. Unknown therefore means send now.
tg_uplink_unknown() {
	tg_have ip && return 1
	[ "$IP_TOLD" = 1 ] ||
		tg_cfg_log "no ip command, cannot tell whether another uplink exists, sending at once"
	[ "$DAEMON" = 1 ] && IP_TOLD=1
	return 0
}

tg_alt_uplink() {
	local md dev
	tg_uplink_unknown && return 0
	md=$(tg_modem_l3dev)
	for dev in $(tg_default_devs); do
		[ -n "$md" ] && [ "$dev" = "$md" ] && continue
		return 0
	done
	return 1
}

tg_any_uplink() { tg_uplink_unknown || [ -n "$(tg_default_devs)" ]; }
