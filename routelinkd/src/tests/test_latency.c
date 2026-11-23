#include <stdlib.h>
#include <unistd.h>

#include "t.h"

#include "core/latency.h"
#include "core/util.h"

/* 2025-10-15 00:00:00 UTC */
static const int64_t DAY0 = 1760486400;
#define H(h, m, s) (DAY0 + (h) * 3600 + (m) * 60 + (s))

static char dir[64], path[160];

static void fresh_dir(void)
{
	rl_tz_apply("UTC0");
	snprintf(dir, sizeof(dir), "/tmp/rl-lat-XXXXXX");
	if (!mkdtemp(dir))
		abort();
}

static rl_series *open_series(const char *name, uint16_t kind)
{
	snprintf(path, sizeof(path), "%s/%s", dir, name);
	rl_series *s = rl_series_open(path, kind, NULL);
	if (!s)
		abort();
	return s;
}

static rl_ip ip(const char *s)
{
	rl_ip a;
	if (!rl_ip_parse(s, &a))
		abort();
	return a;
}

/* Records written by an rl_lat, decoded. */
#define MAXREC 256
static struct {
	rl_tier tier[MAXREC];
	int64_t ts[MAXREC];
	int id[MAXREC];
	rl_probe_agg a[MAXREC];
	int n;
	rl_series *minute, *hour; /* also appended here when set */
} recs;

static void on_rec(rl_tier tier, const uint8_t raw[RL_SERIES_REC_SIZE], void *ctx)
{
	(void)ctx;
	if (recs.n < MAXREC) {
		recs.tier[recs.n] = tier;
		rl_probe_decode(raw, &recs.ts[recs.n], &recs.id[recs.n], &recs.a[recs.n]);
		recs.n++;
	}
	rl_series *s = tier == RL_TIER_HOUR ? recs.hour : recs.minute;
	if (s)
		rl_series_append(s, raw);
}

static void reset_recs(rl_series *minute, rl_series *hour)
{
	memset(&recs, 0, sizeof(recs));
	recs.minute = minute;
	recs.hour = hour;
}

/* Ids stay with their address; a free id comes first, then the oldest one not configured. */
static void test_targets(void)
{
	fresh_dir();
	rl_lat_targets t;
	bool changed = false;
	rl_lat_targets_init(&t);
	rl_ip a = ip("223.5.5.5"), b = ip("119.29.29.29"), v6 = ip("2400:3200::1");
	T_EQ_I64(rl_lat_targets_assign(&t, &a, 0, 100, &changed), 1);
	T_ASSERT(changed);
	T_EQ_I64(rl_lat_targets_assign(&t, &b, 0, 200, &changed), 2);
	T_EQ_I64(rl_lat_targets_assign(&t, &v6, 0, 300, &changed), 3);
	changed = false;
	T_EQ_I64(rl_lat_targets_assign(&t, &a, 0, 400, &changed), 1);
	T_ASSERT(!changed);
	T_EQ_I64(t.slot[1].since, 100);

	/* the gateway keeps id 0 while its address changes */
	rl_ip gw = ip("100.64.0.1");
	T_ASSERT(rl_lat_targets_gateway(&t, &gw));
	T_ASSERT(!rl_lat_targets_gateway(&t, &gw));
	T_EQ_U64(rl_lat_targets_find(&t, &gw), 1);
	T_EQ_U64(rl_lat_targets_find(&t, &b), 1u << 2);
	rl_ip none = ip("9.9.9.9");
	T_EQ_U64(rl_lat_targets_find(&t, &none), 0);

	snprintf(path, sizeof(path), "%s/latency.targets.json", dir);
	T_EQ_I64(rl_lat_targets_save(&t, path), 0);
	rl_lat_targets u;
	T_EQ_I64(rl_lat_targets_load(&u, path), 0);
	T_ASSERT(rl_ip_eq(&u.slot[0].ip, &gw));
	T_ASSERT(u.slot[3].used && rl_ip_eq(&u.slot[3].ip, &v6));
	T_EQ_I64(u.slot[2].since, 200);
	T_ASSERT(!u.slot[4].used);

	/* full table: the oldest id outside keep is reused and its old records stop counting */
	for (int i = 4; i < RL_LAT_IDS; i++) {
		char s[32];
		snprintf(s, sizeof(s), "10.0.%d.1", i);
		rl_ip x = ip(s);
		T_EQ_I64(rl_lat_targets_assign(&t, &x, 0, 1000 + i, &changed), i);
	}
	rl_ip late = ip("10.9.9.9");
	T_EQ_I64(rl_lat_targets_assign(&t, &late, 1u << 1, 5000, &changed), 2);
	T_EQ_I64(t.slot[2].since, 5000);
	T_EQ_I64(rl_lat_targets_assign(&t, &none, ~0ULL, 5000, &changed), -1);

	/* damaged and missing files give an empty table */
	FILE *f = fopen(path, "w");
	fputs("{\"version\":1,\"targets\":[{\"id\":5,\"ip\":\"nonsense\"}]}", f);
	fclose(f);
	T_EQ_I64(rl_lat_targets_load(&u, path), -1);
	T_ASSERT(u.slot[0].used && !u.slot[5].used);
	unlink(path);
	T_EQ_I64(rl_lat_targets_load(&u, path), 0);
	T_ASSERT(!u.slot[1].used);
	rmdir(dir);
}

/* Minute records when the minute ends, hour records when the hour ends, partial ones on flush. */
static void test_buckets(void)
{
	rl_tz_apply("UTC0");
	reset_recs(NULL, NULL);
	rl_lat l;
	rl_lat_init(&l, on_rec, NULL);
	for (int r = 0; r < 6; r++) {
		rl_lat_add(&l, H(1, 0, 10 * r), 0, true, 1000);
		rl_lat_add(&l, H(1, 0, 10 * r), 1, r != 3, 20000 + 1000 * (uint32_t)r);
	}
	rl_lat_tick(&l, H(1, 0, 59));
	T_EQ_I64(recs.n, 0);
	rl_lat_tick(&l, H(1, 1, 0));
	T_EQ_I64(recs.n, 2);
	T_EQ_I64(recs.tier[1], RL_TIER_MINUTE);
	T_EQ_I64(recs.ts[1], H(1, 0, 0));
	T_EQ_I64(recs.id[1], 1);
	T_EQ_U64(recs.a[1].sent, 6);
	T_EQ_U64(recs.a[1].lost, 1);
	T_EQ_U64(recs.a[1].min_us, 20000);
	T_EQ_U64(recs.a[1].max_us, 25000);
	T_EQ_U64(rl_probe_agg_avg(&recs.a[1]), (20000 + 21000 + 22000 + 24000 + 25000) / 5);

	/* a probe in a later minute closes the open one itself; flush writes the partial minute */
	rl_lat_add(&l, H(1, 5, 0), 1, false, 0);
	rl_lat_flush(&l, false);
	T_EQ_I64(recs.n, 3);
	T_EQ_I64(recs.ts[2], H(1, 5, 0));
	T_EQ_U64(recs.a[2].lost, 1);
	rl_lat_add(&l, H(1, 5, 30), 1, true, 3000);
	rl_lat_tick(&l, H(2, 0, 0));
	/* the rest of minute 1:05, then the hour with everything */
	T_EQ_I64(recs.n, 6);
	T_EQ_I64(recs.ts[3], H(1, 5, 0));
	T_EQ_U64(recs.a[3].sent, 1);
	T_EQ_I64(recs.tier[4], RL_TIER_HOUR);
	T_EQ_I64(recs.ts[4], H(1, 0, 0));
	T_EQ_I64(recs.id[5], 1);
	T_EQ_U64(recs.a[5].sent, 8);
	T_EQ_U64(recs.a[5].lost, 2);
	T_EQ_U64(recs.a[5].min_us, 3000);
	rl_lat_tick(&l, H(3, 0, 0));
	T_EQ_I64(recs.n, 6);

	rl_lat_add(&l, H(3, 0, 0), 2, true, 1);
	rl_lat_reset(&l);
	rl_lat_flush(&l, true);
	T_EQ_I64(recs.n, 6);
}

/* Hours that ended while stopped are written from the minutes; the current hour is rebuilt. */
static void test_recover(void)
{
	fresh_dir();
	rl_series *m = open_series("latency.minute", RL_LAT_KIND_MINUTE);
	rl_series *h = open_series("latency.hour", RL_LAT_KIND_HOUR);
	reset_recs(m, h);
	rl_lat l;
	rl_lat_init(&l, on_rec, NULL);
	/* hour 0 closed normally, hour 1 has minutes only (stopped at 1:30), hour 3 is the current one */
	for (int mi = 0; mi < 60; mi += 20)
		rl_lat_add(&l, H(0, mi, 0), 1, true, 1000);
	rl_lat_add(&l, H(1, 10, 0), 1, true, 2000);
	rl_lat_add(&l, H(1, 10, 0), 0, true, 500);
	rl_lat_add(&l, H(1, 29, 50), 1, false, 0);
	rl_lat_flush(&l, false); /* stopped: the partial minute is written, the hour is not */
	rl_lat_init(&l, on_rec, NULL);
	rl_lat_add(&l, H(3, 2, 0), 1, true, 4000);
	rl_lat_flush(&l, false);
	T_EQ_I64(rl_series_newest(h), H(0, 0, 0));
	rl_series_commit(m);
	rl_series_commit(h);

	rl_lat r;
	rl_lat_init(&r, on_rec, NULL);
	T_EQ_I64(rl_lat_recover(&r, m, h, H(3, 5, 0)), 2);
	T_EQ_I64(rl_series_newest(h), H(1, 0, 0));
	T_EQ_I64(r.start[1], H(3, 0, 0));
	T_EQ_U64(r.acc[1][1].sent, 1);
	T_EQ_U64(r.acc[1][1].min_us, 4000);

	/* hour 1 as written: id 1 merged from two minutes */
	rl_latq_ctx c = { .minute = m, .hour = h, .targets = NULL, .now = H(3, 5, 0) + 30 * 86400, .minute_days = 7 };
	rl_lat_targets t;
	rl_lat_targets_init(&t);
	bool changed;
	rl_ip x = ip("1.1.1.1");
	rl_lat_targets_assign(&t, &x, 0, 0, &changed);
	c.targets = &t;
	rl_lat_history q;
	T_EQ_I64(rl_lat_query(&c, H(0, 0, 0), H(4, 0, 0), 0, ~0ULL, 0, &q), 0);
	T_EQ_I64(q.tier, RL_TIER_HOUR);
	T_EQ_I64(q.n, 4);
	T_EQ_I64(q.n_ids, 2);
	T_EQ_U64(q.pts[1][1].sent, 2);
	T_EQ_U64(q.pts[1][1].lost, 1);
	T_EQ_U64(q.pts[1][2].sent, 0);
	T_EQ_U64(q.pts[0][1].sent, 1);
	rl_lat_history_free(&q);

	/* a second recovery finds nothing new */
	rl_lat_init(&r, on_rec, NULL);
	T_EQ_I64(rl_lat_recover(&r, m, h, H(3, 6, 0)), 0);
	rl_series_close(m);
	rl_series_close(h);
	unlink(path);
	snprintf(path, sizeof(path), "%s/latency.minute", dir);
	unlink(path);
	rmdir(dir);
}

/* The grid: merged partial records, the open bucket, ids reused, wanted and listed targets, coarser steps. */
static void test_query(void)
{
	fresh_dir();
	rl_series *m = open_series("latency.minute", RL_LAT_KIND_MINUTE);
	reset_recs(m, NULL);
	rl_lat_targets t;
	rl_lat_targets_init(&t);
	bool changed;
	rl_ip a = ip("223.5.5.5"), b = ip("1.1.1.1"), g = ip("100.64.0.1");
	rl_lat_targets_gateway(&t, &g);
	rl_lat_targets_assign(&t, &a, 0, 0, &changed);         /* id 1 */
	rl_lat_targets_assign(&t, &b, 0, H(0, 3, 0), &changed); /* id 2, reused at 0:03 */

	rl_lat l;
	rl_lat_init(&l, on_rec, NULL);
	rl_lat_add(&l, H(0, 0, 0), 1, true, 10000);
	rl_lat_add(&l, H(0, 0, 0), 2, true, 99000); /* before id 2 was reassigned: ignored */
	rl_lat_add(&l, H(0, 0, 10), 1, true, 30000);
	rl_lat_flush(&l, false);
	rl_lat_add(&l, H(0, 0, 20), 1, false, 0);
	rl_lat_add(&l, H(0, 4, 0), 2, true, 5000);
	rl_lat_add(&l, H(0, 5, 0), 1, true, 7000); /* open minute */

	rl_latq_ctx c = { .minute = m, .open = &l, .targets = &t, .now = H(0, 5, 30), .minute_days = 7 };
	rl_lat_history q;
	T_EQ_I64(rl_lat_query(&c, H(0, 0, 30), H(1, 0, 0), 0, ~0ULL, 1, &q), 0);
	T_EQ_I64(q.tier, RL_TIER_MINUTE);
	T_EQ_I64(q.first, H(0, 0, 0));
	T_EQ_I64(q.step, 60);
	T_EQ_I64(q.n, 6); /* up to the open minute */
	T_EQ_I64(q.n_ids, 3);
	T_EQ_I64(q.ids[0], 0); /* listed without data */
	T_EQ_U64(q.sum[0].sent, 0);
	T_EQ_I64(q.ids[1], 1);
	T_EQ_U64(q.pts[1][0].sent, 3);
	T_EQ_U64(q.pts[1][0].lost, 1);
	T_EQ_U64(rl_probe_agg_avg(&q.pts[1][0]), 20000);
	T_EQ_U64(q.pts[1][0].max_us, 30000);
	T_EQ_U64(q.pts[1][5].sent, 1);
	T_EQ_U64(q.sum[1].sent, 4);
	T_EQ_I64(q.ids[2], 2);
	T_EQ_U64(q.pts[2][0].sent, 0);
	T_EQ_U64(q.sum[2].sent, 1);
	T_EQ_U64(q.sum[2].max_us, 5000);
	rl_lat_history_free(&q);

	/* one target; two minutes per point */
	T_EQ_I64(rl_lat_query(&c, H(0, 0, 0), H(0, 6, 0), 3, 1u << 1, 1u << 1, &q), 0);
	T_EQ_I64(q.n_ids, 1);
	T_EQ_I64(q.step, 120);
	T_EQ_I64(q.n, 3);
	T_EQ_U64(q.pts[0][0].sent, 3);
	T_EQ_U64(q.pts[0][2].sent, 1);
	rl_lat_history_free(&q);

	/* nothing wanted, nothing listed */
	T_EQ_I64(rl_lat_query(&c, H(0, 0, 0), H(0, 6, 0), 0, 1u << 7, 0, &q), 0);
	T_EQ_I64(q.n_ids, 0);
	rl_lat_history_free(&q);

	T_EQ_I64(rl_lat_query(&c, 100, 100, 0, ~0ULL, 0, &q), -1);
	T_EQ_I64(rl_lat_query(&c, 100, 200, 1001, ~0ULL, 0, &q), -1);
	T_EQ_I64(rl_lat_query(&c, 100, 200, -1, ~0ULL, 0, &q), -1);
	T_EQ_I64(rl_lat_query(&c, 0, RL_LATQ_MAX_RANGE + 1, 0, ~0ULL, 0, &q), -1);
	/* end - start would overflow into a short range (a crash once: billions of points) */
	T_EQ_I64(rl_lat_query(&c, INT64_MIN + 3600, H(0, 0, 0), 0, ~0ULL, ~0ULL, &q), -1);

	/* older than the minute retention: hours, here only the open one (id 2 counts in the hour it was reused) */
	c.now = H(0, 5, 30) + 8 * 86400;
	T_EQ_I64(rl_lat_query(&c, H(0, 0, 0), H(2, 0, 0), 0, ~0ULL, 0, &q), 0);
	T_EQ_I64(q.tier, RL_TIER_HOUR);
	T_EQ_I64(q.n, 2);
	T_EQ_I64(q.n_ids, 2);
	T_EQ_U64(q.pts[0][0].sent, 4);
	T_EQ_U64(q.pts[1][0].sent, 2);
	T_EQ_U64(q.pts[1][1].sent, 0);
	rl_lat_history_free(&q);
	rl_series_close(m);
	unlink(path);
	rmdir(dir);
}

static void put_outage(rl_series *s, int64_t start, int64_t end, rl_outage_cause cause)
{
	uint8_t rec[RL_SERIES_REC_SIZE];
	rl_outage_encode(rec, start, end, cause);
	T_EQ_I64(rl_series_append(s, rec), 0);
}

/* Outages in a range: overlap, clipping, the ongoing one, availability over the probed time only. */
static void test_outages(void)
{
	fresh_dir();
	rl_series *m = open_series("latency.minute", RL_LAT_KIND_MINUTE);
	rl_series *o = open_series("outages", RL_OUTAGE_KIND);
	reset_recs(m, NULL);
	rl_lat_targets t;
	rl_lat_targets_init(&t);
	bool changed;
	rl_ip a = ip("223.5.5.5"), g = ip("100.64.0.1");
	rl_lat_targets_gateway(&t, &g);
	rl_lat_targets_assign(&t, &a, 0, 0, &changed);

	/* probed from 1:00 to 1:59 (custom target), the gateway alone from 0:00 */
	rl_lat l;
	rl_lat_init(&l, on_rec, NULL);
	for (int64_t ts = H(0, 0, 0); ts < H(2, 0, 0); ts += RL_LAT_INTERVAL) {
		rl_lat_add(&l, ts, 0, true, 500);
		if (ts >= H(1, 0, 0))
			rl_lat_add(&l, ts, 1, ts < H(1, 30, 0) || ts >= H(1, 33, 20), 9000);
	}
	rl_lat_tick(&l, H(2, 0, 0));
	put_outage(o, H(0, 50, 0), H(1, 0, 40), RL_CAUSE_REDIAL);
	put_outage(o, H(1, 30, 0), H(1, 33, 20), RL_CAUSE_UPSTREAM);

	rl_latq_ctx c = { .minute = m, .outages = o, .open = &l, .targets = &t, .now = H(2, 30, 0), .minute_days = 7 };
	rl_outage_list r;
	T_EQ_I64(rl_outage_query(&c, NULL, INT64_MIN + 3600, H(0, 0, 0), &r), -1);
	T_EQ_I64(rl_outage_query(&c, NULL, H(1, 0, 0), H(2, 0, 0), &r), 0);
	T_EQ_U64(r.count, 2);
	T_EQ_I64(r.total_sec, 40 + 200);
	T_EQ_I64(r.probed_sec, 3600);
	T_EQ_I64(r.n, 2);
	T_EQ_I64(r.items[0].start, H(1, 30, 0)); /* newest first */
	T_EQ_I64(r.items[0].cause, RL_CAUSE_UPSTREAM);
	T_EQ_I64(r.items[1].end, H(1, 0, 40)); /* not clipped */
	T_ASSERT(r.items[1].cause == RL_CAUSE_REDIAL && !r.items[1].ongoing);
	/* (3600 - 240) / 3600 = 93.333 % */
	T_EQ_I64((int64_t)(rl_outage_availability(&r) * 100 + 0.5), 9333);
	rl_outage_list_free(&r);

	/* only the gateway was probed: no availability */
	T_EQ_I64(rl_outage_query(&c, NULL, H(0, 0, 0), H(0, 40, 0), &r), 0);
	T_EQ_U64(r.count, 0);
	T_EQ_I64(r.probed_sec, 0);
	T_ASSERT(rl_outage_availability(&r) < 0);
	rl_outage_list_free(&r);

	/* an ongoing outage ends now; the range end is clipped to now */
	rl_outage st = { .down = true, .start = H(2, 20, 0), .wan_down_at = H(2, 19, 55) };
	for (int64_t ts = H(2, 0, 0); ts < H(2, 30, 0); ts += RL_LAT_INTERVAL)
		rl_lat_add(&l, ts, 1, ts < H(2, 20, 0), 9000);
	T_EQ_I64(rl_outage_query(&c, &st, H(2, 0, 0), H(3, 0, 0), &r), 0);
	T_EQ_U64(r.count, 1);
	T_ASSERT(r.items[0].ongoing);
	T_EQ_I64(r.items[0].end, H(2, 30, 0));
	T_EQ_I64(r.items[0].cause, RL_CAUSE_WAN_DOWN);
	T_EQ_I64(r.total_sec, 600);
	T_EQ_I64(r.probed_sec, 1800);
	T_EQ_I64((int64_t)(rl_outage_availability(&r) * 100 + 0.5), 6667);
	rl_outage_list_free(&r);

	T_EQ_I64(rl_outage_query(&c, NULL, 10, 10, &r), -1);
	rl_series_close(m);
	rl_series_close(o);
	unlink(path);
	snprintf(path, sizeof(path), "%s/latency.minute", dir);
	unlink(path);
	rmdir(dir);
}

int main(void)
{
	T_RUN(test_targets);
	T_RUN(test_buckets);
	T_RUN(test_recover);
	T_RUN(test_query);
	T_RUN(test_outages);
	T_DONE();
}
