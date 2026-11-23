/* Open buckets for every tier, closed into records as time passes, plus live per-device rates. */
#ifndef RL_AGG_H
#define RL_AGG_H

#include <stddef.h>
#include <stdint.h>

#include "core/classify.h"
#include "core/rec.h"
#include "core/timeutil.h"

typedef struct rl_agg rl_agg;
/* Called for every record of a bucket that just closed; records arrive in (dev, cls) order. */
typedef void (*rl_close_cb)(rl_tier tier, const rl_rec *r, void *ctx);

rl_agg *rl_agg_new(rl_close_cb on_close, void *ctx);
void rl_agg_free(rl_agg *a);

/* Adds bytes to the open bucket of every tier. Zero bytes still mark the key as present. */
void rl_agg_add(rl_agg *a, int64_t now, uint16_t dev, rl_class cls, uint64_t rx, uint64_t tx);
/* Records the current number of connections of a device (kept as the peak per bucket). */
void rl_agg_conns(rl_agg *a, int64_t now, uint16_t dev, uint32_t conns);
/* Closes every bucket that ended at or before now. Time that went backwards is ignored. */
void rl_agg_tick(rl_agg *a, int64_t now);
/* Current (unfinished) records of a tier; empty until something was added. */
void rl_agg_open(const rl_agg *a, rl_tier tier, rl_rec_cb cb, void *ctx);
/* Drops all open buckets and rates (reset of the traffic data). */
void rl_agg_reset(rl_agg *a);
/*
 * Emits the open bucket of one tier as (partial) records and empties it; the bucket stays open.
 * Used for the minute tier before a shutdown: records are summed, so a second record for the same
 * minute after the restart is fine.
 */
void rl_agg_flush(rl_agg *a, rl_tier tier);
/* Adds a stored record to the open bucket of a tier (rebuilding open buckets after a restart). */
void rl_agg_hydrate(rl_agg *a, int64_t now, rl_tier tier, const rl_rec *r);
/* Start of the open bucket of a tier (0 when nothing is open). */
int64_t rl_agg_open_start(const rl_agg *a, rl_tier tier);

typedef struct {
	uint16_t dev;
	uint64_t rx_rate, tx_rate; /* bytes per second, all classes */
} rl_rate;

/* Ends a sample pass: rates are the bytes added since the previous pass over the elapsed time. */
void rl_agg_sample_done(rl_agg *a, int64_t now_ms);
/* Devices with traffic in the last pass (others are 0). */
size_t rl_agg_rates(const rl_agg *a, const rl_rate **out);

#endif
