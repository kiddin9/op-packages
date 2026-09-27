#!/bin/sh
# /usr/share/AdGuardHome/watchconfig.sh

PATH="/usr/sbin:/usr/bin:/sbin:/bin"

configpath=$(uci -q get adguardhome.config.config_file)
[ -z "$configpath" ] && configpath="/etc/adguardhome/adguardhome.yaml"

while :
do
	sleep 10
	if [ -f "$configpath" ]; then
		/etc/init.d/adguardhome do_redirect 1
		break
	fi
done

exit 0
