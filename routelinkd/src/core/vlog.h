/*
 * Append-only log of variable-length records (DNS log, destinations; P4). Each record is stored as
 * u16 length | payload | u16 length, so the newest records can be read walking backwards, which is how the
 * pages ask for them. The payload starts with a little-endian u32 timestamp; records come in ts order.
 * Like core/series: records wait in RAM until commit, a torn tail is cut off on open, a damaged header
 * renames the file to *.bad.
 */
#ifndef RL_VLOG_H
#define RL_VLOG_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define RL_VLOG_MAGIC 0x31564c52u /* "RLV1" little-endian */
#define RL_VLOG_HDR_SIZE 16
#define RL_VLOG_REC_MAX 8192
/* Records beyond this many bytes waiting for a commit are dropped (and counted). */
#define RL_VLOG_PENDING_MAX (1u << 20)

typedef struct rl_vlog rl_vlog;
/* Return false to stop. */
typedef bool (*rl_vlog_cb)(const uint8_t *rec, size_t len, void *ctx);

rl_vlog *rl_vlog_open(const char *path, uint16_t kind, bool *recovered);
void rl_vlog_close(rl_vlog *v);
/* 0, or -1 when the record is malformed, older than the newest one, or the pending buffer is full. */
int rl_vlog_append(rl_vlog *v, const uint8_t *rec, size_t len);
size_t rl_vlog_pending(const rl_vlog *v);
uint64_t rl_vlog_dropped(const rl_vlog *v);
int rl_vlog_commit(rl_vlog *v);
/* Keeps records with ts >= cutoff, and of those the newest max_records (0 = any number). */
int rl_vlog_compact(rl_vlog *v, int64_t cutoff, uint64_t max_records);
/* Records with start <= ts < end, newest first: pending ones, then the file backwards. */
int rl_vlog_scan_newest(rl_vlog *v, int64_t start, int64_t end, rl_vlog_cb cb, void *ctx);
/* Records on disk plus pending. */
uint64_t rl_vlog_count(const rl_vlog *v);
uint64_t rl_vlog_bytes(const rl_vlog *v);
int rl_vlog_reset(rl_vlog *v);

#endif
