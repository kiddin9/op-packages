#include "t.h"

#include "core/classify.h"

static rl_netview nv;

static void setup(void)
{
	rl_cidr_set_add_str(&nv.local, "192.168.1.0/24");
	rl_cidr_set_add_str(&nv.local, "192.168.2.0/24"); /* guest */
	rl_cidr_set_add_str(&nv.local, "fd00:1::/64");
	rl_cidr_set_add_str(&nv.local, "2001:db8:1::/64"); /* delegated prefix on the LAN */
	rl_cidr_set_add_str(&nv.router_addrs, "192.168.1.1");
	rl_cidr_set_add_str(&nv.router_addrs, "192.168.2.1");
	rl_cidr_set_add_str(&nv.router_addrs, "100.64.0.2"); /* WAN */
	rl_cidr_set_add_str(&nv.router_addrs, "fd00:1::1");
	rl_cidr_set_add_str(&nv.router_addrs, "2001:db8:ff::2"); /* WAN v6 */
}

static rl_ct_sample ct(const char *os, const char *od, const char *rs, const char *rd)
{
	rl_ct_sample s = { 0 };
	rl_ip_parse(os, &s.orig_src);
	rl_ip_parse(od, &s.orig_dst);
	rl_ip_parse(rs, &s.reply_src);
	rl_ip_parse(rd, &s.reply_dst);
	return s;
}

static void expect_one(rl_attribution a, const char *client, rl_class cls, bool is_orig)
{
	rl_ip ip;
	T_EQ_I64(a.n, 1);
	if (a.n != 1)
		return;
	rl_ip_parse(client, &ip);
	T_ASSERT(!a.a[0].router);
	T_ASSERT(rl_ip_eq(&a.a[0].client, &ip));
	T_EQ_I64(a.a[0].cls, cls);
	T_EQ_I64(a.a[0].client_is_orig, is_orig);
}

static void outbound(void)
{
	/* client -> internet, masqueraded */
	rl_ct_sample s = ct("192.168.1.10", "1.1.1.1", "1.1.1.1", "100.64.0.2");
	expect_one(rl_classify(&nv, &s), "192.168.1.10", RL_CLASS_INTERNET, true);
	/* IPv6, no NAT */
	s = ct("2001:db8:1::10", "2606:4700::1111", "2606:4700::1111", "2001:db8:1::10");
	expect_one(rl_classify(&nv, &s), "2001:db8:1::10", RL_CLASS_INTERNET, true);
	/* transparent proxy: REDIRECT to the router still counts as the device's internet use */
	s = ct("192.168.1.10", "142.250.0.1", "192.168.1.1", "192.168.1.10");
	expect_one(rl_classify(&nv, &s), "192.168.1.10", RL_CLASS_INTERNET, true);
}

static void inbound_port_forward(void)
{
	rl_ct_sample s = ct("8.8.8.8", "100.64.0.2", "192.168.1.20", "8.8.8.8");
	expect_one(rl_classify(&nv, &s), "192.168.1.20", RL_CLASS_INTERNET, false);
	s = ct("2a00::1", "2001:db8:1::20", "2001:db8:1::20", "2a00::1");
	expect_one(rl_classify(&nv, &s), "2001:db8:1::20", RL_CLASS_INTERNET, false);
}

static void lan_between_devices(void)
{
	rl_ct_sample s = ct("192.168.2.30", "192.168.1.20", "192.168.1.20", "192.168.2.30");
	rl_attribution a = rl_classify(&nv, &s);
	rl_ip x, y;
	rl_ip_parse("192.168.2.30", &x);
	rl_ip_parse("192.168.1.20", &y);
	T_EQ_I64(a.n, 2);
	T_ASSERT(rl_ip_eq(&a.a[0].client, &x) && a.a[0].client_is_orig && a.a[0].cls == RL_CLASS_LAN);
	T_ASSERT(rl_ip_eq(&a.a[1].client, &y) && !a.a[1].client_is_orig && a.a[1].cls == RL_CLASS_LAN);
	/* hairpin NAT: device -> router WAN address -> DNAT to another device */
	s = ct("192.168.1.10", "100.64.0.2", "192.168.1.20", "192.168.1.10");
	a = rl_classify(&nv, &s);
	T_EQ_I64(a.n, 2);
	T_ASSERT(rl_ip_eq(&a.a[1].client, &y));
	/* v6 */
	s = ct("fd00:1::10", "fd00:1::20", "fd00:1::20", "fd00:1::10");
	T_EQ_I64(rl_classify(&nv, &s).n, 2);
}

static void device_and_router(void)
{
	/* DNS / LuCI on the router */
	rl_ct_sample s = ct("192.168.1.10", "192.168.1.1", "192.168.1.1", "192.168.1.10");
	expect_one(rl_classify(&nv, &s), "192.168.1.10", RL_CLASS_LAN, true);
	s = ct("fd00:1::10", "fd00:1::1", "fd00:1::1", "fd00:1::10");
	expect_one(rl_classify(&nv, &s), "fd00:1::10", RL_CLASS_LAN, true);
	/* router pings a device */
	s = ct("192.168.1.1", "192.168.1.10", "192.168.1.10", "192.168.1.1");
	expect_one(rl_classify(&nv, &s), "192.168.1.10", RL_CLASS_LAN, false);
}

static void router_itself(void)
{
	rl_ct_sample s = ct("100.64.0.2", "151.101.0.1", "151.101.0.1", "100.64.0.2");
	rl_attribution a = rl_classify(&nv, &s);
	T_EQ_I64(a.n, 1);
	T_ASSERT(a.a[0].router && a.a[0].cls == RL_CLASS_ROUTER && a.a[0].client_is_orig);
	/* inbound to the router (WireGuard, SSH from WAN) */
	s = ct("8.8.8.8", "100.64.0.2", "100.64.0.2", "8.8.8.8");
	a = rl_classify(&nv, &s);
	T_EQ_I64(a.n, 1);
	T_ASSERT(a.a[0].router && !a.a[0].client_is_orig);
	s = ct("2001:db8:ff::2", "2a00::1", "2a00::1", "2001:db8:ff::2");
	T_ASSERT(rl_classify(&nv, &s).a[0].router);
}

static void unrelated(void)
{
	rl_ct_sample s = ct("8.8.8.8", "9.9.9.9", "9.9.9.9", "8.8.8.8");
	T_EQ_I64(rl_classify(&nv, &s).n, 0);
}

static void direction(void)
{
	/* 192.168.1.10 downloads 1 MB: the reply direction carries it, so it must be rx */
	uint64_t rx, tx;
	rl_client_bytes(true, (rl_delta){ .orig_bytes = 20000, .reply_bytes = 1 << 20 }, &rx, &tx);
	T_EQ_U64(rx, 1 << 20);
	T_EQ_U64(tx, 20000);
	/* server behind a port forward sends 1 MB: reply direction from the device = tx */
	rl_client_bytes(false, (rl_delta){ .orig_bytes = 20000, .reply_bytes = 1 << 20 }, &rx, &tx);
	T_EQ_U64(tx, 1 << 20);
	T_EQ_U64(rx, 20000);
	T_EQ_STR(rl_class_name(RL_CLASS_LAN), "lan");
}

int main(void)
{
	setup();
	T_RUN(outbound);
	T_RUN(inbound_port_forward);
	T_RUN(lan_between_devices);
	T_RUN(device_and_router);
	T_RUN(router_itself);
	T_RUN(unrelated);
	T_RUN(direction);
	rl_cidr_set_free(&nv.local);
	rl_cidr_set_free(&nv.router_addrs);
	T_DONE();
}
