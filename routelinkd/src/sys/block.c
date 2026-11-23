#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>

#include "sys/block.h"
#include "sys/proc.h"

#define NFT_TIMEOUT_MS 5000

struct rl_block {
	rl_mac *macs; /* as loaded */
	size_t n, cap;
	rl_nft_net local[RL_BLOCK_MAX_NETS];
	size_t n_local;
	bool loaded; /* the table matches macs/local */
	bool dirty;  /* a table of ours may exist */
	char error[200];
};

static int cmp_mac(const void *a, const void *b)
{
	return memcmp(a, b, sizeof(rl_mac));
}

static int load(rl_block *b)
{
	size_t size = 1024 + b->n * 24 + b->n_local * 64;
	char *script = malloc(size), out[512], line[160];
	uint8_t(*macs)[6] = malloc((b->n ? b->n : 1) * 6);
	if (!script || !macs)
		abort();
	for (size_t i = 0; i < b->n; i++)
		memcpy(macs[i], b->macs[i].b, 6);
	size_t len = rl_nft_script(script, size, (const uint8_t(*)[6])macs, b->n, b->local, b->n_local);
	free(macs);
	if (len == (size_t)-1) {
		free(script);
		snprintf(b->error, sizeof(b->error), "nft script too long");
		return -1;
	}
	const char *argv[] = { "nft", "-f", "-", NULL };
	int rc = rl_proc_run(argv, script, len, out, sizeof(out), NFT_TIMEOUT_MS);
	free(script);
	b->dirty = true;
	if (rc == 0) {
		b->loaded = true;
		b->error[0] = '\0';
		if (!b->n)
			b->dirty = false; /* the script only deleted the table */
		return 0;
	}
	b->loaded = false;
	if (rc == 127)
		snprintf(line, sizeof(line), "nft is not installed");
	else if (rc < 0)
		snprintf(line, sizeof(line), "nft did not finish");
	else
		rl_proc_first_line(out, line, sizeof(line));
	snprintf(b->error, sizeof(b->error), "blocking: %s", line[0] ? line : "nft failed");
	syslog(LOG_ERR, "loading the nftables table inet " RL_NFT_TABLE " failed: %s", line[0] ? line : "nft failed");
	return -1;
}

rl_block *rl_block_new(void)
{
	rl_block *b = calloc(1, sizeof(*b));
	if (!b)
		abort();
	b->dirty = true; /* left behind by a daemon that crashed: the first set replaces it */
	return b;
}

void rl_block_free(rl_block *b, bool clear)
{
	if (!b)
		return;
	if (clear && b->dirty) {
		b->n = 0;
		load(b);
	}
	free(b->macs);
	free(b);
}

int rl_block_set(rl_block *b, const rl_mac *macs, size_t n, const rl_nft_net *local, size_t n_local)
{
	rl_mac *sorted = malloc((n ? n : 1) * sizeof(rl_mac));
	if (!sorted)
		abort();
	memcpy(sorted, macs, n * sizeof(rl_mac));
	qsort(sorted, n, sizeof(rl_mac), cmp_mac);
	if (n_local > RL_BLOCK_MAX_NETS)
		n_local = RL_BLOCK_MAX_NETS;
	bool same = n == b->n && (!n || !memcmp(sorted, b->macs, n * sizeof(rl_mac))) &&
		    (!n || (n_local == b->n_local && !memcmp(local, b->local, n_local * sizeof(rl_nft_net))));
	/* unchanged: loaded, or failed (not retried every minute) */
	if ((same && (b->loaded || b->error[0])) || (!n && !b->n && !b->dirty)) {
		free(sorted);
		return b->error[0] ? -1 : 0;
	}
	free(b->macs);
	b->macs = sorted;
	b->n = b->cap = n;
	memcpy(b->local, local, n_local * sizeof(rl_nft_net));
	b->n_local = n_local;
	return load(b);
}

bool rl_block_has(const rl_block *b, const rl_mac *mac)
{
	return b->loaded && bsearch(mac, b->macs, b->n, sizeof(rl_mac), cmp_mac) != NULL;
}

void rl_block_retry(rl_block *b)
{
	b->error[0] = '\0';
	b->loaded = false;
}

void rl_block_check(rl_block *b)
{
	if (!b->n || b->error[0])
		return;
	if (b->loaded) {
		char out[256];
		const char *argv[] = { "nft", "list", "table", "inet", RL_NFT_TABLE, NULL };
		if (rl_proc_run(argv, NULL, 0, out, sizeof(out), NFT_TIMEOUT_MS) == 0)
			return;
		syslog(LOG_NOTICE, "the nftables table inet " RL_NFT_TABLE " went missing, loading it again");
	}
	load(b);
}

const char *rl_block_error(const rl_block *b)
{
	return b->error;
}
