#define _GNU_SOURCE
#include <stdlib.h>
#include <time.h>

#include "core/timeutil.h"

static int64_t floor_mod(int64_t a, int64_t m)
{
	int64_t r = a % m;
	return r < 0 ? r + m : r;
}

static void to_local(int64_t ts, struct tm *tm)
{
	time_t t = (time_t)ts;
	localtime_r(&t, tm);
}

static int64_t from_local(struct tm *tm)
{
	tm->tm_isdst = -1;
	return (int64_t)mktime(tm);
}

int64_t rl_bucket_start(rl_tier tier, int64_t ts)
{
	struct tm tm;

	switch (tier) {
	case RL_TIER_MINUTE:
		/* every zone offset is a whole number of minutes */
		return ts - floor_mod(ts, 60);
	case RL_TIER_HOUR:
		/* align to local hours via the offset in force at ts: handles +5:30 and DST */
		to_local(ts, &tm);
		return ts - floor_mod(ts + tm.tm_gmtoff, 3600);
	case RL_TIER_DAY:
		to_local(ts, &tm);
		tm.tm_hour = tm.tm_min = tm.tm_sec = 0;
		return from_local(&tm);
	case RL_TIER_MONTH:
	default:
		to_local(ts, &tm);
		tm.tm_mday = 1;
		tm.tm_hour = tm.tm_min = tm.tm_sec = 0;
		return from_local(&tm);
	}
}

int64_t rl_bucket_next(rl_tier tier, int64_t ts)
{
	int64_t start = rl_bucket_start(tier, ts);
	struct tm tm;

	switch (tier) {
	case RL_TIER_MINUTE:
		return start + 60;
	case RL_TIER_HOUR:
		return start + 3600;
	case RL_TIER_DAY:
		to_local(start, &tm);
		tm.tm_mday++;
		tm.tm_hour = tm.tm_min = tm.tm_sec = 0;
		return from_local(&tm);
	case RL_TIER_MONTH:
	default:
		to_local(start, &tm);
		tm.tm_mon++;
		tm.tm_mday = 1;
		tm.tm_hour = tm.tm_min = tm.tm_sec = 0;
		return from_local(&tm);
	}
}

int64_t rl_bucket_ceil(rl_tier tier, int64_t ts)
{
	int64_t start = rl_bucket_start(tier, ts);
	return start == ts ? ts : rl_bucket_next(tier, ts);
}

int rl_local_hour(int64_t ts)
{
	struct tm tm;
	to_local(ts, &tm);
	return tm.tm_hour;
}

void rl_tz_apply(const char *posix_tz)
{
	setenv("TZ", posix_tz && *posix_tz ? posix_tz : "UTC0", 1);
	tzset();
}

int64_t rl_tier_seconds(rl_tier tier)
{
	static const int64_t secs[RL_TIER_COUNT] = { 60, 3600, 86400, 31 * 86400 };
	return tier < RL_TIER_COUNT ? secs[tier] : 0;
}

const char *rl_tier_name(rl_tier tier)
{
	static const char *const names[RL_TIER_COUNT] = { "minute", "hour", "day", "month" };
	return tier < RL_TIER_COUNT ? names[tier] : "?";
}
