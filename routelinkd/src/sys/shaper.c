#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#include <libmnl/libmnl.h>
#include <linux/if_link.h>
#include <linux/pkt_sched.h>
#include <linux/rtnetlink.h>

#include "sys/proc.h"
#include "sys/shaper.h"

#define TC_TIMEOUT_MS 5000

typedef struct {
	char name[IFNAMSIZ];
	unsigned gen;    /* rules generation set up on it, 0 = none of ours */
	unsigned failed; /* generation whose setup failed on it */
	bool dirty;      /* something of ours may be on it: clear before setting up */
	bool upload;     /* its setup redirects uploads to the ifb */
} port_t;

struct rl_shaper {
	char marker[128];
	port_t ports[RL_SHAPER_MAX_PORTS];
	int n_ports;
	port_t ifb; /* the shared upload device; dirty = it exists */
	rl_tc_rule *rules;
	size_t n_rules;
	unsigned gen;
	char error[200], ifb_error[200];
	char *script;
	size_t script_size;
};

/* ---- marker: ports that may carry our qdiscs ---- */

static bool marked(const rl_shaper *s, const char *name)
{
	char line[IFNAMSIZ + 2];
	bool found = false;
	FILE *f = s->marker[0] ? fopen(s->marker, "r") : NULL;
	if (!f)
		return false;
	while (!found && fgets(line, sizeof(line), f)) {
		line[strcspn(line, "\n")] = '\0';
		found = !strcmp(line, name);
	}
	fclose(f);
	return found;
}

static void write_marker(const rl_shaper *s)
{
	if (!s->marker[0])
		return;
	bool any = false;
	for (int i = 0; i < s->n_ports; i++)
		any |= s->ports[i].dirty;
	if (!any) {
		unlink(s->marker);
		return;
	}
	char tmp[sizeof(s->marker) + 4];
	snprintf(tmp, sizeof(tmp), "%s.tmp", s->marker);
	FILE *f = fopen(tmp, "w");
	if (!f)
		return;
	for (int i = 0; i < s->n_ports; i++)
		if (s->ports[i].dirty)
			fprintf(f, "%s\n", s->ports[i].name);
	fclose(f);
	rename(tmp, s->marker);
}

/* ---- the ifb device (rtnetlink) ---- */

/* Sends one request and waits for its acknowledgement: 0 or -errno. */
static int rtnl_request(struct nlmsghdr *nlh)
{
	char buf[MNL_SOCKET_BUFFER_SIZE];
	struct mnl_socket *nl = mnl_socket_open2(NETLINK_ROUTE, SOCK_CLOEXEC);
	int rc = -EIO;
	if (!nl)
		return -errno;
	if (mnl_socket_bind(nl, 0, MNL_SOCKET_AUTOPID) < 0)
		goto out;
	nlh->nlmsg_flags |= NLM_F_REQUEST | NLM_F_ACK;
	nlh->nlmsg_seq = (unsigned)time(NULL);
	if (mnl_socket_sendto(nl, nlh, nlh->nlmsg_len) < 0) {
		rc = -errno;
		goto out;
	}
	ssize_t r = mnl_socket_recvfrom(nl, buf, sizeof(buf));
	if (r < 0) {
		rc = -errno;
		goto out;
	}
	rc = mnl_cb_run(buf, (size_t)r, nlh->nlmsg_seq, mnl_socket_get_portid(nl), NULL, NULL) < 0 ? -errno : 0;
out:
	mnl_socket_close(nl);
	return rc;
}

/* Creates the ifb (or finds it) and sets it up: 0 or -errno. */
static int ifb_create(void)
{
	char buf[512];
	struct nlmsghdr *nlh = mnl_nlmsg_put_header(buf);
	unsigned idx = if_nametoindex(RL_TC_IFB);
	nlh->nlmsg_type = RTM_NEWLINK;
	nlh->nlmsg_flags = idx ? 0 : NLM_F_CREATE | NLM_F_EXCL;
	struct ifinfomsg *ifm = mnl_nlmsg_put_extra_header(nlh, sizeof(*ifm));
	ifm->ifi_family = AF_UNSPEC;
	ifm->ifi_index = (int)idx;
	ifm->ifi_flags = IFF_UP;
	ifm->ifi_change = IFF_UP;
	if (!idx) {
		mnl_attr_put_strz(nlh, IFLA_IFNAME, RL_TC_IFB);
		struct nlattr *info = mnl_attr_nest_start(nlh, IFLA_LINKINFO);
		mnl_attr_put_strz(nlh, IFLA_INFO_KIND, "ifb");
		mnl_attr_nest_end(nlh, info);
	}
	return rtnl_request(nlh);
}

static void ifb_delete(void)
{
	char buf[256];
	unsigned idx = if_nametoindex(RL_TC_IFB);
	if (!idx)
		return;
	struct nlmsghdr *nlh = mnl_nlmsg_put_header(buf);
	nlh->nlmsg_type = RTM_DELLINK;
	struct ifinfomsg *ifm = mnl_nlmsg_put_extra_header(nlh, sizeof(*ifm));
	ifm->ifi_family = AF_UNSPEC;
	ifm->ifi_index = (int)idx;
	rtnl_request(nlh);
}

/* ---- tc ---- */

static int run_tc(const char *script, size_t len, bool force, char *out, size_t out_size)
{
	const char *argv[] = { "tc", force ? "-force" : "-batch", force ? "-batch" : "-", force ? "-" : NULL, NULL };
	return rl_proc_run(argv, script, len, out, out_size, TC_TIMEOUT_MS);
}

/* Grows the script buffer until gen fits. */
#define GENERATE(s, call)                                                                     \
	({                                                                                    \
		size_t _n;                                                                    \
		while ((_n = (call)) == (size_t)-1) {                                         \
			s->script_size = s->script_size ? s->script_size * 2 : 16384;         \
			s->script = realloc(s->script, s->script_size);                       \
			if (!s->script)                                                       \
				abort();                                                      \
		}                                                                             \
		_n;                                                                           \
	})

static void ensure_buffer(rl_shaper *s)
{
	if (!s->script) {
		s->script_size = 16384;
		s->script = malloc(s->script_size);
		if (!s->script)
			abort();
	}
}

static void clear_dev(rl_shaper *s, port_t *p)
{
	char out[256];
	ensure_buffer(s);
	size_t n = GENERATE(s, rl_tc_clear_script(s->script, s->script_size, p->name));
	run_tc(s->script, n, true, out, sizeof(out)); /* fails where nothing was set up: fine */
	p->gen = 0;
}

static void clear_port(rl_shaper *s, port_t *p)
{
	clear_dev(s, p);
	p->dirty = false;
}

/* Why tc failed, as one line. */
static void tc_error(int rc, const char *out, char *line, size_t size)
{
	if (rc == 127)
		snprintf(line, size, "tc is not installed (package tc-tiny)");
	else if (rc < 0)
		snprintf(line, size, "tc did not finish");
	else
		rl_proc_first_line(out, line, size);
	if (!line[0])
		snprintf(line, size, "tc failed");
}

/* Clear, then set up the current rules (uploads only with a working ifb). */
static bool apply_port(rl_shaper *s, port_t *p, bool ifb)
{
	char out[512], line[160];
	if (p->dirty)
		clear_port(s, p);
	ensure_buffer(s);
	size_t n = GENERATE(s, rl_tc_script(s->script, s->script_size, p->name, ifb ? RL_TC_IFB : NULL, s->rules,
					     s->n_rules));
	p->upload = ifb;
	if (!n) {
		p->gen = s->gen; /* nothing limits anything */
		return true;
	}
	p->dirty = true;
	int rc = run_tc(s->script, n, false, out, sizeof(out));
	if (rc == 0) {
		p->gen = s->gen;
		return true;
	}
	tc_error(rc, out, line, sizeof(line));
	snprintf(s->error, sizeof(s->error), "%s: %s", p->name, line);
	syslog(LOG_ERR, "speed limits on %s failed: %s (not retried until the rules change)", p->name, line);
	p->failed = s->gen;
	clear_port(s, p); /* no half-done setup */
	return false;
}

/* The ifb exists, is up and has the upload classes. */
static bool apply_ifb(rl_shaper *s)
{
	char out[512], line[160];
	int err = ifb_create();
	if (err) {
		snprintf(s->ifb_error, sizeof(s->ifb_error), "uploads: cannot create %s (kmod-ifb): %s", RL_TC_IFB,
			 strerror(-err));
		syslog(LOG_ERR, "upload limits off: %s", s->ifb_error);
		s->ifb.failed = s->gen;
		return false;
	}
	s->ifb.dirty = true;
	clear_dev(s, &s->ifb);
	ensure_buffer(s);
	size_t n = GENERATE(s, rl_tc_ifb_script(s->script, s->script_size, RL_TC_IFB, s->rules, s->n_rules));
	int rc = run_tc(s->script, n, false, out, sizeof(out));
	if (rc == 0) {
		s->ifb.gen = s->gen;
		s->ifb_error[0] = '\0';
		return true;
	}
	tc_error(rc, out, line, sizeof(line));
	snprintf(s->ifb_error, sizeof(s->ifb_error), "uploads (%s): %s", RL_TC_IFB, line);
	syslog(LOG_ERR, "upload limits off: %s", s->ifb_error);
	s->ifb.failed = s->gen;
	clear_dev(s, &s->ifb);
	return false;
}

static void remove_ifb(rl_shaper *s)
{
	if (!s->ifb.dirty)
		return;
	clear_dev(s, &s->ifb);
	ifb_delete();
	s->ifb.dirty = false;
}

/* ---- rtnetlink: which devices still carry our qdiscs ---- */

typedef struct {
	int ifindex;
	bool htb, clsact;
} qd_state;

typedef struct {
	qd_state *st;
	int n;
} qd_ctx;

static int kind_cb(const struct nlattr *attr, void *data)
{
	const char **kind = data;
	if (mnl_attr_get_type(attr) == TCA_KIND && mnl_attr_validate(attr, MNL_TYPE_NUL_STRING) >= 0)
		*kind = mnl_attr_get_str(attr);
	return MNL_CB_OK;
}

static int qdisc_cb(const struct nlmsghdr *nlh, void *data)
{
	qd_ctx *c = data;
	const struct tcmsg *t = mnl_nlmsg_get_payload(nlh);
	const char *kind = NULL;
	mnl_attr_parse(nlh, sizeof(*t), kind_cb, &kind);
	if (!kind)
		return MNL_CB_OK;
	for (int i = 0; i < c->n; i++) {
		if (c->st[i].ifindex != t->tcm_ifindex)
			continue;
		if (t->tcm_parent == TC_H_ROOT && t->tcm_handle == 0x10000 && !strcmp(kind, "htb"))
			c->st[i].htb = true;
		if (!strcmp(kind, "clsact"))
			c->st[i].clsact = true;
	}
	return MNL_CB_OK;
}

/* Fills htb/clsact for the given ifindexes; -1 when the dump failed. */
static int dump_qdiscs(qd_state *st, int n)
{
	char buf[MNL_SOCKET_BUFFER_SIZE];
	struct mnl_socket *nl = mnl_socket_open2(NETLINK_ROUTE, SOCK_CLOEXEC);
	if (!nl)
		return -1;
	int rc = -1;
	if (mnl_socket_bind(nl, 0, MNL_SOCKET_AUTOPID) < 0)
		goto out;
	struct nlmsghdr *nlh = mnl_nlmsg_put_header(buf);
	nlh->nlmsg_type = RTM_GETQDISC;
	nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
	nlh->nlmsg_seq = (unsigned)time(NULL);
	struct tcmsg *t = mnl_nlmsg_put_extra_header(nlh, sizeof(*t));
	t->tcm_family = AF_UNSPEC;
	if (mnl_socket_sendto(nl, nlh, nlh->nlmsg_len) < 0)
		goto out;
	unsigned seq = nlh->nlmsg_seq, portid = mnl_socket_get_portid(nl);
	qd_ctx c = { st, n };
	for (;;) {
		ssize_t r = mnl_socket_recvfrom(nl, buf, sizeof(buf));
		if (r <= 0)
			goto out;
		int ret = mnl_cb_run(buf, (size_t)r, seq, portid, qdisc_cb, &c);
		if (ret < 0)
			goto out;
		if (ret == MNL_CB_STOP)
			break;
	}
	rc = 0;
out:
	mnl_socket_close(nl);
	return rc;
}

/* ---- public ---- */

rl_shaper *rl_shaper_new(const char *marker)
{
	rl_shaper *s = calloc(1, sizeof(*s));
	if (!s)
		abort();
	if (marker)
		snprintf(s->marker, sizeof(s->marker), "%s", marker);
	s->gen = 1;
	snprintf(s->ifb.name, sizeof(s->ifb.name), "%s", RL_TC_IFB);
	s->ifb.dirty = if_nametoindex(RL_TC_IFB) != 0; /* from before a crash */
	return s;
}

void rl_shaper_free(rl_shaper *s, bool clear)
{
	if (!s)
		return;
	if (clear) {
		for (int i = 0; i < s->n_ports; i++)
			if (s->ports[i].dirty)
				clear_port(s, &s->ports[i]);
		remove_ifb(s);
		write_marker(s);
	}
	free(s->rules);
	free(s->script);
	free(s);
}

void rl_shaper_set_ports(rl_shaper *s, const char (*ports)[IFNAMSIZ], int n)
{
	port_t next[RL_SHAPER_MAX_PORTS];
	int k = 0;
	if (n > RL_SHAPER_MAX_PORTS)
		n = RL_SHAPER_MAX_PORTS;
	for (int i = 0; i < n; i++) {
		port_t *old = NULL;
		for (int j = 0; j < s->n_ports && !old; j++)
			if (!strcmp(s->ports[j].name, ports[i]))
				old = &s->ports[j];
		if (old) {
			next[k] = *old;
			old->name[0] = '\0'; /* taken over */
		} else {
			memset(&next[k], 0, sizeof(next[k]));
			snprintf(next[k].name, sizeof(next[k].name), "%s", ports[i]);
			next[k].dirty = marked(s, ports[i]); /* from before a crash */
		}
		k++;
	}
	for (int j = 0; j < s->n_ports; j++)
		if (s->ports[j].name[0] && s->ports[j].dirty && if_nametoindex(s->ports[j].name))
			clear_port(s, &s->ports[j]); /* no longer a LAN port */
	memcpy(s->ports, next, (size_t)k * sizeof(port_t));
	s->n_ports = k;
	write_marker(s);
}

static int cmp_rule(const void *a, const void *b)
{
	return memcmp(((const rl_tc_rule *)a)->mac, ((const rl_tc_rule *)b)->mac, 6);
}

bool rl_shaper_set_rules(rl_shaper *s, const rl_tc_rule *rules, size_t n)
{
	rl_tc_rule *sorted = malloc((n ? n : 1) * sizeof(*sorted));
	if (!sorted)
		abort();
	memcpy(sorted, rules, n * sizeof(*sorted));
	qsort(sorted, n, sizeof(*sorted), cmp_rule);
	if (n == s->n_rules && (!n || !memcmp(sorted, s->rules, n * sizeof(*sorted)))) {
		free(sorted);
		return false;
	}
	free(s->rules);
	s->rules = sorted;
	s->n_rules = n;
	s->gen++;
	return true;
}

int rl_shaper_sync(rl_shaper *s, bool check)
{
	qd_state st[RL_SHAPER_MAX_PORTS + 1];
	bool down = false, up = false, dumped = false;
	int applied = 0, n = s->n_ports;
	for (size_t i = 0; i < s->n_rules; i++) {
		down |= s->rules[i].down_kbps > 0;
		up |= s->rules[i].up_kbps > 0;
	}
	for (int i = 0; i < n; i++) {
		st[i] = (qd_state){ .ifindex = (int)if_nametoindex(s->ports[i].name) };
		if (!st[i].ifindex)
			s->ports[i].gen = 0; /* gone, and its qdiscs with it */
	}
	st[n] = (qd_state){ .ifindex = (int)if_nametoindex(RL_TC_IFB) };
	if (check && (down || up))
		dumped = dump_qdiscs(st, n + 1) == 0;

	/* uploads first: the ports redirect to the ifb */
	bool ifb = false;
	if (up) {
		bool lost = s->ifb.gen && !st[n].ifindex; /* deleted: the ports' redirects point nowhere now */
		bool need = s->ifb.gen != s->gen || lost || (dumped && !st[n].htb);
		if (need && s->ifb.failed != s->gen) {
			if (s->ifb.gen == s->gen)
				syslog(LOG_INFO, "upload limits on %s were gone, setting them up again", RL_TC_IFB);
			if (apply_ifb(s) && lost)
				for (int i = 0; i < n; i++)
					s->ports[i].gen = 0;
		}
		ifb = s->ifb.gen == s->gen;
	} else {
		remove_ifb(s);
		s->ifb_error[0] = '\0';
	}

	bool failing = false;
	for (int i = 0; i < n; i++) {
		port_t *p = &s->ports[i];
		if (!st[i].ifindex)
			continue;
		bool need = p->gen != s->gen || p->upload != ifb;
		if (!need && dumped && ((down && !st[i].htb) || (ifb && !st[i].clsact))) {
			syslog(LOG_INFO, "speed limits on %s were gone, setting them up again", p->name);
			need = true;
		}
		if (p->failed == s->gen) {
			failing = true;
			continue;
		}
		if (!need)
			continue;
		if (apply_port(s, p, ifb))
			applied++;
		else
			failing = true;
	}
	if (!failing)
		snprintf(s->error, sizeof(s->error), "%s", s->ifb_error);
	if (s->n_rules && !n)
		snprintf(s->error, sizeof(s->error), "no LAN port found to set the limits on");
	write_marker(s);
	return applied;
}

const char *rl_shaper_error(const rl_shaper *s)
{
	return s->error;
}

void rl_shaper_retry(rl_shaper *s)
{
	for (int i = 0; i < s->n_ports; i++)
		s->ports[i].failed = 0;
	s->ifb.failed = 0;
}

size_t rl_shaper_rules(const rl_shaper *s, const rl_tc_rule **out)
{
	*out = s->rules;
	return s->n_rules;
}
