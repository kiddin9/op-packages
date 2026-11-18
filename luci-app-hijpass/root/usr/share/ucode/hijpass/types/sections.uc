// 原始 UCI section 的结构声明；option/list 保留原值，转换与业务校验由 config 模块完成。

/**
 * 所有 section 的公共元数据；索引兼容未知或历史字段，不代替子类型的明确字段。
 * @typedef {{
 *   '.name': string,
 *   '.type': string,
 *   '.index': integer|null,
 *   '.anonymous': boolean|null,
 *   [option: string]: string|string[]|integer|boolean|null
 * }} UciSection
 */

/**
 * 具有启停开关的原始配置；缺失值的启停语义由各业务模块决定。
 * @typedef {UciSection & {
 *   enabled: string|null
 * }} EnabledSection
 */

/**
 * 客户端和服务端节点共用的原始名称、端口与进程选项。
 * @typedef {EnabledSection & {
 *   name: string|null,
 *   listen_port: string|null,
 *   procd_env: string|string[]|null,
 *   log_enabled: string|null
 * }} NamedNodeSection
 */

/**
 * 使用自定义命令和原生 JSON 文件的节点选项；仅供自定义代理使用。
 * @typedef {{
 *   command: string|null,
 *   custom_conf_hash: string|null
 * }} RawCommandOptions
 */

/**
 * 客户端全局配置。
 * @typedef {EnabledSection & {
 *   '.type': 'hijpass',
 *   startup_delay: string|null,
 *   delay_time: string|null,
 *   log_level: string|null,
 *   schema_version: string|null,
 *   legacy_firewall_template: string|null
 * }} HijpassSection
 */

/**
 * 服务端全局配置。
 * @typedef {EnabledSection & {
 *   '.type': 'hijserver'
 * }} HijserverSection
 */

/**
 * 分流模板原始设置；type 是核心名称，.type 是固定的 section 类型。
 * @typedef {EnabledSection & {
 *   '.type': 'shunt',
 *   type: string|null,
 *   config_type: string|null,
 *   shunt_listen_port: string|null,
 *   dns_listen_port: string|null,
 *   log_enabled: string|null,
 *   log_level: string|null,
 *   ruleset_convert: string|null,
 *   use_cache: string|null,
 *   shunt_hash: string|null,
 *   default_proxy_node: string|null,
 *   ruleset_out_node: string|null,
 *   default_dns_node: string|null,
 *   ruleset_dns_node: string|null,
 *   default_strategy: string|null,
 *   procd_env: string|string[]|null,
 *   nest_proxy: string|null
 * }} ShuntSection
 */

/**
 * DNS 服务和上游选择；启用国内/GFW 列表的开关仍为原始字符串。
 * @typedef {UciSection & {
 *   '.type': 'dns',
 *   dns_service: string|null,
 *   direct_dns: string|null,
 *   direct_dns_custom: string|null,
 *   proxy_dns: string|null,
 *   proxy_dns_custom: string|null,
 *   cdg_port: string|null,
 *   use_chn: string|null,
 *   use_gfw: string|null,
 *   domain_proxy_hash: string|null,
 *   domain_direct_hash: string|null,
 *   dns_hook_hash: string|null
 * }} DnsSection
 */

/**
 * 防火墙入口、DNS 转发及访问控制。
 * @typedef {UciSection & {
 *   '.type': 'firewall',
 *   tproxy_proto: string|string[]|null,
 *   proxy_port: string|null,
 *   shunt_port: string|null,
 *   dns_forward: string|null,
 *   proxy_local: string|null,
 *   use_chnroute: string|null,
 *   acl_default_allow: string|null,
 *   proxy_mac_list: string|string[]|null,
 *   proxy_mac_exclude_list: string|string[]|null,
 *   proxy_iface_list: string|string[]|null,
 *   proxy_iface_exclude_list: string|string[]|null,
 *   ip_direct_hash: string|null,
 *   ip_proxy_hash: string|null,
 *   nft_hash: string|null,
 *   nft_hook_hash: string|null
 * }} FirewallSection
 */

/**
 * 规则下载资源、更新计划和网络重试设置。
 * @typedef {UciSection & {
 *   '.type': 'rule',
 *   chn_domain_list: string|string[]|null,
 *   chn_v4_route: string|string[]|null,
 *   chn_v6_route: string|string[]|null,
 *   gfw_list: string|null,
 *   geosite: string|null,
 *   geoip: string|null,
 *   update_schedule: string|null,
 *   download_timeout: string|null,
 *   retry_count: string|null
 * }} RuleSection
 */

/**
 * 规则匹配字段视图；供解析器和完整规则 section 共用。
 * @typedef {{
 *   network: string|string[]|null,
 *   protocol: string|string[]|null,
 *   port: string|string[]|null,
 *   port_range: string|string[]|null,
 *   domain_list: string|null,
 *   ip_list: string|null
 * }} RuleMatchOptions
 */

/**
 * 分流规则的出口、DNS 及匹配条件。
 * @typedef {EnabledSection & RuleMatchOptions & {
 *   '.type': 'shunt_route_rule',
 *   name: string|null,
 *   proxy_node: string|null,
 *   ip_version_split: string|null,
 *   proxy_node_v4: string|null,
 *   proxy_node_v6: string|null,
 *   dns_node: string|null,
 *   dns_proxy_node: string|null,
 *   dns_strategy: string|null
 * }} ShuntRouteRuleSection
 */

/**
 * 分流核心使用的 DNS 节点；port 在转换前为字符串。
 * @typedef {EnabledSection & {
 *   '.type': 'shunt_dns_node',
 *   type: string|null,
 *   tag: string|null,
 *   server: string|null,
 *   port: string|null
 * }} ShuntDnsNodeSection
 */

/**
 * 外部 dhcp 配置中需要读取的 dnsmasq 原始选项。
 * @typedef {UciSection & {
 *   '.type': 'dnsmasq',
 *   port: string|null,
 *   resolvfile: string|null
 * }} DnsmasqSection
 */

/**
 * 安装迁移读取的旧模板字段；不参与当前配置生成。
 * @typedef {HijpassSection & {
 *   nft: string|null,
 *   firewall_template: string|null
 * }} LegacyHijpassSection
 */
