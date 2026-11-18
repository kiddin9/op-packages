// 共享类型声明；仅用于编辑器，不创建或导出运行时对象。

/**
 * @typedef {object} CommandOutput
 * @property {string} stdout 外部命令的原始标准输出；由具体调用方解析。
 * @property {integer} code 命令的退出状态，0 表示成功。
 */

/**
 * @typedef {CommandOutput & {
 *   stderr: string
 * }} CommandResult
 */

/**
 * iptoarr() 的网络字节序地址、地址族（4/6）和已验证的前缀长度。
 * @typedef {{
 *   bytes: integer[],
 *   family: integer,
 *   prefix: integer
 * }} CIDRRange
 */

/**
 * @typedef {{
 *   wan: string[],
 *   local4: string[],
 *   local6: string[],
 *   dns4: string[],
 *   dns6: string[]
 * }} NetworkState
 */

/**
 * 已验证的 HTTP(S) 探测参数；timeout 为秒，socks 是本地端口或空字符串。
 * @typedef {{
 *   url: string,
 *   timeout: integer,
 *   socks: string
 * }} ProbeRequest
 */

/**
 * curl 输出不完整时只包含 URL、成功状态和退出码；耗时均为毫秒。
 * @typedef {{
 *   url: string,
 *   success: boolean,
 *   exit_code: integer,
 *   http_code: integer|null,
 *   remote_ip: string|null,
 *   remote_port: integer|null,
 *   dns_lookup_time_ms: integer|null,
 *   tcp_connect_time_ms: integer|null,
 *   tls_handshake_time_ms: integer|null,
 *   server_processing_time_ms: integer|null,
 *   total_time_ms: integer|null,
 *   first_byte_time_ms: integer|null
 * }} CurlReport
 */


/**
 * @typedef {{
 *   ms: integer,
 *   total_ms: integer
 * }} PingTiming
 */

/** @typedef {PingTiming|{error: string}} PingReport */
