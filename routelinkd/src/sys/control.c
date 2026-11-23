#define _GNU_SOURCE
#include <errno.h>
#include <glob.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/blobmsg.h>

#include "core/timeutil.h"
#include "core/util.h"
#include "sys/control.h"
#include "sys/daemon.h"

#define QUOTA_FILE "quota.json"
#define MAX_TC_RULES 256

/* ---- quota state ---- */

static void quota_path(const rl_daemon *d, char *path, size_t size)
{
	snprintf(path, size, "%s/" QUOTA_FILE, d->cfg.data_dir);
}

static void save_quotas(rl_daemon *d)
{
	char path[256];
	rl_quota_saved *s = calloc(d->rules.n_quotas ? d->rules.n_quotas : 1, sizeof(*s));
	if (!s)
		abort();
	for (size_t i = 0; i < d->rules.n_quotas; i++) {
		snprintf(s[i].section, sizeof(s[i].section), "%s", d->qlive[i].section);
		memcpy(s[i].mac, d->qlive[i].mac.b, 6);
		s[i].run = d->qlive[i].run;
	}
	quota_path(d, path, sizeof(path));
	if (rl_quota_save(path, s, d->rules.n_quotas) != 0)
		syslog(LOG_WARNING, "cannot write %s: %s", path, strerror(errno));
	free(s);
}

/* A fresh live entry per quota rule; the run state of the same section and MAC (or MAC alone) carries over. */
static void rebuild_live(rl_daemon *d, const rl_quota_live *old, size_t n_old, const rl_quota_saved *saved,
			 size_t n_saved)
{
	size_t n = d->rules.n_quotas;
	rl_quota_live *live = calloc(n ? n : 1, sizeof(*live));
	if (!live)
		abort();
	for (size_t i = 0; i < n; i++) {
		const rl_quota_rule *q = &d->rules.quotas[i];
		rl_quota_live *l = &live[i];
		snprintf(l->section, sizeof(l->section), "%s", q->section);
		l->mac = q->mac;
		l->cache_dev = -1;
		bool found = false;
		for (int pass = 0; pass < 2 && !found; pass++) {
			for (size_t j = 0; j < n_old && !found; j++)
				if (rl_mac_eq(&old[j].mac, &q->mac) && (pass || !strcmp(old[j].section, q->section))) {
					l->run = old[j].run;
					found = true;
				}
			for (size_t j = 0; j < n_saved && !found; j++)
				if (!memcmp(saved[j].mac, q->mac.b, 6) && (pass || !strcmp(saved[j].section, q->section))) {
					l->run = saved[j].run;
					found = true;
				}
		}
	}
	free(d->qlive);
	d->qlive = live;
}

/* ---- use of a quota: internet traffic of the device since the period began ---- */

typedef struct {
	uint16_t dev;
	uint64_t rx, tx;
} sum_ctx;

static bool sum_cb(const rl_rec *r, void *x)
{
	sum_ctx *c = x;
	if (r->dev == c->dev && r->cls == RL_CLASS_INTERNET) {
		c->rx += r->rx;
		c->tx += r->tx;
	}
	return true;
}

static uint64_t quota_used(rl_daemon *d, rl_quota_live *l, const rl_quota_rule *q, int64_t start, int64_t now)
{
	rl_device *dev = rl_devtab_find(d->devs, &q->mac);
	if (!dev)
		return 0;
	/* every quota period starts at a local midnight: closed days from the day records, today from the open day */
	int64_t open = rl_agg_open_start(d->agg, RL_TIER_DAY);
	int64_t to = open ? open : now + 1;
	sum_ctx closed = { .dev = dev->idx };
	if (l->cache_from == start && l->cache_to == to && l->cache_gen == d->traffic_gen && l->cache_dev == dev->idx) {
		closed.rx = l->cache_rx;
		closed.tx = l->cache_tx;
	} else {
		if (start < to)
			rl_store_scan(d->store, RL_TIER_DAY, start, to, sum_cb, &closed);
		l->cache_from = start;
		l->cache_to = to;
		l->cache_gen = d->traffic_gen;
		l->cache_dev = dev->idx;
		l->cache_rx = closed.rx;
		l->cache_tx = closed.tx;
	}
	sum_ctx today = { .dev = dev->idx };
	if (open && open >= start)
		rl_agg_open(d->agg, RL_TIER_DAY, sum_cb, &today);
	uint64_t rx = closed.rx + today.rx, tx = closed.tx + today.tx;
	return q->download_only ? rx : rx + tx;
}

/* ---- notices ---- */

static void quota_notice(rl_daemon *d, const rl_quota_rule *q, rl_notify_kind kind, uint64_t used)
{
	rl_notify_event ev = { .kind = kind, .ts = rl_daemon_now(), .used = used, .limit = q->limit,
			       .slow_down = q->slow_down };
	rl_daemon_describe(d, &q->mac, &ev);
	rl_daemon_notify(d, &ev);
}

static void quota_event(rl_daemon *d, rl_event_type type, const rl_mac *mac, int64_t a)
{
	rl_device *dev = rl_devtab_find(d->devs, mac);
	rl_event ev = { .ts = rl_daemon_now(), .type = (uint16_t)type, .dev = dev ? dev->idx : RL_EV_NO_DEV, .a = a };
	rl_events_add(d->events, &ev);
}

static void step_quotas(rl_daemon *d, int64_t now)
{
	bool dirty = false;
	for (size_t i = 0; i < d->rules.n_quotas; i++) {
		const rl_quota_rule *q = &d->rules.quotas[i];
		rl_quota_live *l = &d->qlive[i];
		rl_quota_run before = l->run;
		rl_quota_bounds(q->period, q->reset_day, now, &l->start, &l->end);
		l->used = rl_daemon_traffic_on(d) ? quota_used(d, l, q, l->start, now) : 0;
		unsigned act = rl_quota_step(&l->run, now, l->start, l->used, q->limit);
		char mac[RL_MAC_STRLEN];
		rl_mac_format(&q->mac, mac);
		if (act & RL_QA_RESET)
			quota_event(d, RL_EV_QUOTA_RESET, &q->mac, 0);
		if (act & RL_QA_WARN) {
			syslog(LOG_INFO, "quota of %s at 80 %%", mac);
			quota_event(d, RL_EV_QUOTA_WARN, &q->mac, (int64_t)l->used);
			quota_notice(d, q, RL_NE_QUOTA_WARN, l->used);
		}
		if (act & RL_QA_ENFORCE) {
			syslog(LOG_NOTICE, "quota of %s used up: %s", mac, q->slow_down ? "slowed down" : "blocked");
			quota_event(d, RL_EV_QUOTA_EXCEEDED, &q->mac, (int64_t)l->used);
			quota_notice(d, q, RL_NE_QUOTA_EXCEEDED, l->used);
		}
		if (act & RL_QA_RELEASE)
			syslog(LOG_INFO, "quota of %s: let through again", mac);
		dirty |= before.period_start != l->run.period_start || before.warned != l->run.warned ||
			 before.enforced != l->run.enforced || before.allow_until != l->run.allow_until;
	}
	if (dirty)
		save_quotas(d);
}

/* ---- what is wanted now ---- */

static rl_tc_rule *rule_for(rl_tc_rule *rules, size_t *n, const rl_mac *mac)
{
	for (size_t i = 0; i < *n; i++)
		if (!memcmp(rules[i].mac, mac->b, 6))
			return &rules[i];
	if (*n >= MAX_TC_RULES)
		return NULL;
	rl_tc_rule *r = &rules[(*n)++];
	memset(r, 0, sizeof(*r));
	memcpy(r->mac, mac->b, 6);
	return r;
}

/* The lower of two rates, 0 being "no limit". */
static uint32_t tighter(uint32_t a, uint32_t b)
{
	return !a ? b : !b ? a : RL_MIN(a, b);
}

static void apply(rl_daemon *d, int64_t now)
{
	static rl_tc_rule rules[MAX_TC_RULES];
	rl_mac blocked[MAX_TC_RULES];
	size_t n = 0, n_blocked = 0;
	if (d->role.gateway) {
		for (size_t i = 0; i < d->rules.n_limits; i++) {
			const rl_limit_rule *l = &d->rules.limits[i];
			if (!rl_schedule_active_at(&l->sched, now))
				continue;
			rl_tc_rule *r = rule_for(rules, &n, &l->mac);
			if (r) {
				r->down_kbps = tighter(r->down_kbps, l->down_kbps);
				r->up_kbps = tighter(r->up_kbps, l->up_kbps);
			}
		}
		for (size_t i = 0; i < d->rules.n_quotas; i++) {
			const rl_quota_rule *q = &d->rules.quotas[i];
			if (!d->qlive[i].run.enforced)
				continue;
			if (!q->slow_down) {
				if (n_blocked < MAX_TC_RULES)
					blocked[n_blocked++] = q->mac;
				continue;
			}
			rl_tc_rule *r = rule_for(rules, &n, &q->mac);
			if (r) {
				r->down_kbps = tighter(r->down_kbps, q->down_kbps);
				r->up_kbps = tighter(r->up_kbps, q->up_kbps);
			}
		}
	}

	if (rl_shaper_set_rules(d->shaper, rules, n)) {
		int ports = rl_shaper_sync(d->shaper, false);
		syslog(LOG_INFO, "speed limits: %zu device(s) on %d port(s)", n, ports);
		rl_event ev = { .ts = now, .type = RL_EV_LIMIT_APPLIED, .dev = RL_EV_NO_DEV, .a = (int64_t)n };
		rl_events_add(d->events, &ev);
	} else {
		rl_shaper_sync(d->shaper, false); /* ports that came up since */
	}

	if (!d->role.gateway)
		return;
	/* local networks a blocked device may still reach */
	rl_nft_net local[RL_BLOCK_MAX_NETS];
	size_t n_local = 0;
	for (size_t i = 0; i < d->net.nv.local.n && n_local < RL_BLOCK_MAX_NETS; i++) {
		const rl_cidr *c = &d->net.nv.local.items[i];
		local[n_local].family = c->net.family;
		memcpy(local[n_local].addr, c->net.a, 16);
		local[n_local++].prefix = c->prefix;
	}
	bool fresh[MAX_TC_RULES];
	for (size_t i = 0; i < n_blocked; i++)
		fresh[i] = !rl_block_has(d->block, &blocked[i]);
	if (rl_block_set(d->block, blocked, n_blocked, local, n_local) != 0)
		return;
	/* established and offloaded connections of a newly blocked device end now */
	for (size_t i = 0; i < n_blocked; i++) {
		if (!fresh[i])
			continue;
		rl_ip ips[16];
		size_t k = rl_neigh_ips(d->neigh, &blocked[i], ips, RL_ARRAY_SIZE(ips));
		int dropped = rl_ct_kill(ips, k);
		char mac[RL_MAC_STRLEN];
		rl_mac_format(&blocked[i], mac);
		syslog(LOG_NOTICE, "blocked %s from the internet (%d connections dropped)", mac, dropped);
	}
}

/* ---- LAN ports: bridge members from netifd ---- */

typedef struct {
	char (*ports)[IFNAMSIZ];
	int n, max;
	bool bridge;
} members_ctx;

static void add_port(members_ctx *c, const char *name)
{
	for (int i = 0; i < c->n; i++)
		if (!strcmp(c->ports[i], name))
			return;
	if (c->n < c->max)
		snprintf(c->ports[c->n++], IFNAMSIZ, "%s", name);
}

static void members_cb(struct ubus_request *req, int type, struct blob_attr *msg)
{
	members_ctx *c = req->priv;
	static const struct blobmsg_policy p = { "bridge-members", BLOBMSG_TYPE_ARRAY };
	struct blob_attr *list, *cur;
	int rem;
	blobmsg_parse(&p, 1, &list, blob_data(msg), blob_len(msg));
	if (!list)
		return;
	c->bridge = true;
	blobmsg_for_each_attr(cur, list, rem)
		if (blobmsg_type(cur) == BLOBMSG_TYPE_STRING)
			add_port(c, blobmsg_get_string(cur));
}

/* Adds the bridge members of dev; false when netifd does not know it as a bridge. */
static bool bridge_members(rl_daemon *d, uint32_t id, const char *dev, members_ctx *c)
{
	struct blob_buf b = { 0 };
	blob_buf_init(&b, 0);
	blobmsg_add_string(&b, "name", dev);
	c->bridge = false;
	ubus_invoke(d->ubus_ctx, id, "status", b.head, members_cb, c, 3000);
	blob_buf_free(&b);
	return c->bridge;
}

/* The device a VLAN interface sits on (br-lan.1 → br-lan), from sysfs; false when none. */
static bool lower_dev(const char *dev, char *out, size_t size)
{
	char pattern[64];
	glob_t g;
	snprintf(pattern, sizeof(pattern), "/sys/class/net/%s/lower_*", dev);
	if (glob(pattern, 0, NULL, &g) != 0)
		return false;
	const char *name = strrchr(g.gl_pathv[0], '/');
	bool ok = name && !strncmp(name + 1, "lower_", 6);
	if (ok)
		snprintf(out, size, "%s", name + 7);
	globfree(&g);
	return ok;
}

void rl_control_ports(rl_daemon *d)
{
	char ports[RL_SHAPER_MAX_PORTS][IFNAMSIZ];
	members_ctx c = { ports, 0, RL_SHAPER_MAX_PORTS, false };
	uint32_t id;
	if (!d->role.gateway || !d->ubus_ctx || ubus_lookup_id(d->ubus_ctx, "network.device", &id))
		return;
	for (int i = 0; i < d->net.n_lan; i++) {
		char dev[IFNAMSIZ], lower[IFNAMSIZ];
		if (!if_indextoname((unsigned)d->net.lan_ifindex[i], dev))
			continue;
		if (bridge_members(d, id, dev, &c))
			continue;
		if (lower_dev(dev, lower, sizeof(lower)) && bridge_members(d, id, lower, &c))
			continue;
		add_port(&c, dev); /* a plain port */
	}
	bool same = c.n == d->n_ports;
	for (int i = 0; i < c.n && same; i++)
		same = !strcmp(ports[i], d->ports[i]);
	if (same)
		return;
	memcpy(d->ports, ports, sizeof(ports));
	d->n_ports = c.n;
	rl_shaper_set_ports(d->shaper, (const char(*)[IFNAMSIZ])d->ports, d->n_ports);
	rl_shaper_sync(d->shaper, false);
	char list[256] = "";
	size_t len = 0;
	for (int i = 0; i < c.n; i++) {
		int w = snprintf(list + len, sizeof(list) - len, "%s%.15s", i ? " " : "", ports[i]);
		if (w < 0 || (size_t)w >= sizeof(list) - len)
			break;
		len += (size_t)w;
	}
	syslog(LOG_INFO, "LAN ports for speed limits: %s", c.n ? list : "none");
}

/* ---- public ---- */

void rl_control_init(rl_daemon *d)
{
	char path[256];
	rl_quota_saved *saved = NULL;
	size_t n_saved = 0;
	mkdir(RL_RUN_DIR, 0755);
	d->shaper = rl_shaper_new(RL_RUN_DIR "/shaped");
	d->block = rl_block_new();
	rl_config_rules(&d->rules);
	quota_path(d, path, sizeof(path));
	if (rl_quota_load(path, &saved, &n_saved) != 0)
		syslog(LOG_WARNING, "damaged %s: quota states start over", path);
	rebuild_live(d, NULL, 0, saved, n_saved);
	free(saved);
}

void rl_control_reload(rl_daemon *d)
{
	rl_quota_live *old = d->qlive;
	size_t n_old = d->rules.n_quotas;
	d->qlive = NULL;
	rl_rules_free(&d->rules);
	rl_config_rules(&d->rules);
	rebuild_live(d, old, n_old, NULL, 0);
	free(old);
	rl_shaper_retry(d->shaper);
	rl_block_retry(d->block);
	save_quotas(d);
	rl_control_evaluate(d);
}

void rl_control_check(rl_daemon *d)
{
	rl_shaper_sync(d->shaper, true);
	rl_block_check(d->block);
}

void rl_control_evaluate(rl_daemon *d)
{
	int64_t now = rl_daemon_now();
	if (d->role.gateway)
		step_quotas(d, now);
	apply(d, now);
}

void rl_control_shutdown(rl_daemon *d)
{
	rl_shaper_free(d->shaper, true);
	rl_block_free(d->block, true);
	d->shaper = NULL;
	d->block = NULL;
	rl_rules_free(&d->rules);
	free(d->qlive);
	d->qlive = NULL;
}

int rl_control_allow(rl_daemon *d, const char *section, bool until_period)
{
	int64_t now = rl_daemon_now();
	for (size_t i = 0; i < d->rules.n_quotas; i++) {
		rl_quota_live *l = &d->qlive[i];
		const rl_quota_rule *q = &d->rules.quotas[i];
		if (strcmp(l->section, section))
			continue;
		if (!l->run.period_start)
			step_quotas(d, now); /* not evaluated yet: its period first */
		rl_quota_bounds(q->period, q->reset_day, now, &l->start, &l->end);
		rl_quota_allow(&l->run, until_period ? l->end : now + 3600);
		char mac[RL_MAC_STRLEN];
		rl_mac_format(&q->mac, mac);
		syslog(LOG_NOTICE, "quota of %s: let through until %s", mac, until_period ? "the period ends" : "an hour from now");
		save_quotas(d);
		apply(d, now);
		return 0;
	}
	return -1;
}

size_t rl_control_quotas(rl_daemon *d, rl_quota_view *out, size_t max)
{
	size_t k = 0;
	for (size_t i = 0; i < d->rules.n_quotas && k < max; i++) {
		rl_quota_live *l = &d->qlive[i];
		if (!l->start) /* not evaluated yet */
			rl_quota_bounds(d->rules.quotas[i].period, d->rules.quotas[i].reset_day, rl_daemon_now(), &l->start,
					&l->end);
		out[k++] = (rl_quota_view){ &d->rules.quotas[i], &l->run, l->used, l->start, l->end };
	}
	return k;
}

const char *rl_control_error(const rl_daemon *d)
{
	const char *e = d->shaper ? rl_shaper_error(d->shaper) : "";
	return e[0] || !d->block ? e : rl_block_error(d->block);
}

size_t rl_control_active_limits(const rl_daemon *d)
{
	const rl_tc_rule *r;
	return d->shaper ? rl_shaper_rules(d->shaper, &r) : 0;
}
