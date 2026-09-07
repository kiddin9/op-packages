import { XrayEnum } from '../../enum/xray'

export class Log {
    loglevel: string
    dnsLog: boolean

    constructor(logLevel: string) {
        this.loglevel = logLevel || XrayEnum.DEFAULT_LOG_LEVEL
        this.dnsLog = false
    }
}

export class DnsServer {
    tag: string
    address: string
    port: number
    queryStrategy: string
    domains: string[]
    skipFallback: boolean
    disableCache: boolean

    constructor(type: string, tag: string, address: string, port: number) {
        switch (type) {
            case 'tcp':
                this.address = 'tcp://' + address
                this.port = port
                break
            case 'https':
                this.address = 'https://' + address
                if (port) this.address += ':' + port
                this.address += '/dns-query'
                break
            case 'quic':
                this.address = 'quic://' + address
                this.port = port
                break
            case 'udp':
                this.address = address
                this.port = port
                break
            default:
                throw new Error('Invalid xray DNS server type: ' + type)
        }
        this.tag = tag
        this.domains = []
        this.skipFallback = true
    }
}

export class DNS {
    servers: DnsServer[]
    rules: DnsRule[]
    queryStrategy: string
    disableCache: boolean
    serveStale: boolean
    serveExpiredTTL: number
    disableFallback: boolean
    disableFallbackIfMatch: boolean

    constructor(queryStrategy: string, cache: boolean) {
        this.servers = []
        this.rules = []
        this.queryStrategy = queryStrategy || XrayEnum.DEFAULT_DNS_STRATEGY
        this.disableCache = !cache
        this.serveStale = !cache
        this.serveExpiredTTL = 3600
        this.disableFallback = false
        this.disableFallbackIfMatch = true
    }
}

export class Rule {
    ruleTag: string
    inboundTag: string[]
    outboundTag: string
    balancerTag: string

    constructor(ruleTag: string, inboundTag: string[], outbound: string) {
        this.ruleTag = ruleTag
        this.inboundTag = inboundTag
        if (outbound === XrayEnum.LOAD_BALANCE_OUTBOUND_TAG) {
            this.balancerTag = outbound
        } else {
            this.outboundTag = outbound
        }
    }
}

export class RouteRule extends Rule {
    domain: string[]
    network: string[]
    ip: string[]
    protocol: string[]
    port: string

    constructor(tag: string, outbound: string) {
        super(tag, undefined, outbound)
        this.inboundTag = [XrayEnum.TPROXY_INBOUND_TAG]
        this.domain = []
        this.network = []
        this.ip = []
        this.protocol = []
    }
}

export class DnsRule extends Rule {
    constructor(tag: string[], outbound: string) {
        super(undefined, tag, outbound)
    }
}

export class Route<T extends Rule> {
    rules: T[]
    domainStrategy: string
    balancers: Balancer[]

    constructor() {
        this.rules = []
        this.domainStrategy = 'AsIs'
        this.balancers = []
    }
}

export interface Outbound {
    settings?: any
    protocol: string
    tag: string
    streamSettings?: any
}

export class BlockOutbound implements Outbound {
    settings?: any
    protocol: string
    tag: string
    streamSettings?: any

    constructor(tag: string) {
        this.protocol = 'blackhole'
        this.tag = tag
    }
}

export class Socks implements Outbound {
    settings: any
    protocol: string
    tag: string

    constructor(address: string, port: number, tag: string) {
        this.protocol = 'socks'
        this.tag = tag
        this.settings = { address, port }
    }
}

export class DnsOutbound implements Outbound {
    settings: any
    protocol: string
    tag: string

    constructor(tag: string) {
        this.protocol = 'dns'
        this.tag = tag
        this.settings = {
            rules: [
                { action: 'hijack', qType: '1,28' },
                { action: 'return', rCode: 5 }
            ]
        }
    }
}

export class Freedom implements Outbound {
    settings: any
    protocol: string
    tag: string

    constructor(tag: string) {
        this.protocol = 'freedom'
        this.tag = tag
        this.settings = { domainStrategy: XrayEnum.DEFAULT_DNS_STRATEGY }
    }
}

export interface TlsObject {
    serverName: string
    alpn?: string[]
}

export interface SockoptObject {
    mark?: number
    tcpMaxSeg?: number
    tcpFastOpen?: boolean | number
    tproxy?: string
    domainStrategy?: string
    dialerProxy?: string
    acceptProxyProtocol?: boolean
    tcpKeepAliveInterval?: number
    tcpKeepAliveIdle?: number
    tcpUserTimeout?: number
    tcpCongestion?: string
    interface?: string
    v6only?: boolean
    tcpWindowClamp?: number
    tcpMptcp?: boolean
}

export class Balancer {
    tag: string
    selector: string[]
    fallbackTag: string
    strategy: {
        type: string
        settings?: { expected: number; maxRTT: string; tolerance: number }
    }

    constructor(tag: string) {
        this.tag = tag
        this.selector = []
        this.fallbackTag = undefined
        this.strategy = {
            type: 'leastLoad',
            settings: { expected: 1, maxRTT: '1s', tolerance: 0.05 }
        }
    }
}

export class BurstObservatory {
    subjectSelector: string[]
    pingConfig: {
        destination: string
        connectivity: string
        interval: string
        timeout: string
        sampling: number
        httpMethod: string
    }

    constructor(
        destination: string,
        connectivity: string,
        interval: string,
        timeout: string,
        sampling: number,
        httpMethod: string
    ) {
        this.subjectSelector = []
        this.pingConfig = {
            destination: destination || 'https://connectivitycheck.gstatic.com/generate_204',
            connectivity: connectivity || undefined,
            interval: interval || '60s',
            timeout: timeout || '2s',
            sampling: sampling || 3,
            httpMethod: httpMethod || undefined,
        }
    }
}

export class Inbound {
    protocol: string
    tag: string
    listen?: string
    port: number
    settings: any
    streamSettings: any
    sniffing: any

    constructor(type: string, port: number, tag: string, listen?: string) {
        this.protocol = 'dokodemo-door'
        this.tag = tag
        this.listen = listen
        this.port = port
        this.settings = { network: 'tcp,udp', followRedirect: undefined }
        if (type === 'tproxy') {
            this.settings.followRedirect = true
            this.streamSettings = { sockopt: { tproxy: 'tproxy' } }
            this.sniffing = {
                enabled: true,
                destOverride: ['http', 'tls', 'quic'],
                routeOnly: true
            }
        }
    }
}
