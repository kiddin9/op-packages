import { LuciFlied } from "../../../enum/hijpass";
import {
    DnsNode,
    DnsSection,
    RouteSection,
    RuleDTO,
    ShuntRouteRuleVariant,
    ShuntRouteRule,
    ShuntSection
} from "../../../module/luci";
import uci from "uci";
import { UciUtils } from "../../base/luci/uci";

type RuleListSource = Pick<ShuntRouteRule, 'domainList' | 'ipList'>
    & Partial<Pick<ShuntRouteRule, 'network' | 'protocol' | 'port' | 'portRange'>>;

function parseRuleSetPath(line: string, type: string) {
    let pathOrUrl = line.substring(type === 'remote' ? 16 : 15);
    let filename = pathOrUrl.split('/').pop();
    let tag = filename.substring(0, filename.lastIndexOf('.')) || filename;
    let format = (type === 'remote' ? pathOrUrl : filename).endsWith('srs') ? 'binary' : 'source';
    return { tag: tag, type: type, format: format, pathOrUrl: pathOrUrl }
}

const ShuntUtils = {
    getShuntSection: function () {
        let shuntSection = new ShuntSection();
        let uSection = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE);
        UciUtils.transFromUci(shuntSection, uSection)
        shuntSection.dns = ShuntUtils.getDnsSection()
        shuntSection.route = ShuntUtils.getRouteSection()
        return shuntSection;
    },

    getRouteSection: function () {
        let shuntSection = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE)
        let routeSection = new RouteSection();
        UciUtils.transFromUci(routeSection, shuntSection)

        uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_ROUTE_RULE_TYPE, function (section) {
            let rule = new ShuntRouteRule()
            UciUtils.transFromUci(rule, section)
            routeSection.rules.push(rule)
        })
        return routeSection;
    },

    getRouteRuleVariants: function (rule: ShuntRouteRule): ShuntRouteRuleVariant[] {
        if (rule.ipVersionSplit !== '1') {
            return [{ rule, proxyNode: rule.proxyNode }];
        }

        const variants: ShuntRouteRuleVariant[] = [];
        if (rule.proxyNodeV4) {
            const v4Rule = Object.assign(new ShuntRouteRule(), rule);
            v4Rule.name = rule.name ? rule.name + '-ipv4' : rule.name;
            v4Rule.proxyNode = rule.proxyNodeV4;
            variants.push({ rule: v4Rule, proxyNode: rule.proxyNodeV4, ipVersion: 4 });
        }
        if (rule.proxyNodeV6) {
            const v6Rule = Object.assign(new ShuntRouteRule(), rule);
            v6Rule.name = rule.name ? rule.name + '-ipv6' : rule.name;
            v6Rule.proxyNode = rule.proxyNodeV6;
            variants.push({ rule: v6Rule, proxyNode: rule.proxyNodeV6, ipVersion: 6 });
        }
        return variants;
    },

    getDnsSection: function () {
        let shuntSection = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE)
        let dnsSection = new DnsSection();
        dnsSection.nodes = []
        UciUtils.transFromUci(dnsSection, shuntSection)

        uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_DNS_NODE_TYPE, function (section) {
            if (section.enabled === '0') {
                return;
            }
            let server = new DnsNode()
            UciUtils.transFromUci(server, section)
            dnsSection.nodes.push(server)
        })
        return dnsSection;
    },

    /**
     * 解析规则列表，根据前缀分类
     * @returns {RuleDTO} 包含不同类型规则的对象
     */
    parseRuleList: function (rule: RuleListSource): RuleDTO {
        // 初始化结果对象
        let result = new RuleDTO();
        let domainRules = rule.domainList
        let ipRules = rule.ipList

        result.network = rule.network ? rule.network : []
        result.protocol = rule.protocol ? rule.protocol : []

        if (rule.port) {
            result.port = rule.port
                .map(port => parseInt(port, 10))
                .filter(port => !isNaN(port))
        }

        if (rule.portRange) {
            result.portRange = rule.portRange
                .map(range => range.replace('-', ':'))
                .filter(range => range.length > 0)
        }

        if (domainRules && domainRules.trim() !== '') {
            // 按行分割并处理
            let lines = domainRules.split('\n');

            for (let line of lines) {
                line = line.trim();

                // 跳过空行和注释
                if (line === '' || line.startsWith('#')) {
                    continue;
                }

                // 处理rule-set（域名和IP通用）
                if (line.startsWith('rule-set:')) {
                    let type = line.startsWith('rule-set:remote:') ? 'remote' : 'local';
                    let ruleSet = parseRuleSetPath(line, type);
                    result.ruleSet.push(ruleSet);
                    continue;
                }

                // 处理域名特有规则
                if (line.startsWith('regexp:')) {
                    result.domainRegex.push(line.substring(7));
                } else if (line.startsWith('domain:')) {
                    result.domainSuffix.push(line.substring(7));
                } else if (line.startsWith('full:')) {
                    result.domain.push(line.substring(5));
                } else if (line.startsWith('geosite:')) {
                    result.geoSite.push(line)
                } else {
                    result.domainKeyword.push(line);
                }
            }
        }

        if (ipRules && ipRules.trim() !== '') {
            // 按行分割并处理
            let lines = ipRules.split('\n');
            for (let line of lines) {
                line = line.trim();

                // 跳过空行和注释
                if (line === '' || line.startsWith('#')) {
                    continue;
                }

                // 处理rule-set（域名和IP通用）
                if (line.startsWith('rule-set:')) {
                    let type = line.startsWith('rule-set:remote:') ? 'remote' : 'local';
                    let ruleSet = parseRuleSetPath(line, type);
                    result.ruleSet.push(ruleSet);
                    continue;
                }

                if (line.startsWith('geoip:')) {
                    result.geoIp.push(line)
                } else {
                    result.ipCidr.push(line);
                }
            }
        }

        return result;
    },

}

export { ShuntUtils }
