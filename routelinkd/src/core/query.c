#include <stdlib.h>
#include <string.h>

#include "core/query.h"
#include "core/util.h"

static const char *last_error = "";

const char *rl_query_error(void)
{
	return last_error;
}

static int fail(const char *why)
{
	last_error = why;
	return -1;
}

/* Coverage start of a tier: data older than this was dropped. */
static int64_t coverage(const rl_qctx *c, rl_tier t)
{
	int64_t keep = rl_retention_seconds(c->ret, t);
	return keep < 0 ? INT64_MIN : c->now - keep;
}

/* Queries include the bucket that is still open. */
static int64_t clip_end(const rl_qctx *c, int64_t end)
{
	int64_t limit = rl_bucket_next(RL_TIER_MINUTE, c->now);
	return end < limit ? end : limit;
}

static bool hour_ok(uint32_t mask, int64_t ts)
{
	return !mask || (mask >> rl_local_hour(ts) & 1);
}

static bool matches(int dev, int cls, const rl_rec *r)
{
	if (dev == RL_DEV_WAN || dev == RL_DEV_ROUTER)
		return r->dev == dev;
	if (dev == RL_DEV_ALL) {
		if (r->dev > RL_DEV_MAX && r->dev != RL_DEV_UNKNOWN)
			return false;
	} else if (r->dev != dev) {
		return false;
	}
	return cls == RL_CLS_ANY || r->cls == cls;
}

typedef struct {
	int64_t a, b;
	rl_rec_cb cb;
	void *ctx;
} range_filter;

static bool in_range(const rl_rec *r, void *x)
{
	range_filter *f = x;
	return r->ts >= f->a && r->ts < f->b ? f->cb(r, f->ctx) : true;
}

/* Calls cb for tier records in [a, b): disk, pending, then the open bucket (newer than anything stored). */
static void scan_tier(const rl_qctx *c, rl_tier t, int64_t a, int64_t b, rl_rec_cb cb, void *ctx)
{
	if (a >= b)
		return;
	rl_store_scan(c->store, t, a, b, cb, ctx);
	if (!c->agg)
		return;
	range_filter f = { a, b, cb, ctx };
	rl_agg_open(c->agg, t, in_range, &f);
}

/* ---- history ---- */

typedef struct {
	const rl_history_q *q;
	int64_t *bounds; /* n + 1 */
	size_t n;
	rl_point *pts;
	bool *covered;
} hist_ctx;

static bool hist_cb(const rl_rec *r, void *x)
{
	hist_ctx *h = x;
	/* last bound <= ts */
	size_t lo = 0, hi = h->n;
	while (lo + 1 < hi) {
		size_t mid = (lo + hi) / 2;
		if (h->bounds[mid] <= r->ts)
			lo = mid;
		else
			hi = mid;
	}
	if (r->ts < h->bounds[0] || r->ts >= h->bounds[h->n])
		return true;
	/*
	 * Any record shows that the daemon was recording. Not only the WAN's: that one comes with a sample, and
	 * a minute without one (sample_interval over 60 s, samples put off) can still hold the bytes of
	 * connections that closed in it, which the summary counts.
	 */
	h->covered[lo] = true;
	if (!hour_ok(h->q->hours_mask, r->ts) || !matches(h->q->dev, h->q->cls, r))
		return true;
	h->pts[lo].rx += r->rx;
	h->pts[lo].tx += r->tx;
	return true;
}

int rl_query_history(const rl_qctx *c, const rl_history_q *q, rl_history *out)
{
	memset(out, 0, sizeof(*out));
	int max_points = q->max_points ? q->max_points : RL_QUERY_DEFAULT_POINTS;
	if (q->start >= q->end)
		return fail("start must be before end");
	if (!rl_range_ok(q->start, q->end, RL_QUERY_MAX_RANGE))
		return fail("range too long");
	if (max_points < 1 || max_points > RL_QUERY_MAX_POINTS)
		return fail("max_points out of range");
	if (q->hours_mask >> 24)
		return fail("hours out of range");

	rl_tier tier = RL_TIER_MONTH;
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		if (q->start >= coverage(c, (rl_tier)t) - rl_tier_seconds((rl_tier)t)) {
			tier = (rl_tier)t;
			break;
		}
	}
	if (q->hours_mask && tier > RL_TIER_HOUR)
		return fail("hours filter needs data younger than the hourly retention");

	int64_t end = clip_end(c, q->end);
	int64_t first = rl_bucket_start(tier, q->start);
	int64_t buckets = (end - first + rl_tier_seconds(tier) - 1) / rl_tier_seconds(tier);
	int64_t k = (buckets + max_points - 1) / max_points;
	if (k < 1)
		k = 1;

	hist_ctx h = { .q = q };
	size_t cap = 0;
	for (int64_t b = first;;) {
		h.bounds = rl_grow(h.bounds, &cap, h.n + 2, sizeof(int64_t));
		h.bounds[h.n] = b;
		if (b >= end)
			break;
		for (int64_t i = 0; i < k; i++)
			b = rl_bucket_next(tier, b);
		h.n++;
	}
	h.pts = calloc(h.n ? h.n : 1, sizeof(rl_point));
	h.covered = calloc(h.n ? h.n : 1, sizeof(bool));
	if (!h.pts || !h.covered)
		abort();
	if (h.n)
		scan_tier(c, tier, h.bounds[0], h.bounds[h.n], hist_cb, &h);
	for (size_t i = 0; i < h.n; i++) {
		h.pts[i].ts = h.bounds[i];
		h.pts[i].gap = !h.covered[i];
	}
	free(h.bounds);
	free(h.covered);
	out->tier = tier;
	out->step = rl_tier_seconds(tier) * k;
	out->n = h.n;
	out->pts = h.pts;
	return 0;
}

void rl_history_free(rl_history *h)
{
	free(h->pts);
	h->pts = NULL;
	h->n = 0;
}

/* ---- summary ---- */

typedef struct {
	const rl_summary_q *q;
	rl_summary *s;
	uint32_t *slot; /* dev -> index + 1 */
	size_t cap;
} sum_ctx;

static bool sum_cb(const rl_rec *r, void *x)
{
	sum_ctx *c = x;
	if (!hour_ok(c->q->hours_mask, r->ts))
		return true;
	if (r->dev == RL_DEV_WAN) {
		c->s->wan_rx += r->rx;
		c->s->wan_tx += r->tx;
		return true;
	}
	if (c->q->cls != RL_CLS_ANY && r->cls != c->q->cls)
		return true;
	if (!c->slot[r->dev]) {
		c->s->devs = rl_grow(c->s->devs, &c->cap, c->s->n + 1, sizeof(rl_dev_total));
		c->s->devs[c->s->n] = (rl_dev_total){ .dev = r->dev };
		c->slot[r->dev] = (uint32_t)++c->s->n;
	}
	rl_dev_total *d = &c->s->devs[c->slot[r->dev] - 1];
	d->rx += r->rx;
	d->tx += r->tx;
	c->s->rx += r->rx;
	c->s->tx += r->tx;
	return true;
}

int rl_query_summary(const rl_qctx *c, const rl_summary_q *q, rl_summary *out)
{
	memset(out, 0, sizeof(*out));
	if (q->start >= q->end)
		return fail("start must be before end");
	if (!rl_range_ok(q->start, q->end, RL_QUERY_MAX_RANGE))
		return fail("range too long");
	if (q->hours_mask >> 24)
		return fail("hours out of range");
	if (q->hours_mask && q->start < coverage(c, RL_TIER_HOUR))
		return fail("hours filter needs data younger than the hourly retention");

	sum_ctx sc = { .q = q, .s = out, .slot = calloc(65536, sizeof(uint32_t)) };
	if (!sc.slot)
		abort();
	int64_t hi = clip_end(c, q->end);
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		int64_t cov = coverage(c, (rl_tier)t);
		if (q->start >= cov) {
			int64_t a = rl_bucket_ceil((rl_tier)t, q->start);
			scan_tier(c, (rl_tier)t, a, hi, sum_cb, &sc);
			out->start_exact = a;
			out->granularity = (rl_tier)t;
			break;
		}
		/* the coarser tier takes everything before its first boundary inside this tier's coverage */
		int64_t b = rl_bucket_ceil((rl_tier)(t + 1), cov);
		if (b < hi) {
			scan_tier(c, (rl_tier)t, b, hi, sum_cb, &sc);
			hi = b;
		}
	}
	free(sc.slot);
	return 0;
}

static rl_sort sort_by;

static int cmp_total(const void *x, const void *y)
{
	const rl_dev_total *a = x, *b = y;
	uint64_t va = sort_by == RL_SORT_RX ? a->rx : sort_by == RL_SORT_TX ? a->tx : a->rx + a->tx;
	uint64_t vb = sort_by == RL_SORT_RX ? b->rx : sort_by == RL_SORT_TX ? b->tx : b->rx + b->tx;
	if (va != vb)
		return va < vb ? 1 : -1;
	return a->dev < b->dev ? -1 : a->dev > b->dev;
}

void rl_summary_sort(rl_summary *s, rl_sort by)
{
	sort_by = by;
	qsort(s->devs, s->n, sizeof(rl_dev_total), cmp_total);
}

void rl_summary_free(rl_summary *s)
{
	free(s->devs);
	s->devs = NULL;
	s->n = 0;
}
