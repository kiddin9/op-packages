#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <uci.h>

#include <libmnl/libmnl.h>
#include <linux/neighbour.h>
#include <linux/rtnetlink.h>

#include "core/util.h"
#include "sys/neigh.h"

#define MAX_ENTRIES 8192
#define MAX_LAN 32

typedef struct {
	rl_ip ip;
	rl_mac mac;
	uint16_t state; /* NUD_*; 0 = deleted from the kernel table (mapping kept for attribution) */
	uint8_t used;
	uint8_t from_lease;
} entry;

typedef struct {
	rl_mac mac;
	int64_t expiry;
} lease_seen;

struct rl_neigh {
	struct mnl_socket *ev, *dump;
	unsigned int seq, portid;
	char *buf;
	rl_neigh_cb cb;
	void *ctx;
	int lan[MAX_LAN];
	int n_lan;

	entry *tab;
	size_t cap, n;

	lease_seen *leases;
	size_t n_leases, cap_leases;
};

static entry *slot_for(rl_neigh *n, const rl_ip *ip, bool insert);

static void tab_reset(rl_neigh *n, size_t cap)
{
	entry *old = n->tab;
	size_t old_cap = n->cap;
	n->tab = calloc(cap, sizeof(entry));
	if (!n->tab)
		abort();
	n->cap = cap;
	n->n = 0;
	for (size_t i = 0; i < old_cap; i++) {
		/* drop stale entries when shrinking back after a burst of temporary IPv6 addresses */
		if (!old[i].used || (cap == old_cap && !old[i].state && !old[i].from_lease))
			continue;
		entry *e = slot_for(n, &old[i].ip, true);
		*e = old[i];
	}
	free(old);
}

static entry *slot_for(rl_neigh *n, const rl_ip *ip, bool insert)
{
	size_t mask = n->cap - 1;
	for (size_t i = rl_ip_hash(ip) & mask;; i = (i + 1) & mask) {
		entry *e = &n->tab[i];
		if (!e->used) {
			if (!insert)
				return NULL;
			if ((n->n + 1) * 10 > n->cap * 7) {
				if (n->n >= MAX_ENTRIES)
					tab_reset(n, n->cap); /* first try dropping stale entries */
				if ((n->n + 1) * 10 > n->cap * 7)
					tab_reset(n, n->cap * 2);
				return slot_for(n, ip, true);
			}
			memset(e, 0, sizeof(*e));
			e->used = 1;
			e->ip = *ip;
			n->n++;
			return e;
		}
		if (rl_ip_eq(&e->ip, ip))
			return e;
	}
}

static bool lan_if(const rl_neigh *n, int ifindex)
{
	if (!n->n_lan)
		return true;
	for (int i = 0; i < n->n_lan; i++)
		if (n->lan[i] == ifindex)
			return true;
	return false;
}

static int attr_cb(const struct nlattr *attr, void *data)
{
	const struct nlattr **tb = data;
	if (mnl_attr_type_valid(attr, NDA_MAX) >= 0)
		tb[mnl_attr_get_type(attr)] = attr;
	return MNL_CB_OK;
}

static int msg_cb(const struct nlmsghdr *nlh, void *data)
{
	rl_neigh *n = data;
	const struct ndmsg *ndm = mnl_nlmsg_get_payload(nlh);
	const struct nlattr *tb[NDA_MAX + 1] = { 0 };
	rl_ip ip;

	if (nlh->nlmsg_type != RTM_NEWNEIGH && nlh->nlmsg_type != RTM_DELNEIGH)
		return MNL_CB_OK;
	if ((ndm->ndm_family != AF_INET && ndm->ndm_family != AF_INET6) || !lan_if(n, ndm->ndm_ifindex))
		return MNL_CB_OK;
	mnl_attr_parse(nlh, sizeof(*ndm), attr_cb, tb);
	if (!tb[NDA_DST])
		return MNL_CB_OK;
	uint16_t len = mnl_attr_get_payload_len(tb[NDA_DST]);
	if (ndm->ndm_family == AF_INET && len == 4) {
		uint32_t a;
		memcpy(&a, mnl_attr_get_payload(tb[NDA_DST]), 4);
		rl_ip_from_v4(a, &ip);
	} else if (ndm->ndm_family == AF_INET6 && len == 16) {
		rl_ip_from_v6(mnl_attr_get_payload(tb[NDA_DST]), &ip);
		if (ip.a[0] == 0xfe && (ip.a[1] & 0xc0) == 0x80)
			return MNL_CB_OK; /* link-local */
	} else {
		return MNL_CB_OK;
	}

	if (nlh->nlmsg_type == RTM_DELNEIGH) {
		entry *e = slot_for(n, &ip, false);
		if (e)
			e->state = 0;
		return MNL_CB_OK;
	}
	if (!tb[NDA_LLADDR] || mnl_attr_get_payload_len(tb[NDA_LLADDR]) != 6)
		return MNL_CB_OK;
	if (ndm->ndm_state & (NUD_FAILED | NUD_INCOMPLETE))
		return MNL_CB_OK;
	rl_mac mac;
	memcpy(mac.b, mnl_attr_get_payload(tb[NDA_LLADDR]), 6);
	if (rl_mac_is_zero(&mac))
		return MNL_CB_OK;
	entry *e = slot_for(n, &ip, true);
	e->mac = mac;
	e->state = ndm->ndm_state ? ndm->ndm_state : NUD_STALE;
	e->from_lease = 0;
	if ((ndm->ndm_state & NUD_REACHABLE) && n->cb)
		n->cb(&mac, (int64_t)time(NULL), n->ctx);
	return MNL_CB_OK;
}

rl_neigh *rl_neigh_open(rl_neigh_cb on_reachable, void *ctx)
{
	rl_neigh *n = calloc(1, sizeof(*n));
	if (!n)
		abort();
	n->cb = on_reachable;
	n->ctx = ctx;
	n->buf = malloc(MNL_SOCKET_BUFFER_SIZE * 2);
	if (!n->buf)
		abort();
	tab_reset(n, 256);
	n->dump = mnl_socket_open(NETLINK_ROUTE);
	n->ev = mnl_socket_open2(NETLINK_ROUTE, SOCK_NONBLOCK | SOCK_CLOEXEC);
	if (!n->dump || !n->ev || mnl_socket_bind(n->dump, 0, MNL_SOCKET_AUTOPID) < 0 ||
	    mnl_socket_bind(n->ev, RTMGRP_NEIGH, MNL_SOCKET_AUTOPID) < 0) {
		rl_neigh_close(n);
		return NULL;
	}
	n->portid = mnl_socket_get_portid(n->dump);
	n->seq = (unsigned int)time(NULL);
	return n;
}

void rl_neigh_close(rl_neigh *n)
{
	if (!n)
		return;
	if (n->dump)
		mnl_socket_close(n->dump);
	if (n->ev)
		mnl_socket_close(n->ev);
	free(n->buf);
	free(n->tab);
	free(n->leases);
	free(n);
}

int rl_neigh_fd(const rl_neigh *n)
{
	return mnl_socket_get_fd(n->ev);
}

void rl_neigh_on_readable(rl_neigh *n)
{
	for (;;) {
		ssize_t r = mnl_socket_recvfrom(n->ev, n->buf, MNL_SOCKET_BUFFER_SIZE * 2);
		if (r < 0) {
			if (errno == ENOBUFS)
				continue;
			break;
		}
		mnl_cb_run(n->buf, (size_t)r, 0, 0, msg_cb, n);
	}
}

int rl_neigh_dump(rl_neigh *n)
{
	struct nlmsghdr *nlh = mnl_nlmsg_put_header(n->buf);
	nlh->nlmsg_type = RTM_GETNEIGH;
	nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
	nlh->nlmsg_seq = ++n->seq;
	struct ndmsg *ndm = mnl_nlmsg_put_extra_header(nlh, sizeof(*ndm));
	ndm->ndm_family = AF_UNSPEC;
	if (mnl_socket_sendto(n->dump, nlh, nlh->nlmsg_len) < 0)
		return -1;
	int ret;
	do {
		ssize_t r = mnl_socket_recvfrom(n->dump, n->buf, MNL_SOCKET_BUFFER_SIZE * 2);
		if (r <= 0)
			return -1;
		ret = mnl_cb_run(n->buf, (size_t)r, n->seq, n->portid, msg_cb, n);
	} while (ret > MNL_CB_STOP);
	return ret < 0 ? -1 : 0;
}

void rl_neigh_set_lan_ifindexes(rl_neigh *n, const int *idx, int count)
{
	n->n_lan = count > MAX_LAN ? MAX_LAN : count;
	memcpy(n->lan, idx, (size_t)n->n_lan * sizeof(int));
}

bool rl_neigh_lookup(const rl_neigh *n, const rl_ip *ip, rl_mac *out)
{
	entry *e = slot_for((rl_neigh *)n, ip, false);
	if (!e)
		return false;
	*out = e->mac;
	return true;
}

size_t rl_neigh_ips(const rl_neigh *n, const rl_mac *mac, rl_ip *out, size_t max)
{
	size_t k = 0;
	for (int family = 4; family <= 6; family += 2)
		for (size_t i = 0; i < n->cap && k < max; i++) {
			const entry *e = &n->tab[i];
			if (e->used && e->ip.family == family && (e->state || e->from_lease) && rl_mac_eq(&e->mac, mac))
				out[k++] = e->ip;
		}
	return k;
}

static lease_seen *lease_for(rl_neigh *n, const rl_mac *mac)
{
	for (size_t i = 0; i < n->n_leases; i++)
		if (rl_mac_eq(&n->leases[i].mac, mac))
			return &n->leases[i];
	n->leases = rl_grow(n->leases, &n->cap_leases, n->n_leases + 1, sizeof(lease_seen));
	lease_seen *l = &n->leases[n->n_leases++];
	l->mac = *mac;
	l->expiry = 0;
	return l;
}

/* "expiry mac ip hostname clientid" per line (dnsmasq) */
static void read_leases(rl_neigh *n, rl_devtab *t, int64_t now)
{
	FILE *f = fopen("/tmp/dhcp.leases", "r");
	char line[512];
	if (!f)
		return;
	while (fgets(line, sizeof(line), f)) {
		char mac_s[32], ip_s[64], host[64];
		long long expiry;
		rl_mac mac;
		rl_ip ip;
		if (sscanf(line, "%lld %31s %63s %63s", &expiry, mac_s, ip_s, host) != 4)
			continue;
		if (!rl_mac_parse(mac_s, &mac) || !rl_ip_parse(ip_s, &ip))
			continue;
		entry *e = slot_for(n, &ip, true);
		if (!e->state) {
			e->mac = mac;
			e->from_lease = 1;
		}
		lease_seen *l = lease_for(n, &mac);
		rl_device *d = rl_devtab_find(t, &mac);
		if (d) {
			if (strcmp(host, "*"))
				snprintf(d->hostname, sizeof(d->hostname), "%s", host);
			if (l->expiry && expiry > l->expiry)
				rl_devtab_touch(d, now); /* renewed */
		}
		l->expiry = expiry;
	}
	fclose(f);
}

/* dhcp host sections: routelink_alias (set by the app for names that are not valid hostnames) wins */
static void read_host_names(rl_devtab *t)
{
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (!ctx)
		return;
	for (size_t i = 0; i < rl_devtab_count(t); i++)
		rl_devtab_at(t, i)->name[0] = '\0';
	if (uci_load(ctx, "dhcp", &pkg) == UCI_OK && pkg) {
		struct uci_element *e;
		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			if (strcmp(s->type, "host"))
				continue;
			const char *alias = uci_lookup_option_string(ctx, s, "routelink_alias");
			const char *name = uci_lookup_option_string(ctx, s, "name");
			const char *use = alias && *alias ? alias : name;
			struct uci_option *o = uci_lookup_option(ctx, s, "mac");
			if (!use || !o)
				continue;
			char buf[256];
			if (o->type == UCI_TYPE_STRING) {
				snprintf(buf, sizeof(buf), "%s", o->v.string);
			} else {
				buf[0] = '\0';
				struct uci_element *le;
				uci_foreach_element(&o->v.list, le) {
					strncat(buf, le->name, sizeof(buf) - strlen(buf) - 2);
					strcat(buf, " ");
				}
			}
			for (char *save, *tok = strtok_r(buf, " \t", &save); tok; tok = strtok_r(NULL, " \t", &save)) {
				rl_mac mac;
				rl_device *d;
				if (rl_mac_parse(tok, &mac) && (d = rl_devtab_find(t, &mac)))
					snprintf(d->name, sizeof(d->name), "%s", use);
			}
		}
	}
	uci_free_context(ctx);
}

void rl_names_refresh(rl_neigh *n, rl_devtab *t, int64_t now)
{
	read_leases(n, t, now);
	read_host_names(t);
}
