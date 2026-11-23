#define _GNU_SOURCE
#include <endian.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "core/events.h"
#include "core/util.h"

#define HDR 16
#define REC 16

struct rl_events {
	char path[256];
	rl_event *items;
	size_t n, cap;
	size_t committed; /* items[0..committed) are on disk */
};

static const char *const NAMES[RL_EV_TYPE_END] = {
	[RL_EV_DEVICE_NEW] = "device_new",       [RL_EV_DEVICE_ONLINE] = "device_online",
	[RL_EV_DEVICE_OFFLINE] = "device_offline", [RL_EV_DAEMON_START] = "daemon_start",
	[RL_EV_TIME_JUMP] = "time_jump",         [RL_EV_COMMIT_FAILED] = "commit_failed",
	[RL_EV_DATA_RECOVERED] = "data_recovered", [RL_EV_WIFI_CONNECT] = "wifi_connect",
	[RL_EV_WIFI_DISCONNECT] = "wifi_disconnect", [RL_EV_WAN_DOWN] = "wan_down",
	[RL_EV_WAN_UP] = "wan_up",
	[RL_EV_QUOTA_WARN] = "quota_warn",       [RL_EV_QUOTA_EXCEEDED] = "quota_exceeded",
	[RL_EV_QUOTA_RESET] = "quota_reset",     [RL_EV_LIMIT_APPLIED] = "limit_applied",
};

const char *rl_event_name(rl_event_type t)
{
	return t > 0 && t < RL_EV_TYPE_END ? NAMES[t] : "unknown";
}

rl_event_type rl_event_parse(const char *name)
{
	for (int t = 1; t < RL_EV_TYPE_END; t++)
		if (name && strcmp(NAMES[t], name) == 0)
			return (rl_event_type)t;
	return 0;
}

static void encode(const rl_event *ev, uint8_t out[REC])
{
	uint32_t ts = htole32((uint32_t)ev->ts);
	uint16_t type = htole16(ev->type), dev = htole16(ev->dev);
	uint64_t a = htole64((uint64_t)ev->a);
	memcpy(out, &ts, 4);
	memcpy(out + 4, &type, 2);
	memcpy(out + 6, &dev, 2);
	memcpy(out + 8, &a, 8);
}

static void decode(const uint8_t in[REC], rl_event *ev)
{
	uint32_t ts;
	uint16_t type, dev;
	uint64_t a;
	memcpy(&ts, in, 4);
	memcpy(&type, in + 4, 2);
	memcpy(&dev, in + 6, 2);
	memcpy(&a, in + 8, 8);
	ev->ts = le32toh(ts);
	ev->type = le16toh(type);
	ev->dev = le16toh(dev);
	ev->a = (int64_t)le64toh(a);
}

static void header(uint8_t out[HDR])
{
	uint32_t magic = htole32(RL_EVENTS_MAGIC);
	uint16_t version = htole16(1), size = htole16(REC);
	memset(out, 0, HDR);
	memcpy(out, &magic, 4);
	memcpy(out + 4, &version, 2);
	memcpy(out + 6, &size, 2);
}

static int write_file(const char *path, const rl_event *items, size_t n)
{
	char tmp[300];
	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	FILE *f = fopen(tmp, "w");
	if (!f)
		return -1;
	uint8_t buf[REC];
	header(buf);
	bool ok = fwrite(buf, HDR, 1, f) == 1;
	for (size_t i = 0; ok && i < n; i++) {
		encode(&items[i], buf);
		ok = fwrite(buf, REC, 1, f) == 1;
	}
	ok = ok && fflush(f) == 0 && fsync(fileno(f)) == 0;
	fclose(f);
	if (ok && rename(tmp, path) == 0)
		return 0;
	unlink(tmp);
	return -1;
}

rl_events *rl_events_open(const char *path)
{
	rl_events *e = calloc(1, sizeof(*e));
	if (!e)
		abort();
	snprintf(e->path, sizeof(e->path), "%s", path);
	FILE *f = fopen(path, "r");
	if (f) {
		uint8_t hdr[HDR], expect[HDR], buf[REC];
		header(expect);
		bool ok = fread(hdr, HDR, 1, f) == 1 && memcmp(hdr, expect, 8) == 0;
		while (ok && fread(buf, REC, 1, f) == 1) {
			e->items = rl_grow(e->items, &e->cap, e->n + 1, sizeof(rl_event));
			decode(buf, &e->items[e->n++]);
		}
		fclose(f);
		if (!ok) {
			char bad[300];
			snprintf(bad, sizeof(bad), "%s.bad", path);
			rename(path, bad);
			e->n = 0;
		}
	}
	if (e->n == 0 && write_file(path, NULL, 0) != 0) {
		rl_events_close(e);
		return NULL;
	}
	e->committed = e->n;
	return e;
}

void rl_events_close(rl_events *e)
{
	if (!e)
		return;
	free(e->items);
	free(e);
}

void rl_events_add(rl_events *e, const rl_event *ev)
{
	e->items = rl_grow(e->items, &e->cap, e->n + 1, sizeof(rl_event));
	e->items[e->n++] = *ev;
}

int rl_events_commit(rl_events *e)
{
	if (e->committed == e->n)
		return 0;
	int fd = open(e->path, O_WRONLY | O_APPEND | O_CLOEXEC);
	if (fd < 0)
		return -1;
	struct stat st;
	bool ok = fstat(fd, &st) == 0;
	uint8_t buf[REC];
	for (size_t i = e->committed; ok && i < e->n; i++) {
		encode(&e->items[i], buf);
		ok = write(fd, buf, REC) == REC;
	}
	ok = ok && fsync(fd) == 0;
	if (!ok && ftruncate(fd, st.st_size) != 0) {
		/* a torn tail is rejected (and the file replaced) on the next open */
	}
	close(fd);
	if (!ok)
		return -1;
	e->committed = e->n;
	return 0;
}

int rl_events_compact(rl_events *e, int64_t now, int keep_days, size_t cap)
{
	int64_t cutoff = now - (int64_t)keep_days * 86400;
	size_t drop = 0;
	while (drop < e->n && e->items[drop].ts < cutoff)
		drop++;
	if (e->n - drop > cap)
		drop = e->n - cap;
	if (!drop)
		return 0;
	memmove(e->items, e->items + drop, (e->n - drop) * sizeof(rl_event));
	e->n -= drop;
	e->committed = e->committed > drop ? e->committed - drop : 0;
	/* rewrite only what was already on disk; pending events are appended by the next commit */
	if (write_file(e->path, e->items, e->committed) != 0)
		return -1;
	return 0;
}

int rl_events_reset(rl_events *e)
{
	e->n = e->committed = 0;
	return write_file(e->path, NULL, 0);
}

void rl_events_scan(const rl_events *e, int64_t start, int64_t end, uint32_t type_mask, int dev, size_t offset,
		    size_t limit, rl_event *out, size_t *n, size_t *total)
{
	*n = *total = 0;
	for (size_t i = e->n; i-- > 0;) {
		const rl_event *ev = &e->items[i];
		if (ev->ts < start || ev->ts >= end)
			continue;
		if (type_mask && !(type_mask >> ev->type & 1))
			continue;
		if (dev >= 0 && ev->dev != dev)
			continue;
		if (*total >= offset && *n < limit)
			out[(*n)++] = *ev;
		(*total)++;
	}
}
