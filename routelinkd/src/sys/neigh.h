/* IP -> MAC from the kernel neighbour table (rtnetlink) and DHCP leases; device names from DHCP config. */
#ifndef RL_NEIGH_H
#define RL_NEIGH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/addr.h"
#include "core/devtab.h"

typedef struct rl_neigh rl_neigh;
/* Called when the kernel confirms a LAN neighbour as reachable. */
typedef void (*rl_neigh_cb)(const rl_mac *mac, int64_t now, void *ctx);

rl_neigh *rl_neigh_open(rl_neigh_cb on_reachable, void *ctx);
void rl_neigh_close(rl_neigh *n);
int rl_neigh_fd(const rl_neigh *n);
void rl_neigh_on_readable(rl_neigh *n);
int rl_neigh_dump(rl_neigh *n);
/* Only neighbours on these interfaces count (empty: all). */
void rl_neigh_set_lan_ifindexes(rl_neigh *n, const int *idx, int count);

bool rl_neigh_lookup(const rl_neigh *n, const rl_ip *ip, rl_mac *out);
/* Addresses currently known for a MAC (IPv4 first). */
size_t rl_neigh_ips(const rl_neigh *n, const rl_mac *mac, rl_ip *out, size_t max);

/*
 * Re-reads /tmp/dhcp.leases and the dhcp host sections: fills device hostname/name, adds lease addresses
 * as lookup fallbacks and touches devices whose lease was renewed.
 */
void rl_names_refresh(rl_neigh *n, rl_devtab *t, int64_t now);

#endif
