/*
 * DNS log records (design §10, P4 plan §0.5) in dns.log, a core/vlog: one record per answer a LAN device got,
 * with the name it asked for, the type, the response code and the addresses.
 *
 * Record: ts u32 | mac 6 | qtype u16 | rcode u8 | name length u8 | name | count u8 | per address:
 * family u8 | addr 4/16.
 */
#ifndef RL_DNSLOG_H
#define RL_DNSLOG_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/dns.h"

/* vlog kinds of dns.log and dest.log */
#define RL_DNSLOG_KIND 0x4401
#define RL_DESTLOG_KIND 0x4402

#define RL_DNSLOG_REC_MAX (4 + 6 + 2 + 1 + 1 + RL_DNS_NAME_MAX + 1 + RL_DNS_MAX_ADDRS * 17)

typedef struct {
	int64_t ts;
	uint8_t mac[6];
	uint16_t qtype;
	uint8_t rcode;
	char name[RL_DNS_NAME_MAX + 1];
	int n_addrs;
	rl_dns_addr addrs[RL_DNS_MAX_ADDRS]; /* ttl is not kept */
} rl_dnslog_rec;

/* The record of an answer; returns its length (at most RL_DNSLOG_REC_MAX), 0 when size is too small. */
size_t rl_dnslog_encode(uint8_t *out, size_t size, const rl_dnslog_rec *r);
/* 0, or -1 when the record is malformed. */
int rl_dnslog_decode(const uint8_t *rec, size_t len, rl_dnslog_rec *out);
/* mac NULL = any device; q: lower-case substring of the name, NULL or "" = any. */
bool rl_dnslog_match(const rl_dnslog_rec *r, const uint8_t *mac, const char *q);

#endif
