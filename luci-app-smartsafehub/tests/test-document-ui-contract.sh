#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
STATE_PANELS="$ROOT_DIR/frontend/src/components/StatePanels.tsx"
APP_SHELL="$ROOT_DIR/frontend/src/components/AppShell.tsx"
LOGIN_TEMPLATE="$ROOT_DIR/root/usr/share/ucode/luci/template/smartsafehub/login.ut"
THEME="$ROOT_DIR/frontend/src/utils/theme.ts"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$STATE_PANELS" "$APP_SHELL" "$LOGIN_TEMPLATE" "$THEME"; do
	[ -f "$file" ] || fail "missing required file: ${file#$ROOT_DIR/}"
done

grep -Fq 'class="flex items-center gap-4"' "$STATE_PANELS" || \
	fail 'LoadingPanel must use a compact horizontal layout'
grep -Fq "import { ReloadIcon } from './Icons';" "$STATE_PANELS" || \
	fail 'state panels must use the shared reload icon'
grep -Eq '<ReloadIcon class="[^"]*size-8[^"]*shrink-0[^"]*animate-spin[^"]*" */>' "$STATE_PANELS" || \
	fail 'LoadingPanel reload icon must stay compact, non-shrinking and animated'
grep -Fq '<ReloadIcon class="size-4" />' "$STATE_PANELS" || \
	fail 'ErrorPanel retry action must use the shared reload icon'
grep -Fq 'class="min-w-0 text-left"' "$STATE_PANELS" || \
	fail 'LoadingPanel copy must align beside the spinner'
grep -Fq "? 'pt-2 sm:pt-2 lg:pt-3'" "$APP_SHELL" || \
	fail 'AppShell must reduce top padding while the initial loading panel is visible'
grep -Fq ": 'pt-5 sm:pt-6 lg:pt-8'" "$APP_SHELL" || \
	fail 'AppShell must preserve normal page top padding after loading'
if grep -Fq 'class="mt-5 mb-0 text-lg font-extrabold text-slate-950"' "$STATE_PANELS"; then
	fail 'LoadingPanel must not restore the large text top margin'
fi

grep -Fq '<meta name="color-scheme" content="light dark">' "$LOGIN_TEMPLATE" || \
	fail 'document must advertise light and dark color schemes'
grep -Fq '<meta name="theme-color" content="#f8fafc">' "$LOGIN_TEMPLATE" || \
	fail 'document must provide a default SmartSafeHub theme color'
grep -Fq '<meta name="application-name" content="SmartSafeHub">' "$LOGIN_TEMPLATE" || \
	fail 'document must provide the SmartSafeHub application name'
grep -Fq '<meta name="description" content="SmartSafeHub에서 네트워크, Wi-Fi, 연결된 기기와 SafeShield DNS 보호 상태를 관리합니다.">' "$LOGIN_TEMPLATE" || \
	fail 'document must provide a product description'
grep -Fq '<meta name="robots" content="noindex,nofollow,noarchive">' "$LOGIN_TEMPLATE" || \
	fail 'router administration UI must opt out of search indexing'
grep -Fq "'meta[name=\"theme-color\"]'" "$THEME" || \
	fail 'theme utility must locate the theme-color metadata'
grep -Fq "theme === 'dark' ? '#0f172a' : '#f8fafc'" "$THEME" || \
	fail 'theme-color metadata must follow the selected UI theme'

echo 'PASS: document metadata and loading panel contracts are consistent'
