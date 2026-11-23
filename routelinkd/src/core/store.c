#define _GNU_SOURCE
#include <endian.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "core/store.h"
#include "core/util.h"

static const char *const FILES[RL_TIER_COUNT] = { "traffic.minute", "traffic.hour", "traffic.day", "traffic.month" };

typedef struct {
	char path[256];
	uint64_t size; /* bytes on disk, header included */
	rl_rec *pending;
	size_t n_pending, cap_pending;
} tier_file;

struct rl_store {
	tier_file t[RL_TIER_COUNT];
	int recovered;
};

int64_t rl_retention_seconds(const rl_retention *r, rl_tier tier)
{
	switch (tier) {
	case RL_TIER_MINUTE:
		return (int64_t)r->minute_hours * 3600;
	case RL_TIER_HOUR:
		return (int64_t)r->hour_days * 86400;
	case RL_TIER_DAY:
		return (int64_t)r->day_days * 86400;
	default:
		return -1;
	}
}

static void put_u16(uint8_t *p, uint16_t v)
{
	v = htole16(v);
	memcpy(p, &v, 2);
}

static void put_u32(uint8_t *p, uint32_t v)
{
	v = htole32(v);
	memcpy(p, &v, 4);
}

static void put_u64(uint8_t *p, uint64_t v)
{
	v = htole64(v);
	memcpy(p, &v, 8);
}

static uint16_t get_u16(const uint8_t *p)
{
	uint16_t v;
	memcpy(&v, p, 2);
	return le16toh(v);
}

static uint32_t get_u32(const uint8_t *p)
{
	uint32_t v;
	memcpy(&v, p, 4);
	return le32toh(v);
}

static uint64_t get_u64(const uint8_t *p)
{
	uint64_t v;
	memcpy(&v, p, 8);
	return le64toh(v);
}

static void encode(const rl_rec *r, uint8_t out[RL_STORE_REC_SIZE])
{
	memset(out, 0, RL_STORE_REC_SIZE);
	put_u32(out, (uint32_t)r->ts);
	put_u16(out + 4, r->dev);
	out[6] = r->cls;
	out[7] = r->flags;
	put_u32(out + 8, r->conns);
	put_u64(out + 16, r->rx);
	put_u64(out + 24, r->tx);
}

static void decode(const uint8_t in[RL_STORE_REC_SIZE], rl_rec *r)
{
	r->ts = get_u32(in);
	r->dev = get_u16(in + 4);
	r->cls = in[6];
	r->flags = in[7];
	r->conns = get_u32(in + 8);
	r->rx = get_u64(in + 16);
	r->tx = get_u64(in + 24);
}

static void encode_header(rl_tier tier, uint8_t out[RL_STORE_HDR_SIZE])
{
	memset(out, 0, RL_STORE_HDR_SIZE);
	put_u32(out, RL_STORE_MAGIC);
	put_u16(out + 4, RL_STORE_VERSION);
	put_u16(out + 6, RL_STORE_REC_SIZE);
	out[8] = (uint8_t)tier;
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

static int create_empty(const char *path, rl_tier tier)
{
	uint8_t hdr[RL_STORE_HDR_SIZE];
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0)
		return -1;
	encode_header(tier, hdr);
	bool ok = write_all(fd, hdr, sizeof(hdr)) && fsync(fd) == 0;
	close(fd);
	return ok ? 0 : -1;
}

/* Valid header and a whole number of records. */
static bool file_valid(const char *path, rl_tier tier, uint64_t *size)
{
	struct stat st;
	uint8_t hdr[RL_STORE_HDR_SIZE];
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return false;
	bool ok = fstat(fd, &st) == 0 && st.st_size >= RL_STORE_HDR_SIZE &&
		  (st.st_size - RL_STORE_HDR_SIZE) % RL_STORE_REC_SIZE == 0 && read_at(fd, hdr, sizeof(hdr), 0) &&
		  get_u32(hdr) == RL_STORE_MAGIC && get_u16(hdr + 4) == RL_STORE_VERSION &&
		  get_u16(hdr + 6) == RL_STORE_REC_SIZE && hdr[8] == tier;
	close(fd);
	if (ok)
		*size = (uint64_t)st.st_size;
	return ok;
}

rl_store *rl_store_open(const char *dir)
{
	rl_store *s = calloc(1, sizeof(*s));
	if (!s)
		abort();
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		tier_file *f = &s->t[t];
		snprintf(f->path, sizeof(f->path), "%s/%s", dir, FILES[t]);
		if (file_valid(f->path, (rl_tier)t, &f->size))
			continue;
		if (access(f->path, F_OK) == 0) {
			char bad[sizeof(f->path) + 4];
			snprintf(bad, sizeof(bad), "%s.bad", f->path);
			rename(f->path, bad);
			s->recovered++;
		}
		if (create_empty(f->path, (rl_tier)t) != 0) {
			rl_store_close(s);
			return NULL;
		}
		f->size = RL_STORE_HDR_SIZE;
	}
	return s;
}

void rl_store_close(rl_store *s)
{
	if (!s)
		return;
	for (int t = 0; t < RL_TIER_COUNT; t++)
		free(s->t[t].pending);
	free(s);
}

int rl_store_recovered(const rl_store *s)
{
	return s->recovered;
}

void rl_store_append(rl_store *s, rl_tier tier, const rl_rec *r)
{
	tier_file *f = &s->t[tier];
	f->pending = rl_grow(f->pending, &f->cap_pending, f->n_pending + 1, sizeof(rl_rec));
	f->pending[f->n_pending++] = *r;
}

size_t rl_store_pending(const rl_store *s)
{
	size_t n = 0;
	for (int t = 0; t < RL_TIER_COUNT; t++)
		n += s->t[t].n_pending;
	return n;
}

void rl_store_discard_pending(rl_store *s)
{
	for (int t = 0; t < RL_TIER_COUNT; t++)
		s->t[t].n_pending = 0;
}

static int commit_tier(tier_file *f)
{
	if (!f->n_pending)
		return 0;
	size_t len = f->n_pending * RL_STORE_REC_SIZE;
	uint8_t *buf = malloc(len);
	if (!buf)
		abort();
	for (size_t i = 0; i < f->n_pending; i++)
		encode(&f->pending[i], buf + i * RL_STORE_REC_SIZE);
	int fd = open(f->path, O_WRONLY | O_APPEND | O_CLOEXEC);
	bool ok = fd >= 0 && write_all(fd, buf, len) && fsync(fd) == 0;
	if (fd >= 0) {
		if (!ok && ftruncate(fd, (off_t)f->size) != 0) {
			/* the next open renames the damaged file */
		}
		close(fd);
	}
	free(buf);
	if (!ok)
		return -1;
	f->size += len;
	f->n_pending = 0;
	return 0;
}

int rl_store_commit(rl_store *s)
{
	int rc = 0;
	for (int t = 0; t < RL_TIER_COUNT; t++)
		if (commit_tier(&s->t[t]) != 0)
			rc = -1;
	return rc;
}

static uint64_t disk_records(const tier_file *f)
{
	return (f->size - RL_STORE_HDR_SIZE) / RL_STORE_REC_SIZE;
}

/* Index of the first record with ts >= start (records are in ts order). */
static uint64_t lower_bound(int fd, uint64_t n, int64_t start)
{
	uint64_t lo = 0, hi = n;
	uint8_t raw[RL_STORE_REC_SIZE];
	while (lo < hi) {
		uint64_t mid = lo + (hi - lo) / 2;
		if (!read_at(fd, raw, sizeof(raw), (off_t)(RL_STORE_HDR_SIZE + mid * RL_STORE_REC_SIZE)))
			return n;
		if ((int64_t)get_u32(raw) < start)
			lo = mid + 1;
		else
			hi = mid;
	}
	return lo;
}

#define SCAN_BATCH 256

int rl_store_scan(rl_store *s, rl_tier tier, int64_t start, int64_t end, rl_rec_cb cb, void *ctx)
{
	tier_file *f = &s->t[tier];
	uint64_t n = disk_records(f);
	if (n) {
		int fd = open(f->path, O_RDONLY | O_CLOEXEC);
		if (fd < 0)
			return -1;
		uint8_t buf[SCAN_BATCH * RL_STORE_REC_SIZE];
		for (uint64_t i = lower_bound(fd, n, start); i < n;) {
			uint64_t k = RL_MIN(n - i, (uint64_t)SCAN_BATCH);
			if (!read_at(fd, buf, k * RL_STORE_REC_SIZE, (off_t)(RL_STORE_HDR_SIZE + i * RL_STORE_REC_SIZE))) {
				close(fd);
				return -1;
			}
			for (uint64_t j = 0; j < k; j++) {
				rl_rec r;
				decode(buf + j * RL_STORE_REC_SIZE, &r);
				if (r.ts >= end || !cb(&r, ctx)) {
					close(fd);
					return 0;
				}
			}
			i += k;
		}
		close(fd);
	}
	for (size_t i = 0; i < f->n_pending; i++) {
		const rl_rec *r = &f->pending[i];
		if (r->ts < start)
			continue;
		if (r->ts >= end || !cb(r, ctx))
			break;
	}
	return 0;
}

/* Rewrites a tier without its first `drop` records. */
static int drop_oldest(tier_file *f, rl_tier tier, uint64_t drop)
{
	uint64_t n = disk_records(f);
	if (!drop)
		return 0;
	if (drop > n)
		drop = n;
	char tmp[sizeof(f->path) + 4];
	snprintf(tmp, sizeof(tmp), "%s.tmp", f->path);
	int in = open(f->path, O_RDONLY | O_CLOEXEC);
	int out = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	bool ok = in >= 0 && out >= 0;
	uint8_t hdr[RL_STORE_HDR_SIZE];
	encode_header(tier, hdr);
	ok = ok && write_all(out, hdr, sizeof(hdr));
	uint8_t buf[SCAN_BATCH * RL_STORE_REC_SIZE];
	for (uint64_t i = drop; ok && i < n;) {
		uint64_t k = RL_MIN(n - i, (uint64_t)SCAN_BATCH);
		ok = read_at(in, buf, k * RL_STORE_REC_SIZE, (off_t)(RL_STORE_HDR_SIZE + i * RL_STORE_REC_SIZE)) &&
		     write_all(out, buf, k * RL_STORE_REC_SIZE);
		i += k;
	}
	ok = ok && fsync(out) == 0;
	if (in >= 0)
		close(in);
	if (out >= 0)
		close(out);
	if (ok && rename(tmp, f->path) == 0) {
		f->size = RL_STORE_HDR_SIZE + (n - drop) * RL_STORE_REC_SIZE;
		return 0;
	}
	if (out >= 0)
		unlink(tmp);
	return -1;
}

static uint64_t count_before(tier_file *f, int64_t cutoff)
{
	uint64_t n = disk_records(f);
	if (!n)
		return 0;
	int fd = open(f->path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return 0;
	uint64_t k = lower_bound(fd, n, cutoff);
	close(fd);
	return k;
}

int rl_store_compact(rl_store *s, int64_t now, const rl_retention *ret, uint64_t max_bytes)
{
	int rc = 0;
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		int64_t keep = rl_retention_seconds(ret, (rl_tier)t);
		if (keep < 0)
			continue;
		if (drop_oldest(&s->t[t], (rl_tier)t, count_before(&s->t[t], now - keep)) != 0)
			rc = -1;
	}
	for (int t = 0; t < RL_TIER_MONTH && rl_store_bytes(s) > max_bytes; t++) {
		uint64_t excess = rl_store_bytes(s) - max_bytes;
		uint64_t drop = (excess + RL_STORE_REC_SIZE - 1) / RL_STORE_REC_SIZE;
		if (drop_oldest(&s->t[t], (rl_tier)t, RL_MIN(drop, disk_records(&s->t[t]))) != 0)
			rc = -1;
	}
	return rc;
}

uint64_t rl_store_bytes(const rl_store *s)
{
	uint64_t n = 0;
	for (int t = 0; t < RL_TIER_COUNT; t++)
		n += s->t[t].size + s->t[t].n_pending * RL_STORE_REC_SIZE;
	return n;
}

int64_t rl_store_oldest(rl_store *s, rl_tier tier)
{
	tier_file *f = &s->t[tier];
	if (disk_records(f)) {
		uint8_t raw[RL_STORE_REC_SIZE];
		int fd = open(f->path, O_RDONLY | O_CLOEXEC);
		if (fd >= 0) {
			bool ok = read_at(fd, raw, sizeof(raw), RL_STORE_HDR_SIZE);
			close(fd);
			if (ok)
				return get_u32(raw);
		}
	}
	return f->n_pending ? f->pending[0].ts : INT64_MAX;
}

int64_t rl_store_newest(rl_store *s, rl_tier tier)
{
	tier_file *f = &s->t[tier];
	if (f->n_pending)
		return f->pending[f->n_pending - 1].ts;
	uint64_t n = disk_records(f);
	if (n) {
		uint8_t raw[RL_STORE_REC_SIZE];
		int fd = open(f->path, O_RDONLY | O_CLOEXEC);
		if (fd >= 0) {
			bool ok = read_at(fd, raw, sizeof(raw), (off_t)(RL_STORE_HDR_SIZE + (n - 1) * RL_STORE_REC_SIZE));
			close(fd);
			if (ok)
				return get_u32(raw);
		}
	}
	return INT64_MIN;
}

int rl_store_reset(rl_store *s)
{
	int rc = 0;
	for (int t = 0; t < RL_TIER_COUNT; t++) {
		s->t[t].n_pending = 0;
		if (create_empty(s->t[t].path, (rl_tier)t) != 0)
			rc = -1;
		else
			s->t[t].size = RL_STORE_HDR_SIZE;
	}
	return rc;
}
