// 传输选项按类型区分；Raw 前缀保留原始 UCI 字符串，其余类型为解码后的值。

/**
 * 未选择传输的原始设置；沿用核心默认传输。
 * @typedef {{
 *   transport_type: ''|null
 * }} RawNoTransportOptions
 */

/**
 * 解码后未选择额外传输。
 * @typedef {{
 *   transport_type: ''
 * }} NoTransportOptions
 */

/**
 * http 原始传输选项。
 * @typedef {{
 *   transport_type: 'http',
 *   transport_http_host: string|null,
 *   transport_http_path: string|null,
 *   transport_http_method: string|null,
 *   transport_http_idle_timeout: string|null,
 *   transport_http_ping_timeout: string|null
 * }} RawHttpTransportOptions
 */

/**
 * http 解码后的传输选项；仅声明该传输实际读取的字段。
 * @typedef {{
 *   transport_type: 'http',
 *   transport_http_host: string,
 *   transport_http_path: string,
 *   transport_http_method: string,
 *   transport_http_idle_timeout: string,
 *   transport_http_ping_timeout: string
 * }} HttpTransportOptions
 */

/**
 * ws 原始传输选项。
 * @typedef {{
 *   transport_type: 'ws',
 *   transport_ws_host: string|null,
 *   transport_ws_path: string|null,
 *   transport_ws_max_early_data: string|null,
 *   transport_ws_early_data_header_name: string|null
 * }} RawWebSocketTransportOptions
 */

/**
 * ws 解码后的传输选项；仅声明该传输实际读取的字段。
 * @typedef {{
 *   transport_type: 'ws',
 *   transport_ws_host: string,
 *   transport_ws_path: string,
 *   transport_ws_max_early_data: integer|null,
 *   transport_ws_early_data_header_name: string
 * }} WebSocketTransportOptions
 */

/**
 * grpc 原始传输选项。
 * @typedef {{
 *   transport_type: 'grpc',
 *   transport_grpc_service_name: string|null,
 *   transport_grpc_idle_timeout: string|null,
 *   transport_grpc_ping_timeout: string|null,
 *   transport_grpc_permit_without_stream: string|null
 * }} RawGrpcTransportOptions
 */

/**
 * grpc 解码后的传输选项；仅声明该传输实际读取的字段。
 * @typedef {{
 *   transport_type: 'grpc',
 *   transport_grpc_service_name: string,
 *   transport_grpc_idle_timeout: string,
 *   transport_grpc_ping_timeout: string,
 *   transport_grpc_permit_without_stream: boolean
 * }} GrpcTransportOptions
 */

/**
 * httpupgrade 原始传输选项。
 * @typedef {{
 *   transport_type: 'httpupgrade',
 *   transport_httpupgrade_host: string|null,
 *   transport_httpupgrade_path: string|null
 * }} RawHttpUpgradeTransportOptions
 */

/**
 * httpupgrade 解码后的传输选项；仅声明该传输实际读取的字段。
 * @typedef {{
 *   transport_type: 'httpupgrade',
 *   transport_httpupgrade_host: string,
 *   transport_httpupgrade_path: string
 * }} HttpUpgradeTransportOptions
 */

/**
 * xhttp 原始传输选项。
 * @typedef {{
 *   transport_type: 'xhttp',
 *   transport_xhttp_host: string|null,
 *   transport_xhttp_path: string|null,
 *   transport_xhttp_mode: string|null,
 *   transport_xhttp_method: string|null
 * }} RawXhttpTransportOptions
 */

/**
 * xhttp 解码后的传输选项；仅声明该传输实际读取的字段。
 * @typedef {{
 *   transport_type: 'xhttp',
 *   transport_xhttp_host: string,
 *   transport_xhttp_path: string,
 *   transport_xhttp_mode: string,
 *   transport_xhttp_method: string
 * }} XhttpTransportOptions
 */

/**
 * 所有受支持原始传输设置的联合视图。
 * @typedef {
 *   RawNoTransportOptions|
 *   RawHttpTransportOptions|
 *   RawWebSocketTransportOptions|
 *   RawGrpcTransportOptions|
 *   RawHttpUpgradeTransportOptions|
 *   RawXhttpTransportOptions
 * } RawTransportOptions
 */

/**
 * 解码后传输设置的联合类型；不把互斥传输字段合并为一个大对象。
 * @typedef {
 *   NoTransportOptions|
 *   HttpTransportOptions|
 *   WebSocketTransportOptions|
 *   GrpcTransportOptions|
 *   HttpUpgradeTransportOptions|
 *   XhttpTransportOptions
 * } TransportOptions
 */
