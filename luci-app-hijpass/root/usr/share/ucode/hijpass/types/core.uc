/** @typedef {import('./json.uc').JsonObject} JsonObject */
/** @typedef {import('./proxy-sections.uc').ProxyNodeSection} ProxyNodeSection */
/** @typedef {import('./routing.uc').RoutingInput} RoutingInput */
// 核心原生 JSON 的稳定边界；协议专用扩展保留 JSON 字典。

/**
 * @typedef {{
 *   host: string,
 *   path: string,
 *   mode: string,
 *   uplinkHTTPMethod: string
 * }} XhttpSettings
 */

/**
 * @typedef {{
 *   host: string,
 *   path: string
 * }} HttpupgradeSettings
 */

/**
 * @typedef {{
 *   host: string,
 *   path: string
 * }} WebsocketSettings
 */

/**
 * @typedef {{
 *   serviceName: string,
 *   idle_timeout: integer|null,
 *   health_check_timeout: integer|null,
 *   permit_without_stream: boolean|null
 * }} GrpcSettings
 */

/**
 * Xray streamSettings；apply() 原地填充传输字段，未选择的子对象可以缺省。
 * @typedef {{
 *   network: string|null,
 *   security: string|null,
 *   xhttpSettings: XhttpSettings|null,
 *   httpupgradeSettings: HttpupgradeSettings|null,
 *   wsSettings: WebsocketSettings|null,
 *   grpcSettings: GrpcSettings|null,
 *   tlsSettings: JsonObject|null,
 *   realitySettings: JsonObject|null,
 *   sockopt: JsonObject|null
 * }} StreamSettings
 */

/**
 * @typedef {JsonObject & {
 *   address: string|null
 * }} OutboundSettings
 */

/**
 * @typedef {JsonObject & {
 *   server: string|null,
 *   settings: OutboundSettings|null
 * }} OutboundConfig
 */

/**
 * 两种核心共用的日志、入站、出站和可选 DNS 结构。
 * @typedef {{
 *   log: JsonObject,
 *   inbounds: JsonObject[],
 *   outbounds: OutboundConfig[],
 *   dns: JsonObject|null
 * }} CoreConfigBase
 */

/**
 * sing-box 核心配置；路由规则位于 route。
 * @typedef {CoreConfigBase & {
 *   route: JsonObject|null
 * }} SingboxConfig
 */

/**
 * Xray 核心配置；路由与均衡探测位于 routing、burstObservatory。
 * @typedef {CoreConfigBase & {
 *   routing: JsonObject|null,
 *   burstObservatory: JsonObject|null
 * }} XrayConfig
 */

/**
 * 核心配置总入口；具体生成器返回对应核心的子类型。
 * @typedef {
 *   SingboxConfig|
 *   XrayConfig
 * } CoreConfig
 */

/**
 * 上层选定的生成输入；起点和依赖候选独立，底层不解释 enabled 或生成场景。
 * @typedef {{
 *   rootProxies: ProxyNodeSection[],
 *   availableProxies: ProxyNodeSection[],
 *   routing: RoutingInput|null
 * }} GenerationInput
 */

/**
 * 核心生成结果；nodes 以 section ID 索引，自定义节点没有生成结果。
 * @typedef {{
 *   nodes: Object<string, CoreConfig>,
 *   shunt: CoreConfig|null
 * }} GeneratedConfigs
 */

/**
 * @typedef {{
 *   ok: boolean
 * }} ValidationResult
 */
