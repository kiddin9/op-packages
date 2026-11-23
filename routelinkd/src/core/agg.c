#include <stdlib.h>
#include <string.h>

#include "core/agg.h"
#include "core/util.h"

typedef struct {
	uint64_t rx, tx;
	uint32_t conns;
	uint8_t touched;
} acc;

/* One (dev, cls) key: an accumulator per tier plus bytes since the last sample pass. */
typedef struct {
	uint32_t key;
	acc t[RL_TIER_COUNT];
	uint64_t s_rx, s_tx;
} slot;

struct rl_agg {
	rl_close_cb on_close;
	void *ctx;

	slot *slots;
	size_t n, cap;
	/* key + 1 -> slot index + 1, open addressing; 0 = empty */
	uint32_t *idx_keys, *idx_vals;
	size_t idx_cap;

	int64_t open[RL_TIER_COUNT]; /* bucket start, 0 = nothing open */
	int64_t next[RL_TIER_COUNT];

	int64_t last_ms;
	rl_rate *rates;
	size_t n_rates, cap_rates;
};

static uint32_t make_key(uint16_t dev, rl_class cls)
{
	return (uint32_t)dev << 2 | (uint32_t)cls;
}

static void index_put(uint32_t *keys, uint32_t *vals, size_t cap, uint32_t key, uint32_t val)
{
	size_t mask = cap - 1;
	size_t i = rl_mix32(key) & mask;
	while (keys[i])
		i = (i + 1) & mask;
	keys[i] = key + 1;
	vals[i] = val + 1;
}

static void index_grow(rl_agg *a)
{
	size_t cap = a->idx_cap ? a->idx_cap * 2 : 256;
	uint32_t *keys = calloc(cap, sizeof(uint32_t)), *vals = calloc(cap, sizeof(uint32_t));
	if (!keys || !vals)
		abort();
	for (size_t i = 0; i < a->n; i++)
		index_put(keys, vals, cap, a->slots[i].key, (uint32_t)i);
	free(a->idx_keys);
	free(a->idx_vals);
	a->idx_keys = keys;
	a->idx_vals = vals;
	a->idx_cap = cap;
}

static slot *get_slot(rl_agg *a, uint16_t dev, rl_class cls)
{
	uint32_t key = make_key(dev, cls);
	if (a->idx_cap) {
		size_t mask = a->idx_cap - 1;
		for (size_t i = rl_mix32(key) & mask; a->idx_keys[i]; i = (i + 1) & mask)
			if (a->idx_keys[i] == key + 1)
				return &a->slots[a->idx_vals[i] - 1];
	}
	if ((a->n + 1) * 2 > a->idx_cap)
		index_grow(a);
	a->slots = rl_grow(a->slots, &a->cap, a->n + 1, sizeof(slot));
	slot *s = &a->slots[a->n];
	memset(s, 0, sizeof(*s));
	s->key = key;
	index_put(a->idx_keys, a->idx_vals, a->idx_cap, key, (uint32_t)a->n);
	a->n++;
	return s;
}

rl_agg *rl_agg_new(rl_close_cb on_close, void *ctx)
{
	rl_agg *a = calloc(1, sizeof(*a));
	if (!a)
		abort();
	a->on_close = on_close;
	a->ctx = ctx;
	return a;
}

void rl_agg_free(rl_agg *a)
{
	if (!a)
		return;
	free(a->slots);
	free(a->idx_keys);
	free(a->idx_vals);
	free(a->rates);
	free(a);
}

static void open_if_needed(rl_agg *a, int64_t now)
{
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		if (a->open[t])
			continue;
		a->open[t] = rl_bucket_start((rl_tier)t, now);
		a->next[t] = rl_bucket_next((rl_tier)t, now);
	}
}

void rl_agg_add(rl_agg *a, int64_t now, uint16_t dev, rl_class cls, uint64_t rx, uint64_t tx)
{
	rl_agg_tick(a, now);
	open_if_needed(a, now);
	slot *s = get_slot(a, dev, cls);
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		s->t[t].rx += rx;
		s->t[t].tx += tx;
		s->t[t].touched = 1;
	}
	s->s_rx += rx;
	s->s_tx += tx;
}

void rl_agg_conns(rl_agg *a, int64_t now, uint16_t dev, uint32_t conns)
{
	rl_agg_tick(a, now);
	open_if_needed(a, now);
	slot *s = get_slot(a, dev, RL_CLASS_INTERNET);
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		if (conns > s->t[t].conns)
			s->t[t].conns = conns;
		s->t[t].touched = 1;
	}
}

static int cmp_key(const void *x, const void *y)
{
	uint32_t a = (*(const slot *const *)x)->key, b = (*(const slot *const *)y)->key;
	return a < b ? -1 : a > b;
}

static size_t touched_sorted(const rl_agg *a, rl_tier t, slot ***out)
{
	slot **list = malloc((a->n ? a->n : 1) * sizeof(*list));
	if (!list)
		abort();
	size_t k = 0;
	for (size_t i = 0; i < a->n; i++)
		if (a->slots[i].t[t].touched)
			list[k++] = &a->slots[i];
	qsort(list, k, sizeof(*list), cmp_key);
	*out = list;
	return k;
}

static rl_rec to_rec(const slot *s, rl_tier t, int64_t ts)
{
	rl_rec r = {
		.ts = ts,
		.dev = (uint16_t)(s->key >> 2),
		.cls = (uint8_t)(s->key & 3),
		.conns = s->t[t].conns,
		.rx = s->t[t].rx,
		.tx = s->t[t].tx,
	};
	return r;
}

void rl_agg_tick(rl_agg *a, int64_t now)
{
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		if (!a->open[t] || now < a->next[t])
			continue;
		slot **list;
		size_t k = touched_sorted(a, (rl_tier)t, &list);
		for (size_t i = 0; i < k; i++) {
			rl_rec r = to_rec(list[i], (rl_tier)t, a->open[t]);
			memset(&list[i]->t[t], 0, sizeof(acc));
			if (a->on_close)
				a->on_close((rl_tier)t, &r, a->ctx);
		}
		free(list);
		a->open[t] = rl_bucket_start((rl_tier)t, now);
		a->next[t] = rl_bucket_next((rl_tier)t, now);
	}
}

void rl_agg_open(const rl_agg *a, rl_tier tier, rl_rec_cb cb, void *ctx)
{
	if (!a->open[tier])
		return;
	slot **list;
	size_t k = touched_sorted(a, tier, &list);
	for (size_t i = 0; i < k; i++) {
		rl_rec r = to_rec(list[i], tier, a->open[tier]);
		if (!cb(&r, ctx))
			break;
	}
	free(list);
}

void rl_agg_flush(rl_agg *a, rl_tier tier)
{
	if (!a->open[tier])
		return;
	slot **list;
	size_t k = touched_sorted(a, tier, &list);
	for (size_t i = 0; i < k; i++) {
		rl_rec r = to_rec(list[i], tier, a->open[tier]);
		memset(&list[i]->t[tier], 0, sizeof(acc));
		if (a->on_close)
			a->on_close(tier, &r, a->ctx);
	}
	free(list);
}

void rl_agg_hydrate(rl_agg *a, int64_t now, rl_tier tier, const rl_rec *r)
{
	open_if_needed(a, now);
	slot *s = get_slot(a, r->dev, (rl_class)r->cls);
	s->t[tier].rx += r->rx;
	s->t[tier].tx += r->tx;
	if (r->conns > s->t[tier].conns)
		s->t[tier].conns = r->conns;
	s->t[tier].touched = 1;
}

int64_t rl_agg_open_start(const rl_agg *a, rl_tier tier)
{
	return a->open[tier];
}

void rl_agg_reset(rl_agg *a)
{
	a->n = 0;
	memset(a->open, 0, sizeof(a->open));
	memset(a->next, 0, sizeof(a->next));
	if (a->idx_cap) {
		memset(a->idx_keys, 0, a->idx_cap * sizeof(uint32_t));
		memset(a->idx_vals, 0, a->idx_cap * sizeof(uint32_t));
	}
	a->n_rates = 0;
}

void rl_agg_sample_done(rl_agg *a, int64_t now_ms)
{
	int64_t dt = now_ms - a->last_ms;
	bool first = a->last_ms == 0 || dt <= 0;
	a->last_ms = now_ms;
	a->n_rates = 0;
	for (size_t i = 0; i < a->n; i++) {
		slot *s = &a->slots[i];
		if (!first && (s->s_rx || s->s_tx)) {
			uint16_t dev = (uint16_t)(s->key >> 2);
			rl_rate *r = NULL;
			for (size_t j = 0; j < a->n_rates; j++)
				if (a->rates[j].dev == dev)
					r = &a->rates[j];
			if (!r) {
				a->rates = rl_grow(a->rates, &a->cap_rates, a->n_rates + 1, sizeof(rl_rate));
				r = &a->rates[a->n_rates++];
				memset(r, 0, sizeof(*r));
				r->dev = dev;
			}
			r->rx_rate += s->s_rx * 1000 / (uint64_t)dt;
			r->tx_rate += s->s_tx * 1000 / (uint64_t)dt;
		}
		s->s_rx = s->s_tx = 0;
	}
}

size_t rl_agg_rates(const rl_agg *a, const rl_rate **out)
{
	*out = a->rates;
	return a->n_rates;
}
