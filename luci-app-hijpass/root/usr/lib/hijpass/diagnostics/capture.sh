#!/bin/sh

# 功能入口负责命令执行；相邻 ucode 脚本只校验、转换及生成数据。
. /usr/lib/hijpass/common.sh

data="$HIJPASS_LIB/diagnostics/capturecli.uc"
finish_capture() {
    directory=$1
    case "$directory" in /tmp/hijpass-trace.*) pid=${directory#/tmp/hijpass-trace.} ;; *) echo 'invalid capture directory' >&2; return 1 ;; esac
    case "$pid" in ''|*[!0-9]*) echo 'invalid capture directory' >&2; return 1 ;; esac
    # 元数据损坏仍按本次 PID 删除规则，保证诊断失败不会留下拦截规则。
    nft flush chain inet hijpass "trace-$pid" 2>/dev/null || :
    nft delete chain inet hijpass "trace-$pid" 2>/dev/null || :
    raw=$(mktemp /tmp/hijpass-trace-cleanup.XXXXXX) || return 1
    for chain in pre-filter out-route; do
        nft -a list chain inet hijpass "$chain" 2>/dev/null | sed "s/^/$chain /" >>"$raw"
    done
    plan=$(hijpass_run_ucode "$data" cleanup "$directory" "$raw") || { rm -f "$raw"; return 1; }
    rm -f "$raw"
    json_load "$plan" || return 1
    keep=0
    json_get_var keep keep
    json_select rules
    json_get_keys entries
    for entry in $entries; do
        json_select "$entry"
        json_get_vars chain handle
        nft delete rule inet hijpass "$chain" handle "$handle" 2>/dev/null || :
        json_select ..
    done
    [ "${2:-}" != discard ] || { rm -rf -- "$directory"; return $?; }
    hijpass_run_ucode "$data" report "$directory"
    code=$?
    [ "$keep" = 1 ] || rm -rf -- "$directory"
    return "$code"
}
case "${1:-}" in finish|discard) finish_capture "${2:-}" "$1"; exit $? ;; esac
[ "$(id -u)" = 0 ] || { echo 'must run as root' >&2; exit 1; }
capture=$(hijpass_run_ucode "$data" prepare "$$" "$@") || exit 1
json_load "$capture" || exit 1
json_get_vars directory mode client seconds method url tcpdump iface filter
for command in nft; do command -v "$command" >/dev/null 2>&1 || { echo "$command is required" >&2; exit 1; }; done
[ "$mode" != router ] || command -v curl >/dev/null 2>&1 || { echo 'curl is required' >&2; exit 1; }
[ "$tcpdump" != 1 ] || command -v tcpdump >/dev/null 2>&1 || { echo 'tcpdump is required' >&2; exit 1; }
nft list table inet hijpass >/dev/null 2>&1 || { echo 'nft table inet hijpass not found' >&2; exit 1; }
mkdir -m 700 "$directory" || exit 1
for name in nft.trace nft.setup system.log tcpdump.log tcpdump.err curl.out curl.err; do : >"$directory/$name"; done
hijpass_run_ucode "$data" rules "$capture" >"$directory/add.nft" || { rm -rf "$directory"; exit 1; }
if ! nft -f "$directory/add.nft"; then
    echo 'cannot install trace rule' >"$directory/nft.setup"
    finish_capture "$directory"
    exit 1
fi
nft_pid= log_pid= tcpdump_pid= request_pid=
cleaned=0
cleanup() {
    [ "$cleaned" -eq 0 ] || return
    cleaned=1
    # 先停止并回收生产日志的进程，tcpdump 退出时刷新剩余捕获内容。
    for pid in $request_pid $nft_pid $log_pid $tcpdump_pid; do kill "$pid" 2>/dev/null || :; done
    for pid in $request_pid $nft_pid $log_pid $tcpdump_pid; do wait "$pid" 2>/dev/null || :; done
    finish_capture "$directory"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
nft monitor trace >"$directory/nft.trace" 2>&1 &
nft_pid=$!
if command -v logread >/dev/null 2>&1; then logread -f >"$directory/system.log" 2>&1 & log_pid=$!; fi
# 即时交付数据包，避免快速请求结束时数据仍滞留在 libpcap 缓冲区。
if [ "$tcpdump" = 1 ]; then tcpdump --immediate-mode -l -n -i "$iface" "$filter" >"$directory/tcpdump.log" 2>"$directory/tcpdump.err" & tcpdump_pid=$!; fi
# 部分 OpenWrt BusyBox sleep 只支持整数秒；留出监听器启动时间。
sleep 1 || exit 1
printf 'Trace is active. Generate traffic on the selected client during capture.\n'
if [ "$mode" = client ]; then
    sleep "$seconds" & request_pid=$!
    wait "$request_pid"
else
    set -- curl -sS --max-time "$seconds" -o /dev/null -w 'http_code=%{http_code}\nremote_ip=%{remote_ip}\nremote_port=%{remote_port}\ntime_total=%{time_total}\n'
    [ "$method" != HEAD ] || set -- "$@" -I
    "$@" -- "$url" >"$directory/curl.out" 2>"$directory/curl.err" & request_pid=$!
    wait "$request_pid"
    printf '%s\n' "$?" >"$directory/curl.exit"
fi
request_pid=
cleanup
