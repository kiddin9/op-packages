#!/bin/sh
# shellcheck shell=sh

ss_case_lock_owner_and_contention() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	# shellcheck disable=SC1090
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/locking.sh"
	LOCK="$TMP/collector.lock"
	ss_lock_try "$LOCK"
	[ "$(cat "$LOCK/pid")" = "$$" ]
	# Different process may not acquire the lock or remove its owner.
	! sh -c '. "$1"; ss_lock_try "$2"' sh "$SS_SPEC_ROOT/files/usr/lib/safeshield/locking.sh" "$LOCK"
	! sh -c '. "$1"; ss_lock_release "$2"' sh "$SS_SPEC_ROOT/files/usr/lib/safeshield/locking.sh" "$LOCK"
	[ "$(cat "$LOCK/pid")" = "$$" ]
	ss_lock_release "$LOCK"
	[ ! -e "$LOCK" ]
	# Stale pid may be reclaimed by exactly one contender.
	mkdir "$LOCK"
	printf '99999999\n' >"$LOCK/pid"
	ss_lock_try "$LOCK"
	[ "$(cat "$LOCK/pid")" = "$$" ]
	ss_lock_release "$LOCK"
	# Do not seize a newly created lock before its pid has been populated.
	mkdir "$LOCK"
	! ss_lock_try "$LOCK"
	[ -d "$LOCK" ]
	rmdir "$LOCK"
	# An abandoned pid-less directory (including a crashed recovery guard)
	# becomes reclaimable after its initialization grace period.
	mkdir "$LOCK" "${LOCK}.reclaim"
	touch -t 202001010000 "$LOCK" "${LOCK}.reclaim"
	ss_lock_try "$LOCK"
	ss_lock_release "$LOCK"
)

ss_case_lock_parallel() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	LIB="$SS_SPEC_ROOT/files/usr/lib/safeshield/locking.sh"
	LOCK="$TMP/write.lock"
	RESULT="$TMP/results"
	for id in 1 2 3 4 5 6 7 8; do
		sh -c '
			. "$1"
			ss_lock_wait "$2" 15 || exit 1
			printf "%s\n" "$3" >>"$4"
			sleep 0.05
			ss_lock_release "$2"
		' sh "$LIB" "$LOCK" "$id" "$RESULT" &
	done
	wait
	[ "$(wc -l <"$RESULT")" -eq 8 ]
	[ ! -e "$LOCK" ]
	[ ! -e "${LOCK}.reclaim" ]
)

ss_case_status_write_serialization() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	LIB="$SS_SPEC_ROOT/files/usr/lib/safeshield/locking.sh"
	STATUS="$SS_SPEC_ROOT/files/usr/lib/safeshield/status.sh"
	# Test the real shell writer with a slow stand-in for the ucode serializer.
	# A serializer must observe all previously committed updates under the same lock.
	cat >"$TMP/writer.sh" <<'EOF_WRITER'
#!/bin/sh
. "$1"
. "$2"
RUNNING_STATUS_FILE="$3"
RUNNING_STATUS_LOCK="$4"
json_lock_open() { ss_lock_wait "$RUNNING_STATUS_LOCK" 10; }
json_lock_close() { ss_lock_release "$RUNNING_STATUS_LOCK"; }
ss_status_exec() {
	key="$2"
	[ -f "$RUNNING_STATUS_FILE" ] && cat "$RUNNING_STATUS_FILE"
	sleep 0.05
	printf '%s\n' "$key"
}
ss_status_apply set "$5" unused
EOF_WRITER
	for n in 1 2 3 4 5 6 7 8; do
		sh "$TMP/writer.sh" "$LIB" "$STATUS" "$TMP/status.json" "$TMP/status.lock" "$n" &
	done
	wait
	[ "$(wc -l <"$TMP/status.json")" -eq 8 ]
	[ ! -e "$TMP/status.lock" ]
	[ ! -e "$TMP/status.json.tmp" ]
)

ss_case_status_write_failure() (
	set -eu
	TMP="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMP"' EXIT HUP INT TERM
	# shellcheck disable=SC1090
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/locking.sh"
	# shellcheck disable=SC1090
	. "$SS_SPEC_ROOT/files/usr/lib/safeshield/status.sh"
	RUNNING_STATUS_LOCK="$TMP/status.lock"
	RUNNING_STATUS_FILE="$TMP/status.json"
	json_lock_open() { ss_lock_wait "$RUNNING_STATUS_LOCK" 10; }
	json_lock_close() { ss_lock_release "$RUNNING_STATUS_LOCK"; }
	printf 'original\n' >"$RUNNING_STATUS_FILE"
	ss_status_exec() {
		printf 'partial\n'
		return 1
	}
	! ss_status_apply set key value
	[ "$(cat "$RUNNING_STATUS_FILE")" = 'original' ]
	[ ! -e "${RUNNING_STATUS_FILE}.tmp.$$" ]
	[ ! -e "$RUNNING_STATUS_LOCK" ]
)
