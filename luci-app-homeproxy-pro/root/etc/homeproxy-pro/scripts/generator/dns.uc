/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     generator/dns.uc: build the sing-box `dns` block.
 *
 * Two routing-mode families exist:
 *
 *   1. bypass_mainland_china / proxy_mainland_china / global /
 *      gfwlist - the proxy path. The orchestrator passes main_node
 *      (possibly 'urltest'), main_udp_node, china_dns_server,
 *      direct_domain_list and proxy_domain_list in ctx; the legacy
 *      NAPTR trick (qtype 35) and the CN-IP fallback (cn_ip_fallback)
 *      are part of this path.
 *
 *   2. custom - the user-defined rules path. The orchestrator passes
 *      default_outbound, default_outbound_dns, the dns settings
 *      (default_strategy, default_server, disable_cache, ...) and the
 *      dns_server / dns_rule section lists under dm.dns.
 *
 * The dns_server / dns_rule iteration is the part that is mode-agnostic
 * and lives in this module rather than the orchestrator because every
 * field comes straight from UCI and the legacy 1.14 evaluate/match_response
 * rewrite is the per-field payload.
 */

'use strict';

import { isEmpty, strToBool, strToInt, strToTime, parseURL, validation, parse_port, isValidCIDR } from '../homeproxy-pro.uc';


import { get_outbound, get_resolver, get_ruleset } from './common.uc';

/* Build a DNS server spec from a UCI address string. sing-box wants the
 * server name, the protocol kind, an optional path, and an integer port;
 * the UCI representation is a single string, optionally without a
 * scheme, which is why a default_protocol is supplied. */
function parse_dnsserver(server_addr, default_protocol) {
	if (isEmpty(server_addr))
		return null;

	if (!match(server_addr, /:\/\//))
		server_addr = (default_protocol || 'udp') + '://' + (validation('ip6addr', server_addr) ? `[${server_addr}]` : server_addr);

	/* parseURL() returns null for an address it cannot make sense of (a bad
	 * host, an unknown scheme).  The old code dereferenced the result straight
	 * away, so one malformed UCI value took the whole generator down with
	 * "left-hand side expression is null" instead of naming the dns_server. */
	server_addr = parseURL(server_addr);
	if (!server_addr)
		return null;

	return {
		type: server_addr.protocol,
		server: server_addr.hostname,
		server_port: strToInt(server_addr.port),
		path: (server_addr.pathname !== '/') ? server_addr.pathname : null,
	}
}

/* Parse the DNS rule query_type list UCI emits. A single value comes as
 * a string, a list as an array of strings; both forms are turned into an
 * array of strings or integers (mixing the two is intentional - the type
 * can be a name or a numeric code in UCI). */
function parse_dnsquery(strquery) {
	if (type(strquery) !== 'array' || isEmpty(strquery))
		return null;

	let querys = [];
	for (let i in strquery)
		isnan(int(i)) ? push(querys, i) : push(querys, int(i));

	return querys;
}

/* parse_dnsserver() returns null for an address it cannot make sense of, and
 * both call sites used to spread that null straight into the server object.
 * Spreading null is not a no-op in ucode - it throws
 *
 *   Type error: Value (null) is not iterable
 *
 * so one unusable DNS address took the generator down with an exception that
 * names no field, and the user only saw a rollback. Reproduced on a router
 * (2026-10-01) by putting a single-label value in the China DNS field:
 * parseURL() only sets `hostname` when /sbin/validate_data accepts the value
 * as a hostname, and a dotless name ('cafe', 'beef', 'decade') is not one.
 *
 * A DNS server with no address is not something the configuration can do
 * without, so this fails the same way get_resolver()/get_ruleset() do - with
 * the field name and a usable example - instead of substituting a working
 * resolver the user did not ask for. */
function require_dnsserver(addr, default_protocol, field) {
	const server = parse_dnsserver(addr, default_protocol);

	if (!server)
		die(sprintf("the %s '%s' is not a usable address; use a bare IP, or a DoH/DoT URL such as https://dns.google/dns-query.\n",
			field, addr));

	return server;
};

/* --- proxy routing-mode path (bypass_mainland_china / proxy / / gfwlist) -- */

/* Domains whose NAPTR (qtype 35) queries bypass china-dns.  Aliyun
 * (china-dns's default backend, 223.5.5.5) returns NAPTR with multi-
 * second first responses for these suffixes, which sing-box reports as
 * 'context deadline exceeded' (sipgz12.hbq.r.10086.cn being the
 * reproducible offender); routing the qtype to default-dns (the ISP
 * resolver or the wan_dns fallback) keeps IMS/VoLTE registration fast.
 *
 * The list is deliberately small: every entry is a suffix match, so
 * adding a single host name can broaden the rule by accident.  Add new
 * suffixes here when a fresh NAPTR offender is observed, not when
 * someone reads the comment and thinks "I know a domain that should
 * go direct". */
const NAPTR_BYPASS_SUFFIXES = [
	'r.10086.cn',
	'10086.cn',
	'pub.3gppnetwork.org'
];

/* The address of the bootstrap resolver, or null when there is none.
 *
 * Every DNS server whose address is a *hostname* needs a domain_resolver
 * before sing-box will start it, and that lookup is the one step nothing
 * else can bootstrap: it has to work before any of the configured servers
 * can answer.  `main-dns` is exactly that case - it is the user's DoH/DoT
 * endpoint - and it used to borrow default-dns (the WAN/ISP resolver) for
 * it, which is the single resolver a polluted or unreachable WAN takes down.
 *
 * It used to be a field of its own in the form, which made no sense to read:
 * a second DNS address next to the China DNS server, both of them a bare
 * public IP, for a lookup that happens once at startup.  It is derived now,
 * from the China DNS server, which is the one address this router already
 * knows it can reach directly.  That answer is only usable when it is a bare
 * IP: the option also accepts the literal 'wan' and a DoH/DoT URL, and both
 * of those are hostnames - a hostname cannot resolve the hostname it would be
 * needed to resolve.  For those, and only for those, this returns null and
 * main-dns keeps borrowing the WAN resolver, exactly as it did before any of
 * this existed.
 */
function bootstrap_addr(ctx) {
	const addr = ctx.china_dns_server;
	if (isEmpty(addr))
		return null;

	/* isValidCIDR(), not a hand-rolled shape test.
	 *
	 * The pair of regexes this replaces accepted anything made only of hex
	 * digits and colons - `cafe`, `face`, `abc`, `add`, `dead:beef` are
	 * all perfectly good hostnames and all passed - and the IPv4 branch did
	 * not range-check the octets, so 999.999.999.999 passed too. Measured
	 * on the device (2026-10-01): all six returned an address.
	 *
	 * The cost of being wrong here is not one misbehaving resolver.
	 * append_bootstrap_dns() emits the bootstrap server deliberately
	 * *without* a domain_resolver of its own - existing is the whole point,
	 * it is what every other server bootstraps its own hostname through -
	 * so a hostname there can never be satisfied, and sing-box refuses to
	 * start at all. Verified against 1.14.2 with `server: "cafe"`:
	 *
	 *   FATAL create service: initialize DNS server[0]: missing domain
	 *   resolver for domain server address
	 *
	 * isValidCIDR() is the validator the firewall path already runs every
	 * resource value through for the same reason (a value that is not a
	 * real IP or CIDR reaches a root context), and it range-checks both
	 * families. Reusing it keeps one definition of "is this an address".
	 *
	 * Behaviour for every value this generator is actually pointed at is
	 * unchanged: 223.5.5.5, 1.12.12.21, fdfe::1 and the other literals the
	 * option documents all still pass, and 'wan' / empty / a real hostname
	 * still return null so main-dns keeps borrowing the WAN resolver. */
	return (isValidCIDR(addr, 4) || isValidCIDR(addr, 6)) ? addr : null;
}

/* Append the bootstrap resolver, when there is a usable address for it.
 *
 * The bootstrap server carries a plain IP, has no domain_resolver of its own
 * and is never referenced by a DNS rule: it exists only as the target of the
 * domain_resolver pointer, so there is no cycle for sing-box to reject.
 * Nothing is emitted when there is no such address ("resolve through the WAN
 * resolver"), which keeps a configuration whose China DNS server is a
 * hostname byte-identical to one that never had this.
 *
 * It is emitted only alongside main-dns: without a node there is no DoH/DoT
 * endpoint to bootstrap, and a server nothing points at is just noise. */
function append_bootstrap_dns(config, ctx) {
	const addr = bootstrap_addr(ctx);
	if (isEmpty(addr) || isEmpty(ctx.main_node))
		return;

	push(config.dns.servers, {
		tag: 'bootstrap-dns',
		type: 'udp',
		server: addr,
		detour: ctx.self_mark ? 'direct-out' : null
	});
}

function append_proxy_dns(config, dm, ctx) {
	if (isEmpty(ctx.main_node))
		return;

	/* The user's DoH/DoT endpoint is the one server in this block whose
	 * address is a hostname, so it is the one that needs the bootstrap
	 * resolver.  Which resolver that is follows the China DNS server - the
	 * one direct-routable address already configured for this router - and
	 * only when it is a bare IP; see bootstrap_addr(). */
	const main_resolver = isEmpty(bootstrap_addr(ctx)) ? 'default-dns' : 'bootstrap-dns';

	/* Main DNS */
	push(config.dns.servers, {
		tag: 'main-dns',
		domain_resolver: {
			server: main_resolver,
			strategy: (ctx.ipv6_support !== '1') ? 'ipv4_only' : null
		},
		detour: 'main-out',
		...require_dnsserver(ctx.dns_server, 'tcp', 'DNS server')
	});
	/* The DNS half of the mode's default policy.  It has to name the same
	 * side the route chain falls through to (ctx.proxy_fallback), or a
	 * domain that ends up proxied would be resolved by the resolver of the
	 * other path.  The pair is asserted per mode in the generator suite. */
	config.dns.final = ctx.proxy_fallback ? 'main-dns' : 'default-dns';

	if (length(ctx.direct_domain_list))
		push(config.dns.rules, {
			rule_set: 'direct-domain',
			action: 'route',
			server: (ctx.routing_mode === 'bypass_mainland_china') ? 'china-dns' : 'default-dns'
		});

	/* Everything on the proxy list resolves through the proxy path, in
	 * every proxy mode - not just bypass_mainland_china.  The list is the
	 * user's "this domain must not be answered by the domestic resolver"
	 * escape hatch (Google Play's connect.googleapis.cn and friends), and
	 * the routing half of it (route.uc pushes the same tag to main-out in
	 * all of these modes) was already mode-agnostic.  It has to sit after
	 * direct-domain so that a suffix present in both lists keeps the
	 * bypass-mode precedence and stays predictable. */
	if (length(ctx.proxy_domain_list))
		push(config.dns.rules, {
			rule_set: 'proxy-domain',
			action: 'route',
			server: 'main-dns'
		});

	/* Reject SVCB/HTTPS queries to avoid proxy DNS timeout on null domains */
	push(config.dns.rules, {
		query_type: [64, 65],
		action: 'reject'
	});

	if (ctx.routing_mode === 'bypass_mainland_china') {
		push(config.dns.servers, {
			tag: 'china-dns',
			domain_resolver: {
				server: 'default-dns',
				/* Mirror default-dns's strategy: china-dns itself is
				 * overwhelmingly IPv4-only in practice (223.5.5.5 etc.),
				 * so the field mostly affects the upstream chain; the
				 * two should still track each other for the same reason
				 * default-dns follows ipv6_support. */
				strategy: (ctx.ipv6_support !== '1') ? 'ipv4_only' : 'prefer_ipv6'
			},
			detour: ctx.self_mark ? 'direct-out' : null,
			...require_dnsserver(ctx.china_dns_server, null, 'China DNS server')
		});

		/* Route NAPTR (qtype 35) queries for SIP/ENUM domains to the ISP
		   default-dns directly: see NAPTR_BYPASS_SUFFIXES for the
		   rationale and the explicit offenders. */
		push(config.dns.rules, {
			query_type: [35],
			domain_suffix: NAPTR_BYPASS_SUFFIXES,
			action: 'route',
			server: 'default-dns'
		});

		push(config.dns.rules, {
			rule_set: 'geosite-cn',
			action: 'route',
			server: 'china-dns'
		});

		/* sing-box 1.14: restore CN-IP fallback via evaluate/match_response (opt-in) */
		if (ctx.cn_ip_fallback === '1') {
			push(config.dns.rules, {
				action: 'evaluate',
				server: 'main-dns',
				tag: 'cn-fallback'
			});
			push(config.dns.rules, {
				match_response: 'cn-fallback',
				rule_set: 'geoip-cn',
				action: 'route',
				server: 'china-dns'
			});
		}
	}
}

/* Known DoH/DoT/DoQ hostnames and the IPs we should pin them to. The
 * table is consulted by append_custom_dns() to detect when a user
 * configured one of these encrypted upstreams; without the predefined
 * entry, the resolver itself has to be resolved through the system DNS,
 * and a DNS outage of any kind taken once out leaves the resolver
 * unreachable - a chicken-and-egg loop. Mirrors the hosts server in
 * linux.json line 10; see docs/linux.json 与 pro 的差距分析.md §2.4.
 *
 * Additions go here when the user's pool of encrypted resolvers grows;
 * a new entry needs no code change beyond this table. */
const KNOWN_ENCRYPTED_DNS_HOSTS = {
	'doh.pub':         ['1.12.12.21', '120.53.53.53'],
	'dns.pub':         ['1.12.12.21', '120.53.53.53'],
	'dns.alidns.com':  ['223.5.5.5', '223.6.6.6'],
	'dns.google':      ['8.8.8.8', '8.8.4.4'],
	'one.one.one.one': ['1.1.1.1', '1.0.0.1']
};

/* --- custom routing-mode path (user-defined dns_server / dns_rule) ----- */

function append_custom_dns(config, dm, ctx) {
	/* §2.4 DoH fallback. Pre-emit a hosts-type DNS server pinning any
	 * encrypted-resolver hostname the user configured to its real IPs. The
	 * loop also remembers which server sections hit the table, so the user
	 * server loop below can stamp `domain_resolver: 'hp-dns-hosts'` onto
	 * them - sing-box only consults the hosts table for resolvers that
	 * explicitly point at it, mirroring linux.json line 7
	 * (`{"domain_resolver": "hosts"}`). Without the stamp, the resolver
	 * still has to look up its own hostname through the system DNS and the
	 * chicken-and-egg loop we are trying to break stays open. */
	let doh_predefined = null;
	const doh_resolved_hosts = {};
	for (let cfg in (dm.dns.servers || [])) {
		if (!cfg.enabled)
			continue;
		if (cfg.type !== 'https' && cfg.type !== 'tls' && cfg.type !== 'quic')
			continue;
		const host = cfg.server;
		if (!host || !KNOWN_ENCRYPTED_DNS_HOSTS[host])
			continue;
		if (!doh_predefined)
			doh_predefined = {};
		doh_predefined[host] = KNOWN_ENCRYPTED_DNS_HOSTS[host];
		doh_resolved_hosts[cfg.name] = true;
	}
	if (doh_predefined) {
		push(config.dns.servers, {
			tag: 'hp-dns-hosts',
			type: 'hosts',
			predefined: doh_predefined
		});
	}

	/* DNS servers */
	for (let cfg in dm.dns.servers) {
		if (!cfg.enabled)
			continue;

		let outbound = get_outbound(cfg.outbound, dm);
		if (outbound === 'direct-out' && isEmpty(ctx.self_mark))
			outbound = null;

		push(config.dns.servers, {
			tag: 'cfg-' + cfg.name + '-dns',
			type: cfg.type,
			server: cfg.server,
			server_port: strToInt(cfg.server_port),
			path: cfg.path,
			headers: cfg.headers,
			tls: cfg.tls_sni ? {
				enabled: true,
				server_name: cfg.tls_sni
			} : null,
			domain_resolver: doh_resolved_hosts[cfg.name]
				? 'hp-dns-hosts'
				: ((cfg.address_resolver || cfg.address_strategy) ? {
					server: get_resolver(cfg.address_resolver || ctx.dns_default_server, dm),
					strategy: cfg.address_strategy
				} : null),
			detour: outbound
		});
	}

	/* DNS rules */
	/* sing-box >= 1.14: legacy address-filter rules are auto-wrapped with an
	   evaluate action; deprecated strategy/accept_empty fields are dropped. */
	const builtin_dns_rules = [];
	/* §2.2 First safe rule: reject SVCB (qtype 64) and HTTPS (qtype 65)
	 * queries. A client that learns the answer from these record types
	 * connects to the embedded IP without going through the resolver again,
	 * which makes Fake-IP and any route that hinges on A/AAAA resolution
	 * bypass. Mirrors append_proxy_dns() line 102; emit here as the FIRST
	 * entry so a user rule that targets the same query_type cannot shadow
	 * it (sing-box walks the array in order and stops at the first match).
	 * Without this prefix, a user who adds a higher-priority rule on the
	 * same query_type in custom mode loses Fake-IP integrity. */
	push(builtin_dns_rules, {
		query_type: [64, 65],
		action: 'reject'
	});
	for (let cfg in dm.dns.rules) {
		if (!cfg.enabled)
			continue;

		/* Match fields are valid for every action; action-specific fields
		 * are emitted below per sing-box 1.14's per-action schema.  The
		 * previous code dumped server/method/no_drop/rcode/answer/ns/extra
		 * (and the cache / TTL / client-subnet family) onto every rule
		 * regardless of action, and sing-box then rejected the whole
		 * configuration with "json: unknown field" the moment a user
		 * changed a rule's action and left the old fields in UCI -
		 * LuCI's form value parsing does not delete the previous value
		 * when a depends() guard hides it, the same path route.uc
		 * already had to fix. */
		const rule = {
			ip_version: strToInt(cfg.ip_version),
			query_type: parse_dnsquery(cfg.query_type),
			network: cfg.network,
			protocol: cfg.protocol,
			domain: cfg.domain,
			domain_suffix: cfg.domain_suffix,
			domain_keyword: cfg.domain_keyword,
			domain_regex: cfg.domain_regex,
			port: parse_port(cfg.port),
			port_range: cfg.port_range,
			source_ip_cidr: cfg.source_ip_cidr,
			source_ip_is_private: strToBool(cfg.source_ip_is_private),
			source_port: parse_port(cfg.source_port),
			source_port_range: cfg.source_port_range,
			process_name: cfg.process_name,
			process_path: cfg.process_path,
			process_path_regex: cfg.process_path_regex,
			user: cfg.user,
			rule_set: get_ruleset(cfg.rule_set, dm),
			rule_set_ip_cidr_match_source: strToBool(cfg.rule_set_ip_cidr_match_source),
			invert: strToBool(cfg.invert),
			race: strToBool(cfg.race),
			speculative: strToBool(cfg.speculative),
			action: cfg.action
		};

		/* `route` (and `evaluate`, which needs a server for the eval step).
		 * `resolve` is also a possibility but is not currently exposed in
		 * the UI; if it ever is, this branch is where it lands. */
		if (cfg.action === 'route' || cfg.action === 'evaluate' || cfg.action === 'resolve') {
			rule.server = get_resolver(cfg.server, dm);
			rule.disable_cache = strToBool(cfg.dns_disable_cache);
			rule.disable_optimistic_cache = strToBool(cfg.disable_optimistic_cache);
			rule.rewrite_ttl = strToInt(cfg.rewrite_ttl);
			rule.client_subnet = cfg.client_subnet;
			rule.remove_client_subnet = strToBool(cfg.remove_client_subnet);
		}

		if (cfg.action === 'route' || cfg.action === 'resolve')
			rule.timeout = strToTime(cfg.dns_timeout);

		/* `reject` only accepts method + no_drop.  Anything else here is
		 * an unknown field for the action and the whole config fails. */
		if (cfg.action === 'reject') {
			rule.method = cfg.reject_method;
			rule.no_drop = strToBool(cfg.reject_no_drop);
		}

		/* `predefined` only accepts rcode + answer + ns + extra. */
		if (cfg.action === 'predefined') {
			rule.rcode = cfg.predefined_rcode;
			rule.answer = cfg.predefined_answer;
			rule.ns = cfg.predefined_ns;
			rule.extra = cfg.predefined_extra;
		}

		if (cfg.action === 'evaluate')
			rule.tag = cfg.evaluate_tag || null;

		if (cfg.match_response && cfg.match_response !== '0')
			rule.match_response = (cfg.match_response === '1') ? true : cfg.match_response;

		rule.query_client_subnet = cfg.query_client_subnet;
		rule.query_dnssec = strToBool(cfg.query_dnssec);
		rule.source_mac_address = cfg.source_mac_address;
		rule.source_hostname = cfg.source_hostname;

		const legacy_filter = !isEmpty(cfg.ip_cidr) || strToBool(cfg.ip_is_private) === true;
		/* Every action needs the evaluate prefix to see the response, not just
		 * `route`: with the old `&& cfg.action === 'route'` an address-filtered
		 * reject rule lost the filter entirely and became an unconditional
		 * reject - a DNS black hole for every query. */
		if (legacy_filter && !rule.match_response) {
			/* Wrap a legacy address-filter rule into the 1.14 evaluate/match_response
			   paradigm. Carry the original query-matching fields onto the evaluate
			   prefix rule so only queries that would have hit this rule get
			   pre-resolved; an unconditional evaluate would resolve every query. */
			const eval_tag = '_hp_eval_' + cfg.name;
			const eval_rule = {
				action: 'evaluate',
				server: get_resolver(cfg.server, dm),
				tag: eval_tag
			};
			const eval_match_fields = [
				'inbound', 'ip_version', 'query_type', 'network', 'protocol', 'auth_user',
				'domain', 'domain_suffix', 'domain_keyword', 'domain_regex',
				'port', 'port_range', 'source_ip_cidr', 'source_ip_is_private',
				'source_port', 'source_port_range', 'process_name', 'process_path',
				'process_path_regex', 'user', 'rule_set', 'rule_set_ip_cidr_match_source',
				'invert', 'query_client_subnet', 'query_dnssec', 'source_mac_address',
				'source_hostname'
			];
			for (let f in eval_match_fields)
				eval_rule[f] = rule[f];
			push(builtin_dns_rules, eval_rule);
			rule.match_response = eval_tag;
		}

		/* Response-match fields are only valid together with match_response in
		 * 1.14: sing-box rejects the rule with "Response Match Fields (...)
		 * require match_response to be enabled".  ip_cidr / ip_is_private were
		 * already gated here; the response_* quartet was emitted
		 * unconditionally next door. */
		if (rule.match_response) {
			rule.ip_cidr = cfg.ip_cidr;
			rule.ip_is_private = strToBool(cfg.ip_is_private);
			rule.response_rcode = cfg.response_rcode;
			rule.response_answer = cfg.response_answer;
			rule.response_ns = cfg.response_ns;
			rule.response_extra = cfg.response_extra;
		}

		push(builtin_dns_rules, rule);
	}
	config.dns.rules = builtin_dns_rules;

	config.dns.final = get_resolver(ctx.dns_default_server, dm);
}

/* --- public entry ------------------------------------------------------ */

/* The always-on DNS block. Every routing mode (proxy and custom) gets
 * default-dns (UDP via the WAN resolver) and system-dns (local, used as
 * a fallback). The routing-mode-specific builders push additional
 * servers/rules on top of this list. Keeping the common prefix here is
 * why the proxy-mode and custom-mode paths stay almost mirror images:
 * both branches see config.dns already populated. */
function initDns(config, ctx) {
	/* sing-box refuses the combination outright:
	 *   FATAL initialize DNS router: `optimistic` is conflict with `disable_cache`
	 * (reproduced against 1.14.1 on a real config).  Both are opt-in switches
	 * in the UI, so turning both on used to produce a configuration that
	 * cannot start - the reload fails and rolls back, and the only symptom the
	 * user sees is "my setting did not take".  optimistic wins; the disable_*
	 * switches are dropped rather than emitted. */
	const optimistic = (ctx.dns_optimistic_cache === '1');

	config.dns = {
		servers: [
			{
				tag: 'default-dns',
				type: 'udp',
				server: ctx.wan_dns,
				detour: ctx.self_mark ? 'direct-out' : null
			},
			{
				tag: 'system-dns',
				type: 'local',
				detour: ctx.self_mark ? 'direct-out' : null
			}
		],
		rules: [],
		strategy: ctx.dns_default_strategy,
		disable_cache: optimistic ? null : strToBool(ctx.dns_disable_cache),
		disable_expire: optimistic ? null : strToBool(ctx.dns_disable_cache_expire),
		client_subnet: ctx.dns_client_subnet,
		optimistic: optimistic ? {
			enabled: true,
			/* strToTime(), not the raw UCI string: sing-box parses this
			 * field as a duration and rejects a bare number outright
			 * ("time: missing unit in duration \"3600\""), so the whole
			 * generation would fail - and a failed generation keeps the
			 * previous configuration running, which the user sees as
			 * "my setting did not take".  The UI documents the field as
			 * "Examples: 3d, 1h" but does not enforce a unit, so both
			 * forms have to work: strToTime() turns "3600" into "3600s"
			 * and leaves "3d" alone.  dns_query_timeout below already
			 * does this. */
			timeout: !isEmpty(ctx.dns_optimistic_timeout) ? strToTime(ctx.dns_optimistic_timeout) : '3d'
		} : null,
		timeout: !isEmpty(ctx.dns_query_timeout) ? strToTime(ctx.dns_query_timeout) : null
	};
}

/* Build the sing-box `dns` block. Mutates `config` and returns it for
 * chaining. Routing mode is determined by ctx.routing_mode: any non-
 * 'custom' mode follows the proxy path (the proxy-mode split inside the
 * proxy path is just which rules to emit). */
export function build_dns(config, dm, ctx) {
	initDns(config, ctx);

	/* Custom mode has no main-dns and never resolves its own servers'
	 * hostnames, so it has no bootstrap problem to solve. */
	if (ctx.routing_mode === 'custom')
		append_custom_dns(config, dm, ctx);
	else {
		append_bootstrap_dns(config, ctx);
		append_proxy_dns(config, dm, ctx);
	}

	return config;
};