/** @typedef {import('../../types/routing.uc').Match} Match */
/** @typedef {import('../../types/routing.uc').RoutingEntry} RoutingEntry */
/** @typedef {import('../../types/core.uc').XrayConfig} XrayConfig */
/** @typedef {import('../../types/proxy.uc').RoutingDependencies} RoutingDependencies */
/** @typedef {import('../../types/routing.uc').RoutingSettings} RoutingSettings */
/** @typedef {import('../../types/routing.uc').DNSServer} DNSServer */
import { TAG } from '../constants.uc';
import { optional } from '../json.uc';
import { hasDomain, empty, xrayDomains, xrayRules } from '../rules.uc';
import { socks, inbound, log } from './config.uc';

function dnsStrategy(value) {
	return { '4': 'UseIPv4', '6': 'UseIPv6', '46': 'UseIP', '64': 'UseIP' }[value] || '';
}

/**
 * @param {DNSServer} server
 */
function dnsServer(server, tag) {
	if (index(['udp', 'tcp', 'quic', 'https'], server.type) < 0) {
		die(`invalid Xray DNS type "${server.type}"`);
	}
	let address = server.address, result = { tag, skipFallback: true };
	if (server.type == 'https') {
		address = 'https://' + (index(address, ':') >= 0 ? `[${address}]` : address) + (server.port ? `:${server.port}` : '') + '/dns-query';
	}
	else {
		if (server.type != 'udp') {
			address = `${server.type}://${address}`;
		}
		optional(result, 'port', server.port);
	}
	result.address = address;
	return result;
}

/**
 * 生成 Xray 分流配置，DNS 请求出口规则排在用户路由之前。
 * @param {RoutingSettings} settings 共享 routing.prepare() 的结果。
 * @param {RoutingDependencies} dependencies
 * @returns {XrayConfig} 含 DNS、入站、出站和路由的配置。
 */
export function build(settings, dependencies) {
	let outbounds = map(dependencies.nodes, node => socks(node.name, node.socks_port));
	push(outbounds, { protocol: 'freedom', tag: TAG.direct, settings: {}, streamSettings: { sockopt: { domainStrategy: 'UseIP' } } });
	// Xray 的默认出口由第一项决定，稳定保持其余出口的原顺序。
	let final = filter(outbounds, outbound => outbound.tag == settings.final)[0];
	if (!final) {
		die(`default outbound "${settings.final}" is missing`);
	}
	outbounds = [final, ...filter(outbounds, outbound => outbound != final)];
	push(outbounds, { protocol: 'blackhole', tag: TAG.block }, {
		protocol: 'dns', tag: TAG.dns, settings: { rules: [{ action: 'hijack', qType: '1,28' }, { action: 'return', rCode: 5 }] },
	});
	let dnsServers = [], routes = [], dnsExits = {}, exitOrder = [];
	let routeRules = [{ inboundTag: [TAG.dnsInbound], outboundTag: TAG.dns }];
	let config = {
		log: log(settings.log), outbounds,
		inbounds: [inbound('tproxy', TAG.tproxy, settings.listen, true), inbound('direct', TAG.dnsInbound, settings.dnsPort)],
		routing: { domainStrategy: 'AsIs', rules: routeRules },
		dns: { servers: dnsServers, queryStrategy: dnsStrategy(settings.strategy) || 'UseIP', serveExpiredTTL: 3600,
			disableCache: !settings.cache, serveStale: !settings.cache, disableFallback: false, disableFallbackIfMatch: true },
	};
	/**
	 * @param {RoutingEntry} entry
	 * @param {Match} ruleMatch
	 * @param {string} outboundTag
	 */
	function addDNS(entry, ruleMatch, outboundTag) {
		if (outboundTag == TAG.block) {
			die(`rule "${entry.name}" DNS exit cannot be Block`);
		}
		let tag = entry.name + '-dns', server = dnsServer(entry.dns, tag);
		optional(server, 'domains', xrayDomains(ruleMatch));
		optional(server, 'queryStrategy', dnsStrategy(entry.strategy));
		push(dnsServers, server);
		let serverTags = dnsExits[outboundTag];
		if (type(serverTags) != 'array') {
			serverTags = [];
			dnsExits[outboundTag] = serverTags;
			push(exitOrder, outboundTag);
		}
		push(serverTags, tag);
	}
	for (let entry in settings.entries) {
		let splitMatch = null;
		let versions = entry.split ? filter([4, 6], version => version == 4 ? entry.v4 : entry.v6) : [0];
		for (let version in versions) {
			let ruleMatch = entry.match;
			let name = entry.name + (version && entry.name ? `-ipv${version}` : '');
			let outboundTag = entry.exit;
			if (version == 4) {
				outboundTag = entry.v4;
			}
			else if (version == 6) {
				outboundTag = entry.v6;
			}
			if (empty(ruleMatch, true) || length(ruleMatch.sets) && !hasDomain(ruleMatch) && !length(ruleMatch.ip) && !length(ruleMatch.geosite) && !length(ruleMatch.geoip)) {
				continue;
			}
			for (let protocol in ruleMatch.protocol) {
				if (index(['http', 'tls', 'quic', 'bittorrent'], protocol) < 0) {
					die(`unsupported Xray route protocol "${protocol}"`);
				}
			}
			push(routes, ...xrayRules(ruleMatch, name, outboundTag, version));
			if (outboundTag == TAG.block) {
				continue;
			}
			if (entry.split) {
				if (hasDomain(ruleMatch, true) && !splitMatch) {
					splitMatch = ruleMatch;
				}
			}
			else if (hasDomain(ruleMatch, true)) {
				addDNS(entry, ruleMatch, entry.dnsExit || outboundTag);
			}
		}
		if (splitMatch) {
			if (!entry.dnsExit) {
				die(`split rule "${entry.name}" requires a DNS exit`);
			}
			addDNS(entry, splitMatch, entry.dnsExit);
		}
	}
	let defaultServer = dnsServer(settings.dns, 'default-dns');
	defaultServer.skipFallback = false;
	push(dnsServers, defaultServer);
	for (let outboundTag in exitOrder) {
		push(routeRules, { inboundTag: dnsExits[outboundTag], outboundTag });
	}
	push(routeRules, ...routes);
	return config;
};
