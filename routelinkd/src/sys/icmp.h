/*
 * ICMP and ICMPv6 echo probes over raw sockets on uloop (design §5.3, P3 plan §0.1). A round sends one echo
 * request to each target and reports once every target answered or the timeout passed; replies are matched
 * by identifier, sequence number and source address. Raw sockets need CAP_NET_RAW (root on OpenWrt).
 */
#ifndef RL_ICMP_H
#define RL_ICMP_H

#include <stdbool.h>
#include <stdint.h>

#include "core/addr.h"

#define RL_ICMP_MAX 16 /* probes per round */

typedef struct {
	rl_ip ip;
	int scope; /* interface index for a link-local IPv6 address, else 0 */
	int tag;   /* the caller's (target id) */
	bool answered;
	uint32_t rtt_us;
} rl_icmp_probe;

typedef struct rl_icmp rl_icmp;
/* A round ended: every probe answered or timed out. A probe that could not be sent counts as lost. */
typedef void (*rl_icmp_cb)(const rl_icmp_probe *p, int n, void *ctx);

/* Opens the IPv4 and IPv6 sockets (targets of a family whose socket failed count as lost); NULL when neither
 * opens (errno tells why). */
rl_icmp *rl_icmp_open(rl_icmp_cb cb, void *ctx);
void rl_icmp_close(rl_icmp *ic);
/* Starts a round of n probes (at most RL_ICMP_MAX); a round still running is dropped without a report. */
void rl_icmp_round(rl_icmp *ic, const rl_icmp_probe *p, int n, int timeout_ms);
bool rl_icmp_busy(const rl_icmp *ic);
/* Drops a running round without a report. */
void rl_icmp_cancel(rl_icmp *ic);

#endif
