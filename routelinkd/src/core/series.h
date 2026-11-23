/*
 * Generic append-only log of fixed 32-byte records whose first 4 bytes are a little-endian u32 timestamp
 * (signal, latency and outage history). Like core/store: records wait in RAM until commit, a failed commit
 * keeps the old file length, a damaged file is renamed to *.bad and recreated. Callers encode their own
 * payload (the rl_le_* helpers keep the byte order fixed on big-endian MIPS).
 */
#ifndef RL_SERIES_H
#define RL_SERIES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define RL_SERIES_MAGIC 0x31534c52u /* "RLS1" little-endian */
#define RL_SERIES_VERSION 1
#define RL_SERIES_HDR_SIZE 16
#define RL_SERIES_REC_SIZE 32

typedef struct rl_series rl_series;
/* Return false to stop iterating. */
typedef bool (*rl_series_cb)(const uint8_t *rec, void *ctx);

/*
 * Opens or creates path. kind tags the file: a file of another kind, record size or version counts as
 * damaged, is renamed to path.bad and replaced (*recovered is set). NULL when the file cannot be created.
 */
rl_series *rl_series_open(const char *path, uint16_t kind, bool *recovered);
void rl_series_close(rl_series *s);

/*
 * Queues a record for the next commit. Records must come in ts order (equal is fine): an older one is
 * dropped and -1 returned, so the file stays sorted for the binary searches.
 */
int rl_series_append(rl_series *s, const uint8_t rec[RL_SERIES_REC_SIZE]);
size_t rl_series_pending(const rl_series *s);
/* Forgets records that were not committed yet (recorded before the clock was set). */
void rl_series_discard_pending(rl_series *s);
/* Appends pending records and fsyncs; on failure the file keeps its old length and the records stay queued. */
int rl_series_commit(rl_series *s);
/*
 * Drops records with ts < cutoff, then the oldest ones while the file is larger than max_bytes (0: no
 * size limit). The file is rewritten through path.tmp + rename; on failure it is left as it was.
 */
int rl_series_compact(rl_series *s, int64_t cutoff, uint64_t max_bytes);
/* Records with start <= ts < end from disk, then pending ones, in ts order. */
int rl_series_scan(rl_series *s, int64_t start, int64_t end, rl_series_cb cb, void *ctx);
/* File size plus pending records. */
uint64_t rl_series_bytes(const rl_series *s);
/* Oldest record (disk or pending), INT64_MAX when empty. */
int64_t rl_series_oldest(rl_series *s);
/* Newest record (pending included), INT64_MIN when empty. */
int64_t rl_series_newest(const rl_series *s);
/* Truncates the file and drops pending records. */
int rl_series_reset(rl_series *s);

static inline void rl_le_put16(uint8_t *p, uint16_t v)
{
	p[0] = (uint8_t)v;
	p[1] = (uint8_t)(v >> 8);
}

static inline void rl_le_put32(uint8_t *p, uint32_t v)
{
	for (int i = 0; i < 4; i++)
		p[i] = (uint8_t)(v >> (8 * i));
}

static inline uint16_t rl_le_get16(const uint8_t *p)
{
	return (uint16_t)(p[0] | p[1] << 8);
}

static inline uint32_t rl_le_get32(const uint8_t *p)
{
	return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/* Timestamp of a record. */
static inline int64_t rl_series_ts(const uint8_t *rec)
{
	return (int64_t)rl_le_get32(rec);
}

#endif
