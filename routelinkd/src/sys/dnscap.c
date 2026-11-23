#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <linux/filter.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/uloop.h>

#include "sys/dnscap.h"

#define BUF_SIZE 65536

typedef struct {
	struct uloop_fd fd;
	int ifindex;
	struct rl_dnscap *owner;
} cap_sock;

struct rl_dnscap {
	cap_sock socks[RL_DNSCAP_MAX_IFACES];
	int n;
	rl_dnscap_cb cb;
	void *ctx;
	uint8_t *buf;
	uint64_t answers, bad;
	bool failed_logged;
};

/*
 * Outgoing IPv4/IPv6 packets with UDP or TCP source port 53 (first fragments only; IPv6 without extension
 * headers). Offsets are from the Ethernet header.
 */
static struct sock_filter dns_filter[] = {
	/* 0 */ BPF_STMT(BPF_LD | BPF_W | BPF_ABS, SKF_AD_OFF + SKF_AD_PKTTYPE),
	/* 1 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, PACKET_OUTGOING, 0, 17),
	/* 2 */ BPF_STMT(BPF_LD | BPF_H | BPF_ABS, 12),
	/* 3 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, ETH_P_IP, 1, 0),
	/* 4 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, ETH_P_IPV6, 8, 14),
	/* 5 */ BPF_STMT(BPF_LD | BPF_B | BPF_ABS, 23),
	/* 6 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, IPPROTO_UDP, 1, 0),
	/* 7 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, IPPROTO_TCP, 0, 11),
	/* 8 */ BPF_STMT(BPF_LD | BPF_H | BPF_ABS, 20),
	/* 9 */ BPF_JUMP(BPF_JMP | BPF_JSET | BPF_K, 0x1fff, 9, 0),
	/* 10 */ BPF_STMT(BPF_LDX | BPF_B | BPF_MSH, 14),
	/* 11 */ BPF_STMT(BPF_LD | BPF_H | BPF_IND, 14),
	/* 12 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 53, 5, 6),
	/* 13 */ BPF_STMT(BPF_LD | BPF_B | BPF_ABS, 20),
	/* 14 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, IPPROTO_UDP, 1, 0),
	/* 15 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, IPPROTO_TCP, 0, 3),
	/* 16 */ BPF_STMT(BPF_LD | BPF_H | BPF_ABS, 54),
	/* 17 */ BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 53, 0, 1),
	/* 18 */ BPF_STMT(BPF_RET | BPF_K, 0xffff),
	/* 19 */ BPF_STMT(BPF_RET | BPF_K, 0),
};

static uint16_t be16(const uint8_t *p)
{
	return (uint16_t)(p[0] << 8 | p[1]);
}

static void deliver(rl_dnscap *c, const uint8_t *mac, const uint8_t *p, size_t len)
{
	rl_dns_msg m;
	if (rl_dns_parse(p, len, &m) == 0 && m.response) {
		c->answers++;
		c->cb(mac, &m, c->ctx);
	} else {
		c->bad++;
	}
}

/* A captured frame: Ethernet, IPv4/IPv6, UDP or TCP from port 53. */
static void handle(rl_dnscap *c, const uint8_t *f, size_t len)
{
	if (len < 14)
		return;
	const uint8_t *mac = f; /* destination: the device that asked */
	uint16_t type = be16(f + 12);
	const uint8_t *ip = f + 14, *l4;
	size_t iplen = len - 14, l4len;
	uint8_t proto;
	if (type == ETH_P_IP) {
		if (iplen < 20)
			return;
		size_t ihl = (size_t)(ip[0] & 0xf) * 4, total = be16(ip + 2);
		if (ihl < 20 || total < ihl || total > iplen)
			return;
		proto = ip[9];
		l4 = ip + ihl;
		l4len = total - ihl;
	} else if (type == ETH_P_IPV6) {
		if (iplen < 40)
			return;
		size_t plen = be16(ip + 4);
		if (40 + plen > iplen)
			return;
		proto = ip[6];
		l4 = ip + 40;
		l4len = plen;
	} else {
		return;
	}
	if (proto == IPPROTO_UDP) {
		if (l4len < 8 || be16(l4) != 53)
			return;
		size_t ulen = be16(l4 + 4);
		if (ulen < 8 || ulen > l4len)
			return;
		deliver(c, mac, l4 + 8, ulen - 8);
	} else if (proto == IPPROTO_TCP) {
		if (l4len < 20 || be16(l4) != 53)
			return;
		size_t doff = (size_t)(l4[12] >> 4) * 4;
		if (doff < 20 || doff > l4len)
			return;
		const uint8_t *d = l4 + doff;
		size_t dlen = l4len - doff;
		/* whole messages only: a 2-byte length, then the message */
		while (dlen >= 2) {
			size_t m = be16(d);
			if (m < 12 || m + 2 > dlen)
				break;
			deliver(c, mac, d + 2, m);
			d += m + 2;
			dlen -= m + 2;
		}
	}
}

static void sock_cb(struct uloop_fd *fd, unsigned int events)
{
	cap_sock *s = container_of(fd, cap_sock, fd);
	rl_dnscap *c = s->owner;
	for (int i = 0; i < 64; i++) { /* a burst at a time; uloop calls again */
		struct sockaddr_ll from;
		socklen_t fl = sizeof(from);
		ssize_t n = recvfrom(fd->fd, c->buf, BUF_SIZE, 0, (struct sockaddr *)&from, &fl);
		if (n < 0)
			return;
		if (from.sll_pkttype == PACKET_OUTGOING)
			handle(c, c->buf, (size_t)n);
	}
}

static int open_sock(rl_dnscap *c, cap_sock *s, int ifindex)
{
	struct sock_fprog prog = { .len = sizeof(dns_filter) / sizeof(dns_filter[0]), .filter = dns_filter };
	/* protocol 0: nothing arrives before the filter is attached and the socket bound */
	int fd = socket(AF_PACKET, SOCK_RAW | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	struct sockaddr_ll sll = { .sll_family = AF_PACKET, .sll_protocol = htons(ETH_P_ALL), .sll_ifindex = ifindex };
	if (setsockopt(fd, SOL_SOCKET, SO_ATTACH_FILTER, &prog, sizeof(prog)) < 0 ||
	    bind(fd, (struct sockaddr *)&sll, sizeof(sll)) < 0) {
		close(fd);
		return -1;
	}
	int rcvbuf = 256 << 10;
	setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
	memset(s, 0, sizeof(*s));
	s->owner = c;
	s->ifindex = ifindex;
	s->fd.fd = fd;
	s->fd.cb = sock_cb;
	uloop_fd_add(&s->fd, ULOOP_READ);
	return 0;
}

static void close_sock(cap_sock *s)
{
	uloop_fd_delete(&s->fd);
	close(s->fd.fd);
}

rl_dnscap *rl_dnscap_new(rl_dnscap_cb cb, void *ctx)
{
	rl_dnscap *c = calloc(1, sizeof(*c));
	if (!c)
		abort();
	c->cb = cb;
	c->ctx = ctx;
	c->buf = malloc(BUF_SIZE);
	if (!c->buf)
		abort();
	return c;
}

void rl_dnscap_free(rl_dnscap *c)
{
	if (!c)
		return;
	for (int i = 0; i < c->n; i++)
		close_sock(&c->socks[i]);
	free(c->buf);
	free(c);
}

int rl_dnscap_set_ifaces(rl_dnscap *c, const int *ifindex, int n)
{
	cap_sock next[RL_DNSCAP_MAX_IFACES];
	bool keep[RL_DNSCAP_MAX_IFACES] = { false };
	int k = 0, rc = 0;
	for (int i = 0; i < n && k < RL_DNSCAP_MAX_IFACES; i++) {
		bool dup = false;
		for (int j = 0; j < i && !dup; j++)
			dup = ifindex[j] == ifindex[i];
		if (dup || ifindex[i] <= 0)
			continue;
		int found = -1;
		for (int j = 0; j < c->n && found < 0; j++)
			if (c->socks[j].ifindex == ifindex[i])
				found = j;
		if (found >= 0) {
			keep[found] = true;
			next[k++] = c->socks[found];
		} else if (open_sock(c, &next[k], ifindex[i]) == 0) {
			k++;
		} else {
			rc = -1;
			if (!c->failed_logged)
				syslog(LOG_ERR, "DNS capture on interface %d failed: %s", ifindex[i], strerror(errno));
			c->failed_logged = true;
		}
	}
	for (int j = 0; j < c->n; j++)
		if (!keep[j])
			close_sock(&c->socks[j]);
	/* uloop keeps pointers to the uloop_fd: re-register the moved ones */
	for (int i = 0; i < k; i++) {
		uloop_fd_delete(&next[i].fd);
		c->socks[i] = next[i];
		uloop_fd_add(&c->socks[i].fd, ULOOP_READ);
	}
	c->n = k;
	return rc;
}

uint64_t rl_dnscap_answers(const rl_dnscap *c)
{
	return c->answers;
}

uint64_t rl_dnscap_bad(const rl_dnscap *c)
{
	return c->bad;
}
