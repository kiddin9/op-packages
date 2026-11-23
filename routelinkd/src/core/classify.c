#include "core/classify.h"

static bool is_router(const rl_netview *nv, const rl_ip *ip)
{
	return rl_cidr_set_contains(&nv->router_addrs, ip);
}

/* A LAN device: inside a LAN subnet and not one of the router's own addresses. */
static bool is_local(const rl_netview *nv, const rl_ip *ip)
{
	return rl_cidr_set_contains(&nv->local, ip) && !is_router(nv, ip);
}

static void add(rl_attribution *a, const rl_ip *client, bool router, rl_class cls, bool is_orig)
{
	if (a->n >= 2)
		return;
	if (client)
		a->a[a->n].client = *client;
	a->a[a->n].router = router;
	a->a[a->n].cls = cls;
	a->a[a->n].client_is_orig = is_orig;
	a->n++;
}

rl_attribution rl_classify(const rl_netview *nv, const rl_ct_sample *s)
{
	rl_attribution a = { 0 };
	bool os_local = is_local(nv, &s->orig_src), os_router = is_router(nv, &s->orig_src);
	bool od_local = is_local(nv, &s->orig_dst), od_router = is_router(nv, &s->orig_dst);
	bool rs_local = is_local(nv, &s->reply_src), rs_router = is_router(nv, &s->reply_src);

	if (os_router) {
		if (od_local || rs_local) /* router talks to a device */
			add(&a, rs_local ? &s->reply_src : &s->orig_dst, false, RL_CLASS_LAN, false);
		else if (!od_router)
			add(&a, NULL, true, RL_CLASS_ROUTER, true);
		return a;
	}

	if (os_local) {
		if (od_local) {
			add(&a, &s->orig_src, false, RL_CLASS_LAN, true);
			add(&a, rs_local ? &s->reply_src : &s->orig_dst, false, RL_CLASS_LAN, false);
		} else if (od_router) {
			add(&a, &s->orig_src, false, RL_CLASS_LAN, true);
			/* hairpin NAT to another device */
			if (rs_local && !rl_ip_eq(&s->reply_src, &s->orig_src))
				add(&a, &s->reply_src, false, RL_CLASS_LAN, false);
		} else {
			/* the destination decides: a transparent proxy that redirects to the router is still internet use */
			add(&a, &s->orig_src, false, RL_CLASS_INTERNET, true);
		}
		return a;
	}

	/* opened from outside */
	if (rs_local)
		add(&a, &s->reply_src, false, RL_CLASS_INTERNET, false);
	else if (od_local)
		add(&a, &s->orig_dst, false, RL_CLASS_INTERNET, false);
	else if (od_router || rs_router)
		add(&a, NULL, true, RL_CLASS_ROUTER, false);
	return a;
}

void rl_client_bytes(bool client_is_orig, rl_delta d, uint64_t *rx, uint64_t *tx)
{
	*tx = client_is_orig ? d.orig_bytes : d.reply_bytes;
	*rx = client_is_orig ? d.reply_bytes : d.orig_bytes;
}

const char *rl_class_name(rl_class c)
{
	static const char *const names[RL_CLASS_COUNT] = { "internet", "lan", "router" };
	return c < RL_CLASS_COUNT ? names[c] : "?";
}
