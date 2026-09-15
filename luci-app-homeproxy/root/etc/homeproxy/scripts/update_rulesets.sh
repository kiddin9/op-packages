#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org

CACHE_PATH="$(uci -q get homeproxy.cache.path)"
[ -n "$CACHE_PATH" ] || CACHE_PATH="/etc/homeproxy/cache.db"

rm -f "$CACHE_PATH"
/etc/init.d/homeproxy restart
