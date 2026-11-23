#include "core/dnslog.h"

#include <string.h>

#include "core/series.h"

#define HEAD 14 /* ts, mac, qtype, rcode, name length */

size_t rl_dnslog_encode(uint8_t *out, size_t size, const rl_dnslog_rec *r)
{
	size_t nl = strnlen(r->name, RL_DNS_NAME_MAX);
	int n = r->n_addrs < 0 ? 0 : r->n_addrs > RL_DNS_MAX_ADDRS ? RL_DNS_MAX_ADDRS : r->n_addrs;
	size_t need = HEAD + nl + 1;
	for (int i = 0; i < n; i++)
		need += 1 + (r->addrs[i].family == 6 ? 16 : 4);
	if (need > size)
		return 0;
	rl_le_put32(out, (uint32_t)r->ts);
	memcpy(out + 4, r->mac, 6);
	rl_le_put16(out + 10, r->qtype);
	out[12] = r->rcode;
	out[13] = (uint8_t)nl;
	memcpy(out + 14, r->name, nl);
	uint8_t *p = out + 14 + nl;
	*p++ = (uint8_t)n;
	for (int i = 0; i < n; i++) {
		uint8_t family = r->addrs[i].family == 6 ? 6 : 4;
		size_t a = family == 6 ? 16 : 4;
		*p++ = family;
		memcpy(p, r->addrs[i].addr, a);
		p += a;
	}
	return (size_t)(p - out);
}

int rl_dnslog_decode(const uint8_t *rec, size_t len, rl_dnslog_rec *out)
{
	memset(out, 0, sizeof(*out));
	if (len < HEAD + 1)
		return -1;
	out->ts = rl_series_ts(rec);
	memcpy(out->mac, rec + 4, 6);
	out->qtype = rl_le_get16(rec + 10);
	out->rcode = rec[12];
	size_t nl = rec[13], off = HEAD;
	if (nl > RL_DNS_NAME_MAX || off + nl + 1 > len)
		return -1;
	memcpy(out->name, rec + off, nl);
	out->name[nl] = '\0';
	off += nl;
	int n = rec[off++];
	if (n > RL_DNS_MAX_ADDRS)
		return -1;
	for (int i = 0; i < n; i++) {
		if (off + 1 > len)
			return -1;
		uint8_t family = rec[off++];
		size_t a = family == 6 ? 16 : family == 4 ? 4 : 0;
		if (!a || off + a > len)
			return -1;
		out->addrs[i].family = family;
		memcpy(out->addrs[i].addr, rec + off, a);
		off += a;
	}
	out->n_addrs = n;
	return off == len ? 0 : -1;
}

bool rl_dnslog_match(const rl_dnslog_rec *r, const uint8_t *mac, const char *q)
{
	if (mac && memcmp(r->mac, mac, 6) != 0)
		return false;
	return !q || !q[0] || strstr(r->name, q) != NULL;
}
