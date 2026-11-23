#include "t.h"

#include "core/flows.h"

static rl_ct_sample flow(uint32_t id, uint16_t sport, uint64_t ob, uint64_t rb)
{
	rl_ct_sample s = { .ct_id = id, .orig_sport = sport, .orig_dport = 443, .l4proto = 6, .orig_bytes = ob, .reply_bytes = rb };
	rl_ip_parse("192.168.1.10", &s.orig_src);
	rl_ip_parse("1.1.1.1", &s.orig_dst);
	s.reply_src = s.orig_dst;
	s.reply_dst = s.orig_src;
	s.tuple_hash = rl_flows_tuple_hash(&s);
	return s;
}

static void first_sight_then_deltas(void)
{
	rl_flows *f = rl_flows_new();
	uint64_t *tag;
	rl_flows_begin(f, false);
	rl_ct_sample s = flow(1, 5000, 1000, 5000);
	rl_delta d = rl_flows_update(f, &s, &tag);
	T_EQ_U64(d.orig_bytes, 1000);
	T_EQ_U64(d.reply_bytes, 5000);
	T_EQ_U64(*tag, 0);
	*tag = 42;
	rl_flows_sweep(f);

	rl_flows_begin(f, false);
	s.orig_bytes = 1500;
	s.reply_bytes = 9000;
	d = rl_flows_update(f, &s, &tag);
	T_EQ_U64(d.orig_bytes, 500);
	T_EQ_U64(d.reply_bytes, 4000);
	T_EQ_U64(*tag, 42);
	rl_flows_sweep(f);

	uint64_t t = 0;
	s.orig_bytes = 1600;
	s.reply_bytes = 9100;
	d = rl_flows_destroy(f, &s, &t);
	T_EQ_U64(d.orig_bytes, 100);
	T_EQ_U64(d.reply_bytes, 100);
	T_EQ_U64(t, 42);
	T_EQ_U64(rl_flows_count(f), 0);
	rl_flows_free(f);
}

static void destroy_without_sight(void)
{
	rl_flows *f = rl_flows_new();
	uint64_t t = 7;
	rl_ct_sample s = flow(9, 5001, 300, 1200);
	rl_delta d = rl_flows_destroy(f, &s, &t);
	T_EQ_U64(d.orig_bytes, 300);
	T_EQ_U64(d.reply_bytes, 1200);
	T_EQ_U64(t, 0);
	rl_flows_free(f);
}

static void id_reuse_is_a_new_flow(void)
{
	rl_flows *f = rl_flows_new();
	uint64_t *tag;
	rl_flows_begin(f, false);
	rl_ct_sample a = flow(5, 6000, 100, 100);
	rl_flows_update(f, &a, &tag);
	*tag = 1;
	rl_ct_sample b = flow(5, 6001, 50, 70); /* same id, different tuple */
	rl_delta d = rl_flows_update(f, &b, &tag);
	T_EQ_U64(d.orig_bytes, 50);
	T_EQ_U64(d.reply_bytes, 70);
	T_EQ_U64(*tag, 0);
	T_EQ_U64(rl_flows_count(f), 2);
	rl_flows_free(f);
}

static void counter_reset(void)
{
	rl_flows *f = rl_flows_new();
	uint64_t *tag;
	rl_flows_begin(f, false);
	rl_ct_sample s = flow(3, 7000, 1500, 1500);
	rl_flows_update(f, &s, &tag);
	s.orig_bytes = 200;
	s.reply_bytes = 300;
	rl_delta d = rl_flows_update(f, &s, &tag);
	T_EQ_U64(d.orig_bytes, 0);
	T_EQ_U64(d.reply_bytes, 0);
	s.orig_bytes = 260;
	s.reply_bytes = 330;
	d = rl_flows_update(f, &s, &tag);
	T_EQ_U64(d.orig_bytes, 60);
	T_EQ_U64(d.reply_bytes, 30);
	rl_flows_free(f);
}

static void baseline_pass(void)
{
	rl_flows *f = rl_flows_new();
	uint64_t *tag;
	rl_flows_begin(f, true);
	rl_ct_sample s = flow(4, 7100, 1 << 20, 1 << 20);
	rl_delta d = rl_flows_update(f, &s, &tag);
	T_EQ_U64(d.orig_bytes + d.reply_bytes, 0);
	rl_flows_sweep(f);
	rl_flows_begin(f, false);
	s.orig_bytes += 10;
	d = rl_flows_update(f, &s, &tag);
	T_EQ_U64(d.orig_bytes, 10);
	rl_flows_free(f);
}

static void sweep_lost_destroys(void)
{
	rl_flows *f = rl_flows_new();
	uint64_t *tag;
	rl_flows_begin(f, false);
	rl_ct_sample a = flow(1, 1, 1, 1), b = flow(2, 2, 1, 1);
	rl_flows_update(f, &a, &tag);
	rl_flows_update(f, &b, &tag);
	T_EQ_U64(rl_flows_sweep(f), 0);
	rl_flows_begin(f, false); /* b missing once: kept */
	rl_flows_update(f, &a, &tag);
	T_EQ_U64(rl_flows_sweep(f), 0);
	rl_flows_begin(f, false); /* b missing twice: dropped */
	rl_flows_update(f, &a, &tag);
	T_EQ_U64(rl_flows_sweep(f), 1);
	T_EQ_U64(rl_flows_count(f), 1);
	rl_flows_free(f);
}

static void many_flows(void)
{
	rl_flows *f = rl_flows_new();
	uint64_t *tag, total = 0;
	for (int pass = 1; pass <= 3; pass++) {
		rl_flows_begin(f, false);
		for (uint32_t i = 0; i < 100000; i++) {
			rl_ct_sample s = flow(i, (uint16_t)i, (uint64_t)pass * 10, 0);
			total += rl_flows_update(f, &s, &tag).orig_bytes;
		}
		rl_flows_sweep(f);
	}
	T_EQ_U64(rl_flows_count(f), 100000);
	T_EQ_U64(total, 100000ull * 30);
	/* destroy half; the table must still find the rest after backward-shift deletions */
	for (uint32_t i = 0; i < 100000; i += 2) {
		rl_ct_sample s = flow(i, (uint16_t)i, 30, 0);
		uint64_t t;
		rl_flows_destroy(f, &s, &t);
	}
	T_EQ_U64(rl_flows_count(f), 50000);
	rl_flows_begin(f, false);
	uint64_t extra = 0;
	for (uint32_t i = 1; i < 100000; i += 2) {
		rl_ct_sample s = flow(i, (uint16_t)i, 31, 0);
		extra += rl_flows_update(f, &s, &tag).orig_bytes;
	}
	T_EQ_U64(extra, 50000);
	rl_flows_free(f);
}

int main(void)
{
	T_RUN(first_sight_then_deltas);
	T_RUN(destroy_without_sight);
	T_RUN(id_reuse_is_a_new_flow);
	T_RUN(counter_reset);
	T_RUN(baseline_pass);
	T_RUN(sweep_lost_destroys);
	T_RUN(many_flows);
	T_DONE();
}
