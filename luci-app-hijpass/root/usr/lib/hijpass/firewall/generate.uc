/** @typedef {import('../../../share/ucode/hijpass/types/firewall.uc').FirewallOptions} FirewallOptions */
/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').UciSection} UciSection */
/** @typedef {import('../../../share/ucode/hijpass/types/network.uc').NetworkState} NetworkState */
import * as fs from 'fs';
import { RULE_FILES, FILES } from 'hijpass.config.paths';
import { read } from 'hijpass.uci.read';
import { findShuntSection, findDnsSection, findFirewallSection, findDnsmasqSection } from 'hijpass.config.sections';
import { list, port } from 'hijpass.config.values';
import { lines, text, renderTemplate, command, temporary } from 'hijpass.common';
import { run } from 'hijpass.command.runtime';
import { parseCIDR } from 'hijpass.ip';

// Firewall 的输入仍使用 UCI 字段：proxy_port/shunt_port 为透明代理入口，
// tproxy_proto 为 tcp/udp 列表，dns_forward 为 none/pre-routing/routing；
// proxy_local 控制路由器本机，acl_default_allow 与 MAC/接口列表控制客户端。
// NetworkState：wan 为 WAN 设备名；local4/local6/dns4/dns6 为本地绕过地址数组。
/**
 * 读取固定查询命令的输出，检查退出状态；不通过参数或文件中转查询结果。
 * @param {string[]} args
 * @returns {string}
 */
function query(args) {
    let process = fs.popen(command(args), 'r');
    if (!process) die(`cannot execute ${join(' ', args)}: ${fs.error()}`);
    let output = process.read('all'), code = process.close();
    if (output == null || code != 0) die(`${join(' ', args)} failed: exit=${code}`);
    return output;
}
/**
 * WAN 绕过设备仅来自 wan 防火墙区域；本机地址用于目标地址绕过。
 * @param {string|null} configDirectory
 * @returns {NetworkState}
 */
function networkState(configDirectory) {
    let state = { wan: uniq(lines(query(['fw4', 'zone', 'wan']))), local4: [], local6: [], dns4: [], dns6: [] };
    let addresses;
    try { addresses = json(query(['ip', '-j', 'address', 'show'])); }
    catch (e) { die(`cannot read local addresses: ${e.message}`); }
    if (type(addresses) != 'array') die('invalid local address list');
    for (let iface in addresses) {
        for (let addr in iface.addr_info || []) {
            if (addr.family == 'inet' || addr.family == 'inet6')
                push(addr.family == 'inet6' ? state.local6 : state.local4, `${addr.local}/${addr.prefixlen}`);
        }
    }
    let dhcp = findDnsmasqSection(read('dhcp', configDirectory));
    let resolvText = dhcp?.resolvfile ? fs.readfile(dhcp.resolvfile) : null;
    for (let line in lines(resolvText)) {
        let fields = split(line, /[ \t]+/), address = split(fields[1] || '', '%')[0] || '', bytes = iptoarr(address);
        if (fields[0] != 'nameserver' || !bytes || index(['0.0.0.0', '127.0.0.1', '::', '::1'], address) >= 0)
            continue;
        push(length(bytes) == 4 ? state.dns4 : state.dns6, address);
    }
    return state;
}
/**
 * 读取规则文件，只保留指定地址族的有效 IP 和 CIDR。
 * @param {string} path
 * @param {integer} version
 * @returns {string[]} 地址数组；文件缺失或为空时返回空数组。
 */
function ipList(path, version) {
	return filter(lines(fs.readfile(path)), value => parseCIDR(value)?.family == version);
}

// 默认副本由打包流程从可编辑模板生成，升级时更新且不受用户编辑影响。
/**
 * 读取软件包提供的默认防火墙模板。
 * @returns {string} 默认模板原文；读取失败时抛错。
 */
export function defaultTemplate() { return text('/usr/lib/hijpass/firewall/default.ut'); };

// FirewallOptions：端口为已校验整数，0 表示未启用；protocols 为 tcp/udp 数组。
// wan/interfaces/excludedInterfaces 是设备名数组，macs/excludedMacs 是 MAC 数组。
// proxyLocal/allowAll/useChnRoute/useChn/useGfw/domainSets 控制对应规则和集合。
// ip4/ip6 各含 direct/proxy/china 地址数组；空静态列表不生成集合或匹配规则。
// proxyMark/shuntMark/user 是内部固定参数；*Names 是已引用、转义的 nft 接口列表。
/**
 * 合并 UCI 设置和网络状态，整理防火墙模板参数。
 * @param {UciSection[]} config
 * @param {NetworkState} state
 * @returns {FirewallOptions} 供 firewall.ut 使用的 options 对象。
 */
function options(config, state) {
    let f = findFirewallSection(config);
    if (!f) {
        die('firewall section is missing');
    }
    let dns = findDnsSection(config), shunt = findShuntSection(config);
    let forward = '';
    if (f.dns_forward == 'pre-routing' && dns && dns.dns_service == 'chinadns-ng') {
        forward = dns.cdg_port;
    }
    if (f.dns_forward == 'routing' && shunt && shunt.enabled != '0') {
        forward = shunt.dns_listen_port;
    }
    // option 'tcp,udp' 与 list 两种写法均转换为协议数组。
    let protocols = filter(split(join(',', list(f.tproxy_proto)), /[, \t]+/), value => value != '');
    if (!length(protocols)) {
        die('tproxy_proto is required');
    }
    for (let value in protocols) {
        if (index(['tcp', 'udp'], value) < 0) {
            die('invalid tproxy_proto');
        }
    }
    /**
     * 校验访问控制中的 MAC 地址，发现非法值时报错。
     * @returns {string[]} 原 MAC 地址数组。
     */
    function macs(values) {
        for (let value in values) {
            if (!match(value, /^[A-Fa-f0-9]{2}(:[A-Fa-f0-9]{2}){5}$/)) {
                die('invalid proxy MAC');
            }
        }
        return values;
    }
    /**
     * 校验接口名称，拒绝无法安全写入规则的字符。
     * @returns {string[]} 原接口名称数组。
     */
    function interfaces(values) {
        for (let value in values) {
            if (!match(value, /^[A-Za-z0-9_.:@-]+$/)) {
                die('invalid proxy interface');
            }
        }
        return values;
    }
    /**
     * 将接口名称转义为可嵌入 nft 集合的字符串。
     * @param {string[]} names
     * @returns {string} 带引号、以逗号分隔的接口名称。
     */
    function quoteNames(names) {
        return join(', ', map(names, name => sprintf('%J', name)));
    }
    let result = {
        proxyPort: f.proxy_port ? port(f.proxy_port) : 0,
        shuntPort: f.shunt_port ? port(f.shunt_port) : 0,
        forwardPort: forward ? port(forward) : 0,
        protocols, wan: state.wan,
        proxyMark: 0x1, shuntMark: 0x3, user: 'hijpass',
        proxyLocal: f.proxy_local == '1', allowAll: f.acl_default_allow == '1',
        useChnRoute: f.use_chnroute == '1', useChn: dns?.use_chn == '1', useGfw: dns?.use_gfw == '1',
        domainSets: dns != null && dns.dns_service != 'custom',
        macs: macs(list(f.proxy_mac_list)), excludedMacs: macs(list(f.proxy_mac_exclude_list)),
        interfaces: interfaces(list(f.proxy_iface_list)), excludedInterfaces: interfaces(list(f.proxy_iface_exclude_list)),
    };
    result.wanNames = quoteNames(result.wan);
    result.interfaceNames = quoteNames(result.interfaces);
    result.excludedInterfaceNames = quoteNames(result.excludedInterfaces);
    for (let version in [4, 6]) {
        let lists = {
            direct: uniq([...state[`dns${version}`], ...state[`local${version}`], ...ipList(RULE_FILES.ip_direct, version)]),
            proxy: uniq(ipList(RULE_FILES.ip_proxy, version)),
            china: [],
        };
        if (result.useChnRoute) {
            let routeFile = version == 4 ? RULE_FILES.chn_route : RULE_FILES.chn_route6;
            lists.china = uniq(ipList(routeFile, version));
        }
        result[`ip${version}`] = lists;
    }
    return result;
}
/**
 * 检查代理入口，并使用当前模板生成防火墙规则。
 * @param {UciSection[]} config
 * @param {NetworkState} state
 * @returns {string} 完整 nft 表文本；没有代理或分流入口时为空字符串。
 */
export function generate(config, state) {
    let f = findFirewallSection(config);
    if (!f || !f.proxy_port && !f.shunt_port) {
        return '';
    }
    let path = FILES.firewall_template;
    if (type(path) != 'string') {
        die('invalid firewall template path');
    }
    let output = renderTemplate(path, { options: options(config, state) });
    // 空模板不能让已启用的防火墙被当作关闭处理。
    if (!length(trim(output))) {
        die('firewall template rendered no rules');
    }
    return output;
};

/**
 * 校验完整规则后才替换正式文件；生成、写入、校验和替换任一步失败都保留旧文件。
 * @param {string} path
 * @param {string} output
 * @returns {null}
 */
function writeRules(path, output) {
    if (!length(output)) {
        if (fs.lstat(path) && !fs.unlink(path)) die(`cannot remove ${path}: ${fs.error()}`);
        return;
    }
    let temp = temporary(path), file = fs.open(temp, 'wx', 0o600);
    if (!file) die(`cannot create ${temp}: ${fs.error()}`);
    try {
        if (file.write(output) != length(output) || !file.flush()) die(`cannot write ${temp}`);
        if (!file.close()) die(`cannot close ${temp}`);
        if (system(command(['nft', '-c', '-f', temp])) != 0) die('nft rule validation failed');
        if (!fs.rename(temp, path)) die(`cannot replace ${path}: ${fs.error()}`);
    }
    catch (e) { file.close(); fs.unlink(temp); die(e.message); }
}
/** 生成并写入经过校验的规则。重载由 init.d 或 RPC 调用方执行。 */
export function main() { run(ARGV, (args, configDirectory) => {
    if (length(args) != 1 || !length(args[0])) die('usage: generatecli.uc <rules-file>');
    let path = args[0];
    let config = read('hijpass', configDirectory), firewall = findFirewallSection(config);
    if (!firewall || !firewall.proxy_port && !firewall.shunt_port) {
        writeRules(path, '');
        return;
    }
    writeRules(path, generate(config, networkState(configDirectory)));
});
};
