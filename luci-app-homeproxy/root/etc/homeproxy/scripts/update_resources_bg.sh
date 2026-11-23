#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2025 ImmortalWrt.org

# Run one resource update detached from rpcd and record the outcome for the
# Service Status page. The download involves two remote requests and must not
# happen inside the ubus call, otherwise rpcd stops serving every other page.

NAME="homeproxy"
SCRIPTS_DIR="/etc/$NAME/scripts"
RUN_DIR="/var/run/$NAME"

listtype="$1"
case "$listtype" in
	"china_ip4"|"china_ip6"|"gfw_list"|"china_list") ;;
	*)
		exit 255
		;;
esac

mkdir -p "$RUN_DIR"
status_file="$RUN_DIR/update_resources-$listtype.status"

# The RPC already recorded the "running" state before spawning this task.
# Bound the whole task as well: a wget stuck behind a restarting proxy would
# otherwise hold the global update lock forever.
if command -v timeout > "/dev/null" 2>&1; then
	timeout 240 "$SCRIPTS_DIR/update_resources.sh" "$listtype"
	rc=$?
else
	"$SCRIPTS_DIR/update_resources.sh" "$listtype"
	rc=$?
fi

# Publish the result atomically: the view may poll while this runs and must
# never observe a truncated (empty) status file.
echo "$rc" > "$status_file.tmp"
mv -f "$status_file.tmp" "$status_file"

exit "$rc"
