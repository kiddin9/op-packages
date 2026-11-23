/*
 * DNS log and destinations (design §10, P4 plan §0.5–0.6). While DNS logging is on, sys/dnscap's answers
 * go to dns.log (core/dnslog records in a core/vlog) and to an address → name cache; the traffic accounting
 * reports every device's internet traffic per peer address, summed per hour (core/dest) and written to
 * dest.log when the hour ends, named from the cache. Both logs reach the disk with the daemon's commits; the
 * DNS log also whenever RL_VISITS_DNS_PENDING records wait.
 */
#ifndef RL_VISITS_H
#define RL_VISITS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/addr.h"
#include "core/dest.h"
#include "core/dnslog.h"

#define RL_VISITS_DNS_PENDING 2000 /* DNS records kept in memory before they are written */
#define RL_VISITS_CACHE 4096       /* address → name cache entries */
#define RL_VISITS_MAX_DEVICES 64   /* devices with destinations summed in one hour */
#define RL_VISITS_PEERS 256        /* peers per device and hour */

typedef struct rl_visits rl_visits;

/* Opens dns.log and dest.log in dir; *recovered when a damaged file was replaced. NULL on failure. */
rl_visits *rl_visits_open(const char *dir, bool *recovered);
/* The open hour is lost unless rl_visits_commit(v, true) ran before. */
void rl_visits_close(rl_visits *v);

/* Logging on (capturing on these LAN interfaces) or off. */
void rl_visits_enable(rl_visits *v, bool on, const int *ifindex, int n);
bool rl_visits_on(const rl_visits *v);
/* Records may be written (the clock is trusted). */
void rl_visits_writable(rl_visits *v, bool writable);

/* Internet traffic of a device to a peer; conns counts connections seen for the first time. */
void rl_visits_traffic(rl_visits *v, const rl_mac *mac, const rl_ip *peer, uint64_t rx, uint64_t tx, uint32_t conns,
		       int64_t now);
/* Writes the destinations of an hour that ended. */
void rl_visits_tick(rl_visits *v, int64_t now);
/* Appends pending records to disk; flush also writes the open hour's destinations first. */
int rl_visits_commit(rl_visits *v, bool flush);
/* Keeps keep_days, at most max_dns DNS records, and both logs within max_bytes together. */
void rl_visits_compact(rl_visits *v, int64_t now, int keep_days, uint64_t max_dns, uint64_t max_bytes);
uint64_t rl_visits_bytes(const rl_visits *v);
/* Empties both logs and the open hour. */
void rl_visits_reset(rl_visits *v);

/* DNS records with start <= ts < end, newest first; cb returns false to stop. */
typedef bool (*rl_visits_dns_cb)(const rl_dnslog_rec *r, void *ctx);
int rl_visits_dns_scan(rl_visits *v, int64_t start, int64_t end, rl_visits_dns_cb cb, void *ctx);
uint64_t rl_visits_dns_count(const rl_visits *v);
/*
 * The busiest destinations of mac in the hours overlapping [start, end) (open hour included), at most n,
 * busiest first. -1 on a read error.
 */
int rl_visits_destinations(rl_visits *v, const rl_mac *mac, int64_t start, int64_t end, rl_dest_entry *out, size_t n,
			   size_t *found);

#endif
