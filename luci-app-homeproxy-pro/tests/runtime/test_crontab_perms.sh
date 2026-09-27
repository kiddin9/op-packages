#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# hp_crontab_drop() rewrites /etc/crontabs/root through a temporary file, and
# `mv` replaces the *file*, not its contents: the temporary carries the shell's
# umask (0644) while procd creates the root crontab as 0600.  Every stop/start
# therefore left it world-readable - confirmed on the device (0600 after a
# boot, 0644 after one reload) - and a root crontab can hold other jobs'
# secrets.
#
# The function takes the crontab path as an argument and the module is
# device-side, so this drives it against a sandboxed file and never touches the
# host's own crontab.
#
# Usage: sh tests/runtime/test_crontab_perms.sh <repo-root> [workdir]

set -u

ROOT="${1:-.}"
WORK="${2:-$(mktemp -d)}"

FAILED=0

fail() {
	echo "FAIL: $*"
	FAILED=1
}

# BSD stat takes -f, GNU takes -c; try both rather than assuming a host.
file_mode() {
	stat -c '%a' "$1" 2>"/dev/null" || stat -f '%Lp' "$1" 2>"/dev/null"
}

rm -rf "$WORK"
mkdir -p "$WORK"

# The module is sourced by the init script, which provides log() and CONF.
CONF="homeproxy"
log() { printf '%s\n' "$*" >> "$WORK/log"; }
# shellcheck disable=SC1091
. "$ROOT/root/etc/homeproxy/scripts/runtime/service.sh"

CRONTAB="$WORK/crontab"

write_crontab() {
	cat > "$CRONTAB" <<-'EOF'
		0 3 * * * root /usr/bin/keep-me
		30 4 * * * root /etc/homeproxy/scripts/update_subscriptions.uc #homeproxy_autosetup
	EOF
}

# --- the entry is dropped and the rest of the file survives ---------------
write_crontab
chmod 600 "$CRONTAB"
hp_crontab_drop "$CRONTAB"
drop_rc=$?

if [ "$drop_rc" = 0 ]; then
	echo "PASS: hp_crontab_drop reports success"
else
	fail "hp_crontab_drop returned $drop_rc"
fi

if grep -q "keep-me" "$CRONTAB" && ! grep -q "autosetup" "$CRONTAB"; then
	echo "PASS: the auto-update entry is gone and other jobs survive"
else
	fail "the crontab was not edited as expected:"
	sed 's/^/      /' "$CRONTAB"
fi

if [ "$(file_mode "$CRONTAB")" = "600" ]; then
	echo "PASS: the root crontab is left 0600"
else
	fail "the root crontab is $(file_mode "$CRONTAB") after the rewrite; it was 0600"
fi

# --- a file an older version already loosened is repaired -----------------
write_crontab
chmod 644 "$CRONTAB"
hp_crontab_drop "$CRONTAB"

if [ "$(file_mode "$CRONTAB")" = "600" ]; then
	echo "PASS: a world-readable crontab is tightened to 0600"
else
	fail "a crontab that was already 0644 stayed $(file_mode "$CRONTAB")"
fi

# --- a missing crontab is reported, not invented --------------------------
rm -f "$CRONTAB"
if hp_crontab_drop "$CRONTAB"; then
	fail "hp_crontab_drop claimed success for a crontab that does not exist"
else
	echo "PASS: a missing crontab is reported as a failure"
fi

if [ -e "$CRONTAB" ]; then
	fail "hp_crontab_drop created a crontab that did not exist"
else
	echo "PASS: no crontab is created out of nothing"
fi

rm -rf "$WORK"

if [ "$FAILED" != 0 ]; then
	exit 1
fi
exit 0
