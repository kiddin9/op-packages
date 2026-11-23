#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <syslog.h>
#include <time.h>

#include <libmnl/libmnl.h>
#include <linux/genetlink.h>
#include <linux/nl80211.h>

#include "sys/nl80211.h"

#ifndef SOL_NETLINK
#define SOL_NETLINK 270
#endif

#define REQ_BUF 32768     /* MNL_SOCKET_DUMP_SIZE: a station takes about 1 KB of a dump */
#define EV_BUF 8192       /* one NEW_STATION carries a station's statistics */
#define RATE_ATTRS 63     /* nested rate info table; newer kernels add EHT and S1G attributes */
#define CHAN_WIDTH_320 13 /* NL80211_CHAN_WIDTH_320, missing from older headers */

struct rl_nl80211 {
	struct mnl_socket *req, *ev;
	unsigned int seq, portid;
	uint16_t family;
	uint32_t mlme;
	char *buf, *ev_buf;
	rl_nl_event_cb cb;
	void *ctx;
};

/* ---- attribute helpers ---- */

typedef struct {
	const struct nlattr **tb;
	int max;
} attr_table;

static int table_cb(const struct nlattr *attr, void *data)
{
	attr_table *t = data;
	int type = mnl_attr_get_type(attr);
	if (type <= t->max)
		t->tb[type] = attr;
	return MNL_CB_OK;
}

static void parse_msg(const struct nlmsghdr *nlh, const struct nlattr **tb, int max)
{
	attr_table t = { tb, max };
	memset(tb, 0, (size_t)(max + 1) * sizeof(*tb));
	mnl_attr_parse(nlh, sizeof(struct genlmsghdr), table_cb, &t);
}

static void parse_nested(const struct nlattr *nest, const struct nlattr **tb, int max)
{
	attr_table t = { tb, max };
	memset(tb, 0, (size_t)(max + 1) * sizeof(*tb));
	mnl_attr_parse_nested(nest, table_cb, &t);
}

static bool get_u8(const struct nlattr *a, uint8_t *v)
{
	if (!a || mnl_attr_validate(a, MNL_TYPE_U8) < 0)
		return false;
	*v = mnl_attr_get_u8(a);
	return true;
}

static bool get_u16(const struct nlattr *a, uint16_t *v)
{
	if (!a || mnl_attr_validate(a, MNL_TYPE_U16) < 0)
		return false;
	*v = mnl_attr_get_u16(a);
	return true;
}

static bool get_u32(const struct nlattr *a, uint32_t *v)
{
	if (!a || mnl_attr_validate(a, MNL_TYPE_U32) < 0)
		return false;
	*v = mnl_attr_get_u32(a);
	return true;
}

static bool get_u64(const struct nlattr *a, uint64_t *v)
{
	if (!a || mnl_attr_get_payload_len(a) < sizeof(uint64_t))
		return false;
	memcpy(v, mnl_attr_get_payload(a), sizeof(*v)); /* u64 payloads are only 4-byte aligned */
	return true;
}

static bool get_mac(const struct nlattr *a, rl_mac *mac)
{
	if (!a || mnl_attr_get_payload_len(a) != 6)
		return false;
	memcpy(mac->b, mnl_attr_get_payload(a), 6);
	return true;
}

/* ---- requests ---- */

static struct nlmsghdr *put_req(rl_nl80211 *n, uint16_t type, uint16_t flags, uint8_t cmd, uint8_t version)
{
	struct nlmsghdr *nlh = mnl_nlmsg_put_header(n->buf);
	nlh->nlmsg_type = type;
	nlh->nlmsg_flags = NLM_F_REQUEST | flags;
	nlh->nlmsg_seq = ++n->seq;
	struct genlmsghdr *g = mnl_nlmsg_put_extra_header(nlh, sizeof(*g));
	g->cmd = cmd;
	g->version = version;
	return nlh;
}

/* Sends a dump (or a get with NLM_F_ACK) and runs cb on every answer until the end. */
static int exchange(rl_nl80211 *n, const struct nlmsghdr *nlh, mnl_cb_t cb, void *data)
{
	unsigned int seq = nlh->nlmsg_seq;
	char junk[64];
	/* answers to an earlier request that timed out would fail the sequence check */
	while (recv(mnl_socket_get_fd(n->req), junk, sizeof(junk), MSG_DONTWAIT | MSG_TRUNC) > 0)
		;
	if (mnl_socket_sendto(n->req, nlh, nlh->nlmsg_len) < 0)
		return -1;
	for (;;) {
		ssize_t r = mnl_socket_recvfrom(n->req, n->buf, REQ_BUF);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			return -1; /* also the receive timeout */
		}
		int ret = mnl_cb_run(n->buf, (size_t)r, seq, n->portid, cb, data);
		if (ret == MNL_CB_ERROR)
			return -1;
		if (ret == MNL_CB_STOP)
			return 0;
	}
}

/* ---- family and multicast group ---- */

static int family_cb(const struct nlmsghdr *nlh, void *data)
{
	rl_nl80211 *n = data;
	const struct nlattr *tb[CTRL_ATTR_MAX + 1], *grp;
	uint16_t id;
	parse_msg(nlh, tb, CTRL_ATTR_MAX);
	if (get_u16(tb[CTRL_ATTR_FAMILY_ID], &id))
		n->family = id;
	if (!tb[CTRL_ATTR_MCAST_GROUPS])
		return MNL_CB_OK;
	mnl_attr_for_each_nested(grp, tb[CTRL_ATTR_MCAST_GROUPS]) {
		const struct nlattr *g[CTRL_ATTR_MCAST_GRP_MAX + 1];
		uint32_t gid;
		parse_nested(grp, g, CTRL_ATTR_MCAST_GRP_MAX);
		if (g[CTRL_ATTR_MCAST_GRP_NAME] && mnl_attr_validate(g[CTRL_ATTR_MCAST_GRP_NAME], MNL_TYPE_NUL_STRING) >= 0 &&
		    !strcmp(mnl_attr_get_str(g[CTRL_ATTR_MCAST_GRP_NAME]), NL80211_MULTICAST_GROUP_MLME) &&
		    get_u32(g[CTRL_ATTR_MCAST_GRP_ID], &gid))
			n->mlme = gid;
	}
	return MNL_CB_OK;
}

static int resolve_family(rl_nl80211 *n)
{
	struct nlmsghdr *nlh = put_req(n, GENL_ID_CTRL, NLM_F_ACK, CTRL_CMD_GETFAMILY, 1);
	mnl_attr_put_strz(nlh, CTRL_ATTR_FAMILY_NAME, NL80211_GENL_NAME);
	if (exchange(n, nlh, family_cb, n) != 0)
		return -1;
	if (!n->family) {
		errno = ENOENT;
		return -1;
	}
	return 0;
}

/* ---- events ---- */

static int event_cb(const struct nlmsghdr *nlh, void *data)
{
	rl_nl80211 *n = data;
	const struct genlmsghdr *g = mnl_nlmsg_get_payload(nlh);
	const struct nlattr *tb[NL80211_ATTR_MAX + 1];
	uint32_t ifindex;
	rl_mac mac;
	if (nlh->nlmsg_type != n->family || (g->cmd != NL80211_CMD_NEW_STATION && g->cmd != NL80211_CMD_DEL_STATION))
		return MNL_CB_OK;
	parse_msg(nlh, tb, NL80211_ATTR_MAX);
	if (get_u32(tb[NL80211_ATTR_IFINDEX], &ifindex) && get_mac(tb[NL80211_ATTR_MAC], &mac))
		n->cb(g->cmd == NL80211_CMD_NEW_STATION, (int)ifindex, &mac, n->ctx);
	return MNL_CB_OK;
}

bool rl_nl80211_on_readable(rl_nl80211 *n)
{
	bool lost = false;
	if (!n->ev)
		return false;
	for (;;) {
		ssize_t r = mnl_socket_recvfrom(n->ev, n->ev_buf, EV_BUF);
		if (r < 0) {
			if (errno == ENOBUFS) {
				lost = true;
				continue;
			}
			if (errno == EINTR)
				continue;
			break; /* EAGAIN */
		}
		mnl_cb_run(n->ev_buf, (size_t)r, 0, 0, event_cb, n);
	}
	return lost;
}

int rl_nl80211_event_fd(const rl_nl80211 *n)
{
	return n->ev ? mnl_socket_get_fd(n->ev) : -1;
}

static void open_events(rl_nl80211 *n)
{
	int group = (int)n->mlme;
	if (!n->cb || !n->mlme)
		return;
	n->ev = mnl_socket_open2(NETLINK_GENERIC, SOCK_NONBLOCK | SOCK_CLOEXEC);
	if (!n->ev || mnl_socket_bind(n->ev, 0, MNL_SOCKET_AUTOPID) < 0 ||
	    mnl_socket_setsockopt(n->ev, NETLINK_ADD_MEMBERSHIP, &group, sizeof(group)) < 0) {
		syslog(LOG_WARNING, "nl80211 station events unavailable: %s", strerror(errno));
		if (n->ev)
			mnl_socket_close(n->ev);
		n->ev = NULL;
		return;
	}
	n->ev_buf = malloc(EV_BUF);
	if (!n->ev_buf)
		abort();
}

/* ---- open / close ---- */

rl_nl80211 *rl_nl80211_open(rl_nl_event_cb cb, void *ctx)
{
	rl_nl80211 *n = calloc(1, sizeof(*n));
	if (!n)
		abort();
	n->cb = cb;
	n->ctx = ctx;
	n->buf = malloc(REQ_BUF);
	if (!n->buf)
		abort();
	n->req = mnl_socket_open2(NETLINK_GENERIC, SOCK_CLOEXEC);
	if (!n->req || mnl_socket_bind(n->req, 0, MNL_SOCKET_AUTOPID) < 0) {
		rl_nl80211_close(n);
		return NULL;
	}
	/* a dump that never ends must not stall the daemon */
	struct timeval tv = { .tv_sec = 2 };
	setsockopt(mnl_socket_get_fd(n->req), SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	n->portid = mnl_socket_get_portid(n->req);
	n->seq = (unsigned int)time(NULL);
	if (resolve_family(n) != 0) {
		int err = errno;
		rl_nl80211_close(n);
		errno = err;
		return NULL;
	}
	open_events(n);
	return n;
}

void rl_nl80211_close(rl_nl80211 *n)
{
	if (!n)
		return;
	if (n->req)
		mnl_socket_close(n->req);
	if (n->ev)
		mnl_socket_close(n->ev);
	free(n->buf);
	free(n->ev_buf);
	free(n);
}

/* ---- interfaces ---- */

typedef struct {
	rl_nl_iface *out;
	int max, n;
} ifaces_ctx;

static uint16_t chan_width(uint32_t w)
{
	switch (w) {
	case NL80211_CHAN_WIDTH_20_NOHT:
	case NL80211_CHAN_WIDTH_20:
		return 20;
	case NL80211_CHAN_WIDTH_40:
		return 40;
	case NL80211_CHAN_WIDTH_80:
		return 80;
	case NL80211_CHAN_WIDTH_80P80:
	case NL80211_CHAN_WIDTH_160:
		return 160;
	case NL80211_CHAN_WIDTH_5:
		return 5;
	case NL80211_CHAN_WIDTH_10:
		return 10;
	case CHAN_WIDTH_320:
		return 320;
	default:
		return 0;
	}
}

/* phy name (OpenWrt renames phys, so it is not always "phy<wiphy>") */
static void phy_name(const char *ifname, uint32_t wiphy, char *out, size_t len)
{
	char path[64];
	snprintf(path, sizeof(path), "/sys/class/net/%s/phy80211/name", ifname);
	FILE *f = fopen(path, "r");
	if (f) {
		bool ok = fgets(out, (int)len, f) != NULL;
		fclose(f);
		if (ok) {
			out[strcspn(out, "\r\n")] = '\0';
			if (out[0])
				return;
		}
	}
	snprintf(out, len, "phy%u", wiphy);
}

static int iface_cb(const struct nlmsghdr *nlh, void *data)
{
	ifaces_ctx *c = data;
	const struct nlattr *tb[NL80211_ATTR_MAX + 1];
	uint32_t type, ifindex, v;
	parse_msg(nlh, tb, NL80211_ATTR_MAX);
	if (!get_u32(tb[NL80211_ATTR_IFTYPE], &type) || type != NL80211_IFTYPE_AP ||
	    !get_u32(tb[NL80211_ATTR_IFINDEX], &ifindex) || c->n >= c->max)
		return MNL_CB_OK;
	rl_nl_iface *i = &c->out[c->n++];
	memset(i, 0, sizeof(*i));
	i->ifindex = (int)ifindex;
	if (get_u32(tb[NL80211_ATTR_WIPHY], &v))
		i->wiphy = v;
	if (tb[NL80211_ATTR_IFNAME] && mnl_attr_validate(tb[NL80211_ATTR_IFNAME], MNL_TYPE_NUL_STRING) >= 0)
		snprintf(i->ifname, sizeof(i->ifname), "%s", mnl_attr_get_str(tb[NL80211_ATTR_IFNAME]));
	if (tb[NL80211_ATTR_SSID]) {
		size_t len = mnl_attr_get_payload_len(tb[NL80211_ATTR_SSID]);
		if (len > 32)
			len = 32;
		memcpy(i->ssid, mnl_attr_get_payload(tb[NL80211_ATTR_SSID]), len);
		i->ssid[len] = '\0';
	}
	get_mac(tb[NL80211_ATTR_MAC], &i->bssid);
	if (get_u32(tb[NL80211_ATTR_WIPHY_FREQ], &v))
		i->freq = v;
	if (get_u32(tb[NL80211_ATTR_CHANNEL_WIDTH], &v))
		i->width = chan_width(v);
	phy_name(i->ifname, i->wiphy, i->phy, sizeof(i->phy));
	return MNL_CB_OK;
}

int rl_nl80211_ap_ifaces(rl_nl80211 *n, rl_nl_iface *out, int max)
{
	ifaces_ctx c = { out, max, 0 };
	struct nlmsghdr *nlh = put_req(n, n->family, NLM_F_DUMP, NL80211_CMD_GET_INTERFACE, 0);
	return exchange(n, nlh, iface_cb, &c) == 0 ? c.n : -1;
}

/* ---- stations ---- */

typedef struct {
	int ifindex;
	rl_nl_sta_cb cb;
	void *ctx;
} sta_ctx;

/* Rate, MCS, streams and width of a tx or rx rate info. */
static void parse_rate(const struct nlattr *nest, rl_sta_sample *s, bool tx)
{
	const struct nlattr *r[RATE_ATTRS + 1];
	uint32_t rate32;
	uint16_t rate16;
	uint8_t mcs = 0, nss = 0;
	rl_wifi_mode mode = RL_WIFI_MODE_LEGACY;
	bool have_mcs = true;

	parse_nested(nest, r, RATE_ATTRS);
	uint32_t rate = get_u32(r[NL80211_RATE_INFO_BITRATE32], &rate32) ? rate32
			: get_u16(r[NL80211_RATE_INFO_BITRATE], &rate16) ? rate16
									  : 0;
	if (get_u8(r[NL80211_RATE_INFO_HE_MCS], &mcs)) {
		mode = RL_WIFI_MODE_HE;
		get_u8(r[NL80211_RATE_INFO_HE_NSS], &nss);
	} else if (get_u8(r[NL80211_RATE_INFO_VHT_MCS], &mcs)) {
		mode = RL_WIFI_MODE_VHT;
		get_u8(r[NL80211_RATE_INFO_VHT_NSS], &nss);
	} else if (get_u8(r[NL80211_RATE_INFO_MCS], &mcs)) {
		mode = RL_WIFI_MODE_HT;
		nss = (uint8_t)(mcs / 8 + 1);
		mcs %= 8;
	} else {
		have_mcs = false;
		/* attributes past the HE ones (EHT, S1G) are not read: the mode is unknown, not legacy */
		for (int t = NL80211_RATE_INFO_HE_RU_ALLOC + 1; t <= RATE_ATTRS; t++)
			if (r[t])
				mode = RL_WIFI_MODE_UNKNOWN;
	}
	uint16_t width = 20;
	if (r[NL80211_RATE_INFO_160_MHZ_WIDTH] || r[NL80211_RATE_INFO_80P80_MHZ_WIDTH])
		width = 160;
	else if (r[NL80211_RATE_INFO_80_MHZ_WIDTH])
		width = 80;
	else if (r[NL80211_RATE_INFO_40_MHZ_WIDTH])
		width = 40;
	else if (r[NL80211_RATE_INFO_10_MHZ_WIDTH])
		width = 10;
	else if (r[NL80211_RATE_INFO_5_MHZ_WIDTH])
		width = 5;

	if (tx) {
		if (rate) {
			s->tx_rate = rate * 100; /* 100 kbit/s units */
			s->has |= RL_STA_TX_RATE;
		}
		if (have_mcs) {
			s->tx_mcs = mcs;
			s->has |= RL_STA_TX_MCS;
		}
		if (nss) {
			s->tx_nss = nss;
			s->has |= RL_STA_TX_NSS;
		}
		if (mode != RL_WIFI_MODE_UNKNOWN && (rate || have_mcs)) {
			s->mode = mode;
			s->width = width;
			s->has |= RL_STA_MODE | RL_STA_WIDTH;
		}
	} else {
		if (rate) {
			s->rx_rate = rate * 100;
			s->has |= RL_STA_RX_RATE;
		}
		if (have_mcs) {
			s->rx_mcs = mcs;
			s->has |= RL_STA_RX_MCS;
		}
		if (nss) {
			s->rx_nss = nss;
			s->has |= RL_STA_RX_NSS;
		}
	}
}

static int sta_cb(const struct nlmsghdr *nlh, void *data)
{
	sta_ctx *c = data;
	const struct nlattr *tb[NL80211_ATTR_MAX + 1], *si[NL80211_STA_INFO_MAX + 1];
	rl_sta_sample s;
	uint32_t v32, v32b;
	uint64_t v64, v64b;
	uint8_t v8;

	memset(&s, 0, sizeof(s));
	parse_msg(nlh, tb, NL80211_ATTR_MAX);
	if (!get_mac(tb[NL80211_ATTR_MAC], &s.mac) || !tb[NL80211_ATTR_STA_INFO])
		return MNL_CB_OK;
	s.ifindex = get_u32(tb[NL80211_ATTR_IFINDEX], &v32) ? (int)v32 : c->ifindex;
	parse_nested(tb[NL80211_ATTR_STA_INFO], si, NL80211_STA_INFO_MAX);

	if (get_u32(si[NL80211_STA_INFO_INACTIVE_TIME], &v32)) {
		s.inactive_ms = v32;
		s.has |= RL_STA_INACTIVE;
	}
	if (get_u32(si[NL80211_STA_INFO_CONNECTED_TIME], &v32)) {
		s.connected_sec = v32;
		s.has |= RL_STA_CONNECTED;
	}
	/* signal is a signed dBm value in a u8; 0 means the driver has none */
	if (get_u8(si[NL80211_STA_INFO_SIGNAL], &v8) && (int8_t)v8 < 0) {
		s.signal = (int8_t)v8;
		s.has |= RL_STA_SIGNAL;
	}
	if (get_u8(si[NL80211_STA_INFO_SIGNAL_AVG], &v8) && (int8_t)v8 < 0) {
		s.signal_avg = (int8_t)v8;
		s.has |= RL_STA_SIGNAL_AVG;
	}
	if (get_u64(si[NL80211_STA_INFO_RX_BYTES64], &v64) && get_u64(si[NL80211_STA_INFO_TX_BYTES64], &v64b)) {
		s.rx_bytes = v64;
		s.tx_bytes = v64b;
		s.has |= RL_STA_BYTES;
	} else if (get_u32(si[NL80211_STA_INFO_RX_BYTES], &v32) && get_u32(si[NL80211_STA_INFO_TX_BYTES], &v32b)) {
		s.rx_bytes = v32;
		s.tx_bytes = v32b;
		s.has |= RL_STA_BYTES;
	}
	if (get_u32(si[NL80211_STA_INFO_RX_PACKETS], &v32) && get_u32(si[NL80211_STA_INFO_TX_PACKETS], &v32b)) {
		s.rx_packets = v32;
		s.tx_packets = v32b;
		s.has |= RL_STA_PACKETS;
	}
	if (get_u32(si[NL80211_STA_INFO_TX_RETRIES], &v32)) {
		s.tx_retries = v32;
		s.has |= RL_STA_RETRIES;
	}
	if (get_u32(si[NL80211_STA_INFO_TX_FAILED], &v32)) {
		s.tx_failed = v32;
		s.has |= RL_STA_FAILED;
	}
	if (si[NL80211_STA_INFO_TX_BITRATE])
		parse_rate(si[NL80211_STA_INFO_TX_BITRATE], &s, true);
	if (si[NL80211_STA_INFO_RX_BITRATE])
		parse_rate(si[NL80211_STA_INFO_RX_BITRATE], &s, false);
	if (si[NL80211_STA_INFO_STA_FLAGS] &&
	    mnl_attr_get_payload_len(si[NL80211_STA_INFO_STA_FLAGS]) >= sizeof(struct nl80211_sta_flag_update)) {
		struct nl80211_sta_flag_update f;
		memcpy(&f, mnl_attr_get_payload(si[NL80211_STA_INFO_STA_FLAGS]), sizeof(f));
		if (f.mask & (1u << NL80211_STA_FLAG_AUTHORIZED)) {
			s.authorized = f.set & (1u << NL80211_STA_FLAG_AUTHORIZED);
			s.has |= RL_STA_FLAGS;
		}
	}
	c->cb(&s, c->ctx);
	return MNL_CB_OK;
}

int rl_nl80211_stations(rl_nl80211 *n, int ifindex, rl_nl_sta_cb cb, void *ctx)
{
	sta_ctx c = { ifindex, cb, ctx };
	struct nlmsghdr *nlh = put_req(n, n->family, NLM_F_DUMP, NL80211_CMD_GET_STATION, 0);
	mnl_attr_put_u32(nlh, NL80211_ATTR_IFINDEX, (uint32_t)ifindex);
	return exchange(n, nlh, sta_cb, &c);
}

/* ---- survey ---- */

typedef struct {
	uint32_t wiphy;
	rl_nl_survey_cb cb;
	void *ctx;
} survey_ctx;

static int survey_cb(const struct nlmsghdr *nlh, void *data)
{
	survey_ctx *c = data;
	const struct nlattr *tb[NL80211_ATTR_MAX + 1], *si[NL80211_SURVEY_INFO_MAX + 1];
	rl_survey_sample s;
	uint8_t noise;

	memset(&s, 0, sizeof(s));
	parse_msg(nlh, tb, NL80211_ATTR_MAX);
	if (!tb[NL80211_ATTR_SURVEY_INFO])
		return MNL_CB_OK;
	parse_nested(tb[NL80211_ATTR_SURVEY_INFO], si, NL80211_SURVEY_INFO_MAX);
	if (!get_u32(si[NL80211_SURVEY_INFO_FREQUENCY], &s.freq))
		return MNL_CB_OK;
	s.wiphy = c->wiphy;
	s.in_use = si[NL80211_SURVEY_INFO_IN_USE] != NULL;
	if (get_u8(si[NL80211_SURVEY_INFO_NOISE], &noise) && (int8_t)noise < 0) {
		s.noise = (int8_t)noise;
		s.has |= RL_SV_NOISE;
	}
	if (get_u64(si[NL80211_SURVEY_INFO_TIME], &s.active_ms))
		s.has |= RL_SV_ACTIVE;
	if (get_u64(si[NL80211_SURVEY_INFO_TIME_BUSY], &s.busy_ms))
		s.has |= RL_SV_BUSY;
	if (get_u64(si[NL80211_SURVEY_INFO_TIME_RX], &s.rx_ms))
		s.has |= RL_SV_RX;
	if (get_u64(si[NL80211_SURVEY_INFO_TIME_TX], &s.tx_ms))
		s.has |= RL_SV_TX;
	if (s.has)
		c->cb(&s, c->ctx);
	return MNL_CB_OK;
}

int rl_nl80211_survey(rl_nl80211 *n, int ifindex, uint32_t wiphy, rl_nl_survey_cb cb, void *ctx)
{
	survey_ctx c = { wiphy, cb, ctx };
	struct nlmsghdr *nlh = put_req(n, n->family, NLM_F_DUMP, NL80211_CMD_GET_SURVEY, 0);
	mnl_attr_put_u32(nlh, NL80211_ATTR_IFINDEX, (uint32_t)ifindex);
	return exchange(n, nlh, survey_cb, &c);
}
