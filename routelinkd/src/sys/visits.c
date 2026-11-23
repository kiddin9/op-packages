#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <time.h>

#include "core/dns.h"
#include "core/timeutil.h"
#include "core/vlog.h"
#include "sys/dnscap.h"
#include "sys/visits.h"

#define MERGE_PEERS 4096 /* distinct peers a destinations query sums */

typedef struct {
	rl_mac mac;
	rl_dest_map *map;
} dev_map;

struct rl_visits {
	rl_vlog *dns, *dest;
	rl_dns_cache *cache;
	rl_dnscap *cap;
	bool on, writable, dns_failing;
	int64_t hour; /* start of the hour being summed, 0 = none */
	dev_map devs[RL_VISITS_MAX_DEVICES];
	int n_devs;
	uint64_t dropped_devices;
};

/* ---- DNS answers ---- */

static void on_answer(const uint8_t mac[6], const rl_dns_msg *m, void *ctx)
{
	rl_visits *v = ctx;
	int64_t now = (int64_t)time(NULL);
	rl_dnslog_rec r = { .ts = now, .qtype = m->qtype, .rcode = m->rcode, .n_addrs = m->n_addrs };
	uint8_t buf[RL_DNSLOG_REC_MAX];
	if (!m->qname[0])
		return;
	memcpy(r.mac, mac, 6);
	snprintf(r.name, sizeof(r.name), "%s", m->qname);
	memcpy(r.addrs, m->addrs, sizeof(r.addrs));
	for (int i = 0; i < m->n_addrs; i++) {
		/* connections often start a little later or outlive a short TTL */
		int64_t ttl = m->addrs[i].ttl < 300 ? 300 : m->addrs[i].ttl > 86400 ? 86400 : m->addrs[i].ttl;
		rl_dns_cache_put(v->cache, m->addrs[i].family, m->addrs[i].addr, m->qname, now, now + ttl);
	}
	size_t len = rl_dnslog_encode(buf, sizeof(buf), &r);
	if (!len || rl_vlog_append(v->dns, buf, len) != 0)
		return;
	if (v->writable && rl_vlog_pending(v->dns) >= RL_VISITS_DNS_PENDING) {
		bool failed = rl_vlog_commit(v->dns) != 0;
		if (failed && !v->dns_failing)
			syslog(LOG_ERR, "writing the DNS log failed: %s", strerror(errno));
		v->dns_failing = failed;
	}
}

/* ---- destinations ---- */

static rl_dest_map *map_of(rl_visits *v, const rl_mac *mac)
{
	for (int i = 0; i < v->n_devs; i++)
		if (rl_mac_eq(&v->devs[i].mac, mac))
			return v->devs[i].map;
	if (v->n_devs >= RL_VISITS_MAX_DEVICES) {
		v->dropped_devices++;
		return NULL;
	}
	dev_map *d = &v->devs[v->n_devs++];
	d->mac = *mac;
	if (!d->map)
		d->map = rl_dest_map_new(RL_VISITS_PEERS);
	return d->map;
}

/* Writes the summed hour, one record per device (top RL_DEST_TOP), and starts over. */
static void close_hour(rl_visits *v)
{
	static rl_dest_entry top[RL_DEST_TOP];
	uint8_t buf[RL_VLOG_REC_MAX];
	for (int i = 0; i < v->n_devs; i++) {
		dev_map *d = &v->devs[i];
		size_t n = rl_dest_top(d->map, top, RL_DEST_TOP);
		rl_dest_map_clear(d->map);
		if (!n)
			continue;
		size_t len = rl_dest_encode(buf, sizeof(buf), v->hour, d->mac.b, top, n);
		if (len)
			rl_vlog_append(v->dest, buf, len);
	}
	v->n_devs = 0; /* the maps stay allocated for the next hour */
}

void rl_visits_tick(rl_visits *v, int64_t now)
{
	int64_t hour = rl_bucket_start(RL_TIER_HOUR, now);
	if (v->hour && hour != v->hour)
		close_hour(v);
	v->hour = hour;
}

void rl_visits_traffic(rl_visits *v, const rl_mac *mac, const rl_ip *peer, uint64_t rx, uint64_t tx, uint32_t conns,
		       int64_t now)
{
	if (!v->on)
		return;
	rl_visits_tick(v, now);
	rl_dest_map *m = map_of(v, mac);
	if (!m)
		return;
	const char *host = rl_dns_cache_get(v->cache, peer->family, peer->a, now);
	if (host) {
		size_t l = strlen(host);
		if (l > RL_DEST_HOST_MAX)
			host += l - RL_DEST_HOST_MAX; /* the end of a name says more than its start */
	}
	rl_dest_add(m, peer->family, peer->a, host, rx, tx, conns);
}

/* ---- life cycle ---- */

rl_visits *rl_visits_open(const char *dir, bool *recovered)
{
	char path[256];
	bool bad_d = false, bad_t = false;
	rl_visits *v = calloc(1, sizeof(*v));
	if (!v)
		abort();
	snprintf(path, sizeof(path), "%s/dns.log", dir);
	v->dns = rl_vlog_open(path, RL_DNSLOG_KIND, &bad_d);
	snprintf(path, sizeof(path), "%s/dest.log", dir);
	v->dest = rl_vlog_open(path, RL_DESTLOG_KIND, &bad_t);
	if (!v->dns || !v->dest) {
		rl_vlog_close(v->dns);
		rl_vlog_close(v->dest);
		free(v);
		return NULL;
	}
	if (recovered)
		*recovered = bad_d || bad_t;
	v->cache = rl_dns_cache_new(RL_VISITS_CACHE);
	return v;
}

void rl_visits_close(rl_visits *v)
{
	if (!v)
		return;
	rl_dnscap_free(v->cap);
	for (int i = 0; i < RL_VISITS_MAX_DEVICES; i++)
		rl_dest_map_free(v->devs[i].map);
	rl_dns_cache_free(v->cache);
	rl_vlog_close(v->dns);
	rl_vlog_close(v->dest);
	free(v);
}

void rl_visits_enable(rl_visits *v, bool on, const int *ifindex, int n)
{
	if (!on) {
		if (v->on) {
			syslog(LOG_INFO, "DNS logging stopped");
			rl_dnscap_free(v->cap);
			v->cap = NULL;
			if (v->hour)
				close_hour(v); /* what was summed so far still counts */
			v->hour = 0;
		}
		v->on = false;
		return;
	}
	if (!v->cap) {
		v->cap = rl_dnscap_new(on_answer, v);
		syslog(LOG_INFO, "DNS logging started");
	}
	v->on = true;
	rl_dnscap_set_ifaces(v->cap, ifindex, n);
}

bool rl_visits_on(const rl_visits *v)
{
	return v->on;
}

void rl_visits_writable(rl_visits *v, bool writable)
{
	v->writable = writable;
}

int rl_visits_commit(rl_visits *v, bool flush)
{
	if (flush && v->hour) {
		close_hour(v); /* the rest of this hour gets another record (queries add them up) */
	}
	int rc = 0;
	if (rl_vlog_commit(v->dns) != 0)
		rc = -1;
	if (rl_vlog_commit(v->dest) != 0)
		rc = -1;
	return rc;
}

void rl_visits_compact(rl_visits *v, int64_t now, int keep_days, uint64_t max_dns, uint64_t max_bytes)
{
	int64_t cutoff = now - (int64_t)keep_days * 86400;
	uint64_t dns_bytes = rl_vlog_bytes(v->dns), dest_bytes = rl_vlog_bytes(v->dest);
	uint64_t dest_max = 0;
	/* DNS gets two thirds of the space, destinations the rest */
	if (dns_bytes + dest_bytes > max_bytes) {
		uint64_t dns_budget = max_bytes / 3 * 2, dest_budget = max_bytes - dns_budget;
		uint64_t n = rl_vlog_count(v->dns);
		if (dns_bytes > dns_budget && n) {
			uint64_t fit = n * dns_budget / dns_bytes;
			if (!max_dns || fit < max_dns)
				max_dns = fit ? fit : 1;
		}
		n = rl_vlog_count(v->dest);
		if (dest_bytes > dest_budget && n)
			dest_max = n * dest_budget / dest_bytes ? n * dest_budget / dest_bytes : 1;
	}
	if (rl_vlog_compact(v->dns, cutoff, max_dns) != 0)
		syslog(LOG_WARNING, "trimming the DNS log failed: %s", strerror(errno));
	if (rl_vlog_compact(v->dest, cutoff, dest_max) != 0)
		syslog(LOG_WARNING, "trimming the destination log failed: %s", strerror(errno));
}

uint64_t rl_visits_bytes(const rl_visits *v)
{
	return rl_vlog_bytes(v->dns) + rl_vlog_bytes(v->dest);
}

void rl_visits_reset(rl_visits *v)
{
	rl_vlog_reset(v->dns);
	rl_vlog_reset(v->dest);
	for (int i = 0; i < v->n_devs; i++)
		rl_dest_map_clear(v->devs[i].map);
	v->n_devs = 0;
}

/* ---- queries ---- */

typedef struct {
	rl_visits_dns_cb cb;
	void *ctx;
	bool failed;
} dns_scan_ctx;

static bool dns_scan_cb(const uint8_t *rec, size_t len, void *x)
{
	dns_scan_ctx *c = x;
	rl_dnslog_rec r;
	if (rl_dnslog_decode(rec, len, &r) != 0)
		return true; /* skip what does not decode */
	return c->cb(&r, c->ctx);
}

int rl_visits_dns_scan(rl_visits *v, int64_t start, int64_t end, rl_visits_dns_cb cb, void *ctx)
{
	dns_scan_ctx c = { cb, ctx, false };
	return rl_vlog_scan_newest(v->dns, start, end, dns_scan_cb, &c);
}

uint64_t rl_visits_dns_count(const rl_visits *v)
{
	return rl_vlog_count(v->dns);
}

typedef struct {
	rl_dest_map *m;
	const rl_mac *mac;
} dest_scan_ctx;

/* Newest first: the name of the latest hour that had one stays. */
static bool merge_entry(const rl_dest_entry *e, void *x)
{
	rl_dest_merge(x, e);
	return true;
}

static bool dest_scan_cb(const uint8_t *rec, size_t len, void *x)
{
	dest_scan_ctx *c = x;
	int64_t hour;
	uint8_t mac[6];
	/* the MAC is right after the hour: look before decoding the entries */
	if (len < 10 || memcmp(rec + 4, c->mac->b, 6) != 0)
		return true;
	rl_dest_decode(rec, len, &hour, mac, merge_entry, c->m);
	return true;
}

int rl_visits_destinations(rl_visits *v, const rl_mac *mac, int64_t start, int64_t end, rl_dest_entry *out, size_t n,
			   size_t *found)
{
	rl_dest_map *m = rl_dest_map_new(MERGE_PEERS);
	dest_scan_ctx c = { m, mac };
	/* the open hour first, then the log newest first (records carry the start of their hour) */
	if (v->hour && v->hour + 3600 > start && v->hour < end)
		for (int i = 0; i < v->n_devs; i++) {
			if (!rl_mac_eq(&v->devs[i].mac, mac))
				continue;
			static rl_dest_entry top[RL_VISITS_PEERS];
			size_t k = rl_dest_top(v->devs[i].map, top, RL_VISITS_PEERS);
			for (size_t j = 0; j < k; j++)
				merge_entry(&top[j], m);
		}
	int rc = rl_vlog_scan_newest(v->dest, start - 3599, end, dest_scan_cb, &c);
	*found = rl_dest_map_count(m);
	size_t k = rl_dest_top(m, out, n);
	rl_dest_map_free(m);
	return rc < 0 ? -1 : (int)k;
}
