#define _GNU_SOURCE
#include <errno.h>
#include <netinet/icmp6.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#include <libubox/uloop.h>

#include "sys/icmp.h"

#define PAYLOAD 32
#define HDR 8 /* type, code, checksum, identifier, sequence: the same layout for ICMP and ICMPv6 */
#define ICMP_V4_ECHOREPLY 0
#define ICMP_V4_ECHO 8

/*
 * The SOL_RAW filter of <linux/icmp.h>: that header pulls in <linux/in6.h> since Linux 5.13, which clashes
 * with musl's <netinet/in.h>.
 */
#define RL_ICMP_FILTER 1
struct rl_icmp_filter {
	uint32_t data; /* bit per ICMP type to drop */
};

typedef struct {
	rl_icmp_probe p;
	uint16_t seq;
	bool pending;
	struct timespec sent;
} slot;

struct rl_icmp {
	struct uloop_fd fd4, fd6;
	struct uloop_timeout timer;
	uint16_t ident, seq;
	slot s[RL_ICMP_MAX];
	int n, pending;
	bool busy;
	rl_icmp_cb cb;
	void *ctx;
};

static uint16_t checksum(const uint8_t *p, size_t len)
{
	uint32_t sum = 0;
	for (size_t i = 0; i + 1 < len; i += 2)
		sum += (uint32_t)p[i] << 8 | p[i + 1];
	if (len & 1)
		sum += (uint32_t)p[len - 1] << 8;
	while (sum >> 16)
		sum = (sum & 0xffff) + (sum >> 16);
	return (uint16_t)~sum;
}

static uint32_t elapsed_us(const struct timespec *from)
{
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	int64_t us = (int64_t)(now.tv_sec - from->tv_sec) * 1000000 + (now.tv_nsec - from->tv_nsec) / 1000;
	return us < 0 ? 0 : us > UINT32_MAX ? UINT32_MAX : (uint32_t)us;
}

static void finish(rl_icmp *ic)
{
	rl_icmp_probe out[RL_ICMP_MAX];
	int n = ic->n;
	uloop_timeout_cancel(&ic->timer);
	for (int i = 0; i < n; i++)
		out[i] = ic->s[i].p;
	ic->busy = false;
	ic->n = ic->pending = 0;
	if (ic->cb)
		ic->cb(out, n, ic->ctx); /* may start the next round */
}

static void timer_cb(struct uloop_timeout *t)
{
	rl_icmp *ic = container_of(t, rl_icmp, timer);
	if (ic->busy)
		finish(ic); /* whatever did not answer is lost */
}

/* An echo reply from addr (16 bytes, IPv4 in the first 4) with this identifier and sequence number. */
static void on_reply(rl_icmp *ic, int family, const uint8_t *addr, uint16_t ident, uint16_t seq)
{
	if (!ic->busy || ident != ic->ident)
		return;
	for (int i = 0; i < ic->n; i++) {
		slot *s = &ic->s[i];
		if (!s->pending || s->seq != seq || s->p.ip.family != family ||
		    memcmp(s->p.ip.a, addr, family == 4 ? 4 : 16) != 0)
			continue;
		s->p.answered = true;
		s->p.rtt_us = elapsed_us(&s->sent);
		s->pending = false;
		if (--ic->pending == 0)
			finish(ic);
		return;
	}
}

static void fd4_cb(struct uloop_fd *fd, unsigned int events)
{
	rl_icmp *ic = container_of(fd, rl_icmp, fd4);
	uint8_t buf[1500];
	for (;;) {
		struct sockaddr_in from;
		socklen_t flen = sizeof(from);
		ssize_t len = recvfrom(fd->fd, buf, sizeof(buf), MSG_DONTWAIT, (struct sockaddr *)&from, &flen);
		if (len < 0)
			break; /* EAGAIN */
		/* a raw IPv4 socket delivers the IP header too */
		size_t ihl = (size_t)(buf[0] & 0x0f) * 4;
		if ((size_t)len < ihl + HDR || buf[ihl] != ICMP_V4_ECHOREPLY || buf[ihl + 1] != 0)
			continue;
		const uint8_t *h = buf + ihl;
		on_reply(ic, 4, (const uint8_t *)&from.sin_addr, (uint16_t)(h[4] << 8 | h[5]),
			 (uint16_t)(h[6] << 8 | h[7]));
	}
}

static void fd6_cb(struct uloop_fd *fd, unsigned int events)
{
	rl_icmp *ic = container_of(fd, rl_icmp, fd6);
	uint8_t buf[1500];
	for (;;) {
		struct sockaddr_in6 from;
		socklen_t flen = sizeof(from);
		ssize_t len = recvfrom(fd->fd, buf, sizeof(buf), MSG_DONTWAIT, (struct sockaddr *)&from, &flen);
		if (len < 0)
			break;
		if (len < HDR || buf[0] != ICMP6_ECHO_REPLY || buf[1] != 0)
			continue;
		on_reply(ic, 6, from.sin6_addr.s6_addr, (uint16_t)(buf[4] << 8 | buf[5]), (uint16_t)(buf[6] << 8 | buf[7]));
	}
}

static int open4(void)
{
	int fd = socket(AF_INET, SOCK_RAW | SOCK_NONBLOCK | SOCK_CLOEXEC, IPPROTO_ICMP);
	if (fd < 0)
		return -1;
	/* only echo replies reach this socket, not every ICMP message the router receives */
	struct rl_icmp_filter f = { .data = ~(1u << ICMP_V4_ECHOREPLY) };
	setsockopt(fd, SOL_RAW, RL_ICMP_FILTER, &f, sizeof(f));
	return fd;
}

static int open6(void)
{
	int fd = socket(AF_INET6, SOCK_RAW | SOCK_NONBLOCK | SOCK_CLOEXEC, IPPROTO_ICMPV6);
	if (fd < 0)
		return -1;
	/* the kernel fills in the ICMPv6 checksum */
	struct icmp6_filter f;
	ICMP6_FILTER_SETBLOCKALL(&f);
	ICMP6_FILTER_SETPASS(ICMP6_ECHO_REPLY, &f);
	setsockopt(fd, IPPROTO_ICMPV6, ICMP6_FILTER, &f, sizeof(f));
	return fd;
}

rl_icmp *rl_icmp_open(rl_icmp_cb cb, void *ctx)
{
	rl_icmp *ic = calloc(1, sizeof(*ic));
	if (!ic)
		abort();
	ic->cb = cb;
	ic->ctx = ctx;
	ic->ident = (uint16_t)(getpid() ^ 0x524c); /* "RL": differs from busybox ping, which uses the pid */
	ic->timer.cb = timer_cb;
	ic->fd4.fd = open4();
	int err4 = errno;
	ic->fd6.fd = open6();
	if (ic->fd4.fd < 0 && ic->fd6.fd < 0) {
		free(ic);
		errno = err4;
		return NULL;
	}
	if (ic->fd4.fd >= 0) {
		ic->fd4.cb = fd4_cb;
		uloop_fd_add(&ic->fd4, ULOOP_READ);
	}
	if (ic->fd6.fd >= 0) {
		ic->fd6.cb = fd6_cb;
		uloop_fd_add(&ic->fd6, ULOOP_READ);
	} else {
		syslog(LOG_INFO, "no ICMPv6 socket (%s): IPv6 targets count as lost", strerror(errno));
	}
	return ic;
}

void rl_icmp_close(rl_icmp *ic)
{
	if (!ic)
		return;
	uloop_timeout_cancel(&ic->timer);
	if (ic->fd4.fd >= 0) {
		uloop_fd_delete(&ic->fd4);
		close(ic->fd4.fd);
	}
	if (ic->fd6.fd >= 0) {
		uloop_fd_delete(&ic->fd6);
		close(ic->fd6.fd);
	}
	free(ic);
}

/* Sends one echo request; false when it could not be sent. */
static bool send_echo(rl_icmp *ic, slot *s)
{
	uint8_t pkt[HDR + PAYLOAD];
	memset(pkt, 0, sizeof(pkt));
	bool v6 = s->p.ip.family == 6;
	pkt[0] = v6 ? ICMP6_ECHO_REQUEST : ICMP_V4_ECHO;
	pkt[4] = (uint8_t)(ic->ident >> 8);
	pkt[5] = (uint8_t)ic->ident;
	pkt[6] = (uint8_t)(s->seq >> 8);
	pkt[7] = (uint8_t)s->seq;
	memcpy(pkt + HDR, "RouteLink latency probe", 23);
	ssize_t rc;
	clock_gettime(CLOCK_MONOTONIC, &s->sent);
	if (v6) {
		if (ic->fd6.fd < 0)
			return false;
		struct sockaddr_in6 to = { .sin6_family = AF_INET6, .sin6_scope_id = (uint32_t)s->p.scope };
		memcpy(to.sin6_addr.s6_addr, s->p.ip.a, 16);
		rc = sendto(ic->fd6.fd, pkt, sizeof(pkt), 0, (struct sockaddr *)&to, sizeof(to));
	} else {
		if (ic->fd4.fd < 0)
			return false;
		uint16_t sum = checksum(pkt, sizeof(pkt));
		pkt[2] = (uint8_t)(sum >> 8);
		pkt[3] = (uint8_t)sum;
		struct sockaddr_in to = { .sin_family = AF_INET };
		memcpy(&to.sin_addr, s->p.ip.a, 4);
		rc = sendto(ic->fd4.fd, pkt, sizeof(pkt), 0, (struct sockaddr *)&to, sizeof(to));
	}
	return rc == (ssize_t)sizeof(pkt); /* ENETUNREACH while the WAN is down: lost */
}

void rl_icmp_round(rl_icmp *ic, const rl_icmp_probe *p, int n, int timeout_ms)
{
	rl_icmp_cancel(ic);
	if (n > RL_ICMP_MAX)
		n = RL_ICMP_MAX;
	ic->n = n;
	ic->pending = 0;
	ic->busy = true;
	for (int i = 0; i < n; i++) {
		slot *s = &ic->s[i];
		s->p = p[i];
		s->p.answered = false;
		s->p.rtt_us = 0;
		s->seq = ic->seq++;
		s->pending = send_echo(ic, s);
		ic->pending += s->pending;
	}
	if (ic->pending == 0) {
		finish(ic);
		return;
	}
	uloop_timeout_set(&ic->timer, timeout_ms);
}

bool rl_icmp_busy(const rl_icmp *ic)
{
	return ic->busy;
}

void rl_icmp_cancel(rl_icmp *ic)
{
	uloop_timeout_cancel(&ic->timer);
	ic->busy = false;
	ic->n = ic->pending = 0;
}
