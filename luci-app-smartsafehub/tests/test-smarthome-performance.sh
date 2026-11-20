#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PYTEST'
from pathlib import Path
import re

app = Path('frontend/src/app/App.tsx').read_text()
page = Path('frontend/src/pages/SmartHomePage.tsx').read_text()
api = Path('frontend/src/api/jarbis.ts').read_text()
resource = Path('frontend/src/hooks/useAsyncResource.ts').read_text()

# Avoid a full-page spinner on every navigation. Preserve snapshots in the
# mounted parent, and let each independent RPC display when it completes.
for name in ('jarbisStatus', 'jarbisDevices', 'jarbisCandidates'):
    assert re.search(rf'const {name} = useAsyncResource<', app), name
assert app.count("active: route === 'smarthome'") == 3
assert 'statusResource={jarbisStatus}' in app
assert 'devicesResource={jarbisDevices}' in app
assert 'candidatesResource={jarbisCandidates}' in app
assert 'useState(true)' not in page[page.index('export function SmartHomePage('):page.index('const refreshLight')]
assert 'if (loading) return <LoadingPanel />' not in page
assert 'getJarbisStatus().then(async fresh =>' not in page, 'a serial status -> list read blocks all content'
assert 'const [fresh] = await Promise.all([' in page, 'explicit refresh should fetch concurrently'
assert 'statusResource.replaceData(result)' in page
assert 'devicesResource.replaceData(result)' in page
assert 'candidatesResource.replaceData(result)' in page
assert '!deviceData ?' in page and '!candidateData ?' in page
assert "deviceData ? devices.length : '—'" in page, 'do not report 0 registered bulbs before reading'
assert "candidatesResource.replaceData(result);" in page
assert "}, '기기 검색을 마쳤습니다.', false);" in page, 'scan must not issue another discovery_list read'

# Background reads are abortable/normal priority. Only user-triggered writes
# and command confirmation should use interactive priority.
for method in ('status', 'devices_list', 'discovery_list'):
    assert re.search(rf"'{method}', \{{\}}, 6500, 'normal', signal", api), method
assert "rpc<JarbisLightState>('light_state', { id }, 11500, priority)" in api
assert "getJarbisLightState(id, background ? 'low' : 'high')" in page
assert 'refreshLight(id, true)' in page

# A pending stale refresh must not roll back an explicit add/delete/scan.
mutation = resource[resource.index('const replaceData = useCallback('):]
assert 'generation.current += 1;' in mutation
assert 'controller.current?.abort();' in mutation
assert 'inFlight.current = null;' in mutation
assert 'lastSuccessAt.current = Date.now();' in mutation
print('PASS: 스마트홈 병렬 조회, 재방문 캐시, 지연 구간 표시 및 경쟁 상태 방지')
PYTEST
