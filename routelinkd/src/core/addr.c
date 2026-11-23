#include <arpa/inet.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "core/addr.h"
#include "core/util.h"

static int hexval(int c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	c = tolower(c);
	return c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
}

bool rl_mac_parse(const char *s, rl_mac *out)
{
	if (!s || strlen(s) != 17)
		return false;
	for (int i = 0; i < 6; i++) {
		int hi = hexval(s[i * 3]), lo = hexval(s[i * 3 + 1]);
		if (hi < 0 || lo < 0)
			return false;
		if (i < 5 && s[i * 3 + 2] != ':' && s[i * 3 + 2] != '-')
			return false;
		out->b[i] = (uint8_t)(hi << 4 | lo);
	}
	return true;
}

void rl_mac_format(const rl_mac *m, char out[RL_MAC_STRLEN])
{
	snprintf(out, RL_MAC_STRLEN, "%02X:%02X:%02X:%02X:%02X:%02X", m->b[0], m->b[1], m->b[2], m->b[3], m->b[4],
		 m->b[5]);
}

bool rl_mac_is_random(const rl_mac *m)
{
	return (m->b[0] & 0x02) != 0;
}

bool rl_mac_eq(const rl_mac *a, const rl_mac *b)
{
	return memcmp(a->b, b->b, 6) == 0;
}

bool rl_mac_is_zero(const rl_mac *m)
{
	static const uint8_t zero[6];
	return memcmp(m->b, zero, 6) == 0;
}

uint32_t rl_mac_hash(const rl_mac *m)
{
	return rl_mix32(rl_fnv1a(m->b, 6, RL_FNV_SEED));
}

bool rl_ip_parse(const char *s, rl_ip *out)
{
	memset(out, 0, sizeof(*out));
	if (!s)
		return false;
	if (inet_pton(AF_INET, s, out->a) == 1) {
		out->family = 4;
		return true;
	}
	if (inet_pton(AF_INET6, s, out->a) == 1) {
		out->family = 6;
		return true;
	}
	return false;
}

void rl_ip_from_v4(uint32_t be_addr, rl_ip *out)
{
	memset(out, 0, sizeof(*out));
	out->family = 4;
	memcpy(out->a, &be_addr, 4);
}

void rl_ip_from_v6(const uint8_t a[16], rl_ip *out)
{
	out->family = 6;
	memcpy(out->a, a, 16);
}

void rl_ip_format(const rl_ip *ip, char out[RL_IP_STRLEN])
{
	if (!inet_ntop(ip->family == 4 ? AF_INET : AF_INET6, ip->a, out, RL_IP_STRLEN))
		out[0] = '\0';
}

bool rl_ip_eq(const rl_ip *a, const rl_ip *b)
{
	return a->family == b->family && memcmp(a->a, b->a, a->family == 4 ? 4 : 16) == 0;
}

uint32_t rl_ip_hash(const rl_ip *ip)
{
	return rl_mix32(rl_fnv1a(ip->a, ip->family == 4 ? 4 : 16, RL_FNV_SEED ^ ip->family));
}

static bool prefix_match(const rl_ip *net, const rl_ip *ip, uint8_t prefix)
{
	if (net->family != ip->family)
		return false;
	unsigned full = prefix / 8, rest = prefix % 8;
	if (memcmp(net->a, ip->a, full) != 0)
		return false;
	if (!rest)
		return true;
	uint8_t mask = (uint8_t)(0xff << (8 - rest));
	return (net->a[full] & mask) == (ip->a[full] & mask);
}

void rl_cidr_set_add(rl_cidr_set *s, const rl_ip *ip, uint8_t prefix)
{
	unsigned max = ip->family == 4 ? 32 : 128;
	rl_cidr c = { .net = *ip, .prefix = prefix > max ? max : prefix };
	for (unsigned bit = c.prefix; bit < max; bit++)
		c.net.a[bit / 8] &= (uint8_t) ~(0x80 >> (bit % 8));
	for (size_t i = 0; i < s->n; i++)
		if (s->items[i].prefix == c.prefix && rl_ip_eq(&s->items[i].net, &c.net))
			return;
	s->items = rl_grow(s->items, &s->cap, s->n + 1, sizeof(*s->items));
	s->items[s->n++] = c;
}

bool rl_cidr_set_add_str(rl_cidr_set *s, const char *cidr)
{
	char buf[64];
	rl_ip ip;
	long prefix = -1;
	snprintf(buf, sizeof(buf), "%s", cidr);
	char *slash = strchr(buf, '/');
	if (slash) {
		char *end;
		*slash = '\0';
		prefix = strtol(slash + 1, &end, 10);
		if (*end || prefix < 0)
			return false;
	}
	if (!rl_ip_parse(buf, &ip))
		return false;
	long max = ip.family == 4 ? 32 : 128;
	if (prefix > max)
		return false;
	rl_cidr_set_add(s, &ip, (uint8_t)(prefix < 0 ? max : prefix));
	return true;
}

bool rl_cidr_set_contains(const rl_cidr_set *s, const rl_ip *ip)
{
	for (size_t i = 0; i < s->n; i++)
		if (prefix_match(&s->items[i].net, ip, s->items[i].prefix))
			return true;
	return false;
}

void rl_cidr_set_clear(rl_cidr_set *s)
{
	s->n = 0;
}

void rl_cidr_set_free(rl_cidr_set *s)
{
	free(s->items);
	s->items = NULL;
	s->n = s->cap = 0;
}
