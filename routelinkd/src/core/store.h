/* Append-only tier files: closed records wait in RAM and reach the disk at commit time. */
#ifndef RL_STORE_H
#define RL_STORE_H

#include <stddef.h>
#include <stdint.h>

#include "core/rec.h"
#include "core/timeutil.h"

#define RL_STORE_MAGIC 0x31544c52u /* "RLT1" little-endian */
#define RL_STORE_VERSION 1
#define RL_STORE_HDR_SIZE 16
#define RL_STORE_REC_SIZE 32

typedef struct {
	int minute_hours;
	int hour_days;
	int day_days;
	int event_days;
} rl_retention;

/* How far back a tier keeps data; -1 for months (kept forever). */
int64_t rl_retention_seconds(const rl_retention *r, rl_tier tier);

typedef struct rl_store rl_store;

/* Opens or creates traffic.{minute,hour,day,month} in dir. Damaged files are renamed to *.bad. */
rl_store *rl_store_open(const char *dir);
void rl_store_close(rl_store *s);
/* Number of files that were damaged and replaced while opening. */
int rl_store_recovered(const rl_store *s);

void rl_store_append(rl_store *s, rl_tier tier, const rl_rec *r);
size_t rl_store_pending(const rl_store *s);
/* Forgets records that were not committed yet (recorded before the clock was set). */
void rl_store_discard_pending(rl_store *s);
/* Appends pending records to disk and fsyncs; on failure the files keep their old length. */
int rl_store_commit(rl_store *s);
/* Drops expired records, then the oldest minute/hour/day records while the total exceeds max_bytes. */
int rl_store_compact(rl_store *s, int64_t now, const rl_retention *ret, uint64_t max_bytes);
/* Records with start <= ts < end from disk, then pending ones, in ts order. */
int rl_store_scan(rl_store *s, rl_tier tier, int64_t start, int64_t end, rl_rec_cb cb, void *ctx);
uint64_t rl_store_bytes(const rl_store *s);
/* Oldest record of a tier, or INT64_MAX when empty. */
int64_t rl_store_oldest(rl_store *s, rl_tier tier);
/* Newest record of a tier (pending included), or INT64_MIN when empty. */
int64_t rl_store_newest(rl_store *s, rl_tier tier);
/* Truncates every tier and drops pending records. */
int rl_store_reset(rl_store *s);

#endif
