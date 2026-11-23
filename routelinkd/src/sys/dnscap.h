/*
 * DNS answers captured on the LAN (design §10, P4 plan §0.5): one AF_PACKET socket per LAN interface (the
 * bridge), a BPF filter that passes only packets the router sends with UDP or TCP source port 53, so the
 * answers that go to LAN devices (from the router's resolver or forwarded from outside). Over TCP only
 * whole messages within one segment are read. The destination MAC is the device that asked.
 */
#ifndef RL_DNSCAP_H
#define RL_DNSCAP_H

#include <stdint.h>

#include "core/dns.h"

#define RL_DNSCAP_MAX_IFACES 16

typedef void (*rl_dnscap_cb)(const uint8_t client_mac[6], const rl_dns_msg *m, void *ctx);

typedef struct rl_dnscap rl_dnscap;

rl_dnscap *rl_dnscap_new(rl_dnscap_cb cb, void *ctx);
void rl_dnscap_free(rl_dnscap *c);
/* Captures on these interfaces (duplicates ignored); sockets are opened and closed to match. 0 or -1. */
int rl_dnscap_set_ifaces(rl_dnscap *c, const int *ifindex, int n);
/* Answers parsed so far, and packets that did not parse. */
uint64_t rl_dnscap_answers(const rl_dnscap *c);
uint64_t rl_dnscap_bad(const rl_dnscap *c);

#endif
