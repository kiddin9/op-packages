#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# B1.2: integration test for subscription/repository.uc. Unlike
# the filter/decoder unit tests, this one writes to a real UCI
# cursor, so the runner stages a sandboxed config dir with a
# pre-existing homeproxy file and points the cursor at it.
#
# Staging layout:
#   $WORK/sandbox/homeproxy           UCI file with seed sections
#   $WORK/sandbox/                    cursor root
#   $WORK/scripts/                    test + homeproxy mock + module
#
# cursor(dir) reads from <dir>/<name> directly (NOT <dir>/config/
# <name>), so the seed file lives at the top of the sandbox dir.
#
# Run from tests/ucode/run.sh, which exports UCODE_MODULES_DIR so
# `import { cursor } from 'uci'` and `import { md5 } from 'digest'`
# resolve against the local testbed modules.
#
# Usage: sh tests/ucode/test_subscription_repository.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-subscription-repo-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

SANDBOX="$WORK/sandbox"
STAGE="$WORK/scripts"

rm -rf "$WORK"
mkdir -p "$SANDBOX" "$STAGE"

# Seed the UCI file. The cursor reads <sandbox>/homeproxy (NOT
# <sandbox>/config/homeproxy); see the comment above.
uci_seed() {
	printf 'config homeproxy %s\n' "$1" >> "$SANDBOX/homeproxy"
	shift
	for kv in "$@"; do
		key="${kv%%=*}"
		val="${kv#*=}"
		printf '\toption %s %s\n' "$key" "$val" >> "$SANDBOX/homeproxy"
	done
}

# The real /etc/config/homeproxy always carries `config homeproxy 'config'`;
# the sandbox needs it too, because libuci's uci_set() creates an anonymous
# section when the named one does not exist, and the main_node assertions
# read the options back by the section name 'config'.
uci_seed config routing_mode=bypass_mainland_china main_node=urltest

uci_seed cfgUSER0001 label=user-only type=vless address=user.example.com
uci_seed cfgKEEP00001 label=kept-node grouphash=test-group type=vless \
	address=old.example.com stale_field=remove-me
uci_seed cfgDROP00001 label=dropped-node grouphash=test-group type=vless \
	address=gone.example.com

# Stage the mock + the module + the test alongside each other so
# bare-name imports (`from 'homeproxy'`, `from 'repository'`) resolve
# via the work-dir -L path.
#
# PR-03: Repository imports parser/flatten.uc, which in turn imports
# parser/mapping.uc. Stage the whole parser/ tree into a sibling
# `parser/` directory so the bare-name imports inside it resolve.
cp "$ROOT/tests/ucode/mocks/homeproxy.uc" "$STAGE/"
# repository.uc imports '../parser/flatten.uc', so parser/ must be a
# sibling of the directory holding repository.uc (STAGE/subscription/),
# not of STAGE itself.
mkdir -p "$STAGE/subscription" "$STAGE/parser"
cp "$ROOT/root/etc/homeproxy/scripts/parser/"*.uc "$STAGE/parser/"
cp "$ROOT/root/etc/homeproxy/scripts/subscription/repository.uc" "$STAGE/subscription/"
cp "$ROOT/tests/ucode/test_subscription_repository.uc" "$STAGE/"

if ( cd "$STAGE" && ucode -L "$STAGE" test_subscription_repository.uc "$SANDBOX" ); then
	echo "PASS: subscription repository integration test"
else
	echo "FAIL: subscription repository integration test"
	FAILED=1
fi

exit $FAILED
