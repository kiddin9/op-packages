import { CORE_TYPE } from "../enum/hijpass";

export class DnsNode {
    tag: string;
    type: string;
    server: string;
    port: string;
}

export class DnsSection {
    defaultDnsNode: string;
    defaultStrategy: string;
    rulesetDnsNode: string;
    useCache: string;
    nodes: DnsNode[];

    constructor() {
        this.nodes = [];
    }
}

export class ShuntRouteRule {
    enabled: string;
    name: string;
    proxyNode: string;
    ipVersionSplit: string;
    proxyNodeV4: string;
    proxyNodeV6: string;

    protocol: string[];
    network: string[];
    port: string[];
    portRange: string[];
    domainList: string;
    ipList: string;

    dnsNode: string;
    dnsProxyNode: string;
    dnsStrategy: string;

    constructor() {
        this.port = [];
        this.portRange = [];
        this.network = [];
        this.protocol = [];
        this.ipVersionSplit = '0';
    }
}

export class RouteSection {
    defaultProxyNode: string;
    rulesetOutNode: string;
    rulesetConvert: string;
    rules: ShuntRouteRule[];

    constructor() {
        this.rules = [];
    }
}

export class ShuntSection {
    type: string;
    configType: string;
    shuntListenPort: string;
    dnsListenPort: string;
    logLevel: string;
    logPath: string;
    route: RouteSection;
    dns: DnsSection;
}

export class RuleDTO {
    domain: string[];
    domainRegex: string[];
    domainKeyword: string[];
    domainSuffix: string[];
    ipCidr: string[];

    network: string[];
    protocol: string[];
    port: number[];
    portRange: string[];
    ipVersion?: 4 | 6;

    ruleSet: RuleSetDTO[]; // 规则集合
    geoIp: string[];
    geoSite: string[];

    constructor() {
        this.domain = [];
        this.domainRegex = [];
        this.domainKeyword = [];
        this.domainSuffix = [];
        this.ruleSet = [];
        this.ipCidr = [];
        this.geoIp = [];
        this.geoSite = [];
        this.network = [];
        this.protocol = [];
        this.port = [];
        this.portRange = [];
    }

    containDomain(): boolean {
        return this.domain.length > 0
            || this.domainRegex.length > 0
            || this.domainSuffix.length > 0
            || this.domainKeyword.length > 0
    }

    containGeo(): boolean {
        return this.geoSite.length > 0 || this.geoIp.length > 0
    }

    containRuleSet(): boolean {
        return this.ruleSet.length > 0
    }

    containIp(): boolean {
        return this.ipCidr.length > 0
            || this.geoIp.length > 0
    }

    isEmpty(collectionType: "geo" | "set"): boolean {
        return !(this.containDomain()
            || this.containIp()
            || (collectionType === "geo" && this.containGeo())
            || (collectionType === "set" && this.containRuleSet())
            || this.network.length > 0
            || this.port.length > 0
            || this.portRange.length > 0
            || this.protocol.length > 0)
    }
}

export interface ShuntRouteRuleVariant {
    rule: ShuntRouteRule;
    proxyNode: string;
    ipVersion?: 4 | 6;
}

export interface RuleSetDTO {
    tag: string;
    type: string;
    format: string;
    pathOrUrl: string;
}

export interface CoreAdapter {
    genShuntConf: () => {}
    genProxyConf: (proxyNode: ProxyNode) => {}
}

export interface LuciConvertUtils {
    convert: (ProxyNode: ProxyNode) => {}
}

/**
 * 代理节点基础配置
 */
export interface ProxyNode {
    name: string;
    cfgid?: string;
    type: string;
    core?: string;
    enabled: string;
    listen_port: string;
    socks_port: string;
    upstream_proxy_node?: string;
    procd_env: string[];
    log_level?: string;
    log_path: string;
}

/**
 * 负载均衡代理节点。
 *
 * 成员节点只通过其本地 SOCKS 端口接入，不复制成员的协议配置。
 */
export class LoadBalanceProxyNode implements ProxyNode {
    name: string;
    type: 'load_balance' = 'load_balance';
    core: string = CORE_TYPE.SING_BOX;
    enabled: string = '1';
    listen_port: string;
    socks_port: string;
    member_node: string[];
    procd_env: string[];
    log_level: string;
    log_path: string;

    // sing-box urltest
    url: string;
    interval: string;
    tolerance: string;
    idle_timeout: string;
    interrupt_exist_connections: string;

    // Xray balancer
    strategy: string;
    strategy_expected: string;
    strategy_max_rtt: string;
    strategy_tolerance: string;
    fallback_tag: string;

    // Xray burstObservatory
    probe_url: string;
    probe_connectivity: string;
    probe_interval: string;
    probe_timeout: string;
    probe_sampling: string;
    probe_http_method: string;

    constructor() {
        this.member_node = [];
        this.procd_env = [];
    }
}

/**
 * 自定义代理配置
 */
export class CustomProxyNode implements ProxyNode {
    name: string;
    type: 'custom' = 'custom';
    enabled: string = '1';
    command: string;
    listen_port: string;
    socks_port: string;
    procd_env: string[];
    log_enabled: string;
    log_path: string;

    constructor() {
        this.type = 'custom';
        this.enabled = '1';
        this.procd_env = [];
    }
}

/**
 * Hysteria2 代理配置
 */
export class Hysteria2Config implements ProxyNode {
    name: string;
    type: 'hysteria2' = 'hysteria2';
    enabled: string = '1';
    /** 核心选择：'' 或 'sing-box' 使用 sing-box，'xray' 使用 xray */
    core: string;
    server: string;
    server_port: string;
    // sing-box 独有
    server_ports: string[];
    hop_interval: string;
    obfs_type: string;
    obfs_password: string;
    brutal_debug: string;
    // xray 独有
    udp_idle_timeout: string;
    // 共有
    up_mbps: string;
    down_mbps: string;
    password: string;
    network: string;
    tls_server_name: string;
    tls_insecure: string;
    listen_port: string;
    socks_port: string;

    procd_env: string[];
    log_path: string;

    constructor() {
        this.type = 'hysteria2';
        this.enabled = '1';
        this.core = CORE_TYPE.SING_BOX;
        this.server_ports = [];
        this.network = '';
        this.brutal_debug = '0';
        this.tls_insecure = '0';
        // TLS 默认启用（不可配置）
    }
}

/**
 * Shadowsocks 代理配置
 */
export class ShadowsocksConfig implements ProxyNode {
    name: string;
    type: 'shadowsocks' = 'shadowsocks';
    enabled: string = '1';
    /** 核心选择：'sing-box'（默认）或 'xray' */
    core: string;
    server: string;
    server_port: string;
    method: string;
    password: string;
    plugin: string;
    plugin_opts: string;
    network: string;
    udp_over_tcp: string;
    listen_port: string;
    socks_port: string;
    multiplex_enabled: string;
    multiplex_protocol: string;
    multiplex_max_connections: string;
    multiplex_min_streams: string;
    multiplex_max_streams: string;
    multiplex_brutal_enabled: string;
    multiplex_brutal_up_mbps: string;
    multiplex_brutal_down_mbps: string;

    procd_env: string[];
    log_path: string;

    constructor() {
        this.type = 'shadowsocks';
        this.enabled = '1';
        this.core = CORE_TYPE.SING_BOX;
        this.network = '';
        this.udp_over_tcp = '0';
        this.multiplex_enabled = '0';
        this.multiplex_protocol = 'h2mux';
        this.multiplex_brutal_enabled = '0';
    }
}

/**
 * TUIC 代理配置
 */
export class TuicConfig implements ProxyNode {
    name: string;
    type: 'tuic' = 'tuic';
    enabled: string = '1';
    core: string;
    server: string;
    server_port: string;
    uuid: string;
    password: string;
    congestion_control: string;
    udp_relay_mode: string;
    udp_over_stream: string;
    zero_rtt_handshake: string;
    heartbeat: string;
    network: string;
    tls_server_name: string;
    tls_insecure: string;
    listen_port: string;
    socks_port: string;

    procd_env: string[];
    log_path: string;

    constructor() {
        this.type = 'tuic';
        this.enabled = '1';
        this.core = CORE_TYPE.SING_BOX;
        this.congestion_control = 'cubic';
        this.udp_relay_mode = '';
        this.udp_over_stream = '0';
        this.zero_rtt_handshake = '0';
        this.heartbeat = '10s';
        this.network = '';
        this.tls_insecure = '0';
    }
}

/**
 * ShadowTLS 代理配置
 */
export class ShadowTLSConfig implements ProxyNode {
    name: string;
    type: 'shadowtls' = 'shadowtls';
    enabled: string = '1';
    core: string;
    server: string;
    server_port: string;
    version: string;
    password: string;
    tls_server_name: string;
    tls_insecure: string;
    listen_port: string;
    socks_port: string;
    procd_env: string[];
    log_path: string;

    constructor() {
        this.type = 'shadowtls';
        this.enabled = '1';
        this.core = CORE_TYPE.SING_BOX;
        this.version = '1';
        this.tls_insecure = '0';
    }
}

/**
 * VLESS 代理配置
 */
export class VlessConfig implements ProxyNode {
    name: string;
    type: 'vless' = 'vless';
    enabled: string = '1';
    /** 核心选择：'sing-box' 使用 sing-box，'xray'（默认）使用 xray */
    core: string;
    server: string;
    server_port: string;
    uuid: string;
    flow: string;
    network: string;
    packet_encoding: string;
    tls_server_name: string;
    tls_insecure: string;
    tls_reality_enabled: string;
    tls_reality_public_key: string;
    tls_reality_short_id: string;
    listen_port: string;
    socks_port: string;
    multiplex_enabled: string;
    multiplex_protocol: string;
    multiplex_max_connections: string;
    multiplex_min_streams: string;
    multiplex_max_streams: string;
    multiplex_brutal_enabled: string;
    multiplex_brutal_up_mbps: string;
    multiplex_brutal_down_mbps: string;
    // V2Ray 传输层
    transport_type: string;
    transport_http_host: string;
    transport_http_path: string;
    transport_http_method: string;
    transport_http_idle_timeout: string;
    transport_http_ping_timeout: string;
    transport_ws_host: string;
    transport_ws_path: string;
    transport_ws_max_early_data: string;
    transport_ws_early_data_header_name: string;
    transport_grpc_service_name: string;
    transport_grpc_idle_timeout: string;
    transport_grpc_ping_timeout: string;
    transport_grpc_permit_without_stream: string;
    transport_httpupgrade_host: string;
    transport_httpupgrade_path: string;
    // XHTTP 传输层
    transport_xhttp_host: string;
    transport_xhttp_path: string;
    transport_xhttp_mode: string;

    procd_env: string[];
    log_path: string;

    constructor() {
        this.type = 'vless';
        this.enabled = '1';
        this.core = CORE_TYPE.XRAY;   // VLESS 默认用 xray（支持 Vision/XHTTP+REALITY）
        this.network = 'tcp';
        this.packet_encoding = '';
        this.tls_insecure = '0';
        this.tls_reality_enabled = '0';
        this.multiplex_enabled = '0';
        this.multiplex_protocol = 'h2mux';
        this.multiplex_brutal_enabled = '0';
        // 传输层默认值
        this.transport_type = '';
        this.transport_http_idle_timeout = '15s';
        this.transport_http_ping_timeout = '15s';
        this.transport_grpc_idle_timeout = '15s';
        this.transport_grpc_ping_timeout = '15s';
        this.transport_grpc_permit_without_stream = '0';
        // XHTTP 传输层默认值
        this.transport_xhttp_path = '/';
        this.transport_xhttp_mode = 'auto';
    }
}
