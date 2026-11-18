/** @typedef {import('../types/json.uc').JsonObject} JsonObject */
import { list, port } from '../config/values.uc';
import { TAG } from './constants.uc';
import { optional } from './json.uc';

// Match 字段均为数组：domain/suffix/keyword/regex 域名条件，ip 为地址或 CIDR，
// geoip/geosite 为 Geo 标签，network/protocol/ports/ranges 为传输限制。
// sets 元素：{type, tag, path|url}，表示本地或远端 sing-box 规则集。
/** @typedef {import('../types/routing.uc').Match} Match */
/** @typedef {import('../types/sections.uc').RuleMatchOptions} RuleMatchOptions */
/**
 * 将 UCI 分流规则拆成各类匹配条件。
 * @param {RuleMatchOptions} section UCI shunt_route_rule 的匹配字段。
 * @returns {Match} Match 对象，各类域名、IP、协议和端口条件均为数组。
 */
export function parse(section) {
	let r = {
		domain: [], suffix: [], keyword: [], regex: [], ip: [], geoip: [], geosite: [], sets: [],
		network: list(section.network), protocol: list(section.protocol),
		ports: map(list(section.port), p => port(p)), ranges: map(list(section.port_range), p => replace(p, '-', ':')),
	};
	for (let key in ['domain_list', 'ip_list']) {
		for (let line in split(section[key] || '', '\n')) {
			line = trim(line);
			if (!line || substr(line, 0, 1) == '#') {
				continue;
			}
			let set = match(line, /^rule-set:(local|remote):(.*)$/);
			if (set) {
				let filename = split(set[2], '/')[-1];
				let tag = replace(filename, /[.][^.]*$/, '');
				// source JSON 与 binary SRS 必须明确区分，不能使用核心的 binary 默认值。
				let entry = { type: set[1], tag, format: match(set[2], /srs$/) ? 'binary' : 'source' };
				entry[set[1] == 'remote' ? 'url' : 'path'] = set[2];
				push(r.sets, entry);
				continue;
			}
			if (key == 'ip_list') {
				push(substr(line, 0, 6) == 'geoip:' ? r.geoip : r.ip, line);
			}
			else {
				let prefix = match(line, /^(full|domain|regexp|geosite):(.*)$/);
				if (!prefix) {
					push(r.keyword, line);
				}
				else {
					switch (prefix[1]) {
					case 'full': push(r.domain, prefix[2]); break;
					case 'domain': push(r.suffix, prefix[2]); break;
					case 'regexp': push(r.regex, prefix[2]); break;
					case 'geosite': push(r.geosite, line); break;
					}
				}
			}
		}
	}
	return r;
};
/**
 * 检查规则是否包含域名条件，可按需计入 GeoSite。
 * @param {Match} r
 * @param {boolean} [includeGeoSite] 核心支持 GeoSite 或先转换规则集时纳入 GeoSite。
 * @returns {boolean} 存在域名条件时为 true。
 */
export function hasDomain(r, includeGeoSite) {
	return length(r.domain) + length(r.suffix) + length(r.keyword) + length(r.regex)
		+ (includeGeoSite ? length(r.geosite) : 0) > 0;
};
/**
 * 按当前核心支持的条件判断规则是否为空。
 * @param {Match} r
 * @param {boolean} geo 是否按 Xray Geo 标签判断匹配条件。
 * @returns {boolean} 没有可用匹配条件时为 true。
 */
export function empty(r, geo) {
	return !hasDomain(r) && !length(r.ip) && !length(r.network) && !length(r.protocol)
		&& !length(r.ports) && !length(r.ranges) && !(geo ? length(r.geoip) + length(r.geosite) : length(r.sets));
};
/**
 * 将 GeoSite 和 GeoIP 引用补充为本地 SRS 规则集引用。
 * @param {Match} r
 * @returns {null} 无业务返回值；追加到 r.sets，保留原 Geo 数组。
 */
export function convertGeo(r) {
	for (let value in [...r.geosite, ...r.geoip]) {
		let tag = replace(value, ':', '-');
		push(r.sets, { type: 'local', tag, format: 'binary', path: `/etc/hijpass/ruleset/${tag}.srs` });
	}
};
/**
 * 将匹配条件转换为 sing-box 规则字段。
 * @param {Match} r
 * @param {boolean} dnsOnly
 * @returns {JsonObject} 仅含非空字段的对象；dnsOnly 时省略 IP、网络、协议和端口。
 */
export function singboxMatch(r, dnsOnly) {
	let out = {};
	for (let key, values in { domain: r.domain, domain_suffix: r.suffix, domain_keyword: r.keyword, domain_regex: r.regex }) {
		if (length(values)) {
			out[key] = values;
		}
	}
	if (length(r.sets)) {
		out.rule_set = map(r.sets, s => s.tag);
	}
	if (!dnsOnly) {
		for (let key, values in { ip_cidr: r.ip, network: r.network, protocol: r.protocol, port: r.ports, port_range: r.ranges }) {
			if (length(values)) {
				out[key] = values;
			}
		}
	}
	return out;
};
/**
 * 将域名条件转换为 Xray 的前缀表达式。
 * @param {Match} r
 * @returns {string[]} 包含 full:/domain:/regexp:、关键字和 geosite: 的字符串数组。
 */
export function xrayDomains(r) {
	return [...map(r.domain, d => 'full:' + d), ...map(r.suffix, d => 'domain:' + d), ...r.keyword, ...map(r.regex, d => 'regexp:' + d), ...r.geosite];
};
/**
 * 将域名和 IP 匹配条件分别转换为 Xray 路由规则。
 * @param {Match} r
 * @param {string} name
 * @param {string} exit
 * @param {integer} version 0 表示不限制地址族，4/6 表示 IPv4/IPv6。
 * @returns {JsonObject[]} 带出口、名称及可选地址族限制的规则数组。
 */
export function xrayRules(r, name, exit, version) {
	let base = { inboundTag: [TAG.tproxy], outboundTag: exit };
	optional(base, 'ruleTag', name);
	optional(base, 'network', r.network);
	optional(base, 'protocol', r.protocol);
	optional(base, 'port', join(',', [...map(r.ports, p => `${p}`), ...map(r.ranges, p => replace(p, ':', '-'))]));
	let domains = xrayDomains(r);
	let ips = [...filter(r.ip, ip => {
		if (!version) {
			return true;
		}
		let value = replace(ip, /^!/, '');
		// ext: 文件规则和 geoip: 标签可能同时包含 IPv4/IPv6；冒号并不总是 IPv6 地址。
		if (match(value, /^(ext|geoip):/)) {
			return true;
		}
		if (index(value, ':') >= 0) {
			return version == 6;
		}
		return match(value, /^[0-9]{1,3}([.][0-9]{1,3}){3}(\/[0-9]+)?$/) ? version == 4 : true;
	}), ...r.geoip];
	let family = null;
	if (version == 4) {
		family = '0.0.0.0/0';
	}
	else if (version == 6) {
		family = '::/0';
	}
	let result = [];
	// Xray 的域名和 IP 条件分成两条规则，避免在单条规则中意外变成 AND。
	if (length(domains)) {
		let rule = { ...base, domain: domains };
		if (family) {
			rule.ip = [family];
		}
		push(result, rule);
	}
	if (length(ips)) {
		push(result, { ...base, ip: ips });
	}
	if (!length(result)) {
		if (family) {
			base.ip = [family];
		}
		push(result, base);
	}
	return result;
};
