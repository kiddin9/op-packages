/** @typedef {import('../../types/proxy.uc').DecodedProxyNode} DecodedProxyNode */
/** @typedef {import('../../types/proxy-sections.uc').ProxyNodeSection} ProxyNodeSection */
import { fields as shadowsocks } from './shadowsocks.uc';
import { fields as vless } from './vless.uc';
import { fields as hysteria2 } from './hysteria2.uc';
import { fields as tuic } from './tuic.uc';
import { fields as shadowtls } from './shadowtls.uc';
import { fields as loadbalance } from './loadbalance.uc';
import { LOCAL_FIELDS } from './options.uc';
import { decode, duration } from '../values.uc';

// 核心由 core 字段决定；未设置时统一使用 sing-box，不根据协议推断。
export const CORE = { singbox: 'sing-box', xray: 'xray' };
/**
 * 为空的核心选项补上默认值。
 * @param {string|null} [value]
 * @returns {string} 核心名称，默认为 sing-box；此处不校验支持情况。
 */
export function core(value) { return value || CORE.singbox; };

export const CONFIG_TYPE = { generated: 'generated', custom: 'custom' };
/**
 * 规范化配置类型，并拒绝不支持的类型。
 * @param {string|null} [value]
 * @returns {string} generated 或 custom，默认为 generated。
 */
export function configType(value) {
	value ||= CONFIG_TYPE.generated;
	if (index(values(CONFIG_TYPE), value) < 0) {
		die(`unsupported config_type "${value}"`);
	}
	return value;
};

export const TYPE = {
	shadowsocks: 'shadowsocks', vless: 'vless', hysteria2: 'hysteria2',
	tuic: 'tuic', shadowtls: 'shadowtls', balance: 'load_balance',
};
const protocols = {
	[TYPE.shadowsocks]: shadowsocks, [TYPE.vless]: vless, [TYPE.hysteria2]: hysteria2,
	[TYPE.tuic]: tuic, [TYPE.shadowtls]: shadowtls, [TYPE.balance]: loadbalance,
};
// 自定义配置只声明本地接入信息和用户命令，不读取核心、协议或日志级别。
const commandFields = {
	...LOCAL_FIELDS,
	command: ['text', ''], // 原样交给 /bin/sh -c；可用 {conf_path} 引用用户配置文件
};

// Proxy 为对应协议 fields 的解码结果，只包含该协议声明的字段，额外包含：
// id/name/config_type（标识），type/core（仅自动生成），upstream（上游 Proxy 或 null），members（成员数组）。
// upstream/members 在 dependencies.uc 中连接，生成器不再根据名字查询和重复解码。
/**
 * 把 UCI 节点转换为对应配置类型，并校验必填字段。
 * 返回：节点对象；upstream 为 null，members 为空数组，等待连接依赖。
 * @param {ProxyNodeSection} section
 * @returns {DecodedProxyNode}
 */
export function decodeProxy(section) {
	let mode = configType(section.config_type), custom = mode == CONFIG_TYPE.custom;
	let engine = custom ? '' : core(section.core);
	if (!custom && index(values(CORE), engine) < 0) {
		die(`unsupported core "${engine}"`);
	}
	let fields = custom ? commandFields : protocols[section.type];
	if (!fields) {
		die(`unsupported proxy type "${section.type}"`);
	}
	let node = decode(section, fields);
	node.id = section['.name'];
	node.name = section.name || node.id;
	node.config_type = mode;
	node.type = custom ? '' : section.type;
	node.core = engine;
	node.upstream = null;
	node.members = [];
	if (custom && !trim(node.command)) {
		die(`custom node "${node.name}" has no command`);
	}
	if (!node.listen_port || !node.socks_port) {
		die('invalid listen_port or socks_port');
	}
	if (!custom && node.type != TYPE.balance && (!node.server || !node.server_port)) {
		die('invalid server or server_port');
	}
	if (node.type == TYPE.vless) {
		// 旧 sing-box 默认启用 TLS；旧 Xray 仅在填写 SNI 时启用 TLS。
		node.security ||= node.tls_reality_enabled ? 'reality'
			: (engine == CORE.singbox || node.tls_server_name ? 'tls' : 'none');
		if (index(['none', 'tls', 'reality'], node.security) < 0) die('unsupported VLESS security');
	}
	if (node.type == TYPE.vless && engine == CORE.xray && node.transport_type == 'grpc'
		&& (duration(node.transport_grpc_idle_timeout) > 2147483647 || duration(node.transport_grpc_ping_timeout) > 2147483647)) {
		die('gRPC timeout exceeds 32-bit range');
	}
	if (engine == CORE.xray && index([TYPE.shadowsocks, TYPE.vless], node.type) >= 0) {
		node.mux_enabled = decode(section, { mux_enabled: ['bool', false] }).mux_enabled;
		if (node.mux_enabled) {
			let mux = decode(section, { mux_concurrency: ['text', '8'], mux_xudp_concurrency: ['text', '16'],
				mux_udp443: ['text', 'reject'] });
			for (let key, maximum in { mux_concurrency: 128, mux_xudp_concurrency: 1024 }) {
				if (!match(mux[key], /^-?[0-9]+$/) || +mux[key] < -1 || +mux[key] > maximum)
					die(`${key} must be an integer from -1 to ${maximum}`);
				mux[key] = int(mux[key]);
			}
			if (index(['reject', 'allow', 'skip'], mux.mux_udp443) < 0) die('invalid Mux UDP/443 policy');
			if (node.type == TYPE.vless && node.flow && mux.mux_concurrency >= 0)
				die('Vision requires Mux TCP concurrency -1; use XUDP for UDP multiplexing');
			node = { ...node, ...mux };
		}
	}
	return node;
};
