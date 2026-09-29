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
'require tools.firewall as fwtool';
'require tools.widgets as widgets';

/* Access Control tab. Five sub-tabs (interface control, LAN IP policy,
 * WAN IP policy, proxy domain list, direct domain list). Each domain-list
 * sub-tab reads/writes the proxy_list / direct_list files through an
 * ubus RPC; the load callback is the only path that touches that RPC. */
function render(ctx) {
	const { s, hosts, stubValidator } = ctx;
	let o, ss, so;

	s.tab('control', _('Access Control'));

	o = s.taboption('control', form.SectionValue, '_control', form.NamedSection, 'control', 'homeproxy');
	ss = o.subsection;

	/* Interface control start */
	ss.tab('interface', _('Interface Control'));

	so = ss.taboption('interface', widgets.DeviceSelect, 'listen_interfaces', _('Listen interfaces'),
		_('Only process traffic from specific interfaces. Leave empty for all.'));
	so.multiple = true;
	so.noaliases = true;

	so = ss.taboption('interface', widgets.DeviceSelect, 'bind_interface', _('Bind interface'),
		_('Bind outbound traffic to specific interface. Leave empty to auto detect.'));
	so.multiple = false;
	so.noaliases = true;
	/* Interface control end */

	/* LAN IP policy start */
	ss.tab('lan_ip_policy', _('LAN IP Policy'));

	so = ss.taboption('lan_ip_policy', form.ListValue, 'lan_proxy_mode', _('Proxy filter mode'));
	so.value('disabled', _('Disable'));
	so.value('listed_only', _('Proxy listed only'));
	so.value('except_listed', _('Proxy all except listed'));
	so.default = 'disabled';
	so.rmempty = false;

	so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_direct_ipv4_ips', _('Direct IPv4 IP-s'), null, 'ipv4', hosts, true);
	so.depends('lan_proxy_mode', 'except_listed');

	so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_direct_ipv6_ips', _('Direct IPv6 IP-s'), null, 'ipv6', hosts, true);
	so.depends({'lan_proxy_mode': 'except_listed', 'homeproxy.config.ipv6_support': '1'});

	so = fwtool.addMACOption(ss, 'lan_ip_policy', 'lan_direct_mac_addrs', _('Direct MAC-s'), null, hosts);
	so.depends('lan_proxy_mode', 'except_listed');

	so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_proxy_ipv4_ips', _('Proxy IPv4 IP-s'), null, 'ipv4', hosts, true);
	so.depends('lan_proxy_mode', 'listed_only');

	so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_proxy_ipv6_ips', _('Proxy IPv6 IP-s'), null, 'ipv6', hosts, true);
	so.depends({'lan_proxy_mode': 'listed_only', 'homeproxy.config.ipv6_support': '1'});

	so = fwtool.addMACOption(ss, 'lan_ip_policy', 'lan_proxy_mac_addrs', _('Proxy MAC-s'), null, hosts);
	so.depends('lan_proxy_mode', 'listed_only');

	so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_gaming_mode_ipv4_ips', _('Gaming mode IPv4 IP-s'), null, 'ipv4', hosts, true);

	so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_gaming_mode_ipv6_ips', _('Gaming mode IPv6 IP-s'), null, 'ipv6', hosts, true);
	so.depends('homeproxy.config.ipv6_support', '1');

	so = fwtool.addMACOption(ss, 'lan_ip_policy', 'lan_gaming_mode_mac_addrs', _('Gaming mode MAC-s'), null, hosts);

	so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_global_proxy_ipv4_ips', _('Global proxy IPv4 IP-s'), null, 'ipv4', hosts, true);
	so.depends({'homeproxy.config.routing_mode': 'custom', '!reverse': true});

	so = fwtool.addIPOption(ss, 'lan_ip_policy', 'lan_global_proxy_ipv6_ips', _('Global proxy IPv6 IP-s'), null, 'ipv6', hosts, true);
	so.depends({'homeproxy.config.routing_mode': /^((?!custom).)+$/, 'homeproxy.config.ipv6_support': '1'});

	so = fwtool.addMACOption(ss, 'lan_ip_policy', 'lan_global_proxy_mac_addrs', _('Global proxy MAC-s'), null, hosts);
	so.depends({'homeproxy.config.routing_mode': 'custom', '!reverse': true});
	/* LAN IP policy end */

	/* WAN IP policy start */
	ss.tab('wan_ip_policy', _('WAN IP Policy'));

	so = ss.taboption('wan_ip_policy', form.DynamicList, 'wan_proxy_ipv4_ips', _('Proxy IPv4 IP-s'));
	so.datatype = 'or(ip4addr, cidr4)';

	so = ss.taboption('wan_ip_policy', form.DynamicList, 'wan_proxy_ipv6_ips', _('Proxy IPv6 IP-s'));
	so.datatype = 'or(ip6addr, cidr6)';
	so.depends('homeproxy.config.ipv6_support', '1');

	so = ss.taboption('wan_ip_policy', form.DynamicList, 'wan_direct_ipv4_ips', _('Direct IPv4 IP-s'));
	so.datatype = 'or(ip4addr, cidr4)';

	so = ss.taboption('wan_ip_policy', form.DynamicList, 'wan_direct_ipv6_ips', _('Direct IPv6 IP-s'));
	so.datatype = 'or(ip6addr, cidr6)';
	so.depends('homeproxy.config.ipv6_support', '1');
	/* WAN IP policy end */

	/* Proxy domain list start */
	ss.tab('proxy_domain_list', _('Proxy Domain List'));

	so = ss.taboption('proxy_domain_list', form.TextValue, '_proxy_domain_list');
	so.rows = 10;
	so.monospace = true;
	so.datatype = 'hostname';
	so.description = _('One domain per line. No spaces, no comments, no wildcards; the backend rejects invalid characters and tells you which line.');
	so.depends({'homeproxy.config.routing_mode': 'custom', '!reverse': true});
	so.load = function(/* ... */) {
		return hp.rpcCall('acllist_read', ['proxy_list'],
				{ params: ['type'], expect: { '': {} } }).then((res) => {
			/* acllist_read returns { content: null, error: '...' }
			 * when the backend rejected the request (bad type, file
			 * unreadable, ...). Surface the error instead of silently
			 * resolving to "" which makes the field look unchanged. */
			if (res && res.error)
				ui.addNotification(null, E('p', _('Failed to read domain list: %s.').format(res.error)));
			return res ? res.content : '';
		}, {});
	}
	so.write = function(_section_id, value) {
		return hp.rpcCall('acllist_write', ['proxy_list', value], { params: ['type', 'content'], expect: { '': {} } }).then((ret) => {
			/* Without this, a backend error like "UCI commit failed"
			 * is silently dropped and the user sees the old value
			 * reappear after refresh with no explanation. */
			if (ret && ret.result === false)
				throw (ret.error || 'unknown error');
			return true;
		});
	}
	so.remove = function(/* ... */) {
		/* routing_mode is an option of the page's 'config' NamedSection, not
		 * of this nested 'control' one: `this.section.formvalue(...)` walks
		 * the children of `this.section`, never found it and returned null,
		 * so the test below was always true and a reset wiped the file even
		 * in custom mode, where the list is in use. Read the saved UCI value
		 * the backend will act on. */
		let routing_mode = uci.get('homeproxy', 'config', 'routing_mode');
		if (routing_mode !== 'custom')
			return hp.rpcCall('acllist_write', ['proxy_list', ''], { params: ['type', 'content'], expect: { '': {} } }).then((ret) => {
				if (ret && ret.result === false)
					throw (ret.error || 'unknown error');
				return true;
			});
		return true;
	}
	so.validate = function(section_id, value) {
		if (section_id && value)
			for (let i of value.split('\n'))
				if (i && !stubValidator.apply('hostname', i))
					return _('Expecting: %s').format(_('valid hostname'));

		return true;
	}
	/* Proxy domain list end */

	/* Direct domain list start */
	ss.tab('direct_domain_list', _('Direct Domain List'));

	so = ss.taboption('direct_domain_list', form.TextValue, '_direct_domain_list');
	so.rows = 10;
	so.monospace = true;
	so.datatype = 'hostname';
	so.description = _('One domain per line. No spaces, no comments, no wildcards; the backend rejects invalid characters and tells you which line.');
	so.depends({'homeproxy.config.routing_mode': 'custom', '!reverse': true});
	so.load = function(/* ... */) {
		return hp.rpcCall('acllist_read', ['direct_list'],
				{ params: ['type'], expect: { '': {} } }).then((res) => {
			if (res && res.error)
				ui.addNotification(null, E('p', _('Failed to read domain list: %s.').format(res.error)));
			return res ? res.content : '';
		}, {});
	}
	so.write = function(_section_id, value) {
		return hp.rpcCall('acllist_write', ['direct_list', value], { params: ['type', 'content'], expect: { '': {} } }).then((ret) => {
			if (ret && ret.result === false)
				throw (ret.error || 'unknown error');
			return true;
		});
	}
	so.remove = function(/* ... */) {
		/* Same `this.section` mistake as the proxy list above. */
		let routing_mode = uci.get('homeproxy', 'config', 'routing_mode');
		if (routing_mode !== 'custom')
			return hp.rpcCall('acllist_write', ['direct_list', ''], { params: ['type', 'content'], expect: { '': {} } }).then((ret) => {
				if (ret && ret.result === false)
					throw (ret.error || 'unknown error');
				return true;
			});
		return true;
	}
	so.validate = function(section_id, value) {
		if (section_id && value)
			for (let i of value.split('\n'))
				if (i && !stubValidator.apply('hostname', i))
					return _('Expecting: %s').format(_('valid hostname'));

		return true;
	}
	/* Direct domain list end */
	/* ACL settings end */
}

return baseclass.extend({ render });
