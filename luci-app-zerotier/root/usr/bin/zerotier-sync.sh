#!/bin/sh

PERSIST_DIR=$(uci -q get zerotier.global.config_path 2>/dev/null)
[ -n "$PERSIST_DIR" ] || PERSIST_DIR="/etc/zerotier"
RUNTIME_DIR="/var/lib/zerotier-one"

# config_path pointing at the runtime home itself would sync a dir onto itself
[ "$PERSIST_DIR" = "$RUNTIME_DIR" ] && exit 0
# copy_config_path=0 links CONFIG_PATH to config_path: same directory, nothing
# to sync (and copying files onto themselves would just error)
[ "$(readlink -f "$RUNTIME_DIR" 2>/dev/null)" = "$(readlink -f "$PERSIST_DIR" 2>/dev/null)" ] && exit 0

[ -d "$RUNTIME_DIR" ] || exit 0
mkdir -p "$PERSIST_DIR" || exit 1

# State dirs whose contents must survive a restart. peers.d is deliberately
# absent: it is a pure discovery cache that zerotier-one rebuilds from
# scratch on every start, so persisting it only costs flash writes. It is
# still pruned below, so leftovers from older versions get cleaned up.
STATE_DIRS="networks.d moons.d controller.d"

# 1) Prune: drop persisted files the daemon has removed from the runtime
#    dir. Without this, e.g. a left network's networks.d/<id>.conf survives
#    here and is copied back on the next start, rejoining the network (an
#    <id>.conf present there means "join").
for d in $STATE_DIRS peers.d; do
	[ -d "$PERSIST_DIR/$d" ] || continue
	find "$PERSIST_DIR/$d" -type f | while read -r f; do
		rel="${f#"$PERSIST_DIR"/}"
		[ -f "$RUNTIME_DIR/$rel" ] || rm -f "$f"
	done
	find "$PERSIST_DIR/$d" -depth -type d -empty -delete 2>/dev/null
done

# 2) Copy the state dirs. One `cp -a` per directory instead of a mkdir and a
#    cp per file: this runs on every Save&Apply, every service stop and every
#    "Backup Now", so the per-file form forked hundreds of processes on a
#    controller node and rewrote all of peers.d to flash each time.
for d in $STATE_DIRS; do
	[ -d "$RUNTIME_DIR/$d" ] || continue
	mkdir -p "$PERSIST_DIR/$d"
	cp -a "$RUNTIME_DIR/$d/." "$PERSIST_DIR/$d/" 2>/dev/null
done

# 3) Top-level files only (identity.secret, planet, local.conf, *.secret,
#    ...). They all live flat in PERSIST_DIR, so no mkdir is needed.
cd "$RUNTIME_DIR" || exit 1

find . -maxdepth 1 -type f \
    ! -name 'zerotier-one.pid' \
    ! -name 'zerotier-one.port' \
    ! -name 'zerotier.log' \
    ! -name 'metrics.prom' \
    ! -name '.DS_Store' \
    -exec cp -a {} "$PERSIST_DIR/" \;

logger -t zerotier-sync "synced runtime config to $PERSIST_DIR"
