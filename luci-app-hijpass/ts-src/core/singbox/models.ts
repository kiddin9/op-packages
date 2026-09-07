import { SingBoxEnum } from '../../enum/singbox'
import { RuleDTO } from '../../module/luci'

export class Log {
    disabled: boolean
    level: string
    timestamp: boolean

    constructor(logLevel: string) {
        this.disabled = false
        this.level = logLevel || SingBoxEnum.DEFAULT_LOG_LEVEL
        this.timestamp = true
    }
}

export class DnsServer {
    type: string
    tag: string
    server: string
    server_port?: number
    detour?: string

    constructor(type: string, tag: string, server: string, port: number | undefined, detour?: string) {
        this.type = type
        this.tag = tag
        this.server = server
        this.server_port = Number.isFinite(port) && port > 0 ? port : undefined
        this.detour = detour === SingBoxEnum.DIRECT_OUTBOUND_TAG ? undefined : detour
    }
}

export class DNS {
    servers: DnsServer[]
    rules: DnsRule[]
    strategy: string
    disable_cache: boolean
    disable_expire: boolean
    final: string

    constructor(defaultTag: string, defaultStrategy: string, cache: boolean) {
        this.servers = []
        this.rules = []
        this.strategy = defaultStrategy || SingBoxEnum.DEFAULT_DNS_STRATEGY
        this.disable_cache = !cache
        this.disable_expire = !cache
        this.final = defaultTag
    }
}

export class Rule {
    action: string
    outbound: string

    constructor(action: string, outbound: string) {
        this.action = action
        this.outbound = outbound
    }
}

export class RouteRule extends Rule {
    ip_version?: 4 | 6
    protocol: string[]
    port: number[]
    port_range: string[]
    domain: string[]
    domain_suffix: string[]
    domain_keyword: string[]
    domain_regex: string[]
    rule_set: string[]
    ip_cidr: string[]
    network: string[]

    constructor(action: string, outbound: string) {
        super(action, outbound)
    }

    initRule(rule: RuleDTO): RouteRule {
        this.ip_version = rule.ipVersion
        this.network = rule.network
        this.protocol = rule.protocol
        this.port = rule.port
        this.port_range = rule.portRange.map(range => range.replace('-', ':'))
        this.domain = rule.domain
        this.domain_suffix = rule.domainSuffix
        this.domain_keyword = rule.domainKeyword
        this.domain_regex = rule.domainRegex
        this.rule_set = rule.ruleSet.map(r => r.tag)
        this.ip_cidr = rule.ipCidr
        return this
    }
}

export class DnsRule extends Rule {
    domain: string[]
    domain_keyword: string[]
    domain_regex: string[]
    domain_suffix: string[]
    rule_set: string[]
    server: string
    strategy: string
    disable_cache: boolean
    disable_expire: boolean

    constructor(action: string, server: string, strategy: string) {
        super(action, undefined)
        this.action = action
        this.server = server
        this.strategy = strategy
        this.disable_cache = true
    }

    initRule(rule: RuleDTO): DnsRule {
        this.domain = rule.domain
        this.domain_suffix = rule.domainSuffix
        this.domain_keyword = rule.domainKeyword
        this.domain_regex = rule.domainRegex
        this.rule_set = rule.ruleSet.map(r => r.tag)
        return this
    }
}

export class SniffRule extends RouteRule {
    constructor() { super('sniff', undefined) }
}

export class HijackDnsRule extends RouteRule {
    constructor() {
        super('hijack-dns', undefined)
        this.protocol = ['dns']
    }
}

export class RuleSet {
    type: string
    tag: string
    format: string

    constructor(tag: string, type: string, format: string) {
        this.type = type
        this.tag = tag
        this.format = format
    }
}

export class RemoteRuleSet extends RuleSet {
    url: string
    http_client?: HTTPClient
    update_interval: number

    constructor(tag: string, format: string, url: string, download_detour: string, update_interval: number) {
        super(tag, 'remote', format)
        this.url = url
        if (download_detour) this.http_client = new HTTPClient(download_detour)
        this.update_interval = update_interval
    }
}

export class HTTPClient {
    detour: string

    constructor(detour: string) {
        this.detour = detour
    }
}

export class LocalRuleSet extends RuleSet {
    path: string

    constructor(tag: string, format: string, path: string) {
        super(tag, 'local', format)
        this.path = path
    }
}

export class Route {
    rules: RouteRule[]
    rule_set: RuleSet[]
    default_domain_resolver: string
    final: string

    constructor(defaultProxyTag: string, resolver: string) {
        this.rules = [new SniffRule(), new HijackDnsRule()]
        this.rule_set = []
        this.default_domain_resolver = resolver
        this.final = defaultProxyTag
    }
}

export interface Inbound {
    type: 'tproxy' | 'direct' | 'socks'
    tag: string
    listen: string
    listen_port: number
}

export interface Listener {
    listen: string
    listen_port: number
}

export class TproxyInbound implements Inbound, Listener {
    type: 'tproxy' = 'tproxy'
    tag: string
    listen: string
    listen_port: number

    constructor(port: number, tag: string, address?: string) {
        this.tag = tag
        this.listen = address ?? '::'
        this.listen_port = port
    }
}

export class DnsInbound implements Inbound, Listener {
    type: 'direct' = 'direct'
    tag: string
    listen: string
    listen_port: number

    constructor(port: number, tag: string) {
        this.tag = tag
        this.listen = '::'
        this.listen_port = port
    }
}

export class SocksInbound implements Inbound, Listener {
    type: 'socks' = 'socks'
    tag: string
    listen: string
    listen_port: number
    users?: [{ username: string; password: string }]

    constructor(port: number, tag: string, address?: string) {
        this.tag = tag
        this.listen = address ?? '::'
        this.listen_port = port
    }
}

export interface Outbound {
    type: string
    tag: string
}

export interface Server {
    server: string
    server_port: number
}

export class BlockOutbound implements Outbound {
    type = 'block'
    tag: string
    constructor(tag: string) { this.tag = tag }
}

export class DirectOutbound implements Outbound {
    type = 'direct'
    tag: string
    domain_resolver: string
    constructor(tag: string) { this.tag = tag }
}

export class URLTest implements Outbound {
    type = 'urltest'
    tag: string
    url: string
    interval: string
    tolerance: number
    idle_timeout: string
    interrupt_exist_connections: boolean
    outbounds: string[]

    constructor(
        tag: string,
        url: string,
        interval: string,
        tolerance: number,
        idle_timeout: string,
        interrupt_exist_connections: boolean
    ) {
        this.tag = tag
        this.outbounds = []
        this.url = url
        this.interval = interval
        this.tolerance = tolerance
        this.idle_timeout = idle_timeout
        this.interrupt_exist_connections = interrupt_exist_connections
    }
}

export class SocksOutbound implements Server, Outbound {
    type = 'socks'
    tag: string
    server: string
    server_port: number
    version: '4' | '5' = '5'
    domain_resolver: string

    constructor(server: string, server_port: number, tag: string) {
        this.tag = tag
        this.server = server
        this.server_port = server_port
        this.version = '5'
    }
}

export class TlsConfig {
    enabled: boolean
    server_name: string
    insecure?: boolean
    reality?: { enabled: boolean; public_key: string; short_id: string }

    constructor(serverName: string) {
        this.enabled = true
        this.server_name = serverName
    }
}

export class BrutalConfig {
    enabled: boolean
    up_mbps?: number
    down_mbps?: number

    constructor() { this.enabled = true }
}

export class MultiplexConfig {
    enabled: boolean
    protocol?: 'smux' | 'yamux' | 'h2mux'
    max_connections?: number
    min_streams?: number
    max_streams?: number
    brutal?: BrutalConfig

    constructor() { this.enabled = true }
}
