/** @typedef {import('../types/core.uc').GenerationInput} GenerationInput */
/** @typedef {import('../types/core.uc').GeneratedConfigs} GeneratedConfigs */
/** @typedef {import('../types/core.uc').CoreConfig} CoreConfig */
/** @typedef {import('../types/core.uc').ValidationResult} ValidationResult */
/** @typedef {import('../types/sections.uc').UciSection} UciSection */
import {
	findHijpassSection, findShuntSection, filterProxyNodeSections,
	filterShuntDnsNodeSections, filterShuntRouteRuleSections, validateSections
} from './sections.uc';
import { render } from '../coreconfig/render.uc';

/**
 * 根据生效或预览场景选择输入，再生成核心配置；不写文件或启动服务。
 * @param {UciSection[]} sections
 * @param {string} [target] 要预览的 proxy_node 或 shunt section ID；省略时生成启用配置。
 * @returns {GeneratedConfigs|CoreConfig} 全量配置集合，或指定 section 的核心配置。
 */
export function generate(sections, target) {
	validateSections(sections);
	let targetSection = target ? filter(sections, section => section['.name'] == target)[0] : null;
	if (target && !targetSection) {
		die('target section not found');
	}
	if (targetSection && targetSection['.type'] != 'proxy_node' && targetSection['.type'] != 'shunt') {
		die(`unsupported target section type "${targetSection['.type']}"`);
	}
	let availableProxies = filter(filterProxyNodeSections(sections), section => section.enabled == '1');
	// 显式预览允许目标未启用；它引用的依赖仍须来自启用的候选节点。
	let rootProxies = targetSection?.['.type'] == 'proxy_node' ? filterProxyNodeSections([targetSection]) : availableProxies;
	let shunt = findShuntSection(targetSection ? [targetSection] : sections);
	if (!target && shunt && (shunt.enabled == '0' || shunt.config_type != 'tmpl')) {
		shunt = null;
	}
	/** @type {GenerationInput} */
	let selection = {
		rootProxies, availableProxies,
		routing: shunt ? {
			shunt,
			dnsNodes: filter(filterShuntDnsNodeSections(sections), section => section.enabled != '0'),
			rules: filter(filterShuntRouteRuleSections(sections), section => section.enabled == '1'),
		} : null,
	};
	let result = render(selection);
	if (!target) {
		return result;
	}
	let config = shunt ? result.shunt : result.nodes[target];
	if (!config) {
		die('custom node configuration is not generated');
	}
	return config;
};

/**
 * 检查待保存配置；服务关闭时允许未完成表单，但仍校验快照结构。
 * @param {UciSection[]} sections
 * @returns {ValidationResult} 校验成功返回 {ok: true}，失败时抛错。
 */
export function validate(sections) {
	if (findHijpassSection(sections)?.enabled == '0') {
		validateSections(sections);
	}
	else {
		generate(sections);
	}
	return { ok: true };
};
