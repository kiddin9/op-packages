#include "t.h"

#include "core/addr.h"

static void mac_parse_format(void)
{
	rl_mac m;
	char s[RL_MAC_STRLEN];
	T_ASSERT(rl_mac_parse("aa-bb-cc-00-11-22", &m));
	rl_mac_format(&m, s);
	T_EQ_STR(s, "AA:BB:CC:00:11:22");
	T_ASSERT(rl_mac_parse("AA:BB:CC:00:11:22", &m));
	T_ASSERT(!rl_mac_parse("AA:BB:CC:00:11", &m));
	T_ASSERT(!rl_mac_parse("AA:BB:CC:00:11:2G", &m));
	T_ASSERT(!rl_mac_parse("", &m));
}

static void mac_random(void)
{
	rl_mac m;
	rl_mac_parse("02:00:00:00:00:01", &m);
	T_ASSERT(rl_mac_is_random(&m));
	rl_mac_parse("00:1A:2B:00:00:01", &m);
	T_ASSERT(!rl_mac_is_random(&m));
	rl_mac_parse("DA:A1:19:00:00:01", &m); /* 0xDA has the local bit */
	T_ASSERT(rl_mac_is_random(&m));
}

static void ip_parse_format(void)
{
	rl_ip a, b;
	char s[RL_IP_STRLEN];
	T_ASSERT(rl_ip_parse("192.168.1.77", &a));
	T_EQ_I64(a.family, 4);
	rl_ip_format(&a, s);
	T_EQ_STR(s, "192.168.1.77");
	T_ASSERT(rl_ip_parse("fd12:3456:789a:1::5", &b));
	T_EQ_I64(b.family, 6);
	rl_ip_format(&b, s);
	T_EQ_STR(s, "fd12:3456:789a:1::5");
	T_ASSERT(!rl_ip_eq(&a, &b));
	T_ASSERT(!rl_ip_parse("300.1.1.1", &a));
	T_ASSERT(!rl_ip_parse("nonsense", &a));
}

static void cidr_sets(void)
{
	rl_cidr_set s = { 0 };
	rl_ip ip;
	T_ASSERT(rl_cidr_set_add_str(&s, "192.168.1.1/24"));
	T_ASSERT(rl_cidr_set_add_str(&s, "fd12:3456:789a::/48"));
	T_ASSERT(rl_cidr_set_add_str(&s, "192.168.1.0/24")); /* same network after masking */
	T_EQ_U64(s.n, 2);
	rl_ip_parse("192.168.1.77", &ip);
	T_ASSERT(rl_cidr_set_contains(&s, &ip));
	rl_ip_parse("192.168.2.1", &ip);
	T_ASSERT(!rl_cidr_set_contains(&s, &ip));
	rl_ip_parse("fd12:3456:789a:1::5", &ip);
	T_ASSERT(rl_cidr_set_contains(&s, &ip));
	rl_ip_parse("fd12:3456:789b::5", &ip);
	T_ASSERT(!rl_cidr_set_contains(&s, &ip));
	T_ASSERT(!rl_cidr_set_add_str(&s, "10.0.0.0/33"));
	rl_cidr_set_free(&s);
}

static void cidr_zero_prefix_and_hosts(void)
{
	rl_cidr_set s = { 0 };
	rl_ip ip;
	rl_cidr_set_add_str(&s, "0.0.0.0/0");
	rl_cidr_set_add_str(&s, "2001:db8::1"); /* host */
	rl_ip_parse("8.8.8.8", &ip);
	T_ASSERT(rl_cidr_set_contains(&s, &ip));
	rl_ip_parse("2001:db8::1", &ip);
	T_ASSERT(rl_cidr_set_contains(&s, &ip));
	rl_ip_parse("2001:db8::2", &ip);
	T_ASSERT(!rl_cidr_set_contains(&s, &ip));
	rl_cidr_set_clear(&s);
	T_EQ_U64(s.n, 0);
	rl_cidr_set_free(&s);
}

int main(void)
{
	T_RUN(mac_parse_format);
	T_RUN(mac_random);
	T_RUN(ip_parse_format);
	T_RUN(cidr_sets);
	T_RUN(cidr_zero_prefix_and_hosts);
	T_DONE();
}
