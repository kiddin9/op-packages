#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CUSTOM_SELECT="$ROOT_DIR/frontend/src/components/CustomSelect.tsx"
ICONS="$ROOT_DIR/frontend/src/components/Icons.tsx"
APP_STYLE="$ROOT_DIR/frontend/src/styles/app.css"
WIFI_PAGE="$ROOT_DIR/frontend/src/pages/WifiPage.tsx"
LAN_PAGE="$ROOT_DIR/frontend/src/pages/LanPage.tsx"
SETTINGS_PAGE="$ROOT_DIR/frontend/src/pages/SettingsPage.tsx"
UPDATES_CARD="$ROOT_DIR/frontend/src/components/SoftwareUpdatesCard.tsx"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -f "$CUSTOM_SELECT" ] || fail 'shared CustomSelect component is missing'

if grep -R -n '<select' "$ROOT_DIR/frontend/src" --include='*.tsx' --include='*.ts' >/dev/null 2>&1; then
  fail 'frontend source must not reintroduce browser-native select elements'
fi

# Shared popup and selection-state contract.
grep -Fq "import { createPortal } from 'preact/compat';" "$CUSTOM_SELECT" || \
  fail 'custom dropdown must portal its popup outside card overflow containers'
grep -Fq "const appRoot = rootRef.current?.closest('.ssh-app');" "$CUSTOM_SELECT" || \
  fail 'custom dropdown popup must remain inside the themed SmartSafeHub application root'
grep -Fq 'ssh-custom-select-trigger flex w-full' "$CUSTOM_SELECT" || \
  fail 'custom dropdown trigger must expose the shared theme hook class'
grep -Fq 'class="ssh-custom-select-menu fixed z-[1000]' "$CUSTOM_SELECT" || \
  fail 'custom dropdown popup must use a stable fixed overlay position and z-index'
grep -Fq 'const menuWidth = Math.min(' "$CUSTOM_SELECT" || \
  fail 'custom dropdown popup width must be clamped to the viewport'
grep -Fq 'width: `${menuWidth}px`' "$CUSTOM_SELECT" || \
  fail 'custom dropdown popup must match the trigger width within viewport bounds'
grep -Fq "availableAbove > availableBelow" "$CUSTOM_SELECT" || \
  fail 'custom dropdown popup must flip above the trigger when lower viewport space is insufficient'
grep -Fq 'event.composedPath()' "$CUSTOM_SELECT" || \
  fail 'outside-click detection must support SmartSafeHub Shadow DOM event retargeting'
grep -Fq 'role="listbox"' "$CUSTOM_SELECT" || \
  fail 'custom dropdown menu must expose listbox semantics'
grep -Fq 'aria-haspopup="listbox"' "$CUSTOM_SELECT" || \
  fail 'custom dropdown trigger must announce its listbox popup'
grep -Fq 'aria-expanded={open}' "$CUSTOM_SELECT" || \
  fail 'custom dropdown trigger must expose open state'
grep -Fq 'role="option"' "$CUSTOM_SELECT" || \
  fail 'custom dropdown items must expose option semantics'
grep -Fq 'aria-selected={active}' "$CUSTOM_SELECT" || \
  fail 'custom dropdown must expose the current selected option'
grep -Fq 'class="size-2 shrink-0 rounded-full bg-teal-500"' "$CUSTOM_SELECT" || \
  fail 'custom dropdown selected item must use the SmartSafeHub teal state indicator'
grep -Fq 'ChevronDownIcon' "$CUSTOM_SELECT" || \
  fail 'custom dropdown trigger must use the shared disclosure icon'
grep -Fq 'export function ChevronDownIcon' "$ICONS" || \
  fail 'shared icon set must provide the dropdown disclosure icon'

# Keyboard contract.
for key in ArrowDown ArrowUp Home End Enter Escape Tab; do
  grep -Fq "case '$key':" "$CUSTOM_SELECT" || \
    fail "custom dropdown must handle the $key key"
done
grep -Fq "case ' ':" "$CUSTOM_SELECT" || \
  fail 'custom dropdown must handle Space activation'

# All previous native selects use the shared component.
grep -Fq 'id={`wifi-security-${network.section}`}' "$WIFI_PAGE" || \
  fail 'Wi-Fi security dropdown must use CustomSelect'
grep -Fq 'id="lan-prefix-length"' "$LAN_PAGE" || \
  fail 'LAN prefix dropdown must use CustomSelect'
grep -Fq 'id="lan-dhcp-lease-time"' "$LAN_PAGE" || \
  fail 'LAN lease dropdown must use CustomSelect'
grep -Fq 'id="smartsafehub-timezone"' "$SETTINGS_PAGE" || \
  fail 'timezone dropdown must use CustomSelect'
grep -Fq 'id="scheduled-reboot-frequency"' "$SETTINGS_PAGE" || \
  fail 'scheduled reboot frequency must use CustomSelect'
grep -Fq 'id="scheduled-reboot-day"' "$SETTINGS_PAGE" || \
  fail 'scheduled reboot weekday must use CustomSelect'
grep -Fq 'id="software-update-check-interval"' "$UPDATES_CARD" || \
  fail 'software update interval must use CustomSelect'

# Dark-mode overrides must cover portaled/disabled custom controls.
grep -Fq ".ssh-app[data-theme='dark'] .ssh-custom-select-trigger:disabled" "$APP_STYLE" || \
  fail 'custom dropdown disabled trigger needs an explicit dark-mode surface'
grep -Fq ".ssh-app[data-theme='dark'] .ssh-custom-select-trigger:focus-visible" "$APP_STYLE" || \
  fail 'custom dropdown focus ring needs a dark-mode override'
grep -Fq ".ssh-app[data-theme='dark'] .ssh-custom-select-menu" "$APP_STYLE" || \
  fail 'custom dropdown popup needs a dark-mode shadow treatment'

# Obsolete native-select arrow normalization must stay removed.
if grep -Fq '.ssh-app select {' "$APP_STYLE"; then
  fail 'obsolete native-select arrow normalization must not return'
fi

echo 'PASS: shared SmartSafeHub custom dropdown positioning, accessibility, theme and migration contracts are present'
