#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
# Minimal jsonfilter substitute for hosts without OpenWrt jsonfilter.
if ! command -v jsonfilter >/dev/null 2>&1; then
 mkdir -p "$TEMP/bin"
 cat > "$TEMP/bin/jsonfilter" <<'PYJSON'
#!/usr/bin/env python3
import json,sys
args=sys.argv
try:
 data=json.load(open(args[args.index('-i')+1]))
 key=args[args.index('-e')+1].removeprefix('@.')
 print(data.get(key, ''))
except Exception:
 pass
PYJSON
 chmod +x "$TEMP/bin/jsonfilter"
 PATH="$TEMP/bin:$PATH"
 export PATH
fi
. "$ROOT/root/usr/lib/smartsafehub/runtime.sh"
SMARTSAFEHUB_RUNTIME_DIAG_DIR="$TEMP/runtime"
ssh_runtime_init health
ssh_runtime_status | grep -Fq '"phase":"not_run"'
ssh_runtime_execute run-once true
[ -f "$TEMP/runtime/health.json" ]
grep -Fq '"last_result":"success"' "$TEMP/runtime/health.json"
if ssh_runtime_execute run-once false; then
 echo 'failed operation returned success' >&2; exit 1
fi
grep -Fq '"last_error_code":"EXIT_1"' "$TEMP/runtime/health.json"
grep -Fq '"consecutive_failures":1' "$TEMP/runtime/health.json"
ssh_runtime_execute run-once true
grep -Fq '"consecutive_failures":0' "$TEMP/runtime/health.json"
grep -Fq '"last_result":"success"' "$TEMP/runtime/health.json"
for service in device health activity-sync; do
 script="$ROOT/root/usr/libexec/smartsafehub-$service"
 sh -n "$script"
 grep -Fq 'runtime-status)' "$script"
 grep -Fq 'ssh_runtime_execute' "$script"
done
grep -Eq '^PKG_RELEASE:=[0-9]+$' "$ROOT/Makefile"
echo 'daemon runtime checks: OK'
