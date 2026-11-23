#include <signal.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

#include "t.h"

#include "core/series.h"

#define KIND 7

static char dir[64], path[128];

static void fresh(void)
{
	snprintf(dir, sizeof(dir), "/tmp/rl-series-XXXXXX");
	if (!mkdtemp(dir))
		abort();
	snprintf(path, sizeof(path), "%s/test.series", dir);
}

static void rec(uint8_t out[RL_SERIES_REC_SIZE], int64_t ts, uint32_t v)
{
	memset(out, 0xAB, RL_SERIES_REC_SIZE);
	rl_le_put32(out, (uint32_t)ts);
	rl_le_put32(out + 28, v);
}

static int put(rl_series *s, int64_t ts, uint32_t v)
{
	uint8_t r[RL_SERIES_REC_SIZE];
	rec(r, ts, v);
	return rl_series_append(s, r);
}

typedef struct {
	int n;
	uint64_t sum;
	int64_t first, last;
	bool ordered, intact;
	int stop_after;
} acc;

static bool acc_cb(const uint8_t *r, void *ctx)
{
	acc *a = ctx;
	int64_t ts = rl_series_ts(r);
	if (a->n == 0)
		a->first = ts;
	else if (ts < a->last)
		a->ordered = false;
	if (r[4] != 0xAB || r[27] != 0xAB)
		a->intact = false;
	a->last = ts;
	a->n++;
	a->sum += rl_le_get32(r + 28);
	return !a->stop_after || a->n < a->stop_after;
}

static acc scan(rl_series *s, int64_t a, int64_t b)
{
	acc x = { .ordered = true, .intact = true };
	rl_series_scan(s, a, b, acc_cb, &x);
	return x;
}

static off_t file_size(void)
{
	struct stat st;
	return stat(path, &st) == 0 ? st.st_size : -1;
}

static void roundtrip(void)
{
	fresh();
	bool recovered = true;
	rl_series *s = rl_series_open(path, KIND, &recovered);
	T_ASSERT(s != NULL);
	T_ASSERT(!recovered);
	T_EQ_I64(rl_series_oldest(s), INT64_MAX);
	T_EQ_I64(rl_series_newest(s), INT64_MIN);
	for (int i = 0; i < 300; i++)
		T_EQ_I64(put(s, 1000 + 60 * i, (uint32_t)i), 0);
	T_EQ_U64(rl_series_pending(s), 300);
	T_EQ_I64(rl_series_commit(s), 0);
	T_EQ_U64(rl_series_pending(s), 0);
	T_EQ_I64(file_size(), RL_SERIES_HDR_SIZE + 300 * RL_SERIES_REC_SIZE);
	rl_series_close(s);

	s = rl_series_open(path, KIND, &recovered);
	T_ASSERT(!recovered);
	acc a = scan(s, 0, INT64_MAX);
	T_EQ_I64(a.n, 300);
	T_ASSERT(a.ordered);
	T_ASSERT(a.intact);
	T_EQ_U64(a.sum, 299 * 300 / 2);
	T_EQ_U64(rl_series_bytes(s), RL_SERIES_HDR_SIZE + 300 * RL_SERIES_REC_SIZE);
	T_EQ_I64(rl_series_oldest(s), 1000);
	T_EQ_I64(rl_series_newest(s), 1000 + 60 * 299);
	/* the scan stops when the callback says so */
	acc stop = { .ordered = true, .intact = true, .stop_after = 5 };
	rl_series_scan(s, 0, INT64_MAX, acc_cb, &stop);
	T_EQ_I64(stop.n, 5);
	rl_series_close(s);
}

static void scan_range_disk_and_pending(void)
{
	fresh();
	rl_series *s = rl_series_open(path, KIND, NULL);
	for (int i = 0; i < 10; i++)
		put(s, 60 * i, 1);
	rl_series_commit(s);
	for (int i = 10; i < 15; i++)
		put(s, 60 * i, 10);
	acc a = scan(s, 300, 720); /* ts 300..660 */
	T_EQ_I64(a.n, 7);
	T_EQ_U64(a.sum, 5 * 1 + 2 * 10);
	T_EQ_I64(a.first, 300);
	T_EQ_I64(a.last, 660);
	T_ASSERT(a.ordered);
	T_EQ_I64(scan(s, 5000, 6000).n, 0);
	T_EQ_I64(scan(s, 600, 600).n, 0);
	T_EQ_I64(rl_series_oldest(s), 0);
	T_EQ_I64(rl_series_newest(s), 840);
	rl_series_close(s);
}

static void order_is_kept(void)
{
	fresh();
	rl_series *s = rl_series_open(path, KIND, NULL);
	T_EQ_I64(put(s, 100, 1), 0);
	T_EQ_I64(put(s, 100, 2), 0); /* same ts: fine */
	T_EQ_I64(put(s, 99, 3), -1);
	T_EQ_U64(rl_series_pending(s), 2);
	rl_series_commit(s);
	T_EQ_I64(put(s, 50, 4), -1); /* older than what is on disk */
	T_EQ_I64(put(s, 200, 5), 0);
	rl_series_discard_pending(s);
	T_EQ_I64(rl_series_newest(s), 100);
	T_EQ_I64(put(s, 150, 6), 0); /* the discarded 200 no longer counts */
	rl_series_close(s);
}

static void failed_commit_keeps_length(void)
{
	fresh();
	rl_series *s = rl_series_open(path, KIND, NULL);
	for (int i = 0; i < 4; i++)
		put(s, i, 1);
	T_EQ_I64(rl_series_commit(s), 0);
	off_t before = file_size();

	/* the file cannot be opened: nothing is written, the records stay queued */
	char aside[160];
	snprintf(aside, sizeof(aside), "%s.aside", path);
	T_EQ_I64(rename(path, aside), 0);
	T_EQ_I64(mkdir(path, 0700), 0);
	put(s, 10, 1);
	T_ASSERT(rl_series_commit(s) != 0);
	T_EQ_U64(rl_series_pending(s), 1);
	rmdir(path);
	T_EQ_I64(rename(aside, path), 0);

	/* a write that fails half way (file size limit): the torn tail is cut off again */
	for (int i = 11; i < 20; i++)
		put(s, i, 1);
	struct rlimit old, lim;
	getrlimit(RLIMIT_FSIZE, &old);
	lim = old;
	lim.rlim_cur = (rlim_t)before + RL_SERIES_REC_SIZE + RL_SERIES_REC_SIZE / 2;
	signal(SIGXFSZ, SIG_IGN);
	setrlimit(RLIMIT_FSIZE, &lim);
	int rc = rl_series_commit(s);
	setrlimit(RLIMIT_FSIZE, &old);
	T_ASSERT(rc != 0);
	T_EQ_I64(file_size(), before);
	T_EQ_U64(rl_series_pending(s), 10);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 14);

	T_EQ_I64(rl_series_commit(s), 0);
	T_EQ_U64(rl_series_pending(s), 0);
	rl_series_close(s);
	s = rl_series_open(path, KIND, NULL);
	acc a = scan(s, 0, INT64_MAX);
	T_EQ_I64(a.n, 14);
	T_ASSERT(a.ordered && a.intact);
	rl_series_close(s);
}

static void compact_cutoff_and_size(void)
{
	fresh();
	rl_series *s = rl_series_open(path, KIND, NULL);
	for (int i = 0; i < 100; i++)
		put(s, 60 * i, (uint32_t)i);
	rl_series_commit(s);
	put(s, 6000, 100); /* pending */
	T_EQ_I64(rl_series_compact(s, 60 * 40, 0), 0);
	acc a = scan(s, 0, INT64_MAX);
	T_EQ_I64(a.n, 61);
	T_EQ_I64(a.first, 60 * 40);
	T_EQ_I64(file_size(), RL_SERIES_HDR_SIZE + 60 * RL_SERIES_REC_SIZE);

	/* size cap: header + 20 records, the pending one included */
	uint64_t cap = RL_SERIES_HDR_SIZE + 20 * RL_SERIES_REC_SIZE;
	T_EQ_I64(rl_series_compact(s, 0, cap), 0);
	T_ASSERT(rl_series_bytes(s) <= cap);
	a = scan(s, 0, INT64_MAX);
	T_EQ_I64(a.n, 20);
	T_EQ_I64(a.first, 60 * 81);
	T_EQ_I64(a.last, 6000);
	rl_series_close(s);

	s = rl_series_open(path, KIND, NULL);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 19); /* the pending record was never committed */
	T_EQ_I64(rl_series_oldest(s), 60 * 81);
	/* pending records older than the cutoff go too */
	put(s, 99999, 1);
	T_EQ_I64(rl_series_compact(s, 100000, 0), 0);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 0);
	T_EQ_U64(rl_series_pending(s), 0);
	rl_series_close(s);
}

static void failed_compaction_keeps_file(void)
{
	fresh();
	rl_series *s = rl_series_open(path, KIND, NULL);
	for (int i = 0; i < 10; i++)
		put(s, 60 * i, 1);
	rl_series_commit(s);
	char tmp[160];
	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	mkdir(tmp, 0700); /* the temporary file cannot be created */
	T_ASSERT(rl_series_compact(s, 1000000, 0) != 0);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 10);
	rl_series_close(s);
}

static void damaged_files(void)
{
	fresh();
	rl_series *s = rl_series_open(path, KIND, NULL);
	put(s, 86400, 1);
	put(s, 86460, 1);
	rl_series_commit(s);
	rl_series_close(s);

	/* torn record */
	T_EQ_I64(truncate(path, RL_SERIES_HDR_SIZE + RL_SERIES_REC_SIZE + 5), 0);
	bool recovered = false;
	s = rl_series_open(path, KIND, &recovered);
	T_ASSERT(s != NULL);
	T_ASSERT(recovered);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 0);
	put(s, 86400, 1);
	T_EQ_I64(rl_series_commit(s), 0);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 1);
	rl_series_close(s);
	char bad[160];
	snprintf(bad, sizeof(bad), "%s.bad", path);
	T_EQ_I64(access(bad, F_OK), 0);

	/* another kind of file under this name */
	s = rl_series_open(path, KIND + 1, &recovered);
	T_ASSERT(recovered);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 0);
	rl_series_close(s);

	/* garbage header */
	FILE *f = fopen(path, "w");
	fputs("not a series file at all, really", f);
	fclose(f);
	s = rl_series_open(path, KIND, &recovered);
	T_ASSERT(recovered);
	rl_series_close(s);

	/* records out of order */
	s = rl_series_open(path, KIND, &recovered);
	T_ASSERT(!recovered);
	put(s, 500, 1);
	put(s, 600, 1);
	rl_series_commit(s);
	rl_series_close(s);
	uint8_t r[RL_SERIES_REC_SIZE];
	rec(r, 100, 1);
	f = fopen(path, "r+");
	fseek(f, RL_SERIES_HDR_SIZE + RL_SERIES_REC_SIZE, SEEK_SET);
	fwrite(r, sizeof(r), 1, f);
	fclose(f);
	s = rl_series_open(path, KIND, &recovered);
	T_ASSERT(recovered);
	rl_series_close(s);

	/* a directory that cannot hold the file */
	T_ASSERT(rl_series_open("/nonexistent-dir/x.series", KIND, NULL) == NULL);
}

static void reset(void)
{
	fresh();
	rl_series *s = rl_series_open(path, KIND, NULL);
	put(s, 10, 1);
	rl_series_commit(s);
	put(s, 20, 1);
	T_EQ_I64(rl_series_reset(s), 0);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 0);
	T_EQ_U64(rl_series_pending(s), 0);
	T_EQ_I64(rl_series_newest(s), INT64_MIN);
	T_EQ_I64(put(s, 5, 1), 0); /* older than before the reset is fine now */
	T_EQ_I64(rl_series_commit(s), 0);
	rl_series_close(s);
	s = rl_series_open(path, KIND, NULL);
	T_EQ_I64(scan(s, 0, INT64_MAX).n, 1);
	rl_series_close(s);
}

static void byte_order(void)
{
	uint8_t b[4];
	rl_le_put32(b, 0x11223344u);
	T_EQ_U64(b[0], 0x44);
	T_EQ_U64(b[3], 0x11);
	T_EQ_U64(rl_le_get32(b), 0x11223344u);
	rl_le_put16(b, 0xBEEF);
	T_EQ_U64(b[0], 0xEF);
	T_EQ_U64(rl_le_get16(b), 0xBEEF);
	rl_le_put32(b, 0xFFFFFFFFu);
	T_EQ_I64(rl_series_ts(b), 0xFFFFFFFFLL);
}

int main(void)
{
	T_RUN(roundtrip);
	T_RUN(scan_range_disk_and_pending);
	T_RUN(order_is_kept);
	T_RUN(failed_commit_keeps_length);
	T_RUN(compact_cutoff_and_size);
	T_RUN(failed_compaction_keeps_file);
	T_RUN(damaged_files);
	T_RUN(reset);
	T_RUN(byte_order);
	T_DONE();
}
