#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Mutation test: new shell sources must be included without hand registration.
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CHECKER="$ROOT_DIR/tools/check_shell_syntax.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
for directory in tests spec root/usr/lib root/usr/libexec root/etc/init.d root/etc/rc.button; do
    mkdir -p "$TMP/$directory"
done
printf '#!/bin/sh\nprintf "ok\\n"\n' > "$TMP/tests/test-existing.sh"
sh "$CHECKER" "$TMP" >/dev/null || fail 'valid fixture rejected'
for relative in tests/test-new.sh spec/new_spec.sh root/usr/lib/common.sh \
    root/usr/libexec/smartsafehub-new root/etc/init.d/smartsafehub-new root/etc/rc.button/new; do
    printf '#!/bin/sh\nif true; then\n' > "$TMP/$relative"
    if sh "$CHECKER" "$TMP" >"$TMP/out" 2>"$TMP/err"; then
        fail "new malformed shell source was ignored: $relative"
    fi
    grep -Fq 'invalid shell syntax:' "$TMP/err" || \
        fail "unexpected syntax checker failure: $relative"
    rm -f "$TMP/$relative"
done
sh "$CHECKER" "$TMP" >/dev/null || fail 'fixture not restored'
printf 'PASS: automatic syntax discovery catches new test and router shell files\n'
