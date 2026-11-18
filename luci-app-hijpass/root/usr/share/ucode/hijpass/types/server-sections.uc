/**
 * @typedef {{
 *   multiplex_enabled?: string|null,
 *   multiplex_padding?: string|null,
 *   multiplex_brutal_enabled?: string|null,
 *   multiplex_brutal_up_mbps?: string|null,
 *   multiplex_brutal_down_mbps?: string|null
 * }} RawServerMultiplex
 */

/** @typedef {import('./sections.uc').EnabledSection} EnabledSection */

/**
 * 标准服务端节点的公共 UCI 字段。
 * @typedef {EnabledSection & {
 *   '.type': 'server_node',
 *   name: string|null,
 *   core: string|null,
 *   listen: string|null,
 *   listen_port: string|null,
 *   allow_firewall: string|null,
 *   log_enabled: string|null,
 *   log_level: string|null,
 *   legacy_custom: string|null
 * }} ServerBaseSection
 */

/**
 * 服务端证书/私钥路径，内容由核心读取。
 * @typedef {{
 *   server_name: string|null,
 *   certificate_path: string|null,
 *   key_path: string|null
 * }} ServerTLSOptions
 */

/**
 * @typedef {ServerBaseSection & RawServerMultiplex & {
 *   type: 'shadowsocks',
 *   method: string|null,
 *   password: string|null
 * }} ShadowsocksServerSection
 */

/**
 * @typedef {ServerBaseSection & ServerTLSOptions & {
 *   type: 'hysteria2',
 *   password: string|null,
 *   obfs_password: string|null,
 *   up_mbps: string|null,
 *   down_mbps: string|null
 * }} Hysteria2ServerSection
 */

/**
 * @typedef {ServerBaseSection & RawServerMultiplex & ServerTLSOptions & {
 *   type: 'vless',
 *   uuid: string|null,
 *   flow: string|null,
 *   transport: string|null,
 *   security: string|null,
 *   http_host: string|string[]|null,
 *   http_path: string|null,
 *   http_method: string|null,
 *   http_idle_timeout: string|null,
 *   httpupgrade_host: string|null,
 *   httpupgrade_path: string|null,
 *   ws_path: string|null,
 *   grpc_service_name: string|null,
 *   xhttp_host: string|null,
 *   xhttp_path: string|null,
 *   xhttp_mode: string|null,
 *   xhttp_method: string|null,
 *   reality_server: string|null,
 *   reality_port: string|null,
 *   reality_private_key: string|null,
 *   reality_short_id: string|null
 * }} VlessServerSection
 */

/** @typedef {ShadowsocksServerSection|Hysteria2ServerSection|VlessServerSection} ServerNodeSection */
