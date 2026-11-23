#include "core/nftgen.h"

#include <arpa/inet.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

typedef struct {
	char *buf;
	size_t size, len;
	bool overflow;
} out_t;

static void add(out_t *o, const char *fmt, ...)
{
	if (o->overflow)
		return;
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(o->buf + o->len, o->size - o->len, fmt, ap);
	va_end(ap);
	if (n < 0 || (size_t)n >= o->size - o->len) {
		o->overflow = true;
		return;
	}
	o->len += (size_t)n;
}

static void nets(out_t *o, const rl_nft_net *local, size_t n, uint8_t family)
{
	bool first = true;
	for (size_t i = 0; i < n; i++) {
		if (local[i].family != family)
			continue;
		char ip[INET6_ADDRSTRLEN];
		inet_ntop(family == 6 ? AF_INET6 : AF_INET, local[i].addr, ip, sizeof(ip));
		add(o, "%s%s/%u", first ? "" : ", ", ip, local[i].prefix);
		first = false;
	}
}

static bool has(const rl_nft_net *local, size_t n, uint8_t family)
{
	for (size_t i = 0; i < n; i++)
		if (local[i].family == family)
			return true;
	return false;
}

size_t rl_nft_script(char *buf, size_t size, const uint8_t (*block)[6], size_t n_block, const rl_nft_net *local,
		     size_t n_local)
{
	out_t o = { buf, size, 0, false };
	if (size)
		buf[0] = '\0';
	/* "add table" first makes the delete succeed when the table does not exist yet. */
	add(&o, "add table inet " RL_NFT_TABLE "\ndelete table inet " RL_NFT_TABLE "\n");
	if (n_block) {
		add(&o, "table inet " RL_NFT_TABLE " {\n");
		add(&o, "\tset block {\n\t\ttype ether_addr\n\t\telements = { ");
		for (size_t i = 0; i < n_block; i++)
			add(&o, "%s%02x:%02x:%02x:%02x:%02x:%02x", i ? ", " : "", block[i][0], block[i][1], block[i][2],
			    block[i][3], block[i][4], block[i][5]);
		add(&o, " }\n\t}\n");
		add(&o, "\tset local4 {\n\t\ttype ipv4_addr\n\t\tflags interval\n");
		if (has(local, n_local, 4)) {
			add(&o, "\t\telements = { ");
			nets(&o, local, n_local, 4);
			add(&o, " }\n");
		}
		add(&o, "\t}\n\tset local6 {\n\t\ttype ipv6_addr\n\t\tflags interval\n");
		if (has(local, n_local, 6)) {
			add(&o, "\t\telements = { ");
			nets(&o, local, n_local, 6);
			add(&o, " }\n");
		}
		add(&o, "\t}\n");
		/* Just before fw4's forward chain (priority filter = 0). */
		add(&o, "\tchain forward {\n\t\ttype filter hook forward priority filter - 1; policy accept;\n");
		add(&o, "\t\tether saddr @block ip daddr != @local4 counter drop\n");
		add(&o, "\t\tether saddr @block ip6 daddr != @local6 counter drop\n");
		add(&o, "\t}\n}\n");
	}
	return o.overflow ? (size_t)-1 : o.len;
}
