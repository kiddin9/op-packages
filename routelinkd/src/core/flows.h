/* Per-connection byte counters from conntrack, turned into deltas without zeroing the kernel counters. */
#ifndef RL_FLOWS_H
#define RL_FLOWS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/addr.h"

/* One conntrack entry as read from a dump or a DESTROY event. */
typedef struct {
	uint32_t ct_id;
	uint32_t tuple_hash; /* rl_flows_tuple_hash(): guards against ct id reuse */
	rl_ip orig_src, orig_dst, reply_src, reply_dst;
	uint16_t orig_sport, orig_dport; /* host order; 0 for protocols without ports */
	uint8_t l4proto;
	uint64_t orig_bytes, reply_bytes;
	uint64_t orig_pkts, reply_pkts;
} rl_ct_sample;

typedef struct {
	uint64_t orig_bytes, reply_bytes;
} rl_delta;

typedef struct rl_flows rl_flows;

rl_flows *rl_flows_new(void);
void rl_flows_free(rl_flows *f);

/* Hash of the original-direction 5-tuple. */
uint32_t rl_flows_tuple_hash(const rl_ct_sample *s);

/*
 * Starts a dump pass. With baseline set (the first pass after start-up), counters are only recorded:
 * bytes from before the daemon started must not land in the current bucket.
 */
void rl_flows_begin(rl_flows *f, bool baseline);

/*
 * A flow seen in a dump. Returns the bytes since it was last seen (all bytes the first time, unless the
 * pass is a baseline). A counter that went backwards (someone zeroed it) yields 0 and becomes the new
 * reference. *tag points at a per-flow value the caller may use (0 until set).
 */
rl_delta rl_flows_update(rl_flows *f, const rl_ct_sample *s, uint64_t **tag);

/* A DESTROY event: returns the final delta and the flow's tag (0 if never seen), then forgets it. */
rl_delta rl_flows_destroy(rl_flows *f, const rl_ct_sample *s, uint64_t *tag);

/* Ends a dump pass: drops flows missing from this and the previous pass (their DESTROY was lost). */
size_t rl_flows_sweep(rl_flows *f);

size_t rl_flows_count(const rl_flows *f);

/* Calls fn for every live flow (used to count connections per device). */
void rl_flows_each(const rl_flows *f, void (*fn)(uint64_t tag, void *ctx), void *ctx);

#endif
