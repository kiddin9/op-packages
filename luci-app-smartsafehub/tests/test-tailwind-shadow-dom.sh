#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
STYLES="$ROOT_DIR/frontend/src/styles/app.css"
NAVIGATION="$ROOT_DIR/frontend/src/components/ProductNavigation.tsx"
MAIN="$ROOT_DIR/frontend/src/main.tsx"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$STYLES" "$NAVIGATION" "$MAIN"; do
	[ -f "$file" ] || fail "missing Shadow DOM frontend source: ${file#$ROOT_DIR/}"
done

grep -Fq '@layer properties, theme, base, components, utilities;' "$STYLES" || \
	fail 'Tailwind properties layer must precede theme/base/components/utilities'
grep -Fq 'Tailwind CSS v4 initializes utility internals such as --tw-border-style' "$STYLES" || \
	fail 'Shadow DOM Tailwind fallback must document why it exists'
grep -Fq '@layer properties {' "$STYLES" || \
	fail 'Shadow DOM Tailwind fallback must live in the low-priority properties layer'
grep -Fq '  :host,' "$STYLES" || \
	fail 'Shadow DOM Tailwind fallback must initialize the host'
grep -Fq '  *::before,' "$STYLES" || \
	fail 'Shadow DOM Tailwind fallback must cover pseudo-elements'
grep -Fq '  ::backdrop {' "$STYLES" || \
	fail 'Shadow DOM Tailwind fallback must cover backdrop utilities'

for declaration in \
	'--tw-border-style: solid;' \
	'--tw-translate-x: 0;' \
	'--tw-translate-y: 0;' \
	'--tw-shadow: 0 0 #0000;' \
	'--tw-ring-shadow: 0 0 #0000;' \
	'--tw-ring-offset-width: 0px;' \
	'--tw-blur: initial;' \
	'--tw-duration: initial;'; do
	grep -Fq -- "$declaration" "$STYLES" || \
		fail "Shadow DOM Tailwind fallback is missing: $declaration"
done

# The production app loads app.css inside the ShadowRoot. Keep a real Tailwind
# border utility in the navigation contract so a missing property fallback is
# caught before the router sidebar silently loses its divider again.
grep -Fq "const stylesheetUrl = assetUrl('app.css', host);" "$MAIN" || \
	fail 'production frontend must continue loading app.css inside the ShadowRoot'
grep -Fq 'border-r border-slate-200' "$NAVIGATION" || \
	fail 'desktop sidebar must keep its Tailwind right-border utility contract'

printf 'PASS: Tailwind v4 Shadow DOM property fallbacks keep production utilities stable\n'
