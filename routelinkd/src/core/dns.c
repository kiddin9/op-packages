#include "core/dns.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_JUMPS 16

static uint16_t be16(const uint8_t *p)
{
	return (uint16_t)(p[0] << 8 | p[1]);
}

static uint32_t be32(const uint8_t *p)
{
	return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

/*
 * Reads the name at *off into out (lower case, dotted) and moves *off past it. Pointers must point to
 * earlier offsets, so a crafted loop cannot spin. -1 on anything malformed.
 */
static int read_name(const uint8_t *p, size_t len, size_t *off, char *out)
{
	size_t pos = *off, n = 0;
	size_t end = 0; /* where the caller continues: after the first pointer, or after the name */
	int jumps = 0;
	for (;;) {
		if (pos >= len)
			return -1;
		uint8_t l = p[pos];
		if ((l & 0xc0) == 0xc0) {
			if (pos + 1 >= len || ++jumps > MAX_JUMPS)
				return -1;
			size_t target = (size_t)(l & 0x3f) << 8 | p[pos + 1];
			if (target >= pos)
				return -1;
			if (!end)
				end = pos + 2;
			pos = target;
			continue;
		}
		if (l & 0xc0)
			return -1; /* extended label types */
		pos++;
		if (l == 0)
			break;
		if (pos + l > len || n + l + 1 > RL_DNS_NAME_MAX)
			return -1;
		if (n)
			out[n++] = '.';
		for (uint8_t i = 0; i < l; i++) {
			unsigned char ch = p[pos + i];
			out[n++] = (char)(ch >= 0x20 && ch < 0x7f && ch != '\\' ? tolower(ch) : '?');
		}
		pos += l;
	}
	out[n] = '\0';
	*off = end ? end : pos;
	return 0;
}

/*
 * Only what host names are made of: letters (already lower case), digits, '-', '_', '.' and '*'. A name with
 * anything else is not kept, so markup a device puts into a lookup never reaches the log or a page.
 */
static bool host_chars(const char *s)
{
	for (; *s; s++)
		if (!((*s >= 'a' && *s <= 'z') || (*s >= '0' && *s <= '9') || *s == '-' || *s == '_' || *s == '.' ||
		      *s == '*'))
			return false;
	return true;
}

int rl_dns_parse(const uint8_t *p, size_t len, rl_dns_msg *m)
{
	memset(m, 0, sizeof(*m));
	if (len < 12)
		return -1;
	m->id = be16(p);
	uint16_t flags = be16(p + 2);
	m->response = flags & 0x8000;
	m->rcode = flags & 0xf;
	m->truncated = flags & 0x0200;
	uint16_t qd = be16(p + 4), an = be16(p + 6);
	if (qd < 1)
		return -1;
	size_t off = 12;
	if (read_name(p, len, &off, m->qname) < 0 || off + 4 > len || !host_chars(m->qname))
		return -1;
	m->qtype = be16(p + off);
	off += 4;
	/* Further questions (practically never) are skipped. */
	for (int i = 1; i < qd; i++) {
		char skip[RL_DNS_NAME_MAX + 1];
		if (read_name(p, len, &off, skip) < 0 || off + 4 > len)
			return -1;
		off += 4;
	}
	if (!m->response)
		return 0;
	for (int i = 0; i < an; i++) {
		char owner[RL_DNS_NAME_MAX + 1];
		if (read_name(p, len, &off, owner) < 0 || off + 10 > len) {
			m->truncated = true;
			break;
		}
		uint16_t type = be16(p + off), cls = be16(p + off + 2);
		uint32_t ttl = be32(p + off + 4);
		uint16_t rdlen = be16(p + off + 8);
		off += 10;
		if (off + rdlen > len) {
			m->truncated = true;
			break;
		}
		if (cls == 1 && type == RL_DNS_A && rdlen == 4 && m->n_addrs < RL_DNS_MAX_ADDRS) {
			rl_dns_addr *a = &m->addrs[m->n_addrs++];
			a->family = 4;
			memcpy(a->addr, p + off, 4);
			a->ttl = ttl;
		} else if (cls == 1 && type == RL_DNS_AAAA && rdlen == 16 && m->n_addrs < RL_DNS_MAX_ADDRS) {
			rl_dns_addr *a = &m->addrs[m->n_addrs++];
			a->family = 6;
			memcpy(a->addr, p + off, 16);
			a->ttl = ttl;
		} else if (cls == 1 && type == RL_DNS_CNAME && !m->cname[0]) {
			size_t at = off;
			if (read_name(p, off + rdlen, &at, m->cname) < 0 || !host_chars(m->cname))
				m->cname[0] = '\0';
		}
		off += rdlen;
	}
	return 0;
}

const char *rl_dns_type_name(uint16_t type, char *buf)
{
	switch (type) {
	case RL_DNS_A:
		return "A";
	case RL_DNS_AAAA:
		return "AAAA";
	case RL_DNS_CNAME:
		return "CNAME";
	case RL_DNS_HTTPS:
		return "HTTPS";
	case 2:
		return "NS";
	case 6:
		return "SOA";
	case 12:
		return "PTR";
	case 15:
		return "MX";
	case 16:
		return "TXT";
	case 33:
		return "SRV";
	case 64:
		return "SVCB";
	default:
		snprintf(buf, 8, "%u", type);
		return buf;
	}
}

const char *rl_dns_rcode_name(uint8_t rcode)
{
	static const char *names[] = { "NOERROR", "FORMERR", "SERVFAIL", "NXDOMAIN", "NOTIMP", "REFUSED" };
	return rcode < 6 ? names[rcode] : "ERROR";
}

/* ---- cache: open addressing on the address, FIFO eviction through a ring of slots ---- */

typedef struct {
	bool used;
	uint8_t family;
	uint8_t addr[16];
	int64_t expires;
	uint64_t seq;
	char name[RL_DNS_NAME_MAX + 1];
} entry;

struct rl_dns_cache {
	entry *slots;
	size_t cap, n;
	uint64_t seq;
};

rl_dns_cache *rl_dns_cache_new(size_t capacity)
{
	rl_dns_cache *c = calloc(1, sizeof(*c));
	if (!c)
		return NULL;
	c->cap = capacity < 8 ? 8 : capacity;
	c->slots = calloc(c->cap * 2, sizeof(entry)); /* load factor ≤ 0.5 */
	if (!c->slots) {
		free(c);
		return NULL;
	}
	return c;
}

void rl_dns_cache_free(rl_dns_cache *c)
{
	if (!c)
		return;
	free(c->slots);
	free(c);
}

static size_t hash(uint8_t family, const uint8_t *addr)
{
	uint64_t h = 1469598103934665603ull ^ family;
	for (int i = 0; i < (family == 6 ? 16 : 4); i++)
		h = (h ^ addr[i]) * 1099511628211ull;
	return (size_t)h;
}

static bool same(const entry *e, uint8_t family, const uint8_t *addr)
{
	return e->used && e->family == family && memcmp(e->addr, addr, family == 6 ? 16 : 4) == 0;
}

static entry *find(rl_dns_cache *c, uint8_t family, const uint8_t *addr)
{
	size_t size = c->cap * 2;
	for (size_t i = 0, at = hash(family, addr) % size; i < size; i++, at = (at + 1) % size) {
		if (!c->slots[at].used)
			return NULL;
		if (same(&c->slots[at], family, addr))
			return &c->slots[at];
	}
	return NULL;
}

/* Removes slot `at` and moves later members of its probe chain back (linear-probing deletion). */
static void remove_at(rl_dns_cache *c, size_t at)
{
	size_t size = c->cap * 2;
	c->slots[at].used = false;
	c->n--;
	for (size_t next = (at + 1) % size; c->slots[next].used; next = (next + 1) % size) {
		entry e = c->slots[next];
		c->slots[next].used = false;
		c->n--;
		size_t to = hash(e.family, e.addr) % size;
		while (c->slots[to].used)
			to = (to + 1) % size;
		c->slots[to] = e;
		c->n++;
	}
}

static void evict(rl_dns_cache *c, int64_t now)
{
	size_t size = c->cap * 2, oldest = SIZE_MAX;
	for (size_t i = 0; i < size; i++) {
		if (!c->slots[i].used)
			continue;
		if (c->slots[i].expires <= now) {
			remove_at(c, i);
			return;
		}
		if (oldest == SIZE_MAX || c->slots[i].seq < c->slots[oldest].seq)
			oldest = i;
	}
	if (oldest != SIZE_MAX)
		remove_at(c, oldest);
}

void rl_dns_cache_put(rl_dns_cache *c, uint8_t family, const uint8_t *addr, const char *name, int64_t now,
		      int64_t expires)
{
	if (family != 4 && family != 6)
		return;
	entry *e = find(c, family, addr);
	if (!e) {
		if (c->n >= c->cap)
			evict(c, now);
		size_t size = c->cap * 2, at = hash(family, addr) % size;
		while (c->slots[at].used)
			at = (at + 1) % size;
		e = &c->slots[at];
		memset(e, 0, sizeof(*e));
		e->used = true;
		e->family = family;
		memcpy(e->addr, addr, family == 6 ? 16 : 4);
		c->n++;
	}
	e->expires = expires;
	e->seq = ++c->seq;
	snprintf(e->name, sizeof(e->name), "%s", name);
}

const char *rl_dns_cache_get(rl_dns_cache *c, uint8_t family, const uint8_t *addr, int64_t now)
{
	entry *e = (family == 4 || family == 6) ? find(c, family, addr) : NULL;
	return e && e->expires > now ? e->name : NULL;
}

size_t rl_dns_cache_size(const rl_dns_cache *c)
{
	return c->n;
}
