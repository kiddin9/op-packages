#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
grep -Fq 'ACCOUNT_STATUS_INTERVAL_MS = 60_000' frontend/src/hooks/useDashboardAccountStatus.ts
grep -Fq "document.visibilityState === 'hidden'" frontend/src/hooks/useDashboardAccountStatus.ts
grep -Fq 'staleTimeMs = 30_000' frontend/src/hooks/useAsyncResource.ts
grep -Fq 'if (!fresh) void load();' frontend/src/hooks/useAsyncResource.ts
grep -Fq 'const updates = useSoftwareUpdates(true);' frontend/src/app/App.tsx
printf 'PASS: periodic local account state, stale cache, global update polling
'
