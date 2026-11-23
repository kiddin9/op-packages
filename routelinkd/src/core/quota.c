#include "core/quota.h"

#include <json-c/json.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "core/addr.h"
#include "core/util.h"

int rl_quota_period_parse(const char *s)
{
	if (!s)
		return -1;
	if (strcmp(s, "day") == 0)
		return RL_QUOTA_DAY;
	if (strcmp(s, "week") == 0)
		return RL_QUOTA_WEEK;
	if (strcmp(s, "month") == 0)
		return RL_QUOTA_MONTH;
	return -1;
}

const char *rl_quota_state_name(rl_quota_state s)
{
	static const char *names[] = { "ok", "warned", "exceeded", "allowed" };
	return names[s];
}

/* Local midnight of the calendar day year/mon/mday (normalised, so day 0 or 32 is fine). */
static int64_t midnight(int year, int mon, int mday)
{
	struct tm tm = { .tm_year = year, .tm_mon = mon, .tm_mday = mday, .tm_isdst = -1 };
	return (int64_t)mktime(&tm);
}

void rl_quota_bounds(rl_quota_period p, int reset_day, int64_t now, int64_t *start, int64_t *end)
{
	time_t t = (time_t)now;
	struct tm tm;
	localtime_r(&t, &tm);
	switch (p) {
	case RL_QUOTA_DAY:
		*start = midnight(tm.tm_year, tm.tm_mon, tm.tm_mday);
		*end = midnight(tm.tm_year, tm.tm_mon, tm.tm_mday + 1);
		break;
	case RL_QUOTA_WEEK: {
		int first = reset_day >= 1 && reset_day <= 7 ? reset_day : 1;
		int weekday = tm.tm_wday == 0 ? 7 : tm.tm_wday;
		int back = (weekday - first + 7) % 7;
		*start = midnight(tm.tm_year, tm.tm_mon, tm.tm_mday - back);
		*end = midnight(tm.tm_year, tm.tm_mon, tm.tm_mday - back + 7);
		break;
	}
	default: {
		int day = reset_day >= 1 && reset_day <= 28 ? reset_day : 1;
		int mon = tm.tm_mday >= day ? tm.tm_mon : tm.tm_mon - 1;
		*start = midnight(tm.tm_year, mon, day);
		*end = midnight(tm.tm_year, mon + 1, day);
		break;
	}
	}
}

unsigned rl_quota_step(rl_quota_run *r, int64_t now, int64_t period_start, uint64_t used, uint64_t limit)
{
	unsigned act = 0;
	if (r->period_start != period_start) {
		if (r->period_start)
			act |= RL_QA_RESET;
		if (r->enforced)
			act |= RL_QA_RELEASE;
		r->period_start = period_start;
		r->warned = r->enforced = false;
		r->allow_until = 0;
	}
	if (r->allow_until > now) {
		r->state = RL_QS_ALLOWED;
		if (r->enforced) {
			r->enforced = false;
			act |= RL_QA_RELEASE;
		}
		return act;
	}
	r->allow_until = 0;
	if (limit && used >= limit) {
		r->state = RL_QS_EXCEEDED;
		if (!r->enforced) {
			r->enforced = true;
			r->warned = true;
			act |= RL_QA_ENFORCE;
		}
		return act;
	}
	if (r->enforced) { /* the limit was raised (or removed) */
		r->enforced = false;
		act |= RL_QA_RELEASE;
	}
	if (limit && used >= limit - limit / 5) { /* 80 % */
		r->state = RL_QS_WARNED;
		if (!r->warned) {
			r->warned = true;
			act |= RL_QA_WARN;
		}
	} else {
		r->state = RL_QS_OK;
		r->warned = false;
	}
	return act;
}

unsigned rl_quota_allow(rl_quota_run *r, int64_t until)
{
	r->allow_until = until;
	r->state = RL_QS_ALLOWED;
	if (!r->enforced)
		return 0;
	r->enforced = false;
	return RL_QA_RELEASE;
}

static int64_t get_i64(json_object *o, const char *key)
{
	json_object *v;
	return json_object_object_get_ex(o, key, &v) ? json_object_get_int64(v) : 0;
}

static bool get_bool(json_object *o, const char *key)
{
	json_object *v;
	return json_object_object_get_ex(o, key, &v) && json_object_get_boolean(v);
}

int rl_quota_load(const char *path, rl_quota_saved **out, size_t *n)
{
	size_t cap = 0;
	*out = NULL;
	*n = 0;
	if (access(path, F_OK) != 0)
		return 0;
	json_object *root = json_object_from_file(path), *list, *v;
	if (!root || !json_object_object_get_ex(root, "quotas", &list) || !json_object_is_type(list, json_type_array)) {
		json_object_put(root);
		return -1;
	}
	for (size_t i = 0; i < json_object_array_length(list); i++) {
		json_object *e = json_object_array_get_idx(list, i);
		rl_mac mac;
		if (!json_object_object_get_ex(e, "mac", &v) || !rl_mac_parse(json_object_get_string(v), &mac) ||
		    !json_object_object_get_ex(e, "section", &v))
			continue;
		*out = rl_grow(*out, &cap, *n + 1, sizeof(**out));
		rl_quota_saved *q = &(*out)[(*n)++];
		memset(q, 0, sizeof(*q));
		snprintf(q->section, sizeof(q->section), "%s", json_object_get_string(v));
		memcpy(q->mac, mac.b, 6);
		q->run.period_start = get_i64(e, "period_start");
		q->run.warned = get_bool(e, "warned");
		q->run.enforced = get_bool(e, "enforced");
		q->run.allow_until = get_i64(e, "allow_until");
	}
	json_object_put(root);
	return 0;
}

int rl_quota_save(const char *path, const rl_quota_saved *s, size_t n)
{
	char tmp[512], mac[RL_MAC_STRLEN];
	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	json_object *root = json_object_new_object(), *list = json_object_new_array();
	json_object_object_add(root, "version", json_object_new_int(1));
	for (size_t i = 0; i < n; i++) {
		json_object *e = json_object_new_object();
		rl_mac m;
		memcpy(m.b, s[i].mac, 6);
		rl_mac_format(&m, mac);
		json_object_object_add(e, "section", json_object_new_string(s[i].section));
		json_object_object_add(e, "mac", json_object_new_string(mac));
		json_object_object_add(e, "period_start", json_object_new_int64(s[i].run.period_start));
		json_object_object_add(e, "warned", json_object_new_boolean(s[i].run.warned));
		json_object_object_add(e, "enforced", json_object_new_boolean(s[i].run.enforced));
		json_object_object_add(e, "allow_until", json_object_new_int64(s[i].run.allow_until));
		json_object_array_add(list, e);
	}
	json_object_object_add(root, "quotas", list);
	int rc = json_object_to_file_ext(tmp, root, JSON_C_TO_STRING_PLAIN);
	json_object_put(root);
	if (rc != 0)
		return -1;
	FILE *f = fopen(tmp, "r+");
	if (f) {
		fflush(f);
		fsync(fileno(f));
		fclose(f);
	}
	return rename(tmp, path) == 0 ? 0 : -1;
}
