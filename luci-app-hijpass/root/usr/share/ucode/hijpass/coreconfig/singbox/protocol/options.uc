/** @typedef {import('../../../types/json.uc').JsonObject} JsonObject */
/** @typedef {import('../../../types/proxy.uc').TLSProxy} TLSProxy */
/** @typedef {import('../../../types/transport.uc').TransportOptions} TransportOptions */
/** @typedef {import('../../../types/proxy.uc').MultiplexOptions} MultiplexOptions */
/** @typedef {import('../../../types/proxy.uc').RemoteProxy} RemoteProxy */
import { optional } from '../../json.uc';

// Native outbound 公共字段：type/tag 标识协议与出口，server/server_port 远端地址。
// tls 只由支持 TLS 的协议添加；detour 由调用者从已连接的 upstream 设置。
/**
 * 填写 sing-box 出站的协议、地址和网络字段。
 * @param {RemoteProxy} n
 * @returns {JsonObject} 基础出站对象，供具体协议继续补充。
 */
export function endpoint(n) {
	let out = { type: n.type, tag: n.name, server: n.server, server_port: n.server_port };
	return optional(out, 'network', n.network);
};
/**
 * 生成已启用的 TLS 设置，并补上默认服务器名称。
 * @param {TLSProxy} n
 * @returns {JsonObject} TLS 对象；SNI 默认使用节点 server。
 */
export function tls(n) {
	return { enabled: true, server_name: n.tls_server_name || n.server, insecure: n.tls_insecure };
};
/**
 * 生成连接复用设置，按需附加 Brutal 参数。
 * @param {MultiplexOptions} n
 * @returns {JsonObject|null} multiplex 对象；未启用时为 null。
 */
export function multiplex(n) {
	if (!n.multiplex_enabled) {
		return null;
	}
	let out = { enabled: true, protocol: n.multiplex_protocol };
	if (n.multiplex_padding) out.padding = true;
	for (let key in ['max_connections', 'min_streams', 'max_streams']) optional(out, key, n[`multiplex_${key}`]);
	if (n.multiplex_brutal_enabled) {
		out.brutal = { enabled: true };
		optional(out.brutal, 'up_mbps', n.multiplex_brutal_up_mbps);
		optional(out.brutal, 'down_mbps', n.multiplex_brutal_down_mbps);
	}
	return out;
};
/**
 * 将节点传输选项转换为 sing-box 传输配置。
 * @param {TransportOptions} n
 * @returns {JsonObject|null} transport 对象；未选择传输时为 null，不支持的类型抛错。
 */
export function transport(n) {
	let kind = n.transport_type;
	if (!kind) {
		return null;
	}
	let out = { type: kind };
	switch (kind) {
	case 'http':
		optional(out, 'host', n.transport_http_host);
		optional(out, 'path', n.transport_http_path);
		optional(out, 'method', n.transport_http_method);
		optional(out, 'idle_timeout', n.transport_http_idle_timeout);
		optional(out, 'ping_timeout', n.transport_http_ping_timeout);
		break;
	case 'ws':
		optional(out, 'path', n.transport_ws_path);
		optional(out, 'max_early_data', n.transport_ws_max_early_data);
		optional(out, 'early_data_header_name', n.transport_ws_early_data_header_name);
		if (n.transport_ws_host) {
			out.headers = { Host: n.transport_ws_host };
		}
		break;
	case 'grpc':
		optional(out, 'service_name', n.transport_grpc_service_name);
		optional(out, 'idle_timeout', n.transport_grpc_idle_timeout);
		optional(out, 'ping_timeout', n.transport_grpc_ping_timeout);
		if (n.transport_grpc_permit_without_stream) {
			out.permit_without_stream = true;
		}
		break;
	case 'httpupgrade':
		optional(out, 'host', n.transport_httpupgrade_host);
		optional(out, 'path', n.transport_httpupgrade_path);
		break;
	default: die(`unsupported sing-box transport "${kind}"`);
	}
	return out;
};
