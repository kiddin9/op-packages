#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 ImmortalWrt.org

SCRIPTS_DIR="/etc/homeproxy/scripts"

# update_resources.sh exit codes: 0 updated, 1 failed, 2 another run holds the
# lock, 3 already up to date.
changed=0
for i in "china_ip4" "china_ip6" "gfw_list" "china_list" "geoip_cn" "geosite_cn"; do
	"$SCRIPTS_DIR"/update_resources.sh "$i"
	[ "$?" -eq 0 ] && changed=1
done

# The nft sets (china_ip4/ip6.txt) and the dnsmasq snippets (gfw_list.txt,
# china_list.txt) are rendered from those files, and the client rule-sets are
# loaded from the two .srs files, so a downloaded list only takes effect after
# they have been regenerated. Without this the daily cron update rewrote the
# files on disk and nothing else.
[ "$changed" -eq 0 ] || /etc/init.d/homeproxy refresh_lists

# update_subscriptions.uc restarts the service itself when it changed the UCI
# configuration.
"$SCRIPTS_DIR"/update_subscriptions.uc
