/*
 * nl80211 over generic netlink (libmnl, no libnl): AP-mode interfaces, station and survey dumps, and the
 * NEW_STATION / DEL_STATION events of the "mlme" multicast group. Only attributes that 4.x kernels already
 * have are read (no EHT), so the same code builds against every supported release.
 */
#ifndef RL_NL80211_H
#define RL_NL80211_H

#include <net/if.h>
#include <stdbool.h>
#include <stdint.h>

#include "core/addr.h"
#include "core/wifi.h"

#define RL_NL_MAX_IFACES 16

typedef struct {
	int ifindex;
	uint32_t wiphy;
	char ifname[IFNAMSIZ];
	char phy[16];
	char ssid[33];
	rl_mac bssid;
	uint32_t freq;  /* MHz; 0 while the interface does not operate */
	uint16_t width; /* MHz; 0 when unknown */
} rl_nl_iface;

typedef struct rl_nl80211 rl_nl80211;
/* NEW_STATION (added) or DEL_STATION on an interface. */
typedef void (*rl_nl_event_cb)(bool added, int ifindex, const rl_mac *mac, void *ctx);
typedef void (*rl_nl_sta_cb)(const rl_sta_sample *s, void *ctx);
typedef void (*rl_nl_survey_cb)(const rl_survey_sample *s, void *ctx);

/* NULL when the kernel has no nl80211 (no wireless driver loaded); errno tells why. */
rl_nl80211 *rl_nl80211_open(rl_nl_event_cb cb, void *ctx);
void rl_nl80211_close(rl_nl80211 *n);
/* Event socket, -1 when station events are not available. */
int rl_nl80211_event_fd(const rl_nl80211 *n);
/* Reads pending events; true when some were lost (the caller resyncs with a dump). */
bool rl_nl80211_on_readable(rl_nl80211 *n);

/* Interfaces in AP mode: the count (at most max), or -1. */
int rl_nl80211_ap_ifaces(rl_nl80211 *n, rl_nl_iface *out, int max);
/* Station dump of one interface: 0 or -1. */
int rl_nl80211_stations(rl_nl80211 *n, int ifindex, rl_nl_sta_cb cb, void *ctx);
/* Survey dump of the radio behind an interface (wiphy is copied into every sample): 0 or -1. */
int rl_nl80211_survey(rl_nl80211 *n, int ifindex, uint32_t wiphy, rl_nl_survey_cb cb, void *ctx);

#endif
