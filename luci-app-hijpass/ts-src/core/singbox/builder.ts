import './protocols/registry'
import uci from 'uci'
import {
    BlockOutbound, DirectOutbound, DNS, DnsInbound, DnsRule, DnsServer,
    Log, Outbound, RemoteRuleSet, LocalRuleSet, Route, RouteRule, RuleSet,
    SocksInbound, SocksOutbound, TproxyInbound, URLTest
} from './models'
import { ShuntUtils } from '../../utils/feature/shunt/section'
import { LuciFlied, PROXY_TYPE, ShuntTag } from '../../enum/hijpass'
import { SingBoxEnum } from '../../enum/singbox'
import { CoreAdapter, LoadBalanceProxyNode, ProxyNode, RuleDTO, RuleSetDTO } from '../../module/luci'
import { singboxRegistry } from './protocols/protocol'
import { ProxyChainUtils } from '../../utils/feature/proxy/chain'

export const SingBoxUtils: CoreAdapter & { writeGeoRule: () => void } = {
    genShuntConf: genConf,
    genProxyConf,
    writeGeoRule
}

function genConf() {
    const shuntSection = ShuntUtils.getShuntSection()
    if (!shuntSection) return

    const dnsServerMap = new Map<string, DnsServer>()
    const ruleSetMap = new Map<string, RuleSet>()
    const dnsConf = shuntSection.dns
    const routeConf = shuntSection.route
    const route = new Route(transOutTag(routeConf.defaultProxyNode), dnsConf.defaultDnsNode)
    const dns = new DNS(
        dnsConf.defaultDnsNode,
        transDnsStrategy(dnsConf.defaultStrategy),
        dnsConf.useCache === '1'
    )

    dnsConf.nodes.forEach(function (dnsNode) {
        const server = new DnsServer(dnsNode.type, dnsNode.tag, dnsNode.server, parseInt(dnsNode.port, 10), undefined)
        dnsServerMap.set(dnsNode.tag, server)
    })

    let outbounds: any[] = [
        new DirectOutbound(SingBoxEnum.DIRECT_OUTBOUND_TAG),
        new BlockOutbound(SingBoxEnum.BLOCK_OUTBOUND_TAG)
    ]

    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section) {
        if (section.enabled === '1') {
            outbounds.push(new SocksOutbound('127.0.0.1', Number(section.socks_port), section.name))
        }
    })

    const inbounds = [
        new TproxyInbound(parseInt(shuntSection.shuntListenPort, 10), SingBoxEnum.TPROXY_INBOUND_TAG),
        new DnsInbound(parseInt(shuntSection.dnsListenPort, 10), SingBoxEnum.DNS_INBOUND_TAG)
    ]

    if (route.default_domain_resolver && route.final) {
        const dnsTmpl = dnsServerMap.get(route.default_domain_resolver)
        if (!dnsTmpl) throw new Error(_('Default global DNS "%s" does not exist').format(route.default_domain_resolver))
        dns.servers.push(genDnsFromTmpl(dnsTmpl.tag, route.final, dnsTmpl))
    }

    if (routeConf.rulesetOutNode) {
        const outTag = transOutTag(routeConf.rulesetOutNode)
        const node = outbounds.find(o => o.tag === outTag)
        if (node) {
            const rulesetOutNode = structuredClone(node)
            rulesetOutNode.tag = SingBoxEnum.RULESET_OUTBOUND_TAG
            if (dnsConf.rulesetDnsNode) {
                rulesetOutNode.domain_resolver = SingBoxEnum.RULESET_DNS_NAME
                const dnsTmpl = dnsServerMap.get(dnsConf.rulesetDnsNode)
                if (!dnsTmpl) throw new Error(_('%s "%s" does not exist').format(_('Rule-set DNS'), dnsConf.rulesetDnsNode))
                dns.servers.push(genDnsFromTmpl(SingBoxEnum.RULESET_DNS_NAME, SingBoxEnum.RULESET_OUTBOUND_TAG, dnsTmpl))
            }
            outbounds.push(rulesetOutNode)
        }
    }

    routeConf.rules.forEach(function (routeRule) {
        if (routeRule.enabled !== '1') return
        const isIpVersionSplit = routeRule.ipVersionSplit === '1'
        let splitDnsRuleDTO: RuleDTO = undefined
        let splitDnsNeeded = false

        ShuntUtils.getRouteRuleVariants(routeRule).forEach(function (variant) {
            const luciRuleDTO = ShuntUtils.parseRuleList(variant.rule)
            const hasDnsTarget = hasSingBoxDnsTargetRule(luciRuleDTO, routeConf.rulesetConvert)
            luciRuleDTO.ipVersion = variant.ipVersion

            if (routeConf.rulesetConvert === '1') {
                convertGeoRule(luciRuleDTO)
            } else if (luciRuleDTO.containGeo()) {
                dropGeoRule(luciRuleDTO)
                if (!hasSingBoxTargetRule(luciRuleDTO)) return
            }

            if (luciRuleDTO.isEmpty('set')) return

            for (const rs of luciRuleDTO.ruleSet) {
                ruleSetMap.set(rs.tag, genRuleSet(rs, routeConf.rulesetOutNode ? SingBoxEnum.RULESET_OUTBOUND_TAG : undefined))
            }

            let action = 'route'
            let outbound = transOutTag(variant.proxyNode)
            if (variant.proxyNode === ShuntTag.BLOCK_OUTBOUND_TAG) {
                action = 'reject'
                outbound = undefined
            }
            route.rules.push(new RouteRule(action, outbound).initRule(luciRuleDTO))

            if (action === 'reject') return

            if (isIpVersionSplit) {
                if (hasDnsTarget) {
                    splitDnsRuleDTO = splitDnsRuleDTO || luciRuleDTO
                    splitDnsNeeded = true
                }
                return
            }

            if (luciRuleDTO.containDomain() || luciRuleDTO.containIp() || luciRuleDTO.containRuleSet()) {
                appendSingBoxDnsRule(routeRule, variant.rule.name, luciRuleDTO, transOutTag(routeRule.dnsProxyNode) || outbound, dnsServerMap, route, dns)
            }
        })

        if (isIpVersionSplit && splitDnsNeeded && splitDnsRuleDTO) {
            const detour = transOutTag(routeRule.dnsProxyNode)
            if (!detour) {
                throw new Error(_('Route rule "%s" uses IPv4/IPv6 split and must specify a DNS exit node').format(routeRule.name))
            }
            appendSingBoxDnsRule(routeRule, routeRule.name, splitDnsRuleDTO, detour, dnsServerMap, route, dns)
        }
    })

    ruleSetMap.forEach(value => route.rule_set.push(value))

    return {
        log: new Log(shuntSection.logLevel),
        inbounds,
        outbounds,
        dns,
        route
    }
}

function genProxyConf(proxyNode: ProxyNode): {} {
    if (proxyNode.type === PROXY_TYPE.LOAD_BALANCE) {
        return genLoadBalanceProxyConf(proxyNode as LoadBalanceProxyNode)
    }

    const outbound: any = singboxRegistry.build(proxyNode.type, proxyNode)
    const outbounds = [outbound]
    appendProxyChainOutbounds(proxyNode, outbound, outbounds)

    return {
        log: new Log(proxyNode.log_level),
        dns: { servers: [{ type: 'local', tag: 'local' }] },
        inbounds: [
            new TproxyInbound(Number(proxyNode.listen_port), 'tproxy-in', '127.0.0.1'),
            new SocksInbound(Number(proxyNode.socks_port), 'socks-in', '127.0.0.1')
        ],
        outbounds
    }
}

function genLoadBalanceProxyConf(proxyNode: LoadBalanceProxyNode): {} {
    const members = ProxyChainUtils.resolveLoadBalanceMembers(proxyNode)
    const loadBalance = new URLTest(
        SingBoxEnum.LOAD_BALANCE_OUTBOUND_TAG,
        proxyNode.url || undefined,
        proxyNode.interval || undefined,
        proxyNode.tolerance ? parseInt(proxyNode.tolerance, 10) : undefined,
        proxyNode.idle_timeout || undefined,
        proxyNode.interrupt_exist_connections === '1' ? true : undefined
    )
    loadBalance.outbounds = members.map(member => member.tag)

    return {
        log: new Log(proxyNode.log_level),
        dns: { servers: [{ type: 'local', tag: 'local' }] },
        inbounds: [
            new TproxyInbound(Number(proxyNode.listen_port), 'tproxy-in', '127.0.0.1'),
            new SocksInbound(Number(proxyNode.socks_port), 'socks-in', '127.0.0.1')
        ],
        outbounds: [
            loadBalance,
            ...members.map(member => new SocksOutbound('127.0.0.1', member.socksPort, member.tag))
        ],
        route: { final: SingBoxEnum.LOAD_BALANCE_OUTBOUND_TAG }
    }
}

function appendProxyChainOutbounds(proxyNode: ProxyNode, outbound: any, outbounds: any[]) {
    const upstream = ProxyChainUtils.resolveUpstreamProxy(proxyNode)
    if (!upstream) return

    outbound.detour = upstream.tag
    outbounds.push(new SocksOutbound('127.0.0.1', upstream.socksPort, upstream.tag))
}

function writeGeoRule() {
    const routeConf = ShuntUtils.getRouteSection()
    const geoSiteSet = new Set<string>()
    const geoIpSet = new Set<string>()
    for (const rule of routeConf.rules) {
        if (rule.enabled !== '1') continue
        const luciRuleDTO = ShuntUtils.parseRuleList(rule)
        for (const geo of luciRuleDTO.geoSite) geoSiteSet.add(geo.replace('geosite:', ''))
        for (const geo of luciRuleDTO.geoIp) geoIpSet.add(geo.replace('geoip:', ''))
    }
    const geoSiteList = [...geoSiteSet]
    const geoIpList = [...geoIpSet]
    const originalIps = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'geoip_ruleset') ?? []
    const originalSites = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'geosite_ruleset') ?? []

    if (geoIpList.length > 0) {
        if (!isArrEqual(originalIps, geoIpList)) {
            uci.set_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'geoip_ruleset', geoIpList)
        }
    } else {
        uci.set_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'geoip_ruleset', undefined)
    }
    if (geoSiteList.length > 0) {
        if (!isArrEqual(originalSites, geoSiteList)) {
            uci.set_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'geosite_ruleset', geoSiteList)
        }
    } else {
        uci.set_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'geosite_ruleset', undefined)
    }
}

function genDnsFromTmpl(tag: string, detour: string, tmpl: DnsServer): DnsServer {
    return new DnsServer(tmpl.type, tag, tmpl.server, tmpl.server_port, detour)
}

function genRuleSet(rs: RuleSetDTO, detour: string): RuleSet {
    if (rs.type === 'remote') return new RemoteRuleSet(rs.tag, rs.format, rs.pathOrUrl, detour, undefined)
    return new LocalRuleSet(rs.tag, rs.format, rs.pathOrUrl)
}

function transDnsStrategy(strategy: string) {
    switch (strategy) {
        case '4': return 'ipv4_only'
        case '6': return 'ipv6_only'
        case '64': return 'prefer_ipv6'
        case '46': return 'prefer_ipv4'
        default: return undefined
    }
}

function appendSingBoxDnsRule(routeRule: any, ruleName: string, luciRuleDTO: RuleDTO, detour: string, dnsServerMap: Map<string, DnsServer>, route: Route, dns: DNS) {
    const dnsTag = routeRule.dnsNode
    const dnsTmpl = dnsTag
        ? dnsServerMap.get(dnsTag)
        : dnsServerMap.get(route.default_domain_resolver)
    if (!dnsTmpl) {
        throw new Error(_('Route rule "%s" DNS node "%s" does not exist').format(routeRule.name || ruleName, routeRule.dnsNode || route.default_domain_resolver || ''))
    }
    dns.servers.push(genDnsFromTmpl(transDnsTag(ruleName), detour, dnsTmpl))
    dns.rules.push(
        new DnsRule('route', transDnsTag(ruleName), transDnsStrategy(routeRule.dnsStrategy))
            .initRule(luciRuleDTO)
    )
}

function transOutTag(tag: string) {
    if (tag === ShuntTag.BLOCK_OUTBOUND_TAG) return SingBoxEnum.BLOCK_OUTBOUND_TAG
    if (tag === ShuntTag.DIRECT_OUTBOUND_TAG) return SingBoxEnum.DIRECT_OUTBOUND_TAG
    return tag
}

function transDnsTag(name: string) { return name + '-dns' }

function convertGeoRule(luciRuleDTO: RuleDTO) {
    luciRuleDTO.ruleSet = []
    for (const geo of luciRuleDTO.geoSite) {
        const tag = geo.replace('geosite:', 'geosite-')
        luciRuleDTO.ruleSet.push({ tag, type: 'local', format: 'binary', pathOrUrl: '/etc/hijpass/ruleset/' + tag + '.srs' })
    }
    for (const geo of luciRuleDTO.geoIp) {
        const tag = geo.replace('geoip:', 'geoip-')
        luciRuleDTO.ruleSet.push({ tag, type: 'local', format: 'binary', pathOrUrl: '/etc/hijpass/ruleset/' + tag + '.srs' })
    }
}

function dropGeoRule(luciRuleDTO: RuleDTO) {
    luciRuleDTO.geoSite = []
    luciRuleDTO.geoIp = []
}

function hasSingBoxTargetRule(luciRuleDTO: RuleDTO) {
    return luciRuleDTO.containDomain()
        || luciRuleDTO.containIp()
        || luciRuleDTO.containRuleSet()
}

function hasSingBoxDnsTargetRule(luciRuleDTO: RuleDTO, rulesetConvert: string) {
    return luciRuleDTO.containDomain()
        || luciRuleDTO.containRuleSet()
        || (rulesetConvert === '1' && luciRuleDTO.geoSite.length > 0)
}

function isArrEqual(arr1: any[], arr2: any[]) {
    if (!arr1 || !arr2) return false
    return arr1.length === arr2.length && arr1.every((val, i) => val === arr2[i])
}
