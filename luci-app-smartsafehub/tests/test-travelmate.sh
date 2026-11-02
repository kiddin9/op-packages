#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
demo=(root/'frontend/src/demo/data.ts').read_text()
assert "id: 'travelmate'" in demo
assert "version: '2.4.9-r6'" in demo
assert "webUi: null, // Demo never exposes actual LuCI administration routes." in demo
assert "'travelmate': {" in demo
assert "installed: false" in demo
assert "category: 'network'" in demo
assert "luci-app-travelmate" in (root/'docs/APPS.md').read_text()
assert "case 'network': return 'network'" in (root/'frontend/src/components/AppsCategoryIcon.tsx').read_text()
manager = (root/'root/usr/libexec/smartsafehub-apps-manager').read_text()
view = (root/'root/usr/share/rpcd/ucode/smartsafehub/apps.uc').read_text()
assert '[ "$id" = travelmate ]' in manager
assert '[ "$app" = travelmate ]' in manager
assert 'travelmate_pins_match_arch "$arch" "$pins"' in manager
assert 'libopenssl3 libatomic1' in manager
assert 'reviewed_arch=' in manager
assert 'primary_package=luci-app-travelmate' in manager
assert 'web_ui.path")" = /cgi-bin/luci/admin/services/travelmate' in manager
assert "id == 'travelmate'" in view
assert "item?.web_ui?.package == 'luci-app-travelmate'" in view
assert "item?.web_ui?.path == '/cgi-bin/luci/admin/services/travelmate'" in view
assert 'shared_travelmate_dep' in manager
assert 'rpcd-mod-rpcsys|libopenssl3|libatomic1' in manager
assert 'shared_travelmate_dep "$name" && return 42' in manager
assert 'app="$id" # Status checks' in manager
assert 'append_owned_pin "$name"' in manager
page=(root/'frontend/src/pages/AppsPage.tsx').read_text()
assert "removeTarget.id === 'travelmate'" in page
assert '공용 패키지는 안전을 위해 유지됩니다.' in page
assert 'state?.partial && !managed' in page
PY
printf '%s\n' 'PASS: Travelmate Apps demo and catalog contract'

# Exercise the exact APK transaction-plan validators, not only static labels.
# Both exact reviewed dependency sets are accepted; core upgrades,
# missing prerequisites, wrong-architecture pins and auto-removal fail closed.
MANAGER="$ROOT/root/usr/libexec/smartsafehub-apps-manager"
TMPDIR_TM="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMPDIR_TM"' EXIT HUP INT TERM
awk '/^travelmate_required_packages\(\)/,/^}/' "$MANAGER" > "$TMPDIR_TM/functions"
awk '/^travelmate_pins_match_arch\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
awk '/^shared_travelmate_dep\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
awk '/^review_install_plan\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
awk '/^review_remove_plan\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
# shellcheck source=/dev/null
. "$TMPDIR_TM/functions"
AARCH="$(travelmate_required_packages aarch64_cortex-a53)" || exit 1
[ "$(travelmate_required_packages x86_64)" = "$AARCH" ] || { echo 'FAIL: x86 package set differs' >&2; exit 1; }
MIPS="$(travelmate_required_packages mipsel_24kc)" || exit 1
if travelmate_required_packages mipsel >/dev/null; then
 echo 'FAIL: unknown feed architecture accepted' >&2; exit 1
fi
# Exercise the exact preflight validator on pinned TSV files.
: > "$TMPDIR_TM/aarch-pins"
for name in $AARCH; do
 printf '%s\t%s\t%s\n' "$name" '1-r1' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' >> "$TMPDIR_TM/aarch-pins"
done
travelmate_pins_match_arch aarch64_cortex-a53 "$TMPDIR_TM/aarch-pins" || { echo 'FAIL: approved aarch pins rejected' >&2; exit 1; }
if travelmate_pins_match_arch mipsel_24kc "$TMPDIR_TM/aarch-pins"; then
 echo 'FAIL: incomplete MIPS pins accepted' >&2; exit 1
fi
cp "$TMPDIR_TM/aarch-pins" "$TMPDIR_TM/mips-pins"
printf 'libatomic1\t14.3.0-r5\t%s\n' 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' >> "$TMPDIR_TM/mips-pins"
travelmate_pins_match_arch mipsel_24kc "$TMPDIR_TM/mips-pins" || { echo 'FAIL: approved MIPS pins rejected' >&2; exit 1; }
if travelmate_pins_match_arch x86_64 "$TMPDIR_TM/mips-pins"; then
 echo 'FAIL: MIPS-only pin accepted on x86' >&2; exit 1
fi
grep -v '^libopenssl3[[:space:]]' "$TMPDIR_TM/aarch-pins" > "$TMPDIR_TM/missing-pins"
if travelmate_pins_match_arch aarch64_cortex-a53 "$TMPDIR_TM/missing-pins"; then
 echo 'FAIL: missing OpenSSL pin accepted' >&2; exit 1
fi
app=travelmate
shared_travelmate_dep libopenssl3 || { echo 'FAIL: OpenSSL is not protected' >&2; exit 1; }
shared_travelmate_dep libatomic1 || { echo 'FAIL: libatomic is not protected' >&2; exit 1; }
if shared_travelmate_dep travelmate; then
 echo 'FAIL: application package marked shared' >&2; exit 1
fi
printf '%s\n' \
 '(1/8) Installing curl (signed)' \
 '(2/8) Installing libcurl4 (signed)' \
 '(3/8) Installing libnghttp2-14 (signed)' \
 '(4/8) Installing iwinfo (signed)' \
 '(5/8) Installing rpcd-mod-rpcsys (signed)' \
 '(6/8) Installing libopenssl3 (signed)' \
 '(7/8) Installing travelmate (signed)' \
 '(8/8) Installing luci-app-travelmate (signed)' > "$TMPDIR_TM/plan"
review_install_plan "$TMPDIR_TM/plan" "$AARCH" || { echo 'FAIL: signed aarch/x86 plan rejected' >&2; exit 1; }
if review_install_plan "$TMPDIR_TM/plan" "$MIPS"; then
 echo 'FAIL: missing MIPS libatomic accepted' >&2; exit 1
fi
printf '%s\n' '(9/9) Installing libatomic1 (signed)' >> "$TMPDIR_TM/plan"
review_install_plan "$TMPDIR_TM/plan" "$MIPS" || { echo 'FAIL: signed MIPS plan rejected' >&2; exit 1; }
if review_install_plan "$TMPDIR_TM/plan" "$AARCH"; then
 echo 'FAIL: unexpected libatomic on aarch accepted' >&2; exit 1
fi
printf '%s\n' '(10/10) Upgrading rpcd (unapproved)' >> "$TMPDIR_TM/plan"
if review_install_plan "$TMPDIR_TM/plan" "$MIPS"; then
 echo 'FAIL: core RPC upgrade accepted' >&2; exit 1
fi
sed '/Installing libopenssl3 /d; /Upgrading rpcd /d' "$TMPDIR_TM/plan" > "$TMPDIR_TM/missing"
if review_install_plan "$TMPDIR_TM/missing" "$MIPS"; then
 echo 'FAIL: incomplete OpenSSL dependency plan accepted' >&2; exit 1
fi
printf '%s\n' '(1/2) Purging travelmate (test)' '(2/2) Purging luci-app-travelmate (test)' > "$TMPDIR_TM/remove"
review_remove_plan "$TMPDIR_TM/remove" 'travelmate luci-app-travelmate' || { echo 'FAIL: app-only removal rejected' >&2; exit 1; }
printf '%s\n' '(3/3) Purging rpcd-mod-rpcsys (test)' >> "$TMPDIR_TM/remove"
if review_remove_plan "$TMPDIR_TM/remove" 'travelmate luci-app-travelmate'; then
 echo 'FAIL: shared RPC package removal accepted' >&2; exit 1
fi
printf '%s\n' 'PASS: Travelmate signed dependencies and core package protection'

# Exercise the actual status() implementation with a fake installed-package
# database. Shared dependencies surviving removal must NOT appear as a partial
# Travelmate install; interrupted owned installs must still be recoverable.
awk '/^status\(\)/,/^}/' "$MANAGER" >> "$TMPDIR_TM/functions"
cat > "$TMPDIR_TM/status-test.sh" <<'SH_STATUS'
#!/bin/sh
set -eu
. "$1"
RUNTIME="$2/runtime"
OWNED="$2/owned"
CATALOG="$2/catalog.json"
TM_INSTALLED="$2/installed"
TM_PKG_NAMES="$2/packages"
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
valid_version() { return 0; }
owned_manifest() { printf '%s/%s' "$OWNED" "$1"; }
installed() { grep -Fxq "$1" "$TM_INSTALLED"; }
installed_version() { printf '%s\n' '2.4.9-r5'; }
web_ui_package() { printf '%s\n' luci-app-travelmate; }
extract_pins() { return 1; }
select_upgrades() { return 1; }
field() {
 case "$2" in
  '@.apps[0].package_arch') printf '%s\n' aarch64_cortex-a53;;
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
printf '%s\n' 'PASS: Travelmate removal retains shared packages without confusing install status'
SH_STATUS
sh "$TMPDIR_TM/status-test.sh" "$TMPDIR_TM/functions" "$TMPDIR_TM"
