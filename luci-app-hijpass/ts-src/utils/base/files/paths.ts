import { LuciFlied } from "../../../enum/hijpass";
import uci from "uci";

const DEFAULT_PATHS: Record<string, Record<string, string>> = {
    [LuciFlied.CONF_NAME]: {
        client_dir: '/etc/hijpass/client',
        shunt_conf: '/etc/hijpass/shunt.json',
        ip_direct: '/etc/hijpass/rules/ip-direct.txt',
        ip_proxy: '/etc/hijpass/rules/ip-proxy.txt',
        domain_direct: '/etc/hijpass/rules/domain-direct.txt',
        domain_proxy: '/etc/hijpass/rules/domain-proxy.txt',
        nft: '/etc/hijpass/fw4-template.nft',
        nft_hook: '/etc/hijpass/hook/nft-hook.sh',
        dns_hook: '/etc/hijpass/hook/dns-hook.sh',
    },
    [LuciFlied.SERVER_CONF_NAME]: {
        server_dir: '/etc/hijpass/server',
    },
};

function normalizeFileContent(value?: string) {
    const content = (value || '').trim().replace(/\r\n/g, '\n');
    return content ? content + '\n' : '';
}

function getFilePath(option: any, confName: string = LuciFlied.CONF_NAME) {
    let path = uci.get_first(confName, confName, option)
    if (path) {
        return path
    }
    const defaultPath = DEFAULT_PATHS[confName]?.[option];
    if (defaultPath) {
        return defaultPath;
    }
    console.log(option + ' path is empty')
    return ''
}

function getNodeConfigFilePath(confName: string, dirPath: string, sectionId: string, optionContext?: any) {
    if (!dirPath) {
        throw new Error(_('Configuration file directory is empty'));
    }

    const formName = optionContext?.section?.formvalue?.(sectionId, 'name');
    const name = formName || uci.get(confName, sectionId, 'name') || sectionId;
    return dirPath + '/' + name + '-' + sectionId + '.json';
}

function getProxyConfigFilePath(section: any) {
    const name = section.name || section['.name'];
    return getFilePath('client_dir') + '/' + name + '-' + section['.name'] + '.json';
}

function getServerConfigFilePath(section: any) {
    const name = section.name || section['.name'];
    return getFilePath('server_dir', LuciFlied.SERVER_CONF_NAME) + '/' + name + '-' + section['.name'] + '.json';
}

const FilePathUtils = {
    normalizeFileContent,
    getFilePath,
    getNodeConfigFilePath,
    getProxyConfigFilePath,
    getServerConfigFilePath,
}

export { FilePathUtils }
