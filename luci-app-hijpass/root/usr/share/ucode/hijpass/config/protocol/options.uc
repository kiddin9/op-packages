// 共享字段只由支持该能力的协议组合；每个对象均是明确的字段声明。
export const LOCAL_FIELDS = {
	".name": ["text", ""], // UCI section ID；用于文件名和依赖索引，不是显示名称
	name: ["text", ""], // 节点名称；其它节点通过此名称引用它
	listen_port: ["port", 0], // 本机透明代理监听端口，1–65535
	socks_port: ["port", 0], // 本机 SOCKS 监听端口，供代理链/分流访问，1–65535
};

export const BASE_FIELDS = {
	...LOCAL_FIELDS,
	config_type: ["text", "generated"], // generated 自动生成配置；custom 由用户维护配置与命令
	type: ["text", ""], // 协议名，决定选用哪份字段声明和生成器
	core: ["text", "sing-box"], // 自动生成使用的核心：sing-box/xray
	log_level: ["text", "info"], // 核心日志级别；默认 info
};

export const SERVER_FIELDS = {
	server: ["text", ""], // 远端域名或 IP；链式代理启动前会解析域名
	server_port: ["port", 0], // 远端服务监听端口，1–65535
};

export const TLS_FIELDS = {
	tls_server_name: ["text", ""], // TLS SNI 与证书校验名称；解析 server 不会改写此字段
	tls_insecure: ["bool", false], // 0/1；允许跳过 TLS 证书校验
};

export const REALITY_FIELDS = {
	tls_reality_enabled: ["bool", false], // 0/1；启用 Reality 握手
	tls_reality_public_key: ["text", ""], // Reality 服务端公钥
	tls_reality_short_id: ["text", ""], // Reality short ID，十六进制字符串
};

export const MULTIPLEX_FIELDS = {
	multiplex_enabled: ["bool", false], // 0/1；启用连接复用
	multiplex_padding: ["bool", false], // sing-box 复用填充
	multiplex_protocol: ["text", "h2mux"], // sing-box 复用协议（h2mux/smux/yamux）
	multiplex_max_connections: ["integer", null, 2147483647], // sing-box 最大底层连接数；0 使用核心默认值
	multiplex_min_streams: ["integer", null, 2147483647], // sing-box 每连接最小流数；0 使用核心默认值
	multiplex_max_streams: ["integer", null, 2147483647], // sing-box 每连接最大流数
	multiplex_brutal_enabled: ["bool", false], // 0/1；启用 sing-box Brutal 复用拥塞控制
	multiplex_brutal_up_mbps: ["integer", null, 2147483647], // Brutal 上行带宽，单位 Mbps
	multiplex_brutal_down_mbps: ["integer", null, 2147483647], // Brutal 下行带宽，单位 Mbps
};

export const TRANSPORT_FIELDS = {
	transport_type: ["text", ""], // 传输封装类型；空值为协议默认传输
	transport_http_host: ["text", ""], // HTTP 传输的 Host 头
	transport_http_path: ["text", ""], // HTTP 传输请求路径
	transport_http_method: ["text", ""], // HTTP 传输请求方法
	transport_http_idle_timeout: ["duration", "15s"], // HTTP 空闲时长；UCI 写时长字符串，保留时长字符串
	transport_http_ping_timeout: ["duration", "15s"], // HTTP ping 等待时长，保留时长字符串
	transport_ws_host: ["text", ""], // WebSocket Host 头
	transport_ws_path: ["text", ""], // WebSocket 请求路径
	transport_ws_max_early_data: ["integer", null, 4294967295], // WebSocket early data 最大字节数
	transport_ws_early_data_header_name: ["text", ""], // 承载 WebSocket early data 的 HTTP 头名
	transport_grpc_service_name: ["text", ""], // gRPC service 名称
	transport_grpc_idle_timeout: ["duration", "15s"], // gRPC 空闲时长，保留时长字符串
	transport_grpc_ping_timeout: ["duration", "15s"], // gRPC ping 等待时长，保留时长字符串
	transport_grpc_permit_without_stream: ["bool", false], // 0/1；没有活跃流时仍发送 gRPC ping
	transport_httpupgrade_host: ["text", ""], // HTTPUpgrade Host 头
	transport_httpupgrade_path: ["text", ""], // HTTPUpgrade 请求路径
	transport_xhttp_host: ["text", ""], // Xray XHTTP Host 头
	transport_xhttp_path: ["text", ""], // Xray XHTTP 请求路径
	transport_xhttp_mode: ["text", ""], // Xray XHTTP 模式（auto/packet-up/stream-up/stream-one）
	transport_xhttp_method: ["text", ""], // Xray XHTTP 上行请求方法；空值使用核心默认值
};
