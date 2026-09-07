import view from "view";
import uci from "uci";
import { FIREWALL_DNS_FORWARD, LuciFlied } from "../enum/hijpass";
import form from "form";
import { SaveApplyUtils } from "../utils/actions/save-apply/index";
import { FormUtils } from "../utils/base/luci/form";
import { FilePathUtils } from "../utils/base/files/paths";
import { FirewallFormUtils } from "../utils/feature/firewall/form";
import { FirewallDnsForwardUtils } from "../utils/feature/firewall/dns-forward";


const v = view.extend({
    load: function () {
        return Promise.all([
            uci.load(LuciFlied.CONF_NAME),
            uci.load('firewall'),
        ]);
    },

    handleSaveApply: SaveApplyUtils.genHandleSaveApply(),

    render: async function () {
        let m = new form.Map(LuciFlied.CONF_NAME, _('Firewall Configuration'),
            _('Configure Firewall'));

        let s = m.section(form.TypedSection, LuciFlied.FIREWALL_SECTION_TYPE);
        s.anonymous = true;
        s.addremove = false;
        // 创建标签页
        createTabs(s);

        // 创建基础配置选项
        createGeneralOptions(s);
        // 创建 ACL 配置选项
        await createAclOptions(s);
        // 创建文本编辑选项
        createTextOptions(s);

        return m.render();
    }
});

// 创建基础配置选项
function createGeneralOptions(s: LuCI.form.AbstractSection) {
    // TPROXY 协议配置
    let o = s.taboption('basic', form.ListValue, 'tproxy_proto', _('TPROXY Protocol'),
        _('TPROXY Protocol Type'));
    o.value('tcp', 'TCP');
    o.value('udp', 'UDP');
    o.value('tcp,udp', 'TCP + UDP');
    o.default = 'tcp,udp';
    o.rmempty = false;

    // 代理端口配置
    createPortOptions(s);

    // 列表选项配置
    createListOptions(s);
}

// 创建端口选择选项
function createPortOptions(s: LuCI.form.AbstractSection) {
    let proxyPort = s.taboption('basic', form.ListValue, 'proxy_port', _('Proxy Port'),
        _('Select Proxy Port'));
    FormUtils.appendEnabledNodeListenPorts(proxyPort);
    proxyPort.value('', _('Disabled'));
    proxyPort.default = '';
    proxyPort.rmempty = true;

    let shuntPort = s.taboption('basic', form.ListValue, 'shunt_port', _('Default Shunt Port'),
        _('Select Shunt Port'));
    const shuntListenPort = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'shunt_listen_port');
    if (shuntListenPort) {
        shuntPort.value(shuntListenPort, _('Shunt Port: %s').format(shuntListenPort));
    }
    FormUtils.appendEnabledNodeListenPorts(shuntPort);
    shuntPort.value('', _('Disabled'));
    shuntPort.default = '';
    shuntPort.rmempty = true;

    let dnsForward = s.taboption('basic', form.ListValue, 'dns_forward', _('DNS Forwarding'),
        _('Redirect DNS queries from clients selected by the firewall ACL and, when enabled, router system DNS queries to the selected local DNS service'));
    dnsForward.value(FIREWALL_DNS_FORWARD.NONE, _('Do not forward'));

    const preRoutingTarget = FirewallDnsForwardUtils.getPreRoutingTarget();
    dnsForward.value(FIREWALL_DNS_FORWARD.PRE_ROUTING,
        FirewallDnsForwardUtils.getTargetLabel(_('Independent DNS'), preRoutingTarget));

    const routingTarget = FirewallDnsForwardUtils.getRoutingTarget();
    dnsForward.value(FIREWALL_DNS_FORWARD.ROUTING,
        FirewallDnsForwardUtils.getTargetLabel(_('Core DNS'), routingTarget));

    dnsForward.default = FIREWALL_DNS_FORWARD.NONE;
    dnsForward.rmempty = false;
    dnsForward.validate = function (_sectionId: string, value: string) {
        return FirewallDnsForwardUtils.validateSource(value);
    };
}

// 创建列表选项
function createListOptions(s: LuCI.form.AbstractSection) {
    let o = s.taboption('basic', form.Flag, 'use_chnroute', _('Use CHN Route'),
        _('Enable CHN IP Route'));

    o.rmempty = true;
}

// 创建所有文本编辑选项
function createTextOptions(s: LuCI.form.AbstractSection) {
    // IP 直连列表（IPv4 + IPv6）
    FormUtils.createTextOption(s, 'ip_direct', 'ip_direct_hash', null,
        _('Edit IP Direct List'),
        FilePathUtils.getFilePath('ip_direct'));

    // IP 代理列表（IPv4 + IPv6）
    FormUtils.createTextOption(s, 'ip_proxy', 'ip_proxy_hash', null,
        _('Edit IP Proxy List'), FilePathUtils.getFilePath('ip_proxy'));

    // 防火墙规则
    FormUtils.createTextOption(s, 'nftables', 'nft_hash', null,
        _('Edit the nftables rule template. Intended for users familiar with nftables and HiJpass rule generation. Arbitrary changes may break compatibility with LuCI configuration features and affect network connectivity.'),
        FilePathUtils.getFilePath('nft'));

    FirewallFormUtils.createNftViewOption(s);

    // 用户自定义启动脚本
    FormUtils.createTextOption(s, 'hook', 'nft_hook_hash', null,
        _('Executed after HiJpass attempts to load its generated nftables rules during firewall start or reload. Runs only when the generated rules file and this script exist; it may also run if loading the rules fails.'),
        FilePathUtils.getFilePath('nft_hook'));
}

// 创建所有标签页
function createTabs(s: LuCI.form.AbstractSection) {
    s.tab('basic', _('Basic Settings'));
    s.tab('acl', _('Access Control List'));
    s.tab('ip_direct', _('IP Direct List'));
    s.tab('ip_proxy', _('IP Proxy List'));
    s.tab('nftables', _('Firewall Rules'));
    s.tab('hook', _('Custom Script'));
}

// 创建 ACL 访问控制列表配置选项
async function createAclOptions(s: LuCI.form.AbstractSection) {
    let proxyLocal = s.taboption('acl', form.Flag, 'proxy_local', _('Proxy Router Traffic'),
        _('Transparently proxy eligible router-originated TCP and UDP traffic'));
    proxyLocal.rmempty = false;
    proxyLocal.default = '1';

    // 代理模式开关
    // 关闭（默认）：默认不代理，下方列表为走代理设备
    // 开启：默认全代理，下方列表为不走代理设备
    let aclMode = s.taboption('acl', form.Flag, 'acl_default_allow', _('Default Proxy All'),
        _('Off: Default no proxy; On: Default proxy all'));
    aclMode.rmempty = false;
    aclMode.default = '0';

    const aclContext = await FirewallFormUtils.loadAclContext();
    const ifaceValidate = FirewallFormUtils.createIfaceValidator(aclContext.interfaces);

    // 关闭模式：走代理设备（MAC）
    let proxyMacOpt = s.taboption('acl', form.DynamicList, 'proxy_mac_list', _('Proxy Device'),
        _('Proxy Device'));
    proxyMacOpt.datatype = 'macaddr';
    proxyMacOpt.rmempty = true;
    proxyMacOpt.depends('acl_default_allow', '0');
    FirewallFormUtils.appendHostHintOptions(proxyMacOpt, aclContext.hostHints);

    // 关闭模式：走代理接口
    let proxyIfaceOpt = s.taboption('acl', form.DynamicList, 'proxy_iface_list', _('Proxy Interface'),
        _('Proxy client traffic entering through the selected logical network interfaces; WAN interfaces cannot be selected'));
    proxyIfaceOpt.rmempty = true;
    proxyIfaceOpt.depends('acl_default_allow', '0');
    proxyIfaceOpt.validate = ifaceValidate;
    FirewallFormUtils.appendInterfaceOptions(proxyIfaceOpt, aclContext.interfaces);

    // 开启模式：不走代理设备（MAC）
    let excludeMacOpt = s.taboption('acl', form.DynamicList, 'proxy_mac_exclude_list', _('Non-Proxy Device'),
        _('Non-Proxy Device'));
    excludeMacOpt.datatype = 'macaddr';
    excludeMacOpt.rmempty = true;
    excludeMacOpt.depends('acl_default_allow', '1');
    FirewallFormUtils.appendHostHintOptions(excludeMacOpt, aclContext.hostHints);

    // 开启模式：不走代理接口
    let excludeIfaceOpt = s.taboption('acl', form.DynamicList, 'proxy_iface_exclude_list', _('Non-Proxy Interface'),
        _('Exclude client traffic entering through the selected logical network interfaces; WAN interfaces are always excluded'));
    excludeIfaceOpt.rmempty = true;
    excludeIfaceOpt.depends('acl_default_allow', '1');
    excludeIfaceOpt.validate = ifaceValidate;
    FirewallFormUtils.appendInterfaceOptions(excludeIfaceOpt, aclContext.interfaces);
}

export default v;
