import { ProxyChainUtils } from "./chain";

function findProxyDependencyCycleFrom(
    nodeName: string,
    dependencies: string[],
    sections: Map<string, any> = ProxyChainUtils.getProxySectionMap()
): string[] | undefined {
    const visited = new Set<string>();

    function visit(currentName: string, path: string[]): string[] | undefined {
        if (currentName === nodeName) return path;
        if (visited.has(currentName)) return undefined;

        visited.add(currentName);
        const section = sections.get(currentName);
        if (!section) return undefined;

        for (const dependency of ProxyChainUtils.getProxyDependencies(section)) {
            const cycle = visit(dependency, path.concat(dependency));
            if (cycle) return cycle;
        }
        return undefined;
    }

    for (const dependency of dependencies) {
        const cycle = visit(dependency, [nodeName, dependency]);
        if (cycle) return cycle;
    }
    return undefined;
}

export { findProxyDependencyCycleFrom }
