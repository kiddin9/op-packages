#include "core/dest.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "core/series.h"
#include "core/util.h"

struct rl_dest_map {
	rl_dest_entry *slots;
	bool *used;
	size_t cap, n;
};

static size_t alen(uint8_t family)
{
	return family == 6 ? 16 : 4;
}

rl_dest_map *rl_dest_map_new(size_t capacity)
{
	rl_dest_map *m = calloc(1, sizeof(*m));
	if (!m)
		abort();
	m->cap = capacity < 8 ? 8 : capacity;
	m->slots = calloc(m->cap * 2, sizeof(*m->slots));
	m->used = calloc(m->cap * 2, sizeof(*m->used));
	if (!m->slots || !m->used)
		abort();
	return m;
}

void rl_dest_map_free(rl_dest_map *m)
{
	if (!m)
		return;
	free(m->slots);
	free(m->used);
	free(m);
}

void rl_dest_map_clear(rl_dest_map *m)
{
	memset(m->used, 0, m->cap * 2 * sizeof(*m->used));
	m->n = 0;
}

size_t rl_dest_map_count(const rl_dest_map *m)
{
	return m->n;
}

bool rl_dest_add(rl_dest_map *m, uint8_t family, const uint8_t *addr, const char *host, uint64_t rx, uint64_t tx,
		 uint32_t conns)
{
	if (family != 4 && family != 6)
		return false;
	size_t size = m->cap * 2;
	size_t at = rl_mix32(rl_fnv1a(addr, alen(family), RL_FNV_SEED ^ family)) % size;
	while (m->used[at]) {
		rl_dest_entry *e = &m->slots[at];
		if (e->family == family && memcmp(e->addr, addr, alen(family)) == 0) {
			e->rx += rx;
			e->tx += tx;
			e->conns += conns;
			if (host && host[0])
				snprintf(e->host, sizeof(e->host), "%s", host);
			return true;
		}
		at = (at + 1) % size;
	}
	if (m->n >= m->cap)
		return false;
	rl_dest_entry *e = &m->slots[at];
	memset(e, 0, sizeof(*e));
	e->family = family;
	memcpy(e->addr, addr, alen(family));
	e->rx = rx;
	e->tx = tx;
	e->conns = conns;
	if (host)
		snprintf(e->host, sizeof(e->host), "%s", host);
	m->used[at] = true;
	m->n++;
	return true;
}

bool rl_dest_merge(rl_dest_map *m, const rl_dest_entry *e)
{
	size_t size = m->cap * 2;
	if (e->family != 4 && e->family != 6)
		return false;
	size_t at = rl_mix32(rl_fnv1a(e->addr, alen(e->family), RL_FNV_SEED ^ e->family)) % size;
	while (m->used[at]) {
		rl_dest_entry *x = &m->slots[at];
		if (x->family == e->family && memcmp(x->addr, e->addr, alen(e->family)) == 0) {
			if (!x->host[0])
				memcpy(x->host, e->host, sizeof(x->host));
			break;
		}
		at = (at + 1) % size;
	}
	/* counters (and the name of a new peer) through the usual path */
	return rl_dest_add(m, e->family, e->addr, m->used[at] ? NULL : e->host, e->rx, e->tx, e->conns);
}

static int busier(const void *a, const void *b)
{
	const rl_dest_entry *x = a, *y = b;
	uint64_t tx_ = x->rx + x->tx, ty = y->rx + y->tx;
	return tx_ < ty ? 1 : tx_ > ty ? -1 : 0;
}

size_t rl_dest_top(const rl_dest_map *m, rl_dest_entry *out, size_t n)
{
	rl_dest_entry *all = malloc((m->n ? m->n : 1) * sizeof(*all));
	if (!all)
		abort();
	size_t k = 0;
	for (size_t i = 0; i < m->cap * 2; i++)
		if (m->used[i])
			all[k++] = m->slots[i];
	qsort(all, k, sizeof(*all), busier);
	size_t take = RL_MIN(k, n);
	memcpy(out, all, take * sizeof(*out));
	free(all);
	return take;
}

static void put64(uint8_t *p, uint64_t v)
{
	rl_le_put32(p, (uint32_t)v);
	rl_le_put32(p + 4, (uint32_t)(v >> 32));
}

static uint64_t get64(const uint8_t *p)
{
	return rl_le_get32(p) | (uint64_t)rl_le_get32(p + 4) << 32;
}

#define HEAD 11

size_t rl_dest_encode(uint8_t *out, size_t size, int64_t hour, const uint8_t mac[6], const rl_dest_entry *e, size_t n)
{
	if (size < HEAD)
		return 0;
	rl_le_put32(out, (uint32_t)hour);
	memcpy(out + 4, mac, 6);
	size_t len = HEAD, count = 0;
	for (size_t i = 0; i < n && count < 255; i++) {
		size_t hl = strnlen(e[i].host, RL_DEST_HOST_MAX);
		size_t need = 1 + alen(e[i].family) + 8 + 8 + 4 + 1 + hl;
		if (len + need > size)
			break;
		uint8_t *p = out + len;
		*p++ = e[i].family;
		memcpy(p, e[i].addr, alen(e[i].family));
		p += alen(e[i].family);
		put64(p, e[i].rx);
		put64(p + 8, e[i].tx);
		rl_le_put32(p + 16, e[i].conns);
		p[20] = (uint8_t)hl;
		memcpy(p + 21, e[i].host, hl);
		len += need;
		count++;
	}
	out[10] = (uint8_t)count;
	return len;
}

int rl_dest_decode(const uint8_t *rec, size_t len, int64_t *hour, uint8_t mac[6], rl_dest_cb cb, void *ctx)
{
	if (len < HEAD)
		return -1;
	*hour = rl_series_ts(rec);
	memcpy(mac, rec + 4, 6);
	size_t off = HEAD;
	for (int i = 0; i < rec[10]; i++) {
		rl_dest_entry e;
		memset(&e, 0, sizeof(e));
		if (off + 1 > len)
			return -1;
		e.family = rec[off++];
		if (e.family != 4 && e.family != 6)
			return -1;
		size_t a = alen(e.family);
		if (off + a + 21 > len)
			return -1;
		memcpy(e.addr, rec + off, a);
		off += a;
		e.rx = get64(rec + off);
		e.tx = get64(rec + off + 8);
		e.conns = rl_le_get32(rec + off + 16);
		size_t hl = rec[off + 20];
		off += 21;
		if (hl > RL_DEST_HOST_MAX || off + hl > len)
			return -1;
		memcpy(e.host, rec + off, hl);
		off += hl;
		if (!cb(&e, ctx))
			return 0;
	}
	return 0;
}
