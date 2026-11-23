/* Event log (device online/offline/new, daemon events), kept in RAM and appended to disk at commit. */
#ifndef RL_EVENTS_H
#define RL_EVENTS_H

#include <stddef.h>
#include <stdint.h>

#define RL_EVENTS_MAGIC 0x31454c52u /* "RLE1" */
#define RL_EV_NO_DEV 0xFFFF

typedef enum {
	RL_EV_DEVICE_NEW = 1,
	RL_EV_DEVICE_ONLINE,
	RL_EV_DEVICE_OFFLINE,
	RL_EV_DAEMON_START,
	RL_EV_TIME_JUMP,
	RL_EV_COMMIT_FAILED,
	RL_EV_DATA_RECOVERED,
	RL_EV_WIFI_CONNECT,    /* a = frequency (MHz) of the interface it joined */
	RL_EV_WIFI_DISCONNECT, /* a = frequency (MHz) of the interface it left */
	RL_EV_WAN_DOWN,        /* netifd: the WAN interface went down */
	RL_EV_WAN_UP,          /* netifd: the WAN interface came up */
	RL_EV_QUOTA_WARN,      /* a = bytes used; the device's quota reached 80 % */
	RL_EV_QUOTA_EXCEEDED,  /* a = bytes used; blocked or slowed down */
	RL_EV_QUOTA_RESET,     /* a new quota period began */
	RL_EV_LIMIT_APPLIED,   /* a = speed-limit rules now set up (debugging) */
	RL_EV_TYPE_END
} rl_event_type;

typedef struct {
	int64_t ts;
	uint16_t type;
	uint16_t dev; /* device index or RL_EV_NO_DEV */
	int64_t a;    /* type specific: seconds jumped, ... */
} rl_event;

typedef struct rl_events rl_events;

rl_events *rl_events_open(const char *path);
void rl_events_close(rl_events *e);
void rl_events_add(rl_events *e, const rl_event *ev);
int rl_events_commit(rl_events *e);
/* Drops events older than keep_days and the oldest beyond cap. */
int rl_events_compact(rl_events *e, int64_t now, int keep_days, size_t cap);
int rl_events_reset(rl_events *e);

/*
 * Newest first. type_mask: bit per rl_event_type (0 = all); dev: -1 = any.
 * Fills up to limit events after skipping offset; *total counts all matches.
 */
void rl_events_scan(const rl_events *e, int64_t start, int64_t end, uint32_t type_mask, int dev, size_t offset,
		    size_t limit, rl_event *out, size_t *n, size_t *total);

const char *rl_event_name(rl_event_type t);
/* Inverse of rl_event_name; 0 for unknown names. */
rl_event_type rl_event_parse(const char *name);

#endif
