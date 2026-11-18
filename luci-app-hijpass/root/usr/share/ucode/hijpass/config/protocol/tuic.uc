import { BASE_FIELDS, SERVER_FIELDS, TLS_FIELDS } from './options.uc';

// tuic 的字段契约；不包含其它协议的专用字段。
export const fields = {
	...BASE_FIELDS,
	...SERVER_FIELDS,
	...TLS_FIELDS,
	password: ["text", ""], // 远端认证密码
	uuid: ["text", ""], // 远端用户 UUID
	network: ["text", ""], // 允许的网络（tcp/udp 或组合）；空值使用核心默认值
	congestion_control: ["text", "cubic"], // TUIC 拥塞控制（cubic/new_reno/bbr），默认 cubic
	udp_relay_mode: ["text", ""], // TUIC UDP 转发模式（native/quic）
	udp_over_stream: ["bool", false], // 0/1；使用 QUIC stream 转发 UDP
	zero_rtt_handshake: ["bool", false], // 0/1；启用 TUIC 0-RTT 握手
	heartbeat: ["duration", "10s"], // TUIC 心跳间隔，保留时长字符串；默认 10 秒
};
