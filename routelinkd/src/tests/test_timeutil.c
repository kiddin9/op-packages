#include <time.h>

#include "t.h"

#include "core/timeutil.h"

/* Local wall-clock time -> epoch in the current TZ. */
static int64_t local(int y, int mo, int d, int h, int mi, int s)
{
	struct tm tm = { .tm_year = y - 1900, .tm_mon = mo - 1, .tm_mday = d, .tm_hour = h, .tm_min = mi, .tm_sec = s, .tm_isdst = -1 };
	return mktime(&tm);
}

static void shanghai_hour_day_month(void)
{
	rl_tz_apply("CST-8");
	int64_t t = local(2026, 10, 5, 13, 47, 12);
	T_EQ_I64(rl_bucket_start(RL_TIER_MINUTE, t), local(2026, 10, 5, 13, 47, 0));
	T_EQ_I64(rl_bucket_start(RL_TIER_HOUR, t), local(2026, 10, 5, 13, 0, 0));
	T_EQ_I64(rl_bucket_start(RL_TIER_DAY, t), local(2026, 10, 5, 0, 0, 0));
	T_EQ_I64(rl_bucket_start(RL_TIER_MONTH, t), local(2026, 10, 1, 0, 0, 0));
	T_EQ_I64(rl_bucket_next(RL_TIER_MONTH, local(2026, 10, 31, 23, 59, 0)), local(2026, 11, 1, 0, 0, 0));
	T_EQ_I64(rl_bucket_next(RL_TIER_MONTH, local(2026, 12, 15, 0, 0, 0)), local(2027, 1, 1, 0, 0, 0));
	T_EQ_I64(rl_bucket_next(RL_TIER_MINUTE, t), local(2026, 10, 5, 13, 48, 0));
	T_EQ_I64(rl_local_hour(t), 13);
}

static void half_hour_zone(void)
{
	rl_tz_apply("IST-5:30");
	int64_t t = local(2026, 10, 5, 10, 15, 0);
	int64_t h = rl_bucket_start(RL_TIER_HOUR, t);
	T_EQ_I64(h, local(2026, 10, 5, 10, 0, 0));
	T_EQ_I64(h % 3600, 1800); /* 04:30 UTC */
	T_EQ_I64(rl_bucket_next(RL_TIER_HOUR, t), local(2026, 10, 5, 11, 0, 0));
}

static void dst_day_lengths(void)
{
	rl_tz_apply("CET-1CEST,M3.5.0,M10.5.0/3");
	/* 2026-10-25: DST ends, the day has 25 hours; 2026-03-29: 23 hours. */
	int64_t d = rl_bucket_start(RL_TIER_DAY, local(2026, 10, 25, 12, 0, 0));
	T_EQ_I64(rl_bucket_next(RL_TIER_DAY, d) - d, 25 * 3600);
	int64_t s = rl_bucket_start(RL_TIER_DAY, local(2026, 3, 29, 12, 0, 0));
	T_EQ_I64(rl_bucket_next(RL_TIER_DAY, s) - s, 23 * 3600);
	/* Hour buckets stay one real hour long across the change. */
	int64_t h = rl_bucket_start(RL_TIER_HOUR, d + 2 * 3600 + 1800);
	T_EQ_I64(rl_bucket_next(RL_TIER_HOUR, h) - h, 3600);
}

static void utc_and_ceil(void)
{
	rl_tz_apply(NULL);
	T_EQ_I64(rl_local_hour(1759650000), (1759650000 % 86400) / 3600);
	T_EQ_I64(rl_bucket_ceil(RL_TIER_HOUR, 7200), 7200);
	T_EQ_I64(rl_bucket_ceil(RL_TIER_HOUR, 7201), 10800);
	T_EQ_I64(rl_bucket_start(RL_TIER_MINUTE, 119), 60);
	T_EQ_STR(rl_tier_name(RL_TIER_DAY), "day");
	T_EQ_I64(rl_tier_seconds(RL_TIER_HOUR), 3600);
}

int main(void)
{
	T_RUN(shanghai_hour_day_month);
	T_RUN(half_hour_zone);
	T_RUN(dst_day_lengths);
	T_RUN(utc_and_ceil);
	T_DONE();
}
