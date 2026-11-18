/** @typedef {import('../../types/routing.uc').Match} Match */
/** @typedef {import('../../types/routing.uc').RoutingEntry} RoutingEntry */
/** @typedef {import('../../types/core.uc').SingboxConfig} SingboxConfig */
/** @typedef {import('../../types/proxy.uc').RoutingDependencies} RoutingDependencies */
/** @typedef {import('../../types/routing.uc').RoutingSettings} RoutingSettings */
/** @typedef {import('../../types/routing.uc').DNSServer} DNSServer */
import { TAG } from '../constants.uc';
import { optional } from '../json.uc';
import { hasDomain, empty, convertGeo, singboxMatch } from '../rules.uc';
import { socks, inbound } from './config.uc';

function dnsStrategy(value) {
	return { '4': 'ipv4_only', '6': 'ipv6_only', '46': 'prefer_ipv4', '64': 'prefer_ipv6' }[value] || '';
}

/**
 * @param {DNSServer} server
 */
function dnsServer(server, tag, detour) {
	if (index(['udp', 'tcp', 'tls', 'quic', 'https', 'local'], server.type) < 0) {
		die(`invalid sing-box DNS type "${server.type}"`);
	}
	let result = { type: server.type, tag };
	if (server.type != 'local') {
		result.server = server.address;
		optional(result, 'server_port', server.port);
		if (detour != TAG.direct) {
			optional(result, 'detour', detour);
		}
	}
	return result;
}

/**
 * 生成 sing-box 分流配置；规则集转换只作用于本次生成的匹配条件副本。
 * @param {RoutingSettings} settings 共享 routing.prepare() 的结果。
 * @param {RoutingDependencies} dependencies
 * @returns {SingboxConfig} 含 DNS、入站、出站和路由的配置。
 */
export function build(settings, dependencies) {
	let dnsServers = [dnsServer(settings.dns, settings.dns.tag, settings.final)], dnsRules = [];
	let routeRules = [{ action: 'sniff' }, { protocol: ['dns'], action: 'hijack-dns' }];
	let outbounds = [{ type: 'direct', tag: TAG.direct }, ...map(dependencies.nodes, node => socks(node.name, node.socks_port))];
	let config = {
		log: { disabled: false, level: settings.log, timestamp: true },
		dns: { servers: dnsServers, final: settings.dns.tag,
			disable_cache: !settings.cache, disable_expire: !settings.cache },
		inbounds: [inbound('tproxy', TAG.tproxy, settings.listen, '::'), inbound('direct', TAG.dnsInbound, settings.dnsPort, '::')],
		outbounds,
		route: { rules: routeRules, final: settings.final, default_domain_resolver: settings.dns.tag },
	};
	optional(config.dns, 'strategy', dnsStrategy(settings.strategy));
	if (settings.rulesetExit) {
		let outbound = settings.rulesetExit == TAG.direct ? { type: 'direct', tag: TAG.ruleset }
			: socks(TAG.ruleset, dependencies.byName[settings.rulesetExit].socks_port);
		if (settings.rulesetDNS) {
			outbound.domain_resolver = TAG.rulesetDNS;
			push(dnsServers, dnsServer(settings.rulesetDNS, TAG.rulesetDNS, TAG.ruleset));
		}
		push(outbounds, outbound);
	}
	let sets = {}, setOrder = [];
	// DNS 规则与服务器成对登记，保持与路由规则相同的优先级。
	/**
	 * @param {RoutingEntry} entry
	 * @param {Match} ruleMatch
	 * @param {string} outboundTag
	 */
	function addDNS(entry, ruleMatch, outboundTag) {
		if (outboundTag == TAG.block) {
			die(`rule "${entry.name}" DNS exit cannot be Block`);
		}
		let tag = entry.name + '-dns';
		push(dnsServers, dnsServer(entry.dns, tag, outboundTag));
		let rule = { ...singboxMatch(ruleMatch, true), action: 'route', server: tag, disable_cache: true };
		optional(rule, 'strategy', dnsStrategy(entry.strategy));
		push(dnsRules, rule);
	}
	for (let entry in settings.entries) {
		let splitMatch = null;
		// 只为已选择出口的地址族创建规则。
		let versions = entry.split ? filter([4, 6], version => version == 4 ? entry.v4 : entry.v6) : [0];
		for (let version in versions) {
			let ruleMatch = { ...entry.match, sets: [...entry.match.sets] };
			let outboundTag = entry.exit;
			if (version == 4) {
				outboundTag = entry.v4;
			}
			else if (version == 6) {
				outboundTag = entry.v6;
			}
			let hasDNS = hasDomain(ruleMatch, settings.convert) || length(ruleMatch.sets) > 0;
			if (settings.convert) {
				convertGeo(ruleMatch);
			}
			else if (length(ruleMatch.geoip) + length(ruleMatch.geosite) && !hasDomain(ruleMatch) && !length(ruleMatch.ip) && !length(ruleMatch.sets)) {
				continue;
			}
			if (empty(ruleMatch, false)) {
				continue;
			}
			for (let set in ruleMatch.sets) {
				let value = { ...set };
				if (value.type == 'remote' && settings.rulesetExit) {
					value.http_client = { detour: TAG.ruleset };
				}
				if (!sets[set.tag]) {
					push(setOrder, set.tag);
				}
				sets[set.tag] = value;
			}
			let rule = singboxMatch(ruleMatch, false);
			if (version) {
				rule.ip_version = version;
			}
			if (outboundTag == TAG.block) {
				rule.action = 'reject';
			}
			else {
				rule.action = 'route';
				rule.outbound = outboundTag;
			}
			push(routeRules, rule);
			if (outboundTag == TAG.block) {
				continue;
			}
			if (entry.split) {
				if (hasDNS && !splitMatch) {
					splitMatch = ruleMatch;
				}
			}
			else if (hasDNS || length(ruleMatch.ip) + length(ruleMatch.sets)) {
				addDNS(entry, ruleMatch, entry.dnsExit || outboundTag);
			}
		}
		// IPv4/IPv6 路由共用一条 DNS 策略，出口必须显式指定。
		if (splitMatch) {
			if (!entry.dnsExit) {
				die(`split rule "${entry.name}" requires a DNS exit`);
			}
			addDNS(entry, splitMatch, entry.dnsExit);
		}
	}
	if (length(dnsRules)) {
		config.dns.rules = dnsRules;
	}
	if (length(setOrder)) {
		config.route.rule_set = map(setOrder, tag => sets[tag]);
	}
	return config;
};
