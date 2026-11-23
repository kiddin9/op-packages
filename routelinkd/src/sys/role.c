#include <string.h>
#include <uci.h>

#include <libubox/blobmsg.h>

#include "sys/role.h"

static bool truthy(const char *v)
{
	return v && (!strcmp(v, "1") || !strcmp(v, "true") || !strcmp(v, "on") || !strcmp(v, "yes"));
}

static rl_offload detect_offload(void)
{
	rl_offload o = RL_OFFLOAD_NONE;
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (!ctx)
		return o;
	if (uci_load(ctx, "firewall", &pkg) == UCI_OK && pkg) {
		struct uci_element *e;
		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			if (strcmp(s->type, "defaults"))
				continue;
			if (truthy(uci_lookup_option_string(ctx, s, "flow_offloading")))
				o = RL_OFFLOAD_SOFTWARE;
			if (truthy(uci_lookup_option_string(ctx, s, "flow_offloading_hw")))
				o = RL_OFFLOAD_HARDWARE;
		}
	}
	/* Lean / ImmortalWrt "Turbo ACC" */
	pkg = NULL;
	if (o == RL_OFFLOAD_NONE && uci_load(ctx, "turboacc", &pkg) == UCI_OK && pkg) {
		struct uci_element *e;
		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			if (truthy(uci_lookup_option_string(ctx, s, "hw_flow")))
				o = RL_OFFLOAD_HARDWARE;
			else if (truthy(uci_lookup_option_string(ctx, s, "sfe_flow")))
				o = RL_OFFLOAD_SFE;
			else if (truthy(uci_lookup_option_string(ctx, s, "sw_flow")) && o == RL_OFFLOAD_NONE)
				o = RL_OFFLOAD_SOFTWARE;
		}
	}
	uci_free_context(ctx);
	return o;
}

/* service list {name: "nlbwmon"} -> { nlbwmon: { instances: { x: { running: true } } } } */
static void service_cb(struct ubus_request *req, int type, struct blob_attr *msg)
{
	bool *running = req->priv;
	struct blob_attr *svc, *inst, *cur;
	int rem, rem2;
	blob_for_each_attr(svc, msg, rem) {
		blobmsg_for_each_attr(inst, svc, rem2) {
			if (strcmp(blobmsg_name(inst), "instances"))
				continue;
			int rem3;
			blobmsg_for_each_attr(cur, inst, rem3) {
				static const struct blobmsg_policy p = { "running", BLOBMSG_TYPE_BOOL };
				struct blob_attr *r;
				blobmsg_parse(&p, 1, &r, blobmsg_data(cur), blobmsg_len(cur));
				if (r && blobmsg_get_bool(r))
					*running = true;
			}
		}
	}
}

static bool nlbwmon_running(struct ubus_context *ctx)
{
	uint32_t id;
	bool running = false;
	struct blob_buf b = { 0 };
	if (!ctx || ubus_lookup_id(ctx, "service", &id))
		return false;
	blob_buf_init(&b, 0);
	blobmsg_add_string(&b, "name", "nlbwmon");
	ubus_invoke(ctx, id, "list", b.head, service_cb, &running, 2000);
	blob_buf_free(&b);
	return running;
}

void rl_role_detect(struct ubus_context *ctx, const rl_netinfo *ni, rl_role *r)
{
	r->gateway = ni->has_wan;
	r->offload = detect_offload();
	r->nlbwmon_running = nlbwmon_running(ctx);
}

bool rl_role_wifi_configured(void)
{
	bool found = false;
	struct uci_context *ctx = uci_alloc_context();
	struct uci_package *pkg = NULL;
	if (!ctx)
		return false;
	if (uci_load(ctx, "wireless", &pkg) == UCI_OK && pkg) {
		struct uci_element *e;
		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			if (strcmp(s->type, "wifi-iface") || truthy(uci_lookup_option_string(ctx, s, "disabled")))
				continue;
			const char *mode = uci_lookup_option_string(ctx, s, "mode");
			const char *dev = uci_lookup_option_string(ctx, s, "device");
			if (mode && strcmp(mode, "ap"))
				continue;
			struct uci_section *radio = dev ? uci_lookup_section(ctx, pkg, dev) : NULL;
			if (radio && truthy(uci_lookup_option_string(ctx, radio, "disabled")))
				continue;
			found = true;
			break;
		}
	}
	uci_free_context(ctx);
	return found;
}

const char *rl_offload_name(rl_offload o)
{
	switch (o) {
	case RL_OFFLOAD_SOFTWARE:
		return "software";
	case RL_OFFLOAD_HARDWARE:
		return "hardware";
	case RL_OFFLOAD_SFE:
		return "sfe";
	default:
		return "none";
	}
}

bool rl_offload_warning(rl_offload o)
{
	return o == RL_OFFLOAD_HARDWARE || o == RL_OFFLOAD_SFE;
}
