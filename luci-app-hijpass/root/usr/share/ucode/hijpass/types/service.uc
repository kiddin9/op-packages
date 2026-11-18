// 共享类型声明；仅用于编辑器，不创建或导出运行时对象。

/**
 * @typedef {object} ServicePlan
 * @property {ServiceInstance[]} instances procd 的进程描述数组。
 */

/**
 * @typedef {object} ChinadnsOptions
 * @property {integer} listenPort 监听端口。
 * @property {string} direct 国内上游地址。
 * @property {string} proxy 代理上游地址。
 * @property {boolean} useChn 国内列表开关。
 * @property {boolean} useGfw 代理列表开关。
 * @property {string|null} chnList 国内列表路径，启用列表时提供。
 * @property {string|null} gfwList 代理列表路径，启用列表时提供。
 */

/**
 * Shell procd 桥接层的业务输入；DNS 实例可以省略 log/shunt。
 * @typedef {{
 *   id: string,
 *   name: string,
 *   command: string[],
 *   check?: string[],
 *   env: string[],
 *   user: string,
 *   log: string|null,
 *   shunt: boolean|null
 * }} ServiceInstance
 */

/**
 * 完整生成、等待原子替换的配置文件。
 * @typedef {{
 *   path: string,
 *   data: string
 * }} ConfigFile
 */

/**
 * DNS 准备阶段只读取 dnsmasq 的原始 port；未配置时采用 53。
 * @typedef {{
 *   port: string|null
 * }} DnsmasqOptions
 */

/**
 * 服务执行层的开关和日志路径。
 * @typedef {{
 *   enabled: boolean,
 *   geo_convert: boolean,
 *   log_paths: string[]
 * }} ServiceSettings
 */

/**
 * 服务端启动计划及按传输协议分组的放行端口。
 * @typedef {ServicePlan & {
 *   ports: { tcp: integer[], udp: integer[] }
 * }} ServerPlan
 */
