#!/bin/sh
DIR="$1"
[ -z "$DIR" ] && { echo "Usage: restore.sh <backup-dir>"; exit 1; }
[ ! -d "$DIR" ] && { echo "Directory not found: $DIR"; exit 1; }

SAFETY="/etc/config.bak.pre-restore.$(date +%s)"
mkdir -p "$SAFETY"
for f in "$DIR"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    [ -f "/etc/config/$base" ] && cp "/etc/config/$base" "$SAFETY/"
    cp "$f" "/etc/config/$base"
done

for c in network firewall dhcp wireless wizard netwizard taskplan; do
    uci -q commit $c 2>/dev/null
done

/etc/init.d/network reload >/dev/null 2>&1 &
/etc/init.d/firewall reload >/dev/null 2>&1 &

echo "Restored from $DIR"
echo "Previous state saved to $SAFETY"
