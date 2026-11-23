#define _GNU_SOURCE
#include <errno.h>
#include <glob.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/statvfs.h>
#include <sys/sysinfo.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#include "core/classify.h"
#include "core/recover.h"
#include "core/util.h"
#include "core/version.h"
#include "sys/api.h"
#include "sys/daemon.h"

#ifndef RL_BUILD_EPOCH
#define RL_BUILD_EPOCH 0
#endif

#define JFFS2_MAGIC 0x72b6
#define UBIFS_MAGIC 0x24051905
#define OVERLAYFS_MAGIC 0x794c7630

/* ---- flow tags: which devices a connection belongs to, cached per flow ----
 * bits 0-15 dev0, 16-17 cls0, 18 orig0 | 20-35 dev1, 36-37 cls1, 38 orig1 | 40-41 n | 62 valid
 */
#define TAG_VALID (1ULL << 62)

static uint64_t tag_pack(int n, const uint16_t dev[2], const rl_class cls[2], const bool orig[2])
{
	uint64_t t = TAG_VALID | (uint64_t)n << 40;
	for (int i = 0; i < n; i++)
		t |= ((uint64_t)dev[i] | (uint64_t)cls[i] << 16 | (uint64_t)orig[i] << 18) << (20 * i);
	return t;
}

static int tag_n(uint64_t t)
{
	return (int)(t >> 40 & 3);
}

static uint16_t tag_dev(uint64_t t, int i)
{
	return (uint16_t)(t >> (20 * i));
}

static rl_class tag_cls(uint64_t t, int i)
{
	return (rl_class)(t >> (20 * i + 16) & 3);
}

static bool tag_orig(uint64_t t, int i)
{
	return t >> (20 * i + 18) & 1;
}

int64_t rl_daemon_now(void)
{
	return (int64_t)time(NULL);
}

static int64_t now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static long uptime(void)
{
	struct sysinfo si;
	return sysinfo(&si) == 0 ? si.uptime : 0;
}

static void event(rl_daemon *d, rl_event_type type, uint16_t dev, int64_t a)
{
	rl_event ev = { .ts = rl_daemon_now(), .type = (uint16_t)type, .dev = dev, .a = a };
	rl_events_add(d->events, &ev);
}

bool rl_daemon_traffic_on(const rl_daemon *d)
{
	return d->cfg.traffic && d->role.gateway && d->ct;
}

/* ---- push notices ---- */

void rl_daemon_describe(rl_daemon *d, const rl_mac *mac, rl_notify_event *ev)
{
	rl_device *dev = rl_devtab_find(d->devs, mac);
	rl_ip ips[4];
	rl_mac_format(mac, ev->mac);
	if (dev && !ev->name[0])
		snprintf(ev->name, sizeof(ev->name), "%s", dev->name[0] ? dev->name : dev->hostname);
	if (!ev->ip[0]) {
		size_t n = rl_neigh_ips(d->neigh, mac, ips, RL_ARRAY_SIZE(ips));
		if (n)
			rl_ip_format(&ips[0], ev->ip); /* IPv4 first */
	}
}

void rl_daemon_notify(rl_daemon *d, const rl_notify_event *ev)
{
	if (d->role.gateway && d->notifier)
		rl_notifier_event(d->notifier, ev);
}

/* Names and addresses are often only known a little after a device appeared: filled in when the batch goes. */
static void refresh_notice(void *ctx, rl_notify_event *ev)
{
	rl_daemon *d = ctx;
	rl_mac mac;
	if (ev->mac[0] && rl_mac_parse(ev->mac, &mac))
		rl_daemon_describe(d, &mac, ev);
}

static void device_notice(rl_daemon *d, const rl_device *dev, rl_notify_kind kind)
{
	rl_notify_event ev = { .kind = kind, .ts = rl_daemon_now() };
	rl_daemon_describe(d, &dev->mac, &ev);
	rl_daemon_notify(d, &ev);
}

static void device_new(rl_daemon *d, const rl_device *dev)
{
	char s[RL_MAC_STRLEN];
	rl_mac_format(&dev->mac, s);
	syslog(LOG_INFO, "new device %s", s);
	event(d, RL_EV_DEVICE_NEW, dev->idx, 0);
	/* a fresh device table (first start, devices reset) would announce every device at once */
	if (rl_daemon_now() >= d->quiet_until)
		device_notice(d, dev, RL_NE_DEVICE_NEW);
}

/* ---- attribution ---- */

static uint16_t resolve(rl_daemon *d, const rl_ip *ip, int64_t now, bool *pending)
{
	rl_mac mac;
	bool created;
	if (!rl_neigh_lookup(d->neigh, ip, &mac)) {
		*pending = true;
		return RL_DEV_UNKNOWN;
	}
	rl_device *dev = rl_devtab_get(d->devs, &mac, now, &created);
	if (!dev) {
		*pending = true;
		return RL_DEV_UNKNOWN;
	}
	if (created)
		device_new(d, dev);
	return dev->idx;
}

/* Returns the tag for a sample; *cacheable is false while some address is still unresolved. */
static uint64_t attribute(rl_daemon *d, const rl_ct_sample *s, int64_t now, bool *cacheable)
{
	rl_attribution a = rl_classify(&d->net.nv, s);
	uint16_t dev[2] = { 0, 0 };
	rl_class cls[2] = { 0, 0 };
	bool orig[2] = { false, false }, pending = false;
	for (int i = 0; i < a.n; i++) {
		dev[i] = a.a[i].router ? RL_DEV_ROUTER : resolve(d, &a.a[i].client, now, &pending);
		cls[i] = a.a[i].cls;
		orig[i] = a.a[i].client_is_orig;
	}
	*cacheable = a.n > 0 && !pending;
	return tag_pack(a.n, dev, cls, orig);
}

static void apply(rl_daemon *d, uint64_t tag, rl_delta delta, int64_t now)
{
	if (!delta.orig_bytes && !delta.reply_bytes)
		return;
	for (int i = 0; i < tag_n(tag); i++) {
		uint64_t rx, tx;
		uint16_t dev = tag_dev(tag, i);
		rl_client_bytes(tag_orig(tag, i), delta, &rx, &tx);
		rl_agg_add(d->agg, now, dev, tag_cls(tag, i), rx, tx);
		rl_device *dv = dev <= RL_DEV_MAX ? rl_devtab_by_idx(d->devs, dev) : NULL;
		if (dv)
			rl_devtab_touch(dv, now);
	}
}

/* Destinations: a device's internet traffic per peer (DNS logging on). */
static void destinations(rl_daemon *d, const rl_ct_sample *s, uint64_t tag, rl_delta delta, bool first, int64_t now)
{
	for (int i = 0; i < tag_n(tag); i++) {
		uint16_t dev = tag_dev(tag, i);
		rl_device *dv;
		if (tag_cls(tag, i) != RL_CLASS_INTERNET || dev > RL_DEV_MAX || !(dv = rl_devtab_by_idx(d->devs, dev)))
			continue;
		uint64_t rx, tx;
		rl_client_bytes(tag_orig(tag, i), delta, &rx, &tx);
		if (!rx && !tx && !first)
			continue;
		/* opened by the device: the peer is where it went; opened from outside: where it came from */
		const rl_ip *peer = tag_orig(tag, i) ? &s->orig_dst : &s->orig_src;
		rl_visits_traffic(d->visits, &dv->mac, peer, rx, tx, first, now);
	}
}

static void on_ct(const rl_ct_sample *s, bool destroyed, void *ctx)
{
	rl_daemon *d = ctx;
	int64_t now = rl_daemon_now();
	uint64_t tag;
	rl_delta delta;
	bool cacheable, first = false;

	if (destroyed) {
		delta = rl_flows_destroy(d->flows, s, &tag);
		if (!(tag & TAG_VALID)) {
			tag = attribute(d, s, now, &cacheable);
			first = true; /* opened and closed between two dumps */
		}
	} else {
		uint64_t *slot;
		delta = rl_flows_update(d->flows, s, &slot);
		if (!(*slot & TAG_VALID)) {
			tag = attribute(d, s, now, &cacheable);
			if (cacheable) {
				*slot = tag;
				first = true;
			}
		} else {
			tag = *slot;
		}
	}
	apply(d, tag, delta, now);
	if (d->visits && rl_visits_on(d->visits) && (tag & TAG_VALID))
		destinations(d, s, tag, delta, first, now);
}

static void count_conn(uint64_t tag, void *ctx)
{
	rl_daemon *d = ctx;
	if (!(tag & TAG_VALID))
		return;
	for (int i = 0; i < tag_n(tag); i++)
		if (tag_cls(tag, i) == RL_CLASS_INTERNET)
			d->conn_count[tag_dev(tag, i)]++;
}

/* ---- presence ---- */

static void on_presence(rl_device *dev, bool online, void *ctx)
{
	rl_daemon *d = ctx;
	if (rl_daemon_now() - d->started < RL_STARTUP_GRACE)
		return;
	event(d, online ? RL_EV_DEVICE_ONLINE : RL_EV_DEVICE_OFFLINE, dev->idx, 0);
	const rl_devflag *flag = rl_daemon_devflag(d, &dev->mac);
	if (flag && flag->watch)
		device_notice(d, dev, online ? RL_NE_DEVICE_ONLINE : RL_NE_DEVICE_OFFLINE);
}

static void on_reachable(const rl_mac *mac, int64_t now, void *ctx)
{
	rl_daemon *d = ctx;
	bool created;
	rl_device *dev = rl_devtab_get(d->devs, mac, now, &created);
	if (!dev)
		return;
	if (created)
		device_new(d, dev);
	rl_devtab_touch(dev, now);
}

/* ---- sampling ---- */

/*
 * Runs t within ms, or earlier where it was due earlier: rearming from scratch on every configuration reload
 * put a sample (or commit) off again and again while reloads came faster than its interval.
 */
static void arm_by(struct uloop_timeout *t, int ms)
{
	if (!t->pending || uloop_timeout_remaining64(t) > ms)
		uloop_timeout_set(t, ms);
}

static void schedule_sample(rl_daemon *d)
{
	int secs = rl_daemon_now() < d->live_until ? d->cfg.live_interval : d->cfg.sample_interval;
	arm_by(&d->sample_timer, secs * 1000);
}

static bool mac_of(uint16_t dev, rl_mac *out, void *ctx)
{
	rl_daemon *d = ctx;
	rl_device *dv = rl_devtab_by_idx(d->devs, dev);
	if (!dv)
		return false;
	*out = dv->mac;
	return true;
}

static void handle_time_jump(rl_daemon *d, int64_t now)
{
	int64_t jump = now - d->last_clock;
	syslog(LOG_NOTICE, "clock jumped by %lld s", (long long)jump);
	if (!d->synced) {
		/* everything recorded so far carries the wrong time: drop it, the clock is set now */
		rl_agg_reset(d->agg);
		rl_store_discard_pending(d->store);
		rl_recover(d->store, d->agg, now);
		if (d->sig_minute) {
			rl_wifi_reset_data(d->wifi);
			rl_series_discard_pending(d->sig_minute);
			rl_series_discard_pending(d->sig_hour);
			rl_wifi_recover(d->wifi, d->sig_minute, d->sig_hour, now, mac_of, d);
		}
		if (d->lat_minute) {
			rl_lat_reset(&d->lat);
			rl_series_discard_pending(d->lat_minute);
			rl_series_discard_pending(d->lat_hour);
			rl_series_discard_pending(d->outages);
			rl_lat_recover(&d->lat, d->lat_minute, d->lat_hour, now);
			d->outage = (rl_outage){ 0 };
		}
		d->synced = true;
	}
	event(d, RL_EV_TIME_JUMP, RL_EV_NO_DEV, jump);
}

/* Both samplers watch the clock: a step means NTP set it (or someone changed it). */
static void check_clock(rl_daemon *d, int64_t now)
{
	if (d->last_clock && (now < d->last_clock - 60 || now > d->last_clock + 3600))
		handle_time_jump(d, now);
	d->last_clock = now;
}

void rl_daemon_sample(rl_daemon *d)
{
	int64_t now = rl_daemon_now();
	if (!rl_daemon_traffic_on(d) || !d->net_ready)
		return;
	check_clock(d, now);

	rl_flows_begin(d->flows, d->baseline_next);
	d->baseline_next = false;
	if (rl_ct_dump(d->ct) < 0)
		syslog(LOG_WARNING, "conntrack dump failed: %s", strerror(errno));
	rl_flows_sweep(d->flows);

	memset(d->conn_count, 0, 65536 * sizeof(uint32_t));
	rl_flows_each(d->flows, count_conn, d);
	for (size_t i = 0; i < rl_devtab_count(d->devs); i++)
		if (d->conn_count[i])
			rl_agg_conns(d->agg, now, (uint16_t)i, d->conn_count[i]);

	uint64_t rx, tx;
	if (rl_netinfo_wan_bytes(&d->net, &rx, &tx)) {
		uint64_t drx = 0, dtx = 0;
		if (d->wan_valid) {
			drx = rx >= d->wan_rx ? rx - d->wan_rx : rx; /* interface re-created (PPPoE redial) */
			dtx = tx >= d->wan_tx ? tx - d->wan_tx : tx;
		}
		d->wan_rx = rx;
		d->wan_tx = tx;
		d->wan_valid = true;
		rl_agg_add(d->agg, now, RL_DEV_WAN, RL_CLASS_INTERNET, drx, dtx);
	} else {
		d->wan_valid = false;
		rl_agg_add(d->agg, now, RL_DEV_WAN, RL_CLASS_INTERNET, 0, 0); /* still recording */
	}
	rl_agg_tick(d->agg, now);
	rl_agg_sample_done(d->agg, now_ms());
	rl_devtab_presence(d->devs, now, on_presence, d);
	if (d->visits && rl_visits_on(d->visits)) {
		rl_visits_tick(d->visits, now); /* an hour that ended without traffic since */
		rl_visits_writable(d->visits, d->synced);
	}
	d->last_sample = now;
}

static void sample_timer_cb(struct uloop_timeout *t)
{
	rl_daemon *d = container_of(t, rl_daemon, sample_timer);
	rl_daemon_sample(d);
	schedule_sample(d);
}

void rl_daemon_live(rl_daemon *d)
{
	int64_t now = rl_daemon_now();
	bool was_live = now < d->live_until;
	d->live_until = now + RL_LIVE_LEASE;
	if (!was_live) {
		rl_daemon_sample(d);
		schedule_sample(d);
	}
}

/* ---- ct / neighbour sockets ---- */

static void ct_fd_cb(struct uloop_fd *fd, unsigned int events)
{
	rl_daemon *d = container_of(fd, rl_daemon, ct_fd);
	if (rl_ct_on_readable(d->ct)) {
		syslog(LOG_WARNING, "conntrack events lost, resyncing");
		rl_daemon_sample(d);
	}
}

static void neigh_fd_cb(struct uloop_fd *fd, unsigned int events)
{
	rl_daemon *d = container_of(fd, rl_daemon, neigh_fd);
	rl_neigh_on_readable(d->neigh);
}

static void open_traffic(rl_daemon *d)
{
	if (d->ct || !d->cfg.traffic || !d->role.gateway)
		return;
	d->ct = rl_ct_open(on_ct, d);
	if (!d->ct)
		return;
	d->ct_fd.fd = rl_ct_event_fd(d->ct);
	d->ct_fd.cb = ct_fd_cb;
	uloop_fd_add(&d->ct_fd, ULOOP_READ);
	d->baseline_next = true;
	syslog(LOG_INFO, "traffic accounting started");
}

static void close_traffic(rl_daemon *d)
{
	if (!d->ct)
		return;
	uloop_fd_delete(&d->ct_fd);
	rl_ct_close(d->ct);
	d->ct = NULL;
	d->wan_valid = false;
}

/* ---- wireless (AP role) ---- */

bool rl_daemon_wifi_on(const rl_daemon *d)
{
	return d->wifi_on;
}

int rl_daemon_wifi_interval(const rl_daemon *d)
{
	return rl_daemon_now() < d->wifi_live_until ? RL_WIFI_LIVE_INTERVAL : RL_WIFI_INTERVAL;
}

static void on_sig_rec(rl_tier tier, const uint8_t rec[RL_SERIES_REC_SIZE], void *ctx)
{
	rl_daemon *d = ctx;
	rl_series *s = tier == RL_TIER_HOUR ? d->sig_hour : d->sig_minute;
	if (s)
		rl_series_append(s, rec);
}

static void on_assoc(const rl_wifi_sta *st, bool connected, void *ctx)
{
	rl_daemon *d = ctx;
	event(d, connected ? RL_EV_WIFI_CONNECT : RL_EV_WIFI_DISCONNECT, st->dev, st->freq);
}

typedef struct {
	rl_daemon *d;
	const rl_nl_iface *ifc;
	int64_t now;
} sta_ctx;

static void on_station(const rl_sta_sample *s, void *x)
{
	sta_ctx *c = x;
	rl_daemon *d = c->d;
	bool created;
	if ((s->has & RL_STA_FLAGS) && !s->authorized)
		return; /* still in the handshake, or a wrong password: not a device of this network (yet) */
	rl_device *dev = rl_devtab_get(d->devs, &s->mac, c->now, &created);
	if (!dev)
		return;
	if (created)
		device_new(d, dev);
	rl_devtab_touch(dev, c->now);
	rl_wifi_update(d->wifi, s, dev->idx, c->ifc->ifname, c->ifc->freq, c->now);
}

static void wifi_sample(rl_daemon *d)
{
	rl_nl_iface ifaces[RL_NL_MAX_IFACES];
	int64_t now = rl_daemon_now();
	if (!d->wifi_on)
		return;
	check_clock(d, now);
	rl_wifi_tick(d->wifi, now);
	int n = rl_nl80211_ap_ifaces(d->nl, ifaces, RL_NL_MAX_IFACES);
	bool complete = n >= 0; /* a failed dump must not look like every station left */
	if (n >= 0) {
		memcpy(d->ifaces, ifaces, (size_t)n * sizeof(rl_nl_iface));
		d->n_ifaces = n;
	}
	rl_wifi_begin(d->wifi);
	for (int i = 0; n >= 0 && i < d->n_ifaces; i++) {
		sta_ctx c = { d, &d->ifaces[i], now };
		if (rl_nl80211_stations(d->nl, d->ifaces[i].ifindex, on_station, &c) != 0)
			complete = false;
	}
	rl_wifi_end(d->wifi, now, complete);
	if (!rl_daemon_traffic_on(d))
		rl_devtab_presence(d->devs, now, NULL, NULL); /* no online/offline events from an AP */
}

static void wifi_timer_cb(struct uloop_timeout *t)
{
	rl_daemon *d = container_of(t, rl_daemon, wifi_timer);
	wifi_sample(d);
	if (d->wifi_on)
		uloop_timeout_set(t, rl_daemon_wifi_interval(d) * 1000);
}

/* Samples within a second (a station joined: catch its authorization quickly). */
static void wifi_sample_soon(rl_daemon *d)
{
	if (d->wifi_on && (!d->wifi_timer.pending || uloop_timeout_remaining64(&d->wifi_timer) > 1000))
		uloop_timeout_set(&d->wifi_timer, 1000);
}

void rl_daemon_wifi_live(rl_daemon *d)
{
	int64_t now = rl_daemon_now();
	bool was_live = now < d->wifi_live_until;
	d->wifi_live_until = now + RL_LIVE_LEASE;
	if (!was_live && d->wifi_on) {
		wifi_sample(d);
		uloop_timeout_set(&d->wifi_timer, RL_WIFI_LIVE_INTERVAL * 1000);
	}
}

typedef struct {
	rl_daemon *d;
	int64_t now;
} survey_ctx;

static void on_survey(const rl_survey_sample *s, void *x)
{
	survey_ctx *c = x;
	rl_wifi_survey_add(c->d->wifi, s, c->now);
}

static void survey_sample(rl_daemon *d)
{
	uint32_t wiphys[RL_NL_MAX_IFACES];
	size_t n = 0;
	survey_ctx c = { d, rl_daemon_now() };
	for (int i = 0; i < d->n_ifaces; i++) {
		const rl_nl_iface *ifc = &d->ifaces[i];
		bool done = false;
		for (size_t j = 0; j < n && !done; j++)
			done = wiphys[j] == ifc->wiphy;
		if (done)
			continue; /* one dump per radio */
		wiphys[n++] = ifc->wiphy;
		rl_wifi_survey_begin(d->wifi, ifc->wiphy);
		if (rl_nl80211_survey(d->nl, ifc->ifindex, ifc->wiphy, on_survey, &c) == 0)
			rl_wifi_survey_end(d->wifi, ifc->wiphy);
	}
	rl_wifi_survey_retain(d->wifi, wiphys, n);
}

static void survey_timer_cb(struct uloop_timeout *t)
{
	rl_daemon *d = container_of(t, rl_daemon, survey_timer);
	if (!d->wifi_on)
		return;
	survey_sample(d);
	uloop_timeout_set(t, RL_SURVEY_INTERVAL * 1000);
}

static void on_nl_event(bool added, int ifindex, const rl_mac *mac, void *ctx)
{
	rl_daemon *d = ctx;
	if (!d->wifi_on)
		return;
	if (added)
		wifi_sample_soon(d);
	else
		rl_wifi_disassoc(d->wifi, mac, ifindex, rl_daemon_now());
}

static void nl_fd_cb(struct uloop_fd *fd, unsigned int events)
{
	rl_daemon *d = container_of(fd, rl_daemon, nl_fd);
	if (rl_nl80211_on_readable(d->nl))
		wifi_sample_soon(d); /* events were lost: the next dump catches up */
}

static void open_nl(rl_daemon *d)
{
	if (d->nl)
		return;
	d->nl = rl_nl80211_open(on_nl_event, d);
	if (!d->nl) {
		if (!d->nl_missing_logged)
			syslog(LOG_INFO, "no nl80211 (%s): wireless sampling unavailable", strerror(errno));
		d->nl_missing_logged = true;
		return;
	}
	d->nl_fd.fd = rl_nl80211_event_fd(d->nl);
	d->nl_fd.cb = nl_fd_cb;
	if (d->nl_fd.fd >= 0)
		uloop_fd_add(&d->nl_fd, ULOOP_READ);
}

static void close_nl(rl_daemon *d)
{
	if (!d->nl)
		return;
	if (d->nl_fd.fd >= 0)
		uloop_fd_delete(&d->nl_fd);
	rl_nl80211_close(d->nl);
	d->nl = NULL;
}

static int open_signal(rl_daemon *d)
{
	char path[256];
	bool bad_m = false, bad_h = false;
	if (d->sig_minute)
		return 0;
	snprintf(path, sizeof(path), "%s/signal.minute", d->cfg.data_dir);
	d->sig_minute = rl_series_open(path, RL_SIG_KIND_MINUTE, &bad_m);
	snprintf(path, sizeof(path), "%s/signal.hour", d->cfg.data_dir);
	d->sig_hour = rl_series_open(path, RL_SIG_KIND_HOUR, &bad_h);
	if (!d->sig_minute || !d->sig_hour) {
		syslog(LOG_ERR, "cannot open the signal files in %s", d->cfg.data_dir);
		rl_series_close(d->sig_minute);
		rl_series_close(d->sig_hour);
		d->sig_minute = d->sig_hour = NULL;
		return -1;
	}
	if (bad_m || bad_h) {
		syslog(LOG_WARNING, "damaged signal files were replaced");
		event(d, RL_EV_DATA_RECOVERED, RL_EV_NO_DEV, 0);
	}
	int n = rl_wifi_recover(d->wifi, d->sig_minute, d->sig_hour, rl_daemon_now(), mac_of, d);
	if (n)
		syslog(LOG_INFO, "rebuilt %d hourly signal records after downtime", n);
	return 0;
}

static void close_signal(rl_daemon *d)
{
	rl_series_close(d->sig_minute);
	rl_series_close(d->sig_hour);
	d->sig_minute = d->sig_hour = NULL;
}

static void start_wifi(rl_daemon *d)
{
	if (d->wifi_on || !d->nl || open_signal(d) != 0)
		return;
	d->wifi_on = true;
	uloop_timeout_set(&d->wifi_timer, 0);
	uloop_timeout_set(&d->survey_timer, 1000); /* after the first station sample found the interfaces */
	syslog(LOG_INFO, "wireless sampling started");
}

/* flush: write the open buckets (the open hour too: nothing rebuilds it while the daemon keeps running). */
static void stop_wifi(rl_daemon *d, bool flush)
{
	if (!d->wifi_on)
		return;
	uloop_timeout_cancel(&d->wifi_timer);
	uloop_timeout_cancel(&d->survey_timer);
	if (flush)
		rl_wifi_flush(d->wifi, true);
	rl_wifi_clear(d->wifi);
	rl_wifi_survey_retain(d->wifi, NULL, 0);
	d->n_ifaces = 0;
	d->wifi_on = false;
	syslog(LOG_INFO, "wireless sampling stopped");
}

static void detect_ap(rl_daemon *d)
{
	rl_nl_iface ifaces[RL_NL_MAX_IFACES];
	open_nl(d);
	d->role.ap = d->nl && (rl_nl80211_ap_ifaces(d->nl, ifaces, RL_NL_MAX_IFACES) > 0 || rl_role_wifi_configured());
	if (d->cfg.wifi && d->role.ap)
		start_wifi(d);
	else
		stop_wifi(d, true);
}

/* ---- latency probes and outages (gateway role) ---- */

bool rl_daemon_probe_on(const rl_daemon *d)
{
	return d->probe_on;
}

uint64_t rl_daemon_probe_targets(const rl_daemon *d)
{
	uint64_t mask = 0;
	if (!d->probe_on)
		return 0;
	if (d->cfg.probe_gateway && d->targets.slot[RL_LAT_GATEWAY].ip.family)
		mask |= 1ULL << RL_LAT_GATEWAY;
	for (int i = 0; i < d->n_probe_ids; i++)
		mask |= 1ULL << d->probe_ids[i];
	return mask;
}

static void on_lat_rec(rl_tier tier, const uint8_t rec[RL_SERIES_REC_SIZE], void *ctx)
{
	rl_daemon *d = ctx;
	rl_series *s = tier == RL_TIER_HOUR ? d->lat_hour : d->lat_minute;
	if (s)
		rl_series_append(s, rec);
}

/* An outage only reaches the log when it ends; until then it lives in d->outage. */
static void on_outage(rl_daemon *d, const rl_outage_event *ev)
{
	if (ev->started)
		syslog(LOG_NOTICE, "internet unreachable (no probe target answered since %lld)", (long long)ev->start);
	if (d->notifier)
		rl_notifier_hold(d->notifier, d->outage.down); /* nothing would get out */
	if (!ev->ended)
		return;
	syslog(LOG_NOTICE, "internet reachable again after %lld s (%s)", (long long)(ev->end - ev->start),
	       rl_outage_cause_name(ev->cause));
	rl_notify_event notice = { .kind = RL_NE_OUTAGE, .ts = rl_daemon_now(), .duration = ev->end - ev->start,
				   .cause = rl_outage_cause_name(ev->cause) };
	rl_daemon_notify(d, &notice);
	uint8_t rec[RL_SERIES_REC_SIZE];
	rl_outage_encode(rec, ev->start, ev->end, ev->cause);
	if (d->outages)
		rl_series_append(d->outages, rec);
}

static void save_targets(rl_daemon *d)
{
	if (rl_lat_targets_save(&d->targets, d->targets_path) != 0)
		syslog(LOG_WARNING, "cannot write %s: %s", d->targets_path, strerror(errno));
}

/* Ids for the configured custom targets: an address probed before keeps its id (and its history). */
static void assign_targets(rl_daemon *d)
{
	bool changed = false;
	uint64_t keep = 0;
	for (int i = 0; i < d->cfg.n_probe_targets; i++)
		keep |= rl_lat_targets_find(&d->targets, &d->cfg.probe_targets[i]) & ~(1ULL << RL_LAT_GATEWAY);
	d->n_probe_ids = 0;
	for (int i = 0; i < d->cfg.n_probe_targets; i++) {
		int id = rl_lat_targets_assign(&d->targets, &d->cfg.probe_targets[i], keep, rl_daemon_now(), &changed);
		if (id < 0)
			continue;
		keep |= 1ULL << id;
		d->probe_ids[d->n_probe_ids++] = id;
	}
	if (changed)
		save_targets(d);
}

/* The WAN's next hop and the interface whose ifup/ifdown count as the WAN's, from the latest netinfo. */
static void update_wan(rl_daemon *d)
{
	const rl_netinfo *ni = &d->net;
	if (ni->gw_iface[0]) {
		snprintf(d->wan_iface, sizeof(d->wan_iface), "%s", ni->gw_iface);
		if (d->wan_state < 0)
			d->wan_state = 1;
		d->gw_scope = ni->gw_scope;
		if (d->lat_minute && rl_lat_targets_gateway(&d->targets, &ni->gw)) {
			char s[RL_IP_STRLEN];
			rl_ip_format(&ni->gw, s);
			syslog(LOG_INFO, "WAN next hop %s (%s)", s, ni->gw_iface);
			save_targets(d);
		}
	} else if (!d->wan_iface[0] && ni->n_wan_names) {
		/* not up since the daemon started: "wan" when it is in a WAN zone, else the first such interface */
		int pick = 0;
		for (int i = 0; i < ni->n_wan_names; i++)
			if (!strcmp(ni->wan_names[i], "wan"))
				pick = i;
		snprintf(d->wan_iface, sizeof(d->wan_iface), "%s", ni->wan_names[pick]);
	}
}

static void probe_done(const rl_icmp_probe *p, int n, void *ctx)
{
	rl_daemon *d = ctx;
	int custom = 0, answered = 0;
	for (int i = 0; i < n; i++) {
		rl_lat_add(&d->lat, d->round_ts, p[i].tag, p[i].answered, p[i].rtt_us);
		if (p[i].tag != RL_LAT_GATEWAY) {
			custom++;
			answered += p[i].answered;
		}
	}
	rl_outage_event ev = rl_outage_round(&d->outage, d->round_ts, custom, answered);
	on_outage(d, &ev);
}

static void probe_timer_cb(struct uloop_timeout *t)
{
	rl_daemon *d = container_of(t, rl_daemon, probe_timer);
	rl_icmp_probe p[RL_ICMP_MAX];
	int n = 0;
	int64_t now = rl_daemon_now();
	if (!d->probe_on)
		return;
	uloop_timeout_set(t, RL_LAT_INTERVAL * 1000);
	check_clock(d, now);
	rl_lat_tick(&d->lat, now);
	const rl_lat_slot *gw = &d->targets.slot[RL_LAT_GATEWAY];
	/* the last known next hop while the WAN is down: its loss shows the WAN outage */
	if (d->cfg.probe_gateway && gw->ip.family)
		p[n++] = (rl_icmp_probe){ .ip = gw->ip, .scope = d->gw_scope, .tag = RL_LAT_GATEWAY };
	for (int i = 0; i < d->n_probe_ids && n < RL_ICMP_MAX; i++)
		p[n++] = (rl_icmp_probe){ .ip = d->targets.slot[d->probe_ids[i]].ip, .tag = d->probe_ids[i] };
	d->round_ts = now;
	rl_icmp_round(d->icmp, p, n, RL_LAT_TIMEOUT_MS);
}

static int open_latency(rl_daemon *d)
{
	char path[256];
	bool bad_m = false, bad_h = false, bad_o = false;
	if (d->lat_minute)
		return 0;
	snprintf(path, sizeof(path), "%s/latency.minute", d->cfg.data_dir);
	d->lat_minute = rl_series_open(path, RL_LAT_KIND_MINUTE, &bad_m);
	snprintf(path, sizeof(path), "%s/latency.hour", d->cfg.data_dir);
	d->lat_hour = rl_series_open(path, RL_LAT_KIND_HOUR, &bad_h);
	snprintf(path, sizeof(path), "%s/outages", d->cfg.data_dir);
	d->outages = rl_series_open(path, RL_OUTAGE_KIND, &bad_o);
	snprintf(d->targets_path, sizeof(d->targets_path), "%s/latency.targets.json", d->cfg.data_dir);
	bool bad_t = rl_lat_targets_load(&d->targets, d->targets_path) != 0;
	if (!d->lat_minute || !d->lat_hour || !d->outages) {
		syslog(LOG_ERR, "cannot open the latency files in %s", d->cfg.data_dir);
		rl_series_close(d->lat_minute);
		rl_series_close(d->lat_hour);
		rl_series_close(d->outages);
		d->lat_minute = d->lat_hour = d->outages = NULL;
		return -1;
	}
	if (bad_m || bad_h || bad_o || bad_t) {
		syslog(LOG_WARNING, "damaged latency files were replaced");
		event(d, RL_EV_DATA_RECOVERED, RL_EV_NO_DEV, 0);
	}
	assign_targets(d);
	rl_lat_reset(&d->lat);
	int n = rl_lat_recover(&d->lat, d->lat_minute, d->lat_hour, rl_daemon_now());
	if (n)
		syslog(LOG_INFO, "rebuilt %d hourly latency records after downtime", n);
	return 0;
}

static void close_latency(rl_daemon *d)
{
	rl_series_close(d->lat_minute);
	rl_series_close(d->lat_hour);
	rl_series_close(d->outages);
	d->lat_minute = d->lat_hour = d->outages = NULL;
	rl_lat_reset(&d->lat);
}

static void start_probe(rl_daemon *d)
{
	if (d->probe_on || open_latency(d) != 0)
		return;
	d->icmp = rl_icmp_open(probe_done, d);
	if (!d->icmp) {
		if (!d->icmp_missing_logged)
			syslog(LOG_ERR, "no raw ICMP socket (%s): latency probes unavailable", strerror(errno));
		d->icmp_missing_logged = true;
		return;
	}
	d->probe_on = true;
	uloop_timeout_set(&d->probe_timer, 1000);
	syslog(LOG_INFO, "latency probes started: %d targets%s", d->n_probe_ids,
	       d->cfg.probe_gateway ? " and the WAN's next hop" : "");
}

/*
 * An ongoing outage ends now. flush: write the open buckets, the open hour too (nothing rebuilds it while
 * the daemon keeps running); without, the open minute is left for the commit that follows (shutdown).
 */
static void stop_probe(rl_daemon *d, bool flush)
{
	if (!d->probe_on)
		return;
	uloop_timeout_cancel(&d->probe_timer);
	rl_icmp_close(d->icmp);
	d->icmp = NULL;
	rl_outage_event ev = rl_outage_stop(&d->outage, rl_daemon_now());
	on_outage(d, &ev);
	if (flush) {
		rl_lat_flush(&d->lat, true);
		rl_lat_reset(&d->lat);
	}
	d->probe_on = false;
	syslog(LOG_INFO, "latency probes stopped");
}

static void detect_probe(rl_daemon *d)
{
	if (d->cfg.probe && d->role.gateway)
		start_probe(d);
	else
		stop_probe(d, true);
	update_wan(d);
}

/* netifd's ifup / ifdown: WAN events for the outage cause and the event log, then a fresh network view. */
static void on_netifd_event(struct ubus_context *ctx, struct ubus_event_handler *ev, const char *type,
			    struct blob_attr *msg)
{
	rl_daemon *d = container_of(ev, rl_daemon, wan_ev);
	enum { N_ACTION, N_IFACE, __N_MAX };
	static const struct blobmsg_policy policy[__N_MAX] = {
		[N_ACTION] = { "action", BLOBMSG_TYPE_STRING },
		[N_IFACE] = { "interface", BLOBMSG_TYPE_STRING },
	};
	struct blob_attr *tb[__N_MAX];
	blobmsg_parse(policy, __N_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[N_ACTION] || !tb[N_IFACE])
		return;
	const char *action = blobmsg_get_string(tb[N_ACTION]), *iface = blobmsg_get_string(tb[N_IFACE]);
	bool up = !strcmp(action, "ifup");
	if (!up && strcmp(action, "ifdown"))
		return;
	if (d->role.gateway && d->wan_iface[0] && !strcmp(iface, d->wan_iface) && d->wan_state != up) {
		d->wan_state = up;
		rl_outage_wan(&d->outage, up, rl_daemon_now());
		event(d, up ? RL_EV_WAN_UP : RL_EV_WAN_DOWN, RL_EV_NO_DEV, 0);
		syslog(LOG_INFO, "WAN interface %s is %s", iface, up ? "up" : "down");
	}
	/* addresses, routes and the next hop changed: refresh soon (not from within a ubus callback) */
	if (!d->names_timer.pending || uloop_timeout_remaining64(&d->names_timer) > 1000)
		uloop_timeout_set(&d->names_timer, 1000);
}

/* ---- router-side speed test ---- */

static void open_speedtest(rl_daemon *d)
{
	char path[256];
	snprintf(path, sizeof(path), "%s/speedtest.json", d->cfg.data_dir);
	d->speed = rl_speedtest_open(path);
}

int rl_daemon_speedtest(rl_daemon *d, const char *server, bool *already)
{
	rl_speed_params p = { .streams = d->cfg.speed_streams, .duration = d->cfg.speed_duration };
	snprintf(p.server, sizeof(p.server), "%s", server);
	/* the WAN devices that are up now; the child reads their counters */
	p.n_wan = d->net.n_wan;
	memcpy(p.wan_devs, d->net.wan_devs, sizeof(p.wan_devs));
	return rl_speedtest_start(d->speed, &p, rl_daemon_now(), already);
}

/* ---- LuCI menu: an access point only shows Wireless and Settings ---- */

static bool set_marker(const char *name, bool on)
{
	char path[64];
	snprintf(path, sizeof(path), RL_RUN_DIR "/%s", name);
	bool exists = access(path, F_OK) == 0;
	if (on == exists)
		return false;
	if (on) {
		mkdir(RL_RUN_DIR, 0755);
		FILE *f = fopen(path, "w");
		if (f)
			fclose(f);
	} else {
		unlink(path);
	}
	return true;
}

static void update_menu(rl_daemon *d, bool running)
{
	bool changed = set_marker("ap", running && d->role.ap);
	changed |= set_marker("ap-only", running && d->role.ap && !d->role.gateway);
	if (!changed)
		return;
	/* LuCI caches the menu with its dependencies resolved */
	glob_t g;
	if (glob("/tmp/luci-indexcache*", 0, NULL, &g) == 0) {
		for (size_t i = 0; i < g.gl_pathc; i++)
			unlink(g.gl_pathv[i]);
		globfree(&g);
	}
}

/* ---- periodic refresh: interfaces, role, names, clock ---- */

static void check_synced(rl_daemon *d)
{
	if (d->synced)
		return;
	int64_t now = rl_daemon_now();
	if (!rl_config_ntp_enabled() || (uptime() > 900 && now > RL_BUILD_EPOCH)) {
		d->synced = true;
		syslog(LOG_INFO, "clock considered set");
	}
}

/* DNS logging (and with it the destinations) on the LAN interfaces, gateway role only. */
static void detect_dns(rl_daemon *d)
{
	if (!d->visits)
		return;
	bool on = d->cfg.dns && d->role.gateway && d->net_ready;
	rl_visits_enable(d->visits, on, d->net.lan_ifindex, d->net.n_lan);
	if (on)
		rl_visits_writable(d->visits, d->synced);
}

/* Every minute on the minute: schedules apply from their first second. */
static void schedule_control(rl_daemon *d)
{
	int64_t now = rl_daemon_now();
	uloop_timeout_set(&d->control_timer, (int)(60 - now % 60) * 1000 + 200);
}

static void control_timer_cb(struct uloop_timeout *t)
{
	rl_daemon *d = container_of(t, rl_daemon, control_timer);
	rl_control_evaluate(d);
	schedule_control(d);
}

/* netifd's device events (a wireless interface came back, a port went up): ports and qdiscs again. */
static void ports_timer_cb(struct uloop_timeout *t)
{
	rl_daemon *d = container_of(t, rl_daemon, ports_timer);
	if (!d->net_ready)
		return;
	rl_control_ports(d);
	rl_control_check(d);
}

static void on_device_event(struct ubus_context *ctx, struct ubus_event_handler *ev, const char *type,
			    struct blob_attr *msg)
{
	rl_daemon *d = container_of(ev, rl_daemon, dev_ev);
	if (!d->ports_timer.pending || uloop_timeout_remaining64(&d->ports_timer) > 2000)
		uloop_timeout_set(&d->ports_timer, 2000);
}

static void names_timer_cb(struct uloop_timeout *t)
{
	rl_daemon *d = container_of(t, rl_daemon, names_timer);
	if (d->ubus_ctx && rl_netinfo_refresh(d->ubus_ctx, &d->net) == 0) {
		bool first = !d->net_ready;
		d->net_ready = true;
		rl_role_detect(d->ubus_ctx, &d->net, &d->role);
		rl_neigh_set_lan_ifindexes(d->neigh, d->net.lan_ifindex, d->net.n_lan);
		if (first)
			rl_neigh_dump(d->neigh);
		if (d->cfg.traffic && d->role.gateway)
			open_traffic(d);
		else
			close_traffic(d);
		detect_ap(d);
		detect_probe(d);
		detect_dns(d);
		update_menu(d, true);
		rl_control_ports(d);
		if (first) {
			rl_daemon_sample(d);
			schedule_sample(d);
			rl_control_evaluate(d);
			schedule_control(d);
		} else {
			rl_control_check(d);
		}
	}
	rl_names_refresh(d->neigh, d->devs, rl_daemon_now());
	check_synced(d);
	uloop_timeout_set(t, d->net_ready ? 60000 : 2000);
}

/* ---- persistence ---- */

static bool on_flash(const char *dir)
{
	struct statfs fs;
	if (statfs(dir, &fs) != 0)
		return true;
	if ((unsigned long)fs.f_type == OVERLAYFS_MAGIC && statfs("/overlay", &fs) != 0)
		return true;
	return (unsigned long)fs.f_type == JFFS2_MAGIC || (unsigned long)fs.f_type == UBIFS_MAGIC;
}

static uint64_t signal_bytes(const rl_daemon *d)
{
	return d->sig_minute ? rl_series_bytes(d->sig_minute) + rl_series_bytes(d->sig_hour) : 0;
}

static uint64_t latency_bytes(const rl_daemon *d)
{
	return d->lat_minute ? rl_series_bytes(d->lat_minute) + rl_series_bytes(d->lat_hour) +
				       rl_series_bytes(d->outages)
			     : 0;
}

uint64_t rl_daemon_storage(const rl_daemon *d)
{
	return rl_store_bytes(d->store) + signal_bytes(d) + latency_bytes(d) + (d->visits ? rl_visits_bytes(d->visits) : 0);
}

static void compute_limits(rl_daemon *d)
{
	struct statvfs vfs;
	uint64_t max = (uint64_t)d->cfg.max_size_mb << 20;
	if (statvfs(d->cfg.data_dir, &vfs) == 0) {
		uint64_t avail = (uint64_t)vfs.f_bavail * vfs.f_frsize + rl_daemon_storage(d);
		uint64_t pct = avail / 100 * (uint64_t)d->cfg.max_size_percent;
		if (pct < max)
			max = pct;
	}
	if (max < (1u << 20))
		max = 1u << 20;
	d->max_bytes = max;
	d->commit_interval = d->cfg.commit_interval ? d->cfg.commit_interval : on_flash(d->cfg.data_dir) ? 3600 : 600;
}

int rl_daemon_commit(rl_daemon *d, bool flush_minute)
{
	check_synced(d);
	if (!d->synced)
		return -1;
	int64_t now = rl_daemon_now();
	int rc = 0;
	if (flush_minute) {
		rl_agg_flush(d->agg, RL_TIER_MINUTE); /* the partial minute; rl_recover adds it back after a restart */
		rl_wifi_flush(d->wifi, false);        /* likewise; rl_wifi_recover rebuilds the open hour from it */
		rl_lat_flush(&d->lat, false);         /* likewise (rl_lat_recover) */
	}
	if (rl_store_commit(d->store) != 0)
		rc = -1;
	if (d->sig_minute && (rl_series_commit(d->sig_minute) != 0 || rl_series_commit(d->sig_hour) != 0))
		rc = -1;
	if (d->lat_minute && (rl_series_commit(d->lat_minute) != 0 || rl_series_commit(d->lat_hour) != 0 ||
			      rl_series_commit(d->outages) != 0))
		rc = -1;
	if (d->visits) {
		rl_visits_writable(d->visits, true);
		if (rl_visits_commit(d->visits, flush_minute) != 0) /* flush: the open hour's destinations too */
			rc = -1;
	}
	if (rl_devtab_save(d->devs, d->devtab_path) != 0)
		rc = -1;
	int64_t day = rl_bucket_start(RL_TIER_DAY, now);
	if (day != d->last_compact_day) {
		/* DNS log and destinations at most 1/8 */
		if (d->visits)
			rl_visits_compact(d->visits, now, d->cfg.dns_keep_days, (uint64_t)d->cfg.dns_max_records,
					  d->max_bytes / 8);
		/* signal history gets at most 3/8 of the size limit: minutes 1/4, hours 1/8 */
		if (d->sig_minute) {
			rl_series_compact(d->sig_minute, now - (int64_t)d->cfg.signal_minute_days * 86400, d->max_bytes / 4);
			rl_series_compact(d->sig_hour, now - (int64_t)d->cfg.signal_hour_days * 86400, d->max_bytes / 8);
		}
		/* latency at most 7/32: minutes 1/8, hours 1/16, outages 1/32 */
		if (d->lat_minute) {
			rl_series_compact(d->lat_minute, now - (int64_t)d->cfg.latency_minute_days * 86400, d->max_bytes / 8);
			rl_series_compact(d->lat_hour, now - (int64_t)d->cfg.latency_hour_days * 86400, d->max_bytes / 16);
			rl_series_compact(d->outages, now - (int64_t)d->cfg.outage_days * 86400, d->max_bytes / 32);
		}
		uint64_t sig = signal_bytes(d) + latency_bytes(d) + (d->visits ? rl_visits_bytes(d->visits) : 0);
		uint64_t store_max = d->max_bytes > sig ? d->max_bytes - sig : 0;
		rl_store_compact(d->store, now, &d->cfg.ret, RL_MAX(store_max, d->max_bytes / 2));
		rl_events_compact(d->events, now, d->cfg.ret.event_days, RL_EVENTS_CAP);
		d->last_compact_day = day;
	}
	if (rc != 0 && !d->commit_failing) {
		syslog(LOG_ERR, "writing to %s failed: %s", d->cfg.data_dir, strerror(errno));
		event(d, RL_EV_COMMIT_FAILED, RL_EV_NO_DEV, 0);
	}
	d->commit_failing = rc != 0;
	if (rl_events_commit(d->events) != 0)
		rc = -1;
	if (rc == 0)
		d->last_commit = now;
	return rc;
}

static void commit_timer_cb(struct uloop_timeout *t)
{
	rl_daemon *d = container_of(t, rl_daemon, commit_timer);
	rl_daemon_commit(d, false);
	uloop_timeout_set(t, d->commit_interval * 1000);
}

static void on_close(rl_tier tier, const rl_rec *r, void *ctx)
{
	rl_daemon *d = ctx;
	rl_store_append(d->store, tier, r);
}

void rl_daemon_reset(rl_daemon *d, unsigned scope)
{
	if (scope & RL_RESET_DEVICES)
		scope |= RL_RESET_TRAFFIC | RL_RESET_EVENTS | RL_RESET_SIGNAL; /* indexes would be reused */
	if (scope & RL_RESET_TRAFFIC) {
		rl_store_reset(d->store);
		rl_agg_reset(d->agg);
		d->baseline_next = true;
		d->wan_valid = false;
		d->traffic_gen++; /* quota sums start over */
	}
	if ((scope & RL_RESET_DNS) && d->visits)
		rl_visits_reset(d->visits);
	if (scope & RL_RESET_EVENTS)
		rl_events_reset(d->events);
	if (scope & RL_RESET_SIGNAL) {
		if (d->sig_minute) {
			rl_series_reset(d->sig_minute);
			rl_series_reset(d->sig_hour);
		}
		rl_wifi_reset_data(d->wifi);
	}
	if (scope & RL_RESET_LATENCY) {
		if (d->lat_minute) {
			rl_series_reset(d->lat_minute);
			rl_series_reset(d->lat_hour);
			rl_series_reset(d->outages);
		}
		rl_lat_reset(&d->lat);
		/* an ongoing outage is dropped too; the WAN's latest ifdown / ifup still count */
		d->outage = (rl_outage){ .wan_down_at = d->outage.wan_down_at, .wan_up_at = d->outage.wan_up_at };
	}
	if (scope & RL_RESET_DEVICES) {
		rl_wifi_clear(d->wifi); /* stations refer to device indexes */
		rl_devtab_clear(d->devs);
		rl_devtab_save(d->devs, d->devtab_path);
		rl_flows_free(d->flows);
		d->flows = rl_flows_new();
		d->quiet_until = rl_daemon_now() + RL_STARTUP_GRACE; /* every device is new again */
	}
	syslog(LOG_NOTICE, "data reset (scope %u)", scope);
}

void rl_daemon_time_synced(rl_daemon *d)
{
	if (!d->synced)
		syslog(LOG_INFO, "clock synchronised by ntpd");
	d->synced = true;
}

/* ---- config device sections ---- */

static void load_devflags(rl_daemon *d)
{
	free(d->devflags);
	d->n_devflags = rl_config_devices(&d->devflags);
}

const rl_devflag *rl_daemon_devflag(const rl_daemon *d, const rl_mac *mac)
{
	for (size_t i = 0; i < d->n_devflags; i++)
		if (rl_mac_eq(&d->devflags[i].mac, mac))
			return &d->devflags[i];
	return NULL;
}

/* ---- setup ---- */

static int mkdirs(const char *path)
{
	char buf[256];
	snprintf(buf, sizeof(buf), "%s", path);
	for (char *p = buf + 1; *p; p++) {
		if (*p != '/')
			continue;
		*p = '\0';
		if (mkdir(buf, 0755) != 0 && errno != EEXIST)
			return -1;
		*p = '/';
	}
	return mkdir(buf, 0755) != 0 && errno != EEXIST ? -1 : 0;
}

/* sysupgrade keeps the data directory (it may have been moved to USB or a disk). */
static void write_keep_list(const char *dir)
{
	char want[260], have[260] = "";
	snprintf(want, sizeof(want), "%s/\n", dir);
	FILE *f = fopen("/lib/upgrade/keep.d/routelink", "r");
	if (f) {
		if (!fgets(have, sizeof(have), f))
			have[0] = '\0';
		fclose(f);
	}
	if (!strcmp(want, have))
		return;
	f = fopen("/lib/upgrade/keep.d/routelink", "w");
	if (f) {
		fputs(want, f);
		fclose(f);
	}
}

static int open_data(rl_daemon *d)
{
	char path[256];
	if (mkdirs(d->cfg.data_dir) != 0) {
		syslog(LOG_ERR, "cannot create %s: %s", d->cfg.data_dir, strerror(errno));
		return -1;
	}
	write_keep_list(d->cfg.data_dir);
	d->store = rl_store_open(d->cfg.data_dir);
	snprintf(path, sizeof(path), "%s/events.bin", d->cfg.data_dir);
	d->events = rl_events_open(path);
	if (!d->store || !d->events) {
		syslog(LOG_ERR, "cannot open data files in %s", d->cfg.data_dir);
		return -1;
	}
	snprintf(d->devtab_path, sizeof(d->devtab_path), "%s/devices.json", d->cfg.data_dir);
	bool damaged = rl_devtab_load(d->devs, d->devtab_path) != 0;
	if (damaged || rl_store_recovered(d->store)) {
		syslog(LOG_WARNING, "damaged data files were replaced");
		event(d, RL_EV_DATA_RECOVERED, RL_EV_NO_DEV, 0);
	}
	bool bad_visits = false;
	d->visits = rl_visits_open(d->cfg.data_dir, &bad_visits);
	if (!d->visits)
		syslog(LOG_ERR, "cannot open the DNS and destination logs in %s", d->cfg.data_dir);
	else if (bad_visits)
		syslog(LOG_WARNING, "a damaged DNS or destination log was replaced");
	compute_limits(d);
	return 0;
}

static void close_data(rl_daemon *d)
{
	rl_store_close(d->store);
	rl_events_close(d->events);
	rl_visits_close(d->visits);
	d->store = NULL;
	d->events = NULL;
	d->visits = NULL;
}

static void on_ubus_connect(struct ubus_context *ctx)
{
	rl_daemon *d = container_of(ctx, rl_daemon, ubus.ctx);
	d->ubus_ctx = ctx;
	rl_api_register(ctx);
	d->wan_ev.cb = on_netifd_event;
	if (ubus_register_event_handler(ctx, &d->wan_ev, "network.interface") != 0)
		syslog(LOG_WARNING, "cannot subscribe to network.interface events: no WAN events");
	d->dev_ev.cb = on_device_event;
	if (ubus_register_event_handler(ctx, &d->dev_ev, "network.device") != 0)
		syslog(LOG_WARNING, "cannot subscribe to network.device events");
	uloop_timeout_set(&d->names_timer, 0);
}

/* Channels, language and the router's name for the push messages. */
static void configure_notify(rl_daemon *d)
{
	char host[64] = "";
	if (gethostname(host, sizeof(host) - 1) != 0)
		host[0] = '\0';
	bool zh = rl_config_notify_zh(d->cfg.notify_lang, d->zonename);
	rl_notifier_configure(d->notifier, d->rules.channels, d->rules.n_channels, zh, host);
}

static void apply_timezone(rl_daemon *d)
{
	rl_config_timezone(d->tz, sizeof(d->tz), d->zonename, sizeof(d->zonename));
	rl_tz_apply(d->tz);
}

int rl_daemon_init(rl_daemon *d)
{
	memset(d, 0, sizeof(*d));
	d->started = rl_daemon_now();
	rl_config_defaults(&d->cfg);
	rl_config_load(&d->cfg);
	apply_timezone(d);

	d->devs = rl_devtab_new();
	d->flows = rl_flows_new();
	d->agg = rl_agg_new(on_close, d);
	d->wifi = rl_wifi_new(on_sig_rec, on_assoc, d);
	d->nl_fd.fd = -1;
	rl_lat_init(&d->lat, on_lat_rec, d);
	rl_lat_targets_init(&d->targets);
	d->wan_state = -1;
	load_devflags(d);
	d->conn_count = calloc(65536, sizeof(uint32_t));
	if (!d->conn_count)
		abort();
	if (open_data(d) != 0)
		return -1;
	/* a fresh device table: the first minutes would announce every device as new */
	d->quiet_until = rl_devtab_count(d->devs) ? 0 : d->started + RL_STARTUP_GRACE;
	open_speedtest(d);
	rl_control_init(d);
	d->notifier = rl_notifier_new();
	rl_notifier_set_refresh(d->notifier, refresh_notice, d);
	configure_notify(d);
	int caught_up = rl_recover(d->store, d->agg, d->started);
	if (caught_up)
		syslog(LOG_INFO, "rebuilt %d hour/day/month records after downtime", caught_up);
	d->last_compact_day = rl_bucket_start(RL_TIER_DAY, d->started);
	d->synced = !rl_config_ntp_enabled() || (uptime() > 900 && d->started > RL_BUILD_EPOCH);
	event(d, RL_EV_DAEMON_START, RL_EV_NO_DEV, 0);

	d->neigh = rl_neigh_open(on_reachable, d);
	if (!d->neigh) {
		syslog(LOG_ERR, "rtnetlink unavailable: %s", strerror(errno));
		return -1;
	}
	d->neigh_fd.fd = rl_neigh_fd(d->neigh);
	d->neigh_fd.cb = neigh_fd_cb;
	uloop_fd_add(&d->neigh_fd, ULOOP_READ);

	d->sample_timer.cb = sample_timer_cb;
	d->names_timer.cb = names_timer_cb;
	d->commit_timer.cb = commit_timer_cb;
	d->wifi_timer.cb = wifi_timer_cb;
	d->survey_timer.cb = survey_timer_cb;
	d->probe_timer.cb = probe_timer_cb;
	d->control_timer.cb = control_timer_cb;
	d->ports_timer.cb = ports_timer_cb;
	uloop_timeout_set(&d->commit_timer, d->commit_interval * 1000);

	rl_api_init(d);
	d->ubus.cb = on_ubus_connect;
	ubus_auto_connect(&d->ubus);
	syslog(LOG_INFO, "routelinkd %s started, data in %s, commit every %d s", rl_version(), d->cfg.data_dir,
	       d->commit_interval);
	return 0;
}

void rl_daemon_reload(rl_daemon *d)
{
	rl_config old = d->cfg;
	rl_config_defaults(&d->cfg);
	rl_config_load(&d->cfg);
	apply_timezone(d);
	load_devflags(d);
	if (d->lat_minute)
		assign_targets(d); /* the probe targets may have changed */
	if (strcmp(old.data_dir, d->cfg.data_dir) != 0) {
		/* data is not migrated: close the old directory after a final write */
		rl_config moved = d->cfg;
		d->cfg = old;
		stop_probe(d, true);
		rl_daemon_commit(d, true);
		d->cfg = moved;
		close_data(d);
		close_latency(d);
		rl_speedtest_close(d->speed); /* a running test is dropped */
		/* the minutes were flushed above; the next names refresh restarts sampling in the new directory */
		stop_wifi(d, false);
		close_signal(d);
		rl_devtab_clear(d->devs);
		rl_flows_free(d->flows);
		d->flows = rl_flows_new();
		rl_agg_reset(d->agg);
		if (open_data(d) != 0) {
			syslog(LOG_ERR, "keeping the old data directory %s", old.data_dir);
			snprintf(d->cfg.data_dir, sizeof(d->cfg.data_dir), "%s", old.data_dir);
			open_data(d);
		}
		rl_recover(d->store, d->agg, rl_daemon_now());
		open_speedtest(d);
		d->baseline_next = true;
	}
	compute_limits(d);
	if (!d->cfg.traffic)
		close_traffic(d);
	rl_control_reload(d); /* limits, quotas, channels */
	configure_notify(d);
	detect_dns(d);
	uloop_timeout_set(&d->names_timer, 0);
	/* a shorter interval applies at once, a longer one after the next commit: a reload puts off none */
	arm_by(&d->commit_timer, d->commit_interval * 1000);
	schedule_sample(d);
	syslog(LOG_INFO, "configuration reloaded");
}

void rl_daemon_shutdown(rl_daemon *d)
{
	stop_probe(d, false); /* an ongoing outage ends here; the commit writes the open minute */
	rl_daemon_commit(d, true);
	update_menu(d, false);
	rl_control_shutdown(d); /* limits and blocks go with the daemon */
	rl_notifier_free(d->notifier);
	d->notifier = NULL;
	close_traffic(d);
	close_nl(d);
	close_signal(d);
	close_latency(d);
	rl_speedtest_close(d->speed);
	rl_wifi_free(d->wifi);
	free(d->devflags);
	if (d->neigh) {
		uloop_fd_delete(&d->neigh_fd);
		rl_neigh_close(d->neigh);
	}
	close_data(d);
	rl_netinfo_free(&d->net);
	rl_devtab_free(d->devs);
	rl_flows_free(d->flows);
	rl_agg_free(d->agg);
	free(d->conn_count);
	syslog(LOG_INFO, "stopped");
}
