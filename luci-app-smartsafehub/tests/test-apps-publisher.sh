#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY_TEST'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
rpc = (root / 'root/usr/share/rpcd/ucode/smartsafehub/apps.uc').read_text()
types = (root / 'frontend/src/types/apps.ts').read_text()
ui = (root / 'frontend/src/pages/AppsPage.tsx').read_text()
css = (root / 'frontend/src/styles/app.css').read_text()
demo = (root / 'frontend/src/demo/data.ts').read_text()
helper = (root / 'frontend/src/utils/appsPublisher.ts').read_text()

# Hub schema 1 transports snake_case; public router RPC exposes camelCase.
assert "item?.publisher_type == 'first_party' ? 'first_party' : 'third_party'" in rpc
assert 'publisherType:' in rpc
assert "publisherType?: 'first_party' | 'third_party'" in types
assert "return type === 'first_party';" in helper
assert 'isFirstPartyPublisher(app.publisherType)' in ui
assert 'app.id ===' not in ui.split('ssh-apps-official-badge')[0].split('<div class="mt-auto')[-1]
assert '✦</span> SmartSafeHub 공식' in ui
assert '✓ 검증된 앱' in ui
assert 'ssh-apps-official-badge' in ui
assert ".ssh-app[data-theme='dark'] .ssh-apps-official-badge" in css

# Official status is explicit demo metadata, never derived from app name or slug.
fixtures = {}
for slug in ('retro-arcade', 'travelmate', 'wake-on-lan', 'network-usage-monitor'):
    pattern = rf"id: '{slug}',(?:(?!\n    }}).)*?publisherType: '([^']+)'"
    found = re.search(pattern, demo, re.DOTALL)
    assert found, f'publisher type missing for {slug}'
    fixtures[slug] = found.group(1)
assert fixtures['retro-arcade'] == 'first_party'
assert all(value == 'third_party' for slug, value in fixtures.items() if slug != 'retro-arcade')

# No new elevated RPC rights, remote URLs or installer catalog trust.
assert "item.runtime != 'router' || item.installer != 'apk'" in rpc
assert "webUi: length(path)" in rpc
PY_TEST
printf '%s\n' 'PASS: Apps publisher type and official badge contract'
