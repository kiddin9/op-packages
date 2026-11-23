/*
 * Speed limits on the LAN bridge ports (design §9.1, P4 plan §0.2): core/tcgen's scripts run through
 * `tc -batch -`, one port at a time (clear, then set up). The ports are checked for RouteLink's qdiscs (an
 * rtnetlink dump) because `wifi reload` and ports going down and up drop them. A setup that fails (missing
 * kernel modules, no tc) is reported, not retried, until the rules or the ports change or retry is called.
 */
#ifndef RL_SHAPER_H
#define RL_SHAPER_H

#include <net/if.h>
#include <stdbool.h>
#include <stddef.h>

#include "core/tcgen.h"

#define RL_SHAPER_MAX_PORTS 32

typedef struct rl_shaper rl_shaper;

/* marker: file listing the ports set up (survives a daemon crash, not a reboot); NULL for none */
rl_shaper *rl_shaper_new(const char *marker);
/* clear: remove the limits from every port first (the daemon stops). */
void rl_shaper_free(rl_shaper *s, bool clear);
/* The ports to shape; a port that left is cleared. */
void rl_shaper_set_ports(rl_shaper *s, const char (*ports)[IFNAMSIZ], int n);
/* The rules that apply now (one per MAC). Returns true when they changed. */
bool rl_shaper_set_rules(rl_shaper *s, const rl_tc_rule *rules, size_t n);
/*
 * Brings the ports up to date; with check also the ones whose qdiscs went missing. Returns the number of
 * ports that were set up (or cleared) now.
 */
int rl_shaper_sync(rl_shaper *s, bool check);
/* Why setting up failed, "" when every port is fine. */
const char *rl_shaper_error(const rl_shaper *s);
/* Tries failed ports again at the next sync (configuration reload). */
void rl_shaper_retry(rl_shaper *s);
/* The current rules. */
size_t rl_shaper_rules(const rl_shaper *s, const rl_tc_rule **out);

#endif
