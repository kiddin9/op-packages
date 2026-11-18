// 共享类型声明；仅用于编辑器，不创建或导出运行时对象。

/**
 * @typedef {object} Capture
 * @property {string} mode client 或 router，决定报告布局。
 * @property {string} client 客户端 IP，client 模式使用。
 * @property {string} protocol all/tcp/udp，client 模式的网络过滤。
 * @property {string} port 目标端口或 all。
 * @property {integer} seconds 捕获时长，秒。
 * @property {string|null} url router 模式的请求 URL。
 * @property {string} method HEAD/GET，router 模式使用。
 * @property {string|null} host router 模式的目标域名或 IP。
 * @property {integer|null} targetPort router 模式的目标端口。
 * @property {string[]} addresses 解析后的目标 IP，空数组表示没有解析结果。
 * @property {boolean} verbose 是否输出原始日志。
 * @property {boolean} tcpdump 是否包含抓包报告。
 * @property {string} iface tcpdump 接口。
 * @property {string} filter tcpdump BPF 过滤表达式。
 * @property {boolean} keep 是否保留任务文件。
 * @property {string} chain 任务专属 nft 链名。
 * @property {string} comment 任务专属 nft 注释，用于区分规则。
 */

/**
 * @typedef {Capture & {
 *   directory: string
 * }} PreparedCapture
 */

/**
 * 诊断开始时的日志位置；offset 为字节数，inode 用于识别日志轮转。
 * @typedef {{
 *   path: string,
 *   offset: integer,
 *   inode: integer
 * }} LogPosition
 */

/**
 * @typedef {{
 *   capture: PreparedCapture,
 *   positions: LogPosition[]|null
 * }} CaptureMetadata
 */

/**
 * @typedef {{
 *   chain: string,
 *   comment: string
 * }} TraceIdentity
 */

/**
 * @typedef {{
 *   chain: string,
 *   handle: string
 * }} CleanupRule
 */

/**
 * @typedef {TraceIdentity & {
 *   rules: CleanupRule[]
 * }} CleanupPlan
 */

/**
 * @typedef {{
 *   syn: integer,
 *   syn_ack: integer,
 *   fin: integer,
 *   rst: integer,
 *   udp: integer,
 *   payload_packets: integer,
 *   payload_bytes: integer
 * }} PacketCounts
 */

/**
 * @typedef {{
 *   counts: PacketCounts,
 *   interfaces: Object<string, integer>,
 *   flows: Object<string, integer>
 * }} PacketSummary
 */
