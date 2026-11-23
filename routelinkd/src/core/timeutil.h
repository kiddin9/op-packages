/* Time buckets aligned to the router's local time zone. */
#ifndef RL_TIMEUTIL_H
#define RL_TIMEUTIL_H

#include <stdint.h>

typedef enum { RL_TIER_MINUTE, RL_TIER_HOUR, RL_TIER_DAY, RL_TIER_MONTH, RL_TIER_COUNT } rl_tier;

/* Start of the bucket that contains ts, in the process-local time zone (TZ must be applied). */
int64_t rl_bucket_start(rl_tier tier, int64_t ts);
/* Start of the bucket after the one that contains ts. */
int64_t rl_bucket_next(rl_tier tier, int64_t ts);
/* First bucket boundary at or after ts. */
int64_t rl_bucket_ceil(rl_tier tier, int64_t ts);
/* Local hour of day (0-23). */
int rl_local_hour(int64_t ts);
/* setenv("TZ") + tzset(); NULL or "" means UTC. */
void rl_tz_apply(const char *posix_tz);
/* Nominal length used for retention and step maths (month = 31 days). */
int64_t rl_tier_seconds(rl_tier tier);
const char *rl_tier_name(rl_tier tier);

#endif
