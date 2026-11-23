#include <stdlib.h>
#include <unistd.h>

#include "t.h"

#include "core/util.h"
#include "core/wifi.h"

/* 2025-10-15 00:00:00 UTC */
static const int64_t DAY0 = 1760486400;
#define H(h, m, s) (DAY0 + (h) * 3600 + (m) * 60 + (s))

#define MAXREC 256
#define MAXEV 32

static struct {
	rl_tier tier[MAXREC];
	rl_sig_rec rec[MAXREC];
	int n;
} recs;

static struct {
	uint8_t last[MAXEV]; /* last MAC byte */
	bool connected[MAXEV];
	uint32_t freq[MAXEV];
	int n;
} evs;

static void on_rec(rl_tier tier, const uint8_t raw[RL_SERIES_REC_SIZE], void *ctx)
{
	(void)ctx;
	if (recs.n < MAXREC) {
		recs.tier[recs.n] = tier;
		rl_sig_decode(raw, &recs.rec[recs.n++]);
	}
}

static void on_assoc(const rl_wifi_sta *st, bool connected, void *ctx)
{
	(void)ctx;
	if (evs.n < MAXEV) {
		evs.last[evs.n] = st->mac.b[5];
		evs.connected[evs.n] = connected;
		evs.freq[evs.n++] = st->freq;
	}
}

static rl_wifi *fresh(void)
{
	rl_tz_apply("UTC0");
	memset(&recs, 0, sizeof(recs));
	memset(&evs, 0, sizeof(evs));
	return rl_wifi_new(on_rec, on_assoc, NULL);
}

static rl_sta_sample sta(uint8_t last, int ifindex, int8_t signal)
{
	rl_sta_sample s = { .mac = { { 0x02, 0x11, 0x22, 0x33, 0x44, last } }, .ifindex = ifindex };
	s.has = RL_STA_SIGNAL | RL_STA_INACTIVE;
	s.signal = signal;
	s.inactive_ms = 100;
	return s;
}

static rl_sta_sample sta_rates(uint8_t last, int8_t signal, uint32_t tx, uint32_t rx, uint32_t retries, uint32_t failed)
{
	rl_sta_sample s = sta(last, 1, signal);
	s.has |= RL_STA_TX_RATE | RL_STA_RX_RATE | RL_STA_RETRIES | RL_STA_FAILED;
	s.tx_rate = tx;
	s.rx_rate = rx;
	s.tx_retries = retries;
	s.tx_failed = failed;
	return s;
}

/* One complete dump at now with the given samples (ifindex 1 = 2.4 GHz, 2 = 5 GHz). */
static void dump(rl_wifi *w, int64_t now, const rl_sta_sample *s, int n)
{
	rl_wifi_tick(w, now);
	rl_wifi_begin(w);
	for (int i = 0; i < n; i++)
		rl_wifi_update(w, &s[i], s[i].mac.b[5], s[i].ifindex == 2 ? "phy1-ap0" : "phy0-ap0",
			       s[i].ifindex == 2 ? 5180 : 2437, now);
	rl_wifi_end(w, now, true);
}

static const rl_sig_rec *find_rec(rl_tier t, int64_t ts, uint16_t dev)
{
	for (int i = 0; i < recs.n; i++)
		if (recs.tier[i] == t && recs.rec[i].ts == ts && recs.rec[i].dev == dev)
			return &recs.rec[i];
	return NULL;
}

static int count_tier(rl_tier t)
{
	int n = 0;
	for (int i = 0; i < recs.n; i++)
		n += recs.tier[i] == t;
	return n;
}

static void test_encode(void)
{
	rl_sig_rec a, b;
	memset(&a, 0, sizeof(a)); /* padding too: compared with memcmp */
	memset(&b, 0, sizeof(b));
	a.ts = H(1, 2, 0);
	a.dev = 513;
	a.flags = RL_SIG_F_SIGNAL | RL_SIG_F_COUNTERS;
	a.avg_signal = -61;
	a.min_signal = -75;
	a.max_signal = -40;
	a.samples = 61;
	a.rate_samples = 60;
	a.avg_tx_rate = 866700;
	a.avg_rx_rate = 6500;
	a.tx_retries = 4000000000u;
	a.tx_failed = 7;
	a.freq = 5180;
	uint8_t raw[RL_SERIES_REC_SIZE];
	rl_sig_encode(&a, raw);
	T_EQ_I64(rl_series_ts(raw), H(1, 2, 0));
	rl_sig_decode(raw, &b);
	T_ASSERT(memcmp(&a, &b, sizeof(a)) == 0);
}

static void test_channel(void)
{
	T_EQ_I64(rl_wifi_channel(2412), 1);
	T_EQ_I64(rl_wifi_channel(2437), 6);
	T_EQ_I64(rl_wifi_channel(2484), 14);
	T_EQ_I64(rl_wifi_channel(5180), 36);
	T_EQ_I64(rl_wifi_channel(5825), 165);
	T_EQ_I64(rl_wifi_channel(5955), 1);
	T_EQ_I64(rl_wifi_channel(5935), 2);
	T_EQ_I64(rl_wifi_channel(6415), 93);
	T_EQ_I64(rl_wifi_channel(58320), 1);
	T_EQ_I64(rl_wifi_channel(0), 0);
	T_EQ_I64(rl_wifi_channel(900), 0);
	T_EQ_STR(rl_wifi_mode_name(RL_WIFI_MODE_HE), "he");
	T_EQ_STR(rl_wifi_mode_name(RL_WIFI_MODE_LEGACY), "legacy");
}

static void test_baseline_and_events(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample a = sta(1, 1, -50), b = sta(2, 2, -60), both[] = { a, b };

	dump(w, H(0, 0, 0), &a, 1); /* baseline: a was there before the daemon started */
	T_EQ_I64(evs.n, 0);
	T_ASSERT(rl_wifi_find(w, &a.mac)->associated);

	dump(w, H(0, 0, 10), both, 2);
	T_EQ_I64(evs.n, 1);
	T_EQ_I64(evs.last[0], 2);
	T_ASSERT(evs.connected[0]);
	T_EQ_I64(evs.freq[0], 5180);
	T_EQ_I64(rl_wifi_count_on(w, 1), 1);
	T_EQ_I64(rl_wifi_count_on(w, 2), 1);

	/* an incomplete dump (one interface failed) does not make anybody leave */
	rl_wifi_tick(w, H(0, 0, 20));
	rl_wifi_begin(w);
	rl_wifi_update(w, &b, 2, "phy1-ap0", 5180, H(0, 0, 20));
	rl_wifi_end(w, H(0, 0, 20), false);
	T_EQ_I64(evs.n, 1);
	T_ASSERT(rl_wifi_find(w, &a.mac)->associated);

	dump(w, H(0, 0, 30), &b, 1);
	T_EQ_I64(evs.n, 2);
	T_EQ_I64(evs.last[1], 1);
	T_ASSERT(!evs.connected[1]);
	T_EQ_I64(evs.freq[1], 2437);
	T_ASSERT(!rl_wifi_find(w, &a.mac)->associated);
	T_EQ_I64(rl_wifi_find(w, &a.mac)->changed, H(0, 0, 30));

	/* a comes back */
	dump(w, H(0, 0, 40), both, 2);
	T_EQ_I64(evs.n, 3);
	T_ASSERT(evs.connected[2]);
	rl_wifi_free(w);
}

static void test_unauthorized(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample a = sta(1, 1, -50);
	dump(w, H(0, 0, 0), NULL, 0);
	a.has |= RL_STA_FLAGS;
	a.authorized = false; /* still in the WPA handshake (or a wrong password) */
	dump(w, H(0, 0, 10), &a, 1);
	T_EQ_I64(evs.n, 0);
	T_ASSERT(!rl_wifi_find(w, &a.mac) || !rl_wifi_find(w, &a.mac)->associated);
	a.authorized = true;
	dump(w, H(0, 0, 20), &a, 1);
	T_EQ_I64(evs.n, 1);
	T_ASSERT(evs.connected[0]);
	rl_wifi_free(w);
}

static void test_band_change(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample a = sta(1, 1, -50);
	dump(w, H(0, 0, 0), &a, 1);
	a.ifindex = 2; /* band steering moved it to 5 GHz */
	dump(w, H(0, 0, 10), &a, 1);
	T_EQ_I64(evs.n, 2);
	T_ASSERT(!evs.connected[0]);
	T_EQ_I64(evs.freq[0], 2437);
	T_ASSERT(evs.connected[1]);
	T_EQ_I64(evs.freq[1], 5180);
	T_EQ_STR(rl_wifi_find(w, &a.mac)->ifname, "phy1-ap0");

	/* the late DEL_STATION from the old interface is ignored */
	rl_wifi_disassoc(w, &a.mac, 1, H(0, 0, 12));
	T_EQ_I64(evs.n, 2);
	rl_wifi_disassoc(w, &a.mac, 2, H(0, 0, 14));
	T_EQ_I64(evs.n, 3);
	T_ASSERT(!evs.connected[2]);
	T_EQ_I64(evs.freq[2], 5180);
	/* already gone: no second event */
	rl_wifi_disassoc(w, &a.mac, 2, H(0, 0, 15));
	dump(w, H(0, 0, 20), NULL, 0);
	T_EQ_I64(evs.n, 3);
	rl_wifi_free(w);
}

static void test_minute_aggregation(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample s;
	s = sta_rates(1, -50, 100000, 50000, 1000, 10);
	dump(w, H(0, 0, 0), &s, 1);
	s = sta_rates(1, -60, 200000, 70000, 1010, 12);
	dump(w, H(0, 0, 20), &s, 1);
	s = sta_rates(1, -70, 300000, 90000, 1015, 12);
	dump(w, H(0, 0, 40), &s, 1);
	T_EQ_I64(recs.n, 0);

	/* counters went back (station reconnected between two dumps): that step counts 0 */
	s = sta_rates(1, -55, 100000, 60000, 3, 1);
	dump(w, H(0, 1, 0), &s, 1);
	const rl_sig_rec *m = find_rec(RL_TIER_MINUTE, H(0, 0, 0), 1);
	T_ASSERT(m != NULL);
	if (m) {
		T_EQ_I64(m->avg_signal, -60);
		T_EQ_I64(m->min_signal, -70);
		T_EQ_I64(m->max_signal, -50);
		T_EQ_I64(m->samples, 3);
		T_EQ_I64(m->rate_samples, 3);
		T_EQ_I64(m->avg_tx_rate, 200000);
		T_EQ_I64(m->avg_rx_rate, 70000);
		T_EQ_I64(m->tx_retries, 15); /* first sample is the baseline */
		T_EQ_I64(m->tx_failed, 2);
		T_EQ_I64(m->freq, 2437);
		T_EQ_I64(m->flags, RL_SIG_F_SIGNAL | RL_SIG_F_TX_RATE | RL_SIG_F_RX_RATE | RL_SIG_F_COUNTERS);
	}
	s = sta_rates(1, -55, 100000, 60000, 5, 1);
	dump(w, H(0, 1, 30), &s, 1);
	dump(w, H(0, 2, 0), &s, 1);
	m = find_rec(RL_TIER_MINUTE, H(0, 1, 0), 1);
	T_ASSERT(m != NULL);
	if (m) {
		T_EQ_I64(m->tx_retries, 2); /* 1015 -> 3 counted 0, then 3 -> 5 */
		T_EQ_I64(m->tx_failed, 0);
	}

	/* signal only: no rate or counter flags */
	rl_wifi_free(w);
	w = fresh();
	s = sta(4, 1, -80);
	dump(w, H(0, 0, 0), &s, 1);
	dump(w, H(0, 1, 0), NULL, 0);
	m = find_rec(RL_TIER_MINUTE, H(0, 0, 0), 4);
	T_ASSERT(m && m->flags == RL_SIG_F_SIGNAL);
	rl_wifi_free(w);
}

static void test_hour_and_order(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample s[2] = { sta(1, 1, -50), sta(2, 2, -70) };
	for (int64_t t = H(0, 58, 0); t < H(0, 59, 0); t += 10)
		dump(w, t, s, 2);
	/* b leaves at 00:59:00; its hour stays open until the hour ends */
	for (int64_t t = H(0, 59, 0); t < H(1, 0, 30); t += 10)
		dump(w, t, s, 1);
	T_EQ_I64(count_tier(RL_TIER_HOUR), 2);
	T_EQ_I64(count_tier(RL_TIER_MINUTE), 3); /* 00:58 a+b, 00:59 a, 01:00 still open */
	const rl_sig_rec *ha = find_rec(RL_TIER_HOUR, H(0, 0, 0), 1), *hb = find_rec(RL_TIER_HOUR, H(0, 0, 0), 2);
	T_ASSERT(ha && hb);
	if (ha && hb) {
		T_EQ_I64(ha->samples, 12);
		T_EQ_I64(hb->samples, 6);
		T_EQ_I64(hb->avg_signal, -70);
	}
	/* records leave in ts order */
	for (int i = 1; i < recs.n; i++)
		if (recs.tier[i] == recs.tier[i - 1])
			T_ASSERT(recs.rec[i].ts >= recs.rec[i - 1].ts);

	/* a gap: buckets close on the next tick even without samples */
	recs.n = 0;
	rl_wifi_tick(w, H(3, 0, 0));
	T_EQ_I64(count_tier(RL_TIER_MINUTE), 1);
	T_EQ_I64(count_tier(RL_TIER_HOUR), 1);
	T_ASSERT(find_rec(RL_TIER_HOUR, H(1, 0, 0), 1) != NULL);
	rl_wifi_free(w);
}

static void test_flush(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample s = sta(1, 1, -50);
	dump(w, H(0, 0, 0), &s, 1);
	dump(w, H(0, 0, 10), &s, 1);
	rl_wifi_flush(w, false);
	T_EQ_I64(recs.n, 1);
	T_EQ_I64(recs.tier[0], RL_TIER_MINUTE);
	T_EQ_I64(recs.rec[0].samples, 2);
	rl_wifi_flush(w, false); /* nothing new */
	T_EQ_I64(recs.n, 1);
	s.signal = -60;
	dump(w, H(0, 0, 20), &s, 1);
	dump(w, H(0, 1, 0), NULL, 0);
	T_EQ_I64(count_tier(RL_TIER_MINUTE), 2);
	T_EQ_I64(recs.rec[1].ts, H(0, 0, 0));
	T_EQ_I64(recs.rec[1].samples, 1);
	/* the hour bucket was not touched by the minute flush */
	rl_wifi_flush(w, true);
	const rl_sig_rec *h = find_rec(RL_TIER_HOUR, H(0, 0, 0), 1);
	T_ASSERT(h && h->samples == 3);
	rl_wifi_free(w);
}

static void test_ring(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample s;
	for (int i = 0; i < RL_WIFI_RING + 20; i++) {
		s = sta_rates(1, (int8_t)(-40 - i % 30), 1000, 2000, (uint32_t)(i * 2), 0);
		dump(w, H(0, 0, 0) + i, &s, 1);
	}
	rl_wifi_sta *st = rl_wifi_find(w, &s.mac);
	rl_live_pt pts[RL_WIFI_RING + 5];
	size_t n = rl_wifi_live(st, 0, INT64_MAX, pts, RL_ARRAY_SIZE(pts));
	T_EQ_I64(n, RL_WIFI_RING);
	T_EQ_I64(pts[0].ts, H(0, 0, 20));
	T_EQ_I64(pts[n - 1].ts, H(0, 0, RL_WIFI_RING + 19));
	T_EQ_I64(pts[1].retries, 2);
	T_EQ_I64(pts[1].flags, RL_SIG_F_SIGNAL | RL_SIG_F_TX_RATE | RL_SIG_F_RX_RATE | RL_SIG_F_COUNTERS);
	n = rl_wifi_live(st, H(0, 0, 100), H(0, 0, 110), pts, RL_ARRAY_SIZE(pts));
	T_EQ_I64(n, 10);
	T_EQ_I64(pts[0].ts, H(0, 0, 100));
	n = rl_wifi_live(st, 0, INT64_MAX, pts, 5);
	T_EQ_I64(n, 5);
	T_EQ_I64(pts[4].ts, H(0, 0, RL_WIFI_RING + 19)); /* the newest ones */
	rl_wifi_free(w);
}

static void test_forget(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample s = sta(1, 1, -50);
	dump(w, H(0, 0, 0), &s, 1);
	dump(w, H(0, 0, 10), NULL, 0);
	T_EQ_I64(rl_wifi_count(w), 1);
	rl_wifi_tick(w, H(0, 0, 10) + RL_WIFI_FORGET);
	T_EQ_I64(rl_wifi_count(w), 1); /* its hour is still open */
	rl_wifi_tick(w, H(1, 0, 0));
	T_EQ_I64(rl_wifi_count(w), 0);
	T_ASSERT(find_rec(RL_TIER_HOUR, H(0, 0, 0), 1) != NULL);

	/* clear: baseline again, nothing emitted */
	dump(w, H(1, 0, 10), &s, 1);
	int before = evs.n;
	rl_wifi_clear(w);
	T_EQ_I64(rl_wifi_count(w), 0);
	dump(w, H(1, 0, 20), &s, 1);
	T_EQ_I64(evs.n, before);
	rl_wifi_free(w);
}

static void test_reset_data(void)
{
	rl_wifi *w = fresh();
	rl_sta_sample s = sta(1, 1, -50);
	dump(w, H(0, 0, 0), &s, 1);
	rl_wifi_reset_data(w);
	rl_wifi_sta *st = rl_wifi_find(w, &s.mac);
	rl_live_pt pts[4];
	rl_sig_rec r;
	T_ASSERT(st && st->associated);
	T_EQ_I64(rl_wifi_live(st, 0, INT64_MAX, pts, 4), 0);
	T_ASSERT(!rl_wifi_open_rec(st, RL_TIER_MINUTE, &r));
	dump(w, H(0, 2, 0), &s, 1);
	T_EQ_I64(recs.n, 0);
	T_EQ_I64(evs.n, 0);
	rl_wifi_free(w);
}

/* ---- queries ---- */

static char dir[64], pm[128], ph[128];

static void open_series(rl_series **minute, rl_series **hour)
{
	snprintf(dir, sizeof(dir), "/tmp/rl-wifi-XXXXXX");
	if (!mkdtemp(dir))
		abort();
	snprintf(pm, sizeof(pm), "%s/signal.minute", dir);
	snprintf(ph, sizeof(ph), "%s/signal.hour", dir);
	*minute = rl_series_open(pm, RL_SIG_KIND_MINUTE, NULL);
	*hour = rl_series_open(ph, RL_SIG_KIND_HOUR, NULL);
}

static void put(rl_series *s, int64_t ts, uint16_t dev, int8_t sig, uint16_t samples)
{
	rl_sig_rec r = { .ts = ts, .dev = dev, .flags = RL_SIG_F_SIGNAL | RL_SIG_F_TX_RATE, .avg_signal = sig,
			 .min_signal = (int8_t)(sig - 5), .max_signal = (int8_t)(sig + 5), .samples = samples,
			 .rate_samples = samples, .avg_tx_rate = 1000, .freq = 2437 };
	uint8_t raw[RL_SERIES_REC_SIZE];
	rl_sig_encode(&r, raw);
	rl_series_append(s, raw);
}

static void test_query_minute(void)
{
	rl_series *mi, *ho;
	open_series(&mi, &ho);
	put(mi, H(0, 0, 0), 3, -60, 6);
	put(mi, H(0, 0, 0), 4, -40, 6); /* another device */
	put(mi, H(0, 2, 0), 3, -70, 6);
	put(mi, H(0, 2, 0), 3, -50, 2); /* second (partial) record of the same minute */
	rl_sigq_ctx c = { .minute = mi, .hour = ho, .now = H(0, 5, 0), .minute_days = 7, .hour_days = 30,
			  .live_step = 10 };
	rl_sig_history h;
	T_EQ_I64(rl_sig_query(&c, 3, H(0, 0, 0), H(0, 4, 0), 0, &h), 0);
	T_EQ_I64(h.tier, RL_SIGQ_MINUTE);
	T_EQ_I64(h.step, 60);
	T_EQ_I64(h.n, 4);
	T_EQ_I64(h.pts[0].ts, H(0, 0, 0));
	T_EQ_I64(h.pts[0].avg_signal, -60);
	T_EQ_I64(h.pts[0].min_signal, -65);
	T_EQ_I64(h.pts[1].flags, 0); /* gap */
	T_EQ_I64(h.pts[2].avg_signal, -65); /* (6 * -70 + 2 * -50) / 8 */
	T_EQ_I64(h.pts[2].min_signal, -75);
	T_EQ_I64(h.pts[2].avg_tx_rate, 1000);
	T_ASSERT(!(h.pts[2].flags & RL_SIG_F_COUNTERS));
	rl_sig_history_free(&h);

	/* max_points merges buckets */
	T_EQ_I64(rl_sig_query(&c, 3, H(0, 0, 0), H(0, 4, 0), 2, &h), 0);
	T_EQ_I64(h.n, 2);
	T_EQ_I64(h.step, 120);
	T_EQ_I64(h.pts[0].avg_signal, -60);
	T_EQ_I64(h.pts[1].avg_signal, -65);
	rl_sig_history_free(&h);

	/* older than the minute retention: hours */
	put(ho, H(0, 0, 0) - 40 * 86400, 3, -66, 300);
	c.now = H(0, 5, 0);
	T_EQ_I64(rl_sig_query(&c, 3, H(0, 0, 0) - 40 * 86400, H(0, 0, 0) - 39 * 86400, 0, &h), 0);
	T_EQ_I64(h.tier, RL_SIGQ_HOUR);
	T_EQ_I64(h.step, 3600);
	T_EQ_I64(h.n, 24);
	T_EQ_I64(h.pts[0].avg_signal, -66);
	T_EQ_I64(h.pts[1].flags, 0);
	rl_sig_history_free(&h);

	/* invalid arguments */
	T_EQ_I64(rl_sig_query(&c, 3, H(0, 4, 0), H(0, 4, 0), 0, &h), -1);
	T_EQ_I64(rl_sig_query(&c, 3, 0, H(0, 4, 0), 0, &h), -1);
	T_EQ_I64(rl_sig_query(&c, 3, INT64_MIN + 3600, H(0, 4, 0), 0, &h), -1); /* end - start overflows */
	T_EQ_I64(rl_sig_query(&c, 3, H(0, 0, 0), H(0, 4, 0), RL_SIGQ_MAX_POINTS + 1, &h), -1);
	rl_series_close(mi);
	rl_series_close(ho);
}

static void test_query_open_and_live(void)
{
	rl_series *mi, *ho;
	open_series(&mi, &ho);
	rl_wifi *w = rl_wifi_new(NULL, NULL, NULL);
	rl_tz_apply("UTC0");
	rl_sta_sample s = sta_rates(9, -50, 1000, 500, 0, 0);
	for (int64_t t = H(0, 0, 0); t <= H(0, 3, 30); t += 10) {
		s.signal = t < H(0, 3, 0) ? -50 : -70;
		rl_wifi_tick(w, t);
		rl_wifi_begin(w);
		rl_wifi_update(w, &s, 9, "phy0-ap0", 2437, t);
		rl_wifi_end(w, t, true);
	}
	rl_sigq_ctx c = { .minute = mi, .hour = ho, .wifi = w, .now = H(0, 3, 35), .minute_days = 7, .hour_days = 30,
			  .live_step = 10 };
	rl_sig_history h;

	/* recent start: the ring */
	T_EQ_I64(rl_sig_query(&c, 9, H(0, 2, 0), H(0, 4, 0), 0, &h), 0);
	T_EQ_I64(h.tier, RL_SIGQ_LIVE);
	T_EQ_I64(h.step, 10);
	T_EQ_I64(h.n, 10); /* 02:00 .. 03:30 */
	T_EQ_I64(h.pts[0].ts, H(0, 2, 0));
	T_EQ_I64(h.pts[9].avg_signal, -70);
	T_EQ_I64(h.pts[9].avg_rx_rate, 500);
	rl_sig_history_free(&h);
	T_EQ_I64(rl_sig_query(&c, 9, H(0, 2, 0), H(0, 4, 0), 4, &h), 0);
	T_EQ_I64(h.n, 4);
	T_EQ_I64(h.pts[3].avg_signal, -70);
	T_EQ_I64(h.pts[0].ts, H(0, 2, 0));
	rl_sig_history_free(&h);

	/* minutes: no records written (no on_rec), but the open minute and hour count */
	c.now = H(0, 3, 35) + RL_WIFI_LIVE_RANGE;
	T_EQ_I64(rl_sig_query(&c, 9, H(0, 0, 0), H(0, 4, 0), 0, &h), 0);
	T_EQ_I64(h.tier, RL_SIGQ_MINUTE);
	T_EQ_I64(h.n, 4);
	T_EQ_I64(h.pts[0].flags, 0); /* closed without a callback: lost */
	T_EQ_I64(h.pts[3].avg_signal, -70);
	rl_sig_history_free(&h);
	c.now = H(0, 3, 35) + 40 * 86400;
	T_EQ_I64(rl_sig_query(&c, 9, H(0, 0, 0), H(1, 0, 0), 0, &h), 0);
	T_EQ_I64(h.tier, RL_SIGQ_HOUR);
	T_EQ_I64(h.n, 1);
	T_EQ_I64(h.pts[0].avg_signal, -54); /* 18 x -50, 4 x -70: -53.6 */
	rl_sig_history_free(&h);

	rl_wifi_free(w);
	rl_series_close(mi);
	rl_series_close(ho);
}

/* ---- recovery ---- */

static bool mac_of(uint16_t dev, rl_mac *out, void *ctx)
{
	(void)ctx;
	if (dev == 99)
		return false;
	*out = (rl_mac){ { 0x02, 0, 0, 0, 0, (uint8_t)dev } };
	return true;
}

typedef struct {
	int n;
	rl_sig_rec r[16];
} hour_list;

static bool collect(const uint8_t *raw, void *x)
{
	hour_list *l = x;
	if (l->n < 16)
		rl_sig_decode(raw, &l->r[l->n++]);
	return true;
}

static void test_recover(void)
{
	rl_series *mi, *ho;
	open_series(&mi, &ho);
	rl_wifi *w = fresh();
	put(ho, H(0, 0, 0), 5, -50, 360);
	for (int64_t t = H(0, 50, 0); t < H(1, 0, 0); t += 60)
		put(mi, t, 5, -50, 6); /* covered by the hour record */
	for (int64_t t = H(1, 0, 0); t < H(1, 30, 0); t += 60) {
		put(mi, t, 5, -60, 6);
		if (t == H(1, 10, 0))
			put(mi, t, 6, -80, 6);
	}
	for (int64_t t = H(3, 0, 0); t < H(3, 10, 0); t += 60) {
		put(mi, t, 5, -70, 6);
		put(mi, t, 99, -70, 6); /* not in the device table */
	}
	T_EQ_I64(rl_wifi_recover(w, mi, ho, H(3, 15, 0), mac_of, NULL), 2);
	hour_list l = { 0 };
	rl_series_scan(ho, 0, INT64_MAX, collect, &l);
	T_EQ_I64(l.n, 3);
	T_EQ_I64(l.r[1].ts, H(1, 0, 0));
	T_EQ_I64(l.r[1].dev, 5);
	T_EQ_I64(l.r[1].samples, 180);
	T_EQ_I64(l.r[1].avg_signal, -60);
	T_EQ_I64(l.r[2].ts, H(1, 0, 0));
	T_EQ_I64(l.r[2].dev, 6);

	/* the open hour came back: 10 minutes at -70, then samples at -50 */
	rl_mac m5 = { { 0x02, 0, 0, 0, 0, 5 } };
	rl_wifi_sta *st = rl_wifi_find(w, &m5);
	T_ASSERT(st && !st->associated && st->dev == 5);
	rl_sta_sample s = sta(0, 1, -50);
	s.mac = m5;
	for (int64_t t = H(3, 15, 0); t < H(3, 25, 0); t += 10) {
		rl_wifi_tick(w, t);
		rl_wifi_begin(w);
		rl_wifi_update(w, &s, 5, "phy0-ap0", 2437, t);
		rl_wifi_end(w, t, true);
	}
	T_EQ_I64(evs.n, 0); /* the first dump after a restart is a baseline */
	rl_wifi_tick(w, H(4, 0, 0));
	const rl_sig_rec *h = find_rec(RL_TIER_HOUR, H(3, 0, 0), 5);
	T_ASSERT(h != NULL);
	if (h) {
		T_EQ_I64(h->samples, 120);
		T_EQ_I64(h->avg_signal, -60);
	}
	T_ASSERT(find_rec(RL_TIER_HOUR, H(3, 0, 0), 99) == NULL);

	/* nothing to do the second time */
	rl_wifi_free(w);
	w = fresh();
	T_EQ_I64(rl_wifi_recover(w, mi, ho, H(3, 16, 0), mac_of, NULL), 0);
	rl_wifi_free(w);
	rl_series_close(mi);
	rl_series_close(ho);
}

/* ---- survey ---- */

static rl_survey_sample sv(uint32_t wiphy, uint32_t freq, bool in_use, uint64_t active, uint64_t busy)
{
	return (rl_survey_sample){ .wiphy = wiphy, .freq = freq, .in_use = in_use, .noise = -92, .active_ms = active,
				   .busy_ms = busy, .has = RL_SV_NOISE | RL_SV_ACTIVE | RL_SV_BUSY };
}

static void survey(rl_wifi *w, uint32_t wiphy, const rl_survey_sample *s, int n, int64_t now)
{
	rl_wifi_survey_begin(w, wiphy);
	for (int i = 0; i < n; i++)
		rl_wifi_survey_add(w, &s[i], now);
	rl_wifi_survey_end(w, wiphy);
}

static void test_survey(void)
{
	rl_wifi *w = fresh();
	rl_survey_sample a[] = { sv(0, 2412, true, 10000, 2000), sv(0, 2437, false, 200, 100) };
	survey(w, 0, a, 2, 100);
	T_EQ_I64(rl_wifi_survey_count(w), 2);
	const rl_survey_entry *r = rl_wifi_survey_radio(w, 0, 2412);
	T_ASSERT(r && r->busy_pct == -1 && r->busy_pct_total == 20);

	rl_survey_sample b[] = { sv(0, 2412, true, 70000, 32000), sv(0, 2437, false, 200, 100) };
	survey(w, 0, b, 2, 160);
	r = rl_wifi_survey_radio(w, 0, 2412);
	T_ASSERT(r && r->busy_pct == 50 && r->updated == 160);
	const rl_survey_entry *o = rl_wifi_survey_radio(w, 0, 2437); /* found by freq */
	T_ASSERT(o && o->busy_pct == -1 && o->busy_pct_total == 50);

	/* counters reset (channel change on some drivers) */
	rl_survey_sample c[] = { sv(0, 2412, true, 5000, 4000) };
	survey(w, 0, c, 1, 220);
	r = rl_wifi_survey_radio(w, 0, 2412);
	T_ASSERT(r && r->busy_pct == -1);
	T_EQ_I64(rl_wifi_survey_count(w), 1); /* 2437 was not reported this time */

	/* no in-use flag (mac80211_hwsim): the radio's frequency decides */
	rl_survey_sample d[] = { sv(1, 5180, false, 1000, 100) };
	survey(w, 1, d, 1, 220);
	T_EQ_I64(rl_wifi_survey_count(w), 2);
	T_ASSERT(rl_wifi_survey_radio(w, 1, 5180) != NULL);
	T_ASSERT(rl_wifi_survey_radio(w, 1, 5200) == NULL);

	uint32_t keep = 1;
	rl_wifi_survey_retain(w, &keep, 1);
	T_EQ_I64(rl_wifi_survey_count(w), 1);
	T_EQ_I64(rl_wifi_survey_at(w, 0)->s.wiphy, 1);

	/* busy above active (driver quirk) is clamped */
	rl_survey_sample e1[] = { sv(1, 5180, true, 1000, 100) }, e2[] = { sv(1, 5180, true, 2000, 1500) };
	survey(w, 1, e1, 1, 300);
	survey(w, 1, e2, 1, 360);
	T_EQ_I64(rl_wifi_survey_radio(w, 1, 5180)->busy_pct, 100);
	rl_wifi_free(w);
}

int main(void)
{
	T_RUN(test_encode);
	T_RUN(test_channel);
	T_RUN(test_baseline_and_events);
	T_RUN(test_unauthorized);
	T_RUN(test_band_change);
	T_RUN(test_minute_aggregation);
	T_RUN(test_hour_and_order);
	T_RUN(test_flush);
	T_RUN(test_ring);
	T_RUN(test_forget);
	T_RUN(test_reset_data);
	T_RUN(test_query_minute);
	T_RUN(test_query_open_and_live);
	T_RUN(test_recover);
	T_RUN(test_survey);
	T_DONE();
}
