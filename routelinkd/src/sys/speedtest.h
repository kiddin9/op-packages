/*
 * Router-side speed test (design §12, P3 plan §0.4). A forked child does the blocking work: name lookup,
 * TCP handshake timing, then parallel uclient-fetch downloads and uploads while it samples the WAN byte
 * counters (so traffic of other devices at the same time counts too). It reports over a pipe; the daemon
 * keeps the progress and appends the result to speedtest.json. One test at a time.
 */
#ifndef RL_SPEEDTEST_H
#define RL_SPEEDTEST_H

#include <net/if.h>
#include <stdbool.h>

#include "core/speedtest.h"
#include "sys/netinfo.h"

typedef struct {
	char server[256]; /* "" = Cloudflare, else a LibreSpeed base URL */
	int streams;      /* parallel transfers */
	int duration;     /* seconds per direction */
	char wan_devs[RL_MAX_WAN_DEVS][IFNAMSIZ];
	int n_wan;
} rl_speed_params;

/* The running test. */
typedef struct {
	int id;
	rl_speed_phase phase;
	double progress; /* 0-1 */
} rl_speed_run;

typedef struct rl_speedtest rl_speedtest;

/* Loads the results kept at path. */
rl_speedtest *rl_speedtest_open(const char *path);
/* Stops a running test (its processes are killed, nothing is recorded). */
void rl_speedtest_close(rl_speedtest *s);
/*
 * Starts a test and returns its id; while one runs, returns that one's id with *already set. -1 when the
 * process cannot be started.
 */
int rl_speedtest_start(rl_speedtest *s, const rl_speed_params *p, int64_t now, bool *already);
/* The running test, NULL when none runs. */
const rl_speed_run *rl_speedtest_current(const rl_speedtest *s);
/* Finished tests, oldest first. */
const rl_speed_log *rl_speedtest_log(const rl_speedtest *s);

#endif
