#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# The subscription updater has to actually run.
#
# update_subscriptions.uc used to read subscription_urls and filter_keywords
# off access_control.subscription, while the Loader puts them on access_control
# itself.  Both came back [], so `if (!isEmpty(subscription_urls)) call(main)`
# was false: the script exited 0 having logged nothing, and both the LuCI
# "Update nodes from subscriptions" button and the cron entry were silent
# no-ops.  Nothing caught it because no test had ever executed main() - the
# repository test calls apply_nodes() directly, and the model test asserted the
# *correct* shape, which only made the consumer's wrong read look fine.
#
# So this test drives the real script end to end and asserts the one property
# that was missing: given a configured subscription URL, the updater must
# attempt an update and say something about the outcome.  The URL points at a
# closed port, so the attempt fails fast and main() returns before the
# `/etc/init.d/homeproxy reload` at its end - the device is not touched.
#
# Usage: sh tests/ucode/test_subscription_updater_runs.sh <repo-root> [workdir]

set -u

ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)"
WORK="${2:-/tmp/hp-updater-test}"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	exit 2
fi

rm -rf "$WORK"
mkdir -p "$WORK/scripts" "$WORK/cfg" "$WORK/run"
cp -R "$ROOT/root/etc/homeproxy/scripts/." "$WORK/scripts/"

# Shadow `touch` so the test can see that a run refreshes its lock: the lock's
# mtime is the only thing that separates a live run from one a kill left
# behind, and the fetch loop (one wget per URL, ten seconds each) is where a
# run spends its time.  The stub records the call and forwards to the real one.
REAL_TOUCH="$(command -v touch)"
mkdir -p "$WORK/bin"
cat > "$WORK/bin/touch" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$WORK/touch.log"
exec "$REAL_TOUCH" "\$@"
EOF
chmod +x "$WORK/bin/touch"
PATH="$WORK/bin:$PATH"
export PATH

# Redirect the package's runtime dir into the sandbox so the test does not
# append to the device's live /var/run/homeproxy/homeproxy.log, and point the
# configuration directory at the sandbox.  The updater reads the config
# *inside* the lock now (A4), and it takes the directory from homeproxy.uc's
# UCICONFIG_DIR, so both rewrites land in this one file.
sed -e "s#^export const RUN_DIR = '/var/run/homeproxy';#export const RUN_DIR = '$WORK/run';#" \
    -e "s#^export const UCICONFIG_DIR = '/etc/config';#export const UCICONFIG_DIR = '$WORK/cfg';#" \
    "$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$WORK/scripts/homeproxy.uc"

# An unpatched copy would read - and on a real device write - the live
# /etc/config/homeproxy.  Fail here instead of silently testing the wrong file.
if ! grep -q "^export const UCICONFIG_DIR = '$WORK/cfg';" "$WORK/scripts/homeproxy.uc"; then
	echo "FAIL: could not point the updater at the sandbox config (anchor moved)"
	rm -rf "$WORK"
	exit 1
fi

# Point the updater's Loader at the sandbox config.  Portable sed: write to a
# temp file and rename, so this works under both busybox and BSD sed.
#
# The updater resolves the directory through homeproxy.uc's UCICONFIG_DIR (see
# the rewrite above), so this step only needs to confirm the staged copy is the
# one that was rewritten - it no longer contains a literal config path.
if ! grep -q "^export const UCICONFIG_DIR = '$WORK/cfg';" "$WORK/scripts/homeproxy.uc"; then
	echo "FAIL: the staged homeproxy.uc does not point at the sandbox config"
	rm -rf "$WORK"
	exit 1
fi

cat > "$WORK/cfg/homeproxy" <<-EOF
	config homeproxy 'config'
		option routing_mode 'proxy'
		option main_node 'nil'

	config homeproxy 'subscription'
		list subscription_url 'https://127.0.0.1:1/never'
		option filter_nodes 'disabled'
		option auto_update '0'
EOF

LOGFILE="$WORK/run/homeproxy.log"

FAILED=0
if ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" update_subscriptions.uc ) > "$WORK/stdout" 2>&1; then
	:
else
	echo "FAIL: update_subscriptions.uc exited non-zero"
	cat "$WORK/stdout"
	FAILED=1
fi

# The property under test: a configured URL means the updater must try.  Before
# the fix the log stayed empty because main() was never reached.
if [ -s "$LOGFILE" ]; then
	echo "PASS: the updater attempted an update and logged the outcome"
	sed 's/^/      /' "$LOGFILE"
else
	echo "FAIL: the updater logged nothing - main() was not reached, so the"
	echo "      subscription URL was read from the wrong level again"
	FAILED=1
fi

# And the log must name the failure rather than claim success.
if grep -q "Successfully updated subscriptions" "$LOGFILE" 2>/dev/null; then
	echo "FAIL: the updater reported success against an unreachable subscription"
	FAILED=1
fi

# The run has to keep its own lock fresh for as long as it works: nothing
# refreshed the mtime while the fetch was in progress, so a run slower than
# LOCK_STALE could have its lock reclaimed as stale and then race the second
# run through the same read-modify-write.
if grep -q "update_subscriptions.lock" "$WORK/touch.log" 2>/dev/null; then
	echo "PASS: the updater refreshes its lock while it works"
else
	echo "FAIL: the lock's mtime is never refreshed - a run longer than the stale"
	echo "      window can have its lock broken underneath it"
	FAILED=1
fi

# --- the lock ------------------------------------------------------------
# The cron entry and the LuCI button can both start this script, and an update
# is a read-modify-write of the whole configuration, so two runs interleaving
# them is last-writer-wins. A fresh lock must make the second run stand down...
LOCKDIR="$WORK/run/update_subscriptions.lock"
rm -f "$LOGFILE"
mkdir -p "$LOCKDIR"

# A4: the lock is now taken *before* the configuration is read, so a run that
# stands down must not have touched the config at all - and in particular must
# not have written the recovery snapshot the failure path would restore.
cp "$WORK/cfg/homeproxy" "$WORK/cfg.before-standdown"

if ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" update_subscriptions.uc ) > "$WORK/stdout2" 2>&1; then
	:
else
	echo "FAIL: the updater exited non-zero while another run held the lock"
	FAILED=1
fi

if grep -q "already running" "$LOGFILE" 2>/dev/null; then
	echo "PASS: a held lock makes the updater stand down"
else
	echo "FAIL: the updater ignored an existing lock"
	sed 's/^/      /' "$LOGFILE"
	FAILED=1
fi

if cmp -s "$WORK/cfg.before-standdown" "$WORK/cfg/homeproxy"; then
	echo "PASS: a run that lost the lock left the configuration untouched"
else
	echo "FAIL: a run that lost the lock still rewrote the configuration"
	FAILED=1
fi

if [ -e "$WORK/cfg/homeproxy.hp-restore" ]; then
	echo "FAIL: a run that lost the lock wrote a recovery snapshot"
	FAILED=1
fi

# ...and a lock left behind by a killed process must not block every future
# update, so one older than the stale window is broken.
rm -f "$LOGFILE"
rm -rf "$LOCKDIR"
mkdir -p "$LOCKDIR"
touch -t 202001010000 "$LOCKDIR"
if ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" update_subscriptions.uc ) > "$WORK/stdout3" 2>&1; then
	:
else
	echo "FAIL: the updater exited non-zero on a stale lock"
	FAILED=1
fi

if grep -q "Breaking a stale update lock" "$LOGFILE" 2>/dev/null; then
	echo "PASS: a stale lock is broken rather than blocking forever"
else
	echo "FAIL: a stale lock was not broken - every future update would be skipped"
	sed 's/^/      /' "$LOGFILE"
	FAILED=1
fi

if [ -d "$LOCKDIR" ]; then
	echo "FAIL: the lock was left behind after the run"
	FAILED=1
fi

rm -rf "$WORK"

if [ "$FAILED" != 0 ]; then
	exit 1
fi

exit 0
