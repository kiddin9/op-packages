/*
 * Restart recovery. Only the minute tier is the source of truth on disk for the most recent data: hour,
 * day and month buckets live in RAM until they close. After a restart (or a crash) this module
 *  1. writes the hour/day/month records of buckets that ended while the daemon was not running,
 *     summed from the next finer tier, and
 *  2. rebuilds the open hour/day/month buckets from the stored finer records,
 * so a restart loses at most the minute records that were not committed yet.
 */
#ifndef RL_RECOVER_H
#define RL_RECOVER_H

#include <stdint.h>

#include "core/agg.h"
#include "core/store.h"

/* Number of catch-up records written. Call with an agg that has nothing open yet. */
int rl_recover(rl_store *s, rl_agg *a, int64_t now);

#endif
