#include "core/schedule.h"

#include <ctype.h>
#include <string.h>
#include <time.h>

int rl_weekday_parse(const char *s)
{
	static const char *names[] = { "mon", "tue", "wed", "thu", "fri", "sat", "sun" };
	for (int i = 0; s && i < 7; i++)
		if (strcmp(s, names[i]) == 0)
			return i + 1;
	return 0;
}

int rl_time_parse(const char *s)
{
	if (!s || !isdigit((unsigned char)s[0]))
		return -1;
	int h = 0, m = 0, i = 0;
	while (isdigit((unsigned char)s[i]) && i < 2)
		h = h * 10 + (s[i++] - '0');
	if (s[i++] != ':' || !isdigit((unsigned char)s[i]) || !isdigit((unsigned char)s[i + 1]) || s[i + 2])
		return -1;
	m = (s[i] - '0') * 10 + (s[i + 1] - '0');
	return h < 24 && m < 60 ? h * 60 + m : -1;
}

static bool on_day(const rl_schedule *s, int weekday)
{
	return !s->days || (s->days & (1u << (weekday - 1)));
}

bool rl_schedule_active(const rl_schedule *s, int weekday, int minute)
{
	if (s->start < 0)
		return on_day(s, weekday);
	if (s->stop > s->start)
		return on_day(s, weekday) && minute >= s->start && minute < s->stop;
	/* Past midnight: the evening part on its own day, the morning part on the next. */
	int yesterday = weekday == 1 ? 7 : weekday - 1;
	return (on_day(s, weekday) && minute >= s->start) || (on_day(s, yesterday) && minute < s->stop);
}

bool rl_schedule_active_at(const rl_schedule *s, int64_t ts)
{
	time_t t = (time_t)ts;
	struct tm tm;
	localtime_r(&t, &tm);
	int weekday = tm.tm_wday == 0 ? 7 : tm.tm_wday;
	return rl_schedule_active(s, weekday, tm.tm_hour * 60 + tm.tm_min);
}
