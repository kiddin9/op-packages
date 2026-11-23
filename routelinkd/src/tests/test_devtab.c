#include <stdlib.h>

#include "t.h"

#include "core/devtab.h"

static rl_mac mac(const char *s)
{
	rl_mac m;
	rl_mac_parse(s, &m);
	return m;
}

static void indexes(void)
{
	rl_devtab *t = rl_devtab_new();
	bool created;
	rl_mac a = mac("AA:00:00:00:00:01"), b = mac("AA:00:00:00:00:02");
	rl_device *d = rl_devtab_get(t, &a, 100, &created);
	T_ASSERT(created);
	T_EQ_I64(d->idx, 0);
	d = rl_devtab_get(t, &b, 100, &created);
	T_EQ_I64(d->idx, 1);
	d = rl_devtab_get(t, &a, 200, &created);
	T_ASSERT(!created);
	T_EQ_I64(d->idx, 0);
	T_ASSERT(rl_devtab_by_idx(t, 1) && rl_mac_eq(&rl_devtab_by_idx(t, 1)->mac, &b));
	T_ASSERT(rl_devtab_by_idx(t, 2) == NULL);
	/* many devices: the map grows */
	for (int i = 0; i < 1000; i++) {
		char s[18];
		snprintf(s, sizeof(s), "BB:00:00:00:%02X:%02X", i >> 8, i & 0xff);
		rl_mac m = mac(s);
		rl_devtab_get(t, &m, 1, &created);
	}
	T_EQ_U64(rl_devtab_count(t), 1002);
	rl_mac m = mac("BB:00:00:00:03:E7");
	T_EQ_I64(rl_devtab_find(t, &m)->idx, 1001);
	rl_devtab_free(t);
}

static void save_load(void)
{
	char dir[] = "/tmp/rl-devtab-XXXXXX", path[128];
	if (!mkdtemp(dir))
		abort();
	snprintf(path, sizeof(path), "%s/devices.json", dir);
	rl_devtab *t = rl_devtab_new();
	bool created;
	rl_mac a = mac("AA:00:00:00:00:01"), b = mac("02:00:00:00:00:02");
	rl_devtab_get(t, &a, 100, &created);
	rl_device *d = rl_devtab_get(t, &b, 150, &created);
	rl_devtab_touch(d, 900);
	T_EQ_I64(rl_devtab_save(t, path), 0);
	T_EQ_I64(rl_devtab_save(t, path), 0); /* second save keeps a .bak */
	rl_devtab_free(t);

	t = rl_devtab_new();
	T_EQ_I64(rl_devtab_load(t, path), 0);
	T_EQ_U64(rl_devtab_count(t), 2);
	d = rl_devtab_find(t, &b);
	T_ASSERT(d != NULL);
	if (d) {
		T_EQ_I64(d->idx, 1);
		T_EQ_I64(d->first_seen, 150);
		T_EQ_I64(d->last_seen, 900);
	}
	rl_devtab_free(t);

	/* damaged main file: the backup is used */
	FILE *f = fopen(path, "w");
	fputs("{\"version\":1,\"devices\":[{\"idx\":5", f);
	fclose(f);
	t = rl_devtab_new();
	T_EQ_I64(rl_devtab_load(t, path), 0);
	T_EQ_U64(rl_devtab_count(t), 2);
	rl_devtab_free(t);

	/* both damaged: empty table, error reported */
	char bak[160];
	snprintf(bak, sizeof(bak), "%s.bak", path);
	f = fopen(bak, "w");
	fputs("garbage", f);
	fclose(f);
	t = rl_devtab_new();
	T_EQ_I64(rl_devtab_load(t, path), -1);
	T_EQ_U64(rl_devtab_count(t), 0);
	rl_devtab_free(t);

	/* nothing on disk yet */
	t = rl_devtab_new();
	snprintf(path, sizeof(path), "%s/missing.json", dir);
	T_EQ_I64(rl_devtab_load(t, path), 0);
	rl_devtab_free(t);
}

static int changes;
static bool last_state;

static void on_change(rl_device *d, bool online, void *ctx)
{
	(void)d;
	(void)ctx;
	changes++;
	last_state = online;
}

static void presence(void)
{
	rl_devtab *t = rl_devtab_new();
	bool created;
	rl_mac a = mac("AA:00:00:00:00:01");
	rl_device *d = rl_devtab_get(t, &a, 1000, &created);
	rl_devtab_presence(t, 1000, on_change, NULL);
	T_EQ_I64(changes, 0); /* never active yet */
	rl_devtab_touch(d, 1000);
	rl_devtab_presence(t, 1000, on_change, NULL);
	T_EQ_I64(changes, 1);
	T_ASSERT(last_state);
	rl_devtab_presence(t, 1179, on_change, NULL);
	T_EQ_I64(changes, 1);
	rl_devtab_presence(t, 1181, on_change, NULL);
	T_EQ_I64(changes, 2);
	T_ASSERT(!last_state);
	rl_devtab_presence(t, 1300, on_change, NULL);
	T_EQ_I64(changes, 2);
	rl_devtab_touch(d, 1400);
	rl_devtab_presence(t, 1400, on_change, NULL);
	T_EQ_I64(changes, 3);
	T_ASSERT(last_state);
	rl_devtab_free(t);
}

int main(void)
{
	T_RUN(indexes);
	T_RUN(save_load);
	T_RUN(presence);
	T_DONE();
}
