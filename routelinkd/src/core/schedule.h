/*
 * When a speed-limit rule applies (P4): on some weekdays, optionally only between two local times. A window
 * whose end is not after its start runs past midnight, and then belongs to the day it starts on.
 */
#ifndef RL_SCHEDULE_H
#define RL_SCHEDULE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
	/* bit 0 = Monday … bit 6 = Sunday; 0 = every day */
	uint8_t days;
	/* minutes after local midnight; start < 0 = all day */
	int16_t start, stop;
} rl_schedule;

/* "mon" … "sun" → 1 … 7, 0 when unknown. */
int rl_weekday_parse(const char *s);
/* "HH:MM" → minutes, -1 when invalid. */
int rl_time_parse(const char *s);

/* weekday 1 = Monday … 7 = Sunday, minute 0–1439. */
bool rl_schedule_active(const rl_schedule *s, int weekday, int minute);
/* At ts in the process-local time zone (TZ applied). */
bool rl_schedule_active_at(const rl_schedule *s, int64_t ts);

#endif
