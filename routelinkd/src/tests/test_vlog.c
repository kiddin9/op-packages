#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#include "t.h"

#include "core/series.h"
#include "core/vlog.h"

#define KIND 3

static char dir[64], path[128];

static void fresh(void)
{
	snprintf(dir, sizeof(dir), "/tmp/rl-vlog-XXXXXX");
	if (!mkdtemp(dir))
		abort();
	snprintf(path, sizeof(path), "%s/test.log", dir);
}

/* A record: ts, then `extra` bytes of value v (lengths vary with v). */
static int put(rl_vlog *v, int64_t ts, uint8_t value, size_t extra)
{
	uint8_t r[600];
	rl_le_put32(r, (uint32_t)ts);
	memset(r + 4, value, extra);
	return rl_vlog_append(v, r, 4 + extra);
}

typedef struct {
	int n;
	int64_t ts[4096];
	int stop_after;
	bool intact;
} acc;

static bool collect(const uint8_t *rec, size_t len, void *ctx)
{
	acc *a = ctx;
	if (len > 4 && rec[len - 1] != rec[4])
		a->intact = false;
	a->ts[a->n++] = rl_series_ts(rec);
	return !a->stop_after || a->n < a->stop_after;
}

static void test_newest_first(void)
{
	fresh();
	rl_vlog *v = rl_vlog_open(path, KIND, NULL);
	T_ASSERT(v);
	for (int i = 0; i < 10; i++)
		T_EQ_I64(put(v, 100 + i, (uint8_t)i, (size_t)(i * 7 % 50)), 0);
	T_EQ_I64(rl_vlog_commit(v), 0);
	for (int i = 10; i < 13; i++)
		put(v, 100 + i, (uint8_t)i, 3);
	T_EQ_U64(rl_vlog_count(v), 13);

	acc a = { .intact = true };
	rl_vlog_scan_newest(v, 0, 1000, collect, &a);
	T_EQ_I64(a.n, 13);
	T_EQ_I64(a.ts[0], 112);
	T_EQ_I64(a.ts[12], 100);
	T_ASSERT(a.intact);

	/* A range in the middle, and stopping early. */
	acc b = { .intact = true };
	rl_vlog_scan_newest(v, 103, 111, collect, &b);
	T_EQ_I64(b.n, 8);
	T_EQ_I64(b.ts[0], 110);
	T_EQ_I64(b.ts[7], 103);
	acc c = { .stop_after = 2, .intact = true };
	rl_vlog_scan_newest(v, 0, 1000, collect, &c);
	T_EQ_I64(c.n, 2);

	/* Out of order, too short and too long are refused. */
	T_EQ_I64(put(v, 50, 1, 1), -1);
	uint8_t three[3] = { 0 };
	T_EQ_I64(rl_vlog_append(v, three, 3), -1);
	rl_vlog_close(v);
}

static void test_reopen_and_torn_tail(void)
{
	fresh();
	rl_vlog *v = rl_vlog_open(path, KIND, NULL);
	for (int i = 0; i < 5; i++)
		put(v, 200 + i, 9, 20);
	rl_vlog_commit(v);
	rl_vlog_close(v);

	/* A crash in the middle of the next commit leaves half a record. */
	int fd = open(path, O_WRONLY | O_APPEND);
	uint8_t half[9] = { 40, 0, 1, 2, 3, 4, 5, 6, 7 };
	T_ASSERT(write(fd, half, sizeof(half)) == (ssize_t)sizeof(half));
	close(fd);

	bool recovered = true;
	v = rl_vlog_open(path, KIND, &recovered);
	T_ASSERT(!recovered);
	T_EQ_U64(rl_vlog_count(v), 5);
	T_EQ_I64(put(v, 205, 9, 20), 0);
	T_EQ_I64(rl_vlog_commit(v), 0);
	acc a = { .intact = true };
	rl_vlog_scan_newest(v, 0, 1000, collect, &a);
	T_EQ_I64(a.n, 6);
	T_ASSERT(a.intact);
	rl_vlog_close(v);

	/* Another kind or a garbage header: renamed to .bad and started over. */
	v = rl_vlog_open(path, KIND + 1, &recovered);
	T_ASSERT(recovered);
	T_EQ_U64(rl_vlog_count(v), 0);
	char bad[160];
	snprintf(bad, sizeof(bad), "%s.bad", path);
	T_ASSERT(access(bad, F_OK) == 0);
	rl_vlog_close(v);
}

/* More than one 64 KB chunk: backward reading has to find record boundaries across chunks. */
static void test_big_file(void)
{
	fresh();
	rl_vlog *v = rl_vlog_open(path, KIND, NULL);
	for (int i = 0; i < 3000; i++)
		put(v, 1000 + i, (uint8_t)(i % 251), (size_t)(i % 97));
	T_EQ_I64(rl_vlog_commit(v), 0);
	T_ASSERT(rl_vlog_bytes(v) > 128 * 1024);
	static acc a;
	memset(&a, 0, sizeof(a));
	a.intact = true;
	rl_vlog_scan_newest(v, 0, 1 << 30, collect, &a);
	T_EQ_I64(a.n, 3000);
	T_ASSERT(a.intact);
	bool ordered = true;
	for (int i = 1; i < a.n; i++)
		if (a.ts[i] != a.ts[i - 1] - 1)
			ordered = false;
	T_ASSERT(ordered);
	rl_vlog_close(v);
}

static void test_compact(void)
{
	fresh();
	rl_vlog *v = rl_vlog_open(path, KIND, NULL);
	for (int i = 0; i < 100; i++)
		put(v, 100 + i, (uint8_t)i, (size_t)(i % 13));
	rl_vlog_commit(v);
	T_EQ_I64(rl_vlog_compact(v, 150, 0), 0);
	T_EQ_U64(rl_vlog_count(v), 50);
	T_EQ_I64(rl_vlog_compact(v, 0, 20), 0);
	T_EQ_U64(rl_vlog_count(v), 20);
	acc a = { .intact = true };
	rl_vlog_scan_newest(v, 0, 1000, collect, &a);
	T_EQ_I64(a.n, 20);
	T_EQ_I64(a.ts[19], 180);
	T_ASSERT(a.intact);
	rl_vlog_close(v);
	v = rl_vlog_open(path, KIND, NULL);
	T_EQ_U64(rl_vlog_count(v), 20);
	T_EQ_I64(put(v, 179, 1, 1), -1); /* still knows its newest record */
	T_EQ_I64(rl_vlog_reset(v), 0);
	T_EQ_U64(rl_vlog_count(v), 0);
	rl_vlog_close(v);
}

int main(void)
{
	T_RUN(test_newest_first);
	T_RUN(test_reopen_and_torn_tail);
	T_RUN(test_big_file);
	T_RUN(test_compact);
	T_DONE();
}
