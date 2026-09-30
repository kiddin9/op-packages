/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';

'require form';
'require network';
'require poll';
'require uci';
'require validation';
'require view';

'require homeproxy-pro as hp';
'require view.homeproxy-pro.client.common as common';
'require view.homeproxy-pro.client.routing as routing';
'require view.homeproxy-pro.client.nodes as nodes';
'require view.homeproxy-pro.client.dns as dns';
'require view.homeproxy-pro.client.access as access';
'require view.homeproxy-pro.client.subscription as subscription';
'require view.homeproxy-pro.client.udp_nat as udp_nat';
'require view.homeproxy-pro.client.tun_dns as tun_dns';

/* Module-scoped guard: register the view-level status poll exactly
 * once, regardless of how many times the view's render() runs (LuCI
 * sometimes re-invokes the view handler on UCI commit). Without this,
 * poll.add() inside a section render() handler leaks a fresh handler
 * on every render and the status bar starts updating multiple times
 * per tick. */
/* Built on the first render, so the poll closure captures that render's
 * features.version. The "have we registered" state lives inside
 * hp.statusPoller(), shared with the other view. */
let ensureStatusPoll = null;

function getServiceStatus() {
	/* The fallback is `null`, not `{}`: that is what lets the caller tell
	 * "the status query did not answer" from "the service is not running".
	 * With the default `{}` the try/catch below swallowed the difference and
	 * reported a failed query as NOT RUNNING. */
	return hp.rpcCall('list', ['homeproxy-pro'],
			{ object: 'service', params: ['name'], expect: { '': {} }, fallback: null }).then((res) => {
		if (res === null)
			return null;

		try {
			return res['homeproxy-pro']['instances']['sing-box-c']['running'] === true;
		} catch (e) {
			/* It answered, and there is no such instance. */
			return false;
		}
	});
}

function renderStatus(isRunning, version) {
	/* Defense-in-depth: features.version comes from `sing-box version`
	 * stdout parsed by a regex, but it is interpolated into an
	 * `innerHTML =` sink. Force the version through a strict allow-list
	 * regex (semver-ish) so a hostile sing-box binary - or a future
	 * change to the parser - cannot smuggle HTML into this template.
	 * Anything that does not match renders as 'unknown' instead of
	 * being silently dropped. */
	let safeVersion = 'unknown';
	if (typeof version === 'string' && /^[\w.\-+]+$/.test(version))
		safeVersion = version;

	const state = hp.statusLabel(isRunning);
	return '<em><span style="color:%s"><strong>%s (sing-box v%s) %s</strong></span></em>'
		.format(state.color, _('HomeProxy'), safeVersion, state.text);
}

let stubValidator = {
	/* Forward the type functions from the real validator module and let
	 * them call back into their factory. validation.js exports the
	 * ValidatorFactory instance; without `factory` here the chained
	 * apply() falls off the edge and `this.factory.parseIPv4` throws
	 * "undefined is not an object" the first time a node's address is
	 * fed through `ip6addr`/`ip4addr`/`cidr4`/etc. (commit 67d2c3a
	 * missed the factory wiring when it added this helper). */
	factory: validation,
	apply(type, value, args) {
		if (value != null)
			this.value = value;

		return validation.types[type].apply(this, args);
	},
	assert(condition) {
		return !!condition;
	}
};

return view.extend({
	load() {
		return Promise.all([
			uci.load('homeproxy-pro'),
			hp.getBuiltinFeatures(),
			network.getHostHints()
		]);
	},

	render(data) {
		let m, s;

		let features = data[1],
		    hosts = data[2]?.hosts;

		/* Cache all configured proxy nodes, they will be called multiple times */
		let proxy_nodes = {};
		uci.sections('homeproxy-pro', 'node', (res) => {
			let nodeaddr = ((res.type === 'direct') ? res.override_address : res.address) || '',
			    nodeport = ((res.type === 'direct') ? res.override_port : res.port) || '';

			proxy_nodes[res['.name']] =
				String.format('[%s] %s', res.type, res.label || ((stubValidator.apply('ip6addr', nodeaddr) ?
					String.format('[%s]', nodeaddr) : nodeaddr) + ':' + nodeport));
		});

		m = new form.Map('homeproxy-pro', _('HomeProxy'),
			_('The modern ImmortalWrt proxy platform for ARM64/AMD64.'));

		s = m.section(form.TypedSection);
		s.render = function () {
			/* The status bar is rendered into the page body by the
			 * view-level poll handler below. This section only paints the
			 * placeholder; registering poll.add() here would leak a fresh
			 * poll handler every time the user calls map.reset() (every
			 * UCI write re-renders this section). */
			return E('div', { class: 'cbi-section', id: 'status_bar' }, [
					E('p', { id: 'service_status' }, _('Collecting data...'))
			]);
		}

		/* View-level poll: registered exactly once per navigation, never
		 * inside a section's render() handler. getElementById may return
		 * null when LuCI swaps the DOM tree between renders - guard
		 * against it instead of throwing. */
		if (ensureStatusPoll === null)
			ensureStatusPoll = hp.statusPoller({
				poll: poll,
				read: getServiceStatus,
				paint: function(res) {
					let view = document.getElementById('service_status');
					if (view)
						view.innerHTML = renderStatus(res, features.version);
				}
			});

		ensureStatusPoll();

		s = m.section(form.NamedSection, 'config', 'homeproxy-pro');

		/* ctx bundles the values each tab needs so the tab modules don't
		 * have to recompute them. The destructuring keys are intentionally
		 * explicit - a tab that grabs something not in this list is a bug. */
		const ctx = {
			s, features, hosts, proxy_nodes,
			stubValidator, self: this,
		};

		/* Tab ordering follows the order of these calls: routing,
		 * routing_node, routing_rule, dns, dns_server, dns_rule, ruleset,
		 * dns_cache, control, udp_nat, tun_dns. The DNS tab sits before
		 * Access Control because the pages a preset-routing-mode user
		 * actually sees are Routing Settings, DNS Settings, Access Control,
		 * UDP NAT Settings and TUN DNS, in that order. The shared
		 * rule-section bodies live in common.js and are called out-of-order
		 * with respect to their file to keep the rendering sequence intact. */
		routing.render(ctx);
		nodes.renderRoutingNodes(ctx);
		routing.renderRoutingRules(ctx);
		dns.renderDnsSettings(ctx);
		nodes.renderDnsServers(ctx);
		dns.renderDnsRules(ctx);
		subscription.render(ctx);
		dns.renderDnsCache(ctx);
		access.render(ctx);
		udp_nat.renderUdpNat(ctx);
		tun_dns.renderTunDns(ctx);

		return m.render();
	}
});
