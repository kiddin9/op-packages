/*
 * DNS logging (design §10, P4): parsing queries and answers captured on the LAN bridge, and the
 * "address → name" cache the destination log uses. Parsing never trusts the packet: every read is bounds
 * checked, compression pointers may only point backwards and are followed a limited number of times.
 */
#ifndef RL_DNS_H
#define RL_DNS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define RL_DNS_NAME_MAX 254 /* dotted, without the trailing dot */
#define RL_DNS_MAX_ADDRS 8

enum { RL_DNS_A = 1, RL_DNS_CNAME = 5, RL_DNS_AAAA = 28, RL_DNS_HTTPS = 65 };

typedef struct {
	uint8_t family; /* 4 or 6 */
	uint8_t addr[16];
	uint32_t ttl;
} rl_dns_addr;

typedef struct {
	uint16_t id;
	bool response;
	uint8_t rcode;
	uint16_t qtype;
	/* Lower case, only letters, digits and "-_.*": a question with any other byte fails to parse. */
	char qname[RL_DNS_NAME_MAX + 1];
	/* First CNAME target in the answer (same characters), "" when none. */
	char cname[RL_DNS_NAME_MAX + 1];
	int n_addrs;
	rl_dns_addr addrs[RL_DNS_MAX_ADDRS];
	/* The answer section was cut short (truncated packet or TC bit); what was read is kept. */
	bool truncated;
} rl_dns_msg;

/* A DNS message (UDP payload, or a TCP segment's message without the 2-byte length). 0 or -1. */
int rl_dns_parse(const uint8_t *p, size_t len, rl_dns_msg *out);
/* "A", "AAAA", …, or the number. buf holds at least 8 bytes. */
const char *rl_dns_type_name(uint16_t type, char *buf);
const char *rl_dns_rcode_name(uint8_t rcode);

/* Address → name cache with TTL expiry, fixed capacity, least recently stored entries go first. */
typedef struct rl_dns_cache rl_dns_cache;
rl_dns_cache *rl_dns_cache_new(size_t capacity);
void rl_dns_cache_free(rl_dns_cache *c);
/* At capacity an expired entry makes room, otherwise the one stored longest ago. */
void rl_dns_cache_put(rl_dns_cache *c, uint8_t family, const uint8_t *addr, const char *name, int64_t now,
		      int64_t expires);
/* Name for an address still valid at now, NULL otherwise. */
const char *rl_dns_cache_get(rl_dns_cache *c, uint8_t family, const uint8_t *addr, int64_t now);
size_t rl_dns_cache_size(const rl_dns_cache *c);

#endif
