import { BASE_FIELDS, SERVER_FIELDS, MULTIPLEX_FIELDS } from './options.uc';

// shadowsocks 的字段契约；不包含其它协议的专用字段。
export const fields = {
	...BASE_FIELDS,
	...SERVER_FIELDS,
	...MULTIPLEX_FIELDS,
	password: ["text", ""], // 远端认证密码
	network: ["text", ""], // 允许的网络（tcp/udp 或组合）；空值使用核心默认值
	method: ["text", ""], // Shadowsocks 加密方法
	plugin: ["text", ""], // sing-box SIP003 插件名称
	plugin_opts: ["text", ""], // SIP003 插件参数字符串
	udp_over_tcp: ["bool", false], // 0/1；sing-box UDP-over-TCP；新版 Xray 已不支持
};
