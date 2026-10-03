#!/bin/sh
BACKUP_DIR="/etc/config.bak.$(date +%s)"
mkdir -p "$BACKUP_DIR"
COUNT=0
for f in network firewall dhcp wireless system wizard netwizard taskplan; do
    if [ -f /etc/config/$f ]; then
        cp /etc/config/$f "$BACKUP_DIR/"
        COUNT=$((COUNT + 1))
    fi
done
echo "Backed up $COUNT files to $BACKUP_DIR"
ls -1 "$BACKUP_DIR"
