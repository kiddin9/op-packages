/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').DnsSection} DnsSection */
/** @typedef {import('../../../share/ucode/hijpass/types/service.uc').ServiceInstance} ServiceInstance */
/** @typedef {import('../../../share/ucode/hijpass/types/service.uc').ChinadnsOptions} ChinadnsOptions */
/** @typedef {import('../../../share/ucode/hijpass/types/service.uc').DnsmasqOptions} DnsmasqOptions */
/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').UciSection} UciSection */
import * as fs from 'fs';
import { RULE_FILES } from 'hijpass.config.paths';
import { read } from 'hijpass.uci.read';
import { findDnsSection, findDnsmasqSection } from 'hijpass.config.sections';
import { port } from 'hijpass.config.values';
import { domain } from '../rules/rules.uc';
import { lines, atomic, renderTemplate } from 'hijpass.common';
import { logger } from '../maintenance/logs.uc';

// ChinadnsOptions：listenPort 为监听端口，direct/proxy 为解析后的上游地址，
// useChn/useGfw 为列表开关，chnList/gfwList 为对应列表路径。
// 自定义域名文件可以包含 geosite: 标签，启动时提取为 chinadns 的纯域名文件。
/**
 * 合并普通域名和已提取的 Geo 域名，去重后写入文件。
 * @param {string} path
 * @param {string} output
 * @returns {integer} 去重后的域名数量；结果写入 output。
 */
function domains(path, output) {
	let result = [], tags = [];
	for (let line in lines(fs.readfile(path))) {
		if (substr(line, 0, 8) == 'geosite:') {
			push(tags, substr(line, 8));
		}
		else {
			let value = domain(line);
			if (value) {
				push(result, value);
			}
		}
	}
	// Geo 提取由 Shell 完成；此处只合并提取结果与用户域名。
	if (length(tags)) {
		push(result, ...map(lines(fs.readfile(replace(output, /[.]txt$/, '-geo.txt'))), lc));
	}
	result = uniq(result);
	atomic(output, join('\n', result) + '\n', 0o644);
	return length(result);
}
/**
 * @param {DnsSection} dns
 * @param {string} key
 */
function configuredUpstream(dns, key) {
	return dns[key] == 'custom' ? dns[`${key}_custom`] : dns[key];
}

/**
 * 根据 DNS 配置整理 chinadns-ng 模板参数。
 * @param {UciSection[]} sections
 * @param {DnsmasqOptions|null} dnsmasq dnsmasq section；未配置时使用默认端口 53。
 * @returns {ChinadnsOptions|null} 模板参数对象；其他 DNS 模式返回 null。
 */
export function options(sections, dnsmasq) {
	let dns = findDnsSection(sections);
	if (!dns || dns.dns_service != 'chinadns-ng') {
		return null;
	}
	/**
	 * 将 DNS 上游选项转换成实际服务器地址。
	 * @returns {string} 上游地址；缺失或含换行时抛错。
	 */
	function upstream(key) {
		let value = configuredUpstream(dns, key);
		if (value == 'dnsmasq') {
			value = `127.0.0.1#${dnsmasq?.port || '53'}`;
		}
		if (!value || match(value, /[\r\n]/)) {
			die(`invalid ${key}`);
		}
		return value;
	}
	return {
		listenPort: port(dns.cdg_port), direct: upstream('direct_dns'), proxy: upstream('proxy_dns'),
		useChn: dns.use_chn == '1', useGfw: dns.use_gfw == '1',
		chnList: RULE_FILES.chn_list, gfwList: RULE_FILES.gfw_list,
	};
};
/**
 * 生成 chinadns-ng 配置和域名文件，并准备启动参数。
 * @param {UciSection[]} sections
 * @param {string} [configDirectory] 需要 dnsmasq 时从此目录加载 dhcp 配置。
 * @returns {ServiceInstance|null} procd 实例 {id, name, command, env, user}；其他 DNS 模式返回 null。
 */
export function prepare(sections, configDirectory) {
	let dns = findDnsSection(sections), dnsmasq = null;
	if (!dns) {
		return null;
	}
	if (dns.dns_service == 'chinadns-ng'
		&& index(map(['direct_dns', 'proxy_dns'], key => configuredUpstream(dns, key)), 'dnsmasq') >= 0) {
		dnsmasq = findDnsmasqSection(read('dhcp', configDirectory));
	}
	let settings = options(sections, dnsmasq);
	if (!settings) {
		return null;
	}
	let proxyCount = domains(RULE_FILES.domain_proxy, '/tmp/hijpass/domain-proxy.txt');
	let directCount = domains(RULE_FILES.domain_direct, '/tmp/hijpass/domain-direct.txt');
	atomic('/etc/hijpass/chinadns-ng.conf', renderTemplate('/usr/lib/hijpass/service/chinadns.ut', { options: settings }), 0o644);
	logger(sections)('INFO', `chinadns-ng prepared: port=${settings.listenPort}, direct_domains=${directCount}, proxy_domains=${proxyCount}, chn_list=${settings.useChn}, gfw_list=${settings.useGfw}`);
	return { id: dns['.name'], name: 'chinadns-ng', command: ['chinadns-ng', '-C', '/etc/hijpass/chinadns-ng.conf'], env: [], user: 'hijpass' };
};
