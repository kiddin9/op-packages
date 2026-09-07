import uci from "uci";
import { CORE_TYPE, LuciFlied, PROXY_TYPE, normalizeCoreType } from "../../../enum/hijpass";
import type { LoadBalanceProxyNode, ProxyNode } from "../../../module/luci";

export const MAX_PROXY_CHAIN_NODES = 3;
export const LOAD_BALANCE_MEMBER_TAG_PREFIX = 'lb-member-';

export interface ResolvedUpstreamProxy {
    name: string;
    socksPort: number;
    tag: string;
    core: string;
    section: any;
}

export interface ResolvedLoadBalanceMember extends ResolvedUpstreamProxy {
    tag: string;
}

function getProxyName(section: any): string {
    return section?.name || section?.['.name'] || '';
}

function getProxyCore(section: any): string {
    return normalizeCoreType(section?.core || CORE_TYPE.SING_BOX);
}

function isPort(value: any): boolean {
    if (!value) return false;
    const port = Number(value);
    return Number.isInteger(port) && port > 0 && port <= 65535;
}

function getProxySections(): any[] {
    const sections: any[] = [];
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section: any) {
        sections.push(section);
    });
    return sections;
}

function getProxySectionMap(): Map<string, any> {
    const sections = new Map<string, any>();
    getProxySections().forEach((section) => {
        const name = getProxyName(section);
        if (name) sections.set(name, section);
    });
    return sections;
}

function getUpstreamProxyOutboundTag(name: string): string {
    return 'upstream-' + name;
}

function normalizeProxyNodeList(value: any): string[] {
    if (!value) return [];
    return (Array.isArray(value) ? value : [value]).filter((name) => Boolean(name));
}

function getLoadBalanceMemberOutboundTag(index: number): string {
    return LOAD_BALANCE_MEMBER_TAG_PREFIX + index;
}

function resolveLoadBalanceMembers(
    proxyNode: LoadBalanceProxyNode,
    sections: Map<string, any> = getProxySectionMap()
): ResolvedLoadBalanceMember[] {
    const memberNames = normalizeProxyNodeList(proxyNode.member_node);
    if (memberNames.length === 0) {
        throw new Error('Load balancing node has no members: ' + proxyNode.name);
    }

    return memberNames.map((memberName, index) => {
        if (memberName === proxyNode.name) {
            throw new Error('Load balancing node cannot include itself: ' + memberName);
        }

        const section = sections.get(memberName);
        if (!section) {
            throw new Error('Load balancing member node not found: ' + memberName);
        }
        if (section.type === PROXY_TYPE.LOAD_BALANCE) {
            throw new Error('Nested load balancing members are not supported: ' + memberName);
        }
        if (section.enabled !== '1') {
            throw new Error('Load balancing member node disabled: ' + memberName);
        }
        if (!isPort(section.socks_port)) {
            throw new Error('Load balancing member node SOCKS port invalid: ' + memberName);
        }

        return {
            name: memberName,
            socksPort: Number(section.socks_port),
            tag: getLoadBalanceMemberOutboundTag(index),
            core: getProxyCore(section),
            section,
        };
    });
}

function resolveUpstreamProxy(
    proxyNode: ProxyNode,
    sections: Map<string, any> = getProxySectionMap()
): ResolvedUpstreamProxy | undefined {
    const upstreamName = proxyNode.upstream_proxy_node;
    if (!upstreamName) return undefined;
    if (upstreamName === proxyNode.name) {
        throw new Error('Upstream proxy node cannot be itself: ' + upstreamName);
    }

    const upstreamSection = sections.get(upstreamName);
    if (!upstreamSection) {
        throw new Error('Upstream proxy node not found: ' + upstreamName);
    }
    if (upstreamSection.enabled !== '1') {
        throw new Error('Upstream proxy node disabled: ' + upstreamName);
    }
    if (!isPort(upstreamSection.socks_port)) {
        throw new Error('Upstream proxy node SOCKS port invalid: ' + upstreamName);
    }

    return {
        name: upstreamName,
        socksPort: Number(upstreamSection.socks_port),
        tag: getUpstreamProxyOutboundTag(upstreamName),
        core: getProxyCore(upstreamSection),
        section: upstreamSection,
    };
}

function collectProxyChain(startName: string, sections: Map<string, any>) {
    const chain: string[] = [];
    const seen = new Set<string>();
    let currentName = startName;

    while (currentName) {
        if (seen.has(currentName)) {
            chain.push(currentName);
            return { chain, cycle: true };
        }

        seen.add(currentName);
        chain.push(currentName);

        const section = sections.get(currentName);
        if (!section || !section.upstream_proxy_node) break;
        currentName = section.upstream_proxy_node;
    }

    return { chain, cycle: false };
}

function getProxyDependencies(section: any): string[] {
    const dependencies: string[] = [];
    if (section?.type === PROXY_TYPE.LOAD_BALANCE) {
        dependencies.push(...normalizeProxyNodeList(section.member_node));
    } else if (section?.upstream_proxy_node) {
        dependencies.push(section.upstream_proxy_node);
    }
    return dependencies;
}

function findProxyDependencyCycle(sections: Map<string, any>): string[] | undefined {
    const visited = new Set<string>();
    const visiting = new Set<string>();
    const stack: string[] = [];

    function visit(name: string): string[] | undefined {
        if (visiting.has(name)) {
            const cycleStart = stack.indexOf(name);
            return stack.slice(cycleStart).concat(name);
        }
        if (visited.has(name)) return undefined;

        const section = sections.get(name);
        if (!section || section.enabled !== '1') return undefined;

        visiting.add(name);
        stack.push(name);
        for (const dependency of getProxyDependencies(section)) {
            const cycle = visit(dependency);
            if (cycle) return cycle;
        }
        stack.pop();
        visiting.delete(name);
        visited.add(name);
        return undefined;
    }

    for (const name of sections.keys()) {
        const cycle = visit(name);
        if (cycle) return cycle;
    }
    return undefined;
}

const ProxyChainUtils = {
    getProxyName,
    getProxyCore,
    getProxySections,
    getProxySectionMap,
    isPort,
    getUpstreamProxyOutboundTag,
    normalizeProxyNodeList,
    getLoadBalanceMemberOutboundTag,
    resolveUpstreamProxy,
    resolveLoadBalanceMembers,
    collectProxyChain,
    getProxyDependencies,
    findProxyDependencyCycle,
}

export { ProxyChainUtils }
