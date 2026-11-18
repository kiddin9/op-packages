/** @typedef {import('../types/core.uc').GenerationInput} GenerationInput */
/** @typedef {import('../types/core.uc').GeneratedConfigs} GeneratedConfigs */
/** @typedef {import('../types/routing.uc').RoutingSettings} RoutingSettings */
/** @typedef {import('../types/proxy.uc').DecodedProxyNode} DecodedProxyNode */
import { CORE, CONFIG_TYPE } from '../config/protocol/proxy.uc';
import { resolve as resolveDependencies, validate as validateDependencies } from './dependencies.uc';
import { cleanObject } from './json.uc';
import { build as singbox } from './singbox/config.uc';
import { build as xray } from './xray/config.uc';
import { prepare as prepareRouting, build as buildRouting } from './routing.uc';

/**
 * 检查节点和分流监听端口是否相互冲突。
 * @param {DecodedProxyNode[]} nodes
 * @param {RoutingSettings|null} shunt
 * @returns {null} 无业务返回值；发现重复端口时抛错。
 */
function validatePorts(nodes, shunt) {
	let owners = {};
	/**
	 * 登记端口占用者，拒绝重复占用。
	 * @returns {null} 无业务返回值，更新端口登记表。
	 */
	function add(port, owner) {
		if (owners[port]) {
			die(`port ${port} is shared by ${owners[port]} and ${owner}`);
		}
		owners[port] = owner;
	}
	for (let n in nodes) {
		add(n.listen_port, `${n.name}.listen_port`);
		add(n.socks_port, `${n.name}.socks_port`);
	}
	if (shunt) {
		add(shunt.listen, 'shunt.shunt_listen_port');
		add(shunt.dnsPort, 'shunt.dns_listen_port');
	}
};

/**
 * 解析显式提供的节点和分流输入，校验后生成核心配置；不筛选启用状态或写文件。
 * @param {GenerationInput} input 调用方选定的代理起点、依赖候选及可选分流输入。
 * @returns {GeneratedConfigs} nodes 以 section ID 索引；传入分流输入时生成 shunt。
 */
export function render(input) {
	let dependencies = resolveDependencies(input.rootProxies, input.availableProxies);
	validateDependencies(dependencies);
	let routing = input.routing ? prepareRouting(input.routing, dependencies) : null;
	validatePorts(dependencies.nodes, routing);
	let result = { nodes: {} };
	for (let n in dependencies.nodes) {
		if (n.config_type == CONFIG_TYPE.custom) {
			continue;
		}
		try { result.nodes[n.id] = cleanObject(n.core == CORE.xray ? xray(n) : singbox(n)); }
		catch (e) { die(`node "${n.name}": ${e.message}`); }
	}
	if (routing) {
		result.shunt = cleanObject(buildRouting(routing, dependencies));
	}
	return result;
};
