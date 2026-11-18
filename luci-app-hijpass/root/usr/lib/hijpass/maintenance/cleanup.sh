#!/bin/sh

. /usr/lib/hijpass/common.sh

# 仅删除选定 section 的旧配置；固定目录与文件名由 ucode 校验、组装。
id=${2:-}
plan=$(hijpass_run_ucode "$HIJPASS_LIB/maintenance/cleanup.uc" "$@") || exit 1
json_load "$plan" || exit 1
json_get_vars directory keep
removed=0
for path in "$directory"/*-"$id".json; do
    [ "$path" != "$keep" ] || continue
    [ ! -d "$path" ] || continue
    if [ -e "$path" ] || [ -L "$path" ]; then
        rm -f -- "$path" || { hijpass_log ERROR "Cannot remove obsolete configuration: section=$id"; exit 1; }
        removed=$((removed + 1))
    fi
done
level=DEBUG
[ "$removed" -eq 0 ] || level=INFO
hijpass_log "$level" "Obsolete configurations removed: section=$id, files=$removed"
