#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEMO="$ROOT/frontend/src/demo/main.tsx"
FIXTURES="$ROOT/frontend/src/demo/data.ts"
CONFIG="$ROOT/frontend/vite.demo.config.ts"

for path in "$DEMO" "$FIXTURES" "$CONFIG"; do
  [ -f "$path" ] || { echo "missing demo source: $path" >&2; exit 1; }
done

grep -Fq "<HomePage" "$DEMO"
grep -Fq "<SafeShieldPage" "$DEMO"
grep -Fq "<ConnectedDevicesPage" "$DEMO"
for page in ActivityPage WanPage LanPage WifiPage SafeShieldRulesPage UpdatePage SmartSafeHubAccountPage AppsPage; do
  grep -Fq "<$page" "$DEMO"
done
grep -Fq "'rules', 'account', 'apps', 'system'" "$ROOT/frontend/src/app/routes.ts"
grep -Fq 'onDemoAction={readonlyNotice}' "$DEMO"
grep -Fq 'demoAccount, demoApps, demoAppsStatus, demoAppsMetrics' "$DEMO"
grep -Fq 'https://www.smartsafehub.com/router-demo/' "$ROOT/README.md"
grep -Fq "demo ? (" "$ROOT/frontend/src/pages/SmartSafeHubAccountPage.tsx"
grep -Fq "if (demo) {" "$ROOT/frontend/src/pages/AppsPage.tsx"
grep -Fq "if (action === 'remove') closeRemoveDialog();" "$ROOT/frontend/src/pages/AppsPage.tsx"
grep -Fq "demo ? (" "$ROOT/frontend/src/pages/AppsPage.tsx"
grep -Fq "demoAccount" "$FIXTURES"
grep -Fq "updateAvailable: true," "$FIXTURES" || {
  echo 'demo must show an App update badge' >&2
  exit 1
}
grep -Fq "'network-usage-monitor': 117760" "$FIXTURES" || {
  echo 'demo must provide an installed size for the network app' >&2
  exit 1
}
grep -Fq 'storage: demoAppsMetrics.storage' "$FIXTURES" || {
  echo 'dashboard and Apps demo storage must share one fixture' >&2
  exit 1
}
grep -Fq "demoApps" "$FIXTURES"
# Keep the public demo's Network Watch, first-party label and sample releases visible.
grep -Fq "case 'netwatch':" "$DEMO"
grep -Fq '<NetworkWatchPage data={demoNetwatch} devices={demoDevices} activity={demoActivity}' "$DEMO"
grep -Fq "'safeshield', 'netwatch', 'rules'" "$ROOT/frontend/src/components/ProductNavigation.tsx"
grep -Fq 'Network Watch' "$ROOT/docs/ROUTER_DEMO.md"
grep -Fq '실제 네트워크를 관찰하거나 차단하지 않으며' "$ROOT/docs/ROUTER_DEMO.md"
grep -Fq "version: '1.2.0-r4'" "$FIXTURES"
grep -Fq "version: '2.4.9-r6'" "$FIXTURES"
grep -Fq "demo={demo}" "$ROOT/frontend/src/components/AppShell.tsx"
grep -Fq "!demo ?" "$ROOT/frontend/src/components/ProductNavigation.tsx"
grep -Fq "base: '/static/router-demo/'" "$CONFIG"

# No fake bootstrap or real RPC in the public demo entry.
if grep -Eq 'callApi|callRpc|fetch\(|probeLuciSession|__SMARTHUB_BOOTSTRAP__|/cgi-bin/' "$DEMO" "$FIXTURES"; then
  echo 'Public demo must not call any router APIs' >&2
  exit 1
fi

# tests/runtime/router-demo.test.mjs runs in the frontend CI job alongside
# the other behavioral runtime tests; keep ShellSpec's source contracts here.
# The Hub consumes a committed, separately built bundle. New developers build
# it locally, then commit the output; this test does not generate build files.
if grep -q '^frontend/demo-dist/$' "$ROOT/.gitignore"; then
  echo 'Demo build output must be committed, not ignored' >&2
  exit 1
fi
grep -Fq 'Build standalone router demo' "$ROOT/.github/workflows/ci.yml"
grep -Fq 'Validate committed router demo assets' "$ROOT/.github/workflows/ci.yml"

printf "%s\n" "PASS: router demo contract"
