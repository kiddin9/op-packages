/** @typedef {import('../../../types/json.uc').JsonObject} JsonObject */
/** @typedef {import('../../../types/proxy.uc').Hysteria2Proxy} Hysteria2Proxy */
// Hysteria2 在 Xray 中使用 hysteria 协议及 version=2；认证位于传输设置。
// 带宽放在 finalmask.quicParams；未设置与明确为 0 必须区分。
/**
 * 将 Hysteria2 节点转换为 Xray 原生出站配置。
 * @param {Hysteria2Proxy} n
 * @returns {JsonObject} 使用 hysteria 协议、版本 2 的出站对象，认证和带宽位于 streamSettings。
 */
export function build(n) {
	let stream = {
		network: 'hysteria', security: 'tls',
		tlsSettings: { serverName: n.tls_server_name || n.server, alpn: ['h3'] },
		hysteriaSettings: { version: 2, auth: n.password, udpIdleTimeout: n.udp_idle_timeout },
	};
	if (n.up_mbps != null || n.down_mbps != null) {
		/**
		 * 将带宽数值转换成 Xray 所需的文本格式。
		 * @returns {string} 未设置为 ""，零值为 "0"，其他为 "数值 mbps"。
		 */
		function bandwidth(value) {
			if (value == null) {
				return '';
			}
			if (value) {
				return `${value} mbps`;
			}
			return '0';
		}
		stream.finalmask = { quicParams: { brutalUp: bandwidth(n.up_mbps), brutalDown: bandwidth(n.down_mbps) } };
	}
	return {
		protocol: 'hysteria', tag: n.name,
		settings: { version: 2, address: n.server, port: n.server_port },
		streamSettings: stream,
	};
};
