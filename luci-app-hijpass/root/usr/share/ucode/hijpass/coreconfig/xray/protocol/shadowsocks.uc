/** @typedef {import('../../../types/json.uc').JsonObject} JsonObject */
/** @typedef {import('../../../types/proxy.uc').ShadowsocksProxy} ShadowsocksProxy */
// settings 使用最新 Xray 的扁平地址结构；不再生成旧 servers 数组。
// 最新核心已移除 udp_over_tcp，明确报错以避免生成无效配置。
/**
 * 将 Shadowsocks 节点转换为 Xray 原生出站配置。
 * @param {ShadowsocksProxy} n
 * @returns {JsonObject} 出站对象，地址和认证字段直接位于 settings。
 */
export function build(n) {
	if (n.udp_over_tcp) {
		die('Xray main no longer supports Shadowsocks udp_over_tcp; disable it or select sing-box');
	}
	return {
		protocol: n.type, tag: n.name,
		settings: { address: n.server, port: n.server_port, method: n.method, password: n.password },
	};
};
