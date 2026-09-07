import { LuciFlied, PROXY_TYPE } from "../../../enum/hijpass";
import fs from "fs";
import uci from "uci";
import { FactoryType, LuciConverterFactory } from "../../../core/adapter";
import { JsonUtils } from "../../base/files/json";
import { FilePathUtils } from "../../base/files/paths";
import { ProxyUtils } from "./section";

function isIpAddress(value: string): boolean {
    return /^(\d{1,3}\.){3}\d{1,3}$/.test(value) || /^[0-9a-fA-F:]+$/.test(value);
}

function getPrimaryOutbound(proxyConf: any): any {
    return Array.isArray(proxyConf?.outbounds) ? proxyConf.outbounds[0] : undefined;
}

function replacePrimaryOutboundServer(proxyConf: any, address: string): boolean {
    const outbound = getPrimaryOutbound(proxyConf);
    if (!outbound) return false;

    if (outbound.server) {
        outbound.server = address;
        return true;
    }
    if (outbound.settings?.address) {
        outbound.settings.address = address;
        return true;
    }
    if (outbound.settings?.servers?.[0]?.address) {
        outbound.settings.servers[0].address = address;
        return true;
    }
    if (outbound.settings?.vnext?.[0]?.address) {
        outbound.settings.vnext[0].address = address;
        return true;
    }
    return false;
}

async function resolveNestedProxyServer(proxyConfig: any, proxyConf: any) {
    if (!proxyConfig.upstream_proxy_node || !proxyConfig.server || isIpAddress(proxyConfig.server)) {
        return;
    }

    const result = await fs.exec_direct('/usr/lib/hijpass/net.sh', ['resolve', proxyConfig.server], 'json');
    if (!result?.address) {
        throw new Error(_('Resolve proxy server failed: %s').format(proxyConfig.server));
    }
    if (!replacePrimaryOutboundServer(proxyConf, result.address)) {
        throw new Error(_('Unsupported proxy config server field: %s').format(proxyConfig.name || proxyConfig.server));
    }
}

async function writeGeneratedProxyConfigs() {
    const tasks: Promise<any>[] = [];

    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, (section: any) => {
        const proxyConfig = ProxyUtils.createProxyConfigFromSection(section);
        if (section.enabled !== '1'
            || !proxyConfig
            || proxyConfig.type === PROXY_TYPE.CUSTOM
            || proxyConfig.core === FactoryType.CUSTOM) {
            return;
        }

        const proxyConf = LuciConverterFactory.genProxyConf(proxyConfig.core, proxyConfig);

        tasks.push(resolveNestedProxyServer(proxyConfig, proxyConf).then(() => {
            const outData = typeof proxyConf === 'string'
                ? proxyConf
                : JSON.stringify(proxyConf, JsonUtils.omitEmptyReplacer, 2);
            return fs.write(FilePathUtils.getProxyConfigFilePath(section), outData);
        }));
    });

    if (tasks.length === 0) {
        return;
    }

    const results = await Promise.allSettled(tasks);
    results.forEach(result => {
        if (result.status === 'rejected') {
            throw new Error(result.reason?.message || String(result.reason));
        }
    });
}

function generateProxyConfigFromSection(section: any) {
    const proxyConfig = ProxyUtils.createProxyConfigFromSection(section);
    if (!proxyConfig) {
        return;
    }

    return LuciConverterFactory.genProxyConf(proxyConfig.core, proxyConfig);
}

const ProxyConfigFileUtils = {
    writeGeneratedProxyConfigs,
    generateProxyConfigFromSection,
}

export { ProxyConfigFileUtils }
