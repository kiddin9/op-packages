#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
UPDATES_HOOK="$ROOT_DIR/frontend/src/hooks/useSoftwareUpdates.ts"
FIRMWARE_HOOK="$ROOT_DIR/frontend/src/hooks/useFirmwareUpdates.ts"
ASYNC_RESOURCE="$ROOT_DIR/frontend/src/hooks/useAsyncResource.ts"
RPC="$ROOT_DIR/frontend/src/api/rpc.ts"
SESSION="$ROOT_DIR/frontend/src/auth/session.ts"
MAIN="$ROOT_DIR/frontend/src/main.tsx"
BUILT_JS="$ROOT_DIR/root/www/luci-static/smartsafehub/app.js"
RELOAD_RUNTIME_TEST="$ROOT_DIR/tests/runtime/reload-safety.test.mjs"
SESSION_RUNTIME_TEST="$ROOT_DIR/tests/runtime/session-expiry-events.test.mjs"
SESSION_RESPONSE_TEST="$ROOT_DIR/tests/runtime/session-response.test.mjs"
RPC_SESSION_TEST="$ROOT_DIR/tests/runtime/rpc-session-expiry.test.mjs"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in \
	"$UPDATES_HOOK" \
	"$FIRMWARE_HOOK" \
	"$ASYNC_RESOURCE" \
	"$RPC" \
	"$SESSION" \
	"$MAIN" \
	"$BUILT_JS" \
	"$RELOAD_RUNTIME_TEST" \
	"$SESSION_RUNTIME_TEST" \
	"$SESSION_RESPONSE_TEST" \
	"$RPC_SESSION_TEST"; do
	[ -f "$file" ] || fail "missing reload-safety input: ${file#$ROOT_DIR/}"
done

command -v node >/dev/null 2>&1 || fail 'node is required for reload-safety behavioral tests'

node_major="$(node -p 'process.versions.node.split(".")[0]')"
case "$node_major" in
	''|*[!0-9]*) fail 'unable to determine node major version' ;;
esac
[ "$node_major" -ge 22 ] || \
	fail 'Node.js 22 or newer is required to execute TypeScript session regression tests'

# A network, authentication, polling, or generic error path must never own a full-document reload.
for file in "$ASYNC_RESOURCE" "$RPC" "$SESSION" "$MAIN"; do
	if grep -Eq 'location\.(reload|replace|assign)[[:space:]]*\(|location\.href[[:space:]]*=' "$file"; then
		fail "full-document navigation is forbidden in ${file#$ROOT_DIR/}"
	fi
done

if grep -Eq 'resource\.error.*(reload|location)|(reload|location).*resource\.error' "$UPDATES_HOOK"; then
	fail 'software-update resource errors must never be connected to a document reload'
fi
if grep -Eq 'resource\.error.*(reload|location)|(reload|location).*resource\.error' "$FIRMWARE_HOOK"; then
	fail 'firmware resource errors must never be connected to a document reload'
fi

# The built artifact must contain only the two guarded reload sites: software
# self-update completion and firmware reboot reconnect.
built_reload_count="$(grep -o 'location\.reload(' "$BUILT_JS" | wc -l | tr -d '[:space:]')"
[ "$built_reload_count" = '2' ] || \
	fail "built frontend must contain exactly two guarded reload sites (found $built_reload_count)"

# Execute the actual source body of the self-update effect across the historical failure scenarios.
run_node_typescript() {
	if node --help 2>/dev/null | grep -Fq -- '--experimental-strip-types'; then
		node --experimental-strip-types --no-warnings "$1"
	else
		node "$1"
	fi
}

run_node_typescript "$RELOAD_RUNTIME_TEST"
run_node_typescript "$SESSION_RUNTIME_TEST"
run_node_typescript "$SESSION_RESPONSE_TEST"
run_node_typescript "$RPC_SESSION_TEST"

printf 'PASS: reload/navigation safety and session-expiry regression guards are enforced\n'
