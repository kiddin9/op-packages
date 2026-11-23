#include <json-c/json.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "core/devtab.h"
#include "core/rec.h"
#include "core/util.h"

struct rl_devtab {
	rl_device *devs; /* position == idx */
	size_t n, cap;
	uint32_t *map; /* open addressing: device position + 1, 0 = empty */
	size_t map_cap;
};

rl_devtab *rl_devtab_new(void)
{
	rl_devtab *t = calloc(1, sizeof(*t));
	if (!t)
		abort();
	return t;
}

void rl_devtab_free(rl_devtab *t)
{
	if (!t)
		return;
	free(t->devs);
	free(t->map);
	free(t);
}

static void map_put(uint32_t *map, size_t cap, const rl_device *devs, uint32_t pos)
{
	size_t mask = cap - 1;
	size_t i = rl_mac_hash(&devs[pos].mac) & mask;
	while (map[i])
		i = (i + 1) & mask;
	map[i] = pos + 1;
}

static void map_rebuild(rl_devtab *t, size_t cap)
{
	free(t->map);
	t->map = calloc(cap, sizeof(uint32_t));
	if (!t->map)
		abort();
	t->map_cap = cap;
	for (size_t i = 0; i < t->n; i++)
		map_put(t->map, cap, t->devs, (uint32_t)i);
}

rl_device *rl_devtab_find(rl_devtab *t, const rl_mac *mac)
{
	if (!t->map_cap)
		return NULL;
	size_t mask = t->map_cap - 1;
	for (size_t i = rl_mac_hash(mac) & mask; t->map[i]; i = (i + 1) & mask)
		if (rl_mac_eq(&t->devs[t->map[i] - 1].mac, mac))
			return &t->devs[t->map[i] - 1];
	return NULL;
}

static rl_device *append(rl_devtab *t, const rl_mac *mac)
{
	if (t->n > RL_DEV_MAX)
		return NULL;
	t->devs = rl_grow(t->devs, &t->cap, t->n + 1, sizeof(rl_device));
	rl_device *d = &t->devs[t->n];
	memset(d, 0, sizeof(*d));
	d->mac = *mac;
	d->idx = (uint16_t)t->n;
	t->n++;
	if (t->n * 2 > t->map_cap)
		map_rebuild(t, t->map_cap ? t->map_cap * 2 : 64);
	else
		map_put(t->map, t->map_cap, t->devs, d->idx);
	return d;
}

rl_device *rl_devtab_get(rl_devtab *t, const rl_mac *mac, int64_t now, bool *created)
{
	*created = false;
	rl_device *d = rl_devtab_find(t, mac);
	if (d)
		return d;
	d = append(t, mac);
	if (!d)
		return NULL;
	d->first_seen = d->last_seen = now;
	*created = true;
	return d;
}

rl_device *rl_devtab_by_idx(rl_devtab *t, uint16_t idx)
{
	return idx < t->n ? &t->devs[idx] : NULL;
}

size_t rl_devtab_count(const rl_devtab *t)
{
	return t->n;
}

rl_device *rl_devtab_at(rl_devtab *t, size_t i)
{
	return i < t->n ? &t->devs[i] : NULL;
}

void rl_devtab_touch(rl_device *d, int64_t now)
{
	if (now > d->last_active)
		d->last_active = now;
	if (now > d->last_seen)
		d->last_seen = now;
}

void rl_devtab_presence(rl_devtab *t, int64_t now, void (*cb)(rl_device *, bool, void *), void *ctx)
{
	for (size_t i = 0; i < t->n; i++) {
		rl_device *d = &t->devs[i];
		bool online = d->last_active && now - d->last_active <= RL_OFFLINE_AFTER;
		if (online == d->online)
			continue;
		d->online = online;
		if (cb)
			cb(d, online, ctx);
	}
}

void rl_devtab_clear(rl_devtab *t)
{
	t->n = 0;
	if (t->map)
		memset(t->map, 0, t->map_cap * sizeof(uint32_t));
}

static int load_file(rl_devtab *t, const char *path)
{
	json_object *root = json_object_from_file(path);
	json_object *list, *version;
	if (!root)
		return -1;
	int rc = -1;
	if (!json_object_object_get_ex(root, "version", &version) || json_object_get_int(version) != 1 ||
	    !json_object_object_get_ex(root, "devices", &list) || !json_object_is_type(list, json_type_array))
		goto out;
	rl_devtab_clear(t);
	size_t n = json_object_array_length(list);
	for (size_t i = 0; i < n; i++) {
		json_object *e = json_object_array_get_idx(list, i), *v;
		rl_mac mac;
		if (!json_object_object_get_ex(e, "idx", &v) || (size_t)json_object_get_int(v) != i ||
		    !json_object_object_get_ex(e, "mac", &v) || !rl_mac_parse(json_object_get_string(v), &mac) ||
		    rl_devtab_find(t, &mac)) {
			rl_devtab_clear(t);
			goto out;
		}
		rl_device *d = append(t, &mac);
		if (json_object_object_get_ex(e, "first", &v))
			d->first_seen = json_object_get_int64(v);
		if (json_object_object_get_ex(e, "last", &v))
			d->last_seen = json_object_get_int64(v);
	}
	rc = 0;
out:
	json_object_put(root);
	return rc;
}

int rl_devtab_load(rl_devtab *t, const char *path)
{
	char bak[512];
	snprintf(bak, sizeof(bak), "%s.bak", path);
	bool have_main = access(path, F_OK) == 0, have_bak = access(bak, F_OK) == 0;
	if (have_main && load_file(t, path) == 0)
		return 0;
	if (have_bak && load_file(t, bak) == 0)
		return 0;
	rl_devtab_clear(t);
	return have_main || have_bak ? -1 : 0;
}

int rl_devtab_save(const rl_devtab *t, const char *path)
{
	char tmp[512], bak[512], mac[RL_MAC_STRLEN];
	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	snprintf(bak, sizeof(bak), "%s.bak", path);
	json_object *root = json_object_new_object(), *list = json_object_new_array();
	json_object_object_add(root, "version", json_object_new_int(1));
	for (size_t i = 0; i < t->n; i++) {
		json_object *e = json_object_new_object();
		rl_mac_format(&t->devs[i].mac, mac);
		json_object_object_add(e, "idx", json_object_new_int((int)i));
		json_object_object_add(e, "mac", json_object_new_string(mac));
		json_object_object_add(e, "first", json_object_new_int64(t->devs[i].first_seen));
		json_object_object_add(e, "last", json_object_new_int64(t->devs[i].last_seen));
		json_object_array_add(list, e);
	}
	json_object_object_add(root, "devices", list);
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
	if (access(path, F_OK) == 0)
		rename(path, bak);
	return rename(tmp, path) == 0 ? 0 : -1;
}
