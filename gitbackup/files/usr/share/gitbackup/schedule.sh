# shellcheck shell=sh
#
# gitbackup -- schedule: gb_cron_valid, gb_preset_expr, gb_cron_apply. Needs
# lib.sh and device.sh.

# gb_preset_expr <preset> <device> -- time derived from a hash of <device>:
# a fleet does not hit the remote at once, re-saving does not reshuffle.
# sha256sum: busybox has no cksum; "0x": ash has no 16#N arithmetic.
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

# _gb_field_valid <field-expr> <min> <max> -- bounds use `test`, never $(( )):
# a leading zero would read as octal there.
_gb_field_valid() {
	_gb_fv_expr="$1"
	_gb_fv_min="$2"
	_gb_fv_max="$3"

	# IFS splitting silently drops a trailing empty field: "5," would pass.
	case "$_gb_fv_expr" in
		,*|*,|*,,*) return 1 ;;
	esac

	_gb_fv_saved_ifs="$IFS"
	IFS=','
	set -f
	# shellcheck disable=SC2086  # splitting on IFS=',' is the point
	set -- $_gb_fv_expr
	set +f
	IFS="$_gb_fv_saved_ifs"
	[ "$#" -gt 0 ] || return 1

	for _gb_fv_term in "$@"; do
		[ -n "$_gb_fv_term" ] || return 1

		_gb_fv_range="$_gb_fv_term"
		case "$_gb_fv_term" in
			*/*)
				_gb_fv_range="${_gb_fv_term%%/*}"
				_gb_fv_step="${_gb_fv_term#*/}"
				case "$_gb_fv_step" in ''|*[!0-9]*) return 1 ;; esac
				# Step 0 or beyond the span parses in busybox crond but fires
				# only on the lowest value.
				[ "$_gb_fv_step" -ge 1 ] && [ "$_gb_fv_step" -le "$_gb_fv_max" ] || return 1
				;;
		esac

		case "$_gb_fv_range" in
			'*') ;;
			*-*)
				_gb_fv_lo="${_gb_fv_range%%-*}"
				_gb_fv_hi="${_gb_fv_range#*-}"
				case "$_gb_fv_lo" in ''|*[!0-9]*) return 1 ;; esac
				case "$_gb_fv_hi" in ''|*[!0-9]*) return 1 ;; esac
				[ "$_gb_fv_lo" -ge "$_gb_fv_min" ] && [ "$_gb_fv_lo" -le "$_gb_fv_max" ] || return 1
				[ "$_gb_fv_hi" -ge "$_gb_fv_min" ] && [ "$_gb_fv_hi" -le "$_gb_fv_max" ] || return 1
				# Reversed range parses in busybox but yields a wrong bitmap.
				[ "$_gb_fv_lo" -le "$_gb_fv_hi" ] || return 1
				;;
			*)
				case "$_gb_fv_range" in ''|*[!0-9]*) return 1 ;; esac
				[ "$_gb_fv_range" -ge "$_gb_fv_min" ] && [ "$_gb_fv_range" -le "$_gb_fv_max" ] || return 1
				;;
		esac
	done
}

# gb_cron_valid <expr> -- 1 with a reason on stderr. busybox crond has no
# @-macros: "@daily ..." errors or, under six tokens, is dropped silently.
gb_cron_valid() {
	_gb_cv_expr="${1-}"
	case "$_gb_cv_expr" in
		'@'*)
			printf 'busybox crond does not understand "%s" (no @-macro support on 25.12); use an explicit expression, e.g. "0 3 * * *" for once a day at 03:00\n' \
				"$_gb_cv_expr" >&2
			return 1
			;;
	esac

	set -f
	# shellcheck disable=SC2086  # splitting on whitespace is the point
	set -- $_gb_cv_expr
	set +f
	if [ "$#" -ne 5 ]; then
		printf 'a cron expression needs exactly 5 fields (minute hour day-of-month month day-of-week), got %s in "%s"\n' \
			"$#" "$_gb_cv_expr" >&2
		return 1
	fi

	# busybox has no Sunday-as-7 alias.
	_gb_cv_bad=''
	_gb_field_valid "$1" 0 59 || _gb_cv_bad='minute'
	[ -n "$_gb_cv_bad" ] || { _gb_field_valid "$2" 0 23 || _gb_cv_bad='hour'; }
	[ -n "$_gb_cv_bad" ] || { _gb_field_valid "$3" 1 31 || _gb_cv_bad='day-of-month'; }
	[ -n "$_gb_cv_bad" ] || { _gb_field_valid "$4" 1 12 || _gb_cv_bad='month'; }
	[ -n "$_gb_cv_bad" ] || { _gb_field_valid "$5" 0 6 || _gb_cv_bad='day-of-week'; }
	if [ -n "$_gb_cv_bad" ]; then
		printf '%s field is not a valid value, range, step or list of them in "%s"\n' \
			"$_gb_cv_bad" "$_gb_cv_expr" >&2
		return 1
	fi
	return 0
}

# gb_cron_apply -- rewrites only the "# gitbackup"-marked line. schedule=off
# keeps the crontab file even if empty: cron's init script refuses to start
# on an empty crontabs directory, which would kill every other job.
gb_cron_apply() {
	_gb_ca_crontab="${GB_CRONTAB:-/etc/crontabs/root}"
	_gb_ca_sched=$(gb_uci_get gitbackup.main.schedule daily)
	_gb_ca_expr=''

	# No "gitbackup." substring in the temp name: a test grep would read it as
	# a UCI path. Sweeps leftovers from crashed runs.
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
