#!/bin/sh

# 功能入口负责命令执行；相邻 ucode 脚本只校验、转换及生成数据。
. /usr/lib/hijpass/common.sh
stage=accounts
trap 'code=$?; if [ "$code" -ne 0 ]; then hijpass_log ERROR "Hijpass installation setup failed: stage=$stage, exit=$code"; fi' EXIT
hijpass_log INFO 'Preparing hijpass installation'

# 安装时准备系统账户、目录与防火墙入口；旧配置转换独立执行。
for file in group passwd shadow; do
    case "$file" in
        group) entry='hijpass:x:4396:hijpass' ;;
        passwd) entry='hijpass:x:0:4396:hijpass:/var/run/hijpass:/bin/false' ;;
        shadow) entry='hijpass:x:0:0:99999:7:::' ;;
    esac
    if ! grep -q '^hijpass:' "/etc/$file"; then
        # 已有账户文件可能没有尾换行；先补分隔，避免与最后一个账户连在一起。
        [ ! -s "/etc/$file" ] || [ -z "$(tail -c 1 "/etc/$file")" ] || printf '\n' >>"/etc/$file" || exit 1
        printf '%s\n' "$entry" >>"/etc/$file" || exit 1
    fi
done
stage=migration
hijpass_run_ucode "$HIJPASS_LIB/install/migrate.uc" || exit 1
# 让 crond 立即丢弃已移除的旧任务；任务内容的转换只在安装迁移脚本中进行。
stage=cron
[ ! -x /etc/init.d/cron ] || hijpass_run_logged 'Cron reload' /etc/init.d/cron restart || exit 1
# 防火墙 include 是安装配置，不属于旧字段迁移。
stage=firewall-include
uci -q set firewall.hijpass=include &&
    uci -q set firewall.hijpass.type=script &&
    uci -q set firewall.hijpass.path=/usr/lib/hijpass/firewall/fw4.sh &&
    uci -q commit firewall || exit 1
stage=directories
mkdir -p /etc/hijpass/client /etc/hijpass/server /tmp/hijpass/log /tmp/hijserver/log || exit 1
stage=luci-cache
rm -f /tmp/hijpass_last_update || exit 1
rm -rf /tmp/luci-*cache || exit 1
hijpass_log INFO 'Hijpass installation setup completed'
