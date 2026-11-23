#include "t.h"

#include "core/agg.h"

#define MAXREC 64

static struct {
	rl_tier tier[MAXREC];
	rl_rec rec[MAXREC];
	int n;
} closed;

static void on_close(rl_tier tier, const rl_rec *r, void *ctx)
{
	(void)ctx;
	if (closed.n < MAXREC) {
		closed.tier[closed.n] = tier;
		closed.rec[closed.n++] = *r;
	}
}

static int count_tier(rl_tier t)
{
	int n = 0;
	for (int i = 0; i < closed.n; i++)
		n += closed.tier[i] == t;
	return n;
}

static const rl_rec *find(rl_tier t, uint16_t dev, uint8_t cls)
{
	for (int i = 0; i < closed.n; i++)
		if (closed.tier[i] == t && closed.rec[i].dev == dev && closed.rec[i].cls == cls)
			return &closed.rec[i];
	return NULL;
}

static bool count_open(const rl_rec *r, void *ctx)
{
	(void)r;
	(*(int *)ctx)++;
	return true;
}

static const int64_t T0 = 1759622400; /* 2025-10-05 00:00:00 UTC */

static void minute_close(void)
{
	rl_tz_apply("UTC0");
	closed.n = 0;
	rl_agg *a = rl_agg_new(on_close, NULL);
	rl_agg_add(a, T0 + 5, 2, RL_CLASS_INTERNET, 100, 10);
	rl_agg_add(a, T0 + 20, 2, RL_CLASS_INTERNET, 200, 20);
	rl_agg_add(a, T0 + 50, 2, RL_CLASS_INTERNET, 300, 30);
	rl_agg_conns(a, T0 + 50, 2, 7);
	rl_agg_tick(a, T0 + 59);
	T_EQ_I64(closed.n, 0);
	rl_agg_tick(a, T0 + 60);
	T_EQ_I64(count_tier(RL_TIER_MINUTE), 1);
	T_EQ_I64(count_tier(RL_TIER_HOUR), 0);
	const rl_rec *r = find(RL_TIER_MINUTE, 2, RL_CLASS_INTERNET);
	T_ASSERT(r != NULL);
	if (r) {
		T_EQ_U64(r->rx, 600);
		T_EQ_U64(r->tx, 60);
		T_EQ_I64(r->ts, T0);
		T_EQ_U64(r->conns, 7);
	}
	int open = 0;
	rl_agg_open(a, RL_TIER_HOUR, count_open, &open);
	T_EQ_I64(open, 1);
	open = 0;
	rl_agg_open(a, RL_TIER_MINUTE, count_open, &open);
	T_EQ_I64(open, 0);
	rl_agg_free(a);
}

static void day_change_closes_three_tiers(void)
{
	rl_tz_apply("UTC0");
	closed.n = 0;
	rl_agg *a = rl_agg_new(on_close, NULL);
	rl_agg_add(a, T0 + 86399, 3, RL_CLASS_LAN, 1, 2);
	rl_agg_add(a, T0 + 86399, 2, RL_CLASS_INTERNET, 5, 6);
	rl_agg_tick(a, T0 + 86400);
	T_EQ_I64(count_tier(RL_TIER_MINUTE), 2);
	T_EQ_I64(count_tier(RL_TIER_HOUR), 2);
	T_EQ_I64(count_tier(RL_TIER_DAY), 2);
	T_EQ_I64(count_tier(RL_TIER_MONTH), 0);
	/* deterministic order: dev 2 before dev 3 */
	T_EQ_I64(closed.rec[0].dev, 2);
	T_EQ_I64(closed.rec[1].dev, 3);
	const rl_rec *d = find(RL_TIER_DAY, 3, RL_CLASS_LAN);
	T_ASSERT(d && d->ts == T0 && d->rx == 1 && d->tx == 2);
	rl_agg_free(a);
}

static void rates(void)
{
	rl_tz_apply("UTC0");
	rl_agg *a = rl_agg_new(on_close, NULL);
	const rl_rate *r;
	rl_agg_sample_done(a, (T0 + 0) * 1000);
	rl_agg_add(a, T0 + 1, 2, RL_CLASS_INTERNET, 2 << 20, 0);
	rl_agg_add(a, T0 + 1, 2, RL_CLASS_LAN, 0, 1000);
	rl_agg_sample_done(a, (T0 + 2) * 1000);
	size_t n = rl_agg_rates(a, &r);
	T_EQ_U64(n, 1);
	T_EQ_U64(r[0].dev, 2);
	T_EQ_U64(r[0].rx_rate, 1 << 20);
	T_EQ_U64(r[0].tx_rate, 500);
	rl_agg_sample_done(a, (T0 + 4) * 1000);
	T_EQ_U64(rl_agg_rates(a, &r), 0);
	rl_agg_free(a);
}

static void time_goes_back(void)
{
	rl_tz_apply("UTC0");
	closed.n = 0;
	rl_agg *a = rl_agg_new(on_close, NULL);
	rl_agg_add(a, T0 + 130, 2, RL_CLASS_INTERNET, 10, 0);
	rl_agg_tick(a, T0 + 10); /* 120 s back: nothing closes */
	rl_agg_add(a, T0 + 10, 2, RL_CLASS_INTERNET, 5, 0);
	T_EQ_I64(closed.n, 0);
	rl_agg_tick(a, T0 + 180);
	const rl_rec *r = find(RL_TIER_MINUTE, 2, RL_CLASS_INTERNET);
	T_ASSERT(r && r->ts == T0 + 120 && r->rx == 15);
	rl_agg_free(a);
}

static void zero_wan_record(void)
{
	rl_tz_apply("UTC0");
	closed.n = 0;
	rl_agg *a = rl_agg_new(on_close, NULL);
	rl_agg_add(a, T0 + 1, RL_DEV_WAN, RL_CLASS_INTERNET, 0, 0);
	rl_agg_add(a, T0 + 31, RL_DEV_WAN, RL_CLASS_INTERNET, 0, 0);
	rl_agg_tick(a, T0 + 61);
	T_EQ_I64(count_tier(RL_TIER_MINUTE), 1);
	T_ASSERT(find(RL_TIER_MINUTE, RL_DEV_WAN, RL_CLASS_INTERNET) != NULL);
	rl_agg_reset(a);
	int open = 0;
	rl_agg_open(a, RL_TIER_HOUR, count_open, &open);
	T_EQ_I64(open, 0);
	rl_agg_free(a);
}

int main(void)
{
	T_RUN(minute_close);
	T_RUN(day_change_closes_three_tiers);
	T_RUN(rates);
	T_RUN(time_goes_back);
	T_RUN(zero_wan_record);
	T_DONE();
}
