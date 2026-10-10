#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
account=frontend/src/hooks/useDeviceRegistration.ts
sidebar=frontend/src/hooks/useDashboardAccountStatus.ts
resource=frontend/src/hooks/useAsyncResource.ts
software=frontend/src/hooks/useSoftwareUpdates.ts
firmware=frontend/src/hooks/useFirmwareUpdates.ts
# A response from an earlier request must never overwrite newer account state.
grep -Fq 'generation !== requestGeneration.current' "$account"
grep -Fq 'commitStatus(localStatus, generation)' "$account"
grep -Fq 'if (accountRoute) return;' "$sidebar"
grep -Fq 'generation.current === requestGeneration' "$sidebar"
# The freshness clock is the last successful response, not request initiation.
grep -Fq 'lastSuccessAt.current = Date.now()' "$resource"
grep -Fq 'Date.now() - lastSuccessAt.current < staleTimeMs' "$resource"
grep -Fq 'failureCount.current += 1' "$resource"
grep -Fq 'RETRY_MAX_MS = 30_000' "$resource"
# Active updates refresh on tab return; router outages must use bounded retries.
grep -Fq 'refreshOnVisible: pollingPhase' "$software"
grep -Fq 'refreshOnVisible: isActivePhase(pollingPhase' "$firmware"
grep -Fq 'void load(false).finally(schedule);' "$resource"
echo 'PASS: account response ordering, cache success timing, and update recovery'
