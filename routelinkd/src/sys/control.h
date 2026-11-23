/*
 * Speed limits, quotas and blocking in the daemon (design §9, P4 plan §0.2–0.4): once a minute the limit
 * rules whose schedule applies and the quotas' use (internet traffic of the device since its period began,
 * from the day records plus the open day) decide which tc rules (sys/shaper) and which blocked MACs
 * (sys/block) are wanted. Quota run state lives in quota.json. Gateway role only.
 */
#ifndef RL_CONTROL_H
#define RL_CONTROL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "core/quota.h"
#include "sys/config.h"

struct rl_daemon;

/* A quota's current use and state, for the `quotas` method. */
typedef struct {
	const rl_quota_rule *rule;
	const rl_quota_run *run;
	uint64_t used;
	int64_t start, end;
} rl_quota_view;

void rl_control_init(struct rl_daemon *d);
/* The rules were reloaded: carries the quota state over, evaluates now, tries failed setups again. */
void rl_control_reload(struct rl_daemon *d);
/* The LAN ports (bridge members of the LAN interfaces, from netifd) after a network refresh. */
void rl_control_ports(struct rl_daemon *d);
/* Ports whose qdiscs went missing get them back; the block table too. */
void rl_control_check(struct rl_daemon *d);
/* Schedules and quotas (every minute). */
void rl_control_evaluate(struct rl_daemon *d);
void rl_control_shutdown(struct rl_daemon *d);
/* quota_allow: until the hour is over or the period ends. -1 when the section is no enabled quota. */
int rl_control_allow(struct rl_daemon *d, const char *section, bool until_period);
size_t rl_control_quotas(struct rl_daemon *d, rl_quota_view *out, size_t max);
/* Why limits or blocking could not be set up, "" when fine. */
const char *rl_control_error(const struct rl_daemon *d);
/* Speed-limit rules set up now. */
size_t rl_control_active_limits(const struct rl_daemon *d);

#endif
