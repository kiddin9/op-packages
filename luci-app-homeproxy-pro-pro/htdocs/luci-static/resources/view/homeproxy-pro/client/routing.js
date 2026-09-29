/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';

'require baseclass';
'require form';
'require uci';

'require homeproxy as hp';
'require view.homeproxy.client.common as common';

/* Routing tab and the wrapping custom-routing NamedSection. The
 * routing_node tab lives in nodes.js; the routing_rule sub-section is
 * shared with dns and lives in common.js as renderRuleSection. */
function render(ctx) {
	const { s, proxy_nodes, features, stubValidator } = ctx;
	let o, ss, so;

	s.tab('routing', _('Routing Settings'));

	o = s.taboption('routing', form.ListValue, 'main_node', _('Main node'));
	o.value('nil', _('Disable'));
	o.value('urltest', _('URLTest'));
	for (let i in proxy_nodes)
		o.value(i, proxy_nodes[i]);
	o.default = 'nil';
	o.depends({'routing_mode': 'custom', '!reverse': true});
	o.rmempty = false;

	o = s.taboption('routing', hp.CBIStaticList, 'main_urltest_nodes', _('URLTest nodes'),
		_('List of nodes to test.'));
	for (let i in proxy_nodes)
		o.value(i, proxy_nodes[i]);
	o.depends('main_node', 'urltest');
	o.rmempty = false;

	o = s.taboption('routing', form.Value, 'main_urltest_interval', _('Test interval'),
		_('The test interval in seconds.'));
	o.datatype = 'uinteger';
	o.placeholder = '180';
	o.depends('main_node', 'urltest');

	o = s.taboption('routing', form.Value, 'main_urltest_tolerance', _('Test tolerance'),
		_('The test tolerance in milliseconds.'));
	o.datatype = 'uinteger';
	o.placeholder = '50';
	o.depends('main_node', 'urltest');

	o = s.taboption('routing', form.ListValue, 'main_udp_node', _('Main UDP node'));
	o.value('nil', _('Disable'));
	o.value('same', _('Same as main node'));
	o.value('urltest', _('URLTest'));
	for (let i in proxy_nodes)
		o.value(i, proxy_nodes[i]);
	o.default = 'nil';
	o.depends({'routing_mode': /^((?!custom).)+$/, 'proxy_mode': /^((?!redirect$).)+$/});
	o.rmempty = false;

	o = s.taboption('routing', hp.CBIStaticList, 'main_udp_urltest_nodes', _('URLTest nodes'),
		_('List of nodes to test.'));
	for (let i in proxy_nodes)
		o.value(i, proxy_nodes[i]);
	o.depends('main_udp_node', 'urltest');
	o.rmempty = false;

	o = s.taboption('routing', form.Value, 'main_udp_urltest_interval', _('Test interval'),
		_('The test interval in seconds.'));
	o.datatype = 'uinteger';
	o.placeholder = '180';
	o.depends('main_udp_node', 'urltest');

	o = s.taboption('routing', form.Value, 'main_udp_urltest_tolerance', _('Test tolerance'),
		_('The test tolerance in milliseconds.'));
	o.datatype = 'uinteger';
	o.placeholder = '50';
	o.depends('main_udp_node', 'urltest');

	o = s.taboption('routing', form.ListValue, 'routing_mode', _('Routing mode'));
	o.value('gfwlist', _('GFWList'));
	o.value('bypass_mainland_china', _('Bypass mainland China'));
	o.value('proxy_mainland_china', _('Only proxy mainland China'));
	o.value('custom', _('Custom routing'));
	o.value('global', _('Global'));
	o.default = 'bypass_mainland_china';
	o.rmempty = false;
	o.onchange = function(ev, section_id, value) {
		/* Save on every transition, not only into custom: leaving custom
		 * leaves the user's `routing.default_outbound`, `default_outbound_dns`
		 * and `bypass_cn_traffic` in UCI. The generator's read-only-in-custom
		 * gate (5573269) keeps the generation valid, but the residue stays in
		 * the file until the next time someone enters custom and saves
		 * again, which is invisible to the user. Triggering save on every
		 * change makes the UCI state track the mode the user actually picked. */
		if (section_id && value)
			this.map.save(null, true);
	}

	o = s.taboption('routing', form.Value, 'routing_port', _('Routing ports'),
		_('Specify target ports to be proxied. Multiple ports must be separated by commas.'));
	o.value('', _('All ports'));
	o.value('common', _('Common ports only (bypass P2P traffic)'));
	o.validate = function(section_id, value) {
		if (section_id && value && value !== 'common') {

			let ports = [];
			for (let i of value.split(',')) {
				if (!stubValidator.apply('port', i) && !stubValidator.apply('portrange', i))
					return _('Expecting: %s').format(_('valid port value'));
				if (ports.includes(i))
					return _('Port %s alrealy exists!').format(i);
				ports = ports.concat(i);
			}
		}

		return true;
	}

	o = s.taboption('routing', form.ListValue, 'proxy_mode', _('Proxy mode'));
	o.value('redirect', _('Redirect TCP'));
	if (features.hp_has_tproxy)
		o.value('redirect_tproxy', _('Redirect TCP + TProxy UDP'));
	if (features.hp_has_ip_full && features.hp_has_tun) {
		o.value('redirect_tun', _('Redirect TCP + Tun UDP'));
		o.value('tun', _('Tun TCP/UDP'));
	} else {
		o.description = _('To enable Tun support, you need to install <code>ip-full</code> and <code>kmod-tun</code>');
	}
	o.default = 'redirect_tproxy';
	o.rmempty = false;

	o = s.taboption('routing', form.Flag, 'ipv6_support', _('IPv6 support'));
	o.default = o.enabled;
	o.rmempty = false;

	/* §2.7 (linux.json 与 pro 的差距分析): opt-in switch to the tutorial's
	 * universal sniffer list + 100ms timeout. Default off so an upgrade is
	 * invisible; arch-guard 40 pins the default '0' against drift. */
	o = s.taboption('routing', form.Flag, 'sniffer_advanced_mode',
		_('Sniffer: advanced mode (100ms, universal list)'),
		_('Use the tutorial-recommended sniffer profile (100ms timeout, http/tls/stun/quic/dns). Default keeps the 300ms / unconstrained-list behaviour.'));
	o.default = '0';
	o.rmempty = false;

	/* Custom routing settings start */
	/* Routing settings start */
	o = s.taboption('routing', form.SectionValue, '_routing', form.NamedSection, 'routing', 'homeproxy');
	o.depends('routing_mode', 'custom');

	ss = o.subsection;
	so = ss.option(form.ListValue, 'tcpip_stack', _('TCP/IP stack'),
		_('TCP/IP stack.'));
	if (features.with_gvisor) {
		so.value('mixed', _('Mixed'));
		so.value('gvisor', _('gVisor'));
	}
	so.value('system', _('System'));
	so.default = 'system';
	so.depends('homeproxy.config.proxy_mode', 'redirect_tun');
	so.depends('homeproxy.config.proxy_mode', 'tun');
	so.rmempty = false;
	so.onchange = function(ev, section_id, value) {
		let desc = ev.target.nextElementSibling;
		if (value === 'mixed')
			desc.innerHTML = _('Mixed <code>system</code> TCP stack and <code>gVisor</code> UDP stack.')
		else if (value === 'gvisor')
			desc.innerHTML = _('Based on google/gvisor.');
		else if (value === 'system')
			desc.innerHTML = _('Less compatibility and sometimes better performance.');
	}

	so = ss.option(form.Flag, 'endpoint_independent_nat', _('Enable endpoint-independent NAT'),
		_('Performance may degrade slightly, so it is not recommended to enable on when it is not needed.'));
	so.default = so.enabled;
	so.depends('tcpip_stack', 'mixed');
	so.depends('tcpip_stack', 'gvisor');
	so.rmempty = false;

	so = ss.option(form.Value, 'udp_timeout', _('UDP NAT expiration time'),
		_('In seconds.'));
	so.datatype = 'uinteger';
	so.placeholder = '300';
	so.depends('homeproxy.config.proxy_mode', 'redirect_tproxy');
	so.depends('homeproxy.config.proxy_mode', 'redirect_tun');
	so.depends('homeproxy.config.proxy_mode', 'tun');

	so = ss.option(form.Flag, 'bypass_cn_traffic', _('Bypass CN traffic'),
		_('Bypass mainland China traffic via firewall rules by default.'));
	so.rmempty = false;

	so = ss.option(form.Flag, 'find_neighbor', _('Find neighbor hosts'),
		_('Enable neighbor resolution so rules can match LAN devices by hostname (1.14).'));
	so.rmempty = false;

	so = ss.option(form.ListValue, 'domain_strategy', _('Domain strategy'),
		_('If set, the requested domain name will be resolved to IP before routing.'));
	for (let i in hp.dns_strategy)
		so.value(i, hp.dns_strategy[i]);

	so = ss.option(form.ListValue, 'default_outbound', _('Default outbound'),
		_('Default outbound for connections not matched by any routing rules.'));
	so.load = function(section_id) {
		delete this.keylist;
		delete this.vallist;

		this.value('nil', _('Disable (the service)'));
		this.value('direct-out', _('Direct'));
		this.value('block-out', _('Block'));
		uci.sections('homeproxy', 'routing_node', (res) => {
			if (res.enabled === '1')
				this.value(res['.name'], res.label);
		});

		return this.super('load', section_id);
	}
	so.default = 'nil';
	so.rmempty = false;

	so = ss.option(form.ListValue, 'default_outbound_dns', _('Default outbound DNS'),
		_('Default DNS server for resolving domain name in the server address.'));
	so.load = function(section_id) {
		delete this.keylist;
		delete this.vallist;

		this.value('default-dns', _('Default DNS (issued by WAN)'));
		this.value('system-dns', _('System DNS'));
		uci.sections('homeproxy', 'dns_server', (res) => {
			if (res.enabled === '1')
				this.value(res['.name'], res.label);
		});

		return this.super('load', section_id);
	}
	so.default = 'default-dns';
	so.rmempty = false;
	/* Routing settings end */
}

/* Routing rule sub-section. Split out from render() so the orchestrator can
 * call it after nodes.renderRoutingNodes() and preserve the original tab
 * ordering (routing, routing_node, routing_rule). */
function renderRoutingRules(ctx) {
	const { s, self } = ctx;

	/* Routing rules start */
	common.renderRuleSection(s, 'routing', self);
	/* Routing rules end */
}

return baseclass.extend({ render, renderRoutingRules });
