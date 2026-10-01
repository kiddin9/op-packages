#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Guards that decide whether a configuration can be BUILT at all, as opposed
 * to guards that decide what it contains. Both of the rules pinned here used
 * to reject configurations sing-box accepts, and both rejections were fatal
 * rather than noisy, so each one could take the proxy down over a value the
 * user never thought was load-bearing.
 *
 *   1. config/model.uc Node.validate - "TLS enabled without server_name"
 *      fired for every TLS node that had no explicit SNI, including the
 *      ordinary case of a share link with no `sni=` parameter and a node
 *      form that lets you save one. sing-box defaults an outbound's
 *      tls.server_name to the outbound's server address, so a hostname
 *      address needs no SNI at all. As a main node the node failed
 *      OutboundFactory.create() -> die(), i.e. `node '<id>': TLS enabled
 *      without server_name`, the reload rolled back to the previous
 *      configuration and a boot start refused to come up.
 *      Reproduced on a router (2026-10-01, sing-box 1.14.2).
 *      The rule is now scoped to IP addresses, where the implicit SNI is
 *      the literal IP and the connection genuinely cannot succeed.
 *
 *   2. generator/dns.uc bootstrap_addr - the two regexes it used accepted
 *      any hostname made only of hex digits and colons (cafe, face, abc,
 *      add, dead:beef) and an out-of-range IPv4 (999.999.999.999). The
 *      bootstrap server is emitted with no domain_resolver on purpose, so a
 *      hostname there is unsatisfiable and sing-box refuses to start:
 *        FATAL create service: initialize DNS server[0]: missing domain
 *        resolver for domain server address
 *      It now goes through isValidCIDR(), like every other address that
 *      reaches a root context.
 *
 * Everything here is a pure function of its arguments - no UCI cursor, no
 * confdir, no files. That is deliberate: `cursor(<dir>)` returns null on the
 * target (measured 2026-10-01), and a test that loads UCI through a sandbox
 * confdir therefore reads an empty configuration there and passes
 * vacuously. Asserting the guards directly needs neither.
 *
 * Run from tests/ucode/test_build_guards.sh.
 */

'use strict';

import { Node } from './config/model.uc';
import { OutboundFactory } from './config/adapter.uc';
import { build_dns } from './generator/dns.uc';

let failures = 0;
let checks = 0;

function ok(name, condition, detail) {
	checks++;
	if (!condition) {
		printf('FAIL %s%s\n', name, detail === null ? '' : sprintf(': %J', detail));
		failures++;
	}
}

function expect_problems(name, node, expected) {
	checks++;
	const got = OutboundFactory.problems(node);
	if (sprintf('%J', got) !== sprintf('%J', expected)) {
		printf('FAIL %s: expected problems %J, got %J\n', name, expected, got);
		failures++;
	}
}

/* A node as the Loader builds it: the nested sub-objects, not a flat dict. */
function node(address, tls_enabled, server_name, reality) {
	return Node.create({
		id: 'n1',
		name: 'test',
		type: 'trojan',
		address: address,
		port: '443',
		credentials: { password: 'secret' },
		protocol_options: {},
		common: {},
		multiplex: {},
		transport: { type: null },
		tls: {
			enabled: tls_enabled,
			server_name: server_name,
			insecure: '0',
			reality: { enabled: reality || '0' }
		}
	});
}

/* --- 1. the TLS / server_name rule -------------------------------------- */

/* The regression: a share link with no `sni=` parameter, on a hostname. This
 * is the shape the trojan/anytls/hysteria2/tuic parsers produce. */
expect_problems('hostname address, TLS, no server_name',
	node('bwg.example.com', '1', null, null), []);
ok('... is buildable',
	OutboundFactory.buildable(node('bwg.example.com', '1', null, null)) === true);

/* ... and the whole point: the outbound is actually produced, with a TLS
 * block that lets sing-box fall back to the address as the SNI. */
{
	const built = OutboundFactory.tryCreate(node('bwg.example.com', '1', null, null), '100');
	checks++;
	if (length(built.problems) || built.outbound === null) {
		printf('FAIL outbound build for a sni-less hostname node: %J\n', built.problems);
		failures++;
	} else if (built.outbound.tls?.enabled !== true || 'server_name' in built.outbound.tls) {
		printf('FAIL outbound tls shape: expected { enabled: true } with no server_name, got %J\n',
			built.outbound.tls);
		failures++;
	}
}

/* The rule still fires where it is right to: an IP address with no SNI gets
 * SNI=IP, which no real certificate answers to. */
expect_problems('IPv4 address, TLS, no server_name',
	node('1.2.3.4', '1', null, null),
	['TLS enabled on IP address 1.2.3.4 without server_name']);
expect_problems('IPv6 address, TLS, no server_name',
	node('2001:67c:4e8::1', '1', null, null),
	['TLS enabled on IP address 2001:67c:4e8::1 without server_name']);

/* reality runs its own handshake, so it never needed server_name. */
expect_problems('IP address, TLS, reality, no server_name',
	node('1.2.3.4', '1', null, '1'), []);

/* An explicit SNI is and always was fine, on either address shape. */
expect_problems('hostname address, TLS, explicit server_name',
	node('bwg.example.com', '1', 'cdn.example.net', null), []);
expect_problems('IP address, TLS, explicit server_name',
	node('1.2.3.4', '1', 'cdn.example.net', null), []);

/* No TLS at all: the rule never applied, and still does not. */
expect_problems('hostname address, no TLS, no server_name',
	node('bwg.example.com', '0', null, null), []);

/* The rule must not have shadowed the cross-protocol checks. */
expect_problems('still reports a missing credential',
	Node.create({
		id: 'n2', name: 't', type: 'trojan', address: 'bwg.example.com', port: '443',
		credentials: {}, protocol_options: {}, common: {}, multiplex: {},
		transport: { type: null },
		tls: { enabled: '1', server_name: null, insecure: '0', reality: { enabled: '0' } }
	}),
	['trojan requires password']);
expect_problems('still reports an out-of-range port',
	Node.create({
		id: 'n3', name: 't', type: 'trojan', address: 'bwg.example.com', port: '70000',
		credentials: { password: 'x' }, protocol_options: {}, common: {}, multiplex: {},
		transport: { type: null },
		tls: { enabled: '1', server_name: null, insecure: '0', reality: { enabled: '0' } }
	}),
	["invalid port '70000'"]);

/* --- 2. the bootstrap resolver address ---------------------------------- */

/* append_bootstrap_dns() and append_proxy_dns() are private, so the guards are
 * asserted through the public entry point: what ends up in the dns block, and
 * what build_dns() does with a China DNS value it cannot use.
 *
 * `mode` is 'built' (the block was produced) or 'died' (build_dns refused,
 * naming the field). The "died" case is the point of the third rule below: a
 * value the option cannot express used to reach the generator as `...null`
 * and throw "Value (null) is not iterable", which names no field at all. */
function dns_for(china_dns_server) {
	const config = { };
	const ctx = {
		routing_mode: 'bypass_mainland_china',
		proxy_mode: 'redirect_tproxy',
		main_node: 'n1',
		main_udp_node: 'nil',
		ipv6_support: '0',
		log_level: 'warn',
		self_mark: '100',
		wan_dns: '223.5.5.5',
		dns_server: 'https://dns.google/dns-query',
		china_dns_server: china_dns_server,
		cn_ip_fallback: '0',
		sniffer_advanced_mode: '0',
		direct_domain_list: [],
		proxy_domain_list: []
	};

	try {
		build_dns(config, { dns: { servers: [], rules: [] } }, ctx);
	} catch (e) {
		return { died: sprintf('%s', e.message) };
	}

	return { died: null, config: config };
}

function bootstrap_server(addr) {
	const r = dns_for(addr);
	if (r.died !== null)
		return null;

	for (let s in (r.config.dns?.servers || []))
		if (s.tag === 'bootstrap-dns')
			return s;

	return null;
}

/* The values the option documents, plus the other family. A bare IP is the
 * one thing a bootstrap server can be: it has no domain_resolver of its own,
 * so it must be able to answer without one. */
ok('bare IPv4 is used as the bootstrap address',
	bootstrap_server('223.5.5.5')?.server === '223.5.5.5',
	bootstrap_server('223.5.5.5'));
ok('bare IPv6 is used as the bootstrap address',
	bootstrap_server('fdfe::1')?.server === 'fdfe::1',
	bootstrap_server('fdfe::1'));

/* A real hostname was never a candidate: main-dns keeps borrowing the WAN
 * resolver, which is the documented behaviour for 'wan' and for a host name. */
ok('a dotted hostname yields no bootstrap server',
	bootstrap_server('dns.alidns.com') === null,
	bootstrap_server('dns.alidns.com'));
ok("the 'wan' sentinel yields no bootstrap server",
	bootstrap_server('wan') === null,
	bootstrap_server('wan'));
ok('an empty value yields no bootstrap server',
	bootstrap_server('') === null,
	bootstrap_server(''));

/* Every one of these used to be accepted as a bare address by the regex pair
 * bootstrap_addr() carried - a hostname made only of hex digits and colons,
 * or an IPv4 whose octets were never range-checked. Measured on the target,
 * all seven were emitted as a `bootstrap-dns` server address, and that
 * server has no domain_resolver by design, so sing-box refused to start:
 *
 *   FATAL create service: initialize DNS server[0]: missing domain resolver
 *   for domain server address
 *
 * The invariant pinned here is that no China DNS value can produce a
 * bootstrap server unless it is a real address. */
for (let bad in ['cafe', 'face', 'abc', 'add', 'dead:beef', '999.999.999.999', '1.2.3']) {
	checks++;
	if (bootstrap_server(bad) !== null) {
		printf('FAIL china_dns_server %s: emitted a bootstrap-dns server (%J)\n',
			bad, bootstrap_server(bad));
		failures++;
	}
}

/* And the failure mode for a value the option cannot express at all is a
 * refusal that names the field. Spreading the null parse_dnsserver() returns
 * used to throw "Value (null) is not iterable" instead - an exception naming
 * no field, exit 254, rollback.
 *
 * Which values land here is a property of /sbin/validate_data, not of this
 * generator: a dotless name is a valid *hostname* to it, so 'cafe' is carried
 * through to china-dns unchanged, while 'dead:beef' (a colon with no port)
 * is not parseable at all. Both are accepted here; only the second may die,
 * and it has to die by name. */
for (let bad in ['cafe', 'face', 'abc', 'add', 'dead:beef', '999.999.999.999', '1.2.3']) {
	checks++;
	const died = dns_for(bad).died;
	if (died !== null && (!match(died, /China DNS server/) || match(died, /not iterable/))) {
		printf('FAIL china_dns_server %s: died with %J (want null, or a message naming the field)\n',
			bad, died);
		failures++;
	}
}

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);
