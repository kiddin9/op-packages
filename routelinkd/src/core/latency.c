#include <json-c/json.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "core/latency.h"
#include "core/util.h"

static const rl_tier TIERS[2] = { RL_TIER_MINUTE, RL_TIER_HOUR };
enum { T_MIN, T_HOUR };

/* ---- target table ---- */

void rl_lat_targets_init(rl_lat_targets *t)
{
	memset(t, 0, sizeof(*t));
	t->slot[RL_LAT_GATEWAY].used = true;
}

static int load_file(rl_lat_targets *t, const char *path)
{
	json_object *root = json_object_from_file(path), *list, *v;
	if (!root)
		return -1;
	int rc = -1;
	if (!json_object_object_get_ex(root, "version", &v) || json_object_get_int(v) != 1 ||
	    !json_object_object_get_ex(root, "targets", &list) || !json_object_is_type(list, json_type_array))
		goto out;
	rl_lat_targets_init(t);
	for (size_t i = 0; i < json_object_array_length(list); i++) {
		json_object *e = json_object_array_get_idx(list, i);
		rl_ip ip = { 0 };
		if (!json_object_object_get_ex(e, "id", &v))
			goto bad;
		int id = json_object_get_int(v);
		if (id < 0 || id >= RL_LAT_IDS || !json_object_object_get_ex(e, "ip", &v))
			goto bad;
		const char *s = json_object_get_string(v);
		if (s && *s && !rl_ip_parse(s, &ip))
			goto bad;
		if (id != RL_LAT_GATEWAY && !ip.family)
			goto bad;
		rl_lat_slot *slot = &t->slot[id];
		slot->used = true;
		slot->ip = ip;
		if (json_object_object_get_ex(e, "since", &v))
			slot->since = json_object_get_int64(v);
	}
	rc = 0;
	goto out;
bad:
	rl_lat_targets_init(t);
out:
	json_object_put(root);
	return rc;
}

int rl_lat_targets_load(rl_lat_targets *t, const char *path)
{
	rl_lat_targets_init(t);
	if (access(path, F_OK) != 0)
		return 0;
	return load_file(t, path);
}

int rl_lat_targets_save(const rl_lat_targets *t, const char *path)
{
	char tmp[512], ip[RL_IP_STRLEN];
	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	json_object *root = json_object_new_object(), *list = json_object_new_array();
	json_object_object_add(root, "version", json_object_new_int(1));
	for (int id = 0; id < RL_LAT_IDS; id++) {
		const rl_lat_slot *s = &t->slot[id];
		if (!s->used)
			continue;
		json_object *e = json_object_new_object();
		ip[0] = '\0';
		if (s->ip.family)
			rl_ip_format(&s->ip, ip);
		json_object_object_add(e, "id", json_object_new_int(id));
		json_object_object_add(e, "ip", json_object_new_string(ip));
		json_object_object_add(e, "since", json_object_new_int64(s->since));
		json_object_array_add(list, e);
	}
	json_object_object_add(root, "targets", list);
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

int rl_lat_targets_assign(rl_lat_targets *t, const rl_ip *ip, uint64_t keep, int64_t now, bool *changed)
{
	int free_id = -1, oldest = -1;
	for (int id = 1; id < RL_LAT_IDS; id++) {
		const rl_lat_slot *s = &t->slot[id];
		if (s->used && rl_ip_eq(&s->ip, ip))
			return id;
		if (!s->used && free_id < 0)
			free_id = id;
		if (s->used && !(keep >> id & 1) && (oldest < 0 || s->since < t->slot[oldest].since))
			oldest = id;
	}
	int id = free_id >= 0 ? free_id : oldest;
	if (id < 0)
		return -1;
	t->slot[id] = (rl_lat_slot){ .used = true, .ip = *ip, .since = now };
	*changed = true;
	return id;
}

bool rl_lat_targets_gateway(rl_lat_targets *t, const rl_ip *ip)
{
	rl_lat_slot *s = &t->slot[RL_LAT_GATEWAY];
	if (s->ip.family == ip->family && rl_ip_eq(&s->ip, ip))
		return false;
	s->ip = *ip;
	return true;
}

uint64_t rl_lat_targets_find(const rl_lat_targets *t, const rl_ip *ip)
{
	uint64_t mask = 0;
	for (int id = 0; id < RL_LAT_IDS; id++)
		if (t->slot[id].used && t->slot[id].ip.family && rl_ip_eq(&t->slot[id].ip, ip))
			mask |= 1ULL << id;
	return mask;
}

/* ---- open buckets ---- */

void rl_lat_init(rl_lat *l, rl_lat_rec_cb cb, void *ctx)
{
	memset(l, 0, sizeof(*l));
	l->cb = cb;
	l->ctx = ctx;
}

/* Writes the records of tier t's open bucket and empties it (the bucket stays open). */
static void emit(rl_lat *l, int t)
{
	for (int id = 0; id < RL_LAT_IDS; id++) {
		const rl_probe_agg *a = &l->acc[t][id];
		uint8_t rec[RL_SERIES_REC_SIZE];
		if (!a->sent)
			continue;
		rl_probe_encode(rec, l->start[t], id, a);
		if (l->cb)
			l->cb(TIERS[t], rec, l->ctx);
	}
	memset(l->acc[t], 0, sizeof(l->acc[t]));
}

void rl_lat_add(rl_lat *l, int64_t ts, int id, bool answered, uint32_t rtt_us)
{
	if (id < 0 || id >= RL_LAT_IDS)
		return;
	for (int t = 0; t < 2; t++) {
		int64_t b = rl_bucket_start(TIERS[t], ts);
		if (l->start[t] != b) {
			if (l->start[t])
				emit(l, t);
			l->start[t] = b;
		}
		rl_probe_agg_add(&l->acc[t][id], answered, rtt_us);
	}
}

void rl_lat_tick(rl_lat *l, int64_t now)
{
	for (int t = 0; t < 2; t++) {
		if (!l->start[t] || rl_bucket_next(TIERS[t], l->start[t]) > now)
			continue;
		emit(l, t);
		l->start[t] = 0;
	}
}

void rl_lat_flush(rl_lat *l, bool hour)
{
	for (int t = 0; t < (hour ? 2 : 1); t++)
		if (l->start[t])
			emit(l, t);
}

void rl_lat_reset(rl_lat *l)
{
	memset(l->start, 0, sizeof(l->start));
	memset(l->acc, 0, sizeof(l->acc));
}

/* ---- restart recovery ---- */

typedef struct {
	rl_lat *l;
	rl_series *hour;
	int64_t cur;               /* the current hour */
	int64_t group, group_end;  /* hour being summed */
	rl_probe_agg sum[RL_LAT_IDS];
	bool any;
	int written;
} recover_ctx;

static void recover_group(recover_ctx *c)
{
	if (!c->any)
		return;
	for (int id = 0; id < RL_LAT_IDS; id++) {
		const rl_probe_agg *a = &c->sum[id];
		uint8_t rec[RL_SERIES_REC_SIZE];
		if (!a->sent)
			continue;
		if (c->group < c->cur) {
			/* the hour ended while nothing was recording */
			rl_probe_encode(rec, c->group, id, a);
			if (rl_series_append(c->hour, rec) == 0)
				c->written++;
		} else {
			c->l->start[T_HOUR] = c->group;
			rl_probe_agg_merge(&c->l->acc[T_HOUR][id], a);
		}
	}
	memset(c->sum, 0, sizeof(c->sum));
	c->any = false;
}

static bool recover_cb(const uint8_t *raw, void *x)
{
	recover_ctx *c = x;
	int64_t ts;
	int id;
	rl_probe_agg a;
	rl_probe_decode(raw, &ts, &id, &a);
	if (ts >= c->group_end || ts < c->group) {
		recover_group(c);
		c->group = rl_bucket_start(RL_TIER_HOUR, ts);
		c->group_end = rl_bucket_next(RL_TIER_HOUR, ts);
	}
	if (id < RL_LAT_IDS) {
		rl_probe_agg_merge(&c->sum[id], &a);
		c->any = true;
	}
	return true;
}

int rl_lat_recover(rl_lat *l, rl_series *minute, rl_series *hour, int64_t now)
{
	int64_t oldest = rl_series_oldest(minute);
	if (oldest == INT64_MAX)
		return 0;
	/* start after the newest hour record, but not before the minute data begins */
	int64_t from = rl_bucket_start(RL_TIER_HOUR, oldest);
	int64_t newest = rl_series_newest(hour);
	if (newest != INT64_MIN && rl_bucket_next(RL_TIER_HOUR, newest) > from)
		from = rl_bucket_next(RL_TIER_HOUR, newest);
	recover_ctx c = { .l = l, .hour = hour, .cur = rl_bucket_start(RL_TIER_HOUR, now) };
	rl_series_scan(minute, from, rl_bucket_next(RL_TIER_HOUR, now), recover_cb, &c);
	recover_group(&c);
	return c.written;
}

/* ---- latency query ---- */

/*
 * Whether a record of id for the bucket [ts, ts + sec) counts: a known target, and not from before its id was
 * reused (the bucket in which that happened counts).
 */
static bool counts(const rl_lat_targets *t, int id, int64_t ts, int64_t sec)
{
	return id >= 0 && id < RL_LAT_IDS && t->slot[id].used && ts + sec > t->slot[id].since;
}

typedef struct {
	const rl_latq_ctx *c;
	rl_lat_history *h;
	uint64_t want;
	rl_probe_agg *rows[RL_LAT_IDS]; /* by id, allocated on first use */
} grid_ctx;

static rl_probe_agg *row_of(grid_ctx *g, int id)
{
	if (!g->rows[id]) {
		g->rows[id] = calloc(g->h->n ? g->h->n : 1, sizeof(rl_probe_agg));
		if (!g->rows[id])
			abort();
	}
	return g->rows[id];
}

static void grid_add(grid_ctx *g, int64_t ts, int id, const rl_probe_agg *a)
{
	rl_lat_history *h = g->h;
	if (!counts(g->c->targets, id, ts, rl_tier_seconds(h->tier)) || !(g->want >> id & 1) || ts < h->first ||
	    !a->sent)
		return;
	size_t i = (size_t)((ts - h->first) / h->step);
	if (i >= h->n)
		return;
	rl_probe_agg_merge(&row_of(g, id)[i], a);
}

static bool grid_cb(const uint8_t *raw, void *x)
{
	int64_t ts;
	int id;
	rl_probe_agg a;
	rl_probe_decode(raw, &ts, &id, &a);
	grid_add(x, ts, id, &a);
	return true;
}

/* The tier a range starting at start reads: minutes within their retention, else hours. */
static int tier_for(const rl_latq_ctx *c, int64_t start)
{
	return start >= c->now - (int64_t)c->minute_days * 86400 - 60 ? T_MIN : T_HOUR;
}

int rl_lat_query(const rl_latq_ctx *c, int64_t start, int64_t end, int max_points, uint64_t want, uint64_t always,
		 rl_lat_history *out)
{
	memset(out, 0, sizeof(*out));
	if (!max_points)
		max_points = RL_LATQ_DEFAULT_POINTS;
	if (!rl_range_ok(start, end, RL_LATQ_MAX_RANGE) || max_points < 1 || max_points > RL_LATQ_MAX_POINTS)
		return -1;
	int t = tier_for(c, start);
	rl_series *s = t == T_MIN ? c->minute : c->hour;
	int64_t limit = rl_bucket_next(RL_TIER_MINUTE, c->now); /* include the open bucket */
	if (end > limit)
		end = limit;
	int64_t sec = rl_tier_seconds(TIERS[t]);
	out->tier = TIERS[t];
	out->first = rl_bucket_start(TIERS[t], start);
	int64_t buckets = end > out->first ? (end - out->first + sec - 1) / sec : 0;
	int64_t k = (buckets + max_points - 1) / max_points;
	if (k < 1)
		k = 1;
	out->step = sec * k;
	out->n = (size_t)((buckets + k - 1) / k);

	grid_ctx g = { .c = c, .h = out, .want = want };
	if (out->n) {
		if (s)
			rl_series_scan(s, out->first, out->first + (int64_t)out->n * out->step, grid_cb, &g);
		if (c->open && c->open->start[t])
			for (int id = 0; id < RL_LAT_IDS; id++)
				grid_add(&g, c->open->start[t], id, &c->open->acc[t][id]);
	}
	for (int id = 0; id < RL_LAT_IDS; id++) {
		if (!(want >> id & 1) || (!g.rows[id] && !(always >> id & 1 && c->targets->slot[id].used)))
			continue;
		int i = out->n_ids++;
		out->ids[i] = (uint8_t)id;
		out->pts[i] = row_of(&g, id);
		for (size_t p = 0; p < out->n; p++)
			rl_probe_agg_merge(&out->sum[i], &out->pts[i][p]);
	}
	return 0;
}

void rl_lat_history_free(rl_lat_history *h)
{
	for (int i = 0; i < h->n_ids; i++)
		free(h->pts[i]);
	memset(h, 0, sizeof(*h));
}

/* ---- outages ---- */

typedef struct {
	rl_outage_list *l;
	size_t cap;
	int64_t start, to; /* the range, its end clipped to now */
} outage_ctx;

static void outage_add(outage_ctx *o, int64_t s, int64_t e, rl_outage_cause cause, bool ongoing)
{
	if (e <= o->start || e < s)
		return;
	o->l->count++;
	int64_t a = RL_MAX(s, o->start), b = RL_MIN(e, o->to);
	if (b > a)
		o->l->total_sec += b - a;
	o->l->items = rl_grow(o->l->items, &o->cap, o->l->n + 1, sizeof(rl_outage_item));
	o->l->items[o->l->n++] = (rl_outage_item){ .start = s, .end = e, .cause = cause, .ongoing = ongoing };
}

static bool outage_cb(const uint8_t *raw, void *x)
{
	int64_t s, e;
	rl_outage_cause cause;
	rl_outage_decode(raw, &s, &e, &cause);
	outage_add(x, s, e, cause, false);
	return true;
}

/*
 * Probed time: per bucket, the rounds that reached a custom target (its sent count, summed over the records
 * of the bucket) times the round interval, at most the bucket's length.
 */
typedef struct {
	const rl_latq_ctx *c;
	int64_t sec, bucket, from, to, probed;
	uint32_t sent[RL_LAT_IDS];
} probed_ctx;

static void probed_close(probed_ctx *p)
{
	uint32_t rounds = 0;
	for (int id = 0; id < RL_LAT_IDS; id++)
		if (id != RL_LAT_GATEWAY && p->sent[id] > rounds)
			rounds = p->sent[id];
	if (p->bucket >= p->from && p->bucket < p->to)
		p->probed += RL_MIN((int64_t)rounds * RL_LAT_INTERVAL, p->sec);
	memset(p->sent, 0, sizeof(p->sent));
}

static void probed_add(probed_ctx *p, int64_t ts, int id, uint32_t sent)
{
	if (!counts(p->c->targets, id, ts, p->sec) || !sent)
		return;
	if (ts != p->bucket) {
		probed_close(p);
		p->bucket = ts;
	}
	p->sent[id] += sent;
}

static bool probed_cb(const uint8_t *raw, void *x)
{
	int64_t ts;
	int id;
	rl_probe_agg a;
	rl_probe_decode(raw, &ts, &id, &a);
	probed_add(x, ts, id, a.sent);
	return true;
}

static int64_t probed_seconds(const rl_latq_ctx *c, int64_t start, int64_t to)
{
	if (to <= start)
		return 0;
	int t = tier_for(c, start);
	rl_series *s = t == T_MIN ? c->minute : c->hour;
	probed_ctx p = { .c = c, .sec = rl_tier_seconds(TIERS[t]), .from = rl_bucket_start(TIERS[t], start), .to = to };
	p.bucket = p.from;
	if (s)
		rl_series_scan(s, p.from, to, probed_cb, &p);
	if (c->open && c->open->start[t] && c->open->start[t] < to)
		for (int id = 0; id < RL_LAT_IDS; id++)
			probed_add(&p, c->open->start[t], id, c->open->acc[t][id].sent);
	probed_close(&p);
	return RL_MIN(p.probed, to - start);
}

int rl_outage_query(const rl_latq_ctx *c, const rl_outage *state, int64_t start, int64_t end, rl_outage_list *out)
{
	memset(out, 0, sizeof(*out));
	if (!rl_range_ok(start, end, RL_LATQ_MAX_RANGE))
		return -1;
	outage_ctx o = { .l = out, .start = start, .to = RL_MIN(end, c->now) };
	if (c->outages)
		rl_series_scan(c->outages, 0, end, outage_cb, &o);
	if (state && state->down && state->start < end)
		outage_add(&o, state->start, c->now, rl_outage_cause_at(state, c->now), true);
	/* newest first, at most RL_OUTAGEQ_MAX_ITEMS */
	for (size_t i = 0; i < out->n / 2; i++) {
		rl_outage_item tmp = out->items[i];
		out->items[i] = out->items[out->n - 1 - i];
		out->items[out->n - 1 - i] = tmp;
	}
	if (out->n > RL_OUTAGEQ_MAX_ITEMS)
		out->n = RL_OUTAGEQ_MAX_ITEMS;
	out->probed_sec = probed_seconds(c, start, o.to);
	return 0;
}

void rl_outage_list_free(rl_outage_list *l)
{
	free(l->items);
	memset(l, 0, sizeof(*l));
}

double rl_outage_availability(const rl_outage_list *l)
{
	if (l->probed_sec <= 0)
		return -1;
	int64_t up = l->probed_sec - RL_MIN(l->total_sec, l->probed_sec);
	int64_t hundredths = (up * 20000 + l->probed_sec) / (2 * l->probed_sec); /* rounded */
	return (double)hundredths / 100.0;
}
