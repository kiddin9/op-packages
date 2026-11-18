// 后端使用的文件位置；编辑器的原生文件接口和 ACL 与此保持一致。
// RULE_FILES 为可编辑/下载的规则文件，FILES 为模板、Hook 和分流配置。
export const RULE_FILES = {
    ip_direct: '/etc/hijpass/rules/ip-direct.txt',
    ip_proxy: '/etc/hijpass/rules/ip-proxy.txt',
    domain_direct: '/etc/hijpass/rules/domain-direct.txt',
    domain_proxy: '/etc/hijpass/rules/domain-proxy.txt',
    gfw_list: '/etc/hijpass/rules/gfw-list.txt',
    chn_route: '/etc/hijpass/rules/chn-route.txt',
    chn_route6: '/etc/hijpass/rules/chn-route6.txt',
    chn_list: '/etc/hijpass/rules/chn-list.txt',
};
export const FILES = {
    firewall_template: '/etc/hijpass/firewall.ut',
    nft_hook: '/etc/hijpass/hook/nft-hook.sh',
    dns_hook: '/etc/hijpass/hook/dns-hook.sh',
    shunt_conf: '/etc/hijpass/shunt.json',
};
export const CLIENT_DIR = '/etc/hijpass/client';
export const SERVER_DIR = '/etc/hijpass/server';
const LOG_DIR = '/tmp/hijpass/log';
const SERVER_LOG_DIR = '/tmp/hijserver/log';

/** @typedef {import('../types/config.uc').NodeIdentity} NodeIdentity */
/** @typedef {import('../types/config.uc').LogSource} LogSource */

/**
 * 校验节点标识和名称，生成统一文件名。
 * @param {NodeIdentity} section
 * @param {string} [name]
 * @returns {string} 不含扩展名的“节点名称-section ID”；名称缺失时使用 section ID。
 */
export function nodeFilename(section, name) {
    let id = section['.name'];
    if (type(id) != 'string' || !match(id, /^[A-Za-z0-9_-]+$/)) {
        die('invalid section ID');
    }
    name ||= section.name || id;
    if (type(name) != 'string' || match(name, /[\/\\\r\n]/) || index(name, sprintf('%c', 0)) >= 0) {
        die('invalid node name');
    }
    return `${name}-${id}`;
};
/**
 * 确定客户端或服务端节点的配置文件位置。
 * @param {NodeIdentity} section
 * @param {boolean} [server]
 * @returns {string} 固定目录下的节点 JSON 绝对路径。
 */
export function nodeConfig(section, server) {
    return `${server ? SERVER_DIR : CLIENT_DIR}/${nodeFilename(section)}.json`;
};

// 日志位置与开关分离：主日志始终记录，节点及分流只读取 log_enabled。
/**
 * 根据配置类型和日志开关确定日志位置。
 * @param {LogSource} section
 * @param {boolean} [server]
 * @returns {string} 日志绝对路径；未启用或不支持日志时为空字符串。
 */
export function logPath(section, server) {
    if (section['.type'] == 'hijpass') {
        return `${LOG_DIR}/hijpass.log`;
    }
    if (section.log_enabled != '1') {
        return '';
    }
    if (section['.type'] == 'shunt') {
        return `${LOG_DIR}/shunt.log`;
    }
    if (section['.type'] == 'proxy_node') {
        return `${LOG_DIR}/${nodeFilename(section)}.log`;
    }
    if (server && section['.type'] == 'server_node') {
        return `${SERVER_LOG_DIR}/${nodeFilename(section)}.log`;
    }
    return '';
};
