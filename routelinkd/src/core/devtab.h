/* Devices by MAC with stable indexes (records refer to the index), first/last seen and presence. */
#ifndef RL_DEVTAB_H
#define RL_DEVTAB_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/addr.h"

#define RL_OFFLINE_AFTER 180 /* seconds without any activity */

typedef struct {
	rl_mac mac;
	uint16_t idx;
	int64_t first_seen, last_seen; /* persisted */
	int64_t last_active;           /* traffic, neighbour confirmation or lease renewal */
	bool online;
	char hostname[64]; /* from DHCP leases, refreshed at runtime */
	char name[64];     /* dhcp host name or routelink_alias, refreshed at runtime */
} rl_device;

typedef struct rl_devtab rl_devtab;

rl_devtab *rl_devtab_new(void);
void rl_devtab_free(rl_devtab *t);

/*
 * Loads devices.json, falling back to devices.json.bak. Returns 0 when one of them loaded or neither
 * exists, -1 when both are damaged (the table stays empty).
 */
int rl_devtab_load(rl_devtab *t, const char *path);
/* Writes path.tmp, keeps the previous file as path.bak, then renames. */
int rl_devtab_save(const rl_devtab *t, const char *path);

/* Finds or adds a device; *created is set for new ones. NULL when the table is full. */
rl_device *rl_devtab_get(rl_devtab *t, const rl_mac *mac, int64_t now, bool *created);
rl_device *rl_devtab_find(rl_devtab *t, const rl_mac *mac);
rl_device *rl_devtab_by_idx(rl_devtab *t, uint16_t idx);
size_t rl_devtab_count(const rl_devtab *t);
/* Device i in index order (i < count). */
rl_device *rl_devtab_at(rl_devtab *t, size_t i);

void rl_devtab_touch(rl_device *d, int64_t now);
/* Online after any activity, offline after RL_OFFLINE_AFTER s without; cb runs on every change. */
void rl_devtab_presence(rl_devtab *t, int64_t now, void (*cb)(rl_device *d, bool online, void *ctx), void *ctx);
void rl_devtab_clear(rl_devtab *t);

#endif
