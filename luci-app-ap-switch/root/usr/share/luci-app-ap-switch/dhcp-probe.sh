#!/bin/sh

[ "$1" = "bound" ] || exit 0

echo "$ip" > /tmp/ap_switch_probed_ip
