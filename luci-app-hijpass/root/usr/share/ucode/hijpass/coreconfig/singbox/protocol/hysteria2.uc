/** @typedef {import('../../../types/json.uc').JsonObject} JsonObject */
/** @typedef {import('../../../types/proxy.uc').Hysteria2Proxy} Hysteria2Proxy */
import { endpoint, tls } from './options.uc';
import { optional } from '../../json.uc';

// up_mbps/down_mbps 为带宽；server_ports 为端口跳跃范围，核心使用冒号分隔。
// hop_interval 为跳跃间隔；obfs 仅支持有密码的 salamander。
/**
 * 将 Hysteria2 节点转换为 sing-box 原生出站配置。
 * @param {Hysteria2Proxy} n 已解码的专用字段；通用地址/TLS 交给 options.uc。
 * @returns {JsonObject} 含 TLS、认证及可选带宽、跳跃端口和混淆设置的出站对象。
 */
export function build(n) {
	let out = endpoint(n);
	out.tls = tls(n);
	optional(out, 'password', n.password);
	optional(out, 'up_mbps', n.up_mbps);
	optional(out, 'down_mbps', n.down_mbps);
	optional(out, 'server_ports', map(n.server_ports, p => replace(p, '-', ':')));
	optional(out, 'hop_interval', n.hop_interval);
	if (n.obfs_type == 'salamander' && n.obfs_password) {
		out.obfs = { type: n.obfs_type, password: n.obfs_password };
	}
	return out;
};
