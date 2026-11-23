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
#include "core/vlog.h"

#define HDR RL_VLOG_HDR_SIZE
#define VERSION 1
#define FRAME 4 /* length before and after the payload */

struct rl_vlog {
	char path[256];
	uint16_t kind;
	uint64_t size;  /* bytes on disk, header included */
	uint64_t count; /* records on disk */
	uint8_t *pending;
	size_t pending_len, pending_cap; /* bytes, framed like on disk */
	size_t n_pending;
	uint64_t dropped;
	int64_t newest; /* INT64_MIN when empty */
};

static void encode_header(uint16_t kind, uint8_t out[HDR])
{
	memset(out, 0, HDR);
	rl_le_put32(out, RL_VLOG_MAGIC);
	rl_le_put16(out + 4, VERSION);
	rl_le_put16(out + 6, kind);
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

/*
 * Walks the records forward, checking both lengths of each frame. Returns the offset where the valid part
 * ends (a torn tail after a crash is cut there), counting the records and the newest ts.
 */
static uint64_t walk(int fd, uint64_t size, uint64_t *count, int64_t *newest)
{
	uint64_t off = HDR;
	*count = 0;
	*newest = INT64_MIN;
	uint8_t len2[2], payload[4];
	while (off + FRAME <= size) {
		if (!read_at(fd, len2, 2, (off_t)off))
			break;
		uint16_t len = rl_le_get16(len2);
		if (len < 4 || off + FRAME + len > size || !read_at(fd, payload, 4, (off_t)(off + 2)) ||
		    !read_at(fd, len2, 2, (off_t)(off + 2 + len)) || rl_le_get16(len2) != len)
			break;
		int64_t ts = rl_series_ts(payload);
		if (ts < *newest)
			break;
		*newest = ts;
		(*count)++;
		off += FRAME + len;
	}
	return off;
}

static bool open_existing(rl_vlog *v)
{
	struct stat st;
	uint8_t hdr[HDR], expect[HDR];
	int fd = open(v->path, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return false;
	encode_header(v->kind, expect);
	bool ok = fstat(fd, &st) == 0 && st.st_size >= HDR && read_at(fd, hdr, HDR, 0) && memcmp(hdr, expect, 8) == 0;
	if (ok) {
		uint64_t end = walk(fd, (uint64_t)st.st_size, &v->count, &v->newest);
		if (end != (uint64_t)st.st_size && ftruncate(fd, (off_t)end) != 0)
			ok = false;
		v->size = end;
	}
	close(fd);
	return ok;
}

rl_vlog *rl_vlog_open(const char *path, uint16_t kind, bool *recovered)
{
	rl_vlog *v = calloc(1, sizeof(*v));
	if (!v)
		abort();
	if (recovered)
		*recovered = false;
	snprintf(v->path, sizeof(v->path), "%s", path);
	v->kind = kind;
	if (!open_existing(v)) {
		if (access(v->path, F_OK) == 0) {
			char bad[sizeof(v->path) + 4];
			snprintf(bad, sizeof(bad), "%s.bad", v->path);
			rename(v->path, bad);
			if (recovered)
				*recovered = true;
		}
		if (create_empty(v->path, kind) != 0) {
			free(v);
			return NULL;
		}
		v->size = HDR;
		v->count = 0;
		v->newest = INT64_MIN;
	}
	return v;
}

void rl_vlog_close(rl_vlog *v)
{
	if (!v)
		return;
	free(v->pending);
	free(v);
}

int rl_vlog_append(rl_vlog *v, const uint8_t *rec, size_t len)
{
	if (len < 4 || len > RL_VLOG_REC_MAX)
		return -1;
	int64_t ts = rl_series_ts(rec);
	if (ts < v->newest)
		return -1;
	if (v->pending_len + len + FRAME > RL_VLOG_PENDING_MAX) {
		v->dropped++;
		return -1;
	}
	v->pending = rl_grow(v->pending, &v->pending_cap, v->pending_len + len + FRAME, 1);
	uint8_t *p = v->pending + v->pending_len;
	rl_le_put16(p, (uint16_t)len);
	memcpy(p + 2, rec, len);
	rl_le_put16(p + 2 + len, (uint16_t)len);
	v->pending_len += len + FRAME;
	v->n_pending++;
	v->newest = ts;
	return 0;
}

size_t rl_vlog_pending(const rl_vlog *v)
{
	return v->n_pending;
}

uint64_t rl_vlog_dropped(const rl_vlog *v)
{
	return v->dropped;
}

int rl_vlog_commit(rl_vlog *v)
{
	if (!v->pending_len)
		return 0;
	int fd = open(v->path, O_WRONLY | O_APPEND | O_CLOEXEC);
	bool ok = fd >= 0 && write_all(fd, v->pending, v->pending_len) && fsync(fd) == 0;
	if (fd >= 0) {
		if (!ok && ftruncate(fd, (off_t)v->size) != 0) {
			/* the next open cuts the torn tail */
		}
		close(fd);
	}
	if (!ok)
		return -1;
	v->size += v->pending_len;
	v->count += v->n_pending;
	v->pending_len = 0;
	v->n_pending = 0;
	return 0;
}

/* Newest first through a framed buffer [from, to): the trailing length leads to each record's start. */
static int scan_back(const uint8_t *buf, size_t len, int64_t start, int64_t end, rl_vlog_cb cb, void *ctx, bool *stop)
{
	size_t at = len;
	while (at >= FRAME) {
		uint16_t l = rl_le_get16(buf + at - 2);
		if (l < 4 || (size_t)l + FRAME > at)
			return -1;
		const uint8_t *rec = buf + at - 2 - l;
		int64_t ts = rl_series_ts(rec);
		at -= (size_t)l + FRAME;
		if (ts >= end)
			continue;
		if (ts < start || !cb(rec, l, ctx)) {
			*stop = true;
			return 0;
		}
	}
	return 0;
}

#define CHUNK (64 * 1024)

int rl_vlog_scan_newest(rl_vlog *v, int64_t start, int64_t end, rl_vlog_cb cb, void *ctx)
{
	bool stop = false;
	if (start >= end)
		return 0;
	if (scan_back(v->pending, v->pending_len, start, end, cb, ctx, &stop) < 0)
		return -1;
	if (stop || v->size <= HDR)
		return 0;
	int fd = open(v->path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	/*
	 * Read backwards in chunks of whole records: the trailing lengths tell where each record begins, so a
	 * chunk always starts on a frame boundary that the previous trailer pointed at.
	 */
	uint8_t *buf = malloc(CHUNK + RL_VLOG_REC_MAX + FRAME);
	if (!buf) {
		close(fd);
		return -1;
	}
	uint64_t end_off = v->size;
	int rc = 0;
	while (!stop && end_off > HDR) {
		/* Find a start offset ≥ end_off - CHUNK on a record boundary by walking trailers back. */
		uint64_t from = end_off;
		uint8_t len2[2];
		while (from > HDR) {
			if (!read_at(fd, len2, 2, (off_t)(from - 2))) {
				rc = -1;
				goto out;
			}
			uint64_t l = rl_le_get16(len2) + FRAME;
			if (l > from - HDR) {
				rc = -1;
				goto out;
			}
			if (end_off - (from - l) > CHUNK && from != end_off)
				break;
			from -= l;
		}
		size_t n = (size_t)(end_off - from);
		if (!read_at(fd, buf, n, (off_t)from) || scan_back(buf, n, start, end, cb, ctx, &stop) < 0) {
			rc = -1;
			goto out;
		}
		end_off = from;
	}
out:
	free(buf);
	close(fd);
	return rc;
}

uint64_t rl_vlog_count(const rl_vlog *v)
{
	return v->count + v->n_pending;
}

uint64_t rl_vlog_bytes(const rl_vlog *v)
{
	return v->size + v->pending_len;
}

int rl_vlog_compact(rl_vlog *v, int64_t cutoff, uint64_t max_records)
{
	int fd = open(v->path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	/* First pass: how many records are old, so how many to skip from the front. */
	uint64_t off = HDR, old = 0, i = 0;
	uint8_t frame[4 + 2];
	while (off < v->size) {
		if (!read_at(fd, frame, 6, (off_t)off)) {
			close(fd);
			return -1;
		}
		uint16_t len = rl_le_get16(frame);
		if (rl_series_ts(frame + 2) < cutoff)
			old = i + 1;
		off += FRAME + len;
		i++;
	}
	uint64_t keep = v->count - old;
	uint64_t skip = old + (max_records && keep > max_records ? keep - max_records : 0);
	if (skip == 0) {
		close(fd);
		return 0;
	}
	char tmp[sizeof(v->path) + 4];
	snprintf(tmp, sizeof(tmp), "%s.tmp", v->path);
	int out = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	uint8_t hdr[HDR];
	encode_header(v->kind, hdr);
	bool ok = out >= 0 && write_all(out, hdr, HDR);
	off = HDR;
	for (uint64_t j = 0; ok && j < skip; j++) {
		uint8_t len2[2];
		ok = read_at(fd, len2, 2, (off_t)off);
		off += FRAME + rl_le_get16(len2);
	}
	uint64_t size = HDR;
	uint8_t *buf = ok ? malloc(CHUNK) : NULL;
	ok = ok && buf;
	while (ok && off < v->size) {
		size_t n = (size_t)RL_MIN((uint64_t)CHUNK, v->size - off);
		ok = read_at(fd, buf, n, (off_t)off) && write_all(out, buf, n);
		off += n;
		size += n;
	}
	free(buf);
	close(fd);
	ok = ok && fsync(out) == 0;
	if (out >= 0)
		close(out);
	if (!ok || rename(tmp, v->path) != 0) {
		unlink(tmp);
		return -1;
	}
	v->size = size;
	v->count -= skip;
	return 0;
}

int rl_vlog_reset(rl_vlog *v)
{
	v->pending_len = 0;
	v->n_pending = 0;
	v->count = 0;
	v->newest = INT64_MIN;
	if (create_empty(v->path, v->kind) != 0)
		return -1;
	v->size = HDR;
	return 0;
}
