/* Which LAN device a connection belongs to, and whether it is internet, LAN or router traffic. */
#ifndef RL_CLASSIFY_H
#define RL_CLASSIFY_H

#include <stdbool.h>

#include "core/addr.h"
#include "core/flows.h"

typedef enum { RL_CLASS_INTERNET, RL_CLASS_LAN, RL_CLASS_ROUTER, RL_CLASS_COUNT } rl_class;

typedef struct {
	rl_cidr_set local;        /* LAN-zone subnets (IPv4 networks, IPv6 prefixes) */
	rl_cidr_set router_addrs; /* every address of the router itself, as host routes */
} rl_netview;

typedef struct {
	int n; /* 0, 1 or 2 */
	struct {
		rl_ip client;        /* the LAN device (unset when router is true) */
		bool router;         /* traffic of the router itself */
		rl_class cls;
		bool client_is_orig; /* the device opened the connection */
	} a[2];
} rl_attribution;

rl_attribution rl_classify(const rl_netview *nv, const rl_ct_sample *s);

/* rx/tx from the device's point of view: what it received and what it sent. */
void rl_client_bytes(bool client_is_orig, rl_delta d, uint64_t *rx, uint64_t *tx);

const char *rl_class_name(rl_class c);

#endif
