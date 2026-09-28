#!/bin/sh
# Open-Box 卸载清理脚本
set -eu

INSTALL_ROOT="/opt/open-box"
STATUS_PATH="/tmp/openbox-uninstall.status"
PURGE=0
DETACH=0

while [ $# -gt 0 ]; do
	case "$1" in
		--purge) PURGE=1; shift ;;
		--detach) DETACH=1; shift ;;
		*) shift ;;
	esac
done

if [ "$DETACH" = "1" ]; then
	_args=""
	[ "$PURGE" = "1" ] && _args="--purge"
	nohup sh "$0" $_args >/dev/null 2>&1 &
	echo "卸载已在后台启动"
	exit 0
fi

{
	echo "pid=$$"
	echo "stage=stopping"
} > "$STATUS_PATH" 2>/dev/null || true

/etc/init.d/openbox stop >/dev/null 2>&1 || true
/etc/init.d/openbox-panel stop >/dev/null 2>&1 || true
/etc/init.d/openbox disable >/dev/null 2>&1 || true
/etc/init.d/openbox-panel disable >/dev/null 2>&1 || true

{
	echo "pid=$$"
	echo "stage=firewall"
} > "$STATUS_PATH" 2>/dev/null || true

if command -v uci >/dev/null 2>&1; then
	uci -q delete firewall.openbox_panel || true
	uci -q delete firewall.openbox_dns || true
	uci -q delete firewall.openbox_tun_forward || true
	uci -q delete firewall.openbox_tun_input || true
	uci -q delete firewall.openbox_v6block || true
	for _ob_rule in $(uci -q show firewall 2>/dev/null | sed -n 's/^firewall\.\(openbox_srv_[A-Za-z0-9_]*\)=rule$/\1/p'); do
		uci -q delete "firewall.$_ob_rule" || true
	done
	if [ -n "$(uci -q changes firewall)" ]; then
		uci -q commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1 || true
	fi
fi

{
	echo "pid=$$"
	echo "stage=files"
} > "$STATUS_PATH" 2>/dev/null || true

rm -f /etc/init.d/openbox /etc/init.d/openbox-panel
rm -f /www/luci-static/resources/view/openbox/main.js /www/luci-static/resources/view/openbox/status.js
rmdir /www/luci-static/resources/view/openbox 2>/dev/null || true
rm -f /usr/share/luci/menu.d/luci-app-openbox.json
rm -f /usr/share/rpcd/acl.d/luci-app-openbox.json
[ -L /usr/bin/open-box ] && rm -f /usr/bin/open-box
rm -rf /tmp/luci-*cache* 2>/dev/null || true

if [ "$PURGE" = "1" ]; then
	rm -rf "$INSTALL_ROOT"
else
	for entry in "$INSTALL_ROOT"/*; do
		[ -e "$entry" ] || continue
		base=$(basename -- "$entry")
		[ "$base" = "data" ] && continue
		rm -rf "$entry"
	done
fi

{
	echo "pid=$$"
	echo "stage=done"
} > "$STATUS_PATH" 2>/dev/null || true

echo "Open-Box 卸载完成"
