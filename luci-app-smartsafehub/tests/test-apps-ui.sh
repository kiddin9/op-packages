#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
page = (root / 'frontend/src/pages/AppsPage.tsx').read_text()
styles = (root / 'frontend/src/styles/app.css').read_text()
package = (root / 'Makefile').read_text()


def check(ok, message):
    if not ok:
        raise AssertionError(message)


# Version/revision validity is covered by test-package-contract.sh.
check('border-teal-300 text-teal-800 hover:bg-teal-50' in page, 'install should stay teal')
check('border-red-300 text-red-700 hover:bg-red-50' in page, 'removal must be red outline')
check('hover\\:bg-red-50:hover' in styles, 'red hover needs an explicit dark-mode style')
check('rgb(239 68 68 / 0.16)' in styles, 'dark-mode removal hover should be subtle')
check('ssh-apps-installed-badge' in page and 'ssh-apps-update-badge' in page and
      'ssh-apps-update-button' in page,
      'installed, update notice and update action need distinct styles')
check('.ssh-apps-update-button' in styles and ".ssh-app[data-theme='dark'] .ssh-apps-update-button" in styles,
      'update action must have a distinct dark-mode style')


# App installation storage must refer to the writable APK filesystem.
backend = (root / 'root/usr/share/rpcd/ucode/smartsafehub/apps-manager.uc').read_text()
card = (root / 'frontend/src/components/AppsStorageCard.tsx').read_text()
utils = (root / 'frontend/src/utils/appsStorage.ts').read_text()
check("safe_call('system', 'info', {})" in backend and
      "from_system_root(info?.root)" in backend,
      'Apps disk data must prefer procd system.info root stats')
check("from_statvfs(stats, mount)" in backend and "[ '/overlay', '/' ]" in backend,
      'statvfs fallback must support overlay and ext4 rootfs')
storage_module = (root / 'root/usr/share/rpcd/ucode/smartsafehub/apps-storage.uc').read_text()
check("type(value) == 'int'" in storage_module and "type(value) == 'double'" in storage_module,
      'ucode type() emits int/double and must never require integer')
check("root.total * 1024" in storage_module and "root.avail * 1024" in storage_module,
      'procd system.info root counters are KiB, not raw bytes')
check("MAX_BYTES / frsize" in storage_module,
      'unexpected statvfs counters must not overflow safe byte values')
check('stats.bavail' in storage_module and 'stats.frsize' in storage_module and 'storage: storage' in backend,
      'optional Apps metrics must report actual APK-available bytes without spawning df')
check('read_apps_metrics(request)' in backend and 'restore: restore_status(), installed: installed' in backend,
      'critical Apps status must be separate from optional storage metrics')
check("ensure_job('sizes')" in backend and "ensure_job('status')" in backend,
      'APK scan must execute asynchronously and independently from RPC status')
check('apps_metrics:' in (root / 'root/usr/share/rpcd/ucode/smartsafehub.uc').read_text(),
      'metrics RPC must be independently accessible')
import json
acl = json.loads((root / 'root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json').read_text())
check('apps_metrics' in acl['luci-app-smartsafehub']['read']['ubus']['smartsafehub'],
      'critical regression: Apps metrics RPC is missing from LuCI read ACL')
check('fetchAppsMetrics' in (root / 'frontend/src/app/App.tsx').read_text() and
      '!data?.ready ? 3_000 : 60000' in (root / 'frontend/src/app/App.tsx').read_text(),
      'optional Apps metrics should run separately and less frequently')
check("'/bin/df'" not in backend and "'/bin/df'" not in storage_module, 'storage must not spawn a polling command')
check('lg:grid-cols-[minmax(0,1fr)_minmax(0,18.5rem)]' in page,
      'Apps storage should be a compact fixed-width column on desktop, stacked on mobile')
check('ssh-apps-storage-card' in card and 'size-24' in card and 'gap-3' in card and 'sm:p-5' not in card,
      'storage card must be compact without hiding the donut or capacity data')
check('<AppsStorageCard storage={metrics?.storage} />' in page,
      'Apps storage should be read from independent optional metrics')
check('stroke-dasharray=' in card and 'aria-label="앱 설치 저장 공간"' in card,
      'storage donut must be accessible and use SVG')
check('Math.PI * 39' in card and 'r="39"' in card and card.count('size-24') == 2,
      'storage donut needs a larger ring and enough room around the center label')
check('용량 정보를 확인할 수 없습니다.' in card and 'summarizeAppsStorage(storage)' in card,
      'storage errors and older RPC responses need a safe fallback')
check('storage.availableBytes > storage.totalBytes' in utils,
      'malformed storage reports must be rejected')
check('usedText: formatStorageBytes(storage.totalBytes - storage.availableBytes)' in utils,
      'used storage must be derived from validated total and APK-available counters')
check('사용 {summary.usedText} / 전체 {summary.totalText}' in card,
      'storage card must show used and total bytes without increasing its height')
check('파일시스템 예약 공간' in card and '앱 설치 가능 공간</p>' not in card,
      'capacity breakdown must explain reserved space and avoid redundant footer')
check(".ssh-app[data-theme='dark'] .ssh-apps-storage-track" in styles and
      "[data-level='critical']" in styles,
      'donut must support dark mode and dangerously low storage')

# Per-app size reflects the installed APK package metadata only (no du scan).
manager = (root / 'root/usr/libexec/smartsafehub-apps-manager').read_text()
check('installed_size_bytes() {' in manager and '"$APK" info -s "$name"' in manager,
      'Apps installed size should query each package independently')
check('du -' not in manager and 'find /' not in manager,
      'installed size must not recursively scan the router filesystem')
check('installedSizes[fields[0]]' in backend and 'length(fields) != 2' in backend and
      'installedBytes:' not in backend and 'installedVersion:' in backend,
      'package size data must be parsed separately from the six-column status')
check('sizes) mkdir -p "$RUNTIME"; sizes;;' in manager and 'installed_size_bytes "$name"' in manager,
      'optional sizes command must report app APK totals without modifying status')
check('apps-size-diag' not in manager and 'diagnostic=' not in manager,
      'optional size checks must not create the retired diagnostics TSV')
check('rm -f /tmp/smartsafehub/apps-size-diagnostics.tsv' in package,
      'package upgrade must clean up the retired runtime diagnostic file')
check('app_bytes=' not in manager and 'set --' not in manager.split('sizes() {')[0].split('status() {')[1],
      'status must not invoke optional size processing')
check('sizeLabel !== null' in page and '설치 용량 약 {sizeLabel}' in page,
      'installed app card must show a real size only when known')
check('showOfferedVersion || sizeLabel !== null' in page and
      'showOfferedVersion && sizeLabel !== null' in page and
      'flex-wrap items-center gap-x-1.5' in page,
      'offered version and installed size must share a compact wrapping metadata row')
check(page.count('설치 용량 약 {sizeLabel}') == 1 and page.count('제공 v{app.version}') == 1,
      'Apps metadata must not duplicate version or installed size rows')
check('Number.isSafeInteger(bytes)' in page and 'installed && typeof bytes' in page and 'metrics?.installedSizes' in page,
      'missing or invalid sizes must not be guessed')
check('캐시는 포함되지 않습니다' in page,
      'metadata size must not be misrepresented as actual overlay consumption')
check('installedVersion?: string | null' in (root / 'frontend/src/types/apps.ts').read_text(),
      'installed APK version must have a typed field')
check('installed_release="$(installed_version "$primary_package" || :)"' in manager and
      '"$update_ready" "$installed_release"' in manager,
      'current APK version must originate from installed package metadata')
check('installedVersion: length(fields) >= 7' in backend and
      'match(fields[6]' in backend,
      'RPC parser must validate installed APK version')
check('설치 v${installedVersion}' in page and '제공 v{app.version}' in page,
      'installed and approved versions must have independent labels')
check('업데이트 가능</span>' in page and '설치 버전 확인 불가' in page,
      'updates must be distinguished from unknown installed versions')

# Category icons are local, consistent across cards and filters, and safe
# for unknown/future catalog categories. No external icon service or assets.
icon_source = (root / 'frontend/src/components/AppsCategoryIcon.tsx').read_text()
shared_icons = (root / 'frontend/src/components/Icons.tsx').read_text()
check('AppsCategoryIcon, appsCategoryOf' in page and
      '<AppsCategoryIcon category={tab.id} class="size-4 shrink-0" />' in page and
      '<AppsCategoryIcon category={appsCategoryOf(app.category)} class="size-7" />' in page,
      'filters and cards must share category-specific icons in appropriately sized frames')

check('class="grid size-14 shrink-0 place-items-center rounded-xl bg-slate-100 text-slate-600"' in page,
      'app card category icon frame must be 56px and align with the installed size row')
check('<AppsCategoryIcon category={appsCategoryOf(app.category)} class="size-7" />' in page and
      'class="grid size-11 shrink-0 place-items-center' not in page,
      'app category icon itself must be 28px while retaining the 56px frame')
check('<AppsCategoryIcon category={tab.id} class="size-4 shrink-0" />' in page,
      'category filter icons must remain compact and not change touch targets')
check('appsCategoryOf(app.category) === category' in page,
      'icon categorization and filtering must use the same normalization')
check('aria-label="앱 카테고리"' in page and '>{tab.label}</button>' in page and
      'inline-flex min-h-10 items-center gap-1.5' in page,
      'filter icons must retain text labels, touch targets and wrapping')
for catalog_key, category_key in [('network', 'network'), ('security', 'security'),
                                  ('entertainment', 'entertainment'), ('smart_home', 'smart_home'),
                                  ('iot', 'smart_home')]:
    check(f"case '{catalog_key}':" in icon_source,
          f'category {catalog_key} must be explicitly mapped to {category_key}')
for tab_key, icon_name in [('all', 'AppsIcon'), ('network', 'NetworkNodesIcon'),
                           ('security', 'ShieldIcon'), ('smart_home', 'HomeIcon'),
                           ('entertainment', 'GamepadIcon')]:
    check(f"case '{tab_key}': return <{icon_name}" in icon_source,
          f'{tab_key} category has the wrong icon')
check("default: return 'other';" in icon_source and
      'default: return <CircleEllipsisIcon' in icon_source and
      "{ id: 'other', label: '기타' }" in page,
      'unknown categories must use the other filter and its ellipsis icon')
check("case 'utilities': return <WrenchIcon" in icon_source and
      "case 'other': return <CircleEllipsisIcon" in icon_source and
      "case 'other': return 'other'" in icon_source and
      "{ id: 'utilities', label: '도구' }" in page,
      'tools and other must have their own explicit category and distinct icons')
check('PowerIcon' not in icon_source and 'PuzzleIcon' not in icon_source,
      'category icons must not revert to power or puzzle symbols')
for name in ['NetworkNodesIcon', 'GamepadIcon', 'WrenchIcon', 'CircleEllipsisIcon']:
    check(f'export function {name}(props: IconProps)' in shared_icons,
          f'{name} should use the local SVG IconBase and remain in the UI bundle')
check('<circle cx="12" cy="12" r="10" />' in shared_icons and
      'M8 12h.01M12 12h.01M16 12h.01' in shared_icons and
      '3.106-3.105' in shared_icons,
      'tools use a wrench, other uses a circle ellipsis, not network-like nodes')
check('aria-hidden={title ? undefined : true}' in shared_icons and
      'fill="none"' in shared_icons and 'stroke="currentColor"' in shared_icons,
      'icons must be decorative line SVGs that inherit light/dark text color')
check('https://' not in icon_source and '<img' not in icon_source,
      'category icons must not load unverified remote artwork')

# A transient catalog failure must not erase a previous successful result or
# turn asynchronously fetched installation status into false retired warnings.
check('const currentData = data;' in page, 'cached catalog must remain visible after a refresh failure')
check('error && !currentData' in page and 'error && currentData' in page,
      'catalog errors should be prominent only when no previous catalog exists')
check('role="status">이전 목록</span>' in page, 'cached catalog should have a compact non-blocking stale marker')
check('state.retired === true && state.managed' in page and '!error && !loading && !refreshing' in page,
      'retirement must require explicit backend proof and a complete catalog')
status_rpc = (root / 'root/usr/share/rpcd/ucode/smartsafehub/apps-manager.uc').read_text()
check("retired: length(fields) == 8 && fields[7] == '1'" in status_rpc,
      'retired status must originate only from a signed-off local owner manifest record')
check('retired?: boolean;' in (root / 'frontend/src/types/apps.ts').read_text(),
      'retired proof must be optional for older router responses')

# Removal never calls onRemove from a card or from the orphan-list button.
check("onClick={(event) => removable ? openRemoveDialog(app, event.currentTarget)" in page,
      'catalog removal must open confirmation')
check("onClick={(event) => openRemoveDialog({ id, name: id" in page,
      'orphaned apps must open the same confirmation')
check("onClick={() => void requestOperation(removeTarget, 'remove')}" in page,
      'dialog approval must be the only removal confirmation action')
check(page.count('onRemove(app.id)') == 1, 'only the accepted operation may call the remove RPC callback')
check('aria-modal="true"' in page and 'aria-labelledby="apps-remove-title"' in page,
      'remove confirmation must be accessible')
check('취소</button>' in page and '앱 제거</button>' in page, 'dialog must offer both choices')
check("if (event.key === 'Escape')" in page and "event.key !== 'Tab'" in page,
      'dialog must support escape and focus containment')
check("if (action === 'remove') closeRemoveDialog()" in page,
      'confirmed operation should close the modal before starting')
check("if (!installStatus || statusError || pending !== null || running || restoring) return;" in page,
      'operation must preserve status and concurrency guards')

# Installing still uses the existing confirmation and neither action bypasses RPC guards.
check("action === 'install' && !window.confirm" in page, 'existing install confirmation must remain')
check("<OperationIndicator action={activeAction} />" in page, 'loading must show on app and orphan entries')
check("{removing ? '제거 중…' : action === 'update' ? '업데이트 중…' : '설치 중…'}" in page,
      'install, update and remove must show distinct spinner states')
check("job.action === 'remove' ? '앱 제거 중' : job.action === 'update' ? '앱 업데이트 중' : '앱 설치 중'" in page,
      'running job status must use the action name')
check("job.phase === 'failed' ? 'border-rose-200 bg-rose-50 text-rose-800'" in page,
      'errors must keep a red alert')
check('useState<string | null>(readDismissedAppsJob)' in page,
      'dismissal must be restored after refreshing Apps')
check('saveDismissedAppsJob(key)' in page and 'onClick={() => dismissJob(jobKey)}' in page,
      'dismissing a job should persist the dismissed operation ID')
check("onClick={() => void requestOperation(app, 'update')}" in page, 'approved update action must be shown')
check('setDismissedJob(null)' not in page,
      'starting a new operation must not resurrect the previous failure')
PY
echo 'PASS: Apps removal confirmation, theme and operation states'

# Real ucode runtime coverage: prevents wrong numeric type names and unit
# conversions from passing the static Apps UI contract again.
if command -v ucode >/dev/null 2>&1; then
    ucode "$ROOT/tests/apps-storage-test.uc"
elif [ "${SMARTSAFEHUB_REQUIRE_UCODE:-0}" = '1' ]; then
    echo 'FAIL: Apps storage runtime test requires ucode' >&2
    exit 1
fi
