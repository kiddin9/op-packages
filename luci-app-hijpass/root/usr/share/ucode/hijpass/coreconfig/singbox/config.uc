/** @typedef {import('../../types/json.uc').JsonObject} JsonObject */
/** @typedef {import('../../types/core.uc').SingboxConfig} SingboxConfig */
/** @typedef {import('../../types/proxy.uc').GeneratedProxyNode} GeneratedProxyNode */
import { build as shadowsocks } from './protocol/shadowsocks.uc';
import { build as vless } from './protocol/vless.uc';
import { build as hysteria2 } from './protocol/hysteria2.uc';
import { build as tuic } from './protocol/tuic.uc';
import { build as shadowtls } from './protocol/shadowtls.uc';
import { TYPE } from '../../config/protocol/proxy.uc';
import { TAG } from '../constants.uc';
import { optional } from '../json.uc';

const builders = {
	[TYPE.shadowsocks]: shadowsocks, [TYPE.vless]: vless, [TYPE.hysteria2]: hysteria2,
	[TYPE.tuic]: tuic, [TYPE.shadowtls]: shadowtls,
};

/**
 * 生成连接本机节点端口的 SOCKS5 出站配置。
 * @returns {JsonObject} sing-box SOCKS5 出站对象。
 */
export function socks(tag, port) {
	return { type: 'socks', tag, server: '127.0.0.1', server_port: port, version: '5' };
};
/**
 * 生成 sing-box 入站，默认只监听本机。
 * @returns {JsonObject} 含 type、tag、listen 和 listen_port 的入站对象。
 */
export function inbound(kind, tag, port, address) {
	return { type: kind, tag, listen: address || '127.0.0.1', listen_port: port };
};

// Config 字段：log 日志；dns DNS 服务器和规则；inbounds 本地监听；
// outbounds 远端出口；route 匹配规则及默认出口。返回普通 JSON 对象。
/**
 * 组装单个节点的完整 sing-box 配置。
 * @param {GeneratedProxyNode} n
 * @returns {SingboxConfig} 含日志、DNS、入站、出站和路由的配置对象。
 */
export function build(n) {
	let config = {
		log: { disabled: false, level: n.log_level || 'info', timestamp: true },
		dns: { servers: [{ type: 'local', tag: 'local' }] },
		inbounds: [inbound('tproxy', TAG.tproxy, n.listen_port), inbound('socks', TAG.socks, n.socks_port)],
		outbounds: [],
		route: { default_domain_resolver: 'local' },
	};
	if (n.type == TYPE.balance) {
		let balance = { type: 'urltest', tag: TAG.balance, outbounds: [] };
		for (let key in ['url', 'tolerance']) optional(balance, key, n[key]);
		if (n.interrupt_exist_connections) {
			balance.interrupt_exist_connections = true;
		}
		for (let key in ['interval', 'idle_timeout']) optional(balance, key, n[key]);
		push(config.outbounds, balance);
		for (let i, member in n.members) {
			let tag = `${TAG.member}${i}`;
			push(balance.outbounds, tag);
			push(config.outbounds, socks(tag, member.socks_port));
		}
		config.route.final = TAG.balance;
	}
	else {
		let builder = builders[n.type];
		if (!builder) {
			die(`unsupported sing-box protocol "${n.type}"`);
		}
		let outbound = builder(n);
		push(config.outbounds, outbound);
		// 上游是已经连接的对象，不需要在构建阶段再次查询节点或做类型断言。
		if (n.upstream) {
			outbound.detour = TAG.upstream + n.upstream.name;
			push(config.outbounds, socks(outbound.detour, n.upstream.socks_port));
		}
	}
	return config;
};
