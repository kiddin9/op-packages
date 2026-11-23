/*
 * Latency history and the outage log over core/series (P3 plan §0.3, §1.1-1.2): the open minute and hour
 * buckets of every probe target, restart recovery of the hour records from the minutes, the table that keeps
 * target ids stable while the configured targets change, and the `latency` and `outages` queries.
 */
#ifndef RL_LATENCY_H
#define RL_LATENCY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/addr.h"
#include "core/probe.h"
#include "core/series.h"
#include "core/timeutil.h"

#define RL_LAT_KIND_MINUTE 0x4c01
#define RL_LAT_KIND_HOUR 0x4c02
#define RL_OUTAGE_KIND 0x4f01

#define RL_LAT_INTERVAL 10     /* seconds between probe rounds */
#define RL_LAT_TIMEOUT_MS 2000 /* an echo request unanswered this long is lost */
#define RL_LAT_IDS 64          /* target ids 0..63 */
#define RL_LAT_GATEWAY 0       /* id of the WAN's next hop, whatever its address */

/* ---- target table (latency.targets.json) ---- */

typedef struct {
	bool used;
	rl_ip ip;      /* the gateway's latest next hop; family 0 while unknown */
	int64_t since; /* records of this id from before belong to an earlier target (the id was reused) */
} rl_lat_slot;

typedef struct {
	rl_lat_slot slot[RL_LAT_IDS];
} rl_lat_targets;

/* Empty table: only the gateway slot. */
void rl_lat_targets_init(rl_lat_targets *t);
/* Loads path; a missing file gives an empty table, a damaged one too (returns -1 then). */
int rl_lat_targets_load(rl_lat_targets *t, const char *path);
int rl_lat_targets_save(const rl_lat_targets *t, const char *path);
/*
 * The id of a custom target: its existing id, else a free one, else the one assigned longest ago whose bit
 * is not in keep (its earlier records stop counting). -1 when every id is kept. *changed is set when the
 * table changed.
 */
int rl_lat_targets_assign(rl_lat_targets *t, const rl_ip *ip, uint64_t keep, int64_t now, bool *changed);
/* Records the gateway's address; true when it changed. */
bool rl_lat_targets_gateway(rl_lat_targets *t, const rl_ip *ip);
/* Ids (bit per id) whose address is ip: custom targets and the gateway's current next hop. */
uint64_t rl_lat_targets_find(const rl_lat_targets *t, const rl_ip *ip);

/* ---- open buckets ---- */

/* A closed (or flushed) latency record; tier is RL_TIER_MINUTE or RL_TIER_HOUR. */
typedef void (*rl_lat_rec_cb)(rl_tier tier, const uint8_t rec[RL_SERIES_REC_SIZE], void *ctx);

typedef struct {
	int64_t start[2]; /* minute, hour bucket; 0 = nothing open */
	rl_probe_agg acc[2][RL_LAT_IDS];
	rl_lat_rec_cb cb;
	void *ctx;
} rl_lat;

void rl_lat_init(rl_lat *l, rl_lat_rec_cb cb, void *ctx);
/* A probe of target id at ts (the round's start); buckets that ended before ts are written first. */
void rl_lat_add(rl_lat *l, int64_t ts, int id, bool answered, uint32_t rtt_us);
/* Writes the buckets that ended by now. */
void rl_lat_tick(rl_lat *l, int64_t now);
/* Writes the open minute (and the open hour) as records and starts them over: a bucket may get several
 * records, readers merge them. */
void rl_lat_flush(rl_lat *l, bool hour);
/* Forgets the open buckets. */
void rl_lat_reset(rl_lat *l);
/*
 * Restart recovery (like rl_wifi_recover): writes the hour records of hours that ended while nothing was
 * recording, summed from latency.minute, and rebuilds the open hour from the minutes of the current hour.
 * Call on a fresh rl_lat. Returns the number of hour records written.
 */
int rl_lat_recover(rl_lat *l, rl_series *minute, rl_series *hour, int64_t now);

/* ---- queries ---- */

#define RL_LATQ_DEFAULT_POINTS 500
#define RL_LATQ_MAX_POINTS 1000
#define RL_LATQ_MAX_RANGE (10LL * 366 * 86400)
#define RL_OUTAGEQ_MAX_ITEMS 1000

typedef struct {
	rl_series *minute, *hour, *outages; /* may be NULL */
	const rl_lat *open;                 /* open buckets, may be NULL */
	const rl_lat_targets *targets;
	int64_t now;
	int minute_days; /* retention of latency.minute */
} rl_latq_ctx;

typedef struct {
	rl_tier tier; /* RL_TIER_MINUTE or RL_TIER_HOUR */
	int64_t first, step;
	size_t n;                       /* points per target, at first + i * step */
	int n_ids;                      /* targets in the result, ids ascending */
	uint8_t ids[RL_LAT_IDS];
	rl_probe_agg *pts[RL_LAT_IDS];  /* n points per result target; sent 0 = no data */
	rl_probe_agg sum[RL_LAT_IDS];   /* whole range per result target */
} rl_lat_history;

/*
 * Latency of the targets in want (bit per id): minutes when start is within their retention, else hours, on a
 * regular grid of at most max_points points (0: default). Targets in always are listed even without data in
 * the range, the others only when they have some. 0, or -1 for invalid arguments.
 */
int rl_lat_query(const rl_latq_ctx *c, int64_t start, int64_t end, int max_points, uint64_t want, uint64_t always,
		 rl_lat_history *out);
void rl_lat_history_free(rl_lat_history *h);

typedef struct {
	int64_t start, end;
	rl_outage_cause cause;
	bool ongoing;
} rl_outage_item;

typedef struct {
	size_t count;       /* outages overlapping the range */
	int64_t total_sec;  /* their time inside the range */
	int64_t probed_sec; /* time of the range in which custom targets were probed */
	size_t n;
	rl_outage_item *items; /* newest first, at most RL_OUTAGEQ_MAX_ITEMS */
} rl_outage_list;

/* Outages overlapping [start, end): the log plus the ongoing one of state (ending now). 0 or -1. */
int rl_outage_query(const rl_latq_ctx *c, const rl_outage *state, int64_t start, int64_t end, rl_outage_list *out);
void rl_outage_list_free(rl_outage_list *l);
/* Percent of the probed time without an outage, two decimals; negative when nothing was probed. */
double rl_outage_availability(const rl_outage_list *l);

#endif
