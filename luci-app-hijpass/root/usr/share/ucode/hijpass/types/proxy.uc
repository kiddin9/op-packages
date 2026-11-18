/**
 * @typedef {{
 *   mux_enabled?: boolean,
 *   mux_concurrency?: integer,
 *   mux_xudp_concurrency?: integer,
 *   mux_udp443?: string
 * }} XrayMuxOptions
 */

/** @typedef {import('./transport.uc').TransportOptions} TransportOptions */
// 已解码的节点与能力字段；原始 UCI 字段声明位于 config/protocol/。

/**
 * 解码后统一补齐的标识、本地端口和依赖；upstream/members 连接到节点对象。
 * @typedef {{
 *   '.name': string,
 *   name: string,
 *   listen_port: integer,
 *   socks_port: integer,
 *   id: string,
 *   config_type: string,
 *   type: string,
 *   core: string,
 *   upstream: DecodedProxyNode|null,
 *   members: DecodedProxyNode[]
 * }} ProxyIdentity
 */

/**
 * @typedef {ProxyIdentity & {
 *   config_type: 'generated',
 *   log_level: string
 * }} GeneratedProxy
 */

/**
 * 远端地址与可选网络；ShadowTLS 不声明 network，读取时为 null。
 * @typedef {GeneratedProxy & {
 *   server: string,
 *   server_port: integer,
 *   network: string|null
 * }} RemoteProxy
 */

/**
 * 经 config/values.decode 转换的字段；布尔、整数与时长字符串不再混用。
 * @typedef {{
 *   tls_server_name: string,
 *   tls_insecure: boolean
 * }} TLSOptions
 */

/**
 * 经 config/values.decode 转换的字段；布尔、整数与时长字符串不再混用。
 * @typedef {{
 *   tls_reality_enabled: boolean,
 *   tls_reality_public_key: string,
 *   tls_reality_short_id: string
 * }} RealityOptions
 */

/**
 * 经 config/values.decode 转换的字段；布尔、整数与时长字符串不再混用。
 * @typedef {{
 *   multiplex_enabled: boolean,
 *   multiplex_padding: boolean,
 *   multiplex_protocol: string,
 *   multiplex_max_connections: integer|null,
 *   multiplex_min_streams: integer|null,
 *   multiplex_max_streams: integer|null,
 *   multiplex_brutal_enabled: boolean,
 *   multiplex_brutal_up_mbps: integer|null,
 *   multiplex_brutal_down_mbps: integer|null
 * }} MultiplexOptions
 */


/**
 * @typedef {RemoteProxy & MultiplexOptions & XrayMuxOptions & {
 *   type: 'shadowsocks',
 *   password: string,
 *   network: string,
 *   method: string,
 *   plugin: string,
 *   plugin_opts: string,
 *   udp_over_tcp: boolean
 * }} ShadowsocksProxy
 */

/**
 * @typedef {RemoteProxy & TLSOptions & RealityOptions & MultiplexOptions & XrayMuxOptions & TransportOptions & {
 *   type: 'vless',
 *   security: string,
 *   uuid: string,
 *   network: string,
 *   flow: string,
 *   packet_encoding: string
 * }} VlessProxy
 */

/**
 * @typedef {RemoteProxy & TLSOptions & {
 *   type: 'hysteria2',
 *   password: string,
 *   network: string,
 *   up_mbps: integer|null,
 *   down_mbps: integer|null,
 *   udp_idle_timeout: integer|null,
 *   server_ports: string[],
 *   hop_interval: string,
 *   obfs_type: string,
 *   obfs_password: string
 * }} Hysteria2Proxy
 */

/**
 * @typedef {RemoteProxy & TLSOptions & {
 *   type: 'tuic',
 *   password: string,
 *   uuid: string,
 *   network: string,
 *   congestion_control: string,
 *   udp_relay_mode: string,
 *   udp_over_stream: boolean,
 *   zero_rtt_handshake: boolean,
 *   heartbeat: string
 * }} TuicProxy
 */

/**
 * @typedef {RemoteProxy & TLSOptions & {
 *   type: 'shadowtls',
 *   password: string,
 *   version: integer
 * }} ShadowtlsProxy
 */

/**
 * @typedef {GeneratedProxy & {
 *   type: 'load_balance',
 *   url: string,
 *   interval: string,
 *   tolerance: integer|null,
 *   idle_timeout: string,
 *   interrupt_exist_connections: boolean,
 *   strategy: string,
 *   strategy_expected: integer,
 *   strategy_max_rtt: string,
 *   strategy_tolerance: double,
 *   fallback_tag: string,
 *   probe_url: string,
 *   probe_connectivity: string,
 *   probe_interval: string,
 *   probe_timeout: string,
 *   probe_sampling: integer,
 *   probe_http_method: string
 * }} BalanceProxy
 */

/**
 * @typedef {ProxyIdentity & {
 *   config_type: 'custom',
 *   core: '',
 *   type: '',
 *   command: string
 * }} CustomProxy
 */

/**
 * @typedef {ShadowsocksProxy|VlessProxy|Hysteria2Proxy|TuicProxy|ShadowtlsProxy|BalanceProxy} GeneratedProxyNode
 */

/**
 * 原始 ProxyNodeSection 经 decodeProxy() 转换后的节点；端口为整数，依赖为节点引用。
 * @typedef {CustomProxy|GeneratedProxyNode} DecodedProxyNode
 */

/**
 * @typedef {{
 *   [name: string]: DecodedProxyNode
 * }} ProxyIndex
 */

/**
 * @typedef {{
 *   nodes: DecodedProxyNode[]
 * }} ProxyGraph
 */

/**
 * @typedef {ProxyGraph & {
 *   byName: ProxyIndex
 * }} RoutingDependencies
 */

/**
 * @typedef {RoutingDependencies & {
 *   byID: ProxyIndex
 * }} ResolvedDependencies
 */

/**
 * TLS 公共选项读取的远端节点字段。
 * @typedef {RemoteProxy & TLSOptions} TLSProxy
 */
