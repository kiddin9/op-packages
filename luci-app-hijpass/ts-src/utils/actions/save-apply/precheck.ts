import { CORE_TYPE, LuciFlied, PROXY_TYPE, normalizeCoreType, ShuntTag } from "../../../enum/hijpass";
import uci from "uci";
import ui from "ui";
import { NotificationUtils } from "../../base/luci/notification";
import { FactoryType } from "../../../core/adapter";
import { ShuntUtils } from "../../feature/shunt/section";
import { MAX_PROXY_CHAIN_NODES, ProxyChainUtils } from "../../feature/proxy/chain";
import { FirewallDnsForwardUtils } from "../../feature/firewall/dns-forward";

const XRAY_ROUTE_PROTOCOLS = ['http', 'tls', 'quic', 'bittorrent'];
const XRAY_TLS_PROTOCOLS = ['hysteria2', 'vless'];

function normalizeList(value: any): string[] {
    if (!value) {
        return [];
    }
    return Array.isArray(value) ? value.filter((item: string) => item) : [value];
}

function isSpecialProxyNode(node: string) {
    return node === ShuntTag.DIRECT_OUTBOUND_TAG
        || node === ShuntTag.BLOCK_OUTBOUND_TAG;
}

function reportWarnings(title: string, warnings: string[]): boolean {
    if (warnings.length === 0) {
        return true;
    }

    NotificationUtils.warning(title, warnings.join('\n'), 8000);
    return false;
}

function isTemplateShuntActive() {
    return uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'enabled') !== '0'
        && uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'config_type') === 'tmpl';
}

function checkMissingProxyRefs() {
    const existingNodes = new Set<string>();
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section: any) {
        if (section.name) {
            existingNodes.add(section.name);
        }
    });

    const warnings: string[] = [];
    function checkRef(ref: string, message: string) {
        if (ref && !isSpecialProxyNode(ref) && !existingNodes.has(ref)) {
            warnings.push(message);
        }
    }

    const defaultNode = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'default_proxy_node');
    if (!defaultNode) {
        warnings.push(_('Default global exit is not configured'));
    } else {
        checkRef(defaultNode, _('Default global exit "%s" does not exist').format(defaultNode));
    }

    const rulesetNode = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'ruleset_out_node');
    checkRef(rulesetNode, _('Rule-set exit "%s" does not exist').format(rulesetNode));

    uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_ROUTE_RULE_TYPE, function (section: any) {
        if (section.enabled !== '1') {
            return;
        }
        const ruleName = section.name || section['.name'];
        if (section.ip_version_split === '1') {
            if (!section.proxy_node_v4) {
                warnings.push(_('Route rule "%s" IPv4 proxy node is not configured').format(ruleName));
            } else {
                checkRef(section.proxy_node_v4, _('Route rule "%s" IPv4 proxy node "%s" does not exist').format(ruleName, section.proxy_node_v4));
            }
            if (!section.proxy_node_v6) {
                warnings.push(_('Route rule "%s" IPv6 proxy node is not configured').format(ruleName));
            } else {
                checkRef(section.proxy_node_v6, _('Route rule "%s" IPv6 proxy node "%s" does not exist').format(ruleName, section.proxy_node_v6));
            }
            return;
        }

        if (!section.proxy_node) {
            warnings.push(_('Route rule "%s" proxy node is not configured').format(ruleName));
        } else {
            checkRef(section.proxy_node, _('Route rule "%s" proxy node "%s" does not exist').format(ruleName, section.proxy_node));
        }
    });

    return reportWarnings(_('Configuration contains missing proxy nodes'), warnings);
}

function checkDisabledProxyRefs() {
    const disabledNodes = new Set<string>();
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section: any) {
        if (section.enabled !== '1' && section.name) {
            disabledNodes.add(section.name);
        }
    });

    if (disabledNodes.size === 0) {
        return true;
    }

    const warnings: string[] = [];

    const defaultNode = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'default_proxy_node');
    if (defaultNode && disabledNodes.has(defaultNode)) {
        warnings.push(_('Default global exit "%s" is not enabled').format(defaultNode));
    }

    const rulesetNode = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'ruleset_out_node');
    if (rulesetNode && disabledNodes.has(rulesetNode)) {
        warnings.push(_('Rule-set exit "%s" is not enabled').format(rulesetNode));
    }

    uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_ROUTE_RULE_TYPE, function (section: any) {
        if (section.enabled !== '1') {
            return;
        }
        const ruleName = section.name || section['.name'];
        if (section.ip_version_split === '1') {
            if (section.proxy_node_v4 && disabledNodes.has(section.proxy_node_v4)) {
                warnings.push(_('Route rule "%s" IPv4 proxy node "%s" is not enabled').format(ruleName, section.proxy_node_v4));
            }
            if (section.proxy_node_v6 && disabledNodes.has(section.proxy_node_v6)) {
                warnings.push(_('Route rule "%s" IPv6 proxy node "%s" is not enabled').format(ruleName, section.proxy_node_v6));
            }
        } else if (section.proxy_node && disabledNodes.has(section.proxy_node)) {
            warnings.push(_('Route rule "%s" proxy node "%s" is not enabled').format(ruleName, section.proxy_node));
        }
        if (section.dns_proxy_node && disabledNodes.has(section.dns_proxy_node)) {
            warnings.push(_('Route rule "%s" DNS exit node "%s" is not enabled').format(ruleName, section.dns_proxy_node));
        }
    });

    return reportWarnings(_('Configuration contains disabled nodes'), warnings);
}

function checkLoadBalanceRefs() {
    const sections = ProxyChainUtils.getProxySectionMap();
    const warnings: string[] = [];

    sections.forEach((section: any) => {
        if (section.enabled !== '1' || section.type !== PROXY_TYPE.LOAD_BALANCE) return;

        const nodeName = ProxyChainUtils.getProxyName(section);
        const core = normalizeCoreType(section.core);
        if (core !== CORE_TYPE.SING_BOX && core !== CORE_TYPE.XRAY) {
            warnings.push(_('Load balancing node "%s" has an unsupported backend core').format(nodeName));
        }

        const members = ProxyChainUtils.normalizeProxyNodeList(section.member_node);
        if (members.length === 0) {
            warnings.push(_('Load balancing node "%s" has no member nodes').format(nodeName));
            return;
        }

        const duplicateMembers = members.filter((member, index) => members.indexOf(member) !== index);
        if (duplicateMembers.length > 0) {
            warnings.push(_('Load balancing node "%s" contains duplicate member nodes: %s')
                .format(nodeName, Array.from(new Set(duplicateMembers)).join(', ')));
        }

        members.forEach((memberName) => {
            if (memberName === nodeName) {
                warnings.push(_('Load balancing node "%s" cannot include itself').format(nodeName));
                return;
            }

            const member = sections.get(memberName);
            if (!member) {
                warnings.push(_('Load balancing node "%s" member node "%s" does not exist')
                    .format(nodeName, memberName));
                return;
            }
            if (member.type === PROXY_TYPE.LOAD_BALANCE) {
                warnings.push(_('Load balancing node "%s" cannot contain load balancing member "%s"')
                    .format(nodeName, memberName));
            }
            if (member.enabled !== '1') {
                warnings.push(_('Load balancing node "%s" member node "%s" is not enabled')
                    .format(nodeName, memberName));
            }
            if (!ProxyChainUtils.isPort(member.socks_port)) {
                warnings.push(_('Load balancing node "%s" member node "%s" has no valid SOCKS port configured')
                    .format(nodeName, memberName));
            }
        });

        if (section.fallback_tag && members.indexOf(section.fallback_tag) < 0) {
            warnings.push(_('Load balancing node "%s" fallback node "%s" is not a member')
                .format(nodeName, section.fallback_tag));
        }
    });

    return reportWarnings(_('Configuration contains invalid load balancing nodes'), warnings);
}

function checkProxyChainRefs() {
    const sections = ProxyChainUtils.getProxySectionMap();
    const warnings: string[] = [];

    sections.forEach((section: any) => {
        if (section.enabled !== '1'
            || section.type === PROXY_TYPE.LOAD_BALANCE
            || !section.upstream_proxy_node) {
            return;
        }

        const nodeName = ProxyChainUtils.getProxyName(section);
        const upstreamName = section.upstream_proxy_node;
        const upstreamSection = sections.get(upstreamName);

        if (!upstreamSection) {
            warnings.push(_('Proxy node "%s" upstream proxy node "%s" does not exist').format(nodeName, upstreamName));
            return;
        }
        if (upstreamSection.enabled !== '1') {
            warnings.push(_('Proxy node "%s" upstream proxy node "%s" is not enabled').format(nodeName, upstreamName));
        }
        if (!ProxyChainUtils.isPort(upstreamSection.socks_port)) {
            warnings.push(_('Proxy node "%s" upstream proxy node "%s" has no valid SOCKS port configured').format(nodeName, upstreamName));
        }

        const result = ProxyChainUtils.collectProxyChain(nodeName, sections);
        if (!result.cycle && result.chain.length > MAX_PROXY_CHAIN_NODES) {
            warnings.push(_('Proxy node "%s" nesting chain exceeds %d nodes: %s')
                .format(nodeName, MAX_PROXY_CHAIN_NODES, result.chain.join(' -> ')));
        }
    });

    const dependencyCycle = ProxyChainUtils.findProxyDependencyCycle(sections);
    if (dependencyCycle) {
        warnings.push(_('Proxy node dependency chain has a cycle: %s').format(dependencyCycle.join(' -> ')));
    }

    return reportWarnings(_('Configuration contains invalid upstream proxy nodes'), warnings);
}

function checkInvalidDnsNodeRefs() {
    const existingDnsNodes = new Set<string>();
    const disabledDnsNodes = new Set<string>();
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_DNS_NODE_TYPE, function (section: any) {
        if (!section.tag) {
            return;
        }
        existingDnsNodes.add(section.tag);
        if (section.enabled === '0') {
            disabledDnsNodes.add(section.tag);
        }
    });

    const missingWarnings: string[] = [];
    const disabledWarnings: string[] = [];
    function checkRef(ref: string, label: string) {
        if (!ref) {
            return;
        }
        if (!existingDnsNodes.has(ref)) {
            missingWarnings.push(_('%s "%s" does not exist').format(label, ref));
            return;
        }
        if (disabledDnsNodes.has(ref)) {
            disabledWarnings.push(_('%s "%s" is not enabled').format(label, ref));
        }
    }

    const defaultDnsNode = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'default_dns_node');
    if (!defaultDnsNode) {
        missingWarnings.push(_('Default global DNS is not configured'));
    } else {
        checkRef(defaultDnsNode, _('Default global DNS'));
    }
    checkRef(
        uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'ruleset_dns_node'),
        _('Rule-set DNS')
    );
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_ROUTE_RULE_TYPE, function (section: any) {
        if (section.enabled !== '1') {
            return;
        }
        checkRef(section.dns_node, _('Route rule "%s" DNS node').format(section.name || section['.name']));
    });

    return reportWarnings(_('Configuration contains missing DNS nodes'), missingWarnings)
        && reportWarnings(_('Configuration contains disabled DNS nodes'), disabledWarnings);
}

function checkMissingDnsExitRefs() {
    const existingNodeNames = new Set<string>();
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section: any) {
        if (section.name) existingNodeNames.add(section.name);
    });

    const shuntType = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'type');
    const rulesetConvert = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'ruleset_convert');
    const missingDnsExits: string[] = [];
    ShuntUtils.getRouteSection().rules.forEach(function (section: any) {
        if (section.enabled !== '1') {
            return;
        }
        const dnsExit = section.dnsProxyNode;
        const ruleName = section.name || _('Unnamed Rule');
        if (routeRuleRequiresDnsExit(section, shuntType, rulesetConvert) && !dnsExit) {
            missingDnsExits.push(_('Route rule "%s" uses IPv4/IPv6 split and must specify a DNS exit node').format(ruleName));
            return;
        }
        if (dnsExit && dnsExit !== ShuntTag.DIRECT_OUTBOUND_TAG && !existingNodeNames.has(dnsExit)) {
            missingDnsExits.push(_('Route rule "%s" DNS exit node "%s" does not exist').format(ruleName, dnsExit));
        }
    });

    return reportWarnings(_('Configuration contains invalid DNS exit nodes'), missingDnsExits);
}

function routeRuleRequiresDnsExit(rule: any, shuntType: string, rulesetConvert: string) {
    if (rule.ipVersionSplit !== '1') {
        return false;
    }

    const ruleDTO = ShuntUtils.parseRuleList(rule);
    if (shuntType === FactoryType.XRAY) {
        return ruleDTO.containDomain() || ruleDTO.geoSite.length > 0;
    }

    return ruleDTO.containDomain()
        || ruleDTO.containRuleSet()
        || (rulesetConvert === '1' && ruleDTO.geoSite.length > 0);
}

function checkFirewallPortTargets() {
    const enabledProxyPorts = new Set<string>();
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section: any) {
        if (section.enabled === '1' && section.listen_port) {
            enabledProxyPorts.add(section.listen_port);
        }
    });

    const proxyPort = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.FIREWALL_SECTION_TYPE, 'proxy_port');
    const shuntPort = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.FIREWALL_SECTION_TYPE, 'shunt_port');
    const shuntEnabled = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'enabled') !== '0';
    const shuntListenPort = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'shunt_listen_port');
    const warnings: string[] = [];

    if (proxyPort && !enabledProxyPorts.has(proxyPort)) {
        warnings.push(_('Firewall proxy port %s does not reference an enabled proxy node').format(proxyPort));
    }
    if (shuntPort
        && !enabledProxyPorts.has(shuntPort)
        && !(shuntEnabled && shuntListenPort === shuntPort)) {
        warnings.push(_('Firewall shunt port %s does not reference an enabled proxy node or shunt service').format(shuntPort));
    }

    return reportWarnings(_('Configuration conflict'), warnings);
}

function checkFirewallDnsForwardTarget() {
    const error = FirewallDnsForwardUtils.validateSource(FirewallDnsForwardUtils.getSource());
    return error === true || reportWarnings(_('Configuration conflict'), [error]);
}

function checkDnsRoutingTargets() {
    const dnsService = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE, 'dns_service');
    if (dnsService !== 'chinadns-ng') {
        return true;
    }

    const routingTarget = FirewallDnsForwardUtils.getRoutingTarget();
    const routingServer = routingTarget.port ? '127.0.0.1#' + routingTarget.port : '';
    const warnings: string[] = [];
    [
        ['direct_dns', _('Direct Domain DNS')],
        ['proxy_dns', _('Proxy Domain DNS')],
    ].forEach(([option, label]) => {
        const value = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE, option);
        if (!value || value === 'dnsmasq' || value === 'system' || value === 'custom') {
            return;
        }
        if (!routingTarget.available || value !== routingServer) {
            warnings.push(_('%s references an unavailable Core DNS port').format(label));
        }
    });

    return reportWarnings(_('Configuration conflict'), warnings);
}

function checkXrayRouteProtocols() {
    const shuntType = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'type');
    if (shuntType !== FactoryType.XRAY) {
        return true;
    }

    const warnings: string[] = [];
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_ROUTE_RULE_TYPE, function (section: any) {
        if (section.enabled !== '1') {
            return;
        }

        const unsupported = normalizeList(section.protocol)
            .filter((protocol) => XRAY_ROUTE_PROTOCOLS.indexOf(protocol) === -1);
        if (unsupported.length > 0) {
            warnings.push(_('Route rule "%s" contains protocols unsupported by Xray: %s')
                .format(section.name || section['.name'], unsupported.join(', ')));
        }
    });

    if (warnings.length > 0) {
        NotificationUtils.warning(
            _('Unsupported Xray protocol configuration'),
            warnings.join('\n') + '\n' + _('Xray route protocol only supports: %s').format(XRAY_ROUTE_PROTOCOLS.join(', ')),
            8000
        );
        return false;
    }

    return true;
}

function checkXrayDnsServerTypes() {
    const shuntType = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'type');
    if (shuntType !== FactoryType.XRAY) {
        return true;
    }

    const warnings: string[] = [];
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_DNS_NODE_TYPE, function (section: any) {
        if (section.enabled === '0') {
            return;
        }
        if (section.type === 'tls') {
            warnings.push(_('DNS node "%s" uses TLS, which is only supported by sing-box').format(section.tag || section['.name']));
        }
    });

    return reportWarnings(_('Unsupported Xray DNS configuration'), warnings);
}

function checkXrayTlsInsecure() {
    const warnings: string[] = [];
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section: any) {
        if (section.enabled !== '1' || normalizeCoreType(section.core) !== FactoryType.XRAY || section.tls_insecure !== '1') {
            return;
        }
        if (XRAY_TLS_PROTOCOLS.indexOf(section.type) !== -1) {
            warnings.push(_('Proxy node "%s" enables insecure TLS, which is not supported by current Xray').format(section.name || section['.name']));
        }
    });

    return reportWarnings(_('Unsupported Xray TLS configuration'), warnings);
}

function confirmWarning(title: string, description: string, warnings: string[]) {
    return new Promise<boolean>((resolve) => {
        ui.showModal(title, [
            E('div', {
                style: [
                    'box-sizing:border-box',
                    'width:100%',
                    'margin:0 0 14px 0',
                    'padding:14px 16px',
                    'border-radius:4px',
                    'background:rgba(127,127,127,0.08)',
                    'line-height:1.55'
                ].join(';')
            }, [
                E('div', {style: 'margin:0 0 12px 0'}, description),
                E('div', {style: 'display:flex;flex-direction:column;gap:6px;margin:0'}, warnings.map((warning) => (
                    E('div', {style: 'margin:0;word-break:break-word'}, warning)
                )))
            ]),
            E('div', {style: 'display:flex;justify-content:flex-end;gap:10px;margin:0'}, [
                E('button', {
                    class: 'btn cbi-button',
                    click: function (ev: Event) {
                        ev.preventDefault();
                        ui.hideModal();
                        resolve(false);
                    }
                }, _('Cancel')),
                E('button', {
                    class: 'btn cbi-button-action',
                    click: function (ev: Event) {
                        ev.preventDefault();
                        ui.hideModal();
                        resolve(true);
                    }
                }, _('Continue Apply'))
            ])
        ]);
    });
}

function getSkippedRouteRuleMessage(rule: any, shuntType: string, rulesetConvert: string) {
    const ruleDTO = ShuntUtils.parseRuleList(rule);
    const ruleName = rule.name || rule['.name'] || _('Unnamed Rule');
    const canConvertGeoRule = rulesetConvert === '1';

    if (shuntType === FactoryType.XRAY) {
        if (ruleDTO.isEmpty('geo')) {
            return _('Route rule "%s" has no valid match conditions for Xray').format(ruleName);
        }
        if (ruleDTO.containRuleSet()
            && !ruleDTO.containDomain()
            && !ruleDTO.containIp()
            && !ruleDTO.containGeo()) {
            return _('Route rule "%s" only contains rule-set target conditions unsupported by Xray').format(ruleName);
        }
        return null;
    }

    if (shuntType === FactoryType.SING_BOX) {
        if (!canConvertGeoRule && ruleDTO.containGeo()) {
            ruleDTO.geoSite = [];
            ruleDTO.geoIp = [];
            if (!ruleDTO.containDomain() && !ruleDTO.containIp() && !ruleDTO.containRuleSet()) {
                return _('Route rule "%s" has no target conditions for sing-box after removing unconverted geosite/geoip').format(ruleName);
            }
        }
        if (ruleDTO.isEmpty('set') && !(canConvertGeoRule && ruleDTO.containGeo())) {
            return _('Route rule "%s" has no valid match conditions for sing-box').format(ruleName);
        }
    }

    return null;
}

function confirmSkippedRouteRules() {
    const shuntType = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'type');
    const rulesetConvert = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'ruleset_convert');
    const warnings: string[] = [];

    ShuntUtils.getRouteSection().rules.forEach((rule) => {
        if (rule.enabled !== '1') {
            return;
        }

        const message = getSkippedRouteRuleMessage(rule, shuntType, rulesetConvert);
        if (message) warnings.push(message);
    });

    if (warnings.length > 0) {
        return confirmWarning(
            _('Some route rules will be skipped'),
            _('The following rules have no valid configuration for the current core and options, so they will not be written to the final configuration. Continue applying the configuration?'),
            warnings
        );
    }

    return true;
}

const PrecheckUtils = {
    runSaveApplyPrechecks: async function () {
        if (!checkProxyChainRefs()
            || !checkLoadBalanceRefs()
            || !checkXrayTlsInsecure()
            || !checkFirewallPortTargets()
            || !checkFirewallDnsForwardTarget()
            || !checkDnsRoutingTargets()) {
            return false;
        }

        if (!isTemplateShuntActive()) {
            return true;
        }

        return checkMissingProxyRefs()
            && checkDisabledProxyRefs()
            && checkInvalidDnsNodeRefs()
            && checkMissingDnsExitRefs()
            && await confirmSkippedRouteRules()
            && checkXrayRouteProtocols()
            && checkXrayDnsServerTypes();
    },
}

export { PrecheckUtils }
