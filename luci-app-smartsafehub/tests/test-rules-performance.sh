#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PAGE="$ROOT/frontend/src/pages/SafeShieldRulesPage.tsx"
RPC="$ROOT/frontend/src/api/rpc.ts"
DIAG="$ROOT/frontend/src/api/rpcDiagnostics.ts"
UTIL="$ROOT/frontend/src/utils/ruleLists.ts"
fail() { echo "FAIL: $*" >&2; exit 1; }
grep -Fq 'memo(function RuleListCard' "$PAGE" || fail 'rule card should skip unchanged parent updates'
grep -Fq 'sameRecommendationContent(previous, status)' "$PAGE" || fail 'poll should preserve unchanged list references'
grep -Fq 'new Set(recommendedDomains)' "$PAGE" || fail 'domain membership should use a Set'
grep -Fq 'filterRuleGroups(rules, query' "$PAGE" || fail 'rule grouping should be memoized'
grep -Fq 'recommendedDomainSet.has(domain)' "$UTIL" || fail 'grouping should use Set membership'
if grep -Fq 'recommendedDomains.includes(domain)' "$PAGE"; then fail 'quadratic ownership lookup remains'; fi
grep -Fq 'ensureRpcDiagnostics()' "$RPC" || fail 'production diagnostics should be exposed'
grep -Fq 'recordRpcTiming({' "$RPC" || fail 'RPC completion should be timed'
grep -Fq 'MAX_RECENT = 60' "$DIAG" || fail 'in-memory diagnostic history should be bounded'
if grep -Eq 'localStorage|sessionStorage|sendBeacon' "$DIAG"; then fail 'RPC timings must not persist or be uploaded'; fi
if grep -Eq 'params:|sessionId:|responseData:|errorMessage:' "$DIAG"; then fail 'diagnostics must not retain sensitive RPC inputs'; fi
echo 'PASS: rules render optimization and private RPC timing contract'
