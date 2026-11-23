#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include <libubox/blobmsg.h>

#include "core/dnslog.h"
#include "core/query.h"
#include "core/util.h"
#include "core/version.h"
#include "sys/api.h"
#include "sys/daemon.h"

#define MAX_DEVICES_OUT 500
#define MAX_EVENTS_OUT 1000
#define MAX_IPS 8

static const char *const CAPABILITIES[] = { "traffic", "wifi", "latency", "speedtest", "limits", "quotas", "dns", "notify" };

static struct rl_daemon *D;
static struct blob_buf b;

void rl_api_init(struct rl_daemon *d)
{
	D = d;
}

/* ---- helpers ---- */

static void add_mac(const char *name, uint16_t dev)
{
	char s[RL_MAC_STRLEN];
	rl_device *d;
	if (dev == RL_DEV_UNKNOWN) {
		blobmsg_add_string(&b, name, "unknown");
	} else if (dev == RL_DEV_ROUTER) {
		blobmsg_add_string(&b, name, "router");
	} else if ((d = rl_devtab_by_idx(D->devs, dev))) {
		rl_mac_format(&d->mac, s);
		blobmsg_add_string(&b, name, s);
	} else {
		blobmsg_add_string(&b, name, "unknown");
	}
}

/* "AA:..", "unknown" or "router" -> device; -1 when the MAC was never seen, -2 when malformed */
static int parse_device(const char *s)
{
	rl_mac mac;
	rl_device *d;
	if (!strcmp(s, "unknown"))
		return RL_DEV_UNKNOWN;
	if (!strcmp(s, "router"))
		return RL_DEV_ROUTER;
	if (!rl_mac_parse(s, &mac))
		return -2;
	d = rl_devtab_find(D->devs, &mac);
	return d ? d->idx : -1;
}

static int parse_class(struct blob_attr *a, bool allow_wan, int *cls, bool *wan)
{
	*wan = false;
	*cls = RL_CLASS_INTERNET;
	if (!a)
		return 0;
	const char *s = blobmsg_get_string(a);
	if (!strcmp(s, "internet"))
		*cls = RL_CLASS_INTERNET;
	else if (!strcmp(s, "lan"))
		*cls = RL_CLASS_LAN;
	else if (!strcmp(s, "router"))
		*cls = RL_CLASS_ROUTER;
	else if (!strcmp(s, "all"))
		*cls = RL_CLS_ANY;
	else if (allow_wan && !strcmp(s, "wan"))
		*wan = true;
	else
		return -1;
	return 0;
}

static int64_t get_i64(struct blob_attr *a, int64_t def)
{
	return a ? (int64_t)blobmsg_cast_u64(a) : def;
}

static rl_qctx query_ctx(void)
{
	return (rl_qctx){ .store = D->store, .agg = D->agg, .ret = &D->cfg.ret, .now = rl_daemon_now() };
}

static const rl_rate *rate_of(uint16_t dev)
{
	const rl_rate *r;
	size_t n = rl_agg_rates(D->agg, &r);
	for (size_t i = 0; i < n; i++)
		if (r[i].dev == dev)
			return &r[i];
	return NULL;
}

/* ---- info ---- */

static int m_info(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req, const char *method,
		  struct blob_attr *msg)
{
	void *c;
	blob_buf_init(&b, 0);
	blobmsg_add_string(&b, "version", rl_version());
	blobmsg_add_u32(&b, "api", RL_API_VERSION);
	c = blobmsg_open_array(&b, "roles");
	if (D->role.gateway)
		blobmsg_add_string(&b, NULL, "gateway");
	if (D->role.ap)
		blobmsg_add_string(&b, NULL, "ap");
	blobmsg_close_array(&b, c);
	c = blobmsg_open_array(&b, "modules");
	if (rl_daemon_traffic_on(D))
		blobmsg_add_string(&b, NULL, "traffic");
	if (rl_daemon_wifi_on(D))
		blobmsg_add_string(&b, NULL, "wifi");
	if (rl_daemon_probe_on(D))
		blobmsg_add_string(&b, NULL, "latency");
	if (D->role.gateway) {
		blobmsg_add_string(&b, NULL, "speedtest"); /* WAN counters: gateway only */
		blobmsg_add_string(&b, NULL, "limits");
	}
	if (D->role.gateway && rl_daemon_traffic_on(D))
		blobmsg_add_string(&b, NULL, "quotas"); /* they count the traffic records */
	if (D->visits && rl_visits_on(D->visits))
		blobmsg_add_string(&b, NULL, "dns");
	if (D->role.gateway)
		blobmsg_add_string(&b, NULL, "notify");
	blobmsg_close_array(&b, c);
	/* every module this build has, switched on or not (modules only lists the running ones) */
	c = blobmsg_open_array(&b, "capabilities");
	for (size_t i = 0; i < ARRAY_SIZE(CAPABILITIES); i++)
		blobmsg_add_string(&b, NULL, CAPABILITIES[i]);
	blobmsg_close_array(&b, c);
	blobmsg_add_string(&b, "offload", rl_offload_name(D->role.offload));
	blobmsg_add_u8(&b, "offload_warning", rl_offload_warning(D->role.offload));
	blobmsg_add_u8(&b, "nlbwmon_running", D->role.nlbwmon_running);
	blobmsg_add_u8(&b, "conntrack_accounting", rl_ct_accounting());
	blobmsg_add_u8(&b, "time_synced", D->synced);
	blobmsg_add_string(&b, "zonename", D->zonename);
	blobmsg_add_string(&b, "data_dir", D->cfg.data_dir);
	blobmsg_add_u64(&b, "storage_used", rl_daemon_storage(D));
	blobmsg_add_u64(&b, "storage_limit", D->max_bytes);
	blobmsg_add_u32(&b, "commit_interval", (uint32_t)D->commit_interval);
	blobmsg_add_u64(&b, "last_commit", (uint64_t)D->last_commit);
	blobmsg_add_u32(&b, "sample_interval", (uint32_t)D->cfg.sample_interval);
	blobmsg_add_u32(&b, "live_interval", (uint32_t)D->cfg.live_interval);
	blobmsg_add_u64(&b, "live_until", (uint64_t)D->live_until);
	blobmsg_add_u64(&b, "started", (uint64_t)D->started);
	blobmsg_add_u64(&b, "events_lost", D->ct ? rl_ct_events_lost(D->ct) : 0);
	blobmsg_add_string(&b, "limits_error", rl_control_error(D));
	blobmsg_add_u8(&b, "dns_enabled", D->visits && rl_visits_on(D->visits));
	c = blobmsg_open_table(&b, "retention");
	blobmsg_add_u32(&b, "minute_hours", (uint32_t)D->cfg.ret.minute_hours);
	blobmsg_add_u32(&b, "hour_days", (uint32_t)D->cfg.ret.hour_days);
	blobmsg_add_u32(&b, "day_days", (uint32_t)D->cfg.ret.day_days);
	blobmsg_add_u32(&b, "event_days", (uint32_t)D->cfg.ret.event_days);
	blobmsg_add_u32(&b, "signal_minute_days", (uint32_t)D->cfg.signal_minute_days);
	blobmsg_add_u32(&b, "signal_hour_days", (uint32_t)D->cfg.signal_hour_days);
	blobmsg_add_u32(&b, "latency_minute_days", (uint32_t)D->cfg.latency_minute_days);
	blobmsg_add_u32(&b, "latency_hour_days", (uint32_t)D->cfg.latency_hour_days);
	blobmsg_add_u32(&b, "outage_days", (uint32_t)D->cfg.outage_days);
	blobmsg_close_table(&b, c);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- devices ---- */

typedef struct {
	uint64_t *rx, *tx;
	size_t n;
} today_ctx;

static bool today_cb(const rl_rec *r, void *x)
{
	today_ctx *t = x;
	if (r->dev < t->n && (r->cls == RL_CLASS_INTERNET || r->cls == RL_CLASS_LAN)) {
		t->rx[r->dev] += r->rx;
		t->tx[r->dev] += r->tx;
	}
	return true;
}

static int m_devices(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		     const char *method, struct blob_attr *msg)
{
	size_t n = rl_devtab_count(D->devs);
	today_ctx t = { calloc(n + 1, sizeof(uint64_t)), calloc(n + 1, sizeof(uint64_t)), n };
	if (!t.rx || !t.tx)
		abort();
	rl_agg_open(D->agg, RL_TIER_DAY, today_cb, &t); /* the open day bucket is today */

	blob_buf_init(&b, 0);
	void *list = blobmsg_open_array(&b, "devices");
	for (size_t i = 0; i < n && i < MAX_DEVICES_OUT; i++) {
		rl_device *d = rl_devtab_at(D->devs, i);
		rl_ip ips[MAX_IPS];
		char s[RL_IP_STRLEN];
		size_t k = rl_neigh_ips(D->neigh, &d->mac, ips, MAX_IPS);
		const rl_rate *rate = rate_of(d->idx);
		void *e = blobmsg_open_table(&b, NULL);
		add_mac("mac", d->idx);
		blobmsg_add_string(&b, "name", d->name);
		blobmsg_add_string(&b, "hostname", d->hostname);
		for (int family = 4; family <= 6; family += 2) {
			void *a = blobmsg_open_array(&b, family == 4 ? "ipv4" : "ipv6");
			for (size_t j = 0; j < k; j++)
				if (ips[j].family == family) {
					rl_ip_format(&ips[j], s);
					blobmsg_add_string(&b, NULL, s);
				}
			blobmsg_close_array(&b, a);
		}
		blobmsg_add_u64(&b, "first_seen", (uint64_t)d->first_seen);
		blobmsg_add_u64(&b, "last_seen", (uint64_t)d->last_seen);
		const rl_wifi_sta *st = rl_daemon_wifi_on(D) ? rl_wifi_find(D->wifi, &d->mac) : NULL;
		const rl_devflag *flag = rl_daemon_devflag(D, &d->mac);
		/* without traffic accounting (an access point) a station is online while it is associated */
		blobmsg_add_u8(&b, "online", st && !rl_daemon_traffic_on(D) ? st->associated : d->online);
		blobmsg_add_u8(&b, "random_mac", rl_mac_is_random(&d->mac));
		blobmsg_add_u8(&b, "trusted", flag && flag->trusted);
		blobmsg_add_u8(&b, "watch", flag && flag->watch);
		if (st && st->associated) {
			blobmsg_add_string(&b, "ifname", st->ifname);
			if (st->s.has & RL_STA_SIGNAL)
				blobmsg_add_u32(&b, "signal", (uint32_t)(int32_t)st->s.signal);
		}
		blobmsg_add_u64(&b, "today_rx", t.rx[i]);
		blobmsg_add_u64(&b, "today_tx", t.tx[i]);
		blobmsg_add_u64(&b, "rx_rate", rate ? rate->rx_rate : 0);
		blobmsg_add_u64(&b, "tx_rate", rate ? rate->tx_rate : 0);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	if (n > MAX_DEVICES_OUT)
		blobmsg_add_u8(&b, "truncated", true);
	free(t.rx);
	free(t.tx);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- live ---- */

static int cmp_rate(const void *x, const void *y)
{
	const rl_rate *a = x, *c = y;
	uint64_t va = a->rx_rate + a->tx_rate, vc = c->rx_rate + c->tx_rate;
	return va < vc ? 1 : va > vc ? -1 : 0;
}

static int m_live(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req, const char *method,
		  struct blob_attr *msg)
{
	rl_daemon_live(D);
	const rl_rate *r;
	size_t n = rl_agg_rates(D->agg, &r);
	rl_rate *sorted = malloc((n ? n : 1) * sizeof(rl_rate));
	if (!sorted)
		abort();
	memcpy(sorted, r, n * sizeof(rl_rate));
	qsort(sorted, n, sizeof(rl_rate), cmp_rate);
	const rl_rate *wan = rate_of(RL_DEV_WAN);
	uint32_t online = 0;
	for (size_t i = 0; i < rl_devtab_count(D->devs); i++)
		online += rl_devtab_at(D->devs, i)->online;

	blob_buf_init(&b, 0);
	blobmsg_add_u64(&b, "ts", (uint64_t)rl_daemon_now());
	blobmsg_add_u64(&b, "lease_until", (uint64_t)D->live_until);
	blobmsg_add_u32(&b, "interval", (uint32_t)D->cfg.live_interval);
	void *w = blobmsg_open_table(&b, "wan");
	blobmsg_add_u64(&b, "rx_rate", wan ? wan->rx_rate : 0);
	blobmsg_add_u64(&b, "tx_rate", wan ? wan->tx_rate : 0);
	blobmsg_close_table(&b, w);
	blobmsg_add_u32(&b, "online", online);
	void *list = blobmsg_open_array(&b, "devices");
	for (size_t i = 0, k = 0; i < n && k < MAX_DEVICES_OUT; i++) {
		if (sorted[i].dev == RL_DEV_WAN || sorted[i].dev == RL_DEV_ROUTER)
			continue;
		void *e = blobmsg_open_table(&b, NULL);
		add_mac("mac", sorted[i].dev);
		blobmsg_add_u64(&b, "rx_rate", sorted[i].rx_rate);
		blobmsg_add_u64(&b, "tx_rate", sorted[i].tx_rate);
		blobmsg_close_table(&b, e);
		k++;
	}
	blobmsg_close_array(&b, list);
	free(sorted);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- history ---- */

enum { H_MAC, H_START, H_END, H_CLASS, H_HOURS, H_POINTS, __H_MAX };
static const struct blobmsg_policy history_policy[__H_MAX] = {
	[H_MAC] = { "mac", BLOBMSG_TYPE_STRING },     [H_START] = { "start", BLOBMSG_CAST_INT64 },
	[H_END] = { "end", BLOBMSG_CAST_INT64 },      [H_CLASS] = { "class", BLOBMSG_TYPE_STRING },
	[H_HOURS] = { "hours", BLOBMSG_CAST_INT64 },  [H_POINTS] = { "max_points", BLOBMSG_CAST_INT64 },
};

static int m_history(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		     const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[__H_MAX];
	blobmsg_parse(history_policy, __H_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[H_START] || !tb[H_END])
		return UBUS_STATUS_INVALID_ARGUMENT;
	rl_history_q q = {
		.start = get_i64(tb[H_START], 0),
		.end = get_i64(tb[H_END], 0),
		.dev = RL_DEV_ALL,
		.hours_mask = (uint32_t)get_i64(tb[H_HOURS], 0),
		.max_points = (int)get_i64(tb[H_POINTS], 0),
	};
	bool wan;
	if (parse_class(tb[H_CLASS], true, &q.cls, &wan) != 0)
		return UBUS_STATUS_INVALID_ARGUMENT;
	if (wan)
		q.dev = RL_DEV_WAN;
	else if (q.cls == RL_CLASS_ROUTER)
		q.dev = RL_DEV_ROUTER;
	else if (tb[H_MAC]) {
		int dev = parse_device(blobmsg_get_string(tb[H_MAC]));
		if (dev == -2)
			return UBUS_STATUS_INVALID_ARGUMENT;
		if (dev == -1)
			return UBUS_STATUS_NOT_FOUND;
		q.dev = dev;
	}
	rl_qctx c = query_ctx();
	rl_history h;
	if (rl_query_history(&c, &q, &h) != 0)
		return UBUS_STATUS_INVALID_ARGUMENT;

	blob_buf_init(&b, 0);
	blobmsg_add_u64(&b, "start", (uint64_t)q.start);
	blobmsg_add_u64(&b, "end", (uint64_t)q.end);
	blobmsg_add_u64(&b, "step", (uint64_t)h.step);
	blobmsg_add_string(&b, "tier", rl_tier_name(h.tier));
	void *list = blobmsg_open_array(&b, "points");
	for (size_t i = 0; i < h.n; i++) {
		void *p = blobmsg_open_array(&b, NULL);
		blobmsg_add_u64(&b, NULL, (uint64_t)h.pts[i].ts);
		if (h.pts[i].gap) {
			blobmsg_add_field(&b, BLOBMSG_TYPE_UNSPEC, NULL, NULL, 0);
			blobmsg_add_field(&b, BLOBMSG_TYPE_UNSPEC, NULL, NULL, 0);
		} else {
			blobmsg_add_u64(&b, NULL, h.pts[i].rx);
			blobmsg_add_u64(&b, NULL, h.pts[i].tx);
		}
		blobmsg_close_array(&b, p);
	}
	blobmsg_close_array(&b, list);
	rl_history_free(&h);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- summary ---- */

enum { S_START, S_END, S_CLASS, S_HOURS, S_SORT, S_LIMIT, S_OFFSET, __S_MAX };
static const struct blobmsg_policy summary_policy[__S_MAX] = {
	[S_START] = { "start", BLOBMSG_CAST_INT64 }, [S_END] = { "end", BLOBMSG_CAST_INT64 },
	[S_CLASS] = { "class", BLOBMSG_TYPE_STRING }, [S_HOURS] = { "hours", BLOBMSG_CAST_INT64 },
	[S_SORT] = { "sort", BLOBMSG_TYPE_STRING },   [S_LIMIT] = { "limit", BLOBMSG_CAST_INT64 },
	[S_OFFSET] = { "offset", BLOBMSG_CAST_INT64 },
};

static int m_summary(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		     const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[__S_MAX];
	blobmsg_parse(summary_policy, __S_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[S_START] || !tb[S_END])
		return UBUS_STATUS_INVALID_ARGUMENT;
	rl_summary_q q = {
		.start = get_i64(tb[S_START], 0),
		.end = get_i64(tb[S_END], 0),
		.hours_mask = (uint32_t)get_i64(tb[S_HOURS], 0),
	};
	bool wan;
	if (parse_class(tb[S_CLASS], false, &q.cls, &wan) != 0)
		return UBUS_STATUS_INVALID_ARGUMENT;
	rl_sort sort = RL_SORT_TOTAL;
	if (tb[S_SORT]) {
		const char *s = blobmsg_get_string(tb[S_SORT]);
		if (!strcmp(s, "rx"))
			sort = RL_SORT_RX;
		else if (!strcmp(s, "tx"))
			sort = RL_SORT_TX;
		else if (strcmp(s, "total"))
			return UBUS_STATUS_INVALID_ARGUMENT;
	}
	int64_t limit = get_i64(tb[S_LIMIT], 50), offset = get_i64(tb[S_OFFSET], 0);
	if (limit < 1 || limit > MAX_DEVICES_OUT || offset < 0)
		return UBUS_STATUS_INVALID_ARGUMENT;

	rl_qctx c = query_ctx();
	rl_summary s;
	if (rl_query_summary(&c, &q, &s) != 0)
		return UBUS_STATUS_INVALID_ARGUMENT;
	rl_summary_sort(&s, sort);

	blob_buf_init(&b, 0);
	blobmsg_add_u64(&b, "start_exact", (uint64_t)s.start_exact);
	blobmsg_add_u64(&b, "end", (uint64_t)q.end);
	blobmsg_add_string(&b, "granularity", rl_tier_name(s.granularity));
	blobmsg_add_u64(&b, "rx", s.rx);
	blobmsg_add_u64(&b, "tx", s.tx);
	blobmsg_add_u64(&b, "wan_rx", s.wan_rx);
	blobmsg_add_u64(&b, "wan_tx", s.wan_tx);
	blobmsg_add_u32(&b, "count", (uint32_t)s.n);
	void *list = blobmsg_open_array(&b, "devices");
	for (size_t i = (size_t)offset; i < s.n && i < (size_t)(offset + limit); i++) {
		void *e = blobmsg_open_table(&b, NULL);
		add_mac("mac", s.devs[i].dev);
		blobmsg_add_u64(&b, "rx", s.devs[i].rx);
		blobmsg_add_u64(&b, "tx", s.devs[i].tx);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	rl_summary_free(&s);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- events ---- */

enum { E_START, E_END, E_TYPES, E_MAC, E_LIMIT, E_OFFSET, __E_MAX };
static const struct blobmsg_policy events_policy[__E_MAX] = {
	[E_START] = { "start", BLOBMSG_CAST_INT64 }, [E_END] = { "end", BLOBMSG_CAST_INT64 },
	[E_TYPES] = { "types", BLOBMSG_TYPE_ARRAY }, [E_MAC] = { "mac", BLOBMSG_TYPE_STRING },
	[E_LIMIT] = { "limit", BLOBMSG_CAST_INT64 }, [E_OFFSET] = { "offset", BLOBMSG_CAST_INT64 },
};

static int m_events(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		    const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[__E_MAX], *cur;
	int rem;
	blobmsg_parse(events_policy, __E_MAX, tb, blob_data(msg), blob_len(msg));
	int64_t start = get_i64(tb[E_START], 0), end = get_i64(tb[E_END], rl_daemon_now() + 1);
	int64_t limit = get_i64(tb[E_LIMIT], 200), offset = get_i64(tb[E_OFFSET], 0);
	if (start >= end || limit < 1 || limit > MAX_EVENTS_OUT || offset < 0)
		return UBUS_STATUS_INVALID_ARGUMENT;
	uint32_t mask = 0;
	if (tb[E_TYPES])
		blobmsg_for_each_attr(cur, tb[E_TYPES], rem) {
			if (blobmsg_type(cur) != BLOBMSG_TYPE_STRING)
				return UBUS_STATUS_INVALID_ARGUMENT;
			rl_event_type t = rl_event_parse(blobmsg_get_string(cur));
			if (!t)
				return UBUS_STATUS_INVALID_ARGUMENT;
			mask |= 1u << t;
		}
	int dev = -1;
	if (tb[E_MAC]) {
		dev = parse_device(blobmsg_get_string(tb[E_MAC]));
		if (dev == -2)
			return UBUS_STATUS_INVALID_ARGUMENT;
		if (dev == -1)
			dev = 0x10000; /* never seen: no events */
	}
	rl_event *out = malloc((size_t)limit * sizeof(rl_event));
	size_t n, total;
	if (!out)
		abort();
	rl_events_scan(D->events, start, end, mask, dev, (size_t)offset, (size_t)limit, out, &n, &total);

	blob_buf_init(&b, 0);
	blobmsg_add_u32(&b, "count", (uint32_t)total);
	void *list = blobmsg_open_array(&b, "events");
	for (size_t i = 0; i < n; i++) {
		void *e = blobmsg_open_table(&b, NULL);
		blobmsg_add_u64(&b, "ts", (uint64_t)out[i].ts);
		blobmsg_add_string(&b, "type", rl_event_name((rl_event_type)out[i].type));
		if (out[i].dev != RL_EV_NO_DEV)
			add_mac("mac", out[i].dev);
		if (out[i].a)
			blobmsg_add_u64(&b, "value", (uint64_t)out[i].a);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	free(out);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- wireless (AP role) ---- */

/* blobmsg prints INT32 signed: dBm values go out as negative numbers */
static void add_int(const char *name, int v)
{
	blobmsg_add_u32(&b, name, (uint32_t)(int32_t)v);
}

static void add_null(const char *name)
{
	blobmsg_add_field(&b, BLOBMSG_TYPE_UNSPEC, name, NULL, 0);
}

/* The survey entry of the radio behind an interface. */
static const rl_survey_entry *radio_survey(const rl_nl_iface *ifc)
{
	return rl_wifi_survey_radio(D->wifi, ifc->wiphy, ifc->freq);
}

/* AP interfaces in sampling order, the first one of each radio flagged. */
static bool first_of_radio(int i)
{
	for (int j = 0; j < i; j++)
		if (D->ifaces[j].wiphy == D->ifaces[i].wiphy)
			return false;
	return true;
}

enum { ST_LIVE, __ST_MAX };
static const struct blobmsg_policy stations_policy[__ST_MAX] = { [ST_LIVE] = { "live", BLOBMSG_TYPE_BOOL } };

static int m_stations(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		      const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[__ST_MAX];
	char s[RL_MAC_STRLEN];
	blobmsg_parse(stations_policy, __ST_MAX, tb, blob_data(msg), blob_len(msg));
	if (tb[ST_LIVE] && blobmsg_get_bool(tb[ST_LIVE]))
		rl_daemon_wifi_live(D);
	bool on = rl_daemon_wifi_on(D);

	blob_buf_init(&b, 0);
	blobmsg_add_u64(&b, "ts", (uint64_t)rl_daemon_now());
	blobmsg_add_u64(&b, "live_until", (uint64_t)D->wifi_live_until);
	blobmsg_add_u32(&b, "interval", (uint32_t)rl_daemon_wifi_interval(D));
	void *list = blobmsg_open_array(&b, "interfaces");
	for (int i = 0; on && i < D->n_ifaces; i++) {
		const rl_nl_iface *ifc = &D->ifaces[i];
		const rl_survey_entry *sv = radio_survey(ifc);
		if (!ifc->freq)
			continue; /* not operating */
		void *e = blobmsg_open_table(&b, NULL);
		blobmsg_add_string(&b, "ifname", ifc->ifname);
		blobmsg_add_string(&b, "phy", ifc->phy);
		blobmsg_add_string(&b, "ssid", ifc->ssid);
		rl_mac_format(&ifc->bssid, s);
		blobmsg_add_string(&b, "bssid", s);
		blobmsg_add_u32(&b, "freq", ifc->freq);
		blobmsg_add_u32(&b, "channel", (uint32_t)rl_wifi_channel(ifc->freq));
		if (ifc->width)
			blobmsg_add_u32(&b, "width", ifc->width);
		if (sv && (sv->s.has & RL_SV_NOISE))
			add_int("noise", sv->s.noise);
		blobmsg_add_u32(&b, "stations", (uint32_t)rl_wifi_count_on(D->wifi, ifc->ifindex));
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);

	list = blobmsg_open_array(&b, "stations");
	for (size_t i = 0, k = 0; on && i < rl_wifi_count(D->wifi) && k < MAX_DEVICES_OUT; i++) {
		const rl_wifi_sta *st = rl_wifi_at(D->wifi, i);
		const rl_sta_sample *x = &st->s;
		if (!st->associated)
			continue;
		const rl_survey_entry *sv = NULL;
		for (int j = 0; j < D->n_ifaces && !sv; j++)
			if (D->ifaces[j].ifindex == st->ifindex)
				sv = radio_survey(&D->ifaces[j]);
		void *e = blobmsg_open_table(&b, NULL);
		rl_mac_format(&st->mac, s);
		blobmsg_add_string(&b, "mac", s);
		blobmsg_add_string(&b, "ifname", st->ifname);
		blobmsg_add_u32(&b, "freq", st->freq);
		if (x->has & RL_STA_SIGNAL)
			add_int("signal", x->signal);
		if (x->has & RL_STA_SIGNAL_AVG)
			add_int("signal_avg", x->signal_avg);
		if (sv && (sv->s.has & RL_SV_NOISE))
			add_int("noise", sv->s.noise);
		if (x->has & RL_STA_INACTIVE)
			blobmsg_add_u32(&b, "inactive_ms", x->inactive_ms);
		if (x->has & RL_STA_CONNECTED)
			blobmsg_add_u32(&b, "connected_sec", x->connected_sec);
		if (x->has & RL_STA_RX_RATE)
			blobmsg_add_u32(&b, "rx_rate", x->rx_rate);
		if (x->has & RL_STA_TX_RATE)
			blobmsg_add_u32(&b, "tx_rate", x->tx_rate);
		if (x->has & RL_STA_RX_MCS)
			blobmsg_add_u32(&b, "rx_mcs", x->rx_mcs);
		if (x->has & RL_STA_TX_MCS)
			blobmsg_add_u32(&b, "tx_mcs", x->tx_mcs);
		if (x->has & RL_STA_RX_NSS)
			blobmsg_add_u32(&b, "rx_nss", x->rx_nss);
		if (x->has & RL_STA_TX_NSS)
			blobmsg_add_u32(&b, "tx_nss", x->tx_nss);
		if (x->has & RL_STA_WIDTH)
			blobmsg_add_u32(&b, "width", x->width);
		if (x->has & RL_STA_MODE)
			blobmsg_add_string(&b, "mode", rl_wifi_mode_name(x->mode));
		if (x->has & RL_STA_BYTES) {
			blobmsg_add_u64(&b, "rx_bytes", x->rx_bytes);
			blobmsg_add_u64(&b, "tx_bytes", x->tx_bytes);
		}
		if (x->has & RL_STA_PACKETS) {
			blobmsg_add_u64(&b, "rx_packets", x->rx_packets);
			blobmsg_add_u64(&b, "tx_packets", x->tx_packets);
		}
		if (x->has & RL_STA_RETRIES)
			blobmsg_add_u32(&b, "tx_retries", x->tx_retries);
		if (x->has & RL_STA_FAILED)
			blobmsg_add_u32(&b, "tx_failed", x->tx_failed);
		blobmsg_close_table(&b, e);
		k++;
	}
	blobmsg_close_array(&b, list);
	return ubus_send_reply(ctx, req, b.head);
}

enum { G_MAC, G_START, G_END, G_POINTS, __G_MAX };
static const struct blobmsg_policy signal_policy[__G_MAX] = {
	[G_MAC] = { "mac", BLOBMSG_TYPE_STRING }, [G_START] = { "start", BLOBMSG_CAST_INT64 },
	[G_END] = { "end", BLOBMSG_CAST_INT64 },  [G_POINTS] = { "max_points", BLOBMSG_CAST_INT64 },
};

static int m_signal(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		    const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[__G_MAX];
	rl_mac mac;
	blobmsg_parse(signal_policy, __G_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[G_MAC] || !tb[G_START] || !tb[G_END] || !rl_mac_parse(blobmsg_get_string(tb[G_MAC]), &mac))
		return UBUS_STATUS_INVALID_ARGUMENT;
	rl_device *dev = rl_devtab_find(D->devs, &mac);
	if (!dev)
		return UBUS_STATUS_NOT_FOUND;
	int64_t start = get_i64(tb[G_START], 0), end = get_i64(tb[G_END], 0);
	rl_sigq_ctx c = {
		.minute = D->sig_minute,
		.hour = D->sig_hour,
		.wifi = rl_daemon_wifi_on(D) ? D->wifi : NULL,
		.now = rl_daemon_now(),
		.minute_days = D->cfg.signal_minute_days,
		.hour_days = D->cfg.signal_hour_days,
		.live_step = rl_daemon_wifi_interval(D),
	};
	rl_sig_history h;
	if (rl_sig_query(&c, dev->idx, start, end, (int)get_i64(tb[G_POINTS], 0), &h) != 0)
		return UBUS_STATUS_INVALID_ARGUMENT;

	blob_buf_init(&b, 0);
	blobmsg_add_u64(&b, "start", (uint64_t)start);
	blobmsg_add_u64(&b, "end", (uint64_t)end);
	blobmsg_add_u64(&b, "step", (uint64_t)h.step);
	blobmsg_add_string(&b, "tier", rl_sigq_tier_name(h.tier));
	void *list = blobmsg_open_array(&b, "points");
	for (size_t i = 0; i < h.n; i++) {
		const rl_sig_point *p = &h.pts[i];
		void *a = blobmsg_open_array(&b, NULL);
		blobmsg_add_u64(&b, NULL, (uint64_t)p->ts);
		if (p->flags & RL_SIG_F_SIGNAL) {
			add_int(NULL, p->avg_signal);
			add_int(NULL, p->min_signal);
		} else {
			add_null(NULL);
			add_null(NULL);
		}
		if (p->flags & RL_SIG_F_TX_RATE)
			blobmsg_add_u32(&b, NULL, p->avg_tx_rate);
		else
			add_null(NULL);
		if (p->flags & RL_SIG_F_RX_RATE)
			blobmsg_add_u32(&b, NULL, p->avg_rx_rate);
		else
			add_null(NULL);
		if (p->flags & RL_SIG_F_COUNTERS) {
			blobmsg_add_u64(&b, NULL, p->tx_retries);
			blobmsg_add_u64(&b, NULL, p->tx_failed);
		} else {
			add_null(NULL);
			add_null(NULL);
		}
		blobmsg_close_array(&b, a);
	}
	blobmsg_close_array(&b, list);
	rl_sig_history_free(&h);
	return ubus_send_reply(ctx, req, b.head);
}

static void add_busy(int pct)
{
	if (pct >= 0)
		blobmsg_add_u32(&b, "busy_pct", (uint32_t)pct);
	else
		add_null("busy_pct");
}

static int m_survey(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		    const char *method, struct blob_attr *msg)
{
	const rl_survey_entry *used[RL_NL_MAX_IFACES];
	int n_used = 0;
	bool on = rl_daemon_wifi_on(D);

	blob_buf_init(&b, 0);
	void *list = blobmsg_open_array(&b, "radios");
	for (int i = 0; on && i < D->n_ifaces; i++) {
		const rl_nl_iface *ifc = &D->ifaces[i];
		if (!first_of_radio(i))
			continue;
		const rl_survey_entry *sv = radio_survey(ifc);
		uint32_t freq = ifc->freq ? ifc->freq : sv ? sv->s.freq : 0;
		if (sv)
			used[n_used++] = sv;
		void *e = blobmsg_open_table(&b, NULL);
		blobmsg_add_string(&b, "ifname", ifc->ifname);
		blobmsg_add_string(&b, "phy", ifc->phy);
		blobmsg_add_u32(&b, "freq", freq);
		blobmsg_add_u32(&b, "channel", (uint32_t)rl_wifi_channel(freq));
		if (sv && (sv->s.has & RL_SV_NOISE))
			add_int("noise", sv->s.noise);
		if (sv && (sv->s.has & RL_SV_ACTIVE))
			blobmsg_add_u64(&b, "active_ms", sv->s.active_ms);
		if (sv && (sv->s.has & RL_SV_BUSY))
			blobmsg_add_u64(&b, "busy_ms", sv->s.busy_ms);
		if (sv && (sv->s.has & RL_SV_RX))
			blobmsg_add_u64(&b, "rx_ms", sv->s.rx_ms);
		if (sv && (sv->s.has & RL_SV_TX))
			blobmsg_add_u64(&b, "tx_ms", sv->s.tx_ms);
		add_busy(sv ? sv->busy_pct : -1);
		blobmsg_add_u64(&b, "updated", sv ? (uint64_t)sv->updated : 0);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);

	/* other channels: what the driver kept from scans (busy share since the last sample, else overall) */
	list = blobmsg_open_array(&b, "channels");
	for (size_t i = 0; on && i < rl_wifi_survey_count(D->wifi); i++) {
		const rl_survey_entry *sv = rl_wifi_survey_at(D->wifi, i);
		/* no data at all, or outside the Wi-Fi channel plans (mac80211_hwsim also scans 900 MHz S1G) */
		bool skip = (!(sv->s.has & RL_SV_NOISE) && sv->busy_pct < 0 && sv->busy_pct_total < 0) ||
			    !rl_wifi_channel(sv->s.freq);
		for (int j = 0; j < n_used && !skip; j++)
			skip = used[j] == sv;
		if (skip)
			continue;
		const char *phy = "";
		for (int j = 0; j < D->n_ifaces && !*phy; j++)
			if (D->ifaces[j].wiphy == sv->s.wiphy)
				phy = D->ifaces[j].phy;
		void *e = blobmsg_open_table(&b, NULL);
		blobmsg_add_string(&b, "phy", phy);
		blobmsg_add_u32(&b, "freq", sv->s.freq);
		blobmsg_add_u32(&b, "channel", (uint32_t)rl_wifi_channel(sv->s.freq));
		if (sv->s.has & RL_SV_NOISE)
			add_int("noise", sv->s.noise);
		add_busy(sv->busy_pct >= 0 ? sv->busy_pct : sv->busy_pct_total);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- latency and outages (gateway role) ---- */

/* Round trip in ms with one decimal. */
static void add_ms(const char *name, uint32_t us)
{
	blobmsg_add_double(&b, name, (double)((us + 50) / 100) / 10.0);
}

/* Percent with one decimal. */
static void add_pct(const char *name, uint32_t part, uint32_t whole)
{
	blobmsg_add_double(&b, name, (double)(((uint64_t)part * 2000 + whole) / (2 * (uint64_t)whole)) / 10.0);
}

static rl_latq_ctx latq_ctx(void)
{
	return (rl_latq_ctx){
		.minute = D->lat_minute,
		.hour = D->lat_hour,
		.outages = D->outages,
		.open = D->lat_minute ? &D->lat : NULL,
		.targets = &D->targets,
		.now = rl_daemon_now(),
		.minute_days = D->cfg.latency_minute_days,
	};
}

enum { L_START, L_END, L_TARGET, L_POINTS, __L_MAX };
static const struct blobmsg_policy latency_policy[__L_MAX] = {
	[L_START] = { "start", BLOBMSG_CAST_INT64 },   [L_END] = { "end", BLOBMSG_CAST_INT64 },
	[L_TARGET] = { "target", BLOBMSG_TYPE_STRING }, [L_POINTS] = { "max_points", BLOBMSG_CAST_INT64 },
};

static int m_latency(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		     const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[__L_MAX];
	char s[RL_IP_STRLEN];
	blobmsg_parse(latency_policy, __L_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[L_START] || !tb[L_END] || (tb[L_POINTS] && get_i64(tb[L_POINTS], 0) < 1))
		return UBUS_STATUS_INVALID_ARGUMENT;
	uint64_t want = ~0ULL;
	if (tb[L_TARGET]) {
		rl_ip ip;
		if (!rl_ip_parse(blobmsg_get_string(tb[L_TARGET]), &ip))
			return UBUS_STATUS_INVALID_ARGUMENT;
		want = rl_lat_targets_find(&D->targets, &ip);
		if (!want)
			return UBUS_STATUS_NOT_FOUND;
	}
	int64_t start = get_i64(tb[L_START], 0), end = get_i64(tb[L_END], 0);
	rl_latq_ctx c = latq_ctx();
	rl_lat_history h;
	if (rl_lat_query(&c, start, end, (int)get_i64(tb[L_POINTS], 0), want, rl_daemon_probe_targets(D), &h) != 0)
		return UBUS_STATUS_INVALID_ARGUMENT;

	blob_buf_init(&b, 0);
	blobmsg_add_u64(&b, "start", (uint64_t)start);
	blobmsg_add_u64(&b, "end", (uint64_t)end);
	blobmsg_add_u64(&b, "step", (uint64_t)h.step);
	blobmsg_add_string(&b, "tier", rl_tier_name(h.tier));
	void *list = blobmsg_open_array(&b, "targets");
	for (int i = 0; i < h.n_ids; i++) {
		const rl_lat_slot *slot = &D->targets.slot[h.ids[i]];
		void *e = blobmsg_open_table(&b, NULL);
		s[0] = '\0';
		if (slot->ip.family)
			rl_ip_format(&slot->ip, s);
		blobmsg_add_u32(&b, "id", h.ids[i]);
		blobmsg_add_string(&b, "ip", s);
		blobmsg_add_string(&b, "kind", h.ids[i] == RL_LAT_GATEWAY ? "gateway" : "custom");
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	list = blobmsg_open_array(&b, "series");
	for (int i = 0; i < h.n_ids; i++) {
		void *e = blobmsg_open_table(&b, NULL);
		blobmsg_add_u32(&b, "target", h.ids[i]);
		void *pts = blobmsg_open_array(&b, "points");
		for (size_t k = 0; k < h.n; k++) {
			const rl_probe_agg *a = &h.pts[i][k];
			void *p = blobmsg_open_array(&b, NULL);
			blobmsg_add_u64(&b, NULL, (uint64_t)(h.first + (int64_t)k * h.step));
			if (a->sent > a->lost) {
				add_ms(NULL, rl_probe_agg_avg(a));
				add_ms(NULL, a->max_us);
			} else {
				add_null(NULL);
				add_null(NULL);
			}
			if (a->sent)
				add_pct(NULL, a->lost, a->sent);
			else
				add_null(NULL);
			blobmsg_close_array(&b, p);
		}
		blobmsg_close_array(&b, pts);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	list = blobmsg_open_array(&b, "summary");
	for (int i = 0; i < h.n_ids; i++) {
		const rl_probe_agg *a = &h.sum[i];
		void *e = blobmsg_open_table(&b, NULL);
		blobmsg_add_u32(&b, "target", h.ids[i]);
		blobmsg_add_u32(&b, "sent", a->sent);
		blobmsg_add_u32(&b, "lost", a->lost);
		if (a->sent > a->lost) {
			add_ms("avg_ms", rl_probe_agg_avg(a));
			add_ms("max_ms", a->max_us);
		} else {
			add_null("avg_ms");
			add_null("max_ms");
		}
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	rl_lat_history_free(&h);
	return ubus_send_reply(ctx, req, b.head);
}

enum { O_START, O_END, __O_MAX };
static const struct blobmsg_policy outages_policy[__O_MAX] = {
	[O_START] = { "start", BLOBMSG_CAST_INT64 },
	[O_END] = { "end", BLOBMSG_CAST_INT64 },
};

static int m_outages(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		     const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[__O_MAX];
	blobmsg_parse(outages_policy, __O_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[O_START] || !tb[O_END])
		return UBUS_STATUS_INVALID_ARGUMENT;
	rl_latq_ctx c = latq_ctx();
	rl_outage_list l;
	if (rl_outage_query(&c, rl_daemon_probe_on(D) ? &D->outage : NULL, get_i64(tb[O_START], 0),
			    get_i64(tb[O_END], 0), &l) != 0)
		return UBUS_STATUS_INVALID_ARGUMENT;

	blob_buf_init(&b, 0);
	blobmsg_add_u32(&b, "count", (uint32_t)l.count);
	blobmsg_add_u64(&b, "total_sec", (uint64_t)l.total_sec);
	double availability = rl_outage_availability(&l);
	if (availability >= 0)
		blobmsg_add_double(&b, "availability", availability);
	else
		add_null("availability");
	void *list = blobmsg_open_array(&b, "outages");
	for (size_t i = 0; i < l.n; i++) {
		const rl_outage_item *o = &l.items[i];
		void *e = blobmsg_open_table(&b, NULL);
		blobmsg_add_u64(&b, "start", (uint64_t)o->start);
		blobmsg_add_u64(&b, "end", (uint64_t)o->end);
		blobmsg_add_u64(&b, "duration", (uint64_t)(o->end - o->start));
		blobmsg_add_string(&b, "cause", rl_outage_cause_name(o->cause));
		blobmsg_add_u8(&b, "ongoing", o->ongoing);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	rl_outage_list_free(&l);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- router-side speed test ---- */

static const struct blobmsg_policy speed_start_policy[] = { { "server", BLOBMSG_TYPE_STRING } };

static int m_speedtest_start(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
			     const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[1];
	rl_speed_target t;
	blobmsg_parse(speed_start_policy, 1, tb, blob_data(msg), blob_len(msg));
	const char *server = tb[0] ? blobmsg_get_string(tb[0]) : D->cfg.speed_server;
	if (!rl_speed_target_of(server, &t))
		return UBUS_STATUS_INVALID_ARGUMENT;
	if (!D->role.gateway)
		return UBUS_STATUS_NOT_SUPPORTED;
	bool already;
	int id = rl_daemon_speedtest(D, server, &already);
	if (id < 0)
		return UBUS_STATUS_UNKNOWN_ERROR;
	blob_buf_init(&b, 0);
	blobmsg_add_u32(&b, "id", (uint32_t)id);
	if (already)
		blobmsg_add_u8(&b, "already", true); /* libubus has no "busy" status */
	return ubus_send_reply(ctx, req, b.head);
}

/* One decimal (ms). */
static void add_ms1(const char *name, double ms)
{
	blobmsg_add_double(&b, name, (double)(int64_t)(ms * 10 + 0.5) / 10.0);
}

static void add_speed_result(const rl_speed_result *r)
{
	blobmsg_add_u32(&b, "id", (uint32_t)r->id);
	blobmsg_add_u64(&b, "ts", (uint64_t)r->ts);
	blobmsg_add_string(&b, "server", r->server);
	if (r->latency_ms >= 0) {
		add_ms1("latency_ms", r->latency_ms);
		add_ms1("jitter_ms", r->jitter_ms);
	} else {
		add_null("latency_ms");
		add_null("jitter_ms");
	}
	if (r->down_bps >= 0)
		blobmsg_add_u64(&b, "down_bps", (uint64_t)r->down_bps);
	else
		add_null("down_bps");
	if (r->up_bps >= 0)
		blobmsg_add_u64(&b, "up_bps", (uint64_t)r->up_bps);
	else
		add_null("up_bps");
	if (r->error[0])
		blobmsg_add_string(&b, "error", r->error);
}

static const struct blobmsg_policy speed_status_policy[] = { { "id", BLOBMSG_CAST_INT64 } };

static int m_speedtest_status(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
			      const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[1];
	blobmsg_parse(speed_status_policy, 1, tb, blob_data(msg), blob_len(msg));
	const rl_speed_run *run = rl_speedtest_current(D->speed);
	const rl_speed_log *log = rl_speedtest_log(D->speed);
	blob_buf_init(&b, 0);
	if (tb[0]) {
		int64_t id = get_i64(tb[0], 0);
		if (run && run->id == id) {
			blobmsg_add_u32(&b, "id", (uint32_t)id);
			blobmsg_add_u8(&b, "running", true);
			blobmsg_add_string(&b, "phase", rl_speed_phase_name(run->phase));
			blobmsg_add_double(&b, "progress", (double)(int)(run->progress * 100 + 0.5) / 100.0);
			return ubus_send_reply(ctx, req, b.head);
		}
		const rl_speed_result *r = id > 0 && id <= INT32_MAX ? rl_speed_log_find(log, (int)id) : NULL;
		if (!r)
			return UBUS_STATUS_NOT_FOUND;
		blobmsg_add_u32(&b, "id", (uint32_t)id);
		blobmsg_add_u8(&b, "running", false);
		blobmsg_add_string(&b, "phase", r->error[0] ? "failed" : "done");
		blobmsg_add_double(&b, "progress", 1);
		void *t = blobmsg_open_table(&b, "result");
		add_speed_result(r);
		blobmsg_close_table(&b, t);
		if (r->error[0])
			blobmsg_add_string(&b, "error", r->error);
		return ubus_send_reply(ctx, req, b.head);
	}
	blobmsg_add_u8(&b, "running", run != NULL);
	if (run)
		blobmsg_add_u32(&b, "current", (uint32_t)run->id);
	void *list = blobmsg_open_array(&b, "results");
	for (size_t i = log->n; i-- > 0;) {
		void *t = blobmsg_open_table(&b, NULL);
		add_speed_result(&log->items[i]);
		blobmsg_close_table(&b, t);
	}
	blobmsg_close_array(&b, list);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- quotas (P4) ---- */

#define MAX_QUOTAS_OUT 256

static int m_quotas(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
		    const char *method, struct blob_attr *msg)
{
	static rl_quota_view v[MAX_QUOTAS_OUT];
	static const char *const periods[] = { "day", "week", "month" };
	char mac[RL_MAC_STRLEN];
	size_t n = rl_control_quotas(D, v, MAX_QUOTAS_OUT);
	blob_buf_init(&b, 0);
	void *list = blobmsg_open_array(&b, "quotas");
	for (size_t i = 0; i < n; i++) {
		const rl_quota_rule *q = v[i].rule;
		void *e = blobmsg_open_table(&b, NULL);
		rl_mac_format(&q->mac, mac);
		blobmsg_add_string(&b, "section", q->section);
		blobmsg_add_string(&b, "mac", mac);
		blobmsg_add_string(&b, "period", periods[q->period]);
		blobmsg_add_u64(&b, "period_start", (uint64_t)v[i].start);
		blobmsg_add_u64(&b, "period_end", (uint64_t)v[i].end);
		blobmsg_add_u64(&b, "limit", q->limit);
		blobmsg_add_u64(&b, "used", v[i].used);
		/* one decimal */
		blobmsg_add_double(&b, "pct",
				   q->limit ? (double)(uint64_t)((double)v[i].used * 1000.0 / (double)q->limit + 0.5) / 10.0 : 0);
		/* the state of the latest evaluation; a let-through that ran out shows as exceeded until the next one */
		rl_quota_state st = v[i].run->state;
		if (v[i].run->allow_until > rl_daemon_now())
			st = RL_QS_ALLOWED;
		blobmsg_add_string(&b, "state", rl_quota_state_name(st));
		blobmsg_add_u64(&b, "allow_until",
				(uint64_t)(v[i].run->allow_until > rl_daemon_now() ? v[i].run->allow_until : 0));
		blobmsg_add_string(&b, "action", q->slow_down ? "limit" : "block");
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	return ubus_send_reply(ctx, req, b.head);
}

enum { QA_SECTION, QA_UNTIL, __QA_MAX };
static const struct blobmsg_policy quota_allow_policy[__QA_MAX] = {
	[QA_SECTION] = { "section", BLOBMSG_TYPE_STRING },
	[QA_UNTIL] = { "until", BLOBMSG_TYPE_STRING },
};

static int m_quota_allow(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
			 const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[__QA_MAX];
	blobmsg_parse(quota_allow_policy, __QA_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[QA_SECTION] || !tb[QA_UNTIL])
		return UBUS_STATUS_INVALID_ARGUMENT;
	const char *until = blobmsg_get_string(tb[QA_UNTIL]);
	bool period = !strcmp(until, "period");
	if (!period && strcmp(until, "hour"))
		return UBUS_STATUS_INVALID_ARGUMENT;
	if (rl_control_allow(D, blobmsg_get_string(tb[QA_SECTION]), period) != 0)
		return UBUS_STATUS_NOT_FOUND;
	blob_buf_init(&b, 0);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- destinations and the DNS log (P4) ---- */

#define MAX_DEST_OUT 500
#define MAX_DNS_OUT 1000

static void add_addr(const char *name, uint8_t family, const uint8_t *addr)
{
	rl_ip ip;
	char s[RL_IP_STRLEN];
	if (family == 6)
		rl_ip_from_v6(addr, &ip);
	else {
		uint32_t v4;
		memcpy(&v4, addr, 4); /* network order, as stored; addr may be unaligned */
		rl_ip_from_v4(v4, &ip);
	}
	rl_ip_format(&ip, s);
	blobmsg_add_string(&b, name, s);
}

enum { DS_MAC, DS_START, DS_END, DS_LIMIT, __DS_MAX };
static const struct blobmsg_policy destinations_policy[__DS_MAX] = {
	[DS_MAC] = { "mac", BLOBMSG_TYPE_STRING },
	[DS_START] = { "start", BLOBMSG_CAST_INT64 },
	[DS_END] = { "end", BLOBMSG_CAST_INT64 },
	[DS_LIMIT] = { "limit", BLOBMSG_CAST_INT64 },
};

static int m_destinations(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
			  const char *method, struct blob_attr *msg)
{
	static rl_dest_entry out[MAX_DEST_OUT];
	struct blob_attr *tb[__DS_MAX];
	rl_mac mac;
	blobmsg_parse(destinations_policy, __DS_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[DS_MAC] || !tb[DS_START] || !tb[DS_END] || !rl_mac_parse(blobmsg_get_string(tb[DS_MAC]), &mac))
		return UBUS_STATUS_INVALID_ARGUMENT;
	int64_t start = get_i64(tb[DS_START], 0), end = get_i64(tb[DS_END], 0), limit = get_i64(tb[DS_LIMIT], 100);
	if (start < 0 || start >= end || limit < 1 || limit > MAX_DEST_OUT)
		return UBUS_STATUS_INVALID_ARGUMENT;
	if (!rl_devtab_find(D->devs, &mac))
		return UBUS_STATUS_NOT_FOUND;
	size_t found = 0;
	int n = D->visits ? rl_visits_destinations(D->visits, &mac, start, end, out, (size_t)limit, &found) : 0;
	if (n < 0)
		return UBUS_STATUS_UNKNOWN_ERROR;
	blob_buf_init(&b, 0);
	blobmsg_add_u32(&b, "count", (uint32_t)found);
	void *list = blobmsg_open_array(&b, "destinations");
	for (int i = 0; i < n; i++) {
		void *e = blobmsg_open_table(&b, NULL);
		if (out[i].host[0])
			blobmsg_add_string(&b, "host", out[i].host);
		add_addr("ip", out[i].family, out[i].addr);
		blobmsg_add_u64(&b, "rx", out[i].rx);
		blobmsg_add_u64(&b, "tx", out[i].tx);
		blobmsg_add_u32(&b, "conns", out[i].conns);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	return ubus_send_reply(ctx, req, b.head);
}

enum { DN_MAC, DN_START, DN_END, DN_Q, DN_LIMIT, DN_OFFSET, __DN_MAX };
static const struct blobmsg_policy dns_policy[__DN_MAX] = {
	[DN_MAC] = { "mac", BLOBMSG_TYPE_STRING },     [DN_START] = { "start", BLOBMSG_CAST_INT64 },
	[DN_END] = { "end", BLOBMSG_CAST_INT64 },      [DN_Q] = { "q", BLOBMSG_TYPE_STRING },
	[DN_LIMIT] = { "limit", BLOBMSG_CAST_INT64 },  [DN_OFFSET] = { "offset", BLOBMSG_CAST_INT64 },
};

typedef struct {
	const uint8_t *mac;
	char q[RL_DNS_NAME_MAX + 1];
	size_t offset, limit, count;
} dns_ctx;

static bool dns_cb(const rl_dnslog_rec *r, void *x)
{
	dns_ctx *c = x;
	char buf[8];
	if (!rl_dnslog_match(r, c->mac, c->q))
		return true;
	size_t i = c->count++;
	if (i < c->offset || i >= c->offset + c->limit)
		return true; /* counted only */
	char mac[RL_MAC_STRLEN];
	rl_mac m;
	memcpy(m.b, r->mac, 6);
	rl_mac_format(&m, mac);
	void *e = blobmsg_open_table(&b, NULL);
	blobmsg_add_u64(&b, "ts", (uint64_t)r->ts);
	blobmsg_add_string(&b, "mac", mac);
	blobmsg_add_string(&b, "name", r->name);
	blobmsg_add_string(&b, "type", rl_dns_type_name(r->qtype, buf));
	blobmsg_add_string(&b, "rcode", rl_dns_rcode_name(r->rcode));
	void *a = blobmsg_open_array(&b, "answers");
	for (int k = 0; k < r->n_addrs; k++)
		add_addr(NULL, r->addrs[k].family, r->addrs[k].addr);
	blobmsg_close_array(&b, a);
	blobmsg_close_table(&b, e);
	return true;
}

static int m_dns(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req, const char *method,
		 struct blob_attr *msg)
{
	struct blob_attr *tb[__DN_MAX];
	rl_mac mac;
	dns_ctx c = { 0 };
	blobmsg_parse(dns_policy, __DN_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[DN_START] || !tb[DN_END])
		return UBUS_STATUS_INVALID_ARGUMENT;
	int64_t start = get_i64(tb[DN_START], 0), end = get_i64(tb[DN_END], 0);
	int64_t limit = get_i64(tb[DN_LIMIT], 100), offset = get_i64(tb[DN_OFFSET], 0);
	if (start >= end || limit < 1 || limit > MAX_DNS_OUT || offset < 0)
		return UBUS_STATUS_INVALID_ARGUMENT;
	if (tb[DN_MAC]) {
		if (!rl_mac_parse(blobmsg_get_string(tb[DN_MAC]), &mac))
			return UBUS_STATUS_INVALID_ARGUMENT;
		c.mac = mac.b;
	}
	if (tb[DN_Q]) {
		snprintf(c.q, sizeof(c.q), "%s", blobmsg_get_string(tb[DN_Q]));
		for (char *p = c.q; *p; p++)
			*p = (char)tolower((unsigned char)*p);
	}
	c.offset = (size_t)offset;
	c.limit = (size_t)limit;
	blob_buf_init(&b, 0);
	void *list = blobmsg_open_array(&b, "records");
	if (D->visits && rl_visits_dns_scan(D->visits, start, end, dns_cb, &c) != 0) {
		blob_buf_init(&b, 0);
		return UBUS_STATUS_UNKNOWN_ERROR;
	}
	blobmsg_close_array(&b, list);
	blobmsg_add_u32(&b, "count", (uint32_t)c.count);
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- push (P4) ---- */

typedef struct {
	struct ubus_context *ctx;
	struct ubus_request_data req;
} deferred_test;

static void test_done(void *x, bool ok, const char *error)
{
	deferred_test *t = x;
	struct blob_buf r = { 0 };
	blob_buf_init(&r, 0);
	blobmsg_add_u8(&r, "ok", ok);
	if (!ok)
		blobmsg_add_string(&r, "error", error ? error : "failed");
	ubus_send_reply(t->ctx, &t->req, r.head);
	ubus_complete_deferred_request(t->ctx, &t->req, UBUS_STATUS_OK);
	blob_buf_free(&r);
	free(t);
}

static const struct blobmsg_policy notify_test_policy[] = { { "section", BLOBMSG_TYPE_STRING } };

static int m_notify_test(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
			 const char *method, struct blob_attr *msg)
{
	struct blob_attr *tb[1];
	blobmsg_parse(notify_test_policy, 1, tb, blob_data(msg), blob_len(msg));
	if (!tb[0])
		return UBUS_STATUS_INVALID_ARGUMENT;
	if (!D->notifier)
		return UBUS_STATUS_NOT_SUPPORTED;
	deferred_test *t = calloc(1, sizeof(*t));
	if (!t)
		abort();
	t->ctx = ctx;
	ubus_defer_request(ctx, req, &t->req);
	/* the reply comes when uclient-fetch is done (at most RL_NOTIFY_TEST_TIMEOUT s) */
	if (rl_notifier_test(D->notifier, blobmsg_get_string(tb[0]), test_done, t) != 0) {
		ubus_complete_deferred_request(ctx, &t->req, UBUS_STATUS_NOT_FOUND);
		free(t);
	}
	return 0;
}

static int m_notify_status(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
			   const char *method, struct blob_attr *msg)
{
	static rl_channel_status st[64];
	size_t n = D->notifier ? rl_notifier_status(D->notifier, st, RL_ARRAY_SIZE(st)) : 0;
	blob_buf_init(&b, 0);
	void *list = blobmsg_open_array(&b, "channels");
	for (size_t i = 0; i < n; i++) {
		void *e = blobmsg_open_table(&b, NULL);
		blobmsg_add_string(&b, "section", st[i].section);
		blobmsg_add_u64(&b, "last_ok", (uint64_t)st[i].last_ok);
		blobmsg_add_string(&b, "last_error", st[i].last_error);
		blobmsg_add_u64(&b, "last_error_ts", (uint64_t)st[i].last_error_ts);
		blobmsg_close_table(&b, e);
	}
	blobmsg_close_array(&b, list);
	blobmsg_add_u32(&b, "pending", (uint32_t)(D->notifier ? rl_notifier_pending(D->notifier) : 0));
	return ubus_send_reply(ctx, req, b.head);
}

/* ---- maintenance ---- */

static const struct blobmsg_policy reset_policy[] = { { "scope", BLOBMSG_TYPE_STRING } };

static int m_reset(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req, const char *method,
		   struct blob_attr *msg)
{
	struct blob_attr *tb[1];
	blobmsg_parse(reset_policy, 1, tb, blob_data(msg), blob_len(msg));
	if (!tb[0])
		return UBUS_STATUS_INVALID_ARGUMENT;
	const char *s = blobmsg_get_string(tb[0]);
	unsigned scope;
	if (!strcmp(s, "traffic"))
		scope = RL_RESET_TRAFFIC;
	else if (!strcmp(s, "events"))
		scope = RL_RESET_EVENTS;
	else if (!strcmp(s, "signal"))
		scope = RL_RESET_SIGNAL;
	else if (!strcmp(s, "devices"))
		scope = RL_RESET_DEVICES;
	else if (!strcmp(s, "latency"))
		scope = RL_RESET_LATENCY;
	else if (!strcmp(s, "dns"))
		scope = RL_RESET_DNS;
	else if (!strcmp(s, "all"))
		scope = RL_RESET_TRAFFIC | RL_RESET_EVENTS | RL_RESET_DEVICES | RL_RESET_SIGNAL | RL_RESET_LATENCY |
			RL_RESET_DNS;
	else
		return UBUS_STATUS_INVALID_ARGUMENT;
	rl_daemon_reset(D, scope);
	blob_buf_init(&b, 0);
	return ubus_send_reply(ctx, req, b.head);
}

static int m_commit(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req, const char *method,
		    struct blob_attr *msg)
{
	int rc = rl_daemon_commit(D, true);
	blob_buf_init(&b, 0);
	blobmsg_add_u8(&b, "ok", rc == 0);
	return ubus_send_reply(ctx, req, b.head);
}

static int m_ntp_synced(struct ubus_context *ctx, struct ubus_object *obj, struct ubus_request_data *req,
			const char *method, struct blob_attr *msg)
{
	rl_daemon_time_synced(D);
	blob_buf_init(&b, 0);
	return ubus_send_reply(ctx, req, b.head);
}

static const struct ubus_method methods[] = {
	UBUS_METHOD_NOARG("info", m_info),
	UBUS_METHOD_NOARG("devices", m_devices),
	UBUS_METHOD_NOARG("live", m_live),
	UBUS_METHOD("history", m_history, history_policy),
	UBUS_METHOD("summary", m_summary, summary_policy),
	UBUS_METHOD("events", m_events, events_policy),
	UBUS_METHOD("stations", m_stations, stations_policy),
	UBUS_METHOD("signal", m_signal, signal_policy),
	UBUS_METHOD_NOARG("survey", m_survey),
	UBUS_METHOD("latency", m_latency, latency_policy),
	UBUS_METHOD("outages", m_outages, outages_policy),
	UBUS_METHOD("speedtest_start", m_speedtest_start, speed_start_policy),
	UBUS_METHOD("speedtest_status", m_speedtest_status, speed_status_policy),
	UBUS_METHOD_NOARG("quotas", m_quotas),
	UBUS_METHOD("quota_allow", m_quota_allow, quota_allow_policy),
	UBUS_METHOD("destinations", m_destinations, destinations_policy),
	UBUS_METHOD("dns", m_dns, dns_policy),
	UBUS_METHOD("notify_test", m_notify_test, notify_test_policy),
	UBUS_METHOD_NOARG("notify_status", m_notify_status),
	UBUS_METHOD("reset", m_reset, reset_policy),
	UBUS_METHOD_NOARG("commit", m_commit),
	UBUS_METHOD_NOARG("ntp_synced", m_ntp_synced),
};

static struct ubus_object_type type = UBUS_OBJECT_TYPE("routelink", methods);

static struct ubus_object object = {
	.name = "routelink",
	.type = &type,
	.methods = methods,
	.n_methods = ARRAY_SIZE(methods),
};

int rl_api_register(struct ubus_context *ctx)
{
	return ubus_add_object(ctx, &object);
}
