#include <stdlib.h>

#include "t.h"

#include "core/dns.h"

/* A tiny DNS message builder for the tests. */
typedef struct {
	uint8_t b[512];
	size_t n;
} msg;

static void u8(msg *m, unsigned v)
{
	m->b[m->n++] = (uint8_t)v;
}

static void u16(msg *m, unsigned v)
{
	u8(m, v >> 8);
	u8(m, v & 0xff);
}

static void u32(msg *m, uint32_t v)
{
	u16(m, v >> 16);
	u16(m, v & 0xffff);
}

static void name(msg *m, const char *dotted)
{
	const char *s = dotted;
	while (*s) {
		const char *dot = strchr(s, '.');
		size_t l = dot ? (size_t)(dot - s) : strlen(s);
		u8(m, (unsigned)l);
		memcpy(m->b + m->n, s, l);
		m->n += l;
		s += l + (dot ? 1 : 0);
	}
	u8(m, 0);
}

static void header(msg *m, unsigned flags, unsigned qd, unsigned an)
{
	m->n = 0;
	u16(m, 0x1234);
	u16(m, flags);
	u16(m, qd);
	u16(m, an);
	u16(m, 0);
	u16(m, 0);
}

static void test_query(void)
{
	msg m;
	header(&m, 0x0100, 1, 0);
	name(&m, "WWW.Example.COM");
	u16(&m, RL_DNS_AAAA);
	u16(&m, 1);
	rl_dns_msg d;
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), 0);
	T_ASSERT(!d.response);
	T_EQ_STR(d.qname, "www.example.com");
	T_EQ_I64(d.qtype, RL_DNS_AAAA);
	T_EQ_I64(d.id, 0x1234);
}

/* www.baidu.com → CNAME www.a.shifen.com → two A records, names compressed against the question. */
static void test_answer_with_compression(void)
{
	msg m;
	header(&m, 0x8180, 1, 3);
	name(&m, "www.baidu.com"); /* at offset 12 */
	u16(&m, RL_DNS_A);
	u16(&m, 1);
	/* CNAME: owner = pointer to 12 */
	u16(&m, 0xc00c);
	u16(&m, RL_DNS_CNAME);
	u16(&m, 1);
	u32(&m, 600);
	size_t rdlen_at = m.n;
	u16(&m, 0);
	size_t cname_at = m.n;
	u8(&m, 3);
	memcpy(m.b + m.n, "www", 3);
	m.n += 3;
	u8(&m, 1);
	u8(&m, 'a');
	u8(&m, 6);
	memcpy(m.b + m.n, "shifen", 6);
	m.n += 6;
	u16(&m, 0xc000 | (12 + 10)); /* ".com" of the question */
	m.b[rdlen_at] = 0;
	m.b[rdlen_at + 1] = (uint8_t)(m.n - cname_at);
	for (int i = 0; i < 2; i++) {
		u16(&m, 0xc000 | (unsigned)cname_at);
		u16(&m, RL_DNS_A);
		u16(&m, 1);
		u32(&m, 120 + (uint32_t)i);
		u16(&m, 4);
		u8(&m, 110);
		u8(&m, 242);
		u8(&m, 68);
		u8(&m, 66 + (unsigned)i);
	}
	rl_dns_msg d;
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), 0);
	T_ASSERT(d.response);
	T_EQ_STR(rl_dns_rcode_name(d.rcode), "NOERROR");
	T_EQ_STR(d.cname, "www.a.shifen.com");
	T_EQ_I64(d.n_addrs, 2);
	T_EQ_I64(d.addrs[1].addr[3], 67);
	T_EQ_I64(d.addrs[0].ttl, 120);
	T_ASSERT(!d.truncated);

	/* Cut in the middle of the last answer: what was read is kept. */
	T_EQ_I64(rl_dns_parse(m.b, m.n - 3, &d), 0);
	T_EQ_I64(d.n_addrs, 1);
	T_ASSERT(d.truncated);
}

static void test_aaaa_and_nxdomain(void)
{
	msg m;
	header(&m, 0x8180, 1, 1);
	name(&m, "v6.example");
	u16(&m, RL_DNS_AAAA);
	u16(&m, 1);
	u16(&m, 0xc00c);
	u16(&m, RL_DNS_AAAA);
	u16(&m, 1);
	u32(&m, 60);
	u16(&m, 16);
	for (int i = 0; i < 16; i++)
		u8(&m, (unsigned)i);
	rl_dns_msg d;
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), 0);
	T_EQ_I64(d.addrs[0].family, 6);
	T_EQ_I64(d.addrs[0].addr[15], 15);

	header(&m, 0x8183, 1, 0);
	name(&m, "nope.invalid");
	u16(&m, RL_DNS_A);
	u16(&m, 1);
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), 0);
	T_EQ_STR(rl_dns_rcode_name(d.rcode), "NXDOMAIN");
	char buf[8];
	T_EQ_STR(rl_dns_type_name(RL_DNS_HTTPS, buf), "HTTPS");
	T_EQ_STR(rl_dns_type_name(999, buf), "999");
}

static void test_malformed(void)
{
	msg m;
	rl_dns_msg d;
	uint8_t tiny[5] = { 0 };
	T_EQ_I64(rl_dns_parse(tiny, sizeof(tiny), &d), -1);

	/* A pointer to itself, and a forward pointer. */
	header(&m, 0x0100, 1, 0);
	u16(&m, 0xc00c);
	u16(&m, 1);
	u16(&m, 1);
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), -1);
	header(&m, 0x0100, 1, 0);
	u16(&m, 0xc020);
	u16(&m, 1);
	u16(&m, 1);
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), -1);

	/* A label running past the end. */
	header(&m, 0x0100, 1, 0);
	u8(&m, 40);
	u8(&m, 'a');
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), -1);

	/* No question. */
	header(&m, 0x8180, 0, 0);
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), -1);

	/* Random bytes never crash (ASan/UBSan watch). */
	srand(7);
	for (int round = 0; round < 2000; round++) {
		uint8_t junk[96];
		size_t n = (size_t)(rand() % (int)sizeof(junk));
		for (size_t i = 0; i < n; i++)
			junk[i] = (uint8_t)rand();
		if (n > 5)
			junk[5] = 1; /* one question, so parsing goes on */
		rl_dns_parse(junk, n, &d);
	}
}

/* Only host name characters are kept: markup in a lookup must never reach the log (and LuCI or the app). */
static void test_odd_names(void)
{
	msg m;
	rl_dns_msg d;
	header(&m, 0x0100, 1, 0);
	name(&m, "_DMARC.x-y.Example");
	u16(&m, RL_DNS_A);
	u16(&m, 1);
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), 0);
	T_EQ_STR(d.qname, "_dmarc.x-y.example");

	const char *bad[] = { "<img src=x onerror=alert(1)>.evil.com", "a\"b.example", "it's.example", "a/b.example",
			      "a b.example", "x&amp.example" };
	for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
		header(&m, 0x8180, 1, 0);
		name(&m, bad[i]);
		u16(&m, RL_DNS_A);
		u16(&m, 1);
		T_EQ_I64(rl_dns_parse(m.b, m.n, &d), -1);
	}

	/* A NUL byte in a label does not cut the name short before the check. */
	header(&m, 0x8180, 1, 0);
	u8(&m, 9);
	memcpy(m.b + m.n, "ok\0<b>x</", 9);
	m.n += 9;
	u8(&m, 0);
	u16(&m, RL_DNS_A);
	u16(&m, 1);
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), -1);

	/* An odd CNAME target is left out; the addresses after it still count. */
	header(&m, 0x8180, 1, 2);
	name(&m, "www.example.com");
	u16(&m, RL_DNS_A);
	u16(&m, 1);
	u16(&m, 0xc00c);
	u16(&m, RL_DNS_CNAME);
	u16(&m, 1);
	u32(&m, 60);
	size_t rdlen_at = m.n;
	u16(&m, 0);
	size_t target_at = m.n;
	name(&m, "5.0/25.2.0.192.in-addr.arpa");
	m.b[rdlen_at + 1] = (uint8_t)(m.n - target_at);
	u16(&m, 0xc00c);
	u16(&m, RL_DNS_A);
	u16(&m, 1);
	u32(&m, 60);
	u16(&m, 4);
	u32(&m, 0xc0000205);
	T_EQ_I64(rl_dns_parse(m.b, m.n, &d), 0);
	T_EQ_STR(d.qname, "www.example.com");
	T_EQ_STR(d.cname, "");
	T_EQ_I64(d.n_addrs, 1);
	T_ASSERT(!d.truncated);
}

static void test_cache(void)
{
	rl_dns_cache *c = rl_dns_cache_new(8);
	uint8_t a[16] = { 93, 184, 216, 34 }, b[16] = { 1, 1, 1, 1 };
	rl_dns_cache_put(c, 4, a, "example.com", 0, 100);
	T_EQ_STR(rl_dns_cache_get(c, 4, a, 50), "example.com");
	T_ASSERT(rl_dns_cache_get(c, 4, a, 100) == NULL);
	T_ASSERT(rl_dns_cache_get(c, 4, b, 50) == NULL);
	T_ASSERT(rl_dns_cache_get(c, 6, a, 50) == NULL);
	rl_dns_cache_put(c, 4, a, "www.example.com", 150, 200);
	T_EQ_STR(rl_dns_cache_get(c, 4, a, 150), "www.example.com");
	T_EQ_U64(rl_dns_cache_size(c), 1);

	/* Over capacity: an expired entry goes first, then the oldest; the rest stays findable. */
	for (int i = 0; i < 20; i++) {
		uint8_t ip[16] = { 10, 0, 0, (uint8_t)i };
		char n[16];
		snprintf(n, sizeof(n), "h%d", i);
		rl_dns_cache_put(c, 4, ip, n, 500, 1000 + i);
	}
	T_EQ_U64(rl_dns_cache_size(c), 8);
	for (int i = 12; i < 20; i++) {
		uint8_t ip[16] = { 10, 0, 0, (uint8_t)i };
		char n[16];
		snprintf(n, sizeof(n), "h%d", i);
		const char *got = rl_dns_cache_get(c, 4, ip, 500);
		T_ASSERT(got && strcmp(got, n) == 0);
	}
	uint8_t first[16] = { 10, 0, 0, 0 };
	T_ASSERT(rl_dns_cache_get(c, 4, first, 500) == NULL);
	rl_dns_cache_free(c);
}

int main(void)
{
	T_RUN(test_query);
	T_RUN(test_answer_with_compression);
	T_RUN(test_aaaa_and_nxdomain);
	T_RUN(test_malformed);
	T_RUN(test_odd_names);
	T_RUN(test_cache);
	T_DONE();
}
