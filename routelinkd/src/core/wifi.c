#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "core/util.h"
#include "core/wifi.h"

#define REC RL_SERIES_REC_SIZE
#define T_MIN 0 /* acc[] index */
#define T_HOUR 1

struct rl_wifi {
	rl_sig_rec_cb on_rec;
	rl_wifi_assoc_cb on_assoc;
	void *ctx;
	rl_wifi_sta **stas; /* stable addresses: callers keep pointers between calls */
	size_t n, cap;
	bool baseline; /* the next complete dump raises no connect events */
	rl_survey_entry *sv;
	size_t n_sv, cap_sv;
};

static const rl_tier TIERS[2] = { RL_TIER_MINUTE, RL_TIER_HOUR };

/* Rounded quotient for signed sums (dBm averages are negative). */
static int64_t div_round(int64_t sum, int64_t n)
{
	return sum >= 0 ? (sum + n / 2) / n : -((-sum + n / 2) / n);
}

static uint16_t sat16(uint64_t v)
{
	return v > UINT16_MAX ? UINT16_MAX : (uint16_t)v;
}

static uint32_t sat32(uint64_t v)
{
	return v > UINT32_MAX ? UINT32_MAX : (uint32_t)v;
}

/* ---- records ---- */

void rl_sig_encode(const rl_sig_rec *r, uint8_t out[REC])
{
	memset(out, 0, REC);
	rl_le_put32(out, (uint32_t)r->ts);
	rl_le_put16(out + 4, r->dev);
	out[6] = r->flags;
	out[7] = (uint8_t)r->max_signal;
	out[8] = (uint8_t)r->avg_signal;
	out[9] = (uint8_t)r->min_signal;
	rl_le_put16(out + 10, r->samples);
	rl_le_put32(out + 12, r->avg_tx_rate);
	rl_le_put32(out + 16, r->avg_rx_rate);
	rl_le_put32(out + 20, r->tx_retries);
	rl_le_put32(out + 24, r->tx_failed);
	rl_le_put16(out + 28, r->freq);
	rl_le_put16(out + 30, r->rate_samples);
}

void rl_sig_decode(const uint8_t in[REC], rl_sig_rec *r)
{
	r->ts = rl_series_ts(in);
	r->dev = rl_le_get16(in + 4);
	r->flags = in[6];
	r->max_signal = (int8_t)in[7];
	r->avg_signal = (int8_t)in[8];
	r->min_signal = (int8_t)in[9];
	r->samples = rl_le_get16(in + 10);
	r->avg_tx_rate = rl_le_get32(in + 12);
	r->avg_rx_rate = rl_le_get32(in + 16);
	r->tx_retries = rl_le_get32(in + 20);
	r->tx_failed = rl_le_get32(in + 24);
	r->freq = rl_le_get16(in + 28);
	r->rate_samples = rl_le_get16(in + 30);
}

/* ---- accumulators ---- */

static void acc_signal(rl_sig_acc *a, int8_t min, int8_t max)
{
	if (!(a->flags & RL_SIG_F_SIGNAL)) {
		a->min_signal = min;
		a->max_signal = max;
		a->flags |= RL_SIG_F_SIGNAL;
		return;
	}
	if (min < a->min_signal)
		a->min_signal = min;
	if (max > a->max_signal)
		a->max_signal = max;
}

static void acc_add_sample(rl_sig_acc *a, const rl_sta_sample *s, uint32_t retries, uint32_t failed, uint32_t freq)
{
	if (s->has & RL_STA_SIGNAL) {
		acc_signal(a, s->signal, s->signal);
		a->samples++;
		a->sum_signal += s->signal;
	}
	if (s->has & RL_STA_TX_RATE) {
		a->flags |= RL_SIG_F_TX_RATE;
		a->tx_n++;
		a->sum_tx += s->tx_rate;
	}
	if (s->has & RL_STA_RX_RATE) {
		a->flags |= RL_SIG_F_RX_RATE;
		a->rx_n++;
		a->sum_rx += s->rx_rate;
	}
	if (s->has & (RL_STA_RETRIES | RL_STA_FAILED)) {
		a->flags |= RL_SIG_F_COUNTERS;
		a->retries += retries;
		a->failed += failed;
	}
	a->freq = freq;
}

static void acc_add_rec(rl_sig_acc *a, const rl_sig_rec *r)
{
	if ((r->flags & RL_SIG_F_SIGNAL) && r->samples) {
		acc_signal(a, r->min_signal, r->max_signal);
		a->samples += r->samples;
		a->sum_signal += (int64_t)r->avg_signal * r->samples;
	}
	if ((r->flags & RL_SIG_F_TX_RATE) && r->rate_samples) {
		a->flags |= RL_SIG_F_TX_RATE;
		a->tx_n += r->rate_samples;
		a->sum_tx += (uint64_t)r->avg_tx_rate * r->rate_samples;
	}
	if ((r->flags & RL_SIG_F_RX_RATE) && r->rate_samples) {
		a->flags |= RL_SIG_F_RX_RATE;
		a->rx_n += r->rate_samples;
		a->sum_rx += (uint64_t)r->avg_rx_rate * r->rate_samples;
	}
	if (r->flags & RL_SIG_F_COUNTERS) {
		a->flags |= RL_SIG_F_COUNTERS;
		a->retries += r->tx_retries;
		a->failed += r->tx_failed;
	}
	if (r->freq)
		a->freq = r->freq;
}

/* The accumulator as a record of device dev; false when it holds nothing. */
static bool acc_rec(const rl_sig_acc *a, uint16_t dev, rl_sig_rec *out)
{
	if (!a->start || !a->flags)
		return false;
	memset(out, 0, sizeof(*out));
	out->ts = a->start;
	out->dev = dev;
	out->flags = a->flags;
	if (a->flags & RL_SIG_F_SIGNAL) {
		out->avg_signal = (int8_t)div_round(a->sum_signal, a->samples);
		out->min_signal = a->min_signal;
		out->max_signal = a->max_signal;
		out->samples = sat16(a->samples);
	}
	if (a->tx_n)
		out->avg_tx_rate = sat32((a->sum_tx + a->tx_n / 2) / a->tx_n);
	if (a->rx_n)
		out->avg_rx_rate = sat32((a->sum_rx + a->rx_n / 2) / a->rx_n);
	out->rate_samples = sat16(RL_MAX(a->tx_n, a->rx_n));
	out->tx_retries = sat32(a->retries);
	out->tx_failed = sat32(a->failed);
	out->freq = sat16(a->freq);
	return true;
}

static void acc_open(rl_sig_acc *a, int64_t start)
{
	memset(a, 0, sizeof(*a));
	a->start = start;
}

/* ---- emitting records in ts order ---- */

typedef struct {
	rl_tier tier;
	rl_sig_rec r;
} out_rec;

typedef struct {
	out_rec *items;
	size_t n, cap;
} out_list;

static void out_add(out_list *l, rl_tier tier, const rl_sig_rec *r)
{
	l->items = rl_grow(l->items, &l->cap, l->n + 1, sizeof(out_rec));
	l->items[l->n++] = (out_rec){ tier, *r };
}

static int cmp_out(const void *x, const void *y)
{
	const out_rec *a = x, *b = y;
	if (a->tier != b->tier)
		return a->tier < b->tier ? -1 : 1;
	if (a->r.ts != b->r.ts)
		return a->r.ts < b->r.ts ? -1 : 1;
	return a->r.dev < b->r.dev ? -1 : a->r.dev > b->r.dev;
}

static void out_emit(rl_wifi *w, out_list *l)
{
	if (l->n > 1)
		qsort(l->items, l->n, sizeof(out_rec), cmp_out);
	for (size_t i = 0; i < l->n && w->on_rec; i++) {
		uint8_t raw[REC];
		rl_sig_encode(&l->items[i].r, raw);
		w->on_rec(l->items[i].tier, raw, w->ctx);
	}
	free(l->items);
	*l = (out_list){ 0 };
}

/* ---- stations ---- */

rl_wifi *rl_wifi_new(rl_sig_rec_cb on_rec, rl_wifi_assoc_cb on_assoc, void *ctx)
{
	rl_wifi *w = calloc(1, sizeof(*w));
	if (!w)
		abort();
	w->on_rec = on_rec;
	w->on_assoc = on_assoc;
	w->ctx = ctx;
	w->baseline = true;
	return w;
}

static void sta_free(rl_wifi_sta *st)
{
	free(st->ring);
	free(st);
}

void rl_wifi_clear(rl_wifi *w)
{
	for (size_t i = 0; i < w->n; i++)
		sta_free(w->stas[i]);
	w->n = 0;
	w->baseline = true;
}

void rl_wifi_free(rl_wifi *w)
{
	if (!w)
		return;
	rl_wifi_clear(w);
	free(w->stas);
	free(w->sv);
	free(w);
}

rl_wifi_sta *rl_wifi_find(const rl_wifi *w, const rl_mac *mac)
{
	for (size_t i = 0; i < w->n; i++)
		if (rl_mac_eq(&w->stas[i]->mac, mac))
			return w->stas[i];
	return NULL;
}

rl_wifi_sta *rl_wifi_find_dev(const rl_wifi *w, uint16_t dev)
{
	for (size_t i = 0; i < w->n; i++)
		if (w->stas[i]->dev == dev)
			return w->stas[i];
	return NULL;
}

size_t rl_wifi_count(const rl_wifi *w)
{
	return w->n;
}

rl_wifi_sta *rl_wifi_at(const rl_wifi *w, size_t i)
{
	return i < w->n ? w->stas[i] : NULL;
}

size_t rl_wifi_count_on(const rl_wifi *w, int ifindex)
{
	size_t n = 0;
	for (size_t i = 0; i < w->n; i++)
		n += w->stas[i]->associated && w->stas[i]->ifindex == ifindex;
	return n;
}

static rl_wifi_sta *sta_new(rl_wifi *w, const rl_mac *mac)
{
	rl_wifi_sta *st = calloc(1, sizeof(*st));
	if (!st)
		abort();
	st->mac = *mac;
	w->stas = rl_grow(w->stas, &w->cap, w->n + 1, sizeof(*w->stas));
	w->stas[w->n++] = st;
	return st;
}

static void ring_push(rl_wifi_sta *st, const rl_live_pt *p)
{
	if (!st->ring) {
		st->ring = calloc(RL_WIFI_RING, sizeof(rl_live_pt));
		if (!st->ring)
			abort();
	}
	st->ring[st->ring_head] = *p;
	st->ring_head = (uint16_t)((st->ring_head + 1) % RL_WIFI_RING);
	if (st->ring_n < RL_WIFI_RING)
		st->ring_n++;
}

static void notify(rl_wifi *w, const rl_wifi_sta *st, bool connected)
{
	if (w->on_assoc)
		w->on_assoc(st, connected, w->ctx);
}

/* The open bucket of tier i for now; an older one is emitted first (callers normally tick before). */
static rl_sig_acc *acc_at(rl_wifi *w, rl_wifi_sta *st, int i, int64_t now)
{
	rl_sig_acc *a = &st->acc[i];
	int64_t start = rl_bucket_start(TIERS[i], now);
	if (a->start == start)
		return a;
	rl_sig_rec r;
	if (acc_rec(a, st->dev, &r)) {
		out_list l = { 0 };
		out_add(&l, TIERS[i], &r);
		out_emit(w, &l);
	}
	acc_open(a, start);
	return a;
}

void rl_wifi_begin(rl_wifi *w)
{
	for (size_t i = 0; i < w->n; i++)
		w->stas[i]->seen = false;
}

rl_wifi_sta *rl_wifi_update(rl_wifi *w, const rl_sta_sample *s, uint16_t dev, const char *ifname, uint32_t freq,
			    int64_t now)
{
	if ((s->has & RL_STA_FLAGS) && !s->authorized)
		return NULL;
	rl_wifi_sta *st = rl_wifi_find(w, &s->mac);
	if (!st)
		st = sta_new(w, &s->mac);
	st->dev = dev;
	if (st->associated && st->ifindex != s->ifindex) {
		/* moved to another interface of this router (band steering): left one, joined the other */
		st->associated = false;
		st->changed = now;
		notify(w, st, false);
	}
	st->ifindex = s->ifindex;
	snprintf(st->ifname, sizeof(st->ifname), "%s", ifname ? ifname : "");
	st->freq = freq;
	if (!st->associated) {
		st->associated = true;
		st->changed = now;
		st->have_prev = false; /* a new association starts its counters at 0 */
		if (!w->baseline)
			notify(w, st, true);
	}
	st->seen = true;

	/* counter increases since the previous sample; a counter that went back counts 0 */
	uint32_t retries = 0, failed = 0;
	if (s->has & (RL_STA_RETRIES | RL_STA_FAILED)) {
		if (st->have_prev) {
			retries = s->tx_retries >= st->prev_retries ? s->tx_retries - st->prev_retries : 0;
			failed = s->tx_failed >= st->prev_failed ? s->tx_failed - st->prev_failed : 0;
		}
		st->prev_retries = s->tx_retries;
		st->prev_failed = s->tx_failed;
		st->have_prev = true;
	}
	for (int i = 0; i < 2; i++)
		acc_add_sample(acc_at(w, st, i, now), s, retries, failed, freq);

	rl_live_pt p = { .ts = (uint32_t)now, .retries = sat16(retries), .failed = sat16(failed) };
	if (s->has & RL_STA_SIGNAL) {
		p.signal = s->signal;
		p.flags |= RL_SIG_F_SIGNAL;
	}
	if (s->has & RL_STA_TX_RATE) {
		p.tx_rate = s->tx_rate;
		p.flags |= RL_SIG_F_TX_RATE;
	}
	if (s->has & RL_STA_RX_RATE) {
		p.rx_rate = s->rx_rate;
		p.flags |= RL_SIG_F_RX_RATE;
	}
	if (s->has & (RL_STA_RETRIES | RL_STA_FAILED))
		p.flags |= RL_SIG_F_COUNTERS;
	ring_push(st, &p);

	st->s = *s;
	st->updated = now;
	return st;
}

void rl_wifi_end(rl_wifi *w, int64_t now, bool complete)
{
	if (!complete)
		return;
	for (size_t i = 0; i < w->n; i++) {
		rl_wifi_sta *st = w->stas[i];
		if (!st->associated || st->seen)
			continue;
		st->associated = false;
		st->changed = now;
		if (!w->baseline)
			notify(w, st, false);
	}
	w->baseline = false;
}

void rl_wifi_disassoc(rl_wifi *w, const rl_mac *mac, int ifindex, int64_t now)
{
	rl_wifi_sta *st = rl_wifi_find(w, mac);
	if (!st || !st->associated || (ifindex > 0 && st->ifindex != ifindex))
		return;
	st->associated = false;
	st->changed = now;
	notify(w, st, false);
}

void rl_wifi_tick(rl_wifi *w, int64_t now)
{
	out_list l = { 0 };
	for (size_t i = 0; i < w->n; i++) {
		rl_wifi_sta *st = w->stas[i];
		for (int t = 0; t < 2; t++) {
			rl_sig_acc *a = &st->acc[t];
			rl_sig_rec r;
			if (!a->start || rl_bucket_next(TIERS[t], a->start) > now)
				continue;
			if (acc_rec(a, st->dev, &r))
				out_add(&l, TIERS[t], &r);
			memset(a, 0, sizeof(*a));
		}
	}
	out_emit(w, &l);

	size_t k = 0;
	for (size_t i = 0; i < w->n; i++) {
		rl_wifi_sta *st = w->stas[i];
		if (!st->associated && now - st->changed >= RL_WIFI_FORGET && !st->acc[T_MIN].start &&
		    !st->acc[T_HOUR].start) {
			sta_free(st);
			continue;
		}
		w->stas[k++] = st;
	}
	w->n = k;
}

void rl_wifi_flush(rl_wifi *w, bool hour)
{
	out_list l = { 0 };
	for (size_t i = 0; i < w->n; i++) {
		rl_wifi_sta *st = w->stas[i];
		for (int t = 0; t < (hour ? 2 : 1); t++) {
			rl_sig_rec r;
			if (acc_rec(&st->acc[t], st->dev, &r)) {
				out_add(&l, TIERS[t], &r);
				acc_open(&st->acc[t], st->acc[t].start);
			}
		}
	}
	out_emit(w, &l);
}

void rl_wifi_reset_data(rl_wifi *w)
{
	for (size_t i = 0; i < w->n; i++) {
		rl_wifi_sta *st = w->stas[i];
		memset(st->acc, 0, sizeof(st->acc));
		st->ring_head = st->ring_n = 0;
	}
}

size_t rl_wifi_live(const rl_wifi_sta *st, int64_t start, int64_t end, rl_live_pt *out, size_t max)
{
	size_t first = (size_t)(st->ring_head + RL_WIFI_RING - st->ring_n) % RL_WIFI_RING, match = 0, n = 0;
	for (size_t i = 0; i < st->ring_n; i++) {
		const rl_live_pt *p = &st->ring[(first + i) % RL_WIFI_RING];
		match += p->ts >= start && p->ts < end;
	}
	size_t skip = match > max ? match - max : 0; /* keep the newest */
	for (size_t i = 0; i < st->ring_n && n < max; i++) {
		const rl_live_pt *p = &st->ring[(first + i) % RL_WIFI_RING];
		if (p->ts < start || p->ts >= end)
			continue;
		if (skip) {
			skip--;
			continue;
		}
		out[n++] = *p;
	}
	return n;
}

bool rl_wifi_open_rec(const rl_wifi_sta *st, rl_tier tier, rl_sig_rec *out)
{
	return acc_rec(&st->acc[tier == RL_TIER_HOUR ? T_HOUR : T_MIN], st->dev, out);
}

/* ---- restart recovery ---- */

typedef struct {
	uint16_t dev;
	rl_sig_acc acc;
} dev_sum;

typedef struct {
	rl_wifi *w;
	rl_series *hour;
	int64_t now, cur; /* current hour */
	int64_t group, group_end;
	dev_sum *items;
	size_t n, cap;
	int written;
	rl_wifi_mac_fn mac_of;
	void *ctx;
} recover_ctx;

static int cmp_dev_sum(const void *x, const void *y)
{
	const dev_sum *a = x, *b = y;
	return a->dev < b->dev ? -1 : a->dev > b->dev;
}

static void recover_group(recover_ctx *c)
{
	if (!c->n)
		return;
	qsort(c->items, c->n, sizeof(dev_sum), cmp_dev_sum);
	for (size_t i = 0; i < c->n; i++) {
		dev_sum *d = &c->items[i];
		d->acc.start = c->group;
		if (c->group < c->cur) {
			/* the hour ended while nothing was recording */
			rl_sig_rec r;
			uint8_t raw[REC];
			if (!acc_rec(&d->acc, d->dev, &r))
				continue;
			rl_sig_encode(&r, raw);
			if (rl_series_append(c->hour, raw) == 0)
				c->written++;
			continue;
		}
		/* the open hour: hand it to the station (it shows up in the next dump, if it is still here) */
		rl_mac mac;
		if (!c->mac_of || !c->mac_of(d->dev, &mac, c->ctx))
			continue;
		rl_wifi_sta *st = rl_wifi_find(c->w, &mac);
		if (!st)
			st = sta_new(c->w, &mac);
		st->dev = d->dev;
		rl_sig_acc *a = &st->acc[T_HOUR];
		if (a->start != c->group)
			acc_open(a, c->group);
		rl_sig_rec r;
		if (acc_rec(&d->acc, d->dev, &r))
			acc_add_rec(a, &r);
	}
	c->n = 0;
}

static bool recover_cb(const uint8_t *raw, void *x)
{
	recover_ctx *c = x;
	rl_sig_rec r;
	rl_sig_decode(raw, &r);
	if (r.ts >= c->group_end || r.ts < c->group) {
		recover_group(c);
		c->group = rl_bucket_start(RL_TIER_HOUR, r.ts);
		c->group_end = rl_bucket_next(RL_TIER_HOUR, r.ts);
	}
	dev_sum *d = NULL;
	for (size_t i = 0; i < c->n && !d; i++)
		if (c->items[i].dev == r.dev)
			d = &c->items[i];
	if (!d) {
		c->items = rl_grow(c->items, &c->cap, c->n + 1, sizeof(dev_sum));
		d = &c->items[c->n++];
		memset(d, 0, sizeof(*d));
		d->dev = r.dev;
	}
	acc_add_rec(&d->acc, &r);
	return true;
}

int rl_wifi_recover(rl_wifi *w, rl_series *minute, rl_series *hour, int64_t now, rl_wifi_mac_fn mac_of, void *ctx)
{
	int64_t oldest = rl_series_oldest(minute);
	if (oldest == INT64_MAX)
		return 0;
	/* start after the newest hour record, but not before the minute data begins */
	int64_t from = rl_bucket_start(RL_TIER_HOUR, oldest);
	int64_t newest = rl_series_newest(hour);
	if (newest != INT64_MIN && rl_bucket_next(RL_TIER_HOUR, newest) > from)
		from = rl_bucket_next(RL_TIER_HOUR, newest);
	recover_ctx c = { .w = w, .hour = hour, .now = now, .cur = rl_bucket_start(RL_TIER_HOUR, now),
			  .mac_of = mac_of, .ctx = ctx };
	rl_series_scan(minute, from, rl_bucket_next(RL_TIER_HOUR, now), recover_cb, &c);
	recover_group(&c);
	free(c.items);
	return c.written;
}

/* ---- signal history ---- */

const char *rl_sigq_tier_name(rl_sigq_tier t)
{
	switch (t) {
	case RL_SIGQ_LIVE:
		return "live";
	case RL_SIGQ_HOUR:
		return "hour";
	default:
		return "minute";
	}
}

static void point_from(rl_sig_point *p, int64_t ts, const rl_sig_acc *a)
{
	memset(p, 0, sizeof(*p));
	p->ts = ts;
	p->flags = a->flags;
	if (a->flags & RL_SIG_F_SIGNAL) {
		p->avg_signal = (int8_t)div_round(a->sum_signal, a->samples);
		p->min_signal = a->min_signal;
	}
	if (a->tx_n)
		p->avg_tx_rate = sat32((a->sum_tx + a->tx_n / 2) / a->tx_n);
	if (a->rx_n)
		p->avg_rx_rate = sat32((a->sum_rx + a->rx_n / 2) / a->rx_n);
	p->tx_retries = a->retries;
	p->tx_failed = a->failed;
}

/* Ring points in [start, end), merged k at a time when there are more than max_points. */
static bool live_query(const rl_sigq_ctx *c, const rl_wifi_sta *st, int64_t start, int64_t end, int max_points,
		       rl_sig_history *out)
{
	rl_live_pt *pts = malloc(RL_WIFI_RING * sizeof(rl_live_pt));
	if (!pts)
		abort();
	size_t n = rl_wifi_live(st, start, end, pts, RL_WIFI_RING);
	if (!n) {
		free(pts);
		return false;
	}
	size_t k = (n + (size_t)max_points - 1) / (size_t)max_points;
	out->tier = RL_SIGQ_LIVE;
	out->step = (int64_t)(c->live_step > 0 ? c->live_step : 1) * (int64_t)k;
	out->pts = calloc((n + k - 1) / k, sizeof(rl_sig_point));
	if (!out->pts)
		abort();
	for (size_t i = 0; i < n; i += k) {
		rl_sig_acc a = { 0 };
		rl_sta_sample s = { 0 };
		for (size_t j = i; j < n && j < i + k; j++) {
			const rl_live_pt *p = &pts[j];
			s.has = (p->flags & RL_SIG_F_SIGNAL ? RL_STA_SIGNAL : 0) |
				(p->flags & RL_SIG_F_TX_RATE ? RL_STA_TX_RATE : 0) |
				(p->flags & RL_SIG_F_RX_RATE ? RL_STA_RX_RATE : 0) |
				(p->flags & RL_SIG_F_COUNTERS ? RL_STA_RETRIES : 0);
			s.signal = p->signal;
			s.tx_rate = p->tx_rate;
			s.rx_rate = p->rx_rate;
			acc_add_sample(&a, &s, p->retries, p->failed, 0);
		}
		point_from(&out->pts[out->n++], pts[i].ts, &a);
	}
	free(pts);
	return true;
}

typedef struct {
	uint16_t dev;
	int64_t *bounds; /* n + 1 */
	size_t n;
	rl_sig_acc *accs;
} grid_ctx;

static void grid_add(grid_ctx *g, const rl_sig_rec *r)
{
	if (r->dev != g->dev || r->ts < g->bounds[0] || r->ts >= g->bounds[g->n])
		return;
	size_t lo = 0, hi = g->n; /* last bound <= ts */
	while (lo + 1 < hi) {
		size_t mid = (lo + hi) / 2;
		if (g->bounds[mid] <= r->ts)
			lo = mid;
		else
			hi = mid;
	}
	acc_add_rec(&g->accs[lo], r);
}

static bool grid_cb(const uint8_t *raw, void *x)
{
	rl_sig_rec r;
	rl_sig_decode(raw, &r);
	grid_add(x, &r);
	return true;
}

int rl_sig_query(const rl_sigq_ctx *c, uint16_t dev, int64_t start, int64_t end, int max_points, rl_sig_history *out)
{
	memset(out, 0, sizeof(*out));
	if (!max_points)
		max_points = RL_SIGQ_DEFAULT_POINTS;
	if (!rl_range_ok(start, end, RL_SIGQ_MAX_RANGE) || max_points < 1 || max_points > RL_SIGQ_MAX_POINTS)
		return -1;
	const rl_wifi_sta *st = c->wifi ? rl_wifi_find_dev(c->wifi, dev) : NULL;
	if (st && start >= c->now - RL_WIFI_LIVE_RANGE && live_query(c, st, start, end, max_points, out))
		return 0;

	bool minute = start >= c->now - (int64_t)c->minute_days * 86400 - 60;
	rl_tier tier = minute ? RL_TIER_MINUTE : RL_TIER_HOUR;
	rl_series *s = minute ? c->minute : c->hour;
	int64_t limit = rl_bucket_next(RL_TIER_MINUTE, c->now); /* include the open bucket */
	if (end > limit)
		end = limit;
	int64_t first = rl_bucket_start(tier, start), sec = rl_tier_seconds(tier);
	int64_t buckets = end > first ? (end - first + sec - 1) / sec : 0;
	int64_t k = (buckets + max_points - 1) / max_points;
	if (k < 1)
		k = 1;

	grid_ctx g = { .dev = dev };
	size_t cap = 0;
	for (int64_t b = first;;) {
		g.bounds = rl_grow(g.bounds, &cap, g.n + 2, sizeof(int64_t));
		g.bounds[g.n] = b;
		if (b >= end)
			break;
		for (int64_t i = 0; i < k; i++)
			b = rl_bucket_next(tier, b);
		g.n++;
	}
	g.accs = calloc(g.n ? g.n : 1, sizeof(rl_sig_acc));
	out->pts = calloc(g.n ? g.n : 1, sizeof(rl_sig_point));
	if (!g.accs || !out->pts)
		abort();
	if (g.n) {
		if (s)
			rl_series_scan(s, g.bounds[0], g.bounds[g.n], grid_cb, &g);
		rl_sig_rec r;
		if (st && rl_wifi_open_rec(st, tier, &r))
			grid_add(&g, &r);
	}
	for (size_t i = 0; i < g.n; i++)
		point_from(&out->pts[i], g.bounds[i], &g.accs[i]);
	out->n = g.n;
	out->tier = minute ? RL_SIGQ_MINUTE : RL_SIGQ_HOUR;
	out->step = sec * k;
	free(g.bounds);
	free(g.accs);
	return 0;
}

void rl_sig_history_free(rl_sig_history *h)
{
	free(h->pts);
	h->pts = NULL;
	h->n = 0;
}

/* ---- survey ---- */

static rl_survey_entry *sv_find(rl_wifi *w, uint32_t wiphy, uint32_t freq)
{
	for (size_t i = 0; i < w->n_sv; i++)
		if (w->sv[i].s.wiphy == wiphy && w->sv[i].s.freq == freq)
			return &w->sv[i];
	return NULL;
}

void rl_wifi_survey_begin(rl_wifi *w, uint32_t wiphy)
{
	for (size_t i = 0; i < w->n_sv; i++)
		if (w->sv[i].s.wiphy == wiphy)
			w->sv[i].seen = false;
}

static int pct(uint64_t part, uint64_t whole)
{
	if (!whole)
		return -1;
	uint64_t p = (part * 100 + whole / 2) / whole;
	return p > 100 ? 100 : (int)p;
}

const rl_survey_entry *rl_wifi_survey_add(rl_wifi *w, const rl_survey_sample *s, int64_t now)
{
	const uint32_t both = RL_SV_ACTIVE | RL_SV_BUSY;
	rl_survey_entry *e = sv_find(w, s->wiphy, s->freq);
	if (!e) {
		w->sv = rl_grow(w->sv, &w->cap_sv, w->n_sv + 1, sizeof(rl_survey_entry));
		e = &w->sv[w->n_sv++];
		memset(e, 0, sizeof(*e));
		e->busy_pct = -1;
	} else if ((s->has & both) == both && (e->s.has & both) == both && s->active_ms >= e->s.active_ms &&
		   s->busy_ms >= e->s.busy_ms) {
		e->busy_pct = pct(s->busy_ms - e->s.busy_ms, s->active_ms - e->s.active_ms);
	} else {
		e->busy_pct = -1; /* counters reset */
	}
	e->s = *s;
	e->busy_pct_total = (s->has & both) == both ? pct(s->busy_ms, s->active_ms) : -1;
	e->updated = now;
	e->seen = true;
	return e;
}

static void sv_remove_if(rl_wifi *w, bool (*drop)(const rl_survey_entry *e, const void *arg), const void *arg)
{
	size_t k = 0;
	for (size_t i = 0; i < w->n_sv; i++)
		if (!drop(&w->sv[i], arg))
			w->sv[k++] = w->sv[i];
	w->n_sv = k;
}

static bool unseen_on(const rl_survey_entry *e, const void *arg)
{
	return e->s.wiphy == *(const uint32_t *)arg && !e->seen;
}

void rl_wifi_survey_end(rl_wifi *w, uint32_t wiphy)
{
	sv_remove_if(w, unseen_on, &wiphy);
}

typedef struct {
	const uint32_t *wiphys;
	size_t n;
} wiphy_list;

static bool not_listed(const rl_survey_entry *e, const void *arg)
{
	const wiphy_list *l = arg;
	for (size_t i = 0; i < l->n; i++)
		if (l->wiphys[i] == e->s.wiphy)
			return false;
	return true;
}

void rl_wifi_survey_retain(rl_wifi *w, const uint32_t *wiphys, size_t n)
{
	wiphy_list l = { wiphys, n };
	sv_remove_if(w, not_listed, &l);
}

size_t rl_wifi_survey_count(const rl_wifi *w)
{
	return w->n_sv;
}

const rl_survey_entry *rl_wifi_survey_at(const rl_wifi *w, size_t i)
{
	return i < w->n_sv ? &w->sv[i] : NULL;
}

const rl_survey_entry *rl_wifi_survey_radio(const rl_wifi *w, uint32_t wiphy, uint32_t freq)
{
	const rl_survey_entry *in_use = NULL;
	for (size_t i = 0; i < w->n_sv; i++) {
		const rl_survey_entry *e = &w->sv[i];
		if (e->s.wiphy != wiphy)
			continue;
		if (freq && e->s.freq == freq)
			return e;
		if (e->s.in_use && !in_use)
			in_use = e;
	}
	return in_use;
}

/* ---- helpers ---- */

int rl_wifi_channel(uint32_t freq)
{
	if (freq == 2484)
		return 14;
	if (freq >= 2407 && freq < 2484)
		return (int)(freq - 2407) / 5;
	if (freq >= 4910 && freq <= 4980)
		return (int)(freq - 4000) / 5;
	if (freq > 5000 && freq < 5925)
		return (int)(freq - 5000) / 5;
	if (freq == 5935)
		return 2;
	if (freq > 5950 && freq <= 7125)
		return (int)(freq - 5950) / 5;
	if (freq >= 58320 && freq <= 70200)
		return (int)(freq - 56160) / 2160;
	return 0;
}

const char *rl_wifi_mode_name(rl_wifi_mode m)
{
	switch (m) {
	case RL_WIFI_MODE_LEGACY:
		return "legacy";
	case RL_WIFI_MODE_HT:
		return "ht";
	case RL_WIFI_MODE_VHT:
		return "vht";
	case RL_WIFI_MODE_HE:
		return "he";
	default:
		return "";
	}
}
