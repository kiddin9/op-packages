#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, '..', 'htdocs/luci-static/resources/view/tailscale/setting.js'), 'utf8');

function assert(condition, message) {
	if (!condition)
		throw new Error(message);
}

assert(source.includes("uci.load('tailscale_policy_routing')"), 'setting view must load the isolated policy-routing UCI package');
assert(source.includes("method: 'policy_routing_status'"), 'setting view must use the read-only policy-routing status RPC');
assert(source.includes("uci.set('tailscale_policy_routing', 'settings', 'enabled'"), 'toggle must write only the isolated policy-routing UCI package');
assert(!source.includes("uci.set('tailscale', section_id, 'mwan3_table52_precedence'"), 'toggle must not write the core Tailscale UCI package');
assert(source.includes("_('Prioritize Tailscale Routes Before mwan3')"), 'setting view must expose the mwan3 precedence toggle');
assert(source.includes("_('Give routes already present in Tailscale table 52 priority over mwan3-marked traffic. This fixes LAN clients being sent to a WAN instead of a Tailnet or routed subnet. Public destinations not present in table 52 continue through mwan3. Disabled leaves mwan3 precedence unchanged. Verify from a real LAN client or with an equivalent mwan3 fwmark; the router\\'s unmarked ip route get alone is insufficient. The feature remains blocked while table 52 has a default route, such as when using an exit node.')"), 'toggle description must explain scope, disabled impact, real-client validation, and the exit-node safety block');
assert(source.includes('!status.mwan3_present') && source.includes('!status.mwan3_earlier_mark_rule'), 'policy-routing status must surface whether mwan3 and an earlier marked rule were detected');
assert(source.includes("blocked_mwan3_priority: _('Blocked; a mwan3 rule has higher priority than 1000')"), 'policy-routing status must explain when a mwan3 rule precedes the managed priority');

const loadMatch = source.match(/load\(\)\s*\{([\s\S]*?)\n\t\},\n\n\trender/);
assert(loadMatch, 'expected setting view to define a load() method');
assert(!loadMatch[1].includes('callPolicyRoutingStatus('), 'policy-routing status must not block initial page rendering');
assert(source.includes('refreshPolicyRoutingStatus'), 'status must refresh after render');

console.log('setting policy-routing tests passed');
