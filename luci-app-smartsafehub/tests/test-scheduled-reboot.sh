#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-maintenance"
INIT_SCRIPT="$ROOT_DIR/root/etc/init.d/smartsafehub-maintenance"
CONFIG="$ROOT_DIR/root/etc/config/smartsafehub"
SYSTEM_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/system.uc"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
API="$ROOT_DIR/frontend/src/api/smartsafehub.ts"
HOOK="$ROOT_DIR/frontend/src/hooks/useScheduledRebootSettings.ts"
SETTINGS_PAGE="$ROOT_DIR/frontend/src/pages/SettingsPage.tsx"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$HELPER" "$INIT_SCRIPT" "$CONFIG" "$SYSTEM_MODULE" "$RPC_ENTRY" "$ACL" "$API" "$HOOK" "$SETTINGS_PAGE"; do
	[ -f "$file" ] || fail "missing scheduled reboot source: ${file#$ROOT_DIR/}"
done

sh -n "$HELPER" || fail 'maintenance helper must pass POSIX shell syntax validation'
sh -n "$INIT_SCRIPT" || fail 'maintenance init script must pass POSIX shell syntax validation'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin"

cat > "$TMP/bin/uci" <<'EOF_UCI'
#!/bin/sh
set -eu
if [ "${1:-}" = "-q" ]; then
	shift
fi
case "${1:-}" in
	get)
		case "${2:-}" in
			smartsafehub.maintenance.scheduled_reboot_enabled) printf '%s\n' "${MOCK_ENABLED:-0}" ;;
			smartsafehub.maintenance.scheduled_reboot_frequency) printf '%s\n' "${MOCK_FREQUENCY:-weekly}" ;;
			smartsafehub.maintenance.scheduled_reboot_day) printf '%s\n' "${MOCK_DAY:-sun}" ;;
			smartsafehub.maintenance.scheduled_reboot_time) printf '%s\n' "${MOCK_TIME:-04:00}" ;;
			*) exit 1 ;;
		esac
		;;
	batch)
		cat > "${MOCK_UCI_BATCH_LOG:?}"
		;;
	*)
		exit 1
		;;
esac
EOF_UCI
chmod +x "$TMP/bin/uci"

cat > "$TMP/bin/reboot" <<'EOF_REBOOT'
#!/bin/sh
set -eu
printf 'reboot\n' >> "${MOCK_REBOOT_LOG:?}"
EOF_REBOOT
chmod +x "$TMP/bin/reboot"

cat > "$TMP/bin/sync" <<'EOF_SYNC'
#!/bin/sh
exit 0
EOF_SYNC
chmod +x "$TMP/bin/sync"

cat > "$TMP/bin/logger" <<'EOF_LOGGER'
#!/bin/sh
exit 0
EOF_LOGGER
chmod +x "$TMP/bin/logger"

cat > "$TMP/bin/date" <<'EOF_DATE'
#!/bin/sh
set -eu
case "${1:-}" in
	+%s) printf '%s\n' "${MOCK_EPOCH:-1800000000}" ;;
	+%H:%M) printf '%s\n' "${MOCK_LOCAL_TIME:-04:00}" ;;
	+%u) printf '%s\n' "${MOCK_DAY_NUMBER:-7}" ;;
	+%Y-%m-%d) printf '%s\n' "${MOCK_LOCAL_DATE:-2027-01-17}" ;;
	*) exit 1 ;;
esac
EOF_DATE
chmod +x "$TMP/bin/date"

STATE="$TMP/maintenance.state"
UPDATE_STATE="$TMP/updates.state"
FIRMWARE_STATE="$TMP/firmware.state"
FIRMWARE_IMAGE="$TMP/firmware.bin"
UPTIME="$TMP/uptime"
REBOOT_LOG="$TMP/reboot.log"
UCI_BATCH_LOG="$TMP/uci.batch"
printf '7200.00 0.00\n' > "$UPTIME"
: > "$REBOOT_LOG"
: > "$UCI_BATCH_LOG"

current_time="04:00"
current_day_number="7"
current_day="sun"
mock_epoch="1800000000"

run_helper() {
	MOCK_UCI_BATCH_LOG="$UCI_BATCH_LOG" \
	MOCK_REBOOT_LOG="$REBOOT_LOG" \
	MOCK_ENABLED="${MOCK_ENABLED:-1}" \
	MOCK_FREQUENCY="${MOCK_FREQUENCY:-daily}" \
	MOCK_DAY="${MOCK_DAY:-$current_day}" \
	MOCK_TIME="${MOCK_TIME:-$current_time}" \
	SMARTSAFEHUB_MAINTENANCE_STATE_FILE="$STATE" \
	SMARTSAFEHUB_MAINTENANCE_UPDATE_STATE_FILE="$UPDATE_STATE" \
	SMARTSAFEHUB_MAINTENANCE_FIRMWARE_STATE_FILE="$FIRMWARE_STATE" \
	SMARTSAFEHUB_MAINTENANCE_UPDATE_LOCK_DIR="$TMP/update.lock" \
	SMARTSAFEHUB_MAINTENANCE_FIRMWARE_LOCK_DIR="$TMP/firmware.lock" \
	SMARTSAFEHUB_MAINTENANCE_FIRMWARE_IMAGE_FILE="$FIRMWARE_IMAGE" \
	SMARTSAFEHUB_MAINTENANCE_UCI_BIN="$TMP/bin/uci" \
	SMARTSAFEHUB_MAINTENANCE_REBOOT_BIN="$TMP/bin/reboot" \
	SMARTSAFEHUB_MAINTENANCE_SYNC_BIN="$TMP/bin/sync" \
	SMARTSAFEHUB_MAINTENANCE_DATE_BIN="$TMP/bin/date" \
	SMARTSAFEHUB_MAINTENANCE_UPTIME_FILE="$UPTIME" \
	MOCK_EPOCH="$mock_epoch" \
	MOCK_LOCAL_TIME="$current_time" \
	MOCK_DAY_NUMBER="$current_day_number" \
	MOCK_LOCAL_DATE="2027-01-17" \
	PATH="$TMP/bin:$PATH" \
	"$HELPER" "$@"
}

# Disabled by default: the helper must never reboot.
rm -f "$STATE" "$UPDATE_STATE" "$FIRMWARE_STATE" "$FIRMWARE_IMAGE"
: > "$REBOOT_LOG"
MOCK_ENABLED=0 run_helper run-once
[ ! -s "$REBOOT_LOG" ] || fail 'disabled scheduled reboot must not reboot the router'

# A due daily schedule may reboot once when the router is idle and has been up long enough.
rm -f "$STATE" "$UPDATE_STATE" "$FIRMWARE_STATE" "$FIRMWARE_IMAGE"
: > "$REBOOT_LOG"
MOCK_ENABLED=1 MOCK_FREQUENCY=daily run_helper run-once
[ "$(wc -l < "$REBOOT_LOG" | tr -d ' ')" -eq 1 ] || fail 'due idle schedule must request exactly one reboot'
grep -Eq '^last_result[[:space:]]+rebooting$' "$STATE" || fail 'successful scheduled reboot must record rebooting state before reboot'

# Re-running during the same schedule minute must not request a second reboot.
MOCK_ENABLED=1 MOCK_FREQUENCY=daily run_helper run-once
[ "$(wc -l < "$REBOOT_LOG" | tr -d ' ')" -eq 1 ] || fail 'same schedule key must not cause a duplicate reboot'

# A recently booted router must not enter a reboot loop in the same schedule minute.
rm -f "$STATE"
: > "$REBOOT_LOG"
printf '120.00 0.00\n' > "$UPTIME"
MOCK_ENABLED=1 MOCK_FREQUENCY=daily run_helper run-once
[ ! -s "$REBOOT_LOG" ] || fail 'recently booted router must not be rebooted by the same scheduled minute'
grep -Eq '^last_result[[:space:]]+skipped_recent_boot$' "$STATE" || fail 'recent-boot protection must be recorded'
printf '7200.00 0.00\n' > "$UPTIME"

# Software installation/checking must defer the reboot instead of interrupting the updater.
rm -f "$STATE"
: > "$REBOOT_LOG"
printf 'phase\tinstalling\n' > "$UPDATE_STATE"
MOCK_ENABLED=1 MOCK_FREQUENCY=daily run_helper run-once
[ ! -s "$REBOOT_LOG" ] || fail 'software update activity must defer scheduled reboot'
grep -Eq '^last_result[[:space:]]+deferred_management_software_update$' "$STATE" || fail 'software update deferral reason must be recorded'
grep -Eq '^pending_key[[:space:]]+.+$' "$STATE" || fail 'deferred reboot must keep a pending schedule key'

# Once the updater is idle and retry time is due, the pending reboot may proceed.
now="$mock_epoch"
pending_key="$(awk -F '\t' '$1 == "pending_key" { print $2 }' "$STATE")"
{
	printf 'version\t1\n'
	printf 'last_key\t\n'
	printf 'pending_key\t%s\n' "$pending_key"
	printf 'pending_since\t%s\n' "$((now - 60))"
	printf 'next_retry_at\t%s\n' "$((now - 1))"
	printf 'last_result\tdeferred_management_software_update\n'
	printf 'last_result_at\t%s\n' "$((now - 60))"
} > "$STATE"
printf 'phase\tidle\n' > "$UPDATE_STATE"
: > "$REBOOT_LOG"
MOCK_ENABLED=1 MOCK_FREQUENCY=daily run_helper run-once
[ "$(wc -l < "$REBOOT_LOG" | tr -d ' ')" -eq 1 ] || fail 'pending reboot must run after the blocking update becomes idle'

# A prepared firmware image is intentionally treated as busy so a scheduled reboot does not discard the user's pending install.
rm -f "$STATE" "$UPDATE_STATE" "$FIRMWARE_IMAGE"
: > "$REBOOT_LOG"
printf 'phase\tready\n' > "$FIRMWARE_STATE"
MOCK_ENABLED=1 MOCK_FREQUENCY=daily run_helper run-once
[ ! -s "$REBOOT_LOG" ] || fail 'prepared firmware must defer scheduled reboot'
grep -Eq '^last_result[[:space:]]+deferred_firmware_update$' "$STATE" || fail 'firmware deferral reason must be recorded'

# A manual cgi-io upload may exist before firmware validation changes the phase; the image itself must still block reboot.
rm -f "$STATE" "$FIRMWARE_STATE"
: > "$REBOOT_LOG"
printf 'partial upload' > "$FIRMWARE_IMAGE"
MOCK_ENABLED=1 MOCK_FREQUENCY=daily run_helper run-once
[ ! -s "$REBOOT_LOG" ] || fail 'manual firmware upload file must defer scheduled reboot before validation starts'
grep -Eq '^last_result[[:space:]]+deferred_firmware_update$' "$STATE" || fail 'manual firmware upload must use firmware deferral reason'
rm -f "$FIRMWARE_IMAGE"

# Deferred work must stop retrying after the two-hour safety window.
now="$mock_epoch"
{
	printf 'version\t1\n'
	printf 'last_key\t\n'
	printf 'pending_key\ttimeout-test\n'
	printf 'pending_since\t%s\n' "$((now - 7200))"
	printf 'next_retry_at\t%s\n' "$((now - 1))"
	printf 'last_result\tdeferred_firmware_update\n'
	printf 'last_result_at\t%s\n' "$((now - 7200))"
} > "$STATE"
: > "$REBOOT_LOG"
case "$current_day" in
	sun) non_matching_day=mon ;;
	*) non_matching_day=sun ;;
esac
MOCK_ENABLED=1 MOCK_FREQUENCY=weekly MOCK_DAY="$non_matching_day" run_helper run-once
[ ! -s "$REBOOT_LOG" ] || fail 'deferred reboot must be skipped after the maximum defer window'
grep -Eq '^last_result[[:space:]]+skipped_defer_timeout$' "$STATE" || fail 'defer timeout must be recorded'

# Configuration writes must be validated and confined to the maintenance UCI section.
: > "$UCI_BATCH_LOG"
printf 'stale\tpending\n' > "$STATE"
MOCK_ENABLED=1 run_helper configure 1 weekly sun 04:00
grep -Fq "set smartsafehub.maintenance=maintenance" "$UCI_BATCH_LOG" || fail 'configure must create the named maintenance section for upgraded devices'
grep -Fq "scheduled_reboot_enabled='1'" "$UCI_BATCH_LOG" || fail 'configure must persist scheduled reboot enabled state'
grep -Fq "scheduled_reboot_frequency='weekly'" "$UCI_BATCH_LOG" || fail 'configure must persist frequency'
grep -Fq "scheduled_reboot_day='sun'" "$UCI_BATCH_LOG" || fail 'configure must persist weekday'
grep -Fq "scheduled_reboot_time='04:00'" "$UCI_BATCH_LOG" || fail 'configure must persist local reboot time'
[ ! -e "$STATE" ] || fail 'saving a new schedule must clear stale deferred runtime state'
if MOCK_ENABLED=1 run_helper configure 1 weekly invalid 04:00 2>/dev/null; then
	fail 'configure must reject invalid weekday values'
fi
if MOCK_ENABLED=1 run_helper configure 1 weekly sun 25:00 2>/dev/null; then
	fail 'configure must reject invalid reboot times'
fi

# Package/runtime contracts.
grep -Fq "option scheduled_reboot_enabled '0'" "$CONFIG" || fail 'scheduled reboot must be disabled by default'
grep -Fq "option scheduled_reboot_frequency 'weekly'" "$CONFIG" || fail 'default schedule must be weekly'
grep -Fq "option scheduled_reboot_day 'sun'" "$CONFIG" || fail 'default weekly schedule must use Sunday'
grep -Fq "option scheduled_reboot_time '04:00'" "$CONFIG" || fail 'default schedule must use 04:00 local time'
grep -Fq 'procd_add_reload_trigger smartsafehub' "$INIT_SCRIPT" || fail 'maintenance daemon must reload when SmartSafeHub UCI changes'
grep -Fq "set smartsafehub.maintenance=maintenance" "$INIT_SCRIPT" || fail 'init script must migrate older configs that lack the maintenance section'

grep -Fq 'export function read_scheduled_reboot_settings(request)' "$SYSTEM_MODULE" || fail 'scheduled reboot read RPC implementation is missing'
grep -Fq 'export function update_scheduled_reboot_settings(request)' "$SYSTEM_MODULE" || fail 'scheduled reboot update RPC implementation is missing'
grep -Fq "MAINTENANCE_HELPER," "$SYSTEM_MODULE" || fail 'RPC update must persist settings through the validated maintenance helper'
grep -Fq "run_command([ MAINTENANCE_INIT, 'restart' ], 5000);" "$SYSTEM_MODULE" || fail 'saved schedules and timezone changes must restart the maintenance daemon'
grep -Eq '^[[:space:]]*system_scheduled_reboot_settings:[[:space:]]*\{' "$RPC_ENTRY" || fail 'scheduled reboot settings RPC must be registered'
grep -Eq '^[[:space:]]*system_scheduled_reboot_update:[[:space:]]*\{' "$RPC_ENTRY" || fail 'scheduled reboot update RPC must be registered'
jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub | index("system_scheduled_reboot_settings") != null' "$ACL" >/dev/null || fail 'scheduled reboot settings RPC needs read ACL access'
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub | index("system_scheduled_reboot_update") != null' "$ACL" >/dev/null || fail 'scheduled reboot update RPC needs write ACL access'

grep -Fq "callApi(API_OBJECT, 'system_scheduled_reboot_settings')" "$API" || fail 'frontend must load scheduled reboot settings through RPC'
grep -Fq "callApi(API_OBJECT, 'system_scheduled_reboot_update'" "$API" || fail 'frontend must save scheduled reboot settings through RPC'
grep -Fq 'export function useScheduledRebootSettings(active: boolean)' "$HOOK" || fail 'scheduled reboot needs a dedicated frontend hook'
grep -Fq 'function ScheduledRebootSection(props:' "$SETTINGS_PAGE" || fail 'settings UI must expose scheduled reboot management'
grep -Fq 'aria-labelledby="scheduled-reboot-heading"' "$SETTINGS_PAGE" || fail 'scheduled reboot section must have an accessible label'
grep -Fq 'id="scheduled-reboot-heading"' "$SETTINGS_PAGE" || fail 'scheduled reboot section heading must be addressable'
grep -Fq 'role="switch"' "$SETTINGS_PAGE" || fail 'scheduled reboot enable control must use switch semantics'
grep -Fq 'const changed =' "$SETTINGS_PAGE" || fail 'scheduled reboot UI must derive dirty state from persisted settings'
grep -Fq '{changed && (' "$SETTINGS_PAGE" || fail 'scheduled reboot UI must show the unsaved marker only while local settings differ'
grep -Fq '저장되지 않음' "$SETTINGS_PAGE" || fail 'scheduled reboot UI must warn when changes have not been saved'
grep -Fq '<AlertIcon aria-hidden="true" class="size-3.5 shrink-0" />' "$SETTINGS_PAGE" || fail 'scheduled reboot unsaved state must include a warning icon'
grep -Fq "{ value: 'weekly', label: '매주' }" "$SETTINGS_PAGE" || fail 'scheduled reboot must support weekly cadence'
grep -Fq "{ value: 'daily', label: '매일' }" "$SETTINGS_PAGE" || fail 'scheduled reboot must support daily cadence'
grep -Fq '업데이트 작업 중이면 15분 단위로 최대 2시간 연기합니다.' "$SETTINGS_PAGE" || fail 'UI must explain update-conflict deferral behavior'
if ! sed -n '/^function TimeSettingsCard/,/^function healthTone/p' "$SETTINGS_PAGE" | grep -F '<ScheduledRebootSection' >/dev/null; then
	fail 'scheduled reboot section must be rendered inside the time and timezone card'
fi
if sed -n '/^function ScheduledRebootSection/,/^export function SettingsPage/p' "$SETTINGS_PAGE" | grep -F '<ActionCard' >/dev/null; then
	fail 'scheduled reboot must not create a second standalone card inside time settings'
fi

echo 'PASS: scheduled reboot settings, update-safe deferral and reboot-loop protection contracts are consistent'
