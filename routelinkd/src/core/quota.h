/*
 * Data quotas (design §9.2, P4): the period a quota counts in (day, week or month from a reset day, in the
 * router's local time, across DST changes) and its state machine: a notice at 80 %, the action (block or
 * slow down) at 100 %, back to normal when the next period starts, and letting a device through for a while.
 */
#ifndef RL_QUOTA_H
#define RL_QUOTA_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum { RL_QUOTA_DAY, RL_QUOTA_WEEK, RL_QUOTA_MONTH } rl_quota_period;
typedef enum { RL_QS_OK, RL_QS_WARNED, RL_QS_EXCEEDED, RL_QS_ALLOWED } rl_quota_state;

/* "day" | "week" | "month", -1 when unknown. */
int rl_quota_period_parse(const char *s);
const char *rl_quota_state_name(rl_quota_state s);

/*
 * The period containing now: from local midnight; weeks start on reset_day (1 = Monday … 7 = Sunday),
 * months on day reset_day (1–28). TZ must be applied.
 */
void rl_quota_bounds(rl_quota_period p, int reset_day, int64_t now, int64_t *start, int64_t *end);

/* What the daemon has to do after a step. */
enum {
	RL_QA_WARN = 1 << 0,    /* crossed 80 %: notify (quota_warn) */
	RL_QA_ENFORCE = 1 << 1, /* crossed 100 %: block or slow down, notify (quota_exceeded) */
	RL_QA_RELEASE = 1 << 2, /* lift the block / slow-down */
	RL_QA_RESET = 1 << 3,   /* a new period began (quota_reset) */
};

typedef struct {
	int64_t period_start; /* 0 before the first step */
	bool warned, enforced;
	int64_t allow_until; /* let through until, 0 = not */
	rl_quota_state state;
} rl_quota_run;

/*
 * Feeds the current use; returns RL_QA_* flags. Use below the limit again (it was raised) lifts the action,
 * below 80 % the warning too, so the new thresholds count.
 */
unsigned rl_quota_step(rl_quota_run *r, int64_t now, int64_t period_start, uint64_t used, uint64_t limit);
/* Lets the device through until `until` (an hour from now, or the period's end); returns RL_QA_RELEASE if enforced. */
unsigned rl_quota_allow(rl_quota_run *r, int64_t until);

/* A quota's run state as kept in quota.json between restarts (state is recomputed by the next step). */
typedef struct {
	char section[64];
	uint8_t mac[6];
	rl_quota_run run;
} rl_quota_saved;

/* *out is malloc'd (or NULL). A missing file gives no entries; a damaged one too, and returns -1. */
int rl_quota_load(const char *path, rl_quota_saved **out, size_t *n);
/* Written to path.tmp, then renamed. */
int rl_quota_save(const char *path, const rl_quota_saved *s, size_t n);

#endif
