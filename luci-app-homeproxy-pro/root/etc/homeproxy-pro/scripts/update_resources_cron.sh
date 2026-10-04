#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Refresh the four resource lists (china_ip4 / china_ip6 / gfw_list /
# china_list) and reload the service only when one of them actually moved.
#
# Scheduled unconditionally - see hp_sync_resource_cron() in runtime/service.sh
# for why this is not behind the subscription auto_update switch.
#
# Why a reload is needed at all, when the sing-box side reloads itself: the
# lists feed two consumers. update_resources.sh regenerates the sing-box
# rule-sets from them, and sing-box watches those files and picks a new one up
# in place. The firewall reads the same lists directly when firewall_post.ut is
# rendered into the nft sets, and that only happens on an fw4 reload - so
# without this the kernel kept routing from the previous list while sing-box
# had already moved to the new one, and the two halves of the same split
# disagreed. That window is invisible: mainland traffic still works, it just
# stops being mainland for whatever the new entries added.
#
# update_resources.sh exits 3 when a list is already current, so a day with no
# upstream movement costs one round of requests and no interruption.

SCRIPTS_DIR="/etc/homeproxy-pro/scripts"
NAME="homeproxy-pro"
RUN_DIR="/var/run/$NAME"
LOG_PATH="$RUN_DIR/$NAME.log"

mkdir -p "$RUN_DIR" 2>/dev/null

log() {
	printf '%s %s\n' "$(date "+%Y-%m-%d %H:%M:%S")" "$*" >> "$LOG_PATH"
}

changed=0
for i in "china_ip4" "china_ip6" "gfw_list" "china_list"; do
	"$SCRIPTS_DIR"/update_resources.sh "$i"
	case "$?" in
	0) changed=1 ;;
	esac
done

[ "$changed" = "1" ] || exit 0

log "A resource list changed; reloading $NAME so the nft sets catch up."
if ! /etc/init.d/$NAME reload >>"$LOG_PATH" 2>&1; then
	log "Warning: the $NAME reload after a resource update failed; the firewall still uses the previous list."
fi
