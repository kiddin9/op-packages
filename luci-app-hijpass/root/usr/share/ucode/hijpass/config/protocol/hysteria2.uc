import { BASE_FIELDS, SERVER_FIELDS, TLS_FIELDS } from './options.uc';

// hysteria2 的字段契约；不包含其它协议的专用字段。
export const fields = {
	...BASE_FIELDS,
	...SERVER_FIELDS,
	...TLS_FIELDS,
	password: ["text", ""], // 远端认证密码
	network: ["text", ""], // 允许的网络（tcp/udp 或组合）；空值使用核心默认值
	up_mbps: ["integer", null, 2147483647], // Hysteria2 上行 Mbps；null 表示未设置，0 为明确设置零值
	down_mbps: ["integer", null, 2147483647], // Hysteria2 下行 Mbps；保留未设置与显式 0 的差异
	udp_idle_timeout: ["integer", null], // UDP 会话空闲超时，单位秒
	server_ports: ["list", []], // 跳跃端口或范围的字符串列表
	hop_interval: ["duration", ""], // 端口跳跃间隔，保留时长字符串
	obfs_type: ["text", ""], // QUIC 混淆类型，例如 salamander
	obfs_password: ["text", ""], // QUIC 混淆密码
};
