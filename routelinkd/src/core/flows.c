#include <stdlib.h>
#include <string.h>

#include "core/flows.h"
#include "core/util.h"

/* Open addressing with linear probing and backward-shift deletion (no tombstones). */
typedef struct {
	uint32_t id, th;
	uint32_t gen;
	uint8_t used;
	uint64_t ob, rb;
	uint64_t tag;
} slot;

struct rl_flows {
	slot *slots;
	size_t cap; /* power of two */
	size_t n;
	uint32_t gen;
	bool baseline;
};

static uint32_t key_hash(uint32_t id, uint32_t th)
{
	return rl_mix32(id * 0x9e3779b1u ^ th);
}

rl_flows *rl_flows_new(void)
{
	rl_flows *f = calloc(1, sizeof(*f));
	if (!f)
		abort();
	f->cap = 1024;
	f->slots = calloc(f->cap, sizeof(slot));
	if (!f->slots)
		abort();
	f->gen = 1;
	return f;
}

void rl_flows_free(rl_flows *f)
{
	if (!f)
		return;
	free(f->slots);
	free(f);
}

uint32_t rl_flows_tuple_hash(const rl_ct_sample *s)
{
	uint32_t h = RL_FNV_SEED;
	size_t len = s->orig_src.family == 4 ? 4 : 16;
	h = rl_fnv1a(&s->orig_src.family, 1, h);
	h = rl_fnv1a(s->orig_src.a, len, h);
	h = rl_fnv1a(s->orig_dst.a, len, h);
	h = rl_fnv1a(&s->orig_sport, sizeof(s->orig_sport), h);
	h = rl_fnv1a(&s->orig_dport, sizeof(s->orig_dport), h);
	h = rl_fnv1a(&s->l4proto, 1, h);
	return h;
}

static slot *find(const rl_flows *f, uint32_t id, uint32_t th)
{
	size_t mask = f->cap - 1;
	for (size_t i = key_hash(id, th) & mask;; i = (i + 1) & mask) {
		slot *s = &f->slots[i];
		if (!s->used)
			return NULL;
		if (s->id == id && s->th == th)
			return s;
	}
}

static slot *insert_slot(slot *slots, size_t cap, uint32_t id, uint32_t th)
{
	size_t mask = cap - 1;
	size_t i = key_hash(id, th) & mask;
	while (slots[i].used)
		i = (i + 1) & mask;
	return &slots[i];
}

static void grow(rl_flows *f)
{
	size_t cap = f->cap * 2;
	slot *slots = calloc(cap, sizeof(slot));
	if (!slots)
		abort();
	for (size_t i = 0; i < f->cap; i++)
		if (f->slots[i].used)
			*insert_slot(slots, cap, f->slots[i].id, f->slots[i].th) = f->slots[i];
	free(f->slots);
	f->slots = slots;
	f->cap = cap;
}

static void remove_slot(rl_flows *f, slot *victim)
{
	size_t mask = f->cap - 1;
	size_t hole = (size_t)(victim - f->slots);
	f->slots[hole].used = 0;
	f->n--;
	for (size_t i = (hole + 1) & mask; f->slots[i].used; i = (i + 1) & mask) {
		size_t home = key_hash(f->slots[i].id, f->slots[i].th) & mask;
		/* move i into the hole if the hole lies cyclically between home and i */
		bool movable = hole <= i ? (home <= hole || home > i) : (home <= hole && home > i);
		if (movable) {
			f->slots[hole] = f->slots[i];
			f->slots[i].used = 0;
			hole = i;
		}
	}
}

void rl_flows_begin(rl_flows *f, bool baseline)
{
	f->gen++;
	f->baseline = baseline;
}

static uint64_t diff(uint64_t now, uint64_t *ref)
{
	uint64_t d = now >= *ref ? now - *ref : 0;
	*ref = now;
	return d;
}

rl_delta rl_flows_update(rl_flows *f, const rl_ct_sample *s, uint64_t **tag)
{
	rl_delta d = { 0, 0 };
	slot *e = find(f, s->ct_id, s->tuple_hash);
	if (!e) {
		if ((f->n + 1) * 10 > f->cap * 7)
			grow(f);
		e = insert_slot(f->slots, f->cap, s->ct_id, s->tuple_hash);
		memset(e, 0, sizeof(*e));
		e->used = 1;
		e->id = s->ct_id;
		e->th = s->tuple_hash;
		f->n++;
		if (f->baseline) {
			e->ob = s->orig_bytes;
			e->rb = s->reply_bytes;
		}
	}
	d.orig_bytes = diff(s->orig_bytes, &e->ob);
	d.reply_bytes = diff(s->reply_bytes, &e->rb);
	e->gen = f->gen;
	*tag = &e->tag;
	return d;
}

rl_delta rl_flows_destroy(rl_flows *f, const rl_ct_sample *s, uint64_t *tag)
{
	rl_delta d = { s->orig_bytes, s->reply_bytes };
	slot *e = find(f, s->ct_id, s->tuple_hash);
	*tag = 0;
	if (!e)
		return d;
	d.orig_bytes = diff(s->orig_bytes, &e->ob);
	d.reply_bytes = diff(s->reply_bytes, &e->rb);
	*tag = e->tag;
	remove_slot(f, e);
	return d;
}

size_t rl_flows_sweep(rl_flows *f)
{
	size_t dropped = 0;
	for (size_t i = 0; i < f->cap;) {
		slot *e = &f->slots[i];
		if (e->used && e->gen + 1 < f->gen) {
			remove_slot(f, e); /* may shift another entry into i: look at i again */
			dropped++;
			continue;
		}
		i++;
	}
	return dropped;
}

size_t rl_flows_count(const rl_flows *f)
{
	return f->n;
}

void rl_flows_each(const rl_flows *f, void (*fn)(uint64_t tag, void *ctx), void *ctx)
{
	for (size_t i = 0; i < f->cap; i++)
		if (f->slots[i].used)
			fn(f->slots[i].tag, ctx);
}
