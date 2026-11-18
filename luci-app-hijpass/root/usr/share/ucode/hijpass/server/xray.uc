/** @typedef {import('../types/server.uc').ServerOptions} ServerOptions */
/** @typedef {import('../types/core.uc').CoreConfig} CoreConfig */

/**
 * 将已校验的服务端选项组装成 Xray 配置；不读写文件。
 * @param {ServerOptions} node
 * @returns {CoreConfig}
 */
export function build(node) {
    let inbound = { protocol: node.type, tag: 'server', listen: node.listen, port: node.listen_port };
    if (node.type == 'shadowsocks') {
        inbound.settings = { method: node.method, password: node.password, network: 'tcp,udp' };
    }
    else {
        let stream = { network: node.transport, security: node.security };
        inbound.streamSettings = stream;
        if (node.type == 'hysteria2') {
            inbound.protocol = 'hysteria';
            // 26.3 使用 clients；新版本仍兼容，避免旧核心忽略 users 后认证失败。
            inbound.settings = { version: 2, clients: [{ auth: node.password }] };
            stream.network = 'hysteria';
            stream.hysteriaSettings = { version: 2 };
        }
        else {
            inbound.settings = { clients: [{ id: node.uuid, flow: node.flow }], decryption: 'none' };
            if (node.transport == 'httpupgrade')
                stream.httpupgradeSettings = { host: node.httpupgrade_host, path: node.httpupgrade_path };
            if (node.transport == 'ws') stream.wsSettings = { path: node.ws_path };
            if (node.transport == 'grpc') stream.grpcSettings = { serviceName: node.grpc_service_name };
            if (node.transport == 'xhttp') {
                stream.xhttpSettings = { host: node.xhttp_host, path: node.xhttp_path, mode: node.xhttp_mode };
                if (node.xhttp_method) stream.xhttpSettings.uplinkHTTPMethod = node.xhttp_method;
            }
        }
        if (node.security == 'tls') {
            stream.tlsSettings = { serverName: node.server_name,
                certificates: [{ certificateFile: node.certificate_path, keyFile: node.key_path }] };
            if (node.type == 'hysteria2') stream.tlsSettings.alpn = ['h3'];
        }
        else if (node.security == 'reality') {
            let host = index(node.reality_server, ':') >= 0 ? `[${node.reality_server}]` : node.reality_server;
            stream.realitySettings = { target: `${host}:${node.reality_port}`,
                serverNames: [node.server_name], privateKey: node.reality_private_key,
                shortIds: [node.reality_short_id] };
        }
    }
    return { log: { loglevel: node.log_level == 'warn' ? 'warning' : node.log_level },
        inbounds: [inbound], outbounds: [{ protocol: 'freedom', tag: 'direct' }] };
};
