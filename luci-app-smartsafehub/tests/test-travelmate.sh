#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys
root=Path(sys.argv[1])
demo=(root/'frontend/src/demo/data.ts').read_text()
# Scope each assertion to Travelmate; the demo also contains other Apps.
app = demo.split("      id: 'travelmate',", 1)[1].split("\n    },", 1)[0]
status = demo.split("    'travelmate': {", 1)[1].split("\n    },", 1)[0]
assert "webUi: null, // Demo never exposes actual LuCI administration routes." in app
assert "category: 'network'" in app
assert "installed: true" in status
assert "managed: true" in status
app_version = re.search(r"\bversion: '([^']+)'", app)
installed_version = re.search(r"\binstalledVersion: '([^']+)'", status)
assert app_version is not None and installed_version is not None
assert app_version.group(1) == installed_version.group(1)
assert "luci-app-travelmate" in (root/'docs/APPS.md').read_text()
assert "case 'network': return 'network'" in (root/'frontend/src/components/AppsCategoryIcon.tsx').read_text()
manager = (root/'root/usr/libexec/smartsafehub-apps-manager').read_text()
view = (root/'root/usr/share/rpcd/ucode/smartsafehub/apps.uc').read_text()
assert '[ "$id" = travelmate ]' in manager
assert 'firmware_prerequisite' in manager
assert 'approved_primary_package "$index"' in manager
assert 'travelmate_required_packages' not in manager
assert 'travelmate_pins_match_arch' not in manager
assert 'web_ui.path")" = /cgi-bin/luci/admin/services/travelmate' in manager
assert "id == 'travelmate'" in view
assert "item?.web_ui?.package == 'luci-app-travelmate'" in view
assert "item?.web_ui?.path == '/cgi-bin/luci/admin/services/travelmate'" in view
assert 'firmware_prerequisite' in manager
assert 'review_remove_plan' in manager
assert 'approved_primary_package' in manager
assert 'append_owned_pin "$name"' in manager
page=(root/'frontend/src/pages/AppsPage.tsx').read_text()
assert '이전에 직접 설치한 패키지는 Apps가 제거하지 않습니다.' in page
assert '다른 앱이나 공유기 기능에' in page
assert 'state?.partial && !managed' in page
PY
printf '%s\n' 'PASS: Travelmate Apps demo and catalog contract'

# Only Hub-signed pins and solver plans decide the allowed package set.
# A new dependency must not require a new router release; unexpected solver
# additions, removals and system upgrades remain forbidden.
MANAGER="$ROOT/root/usr/libexec/smartsafehub-apps-manager"
TMPDIR_TM="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMPDIR_TM"' EXIT HUP INT TERM
awk '/^review_install_plan\(\)/,/^}/' "$MANAGER" > "$TMPDIR_TM/functions"
awk '/^review_remove_plan\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
awk '/^review_update_plan\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
awk '/^shared_runtime_package\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
. "$TMPDIR_TM/functions"
for shared in libopenssl3 libatomic1 libfuture curl iwinfo rpcd-mod-rpcsys mosquitto-ssl mosquitto-client-ssl cJSON; do
 shared_runtime_package "$shared" || { echo "FAIL: 공용 런타임이 제거 대상으로 분류됨: $shared" >&2; exit 1; }
done
for owned in travelmate luci-app-travelmate etherwake nlbwmon new-signed-helper; do
 if shared_runtime_package "$owned"; then echo "FAIL: 앱 패키지가 공용 런타임으로 분류됨: $owned" >&2; exit 1; fi
done
printf '%s\n' '(1/3) Installing travelmate (signed)' \
  '(2/3) Installing luci-app-travelmate (signed)' \
  '(3/3) Installing new-approved-lib (signed)' > "$TMPDIR_TM/plan"
review_install_plan "$TMPDIR_TM/plan" 'travelmate luci-app-travelmate new-approved-lib' || exit 1
if review_install_plan "$TMPDIR_TM/plan" 'travelmate luci-app-travelmate'; then
 echo 'FAIL: unreviewed dependency installed' >&2; exit 1
fi
printf '%s\n' '(4/4) Upgrading rpcd (unexpected)' >> "$TMPDIR_TM/plan"
if review_install_plan "$TMPDIR_TM/plan" 'travelmate luci-app-travelmate new-approved-lib'; then
 echo 'FAIL: core package upgrade allowed' >&2; exit 1
fi
printf '%s\n' '(1/2) Purging travelmate (signed)' '(2/2) Purging luci-app-travelmate (signed)' > "$TMPDIR_TM/remove"
review_remove_plan "$TMPDIR_TM/remove" 'travelmate luci-app-travelmate' || exit 1
printf '%s\n' '(3/3) Purging rpcd-mod-rpcsys (unreviewed)' >> "$TMPDIR_TM/remove"
if review_remove_plan "$TMPDIR_TM/remove" 'travelmate luci-app-travelmate'; then
 echo 'FAIL: firmware dependency removed' >&2; exit 1
fi
printf '%s\n' '(1/2) Upgrading travelmate (signed)' '(2/2) Installing new-approved-lib (signed)' > "$TMPDIR_TM/update"
review_update_plan "$TMPDIR_TM/update" travelmate new-approved-lib || exit 1
if review_update_plan "$TMPDIR_TM/update" travelmate ''; then
 echo 'FAIL: unreviewed update dependency allowed' >&2; exit 1
fi
printf '%s\n' 'PASS: Travelmate generic signed dependency and solver contract'

# Exercise the actual status() implementation with a fake installed-package
# database. Shared dependencies surviving removal must NOT appear as a partial
# Travelmate install; interrupted owned installs must still be recoverable.
# status() also uses the production version validator and APK comparator.
awk '/^valid_version\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
awk '/^version_is_newer\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
awk '/^status\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
cat > "$TMPDIR_TM/apk" <<'SH_APK'
#!/bin/sh
[ "$#" -eq 4 ] && [ "$1" = version ] && [ "$2" = -t ] || exit 2
case "$3:$4" in
 '2.4.9-r5:2.4.9-r6') printf '%s\n' '<';;
 '2.4.9-r7:2.4.9-r6') printf '%s\n' '>';;
 '2.4.9-r6:2.4.9-r6') printf '%s\n' '=';;
 *) exit 2;;
esac
SH_APK
chmod +x "$TMPDIR_TM/apk"
cat > "$TMPDIR_TM/status-test.sh" <<'SH_STATUS'
#!/bin/sh
set -eu
. "$1"
RUNTIME="$2/runtime"
OWNED="$2/owned"
CATALOG="$2/catalog.json"
TM_INSTALLED="$2/installed"
TM_PKG_NAMES="$2/packages"
APK="$2/apk"
TM_INSTALLED_VERSION=2.4.9-r5
TM_APPROVED_VERSION=2.4.9-r6
mkdir -p "$RUNTIME" "$OWNED"
: > "$CATALOG"
: > "$TM_INSTALLED"
printf '%s\n' 'travelmate' 'luci-app-travelmate' \
  'curl' 'libcurl4' 'libnghttp2-14' 'iwinfo' \
  'rpcd-mod-rpcsys' 'libopenssl3' > "$TM_PKG_NAMES"
fail_status() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
catalog_ids() { printf '%s\n' travelmate; }
valid_id() { return 0; }
valid_package() { return 0; }
owned_manifest() { printf '%s/%s' "$OWNED" "$1"; }
installed() { grep -Fxq "$1" "$TM_INSTALLED"; }
installed_version() { printf '%s\n' "$TM_INSTALLED_VERSION"; }
web_ui_package() { printf '%s\n' luci-app-travelmate; }
extract_pins() { return 1; }
select_upgrades() { return 1; }
field() {
 case "$2" in
  '@.apps[0].package_arch') printf '%s\n' aarch64_cortex-a53;;
  '@.apps[0].packages['*'].version') printf '%s\n' "$TM_APPROVED_VERSION";;
  '@.apps[0].packages['*'].name')
   index="${2#*.packages[}"
   index="${index%%]*}"
   sed -n "$((index + 1))p" "$TM_PKG_NAMES";;
 esac
}
assert_status() {
 status || fail_status 'status command failed'
 actual="$(awk -F '\t' '{print $2 ":" $3 ":" $4}' "$RUNTIME/apps-status.tsv")"
 [ "$actual" = "$1" ] || fail_status "$2: expected $1, got $actual"
}
# No installed packages and no ownership.
assert_status '0:0:0' 'fresh app'
# APKs deliberately preserved by remove_app() are not an app installation.
for dep in curl libcurl4 libnghttp2-14 iwinfo rpcd-mod-rpcsys libopenssl3; do
 printf '%s\n' "$dep" >> "$TM_INSTALLED"
done
assert_status '0:0:0' 'shared dependencies remain after app removal'
# A genuinely partial manual install cannot be silently adopted by Apps.
printf '%s\n' travelmate >> "$TM_INSTALLED"
assert_status '0:1:0' 'manually installed Travelmate remains partial'
sed '/^travelmate$/d' "$TM_INSTALLED" > "$TM_INSTALLED.tmp"
mv -f "$TM_INSTALLED.tmp" "$TM_INSTALLED"
printf '%s\n' luci-app-travelmate >> "$TM_INSTALLED"
assert_status '0:1:0' 'manually installed LuCI component remains partial'
sed '/^luci-app-travelmate$/d' "$TM_INSTALLED" > "$TM_INSTALLED.tmp"
mv -f "$TM_INSTALLED.tmp" "$TM_INSTALLED"
# An unfinished Apps-owned transaction must retain its repair action.
printf '%s\n' 'travelmate 2.4.9-r6 test-hash' > "$OWNED/travelmate"
assert_status '0:1:1' 'owned interrupted install remains repairable'
rm -f "$OWNED/travelmate"
# Full installation remains fully installed and is never reclassified.
printf '%s\n' travelmate luci-app-travelmate >> "$TM_INSTALLED"
assert_status '1:1:0' 'fully present app not classified as removed'
printf '%s\n' 'travelmate 2.4.9-r6 test-hash' > "$OWNED/travelmate"
assert_status '1:1:1' 'fully Apps-managed app not classified as removed'
# A rejected upgrade only needs a review explanation for a newer approved APK.
assert_review_reason() {
 actual_reason="$(awk -F '\t' '{print $9}' "$RUNTIME/apps-status.tsv")"
 [ "$actual_reason" = "$1" ] || fail_status "$2: expected reason '$1', got '$actual_reason'"
}
assert_review_reason review_required 'newer approved APK with rejected update plan'
TM_INSTALLED_VERSION=2.4.9-r6
assert_status '1:1:1' 'equal approved version remains installed'
assert_review_reason '' 'equal approved version'
TM_INSTALLED_VERSION=2.4.9-r7
assert_status '1:1:1' 'newer local version remains installed'
assert_review_reason '' 'older approved version'
TM_INSTALLED_VERSION=2.4.9-r5
TM_APPROVED_VERSION=''
assert_status '1:1:1' 'missing approved version remains installed'
assert_review_reason '' 'missing approved version'
printf '%s\n' 'PASS: Travelmate removal retains shared packages without confusing install status'
printf '%s\n' 'PASS: Travelmate update review reason uses the approved APK version'
SH_STATUS
sh "$TMPDIR_TM/status-test.sh" "$TMPDIR_TM/functions" "$TMPDIR_TM"
