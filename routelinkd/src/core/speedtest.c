#include <inttypes.h>
#include <json-c/json.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#include "core/speedtest.h"
#include "core/util.h"

static const char *const PHASES[] = {
	[RL_SPEED_LATENCY] = "latency", [RL_SPEED_DOWNLOAD] = "download", [RL_SPEED_UPLOAD] = "upload",
	[RL_SPEED_DONE] = "done",       [RL_SPEED_FAILED] = "failed",
};

const char *rl_speed_phase_name(rl_speed_phase p)
{
	return p <= RL_SPEED_FAILED ? PHASES[p] : "failed";
}

/* ---- server ---- */

static bool parse_port(const char *s, int *port)
{
	char *end;
	if (!*s || *s < '0' || *s > '9')
		return false;
	long v = strtol(s, &end, 10);
	if (*end || v < 1 || v > 65535)
		return false;
	*port = (int)v;
	return true;
}

bool rl_speed_target_of(const char *server, rl_speed_target *t)
{
	memset(t, 0, sizeof(*t));
	if (!server || !*server) {
		/*
		 * Plain HTTP: only throughput is measured, the router's CPU does not limit it with TLS, and
		 * uclient-fetch stalls on large bodies over TLS. Cloudflare answers 403 above about 50 MB; a
		 * finished download is simply started again.
		 */
		snprintf(t->down, sizeof(t->down), "http://speed.cloudflare.com/__down?bytes=25000000");
		snprintf(t->up, sizeof(t->up), "http://speed.cloudflare.com/__up");
		snprintf(t->host, sizeof(t->host), "speed.cloudflare.com");
		t->port = 80;
		return true;
	}
	const char *p;
	if (!strncasecmp(server, "https://", 8)) {
		p = server + 8;
		t->port = 443;
	} else if (!strncasecmp(server, "http://", 7)) {
		p = server + 7;
		t->port = 80;
	} else {
		return false;
	}
	for (const char *c = server; *c; c++)
		if ((unsigned char)*c <= ' ' || (unsigned char)*c >= 0x7f || *c == '"' || *c == '\'' || *c == '\\')
			return false; /* it ends up on a command line (no shell, but keep it a plain URL) */

	/* host[:port] or [v6]:port, without user info */
	char auth[256];
	size_t alen = strcspn(p, "/?#");
	if (!alen || alen >= sizeof(auth))
		return false;
	memcpy(auth, p, alen);
	auth[alen] = '\0';
	if (strchr(auth, '@'))
		return false;
	char *host = auth, *port = NULL;
	if (auth[0] == '[') {
		char *close = strchr(auth, ']');
		if (!close || (close[1] && close[1] != ':'))
			return false;
		*close = '\0';
		host = auth + 1;
		port = close[1] ? close + 2 : NULL;
	} else if ((port = strchr(auth, ':'))) {
		*port++ = '\0';
	}
	if (!*host || (port && !parse_port(port, &t->port)))
		return false;
	snprintf(t->host, sizeof(t->host), "%s", host);

	/* the base: the URL up to its query, ending in a slash */
	char base[RL_SPEED_URL_LEN];
	size_t blen = strcspn(server, "?#");
	if (blen + 2 > sizeof(base))
		return false;
	memcpy(base, server, blen);
	base[blen] = '\0';
	if (base[blen - 1] != '/')
		strcat(base, "/");
	if ((size_t)snprintf(t->down, sizeof(t->down), "%sgarbage.php?ckSize=100", base) >= sizeof(t->down) ||
	    (size_t)snprintf(t->up, sizeof(t->up), "%sempty.php", base) >= sizeof(t->up))
		return false;
	return true;
}

/* ---- statistics ---- */

static int cmp_double(const void *x, const void *y)
{
	double a = *(const double *)x, b = *(const double *)y;
	return a < b ? -1 : a > b;
}

void rl_speed_stats(const double *ms, int n, double *median, double *jitter)
{
	double *s = malloc((size_t)n * sizeof(double));
	if (!s)
		abort();
	memcpy(s, ms, (size_t)n * sizeof(double));
	qsort(s, (size_t)n, sizeof(double), cmp_double);
	*median = n % 2 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
	free(s);
	double sum = 0;
	for (int i = 1; i < n; i++)
		sum += ms[i] > ms[i - 1] ? ms[i] - ms[i - 1] : ms[i - 1] - ms[i];
	*jitter = n > 1 ? sum / (n - 1) : 0;
}

int64_t rl_speed_rate(const int64_t *t_ms, const uint64_t *bytes, int n, int warmup_ms)
{
	if (n < 2)
		return -1;
	int from = 0;
	while (from < n && t_ms[from] < t_ms[0] + warmup_ms)
		from++;
	if (from == n)
		from = 0; /* shorter than the warm-up: all of it */
	uint64_t sum = 0;
	for (int i = from + 1; i < n; i++)
		if (bytes[i] >= bytes[i - 1])
			sum += bytes[i] - bytes[i - 1];
	int64_t dt = t_ms[n - 1] - t_ms[from];
	return dt > 0 ? (int64_t)(sum * 8000 / (uint64_t)dt) : -1;
}

/* ---- the test process's lines ---- */

void rl_speed_result_init(rl_speed_result *r, int id, int64_t ts, const char *server)
{
	memset(r, 0, sizeof(*r));
	r->id = id;
	r->ts = ts;
	snprintf(r->server, sizeof(r->server), "%s", server ? server : "");
	r->latency_ms = r->jitter_ms = -1;
	r->down_bps = r->up_bps = -1;
}

bool rl_speed_line(const char *line, rl_speed_result *r, rl_speed_phase *phase, double *progress)
{
	char name[16];
	double a, b;
	int64_t v;
	switch (line[0]) {
	case 'P':
		if (sscanf(line, "P %15s %lf", name, &a) != 2)
			return false;
		for (int p = RL_SPEED_LATENCY; p <= RL_SPEED_UPLOAD; p++)
			if (!strcmp(name, PHASES[p])) {
				*phase = (rl_speed_phase)p;
				*progress = a < 0 ? 0 : a > 1 ? 1 : a;
				return true;
			}
		return false;
	case 'L':
		if (sscanf(line, "L %lf %lf", &a, &b) != 2 || a < 0 || b < 0)
			return false;
		r->latency_ms = a;
		r->jitter_ms = b;
		return true;
	case 'D':
	case 'U':
		if (sscanf(line + 1, " %" SCNd64, &v) != 1 || v < 0)
			return false;
		*(line[0] == 'D' ? &r->down_bps : &r->up_bps) = v;
		return true;
	case 'E':
		if (line[1] != ' ' || !line[2])
			return false;
		snprintf(r->error, sizeof(r->error), "%s", line + 2);
		*phase = RL_SPEED_FAILED;
		return true;
	default:
		return false;
	}
}

/* ---- result log ---- */

static double get_double(json_object *e, const char *key)
{
	json_object *v;
	return json_object_object_get_ex(e, key, &v) ? json_object_get_double(v) : -1;
}

static int64_t get_int64(json_object *e, const char *key, int64_t def)
{
	json_object *v;
	return json_object_object_get_ex(e, key, &v) ? json_object_get_int64(v) : def;
}

static const char *get_string(json_object *e, const char *key)
{
	json_object *v;
	return json_object_object_get_ex(e, key, &v) ? json_object_get_string(v) : "";
}

int rl_speed_log_load(rl_speed_log *l, const char *path)
{
	memset(l, 0, sizeof(*l));
	if (access(path, F_OK) != 0)
		return 0;
	json_object *root = json_object_from_file(path), *list, *v;
	int rc = -1;
	if (!root)
		return -1;
	if (!json_object_object_get_ex(root, "version", &v) || json_object_get_int(v) != 1 ||
	    !json_object_object_get_ex(root, "results", &list) || !json_object_is_type(list, json_type_array))
		goto out;
	l->last_id = (int)get_int64(root, "last_id", 0);
	for (size_t i = 0; i < json_object_array_length(list); i++) {
		json_object *e = json_object_array_get_idx(list, i);
		rl_speed_result r;
		rl_speed_result_init(&r, (int)get_int64(e, "id", 0), get_int64(e, "ts", 0), get_string(e, "server"));
		r.latency_ms = get_double(e, "latency_ms");
		r.jitter_ms = get_double(e, "jitter_ms");
		r.down_bps = get_int64(e, "down_bps", -1);
		r.up_bps = get_int64(e, "up_bps", -1);
		snprintf(r.error, sizeof(r.error), "%s", get_string(e, "error"));
		if (r.id > 0)
			rl_speed_log_add(l, &r);
	}
	rc = 0;
out:
	json_object_put(root);
	return rc;
}

int rl_speed_log_save(const rl_speed_log *l, const char *path)
{
	char tmp[512];
	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	json_object *root = json_object_new_object(), *list = json_object_new_array();
	json_object_object_add(root, "version", json_object_new_int(1));
	json_object_object_add(root, "last_id", json_object_new_int(l->last_id));
	for (size_t i = 0; i < l->n; i++) {
		const rl_speed_result *r = &l->items[i];
		json_object *e = json_object_new_object();
		json_object_object_add(e, "id", json_object_new_int(r->id));
		json_object_object_add(e, "ts", json_object_new_int64(r->ts));
		json_object_object_add(e, "server", json_object_new_string(r->server));
		if (r->latency_ms >= 0) {
			json_object_object_add(e, "latency_ms", json_object_new_double(r->latency_ms));
			json_object_object_add(e, "jitter_ms", json_object_new_double(r->jitter_ms));
		}
		if (r->down_bps >= 0)
			json_object_object_add(e, "down_bps", json_object_new_int64(r->down_bps));
		if (r->up_bps >= 0)
			json_object_object_add(e, "up_bps", json_object_new_int64(r->up_bps));
		if (r->error[0])
			json_object_object_add(e, "error", json_object_new_string(r->error));
		json_object_array_add(list, e);
	}
	json_object_object_add(root, "results", list);
	int rc = json_object_to_file_ext(tmp, root, JSON_C_TO_STRING_PLAIN);
	json_object_put(root);
	if (rc != 0)
		return -1;
	FILE *f = fopen(tmp, "r+");
	if (f) {
		fflush(f);
		fsync(fileno(f));
		fclose(f);
	}
	return rename(tmp, path) == 0 ? 0 : -1;
}

void rl_speed_log_add(rl_speed_log *l, const rl_speed_result *r)
{
	if (l->n == RL_SPEED_KEEP) {
		memmove(l->items, l->items + 1, (l->n - 1) * sizeof(rl_speed_result));
		l->n--;
	}
	l->items = rl_grow(l->items, &l->cap, l->n + 1, sizeof(rl_speed_result));
	l->items[l->n++] = *r;
	if (r->id > l->last_id)
		l->last_id = r->id;
}

const rl_speed_result *rl_speed_log_find(const rl_speed_log *l, int id)
{
	for (size_t i = 0; i < l->n; i++)
		if (l->items[i].id == id)
			return &l->items[i];
	return NULL;
}

void rl_speed_log_free(rl_speed_log *l)
{
	free(l->items);
	memset(l, 0, sizeof(*l));
}
