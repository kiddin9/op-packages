/*
 * Latency probes and outages (design §5.3, P3): per-target aggregation of echo replies into minute and hour
 * records, and the outage state machine. An outage starts when every target except the WAN's next hop has
 * failed 3 rounds in a row and ends when any of them answers; netifd's WAN events give the cause. Without
 * custom targets nothing is ever declared down. Pure: the daemon feeds rounds and events, writes records.
 */
#ifndef RL_PROBE_H
#define RL_PROBE_H

#include <stdbool.h>
#include <stdint.h>

#define RL_PROBE_MAX_TARGETS 8
#define RL_OUTAGE_ROUNDS 3
/* A WAN that was down longer than this was disconnected; shorter was a reconnect (redial). */
#define RL_REDIAL_MAX_SEC 60

typedef struct {
	uint32_t sent, lost;
	uint64_t sum_us; /* over answered probes */
	uint32_t min_us, max_us;
} rl_probe_agg;

void rl_probe_agg_add(rl_probe_agg *a, bool answered, uint32_t rtt_us);
void rl_probe_agg_merge(rl_probe_agg *into, const rl_probe_agg *from);
/* Average round trip in µs, 0 when nothing answered. */
uint32_t rl_probe_agg_avg(const rl_probe_agg *a);

/*
 * Latency record (32 bytes, core/series): ts u32 | target u8 | 3 reserved | sent u32 | lost u32 |
 * avg_us u32 | min_us u32 | max_us u32 | 4 reserved.
 */
void rl_probe_encode(uint8_t rec[32], int64_t ts, int target, const rl_probe_agg *a);
void rl_probe_decode(const uint8_t rec[32], int64_t *ts, int *target, rl_probe_agg *a);

typedef enum { RL_CAUSE_UPSTREAM, RL_CAUSE_WAN_DOWN, RL_CAUSE_REDIAL } rl_outage_cause;
const char *rl_outage_cause_name(rl_outage_cause c);

typedef struct {
	int failed_rounds;
	int64_t first_failed; /* ts of the first round of the current failed run */
	bool down;
	int64_t start;
	/* Last WAN ifdown / ifup seen from netifd, 0 = never. */
	int64_t wan_down_at, wan_up_at;
} rl_outage;

typedef struct {
	bool started; /* an outage was just declared (start set) */
	bool ended;   /* an outage just ended (start, end, cause set) */
	int64_t start, end;
	rl_outage_cause cause;
} rl_outage_event;

/*
 * One probe round at ts: how many custom targets (not the next hop) were probed and how many answered.
 * The outage starts at the first failed round of the run that reached RL_OUTAGE_ROUNDS.
 */
rl_outage_event rl_outage_round(rl_outage *o, int64_t ts, int custom_targets, int custom_answered);
/* netifd ifup/ifdown of the WAN interface. */
void rl_outage_wan(rl_outage *o, bool up, int64_t ts);
/* The daemon is stopping (or probing is switched off): an ongoing outage ends at ts. */
rl_outage_event rl_outage_stop(rl_outage *o, int64_t ts);
/* The cause the ongoing outage would get if it ended at ts. */
rl_outage_cause rl_outage_cause_at(const rl_outage *o, int64_t ts);

/* Outage record (32 bytes): start u32 | end u32 | cause u8 | 23 reserved. */
void rl_outage_encode(uint8_t rec[32], int64_t start, int64_t end, rl_outage_cause cause);
void rl_outage_decode(const uint8_t rec[32], int64_t *start, int64_t *end, rl_outage_cause *cause);

#endif
