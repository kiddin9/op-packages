/** @typedef {import('../types/proxy.uc').DecodedProxyNode} DecodedProxyNode */
/** @typedef {import('../types/proxy.uc').ProxyGraph} ProxyGraph */
/** @typedef {import('../types/proxy.uc').ResolvedDependencies} ResolvedDependencies */
/** @typedef {import('../types/proxy.uc').ProxyIndex} ProxyIndex */
/** @typedef {import('../types/proxy-sections.uc').ProxyNodeSection} ProxyNodeSection */
import { list } from '../config/values.uc';
import { decodeProxy, TYPE, CONFIG_TYPE } from '../config/protocol/proxy.uc';

// ResolvedDependencies：nodes 为按发现顺序排列的节点，byID/byName 为查找索引。
// 每个节点的 upstream/members 直接引用其依赖节点，供核心配置生成使用。
// 解析、连接引用、校验分别执行，查询过程没有隐藏的配置校验副作用。
/**
 * 从调用方指定的起点收集依赖，连接上游和均衡成员；不解释启用状态。
 * @param {ProxyNodeSection[]} rootProxies 要解析的代理起点，空数组表示不生成节点。
 * @param {ProxyNodeSection[]} availableProxies 可按名称引用的依赖候选，由调用方决定范围。
 * @returns {ResolvedDependencies} {nodes, byID, byName}，索引和依赖直接引用节点对象。
 */
export function resolve(rootProxies, availableProxies) {
	/** @type {Object<string, ProxyNodeSection[]>} */
	let proxiesByName = {};
	for (let section in availableProxies) {
		let name = section.name || section['.name'];
		proxiesByName[name] ||= [];
		push(proxiesByName[name], section);
	}
	/** @type {DecodedProxyNode[]} */
	let nodes = [];
	/** @type {ProxyIndex} */
	let byID = {};
	/** @type {ProxyIndex} */
	let byName = {};
	/** @type {Object<string, string[]>} */
	let dependencies = {};
	// 按批次展开依赖，保持发现顺序；每个 ID 只展开一次，循环有界。
	/** @type {ProxyNodeSection[]} */
	let pendingSections = rootProxies;
	while (length(pendingSections)) {
		/** @type {ProxyNodeSection[]} */
		let nextSections = [];
		for (let section in pendingSections) {
			let id = section['.name'], name = section.name || id;
			if (byID[id]) {
				continue;
			}
			if (byName[name] || length(filter(proxiesByName[name] || [], other => other['.name'] != id))) {
				die(`duplicate proxy name "${name}"`);
			}
			let node;
			try { node = decodeProxy(section); }
			catch (e) { die(`node "${name}": ${e.message}`); }
			byID[id] = node;
			byName[name] = node;
			push(nodes, node);
			let dependencyIDs = [];
			dependencies[id] = dependencyIDs;
			// 自定义命令自行管理出站；忽略切换核心后残留的协议依赖字段。
			if (node.config_type == CONFIG_TYPE.custom) {
				continue;
			}
			if (node.type == TYPE.balance && section.upstream_proxy_node) {
				die(`load balancing node cannot have an upstream: ${name}`);
			}
			let dependencyNames = [];
			if (node.type == TYPE.balance) {
				dependencyNames = list(section.member_node);
			}
			else if (section.upstream_proxy_node) {
				dependencyNames = [section.upstream_proxy_node];
			}
			for (let dependencyName in dependencyNames) {
				let matches = proxiesByName[dependencyName] || [];
				if (!length(matches)) {
					die(`proxy node "${dependencyName}" missing from available proxies`);
				}
				if (length(matches) > 1) {
					die(`duplicate proxy name "${dependencyName}"`);
				}
				push(dependencyIDs, matches[0]['.name']);
				push(nextSections, matches[0]);
			}
		}
		pendingSections = nextSections;
	}
	for (let node in nodes) {
		let dependencyNodes = [];
		for (let id in dependencies[node.id]) {
			push(dependencyNodes, byID[id]);
		}
		if (node.type == TYPE.balance) {
			node.members = dependencyNodes;
		}
		else {
			node.upstream = dependencyNodes[0];
		}
	}
	return { nodes, byID, byName };
};

/**
 * 检查代理链的循环、长度和负载均衡成员设置。
 * @param {ProxyGraph} dependencies
 * @returns {null} 无业务返回值；依赖无效时抛错。
 */
export function validate(dependencies) {
	let active = {}, heights = {};
	/**
	 * 递归检查节点依赖，并计算和缓存代理链长度。
	 * @param {DecodedProxyNode} n
	 * @returns {integer} 含自身的链长；均衡节点为 1，其成员分别检查。
	 */
	function visit(n) {
		if (active[n.id]) {
			die(`proxy dependency cycle at "${n.name}"`);
		}
		if (heights[n.id]) {
			return heights[n.id];
		}
		active[n.id] = true;
		let height = 1;
		if (n.type == TYPE.balance) {
			if (!length(n.members)) {
				die(`load balancing node "${n.name}" has no members`);
			}
			let unique = {};
			for (let m in n.members) {
				if (unique[m.name]) {
					die(`duplicate load balancing member "${m.name}"`);
				}
				if (m.type == TYPE.balance) {
					die(`nested load balancing member "${m.name}"`);
				}
				unique[m.name] = true;
				visit(m);
			}
			if (n.fallback_tag && !unique[n.fallback_tag]) {
				die(`fallback "${n.fallback_tag}" is not a load balancing member`);
			}
		}
		else if (n.upstream) {
			height += visit(n.upstream);
		}
		if (height > 3) {
			die(`proxy chain exceeds three nodes at "${n.name}"`);
		}
		delete active[n.id];
		heights[n.id] = height;
		return height;
	}
	for (let n in dependencies.nodes) {
		visit(n);
	}
};
