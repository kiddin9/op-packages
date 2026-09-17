# shellcheck shell=sh
#
# gitbackup -- schedule (spec "Расписание", R100/R101/R103-R107).
#
# Exposes gb_cron_valid, gb_preset_expr, gb_cron_apply and gb_cron_next.
# Every _gb_-prefixed helper is private, same convention as lib.sh. Sourced,
# never executed: nothing here runs at load time, so tests/run.sh can source
# it and call one function without a router underneath it. Assumes lib.sh
# (gb_uci_get, gb_log) and device.sh (gb_device_id) are already sourced,
# same as every other module in this directory.

# gb_preset_expr <preset> <device> -- hourly/daily/weekly, spec's table.
#
# The minute (and, for daily/weekly, the hour) is not fixed: it is folded
# out of a hash of <device> so that a fleet of routers all set to the same
# preset do not wake up in the same second and hit GitHub's API together
# (spec: "двадцать роутеров с daily... получат rate limit все разом").
# Deterministic on purpose, not `$RANDOM` -- re-saving the settings form
# must not reshuffle a router's own schedule.
#
# H is folded into 0-5 (spec's "ночное окно 0:00-5:59"), not the full
# 0-23, so a daily/weekly backup never lands in the middle of the day.
#
# The hash is sha256sum, not a literal "crc" tool: the base image ships no
# cksum(1) at all (`busybox cksum` -> "applet not found", measured on the
# 25.12.4 stand), while sha256sum is already there and already a DEPENDS
# collect.sh relies on. Any digest with a roughly uniform byte distribution
# is equally deterministic for this purpose. 8 hex characters -> 32 bits,
# read as decimal through the explicit "0x" arithmetic prefix -- ash's
# arithmetic does not support the ksh/bash "16#..." base-literal syntax
# (verified on the stand: `$((16#$h))` is an "arithmetic syntax error"),
# but the POSIX "0x..." form works on both ash and the bash/zsh /bin/sh this
# suite also runs under during development.
gb_preset_expr() {
	_gb_preset="$1"
	_gb_dev="$2"

	_gb_hash=$(printf '%s' "$_gb_dev" | sha256sum | cut -c1-8) || return 1
	case "$_gb_hash" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
	_gb_n=$(( 0x$_gb_hash ))
	_gb_m=$(( _gb_n % 60 ))
	_gb_h=$(( _gb_n % 6 ))
	_gb_d=$(( _gb_n % 7 ))

	case "$_gb_preset" in
		hourly) printf '%s * * * *\n' "$_gb_m" ;;
		daily)  printf '%s %s * * *\n' "$_gb_m" "$_gb_h" ;;
		weekly) printf '%s %s * * %s\n' "$_gb_m" "$_gb_h" "$_gb_d" ;;
		*) return 1 ;;
	esac
}

# _gb_strip_lead0 <digits> -- private. Prints <digits> with every leading
# zero removed, down to a single "0" for an all-zero input ("007" -> "7",
# "00" -> "0", "46" -> "46").
#
# Exists only so the rest of this file can safely hand a cron field's
# leading-zero-tolerant value (e.g. the hour "08") to `$(( ))`: busybox
# ash's arithmetic reads a leading zero as an octal prefix ("08" is then an
# invalid octal digit and the whole expression errors out), and -- verified
# on the stand, where it produced the exact same "arithmetic syntax
# error" -- does not implement POSIX's "10#N" decimal-radix prefix as a
# workaround either, unlike the bash/zsh /bin/sh this suite also runs
# under during development. A plain glob-based strip has no radix opinion
# at all.
_gb_strip_lead0() {
	_gb_s0="$1"
	while true; do
		case "$_gb_s0" in
			0?*) _gb_s0="${_gb_s0#0}" ;;
			*) break ;;
		esac
	done
	printf '%s' "$_gb_s0"
}

# _gb_field_values <field-expr> <min> <max> -- private.
#
# Expands one cron field into its sorted, deduplicated, space-separated list
# of matching integers, or prints nothing and returns 1 if the field is not
# a comma-separated list of "*", "*/N", "A", "A-B" or "A-B/N" terms, or any
# number in it falls outside [<min>,<max>]. This is the one engine behind
# both gb_cron_valid (a field is valid exactly when this expands it without
# error) and gb_cron_next (which needs the actual expansion to search for
# the next match).
#
# Bounds checking always goes through `[ -ge ]`/`[ -le ]` (POSIX `test`),
# never `$(( ))`: a leading-zero field value like the hour "08" is a normal
# decimal 8 to `test`, but `$(( 08 ))` is an invalid octal literal and
# busybox ash's arithmetic errors out on it outright (verified on the
# stand: `v=08; echo $((v))` exits nonzero). Arithmetic is used only once a
# value is already known to be a plain decimal string, and only after
# _gb_strip_lead0 below has removed any leading zero -- ash's arithmetic
# does not support the POSIX "10#N" decimal-radix prefix either (also
# verified on the stand: `$((10#08))` is the same "arithmetic syntax
# error", not the workaround it looks like on a bash/zsh /bin/sh).
#
# "*/N" starts from <min>, matching busybox for every field this package's
# presets or a hand-written cron_expr actually vary (minute, hour, month,
# weekday all have min 0 or 1 in a way that lines up with busybox's own
# internal 0-based bitmap). The one field where this is a deliberate,
# disclosed simplification is day-of-month: busybox's own bitmap for that
# field reserves index 0 for a "day zero" that can never occur and starts
# stepping from THAT, so its real "*/10" fires on 10/20/30 (index 0 is
# inert), not the 1/11/21/31 this function returns starting from min=1 --
# measured on the stand by running `busybox crond -f -d0` against fixture
# crontabs and reading its own field-parse debug dump. Nothing in this
# package's presets or acceptance criteria exercises a stepped day-of-month
# field; gb_cron_next's answer for a hand-written one could come out one
# step earlier than the real crond fires. Documented rather than silently
# assumed away.
_gb_field_values() {
	_gb_fv_expr="$1"
	_gb_fv_min="$2"
	_gb_fv_max="$3"
	_gb_fv_out=''

	# A leading/trailing/doubled comma has to be rejected before the split
	# below, not after it: shell field-splitting on IFS="," drops a
	# *trailing* delimiter instead of yielding a trailing empty field (the
	# same expansion that turns "a," into the one field "a", not "a" and
	# ""), so "5," would otherwise sail through as the single term "5" --
	# measured by a fixture in tests/fixtures/cron.tsv that stayed green
	# for the wrong reason until this guard was added. A *leading* comma
	# does still produce a real empty first field and would be caught
	# below regardless, but checking both shapes here up front is one rule
	# instead of two.
	case "$_gb_fv_expr" in
		,*|*,|*,,*) return 1 ;;
	esac

	_gb_fv_saved_ifs="$IFS"
	IFS=','
	# -f (noglob) around the split is not optional: an unquoted "*" or
	# "*/5" term is exactly the input this field parses, and without it the
	# shell pathname-expands "*" against the current directory instead of
	# leaving it as a literal word -- caught by a test run from the repo
	# root, where "*" silently became a couple dozen filenames.
	set -f
	# shellcheck disable=SC2086  # splitting on IFS=',' is the point
	set -- $_gb_fv_expr
	set +f
	IFS="$_gb_fv_saved_ifs"
	[ "$#" -gt 0 ] || return 1

	for _gb_fv_term in "$@"; do
		# An empty term is a bare/leading/trailing/doubled comma ("," ",,"),
		# never a valid field on its own.
		[ -n "$_gb_fv_term" ] || return 1

		_gb_fv_step=1
		_gb_fv_range="$_gb_fv_term"
		case "$_gb_fv_term" in
			*/*)
				_gb_fv_range="${_gb_fv_term%%/*}"
				_gb_fv_step="${_gb_fv_term#*/}"
				case "$_gb_fv_step" in ''|*[!0-9]*) return 1 ;; esac
				# A step of 0, or one bigger than the field's own span,
				# parses without complaint in real busybox crond but
				# silently degenerates to firing on the field's single
				# lowest value forever -- measured on the stand
				# (`*/0`/`*/61` in a minute field both produce a bitmap
				# with only minute 0 set, no parse error at all). That is
				# exactly the kind of "looks configured, never really
				# runs" trap R101's live validation exists to catch
				# before it reaches a crontab.
				[ "$_gb_fv_step" -ge 1 ] && [ "$_gb_fv_step" -le "$_gb_fv_max" ] || return 1
				;;
		esac

		case "$_gb_fv_range" in
			'*')
				_gb_fv_lo="$_gb_fv_min"
				_gb_fv_hi="$_gb_fv_max"
				;;
			*-*)
				_gb_fv_lo="${_gb_fv_range%%-*}"
				_gb_fv_hi="${_gb_fv_range#*-}"
				case "$_gb_fv_lo" in ''|*[!0-9]*) return 1 ;; esac
				case "$_gb_fv_hi" in ''|*[!0-9]*) return 1 ;; esac
				[ "$_gb_fv_lo" -ge "$_gb_fv_min" ] && [ "$_gb_fv_lo" -le "$_gb_fv_max" ] || return 1
				[ "$_gb_fv_hi" -ge "$_gb_fv_min" ] && [ "$_gb_fv_hi" -le "$_gb_fv_max" ] || return 1
				# A reversed range ("5-2") parses in real busybox crond
				# too, but produces a bitmap that is wrong in a way no
				# user intended (measured on the stand) rather than an
				# error -- rejected here instead of reproduced.
				[ "$_gb_fv_lo" -le "$_gb_fv_hi" ] || return 1
				;;
			*)
				case "$_gb_fv_range" in ''|*[!0-9]*) return 1 ;; esac
				[ "$_gb_fv_range" -ge "$_gb_fv_min" ] && [ "$_gb_fv_range" -le "$_gb_fv_max" ] || return 1
				_gb_fv_lo="$_gb_fv_range"
				_gb_fv_hi="$_gb_fv_range"
				;;
		esac

		# A plain "A/N" (no "-" range) is real, accepted busybox syntax --
		# measured on the stand -- but the step is a no-op: it fires on A
		# alone, never repeating. The loop below already reproduces that
		# with no special case, because it starts and ends at the same
		# value: one iteration, done.
		_gb_fv_v=$(_gb_strip_lead0 "$_gb_fv_lo")
		_gb_fv_v=$(( _gb_fv_v ))
		_gb_fv_hi_n=$(_gb_strip_lead0 "$_gb_fv_hi")
		_gb_fv_hi_n=$(( _gb_fv_hi_n ))
		_gb_fv_step_n=$(_gb_strip_lead0 "$_gb_fv_step")
		_gb_fv_step_n=$(( _gb_fv_step_n ))
		while [ "$_gb_fv_v" -le "$_gb_fv_hi_n" ]; do
			_gb_fv_out="$_gb_fv_out $_gb_fv_v"
			_gb_fv_v=$((_gb_fv_v + _gb_fv_step_n))
		done
	done

	printf '%s' "$_gb_fv_out" | tr -s ' ' '\n' | sed '/^$/d' | sort -n -u | tr '\n' ' '
	printf '\n'
}

# gb_cron_valid <expr> -- 0 if busybox crond on 25.12 can actually run
# <expr>, 1 otherwise, with a reason on stderr.
#
# Rejects the "@daily"/"@hourly"/"@reboot" family outright and by name:
# `CONFIG_FEATURE_CROND_SPECIAL_TIMES=n` on the 25.12.4 build means the
# binary has no macro table at all, so "@daily aa bb cc dd ee ff" gives a
# loud "parse error at @daily" -- but a *short* macro line like the classic
# "@daily /bin/echo A" (fewer than six whitespace-separated tokens) is
# dropped by crond with no error and no run, ever (both measured on the
# stand). A validator that let @-macros through on the strength of the
# first, louder failure mode would still ship the second, silent one.
gb_cron_valid() {
	_gb_cv_expr="${1-}"
	case "$_gb_cv_expr" in
		'@'*)
			printf 'busybox crond does not understand "%s" (no @-macro support on 25.12); use an explicit expression, e.g. "0 3 * * *" for once a day at 03:00\n' \
				"$_gb_cv_expr" >&2
			return 1
			;;
	esac

	# -f (noglob): see _gb_field_values -- a field is often a literal "*"
	# and must not be pathname-expanded by this split.
	set -f
	# shellcheck disable=SC2086  # splitting on whitespace is the point
	set -- $_gb_cv_expr
	set +f
	if [ "$#" -ne 5 ]; then
		printf 'a cron expression needs exactly 5 fields (minute hour day-of-month month day-of-week), got %s in "%s"\n' \
			"$#" "$_gb_cv_expr" >&2
		return 1
	fi

	# Field bounds: minute 0-59, hour 0-23, day-of-month 1-31, month 1-12,
	# day-of-week 0-6 -- the last confirmed on the stand by the fact that
	# "0 3 * * 7" is itself a parse error (no Sunday-as-7 alias on this
	# busybox), while 0 and 6 both parse. Five explicit checks rather than a
	# table-driven loop: POSIX sh has no arrays, and indexing positional
	# parameters by an arithmetic offset would need `eval` for no real gain
	# over just naming each field once.
	_gb_cv_bad=''
	_gb_field_values "$1" 0 59  >/dev/null || _gb_cv_bad='minute'
	[ -n "$_gb_cv_bad" ] || { _gb_field_values "$2" 0 23  >/dev/null || _gb_cv_bad='hour'; }
	[ -n "$_gb_cv_bad" ] || { _gb_field_values "$3" 1 31  >/dev/null || _gb_cv_bad='day-of-month'; }
	[ -n "$_gb_cv_bad" ] || { _gb_field_values "$4" 1 12  >/dev/null || _gb_cv_bad='month'; }
	[ -n "$_gb_cv_bad" ] || { _gb_field_values "$5" 0 6   >/dev/null || _gb_cv_bad='day-of-week'; }
	if [ -n "$_gb_cv_bad" ]; then
		printf '%s field is not a valid value, range, step or list of them in "%s"\n' \
			"$_gb_cv_bad" "$_gb_cv_expr" >&2
		return 1
	fi
	return 0
}

# gb_cron_next <expr> -- the next UTC "YYYY-MM-DD HH:MM" <expr> fires at or
# after now, or nothing (exit 1) if <expr> is invalid.
#
# Searches whole days forward from today (up to ~4 years, comfortably past
# any Feb-29-only expression), because every field this function has to
# reason about -- month, day-of-month, day-of-week -- only ever changes at a
# day boundary; only the final hour/minute search happens inside the
# matching day. All arithmetic is on Unix time in UTC, which never has a day
# shorter or longer than 86400 seconds (no DST to account for), so a whole
# day is added by adding exactly 86400 -- no calendar library, no date
# string round-trip, just `date -u -d @<epoch>` to read back the
# month/day-of-month/weekday for a given instant (the "@seconds_since_1970"
# form busybox `date --help` documents as recognized on the stand).
gb_cron_next() {
	_gb_cn_expr="$1"
	gb_cron_valid "$_gb_cn_expr" >/dev/null 2>&1 || return 1

	# -f (noglob): see _gb_field_values -- a field is often a literal "*"
	# and must not be pathname-expanded by this split.
	set -f
	# shellcheck disable=SC2086
	set -- $_gb_cn_expr
	set +f
	_gb_cn_minutes=$(_gb_field_values "$1" 0 59) || return 1
	_gb_cn_hours=$(_gb_field_values "$2" 0 23) || return 1
	_gb_cn_doms=$(_gb_field_values "$3" 1 31) || return 1
	_gb_cn_months=$(_gb_field_values "$4" 1 12) || return 1
	_gb_cn_dows=$(_gb_field_values "$5" 0 6) || return 1

	# Standard cron day-selection rule: when BOTH day-of-month and
	# day-of-week are restricted (neither is "*"), a day qualifies if it
	# matches EITHER one (OR); when only one is restricted, that one alone
	# decides.
	_gb_cn_dom_star=0
	case "$3" in '*') _gb_cn_dom_star=1 ;; esac
	_gb_cn_dow_star=0
	case "$5" in '*') _gb_cn_dow_star=1 ;; esac

	_gb_cn_now=$(date -u +%s) || return 1
	_gb_cn_midnight=$(( _gb_cn_now - (_gb_cn_now % 86400) ))

	_gb_cn_day=0
	while [ "$_gb_cn_day" -le 1466 ]; do
		_gb_cn_day_epoch=$(( _gb_cn_midnight + _gb_cn_day * 86400 ))
		_gb_cn_ymw=$(date -u -d "@$_gb_cn_day_epoch" '+%m %d %w') || return 1
		_gb_cn_mo=${_gb_cn_ymw%% *}
		_gb_cn_rest=${_gb_cn_ymw#* }
		_gb_cn_dm=${_gb_cn_rest%% *}
		_gb_cn_wd=${_gb_cn_rest#* }
		# Same _gb_strip_lead0 as _gb_field_values above, needed here
		# because `date`'s own %m/%d output is zero-padded.
		_gb_cn_mo=$(_gb_strip_lead0 "$_gb_cn_mo")
		_gb_cn_mo=$(( _gb_cn_mo ))
		_gb_cn_dm=$(_gb_strip_lead0 "$_gb_cn_dm")
		_gb_cn_dm=$(( _gb_cn_dm ))
		_gb_cn_wd=$(_gb_strip_lead0 "$_gb_cn_wd")
		_gb_cn_wd=$(( _gb_cn_wd ))

		case " $_gb_cn_months " in
			*" $_gb_cn_mo "*) _gb_cn_month_ok=1 ;;
			*) _gb_cn_month_ok=0 ;;
		esac

		if [ "$_gb_cn_month_ok" -eq 1 ]; then
			_gb_cn_dom_ok=0
			case " $_gb_cn_doms " in *" $_gb_cn_dm "*) _gb_cn_dom_ok=1 ;; esac
			_gb_cn_dow_ok=0
			case " $_gb_cn_dows " in *" $_gb_cn_wd "*) _gb_cn_dow_ok=1 ;; esac

			if [ "$_gb_cn_dom_star" -eq 1 ] && [ "$_gb_cn_dow_star" -eq 1 ]; then
				_gb_cn_day_ok=1
			elif [ "$_gb_cn_dom_star" -eq 1 ]; then
				_gb_cn_day_ok="$_gb_cn_dow_ok"
			elif [ "$_gb_cn_dow_star" -eq 1 ]; then
				_gb_cn_day_ok="$_gb_cn_dom_ok"
			elif [ "$_gb_cn_dom_ok" -eq 1 ] || [ "$_gb_cn_dow_ok" -eq 1 ]; then
				_gb_cn_day_ok=1
			else
				_gb_cn_day_ok=0
			fi

			if [ "$_gb_cn_day_ok" -eq 1 ]; then
				for _gb_cn_h in $_gb_cn_hours; do
					for _gb_cn_m in $_gb_cn_minutes; do
						_gb_cn_cand=$(( _gb_cn_day_epoch + _gb_cn_h * 3600 + _gb_cn_m * 60 ))
						if [ "$_gb_cn_cand" -ge "$_gb_cn_now" ]; then
							date -u -d "@$_gb_cn_cand" '+%Y-%m-%d %H:%M'
							return 0
						fi
					done
				done
			fi
		fi

		_gb_cn_day=$((_gb_cn_day + 1))
	done
	return 1
}

# gb_cron_apply -- reads gitbackup.main.schedule (and cron_expr/device_id as
# needed), (re)writes the single "# gitbackup"-marked line in the crontab,
# and makes it live.
#
# Idempotent by construction: every existing line ending in "# gitbackup" is
# dropped before the (at most one) new one is appended, so applying twice in
# a row -- two saves of the settings form, a reboot re-running this from
# start_service, whatever -- leaves exactly one line, never a growing pile,
# and never touches a line that is not ours (spec: OpenWrt's own crontab
# ships with unrelated vnstat/adblock entries out of the box; confirmed
# present, untouched by this, on the owlab stand).
#
# schedule=off removes that line but leaves the file itself in place, even
# at zero length: `/etc/init.d/cron`'s start_service begins with
# `[ -z "$(ls /etc/crontabs/)" ] && return 1` -- crond refuses to start only
# when the *directory* is empty, and a zero-byte file already satisfies
# that (spec "Проверенные факты", confirmed unchanged on this stand).
# Deleting the file on schedule=off would silently take crond down with it
# for every *other* cron job on the router, which is not this package's
# call to make.
#
# GB_CRONTAB overrides the crontab path so tests/run.sh can point this at a
# plain temp file; the router never sets it. The final
# `/etc/init.d/cron enable && /etc/init.d/cron restart` is guarded by
# `[ -x /etc/init.d/cron ]` for the same reason -- there is no such script
# on a development host -- and is the one piece of this function verified
# only on the owlab stand (via `ps`), never in tests/run.sh, per this
# ticket's own acceptance criteria.
gb_cron_apply() {
	_gb_ca_crontab="${GB_CRONTAB:-/etc/crontabs/root}"
	_gb_ca_sched=$(gb_uci_get gitbackup.main.schedule daily)
	_gb_ca_expr=''

	# Deliberately not named with a "gitbackup" + "." substring next to
	# each other: t_config_sections_match_code's own grep reads any
	# "gitbackup.<word>." it finds anywhere in this directory as a UCI
	# section reference, and a suffix like that would fail it outright
	# for naming a temp file, not a config path (hit during development).
	#
	# A stray one of these from some earlier crashed run (this file's own
	# development left several on the owlab stand before a bug in
	# _gb_field_values was fixed) is swept up here rather than left to
	# accumulate one file per bad run forever -- the crontab directory has
	# no other owner watching it for that.
	rm -f "${_gb_ca_crontab}".newtmp.* 2>/dev/null
	_gb_ca_tmp="${_gb_ca_crontab}.newtmp.$$"
	if [ -f "$_gb_ca_crontab" ]; then
		grep -v '# gitbackup$' "$_gb_ca_crontab" >"$_gb_ca_tmp" 2>/dev/null
	else
		: >"$_gb_ca_tmp"
	fi

	case "$_gb_ca_sched" in
		off) ;;
		hourly|weekly|daily)
			if _gb_ca_dev=$(gb_device_id 2>/dev/null); then
				_gb_ca_expr=$(gb_preset_expr "$_gb_ca_sched" "$_gb_ca_dev") || _gb_ca_expr=''
			fi
			;;
		cron)
			_gb_ca_expr=$(gb_uci_get gitbackup.main.cron_expr)
			;;
		*)
			gb_log err "gitbackup.main.schedule: unknown value '$_gb_ca_sched', crontab left without a gitbackup entry"
			;;
	esac

	if [ "$_gb_ca_sched" != off ]; then
		if [ -n "$_gb_ca_expr" ] && gb_cron_valid "$_gb_ca_expr" 2>/dev/null; then
			printf '%s /usr/sbin/gitbackup run >/dev/null 2>&1 # gitbackup\n' "$_gb_ca_expr" >>"$_gb_ca_tmp"
		else
			gb_log err "gitbackup: schedule '$_gb_ca_sched' did not produce a cron expression busybox crond can run, crontab left without a gitbackup entry"
		fi
	fi

	mv "$_gb_ca_tmp" "$_gb_ca_crontab"

	if [ -x /etc/init.d/cron ]; then
		/etc/init.d/cron enable
		/etc/init.d/cron restart
	fi
}
