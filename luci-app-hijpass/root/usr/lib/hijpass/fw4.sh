#!/bin/sh

. /usr/lib/hijpass/app-logger.sh

log_debug "/usr/lib/hijpass/fw4.sh"

NFT_HOOK=$(uci -q get hijpass.@hijpass[0].nft_hook || :)

NFT_CONF=/etc/hijpass/fw4-rules.nft
TABLE_NAME=hijpass

if nft list tables | grep -q "$TABLE_NAME"; then
    log_info "Deleting existing table: $TABLE_NAME"
    nft delete table inet "$TABLE_NAME"
fi

if [ -f "$NFT_CONF" ]; then
    log_info "Loading nftables rules from: $NFT_CONF"
    nft -f "$NFT_CONF"
    if [ -n "$NFT_HOOK" ] && [ -f "$NFT_HOOK" ]; then
        log_info "Executing nft hook script: $NFT_HOOK"
        $NFT_HOOK || log_error "Execute nft hook failed"
    fi
fi