/* What this router is (gateway, access point), its flow offloading mode and whether nlbwmon runs. */
#ifndef RL_ROLE_H
#define RL_ROLE_H

#include <stdbool.h>

#include <libubus.h>

#include "sys/netinfo.h"

typedef enum { RL_OFFLOAD_NONE, RL_OFFLOAD_SOFTWARE, RL_OFFLOAD_HARDWARE, RL_OFFLOAD_SFE } rl_offload;

typedef struct {
	bool gateway;
	bool ap; /* has (or is configured for) an AP-mode wireless interface; set by the daemon */
	rl_offload offload;
	bool nlbwmon_running;
} rl_role;

/* Gateway, offloading and nlbwmon (ap is left alone: it comes from nl80211). */
void rl_role_detect(struct ubus_context *ctx, const rl_netinfo *ni, rl_role *r);
/* UCI wireless has an enabled wifi-iface in AP mode on an enabled radio (wireless may be down right now). */
bool rl_role_wifi_configured(void);
const char *rl_offload_name(rl_offload o);
/* Hardware offload and SFE bypass conntrack accounting. */
bool rl_offload_warning(rl_offload o);

#endif
