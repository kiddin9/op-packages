import { BASE_FIELDS, SERVER_FIELDS, TLS_FIELDS, REALITY_FIELDS, MULTIPLEX_FIELDS, TRANSPORT_FIELDS } from './options.uc';

// vless 的字段契约；不包含其它协议的专用字段。
export const fields = {
	...BASE_FIELDS,
	...SERVER_FIELDS,
	...TLS_FIELDS,
	...REALITY_FIELDS,
	...MULTIPLEX_FIELDS,
	...TRANSPORT_FIELDS,
	security: ["text", ""], // 空值兼容旧节点的 TLS/REALITY 选择
	uuid: ["text", ""], // 远端用户 UUID
	network: ["text", "tcp"], // 允许的网络（tcp/udp 或组合）；空值使用核心默认值
	flow: ["text", ""], // VLESS flow，例如 xtls-rprx-vision
	packet_encoding: ["text", ""], // sing-box UDP 包封装（xudp/packetaddr）
};
