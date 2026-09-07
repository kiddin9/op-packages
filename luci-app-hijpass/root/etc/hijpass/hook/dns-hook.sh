#!/bin/sh
# DNS 服务 Hook 脚本
# 启动时以 start 参数调用，停止时以 stop 参数调用
# 用法: dns-hook.sh [start|stop]

case "$1" in
start)
    # 在此添加 DNS 服务启动后需要执行的操作
    ;;
stop)
    # 在此添加 DNS 服务停止前需要执行的操作
    ;;
esac

exit 0
