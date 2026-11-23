/* State of the running daemon and the operations the event loop and the ubus API share. */
#ifndef RL_DAEMON_H
#define RL_DAEMON_H

#include <stdbool.h>
#include <stdint.h>

#include <libubox/uloop.h>
#include <libubus.h>

#include "core/agg.h"
#include "core/devtab.h"
#include "core/events.h"
#include "core/flows.h"
#include "core/latency.h"
#include "core/series.h"
#include "core/store.h"
#include "core/wifi.h"
#include "sys/block.h"
#include "sys/config.h"
#include "sys/control.h"
#include "sys/ct.h"
#include "sys/icmp.h"
#include "sys/neigh.h"
#include "sys/netinfo.h"
#include "sys/nl80211.h"
#include "sys/notify.h"
#include "sys/role.h"
#include "sys/shaper.h"
#include "sys/speedtest.h"
#include "sys/visits.h"

#define RL_API_VERSION 1
#define RL_LIVE_LEASE 30   /* seconds a `live` call keeps fast sampling on */
#define RL_EVENTS_CAP 100000
#define RL_STARTUP_GRACE 180 /* no online/offline events right after start */
#define RL_WIFI_INTERVAL 10      /* station sampling */
#define RL_WIFI_LIVE_INTERVAL 1  /* station sampling while a `stations` live lease runs */
#define RL_SURVEY_INTERVAL 60    /* channel busy time */
#define RL_RUN_DIR "/var/run/routelink" /* markers for the LuCI menu (ap, ap-only) */

typedef enum {
	RL_RESET_TRAFFIC = 1,
	RL_RESET_EVENTS = 2,
	RL_RESET_DEVICES = 4,
	RL_RESET_SIGNAL = 8,
	RL_RESET_LATENCY = 16, /* latency history and outages */
	RL_RESET_DNS = 32,     /* DNS log and destinations */
} rl_reset_scope;

/* A quota's run state and use (parallel to rules.quotas). */
typedef struct {
	char section[64];
	rl_mac mac;
	rl_quota_run run;
	uint64_t used;
	int64_t start, end;
	/* sum of the closed days of the period, cached */
	int64_t cache_from, cache_to;
	unsigned cache_gen;
	int cache_dev;
	uint64_t cache_rx, cache_tx;
} rl_quota_live;

typedef struct rl_daemon {
	rl_config cfg;
	char tz[64], zonename[64];

	rl_store *store;
	rl_agg *agg;
	rl_devtab *devs;
	rl_events *events;
	rl_flows *flows;
	rl_netinfo net;
	rl_role role;
	rl_ct *ct;
	rl_neigh *neigh;

	/* wireless (AP role) */
	rl_wifi *wifi;
	rl_nl80211 *nl;              /* NULL without nl80211 (retried every minute) */
	rl_series *sig_minute, *sig_hour; /* opened when the module first runs */
	rl_nl_iface ifaces[RL_NL_MAX_IFACES]; /* AP interfaces of the latest station sample */
	int n_ifaces;
	rl_devflag *devflags; /* config device sections */
	size_t n_devflags;

	/* latency probes and outages (gateway role) */
	rl_icmp *icmp;                              /* open while probing runs */
	rl_series *lat_minute, *lat_hour, *outages; /* opened when the module first runs */
	rl_lat lat;
	rl_lat_targets targets;
	int probe_ids[RL_PROBE_MAX_TARGETS]; /* ids of the configured custom targets */
	int n_probe_ids;
	rl_outage outage;
	int64_t round_ts;
	int gw_scope;                     /* ifindex for a link-local IPv6 next hop */
	char wan_iface[RL_IFACE_NAMELEN]; /* netifd interface whose ifup/ifdown are the WAN's */
	char targets_path[256];
	bool probe_on, icmp_missing_logged;
	int8_t wan_state; /* -1 unknown, 0 down, 1 up: netifd repeats ifdown */
	struct ubus_event_handler wan_ev;

	rl_speedtest *speed; /* router-side speed test and its results */

	/* speed limits, quotas, blocking (gateway role): sys/control */
	rl_rules rules;
	rl_quota_live *qlive;
	rl_shaper *shaper;
	rl_block *block;
	char ports[RL_SHAPER_MAX_PORTS][IFNAMSIZ]; /* LAN bridge members */
	int n_ports;
	unsigned traffic_gen; /* a traffic reset makes cached quota sums stale */
	struct uloop_timeout control_timer, ports_timer;
	struct ubus_event_handler dev_ev;

	rl_visits *visits; /* DNS log and destinations, opened when first switched on */

	rl_notifier *notifier;
	int64_t quiet_until; /* no new-device notices before (a fresh device table) */

	struct ubus_auto_conn ubus;
	struct ubus_context *ubus_ctx; /* NULL while disconnected */

	struct uloop_timeout sample_timer, names_timer, commit_timer, wifi_timer, survey_timer, probe_timer;
	struct uloop_fd ct_fd, neigh_fd, nl_fd;

	int64_t started, last_sample, last_commit, last_compact_day, live_until, wifi_live_until, last_clock;
	bool net_ready, synced, baseline_next, commit_failing, wifi_on, nl_missing_logged;
	uint64_t wan_rx, wan_tx;
	bool wan_valid;
	uint64_t max_bytes;
	int commit_interval;
	uint32_t *conn_count; /* per device index, reused by every sample */
	char devtab_path[256];
} rl_daemon;

int rl_daemon_init(rl_daemon *d);
void rl_daemon_shutdown(rl_daemon *d);
/* SIGHUP: config, time zone and retention. */
void rl_daemon_reload(rl_daemon *d);

bool rl_daemon_traffic_on(const rl_daemon *d);
void rl_daemon_sample(rl_daemon *d);
/* Starts or extends the live lease; samples immediately when it was not running. */
void rl_daemon_live(rl_daemon *d);
/* Wireless sampling runs (AP role, module on). */
bool rl_daemon_wifi_on(const rl_daemon *d);
/* Starts or extends the stations live lease (1 s sampling); samples right away when it was not running. */
void rl_daemon_wifi_live(rl_daemon *d);
/* Current station sampling interval in seconds. */
int rl_daemon_wifi_interval(const rl_daemon *d);
/* Latency probes run (gateway role, module on). */
bool rl_daemon_probe_on(const rl_daemon *d);
/* Target ids being probed (bit per id): the configured custom targets and the next hop when known. */
uint64_t rl_daemon_probe_targets(const rl_daemon *d);
/* Starts a speed test against server ("" = Cloudflare) unless one runs (*already, its id). -1 on failure. */
int rl_daemon_speedtest(rl_daemon *d, const char *server, bool *already);
/* Fills a notice's name, ip and mac for a device. */
void rl_daemon_describe(rl_daemon *d, const rl_mac *mac, rl_notify_event *ev);
/* Hands a notice to the push channels (gateway role). */
void rl_daemon_notify(rl_daemon *d, const rl_notify_event *ev);
/* Bytes of every data file (traffic, signal, latency, DNS log, destinations). */
uint64_t rl_daemon_storage(const rl_daemon *d);
/* The config device section of a MAC, or NULL. */
const rl_devflag *rl_daemon_devflag(const rl_daemon *d, const rl_mac *mac);
/* Writes pending data when the clock is trusted; flush_minute also writes the unfinished minute (before a
 * shutdown or a firmware backup). Returns 0 on success. */
int rl_daemon_commit(rl_daemon *d, bool flush_minute);
void rl_daemon_reset(rl_daemon *d, unsigned scope);
void rl_daemon_time_synced(rl_daemon *d);
int64_t rl_daemon_now(void);

#endif
