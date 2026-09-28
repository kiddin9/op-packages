#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ROUTES="$ROOT_DIR/frontend/src/app/routes.ts"
HASH_ROUTE="$ROOT_DIR/frontend/src/hooks/useHashRoute.ts"
NAVIGATION="$ROOT_DIR/frontend/src/components/ProductNavigation.tsx"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
HOME="$ROOT_DIR/frontend/src/pages/HomePage.tsx"
README="$ROOT_DIR/README.md"
FEATURES="$ROOT_DIR/docs/FEATURES.md"
ARCHITECTURE="$ROOT_DIR/docs/ARCHITECTURE.md"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$ROUTES" "$HASH_ROUTE" "$NAVIGATION" "$APP" "$HOME" "$README" "$FEATURES" "$ARCHITECTURE"; do
	[ -f "$file" ] || fail "missing network settings contract source: ${file#$ROOT_DIR/}"
done

grep -Fq "  | 'network'" "$ROUTES" || fail 'AppRoute must expose the combined network route'
grep -Fq "route: 'network'" "$ROUTES" || fail 'combined network settings route must be registered'
grep -Fq "hash: '#network'" "$ROUTES" || fail 'combined network settings route must use #network'
grep -Fq "label: '네트워크'" "$ROUTES" || fail 'combined route label must be 네트워크'
grep -Fq "title: '네트워크'" "$ROUTES" || fail 'combined page title must be 네트워크'
if grep -Fq "route: 'wan'" "$ROUTES" || grep -Fq "route: 'lan'" "$ROUTES"; then
	fail 'WAN and LAN must not remain as separate visible routes'
fi

grep -Fq "'#network': 'network'" "$HASH_ROUTE" || fail '#network must resolve to combined network settings'
grep -Fq "'#wan': 'network'" "$HASH_ROUTE" || fail 'legacy #wan must remain compatible'
grep -Fq "'#lan': 'network'" "$HASH_ROUTE" || fail 'legacy #lan must remain compatible'
grep -Fq "{ label: 'Network', routes: ['network', 'wifi', 'iptv', 'devices'] }" "$NAVIGATION" || \
	fail 'Network sidebar must expose a single combined settings item'
grep -Fq "case 'network':" "$NAVIGATION" || fail 'combined network item must have an icon'
if grep -Fq "case 'wan':" "$NAVIGATION" || grep -Fq "case 'lan':" "$NAVIGATION"; then
	fail 'sidebar icon routing must not retain separate WAN/LAN entries'
fi

grep -Fq "const wan = useWan(route === 'network');" "$APP" || fail 'WAN settings must load on the combined route'
grep -Fq "const lan = useLan(route === 'home' || route === 'network');" "$APP" || fail 'LAN settings must load on dashboard and combined route'
grep -Fq "case 'network':" "$APP" || fail 'App must render the combined network route'
grep -Fq 'aria-label="인터넷 연결 설정"' "$APP" || fail 'combined page must keep a distinct WAN region'
grep -Fq 'aria-label="내부 네트워크 설정"' "$APP" || fail 'combined page must keep a distinct LAN region'
grep -Fq 'class="mt-8 min-w-0 border-t border-slate-200 pt-8"' "$APP" || fail 'WAN and LAN regions must have a clear visual boundary'
grep -Fq '<WanPage' "$APP" || fail 'combined page must reuse the WAN settings implementation'
grep -Fq '<LanPage' "$APP" || fail 'combined page must reuse the LAN settings implementation'
grep -Fq "if (route === 'network')" "$APP" || fail 'combined route must have an explicit global refresh path'
grep -Fq 'void Promise.all([wan.refresh(), lan.refresh()]);' "$APP" || fail 'global refresh must update WAN and LAN together'
grep -Fq "loading={route === 'network' ? wan.loading || lan.loading : current.loading}" "$APP" || fail 'combined page loading state must cover both sources'
grep -Fq "(route === 'network' && lan.refreshing)" "$APP" || fail 'combined page refresh state must include LAN refresh'

[ "$(grep -Fc 'href="#network"' "$HOME")" -ge 2 ] || fail 'dashboard network links must target the combined page'
if grep -Fq 'href="#lan"' "$HOME" || grep -Fq 'href="#wan"' "$HOME"; then
	fail 'dashboard must not link to legacy WAN/LAN hashes'
fi
grep -Fq '네트워크 보기' "$HOME" || fail 'dashboard detail action must use the concise network label'
grep -Fq '**네트워크 관리**:' "$README" || fail 'README must describe the combined network screen'
grep -Fq '## 네트워크 (WAN/LAN 및 DHCP)' "$FEATURES" || fail 'feature docs must use the concise network page name'
grep -Fq '| `network` | `#network` | WAN 인터넷 연결 + LAN 및 DHCP |' "$ARCHITECTURE" || fail 'architecture route table must use the combined route'

printf 'PASS: WAN and LAN are exposed through one network settings route while preserving independent settings flows\n'
