#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uci.h>

#include <libubox/blobmsg.h>

#include "sys/netinfo.h"

#define MAX_NETS 64

/* network name -> zone kind, from /etc/config/firewall */
typedef struct {
	char name[32];
	bool wan;
} zone_net;

typedef struct {
	zone_net nets[MAX_NETS];
	int n;
} zone_map;

static void zone_add(zone_map *m, const char *net, bool wan)
{
	for (int i = 0; i < m->n; i++)
		if (!strcmp(m->nets[i].name, net)) {
			m->nets[i].wan |= wan;
			return;
		}
	if (m->n < MAX_NETS) {
		snprintf(m->nets[m->n].name, sizeof(m->nets[m->n].name), "%s", net);
		m->nets[m->n++].wan = wan;
	}
}

static int zone_kind(const zone_map *m, const char *net)
{
	for (int i = 0; i < m->n; i++)
		if (!strcmp(m->nets[i].name, net))
			return m->nets[i].wan ? 1 : 0;
	return -1;
}

static void load_zones(zone_map *m)
{
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	m->n = 0;
	if (!ctx)
		return;
	if (uci_load(ctx, "firewall", &pkg) == UCI_OK && pkg) {
		struct uci_element *e;
		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			if (strcmp(s->type, "zone"))
				continue;
			const char *masq = uci_lookup_option_string(ctx, s, "masq");
			bool wan = masq && (!strcmp(masq, "1") || !strcmp(masq, "true") || !strcmp(masq, "on"));
			struct uci_option *o = uci_lookup_option(ctx, s, "network");
			if (!o)
				continue;
			if (o->type == UCI_TYPE_LIST) {
				struct uci_element *le;
				uci_foreach_element(&o->v.list, le)
					zone_add(m, le->name, wan);
			} else {
				char buf[256];
				snprintf(buf, sizeof(buf), "%s", o->v.string);
				for (char *save, *tok = strtok_r(buf, " \t", &save); tok; tok = strtok_r(NULL, " \t", &save))
					zone_add(m, tok, wan);
			}
		}
	}
	uci_free_context(ctx);
}

enum { IF_NAME, IF_UP, IF_L3, IF_V4, IF_V6, IF_V6PFX, IF_ROUTE, __IF_MAX };
static const struct blobmsg_policy if_policy[__IF_MAX] = {
	[IF_NAME] = { "interface", BLOBMSG_TYPE_STRING },
	[IF_UP] = { "up", BLOBMSG_TYPE_BOOL },
	[IF_L3] = { "l3_device", BLOBMSG_TYPE_STRING },
	[IF_V4] = { "ipv4-address", BLOBMSG_TYPE_ARRAY },
	[IF_V6] = { "ipv6-address", BLOBMSG_TYPE_ARRAY },
	[IF_V6PFX] = { "ipv6-prefix-assignment", BLOBMSG_TYPE_ARRAY },
	[IF_ROUTE] = { "route", BLOBMSG_TYPE_ARRAY },
};

enum { A_ADDR, A_MASK, A_LOCAL, __A_MAX };
static const struct blobmsg_policy addr_policy[__A_MAX] = {
	[A_ADDR] = { "address", BLOBMSG_TYPE_STRING },
	[A_MASK] = { "mask", BLOBMSG_TYPE_INT32 },
	[A_LOCAL] = { "local-address", BLOBMSG_TYPE_TABLE },
};

enum { R_TARGET, R_MASK, R_NEXTHOP, __R_MAX };
static const struct blobmsg_policy route_policy[__R_MAX] = {
	[R_TARGET] = { "target", BLOBMSG_TYPE_STRING },
	[R_MASK] = { "mask", BLOBMSG_TYPE_INT32 },
	[R_NEXTHOP] = { "nexthop", BLOBMSG_TYPE_STRING },
};

static bool ip_unspecified(const rl_ip *ip)
{
	static const uint8_t zero[16];
	return memcmp(ip->a, zero, sizeof(zero)) == 0;
}

/* The next hop of a default route (family 4 or 6) in netifd's route list. */
static bool default_nexthop(struct blob_attr *routes, int family, rl_ip *out)
{
	struct blob_attr *cur;
	int rem;
	if (routes)
		blobmsg_for_each_attr(cur, routes, rem) {
			struct blob_attr *tb[__R_MAX];
			rl_ip target;
			blobmsg_parse(route_policy, __R_MAX, tb, blobmsg_data(cur), blobmsg_len(cur));
			if (!tb[R_TARGET] || !tb[R_MASK] || blobmsg_get_u32(tb[R_MASK]) != 0 || !tb[R_NEXTHOP] ||
			    !rl_ip_parse(blobmsg_get_string(tb[R_TARGET]), &target) || target.family != family ||
			    !rl_ip_parse(blobmsg_get_string(tb[R_NEXTHOP]), out) || ip_unspecified(out))
				continue;
			return true;
		}
	return false;
}

typedef struct {
	rl_netinfo *ni;
	zone_map zones;
	bool ok;
} dump_ctx;

/* address/mask entries: the host address is always the router's; the network is LAN when lan is set. */
static void add_addrs(rl_netinfo *ni, struct blob_attr *list, bool lan, bool prefix_assignment)
{
	struct blob_attr *cur;
	int rem;
	if (!list)
		return;
	blobmsg_for_each_attr(cur, list, rem) {
		struct blob_attr *tb[__A_MAX];
		rl_ip ip;
		blobmsg_parse(addr_policy, __A_MAX, tb, blobmsg_data(cur), blobmsg_len(cur));
		if (!tb[A_ADDR] || !rl_ip_parse(blobmsg_get_string(tb[A_ADDR]), &ip))
			continue;
		int mask = tb[A_MASK] ? (int)blobmsg_get_u32(tb[A_MASK]) : (ip.family == 4 ? 32 : 128);
		if (lan)
			rl_cidr_set_add(&ni->nv.local, &ip, (uint8_t)mask);
		if (prefix_assignment) {
			/* the prefix itself is not an address of the router, its local-address is */
			if (tb[A_LOCAL]) {
				struct blob_attr *lt[__A_MAX];
				rl_ip local;
				blobmsg_parse(addr_policy, __A_MAX, lt, blobmsg_data(tb[A_LOCAL]), blobmsg_len(tb[A_LOCAL]));
				if (lt[A_ADDR] && rl_ip_parse(blobmsg_get_string(lt[A_ADDR]), &local))
					rl_cidr_set_add(&ni->nv.router_addrs, &local, local.family == 4 ? 32 : 128);
			}
			continue;
		}
		rl_cidr_set_add(&ni->nv.router_addrs, &ip, ip.family == 4 ? 32 : 128);
	}
}

static void dump_cb(struct ubus_request *req, int type, struct blob_attr *msg)
{
	dump_ctx *d = req->priv;
	static const struct blobmsg_policy p = { "interface", BLOBMSG_TYPE_ARRAY };
	struct blob_attr *list, *cur;
	int rem;
	blobmsg_parse(&p, 1, &list, blob_data(msg), blob_len(msg));
	if (!list)
		return;
	d->ok = true;
	blobmsg_for_each_attr(cur, list, rem) {
		struct blob_attr *tb[__IF_MAX];
		blobmsg_parse(if_policy, __IF_MAX, tb, blobmsg_data(cur), blobmsg_len(cur));
		if (!tb[IF_NAME])
			continue;
		const char *name = blobmsg_get_string(tb[IF_NAME]);
		bool up = tb[IF_UP] && blobmsg_get_bool(tb[IF_UP]);
		const char *l3 = tb[IF_L3] ? blobmsg_get_string(tb[IF_L3]) : NULL;
		int kind = zone_kind(&d->zones, name); /* 1 wan, 0 lan, -1 none */
		rl_netinfo *ni = d->ni;

		add_addrs(ni, tb[IF_V4], kind == 0, false);
		add_addrs(ni, tb[IF_V6], kind == 0, false);
		add_addrs(ni, tb[IF_V6PFX], kind == 0, true);
		if (kind == 1) {
			ni->has_wan = true; /* configured, even while PPPoE is still dialling */
			if (ni->n_wan_names < RL_MAX_WAN_NAMES)
				snprintf(ni->wan_names[ni->n_wan_names++], RL_IFACE_NAMELEN, "%s", name);
		}
		if (!up || !l3)
			continue;
		if (kind == 1) {
			/* the default route: IPv4 wins over IPv6, the first interface over later ones */
			rl_ip gw;
			bool v4 = default_nexthop(tb[IF_ROUTE], 4, &gw);
			bool better = !ni->gw_iface[0] || (v4 && ni->gw.family == 6);
			if (better && (v4 || default_nexthop(tb[IF_ROUTE], 6, &gw))) {
				snprintf(ni->gw_iface, sizeof(ni->gw_iface), "%s", name);
				ni->gw = gw;
				ni->gw_scope = (int)if_nametoindex(l3);
			}
			bool dup = false;
			for (int i = 0; i < ni->n_wan; i++)
				dup |= !strcmp(ni->wan_devs[i], l3);
			if (!dup && ni->n_wan < RL_MAX_WAN_DEVS)
				snprintf(ni->wan_devs[ni->n_wan++], IFNAMSIZ, "%s", l3);
		} else if (kind == 0 && ni->n_lan < RL_MAX_LAN_IFS) {
			int idx = (int)if_nametoindex(l3);
			if (idx > 0)
				ni->lan_ifindex[ni->n_lan++] = idx;
		}
	}
}

int rl_netinfo_refresh(struct ubus_context *ctx, rl_netinfo *ni)
{
	uint32_t id;
	dump_ctx d = { 0 };
	rl_netinfo fresh = { 0 };
	if (!ctx || ubus_lookup_id(ctx, "network.interface", &id))
		return -1;
	d.ni = &fresh;
	load_zones(&d.zones);
	if (ubus_invoke(ctx, id, "dump", NULL, dump_cb, &d, 3000) || !d.ok) {
		rl_netinfo_free(&fresh);
		return -1;
	}
	rl_netinfo_free(ni);
	*ni = fresh;
	return 0;
}

void rl_netinfo_free(rl_netinfo *ni)
{
	rl_cidr_set_free(&ni->nv.local);
	rl_cidr_set_free(&ni->nv.router_addrs);
}

static bool read_counter(const char *dev, const char *name, uint64_t *v)
{
	char path[128];
	snprintf(path, sizeof(path), "/sys/class/net/%s/statistics/%s", dev, name);
	FILE *f = fopen(path, "r");
	if (!f)
		return false;
	bool ok = fscanf(f, "%" SCNu64, v) == 1;
	fclose(f);
	return ok;
}

bool rl_netinfo_wan_bytes(const rl_netinfo *ni, uint64_t *rx, uint64_t *tx)
{
	*rx = *tx = 0;
	bool any = false;
	for (int i = 0; i < ni->n_wan; i++) {
		uint64_t r, t;
		if (read_counter(ni->wan_devs[i], "rx_bytes", &r) && read_counter(ni->wan_devs[i], "tx_bytes", &t)) {
			*rx += r;
			*tx += t;
			any = true;
		}
	}
	return any;
}
