#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RESTORE="$ROOT/root/usr/libexec/smartsafehub-apps-restore"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$TMP/runtime" "$TMP/owned" "$TMP/bin"
cat > "$TMP/bin/apk" <<'MOCK'
#!/bin/sh
[ "$1" = info ] && [ "$2" = -e ] || exit 2
grep -qxF "$3" "$RESTORE_TEST_INSTALLED" 2>/dev/null
MOCK
cat > "$TMP/bin/manager" <<'MOCK'
#!/bin/sh
[ "$1" = start ] && [ "$2" = install ] && [ "$3" = network-usage-monitor ] && [ "$4" = restore ] || exit 4
printf '%s\n' "$3" >> "$RESTORE_TEST_CALLS"
case "${RESTORE_TEST_MODE:-success}" in
 busy) exit 3;;
 offline)
  code=E21
  phase=failed;;
 revoked)
  code=E22
  phase=failed;;
 success)
  printf 'nlbwmon\nluci-app-nlbwmon\nluci-lib-chartjs\n' > "$RESTORE_TEST_INSTALLED"
  code=NONE
  phase=success;;
esac
printf 'phase\t%s\naction\tinstall\napp_id\t%s\ncode\t%s\n' "$phase" "$3" "$code" > "$SMARTSAFEHUB_APPS_RUNTIME_DIR/apps-operation.state"
MOCK
cat > "$TMP/bin/sleep" <<'MOCK'
#!/bin/sh
exit 0
MOCK
chmod +x "$TMP/bin/"*
export SMARTSAFEHUB_APPS_MANAGER_BIN="$TMP/bin/manager"
export SMARTSAFEHUB_APPS_APK_BIN="$TMP/bin/apk"
export SMARTSAFEHUB_APPS_RESTORE_SLEEP_BIN="$TMP/bin/sleep"
export SMARTSAFEHUB_APPS_RESTORE_START_DELAY=0
export SMARTSAFEHUB_APPS_RESTORE_RETRIES=2
export SMARTSAFEHUB_APPS_RESTORE_RETRY_DELAY=0
export SMARTSAFEHUB_APPS_RESTORE_POLL_INTERVAL=0
export SMARTSAFEHUB_APPS_RESTORE_POLL_LIMIT=2
export SMARTSAFEHUB_APPS_RUNTIME_DIR="$TMP/runtime"
export SMARTSAFEHUB_APPS_OWNED_DIR="$TMP/owned"
export RESTORE_TEST_INSTALLED="$TMP/installed"
export RESTORE_TEST_CALLS="$TMP/calls"
: > "$RESTORE_TEST_CALLS"
: > "$RESTORE_TEST_INSTALLED"
# No ownership record (or one from a removed app) must never install packages.
"$RESTORE" run
[ ! -s "$RESTORE_TEST_CALLS" ] || fail 'fresh device tried to restore an app'
# A malformed manifest must never invoke the package manager.
printf 'evil\t1\tbadsha\n' > "$TMP/owned/network-usage-monitor"
"$RESTORE" run
[ ! -s "$RESTORE_TEST_CALLS" ] || fail 'invalid manifest triggered package installation'
grep -Fqx "$(printf 'code\tINVALID_MANIFEST')" "$TMP/runtime/apps-restore.state" || fail 'invalid manifest was not diagnosed'
# The persisted manifest contains only Apps-owned packages. A previously shared
# chart dependency must not be recorded as owned.
HASH="$(printf %064d 0)"
printf 'nlbwmon\t2025.06.02~29236be6-r1\t%s\nluci-app-nlbwmon\t26.288.56989~75a306d\t%s\n' "$HASH" "$HASH" > "$TMP/owned/network-usage-monitor"
export RESTORE_TEST_MODE=offline
"$RESTORE" run
[ "$(wc -l < "$RESTORE_TEST_CALLS" | tr -d ' ')" -eq 2 ] || fail 'network error retry was not bounded'
grep -Fqx "$(printf 'code\tE21')" "$TMP/runtime/apps-restore.state" || fail 'network failure state missing'
: > "$RESTORE_TEST_CALLS"
export RESTORE_TEST_MODE=revoked
"$RESTORE" run
[ "$(wc -l < "$RESTORE_TEST_CALLS" | tr -d ' ')" -eq 1 ] || fail 'revoked approval was retried'
grep -Fqx "$(printf 'code\tE22')" "$TMP/runtime/apps-restore.state" || fail 'revoked approval error missing'
: > "$RESTORE_TEST_CALLS"
export RESTORE_TEST_MODE=success
"$RESTORE" run
[ "$(wc -l < "$RESTORE_TEST_CALLS" | tr -d ' ')" -eq 1 ] || fail 'owned app not restored exactly once'
grep -Fqx "$(printf 'phase\tsuccess')" "$TMP/runtime/apps-restore.state" || fail 'restore success not recorded'
"$RESTORE" run
[ "$(wc -l < "$RESTORE_TEST_CALLS" | tr -d ' ')" -eq 1 ] || fail 'already installed app was reinstalled'
# Apps remove deletes the ownership file. Never recreate it on future boots.
rm -f "$TMP/owned/network-usage-monitor"
: > "$RESTORE_TEST_INSTALLED"
"$RESTORE" run
[ "$(wc -l < "$RESTORE_TEST_CALLS" | tr -d ' ')" -eq 1 ] || fail 'removed app was restored'
# Structural contracts: ownership backup, existing firmware service hook and
# shared RPC status. Do not regress to another procd/init daemon.
grep -Fxq '/etc/smartsafehub/apps-installed/' "$ROOT/root/lib/upgrade/keep.d/smartsafehub-apps" || fail 'sysupgrade backup missing'
[ ! -e "$ROOT/root/etc/init.d/smartsafehub-apps-restore" ] || fail 'extra Apps restore init service introduced'
[ ! -e "$ROOT/root/etc/uci-defaults/93-smartsafehub-apps-restore" ] || fail 'extra Apps restore service enable introduced'
grep -Fq 'start_apps_restore_once' "$ROOT/root/usr/libexec/smartsafehub-firmware" || fail 'existing firmware daemon does not schedule restore'
grep -Fq '"$APPS_RESTORE_BIN" run </dev/null >/dev/null 2>&1 &' "$ROOT/root/usr/libexec/smartsafehub-firmware" || fail 'restore is not a detached one-shot'
grep -Fq 'restore: restore_status()' "$ROOT/root/usr/share/rpcd/ucode/smartsafehub/apps-manager.uc" || fail 'restore status missing from RPC'
grep -Fq 'E21|E25|E31|E35|BUSY' "$ROOT/root/etc/hotplug.d/iface/98-smartsafehub-apps-restore" || fail 'WAN retry safety contract missing'
grep -Fq '"$RUNNER" run </dev/null >/dev/null 2>&1 &' "$ROOT/root/etc/hotplug.d/iface/98-smartsafehub-apps-restore" || fail 'WAN should trigger the one-shot worker directly'
! grep -Fq '"$APK" add' "$RESTORE" || fail 'restore runner must not invoke APK directly'
[ -x "$RESTORE" ] || fail 'restore worker is not executable'
printf 'PASS: sysupgrade Apps restoration without new daemon, retry, revocation and ownership\n'
