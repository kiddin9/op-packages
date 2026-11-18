#!/bin/sh
# 删除本服务的旧任务后追加新任务；重载由 init 负责。
service=$1 schedule=$2 logs=$3
cron=/etc/crontabs/root
mkdir -p "$(dirname "$cron")" || exit 1
touch "$cron" || exit 1
sed -i "\| /usr/lib/hijpass/maintenance/logs\.sh $service\$|d" "$cron" || exit 1
if [ "$service" = hijpass ]; then
    sed -i '\| /usr/lib/hijpass/rules/update\.sh update|d' "$cron" || exit 1
fi
if [ -n "$schedule" ]; then
    printf '%s /usr/lib/hijpass/rules/update.sh update --scheduled\n' "$schedule" >>"$cron" || exit 1
fi
if [ "$logs" = 1 ]; then
    printf '*/10 * * * * /usr/lib/hijpass/maintenance/logs.sh %s\n' "$service" >>"$cron" || exit 1
fi
