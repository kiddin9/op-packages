#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

set -eu

NAME="homeproxy"
RUN_DIR="/var/run/$NAME"
REQUEST_FILE="$RUN_DIR/provider-update-id"
LOCK_FILE="$RUN_DIR/provider-update-v2.lock"
LOG_FILE="$RUN_DIR/homeproxy.log"
PROVIDER_ID="${1:-}"

log() {
	printf '%s [SUBSCRIBE] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

case "$PROVIDER_ID" in
	*[!0-9a-f]*|'') exit 1 ;;
esac
[ "${#PROVIDER_ID}" -eq 32 ] || exit 1

mkdir -p "$RUN_DIR"
if ! lock -n "$LOCK_FILE" 2>/dev/null; then
	log "Another provider update is running; waiting for it to finish..."
	lock "$LOCK_FILE"
fi

umask 077
printf '%s\n' "$PROVIDER_ID" > "$REQUEST_FILE"
cleanup() {
	rm -f "$REQUEST_FILE"
	lock -u "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Give the Clash API response time to reach the panel before HomeProxy restarts.
log "Updating provider $PROVIDER_ID from Clash API..."
sleep 1
if /etc/homeproxy/scripts/update_subscriptions.uc; then
	log "Provider $PROVIDER_ID update completed."
else
	log "Provider $PROVIDER_ID update failed."
	exit 4
fi
