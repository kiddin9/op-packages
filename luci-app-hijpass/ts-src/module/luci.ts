import type { ProxyConfigType } from "../enum/hijpass";

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

    ruleSet: string[]; // 原始规则集引用，仅用于前端预检；路径和格式由后端解析
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

/**
 * 代理节点基础配置
 */
export interface ProxyNode {
    name: string;
    cfgid?: string;
    config_type?: ProxyConfigType;
    type?: string;
    core?: string;
    enabled: string;
    listen_port: string;
    socks_port: string;
    upstream_proxy_node?: string;
    procd_env: string[];
    log_level?: string;
    log_enabled?: string;
}

/**
 * 负载均衡代理节点。
 *
 * 成员节点只通过其本地 SOCKS 端口接入，不复制成员的协议配置。
 */
export interface LoadBalanceProxyNode extends ProxyNode {
    member_node: string[];
}
