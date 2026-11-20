#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HTTP="$ROOT/root/usr/lib/smartsafehub/http.sh"
MAKEFILE="$ROOT/Makefile"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# API requests use a strict curl policy. Signed firmware and Apps downloads
# use a separate uclient-fetch path and are integrity-checked by callers.
grep -Eq '^LUCI_DEPENDS:=.*[[:space:]]\+curl([[:space:]]|$)' "$MAKEFILE" || fail 'curl dependency missing'
for policy in '--disable' '--fail' '--location --max-redirs 0' '--proto' '--proto-redir' '--noproxy' '--write-out'; do
 grep -Fq -- "$policy" "$HTTP" || fail "HTTP policy flag missing: $policy"
done
grep -Eq '^LUCI_DEPENDS:=.*[[:space:]]\+uclient-fetch([[:space:]]|$)' "$MAKEFILE" || fail 'uclient-fetch dependency missing'
grep -Fq 'ssh_http_download() {' "$HTTP" || fail 'file transfer helper missing'
grep -Fq -- '--timeout=30' "$HTTP" || fail 'file transfer inactivity timeout must be 30s'
grep -Fq -- 'timeout="${3:-20}"' "$HTTP" || fail 'default curl API timeout must be 20s'
for script in firmware apps-manager; do
 grep -Fq 'ssh_http_download ' "$ROOT/root/usr/libexec/smartsafehub-$script" || fail "missing uclient file download: $script"
done
if grep -Eq 'ssh_http_request GET .*\.part|ssh_http_request GET .*\.apk' "$ROOT/root/usr/libexec/smartsafehub-firmware" "$ROOT/root/usr/libexec/smartsafehub-apps-manager"; then
 fail 'large file sent through curl deadline'
fi
for file in device activity-sync apps updater apps-metrics firmware health; do
 path="$ROOT/root/usr/libexec/smartsafehub-$file"
 grep -Fq 'ssh_http_request ' "$path" || fail "missing shared secure request: $file"
done
python3 "$ROOT/tests/support/http_transport_check.py" || exit 1
sh "$ROOT/tests/test-download-transport.sh" || exit 1
