/**
 * @typedef {{
 *   multiplex_enabled?: boolean,
 *   multiplex_padding?: boolean,
 *   multiplex_brutal_enabled?: boolean,
 *   multiplex_brutal_up_mbps?: integer,
 *   multiplex_brutal_down_mbps?: integer
 * }} ServerMultiplex
 */

/**
 * 转换后的公共服务端选项；数字已校验，缺失值已填充。
 * @typedef {{
 *   name: string,
 *   type: string,
 *   core: string,
 *   listen: string,
 *   listen_port: integer,
 *   log_level: string,
 *   security: string,
 *   transport: string
 * }} ServerOptionsBase
 */

/**
 * @typedef {{
 *   server_name: string,
 *   certificate_path?: string,
 *   key_path?: string,
 *   reality_server?: string,
 *   reality_port?: integer,
 *   reality_private_key?: string,
 *   reality_short_id?: string
 * }} ServerTLS
 */

/**
 * @typedef {ServerOptionsBase & ServerMultiplex & {
 *   password: string,
 *   method: string
 * }} ShadowsocksServerOptions
 */

/**
 * @typedef {ServerOptionsBase & ServerTLS & {
 *   password: string,
 *   obfs_password?: string,
 *   up_mbps?: integer,
 *   down_mbps?: integer
 * }} Hysteria2ServerOptions
 */

/**
 * @typedef {ServerOptionsBase & ServerMultiplex & ServerTLS & {
 *   uuid: string,
 *   flow: string,
 *   http_host?: string[],
 *   http_path?: string,
 *   http_method?: string,
 *   http_idle_timeout?: string,
 *   httpupgrade_host?: string,
 *   httpupgrade_path?: string,
 *   ws_path?: string,
 *   grpc_service_name?: string,
 *   xhttp_host?: string,
 *   xhttp_path?: string,
 *   xhttp_mode?: string,
 *   xhttp_method?: string
 * }} VlessServerOptions
 */

/** @typedef {ShadowsocksServerOptions|Hysteria2ServerOptions|VlessServerOptions} ServerOptions */
