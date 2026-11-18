// 规则资源与任务计划的稳定输出结构；只描述数据，不携带待执行命令。

/**
 * @typedef {{
 *   path: string,
 *   kind: string
 * }} RuleSource
 */

/**
 * @typedef {{
 *   gfw_list: RuleSource,
 *   chn_domain_list: RuleSource,
 *   chn_v4_route: RuleSource,
 *   chn_v6_route: RuleSource,
 *   geoip: RuleSource,
 *   geosite: RuleSource
 * }} RuleSources
 */

/**
 * @typedef {RuleSource & {
 *   key: string,
 *   urls: string[]
 * }} RuleDownloadJob
 */

/**
 * 单次下载的总超时为 timeout 秒；连接阶段最多等待 10 秒。
 * @typedef {{
 *   timeout: integer,
 *   retries: integer,
 *   enabled: boolean,
 *   jobs: RuleDownloadJob[]
 * }} RuleDownloadPlan
 */

/**
 * @typedef {{
 *   database: string,
 *   tag: string,
 *   input: string,
 *   output: string
 * }} GeoConversionJob
 */

/**
 * @typedef {{
 *   jobs: GeoConversionJob[]
 * }} GeoConversionPlan
 */

/**
 * @typedef {{
 *   value: string,
 *   output: string
 * }} DnsGeoJob
 */

/**
 * @typedef {{
 *   jobs: DnsGeoJob[]
 * }} DnsGeoPlan
 */

/**
 * @typedef {{
 *   kind: string,
 *   extract: boolean,
 *   input: string,
 *   values: string[]
 * }} GeoRequest
 */
