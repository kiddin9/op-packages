#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ROUTES="$ROOT/frontend/src/app/routes.ts"
NAV="$ROOT/frontend/src/components/ProductNavigation.tsx"
UCODE="$ROOT/root/usr/share/rpcd/ucode/smartsafehub/apps.uc"
RPC="$ROOT/root/usr/share/rpcd/ucode/smartsafehub.uc"
HELPER="$ROOT/root/usr/libexec/smartsafehub-apps"
ACL="$ROOT/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
for file in "$ROUTES" "$NAV" "$UCODE" "$RPC" "$HELPER" "$ACL" \
  "$ROOT/frontend/src/pages/AppsPage.tsx" "$ROOT/frontend/src/types/apps.ts"; do
 [ -f "$file" ] || fail "missing ${file##*/}"
done
[ -x "$HELPER" ] || fail 'helper not executable'
sh -n "$HELPER" || fail 'invalid helper shell syntax'
python3 - "$ROUTES" "$NAV" "$ROOT/frontend/src/hooks/useHashRoute.ts" <<'PY' || exit 1
from pathlib import Path
import sys
routes, nav, hash_route = map(lambda p: Path(p).read_text(), sys.argv[1:])
assert "route: 'apps'" in routes and "hash: '#apps'" in routes
assert routes.index("route: 'account'") < routes.index("route: 'apps'") < routes.index("route: 'system'")
assert "{ label: 'Explore', routes: ['apps'] }" in nav
assert "{ label: 'System', routes: ['account', 'system', 'settings'] }" in nav
assert "case 'apps':" in nav and '<AppsIcon' in nav
assert "return '앱으로 확장하기';" in nav
assert "'#apps': 'apps'" in hash_route
PY

grep -Fq 'apps_catalog: {' "$RPC" || fail 'RPC method missing'
grep -Fq 'require_root_password(function(request)' "$RPC" || fail 'RPC password guard missing'
grep -Fq '"apps_catalog"' "$ACL" || fail 'read permission missing'
grep -Fq "'apps_catalog'" "$ROOT/frontend/src/api/smartsafehub.ts" || fail 'frontend RPC missing'
grep -Fq "active: route === 'apps'" "$ROOT/frontend/src/app/App.tsx" || fail 'catalog must be loaded only on Apps route'
# Apps must follow the existing Recent Activity section spacing contract.
# A tall refresh action next to the title pushes the entire heading and card
# down on desktop; keep that control inside the card instead.
python3 - "$ROOT/frontend/src/pages/AppsPage.tsx" "$ROOT/frontend/src/pages/ActivityPage.tsx" <<'PY' || fail 'Apps layout differs from shared section design'
from pathlib import Path
import sys
apps, activity = (Path(path).read_text() for path in sys.argv[1:])
assert '<div class="min-w-0 space-y-6">' in activity
assert '<section class="min-w-0 space-y-6">' in apps
heading = apps.split('<SectionHeading', 1)[1].split('/>', 1)[0]
assert 'action=' not in heading, 'refresh action changes heading height'
card = apps.split('/>', 1)[1].split('{error ?', 1)[0]
assert 'p-4 shadow-sm shadow-slate-900/5 sm:p-5' in card, 'card padding differs from Activity'
assert '목록 새로고침' in card, 'refresh action must be within card'
assert 'disabled={loading || refreshing}' in card, 'refresh loading guard missing'
PY
grep -Fq "item.runtime != 'router' || item.installer != 'apk'" "$UCODE" || fail 'unknown runtimes must stay hidden'
# Separate the privileged APK adapter from display-only Hub catalog parsing.
MANAGER="$ROOT/root/usr/libexec/smartsafehub-apps-manager"
MODULE="$ROOT/root/usr/share/rpcd/ucode/smartsafehub/apps-manager.uc"
[ -x "$MANAGER" ] || fail 'APK manager missing or not executable'
[ -f "$MODULE" ] || fail 'APK RPC adapter missing'
sh -n "$MANAGER" || fail 'APK manager shell syntax invalid'
grep -Fq 'apps_install: {' "$RPC" || fail 'Apps install RPC missing'
grep -Fq 'apps_update: {' "$RPC" || fail 'Apps update RPC missing'
grep -Fq 'apps_remove: {' "$RPC" || fail 'Apps remove RPC missing'
grep -Fq 'apps_status: {' "$RPC" || fail 'Apps status RPC missing'
grep -Fq '"apps_install"' "$ACL" || fail 'Apps install ACL missing'
grep -Fq '"apps_update"' "$ACL" || fail 'Apps update ACL missing'
grep -Fq '"apps_remove"' "$ACL" || fail 'Apps remove ACL missing'
grep -Fq '"apps_status"' "$ACL" || fail 'Apps status ACL missing'
grep -Fq '"apps_metrics"' "$ACL" || fail 'Apps metrics read ACL missing'
grep -Fq 'updateVerifiedApp' "$ROOT/frontend/src/api/smartsafehub.ts" || fail 'Apps frontend update call missing'
grep -Fq 'installVerifiedApp' "$ROOT/frontend/src/api/smartsafehub.ts" || fail 'Apps frontend installation call missing'
# 다크 모드에서 앱 작업 상태 텍스트가 어둡게 남지 않도록 색상 매핑을 확인한다.
python3 - "$ROOT/frontend/src/pages/AppsPage.tsx" "$ROOT/frontend/src/styles/app.css" <<'PY_APPS_THEME' || fail 'Apps 작업 상태 다크 모드 계약이 올바르지 않습니다'
from pathlib import Path
import sys

page, styles = (Path(file).read_text() for file in sys.argv[1:])
assert "'border-teal-200 bg-teal-50 text-teal-900'" in page
assert "'border-rose-200 bg-rose-50 text-rose-800'" in page
assert "[class~='text-teal-900']" in styles
assert "[class~='text-rose-800']" in styles
PY_APPS_THEME
# Apps RPC 인자가 rpcd의 request.args 아래로 전달되는지 검사한다.
# request.app_id는 항상 빈 값이어서 패키지 작업 시작 전에 APPS_INVALID_ID가 발생한다.
python3 - "$RPC" "$MODULE" "$ROOT/frontend/src/api/smartsafehub.ts" <<'PY_RPC' || fail 'Apps RPC 인자 전달 계약이 올바르지 않습니다'
from pathlib import Path
import re
import sys

rpc, adapter, frontend = (Path(path).read_text() for path in sys.argv[1:])
for action in ('install', 'remove'):
    method = f'apps_{action}'
    assert re.search(rf'{method}:\s*\{{\s*args:\s*\{{\s*app_id:\s*', rpc), method
    assert f"'{method}', {{ app_id: appId }}" in frontend, method
assert 'const app_id = request?.args?.app_id;' in adapter
assert 'const app_id = request?.app_id;' not in adapter
assert 'match(app_id, /^[a-z0-9][a-z0-9-]{0,79}$/)' in adapter
assert "run_command([ MANAGER, 'start', action, app_id ], 5000)" in adapter
PY_RPC

# Fake only the HTTP/JSON filter utilities: no external calls or OpenWrt runtime
# are needed to verify identity pinning and mismatch/failure handling.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/runtime"
cat > "$TMP/firmware.json" <<'EOF'
{"device_code":"iptime-ax3000sm","build_id":"2026.10.20-123","channel":"stable"}
EOF
cat > "$TMP/response.json" <<'EOF'
{"schema":1,"device_code":"iptime-ax3000sm","firmware_build_id":"2026.10.20-123","channel":"stable","apps":[]}
EOF
cat > "$TMP/bin/jsonfilter" <<'PY'
#!/usr/bin/env python3
import json,sys
args=sys.argv
obj=json.load(open(args[args.index('-i')+1],encoding='utf-8'))
for key in args[args.index('-e')+1].removeprefix('@.').split('.'):
    obj=obj[key]
print(obj if not isinstance(obj,bool) else str(obj).lower())
PY
cat > "$TMP/bin/uclient-fetch" <<'SH2'
#!/bin/sh
[ "${APPS_TEST_FAIL:-0}" = 0 ] || exit 1
while [ "$#" -gt 0 ]; do
 case "$1" in -O) dest="$2"; shift 2;; *) url="$1"; shift;; esac
done
printf '%s\n' "$url" > "$APPS_TEST_URL_FILE"
cp "$APPS_TEST_RESPONSE" "$dest"
SH2
chmod +x "$TMP/bin/jsonfilter" "$TMP/bin/uclient-fetch"
export SMARTSAFEHUB_APPS_ROM_METADATA="$TMP/firmware.json"
export SMARTSAFEHUB_APPS_METADATA="$TMP/firmware.json"
export SMARTSAFEHUB_APPS_RUNTIME_DIR="$TMP/runtime"
export SMARTSAFEHUB_APPS_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export SMARTSAFEHUB_APPS_UCLIENT_BIN="$TMP/bin/uclient-fetch"
export APPS_TEST_RESPONSE="$TMP/response.json"
export APPS_TEST_URL_FILE="$TMP/url"
"$HELPER" || fail 'valid pinned catalog fetch failed'
grep -Fq 'firmware_build_id=2026.10.20-123&channel=stable' "$TMP/url" || fail 'local identity missing in request'
grep -Fq '"apps":[]' "$TMP/runtime/apps-catalog.json" || fail 'catalog not stored'

# Wrong firmware builds must never be treated as approved.
sed 's/2026.10.20-123/2026.10.20-999/' "$TMP/response.json" > "$TMP/mismatch.json"
export APPS_TEST_RESPONSE="$TMP/mismatch.json"
if "$HELPER"; then fail 'mismatched firmware catalog accepted'; fi
export APPS_TEST_FAIL=1
if "$HELPER"; then fail 'offline catalog fetch accepted'; fi
unset APPS_TEST_FAIL
cat > "$TMP/firmware.json" <<'EOF'
{"device_code":"iptime-ax3000sm","build_id":"../../bad","channel":"stable"}
EOF
if "$HELPER"; then fail 'invalid firmware identity accepted'; fi
printf 'PASS: Apps navigation, catalog pinning and APK RPC contracts\n'
