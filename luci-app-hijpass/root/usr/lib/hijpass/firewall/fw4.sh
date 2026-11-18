#!/bin/sh
# fw4 的 script include：只加载已生成的规则，不生成配置或再次 reload。
. /usr/lib/hijpass/common.sh
HIJPASS_LOG_SOURCE=/usr/lib/hijpass/firewall/fw4.sh
rules=/etc/hijpass/fw4-rules.nft
hook=/etc/hijpass/hook/nft-hook.sh

# fw4 每次重载都会重建 SYN 链；直接重复加载时，仅替换带本应用注释的规则。
sync_syn_exemption() {
    local chain commands
    chain=$(nft -a list chain inet fw4 syn_flood 2>/dev/null) || return 0
    commands=$(printf '%s\n' "$chain" | sed -n 's/.*comment "hijpass: skip global SYN limit" # handle \([0-9][0-9]*\)[[:space:]]*$/delete rule inet fw4 syn_flood handle \1/p')
    if [ "$1" = add ]; then
        commands="$commands
insert rule inet fw4 syn_flood meta l4proto tcp ct direction original meta mark 0x1 ct mark { 0x1, 0x3 } socket transparent 1 counter return comment \"hijpass: skip global SYN limit\""
    fi
    [ -n "$commands" ] || return 0
    printf '%s\n' "$commands" | hijpass_run_logged 'Update hijpass SYN limit exemption' nft -f -
}

# 先撤销旧豁免，确保无规则文件或加载失败时不会残留。
sync_syn_exemption remove || exit 1
if nft list table inet hijpass >/dev/null 2>&1; then
    hijpass_run_logged 'Remove hijpass nft table' nft delete table inet hijpass || exit 1
fi
[ -f "$rules" ] || exit 0
hijpass_run_logged 'Apply hijpass nft rules' nft -f "$rules" || exit 1
sync_syn_exemption add || exit 1
[ ! -x "$hook" ] || hijpass_run_logged 'Run hijpass NFT Hook' "$hook" || exit 1
hijpass_log INFO 'Applied hijpass client nft rules'
