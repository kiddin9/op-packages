import './protocols/registry'
import uci from 'uci'
import {XrayEnum} from '../../enum/xray'
import {ShuntUtils} from '../../utils/feature/shunt/section'
import {
    Balancer, BurstObservatory,
    DNS, DnsOutbound, DnsRule, DnsServer,
    Freedom, Inbound, Log, Outbound, Route,
    RouteRule, Rule, Socks, BlockOutbound
} from './models'
import {LuciFlied, PROXY_TYPE, ShuntTag} from '../../enum/hijpass'
import { CoreAdapter, LoadBalanceProxyNode, ProxyNode, RuleDTO } from '../../module/luci'
import {xrayRegistry} from './protocols/protocol'
import { LOAD_BALANCE_MEMBER_TAG_PREFIX, ProxyChainUtils } from '../../utils/feature/proxy/chain'

export const XrayUtils: CoreAdapter = {
    genShuntConf: genConf,
    genProxyConf
}

function genConf() {
    const shuntSection = ShuntUtils.getShuntSection()

    const dnsServerMap = new Map<string, DnsServer>()
    const route = new Route<RouteRule | DnsRule>()

    const dnsConf = shuntSection.dns
    const dns = new DNS(transDnsStrategy(dnsConf.defaultStrategy), dnsConf.useCache === '1')
    dnsConf.nodes.forEach(function (dnsNode) {
        const server = new DnsServer(dnsNode.type, dnsNode.tag, dnsNode.server, Number(dnsNode.port))
        dnsServerMap.set(dnsNode.tag, server)
    })

    const routeConf = shuntSection.route
    const outbounds: Outbound[] = []
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section) {
        if (section.enabled === '1') {
            const proxyNode = new Socks('127.0.0.1', Number(section.socks_port), transOutTag(section.name))
            if (section.name === routeConf.defaultProxyNode) {
                outbounds.unshift(proxyNode)
            } else {
                outbounds.push(proxyNode)
            }
        }
    })
    if (routeConf.defaultProxyNode === ShuntTag.DIRECT_OUTBOUND_TAG) {
        outbounds.unshift(new Freedom(XrayEnum.DIRECT_OUTBOUND_TAG))
    } else {
        outbounds.push(new Freedom(XrayEnum.DIRECT_OUTBOUND_TAG))
    }
    outbounds.push(new BlockOutbound(XrayEnum.BLOCK_OUTBOUND_TAG))
    outbounds.push(new DnsOutbound(XrayEnum.DNS_OUTBOUND_TAG))

    const inbounds = [
        new Inbound('tproxy', parseInt(shuntSection.shuntListenPort, 10), XrayEnum.TPROXY_INBOUND_TAG),
        new Inbound('direct', parseInt(shuntSection.dnsListenPort, 10), XrayEnum.DNS_INBOUND_TAG, '::')
    ]

    const dnsRules = [new DnsRule([XrayEnum.DNS_INBOUND_TAG], XrayEnum.DNS_OUTBOUND_TAG)]
    const routeRules: RouteRule[] = []
    const defaultDnsTmpl = dnsServerMap.get(dnsConf.defaultDnsNode)
    if (!defaultDnsTmpl) {
        throw new Error(_('Default global DNS "%s" does not exist').format(dnsConf.defaultDnsNode || ''))
    }
    const dnsInOutMap = new Map<string, string[]>()

    routeConf.rules.forEach(function (rule) {
        if (rule.enabled !== '1') return
        const isIpVersionSplit = rule.ipVersionSplit === '1'
        let splitDnsRuleDTO: RuleDTO = undefined
        let splitDnsNeeded = false

        ShuntUtils.getRouteRuleVariants(rule).forEach(function (variant) {
            const ruleOutBoundTag = transOutTag(variant.proxyNode) || outbounds[0].tag

            const luciRuleDTO = ShuntUtils.parseRuleList(variant.rule)
            const hasDnsTarget = hasXrayDnsTargetRule(luciRuleDTO)
            luciRuleDTO.ipVersion = variant.ipVersion
            if (shouldSkipXrayRule(luciRuleDTO)) return

            buildXrayRouteRules(variant.rule.name, ruleOutBoundTag, luciRuleDTO).forEach((routeRule) => {
                routeRules.push(routeRule)
            })

            if (ruleOutBoundTag === XrayEnum.BLOCK_OUTBOUND_TAG) return

            if (isIpVersionSplit) {
                if (hasDnsTarget) {
                    splitDnsRuleDTO = splitDnsRuleDTO || luciRuleDTO
                    splitDnsNeeded = true
                }
                return
            }

            if (hasDnsTarget) {
                const outboundTag = transOutTag(rule.dnsProxyNode) || ruleOutBoundTag
                appendXrayDnsServer(rule, variant.rule.name, outboundTag, luciRuleDTO, dnsServerMap, defaultDnsTmpl, dns, dnsInOutMap)
            }
        })

        if (isIpVersionSplit && splitDnsNeeded && splitDnsRuleDTO) {
            const outboundTag = transOutTag(rule.dnsProxyNode)
            if (!outboundTag) {
                throw new Error(_('Route rule "%s" uses IPv4/IPv6 split and must specify a DNS exit node').format(rule.name))
            }
            appendXrayDnsServer(rule, rule.name, outboundTag, splitDnsRuleDTO, dnsServerMap, defaultDnsTmpl, dns, dnsInOutMap)
        }
    })

    const defaultDnsServer = structuredClone(defaultDnsTmpl)
    defaultDnsServer.tag = transDnsTag('default')
    defaultDnsServer.skipFallback = false
    dns.servers.push(defaultDnsServer)

    dnsInOutMap.forEach((v, k) => dnsRules.push(new DnsRule(v, k)))

    route.rules = route.rules.concat(dnsRules)
    route.rules = route.rules.concat(routeRules)

    const log = new Log(transXrayLogLevel(shuntSection.logLevel))

    return {
        log,
        inbounds,
        outbounds,
        dns,
        routing: route
    }
}

function genProxyConf(config: ProxyNode): {} {
    if (config.type === PROXY_TYPE.LOAD_BALANCE) {
        return genLoadBalanceProxyConf(config as LoadBalanceProxyNode)
    }

    const outbound = xrayRegistry.build(config.type, config)
    return buildBaseProxyConf(config, outbound)
}

function buildBaseProxyConf(config: ProxyNode, outbound: Outbound): {} {
    const inbounds = buildProxyInbounds(config)

    const outbounds = [outbound]
    appendProxyChainOutbounds(config, outbound, outbounds)

    return {
        log: new Log(transXrayLogLevel(config.log_level)),
        inbounds,
        outbounds
    }
}

function buildProxyInbounds(config: ProxyNode): Inbound[] {
    const tproxyInbound = new Inbound('tproxy', Number(config.listen_port), 'tproxy-in')
    tproxyInbound.sniffing = undefined

    const socksInbound = new Inbound('direct', Number(config.socks_port), 'socks-in')
    socksInbound.settings = {udp: true}
    socksInbound.protocol = 'socks'

    return [tproxyInbound, socksInbound]
}

function genLoadBalanceProxyConf(config: LoadBalanceProxyNode): {} {
    const members = ProxyChainUtils.resolveLoadBalanceMembers(config)
    const route = new Route<Rule>()
    route.rules.push(new Rule(undefined, ['tproxy-in', 'socks-in'], XrayEnum.LOAD_BALANCE_OUTBOUND_TAG))

    const balancer = new Balancer(XrayEnum.LOAD_BALANCE_OUTBOUND_TAG)
    balancer.selector = [LOAD_BALANCE_MEMBER_TAG_PREFIX]
    const fallback = members.find(member => member.name === config.fallback_tag) || members[0]
    balancer.fallbackTag = fallback.tag

    const strategy = config.strategy || 'leastLoad'
    balancer.strategy.type = strategy
    if (strategy === 'leastLoad') {
        if (config.strategy_expected) balancer.strategy.settings.expected = parseInt(config.strategy_expected, 10)
        if (config.strategy_max_rtt) balancer.strategy.settings.maxRTT = config.strategy_max_rtt
        if (config.strategy_tolerance) balancer.strategy.settings.tolerance = parseFloat(config.strategy_tolerance)
    } else {
        balancer.strategy.settings = undefined
    }
    route.balancers.push(balancer)

    const burstObservatory = new BurstObservatory(
        config.probe_url || undefined,
        config.probe_connectivity || undefined,
        config.probe_interval || undefined,
        config.probe_timeout || undefined,
        config.probe_sampling ? parseInt(config.probe_sampling, 10) : undefined,
        config.probe_http_method || undefined
    )
    burstObservatory.subjectSelector = [LOAD_BALANCE_MEMBER_TAG_PREFIX]

    const outbounds = members.map(member => new Socks('127.0.0.1', member.socksPort, member.tag))

    return {
        log: new Log(transXrayLogLevel(config.log_level)),
        inbounds: buildProxyInbounds(config),
        outbounds,
        routing: route,
        burstObservatory
    }
}

function transXrayLogLevel(logLevel: string) {
    return logLevel === 'warn' ? 'warning' : logLevel
}

function appendProxyChainOutbounds(config: ProxyNode, outbound: Outbound, outbounds: Outbound[]) {
    const upstream = ProxyChainUtils.resolveUpstreamProxy(config)
    if (!upstream) return

    setDialerProxy(outbound, upstream.tag)
    outbounds.push(new Socks('127.0.0.1', upstream.socksPort, upstream.tag))
}

function setDialerProxy(outbound: Outbound, tag: string) {
    outbound.streamSettings = outbound.streamSettings || {}
    outbound.streamSettings.sockopt = outbound.streamSettings.sockopt || {}
    outbound.streamSettings.sockopt.dialerProxy = tag
    outbound.streamSettings.sockopt.domainStrategy = 'UseIP'
}

function transDnsTag(name: string) {
    return name + '-dns'
}

function shouldSkipXrayRule(luciRuleDTO: RuleDTO) {
    if (luciRuleDTO.isEmpty('geo')) return true
    return luciRuleDTO.containRuleSet()
        && !luciRuleDTO.containDomain()
        && !luciRuleDTO.containIp()
        && !luciRuleDTO.containGeo()
}

function hasXrayDnsTargetRule(luciRuleDTO: RuleDTO) {
    return luciRuleDTO.containDomain() || luciRuleDTO.geoSite.length > 0
}

function appendXrayDnsServer(rule: any, ruleName: string, outboundTag: string, luciRuleDTO: RuleDTO, dnsServerMap: Map<string, DnsServer>, defaultDnsTmpl: DnsServer, dns: DNS, dnsInOutMap: Map<string, string[]>) {
    const dnsTag = transDnsTag(ruleName)
    if (dnsInOutMap.has(outboundTag)) {
        dnsInOutMap.get(outboundTag).push(dnsTag)
    } else {
        dnsInOutMap.set(outboundTag, [dnsTag])
    }
    const dnsTmpl = rule.dnsNode ? dnsServerMap.get(rule.dnsNode) : defaultDnsTmpl
    if (!dnsTmpl) {
        throw new Error(_('Route rule "%s" DNS node "%s" does not exist').format(rule.name || ruleName, rule.dnsNode || ''))
    }
    const server = structuredClone(dnsTmpl)
    server.tag = dnsTag
    server.queryStrategy = transDnsStrategy(rule.dnsStrategy)
    server.domains = buildXrayDomains(luciRuleDTO)
    dns.servers.push(server)
}

function buildXrayRouteRules(name: string, outboundTag: string, luciRuleDTO: RuleDTO): RouteRule[] {
    const routeRule = new RouteRule(name, outboundTag)
    routeRule.network = luciRuleDTO.network
    routeRule.protocol = transRouteProtocol(luciRuleDTO.protocol)

    let allPorts: string[] = luciRuleDTO.port.map(p => String(p))
    if (luciRuleDTO.portRange && luciRuleDTO.portRange.length > 0) {
        allPorts = allPorts.concat(luciRuleDTO.portRange)
    }
    routeRule.port = allPorts.join(',')

    routeRule.domain = buildXrayDomains(luciRuleDTO)
    routeRule.domain = routeRule.domain.length > 0 ? routeRule.domain : undefined
    routeRule.ip = buildXrayIps(luciRuleDTO)
    routeRule.ip = routeRule.ip.length > 0 ? routeRule.ip : undefined

    const rules: RouteRule[] = []
    const ipVersionRange = transXrayIpVersion(luciRuleDTO.ipVersion)
    if (routeRule.domain) {
        const domainRule = structuredClone(routeRule)
        if (ipVersionRange) domainRule.ip = [ipVersionRange]
        else domainRule.ip = undefined
        rules.push(domainRule)
    }
    if (routeRule.ip) {
        const ipRule = structuredClone(routeRule)
        ipRule.domain = undefined
        rules.push(ipRule)
    }
    if (!routeRule.domain && !routeRule.ip) {
        if (ipVersionRange) routeRule.ip = [ipVersionRange]
        rules.push(routeRule)
    }
    return rules
}

function buildXrayDomains(luciRuleDTO: RuleDTO): string[] {
    const domainArrays = [
        addPrefixToElements(luciRuleDTO.domain, 'full:'),
        addPrefixToElements(luciRuleDTO.domainSuffix, 'domain:'),
        luciRuleDTO.domainKeyword,
        addPrefixToElements(luciRuleDTO.domainRegex, 'regexp:'),
        luciRuleDTO.geoSite
    ]
    return ([] as string[]).concat(...domainArrays.filter(a => Array.isArray(a) && a.length > 0))
}

function buildXrayIps(luciRuleDTO: RuleDTO): string[] {
    const ipArrays = [
        filterIpRulesByVersion(luciRuleDTO.ipCidr, luciRuleDTO.ipVersion),
        luciRuleDTO.geoIp
    ]
    return ([] as string[]).concat(...ipArrays.filter(a => Array.isArray(a) && a.length > 0))
}

function filterIpRulesByVersion(rules: string[], ipVersion?: 4 | 6): string[] {
    if (!ipVersion || !Array.isArray(rules)) return rules || []
    return rules.filter((rule) => {
        const normalized = rule.replace(/^!/, '')
        if (normalized.startsWith('geoip:') || normalized.startsWith('ext:')) return true
        if (normalized.indexOf(':') >= 0) return ipVersion === 6
        if (/^\d{1,3}(\.\d{1,3}){3}(\/\d+)?$/.test(normalized)) return ipVersion === 4
        return true
    })
}

function transXrayIpVersion(ipVersion?: 4 | 6) {
    if (ipVersion === 4) return '0.0.0.0/0'
    if (ipVersion === 6) return '::/0'
    return undefined
}

function transOutTag(tag: string) {
    if (tag === ShuntTag.BLOCK_OUTBOUND_TAG) return XrayEnum.BLOCK_OUTBOUND_TAG
    if (tag === ShuntTag.DIRECT_OUTBOUND_TAG) return XrayEnum.DIRECT_OUTBOUND_TAG
    return tag
}

function transDnsStrategy(strategy: string) {
    switch (strategy) {
        case '4':
            return 'UseIPv4'
        case '6':
            return 'UseIPv6'
        case '64':
        case '46':
            return 'UseIP'
        default:
            return undefined
    }
}

function transRouteProtocol(protocol: string[]) {
    if (!protocol) return undefined
    const res = protocol.map((pro: string) => {
        switch (pro) {
            case 'http':
            case 'tls':
            case 'quic':
            case 'bittorrent':
                return pro
            default:
                throw new Error('Unsupported xray rule protocol: ' + pro)
        }
    }).filter(p => p !== undefined)
    return res.length === 0 ? undefined : res
}

function addPrefixToElements(arr: string[], prefix: string) {
    if (!Array.isArray(arr)) return []
    return arr.map(item => prefix + item)
}
