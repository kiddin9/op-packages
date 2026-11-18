#!/bin/sh

# worker 脱离 RPC 后保留输出，最后原子发布退出状态。
. /usr/lib/hijpass/common.sh
directory=$1
shift
trap '' HUP
capture_pid=
cancel_capture() {
    trap '' INT TERM
    if [ -n "$capture_pid" ]; then
        kill "$capture_pid" 2>/dev/null || :
        wait "$capture_pid" 2>/dev/null || :
    fi
    exit 143
}
trap cancel_capture INT TERM
started=$(date +%s)
hijpass_log INFO 'Diagnostic capture started'
"/usr/lib/hijpass/diagnostics/capture.sh" "$@" >"$directory/stdout" 2>"$directory/stderr" 8>&- &
capture_pid=$!
# start 传入登记锁；worker 就绪后才允许启动清理，避免后台派生期间目录被删。
flock -u 8
exec 8>&-
wait "$capture_pid"
code=$?
trap - INT TERM
level=INFO
[ "$code" -eq 0 ] || level=ERROR
if [ -s "$directory/stderr" ]; then
    hijpass_run_ucode "$HIJPASS_LIB/maintenance/logscli.uc" command "$HIJPASS_LOG_SOURCE" "$code" 'Diagnostic capture' "$directory/stderr" >/dev/null 2>&1 || :
fi
hijpass_log "$level" "Diagnostic capture finished: exit=$code, elapsed=$(($(date +%s) - started))s"
printf '%s\n' "$code" >"$directory/exit.tmp"
mv "$directory/exit.tmp" "$directory/exit"
