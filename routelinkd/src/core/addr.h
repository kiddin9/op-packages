/* MAC/IP values and CIDR sets. */
#ifndef RL_ADDR_H
#define RL_ADDR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct { uint8_t b[6]; } rl_mac;
/* family is 4 or 6; IPv4 uses a[0..3], the rest stays zero. */
typedef struct { uint8_t family; uint8_t a[16]; } rl_ip;
typedef struct { rl_ip net; uint8_t prefix; } rl_cidr;
typedef struct { rl_cidr *items; size_t n, cap; } rl_cidr_set;

#define RL_MAC_STRLEN 18
#define RL_IP_STRLEN 46

bool rl_mac_parse(const char *s, rl_mac *out);
void rl_mac_format(const rl_mac *m, char out[RL_MAC_STRLEN]);
bool rl_mac_is_random(const rl_mac *m);
bool rl_mac_eq(const rl_mac *a, const rl_mac *b);
bool rl_mac_is_zero(const rl_mac *m);
uint32_t rl_mac_hash(const rl_mac *m);

bool rl_ip_parse(const char *s, rl_ip *out);
void rl_ip_from_v4(uint32_t be_addr, rl_ip *out);
void rl_ip_from_v6(const uint8_t a[16], rl_ip *out);
void rl_ip_format(const rl_ip *ip, char out[RL_IP_STRLEN]);
bool rl_ip_eq(const rl_ip *a, const rl_ip *b);
uint32_t rl_ip_hash(const rl_ip *ip);

/* Adds net/prefix (host bits are masked off); duplicates are ignored. */
void rl_cidr_set_add(rl_cidr_set *s, const rl_ip *ip, uint8_t prefix);
/* Parses "a.b.c.d/nn" or "x::/nn" (no prefix means a host route). */
bool rl_cidr_set_add_str(rl_cidr_set *s, const char *cidr);
bool rl_cidr_set_contains(const rl_cidr_set *s, const rl_ip *ip);
void rl_cidr_set_clear(rl_cidr_set *s);
void rl_cidr_set_free(rl_cidr_set *s);

#endif
