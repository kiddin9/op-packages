#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#include "t.h"

#include "core/store.h"

static char dir[64];

static void fresh_dir(void)
{
	snprintf(dir, sizeof(dir), "/tmp/rl-store-XXXXXX");
	if (!mkdtemp(dir))
		abort();
}

static rl_rec rec(int64_t ts, uint16_t dev, uint64_t rx)
{
	rl_rec r = { .ts = ts, .dev = dev, .cls = 0, .conns = 3, .rx = rx, .tx = rx / 2 };
	return r;
}

static void put(rl_store *s, rl_tier t, rl_rec r)
{
	rl_store_append(s, t, &r);
}

typedef struct {
	int n;
	uint64_t rx;
	int64_t first, last;
	bool ordered;
} scan_acc;

static bool acc_cb(const rl_rec *r, void *ctx)
{
	scan_acc *a = ctx;
	if (a->n == 0)
		a->first = r->ts;
	else if (r->ts < a->last)
		a->ordered = false;
	a->last = r->ts;
	a->n++;
	a->rx += r->rx;
	return true;
}

static scan_acc scan(rl_store *s, rl_tier t, int64_t a, int64_t b)
{
	scan_acc acc = { .ordered = true };
	rl_store_scan(s, t, a, b, acc_cb, &acc);
	return acc;
}

static void roundtrip(void)
{
	fresh_dir();
	rl_store *s = rl_store_open(dir);
	T_ASSERT(s != NULL);
	for (int i = 0; i < 100; i++)
		rl_store_append(s, RL_TIER_MINUTE, &(rl_rec){ .ts = 60 * i, .dev = (uint16_t)i, .rx = (uint64_t)i << 33, .tx = 7, .conns = 9, .cls = 1 });
	T_EQ_I64(rl_store_commit(s), 0);
	T_EQ_U64(rl_store_pending(s), 0);
	rl_store_close(s);
	s = rl_store_open(dir);
	scan_acc a = scan(s, RL_TIER_MINUTE, 0, 6000);
	T_EQ_I64(a.n, 100);
	T_ASSERT(a.ordered);
	T_EQ_U64(rl_store_bytes(s), RL_STORE_HDR_SIZE * 4 + 100 * RL_STORE_REC_SIZE);
	T_EQ_I64(rl_store_oldest(s, RL_TIER_MINUTE), 0);
	T_EQ_I64(rl_store_oldest(s, RL_TIER_DAY), INT64_MAX);
	rl_store_close(s);
}

static void uncommitted_is_lost(void)
{
	fresh_dir();
	rl_store *s = rl_store_open(dir);
	rl_store_append(s, RL_TIER_HOUR, &(rl_rec){ .ts = 3600, .rx = 1 });
	rl_store_commit(s);
	rl_store_append(s, RL_TIER_HOUR, &(rl_rec){ .ts = 7200, .rx = 2 });
	rl_store_close(s);
	s = rl_store_open(dir);
	T_EQ_I64(scan(s, RL_TIER_HOUR, 0, 100000).n, 1);
	rl_store_append(s, RL_TIER_HOUR, &(rl_rec){ .ts = 10800, .rx = 3 });
	rl_store_discard_pending(s);
	T_EQ_U64(rl_store_pending(s), 0);
	rl_store_commit(s);
	rl_store_close(s);
	s = rl_store_open(dir);
	T_EQ_I64(scan(s, RL_TIER_HOUR, 0, 100000).n, 1);
	rl_store_close(s);
}

static void scan_range_disk_and_pending(void)
{
	fresh_dir();
	rl_store *s = rl_store_open(dir);
	for (int i = 0; i < 10; i++)
		rl_store_append(s, RL_TIER_MINUTE, &(rl_rec){ .ts = 60 * i, .rx = 1 });
	rl_store_commit(s);
	for (int i = 10; i < 15; i++)
		rl_store_append(s, RL_TIER_MINUTE, &(rl_rec){ .ts = 60 * i, .rx = 10 });
	scan_acc a = scan(s, RL_TIER_MINUTE, 300, 720); /* ts 300..660 */
	T_EQ_I64(a.n, 7);
	T_EQ_U64(a.rx, 5 * 1 + 2 * 10);
	T_EQ_I64(a.first, 300);
	T_EQ_I64(a.last, 660);
	T_ASSERT(a.ordered);
	T_EQ_I64(scan(s, RL_TIER_MINUTE, 5000, 6000).n, 0);
	rl_store_close(s);
}

static void compact_expired(void)
{
	fresh_dir();
	rl_store *s = rl_store_open(dir);
	rl_retention ret = { .minute_hours = 1, .hour_days = 1, .day_days = 1, .event_days = 1 };
	int64_t now = 100000;
	for (int i = 0; i < 100; i++)
		put(s, RL_TIER_MINUTE, rec(now - 6000 + 60 * i, 1, 1));
	rl_store_commit(s);
	T_EQ_I64(rl_store_compact(s, now, &ret, 1 << 30), 0);
	scan_acc a = scan(s, RL_TIER_MINUTE, 0, now * 2);
	T_EQ_I64(a.n, 60); /* the last hour */
	T_EQ_I64(a.first, now - 3600);
	rl_store_close(s);
	s = rl_store_open(dir);
	T_EQ_I64(rl_store_recovered(s), 0);
	T_EQ_I64(scan(s, RL_TIER_MINUTE, 0, now * 2).n, 60);
	rl_store_close(s);
}

static void compact_size_cap(void)
{
	fresh_dir();
	rl_store *s = rl_store_open(dir);
	rl_retention ret = { .minute_hours = 1000, .hour_days = 1000, .day_days = 1000, .event_days = 1 };
	for (int i = 0; i < 50; i++) {
		put(s, RL_TIER_MINUTE, rec(1000000 + 60 * i, 1, 1));
		put(s, RL_TIER_HOUR, rec(1000000 + 3600 * i, 1, 1));
	}
	rl_store_commit(s);
	uint64_t cap = RL_STORE_HDR_SIZE * 4 + 70 * RL_STORE_REC_SIZE;
	rl_store_compact(s, 1100000, &ret, cap);
	T_ASSERT(rl_store_bytes(s) <= cap);
	T_EQ_I64(scan(s, RL_TIER_MINUTE, 0, INT64_MAX).n, 20); /* minute tier pays first */
	T_EQ_I64(scan(s, RL_TIER_HOUR, 0, INT64_MAX).n, 50);
	T_EQ_I64(scan(s, RL_TIER_MINUTE, 0, INT64_MAX).first, 1000000 + 60 * 30);
	rl_store_close(s);
}

static void damaged_file(void)
{
	fresh_dir();
	rl_store *s = rl_store_open(dir);
	put(s, RL_TIER_DAY, rec(86400, 1, 1));
	rl_store_commit(s);
	rl_store_close(s);
	char path[128];
	snprintf(path, sizeof(path), "%s/traffic.day", dir);
	T_EQ_I64(truncate(path, RL_STORE_HDR_SIZE + RL_STORE_REC_SIZE / 2), 0);
	s = rl_store_open(dir);
	T_EQ_I64(rl_store_recovered(s), 1);
	T_EQ_I64(scan(s, RL_TIER_DAY, 0, INT64_MAX).n, 0);
	put(s, RL_TIER_DAY, rec(86400, 1, 1));
	T_EQ_I64(rl_store_commit(s), 0);
	T_EQ_I64(scan(s, RL_TIER_DAY, 0, INT64_MAX).n, 1);
	snprintf(path, sizeof(path), "%s/traffic.day.bad", dir);
	T_EQ_I64(access(path, F_OK), 0);
	rl_store_close(s);
}

static void failed_compaction_keeps_file(void)
{
	fresh_dir();
	rl_store *s = rl_store_open(dir);
	rl_retention ret = { .minute_hours = 1, .hour_days = 1, .day_days = 1, .event_days = 1 };
	for (int i = 0; i < 10; i++)
		put(s, RL_TIER_MINUTE, rec(60 * i, 1, 1));
	rl_store_commit(s);
	char tmp[128];
	snprintf(tmp, sizeof(tmp), "%s/traffic.minute.tmp", dir);
	mkdir(tmp, 0700); /* the temporary file cannot be created */
	T_ASSERT(rl_store_compact(s, 1000000, &ret, 1 << 30) != 0);
	T_EQ_I64(scan(s, RL_TIER_MINUTE, 0, INT64_MAX).n, 10);
	rl_store_close(s);
}

static void reset_and_retention(void)
{
	fresh_dir();
	rl_store *s = rl_store_open(dir);
	put(s, RL_TIER_MONTH, rec(0, 1, 1));
	rl_store_commit(s);
	put(s, RL_TIER_MONTH, rec(1, 1, 1));
	T_EQ_I64(rl_store_reset(s), 0);
	T_EQ_I64(scan(s, RL_TIER_MONTH, 0, INT64_MAX).n, 0);
	T_EQ_U64(rl_store_pending(s), 0);
	rl_store_close(s);
	rl_retention r = { .minute_hours = 48, .hour_days = 90, .day_days = 730, .event_days = 90 };
	T_EQ_I64(rl_retention_seconds(&r, RL_TIER_MINUTE), 48 * 3600);
	T_EQ_I64(rl_retention_seconds(&r, RL_TIER_DAY), 730 * 86400LL);
	T_EQ_I64(rl_retention_seconds(&r, RL_TIER_MONTH), -1);
}

int main(void)
{
	T_RUN(roundtrip);
	T_RUN(uncommitted_is_lost);
	T_RUN(scan_range_disk_and_pending);
	T_RUN(compact_expired);
	T_RUN(compact_size_cap);
	T_RUN(damaged_file);
	T_RUN(failed_compaction_keeps_file);
	T_RUN(reset_and_retention);
	T_DONE();
}
