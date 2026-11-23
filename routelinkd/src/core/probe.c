#include "core/probe.h"

#include <string.h>

#include "core/series.h"

void rl_probe_agg_add(rl_probe_agg *a, bool answered, uint32_t rtt_us)
{
	a->sent++;
	if (!answered) {
		a->lost++;
		return;
	}
	if (a->sent - a->lost == 1 || rtt_us < a->min_us)
		a->min_us = rtt_us;
	if (rtt_us > a->max_us)
		a->max_us = rtt_us;
	a->sum_us += rtt_us;
}

void rl_probe_agg_merge(rl_probe_agg *into, const rl_probe_agg *from)
{
	bool had = into->sent > into->lost, has = from->sent > from->lost;
	if (has && (!had || from->min_us < into->min_us))
		into->min_us = from->min_us;
	if (from->max_us > into->max_us)
		into->max_us = from->max_us;
	into->sent += from->sent;
	into->lost += from->lost;
	into->sum_us += from->sum_us;
}

uint32_t rl_probe_agg_avg(const rl_probe_agg *a)
{
	uint32_t answered = a->sent - a->lost;
	return answered ? (uint32_t)(a->sum_us / answered) : 0;
}

void rl_probe_encode(uint8_t rec[32], int64_t ts, int target, const rl_probe_agg *a)
{
	memset(rec, 0, 32);
	rl_le_put32(rec, (uint32_t)ts);
	rec[4] = (uint8_t)target;
	rl_le_put32(rec + 8, a->sent);
	rl_le_put32(rec + 12, a->lost);
	rl_le_put32(rec + 16, rl_probe_agg_avg(a));
	rl_le_put32(rec + 20, a->min_us);
	rl_le_put32(rec + 24, a->max_us);
}

void rl_probe_decode(const uint8_t rec[32], int64_t *ts, int *target, rl_probe_agg *a)
{
	*ts = rl_series_ts(rec);
	*target = rec[4];
	a->sent = rl_le_get32(rec + 8);
	a->lost = rl_le_get32(rec + 12);
	a->sum_us = (uint64_t)rl_le_get32(rec + 16) * (a->sent - a->lost);
	a->min_us = rl_le_get32(rec + 20);
	a->max_us = rl_le_get32(rec + 24);
}

const char *rl_outage_cause_name(rl_outage_cause c)
{
	switch (c) {
	case RL_CAUSE_WAN_DOWN:
		return "wan_down";
	case RL_CAUSE_REDIAL:
		return "redial";
	default:
		return "upstream";
	}
}

/*
 * A WAN ifdown from shortly before the first failed round up to the end explains the outage: a short
 * one followed by ifup was a reconnect, otherwise the WAN was disconnected.
 */
static rl_outage_cause cause_of(const rl_outage *o, int64_t end)
{
	int64_t from = o->start - 30;
	if (!o->wan_down_at || o->wan_down_at < from || o->wan_down_at > end)
		return RL_CAUSE_UPSTREAM;
	if (o->wan_up_at >= o->wan_down_at && o->wan_up_at - o->wan_down_at <= RL_REDIAL_MAX_SEC)
		return RL_CAUSE_REDIAL;
	return RL_CAUSE_WAN_DOWN;
}

static rl_outage_event finish(rl_outage *o, int64_t end)
{
	rl_outage_event ev = { .ended = true, .start = o->start, .end = end, .cause = cause_of(o, end) };
	o->down = false;
	o->failed_rounds = 0;
	return ev;
}

rl_outage_event rl_outage_round(rl_outage *o, int64_t ts, int custom_targets, int custom_answered)
{
	rl_outage_event none = { 0 };
	if (custom_targets <= 0) {
		/* Only the next hop is probed: it can't tell an outage from a dead first hop. */
		return o->down ? finish(o, ts) : (o->failed_rounds = 0, none);
	}
	if (custom_answered > 0) {
		if (o->down)
			return finish(o, ts);
		o->failed_rounds = 0;
		return none;
	}
	if (o->failed_rounds++ == 0)
		o->first_failed = ts;
	if (!o->down && o->failed_rounds >= RL_OUTAGE_ROUNDS) {
		o->down = true;
		o->start = o->first_failed;
		return (rl_outage_event){ .started = true, .start = o->start };
	}
	return none;
}

void rl_outage_wan(rl_outage *o, bool up, int64_t ts)
{
	if (up)
		o->wan_up_at = ts;
	else
		o->wan_down_at = ts;
}

rl_outage_cause rl_outage_cause_at(const rl_outage *o, int64_t ts)
{
	return cause_of(o, ts);
}

rl_outage_event rl_outage_stop(rl_outage *o, int64_t ts)
{
	rl_outage_event none = { 0 };
	o->failed_rounds = 0;
	return o->down ? finish(o, ts) : none;
}

void rl_outage_encode(uint8_t rec[32], int64_t start, int64_t end, rl_outage_cause cause)
{
	memset(rec, 0, 32);
	rl_le_put32(rec, (uint32_t)start);
	rl_le_put32(rec + 4, (uint32_t)end);
	rec[8] = (uint8_t)cause;
}

void rl_outage_decode(const uint8_t rec[32], int64_t *start, int64_t *end, rl_outage_cause *cause)
{
	*start = rl_series_ts(rec);
	*end = (int64_t)rl_le_get32(rec + 4);
	*cause = rec[8] <= RL_CAUSE_REDIAL ? (rl_outage_cause)rec[8] : RL_CAUSE_UPSTREAM;
}
