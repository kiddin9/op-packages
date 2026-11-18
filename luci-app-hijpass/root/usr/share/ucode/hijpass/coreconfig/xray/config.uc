/** @typedef {import('../../types/json.uc').JsonObject} JsonObject */
/** @typedef {import('../../types/core.uc').XrayConfig} XrayConfig */
/** @typedef {import('../../types/proxy.uc').GeneratedProxyNode} GeneratedProxyNode */
import { build as shadowsocks } from './protocol/shadowsocks.uc';
import { build as vless } from './protocol/vless.uc';
import { build as hysteria2 } from './protocol/hysteria2.uc';
import { TYPE } from '../../config/protocol/proxy.uc';
import { TAG } from '../constants.uc';

const builders = { [TYPE.shadowsocks]: shadowsocks, [TYPE.vless]: vless, [TYPE.hysteria2]: hysteria2 };
/**
 * 生成连接本机节点端口的 Xray SOCKS 出站配置。
 * @returns {JsonObject} Xray SOCKS 出站对象。
 */
export function socks(tag, port) {
	return { protocol: 'socks', tag, settings: { address: '127.0.0.1', port } };
};
/**
 * 规范化日志级别，生成 Xray 日志设置。
 * @returns {JsonObject} {loglevel, dnsLog}；warn 转为 warning，默认 info。
 */
export function log(level) { return { loglevel: level == 'warn' ? 'warning' : level || 'info', dnsLog: false }; };
/**
 * 生成 Xray 入站，按类型设置透明代理、UDP 或嗅探。
 * @returns {JsonObject} Xray 入站对象。
 */
export function inbound(kind, tag, port, shunt) {
	let out = { protocol: kind == 'socks' ? 'socks' : 'dokodemo-door', port, tag };
	if (kind == 'socks') {
		out.settings = { udp: true };
	}
	else {
		out.settings = { network: 'tcp,udp' };
		if (kind == 'tproxy') {
			out.settings.followRedirect = true;
			out.streamSettings = { sockopt: { tproxy: 'tproxy' } };
			if (shunt) {
				out.sniffing = { enabled: true, destOverride: ['http', 'tls', 'quic'], routeOnly: true };
			}
		}
		else {
			out.listen = '::';
		}
	}
	return out;
};

// Config 字段：log/inbounds/outbounds 为核心基础配置；routing 为路由表。
// burstObservatory.pingConfig 为负载均衡探测参数，时长使用核心字符串格式。
/**
 * 组装单个节点的完整 Xray 配置。
 * @param {GeneratedProxyNode} n
 * @returns {XrayConfig} 含日志、入站和出站的配置对象；均衡节点附路由和探测设置。
 */
export function build(n) {
	let config = {
		log: log(n.log_level),
		inbounds: [inbound('tproxy', TAG.tproxy, n.listen_port), inbound('socks', TAG.socks, n.socks_port)],
		outbounds: [],
	};
	if (n.type == TYPE.balance) {
		let fallback = TAG.member + '0';
		for (let i, member in n.members) {
			let tag = `${TAG.member}${i}`;
			if (member.name == n.fallback_tag) {
				fallback = tag;
			}
			push(config.outbounds, socks(tag, member.socks_port));
		}
		let strategy = { type: n.strategy || 'leastLoad' };
		if (strategy.type == 'leastLoad') {
			strategy.settings = {
				expected: n.strategy_expected ?? 1, maxRTT: n.strategy_max_rtt || '1s', tolerance: n.strategy_tolerance ?? 0.05,
			};
		}
		config.routing = {
			domainStrategy: 'AsIs',
			rules: [{ inboundTag: [TAG.tproxy, TAG.socks], balancerTag: TAG.balance }],
			balancers: [{ tag: TAG.balance, selector: [TAG.member], fallbackTag: fallback, strategy }],
		};
		config.burstObservatory = {
			subjectSelector: [TAG.member],
			pingConfig: {
				destination: n.probe_url || 'https://connectivitycheck.gstatic.com/generate_204', connectivity: n.probe_connectivity,
				interval: n.probe_interval || '60s', timeout: n.probe_timeout || '2s',
				sampling: n.probe_sampling || 3, httpMethod: n.probe_http_method,
			},
		};
	}
	else {
		let builder = builders[n.type];
		if (!builder) {
			die(`unsupported Xray protocol "${n.type}"`);
		}
		let out = builder(n);
		if (n.mux_enabled) out.mux = { enabled: true, concurrency: n.mux_concurrency,
			xudpConcurrency: n.mux_xudp_concurrency, xudpProxyUDP443: n.mux_udp443 };
		push(config.outbounds, out);
		if (n.upstream) {
			let tag = TAG.upstream + n.upstream.name;
			out.streamSettings ||= {};
			out.streamSettings.sockopt = { dialerProxy: tag, domainStrategy: 'UseIP' };
			push(config.outbounds, socks(tag, n.upstream.socks_port));
		}
	}
	return config;
};
