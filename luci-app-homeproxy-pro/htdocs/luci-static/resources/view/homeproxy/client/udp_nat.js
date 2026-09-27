/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2022-2025 ImmortalWrt.org
 */

'use strict';

'require baseclass';
'require form';

/* UDP NAT tab - the rightmost tab.  sing-box's UDP NAT knobs are not routing
 * decisions, so they get their own page instead of sitting at the bottom of
 * the routing tab.  They are config.* options and stay on the 'config'
 * NamedSection, so only the tab they render under changes.
 *
 * The tab has no depends() of its own: all three options depend on
 * proxy_mode, so a custom proxy mode hides every option and LuCI drops the
 * empty tab with them. */
function renderUdpNat(ctx) {
	const { s } = ctx;
	let o;

	s.tab('udp_nat', _('UDP NAT Settings'));

	o = s.taboption('udp_nat', form.ListValue, 'udp_mapping', _('UDP NAT mapping (1.14)'));
	o.value('endpoint_independent', _('Endpoint independent'));
	o.value('address_dependent', _('Address dependent'));
	o.value('address_and_port_dependent', _('Address and port dependent'));
	o.description = _('sing-box default; recommended for home use (small NAT table, QUIC/game friendly). Choose stricter only for specific UDP issues.');
	o.depends('proxy_mode', 'redirect_tproxy');
	o.depends('proxy_mode', 'redirect_tun');
	o.depends('proxy_mode', 'tun');
	o.default = 'endpoint_independent';
	o.rmempty = false;

	o = s.taboption('udp_nat', form.ListValue, 'udp_filtering', _('UDP NAT filtering (1.14)'));
	o.value('endpoint_independent', _('Endpoint independent'));
	o.value('address_dependent', _('Address dependent'));
	o.value('address_and_port_dependent', _('Address and port dependent'));
	o.description = _('sing-box default; recommended for home use (accepts replies from any remote after mapping). Choose stricter only for specific UDP issues.');
	o.depends('proxy_mode', 'redirect_tproxy');
	o.depends('proxy_mode', 'redirect_tun');
	o.depends('proxy_mode', 'tun');
	o.default = 'endpoint_independent';
	o.rmempty = false;

	o = s.taboption('udp_nat', form.Value, 'udp_nat_max', _('UDP NAT sessions max (1.14)'));
	o.datatype = 'uinteger';
	o.depends('proxy_mode', 'redirect_tproxy');
	o.depends('proxy_mode', 'redirect_tun');
	o.depends('proxy_mode', 'tun');
}

return baseclass.extend({ renderUdpNat });
