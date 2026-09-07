import uci from "uci";
import { FIREWALL_DNS_FORWARD, LuciFlied, PROXY_TYPE } from "../../../enum/hijpass";
import { FirewallDnsForwardUtils } from "../firewall/dns-forward";
import { ProxyChainUtils } from "../proxy/chain";

export type FlowTone = 'normal' | 'direct' | 'proxy' | 'muted' | 'warning';
export type FlowPage = 'firewall' | 'proxy' | 'shunt' | 'dns' | 'dhcp';

export type FlowStep = {
    title: string;
    detail?: string;
    tone?: FlowTone;
    page?: FlowPage;
}

export type FlowBranch = {
    condition: string;
    page?: FlowPage;
    detail?: string;
    steps: FlowStep[];
}

export type FlowDiagram = {
    id: string;
    title: string;
    steps: FlowStep[];
    branches?: FlowBranch[];
    branchMode?: 'parallel' | 'ordered';
    branchDescription?: string;
}

export type ConfigurationFlowPreview = {
    diagrams: FlowDiagram[];
}

function getFirstSection(type: string): any {
    return uci.get_first(LuciFlied.CONF_NAME, type) || {};
}

function normalizeList(value: any): string[] {
    if (!value) return [];
    return (Array.isArray(value) ? value : [value]).filter(Boolean);
}

function isPort(value: any): boolean {
    const port = Number(value);
    return Number.isInteger(port) && port > 0 && port <= 65535;
}

function formatEndpoint(value: string): string {
    return value ? value.replace('#', ':') : _('Not configured');
}

function getAclMode(firewall: any): string {
    return firewall.acl_default_allow === '1' ? _('Bypass mode') : _('Proxy mode');
}

function getAclTitle(firewall: any): string {
    return _('Firewall ACL') + ' · ' + getAclMode(firewall);
}

function getAclDetail(firewall: any): string {
    if (firewall.acl_default_allow === '1') {
        const devices = normalizeList(firewall.proxy_mac_exclude_list).length;
        const interfaces = normalizeList(firewall.proxy_iface_exclude_list).length;
        return _('Excluded: %s devices, %s interfaces').format(String(devices), String(interfaces));
    }

    const devices = normalizeList(firewall.proxy_mac_list).length;
    const interfaces = normalizeList(firewall.proxy_iface_list).length;
    return _('Selected: %s devices, %s interfaces').format(String(devices), String(interfaces));
}

function getProxyTarget(port: string, portLabel: string): FlowStep[] {
    if (!isPort(port)) {
        return [{ title: portLabel, detail: _('No valid listen port'), tone: 'warning', page: 'firewall' }];
    }

    const sections = ProxyChainUtils.getProxySectionMap();
    const proxy = Array.from(sections.values()).find(section =>
        section.enabled === '1' && section.listen_port === port);
    const steps: FlowStep[] = [{ title: portLabel + ': ' + port, tone: 'proxy', page: 'firewall' }];

    if (!proxy) {
        steps.push({ title: _('Proxy node unavailable'), detail: _('No enabled node uses this port'), tone: 'warning', page: 'proxy' });
        return steps;
    }

    if (proxy.type === PROXY_TYPE.LOAD_BALANCE) {
        const members = ProxyChainUtils.normalizeProxyNodeList(proxy.member_node);
        steps.push({
            title: _('Load balancing: %s').format(proxy.name),
            page: 'proxy',
            detail: members.length > 0 ? _('Members: %s').format(members.join(', ')) : _('No member nodes'),
            tone: members.length > 0 ? 'proxy' : 'warning',
        });
        return steps;
    }

    steps.push({
        title: _('Proxy node: %s').format(proxy.name),
        page: 'proxy',
        detail: ProxyChainUtils.getProxyCore(proxy),
        tone: 'proxy',
    });

    const chain = ProxyChainUtils.collectProxyChain(proxy.name, sections);
    chain.chain.slice(1).forEach(name => {
        const upstream = sections.get(name);
        steps.push({
            title: _('Upstream proxy: %s').format(name),
            page: 'proxy',
            detail: upstream?.socks_port ? _('SOCKS port %s').format(upstream.socks_port) : _('Node unavailable'),
            tone: upstream ? 'proxy' : 'warning',
        });
    });
    if (chain.cycle) {
        steps.push({ title: _('Proxy dependency cycle'), tone: 'warning', page: 'proxy' });
    }
    return steps;
}

function getRoutingSteps(shunt: any, path: 'dns' | 'traffic'): FlowStep[] {
    const port = path === 'dns' ? shunt.dns_listen_port : shunt.shunt_listen_port;
    const title = path === 'dns' ? _('Core DNS') : _('Default shunt port');
    if (shunt.enabled === '0' || !isPort(port)) {
        return [{ title, detail: _('Disabled or invalid listen port'), tone: 'warning', page: 'shunt' }];
    }

    // Show the routing resource, not its condition-dependent outbound nodes.
    if (path === 'traffic') {
        return [
            { title: title + ': ' + port, tone: 'proxy', page: 'firewall' },
            { title: _('Default shunt'), detail: shunt.type === 'xray' ? 'Xray' : shunt.type || '', tone: 'proxy', page: 'shunt' },
        ];
    }

    const steps: FlowStep[] = [{
        title: title + ': ' + port,
        page: 'shunt',
        detail: shunt.type === 'xray' ? 'Xray' : shunt.type || '',
        tone: 'proxy',
    }];

    if (shunt.config_type === 'custom') {
        steps.push({ title: _('Custom core configuration'), detail: _('Internal path cannot be expanded'), tone: 'muted', page: 'shunt' });
        return steps;
    }

    const rules = uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_ROUTE_RULE_TYPE)
        .filter((rule: any) => rule.enabled === '1');
    const dnsRules = rules.filter((rule: any) => Boolean(rule.dns_node));
    steps.push({
        title: _('DNS routing rules'),
        page: 'shunt',
        detail: _('%s enabled rules, default DNS: %s')
            .format(String(dnsRules.length), shunt.default_dns_node || _('Not configured')),
        tone: 'normal',
    });
    return steps;
}

function getDnsUpstreamSteps(value: string, customValue: string, shunt: any): FlowStep[] {
    if (value === 'custom') {
        return [{ title: _('Custom DNS'), detail: formatEndpoint(customValue), tone: 'normal', page: 'dns' }];
    }
    if (value === 'dnsmasq' || value === 'system') {
        const dnsmasqPort = uci.get_first('dhcp', 'dnsmasq', 'port') || '53';
        return [{ title: 'dnsmasq', detail: _('Local port %s').format(dnsmasqPort), tone: 'direct', page: 'dhcp' }];
    }

    const routingPort = shunt.dns_listen_port || '';
    if (value === FIREWALL_DNS_FORWARD.ROUTING || value === '127.0.0.1#' + routingPort) {
        return getRoutingSteps(shunt, 'dns');
    }
    return [{ title: _('DNS upstream'), detail: formatEndpoint(value), tone: 'normal', page: 'dns' }];
}

function buildDnsDiagram(global: any, firewall: any, dns: any, shunt: any): FlowDiagram {
    const source = FirewallDnsForwardUtils.getSource();
    const aclDetail = source === FIREWALL_DNS_FORWARD.NONE
        ? getAclDetail(firewall)
        : [
            getAclDetail(firewall),
            firewall.proxy_local === '1' ? _('Router traffic included') : _('Router traffic excluded'),
        ].join('\n');
    const steps: FlowStep[] = [
        { title: _('Client DNS query'), detail: _('TCP/UDP port 53') },
        { title: getAclTitle(firewall), detail: aclDetail, page: 'firewall' },
    ];

    if (source === FIREWALL_DNS_FORWARD.NONE) {
        steps.push({ title: _('No DNS redirect'), detail: _('Keep the original destination'), tone: 'muted', page: 'firewall' });
        return { id: 'dns', title: _('DNS flow'), steps };
    }
    if (source === FIREWALL_DNS_FORWARD.ROUTING) {
        steps.push(...getRoutingSteps(shunt, 'dns'));
        return { id: 'dns', title: _('DNS flow'), steps };
    }
    if (source !== FIREWALL_DNS_FORWARD.PRE_ROUTING) {
        steps.push({ title: _('Unknown DNS forwarding source'), detail: source, tone: 'warning' });
        return { id: 'dns', title: _('DNS flow'), steps };
    }
    if (dns.dns_service !== 'chinadns-ng' || !isPort(dns.cdg_port)) {
        steps.push({ title: _('Independent DNS unavailable'), detail: _('Disabled or invalid listen port'), tone: 'warning', page: 'dns' });
        return { id: 'dns', title: _('DNS flow'), steps };
    }

    steps.push({ title: _('Independent DNS: %s').format(dns.cdg_port), detail: 'chinadns-ng', tone: 'proxy', page: 'dns' });
    const directConditions: string[] = [];
    const proxyConditions: string[] = [];
    if (global.domain_direct) directConditions.push(_('Custom direct domain list'));
    if (global.domain_proxy) proxyConditions.push(_('Custom proxy domain list'));
    if (dns.use_chn === '1') directConditions.push(_('CHN domain list'));
    if (dns.use_gfw === '1') proxyConditions.push(_('GFW domain list'));

    return {
        id: 'dns',
        title: _('DNS flow'),
        steps,
        branches: [
            {
                condition: _('Direct domain branch'),
                page: 'dns',
                detail: directConditions.join(' + ') || undefined,
                steps: getDnsUpstreamSteps(dns.direct_dns, dns.direct_dns_custom, shunt),
            },
            {
                condition: _('Proxy domain branch'),
                page: 'dns',
                detail: proxyConditions.join(' + ') || undefined,
                steps: getDnsUpstreamSteps(dns.proxy_dns, dns.proxy_dns_custom, shunt),
            },
        ],
    };
}

function getDefaultTrafficTarget(firewall: any, shunt: any): FlowStep[] {
    const port = firewall.shunt_port || '';
    if (!isPort(port)) return [{ title: _('Direct'), detail: _('Default shunt port is disabled'), tone: 'direct', page: 'firewall' }];
    if (port === shunt.shunt_listen_port) return getRoutingSteps(shunt, 'traffic');
    return getProxyTarget(port, _('Default shunt port'));
}

function getProxyTrafficTarget(firewall: any, shunt: any): FlowStep[] {
    if (isPort(firewall.proxy_port)) return getProxyTarget(firewall.proxy_port, _('Proxy port'));
    if (isPort(firewall.shunt_port)) return getDefaultTrafficTarget(firewall, shunt);
    return [{ title: _('No proxy target'), tone: 'warning', page: 'firewall' }];
}

function buildTrafficDiagram(global: any, firewall: any, dns: any, shunt: any): FlowDiagram {
    const protocols = (firewall.tproxy_proto || '').split(',').filter(Boolean).map((item: string) => item.toUpperCase());
    const sourceStep: FlowStep = {
        title: _('Client traffic'),
        page: 'firewall',
        detail: protocols.join(' + ') || _('No protocol selected'),
    };
    const aclStep: FlowStep = {
        title: getAclTitle(firewall),
        page: 'firewall',
        detail: [
            getAclDetail(firewall),
            firewall.proxy_local === '1' ? _('Router traffic included') : _('Router traffic excluded'),
        ].join('\n'),
    };
    const hasProxyPort = isPort(firewall.proxy_port);
    const hasShuntPort = isPort(firewall.shunt_port);

    if (!hasProxyPort && !hasShuntPort) {
        return {
            id: 'traffic',
            title: _('Traffic flow'),
            steps: [sourceStep, aclStep, { title: _('No proxy target'), tone: 'warning', page: 'firewall' }],
        };
    }

    const branches: FlowBranch[] = [];
    if (global.ip_proxy || (dns.dns_service === 'chinadns-ng' && global.domain_proxy)) {
        branches.push({ condition: _('Forced proxy address'), page: 'firewall', steps: getProxyTrafficTarget(firewall, shunt) });
    }
    if (global.ip_direct || (dns.dns_service === 'chinadns-ng' && global.domain_direct)) {
        branches.push({ condition: _('Forced direct address'), page: 'firewall', steps: [{ title: _('Direct'), tone: 'direct' }] });
    }
    if (dns.dns_service === 'chinadns-ng' && dns.use_gfw === '1') {
        branches.push({ condition: _('GFW domain set'), page: 'dns', steps: getProxyTrafficTarget(firewall, shunt) });
    }
    if (hasShuntPort && dns.dns_service === 'chinadns-ng' && dns.use_chn === '1') {
        branches.push({ condition: _('CHN domain set'), page: 'dns', steps: [{ title: _('Direct'), tone: 'direct' }] });
    }
    if (hasShuntPort && firewall.use_chnroute === '1') {
        branches.push({ condition: _('CHN route set'), page: 'firewall', steps: [{ title: _('Direct'), tone: 'direct' }] });
    }
    branches.push({ condition: _('No address rule matched'), steps: getDefaultTrafficTarget(firewall, shunt) });

    return {
        id: 'traffic',
        title: _('Traffic flow'),
        steps: [sourceStep, aclStep],
        branches,
        branchMode: 'ordered',
        branchDescription: _('Address rules are evaluated from top to bottom'),
    };
}

function buildConfigurationFlowPreview(): ConfigurationFlowPreview {
    const global = getFirstSection(LuciFlied.GLOBAL_SECTION_TYPE);
    const firewall = getFirstSection(LuciFlied.FIREWALL_SECTION_TYPE);
    const dns = getFirstSection(LuciFlied.DNS_SECTION_TYPE);
    const shunt = getFirstSection(LuciFlied.SHUNT_SECTION_TYPE);
    return {
        diagrams: [buildDnsDiagram(global, firewall, dns, shunt), buildTrafficDiagram(global, firewall, dns, shunt)],
    };
}

export { buildConfigurationFlowPreview };
