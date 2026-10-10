#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Optional execution diagnostics. No network calls, no persistent flash writes.
# This file is sourced by the individual services after common.sh.
ssh_runtime_init() {
 SSH_RUNTIME_NAME="$1"
 SSH_RUNTIME_DIR="${SMARTSAFEHUB_RUNTIME_DIAG_DIR:-/tmp/smartsafehub/runtime}"
 SSH_RUNTIME_FILE="$SSH_RUNTIME_DIR/$SSH_RUNTIME_NAME.json"
 SSH_RUNTIME_DEBUG=0
}
ssh_runtime_now() { date +%s 2>/dev/null || printf 0; }
ssh_runtime_read_number() {
 local key="$1" value
 value="$(jsonfilter -i "$SSH_RUNTIME_FILE" -e "@.$key" 2>/dev/null || true)"
 case "$value" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$value" ;; esac
}
ssh_runtime_status() {
 if [ -s "$SSH_RUNTIME_FILE" ]; then
  cat "$SSH_RUNTIME_FILE"
 else
  printf '{"schema":1,"service":"%s","phase":"not_run","last_run_at":0,"last_success_at":0,"last_duration_ms":0,"last_result":"not_run","last_error_code":null,"consecutive_failures":0,"next_run_at":0}\n' "$SSH_RUNTIME_NAME"
 fi
}
ssh_runtime_execute() {
 local operation="$1" start end elapsed rc prev_success failures next_run result error tmp
 shift
 start="$(ssh_runtime_now)"
 [ "$SSH_RUNTIME_DEBUG" -eq 0 ] || printf 'smartsafehub[%s]: start %s\n' "$SSH_RUNTIME_NAME" "$operation" >&2
 "$@" && rc=0 || rc=$?
 end="$(ssh_runtime_now)"
 elapsed=$(( (end - start) * 1000 ))
 prev_success="$(ssh_runtime_read_number last_success_at)"
 failures="$(ssh_runtime_read_number consecutive_failures)"
 next_run=0
 if [ "$rc" -eq 0 ]; then
  prev_success="$end"; failures=0; result=success; error=null
 else
  failures=$((failures + 1)); result=failed; error="\"EXIT_$rc\""
 fi
 if mkdir -p "$SSH_RUNTIME_DIR" 2>/dev/null; then
  tmp="$SSH_RUNTIME_FILE.tmp.$$"
  if printf '{"schema":1,"service":"%s","operation":"%s","phase":"idle","last_run_at":%s,"last_success_at":%s,"last_duration_ms":%s,"last_result":"%s","last_error_code":%s,"consecutive_failures":%s,"next_run_at":%s}\n' \
   "$SSH_RUNTIME_NAME" "$operation" "$start" "$prev_success" "$elapsed" "$result" "$error" "$failures" "$next_run" > "$tmp"; then
   mv -f "$tmp" "$SSH_RUNTIME_FILE" 2>/dev/null || rm -f "$tmp"
  else
   rm -f "$tmp"
  fi
 fi
 [ "$SSH_RUNTIME_DEBUG" -eq 0 ] || printf 'smartsafehub[%s]: finish %s rc=%s duration_ms=%s\n' "$SSH_RUNTIME_NAME" "$operation" "$rc" "$elapsed" >&2
 return "$rc"
}
ssh_runtime_debug_arg() {
 case "${2:-}" in --debug) SSH_RUNTIME_DEBUG=1 ;; '') ;; *) return 2 ;; esac
}
