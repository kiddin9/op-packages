#include <stdlib.h>
#include <string.h>

#include "core/recover.h"
#include "core/util.h"

/* Sums records by (dev, cls); few devices, so a linear list is enough. */
typedef struct {
	rl_rec *items;
	size_t n, cap;
} sums;

static bool add_cb(const rl_rec *r, void *x)
{
	sums *s = x;
	for (size_t i = 0; i < s->n; i++) {
		rl_rec *e = &s->items[i];
		if (e->dev == r->dev && e->cls == r->cls) {
			e->rx += r->rx;
			e->tx += r->tx;
			if (r->conns > e->conns)
				e->conns = r->conns;
			return true;
		}
	}
	s->items = rl_grow(s->items, &s->cap, s->n + 1, sizeof(rl_rec));
	s->items[s->n++] = *r;
	return true;
}

static int cmp_key(const void *x, const void *y)
{
	const rl_rec *a = x, *b = y;
	uint32_t ka = (uint32_t)a->dev << 2 | a->cls, kb = (uint32_t)b->dev << 2 | b->cls;
	return ka < kb ? -1 : ka > kb;
}

/* Writes the records of complete buckets of tier t that have finer data but no record yet. */
static int catch_up(rl_store *s, rl_tier t, int64_t now)
{
	rl_tier f = (rl_tier)(t - 1);
	int64_t cur = rl_bucket_start(t, now);
	int64_t newest = rl_store_newest(s, t);
	int64_t from;
	int written = 0;

	int64_t oldest = rl_store_oldest(s, f);
	if (oldest == INT64_MAX)
		return 0;
	/* start after the newest record of this tier, but not before the finer data begins */
	from = rl_bucket_start(t, oldest);
	if (newest != INT64_MIN && rl_bucket_next(t, newest) > from)
		from = rl_bucket_next(t, newest);
	for (int64_t b = from; b < cur; b = rl_bucket_next(t, b)) {
		sums acc = { 0 };
		rl_store_scan(s, f, b, rl_bucket_next(t, b), add_cb, &acc);
		if (acc.n)
			qsort(acc.items, acc.n, sizeof(rl_rec), cmp_key);
		for (size_t i = 0; i < acc.n; i++) {
			acc.items[i].ts = b;
			rl_store_append(s, t, &acc.items[i]);
			written++;
		}
		free(acc.items);
	}
	return written;
}

typedef struct {
	rl_agg *a;
	int64_t now;
	rl_tier t;
} hydrate_ctx;

static bool hydrate_cb(const rl_rec *r, void *x)
{
	hydrate_ctx *h = x;
	rl_agg_hydrate(h->a, h->now, h->t, r);
	return true;
}

int rl_recover(rl_store *s, rl_agg *a, int64_t now)
{
	int written = 0;
	for (int t = RL_TIER_HOUR; t < RL_TIER_COUNT; t++) {
		rl_tier f = (rl_tier)(t - 1);
		written += catch_up(s, (rl_tier)t, now);
		hydrate_ctx h = { a, now, (rl_tier)t };
		/* closed finer records inside the open bucket, then the finer open bucket (already rebuilt) */
		rl_store_scan(s, f, rl_bucket_start((rl_tier)t, now), now + 1, hydrate_cb, &h);
		rl_agg_open(a, f, hydrate_cb, &h);
	}
	return written;
}
