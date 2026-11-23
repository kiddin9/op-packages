#include <stdlib.h>

#include "t.h"

#include "core/recover.h"

/* 2025-10-15 00:00:00 UTC (mid-month, so month buckets stay simple) */
static const int64_t DAY0 = 1760486400;
#define H(h, m) (DAY0 + (h) * 3600 + (m) * 60)

static rl_store *store;

static void fresh(void)
{
	char dir[] = "/tmp/rl-recover-XXXXXX";
	if (!mkdtemp(dir))
		abort();
	rl_tz_apply("UTC0");
	store = rl_store_open(dir);
}

static void put(rl_tier t, int64_t ts, uint16_t dev, uint64_t rx)
{
	rl_rec r = { .ts = ts, .dev = dev, .cls = RL_CLASS_INTERNET, .rx = rx, .tx = rx * 2, .conns = 1 };
	rl_store_append(store, t, &r);
}

/* minute records with rx=1 for dev 2 from a to b (exclusive) */
static void minutes(int64_t a, int64_t b)
{
	for (int64_t t = a; t < b; t += 60)
		put(RL_TIER_MINUTE, t, 2, 1);
}

typedef struct {
	int n;
	uint64_t rx, tx;
	int64_t first;
} acc;

static bool sum_cb(const rl_rec *r, void *x)
{
	acc *a = x;
	if (!a->n)
		a->first = r->ts;
	a->n++;
	a->rx += r->rx;
	a->tx += r->tx;
	return true;
}

static acc stored(rl_tier t, int64_t a, int64_t b)
{
	acc x = { 0 };
	rl_store_scan(store, t, a, b, sum_cb, &x);
	return x;
}

static acc open_bucket(rl_agg *a, rl_tier t)
{
	acc x = { 0 };
	rl_agg_open(a, t, sum_cb, &x);
	return x;
}

static void fresh_install_mid_hour(void)
{
	fresh();
	minutes(H(10, 0), H(11, 20));
	rl_agg *a = rl_agg_new(NULL, NULL);
	T_EQ_I64(rl_recover(store, a, H(11, 20) + 30), 1);
	acc h = stored(RL_TIER_HOUR, 0, INT64_MAX);
	T_EQ_I64(h.n, 1);
	T_EQ_I64(h.first, H(10, 0));
	T_EQ_U64(h.rx, 60);
	T_EQ_U64(h.tx, 120);
	T_EQ_U64(open_bucket(a, RL_TIER_HOUR).rx, 20);
	T_EQ_U64(open_bucket(a, RL_TIER_DAY).rx, 80);
	T_EQ_U64(open_bucket(a, RL_TIER_MONTH).rx, 80);
	T_EQ_I64(rl_agg_open_start(a, RL_TIER_HOUR), H(11, 0));
	rl_agg_free(a);
	rl_store_close(store);
}

static void no_duplicate_records(void)
{
	fresh();
	minutes(H(10, 0), H(11, 20));
	put(RL_TIER_HOUR, H(10, 0), 2, 60);
	rl_agg *a = rl_agg_new(NULL, NULL);
	T_EQ_I64(rl_recover(store, a, H(11, 20) + 30), 0);
	T_EQ_I64(stored(RL_TIER_HOUR, 0, INT64_MAX).n, 1);
	T_EQ_U64(open_bucket(a, RL_TIER_DAY).rx, 80);
	rl_agg_free(a);
	rl_store_close(store);
}

static void downtime_across_hours(void)
{
	fresh();
	put(RL_TIER_HOUR, H(9, 0), 2, 60);
	minutes(H(9, 0), H(10, 30)); /* crashed at 10:30 */
	rl_agg *a = rl_agg_new(NULL, NULL);
	T_EQ_I64(rl_recover(store, a, H(12, 10)), 1);
	acc h = stored(RL_TIER_HOUR, H(10, 0), INT64_MAX);
	T_EQ_I64(h.n, 1);
	T_EQ_U64(h.rx, 30);
	T_EQ_U64(open_bucket(a, RL_TIER_HOUR).rx, 0);
	T_EQ_U64(open_bucket(a, RL_TIER_DAY).rx, 60 + 30);
	rl_agg_free(a);
	rl_store_close(store);
}

static void day_catch_up(void)
{
	fresh();
	int64_t y = DAY0 - 86400; /* yesterday */
	put(RL_TIER_DAY, y - 86400, 2, 1440);
	for (int h = 0; h < 24; h++)
		put(RL_TIER_HOUR, y + h * 3600, 2, 60);
	minutes(H(0, 0), H(1, 30));
	rl_agg *a = rl_agg_new(NULL, NULL);
	T_EQ_I64(rl_recover(store, a, H(1, 30)), 2); /* yesterday's day record + today's 00:00 hour */
	acc d = stored(RL_TIER_DAY, y, INT64_MAX);
	T_EQ_I64(d.n, 1);
	T_EQ_U64(d.rx, 1440);
	T_EQ_U64(stored(RL_TIER_HOUR, DAY0, INT64_MAX).rx, 60);
	T_EQ_U64(open_bucket(a, RL_TIER_HOUR).rx, 30);
	T_EQ_U64(open_bucket(a, RL_TIER_DAY).rx, 90);
	/* month: two stored days of October plus today's partial */
	T_EQ_U64(open_bucket(a, RL_TIER_MONTH).rx, 1440 * 2 + 90);
	rl_agg_free(a);
	rl_store_close(store);
}

static void flushed_minute_then_more(void)
{
	fresh();
	minutes(H(10, 0), H(10, 5));
	put(RL_TIER_MINUTE, H(10, 5), 2, 7); /* partial 10:05 flushed at shutdown */
	rl_agg *a = rl_agg_new(NULL, NULL);
	rl_recover(store, a, H(10, 5) + 40);
	rl_agg_add(a, H(10, 5) + 45, 2, RL_CLASS_INTERNET, 3, 0); /* rest of 10:05 after the restart */
	T_EQ_U64(open_bucket(a, RL_TIER_HOUR).rx, 5 + 7 + 3);
	T_EQ_U64(open_bucket(a, RL_TIER_MINUTE).rx, 3);
	rl_agg_free(a);
	rl_store_close(store);
}

static void empty_store(void)
{
	fresh();
	rl_agg *a = rl_agg_new(NULL, NULL);
	T_EQ_I64(rl_recover(store, a, H(5, 0)), 0);
	T_EQ_I64(open_bucket(a, RL_TIER_DAY).n, 0);
	rl_agg_free(a);
	rl_store_close(store);
}

int main(void)
{
	T_RUN(fresh_install_mid_hour);
	T_RUN(no_duplicate_records);
	T_RUN(downtime_across_hours);
	T_RUN(day_catch_up);
	T_RUN(flushed_minute_then_more);
	T_RUN(empty_store);
	T_DONE();
}
