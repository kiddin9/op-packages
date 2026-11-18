#!/bin/sh
# procd 无单独日志文件参数，保留此重定向桥接；exec 让 procd 直接监督核心进程。
log="$1"
shift
if [ -n "$log" ]; then
    exec "$@" >>"$log" 2>&1
else
    exec "$@" >/dev/null 2>&1
fi
