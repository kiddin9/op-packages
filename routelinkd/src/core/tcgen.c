#include "core/tcgen.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

typedef struct {
	char *buf;
	size_t size, len;
	bool overflow;
} out_t;

static void line(out_t *o, const char *fmt, ...)
{
	if (o->overflow)
		return;
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(o->buf + o->len, o->size - o->len, fmt, ap);
	va_end(ap);
	if (n < 0 || (size_t)n + 1 >= o->size - o->len) {
		o->overflow = true;
		return;
	}
	o->len += (size_t)n;
	o->buf[o->len++] = '\n';
	o->buf[o->len] = '\0';
}

#define MAC "%02x:%02x:%02x:%02x:%02x:%02x"
#define MACV(m) (m)[0], (m)[1], (m)[2], (m)[3], (m)[4], (m)[5]

size_t rl_tc_clear_script(char *buf, size_t size, const char *dev)
{
	out_t o = { buf, size, 0, false };
	if (size)
		buf[0] = '\0';
	line(&o, "qdisc del dev %s root handle " RL_TC_HANDLE " htb", dev);
	line(&o, "qdisc del dev %s clsact", dev);
	return o.overflow ? (size_t)-1 : o.len;
}

/* HTB with an unlimited default class and one class per rule that limits (rate taken by pick), by MAC. */
static void htb(out_t *o, const char *dev, const rl_tc_rule *rules, size_t n, bool upload)
{
	line(o, "qdisc add dev %s root handle " RL_TC_HANDLE " htb default 1", dev);
	line(o, "class add dev %s parent " RL_TC_HANDLE " classid 1:1 htb rate 10gbit quantum 1514", dev);
	unsigned cls = RL_TC_FIRST_CLASS;
	for (size_t i = 0; i < n; i++, cls++) {
		uint32_t kbps = upload ? rules[i].up_kbps : rules[i].down_kbps;
		if (!kbps)
			continue;
		line(o, "class add dev %s parent " RL_TC_HANDLE " classid 1:%u htb rate %ukbit ceil %ukbit quantum 1514", dev,
		     cls, kbps, kbps);
		line(o, "filter add dev %s parent " RL_TC_HANDLE " protocol all prio 1 flower %s " MAC " classid 1:%u", dev,
		     upload ? "src_mac" : "dst_mac", MACV(rules[i].mac), cls);
	}
}

size_t rl_tc_script(char *buf, size_t size, const char *dev, const char *ifb, const rl_tc_rule *rules, size_t n)
{
	out_t o = { buf, size, 0, false };
	if (size)
		buf[0] = '\0';
	bool down = false, up = false;
	for (size_t i = 0; i < n; i++) {
		down |= rules[i].down_kbps > 0;
		up |= ifb && rules[i].up_kbps > 0;
	}
	if (down)
		htb(&o, dev, rules, n, false);
	if (up) {
		line(&o, "qdisc add dev %s clsact", dev);
		for (size_t i = 0; i < n; i++)
			if (rules[i].up_kbps)
				line(&o, "filter add dev %s ingress protocol all prio 1 flower src_mac " MAC
					 " action mirred egress redirect dev %s",
				     dev, MACV(rules[i].mac), ifb);
	}
	return o.overflow ? (size_t)-1 : o.len;
}

size_t rl_tc_ifb_script(char *buf, size_t size, const char *ifb, const rl_tc_rule *rules, size_t n)
{
	out_t o = { buf, size, 0, false };
	if (size)
		buf[0] = '\0';
	bool up = false;
	for (size_t i = 0; i < n; i++)
		up |= rules[i].up_kbps > 0;
	if (up)
		htb(&o, ifb, rules, n, true);
	return o.overflow ? (size_t)-1 : o.len;
}
