#include <stdlib.h>

#include "t.h"

#include "core/events.h"

static char path[128];

static void fresh(void)
{
	char dir[] = "/tmp/rl-events-XXXXXX";
	if (!mkdtemp(dir))
		abort();
	snprintf(path, sizeof(path), "%s/events.bin", dir);
}

static rl_event ev(int64_t ts, rl_event_type type, uint16_t dev)
{
	return (rl_event){ .ts = ts, .type = (uint16_t)type, .dev = dev, .a = ts * 2 };
}

static void add(rl_events *e, rl_event x)
{
	rl_events_add(e, &x);
}

static void persist(void)
{
	fresh();
	rl_events *e = rl_events_open(path);
	add(e, ev(100, RL_EV_DEVICE_NEW, 1));
	add(e, ev(200, RL_EV_DEVICE_ONLINE, 1));
	T_EQ_I64(rl_events_commit(e), 0);
	add(e, ev(300, RL_EV_DEVICE_OFFLINE, 1)); /* never committed */
	rl_events_close(e);
	e = rl_events_open(path);
	rl_event out[8];
	size_t n, total;
	rl_events_scan(e, 0, 1000, 0, -1, 0, 8, out, &n, &total);
	T_EQ_U64(n, 2);
	T_EQ_I64(out[0].ts, 200); /* newest first */
	T_EQ_I64(out[0].a, 400);
	rl_events_close(e);
}

static void filters_and_pages(void)
{
	fresh();
	rl_events *e = rl_events_open(path);
	for (int i = 0; i < 10; i++)
		add(e, ev(100 + i, i % 2 ? RL_EV_DEVICE_ONLINE : RL_EV_DEVICE_OFFLINE, (uint16_t)(i % 3)));
	add(e, ev(500, RL_EV_DAEMON_START, RL_EV_NO_DEV));
	rl_event out[16];
	size_t n, total;
	rl_events_scan(e, 0, 1000, 1u << RL_EV_DEVICE_ONLINE, -1, 0, 16, out, &n, &total);
	T_EQ_U64(total, 5);
	rl_events_scan(e, 0, 1000, 0, 0, 0, 16, out, &n, &total);
	T_EQ_U64(total, 4); /* i = 0, 3, 6, 9 */
	rl_events_scan(e, 0, 1000, 0, -1, 2, 3, out, &n, &total);
	T_EQ_U64(total, 11);
	T_EQ_U64(n, 3);
	T_EQ_I64(out[0].ts, 108);
	rl_events_scan(e, 0, 105, 0, -1, 0, 16, out, &n, &total);
	T_EQ_U64(total, 5);
	rl_events_close(e);
}

static void compaction(void)
{
	fresh();
	rl_events *e = rl_events_open(path);
	for (int i = 0; i < 20; i++)
		add(e, ev(86400LL * i, RL_EV_DEVICE_ONLINE, 1));
	rl_events_commit(e);
	T_EQ_I64(rl_events_compact(e, 86400LL * 20, 10, 1000), 0); /* keeps days 10..19 */
	rl_event out[32];
	size_t n, total;
	rl_events_scan(e, 0, INT64_MAX, 0, -1, 0, 32, out, &n, &total);
	T_EQ_U64(total, 10);
	rl_events_compact(e, 86400LL * 20, 100, 4); /* cap */
	rl_events_close(e);
	e = rl_events_open(path);
	rl_events_scan(e, 0, INT64_MAX, 0, -1, 0, 32, out, &n, &total);
	T_EQ_U64(total, 4);
	T_EQ_I64(out[3].ts, 86400LL * 16);
	T_EQ_I64(rl_events_reset(e), 0);
	rl_events_scan(e, 0, INT64_MAX, 0, -1, 0, 32, out, &n, &total);
	T_EQ_U64(total, 0);
	rl_events_close(e);
}

static void names(void)
{
	for (int t = 1; t < RL_EV_TYPE_END; t++)
		T_EQ_I64(rl_event_parse(rl_event_name((rl_event_type)t)), t);
	T_EQ_I64(rl_event_parse("nope"), 0);
	T_EQ_STR(rl_event_name(RL_EV_DEVICE_NEW), "device_new");
	/* stored as numbers: new types only go at the end */
	T_EQ_I64(RL_EV_WIFI_CONNECT, 8);
	T_EQ_STR(rl_event_name(RL_EV_WIFI_DISCONNECT), "wifi_disconnect");
}

int main(void)
{
	T_RUN(persist);
	T_RUN(filters_and_pages);
	T_RUN(compaction);
	T_RUN(names);
	T_DONE();
}
