/* ubus object "routelink" (API version 1, see docs/superpowers/plans/2026-10-05-routelink-p1.md T18). */
#ifndef RL_API_H
#define RL_API_H

#include <libubus.h>

struct rl_daemon;

void rl_api_init(struct rl_daemon *d);
int rl_api_register(struct ubus_context *ctx);

#endif
