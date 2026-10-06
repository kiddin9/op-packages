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
# `/etc/init.d/homeproxy-pro reload` at its end - the device is not touched.
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
cp -R "$ROOT/root/etc/homeproxy-pro/scripts/." "$WORK/scripts/"

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
# append to the device's live /var/run/homeproxy-pro/homeproxy-pro.log, and point the
# configuration directory at the sandbox.  The updater reads the config
# *inside* the lock now (A4), and it takes the directory from homeproxy-pro.uc's
# UCICONFIG_DIR, so both rewrites land in this one file.
sed -e "s#^export const RUN_DIR = '/var/run/homeproxy-pro';#export const RUN_DIR = '$WORK/run';#" \
    -e "s#^export const UCICONFIG_DIR = '/etc/config';#export const UCICONFIG_DIR = '$WORK/cfg';#" \
    "$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" > "$WORK/scripts/homeproxy-pro.uc"

# validate_data.  homeproxy-pro.uc validates a node's address and port by shelling
# out to /sbin/validate_data, which exists only on an OpenWrt target.  Without
# it validation() returns false for everything, every node is rejected as
# "Skipping invalid vless node", and the commit case below can never reach the
# commit - it passed on the device (validate_data present) and failed on CI
# (absent), which is exactly the kind of host difference this test must not
# carry.
#
# The substitution is the one the rest of the suite already uses: the same
# HP_VALIDATE_DATA indirection tests/ucode/run.sh exports off-target, and
# tests/ucode/test_generators.sh applies while staging the generator.  It
# reproduces the caller's contract (exit 0 = valid) and is deliberately a
# pinned fixture rather than an equivalent - see tests/toolchain/validate-data.sh.
if [ ! -x /sbin/validate_data ] && [ -n "${HP_VALIDATE_DATA:-}" ] && [ -x "${HP_VALIDATE_DATA}" ]; then
	sed -e "s#/sbin/validate_data#${HP_VALIDATE_DATA}#g" \
		"$WORK/scripts/homeproxy-pro.uc" > "$WORK/scripts/homeproxy-pro.uc.new"
	mv -f "$WORK/scripts/homeproxy-pro.uc.new" "$WORK/scripts/homeproxy-pro.uc"

	if ! grep -qF "$HP_VALIDATE_DATA" "$WORK/scripts/homeproxy-pro.uc"; then
		echo "FAIL: could not point validation() at HP_VALIDATE_DATA (anchor moved)"
		rm -rf "$WORK"
		exit 1
	fi
fi

# An unpatched copy would read - and on a real device write - the live
# /etc/config/homeproxy-pro.  Fail here instead of silently testing the wrong file.
if ! grep -q "^export const UCICONFIG_DIR = '$WORK/cfg';" "$WORK/scripts/homeproxy-pro.uc"; then
	echo "FAIL: could not point the updater at the sandbox config (anchor moved)"
	rm -rf "$WORK"
	exit 1
fi

# The rewrite above only redirects the *constant*.  It does not redirect the
# cursor on its own: `cursor()` with no argument is a cursor on the real
# /etc/config, and this script's one `uci.commit()` writes through whichever
# cursor it built.  So assert the wiring directly - a bare `cursor()` in the
# updater means the sandbox is a no-op and a case that lets a fetch succeed
# would commit this test's nodes over the user's real configuration.
#
# The Loader takes the same `dir` argument (loader.uc), so a call carrying the
# directory is the established spelling, not a test-only accommodation.
if ! grep -q 'cursor(UCICONFIG_DIR)' "$WORK/scripts/update_subscriptions.uc"; then
	echo "FAIL: the updater builds a bare cursor() - it would read and commit the"
	echo "      live /etc/config regardless of the sandboxed UCICONFIG_DIR."
	rm -rf "$WORK"
	exit 1
fi

# And prove it behaviourally rather than by reading the source: stage a config
# whose only URL is a closed port, and check the run reports the URL *it* was
# given.  A cursor on the real /etc/config would instead see the device's own
# subscription_url and try to reach that one - the difference between this test
# and a test that quietly talks to the user's router.
echo "PASS: the updater's cursor is built on the sandboxed config directory"

cat > "$WORK/cfg/homeproxy-pro" <<-EOF
	config homeproxy-pro 'config'
		option routing_mode 'proxy'
		option main_node 'nil'

	config homeproxy-pro 'subscription'
		list subscription_url 'https://hp-t8-canary.invalid/never'
		option filter_nodes 'disabled'
		option auto_update '0'
EOF

LOGFILE="$WORK/run/homeproxy-pro.log"

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

# The behavioural half of the sandbox check, and the one that matters: the run
# above must have been driven by the config staged HERE.  A cursor on the real
# /etc/config would read the device's own subscription_url and try to fetch
# that instead, so the log would name a different host - or the run would
# succeed against a subscription this test never asked for.  Either way the
# test would be reaching the user's router, which is the whole hazard.
#
# The canary hostname is here so the log can be attributed to THIS config,
# and it is deliberately a name no real subscription would carry.  Note what it
# does and does not prove: the URL is read through Loader.load(UCICONFIG_DIR),
# which was already sandboxed, so this assertion is about the READ path and
# says nothing about the cursor the writes go through.  The write path is
# asserted structurally below, where it can actually be observed.
#
# `.invalid` is reserved by RFC 2606 and never resolves, so the fetch fails
# fast and the run cannot succeed whatever the DNS.
if grep -q "hp-t8-canary.invalid" "$LOGFILE" 2>/dev/null; then
	echo "PASS: the run was driven by the sandboxed config (canary URL was fetched)"
else
	echo "FAIL: the log never mentions the staged canary URL - the updater read a"
	echo "      configuration this test did not write."
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
cp "$WORK/cfg/homeproxy-pro" "$WORK/cfg.before-standdown"

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

if cmp -s "$WORK/cfg.before-standdown" "$WORK/cfg/homeproxy-pro"; then
	echo "PASS: a run that lost the lock left the configuration untouched"
else
	echo "FAIL: a run that lost the lock still rewrote the configuration"
	FAILED=1
fi

if [ -e "$WORK/cfg/homeproxy-pro.hp-restore" ]; then
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

# --- the commit path --------------------------------------------------------
# Everything above runs a fetch that FAILS, which returns before
# `uci.commit(uciconfig)` - so not one of those cases ever exercised the write.
# That is precisely why the bare cursor() went unnoticed: the only dangerous
# line in the script was on a path no test reached.
#
# This case reaches it.  The fetch is satisfied by shadowing
# subscription/fetcher.uc through the -L search path, so a real subscription
# body arrives, at least one node survives it, and the run commits.  What has
# to be asserted is WHERE: a commit through a bare cursor() writes the live
# /etc/config/homeproxy-pro, on a real device, with this test's node in it.
CANARY_DIR="$WORK/commit-run"
mkdir -p "$CANARY_DIR/scripts" "$CANARY_DIR/cfg" "$CANARY_DIR/run"
cp -R "$WORK/scripts/." "$CANARY_DIR/scripts/"
cp "$WORK/cfg/homeproxy-pro" "$CANARY_DIR/cfg/homeproxy-pro"

# Re-point the copy at ITS OWN directories.  `cp -R` of the scripts tree brings
# the sandboxed homeproxy-pro.uc along, and that file still names the parent's
# $WORK/cfg and $WORK/run - so without this the run below reads and COMMITS the
# parent's config, writes its log into the parent's run dir, and the two
# directories this case is about never get touched.  The first version of this
# case did exactly that and reported "the commit path is not being exercised"
# against an empty log, which is the symptom rather than the cause.
sed -e "s#^export const RUN_DIR = '$WORK/run';#export const RUN_DIR = '$CANARY_DIR/run';#" \
    -e "s#^export const UCICONFIG_DIR = '$WORK/cfg';#export const UCICONFIG_DIR = '$CANARY_DIR/cfg';#" \
    "$WORK/scripts/homeproxy-pro.uc" > "$CANARY_DIR/scripts/homeproxy-pro.uc"

for anchor in "RUN_DIR = '$CANARY_DIR/run'" "UCICONFIG_DIR = '$CANARY_DIR/cfg'"; do
	if ! grep -qF "$anchor" "$CANARY_DIR/scripts/homeproxy-pro.uc"; then
		echo "FAIL: could not re-point the commit sandbox at its own directories"
		echo "      (anchor moved: $anchor)"
		rm -rf "$WORK"
		exit 1
	fi
done

# The stand-in for the network: one share link, so the count is non-zero and
# main() proceeds to the commit.  It shadows the whole fetcher module, so the
# canary URL is never actually dialled.
#
# The body is a JSON object with a `servers` array of share-link STRINGS, which
# is the shape the decoder's own test corpus uses.  Two shapes that look
# equivalent are not and both were tried here first: a bare URI list is not
# JSON and falls through to the base64 branch, and a `servers` array of
# OBJECTS decodes but yields no valid node - the run then reports "no valid
# node found" and returns before the commit, which is the failure this case
# exists to rule out.
mkdir -p "$CANARY_DIR/scripts/subscription"
cat > "$CANARY_DIR/scripts/subscription/fetcher.uc" <<'EOF'
export function fetch(url, _ua, log) {
	if (url != 'https://hp-t8-canary.invalid/never')
		return { content: null, error: 'unexpected url: ' + url };

	return {
		content: '{"servers":["vless://vless-uuid@o.example.com:443?security=tls&type=ws&host=o.example.com&path=%2Fws&sni=o.example.com#t8-committed-node"]}',
		error: null
	};
};
EOF

# A successful run reaches the service reload.  Every case above avoided it by
# failing first, so nothing ever had to neutralise it - and a test that restarts
# the user's proxy is not a test, it is an outage.
#
# It cannot be intercepted on PATH: the updater calls the ABSOLUTE path
# `/etc/init.d/homeproxy-pro` (update_subscriptions.uc:471), so a stub earlier in
# PATH is never consulted.  The staged copy is rewritten instead, which is the
# same trick the RUN_DIR / UCICONFIG_DIR rewrites above already use - and the
# anchor is asserted, because a sed that quietly stopped matching would leave
# this case reloading the real service while still reporting success.
mkdir -p "$CANARY_DIR/bin"
cat > "$CANARY_DIR/bin/homeproxy-pro-reload-stub" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$WORK/reload.log"
exit 0
EOF
chmod +x "$CANARY_DIR/bin/homeproxy-pro-reload-stub"

sed "s#executeCommand('/etc/init.d/homeproxy-pro'#executeCommand('$CANARY_DIR/bin/homeproxy-pro-reload-stub'#" \
	"$WORK/scripts/update_subscriptions.uc" > "$CANARY_DIR/scripts/update_subscriptions.uc"

if grep -qF "executeCommand('$CANARY_DIR/bin/homeproxy-pro-reload-stub'" \
	"$CANARY_DIR/scripts/update_subscriptions.uc"; then
	:
else
	echo "FAIL: could not redirect the reload out of the real /etc/init.d"
	echo "      (anchor moved) - refusing to run a case that would restart the"
	echo "      service on whatever machine this is running against."
	rm -rf "$WORK"
	exit 1
fi

# Run it exactly once: a second invocation would commit the same node again and
# make the counts below meaningless.
( cd "$CANARY_DIR/scripts" && ucode -L "$CANARY_DIR/scripts" update_subscriptions.uc ) \
	> "$WORK/stdout-commit" 2>&1

if [ -f "$WORK/reload.log" ]; then
	echo "PASS: the successful run asked for a reload (through the stub)"
else
	echo "FAIL: the commit case never got as far as the reload - the commit path"
	echo "      is still not being exercised."
	sed 's/^/      /' "$WORK/stdout-commit"
	FAILED=1
fi

# The run's own log is the commit-run's, not the parent's: the re-point above
# gave this run its own RUN_DIR, and the updater writes nothing to stdout - it
# logs to the file.  Reading $LOGFILE here (as a first cut of this case did)
# checks the parent run's log, which still describes the earlier failing fetch,
# so the assertion below was reporting on the wrong run entirely.
COMMIT_LOG="$CANARY_DIR/run/homeproxy-pro.log"

if grep -q "Successfully fetched" "$COMMIT_LOG" 2>/dev/null; then
	echo "PASS: the commit run reported a successful import (not a vacuous pass)"
else
	echo "FAIL: the commit run never reported a successful fetch - it is not"
	echo "      exercising the commit path, and the assertion above proves nothing."
	sed 's/^/      /' "$COMMIT_LOG" 2>/dev/null
	sed 's/^/      /' "$WORK/stdout-commit"
	FAILED=1
fi

# The node from the fake body has to be in the SANDBOX config.  This is the
# assertion that matters: it is the only one made after a commit, and it reads
# the file the commit was supposed to land in.
#
# The marker is deliberately NOT a substring of the canary hostname.  An
# earlier version of this case grepped for "t8-canary", which the staged
# subscription_url already contains - so it passed against a run that had
# committed nothing at all, and would have passed against a commit that landed
# in the wrong file.  The node label is the only thing in the sandbox config
# that can only have arrived through a successful import.
if grep -q "t8-committed-node" "$CANARY_DIR/cfg/homeproxy-pro" 2>/dev/null; then
	echo "PASS: a successful run committed into the sandboxed config"
else
	echo "FAIL: the committed node is not in the sandboxed config - the commit"
	echo "      went somewhere else, and on a device that is /etc/config/homeproxy-pro."
	sed 's/^/      /' "$WORK/stdout-commit"
	FAILED=1
fi

# The import has to have happened at all, or the case above is vacuous: a run
# that never reached the commit would leave the same absence.  Assert the run
# reported the import rather than only that the file is missing a node.

# And the mirror image: the node must NOT have been invented anywhere else.  A
# test that can write outside its sandbox is worse than one that cannot run, so
# this is checked rather than assumed.
if [ -e "$CANARY_DIR/cfg/homeproxy-pro.hp-restore" ]; then
	echo "FAIL: the run left a recovery snapshot next to the config it committed"
	FAILED=1
fi

rm -rf "$WORK"

if [ "$FAILED" != 0 ]; then
	exit 1
fi

exit 0
