#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APP_SHELL="$ROOT_DIR/frontend/src/components/AppShell.tsx"
NAVIGATION="$ROOT_DIR/frontend/src/components/ProductNavigation.tsx"
HEADER="$ROOT_DIR/frontend/src/components/ProductHeader.tsx"
ICONS="$ROOT_DIR/frontend/src/components/Icons.tsx"
STYLES="$ROOT_DIR/frontend/src/styles/app.css"
THEME="$ROOT_DIR/frontend/src/utils/theme.ts"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$APP_SHELL" "$NAVIGATION" "$HEADER" "$ICONS" "$STYLES" "$THEME"; do
	[ -f "$file" ] || fail "missing frontend navigation source: ${file#$ROOT_DIR/}"
done

grep -Fq "const SIDEBAR_COLLAPSED_STORAGE_KEY = 'smartsafehub.sidebar.collapsed';" "$APP_SHELL" || \
	fail 'AppShell must define the persistent sidebar preference key'
grep -Fq 'window.localStorage.getItem(SIDEBAR_COLLAPSED_STORAGE_KEY)' "$APP_SHELL" || \
	fail 'AppShell must restore the collapsed sidebar preference'
grep -Fq 'window.localStorage.setItem(' "$APP_SHELL" || \
	fail 'AppShell must persist the collapsed sidebar preference'
grep -Fq "export const THEME_STORAGE_KEY = 'smartsafehub.theme';" "$THEME" || \
	fail 'theme utility must define the persistent theme preference key'
grep -Fq "window.matchMedia('(prefers-color-scheme: dark)')" "$THEME" || \
	fail 'theme utility must use the system color preference as the initial theme'
grep -Fq 'data-theme={theme}' "$APP_SHELL" || \
	fail 'AppShell must expose the active color theme'
grep -Fq "'md:grid-cols-[5rem_minmax(0,1fr)]'" "$APP_SHELL" || \
	fail 'AppShell must provide a compact desktop sidebar column'
grep -Fq "'md:grid-cols-[16rem_minmax(0,1fr)]'" "$APP_SHELL" || \
	fail 'AppShell must provide the expanded desktop sidebar column'
grep -Fq 'class={`ssh-product-main w-full max-w-[1600px]' "$APP_SHELL" || \
	fail 'desktop content must keep its 1600px maximum width while using the left gutter as its large-screen anchor'
if grep -Fq 'ssh-product-main mx-auto' "$APP_SHELL"; then
	fail 'desktop content must not recenter after reaching its maximum width'
fi
grep -Fq 'md:h-[4.5rem] md:py-0' "$HEADER" || \
	fail 'desktop product header must use the shared 72px application-shell height'
grep -Fq 'class="flex w-full items-center justify-between gap-4 md:h-full"' "$HEADER" || \
	fail 'desktop product header content must stay vertically centered within the 72px shell'
if grep -Fq 'max-w-[1600px]' "$HEADER" || grep -Fq 'mx-auto' "$HEADER"; then
	fail 'desktop product header must not center its title and global actions inside the content max-width'
fi
grep -Fq 'collapsed={sidebarCollapsed}' "$APP_SHELL" || \
	fail 'AppShell must pass collapsed state into ProductNavigation'
grep -Fq 'onToggleCollapsed={() => setSidebarCollapsed((collapsed) => !collapsed)}' "$APP_SHELL" || \
	fail 'AppShell must wire the desktop sidebar toggle'

grep -Fq "title={collapsed ? 'SmartSafeHub' : undefined}" "$NAVIGATION" || \
	fail 'collapsed sidebar must retain the SmartSafeHub logo mark'
grep -Fq "aria-label={collapsed ? '사이드바 펼치기' : '사이드바 접기'}" "$NAVIGATION" || \
	fail 'desktop navigation must expose an accessible sidebar toggle'
grep -Fq 'h-[4.5rem] min-h-[4.5rem] shrink-0 items-center border-b border-slate-100' "$NAVIGATION" || \
	fail 'desktop sidebar brand area must use the shared 72px application-shell height'
grep -Fq 'class="ssh-sidebar-toggle absolute right-0 top-[4.5rem] z-20 inline-flex size-7 translate-x-1/2 -translate-y-1/2' "$NAVIGATION" || \
	fail 'sidebar toggle must stay centered on the shared 72px brand/header boundary'
grep -Fq 'title={collapsed ? item.label : undefined}' "$NAVIGATION" || \
	fail 'collapsed navigation items must retain hover labels'
grep -Fq 'aria-label="Beta 기능"' "$NAVIGATION" || \
	fail 'collapsed IPTV navigation item must expose an accessible Beta badge'
grep -Fq 'class="absolute right-0.5 top-0.5 inline-flex size-5' "$NAVIGATION" || \
	fail 'collapsed IPTV navigation badge must keep a compact readable 20px circle'
grep -Fq 'text-[13px] font-extrabold' "$NAVIGATION" || \
	fail 'collapsed IPTV beta glyph must keep a readable 13px weight'
grep -Fq '                      β' "$NAVIGATION" || \
	fail 'collapsed IPTV navigation badge must use the single beta glyph'
if grep -Fq 'text-[8px]' "$NAVIGATION"; then
	fail 'collapsed IPTV navigation badge must not regress to the unreadable 8px beta style'
fi
grep -Fq 'data-collapsed={collapsed ? '\''true'\'' : '\''false'\''}' "$NAVIGATION" || \
	fail 'desktop sidebar must expose its collapsed state'
[ "$(grep -Fc 'onClick={onToggleTheme}' "$NAVIGATION")" -eq 1 ] || \
	fail 'mobile navigation must expose exactly one top-level theme toggle'
grep -Fq 'class="inline-flex size-11 shrink-0 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-600' "$NAVIGATION" || \
	fail 'mobile theme toggle must be an icon button next to the hamburger menu'
grep -Fq 'aria-controls="smartsafehub-mobile-menu"' "$NAVIGATION" || \
	fail 'mobile hamburger menu control must remain available'
[ "$(grep -Fc 'onClick={onToggleTheme}' "$HEADER")" -eq 1 ] || \
	fail 'desktop product header must expose exactly one theme toggle'
grep -Fq 'md:inline-flex' "$HEADER" || \
	fail 'desktop header theme toggle must be hidden below the desktop breakpoint'
grep -Fq "theme === 'dark' ? <SunIcon" "$HEADER" || \
	fail 'desktop header theme toggle must switch between sun and moon icons'
grep -Fq "onToggleTheme={() => setTheme((current) => (current === 'dark' ? 'light' : 'dark'))}" "$APP_SHELL" || \
	fail 'AppShell must wire the desktop header theme action'
[ "$(grep -Fc 'onRefresh={onRefresh}' "$APP_SHELL")" -eq 2 ] || \
	fail 'AppShell must wire refresh actions into both mobile navigation and desktop header'
grep -Fq 'loading={loading}' "$APP_SHELL" || \
	fail 'AppShell must pass loading state to mobile refresh control'
grep -Fq 'refreshing={refreshing}' "$APP_SHELL" || \
	fail 'AppShell must pass refreshing state to mobile refresh control'
[ "$(grep -Fc 'aria-label={`${themeLabel}로 전환`}' "$NAVIGATION")" -eq 1 ] || \
	fail 'theme action must not remain duplicated inside sidebar or mobile drawer menus'
[ "$(grep -Fc 'onClick={onRefresh}' "$HEADER")" -eq 1 ] || \
	fail 'desktop product header must expose exactly one refresh action'
grep -Fq 'class={`ssh-product-header-action hidden h-10 w-10 shrink-0 items-center justify-center rounded-xl' "$HEADER" || \
	fail 'desktop refresh action must use the Cloud Console-sized header button'
grep -Fq 'ReloadIcon class="size-5"' "$HEADER" || \
	fail 'desktop refresh action must use the Cloud Console-sized reload icon while idle'
grep -Fq 'ReloadIcon class="size-5 animate-spin"' "$HEADER" || \
	fail 'desktop refresh action must spin the Cloud Console-sized reload icon while refreshing'
grep -Fq 'text-[0.68rem] font-extrabold uppercase tracking-[0.18em] text-teal-700' "$HEADER" || \
	fail '72px desktop header must retain the SmartSafeHub eyebrow hierarchy'
grep -Fq 'text-xl font-black tracking-tight text-slate-950 sm:text-2xl' "$HEADER" || \
	fail '72px desktop header must retain the strong page-title hierarchy'
grep -Fq 'class="flex min-h-16 items-center justify-between gap-3"' "$NAVIGATION" || \
	fail 'mobile navigation height must remain unchanged while desktop header height is compacted'
if grep -Fq '<span class="hidden sm:inline">' "$HEADER"; then
	fail 'desktop refresh action must not restore a visible text label'
fi
[ "$(grep -Fc 'onClick={onRefresh}' "$NAVIGATION")" -eq 1 ] || \
	fail 'mobile top navigation must expose exactly one refresh action'
grep -Fq 'disabled={loading || refreshing}' "$NAVIGATION" || \
	fail 'mobile refresh action must prevent duplicate requests while loading or refreshing'
grep -Fq 'ReloadIcon class="size-5"' "$NAVIGATION" || \
	fail 'mobile refresh action must use the dedicated reload icon while idle'
grep -Fq 'ReloadIcon class="size-5 animate-spin"' "$NAVIGATION" || \
	fail 'mobile refresh action must spin the shared reload icon while refreshing'
theme_action_line="$(grep -n 'onClick={onToggleTheme}' "$NAVIGATION" | cut -d: -f1)"
refresh_action_line="$(grep -n 'onClick={onRefresh}' "$NAVIGATION" | cut -d: -f1)"
menu_action_line="$(grep -n 'aria-controls="smartsafehub-mobile-menu"' "$NAVIGATION" | head -n 1 | cut -d: -f1)"
[ "$theme_action_line" -lt "$refresh_action_line" ] && [ "$refresh_action_line" -lt "$menu_action_line" ] || \
	fail 'mobile header actions must remain ordered as theme, refresh, then hamburger menu'
grep -Fq 'class="ssh-mobile-navigation' "$NAVIGATION" || \
	fail 'mobile navigation drawer must remain available'


ROUTES="$ROOT_DIR/frontend/src/app/routes.ts"
HASH_ROUTE="$ROOT_DIR/frontend/src/hooks/useHashRoute.ts"

grep -Fq "{ label: 'Network', routes: ['lan', 'wifi', 'iptv', 'devices'] }" "$NAVIGATION" || \
	fail 'Network navigation group must place LAN before Wi-Fi and connected devices'
grep -Fq "route: 'lan'" "$ROUTES" || \
	fail 'LAN route must be registered'
grep -Fq "hash: '#lan'" "$ROUTES" || \
	fail 'LAN route must expose the #lan hash'
grep -Fq "'#lan': 'lan'" "$HASH_ROUTE" || \
	fail 'hash router must resolve #lan'
grep -Fq "{ label: 'System', routes: ['system', 'settings'] }" "$NAVIGATION" || \
	fail 'System navigation group must place settings directly below updates'
grep -Fq "case 'settings':" "$NAVIGATION" || \
	fail 'settings navigation item must have a dedicated icon'
grep -Fq "route: 'settings'" "$ROUTES" || \
	fail 'settings route must be registered'
grep -Fq "hash: '#settings'" "$ROUTES" || \
	fail 'settings route must expose the #settings hash'
grep -Fq "'#settings': 'settings'" "$HASH_ROUTE" || \
	fail 'hash router must resolve #settings'
if grep -Fq "href={luciAdminUrl('/admin/system')}" "$NAVIGATION"; then
	fail 'sidebar/mobile navigation must not expose a direct LuCI advanced-settings link'
fi

grep -Fq 'export function PanelLeftCloseIcon' "$ICONS" || \
	fail 'collapsed navigation must provide a collapse icon'
grep -Fq 'export function PanelLeftOpenIcon' "$ICONS" || \
	fail 'collapsed navigation must provide an expand icon'
grep -Fq '<path d="m15 18-6-6 6-6" />' "$ICONS" || \
	fail 'sidebar collapse icon must use the shared left-chevron path'
grep -Fq '<path d="m9 18 6-6-6-6" />' "$ICONS" || \
	fail 'sidebar expand icon must use the shared right-chevron path'
if grep -Fq '<rect height="18" rx="2" width="18" x="3" y="3" />' "$ICONS"; then
	fail 'sidebar toggle icons must not keep the legacy panel outline'
fi
grep -Fq '<PanelLeftOpenIcon class="size-4" />' "$NAVIGATION" || \
	fail 'sidebar expand icon must use the shared toggle icon size'
grep -Fq '<PanelLeftCloseIcon class="size-4" />' "$NAVIGATION" || \
	fail 'sidebar collapse icon must use the shared toggle icon size'
grep -Fq 'export function MoonIcon' "$ICONS" || fail 'dark mode must provide a moon icon'
grep -Fq 'export function SunIcon' "$ICONS" || fail 'dark mode must provide a sun icon'
grep -Fq 'export function ReloadIcon' "$ICONS" || fail 'header refresh must provide a dedicated reload icon'
if grep -Fq 'export function LoaderIcon' "$ICONS" || grep -Fq 'export function RefreshIcon' "$ICONS"; then
	fail 'refresh/loading states must not keep legacy spinner or refresh icon variants'
fi

grep -Fq '.ssh-product-header-action {' "$STYLES" || \
	fail 'desktop header actions must provide an explicit light-theme border color'
grep -Fq 'border-color: #e2e8f0 !important;' "$STYLES" || \
	fail 'light desktop header border must match Cloud Console slate-200'
grep -Fq '.ssh-product-header-action:hover {' "$STYLES" || \
	fail 'desktop header actions must provide an explicit light hover border color'
grep -Fq 'border-color: #5eead4 !important;' "$STYLES" || \
	fail 'light desktop header hover border must match Cloud Console teal-300'
grep -Fq ".ssh-app[data-theme='dark'] .ssh-product-header-action" "$STYLES" || \
	fail 'desktop header actions must provide a dark-theme border color'
grep -Fq 'border-color: #334155 !important;' "$STYLES" || \
	fail 'dark desktop header border must match Cloud Console slate-700'
grep -Fq 'border-color: #0f766e !important;' "$STYLES" || \
	fail 'dark desktop header hover border must match Cloud Console teal-700'
grep -Fq '.ssh-sidebar-toggle {' "$STYLES" || \
	fail 'sidebar toggle must use a dedicated low-emphasis style'
grep -Fq ".ssh-app[data-theme='dark'] .ssh-sidebar-toggle" "$STYLES" || \
	fail 'sidebar toggle must provide a dark-theme style'
grep -Fq ".ssh-app[data-theme='dark']" "$STYLES" || \
	fail 'authenticated application must provide dark theme styles'
[ "$(grep -Fc 'ssh-product-header-action' "$HEADER")" -eq 2 ] || \
	fail 'desktop product header must use the shared Cloud Console-style action class for theme and refresh'
grep -Fq ".ssh-app[data-theme='dark'] .ssh-product-header-action {" "$STYLES" || \
	fail 'desktop header actions must provide an explicit dark-theme surface contract'
grep -A4 -F ".ssh-app[data-theme='dark'] .ssh-product-header-action {" "$STYLES" | grep -Fq 'border-color: #334155 !important;' || \
	fail 'desktop header actions must keep the Cloud Console slate-700 border in dark mode'

# The exact-root uHTTPd rewrite keeps the browser on the same document URL, so
# hash routing should rely on the browser fragment directly instead of maintaining
# a second route state in sessionStorage.
if grep -Fq 'sessionStorage' "$HASH_ROUTE" || grep -Fq 'smartsafehub.route.hash' "$HASH_ROUTE"; then
	fail 'hash navigation must not duplicate route state in sessionStorage'
fi
grep -Fq 'HASH_ROUTES[window.location.hash]' "$HASH_ROUTE" || \
	fail 'hash router must resolve the current browser fragment directly'
grep -Fq "window.addEventListener('hashchange', handleChange);" "$HASH_ROUTE" || \
	fail 'hash router must react to browser hashchange events'


echo 'PASS: collapsible sidebar, header theme actions, dark theme and direct hash routing contracts are present'
