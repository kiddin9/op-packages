#include <stdlib.h>

#include "t.h"

#include "core/query.h"

/* 2025-10-05 12:00:00 UTC */
static const int64_t NOW = 1759622400 + 12 * 3600;
static const rl_retention RET = { .minute_hours = 48, .hour_days = 90, .day_days = 730, .event_days = 90 };

static rl_store *store;
static rl_qctx ctx;

typedef struct {
	uint16_t dev;
	uint64_t rx;
} series;

/* Records in the daemon's minutes: off for 2 h (nothing at all), and an hour in which no sample ran. */
static const int64_t OFF_A = NOW - 10 * 3600, OFF_B = NOW - 8 * 3600;
static const int64_t UNSAMPLED_A = NOW - 6 * 3600, UNSAMPLED_B = NOW - 5 * 3600;

/*
 * Records in ts order (as the daemon writes them). holes: the minute tier has no records inside [OFF_A, OFF_B)
 * and no WAN record inside [UNSAMPLED_A, UNSAMPLED_B), where only connections that closed left records.
 */
static void fill(rl_tier t, int64_t from, int64_t to, const series *s, int n, bool holes)
{
	for (int64_t b = rl_bucket_start(t, from); b < to; b = rl_bucket_next(t, b)) {
		if (holes && b >= OFF_A && b < OFF_B)
			continue;
		for (int i = 0; i < n; i++) {
			if (holes && s[i].dev == RL_DEV_WAN && b >= UNSAMPLED_A && b < UNSAMPLED_B)
				continue;
			rl_rec r = { .ts = b, .dev = s[i].dev, .cls = RL_CLASS_INTERNET, .rx = s[i].rx, .tx = s[i].rx / 10 };
			rl_store_append(store, t, &r);
		}
	}
}

static void setup(void)
{
	char dir[] = "/tmp/rl-query-XXXXXX";
	if (!mkdtemp(dir))
		abort();
	rl_tz_apply("UTC0");
	store = rl_store_open(dir);
	/* consistent data: 1 byte per device-minute in every tier (dev 3 only in the hour tier) */
	fill(RL_TIER_MINUTE, NOW - 48 * 3600, NOW, (series[]){ { 2, 1 }, { RL_DEV_WAN, 2 } }, 2, true);
	fill(RL_TIER_HOUR, NOW - 90 * 86400LL, NOW, (series[]){ { 2, 60 }, { 3, 600 }, { RL_DEV_WAN, 120 } }, 3, false);
	fill(RL_TIER_DAY, NOW - 730 * 86400LL, NOW - 86400, (series[]){ { 2, 1440 }, { RL_DEV_WAN, 2880 } }, 2, false);
	rl_store_commit(store);
	ctx = (rl_qctx){ .store = store, .agg = NULL, .ret = &RET, .now = NOW };
}

static rl_history hist(int64_t start, int64_t end, int dev, uint32_t mask)
{
	rl_history h;
	rl_history_q q = { .start = start, .end = end, .dev = dev, .cls = RL_CLS_ANY, .hours_mask = mask };
	T_EQ_I64(rl_query_history(&ctx, &q, &h), 0);
	return h;
}

static uint64_t sum_rx(const rl_history *h)
{
	uint64_t s = 0;
	for (size_t i = 0; i < h->n; i++)
		s += h->pts[i].rx;
	return s;
}

static void tier_selection(void)
{
	rl_history h = hist(NOW - 3600, NOW, 2, 0);
	T_EQ_I64(h.tier, RL_TIER_MINUTE);
	T_EQ_I64(h.step, 60);
	T_EQ_U64(h.n, 60);
	T_EQ_U64(sum_rx(&h), 60);
	rl_history_free(&h);

	h = hist(NOW - 48 * 3600, NOW, 2, 0);
	T_EQ_I64(h.tier, RL_TIER_MINUTE);
	T_EQ_I64(h.step, 360);
	T_EQ_U64(h.n, 480);
	rl_history_free(&h);

	h = hist(NOW - 30 * 86400LL, NOW, 2, 0);
	T_EQ_I64(h.tier, RL_TIER_HOUR);
	T_EQ_I64(h.step, 7200);
	T_EQ_U64(h.n, 360);
	T_EQ_U64(sum_rx(&h), 30 * 1440);
	rl_history_free(&h);

	h = hist(NOW - 730 * 86400LL, NOW, 2, 0);
	T_EQ_I64(h.tier, RL_TIER_DAY);
	rl_history_free(&h);
}

/* Points while the daemon was off are gaps; the unsampled hour has records, so it is not one. */
static void gaps(void)
{
	rl_history h = hist(NOW - 24 * 3600, NOW, RL_DEV_ALL, 0);
	T_EQ_I64(h.step, 180);
	int gaps = 0;
	for (size_t i = 0; i < h.n; i++) {
		bool inside = h.pts[i].ts >= OFF_A && h.pts[i].ts < OFF_B;
		T_EQ_I64(h.pts[i].gap, inside);
		gaps += h.pts[i].gap;
	}
	T_EQ_I64(gaps, 40);
	rl_history_free(&h);
}

/*
 * Minutes without a sample (no WAN record: sample_interval over 60 s, or samples put off) hold the bytes of
 * the connections that closed in them. History shows them, as the summary counts them: no gap, same total.
 */
static void unsampled_minutes(void)
{
	int64_t a = UNSAMPLED_A - 600, b = UNSAMPLED_B + 600;
	rl_history h = hist(a, b, 2, 0);
	T_EQ_I64(h.step, 60);
	T_EQ_U64(h.n, 80);
	for (size_t i = 0; i < h.n; i++)
		T_ASSERT(!h.pts[i].gap);
	T_EQ_U64(sum_rx(&h), 80);
	rl_summary s;
	rl_summary_q q = { .start = a, .end = b, .cls = RL_CLS_ANY };
	T_EQ_I64(rl_query_summary(&ctx, &q, &s), 0);
	T_EQ_U64(s.n, 1);
	T_EQ_U64(s.devs[0].rx, sum_rx(&h));
	T_EQ_U64(s.wan_rx, 2 * 20); /* the sampled minutes only */
	rl_summary_free(&s);
	rl_history_free(&h);

	/* the WAN's own curve: nothing counted in the unsampled minutes, but they were recorded */
	h = hist(a, b, RL_DEV_WAN, 0);
	for (size_t i = 0; i < h.n; i++) {
		T_ASSERT(!h.pts[i].gap);
		bool inside = h.pts[i].ts >= UNSAMPLED_A && h.pts[i].ts < UNSAMPLED_B;
		T_EQ_U64(h.pts[i].rx, inside ? 0 : 2);
	}
	rl_history_free(&h);
}

static void hours_filter(void)
{
	uint32_t mask = 1u << 20 | 1u << 21 | 1u << 22;
	rl_history h = hist(NOW - 7 * 86400LL, NOW, 2, mask);
	T_EQ_I64(h.tier, RL_TIER_HOUR);
	T_EQ_U64(sum_rx(&h), 7 * 3 * 60);
	rl_history_free(&h);

	rl_history_q q = { .start = NOW - 100 * 86400LL, .end = NOW, .dev = 2, .cls = RL_CLS_ANY, .hours_mask = mask };
	T_EQ_I64(rl_query_history(&ctx, &q, &h), -1);
	rl_summary s;
	rl_summary_q sq = { .start = NOW - 100 * 86400LL, .end = NOW, .cls = RL_CLS_ANY, .hours_mask = mask };
	T_EQ_I64(rl_query_summary(&ctx, &sq, &s), -1);
	sq.start = NOW - 7 * 86400LL;
	T_EQ_I64(rl_query_summary(&ctx, &sq, &s), 0);
	/* hour tier for the older 5 days, minute tier (dev 2 only) for the last 48 h */
	T_EQ_U64(s.rx, 5 * 3 * (60 + 600) + 2 * 3 * 60);
	rl_summary_free(&s);
}

static void bad_arguments(void)
{
	rl_history h;
	rl_history_q q = { .start = NOW, .end = NOW, .dev = 2 };
	T_EQ_I64(rl_query_history(&ctx, &q, &h), -1);
	q = (rl_history_q){ .start = NOW - 60, .end = NOW, .dev = 2, .max_points = 5000 };
	T_EQ_I64(rl_query_history(&ctx, &q, &h), -1);
	q = (rl_history_q){ .start = INT64_MIN + 3600, .end = NOW, .dev = 2 }; /* end - start overflows */
	T_EQ_I64(rl_query_history(&ctx, &q, &h), -1);
	q = (rl_history_q){ .start = 0, .end = NOW, .dev = 2 };
	T_EQ_I64(rl_query_history(&ctx, &q, &h), -1);
	q = (rl_history_q){ .start = NOW - 60, .end = NOW, .dev = 2, .hours_mask = 1u << 24 };
	T_EQ_I64(rl_query_history(&ctx, &q, &h), -1);
}

static void summary_across_tiers(void)
{
	rl_summary s;
	rl_summary_q q = { .start = NOW - 7 * 86400LL, .end = NOW, .cls = RL_CLASS_INTERNET };
	T_EQ_I64(rl_query_summary(&ctx, &q, &s), 0);
	/* 5 days from the hour tier + 48 h from the minute tier, 1 byte per minute for dev 2 */
	T_EQ_I64(s.granularity, RL_TIER_HOUR);
	T_EQ_I64(s.start_exact, NOW - 7 * 86400LL);
	rl_summary_sort(&s, RL_SORT_TOTAL);
	T_EQ_U64(s.n, 2);
	T_EQ_U64(s.devs[0].dev, 3); /* 600 per hour */
	T_EQ_U64(s.devs[1].dev, 2);
	T_EQ_U64(s.devs[1].rx, 7 * 1440 - 120); /* minus the 2 h the daemon was off */
	T_EQ_U64(s.devs[0].rx, 5 * 24 * 600); /* dev 3 has no minute records */
	rl_summary_free(&s);

	/* a year back reaches into the day tier */
	q.start = NOW - 365 * 86400LL - 1800;
	T_EQ_I64(rl_query_summary(&ctx, &q, &s), 0);
	T_EQ_I64(s.granularity, RL_TIER_DAY);
	T_EQ_I64(s.start_exact, NOW - 365 * 86400LL + 12 * 3600); /* next midnight */
	rl_summary_free(&s);
}

static void close_into_store(rl_tier t, const rl_rec *r, void *x)
{
	(void)x;
	rl_store_append(store, t, r);
}

static void open_bucket_counts(void)
{
	rl_agg *a = rl_agg_new(close_into_store, NULL);
	rl_agg_add(a, NOW + 10, 7, RL_CLASS_INTERNET, 500, 50);
	rl_agg_add(a, NOW + 10, RL_DEV_WAN, RL_CLASS_INTERNET, 600, 60);
	rl_qctx c = ctx;
	c.agg = a;
	c.now = NOW + 20;
	rl_summary s;
	rl_summary_q q = { .start = NOW - 60, .end = NOW + 3600, .cls = RL_CLASS_INTERNET };
	T_EQ_I64(rl_query_summary(&c, &q, &s), 0);
	rl_summary_sort(&s, RL_SORT_RX);
	T_EQ_U64(s.devs[0].dev, 7);
	T_EQ_U64(s.devs[0].rx, 500);
	T_EQ_U64(s.wan_rx, 2 + 600);
	rl_summary_free(&s);
	rl_history h;
	rl_history_q hq = { .start = NOW - 60, .end = NOW + 3600, .dev = 7, .cls = RL_CLS_ANY };
	T_EQ_I64(rl_query_history(&c, &hq, &h), 0);
	T_EQ_U64(h.n, 2); /* the stored minute and the open one */
	T_EQ_U64(h.pts[1].rx, 500);
	T_ASSERT(!h.pts[1].gap);
	rl_history_free(&h);
	rl_agg_free(a);
}

int main(void)
{
	setup();
	T_RUN(tier_selection);
	T_RUN(gaps);
	T_RUN(unsampled_minutes);
	T_RUN(hours_filter);
	T_RUN(bad_arguments);
	T_RUN(summary_across_tiers);
	T_RUN(open_bucket_counts);
	rl_store_close(store);
	T_DONE();
}
