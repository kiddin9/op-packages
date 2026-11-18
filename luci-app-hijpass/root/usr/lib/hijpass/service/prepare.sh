#!/bin/sh
# 生成核心配置和 procd 实例，也可单独更新服务端端口规则。
. /usr/lib/hijpass/common.sh
server=
[ "${1:-}" != server ] || { server=server; shift; }
data="$HIJPASS_LIB/service/preparecli.uc"
run_data() {
    if [ -n "$server" ]; then
        hijpass_run_ucode "$data" server "$@"
    else
        hijpass_run_ucode "$data" "$@"
    fi
}
case "${1:-}" in
    server-files) run_data "$@"; exit $? ;;
esac
settings=$(run_data settings "$@") || exit 1
json_load "$settings" || exit 1
json_get_vars enabled geo_convert
if [ "$enabled" = 1 ]; then
    run_data configs "$@" || exit 1
    if [ -z "$server" ]; then
        [ "$geo_convert" != 1 ] || "$HIJPASS_LIB/rules/geoview.sh" --convert "$@" || exit 1
        "$HIJPASS_LIB/rules/geoview.sh" dns "$@" || exit 1
    fi
    json_select log_paths
    json_get_keys entries
    for entry in $entries; do
        json_get_var path "$entry"
        mkdir -p "$(dirname -- "$path")" || exit 1
    done
fi
plan=$(run_data prepare "$@") || exit 1
printf '%s\n' "$plan"
