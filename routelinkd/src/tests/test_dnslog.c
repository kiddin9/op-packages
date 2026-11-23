#include <stdlib.h>
#include <unistd.h>

#include "t.h"

#include "core/dnslog.h"
#include "core/vlog.h"

static rl_dnslog_rec answer(int64_t ts, uint8_t last, const char *name)
{
	rl_dnslog_rec r = { .ts = ts, .mac = { 0xaa, 0xbb, 0xcc, 0xdd, 0xee, last }, .qtype = RL_DNS_A };
	snprintf(r.name, sizeof(r.name), "%s", name);
	r.n_addrs = 2;
	r.addrs[0] = (rl_dns_addr){ .family = 4, .addr = { 93, 184, 216, 34 } };
	r.addrs[1] = (rl_dns_addr){ .family = 6, .addr = { 0x20, 0x01, 0x0d, 0xb8, [15] = 1 } };
	return r;
}

static void test_round_trip(void)
{
	uint8_t buf[RL_DNSLOG_REC_MAX];
	rl_dnslog_rec r = answer(1790000000, 1, "www.example.com"), back;
	r.rcode = 3;
	size_t n = rl_dnslog_encode(buf, sizeof(buf), &r);
	T_EQ_U64(n, 14 + 15 + 1 + 5 + 17);
	T_EQ_I64(rl_dnslog_decode(buf, n, &back), 0);
	T_EQ_I64(back.ts, 1790000000);
	T_EQ_STR(back.name, "www.example.com");
	T_EQ_I64(back.qtype, RL_DNS_A);
	T_EQ_I64(back.rcode, 3);
	T_EQ_I64(back.n_addrs, 2);
	T_ASSERT(memcmp(&back.addrs[1].addr, &r.addrs[1].addr, 16) == 0);
	T_ASSERT(memcmp(back.mac, r.mac, 6) == 0);

	/* the longest name with every address fits the maximum */
	memset(r.name, 'a', RL_DNS_NAME_MAX);
	r.name[RL_DNS_NAME_MAX] = '\0';
	r.n_addrs = RL_DNS_MAX_ADDRS;
	for (int i = 0; i < RL_DNS_MAX_ADDRS; i++)
		r.addrs[i].family = 6;
	n = rl_dnslog_encode(buf, sizeof(buf), &r);
	T_EQ_U64(n, RL_DNSLOG_REC_MAX);
	T_EQ_I64(rl_dnslog_decode(buf, n, &back), 0);
	T_EQ_U64(rl_dnslog_encode(buf, n - 1, &r), 0);

	/* damage: truncated, a bad family, trailing bytes */
	r = answer(1, 1, "a.b");
	n = rl_dnslog_encode(buf, sizeof(buf), &r);
	T_EQ_I64(rl_dnslog_decode(buf, n - 1, &back), -1);
	T_EQ_I64(rl_dnslog_decode(buf, n + 1, &back), -1);
	buf[14 + 3 + 1] = 5;
	T_EQ_I64(rl_dnslog_decode(buf, n, &back), -1);
	T_EQ_I64(rl_dnslog_decode(buf, 3, &back), -1);
}

static void test_match(void)
{
	rl_dnslog_rec r = answer(1, 7, "img.alicdn.com");
	uint8_t mine[6] = { 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 7 }, other[6] = { 0 };
	T_ASSERT(rl_dnslog_match(&r, NULL, NULL));
	T_ASSERT(rl_dnslog_match(&r, mine, ""));
	T_ASSERT(!rl_dnslog_match(&r, other, NULL));
	T_ASSERT(rl_dnslog_match(&r, mine, "alicdn"));
	T_ASSERT(!rl_dnslog_match(&r, mine, "baidu"));
}

typedef struct {
	int n;
	int64_t first;
} scan_ctx;

static bool count_cb(const uint8_t *rec, size_t len, void *x)
{
	scan_ctx *c = x;
	rl_dnslog_rec r;
	if (rl_dnslog_decode(rec, len, &r) != 0)
		return false;
	if (!c->n++)
		c->first = r.ts;
	return true;
}

/* Records through core/vlog: newest first. */
static void test_in_vlog(void)
{
	char path[] = "/tmp/rl-dnslog-XXXXXX";
	int fd = mkstemp(path);
	close(fd);
	unlink(path);
	rl_vlog *v = rl_vlog_open(path, RL_DNSLOG_KIND, NULL);
	T_ASSERT(v != NULL);
	uint8_t buf[RL_DNSLOG_REC_MAX];
	for (int i = 0; i < 50; i++) {
		rl_dnslog_rec r = answer(1000 + i, 1, i % 2 ? "odd.example" : "even.example");
		T_EQ_I64(rl_vlog_append(v, buf, rl_dnslog_encode(buf, sizeof(buf), &r)), 0);
	}
	T_EQ_I64(rl_vlog_commit(v), 0);
	scan_ctx c = { 0 };
	T_EQ_I64(rl_vlog_scan_newest(v, 1010, 1020, count_cb, &c), 0);
	T_EQ_I64(c.n, 10);
	T_EQ_I64(c.first, 1019);
	rl_vlog_close(v);
	unlink(path);
}

int main(void)
{
	T_RUN(test_round_trip);
	T_RUN(test_match);
	T_RUN(test_in_vlog);
	T_DONE();
}
