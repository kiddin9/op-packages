/** @typedef {import('../../../share/ucode/hijpass/types/rules.uc').RuleSources} RuleSources */
/** @typedef {import('../../../share/ucode/hijpass/types/rules.uc').RuleDownloadPlan} RuleDownloadPlan */
/** @typedef {import('../../../share/ucode/hijpass/types/rules.uc').GeoConversionPlan} GeoConversionPlan */
/** @typedef {import('../../../share/ucode/hijpass/types/rules.uc').DnsGeoPlan} DnsGeoPlan */
/** @typedef {import('../../../share/ucode/hijpass/types/rules.uc').GeoRequest} GeoRequest */
/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').UciSection} UciSection */
import { read } from 'hijpass.uci.read';
import * as fs from 'fs';
import { RULE_FILES } from 'hijpass.config.paths';
import { findHijpassSection, findShuntSection, findDnsSection, findRuleSection, filterShuntRouteRuleSections } from 'hijpass.config.sections';
import { list } from 'hijpass.config.values';
import { text, lines } from 'hijpass.common';
import { run } from 'hijpass.command.runtime';
import { parseCIDR } from 'hijpass.ip';
import { contains } from '../network/network.uc';

// RuleSource：key 为 UCI 下载地址字段，path 为目标文件，kind 为 domain/ip4/ip6/geo。
// 同类多个 URL 分别下载后合并去重；至少一个完整、有效来源成功后才替换旧文件。
/**
 * 定义可更新规则资源的类型和保存位置。
 * @returns {RuleSources} 以下载字段为键的目录，每项含 path 和 kind。
 */
function sources() {
	return {
		gfw_list: { path: RULE_FILES.gfw_list, kind: 'domain' }, chn_domain_list: { path: RULE_FILES.chn_list, kind: 'domain' },
		chn_v4_route: { path: RULE_FILES.chn_route, kind: 'ip4' }, chn_v6_route: { path: RULE_FILES.chn_route6, kind: 'ip6' },
		geosite: { path: '/usr/share/v2ray/geosite.dat', kind: 'geo' }, geoip: { path: '/usr/share/v2ray/geoip.dat', kind: 'geo' },
	};
}
/**
 * 从规则文本行中提取有效域名。
 * @param {string} line
 * @returns {string|null} 小写域名；空行、注释或无法识别的记录返回 null。
 */
export function domain(line) {
	line = lc(trim(line));
	if (!line || substr(line, 0, 1) == '#' || substr(line, 0, 1) == '!') {
		return null;
	}
	let m = match(line, /^server=\/([^/]+)\//);
	if (m) {
		line = m[1];
	}
	else if (substr(line, 0, 2) == '+.') {
		line = substr(line, 2);
	}
	else if (substr(line, 0, 4) == '@@||') {
		line = split(substr(line, 4), '^')[0];
	}
	else {
		line = replace(line, /^(domain|full):/, '');
	}
	return match(line, /^[a-z0-9.-]+[.][a-z]{2,}$/) ? line : null;
};
/**
 * 清洗域名或 IP 规则，过滤无效项并去重排序。
 * @param {string|null} text
 * @param {string} kind
 * @returns {string[]} 有效规则数组；没有有效项时为空数组。
 */
export function normalize(text, kind) {
	let result = [];
	for (let line in lines(text)) {
		if (kind == 'domain') {
			let value = domain(line);
			if (value) {
				push(result, value);
			}
		}
		else {
			let range = parseCIDR(line);
			if (range && range.family == (kind == 'ip4' ? 4 : 6)) {
				push(result, line);
			}
		}
	}
	return sort(uniq(result));
};

// UpdatePlan：timeout/retries 是已校验整数；jobs 含 key/kind/path/urls。
// GeoPlan：database/tag/input/output 只描述业务资源，不携带待执行的命令。
/**
 * 按更新动作和 UCI 设置整理规则下载任务。
 * @param {UciSection[]} config
 * @param {string} action
 * @returns {RuleDownloadPlan} 含 timeout（秒）、retries、enabled 和 jobs 的下载计划。
 */
export function updatePlan(config, action) {
    let settings = findRuleSection(config), catalog = sources();
    if (!settings) {
        die('rule section is missing');
    }
    let groups = { chnlist: ['chn_domain_list'], gfw: ['gfw_list'], chnroute: ['chn_v4_route', 'chn_v6_route'], geo: ['geosite', 'geoip'] };
    let selected = groups[action] || (action == 'all' || action == 'update' ? keys(catalog) : null);
    if (type(selected) != 'array') {
        die('unknown rule action');
    }
    let timeout = int(settings.download_timeout || '120'), retries = int(settings.retry_count || '3');
    if (!match(settings.download_timeout || '120', /^[0-9]+$/) || !match(settings.retry_count || '3', /^[0-9]+$/)
        || type(timeout) != 'int' || type(retries) != 'int' || timeout < 1 || timeout > 600 || retries < 1 || retries > 10) {
        die('invalid download timeout or retry count');
    }
    return { timeout, retries, enabled: findHijpassSection(config)?.enabled == '1',
        jobs: map(selected, key => ({ key, ...catalog[key], urls: list(settings[key]) })) };
};
/**
 * 收集分流中的 Geo 引用，安排本地 SRS 转换任务。
 * @param {UciSection[]} config
 * @returns {GeoConversionPlan} {jobs}，每项含 database、tag、input 和 output。
 */
export function geoPlan(config) {
    let jobs = [];
    for (let database in ['geoip', 'geosite']) {
        let tags = [], key = database == 'geoip' ? 'ip_list' : 'domain_list';
        for (let rule in filterShuntRouteRuleSections(config)) {
            if (rule.enabled != '1') {
                continue;
            }
            for (let line in lines(rule[key])) {
                if (substr(line, 0, length(database) + 1) == database + ':') {
                    push(tags, substr(line, length(database) + 1));
                }
            }
        }
        for (let tag in uniq(tags)) {
            if (!match(tag, /^[A-Za-z0-9_.:@!-]+$/)) {
                die('invalid Geo tag');
            }
            push(jobs, { database, tag, input: `/usr/share/v2ray/${database}.dat`, output: `/etc/hijpass/ruleset/${database}-${tag}.srs` });
        }
    }
    return { jobs };
};
/**
 * 收集 chinadns-ng 规则需要提取的 Geo 域名。
 * @param {UciSection[]} config
 * @returns {DnsGeoPlan} {jobs}，每项含 value 和 output；其他 DNS 模式下 jobs 为空。
 */
export function dnsPlan(config) {
    if (findDnsSection(config)?.dns_service != 'chinadns-ng') {
        return { jobs: [] };
    }
    let jobs = [];
    for (let kind in ['proxy', 'direct']) {
        let tags = [];
        for (let line in lines(fs.readfile(RULE_FILES[`domain_${kind}`]))) {
            if (substr(line, 0, 8) == 'geosite:') {
                push(tags, substr(line, 8));
            }
        }
        let value = join(',', uniq(tags));
        if (value && !match(value, /^[A-Za-z0-9_.:@,\/!-]+$/)) {
            die('invalid Geo argument');
        }
        push(jobs, { value, output: `/tmp/hijpass/domain-${kind}-geo.txt` });
    }
    return { jobs };
};
/**
 * 校验 Geo 查询或提取请求，确定数据文件和标签。
 * @param {string} action
 * @param {string} kind
 * @param {string[]} args
 * @returns {GeoRequest} {kind, extract, input, values}。
 */
export function geoRequest(action, kind, args) {
    if (index(['geoip', 'geosite'], kind) < 0 || !length(args)) {
        die('invalid geo type or argument');
    }
    for (let arg in args) {
        if (!match(arg, /^[A-Za-z0-9_.:@,\/!-]+$/)) {
            die('invalid Geo argument');
        }
    }
    let extract = action == '-e' || action == '--extract';
    if (!extract && action != '-l' && action != '--lookup') {
        die('unknown Geo action');
    }
    return { kind, extract, input: `/usr/share/v2ray/${kind}.dat`, values: args };
};
/**
 * 判断域名是否与规则相同，或属于规则的子域。
 * @param {string} host
 * @param {string} rule
 * @returns {boolean} 匹配时为 true。
 */
function suffix(host, rule) { return host == rule || substr(host, -length(rule) - 1) == '.' + rule; }
/**
 * 查询目标 IP 或域名命中了哪些规则文件。
 * @param {string} target
 * @returns {string} 去重排序的文件名，每行一个；无命中时只返回换行。
 */
export function queryFiles(target) {
	if (!match(target || '', /^[A-Za-z0-9._:\/-]{1,255}$/)) {
		die('invalid query');
	}
	let ip = iptoarr(target), matched = [];
	for (let path in fs.glob('/etc/hijpass/rules/*') || []) {
		if (fs.stat(path)?.type != 'file') {
			continue;
		}
		let name = fs.basename(path);
		if (ip) {
			if (!match(name, /^(chn-route|ip)/)) {
				continue;
			}
		}
		else if (!match(name, /(list[.]txt$|^domain)/)) {
			continue;
		}
		if (length(filter(lines(fs.readfile(path)), line => ip ? contains(target, line) : suffix(lc(target), lc(line))))) {
			push(matched, name);
		}
	}
	return join('\n', sort(uniq(matched))) + '\n';
};
/**
 * 按配置顺序查找首条匹配的分流规则。
 * @param {UciSection[]} sections
 * @param {string} target
 * @returns {string} 命中规则及出口说明；无命中时返回全局默认策略说明。
 */
export function routeMatch(sections, target, geoTags) {
	if (!match(target || '', /^[A-Za-z0-9._:\/-]{1,255}$/)) {
		die('invalid query');
	}
	let ip = !!iptoarr(target), tags = [], loaded = false;
	for (let rule in filterShuntRouteRuleSections(sections)) {
		if (rule.enabled != '1') {
			continue;
		}
		for (let line in lines(rule[ip ? 'ip_list' : 'domain_list'])) {
			if (substr(line, 0, 9) == 'rule-set:') {
				continue;
			}
			let matched = false, kind = ip ? 'geoip' : 'geosite';
			if (substr(line, 0, length(kind) + 1) == kind + ':') {
				if (!loaded) {
					tags = split(trim(geoTags || '') || '', /[ \t\n]+/);
					loaded = true;
				}
				matched = index(tags, substr(line, length(kind) + 1)) >= 0;
			}
			else if (ip) {
				matched = contains(target, line);
			}
			else if (substr(line, 0, 5) == 'full:') {
				matched = lc(target) == lc(substr(line, 5));
			}
			else if (substr(line, 0, 7) == 'domain:') {
				matched = suffix(lc(target), lc(substr(line, 7)));
			}
			else if (substr(line, 0, 7) == 'regexp:') {
				matched = !!match(target, regexp(substr(line, 7), 'i'));
			}
			else {
				matched = index(lc(target), lc(line)) >= 0;
			}
			if (matched) {
				return `规则名称 (Name) : ${rule.name || 'Unnamed'}\n匹配类型 (Type) : ${ip ? 'IP' : '域名'}\n匹配内容 (Item) : ${line}\n代理策略 (Node) : ${rule.proxy_node || 'default'}\n`;
			}
		}
	}
	return `未匹配到任何自定义规则，除去协议、端口等规则外，将使用全局默认策略\n\n规则名称 (Name) : 全局默认\n匹配类型 (Type) : ${ip ? 'IP' : '域名'}\n匹配内容 (Item) : * (全部)\n代理策略 (Node) : ${findShuntSection(sections)?.default_proxy_node || ''}\n`;
};

/**
 * 处理规则更新计划、Geo 转换和规则查询的数据请求。
 * @returns {null} 结果写入 stdout，包括计划、规则文本、查询说明或更新状态。
 */
export function main() { run(ARGV,
    /**
     * @param {string[]} args
     * @param {string|null} configDirectory
     */
    function(args, configDirectory) {
    let action = shift(args);
    if (action == 'busy') return { success: false, code: 'UPDATE_BUSY', message: 'Rule update already running' };
    if (action == 'plan') {
        let config = read('hijpass', configDirectory);
        return updatePlan(config, args[0] || '');
    }
    if (action == 'geo-plan') {
        return geoPlan(read('hijpass', configDirectory));
    }
    if (action == 'dns-plan') {
        return dnsPlan(read('hijpass', configDirectory));
    }
    if (action == 'geo-request') {
        let mode = shift(args), kind = shift(args);
        return geoRequest(mode || '', kind || '', args);
    }
    if (action == 'normalize') {
        return join('\n', normalize(text(args[1]), args[0] || '')) + '\n';
    }
    if (action == 'merge') {
        return join('\n', sort(uniq(lines(text(args[0]))))) + '\n';
    }
    if (action == 'query') {
        return queryFiles(args[0] || '');
    }
    if (action == 'match-plan') {
        let config = read('hijpass', configDirectory), target = args[0] || '';
        if (!match(target || '', /^[A-Za-z0-9._:\/-]{1,255}$/)) {
            die('invalid query');
        }
        let ip = !!iptoarr(target), kind = ip ? 'geoip' : 'geosite';
        let lookup = length(filter(filterShuntRouteRuleSections(config), rule => rule.enabled == '1' && length(filter(lines(rule[ip ? 'ip_list' : 'domain_list']), line => substr(line, 0, length(kind) + 1) == kind + ':')))) > 0;
        return { kind, lookup };
    }
    if (action == 'match') {
        let config = read('hijpass', configDirectory);
        return routeMatch(config, args[0] || '', fs.stdin.read('all'));
    }
    if (action == 'result') {
        let failed = args;
        return { success: !length(failed), ...(length(failed) ? { failed } : {}) };
    }
    die('unknown rules data action');
});
};
