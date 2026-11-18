/** @typedef {import('../types/sections.uc').UciSection} UciSection */
/** @typedef {import('../types/sections.uc').HijpassSection} HijpassSection */
/** @typedef {import('../types/sections.uc').HijserverSection} HijserverSection */
/** @typedef {import('../types/sections.uc').ShuntSection} ShuntSection */
/** @typedef {import('../types/sections.uc').DnsSection} DnsSection */
/** @typedef {import('../types/sections.uc').FirewallSection} FirewallSection */
/** @typedef {import('../types/sections.uc').RuleSection} RuleSection */
/** @typedef {import('../types/sections.uc').DnsmasqSection} DnsmasqSection */
/** @typedef {import('../types/proxy-sections.uc').ProxyNodeSection} ProxyNodeSection */
/** @typedef {import('../types/server-sections.uc').ServerNodeSection} ServerNodeSection */
/** @typedef {import('../types/sections.uc').ShuntRouteRuleSection} ShuntRouteRuleSection */
/** @typedef {import('../types/sections.uc').ShuntDnsNodeSection} ShuntDnsNodeSection */
// Section：.name 是稳定 ID，.type 是配置段类型，.index 是可选排序位置。
// 普通字段是字符串或字符串数组；输入可来自原生 UCI，也可来自 LuCI JSON 快照。
// 本模块只查询与校验内存数据，不读写配置文件。
/**
 * 按类型筛选 UCI section，保持原配置顺序。
 * @param {UciSection[]} sections
 * @param {string} sectionType
 * @returns {UciSection[]} 匹配的原对象数组；无匹配时为空数组。
 */
export function filterSectionsByType(sections, sectionType) {
	return filter(sections, section => section['.type'] == sectionType);
};
/**
 * 查找指定类型的第一个 UCI section。
 * @param {UciSection[]} sections
 * @param {string} sectionType
 * @returns {UciSection|null} 原 section 对象；未找到时返回 null，由调用方处理缺失情况。
 */
export function findFirstSectionByType(sections, sectionType) {
	for (let section in sections) {
		if (section['.type'] == sectionType) {
			return section;
		}
	}
	return null;
};

// 校验快照结构，防止外部 JSON 的数字/对象进入只接受 UCI 字符串的业务转换。
/**
 * 检查配置快照的结构、section 标识和字段类型。
 * @param {UciSection[]} sections
 * @returns {null} 无业务返回值；结构无效时抛错。
 */
export function validateSections(sections) {
	if (type(sections) != 'array' || !length(sections)) {
		die('configuration is empty or cannot unmarshal sections array');
	}
	let ids = {};
	for (let s in sections) {
		if (type(s) != 'object' || !s['.name'] || !s['.type']) {
			die('section requires .name and .type');
		}
		if (ids[s['.name']]) {
			die(`duplicate section "${s['.name']}"`);
		}
		ids[s['.name']] = true;
		for (let key, value in s) {
			if (substr(key, 0, 1) == '.') {
				continue;
			}
			if (type(value) == 'string') {
				continue;
			}
			if (type(value) == 'array' && !length(filter(value, v => type(v) != 'string'))) {
				continue;
			}
			die(`${s['.name']}: ${key} must be a string or string list`);
		}
	}
};

/**
 * 查询 hijpass 配置，返回原对象；缺失时返回 null，由调用方处理。
 * @param {UciSection[]} sections
 * @returns {HijpassSection|null}
 */
export function findHijpassSection(sections) {
	return findFirstSectionByType(sections, 'hijpass');
};

/**
 * 查询 hijserver 配置，返回原对象；缺失时返回 null，由调用方处理。
 * @param {UciSection[]} sections
 * @returns {HijserverSection|null}
 */
export function findHijserverSection(sections) {
	return findFirstSectionByType(sections, 'hijserver');
};

/**
 * 查询 shunt 配置，返回原对象；缺失时返回 null，由调用方处理。
 * @param {UciSection[]} sections
 * @returns {ShuntSection|null}
 */
export function findShuntSection(sections) {
	return findFirstSectionByType(sections, 'shunt');
};

/**
 * 查询 dns 配置，返回原对象；缺失时返回 null，由调用方处理。
 * @param {UciSection[]} sections
 * @returns {DnsSection|null}
 */
export function findDnsSection(sections) {
	return findFirstSectionByType(sections, 'dns');
};

/**
 * 查询 firewall 配置，返回原对象；缺失时返回 null，由调用方处理。
 * @param {UciSection[]} sections
 * @returns {FirewallSection|null}
 */
export function findFirewallSection(sections) {
	return findFirstSectionByType(sections, 'firewall');
};

/**
 * 查询 rule 配置，返回原对象；缺失时返回 null，由调用方处理。
 * @param {UciSection[]} sections
 * @returns {RuleSection|null}
 */
export function findRuleSection(sections) {
	return findFirstSectionByType(sections, 'rule');
};

/**
 * 查询 dnsmasq 配置，返回原对象；缺失时返回 null，由调用方处理。
 * @param {UciSection[]} sections
 * @returns {DnsmasqSection|null}
 */
export function findDnsmasqSection(sections) {
	return findFirstSectionByType(sections, 'dnsmasq');
};

/**
 * 查询 proxy_node 配置，保持原顺序和对象引用；无匹配时返回空数组。
 * @param {UciSection[]} sections
 * @returns {ProxyNodeSection[]}
 */
export function filterProxyNodeSections(sections) {
	return filterSectionsByType(sections, 'proxy_node');
};

/**
 * 查询 server_node 配置，保持原顺序和对象引用；无匹配时返回空数组。
 * @param {UciSection[]} sections
 * @returns {ServerNodeSection[]}
 */
export function filterServerNodeSections(sections) {
	return filterSectionsByType(sections, 'server_node');
};

/**
 * 查询 shunt_route_rule 配置，保持原顺序和对象引用；无匹配时返回空数组。
 * @param {UciSection[]} sections
 * @returns {ShuntRouteRuleSection[]}
 */
export function filterShuntRouteRuleSections(sections) {
	return filterSectionsByType(sections, 'shunt_route_rule');
};

/**
 * 查询 shunt_dns_node 配置，保持原顺序和对象引用；无匹配时返回空数组。
 * @param {UciSection[]} sections
 * @returns {ShuntDnsNodeSection[]}
 */
export function filterShuntDnsNodeSections(sections) {
	return filterSectionsByType(sections, 'shunt_dns_node');
};
