import { CORE_PROTOCOLS, CORE_TYPE, CoreType, PROXY_TYPE, ProxyType, normalizeCoreType } from "../../../enum/hijpass";

type ProxyFieldValue = string | string[];

export interface ImportedProxyConfig {
    name: string;
    values: Record<string, ProxyFieldValue>;
}

interface ParsedUri {
    scheme: string;
    body: string;
    query: URLSearchParams;
    tag: string;
}

interface ParsedAuthority {
    userinfo: string;
    host: string;
    port: string;
}

const DEFAULT_PORTS: Record<string, string> = {
    [PROXY_TYPE.HYSTERIA2]: '443',
    [PROXY_TYPE.SHADOWSOCKS]: '8388',
    [PROXY_TYPE.TUIC]: '443',
    [PROXY_TYPE.SHADOWTLS]: '443',
    [PROXY_TYPE.VLESS]: '443',
};

function splitUri(input: string): ParsedUri {
    const value = input.trim();
    const schemeMatch = value.match(/^([a-z][a-z0-9+.-]*):\/\//i);
    if (!schemeMatch) {
        throw new Error(_('Invalid share link'));
    }

    const scheme = schemeMatch[1].toLowerCase();
    let rest = value.slice(schemeMatch[0].length);
    let tag = '';
    const hashIndex = rest.indexOf('#');
    if (hashIndex >= 0) {
        tag = safeDecode(rest.slice(hashIndex + 1));
        rest = rest.slice(0, hashIndex);
    }

    let queryText = '';
    const queryIndex = rest.indexOf('?');
    if (queryIndex >= 0) {
        queryText = rest.slice(queryIndex + 1);
        rest = rest.slice(0, queryIndex);
    }

    return {
        scheme,
        body: rest,
        query: new URLSearchParams(queryText),
        tag,
    };
}

function safeDecode(value: string): string {
    try {
        return decodeURIComponent(value);
    } catch (err) {
        return value;
    }
}

function encodeText(value: string): string {
    return encodeURIComponent(value);
}

function encodeFragment(value?: string): string {
    return value ? '#' + encodeText(value) : '';
}

function encodeHost(host: string): string {
    if (host.indexOf(':') >= 0 && !host.startsWith('[')) {
        return '[' + host + ']';
    }
    return host;
}

function splitAuthorityBody(body: string): string {
    const slashIndex = body.indexOf('/');
    return slashIndex >= 0 ? body.slice(0, slashIndex) : body;
}

function parseAuthority(body: string): ParsedAuthority {
    const authority = splitAuthorityBody(body);
    const atIndex = authority.lastIndexOf('@');
    const userinfo = atIndex >= 0 ? safeDecode(authority.slice(0, atIndex)) : '';
    const hostPort = atIndex >= 0 ? authority.slice(atIndex + 1) : authority;

    if (hostPort.startsWith('[')) {
        const end = hostPort.indexOf(']');
        if (end < 0) throw new Error(_('Invalid server address'));
        const host = hostPort.slice(1, end);
        const port = hostPort.slice(end + 1).replace(/^:/, '');
        return { userinfo, host, port };
    }

    const colonIndex = hostPort.lastIndexOf(':');
    if (colonIndex > 0 && hostPort.indexOf(':') === colonIndex) {
        return {
            userinfo,
            host: safeDecode(hostPort.slice(0, colonIndex)),
            port: safeDecode(hostPort.slice(colonIndex + 1)),
        };
    }

    return {
        userinfo,
        host: safeDecode(hostPort),
        port: '',
    };
}

function queryValue(query: URLSearchParams, ...names: string[]): string {
    for (const name of names) {
        const value = query.get(name);
        if (value != null && value !== '') return value;
    }
    return '';
}

function isTruthy(value: string): boolean {
    return /^(1|true|yes|on)$/i.test(value || '');
}

function makeQuery(params: Record<string, string | undefined>): string {
    const query = new URLSearchParams();
    Object.keys(params).forEach((key) => {
        const value = params[key];
        if (value != null && value !== '') {
            query.set(key, value);
        }
    });
    const text = query.toString();
    return text ? '?' + text : '';
}

function splitPathEarlyData(path: string): { path: string; maxEarlyData: string } {
    if (!path) return { path: '', maxEarlyData: '' };

    try {
        const url = new URL(path, 'http://hijpass.local');
        const maxEarlyData = url.searchParams.get('ed') || '';
        url.searchParams.delete('ed');
        const query = url.searchParams.toString();
        return {
            path: url.pathname + (query ? '?' + query : ''),
            maxEarlyData,
        };
    } catch (err) {
        return { path, maxEarlyData: '' };
    }
}

function appendPathEarlyData(path: string | undefined, maxEarlyData: string | undefined): string | undefined {
    if (!path || !maxEarlyData) return path;

    const hashIndex = path.indexOf('#');
    const pathAndQuery = hashIndex >= 0 ? path.slice(0, hashIndex) : path;
    const hash = hashIndex >= 0 ? path.slice(hashIndex) : '';
    const separator = pathAndQuery.indexOf('?') >= 0 ? '&' : '?';
    return pathAndQuery + separator + 'ed=' + encodeURIComponent(maxEarlyData) + hash;
}

function toArray(value: any): string[] {
    if (Array.isArray(value)) return value.filter(v => v != null && v !== '').map(v => String(v));
    if (value == null || value === '') return [];
    return [String(value)];
}

function firstPort(portText: string, fallback: string): string {
    const match = String(portText || '').match(/\d+/);
    return match ? match[0] : fallback;
}

function decodeBase64Url(value: string): string {
    let normalized = value.trim().replace(/-/g, '+').replace(/_/g, '/');
    normalized += '='.repeat((4 - normalized.length % 4) % 4);
    const binary = atob(normalized);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return new TextDecoder().decode(bytes);
}

function encodeBase64Url(value: string): string {
    const bytes = new TextEncoder().encode(value);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function decodeUserInfo(value: string): string {
    const plain = safeDecode(value);
    if (plain.indexOf(':') >= 0) return plain;

    try {
        const decoded = decodeBase64Url(value);
        if (decoded.indexOf(':') >= 0) return decoded;
    } catch (err) {
        // keep plain text fallback
    }

    return plain;
}

function splitFirst(value: string, separator: string): [string, string] {
    const index = value.indexOf(separator);
    if (index < 0) return [value, ''];
    return [value.slice(0, index), value.slice(index + separator.length)];
}

function baseValues(type: ProxyType, core: CoreType): Record<string, ProxyFieldValue> {
    return {
        enabled: '1',
        type,
        core,
        log_level: 'info',
    };
}

function normalizeSelectedCore(core: string): CoreType {
    const normalized = normalizeCoreType(core);
    if (normalized !== CORE_TYPE.XRAY && normalized !== CORE_TYPE.SING_BOX) {
        throw new Error(_('Invalid core selection'));
    }
    return normalized as CoreType;
}

function assertCoreSupports(type: ProxyType, core: CoreType): CoreType {
    const protocols = CORE_PROTOCOLS[core] || [];
    if (!protocols.includes(type)) {
        throw new Error(_('Selected core "%s" does not support %s').format(core, type));
    }
    return core;
}

function parseShadowsocks(uri: ParsedUri, core: CoreType): ImportedProxyConfig {
    let authority = uri.body;

    if (authority.indexOf('@') < 0) {
        const encoded = authority.replace(/\/$/, '');
        try {
            authority = decodeBase64Url(encoded);
        } catch (err) {
            throw new Error(_('Invalid Shadowsocks share link'));
        }
    }

    const parsed = parseAuthority(authority);
    const userinfo = decodeUserInfo(parsed.userinfo);
    const [method, password] = splitFirst(userinfo, ':');
    if (!method || !password || !parsed.host) {
        throw new Error(_('Invalid Shadowsocks share link'));
    }

    const pluginText = queryValue(uri.query, 'plugin');
    const [plugin, pluginOpts] = splitFirst(pluginText, ';');

    return {
        name: uri.tag || parsed.host,
        values: {
            ...baseValues(PROXY_TYPE.SHADOWSOCKS, core),
            server: parsed.host,
            server_port: firstPort(parsed.port, DEFAULT_PORTS[PROXY_TYPE.SHADOWSOCKS]),
            method,
            password,
            plugin,
            plugin_opts: pluginOpts,
            udp_over_tcp: isTruthy(queryValue(uri.query, 'udp-over-tcp', 'uot', 'udp_over_tcp')) ? '1' : '0',
            multiplex_enabled: '0',
            multiplex_protocol: 'h2mux',
            multiplex_brutal_enabled: '0',
        },
    };
}

function generateShadowsocks(section: any): string {
    const method = String(section.method || '');
    const password = String(section.password || '');
    if (!method || !password || !section.server) {
        throw new Error(_('Proxy node is incomplete'));
    }

    const userinfo = method.startsWith('2022-')
        ? encodeText(method + ':' + password)
        : encodeBase64Url(method + ':' + password);
    const plugin = section.plugin
        ? String(section.plugin) + (section.plugin_opts ? ';' + String(section.plugin_opts) : '')
        : undefined;

    return 'ss://' + userinfo + '@' + encodeHost(String(section.server)) + ':' +
        encodeText(String(section.server_port || DEFAULT_PORTS[PROXY_TYPE.SHADOWSOCKS])) +
        makeQuery({
            plugin,
            'udp-over-tcp': section.udp_over_tcp === '1' ? '1' : undefined,
        }) +
        encodeFragment(section.name);
}

function parseHysteria2(uri: ParsedUri, core: CoreType): ImportedProxyConfig {
    const parsed = parseAuthority(uri.body);
    if (!parsed.userinfo || !parsed.host) {
        throw new Error(_('Invalid Hysteria2 share link'));
    }

    const portText = parsed.port || DEFAULT_PORTS[PROXY_TYPE.HYSTERIA2];
    const serverPorts = portText.split(',').map(v => v.trim()).filter(Boolean);
    const obfs = queryValue(uri.query, 'obfs');

    return {
        name: uri.tag || parsed.host,
        values: {
            ...baseValues(PROXY_TYPE.HYSTERIA2, core),
            server: parsed.host,
            server_port: firstPort(portText, DEFAULT_PORTS[PROXY_TYPE.HYSTERIA2]),
            server_ports: serverPorts.length > 1 || portText.indexOf('-') >= 0 ? serverPorts : [],
            password: parsed.userinfo,
            obfs_type: obfs,
            obfs_password: queryValue(uri.query, 'obfs-password', 'obfs_password'),
            tls_server_name: queryValue(uri.query, 'sni', 'peer'),
            tls_insecure: isTruthy(queryValue(uri.query, 'insecure', 'allowInsecure', 'allow_insecure')) ? '1' : '0',
            network: '',
            brutal_debug: '0',
        },
    };
}

function generateHysteria2(section: any): string {
    if (!section.password || !section.server) {
        throw new Error(_('Proxy node is incomplete'));
    }

    const ports = toArray(section.server_ports);
    const portText = ports.length > 0
        ? ports.join(',')
        : String(section.server_port || DEFAULT_PORTS[PROXY_TYPE.HYSTERIA2]);

    return 'hysteria2://' + encodeText(String(section.password)) + '@' +
        encodeHost(String(section.server)) + ':' + encodeText(portText) + '/' +
        makeQuery({
            obfs: section.obfs_type,
            'obfs-password': section.obfs_password,
            sni: section.tls_server_name,
            insecure: section.tls_insecure === '1' ? '1' : undefined,
        }) +
        encodeFragment(section.name);
}

function parseVless(uri: ParsedUri, core: CoreType): ImportedProxyConfig {
    const parsed = parseAuthority(uri.body);
    if (!parsed.userinfo || !parsed.host) {
        throw new Error(_('Invalid VLESS share link'));
    }

    const transport = queryValue(uri.query, 'type');
    const security = queryValue(uri.query, 'security');
    if (transport === 'xhttp' && core !== CORE_TYPE.XRAY) {
        throw new Error(_('XHTTP transport is only supported by Xray core'));
    }

    const values: Record<string, ProxyFieldValue> = {
        ...baseValues(PROXY_TYPE.VLESS, core),
        server: parsed.host,
        server_port: firstPort(parsed.port, DEFAULT_PORTS[PROXY_TYPE.VLESS]),
        uuid: parsed.userinfo,
        flow: queryValue(uri.query, 'flow'),
        network: 'tcp',
        packet_encoding: queryValue(uri.query, 'packetEncoding', 'packet_encoding'),
        tls_server_name: queryValue(uri.query, 'sni', 'servername'),
        tls_insecure: isTruthy(queryValue(uri.query, 'allowInsecure', 'allow_insecure', 'insecure')) ? '1' : '0',
        tls_reality_enabled: security === 'reality' ? '1' : '0',
        tls_reality_public_key: queryValue(uri.query, 'pbk', 'publicKey', 'public_key'),
        tls_reality_short_id: queryValue(uri.query, 'sid', 'shortId', 'short_id'),
        multiplex_enabled: '0',
        multiplex_protocol: 'h2mux',
        multiplex_brutal_enabled: '0',
        transport_type: transport === 'tcp' ? '' : transport,
        transport_http_idle_timeout: '15s',
        transport_http_ping_timeout: '15s',
        transport_grpc_idle_timeout: '15s',
        transport_grpc_ping_timeout: '15s',
        transport_grpc_permit_without_stream: '0',
        transport_xhttp_path: '/',
        transport_xhttp_mode: 'auto',
    };

    if (transport === 'ws') {
        const wsPath = splitPathEarlyData(queryValue(uri.query, 'path'));
        values.transport_ws_host = queryValue(uri.query, 'host');
        values.transport_ws_path = wsPath.path;
        values.transport_ws_max_early_data = wsPath.maxEarlyData;
    } else if (transport === 'grpc') {
        values.transport_grpc_service_name = queryValue(uri.query, 'serviceName', 'service_name');
    } else if (transport === 'http') {
        values.transport_http_host = queryValue(uri.query, 'host');
        values.transport_http_path = queryValue(uri.query, 'path');
        values.transport_http_method = queryValue(uri.query, 'method');
    } else if (transport === 'httpupgrade') {
        values.transport_httpupgrade_host = queryValue(uri.query, 'host');
        values.transport_httpupgrade_path = queryValue(uri.query, 'path');
    } else if (transport === 'xhttp') {
        values.transport_xhttp_host = queryValue(uri.query, 'host');
        values.transport_xhttp_path = queryValue(uri.query, 'path') || '/';
        values.transport_xhttp_mode = queryValue(uri.query, 'mode') || 'auto';
    }

    return {
        name: uri.tag || parsed.host,
        values,
    };
}

function generateVless(section: any): string {
    if (!section.uuid || !section.server) {
        throw new Error(_('Proxy node is incomplete'));
    }

    const transport = String(section.transport_type || 'tcp');
    const security = section.tls_reality_enabled === '1'
        ? 'reality'
        : (section.tls_server_name || section.tls_insecure === '1' ? 'tls' : 'none');
    const params: Record<string, string | undefined> = {
        encryption: 'none',
        security,
        sni: section.tls_server_name,
        allowInsecure: section.tls_insecure === '1' ? '1' : undefined,
        flow: section.flow,
        type: transport === '' ? 'tcp' : transport,
        packetEncoding: section.packet_encoding,
        pbk: section.tls_reality_enabled === '1' ? section.tls_reality_public_key : undefined,
        sid: section.tls_reality_enabled === '1' ? section.tls_reality_short_id : undefined,
    };

    if (transport === 'ws') {
        params.host = section.transport_ws_host;
        params.path = appendPathEarlyData(section.transport_ws_path, section.transport_ws_max_early_data);
    } else if (transport === 'grpc') {
        params.serviceName = section.transport_grpc_service_name;
    } else if (transport === 'http') {
        params.host = section.transport_http_host;
        params.path = section.transport_http_path;
        params.method = section.transport_http_method;
    } else if (transport === 'httpupgrade') {
        params.host = section.transport_httpupgrade_host;
        params.path = section.transport_httpupgrade_path;
    } else if (transport === 'xhttp') {
        params.host = section.transport_xhttp_host;
        params.path = section.transport_xhttp_path;
        params.mode = section.transport_xhttp_mode;
    }

    return 'vless://' + encodeText(String(section.uuid)) + '@' +
        encodeHost(String(section.server)) + ':' + encodeText(String(section.server_port || DEFAULT_PORTS[PROXY_TYPE.VLESS])) +
        makeQuery(params) + encodeFragment(section.name);
}

function parseTuic(uri: ParsedUri, core: CoreType): ImportedProxyConfig {
    const parsed = parseAuthority(uri.body);
    const [uuid, password] = splitFirst(parsed.userinfo, ':');
    if (!uuid || !password || !parsed.host) {
        throw new Error(_('Invalid TUIC share link'));
    }

    return {
        name: uri.tag || parsed.host,
        values: {
            ...baseValues(PROXY_TYPE.TUIC, core),
            server: parsed.host,
            server_port: firstPort(parsed.port, DEFAULT_PORTS[PROXY_TYPE.TUIC]),
            uuid,
            password,
            congestion_control: queryValue(uri.query, 'congestion_control') || 'cubic',
            udp_relay_mode: queryValue(uri.query, 'udp_relay_mode'),
            udp_over_stream: isTruthy(queryValue(uri.query, 'udp_over_stream')) ? '1' : '0',
            zero_rtt_handshake: isTruthy(queryValue(uri.query, 'zero_rtt_handshake', 'zero_rtt')) ? '1' : '0',
            heartbeat: queryValue(uri.query, 'heartbeat') || '10s',
            network: '',
            tls_server_name: queryValue(uri.query, 'sni', 'servername'),
            tls_insecure: isTruthy(queryValue(uri.query, 'allow_insecure', 'allowInsecure', 'insecure')) ? '1' : '0',
        },
    };
}

function generateTuic(section: any): string {
    if (!section.uuid || !section.password || !section.server) {
        throw new Error(_('Proxy node is incomplete'));
    }

    return 'tuic://' + encodeText(String(section.uuid)) + ':' + encodeText(String(section.password)) + '@' +
        encodeHost(String(section.server)) + ':' + encodeText(String(section.server_port || DEFAULT_PORTS[PROXY_TYPE.TUIC])) +
        makeQuery({
            congestion_control: section.congestion_control,
            udp_relay_mode: section.udp_relay_mode,
            udp_over_stream: section.udp_over_stream === '1' ? '1' : undefined,
            zero_rtt_handshake: section.zero_rtt_handshake === '1' ? '1' : undefined,
            heartbeat: section.heartbeat,
            sni: section.tls_server_name,
            allow_insecure: section.tls_insecure === '1' ? '1' : undefined,
        }) +
        encodeFragment(section.name);
}

function parseShadowTls(uri: ParsedUri, core: CoreType): ImportedProxyConfig {
    const parsed = parseAuthority(uri.body);
    const password = parsed.userinfo || queryValue(uri.query, 'password');
    if (!parsed.host) {
        throw new Error(_('Invalid ShadowTLS share link'));
    }

    return {
        name: uri.tag || parsed.host,
        values: {
            ...baseValues(PROXY_TYPE.SHADOWTLS, core),
            server: parsed.host,
            server_port: firstPort(parsed.port, DEFAULT_PORTS[PROXY_TYPE.SHADOWTLS]),
            version: queryValue(uri.query, 'version') || '1',
            password,
            tls_server_name: queryValue(uri.query, 'sni', 'servername'),
            tls_insecure: isTruthy(queryValue(uri.query, 'allow_insecure', 'allowInsecure', 'insecure')) ? '1' : '0',
        },
    };
}

function generateShadowTls(section: any): string {
    if (!section.server) {
        throw new Error(_('Proxy node is incomplete'));
    }

    return 'shadowtls://' + (section.password ? encodeText(String(section.password)) + '@' : '') +
        encodeHost(String(section.server)) + ':' + encodeText(String(section.server_port || DEFAULT_PORTS[PROXY_TYPE.SHADOWTLS])) +
        makeQuery({
            version: section.version,
            sni: section.tls_server_name,
            allow_insecure: section.tls_insecure === '1' ? '1' : undefined,
        }) +
        encodeFragment(section.name);
}

const ProxyShareLinkUtils = {
    canExport: function (section: any): boolean {
        const core = normalizeCoreType(section?.core) as CoreType;
        return CORE_PROTOCOLS[core]?.includes(section?.type) ?? false;
    },

    parse: function (input: string, selectedCore: string): ImportedProxyConfig {
        const uri = splitUri(input);
        const core = normalizeSelectedCore(selectedCore);
        switch (uri.scheme) {
            case 'ss':
                return parseShadowsocks(uri, assertCoreSupports(PROXY_TYPE.SHADOWSOCKS, core));
            case 'hysteria2':
            case 'hy2':
                return parseHysteria2(uri, assertCoreSupports(PROXY_TYPE.HYSTERIA2, core));
            case 'vless':
                return parseVless(uri, assertCoreSupports(PROXY_TYPE.VLESS, core));
            case 'tuic':
                return parseTuic(uri, assertCoreSupports(PROXY_TYPE.TUIC, core));
            case 'shadowtls':
            case 'shadow-tls':
                return parseShadowTls(uri, assertCoreSupports(PROXY_TYPE.SHADOWTLS, core));
            default:
                throw new Error(_('Unsupported share link protocol: %s').format(uri.scheme));
        }
    },

    generate: function (section: any): string {
        switch (section?.type) {
            case PROXY_TYPE.SHADOWSOCKS:
                return generateShadowsocks(section);
            case PROXY_TYPE.HYSTERIA2:
                return generateHysteria2(section);
            case PROXY_TYPE.VLESS:
                return generateVless(section);
            case PROXY_TYPE.TUIC:
                return generateTuic(section);
            case PROXY_TYPE.SHADOWTLS:
                return generateShadowTls(section);
            default:
                throw new Error(_('Unsupported proxy type'));
        }
    },
};

export { ProxyShareLinkUtils };
