#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT_DIR/frontend/src/pages/SafeShieldRulesPage.tsx"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

grep -Fq 'border-2 border-slate-300 bg-slate-50 px-4' "$PAGE" || \
	fail 'new-domain inputs must use the emphasized text-input surface'

grep -Fq 'shadow-inner' "$PAGE" || \
	fail 'rules inputs must retain inset affordance'

grep -Fq 'absolute inset-y-0 left-0 flex w-11 items-center justify-center' "$PAGE" || \
	fail 'search icon must use a vertically centered flex wrapper'

grep -Fq 'pl-11' "$PAGE" || \
	fail 'search input must reserve space for the centered icon'

if grep -Fq 'absolute top-1/2 left-3.5 size-4 -translate-y-1/2' "$PAGE"; then
	fail 'search icon must not use transform-based vertical positioning'
fi

echo 'PASS: SafeShield rules input and search icon contracts are present'
