/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';

'require baseclass';
'require form';

/* TUN DNS tab - the rightmost tab.  These two options configure sing-box's
 * own DNS handling inside the TUN interface, which is a different thing from
 * the DNS servers and cache settings on the "DNS Settings" page; keeping them
 * there made three labels starting with "DNS server"/"TUN DNS" sit next to
 * each other on one page.
 *
 * They are config.* options and depend on proxy_mode (TUN modes only), not on
 * routing_mode, so they appear for custom and preset routing alike.  The tab
 * has no depends() of its own: both options depend on proxy_mode, so any
 * other proxy mode hides them and LuCI drops the empty tab with them. */
function renderTunDns(ctx) {
	const { s } = ctx;
	let o;

	s.tab('tun_dns', _('TUN DNS'));

	o = s.taboption('tun_dns', form.ListValue, 'tun_dns_mode', _('TUN DNS mode (1.14)'),
		_('Since sing-box 1.14 the default (Unset) behaves as hijack: sing-box sets the platform interface DNS and hijacks port 53. On OpenWrt this overlaps with the own dnsmasq/nftables DNS hijack of this plugin, so keep Disabled on a gateway unless you need sing-box to own TUN DNS.'));
	o.value('default', _('Unset (default)'));
	o.value('disabled', _('Disabled'));
	o.value('native', _('Native'));
	o.value('hijack', _('Hijack'));
	o.depends('proxy_mode', 'redirect_tun');
	o.depends('proxy_mode', 'tun');
	o.default = 'default';
	o.rmempty = true;

	o = s.taboption('tun_dns', form.DynamicList, 'tun_dns_address', _('TUN DNS addresses (1.14)'));
	o.datatype = 'ipaddr';
	/* The old `proxy_mode: /^((?!custom).)+$/` was written as if proxy_mode
	 * could be 'custom' - it cannot (the values are redirect / redirect_tproxy
	 * / redirect_tun / tun), so the condition was always true and the address
	 * field showed up in plain redirect mode too.  Match the two TUN modes,
	 * the same way tun_dns_mode above does. */
	o.depends({'proxy_mode': /^(redirect_tun|tun)$/, 'tun_dns_mode': /^(disabled|native|hijack)$/});
	o.modalonly = true;
}

return baseclass.extend({ renderTunDns });
