import { LuciFlied } from "../../../enum/hijpass";
import {
    RouteSection,
    RuleDTO,
    ShuntRouteRule
} from "../../../module/luci";
import uci from "uci";
import { UciUtils } from "../../base/luci/uci";

type RuleListSource = Pick<ShuntRouteRule, 'domainList' | 'ipList'>
    & Partial<Pick<ShuntRouteRule, 'network' | 'protocol' | 'port' | 'portRange'>>;

const ShuntUtils = {
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
                    // 预检只记录是否存在规则集引用，路径、格式和 tag 交给后端解析。
                    result.ruleSet.push(line);
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
                    // 预检只记录是否存在规则集引用，路径、格式和 tag 交给后端解析。
                    result.ruleSet.push(line);
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
