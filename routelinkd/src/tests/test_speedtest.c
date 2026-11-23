#include <stdlib.h>
#include <unistd.h>

#include "t.h"

#include "core/speedtest.h"

static void test_target(void)
{
	rl_speed_target t;
	T_ASSERT(rl_speed_target_of("", &t));
	T_EQ_STR(t.down, "http://speed.cloudflare.com/__down?bytes=25000000");
	T_EQ_STR(t.up, "http://speed.cloudflare.com/__up");
	T_EQ_STR(t.host, "speed.cloudflare.com");
	T_EQ_I64(t.port, 80);

	T_ASSERT(rl_speed_target_of("https://ls.example/backend", &t));
	T_EQ_STR(t.down, "https://ls.example/backend/garbage.php?ckSize=100");
	T_EQ_STR(t.up, "https://ls.example/backend/empty.php");
	T_EQ_STR(t.host, "ls.example");
	T_EQ_I64(t.port, 443);

	T_ASSERT(rl_speed_target_of("http://[fd41::10]:8080", &t));
	T_EQ_STR(t.down, "http://[fd41::10]:8080/garbage.php?ckSize=100");
	T_EQ_STR(t.host, "fd41::10");
	T_EQ_I64(t.port, 8080);

	T_ASSERT(rl_speed_target_of("HTTP://172.41.0.10:8080/speed/?x=1", &t));
	T_EQ_STR(t.up, "HTTP://172.41.0.10:8080/speed/empty.php");
	T_EQ_STR(t.host, "172.41.0.10");
	T_EQ_I64(t.port, 8080);

	const char *bad[] = { "ftp://x/", "http://", "speed.example", "http://a b/", "http://u@host/", "http://h:0/",
			      "http://h:99999/", "http://[::1/", "http://h:/", "https://h/x\"y" };
	for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++)
		if (rl_speed_target_of(bad[i], &t))
			T_FAIL("accepted %s", bad[i]);
}

static void test_stats(void)
{
	double ms[] = { 12, 10, 14, 11 }, median, jitter;
	rl_speed_stats(ms, 4, &median, &jitter);
	T_EQ_I64((int64_t)(median * 10), 115);
	T_EQ_I64((int64_t)(jitter * 1000), 3000); /* (2 + 4 + 3) / 3 */
	rl_speed_stats(ms, 1, &median, &jitter);
	T_EQ_I64((int64_t)median, 12);
	T_EQ_I64((int64_t)jitter, 0);
	double odd[] = { 5, 1, 3 };
	rl_speed_stats(odd, 3, &median, &jitter);
	T_EQ_I64((int64_t)median, 3);
}

/* The first second does not count; a counter that went backwards adds nothing. */
static void test_rate(void)
{
	int64_t t[] = { 0, 500, 1000, 2000, 3000 };
	uint64_t b[] = { 0, 9999, 10000, 135000, 260000 };
	T_EQ_I64(rl_speed_rate(t, b, 5, 1000), 1000000); /* 250000 bytes in 2 s */
	T_EQ_I64(rl_speed_rate(t, b, 5, 0), 693333);     /* everything over 3 s */
	uint64_t reset[] = { 0, 10, 10000, 500, 125500 };
	T_EQ_I64(rl_speed_rate(t, reset, 5, 1000), 500000);
	T_EQ_I64(rl_speed_rate(t, b, 1, 1000), -1);
	T_EQ_I64(rl_speed_rate(t, b, 2, 1000), 159984); /* shorter than the warm-up: all of it */
	int64_t same[] = { 0, 0 };
	T_EQ_I64(rl_speed_rate(same, b, 2, 0), -1);
}

static void test_lines(void)
{
	rl_speed_result r;
	rl_speed_phase phase = RL_SPEED_LATENCY;
	double progress = 0;
	rl_speed_result_init(&r, 3, 1790000000, "");
	T_ASSERT(r.latency_ms < 0 && r.down_bps < 0 && r.up_bps < 0 && !r.error[0]);
	T_ASSERT(rl_speed_line("P download 0.25", &r, &phase, &progress));
	T_EQ_I64(phase, RL_SPEED_DOWNLOAD);
	T_EQ_I64((int64_t)(progress * 100), 25);
	T_ASSERT(rl_speed_line("P upload 7", &r, &phase, &progress));
	T_EQ_I64((int64_t)progress, 1);
	T_ASSERT(!rl_speed_line("P done 1", &r, &phase, &progress));
	T_ASSERT(rl_speed_line("L 12.345 1.5", &r, &phase, &progress));
	T_EQ_I64((int64_t)(r.latency_ms * 1000), 12345);
	T_ASSERT(rl_speed_line("D 450000000", &r, &phase, &progress));
	T_ASSERT(rl_speed_line("U 51000000", &r, &phase, &progress));
	T_EQ_I64(r.down_bps, 450000000);
	T_EQ_I64(r.up_bps, 51000000);
	T_ASSERT(!rl_speed_line("D -5", &r, &phase, &progress));
	T_ASSERT(!rl_speed_line("X 1", &r, &phase, &progress));
	T_ASSERT(!rl_speed_line("E", &r, &phase, &progress));
	T_ASSERT(rl_speed_line("E cannot resolve speed.example", &r, &phase, &progress));
	T_EQ_STR(r.error, "cannot resolve speed.example");
	T_EQ_I64(phase, RL_SPEED_FAILED);
	T_EQ_STR(rl_speed_phase_name(RL_SPEED_DONE), "done");
}

/* The latest RL_SPEED_KEEP runs survive a save and load; ids keep counting. */
static void test_log(void)
{
	char dir[64], path[128];
	snprintf(dir, sizeof(dir), "/tmp/rl-speed-XXXXXX");
	if (!mkdtemp(dir))
		abort();
	snprintf(path, sizeof(path), "%s/speedtest.json", dir);
	rl_speed_log l;
	T_EQ_I64(rl_speed_log_load(&l, path), 0);
	T_EQ_I64(l.n, 0);
	for (int i = 1; i <= RL_SPEED_KEEP + 5; i++) {
		rl_speed_result r;
		rl_speed_result_init(&r, i, 1790000000 + i, i % 2 ? "" : "https://ls.example/");
		if (i % 3) {
			r.latency_ms = 10.25;
			r.jitter_ms = 0.5;
			r.down_bps = 1000000LL * i;
			r.up_bps = 2000;
		} else {
			snprintf(r.error, sizeof(r.error), "download failed");
		}
		rl_speed_log_add(&l, &r);
	}
	T_EQ_I64(l.n, RL_SPEED_KEEP);
	T_EQ_I64(l.items[0].id, 6);
	T_EQ_I64(l.last_id, RL_SPEED_KEEP + 5);
	T_EQ_I64(rl_speed_log_save(&l, path), 0);
	rl_speed_log_free(&l);

	T_EQ_I64(rl_speed_log_load(&l, path), 0);
	T_EQ_I64(l.n, RL_SPEED_KEEP);
	T_EQ_I64(l.last_id, RL_SPEED_KEEP + 5);
	const rl_speed_result *r = rl_speed_log_find(&l, 100);
	T_ASSERT(r != NULL);
	T_EQ_STR(r->server, "https://ls.example/");
	T_EQ_I64(r->down_bps, 100000000);
	T_EQ_I64((int64_t)(r->latency_ms * 100), 1025);
	r = rl_speed_log_find(&l, 99);
	T_ASSERT(r && r->latency_ms < 0 && r->down_bps < 0);
	T_EQ_STR(r->error, "download failed");
	T_ASSERT(rl_speed_log_find(&l, 5) == NULL);
	rl_speed_log_free(&l);

	FILE *f = fopen(path, "w");
	fputs("{\"version\":2}", f);
	fclose(f);
	T_EQ_I64(rl_speed_log_load(&l, path), -1);
	T_EQ_I64(l.n, 0);
	unlink(path);
	rmdir(dir);
}

int main(void)
{
	T_RUN(test_target);
	T_RUN(test_stats);
	T_RUN(test_rate);
	T_RUN(test_lines);
	T_RUN(test_log);
	T_DONE();
}
