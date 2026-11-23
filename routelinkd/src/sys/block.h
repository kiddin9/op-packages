/*
 * Cutting devices off the internet (quota action "block", P4 plan §0.3): core/nftgen's table loaded with
 * `nft -f -`. The table is RouteLink's own, so fw4 reloads leave it alone; it is checked every minute while
 * devices are blocked all the same. Dropping the devices' conntrack entries (sys/ct) is the caller's part.
 */
#ifndef RL_BLOCK_H
#define RL_BLOCK_H

#include <stdbool.h>
#include <stddef.h>

#include "core/addr.h"
#include "core/nftgen.h"

#define RL_BLOCK_MAX_NETS 64

typedef struct rl_block rl_block;

rl_block *rl_block_new(void);
/* clear: delete the table first (the daemon stops). */
void rl_block_free(rl_block *b, bool clear);
/*
 * The blocked devices and the local networks they may still reach; loads the table when either changed
 * (or the last load failed). 0, or -1 when nft failed.
 */
int rl_block_set(rl_block *b, const rl_mac *macs, size_t n, const rl_nft_net *local, size_t n_local);
/* Whether mac is blocked by the table as loaded now. */
bool rl_block_has(const rl_block *b, const rl_mac *mac);
/* Forgets a failure: the next set loads the table again (configuration reload). */
void rl_block_retry(rl_block *b);
/* Loads the table again when it went missing. */
void rl_block_check(rl_block *b);
/* Why loading failed, "" when fine. */
const char *rl_block_error(const rl_block *b);

#endif
