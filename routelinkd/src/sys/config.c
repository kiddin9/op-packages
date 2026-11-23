#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <syslog.h>
#include <uci.h>

#include "core/util.h"
#include "sys/config.h"

void rl_config_defaults(rl_config *c)
{
	memset(c, 0, sizeof(*c));
	c->enabled = true;
	c->traffic = true;
	c->wifi = true;
	snprintf(c->data_dir, sizeof(c->data_dir), "/etc/routelink");
	c->commit_interval = 0;
	c->max_size_mb = 32;
	c->max_size_percent = 10;
	c->sample_interval = 30;
	c->live_interval = 2;
	c->ret = (rl_retention){ .minute_hours = 48, .hour_days = 90, .day_days = 730, .event_days = 90 };
	c->signal_minute_days = 7;
	c->signal_hour_days = 30;
	c->latency_minute_days = 7;
	c->latency_hour_days = 90;
	c->outage_days = 365;
	c->probe = true;
	c->probe_gateway = true;
	/* used when the config has no probe section (kept from 0.1.0) */
	static const char *const targets[] = { "223.5.5.5", "119.29.29.29", "1.1.1.1" };
	for (size_t i = 0; i < RL_ARRAY_SIZE(targets); i++)
		rl_ip_parse(targets[i], &c->probe_targets[c->n_probe_targets++]);
	c->speed_streams = 4;
	c->speed_duration = 10;
	c->dns = false;
	c->dns_keep_days = 7;
	c->dns_max_records = 100000;
	snprintf(c->notify_lang, sizeof(c->notify_lang), "auto");
}

static int clamp(int v, int lo, int hi)
{
	return v < lo ? lo : v > hi ? hi : v;
}

static int get_int(struct uci_context *ctx, struct uci_section *s, const char *name, int def)
{
	const char *v = s ? uci_lookup_option_string(ctx, s, name) : NULL;
	if (!v || !*v)
		return def;
	char *end;
	long n = strtol(v, &end, 10);
	return *end ? def : (int)n;
}

static bool get_bool(struct uci_context *ctx, struct uci_section *s, const char *name, bool def)
{
	const char *v = s ? uci_lookup_option_string(ctx, s, name) : NULL;
	if (!v)
		return def;
	return !strcmp(v, "1") || !strcmp(v, "on") || !strcmp(v, "true") || !strcmp(v, "yes") || !strcmp(v, "enabled");
}

static void add_target(rl_config *c, const char *v)
{
	rl_ip ip;
	if (!rl_ip_parse(v, &ip)) {
		/* names would need a blocking lookup in the event loop */
		syslog(LOG_WARNING, "probe target %s ignored: only IP addresses are probed", v);
		return;
	}
	for (int i = 0; i < c->n_probe_targets; i++)
		if (rl_ip_eq(&c->probe_targets[i], &ip))
			return;
	if (c->n_probe_targets < RL_PROBE_MAX_TARGETS)
		c->probe_targets[c->n_probe_targets++] = ip;
	else
		syslog(LOG_WARNING, "probe target %s ignored: at most %d targets", v, RL_PROBE_MAX_TARGETS);
}

/* config probe 'probe': list target (or a space-separated option) */
static void load_targets(rl_config *c, struct uci_context *ctx, struct uci_section *s)
{
	struct uci_option *o = uci_lookup_option(ctx, s, "target");
	c->n_probe_targets = 0;
	if (!o)
		return;
	if (o->type == UCI_TYPE_LIST) {
		struct uci_element *e;
		uci_foreach_element(&o->v.list, e)
			add_target(c, e->name);
	} else {
		char buf[512];
		snprintf(buf, sizeof(buf), "%s", o->v.string);
		for (char *save, *tok = strtok_r(buf, " \t", &save); tok; tok = strtok_r(NULL, " \t", &save))
			add_target(c, tok);
	}
}

void rl_config_load(rl_config *c)
{
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (!ctx)
		return;
	if (uci_load(ctx, "routelink", &pkg) == UCI_OK && pkg) {
		struct uci_section *m = uci_lookup_section(ctx, pkg, "main");
		struct uci_section *r = uci_lookup_section(ctx, pkg, "retention");
		c->enabled = get_bool(ctx, m, "enabled", c->enabled);
		c->traffic = get_bool(ctx, m, "traffic", c->traffic);
		c->wifi = get_bool(ctx, m, "wifi", c->wifi);
		const char *dir = m ? uci_lookup_option_string(ctx, m, "data_dir") : NULL;
		if (dir && dir[0] == '/') {
			snprintf(c->data_dir, sizeof(c->data_dir), "%s", dir);
			size_t len = strlen(c->data_dir);
			while (len > 1 && c->data_dir[len - 1] == '/')
				c->data_dir[--len] = '\0';
		}
		c->commit_interval = clamp(get_int(ctx, m, "commit_interval", c->commit_interval), 0, 86400);
		if (c->commit_interval && c->commit_interval < 60)
			c->commit_interval = 60;
		c->max_size_mb = clamp(get_int(ctx, m, "max_size_mb", c->max_size_mb), 1, 4096);
		c->max_size_percent = clamp(get_int(ctx, m, "max_size_percent", c->max_size_percent), 1, 90);
		c->sample_interval = clamp(get_int(ctx, m, "sample_interval", c->sample_interval), 5, 300);
		c->live_interval = clamp(get_int(ctx, m, "live_interval", c->live_interval), 1, 10);
		/* restart recovery rebuilds a tier from the next finer one: keep enough of each */
		c->ret.minute_hours = clamp(get_int(ctx, r, "minute_hours", c->ret.minute_hours), 2, 24 * 14);
		c->ret.hour_days = clamp(get_int(ctx, r, "hour_days", c->ret.hour_days), 2, 3660);
		c->ret.day_days = clamp(get_int(ctx, r, "day_days", c->ret.day_days), 62, 36600);
		c->ret.event_days = clamp(get_int(ctx, r, "event_days", c->ret.event_days), 1, 3660);
		/* signal hours are rebuilt from minutes after a restart: a day of minutes is plenty */
		c->signal_minute_days = clamp(get_int(ctx, r, "signal_minute_days", c->signal_minute_days), 1, 90);
		c->signal_hour_days = clamp(get_int(ctx, r, "signal_hour_days", c->signal_hour_days), 1, 3660);
		/* the open latency hour is rebuilt from its minutes after a restart: a day of minutes is plenty */
		c->latency_minute_days = clamp(get_int(ctx, r, "latency_minute_days", c->latency_minute_days), 1, 90);
		c->latency_hour_days = clamp(get_int(ctx, r, "latency_hour_days", c->latency_hour_days), 1, 3660);
		c->outage_days = clamp(get_int(ctx, r, "outage_days", c->outage_days), 1, 3660);

		struct uci_section *p = uci_lookup_section(ctx, pkg, "probe");
		if (p) {
			c->probe = get_bool(ctx, p, "enabled", c->probe);
			c->probe_gateway = get_bool(ctx, p, "gateway", c->probe_gateway);
			load_targets(c, ctx, p);
		}
		struct uci_section *st = uci_lookup_section(ctx, pkg, "speedtest");
		const char *server = st ? uci_lookup_option_string(ctx, st, "server") : NULL;
		if (server) {
			while (*server == ' ')
				server++;
			snprintf(c->speed_server, sizeof(c->speed_server), "%s", server);
			c->speed_server[strcspn(c->speed_server, " \t\r\n")] = '\0';
		}
		c->speed_streams = clamp(get_int(ctx, st, "streams", c->speed_streams), 1, 8);
		c->speed_duration = clamp(get_int(ctx, st, "duration", c->speed_duration), 5, 30);

		struct uci_section *dns = uci_lookup_section(ctx, pkg, "dns");
		c->dns = get_bool(ctx, dns, "enabled", c->dns);
		c->dns_keep_days = clamp(get_int(ctx, dns, "keep_days", c->dns_keep_days), 1, 365);
		c->dns_max_records = clamp(get_int(ctx, dns, "max_records", c->dns_max_records), 1000, 1000000);
		struct uci_section *ns = uci_lookup_section(ctx, pkg, "notify");
		const char *lang = ns ? uci_lookup_option_string(ctx, ns, "lang") : NULL;
		if (lang && *lang)
			snprintf(c->notify_lang, sizeof(c->notify_lang), "%s", lang);
	}
	uci_free_context(ctx);
}

/* ---- limits, quotas, push channels ---- */

static uint32_t get_kbps(struct uci_context *ctx, struct uci_section *s, const char *name)
{
	int v = get_int(ctx, s, name, 0);
	return v > 0 ? (uint32_t)clamp(v, 8, 10000000) : 0; /* 8 kbit/s .. 10 Gbit/s */
}

static void get_str(struct uci_context *ctx, struct uci_section *s, const char *name, char *out, size_t size)
{
	const char *v = uci_lookup_option_string(ctx, s, name);
	snprintf(out, size, "%s", v ? v : "");
}

/* list weekdays 'mon' … (or a space-separated option); none = every day */
static uint8_t get_weekdays(struct uci_context *ctx, struct uci_section *s)
{
	struct uci_option *o = uci_lookup_option(ctx, s, "weekdays");
	uint8_t days = 0;
	if (!o)
		return 0;
	if (o->type == UCI_TYPE_LIST) {
		struct uci_element *e;
		uci_foreach_element(&o->v.list, e) {
			int d = rl_weekday_parse(e->name);
			if (d)
				days |= (uint8_t)(1u << (d - 1));
		}
	} else {
		char buf[128];
		snprintf(buf, sizeof(buf), "%s", o->v.string);
		for (char *save, *tok = strtok_r(buf, " \t", &save); tok; tok = strtok_r(NULL, " \t", &save)) {
			int d = rl_weekday_parse(tok);
			if (d)
				days |= (uint8_t)(1u << (d - 1));
		}
	}
	return days;
}

static unsigned get_events(struct uci_context *ctx, struct uci_section *s)
{
	struct uci_option *o = uci_lookup_option(ctx, s, "events");
	unsigned events = 0;
	if (!o)
		return 0;
	if (o->type == UCI_TYPE_LIST) {
		struct uci_element *e;
		uci_foreach_element(&o->v.list, e)
			events |= rl_notify_sub_parse(e->name);
	} else {
		char buf[128];
		snprintf(buf, sizeof(buf), "%s", o->v.string);
		for (char *save, *tok = strtok_r(buf, " \t", &save); tok; tok = strtok_r(NULL, " \t", &save))
			events |= rl_notify_sub_parse(tok);
	}
	return events;
}

static bool add_limit(rl_rules *r, size_t *cap, struct uci_context *ctx, struct uci_section *s, const rl_mac *mac)
{
	rl_limit_rule l = { .mac = *mac };
	snprintf(l.section, sizeof(l.section), "%s", s->e.name);
	l.down_kbps = get_kbps(ctx, s, "download");
	l.up_kbps = get_kbps(ctx, s, "upload");
	if (!l.down_kbps && !l.up_kbps)
		return false;
	l.sched.days = get_weekdays(ctx, s);
	int start = rl_time_parse(uci_lookup_option_string(ctx, s, "start_time"));
	int stop = rl_time_parse(uci_lookup_option_string(ctx, s, "stop_time"));
	l.sched.start = (int16_t)(start >= 0 && stop >= 0 && start != stop ? start : -1);
	l.sched.stop = (int16_t)(l.sched.start >= 0 ? stop : -1);
	r->limits = rl_grow(r->limits, cap, r->n_limits + 1, sizeof(rl_limit_rule));
	r->limits[r->n_limits++] = l;
	return true;
}

static bool add_quota(rl_rules *r, size_t *cap, struct uci_context *ctx, struct uci_section *s, const rl_mac *mac)
{
	rl_quota_rule q = { .mac = *mac };
	snprintf(q.section, sizeof(q.section), "%s", s->e.name);
	int period = rl_quota_period_parse(uci_lookup_option_string(ctx, s, "period"));
	q.period = period < 0 ? RL_QUOTA_MONTH : (rl_quota_period)period;
	q.reset_day = get_int(ctx, s, "reset_day", 1);
	q.reset_day = clamp(q.reset_day, 1, q.period == RL_QUOTA_WEEK ? 7 : 28);
	int mb = get_int(ctx, s, "limit_mb", 0);
	q.limit = mb > 0 ? (uint64_t)mb << 20 : 0;
	const char *dir = uci_lookup_option_string(ctx, s, "direction");
	q.download_only = dir && !strcmp(dir, "download");
	const char *action = uci_lookup_option_string(ctx, s, "action");
	q.slow_down = action && !strcmp(action, "limit");
	q.down_kbps = get_kbps(ctx, s, "limit_download");
	q.up_kbps = get_kbps(ctx, s, "limit_upload");
	if (q.slow_down && !q.down_kbps && !q.up_kbps)
		q.slow_down = false; /* nothing to slow down to: block instead */
	r->quotas = rl_grow(r->quotas, cap, r->n_quotas + 1, sizeof(rl_quota_rule));
	r->quotas[r->n_quotas++] = q;
	return true;
}

static void add_channel(rl_rules *r, size_t *cap, struct uci_context *ctx, struct uci_section *s)
{
	rl_channel c = { 0 };
	int type = rl_notify_type_parse(uci_lookup_option_string(ctx, s, "type"));
	if (type < 0) {
		syslog(LOG_WARNING, "push channel %s ignored: unknown type", s->e.name);
		return;
	}
	c.type = (rl_notify_type)type;
	snprintf(c.section, sizeof(c.section), "%s", s->e.name);
	c.enabled = get_bool(ctx, s, "enabled", true);
	get_str(ctx, s, "name", c.name, sizeof(c.name));
	get_str(ctx, s, "url", c.url, sizeof(c.url));
	get_str(ctx, s, "template", c.tpl, sizeof(c.tpl));
	get_str(ctx, s, "token", c.token, sizeof(c.token));
	get_str(ctx, s, "chat_id", c.chat_id, sizeof(c.chat_id));
	get_str(ctx, s, "secret", c.secret, sizeof(c.secret));
	c.events = get_events(ctx, s);
	r->channels = rl_grow(r->channels, cap, r->n_channels + 1, sizeof(rl_channel));
	r->channels[r->n_channels++] = c;
}

void rl_config_rules(rl_rules *r)
{
	size_t cap_l = 0, cap_q = 0, cap_c = 0;
	memset(r, 0, sizeof(*r));
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (!ctx)
		return;
	if (uci_load(ctx, "routelink", &pkg) == UCI_OK && pkg) {
		struct uci_element *e;
		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			rl_mac mac;
			bool limit = !strcmp(s->type, "limit"), quota = !strcmp(s->type, "quota");
			if (!strcmp(s->type, "notify")) {
				add_channel(r, &cap_c, ctx, s);
				continue;
			}
			if ((!limit && !quota) || !get_bool(ctx, s, "enabled", true))
				continue;
			if (!rl_mac_parse(uci_lookup_option_string(ctx, s, "mac"), &mac)) {
				syslog(LOG_WARNING, "%s %s ignored: no valid mac", s->type, s->e.name);
				continue;
			}
			if (limit)
				add_limit(r, &cap_l, ctx, s, &mac);
			else
				add_quota(r, &cap_q, ctx, s, &mac);
		}
	}
	uci_free_context(ctx);
}

void rl_rules_free(rl_rules *r)
{
	free(r->limits);
	free(r->quotas);
	free(r->channels);
	memset(r, 0, sizeof(*r));
}

static bool chinese_zone(const char *zonename)
{
	static const char *const zones[] = { "Asia/Shanghai", "Asia/Hong_Kong", "Asia/Macau", "Asia/Taipei",
					     "Asia/Chongqing", "Asia/Harbin", "Asia/Urumqi", NULL };
	for (int i = 0; zonename && zones[i]; i++)
		if (!strcmp(zonename, zones[i]))
			return true;
	return false;
}

bool rl_config_notify_zh(const char *lang, const char *zonename)
{
	if (lang && !strncasecmp(lang, "zh", 2))
		return true;
	if (lang && *lang && strcmp(lang, "auto"))
		return false;
	/* follow LuCI's language */
	char luci[32] = "";
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (ctx && uci_load(ctx, "luci", &pkg) == UCI_OK && pkg) {
		struct uci_section *m = uci_lookup_section(ctx, pkg, "main");
		const char *v = m ? uci_lookup_option_string(ctx, m, "lang") : NULL;
		if (v)
			snprintf(luci, sizeof(luci), "%s", v);
	}
	if (ctx)
		uci_free_context(ctx);
	if (luci[0] && strcmp(luci, "auto"))
		return !strncasecmp(luci, "zh", 2);
	return chinese_zone(zonename);
}

size_t rl_config_devices(rl_devflag **out)
{
	size_t n = 0, cap = 0;
	*out = NULL;
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (!ctx)
		return 0;
	if (uci_load(ctx, "routelink", &pkg) == UCI_OK && pkg) {
		struct uci_element *e;
		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			rl_mac mac;
			if (strcmp(s->type, "device") || !rl_mac_parse(uci_lookup_option_string(ctx, s, "mac"), &mac))
				continue;
			rl_devflag *f = NULL;
			for (size_t i = 0; i < n && !f; i++)
				if (rl_mac_eq(&(*out)[i].mac, &mac))
					f = &(*out)[i];
			if (!f) {
				*out = rl_grow(*out, &cap, n + 1, sizeof(rl_devflag));
				f = &(*out)[n++];
				memset(f, 0, sizeof(*f));
				f->mac = mac;
			}
			f->trusted = get_bool(ctx, s, "trusted", false);
			f->watch = get_bool(ctx, s, "watch", false);
		}
	}
	uci_free_context(ctx);
	return n;
}

void rl_config_timezone(char *tz, int tz_len, char *zonename, int zone_len)
{
	tz[0] = zonename[0] = '\0';
	/* UCI first: after a time zone change this reload may run before /etc/init.d/system rewrites /etc/TZ */
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (ctx && uci_load(ctx, "system", &pkg) == UCI_OK && pkg) {
		struct uci_element *e;
		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			if (strcmp(s->type, "system"))
				continue;
			const char *z = uci_lookup_option_string(ctx, s, "zonename");
			const char *t = uci_lookup_option_string(ctx, s, "timezone");
			if (z)
				snprintf(zonename, zone_len, "%s", z);
			if (t)
				snprintf(tz, tz_len, "%s", t);
			break;
		}
	}
	if (ctx)
		uci_free_context(ctx);
	if (tz[0])
		return;
	FILE *f = fopen("/etc/TZ", "r");
	if (f) {
		if (fgets(tz, tz_len, f))
			tz[strcspn(tz, "\r\n")] = '\0';
		fclose(f);
	}
}

bool rl_config_ntp_enabled(void)
{
	bool enabled = true;
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (!ctx)
		return true;
	if (uci_load(ctx, "system", &pkg) == UCI_OK && pkg) {
		struct uci_section *s = uci_lookup_section(ctx, pkg, "ntp");
		const char *v = s ? uci_lookup_option_string(ctx, s, "enabled") : NULL;
		if (v && !strcmp(v, "0"))
			enabled = false;
	}
	uci_free_context(ctx);
	return enabled;
}
