#!/bin/sh

# 功能入口负责命令执行；相邻 ucode 脚本只校验、转换及生成数据。
. /usr/lib/hijpass/common.sh

target=${1:-}
[ "$#" -eq 0 ] || shift
plan=$(hijpass_run_ucode "$HIJPASS_LIB/rules/rulescli.uc" match-plan "$target" "$@") || exit 1
json_load "$plan" || exit 1
json_get_vars kind lookup
tags=
if [ "$lookup" = 1 ]; then tags=$("$HIJPASS_LIB/rules/geoview.sh" -l "$kind" "$target") || exit $?; fi
printf '%s\n' "$tags" | hijpass_run_ucode "$HIJPASS_LIB/rules/rulescli.uc" match "$target" "$@"
