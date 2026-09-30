/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';

'require baseclass';
'require form';
'require uci';

'require homeproxy-pro as hp';
'require view.homeproxy-pro.client.common as common';

/* DNS settings: both routing-mode families in one tab.
 *
 * They used to be two tabs with the same title ('dns' and 'dns_cache'), each
 * wrapping the same 'dns' NamedSection.  Two form.NamedSection instances over
 * one UCI section produce identical cbids, and LuCI resolves a cbid by taking
 * the first matching element in DOM order - which follows tab registration,
 * i.e. the custom-mode tab.  The four cache options were registered in both,
 * so under a preset routing mode the controls the user could actually see were
 * reading and writing an element inside a hidden tab: "Store DNS cache" and
 * "DNS query timeout" did not take.
 *
 * The tab is declared once now and no option name is registered twice, so
 * there is no first-match to get wrong.  Each option carries the routing mode
 * it belongs to as a depends(). */
function renderDnsCacheOptions(ss) {
	let so;

	so = ss.option(form.Flag, 'optimistic_cache', _('Optimistic DNS cache'),
		_('Return expired cache immediately and refresh in background (sing-box 1.14).'));
	so.depends('disable_cache', '0');
	so.depends('disable_cache_expire', '0');
	so.rmempty = false;

	so = ss.option(form.Value, 'optimistic_timeout', _('Optimistic cache timeout'),
		_('Max time an expired entry may be served. Examples: 3d, 1h.'));

	so = ss.option(form.Value, 'dns_timeout', _('DNS query timeout'),
		_('Default timeout per DNS query in seconds (sing-box default: 10).'));
	so.datatype = 'uinteger';

	so = ss.option(form.Flag, 'cache_file_store_dns', _('Store DNS cache'),
		_('Persist DNS cache across restarts (sing-box 1.14, replaces Store RDRC).'));
	so.depends('disable_cache', '0');
	so.rmempty = false;
}

/* DNS settings tab plus the wrapping 'dns' NamedSection. Called after
 * routing.renderRoutingRules() so the NamedSection chain reads
 * config -> routing_node -> routing_rule -> dns from left to right. */
function renderDnsSettings(ctx) {
	const { s, stubValidator } = ctx;
	let o, ss, so;

	s.tab('dns', _('DNS Settings'));

	/* The preset-mode fields.  They belong to the 'config' section, not to
	 * 'dns', so they were never part of the duplicate-cbid problem above -
	 * they are rendered here because this is the only DNS tab now.
	 *
	 * The name says overseas because that is the only thing that belongs
	 * here: every query this field answers goes to a domain that is not on
	 * the China path, and a domestic resolver answers those with polluted or
	 * NXDOMAIN results.  The Chinese public resolvers that used to be listed
	 * below a divider were therefore a footgun with a helpful-looking label -
	 * the one combination that reliably breaks a working proxy.  Only the
	 * overseas public resolvers are offered now. */
	o = s.taboption('dns', form.Value, 'dns_server', _('Overseas DNS server'),
		_('Resolves every domain that is not on the China DNS path, through the selected proxy node. ' +
		'A domestic resolver answers these queries with polluted or NXDOMAIN results, which is what ' +
		'makes a foreign site fail to resolve while the proxy itself works - so only overseas services ' +
		'are offered here. Support UDP, TCP, DoH, DoQ, DoT. TCP protocol will be used if not specified.'));
	o.value('1.1.1.1', _('CloudFlare Public DNS (1.1.1.1)'));
	o.value('208.67.222.222', _('Cisco Public DNS (208.67.222.222)'));
	o.value('8.8.8.8', _('Google Public DNS (8.8.8.8)'));
	o.default = '8.8.8.8';
	o.rmempty = false;
	o.depends({'routing_mode': 'custom', '!reverse': true});
	o.validate = function(section_id, value) {
		if (section_id) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));

			let ipv6_support = this.section.formvalue(section_id, 'ipv6_support');
			try {
				let url = new URL(value.replace(/^.*:\/\//, 'http://'));
				if (stubValidator.apply('hostname', url.hostname))
					return true;
				else if (stubValidator.apply('ip4addr', url.hostname))
					return true;
				else if ((ipv6_support === '1') && stubValidator.apply('ip6addr', url.hostname.match(/^\[(.+)\]$/)?.[1]))
					return true;
				else
					return _('Expecting: %s').format(_('valid DNS server address'));
			} catch(e) {}

			if (!stubValidator.apply((ipv6_support === '1') ? 'ipaddr' : 'ip4addr', value))
				return _('Expecting: %s').format(_('valid DNS server address'));
		}

		return true;
	}

	o = s.taboption('dns', form.Value, 'china_dns_server', _('China DNS server'),
		_('Resolves the domains on the China path, so it has to be a domestic service to get the ' +
		'correct local CDN answers. Keep the default; the upstream may block UDP/53, in which case ' +
		'a DoH address (https://dns.alidns.com/dns-query, https://doh.pub/dns-query) also works. ' +
		'Support UDP, TCP, DoH, DoQ, DoT. A DoH/DoT address here also sends the bootstrap ' +
		'lookup back to the WAN resolver: only a bare IP can resolve the proxy DNS endpoint ' +
		'without the ISP.'));
	o.value('wan', _('WAN DNS (read from interface)'));
	o.value('223.5.5.5', _('Aliyun Public DNS (223.5.5.5)'));
	o.value('210.2.4.8', _('CNNIC Public DNS (210.2.4.8)'));
	o.value('119.29.29.29', _('Tencent Public DNS (119.29.29.29)'));
	o.value('117.50.10.10', _('ThreatBook Public DNS (117.50.10.10)'));
	o.depends('routing_mode', 'bypass_mainland_china');
	o.default = '223.5.5.5';
	o.rmempty = false;
	o.validate = function(section_id, value) {
		if (section_id && !['wan'].includes(value)) {
			if (!value)
				return _('Expecting: %s').format(_('non-empty value'));

			try {
				let url = new URL(value.replace(/^.*:\/\//, 'http://'));
				if (stubValidator.apply('hostname', url.hostname))
					return true;
				else if (stubValidator.apply('ip4addr', url.hostname))
					return true;
				else if (stubValidator.apply('ip6addr', url.hostname.match(/^\[(.+)\]$/)?.[1]))
					return true;
				else
					return _('Expecting: %s').format(_('valid DNS server address'));
			} catch(e) {}

			if (!stubValidator.apply('ipaddr', value))
				return _('Expecting: %s').format(_('valid DNS server address'));
		}

		return true;
	}

	o = s.taboption('dns', form.Flag, 'cn_ip_fallback', _('CN-IP DNS fallback (sing-box 1.14)'),
		_('When the main DNS returns a mainland China IP, re-resolve via China DNS using evaluate/match_response.'));
	o.depends('routing_mode', 'bypass_mainland_china');
	o.rmempty = false;

	/* The 'dns' section, registered exactly once: see the file header.  The
	 * custom-only options below keep their own depends() because the section
	 * is visible in both routing-mode families. */
	o = s.taboption('dns', form.SectionValue, '_dns', form.NamedSection, 'dns', 'homeproxy-pro');
	ss = o.subsection;

	so = ss.option(form.ListValue, 'default_strategy', _('Default DNS strategy'),
		_('The DNS strategy for resolving the domain name in the address.'));
	for (let i in hp.dns_strategy)
		so.value(i, hp.dns_strategy[i]);
	so.depends('routing_mode', 'custom');

	so = ss.option(form.ListValue, 'default_server', _('Default DNS server'));
	so.load = function(section_id) {
		delete this.keylist;
		delete this.vallist;

		this.value('default-dns', _('Default DNS (issued by WAN)'));
		this.value('system-dns', _('System DNS'));
		uci.sections('homeproxy-pro', 'dns_server', (res) => {
			if (res.enabled !== '0')
				this.value(res['.name'], res.label);
		});

		return this.super('load', section_id);
	}
	so.default = 'default-dns';
	so.rmempty = false;
	so.depends('routing_mode', 'custom');

	so = ss.option(form.Flag, 'disable_cache', _('Disable DNS cache'));

	so = ss.option(form.Flag, 'disable_cache_expire', _('Disable cache expire'));
	so.depends('disable_cache', '0');

	so = ss.option(form.Value, 'client_subnet', _('EDNS Client subnet'),
		_('Append a <code>edns0-subnet</code> OPT extra record with the specified IP prefix to every query by default.<br/>' +
		'If value is an IP address instead of prefix, <code>/32</code> or <code>/128</code> will be appended automatically.'));
	so.datatype = 'or(cidr, ipaddr)';
	so.depends('routing_mode', 'custom');

	/* The four cache options are common to both families, so they are
	 * registered once, with no routing-mode dependency of their own. */
	renderDnsCacheOptions(ss);
	/* DNS settings end */
}

/* DNS rules sub-section. Split out from renderDnsSettings() so the
 * orchestrator can call it after nodes.renderDnsServers() and preserve
 * the original tab ordering (dns, dns_server, dns_rule). */
function renderDnsRules(ctx) {
	const { s, self } = ctx;

	/* DNS rules start */
	common.renderRuleSection(s, 'dns', self);
	/* DNS rules end */
}

return baseclass.extend({ renderDnsSettings, renderDnsRules });
