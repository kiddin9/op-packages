/* /etc/config/routelink. */
#ifndef RL_CONFIG_H
#define RL_CONFIG_H

#include <stdbool.h>
#include <stddef.h>

#include "core/addr.h"
#include "core/probe.h"
#include "core/quota.h"
#include "core/schedule.h"
#include "core/store.h"
#include "sys/notify.h"

typedef struct {
	bool enabled;
	bool traffic;
	bool wifi; /* wireless sampling on the AP role */
	char data_dir[200];
	int commit_interval; /* seconds; 0 = automatic */
	int max_size_mb;
	int max_size_percent;
	int sample_interval;
	int live_interval;
	rl_retention ret;
	int signal_minute_days, signal_hour_days;
	int latency_minute_days, latency_hour_days, outage_days;

	/* latency probes (gateway role) */
	bool probe;
	bool probe_gateway; /* the WAN's next hop too */
	rl_ip probe_targets[RL_PROBE_MAX_TARGETS];
	int n_probe_targets;

	/* router-side speed test: "" = Cloudflare, else a LibreSpeed base URL */
	char speed_server[256];
	int speed_streams, speed_duration;

	/* DNS logging and destinations (gateway role), section dns */
	bool dns;
	int dns_keep_days;
	int dns_max_records;

	/* push messages: section notify (type notify_settings), option lang: auto | zh_cn | en */
	char notify_lang[16];
} rl_config;

/* An enabled `config limit` section (P4 plan §1.1). */
typedef struct {
	char section[64];
	rl_mac mac;
	uint32_t down_kbps, up_kbps; /* 0 = not limited */
	rl_schedule sched;
} rl_limit_rule;

/* An enabled `config quota` section. */
typedef struct {
	char section[64];
	rl_mac mac;
	rl_quota_period period;
	int reset_day;
	uint64_t limit; /* bytes; 0 = none */
	bool download_only;
	bool slow_down; /* action limit (else block) */
	uint32_t down_kbps, up_kbps;
} rl_quota_rule;

typedef struct {
	rl_limit_rule *limits;
	size_t n_limits;
	rl_quota_rule *quotas;
	size_t n_quotas;
	rl_channel *channels; /* every `config notify` section, enabled or not */
	size_t n_channels;
} rl_rules;

/* A `config device` section: flags the app and LuCI keep per MAC. */
typedef struct {
	rl_mac mac;
	bool trusted; /* known device (WF-3) */
	bool watch;   /* report when it comes and goes */
} rl_devflag;

void rl_config_defaults(rl_config *c);
/* Reads UCI over the defaults; values out of range are clamped. */
void rl_config_load(rl_config *c);
/* Every `config device` section with a valid mac (later sections win); *out is malloc'd or NULL. */
size_t rl_config_devices(rl_devflag **out);

/* Limits, quotas and push channels; free with rl_rules_free. */
void rl_config_rules(rl_rules *r);
void rl_rules_free(rl_rules *r);
/*
 * Push messages in Chinese? lang: auto (LuCI's language; when that is auto too, Chinese for the time zones
 * of mainland China, Hong Kong, Macau and Taiwan), zh_cn or en.
 */
bool rl_config_notify_zh(const char *lang, const char *zonename);

/* POSIX TZ string from system.@system[0].timezone (else /etc/TZ, else empty) and its zonename. */
void rl_config_timezone(char *tz, int tz_len, char *zonename, int zone_len);
/* system.ntp.enabled (true when unset). */
bool rl_config_ntp_enabled(void);

#endif
