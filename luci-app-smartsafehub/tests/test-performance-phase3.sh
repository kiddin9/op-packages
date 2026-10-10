#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
grep -Fq '`${item.label} (계정 연결 필요)`' frontend/src/components/ProductNavigation.tsx
grep -Fq 'aria-hidden="true"' frontend/src/components/ProductNavigation.tsx
printf 'PASS: accessible disconnected account navigation
'
