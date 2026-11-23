/* conntrack over ctnetlink (libmnl): full dumps and DESTROY events, counters are never zeroed. */
#ifndef RL_CT_H
#define RL_CT_H

#include <stdbool.h>
#include <stdint.h>

#include "core/flows.h"

typedef struct rl_ct rl_ct;
typedef void (*rl_ct_cb)(const rl_ct_sample *s, bool destroyed, void *ctx);

rl_ct *rl_ct_open(rl_ct_cb cb, void *ctx);
void rl_ct_close(rl_ct *c);
/* Event socket for uloop. */
int rl_ct_event_fd(const rl_ct *c);
/* Drains pending DESTROY events. Returns true when events were lost (a dump should follow). */
bool rl_ct_on_readable(rl_ct *c);
/* Reports every current entry through the callback; returns the number of entries or -1. */
int rl_ct_dump(rl_ct *c);
uint64_t rl_ct_events_lost(const rl_ct *c);
/* nf_conntrack_acct: without it every counter stays 0. */
bool rl_ct_accounting(void);
/*
 * Deletes the conntrack entries of these addresses (connections they opened or that were forwarded to
 * them), so that established and offloaded connections of a blocked device stop. Returns how many were
 * deleted, -1 on failure. Uses its own socket.
 */
int rl_ct_kill(const rl_ip *ips, size_t n_ips);

#endif
