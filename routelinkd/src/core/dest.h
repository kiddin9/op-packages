/*
 * Destinations (design §10, P4): where a device's internet traffic goes, summed per peer address over an
 * hour; at the end of the hour the top RL_DEST_TOP peers are written as one record per device, with the
 * host names the DNS cache knew then. Queries merge the hours of a range with the same map.
 */
#ifndef RL_DEST_H
#define RL_DEST_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define RL_DEST_TOP 100
#define RL_DEST_HOST_MAX 63

typedef struct {
	uint8_t family; /* 4 or 6 */
	uint8_t addr[16];
	uint64_t rx, tx;
	uint32_t conns;
	char host[RL_DEST_HOST_MAX + 1]; /* "" when unknown */
} rl_dest_entry;

typedef struct rl_dest_map rl_dest_map;

rl_dest_map *rl_dest_map_new(size_t capacity);
void rl_dest_map_free(rl_dest_map *m);
void rl_dest_map_clear(rl_dest_map *m);
size_t rl_dest_map_count(const rl_dest_map *m);
/*
 * Adds traffic to a peer (host may be NULL, which keeps the known name; a name replaces it: the latest DNS
 * answer is the best guess). When the map is full, peers it has not
 * seen go uncounted and false is returned.
 */
bool rl_dest_add(rl_dest_map *m, uint8_t family, const uint8_t *addr, const char *host, uint64_t rx, uint64_t tx,
		 uint32_t conns);
/* Adds an entry of another hour (queries merge newest first): its name only where none is known yet. */
bool rl_dest_merge(rl_dest_map *m, const rl_dest_entry *e);
/* The n busiest peers (rx + tx), busiest first. */
size_t rl_dest_top(const rl_dest_map *m, rl_dest_entry *out, size_t n);

/*
 * Record: hour u32 | mac 6 | count u8 | per entry: family u8 | addr 4/16 | rx u64 | tx u64 | conns u32 |
 * host length u8 | host. Entries that do not fit in size are left out (they come last: least traffic).
 * Returns the length, 0 when not even the header fits.
 */
size_t rl_dest_encode(uint8_t *out, size_t size, int64_t hour, const uint8_t mac[6], const rl_dest_entry *e, size_t n);
typedef bool (*rl_dest_cb)(const rl_dest_entry *e, void *ctx);
/* Calls cb for every entry; -1 when the record is malformed (entries before the damage were delivered). */
int rl_dest_decode(const uint8_t *rec, size_t len, int64_t *hour, uint8_t mac[6], rl_dest_cb cb, void *ctx);

#endif
