#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HTTP="$ROOT/root/usr/lib/smartsafehub/http.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }

cat > "$TMP/mock-uclient" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" > "$UCLIENT_ARGS"
[ "$1" = -q ] || exit 11
[ "$2" = --timeout=30 ] || exit 12
[ "$3" = -O ] || exit 13
out="$4"
case "$5" in https://*) ;; *) exit 14;; esac
printf '%s' 'fixture-data' > "$out"
[ "${SIMULATE_FAILURE:-0}" = 0 ] || { echo 'signed-private-url' >&2; exit 7; }
SH
cat > "$TMP/mock-curl" <<'SH'
#!/bin/sh
printf 'unexpected curl for file download\n' >&2
exit 19
SH
chmod +x "$TMP/mock-uclient" "$TMP/mock-curl"
export SMARTSAFEHUB_HTTP_UCLIENT_BIN="$TMP/mock-uclient"
export SMARTSAFEHUB_HTTP_CURL_BIN="$TMP/mock-curl"
export UCLIENT_ARGS="$TMP/args"
# shellcheck source=/dev/null
. "$HTTP"
ssh_http_download "$TMP/image.bin" 'https://repo.smartsafehub.com/image.bin' || fail 'verified file download rejected'
[ "$(cat "$TMP/image.bin")" = 'fixture-data' ] || fail 'file not written'
grep -Fq -- '--timeout=30' "$TMP/args" || fail '30-second timeout not applied'
# HTTPS required even for file transfers, before any network access.
rm -f "$TMP/args"
if ssh_http_download "$TMP/unsafe.bin" 'http://repo.smartsafehub.com/file.apk'; then
 fail 'HTTP URL was accepted'
fi
[ ! -e "$TMP/args" ] || fail 'unsafe URL reached network client'
[ ! -e "$TMP/unsafe.bin" ] || fail 'unsafe URL created output'
# Partial data must be cleared and signed URL diagnostics must not leak.
export SIMULATE_FAILURE=1
if ssh_http_download "$TMP/image.bin" 'https://repo.smartsafehub.com/private-token' >"$TMP/out" 2>"$TMP/err"; then
 fail 'partial download returned success'
fi
[ ! -e "$TMP/image.bin" ] || fail 'partial file still present'
[ ! -s "$TMP/out" ] && [ ! -s "$TMP/err" ] || fail 'signed URL leaked in diagnostic output'
# Preserve the curl HTTPS redirect test: file helper never replaces API helper.
grep -Fq -- '--max-redirs 0' "$HTTP" || fail 'API redirect block removed'
printf 'PASS: 펌웨어·Apps 파일은 uclient-fetch 30초 정책으로 다운로드하고 API curl 보호는 유지합니다\n'
