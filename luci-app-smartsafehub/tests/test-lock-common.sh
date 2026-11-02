#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
LIB="$ROOT_DIR/root/usr/lib/smartsafehub/common.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
. "$LIB"

# A live owner must preserve the existing BUSY/75 behavior of updater, firmware
# and activity-sync; a foreign process must never remove a live owner's lock.
sleep 3 & live_pid=$!
mkdir "$TMP/live.lock"
printf '%s\n' "$live_pid" > "$TMP/live.lock/pid"
if ssh_lock_acquire "$TMP/live.lock" 3 0.01 sleep 1; then
 fail 'a live lock may not be stolen by a fast-fail contender'
fi
[ "$(cat "$TMP/live.lock/pid")" = "$live_pid" ] || fail 'live pid owner was replaced'
ssh_lock_release "$TMP/live.lock"
[ -d "$TMP/live.lock" ] || fail 'release by a non-owner removed a live lock'
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true

# A dead owner can be reclaimed, and only the acquiring process may release it.
mkdir "$TMP/stale.lock"
printf '%s\n' '99999999' > "$TMP/stale.lock/pid"
ssh_lock_acquire "$TMP/stale.lock" 3 0.01 sleep 1 || fail 'dead owner lock was not recovered'
[ "$(cat "$TMP/stale.lock/pid")" = "$$" ] || fail 'stale recovery did not publish this owner'
ssh_lock_release "$TMP/stale.lock"
[ ! -e "$TMP/stale.lock" ] || fail 'owner release did not remove the lock'

# An orphaned/invalid pid may be reclaimed only after a bounded grace period.
mkdir "$TMP/orphan.lock"
printf 'incomplete' > "$TMP/orphan.lock/pid"
ssh_lock_acquire "$TMP/orphan.lock" 3 0.01 sleep 1 || fail 'invalid owner marker could not be recovered'
ssh_lock_release "$TMP/orphan.lock"

# A fresh mkdir lock with no pid is INITIALIZING, not stale. Verify that a
# contender cannot take it over before the original writer publishes a pid.
mkdir "$TMP/initializing.lock"
(
 . "$LIB"
 ssh_lock_acquire "$TMP/initializing.lock" 30 0.02 sleep 1 || exit 1
 printf '%s\n' 'acquired' > "$TMP/initializing.result"
 ssh_lock_release "$TMP/initializing.lock"
) & initializing_pid=$!
sleep 0.10
[ ! -f "$TMP/initializing.lock/pid" ] || fail 'pid-less initializing lock was stolen prematurely'
[ ! -f "$TMP/initializing.result" ] || fail 'contender entered while owner was initializing'
rmdir "$TMP/initializing.lock"
wait "$initializing_pid" || fail 'contender did not acquire after owner released'
[ -f "$TMP/initializing.result" ] || fail 'contender was not executed'

# Separate processes must serialize read-modify-write operations (not just
# return success), including during the mkdir -> pid window.
printf '0\n' > "$TMP/counter"
pids=''
i=0
while [ "$i" -lt 4 ]; do
 i=$((i + 1))
 sh -c '
  . "$1"
  j=0
  while [ "$j" -lt 8 ]; do
   ssh_lock_acquire "$2/parallel.lock" 100 0.01 sleep 0 || exit 1
   value="$(cat "$2/counter")"
   printf "%s\n" "$((value + 1))" > "$2/counter.tmp.$$"
   mv "$2/counter.tmp.$$" "$2/counter"
   ssh_lock_release "$2/parallel.lock"
   j=$((j + 1))
  done
 ' sh "$LIB" "$TMP" &
 pids="$pids $!"
done
for pid in $pids; do wait "$pid" || fail 'one parallel contender failed'; done
[ "$(cat "$TMP/counter")" = 32 ] || fail 'parallel lock lost a critical section update'
[ ! -d "$TMP/parallel.lock" ] || fail 'lock directory remains after successful releases'

# UCI/JSON reading helpers use the caller's binaries and never require a file
# when optional metadata is absent.
cat > "$TMP/uci" <<'EOF_UCI'
#!/bin/sh
[ "$1" = '-q' ] && [ "$2" = get ] && [ "$3" = 'smartsafehub.test.enabled' ] || exit 1
printf '1\n'
EOF_UCI
cat > "$TMP/jsonfilter" <<'EOF_JSON'
#!/bin/sh
[ "$1" = '-i' ] && [ "$3" = '-e' ] && [ "$4" = '@.enabled' ] || exit 1
cat "$2"
EOF_JSON
chmod +x "$TMP/uci" "$TMP/jsonfilter"
[ "$(ssh_uci_get "$TMP/uci" smartsafehub.test.enabled)" = 1 ] || fail 'shared UCI reader returned unexpected data'
[ -z "$(ssh_json_value "$TMP/jsonfilter" "$TMP/missing" '@.enabled')" ] || fail 'missing JSON returned data'
printf 'yes\n' > "$TMP/input.json"
[ "$(ssh_json_value "$TMP/jsonfilter" "$TMP/input.json" '@.enabled' nonempty)" = yes ] || fail 'shared JSON reader returned unexpected data'
: > "$TMP/input.json"
[ -z "$(ssh_json_value "$TMP/jsonfilter" "$TMP/input.json" '@.enabled' nonempty)" ] || fail 'nonempty policy accepted empty JSON input'

printf 'PASS: shared lock handles initializing, live, orphaned, stale and parallel ownership safely\n'
