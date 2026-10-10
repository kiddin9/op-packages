#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
grep -Fq 'activity_history: {' root/usr/share/rpcd/ucode/smartsafehub.uc
jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub | index("activity_history") != null' root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json >/dev/null
grep -Fq "callApi<ActivityHistory>(API_OBJECT, 'activity_history')" frontend/src/api/smartsafehub.ts
grep -Fq 'import.meta.env.DEV && elapsedMs >= 1000' frontend/src/api/rpc.ts
printf 'PASS: activity RPC, ACL, slow RPC instrumentation
'
