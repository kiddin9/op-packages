#!/bin/sh
# 参数：reset 重建透明代理路由，remove 清理路由；不需要读取 UCI。
# 固定使用表 233 和 fwmark 0x1，与防火墙模板中的透明代理标记对应。
. /usr/lib/hijpass/common.sh
table=233
mark=0x1

if [ "$#" -ne 1 ]; then
    echo "usage: $0 reset|remove" >&2
    exit 1
fi

action="$1"
case "$action" in
    reset|remove) ;;
    *) echo "unknown route action: $action" >&2; exit 1 ;;
esac
hijpass_log DEBUG "Policy route $action: table=$table, mark=$mark"

for family in -4 -6; do
    # 清除重复启动留下的同一标记规则；只匹配本应用的 mark 和 table。
    # 不存在规则或路由时可正常清理，不修改系统共享的 rt_tables 文件。
    while ip "$family" rule del fwmark "$mark" table "$table" 2>/dev/null; do
        :
    done
    ip "$family" route del local default dev lo table "$table" 2>/dev/null || :

    if [ "$action" = reset ]; then
        # 本地路由是策略规则的前提；设置失败即结束本次路由操作。
        hijpass_run_logged "Add $family local route" ip "$family" route add local default dev lo table "$table" || exit $?
        hijpass_run_logged "Add $family policy rule" ip "$family" rule add fwmark "$mark" table "$table" || exit $?
    fi
done
hijpass_log INFO "Policy routes $action completed for IPv4 and IPv6"
