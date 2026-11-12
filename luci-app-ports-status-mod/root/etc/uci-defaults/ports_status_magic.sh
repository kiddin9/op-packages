#!/bin/sh
# 
# Copyright 2025-2026 Rafał Wabik (IceG) - From eko.one.pl forum
# 
# MIT
# 

PORTS_ORIG="/www/luci-static/resources/view/status/include/29_ports.js"
PORTS_BAK="/www/luci-static/resources/view/status/include/29_ports.bak"
PORTS_CUSTOM="/www/luci-static/resources/view/status/include/29_ports_custom.js"
USER_DEFINED_PORTS="/etc/user_defined_ports.json"

sleep 5

if [ -f "$PORTS_ORIG" ]; then
    mv "$PORTS_ORIG" "$PORTS_BAK"
fi

if [ -f "$PORTS_CUSTOM" ]; then
    mv "$PORTS_CUSTOM" "$PORTS_ORIG"
fi

if [ -f "$USER_DEFINED_PORTS" ]; then
    chmod 664 "$USER_DEFINED_PORTS" >/dev/null 2>&1 &
fi

chmod +x /usr/libexec/rpcd/ports-status-mod >/dev/null 2>&1 &

rm -rf /tmp/luci-indexcache >/dev/null 2>&1 &
rm -rf /tmp/luci-* >/dev/null 2>&1 &
rm -rf /tmp/luci-modulecache/ >/dev/null 2>&1 &

exit 0
