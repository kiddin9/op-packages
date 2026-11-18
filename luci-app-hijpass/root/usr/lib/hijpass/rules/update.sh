#!/bin/sh

# 公共入口：只读查询不创建任务，所有更新共用任务登记和执行互斥。
. /usr/lib/hijpass/common.sh
if [ "${1:-}" = query ]; then
    exec ucode -S -- "$HIJPASS_LIB/rules/rulescli.uc" "$@"
fi
exec "$HIJPASS_LIB/rpc/jobs.sh" run rules "$@"
