/**
 * @typedef {{
 *   mux_enabled?: string|null,
 *   mux_concurrency?: string|null,
 *   mux_xudp_concurrency?: string|null,
 *   mux_udp443?: string|null
 * }} RawXrayMuxOptions
 */

/** @typedef {import('./transport.uc').RawTransportOptions} RawTransportOptions */
/** @typedef {import('./sections.uc').NamedNodeSection} NamedNodeSection */
/** @typedef {import('./sections.uc').RawCommandOptions} RawCommandOptions */
// 原始代理类型按协议和能力组合；字段仍为 UCI 字符串，解码结果位于 proxy.uc。

/**
 * 所有代理节点共用的原始标识和本地运行设置；可承载尚未完成校验的输入。
 * @typedef {NamedNodeSection & {
 *   '.type': 'proxy_node',
 *   config_type: string|null,
 *   type: string|null,
 *   socks_port: string|null,
 *   nest_proxy: string|null
 * }} ProxyNodeSectionBase
 */

/**
 * 自动生成配置的公共核心与日志设置；缺失 config_type 沿用 generated 默认值。
 * @typedef {ProxyNodeSectionBase & {
 *   config_type: 'generated'|''|null,
 *   core: string|null,
 *   log_level: string|null
 * }} GeneratedProxySectionBase
 */

/**
 * 远端服务器地址与端口；本地服务端节点不使用这组字段。
 * @typedef {{
 *   server: string|null,
 *   server_port: string|null
 * }} RawRemoteOptions
 */

/**
 * 支持远端连接和上游代理的协议公共部分；均衡与自定义命令单独建模。
 * @typedef {
 *   GeneratedProxySectionBase &
 *   RawRemoteOptions &
 *   {
 *     upstream_proxy_node: string|null
 *   }
 * } ChainableProxySectionBase
 */

/**
 * 支持选择 TCP/UDP 的原始协议选项。
 * @typedef {{
 *   network: string|null
 * }} RawNetworkOptions
 */

/**
 * 使用密码认证的原始协议选项。
 * @typedef {{
 *   password: string|null
 * }} RawPasswordOptions
 */

/**
 * 原始 TLSOptions 能力；布尔、整数和时长均在解码时转换。
 * @typedef {{
 *   tls_server_name: string|null,
 *   tls_insecure: string|null
 * }} RawTLSOptions
 */

/**
 * 原始 RealityOptions 能力；布尔、整数和时长均在解码时转换。
 * @typedef {{
 *   tls_reality_enabled: string|null,
 *   tls_reality_public_key: string|null,
 *   tls_reality_short_id: string|null
 * }} RawRealityOptions
 */

/**
 * 原始 MultiplexOptions 能力；布尔、整数和时长均在解码时转换。
 * @typedef {{
 *   multiplex_enabled: string|null,
 *   multiplex_padding: string|null,
 *   multiplex_protocol: string|null,
 *   multiplex_max_connections: string|null,
 *   multiplex_min_streams: string|null,
 *   multiplex_max_streams: string|null,
 *   multiplex_brutal_enabled: string|null,
 *   multiplex_brutal_up_mbps: string|null,
 *   multiplex_brutal_down_mbps: string|null,
 *   brutal_debug: string|null
 * }} RawMultiplexOptions
 */


/**
 * shadowsocks 协议的原始字段；只组合该协议实际解码的能力。
 * @typedef {
 *   ChainableProxySectionBase &
 *   RawMultiplexOptions & RawXrayMuxOptions &
 *   RawNetworkOptions &
 *   RawPasswordOptions &
 *   {
 *     type: 'shadowsocks',
 *     method: string|null,
 *     plugin: string|null,
 *     plugin_opts: string|null,
 *     udp_over_tcp: string|null
 *   }
 * } ShadowsocksSection
 */

/**
 * vless 协议的原始字段；只组合该协议实际解码的能力。
 * @typedef {
 *   ChainableProxySectionBase &
 *   RawTLSOptions &
 *   RawRealityOptions &
 *   RawMultiplexOptions & RawXrayMuxOptions &
 *   RawTransportOptions &
 *   RawNetworkOptions &
 *   {
 *     type: 'vless',
 *     security: string|null,
 *     uuid: string|null,
 *     flow: string|null,
 *     packet_encoding: string|null
 *   }
 * } VlessSection
 */

/**
 * hysteria2 协议的原始字段；只组合该协议实际解码的能力。
 * @typedef {
 *   ChainableProxySectionBase &
 *   RawTLSOptions &
 *   RawNetworkOptions &
 *   RawPasswordOptions &
 *   {
 *     type: 'hysteria2',
 *     up_mbps: string|null,
 *     down_mbps: string|null,
 *     udp_idle_timeout: string|null,
 *     server_ports: string|string[]|null,
 *     hop_interval: string|null,
 *     obfs_type: string|null,
 *     obfs_password: string|null
 *   }
 * } Hysteria2Section
 */

/**
 * tuic 协议的原始字段；只组合该协议实际解码的能力。
 * @typedef {
 *   ChainableProxySectionBase &
 *   RawTLSOptions &
 *   RawNetworkOptions &
 *   RawPasswordOptions &
 *   {
 *     type: 'tuic',
 *     uuid: string|null,
 *     congestion_control: string|null,
 *     udp_relay_mode: string|null,
 *     udp_over_stream: string|null,
 *     zero_rtt_handshake: string|null,
 *     heartbeat: string|null
 *   }
 * } TuicSection
 */

/**
 * shadowtls 协议的原始字段；只组合该协议实际解码的能力。
 * @typedef {
 *   ChainableProxySectionBase &
 *   RawTLSOptions &
 *   RawPasswordOptions &
 *   {
 *     type: 'shadowtls',
 *     version: string|null
 *   }
 * } ShadowtlsSection
 */

/**
 * load_balance 协议的原始字段；只组合该协议实际解码的能力。
 * @typedef {GeneratedProxySectionBase & {
 *   type: 'load_balance',
 *   url: string|null,
 *   interval: string|null,
 *   tolerance: string|null,
 *   idle_timeout: string|null,
 *   interrupt_exist_connections: string|null,
 *   strategy: string|null,
 *   strategy_expected: string|null,
 *   strategy_max_rtt: string|null,
 *   strategy_tolerance: string|null,
 *   fallback_tag: string|null,
 *   probe_url: string|null,
 *   probe_connectivity: string|null,
 *   probe_interval: string|null,
 *   probe_timeout: string|null,
 *   probe_sampling: string|null,
 *   probe_http_method: string|null,
 *   member_node: string|string[]|null
 * }} BalanceSection
 */

/**
 * 自定义代理只使用命令与本地运行设置；遗留的核心、协议选项由基类索引兼容。
 * @typedef {
 *   ProxyNodeSectionBase &
 *   RawCommandOptions &
 *   {
 *     config_type: 'custom'
 *   }
 * } CustomProxySection
 */

/**
 * 尚未选择协议的表单草稿；是否允许保存或生效由原有校验链路决定。
 * @typedef {GeneratedProxySectionBase & {
 *   type: ''|null
 * }} DraftProxySection
 */

/**
 * 受支持自动生成协议的原始联合视图。
 * @typedef {
 *   ShadowsocksSection|
 *   VlessSection|
 *   Hysteria2Section|
 *   TuicSection|
 *   ShadowtlsSection|
 *   BalanceSection
 * } GeneratedProxySection
 */

/**
 * 原始代理节点的联合视图；查询函数只筛选 .type，业务校验仍由 decodeProxy() 完成。
 * @typedef {
 *   CustomProxySection|
 *   DraftProxySection|
 *   GeneratedProxySection
 * } ProxyNodeSection
 */
