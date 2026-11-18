#!/bin/sh

# 功能入口负责命令执行；相邻 ucode 脚本只校验、转换及生成数据。
. /usr/lib/hijpass/common.sh

data="$HIJPASS_LIB/network/networkcli.uc"
action=${1:-}
[ "$#" -eq 0 ] || shift
case "$action" in
    iptype) hijpass_run_ucode "$data" "$action" "$@"; exit $? ;;
    connect) url=${1:-}; timeout=${2:-5}; socks=${3:-} ;;
    ping) socks=${1:-}; url="https://${2:-www.google.com}"; timeout=5 ;;
    *) hijpass_json_error 'unknown network action'; exit 1 ;;
esac
plan=$(hijpass_run_ucode "$data" request "$url" "$timeout" "$socks") || { printf '%s\n' "$plan"; exit 1; }
json_load "$plan" || exit 1
json_get_vars url timeout socks
# 单次请求保留真实退出码；curl 失败仍交给 ucode 返回完整测速报告。
set -- curl -I -sS -o /dev/null --max-time "$timeout" -w '%{http_code}\n%{remote_ip}\n%{remote_port}\n%{time_namelookup}\n%{time_connect}\n%{time_appconnect}\n%{time_starttransfer}\n%{time_total}\n'
[ -z "$socks" ] || set -- "$@" --socks5 "127.0.0.1:$socks"
output=$("$@" -- "$url" 2>/dev/null)
code=$?
if [ "$action" = ping ]; then
    printf '%s\n' "$output" | hijpass_run_ucode "$data" ping-report "$code" "$url"
else
    printf '%s\n' "$output" | hijpass_run_ucode "$data" report "$code" "$url"
fi
