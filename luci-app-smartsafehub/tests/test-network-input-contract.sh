#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
WIFI_PAGE="$ROOT_DIR/frontend/src/pages/WifiPage.tsx"
DEVICES_PAGE="$ROOT_DIR/frontend/src/pages/ConnectedDevicesPage.tsx"
APP_STYLE="$ROOT_DIR/frontend/src/styles/app.css"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# Wi-Fi SSID and password inputs should use the same emphasized text-input surface.
count="$(grep -Fc 'border-2 border-slate-300 bg-slate-50 px-4 py-2.5 text-sm font-semibold' "$WIFI_PAGE")"
[ "$count" -ge 2 ] || \
	fail 'Wi-Fi SSID and password inputs must use the emphasized text-input surface'

grep -Fq 'shadow-inner' "$WIFI_PAGE" || \
	fail 'Wi-Fi text inputs must retain inset affordance'

grep -Fq 'focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100' "$WIFI_PAGE" || \
	fail 'Wi-Fi text inputs must use the shared teal focus treatment'

# Wi-Fi security uses the shared SmartSafeHub custom dropdown rather than a native popup.
grep -Fq '<CustomSelect' "$WIFI_PAGE" || \
	fail 'Wi-Fi security must use the shared custom dropdown'
grep -Fq 'variant="emphasized"' "$WIFI_PAGE" || \
	fail 'Wi-Fi security custom dropdown must retain the emphasized form-control surface'
grep -Fq 'ariaLabel={`${network.bandLabel} Wi-Fi 보안 방식`}' "$WIFI_PAGE" || \
	fail 'Wi-Fi security custom dropdown must retain an accessible per-radio label'

# Wi-Fi cards use the same explicit unsaved-state contract as other editable settings.
grep -Fq 'const settingsDirty =' "$WIFI_PAGE" || \
	fail 'Wi-Fi settings must derive whether local values differ from the persisted network state'
grep -Fq 'ssid.trim() !== network.ssid' "$WIFI_PAGE" || \
	fail 'Wi-Fi dirty state must include SSID changes'
grep -Fq 'enabled !== network.enabled' "$WIFI_PAGE" || \
	fail 'Wi-Fi dirty state must include enabled-state changes'
grep -Fq 'security !== savedSecurity' "$WIFI_PAGE" || \
	fail 'Wi-Fi dirty state must include security changes'
grep -Fq 'password.length > 0' "$WIFI_PAGE" || \
	fail 'Wi-Fi dirty state must include an entered replacement password'
grep -Fq '{settingsDirty ? (' "$WIFI_PAGE" || \
	fail 'Wi-Fi cards must render an unsaved marker only while edited'
grep -Fq '저장되지 않음' "$WIFI_PAGE" || \
	fail 'Wi-Fi cards must visibly mark unsaved local changes'
grep -Fq '<AlertIcon aria-hidden="true" class="size-3.5 shrink-0" />' "$WIFI_PAGE" || \
	fail 'Wi-Fi unsaved state must include a warning icon'
grep -Fq 'aria-live="polite"' "$WIFI_PAGE" || \
	fail 'Wi-Fi unsaved state must announce state changes without interrupting the user'
grep -Fq 'role="status"' "$WIFI_PAGE" || \
	fail 'Wi-Fi unsaved marker must expose status semantics'
grep -Fq "if (next === 'none' || next === 'keep')" "$WIFI_PAGE" || \
	fail 'Wi-Fi custom-security revert must discard a password that can no longer be applied'
grep -Fq 'disabled={busy || !settingsDirty}' "$WIFI_PAGE" || \
	fail 'Wi-Fi save action must remain disabled until the card has local changes'
grep -Fq ".ssh-app[data-theme='dark'] [class~='bg-amber-50']" "$APP_STYLE" || \
	fail 'Wi-Fi unsaved marker background must retain a dark-theme mapping'
grep -Fq "[class~='text-amber-800']" "$APP_STYLE" || \
	fail 'Wi-Fi unsaved marker text must retain dark-theme contrast mapping'

# Connected-device search follows the same search-input and icon alignment contract as custom rules.
grep -Fq 'absolute inset-y-0 left-0 flex w-11 items-center justify-center' "$DEVICES_PAGE" || \
	fail 'connected-device search icon must use a vertically centered flex wrapper'

grep -Fq 'border-2 border-slate-300 bg-slate-50 py-2.5 pr-4 pl-11 text-sm font-semibold' "$DEVICES_PAGE" || \
	fail 'connected-device search must use the emphasized text-input surface'

grep -Fq 'shadow-inner' "$DEVICES_PAGE" || \
	fail 'connected-device search must retain inset affordance'

if grep -Fq 'absolute top-1/2 left-3.5 size-5 -translate-y-1/2' "$DEVICES_PAGE"; then
	fail 'connected-device search icon must not use transform-based vertical positioning'
fi

echo 'PASS: Wi-Fi custom dropdown and connected-device input contracts are present'
