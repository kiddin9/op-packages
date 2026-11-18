/** @typedef {import('../../../types/json.uc').JsonObject} JsonObject */
/** @typedef {import('../../../types/proxy.uc').TuicProxy} TuicProxy */
import { endpoint, tls } from './options.uc';
import { optional } from '../../json.uc';

// UUID/password 为认证；congestion_control 为拥塞算法，udp_relay_mode 为 UDP 模式。
// udp_over_stream/zero_rtt_handshake 为开关，heartbeat 为 QUIC 心跳间隔。
/**
 * 将 TUIC 节点转换为 sing-box 原生出站配置。
 * @param {TuicProxy} n
 * @returns {JsonObject} 含 TLS、认证、拥塞控制和 UDP 设置的出站对象。
 */
export function build(n) {
	let out = endpoint(n);
	out.tls = tls(n);
	for (let key in ['uuid', 'password', 'congestion_control', 'udp_relay_mode'])
		optional(out, key, n[key]);
	for (let key in ['udp_over_stream', 'zero_rtt_handshake']) {
		if (n[key]) {
			out[key] = true;
		}
	}
	optional(out, 'heartbeat', n.heartbeat);
	return out;
};
