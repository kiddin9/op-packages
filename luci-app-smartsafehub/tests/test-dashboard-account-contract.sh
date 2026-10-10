#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app=frontend/src/app/App.tsx
home=frontend/src/pages/HomePage.tsx
nav=frontend/src/components/ProductNavigation.tsx
shell=frontend/src/components/AppShell.tsx
hook=frontend/src/hooks/useDashboardAccountStatus.ts
api=frontend/src/api/smartsafehub.ts

grep -Fq 'useDashboardAccountStatus(' "$app" || { echo 'FAIL: dashboard account status hook missing' >&2; exit 1; }
grep -Fq 'deviceRegistration.data?.accountRegistered ?? null' "$app" || { echo 'FAIL: account page state must be shared with the sidebar immediately' >&2; exit 1; }
grep -Fq 'accountRoute && accountPageRegistered !== null' "$hook" || { echo 'FAIL: sidebar must reflect account page connection status immediately' >&2; exit 1; }
grep -Fq 'accountRegistered={dashboardAccountRegistered}' "$app" || { echo 'FAIL: missing account state prop' >&2; exit 1; }
grep -Fq 'accountRegistered === false' "$home" || { echo 'FAIL: missing explicit disconnected guard' >&2; exit 1; }
grep -Fq 'href="#account"' "$home" || { echo 'FAIL: missing account page link' >&2; exit 1; }
grep -Fq 'fetchDeviceRegistrationStatus()' "$hook" || { echo 'FAIL: local status fetch missing' >&2; exit 1; }
if grep -Eq 'refreshDeviceRegistrationStatus|requestDevicePairingCode' "$hook"; then
  echo 'FAIL: dashboard must not synchronize with Hub' >&2
  exit 1
fi
grep -Fq "'device_registration_status'" "$api" || { echo 'FAIL: local RPC missing' >&2; exit 1; }
styles=frontend/src/styles/app.css
for name in ssh-dashboard-account-banner ssh-dashboard-account-banner-icon ssh-dashboard-account-banner-title ssh-dashboard-account-banner-description ssh-dashboard-account-banner-badge ssh-dashboard-account-banner-action; do
  grep -Fq "$name" "$home" || { echo "FAIL: missing themed dashboard account element $name" >&2; exit 1; }
  grep -Fq ".$name" "$styles" || { echo "FAIL: missing theme CSS for $name" >&2; exit 1; }
done
grep -Fq ".ssh-app[data-theme='dark'] .ssh-dashboard-account-banner" "$styles" || { echo 'FAIL: dark-mode account banner colors missing' >&2; exit 1; }
if grep 'ssh-dashboard-account-banner ' "$home" | grep -Eq 'dark:|bg-teal-50|border-teal-200'; then
  echo 'FAIL: mixed Tailwind theme utilities on account banner' >&2
  exit 1
fi
grep -Fq 'accountRegistered={accountRegistered}' "$shell" || { echo 'FAIL: shell must pass registration state to navigation' >&2; exit 1; }
grep -Fq "routeName === 'account' && accountRegistered === false" "$nav" || { echo 'FAIL: dot must appear only when disconnected' >&2; exit 1; }
grep -Fq 'ssh-account-nav-dot-collapsed' "$nav" || { echo 'FAIL: collapsed navigation dot missing' >&2; exit 1; }
grep -Fq '`${item.label} (계정 연결 필요)`' "$nav" || { echo 'FAIL: missing accessible account state on navigation link' >&2; exit 1; }
grep -Fq '.ssh-app[data-theme='"'"'dark'"'"'] .ssh-account-nav-dot' "$styles" || { echo 'FAIL: dark dot style missing' >&2; exit 1; }
# A tiny dot requires a stronger solid amber than the Beta badge's pale surface.
# Both themes must set a visible opaque fill without relying on Tailwind color utilities.
if grep 'ssh-account-nav-dot' "$nav" | grep -Fq 'bg-amber-100'; then
  echo 'FAIL: pale Beta background is insufficient for the account dot' >&2
  exit 1
fi
grep -Fq 'background-color: #d97706;' "$styles" || { echo 'FAIL: light theme account indicator must have an opaque amber fill' >&2; exit 1; }
grep -Fq 'background-color: #fbbf24;' "$styles" || { echo 'FAIL: dark theme account indicator must have a high-contrast amber fill' >&2; exit 1; }
grep -Fq 'width: 10px;' "$styles" || { echo 'FAIL: account indicator should be legible at normal sidebar scale' >&2; exit 1; }
echo 'PASS: account banner and navigation indicator use a single local status'
