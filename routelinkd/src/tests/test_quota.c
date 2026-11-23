#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#include "t.h"

#include "core/quota.h"
#include "core/schedule.h"
#include "core/timeutil.h"

/* Local wall-clock time → epoch seconds in the applied TZ. */
static int64_t local(int y, int mo, int d, int h, int mi)
{
	struct tm tm = { .tm_year = y - 1900, .tm_mon = mo - 1, .tm_mday = d, .tm_hour = h, .tm_min = mi, .tm_isdst = -1 };
	return (int64_t)mktime(&tm);
}

static void test_schedule_parse(void)
{
	T_EQ_I64(rl_weekday_parse("mon"), 1);
	T_EQ_I64(rl_weekday_parse("sun"), 7);
	T_EQ_I64(rl_weekday_parse("Mon"), 0);
	T_EQ_I64(rl_time_parse("20:00"), 1200);
	T_EQ_I64(rl_time_parse("7:05"), 425);
	T_EQ_I64(rl_time_parse("24:00"), -1);
	T_EQ_I64(rl_time_parse("12:60"), -1);
	T_EQ_I64(rl_time_parse("12:3"), -1);
	T_EQ_I64(rl_time_parse(""), -1);
}

static void test_schedule_windows(void)
{
	rl_schedule always = { 0, -1, -1 };
	T_ASSERT(rl_schedule_active(&always, 3, 0));

	/* Weekdays 19:00–22:00 */
	rl_schedule evening = { 0x1f, 19 * 60, 22 * 60 };
	T_ASSERT(rl_schedule_active(&evening, 1, 19 * 60));
	T_ASSERT(!rl_schedule_active(&evening, 1, 22 * 60));
	T_ASSERT(!rl_schedule_active(&evening, 6, 20 * 60));

	/* Friday and Saturday nights 22:00–07:00 run into Saturday and Sunday mornings. */
	rl_schedule night = { (1 << 4) | (1 << 5), 22 * 60, 7 * 60 };
	T_ASSERT(rl_schedule_active(&night, 5, 23 * 60));
	T_ASSERT(rl_schedule_active(&night, 6, 6 * 60));
	T_ASSERT(rl_schedule_active(&night, 7, 6 * 60 + 59));
	T_ASSERT(!rl_schedule_active(&night, 7, 23 * 60));
	T_ASSERT(!rl_schedule_active(&night, 5, 6 * 60));
	/* Sunday night wraps to Monday morning. */
	rl_schedule sunday = { 1 << 6, 23 * 60, 1 * 60 };
	T_ASSERT(rl_schedule_active(&sunday, 1, 30));

	rl_tz_apply("CST-8");
	T_ASSERT(rl_schedule_active_at(&evening, local(2026, 10, 9, 20, 30))); /* a Friday */
	T_ASSERT(!rl_schedule_active_at(&evening, local(2026, 10, 10, 20, 30)));
}

static void test_quota_bounds(void)
{
	int64_t s, e;
	rl_tz_apply("CST-8");
	int64_t now = local(2027, 1, 15, 15, 0); /* Friday */
	rl_quota_bounds(RL_QUOTA_DAY, 1, now, &s, &e);
	T_EQ_I64(s, local(2027, 1, 15, 0, 0));
	T_EQ_I64(e, local(2027, 1, 16, 0, 0));
	rl_quota_bounds(RL_QUOTA_WEEK, 1, now, &s, &e);
	T_EQ_I64(s, local(2027, 1, 11, 0, 0));
	T_EQ_I64(e, local(2027, 1, 18, 0, 0));
	rl_quota_bounds(RL_QUOTA_WEEK, 5, now, &s, &e); /* weeks from Friday: today */
	T_EQ_I64(s, local(2027, 1, 15, 0, 0));
	rl_quota_bounds(RL_QUOTA_MONTH, 1, now, &s, &e);
	T_EQ_I64(s, local(2027, 1, 1, 0, 0));
	T_EQ_I64(e, local(2027, 2, 1, 0, 0));
	rl_quota_bounds(RL_QUOTA_MONTH, 20, now, &s, &e); /* before the 20th: from last December */
	T_EQ_I64(s, local(2026, 12, 20, 0, 0));
	T_EQ_I64(e, local(2027, 1, 20, 0, 0));
	rl_quota_bounds(RL_QUOTA_MONTH, 15, now, &s, &e); /* on the reset day itself */
	T_EQ_I64(s, local(2027, 1, 15, 0, 0));

	/* Across a DST change the day is 23 hours long, midnight to midnight. */
	rl_tz_apply("CET-1CEST,M3.5.0,M10.5.0/3");
	now = local(2026, 3, 29, 12, 0);
	rl_quota_bounds(RL_QUOTA_DAY, 1, now, &s, &e);
	T_EQ_I64(e - s, 23 * 3600);
	rl_quota_bounds(RL_QUOTA_MONTH, 1, local(2026, 3, 31, 23, 30), &s, &e);
	T_EQ_I64(s, local(2026, 3, 1, 0, 0));
	T_EQ_I64(e, local(2026, 4, 1, 0, 0));
	rl_tz_apply(NULL);
}

static void test_quota_states(void)
{
	rl_quota_run r = { 0 };
	const uint64_t limit = 1000;
	T_EQ_U64(rl_quota_step(&r, 10, 1, 100, limit), 0);
	T_EQ_I64(r.state, RL_QS_OK);
	T_EQ_U64(rl_quota_step(&r, 20, 1, 800, limit), RL_QA_WARN);
	T_EQ_STR(rl_quota_state_name(r.state), "warned");
	T_EQ_U64(rl_quota_step(&r, 30, 1, 900, limit), 0); /* warned once */
	T_EQ_U64(rl_quota_step(&r, 40, 1, 1000, limit), RL_QA_ENFORCE);
	T_EQ_I64(r.state, RL_QS_EXCEEDED);
	T_EQ_U64(rl_quota_step(&r, 50, 1, 1200, limit), 0);

	/* Let through for an hour, then enforced again. */
	T_EQ_U64(rl_quota_allow(&r, 50 + 3600), RL_QA_RELEASE);
	T_EQ_U64(rl_quota_step(&r, 60, 1, 1300, limit), 0);
	T_EQ_I64(r.state, RL_QS_ALLOWED);
	T_EQ_U64(rl_quota_step(&r, 50 + 3600, 1, 1400, limit), RL_QA_ENFORCE);

	/* The next period resets and releases. */
	T_EQ_U64(rl_quota_step(&r, 90000, 2, 0, limit), RL_QA_RESET | RL_QA_RELEASE);
	T_EQ_I64(r.state, RL_QS_OK);
	T_ASSERT(!r.warned && !r.enforced);

	/* Jumping straight past 100 % enforces without a separate warning; allowing until the period ends lasts. */
	T_EQ_U64(rl_quota_step(&r, 90010, 2, 5000, limit), RL_QA_ENFORCE);
	T_EQ_U64(rl_quota_allow(&r, 172800), RL_QA_RELEASE);
	T_EQ_U64(rl_quota_step(&r, 100000, 2, 6000, limit), 0);
	T_EQ_U64(rl_quota_step(&r, 172800, 3, 0, limit), RL_QA_RESET);
}

static void test_quota_raised(void)
{
	rl_quota_run r = { 0 };
	T_EQ_U64(rl_quota_step(&r, 10, 1, 1000, 1000), RL_QA_ENFORCE);
	/* the limit is raised: the device is let go, and the new 80 % mark warns again */
	T_EQ_U64(rl_quota_step(&r, 20, 1, 1000, 2000), RL_QA_RELEASE);
	T_EQ_I64(r.state, RL_QS_OK);
	T_ASSERT(!r.enforced && !r.warned);
	T_EQ_U64(rl_quota_step(&r, 30, 1, 1700, 2000), RL_QA_WARN);
	T_EQ_U64(rl_quota_step(&r, 40, 1, 2100, 2000), RL_QA_ENFORCE);
	/* no limit at all (limit_mb 0) lifts it too */
	T_EQ_U64(rl_quota_step(&r, 50, 1, 2100, 0), RL_QA_RELEASE);
	T_EQ_I64(r.state, RL_QS_OK);
}

static void test_quota_file(void)
{
	char path[] = "/tmp/rl-quota-XXXXXX";
	int fd = mkstemp(path);
	T_ASSERT(fd >= 0);
	close(fd);
	unlink(path);
	rl_quota_saved *q;
	size_t n;
	T_EQ_I64(rl_quota_load(path, &q, &n), 0); /* missing: empty */
	T_EQ_U64(n, 0);
	rl_quota_saved s[2] = {
		{ "cfg0a1b2c", { 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x01 }, { .period_start = 1700000000, .warned = true } },
		{ "tv", { 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x02 },
		  { .period_start = 1700000001, .warned = true, .enforced = true, .allow_until = 1700003600 } },
	};
	T_EQ_I64(rl_quota_save(path, s, 2), 0);
	T_EQ_I64(rl_quota_load(path, &q, &n), 0);
	T_EQ_U64(n, 2);
	if (n == 2) {
		T_EQ_STR(q[0].section, "cfg0a1b2c");
		T_ASSERT(memcmp(q[1].mac, s[1].mac, 6) == 0);
		T_EQ_I64(q[0].run.period_start, 1700000000);
		T_ASSERT(q[0].run.warned && !q[0].run.enforced);
		T_ASSERT(q[1].run.enforced);
		T_EQ_I64(q[1].run.allow_until, 1700003600);
	}
	free(q);
	FILE *f = fopen(path, "w");
	fputs("{\"quotas\": 3", f);
	fclose(f);
	T_EQ_I64(rl_quota_load(path, &q, &n), -1);
	T_EQ_U64(n, 0);
	unlink(path);
}

int main(void)
{
	T_RUN(test_schedule_parse);
	T_RUN(test_schedule_windows);
	T_RUN(test_quota_bounds);
	T_RUN(test_quota_states);
	T_RUN(test_quota_raised);
	T_RUN(test_quota_file);
	T_DONE();
}
