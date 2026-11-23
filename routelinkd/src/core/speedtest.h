/*
 * Router-side speed test (design §12, P3 plan §0.4): the server URLs, the statistics, the lines the test
 * process reports over its pipe and the result log (speedtest.json, the latest RL_SPEED_KEEP runs). The
 * measuring itself (sys/speedtest) runs in a child process.
 */
#ifndef RL_SPEEDTEST_CORE_H
#define RL_SPEEDTEST_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define RL_SPEED_KEEP 100
#define RL_SPEED_PINGS 10       /* TCP handshakes timed for the latency */
#define RL_SPEED_WARMUP_MS 1000 /* the first second of a transfer (slow start) does not count */
#define RL_SPEED_URL_LEN 512

typedef enum { RL_SPEED_LATENCY, RL_SPEED_DOWNLOAD, RL_SPEED_UPLOAD, RL_SPEED_DONE, RL_SPEED_FAILED } rl_speed_phase;
const char *rl_speed_phase_name(rl_speed_phase p);

/* Where a test goes: Cloudflare, or a LibreSpeed server given by its base URL. */
typedef struct {
	char down[RL_SPEED_URL_LEN], up[RL_SPEED_URL_LEN];
	char host[256]; /* without brackets for an IPv6 literal */
	int port;       /* of the URL, else 80 / 443 */
} rl_speed_target;

/* server "" = Cloudflare, else an http(s) base URL (a missing trailing slash is added); false when unusable. */
bool rl_speed_target_of(const char *server, rl_speed_target *t);

/* Median and mean difference of consecutive values (ms); n > 0. */
void rl_speed_stats(const double *ms, int n, double *median, double *jitter);
/*
 * Bits per second from cumulative byte counters sampled at t_ms (ascending), leaving out the first warmup_ms;
 * counters that went backwards (interface re-created) add nothing for that step. -1 without two samples.
 */
int64_t rl_speed_rate(const int64_t *t_ms, const uint64_t *bytes, int n, int warmup_ms);

typedef struct {
	int id;
	int64_t ts; /* start */
	char server[256];
	double latency_ms, jitter_ms; /* < 0: not measured */
	int64_t down_bps, up_bps;     /* < 0: not measured */
	char error[128];              /* "" = none */
} rl_speed_result;

/* A result with nothing measured yet. */
void rl_speed_result_init(rl_speed_result *r, int id, int64_t ts, const char *server);

/*
 * One line of the test process (without the newline): "P <phase> <progress>", "L <latency_ms> <jitter_ms>",
 * "D <bps>", "U <bps>", "E <message>". Updates r, *phase (failed after E) and *progress; false when the
 * line is not understood.
 */
bool rl_speed_line(const char *line, rl_speed_result *r, rl_speed_phase *phase, double *progress);

typedef struct {
	rl_speed_result *items; /* oldest first */
	size_t n, cap;
	int last_id;
} rl_speed_log;

/* A missing file gives an empty log; -1 when damaged (the log is empty then). */
int rl_speed_log_load(rl_speed_log *l, const char *path);
int rl_speed_log_save(const rl_speed_log *l, const char *path);
/* Appends r and drops the oldest beyond RL_SPEED_KEEP. */
void rl_speed_log_add(rl_speed_log *l, const rl_speed_result *r);
const rl_speed_result *rl_speed_log_find(const rl_speed_log *l, int id);
void rl_speed_log_free(rl_speed_log *l);

#endif
