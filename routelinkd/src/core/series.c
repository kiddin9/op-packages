#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "core/series.h"
#include "core/util.h"

#define REC RL_SERIES_REC_SIZE
#define HDR RL_SERIES_HDR_SIZE
#define BATCH 256

struct rl_series {
	char path[256];
	uint16_t kind;
	uint64_t size; /* bytes on disk, header included */
	uint8_t *pending;
	size_t n_pending, cap_pending; /* records */
	int64_t newest;                /* INT64_MIN when empty */
};

static void encode_header(uint16_t kind, uint8_t out[HDR])
{
	memset(out, 0, HDR);
	rl_le_put32(out, RL_SERIES_MAGIC);
	rl_le_put16(out + 4, RL_SERIES_VERSION);
	rl_le_put16(out + 6, REC);
	rl_le_put16(out + 8, kind);
}

static bool write_all(int fd, const void *buf, size_t len)
{
	const uint8_t *p = buf;
	while (len) {
		ssize_t w = write(fd, p, len);
		if (w < 0) {
			if (errno == EINTR)
				continue;
			return false;
		}
		p += w;
		len -= (size_t)w;
	}
	return true;
}

static bool read_at(int fd, void *buf, size_t len, off_t off)
{
	uint8_t *p = buf;
	while (len) {
		ssize_t r = pread(fd, p, len, off);
		if (r <= 0) {
			if (r < 0 && errno == EINTR)
				continue;
			return false;
		}
		p += r;
		len -= (size_t)r;
		off += r;
	}
	return true;
}

static uint64_t disk_records(const rl_series *s)
{
	return (s->size - HDR) / REC;
}

static off_t rec_off(uint64_t i)
{
	return (off_t)(HDR + i * REC);
}

static int create_empty(const char *path, uint16_t kind)
{
	uint8_t hdr[HDR];
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0)
		return -1;
	encode_header(kind, hdr);
	bool ok = write_all(fd, hdr, sizeof(hdr)) && fsync(fd) == 0;
	close(fd);
	return ok ? 0 : -1;
}

/* Valid header, a whole number of records, and records in ts order at the ends. */
static bool file_valid(const char *path, uint16_t kind, uint64_t *size)
{
	struct stat st;
	uint8_t hdr[HDR], expect[HDR];
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return false;
	encode_header(kind, expect);
	bool ok = fstat(fd, &st) == 0 && st.st_size >= HDR && (st.st_size - HDR) % REC == 0 &&
		  read_at(fd, hdr, sizeof(hdr), 0) && memcmp(hdr, expect, 10) == 0;
	if (ok && st.st_size >= HDR + 2 * REC) {
		uint8_t first[REC], last[REC];
		ok = read_at(fd, first, REC, HDR) && read_at(fd, last, REC, st.st_size - REC) &&
		     rl_series_ts(first) <= rl_series_ts(last);
	}
	close(fd);
	if (ok)
		*size = (uint64_t)st.st_size;
	return ok;
}

static int64_t disk_ts(const rl_series *s, uint64_t i)
{
	uint8_t raw[REC];
	int fd = open(s->path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return INT64_MIN;
	bool ok = read_at(fd, raw, REC, rec_off(i));
	close(fd);
	return ok ? rl_series_ts(raw) : INT64_MIN;
}

static int64_t disk_newest(const rl_series *s)
{
	uint64_t n = disk_records(s);
	return n ? disk_ts(s, n - 1) : INT64_MIN;
}

rl_series *rl_series_open(const char *path, uint16_t kind, bool *recovered)
{
	rl_series *s = calloc(1, sizeof(*s));
	if (!s)
		abort();
	if (recovered)
		*recovered = false;
	snprintf(s->path, sizeof(s->path), "%s", path);
	s->kind = kind;
	if (!file_valid(s->path, kind, &s->size)) {
		if (access(s->path, F_OK) == 0) {
			char bad[sizeof(s->path) + 4];
			snprintf(bad, sizeof(bad), "%s.bad", s->path);
			rename(s->path, bad);
			if (recovered)
				*recovered = true;
		}
		if (create_empty(s->path, kind) != 0) {
			free(s);
			return NULL;
		}
		s->size = HDR;
	}
	s->newest = disk_newest(s);
	return s;
}

void rl_series_close(rl_series *s)
{
	if (!s)
		return;
	free(s->pending);
	free(s);
}

int rl_series_append(rl_series *s, const uint8_t rec[REC])
{
	int64_t ts = rl_series_ts(rec);
	if (ts < s->newest)
		return -1;
	s->pending = rl_grow(s->pending, &s->cap_pending, s->n_pending + 1, REC);
	memcpy(s->pending + s->n_pending * REC, rec, REC);
	s->n_pending++;
	s->newest = ts;
	return 0;
}

size_t rl_series_pending(const rl_series *s)
{
	return s->n_pending;
}

void rl_series_discard_pending(rl_series *s)
{
	s->n_pending = 0;
	s->newest = disk_newest(s);
}

int rl_series_commit(rl_series *s)
{
	if (!s->n_pending)
		return 0;
	size_t len = s->n_pending * REC;
	int fd = open(s->path, O_WRONLY | O_APPEND | O_CLOEXEC);
	bool ok = fd >= 0 && write_all(fd, s->pending, len) && fsync(fd) == 0;
	if (fd >= 0) {
		if (!ok && ftruncate(fd, (off_t)s->size) != 0) {
			/* the next open renames the damaged file */
		}
		close(fd);
	}
	if (!ok)
		return -1;
	s->size += len;
	s->n_pending = 0;
	return 0;
}

/* Index of the first disk record with ts >= start. */
static uint64_t lower_bound(int fd, uint64_t n, int64_t start)
{
	uint64_t lo = 0, hi = n;
	uint8_t raw[REC];
	while (lo < hi) {
		uint64_t mid = lo + (hi - lo) / 2;
		if (!read_at(fd, raw, REC, rec_off(mid)))
			return n;
		if (rl_series_ts(raw) < start)
			lo = mid + 1;
		else
			hi = mid;
	}
	return lo;
}

int rl_series_scan(rl_series *s, int64_t start, int64_t end, rl_series_cb cb, void *ctx)
{
	if (start >= end)
		return 0;
	uint64_t n = disk_records(s);
	if (n) {
		int fd = open(s->path, O_RDONLY | O_CLOEXEC);
		if (fd < 0)
			return -1;
		uint8_t buf[BATCH * REC];
		for (uint64_t i = lower_bound(fd, n, start); i < n;) {
			uint64_t k = RL_MIN(n - i, (uint64_t)BATCH);
			if (!read_at(fd, buf, k * REC, rec_off(i))) {
				close(fd);
				return -1;
			}
			for (uint64_t j = 0; j < k; j++) {
				const uint8_t *r = buf + j * REC;
				if (rl_series_ts(r) >= end || !cb(r, ctx)) {
					close(fd);
					return 0;
				}
			}
			i += k;
		}
		close(fd);
	}
	for (size_t i = 0; i < s->n_pending; i++) {
		const uint8_t *r = s->pending + i * REC;
		int64_t ts = rl_series_ts(r);
		if (ts < start)
			continue;
		if (ts >= end || !cb(r, ctx))
			break;
	}
	return 0;
}

/* Rewrites the file without its first `drop` records. */
static int drop_oldest(rl_series *s, uint64_t drop)
{
	uint64_t n = disk_records(s);
	if (!drop)
		return 0;
	if (drop > n)
		drop = n;
	char tmp[sizeof(s->path) + 4];
	snprintf(tmp, sizeof(tmp), "%s.tmp", s->path);
	int in = open(s->path, O_RDONLY | O_CLOEXEC);
	int out = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	bool ok = in >= 0 && out >= 0;
	uint8_t hdr[HDR];
	encode_header(s->kind, hdr);
	ok = ok && write_all(out, hdr, sizeof(hdr));
	uint8_t buf[BATCH * REC];
	for (uint64_t i = drop; ok && i < n;) {
		uint64_t k = RL_MIN(n - i, (uint64_t)BATCH);
		ok = read_at(in, buf, k * REC, rec_off(i)) && write_all(out, buf, k * REC);
		i += k;
	}
	ok = ok && fsync(out) == 0;
	if (in >= 0)
		close(in);
	if (out >= 0)
		close(out);
	if (ok && rename(tmp, s->path) == 0) {
		s->size = HDR + (n - drop) * REC;
		return 0;
	}
	if (out >= 0)
		unlink(tmp);
	return -1;
}

int rl_series_compact(rl_series *s, int64_t cutoff, uint64_t max_bytes)
{
	/* pending records older than the cutoff (possible after a long time without a commit) */
	size_t keep_from = 0;
	while (keep_from < s->n_pending && rl_series_ts(s->pending + keep_from * REC) < cutoff)
		keep_from++;
	if (keep_from) {
		memmove(s->pending, s->pending + keep_from * REC, (s->n_pending - keep_from) * REC);
		s->n_pending -= keep_from;
	}

	uint64_t n = disk_records(s), drop = 0;
	if (n) {
		int fd = open(s->path, O_RDONLY | O_CLOEXEC);
		if (fd < 0)
			return -1;
		drop = lower_bound(fd, n, cutoff);
		close(fd);
	}
	if (max_bytes) {
		uint64_t total = s->size - drop * REC + s->n_pending * REC;
		if (total > max_bytes)
			drop += (total - max_bytes + REC - 1) / REC;
	}
	return drop_oldest(s, RL_MIN(drop, n));
}

uint64_t rl_series_bytes(const rl_series *s)
{
	return s->size + s->n_pending * REC;
}

int64_t rl_series_oldest(rl_series *s)
{
	if (disk_records(s)) {
		int64_t ts = disk_ts(s, 0);
		if (ts != INT64_MIN)
			return ts;
	}
	return s->n_pending ? rl_series_ts(s->pending) : INT64_MAX;
}

int64_t rl_series_newest(const rl_series *s)
{
	return s->newest;
}

int rl_series_reset(rl_series *s)
{
	s->n_pending = 0;
	s->newest = INT64_MIN;
	if (create_empty(s->path, s->kind) != 0)
		return -1;
	s->size = HDR;
	return 0;
}
