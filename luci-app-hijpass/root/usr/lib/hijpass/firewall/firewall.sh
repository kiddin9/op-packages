#!/bin/sh
# reset：生成、校验并写入规则；remove：删除规则。成功后统一重载 fw4。
. /usr/lib/hijpass/common.sh
rules=/etc/hijpass/fw4-rules.nft

[ "$#" -ge 1 ] || { echo "usage: $0 reset|remove" >&2; exit 1; }
action=$1
shift
case "$action" in
    reset)
        hijpass_run_logged 'Generate hijpass firewall rules' hijpass_run_ucode "$HIJPASS_LIB/firewall/generatecli.uc" "$rules" "$@" || exit $?
        hijpass_log INFO 'Reloading firewall after updating hijpass client rules' ;;
    remove)
        hijpass_run_logged 'Remove hijpass firewall rules' rm -f "$rules" || exit $?
        hijpass_log INFO 'Reloading firewall after removing hijpass client rules' ;;
    *) echo "unknown firewall action: $action" >&2; exit 1 ;;
esac
hijpass_run_logged 'Reload firewall for hijpass' fw4 reload
