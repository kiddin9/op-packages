#include "t.h"

#include "core/probe.h"

static void test_agg(void)
{
	rl_probe_agg a = { 0 };
	rl_probe_agg_add(&a, true, 3000);
	rl_probe_agg_add(&a, false, 0);
	rl_probe_agg_add(&a, true, 1000);
	rl_probe_agg_add(&a, true, 5000);
	T_EQ_U64(a.sent, 4);
	T_EQ_U64(a.lost, 1);
	T_EQ_U64(a.min_us, 1000);
	T_EQ_U64(a.max_us, 5000);
	T_EQ_U64(rl_probe_agg_avg(&a), 3000);

	/* A minute where everything was lost keeps min/max at 0 and does not spoil the hour's minimum. */
	rl_probe_agg lost = { 0 }, hour = { 0 };
	rl_probe_agg_add(&lost, false, 0);
	T_EQ_U64(rl_probe_agg_avg(&lost), 0);
	rl_probe_agg_merge(&hour, &lost);
	rl_probe_agg_merge(&hour, &a);
	T_EQ_U64(hour.sent, 5);
	T_EQ_U64(hour.lost, 2);
	T_EQ_U64(hour.min_us, 1000);
	T_EQ_U64(rl_probe_agg_avg(&hour), 3000);
}

static void test_record_roundtrip(void)
{
	rl_probe_agg a = { 0 }, b;
	for (int i = 0; i < 6; i++)
		rl_probe_agg_add(&a, i != 2, 2000 + 100 * (uint32_t)i);
	uint8_t rec[32];
	rl_probe_encode(rec, 1790000040, 3, &a);
	int64_t ts;
	int target;
	rl_probe_decode(rec, &ts, &target, &b);
	T_EQ_I64(ts, 1790000040);
	T_EQ_I64(target, 3);
	T_EQ_U64(b.sent, 6);
	T_EQ_U64(b.lost, 1);
	T_EQ_U64(rl_probe_agg_avg(&b), rl_probe_agg_avg(&a));
	T_EQ_U64(b.max_us, 2500);

	int64_t s, e;
	rl_outage_cause c;
	rl_outage_encode(rec, 100, 400, RL_CAUSE_REDIAL);
	rl_outage_decode(rec, &s, &e, &c);
	T_EQ_I64(s, 100);
	T_EQ_I64(e, 400);
	T_EQ_I64(c, RL_CAUSE_REDIAL);
	T_EQ_STR(rl_outage_cause_name(c), "redial");
}

/* Three failed rounds start an outage dated at the first; any answer ends it. */
static void test_outage_rounds(void)
{
	rl_outage o = { 0 };
	rl_outage_event ev;
	ev = rl_outage_round(&o, 100, 3, 0);
	T_ASSERT(!ev.started);
	ev = rl_outage_round(&o, 110, 3, 0);
	T_ASSERT(!ev.started);
	ev = rl_outage_round(&o, 120, 3, 0);
	T_ASSERT(ev.started);
	T_EQ_I64(ev.start, 100);
	ev = rl_outage_round(&o, 130, 3, 0);
	T_ASSERT(!ev.started && !ev.ended);
	ev = rl_outage_round(&o, 140, 3, 1);
	T_ASSERT(ev.ended);
	T_EQ_I64(ev.start, 100);
	T_EQ_I64(ev.end, 140);
	T_EQ_I64(ev.cause, RL_CAUSE_UPSTREAM);

	/* Two failed rounds then an answer: nothing. */
	rl_outage_round(&o, 200, 3, 0);
	rl_outage_round(&o, 210, 3, 0);
	ev = rl_outage_round(&o, 220, 3, 2);
	T_ASSERT(!ev.started && !ev.ended);
	ev = rl_outage_round(&o, 230, 3, 0);
	T_ASSERT(!ev.started);
}

/* The next hop alone never declares an outage, and removing the custom targets ends one. */
static void test_outage_needs_custom_targets(void)
{
	rl_outage o = { 0 };
	for (int i = 0; i < 10; i++)
		T_ASSERT(!rl_outage_round(&o, 100 + 10 * i, 0, 0).started);
	for (int i = 0; i < 3; i++)
		rl_outage_round(&o, 300 + 10 * i, 2, 0);
	T_ASSERT(o.down);
	rl_outage_event ev = rl_outage_round(&o, 340, 0, 0);
	T_ASSERT(ev.ended);
	T_EQ_I64(ev.end, 340);
}

static void test_outage_causes(void)
{
	rl_outage o = { 0 };
	rl_outage_event ev;

	/* ifdown just before the probes failed, ifup 25 s later: a reconnect. */
	rl_outage_wan(&o, false, 995);
	for (int i = 0; i < 3; i++)
		rl_outage_round(&o, 1000 + 10 * i, 3, 0);
	rl_outage_wan(&o, true, 1020);
	ev = rl_outage_round(&o, 1040, 3, 3);
	T_EQ_I64(ev.cause, RL_CAUSE_REDIAL);

	/* Down for five minutes: the WAN was disconnected. */
	rl_outage_wan(&o, false, 2000);
	for (int i = 0; i < 30; i++)
		rl_outage_round(&o, 2005 + 10 * i, 3, 0);
	rl_outage_wan(&o, true, 2300);
	ev = rl_outage_round(&o, 2310, 3, 1);
	T_EQ_I64(ev.cause, RL_CAUSE_WAN_DOWN);

	/* An old ifdown does not explain a later outage. */
	for (int i = 0; i < 3; i++)
		rl_outage_round(&o, 5000 + 10 * i, 3, 0);
	ev = rl_outage_round(&o, 5100, 3, 1);
	T_EQ_I64(ev.cause, RL_CAUSE_UPSTREAM);

	/* Still down when the daemon stops: the outage ends there, WAN never came back. */
	rl_outage_wan(&o, false, 6000);
	for (int i = 0; i < 3; i++)
		rl_outage_round(&o, 6000 + 10 * i, 3, 0);
	ev = rl_outage_stop(&o, 6500);
	T_ASSERT(ev.ended);
	T_EQ_I64(ev.end, 6500);
	T_EQ_I64(ev.cause, RL_CAUSE_WAN_DOWN);
	T_ASSERT(!rl_outage_stop(&o, 6600).ended);
}

int main(void)
{
	T_RUN(test_agg);
	T_RUN(test_record_roundtrip);
	T_RUN(test_outage_rounds);
	T_RUN(test_outage_needs_custom_targets);
	T_RUN(test_outage_causes);
	T_DONE();
}
