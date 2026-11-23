/* History curves and range totals over the tier files plus the open buckets. */
#ifndef RL_QUERY_H
#define RL_QUERY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/agg.h"
#include "core/store.h"

#define RL_QUERY_DEFAULT_POINTS 500
#define RL_QUERY_MAX_POINTS 1000
#define RL_QUERY_MAX_RANGE (10LL * 366 * 86400)

#define RL_DEV_ALL (-1) /* every real device plus RL_DEV_UNKNOWN */
#define RL_CLS_ANY (-1)

typedef struct {
	rl_store *store;
	const rl_agg *agg; /* may be NULL */
	const rl_retention *ret;
	int64_t now;
} rl_qctx;

typedef struct {
	int64_t start, end;
	int dev;             /* RL_DEV_ALL, a device index, RL_DEV_ROUTER or RL_DEV_WAN */
	int cls;             /* RL_CLS_ANY or rl_class; ignored for the pseudo devices */
	uint32_t hours_mask; /* 0: all hours; bit h: local hour h */
	int max_points;      /* 0: default */
} rl_history_q;

typedef struct {
	int64_t ts;
	bool gap; /* no record at all in the point (not even the WAN's): the daemon was not recording */
	uint64_t rx, tx;
} rl_point;

typedef struct {
	rl_tier tier;
	int64_t step; /* nominal seconds per point */
	size_t n;
	rl_point *pts;
} rl_history;

/* 0, or -1 for invalid arguments (see rl_query_error). */
int rl_query_history(const rl_qctx *c, const rl_history_q *q, rl_history *out);
void rl_history_free(rl_history *h);

typedef struct {
	int64_t start, end;
	int cls; /* RL_CLS_ANY or rl_class */
	uint32_t hours_mask;
} rl_summary_q;

typedef struct {
	uint16_t dev;
	uint64_t rx, tx;
} rl_dev_total;

typedef enum { RL_SORT_TOTAL, RL_SORT_RX, RL_SORT_TX } rl_sort;

typedef struct {
	int64_t start_exact;     /* first bucket that was counted */
	rl_tier granularity;     /* coarsest tier used */
	uint64_t rx, tx;         /* all matched devices */
	uint64_t wan_rx, wan_tx; /* WAN interface counters */
	size_t n;
	rl_dev_total *devs;      /* WAN excluded */
} rl_summary;

int rl_query_summary(const rl_qctx *c, const rl_summary_q *q, rl_summary *out);
void rl_summary_sort(rl_summary *s, rl_sort by);
void rl_summary_free(rl_summary *s);

/* Why the last call returned -1. */
const char *rl_query_error(void);

#endif
