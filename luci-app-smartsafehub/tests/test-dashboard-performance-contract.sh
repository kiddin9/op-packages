#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PYTEST'
from pathlib import Path
app = Path('frontend/src/app/App.tsx').read_text()
server = Path('root/usr/share/rpcd/ucode/smartsafehub/system.uc').read_text()
home = Path('frontend/src/pages/HomePage.tsx').read_text()
assert "useActivityHistory(route === 'activity')" in app
assert 'activity={status.data?.activityHistory ?? null}' in app
assert "useSafeShieldStatus(route === 'home' || route === 'safeshield')" in app
assert "useSafeShieldStatistics(route === 'home' || route === 'safeshield', route === 'safeshield')" in app
assert "useSoftwareUpdates(true)" in app
assert "useFirmwareUpdates(true)" in app  # sidebar firmware badge stays current
assert 'if (loading && !data)' in home
assert "let info_finished = false" in server and "let wan_finished = false" in server
assert server.index("const info_request = defer_call('system', 'info'") < server.index("const wan_request = defer_call('network.interface.wan'")
for hook in ('useSoftwareUpdates', 'useFirmwareUpdates'):
    source = Path(f'frontend/src/hooks/{hook}.ts').read_text()
    assert 'const [pollingPhase, setPollingPhase]' in source
    assert 'setPollingPhase(resource.data?.phase ?? null)' in source
    assert 'active: active || resource.data' not in source
print('PASS: dashboard deduplication, reuse, polling, rendering, parallel RPC and update hooks')
PYTEST
