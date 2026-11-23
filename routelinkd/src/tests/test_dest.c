#include <stdlib.h>

#include "t.h"

#include "core/dest.h"
#include "core/vlog.h"

static void ip4(uint8_t out[16], int a, int b, int c, int d)
{
	memset(out, 0, 16);
	out[0] = (uint8_t)a;
	out[1] = (uint8_t)b;
	out[2] = (uint8_t)c;
	out[3] = (uint8_t)d;
}

static void test_sum_and_top(void)
{
	rl_dest_map *m = rl_dest_map_new(256);
	uint8_t a[16];
	for (int i = 0; i < 150; i++) {
		ip4(a, 10, 0, i / 256, i % 256);
		T_ASSERT(rl_dest_add(m, 4, a, NULL, (uint64_t)i * 1000, 10, 1));
	}
	ip4(a, 10, 0, 0, 5);
	rl_dest_add(m, 4, a, "five.example", 0, 1u << 30, 2); /* jumps to the top, gets its name */
	T_EQ_U64(rl_dest_map_count(m), 150);

	static rl_dest_entry top[RL_DEST_TOP];
	size_t n = rl_dest_top(m, top, RL_DEST_TOP);
	T_EQ_U64(n, RL_DEST_TOP);
	T_EQ_STR(top[0].host, "five.example");
	T_EQ_U64(top[0].conns, 3);
	T_EQ_U64(top[1].rx, 149000);
	bool sorted = true;
	for (size_t i = 1; i < n; i++)
		if (top[i].rx + top[i].tx > top[i - 1].rx + top[i - 1].tx)
			sorted = false;
	T_ASSERT(sorted);

	/* A full map refuses new peers but keeps counting known ones. */
	rl_dest_map *small = rl_dest_map_new(8);
	for (int i = 0; i < 8; i++) {
		ip4(a, 1, 1, 1, i);
		rl_dest_add(small, 4, a, NULL, 1, 1, 1);
	}
	ip4(a, 2, 2, 2, 2);
	T_ASSERT(!rl_dest_add(small, 4, a, NULL, 1, 1, 1));
	ip4(a, 1, 1, 1, 3);
	T_ASSERT(rl_dest_add(small, 4, a, NULL, 1, 1, 1));
	rl_dest_map_clear(small);
	T_EQ_U64(rl_dest_map_count(small), 0);
	rl_dest_map_free(small);
	rl_dest_map_free(m);
}

typedef struct {
	int n;
	rl_dest_entry e[256];
} got;

static bool keep(const rl_dest_entry *e, void *ctx)
{
	got *g = ctx;
	g->e[g->n++] = *e;
	return true;
}

/* Queries merge hours newest first: counters add up, the newest known name stays. */
static void test_merge(void)
{
	rl_dest_map *m = rl_dest_map_new(16);
	rl_dest_entry e = { .family = 4, .addr = { 10, 0, 0, 1 }, .rx = 100, .tx = 10, .conns = 1 };
	T_ASSERT(rl_dest_merge(m, &e)); /* newest hour: no name */
	snprintf(e.host, sizeof(e.host), "new.example");
	T_ASSERT(rl_dest_merge(m, &e));
	snprintf(e.host, sizeof(e.host), "old.example");
	T_ASSERT(rl_dest_merge(m, &e));
	rl_dest_entry top[2];
	T_EQ_U64(rl_dest_top(m, top, 2), 1);
	T_EQ_STR(top[0].host, "new.example");
	T_EQ_U64(top[0].rx, 300);
	T_EQ_U64(top[0].conns, 3);
	/* adding live traffic, the latest name wins */
	rl_dest_add(m, 4, e.addr, "latest.example", 1, 1, 0);
	rl_dest_top(m, top, 2);
	T_EQ_STR(top[0].host, "latest.example");
	rl_dest_map_free(m);
}

static void test_record(void)
{
	rl_dest_entry e[3];
	memset(e, 0, sizeof(e));
	e[0].family = 4;
	ip4(e[0].addr, 93, 184, 216, 34);
	e[0].rx = 5000000000ull;
	e[0].tx = 7;
	e[0].conns = 12;
	snprintf(e[0].host, sizeof(e[0].host), "example.com");
	e[1].family = 6;
	for (int i = 0; i < 16; i++)
		e[1].addr[i] = (uint8_t)(0x20 + i);
	e[1].rx = 1;
	e[2].family = 4;
	ip4(e[2].addr, 1, 1, 1, 1);

	uint8_t mac[6] = { 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x01 }, back[6];
	uint8_t rec[RL_VLOG_REC_MAX];
	size_t len = rl_dest_encode(rec, sizeof(rec), 1790002800, mac, e, 3);
	T_ASSERT(len > 11);
	got g = { 0 };
	int64_t hour;
	T_EQ_I64(rl_dest_decode(rec, len, &hour, back, keep, &g), 0);
	T_EQ_I64(hour, 1790002800);
	T_ASSERT(memcmp(back, mac, 6) == 0);
	T_EQ_I64(g.n, 3);
	T_EQ_U64(g.e[0].rx, 5000000000ull);
	T_EQ_STR(g.e[0].host, "example.com");
	T_EQ_I64(g.e[1].family, 6);
	T_EQ_I64(g.e[1].addr[15], 0x2f);
	T_EQ_STR(g.e[2].host, "");

	/* Too small for all: the last entries are left out; a cut record decodes what is whole. */
	size_t part = rl_dest_encode(rec, 11 + 1 + 4 + 21 + 11 + 5, 1, mac, e, 3);
	got h = { 0 };
	T_EQ_I64(rl_dest_decode(rec, part, &hour, back, keep, &h), 0);
	T_EQ_I64(h.n, 1);
	len = rl_dest_encode(rec, sizeof(rec), 1, mac, e, 3);
	got k = { 0 };
	T_EQ_I64(rl_dest_decode(rec, len - 3, &hour, back, keep, &k), -1);
	T_EQ_I64(k.n, 2);
}

/* The top 100 with long names still fits in one log record. */
static void test_worst_case_fits(void)
{
	static rl_dest_entry e[RL_DEST_TOP];
	for (int i = 0; i < RL_DEST_TOP; i++) {
		memset(&e[i], 0, sizeof(e[i]));
		e[i].family = 6;
		memset(e[i].host, 'a' + i % 26, RL_DEST_HOST_MAX);
		e[i].rx = (uint64_t)(RL_DEST_TOP - i);
	}
	uint8_t mac[6] = { 0 };
	static uint8_t rec[RL_VLOG_REC_MAX];
	size_t len = rl_dest_encode(rec, sizeof(rec), 1, mac, e, RL_DEST_TOP);
	T_ASSERT(len <= RL_VLOG_REC_MAX);
	T_ASSERT(rec[10] > 50); /* most of them, the busiest */
}

int main(void)
{
	T_RUN(test_sum_and_top);
	T_RUN(test_merge);
	T_RUN(test_record);
	T_RUN(test_worst_case_fits);
	T_DONE();
}
