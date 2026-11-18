import { vlessSecurity } from "../utils/feature/proxy/security";
import view from "view";
import editor from "hijpass.editor";
import uci from "uci";
import { CORE_TYPE, PROXY_CONFIG_TYPE, LuciFlied, HijpassValues, PROXY_TYPE, ProxyType } from "../enum/hijpass";
import form from "form";
import { SaveApplyUtils } from "../utils/actions/save-apply/index";
import { ServiceUtils } from "../utils/base/luci/service";
import { FormUtils } from "../utils/base/luci/form";
import { ValidationUtils } from "../utils/base/luci/validation";
import { UciUtils } from "../utils/base/luci/uci";
import { ProxyFormUtils } from "../utils/feature/proxy/form";
import { ProxyChainUtils } from "../utils/feature/proxy/chain";
import { findProxyDependencyCycleFrom } from "../utils/feature/proxy/validation";
import { NotificationUtils } from "../utils/base/luci/notification";

function getProxyReferrers(nodeName: string): string[] {
    return ProxyChainUtils.getProxySections()
        .filter((section: any) => ProxyChainUtils.getProxyDependencies(section).includes(nodeName))
        .map((section: any) => ProxyChainUtils.getProxyName(section));
}

function getFirewallReferrers(listenPort: string): string[] {
    if (!listenPort) return [];

    const referrers: string[] = [];
    if (uci.get_first(LuciFlied.CONF_NAME, LuciFlied.FIREWALL_SECTION_TYPE, 'proxy_port') === listenPort) {
        referrers.push(_('Proxy Port'));
    }
    if (uci.get_first(LuciFlied.CONF_NAME, LuciFlied.FIREWALL_SECTION_TYPE, 'shunt_port') === listenPort) {
        referrers.push(_('Default Shunt Port'));
    }
    return referrers;
}

const v = view.extend({
    load: function () {
        return Promise.all([
            uci.load(LuciFlied.CONF_NAME),
            ServiceUtils.getServiceInstances(LuciFlied.CONF_NAME)
        ]);
    },

    handleSaveApply: SaveApplyUtils.genHandleSaveApply(),
    handleSave: function (ev?: Event) {
        return view.prototype.handleSave.call(this, ev);
    },
    render: async function (data: any[]) {
        let m = new form.Map(LuciFlied.CONF_NAME, _('Proxy Nodes'),
            _('Configure Proxy Nodes'));
        ProxyFormUtils.createShareLinkImportSection(m);

        let s = m.section(form.GridSection, LuciFlied.PROXY_NODE_TYPE)
        FormUtils.setAnonymousGridSectionMembers(s);

        // 重写 handleAdd 方法，使用自定义的唯一 ID 生成器
        s.handleAdd = function (ev: Event) {
            let sectionId = UciUtils.generateUniqueSectionId(LuciFlied.CONF_NAME);
            return L.bind(form.GridSection.prototype.handleAdd, this, ev, sectionId)();
        };
        s.handleRemove = function (sectionId: string, ev: Event) {
            const nodeName = uci.get(LuciFlied.CONF_NAME, sectionId, 'name') || sectionId;
            const listenPort = uci.get(LuciFlied.CONF_NAME, sectionId, 'listen_port');
            const firewallReferrers = getFirewallReferrers(listenPort);
            if (firewallReferrers.length > 0) {
                NotificationUtils.warning(
                    _('Cannot Delete Proxy Node'),
                    _('Proxy node "%s" listen port %s is referenced by firewall settings: %s. Remove the references first.')
                        .format(nodeName, listenPort, firewallReferrers.join(', ')),
                    8000
                );
                return;
            }
            const referrers = getProxyReferrers(nodeName);
            if (referrers.length > 0) {
                NotificationUtils.warning(
                    _('Cannot Delete Proxy Node'),
                    _('Proxy node "%s" is referenced by proxy nodes: %s. Remove the references first.')
                        .format(nodeName, referrers.join(', ')),
                    8000
                );
                return;
            }
            return form.GridSection.prototype.handleRemove.call(this, sectionId, ev);
        };
        const instances = data[1] ?? {};
        createProxyOptions(s, instances);

        return E('div', {}, [
            E('style', {}, `.cbi-value[data-name="custom_conf"] > .cbi-value-field {
                    width:100%; min-width:0;
                }
                .cbi-value[data-name="custom_conf"] .cm-editor {
                    min-width:18rem; max-width:56rem; height:26rem; min-height:min(16rem, 60vh); max-height:60vh;
                }
                @media (max-width:1366px) {
                    .cbi-value[data-name="custom_conf"] .cm-editor { min-width:16rem; }
                }`),
            await m.render(),
        ]);
    },
});

/**
 * 创建启用状态选项
 */
function createEnabledOption(s: LuCI.form.AbstractSection) {
    let o = s.option(form.Flag, 'enabled', _('Enable'), '');
    o.modalonly = true;
    o.default = '1';
    o.rmempty = false;
    return o;
}

/**
 * 创建节点名称编辑选项
 */
function createNodeNameOption(s: LuCI.form.AbstractSection) {
    let o = s.option(form.Value, 'name', _('Node Name'),
        _('Modify Proxy Node Name'));
    o.modalonly = true;
    o.validate = ValidationUtils.createTagValidator(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, 'name')
    return o;
}

/**
 * 创建Grid表格显示选项
 */
function createGridDisplayOptions(s: LuCI.form.AbstractSection, instances: any) {
    let typeOpt = s.option(form.TextValue, 'type', _('Type'), _('Proxy Type'));
    typeOpt.modalonly = false;
    typeOpt.textvalue = function (section_id: string) {
        return ProxyFormUtils.renderProxyType(section_id);
    };

    // 显示服务器信息（不同类型显示不同内容）
    let serverInfoOpt = s.option(form.TextValue, 'server_info', _('Configuration Info'), '');
    serverInfoOpt.modalonly = false;
    serverInfoOpt.textvalue = function (section_id: string) {
        return ProxyFormUtils.renderProxyServerInfo(section_id);
    };

    // 运行状态列
    let statusOpt = s.option(form.TextValue, 'run_status', _('Status'), '');
    statusOpt.modalonly = false;
    statusOpt.textvalue = function (section_id: string) {
        return ProxyFormUtils.renderRunStatus(section_id, instances);
    };

    // 启用状态（在表格中显示并可直接修改）
    let enabledOpt = createEnabledOption(s);
    enabledOpt.editable = true;
    enabledOpt.modalonly = false;

    // 操作列：预览 / 日志 / 测速，三个按钮合并在一列
    let actionsOpt = s.option(form.TextValue, 'actions', '');
    actionsOpt.modalonly = false;
    actionsOpt.textvalue = function (section_id: string) {
        return ProxyFormUtils.createGridActionButtons(section_id);
    };
}

/**
 * 创建自定义代理的特定选项
 */
function createCustomProxyOptions(s: LuCI.form.AbstractSection) {
    // 运行命令，{conf_path} 为配置文件路径占位符
    let cmdOpt = s.option(form.Value, 'command', _('Run Command'),
        _("Executed as root. Use {conf_path} for this node configuration file path."));
    cmdOpt.validate = function (_id: string, value: string) { return value.trim() ? true : _('Proxy Run Command'); };
    cmdOpt.rmempty = false;
    cmdOpt.modalonly = true;
    cmdOpt.depends('config_type', PROXY_CONFIG_TYPE.CUSTOM);

    // 配置位置和命名由后端根据节点标识解析。
    let confOpt = s.option(form.TextValue, 'custom_conf', _('Configuration File Content'),
        _("Configuration passed to the run command; enter the complete file contents."));
    confOpt.modalonly = true;
    confOpt.depends('config_type', PROXY_CONFIG_TYPE.CUSTOM);
    FormUtils.setConfContentOptionMembers(confOpt, LuciFlied.CONF_NAME);
    editor.configure(confOpt, 'json', _('Configuration File Content'));
}

/**
 * 创建自定义代理的环境变量和日志选项
 */
function createProxyEnvironmentOptions(s: LuCI.form.AbstractSection) {
    let procdEnvOpt = s.option(form.DynamicList, 'procd_env', _('Procd Environment Variables'),
        _("One NAME=value entry per line, passed to this node process."));
    procdEnvOpt.modalonly = true;

    let logLevelOpt = s.option(form.ListValue, 'log_level', _('Log Level'), _('Core Log Level'));
    logLevelOpt.modalonly = true;
    logLevelOpt.default = 'info';
    logLevelOpt.rmempty = false;
    logLevelOpt.depends('config_type', PROXY_CONFIG_TYPE.GENERATED);
    HijpassValues.PROXY_LOG_LEVELS.forEach(level => logLevelOpt.value(level));

    FormUtils.createLogFlagOption(s)
}

function addLoadBalanceDepends(o: LuCI.form.AbstractValue, core?: string) {
    if (core) {
        o.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core});
        return;
    }
    o.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.SING_BOX});
    o.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY});
}

function createLoadBalanceOptions(s: LuCI.form.AbstractSection) {
    const members = s.option(form.DynamicList, 'member_node', _('Load Balancing Nodes'),
        _('Select proxy nodes to connect through their local SOCKS ports'));
    members.modalonly = true;
    members.rmempty = false;
    addLoadBalanceDepends(members);
    members.load = function (sectionId: string) {
        delete this.keylist;
        delete this.vallist;

        const currentName = this.section.formvalue(sectionId, 'name')
            || uci.get(LuciFlied.CONF_NAME, sectionId, 'name')
            || sectionId;
        ProxyChainUtils.getProxySections().forEach((section: any) => {
            const name = ProxyChainUtils.getProxyName(section);
            if (!name
                || name === currentName
                || section['.name'] === sectionId
                || !ProxyChainUtils.isCustomProxy(section) && section.type === PROXY_TYPE.LOAD_BALANCE) {
                return;
            }

            let label = name;
            if (section.socks_port) label += ' (' + section.socks_port + ')';
            if (section.enabled !== '1') label += ' - ' + _('Disabled');
            this.value(name, label);
        });
        return form.DynamicList.prototype.load.apply(this, [sectionId]);
    };
    members.validate = function (sectionId: string, value: string) {
        if (!value) return true;
        const currentName = this.section.formvalue(sectionId, 'name')
            || uci.get(LuciFlied.CONF_NAME, sectionId, 'name')
            || sectionId;
        if (value === currentName) return _('Load balancing node cannot include itself');

        const sections = ProxyChainUtils.getProxySectionMap();
        const member = sections.get(value);
        if (!member) return _('Load balancing member node not found');
        if (!ProxyChainUtils.isCustomProxy(member) && member.type === PROXY_TYPE.LOAD_BALANCE) {
            return _('Nested load balancing nodes are not supported');
        }
        const dependencyCycle = findProxyDependencyCycleFrom(currentName, [value], sections);
        if (dependencyCycle) {
            return _('Proxy node dependency chain has a cycle: %s').format(dependencyCycle.join(' -> '));
        }
        if (member.enabled !== '1') return _('Load balancing member node is not enabled');
        if (!ProxyChainUtils.isPort(member.socks_port)) {
            return _('Load balancing member node has no valid SOCKS port configured');
        }
        return true;
    };

    const url = s.option(form.Value, 'url', _('Test URL'), _('Health Check URL'));
    url.modalonly = true;
    url.default = 'https://www.gstatic.com/generate_204';
    addLoadBalanceDepends(url, CORE_TYPE.SING_BOX);

    const interval = s.option(form.Value, 'interval', _('Test Interval'), _('Health Check Interval'));
    interval.modalonly = true;
    interval.default = '3m';
    addLoadBalanceDepends(interval, CORE_TYPE.SING_BOX);

    const tolerance = s.option(form.Value, 'tolerance', _('Tolerance (ms)'), _('Tolerance'));
    tolerance.modalonly = true;
    tolerance.default = '50';
    tolerance.datatype = 'uinteger';
    addLoadBalanceDepends(tolerance, CORE_TYPE.SING_BOX);

    const idleTimeout = s.option(form.Value, 'idle_timeout', _('Idle Timeout'), _('Node Idle Timeout'));
    idleTimeout.modalonly = true;
    idleTimeout.default = '30m';
    addLoadBalanceDepends(idleTimeout, CORE_TYPE.SING_BOX);

    const interrupt = s.option(form.Flag, 'interrupt_exist_connections', _('Interrupt Existing Connections'),
        _('Interrupt on Outbound Change'));
    interrupt.modalonly = true;
    interrupt.default = '0';
    addLoadBalanceDepends(interrupt, CORE_TYPE.SING_BOX);

    const strategy = s.option(form.ListValue, 'strategy', _('Load Strategy'), _('Load Balancing Strategy'));
    strategy.modalonly = true;
    strategy.default = 'leastLoad';
    strategy.value('random', _('Random'));
    strategy.value('roundRobin', _('Round Robin'));
    strategy.value('leastPing', _('Lowest Ping'));
    strategy.value('leastLoad', _('Lowest Load'));
    addLoadBalanceDepends(strategy, CORE_TYPE.XRAY);

    const expected = s.option(form.Value, 'strategy_expected', _('Best Nodes'), _('Best Nodes Count'));
    expected.modalonly = true;
    expected.default = '1';
    expected.datatype = 'uinteger';
    expected.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastLoad'});

    const maxRtt = s.option(form.Value, 'strategy_max_rtt', _('Max Acceptable RTT'), _('Max Acceptable RTT'));
    maxRtt.modalonly = true;
    maxRtt.default = '1s';
    maxRtt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastLoad'});

    const strategyTolerance = s.option(form.Value, 'strategy_tolerance', _('Failure Rate Tolerance'),
        _('Failure Rate Tolerance'));
    strategyTolerance.modalonly = true;
    strategyTolerance.default = '0.05';
    strategyTolerance.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastLoad'});

    const fallback = s.option(form.ListValue, 'fallback_tag', _('Fallback Node'), _('Fallback Outbound'));
    fallback.modalonly = true;
    fallback.value('', _('First member node'));
    fallback.load = function (sectionId: string) {
        delete this.keylist;
        delete this.vallist;
        this.value('', _('First member node'));
        const currentName = this.section.formvalue(sectionId, 'name')
            || uci.get(LuciFlied.CONF_NAME, sectionId, 'name')
            || sectionId;
        ProxyChainUtils.getProxySections().forEach((section: any) => {
            const name = ProxyChainUtils.getProxyName(section);
            if (!name || name === currentName || !ProxyChainUtils.isCustomProxy(section) && section.type === PROXY_TYPE.LOAD_BALANCE) return;
            this.value(name, name);
        });
        return form.ListValue.prototype.load.apply(this, [sectionId]);
    };
    fallback.validate = function (sectionId: string, value: string) {
        if (!value) return true;
        const selected = ProxyChainUtils.normalizeProxyNodeList(this.section.formvalue(sectionId, 'member_node'));
        return selected.indexOf(value) >= 0 ? true : _('Fallback node must be a load balancing member');
    };
    addLoadBalanceDepends(fallback, CORE_TYPE.XRAY);

    const probeFields: Array<[string, string, string, string]> = [
        ['probe_url', _('Probe URL'), _('Health Check Probe URL'), 'https://connectivitycheck.gstatic.com/generate_204'],
        ['probe_connectivity', _('Local Connectivity Check URL'), _('Local Connectivity Check URL'), ''],
        ['probe_interval', _('Probe Interval'), _('Probe Interval'), '1m'],
        ['probe_timeout', _('Probe Timeout'), _('Probe Timeout'), '5s'],
    ];
    probeFields.forEach(([name, title, description, defaultValue]) => {
        const option = s.option(form.Value, name, title, description);
        option.modalonly = true;
        if (defaultValue) option.default = defaultValue;
        option.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastPing'});
        option.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastLoad'});
    });

    const sampling = s.option(form.Value, 'probe_sampling', _('Results to Retain'), _('Retain Recent Probe Results'));
    sampling.modalonly = true;
    sampling.default = '10';
    sampling.datatype = 'uinteger';
    sampling.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastPing'});
    sampling.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastLoad'});

    const method = s.option(form.ListValue, 'probe_http_method', _('Probe HTTP Method'), _('Probe HTTP Method'));
    method.modalonly = true;
    method.value('', _('Default (HEAD)'));
    method.value('HEAD', 'HEAD');
    method.value('GET', 'GET');
    method.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastPing'});
    method.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.LOAD_BALANCE, core: CORE_TYPE.XRAY, strategy: 'leastLoad'});
}


/**
 * 创建通用的服务器地址和端口选项（用于所有需要server/server_port的协议）
 */
function createCommonServerOptions(s: LuCI.form.AbstractSection) {
    let serverAddrOpt = s.option(form.Value, 'server', _('Server Address'),
        _("Remote server IP or domain name, without a URL scheme or port."));
    serverAddrOpt.modalonly = true;
    serverAddrOpt.rmempty = false;
    ProxyFormUtils.forProtocols(serverAddrOpt, [PROXY_TYPE.HYSTERIA2, PROXY_TYPE.SHADOWSOCKS,
    PROXY_TYPE.TUIC, PROXY_TYPE.SHADOWTLS, PROXY_TYPE.VLESS]);

    let serverPortOpt = s.option(form.Value, 'server_port', _('Server Port'),
        _("Remote listening port; use the public port when port forwarding is configured."));
    serverPortOpt.datatype = 'port';
    serverPortOpt.modalonly = true;
    serverPortOpt.rmempty = false;
    ProxyFormUtils.forProtocols(serverPortOpt, [PROXY_TYPE.HYSTERIA2, PROXY_TYPE.SHADOWSOCKS,
    PROXY_TYPE.TUIC, PROXY_TYPE.SHADOWTLS, PROXY_TYPE.VLESS]);
}

/**
 * 创建Hysteria2代理的高级选项
 */
function createHysteria2AdvancedOptions(s: LuCI.form.AbstractSection) {
    let serverPortsOpt = s.option(form.DynamicList, 'server_ports', _('Port Hopping'),
        _('Port Hopping Range'));
    serverPortsOpt.modalonly = true;
    serverPortsOpt.datatype = 'portrange';
    serverPortsOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.SING_BOX });

    let hopIntervalOpt = s.option(form.Value, 'hop_interval', _('Port Hop Interval'),
        _('Port Hop Interval'));
    hopIntervalOpt.modalonly = true;
    // hop_interval 依赖于类型是 Hysteria2 且 server_ports 有值
    hopIntervalOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.SING_BOX, server_ports: /./ });

    let upMbpsOpt = s.option(form.Value, 'up_mbps', _('Uplink Speed'),
        _("Upload bandwidth in Mbps; use the available uplink capacity."));
    upMbpsOpt.datatype = 'uinteger';
    upMbpsOpt.modalonly = true;
    upMbpsOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.SING_BOX });
    upMbpsOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.XRAY });

    let downMbpsOpt = s.option(form.Value, 'down_mbps', _('Downlink Speed'),
        _("Download bandwidth in Mbps; use the available downlink capacity."));
    downMbpsOpt.datatype = 'uinteger';
    downMbpsOpt.modalonly = true;
    downMbpsOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.SING_BOX });
    downMbpsOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.XRAY });
}

/**
 * 创建Hysteria2代理的Xray核心独有选项
 */
function createHysteria2XrayOptions(s: LuCI.form.AbstractSection) {
    let udpIdleTimeoutOpt = s.option(form.Value, 'udp_idle_timeout', _('UDP Idle Timeout'),
        _('UDP connection idle timeout in seconds'));
    udpIdleTimeoutOpt.datatype = 'uinteger';
    udpIdleTimeoutOpt.modalonly = true;
    udpIdleTimeoutOpt.placeholder = '60';
    udpIdleTimeoutOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.XRAY });
}

/**
 * 创建Hysteria2代理的OBFS选项（sing-box 核心独有）
 */
function createHysteria2ObfsOptions(s: LuCI.form.AbstractSection) {
    let obfsTypeOpt = s.option(form.ListValue, 'obfs_type', _('OBFS Type'),
        _('QUIC Obfuscation Type'));
    obfsTypeOpt.modalonly = true;
    obfsTypeOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.SING_BOX });

    HijpassValues.HYSTERIA2_OBFS_TYPES.forEach((item) => {
        obfsTypeOpt.value(item.value, _(item.label));
    });

    let obfsPasswordOpt = s.option(form.Value, 'obfs_password', _('OBFS Password'),
        _("Salamander password; must match the server."));
    obfsPasswordOpt.modalonly = true;
    obfsPasswordOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.SING_BOX, obfs_type: 'salamander' });
}

/**
 * 创建VLESS代理的网络和packet_encoding选项
 * packet_encoding 只对 sing-box core 显示（xray 的 VLESS 不支持该字段）
 */
function createVlessNetworkOptions(s: LuCI.form.AbstractSection) {
    let packetEncodingOpt = s.option(form.ListValue, 'packet_encoding', _('UDP Packet Encoding'),
        _('UDP Packet Encoding Method'));
    packetEncodingOpt.modalonly = true;
    // packet_encoding 只对 sing-box core 有意义
    packetEncodingOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.VLESS, core: CORE_TYPE.SING_BOX });

    HijpassValues.VLESS_PACKET_ENCODINGS.forEach((item) => {
        packetEncodingOpt.value(item.value, _(item.label));
    });
}

/**
 * 创建通用传输层类型选择（用于支持Transport的协议：VLESS等）
 * - 所有传输类型统一注册（含 xhttp）
 * - HTTP 仅用于 sing-box，XHTTP 仅用于 Xray，保存时校验所选核心
 * - xhttp 相关子字段仅在 core:xray 时显示
 */
function createTransportTypeOption(s: LuCI.form.AbstractSection) {
    let transportOpt = s.option(form.ListValue, 'transport_type', _('Transport Protocol'),
        _("Leave empty for TCP. HTTP requires sing-box; XHTTP requires Xray. Match the peer transport."));
    transportOpt.modalonly = true;
    ProxyFormUtils.forProtocols(transportOpt, [PROXY_TYPE.VLESS]);

    HijpassValues.V2RAY_TRANSPORT_TYPES.forEach((item) => {
        transportOpt.value(item.value, _(item.label));
    });

    // sing-box 不支持 xhttp
    // 用 this.section.formvalue 读取表单中 core 字段的当前值（未保存的实时值），
    // 而非 uci.get（那只能读到上次保存的旧值）
    transportOpt.validate = function (sectionId: string, value: string) {
        const core = this.section.formvalue(sectionId, 'core');
        const security = this.section.formvalue(sectionId, 'security');
        if (value === 'xhttp' && core !== CORE_TYPE.XRAY) {
            return _('XHTTP transport is only supported by Xray core');
        }
        if (value === 'http' && core !== CORE_TYPE.SING_BOX) {
            return _('HTTP transport is only supported by sing-box core');
        }
        if (core === CORE_TYPE.XRAY && security === 'reality' && (value === 'ws' || value === 'httpupgrade')) {
            return _('Xray REALITY only supports RAW, XHTTP and gRPC transports');
        }
        return true;
    };
}

/**
 * 创建通用的HTTP传输选项（用于支持Transport的协议：VLESS等）
 */
function createTransportHttpOptions(s: LuCI.form.AbstractSection) {
    let hostOpt = s.option(form.Value, 'transport_http_host', _('HTTP Host'),
        _("HTTP Host sent to the server; if the server checks Host, use an accepted value."));
    hostOpt.modalonly = true;
    ProxyFormUtils.forCoreProtocols(hostOpt, CORE_TYPE.SING_BOX, [PROXY_TYPE.VLESS], { transport_type: 'http' });

    let pathOpt = s.option(form.Value, 'transport_http_path', _('HTTP Path'),
        _("Start with /, for example /proxy; match the path configured on the peer."));
    pathOpt.modalonly = true;
    ProxyFormUtils.forCoreProtocols(pathOpt, CORE_TYPE.SING_BOX, [PROXY_TYPE.VLESS], { transport_type: 'http' });

    let methodOpt = s.option(form.Value, 'transport_http_method', _('HTTP Method'),
        _("HTTP request method, for example PUT; match any method restriction on the server."));
    methodOpt.modalonly = true;
    ProxyFormUtils.forCoreProtocols(methodOpt, CORE_TYPE.SING_BOX, [PROXY_TYPE.VLESS], { transport_type: 'http' });

    let idleOpt = s.option(form.Value, 'transport_http_idle_timeout', _('Idle Timeout'),
        _("Duration such as 15s or 1m; HTTP/2 sends a health-check PING after this idle period."));
    idleOpt.modalonly = true;
    idleOpt.default = '15s';
    ProxyFormUtils.forCoreProtocols(idleOpt, CORE_TYPE.SING_BOX, [PROXY_TYPE.VLESS], { transport_type: 'http' });

    let pingOpt = s.option(form.Value, 'transport_http_ping_timeout', _('PING Timeout'),
        _("Duration to wait for an HTTP/2 PING reply, for example 15s."));
    pingOpt.modalonly = true;
    pingOpt.default = '15s';
    ProxyFormUtils.forCoreProtocols(pingOpt, CORE_TYPE.SING_BOX, [PROXY_TYPE.VLESS], { transport_type: 'http' });
}

/**
 * 创建通用的WebSocket传输选项（用于支持Transport的协议：VLESS等）
 */
function createTransportWsOptions(s: LuCI.form.AbstractSection) {
    let hostOpt = s.option(form.Value, 'transport_ws_host', _('WebSocket Host'),
        _("Host header sent with the WebSocket handshake; use the value required by the reverse proxy."));
    hostOpt.modalonly = true;
    ProxyFormUtils.forProtocols(hostOpt, [PROXY_TYPE.VLESS], { transport_type: 'ws' });

    let pathOpt = s.option(form.Value, 'transport_ws_path', _('WebSocket Path'),
        _("Start with /, for example /proxy; match the path configured on the peer."));
    pathOpt.modalonly = true;
    ProxyFormUtils.forProtocols(pathOpt, [PROXY_TYPE.VLESS], { transport_type: 'ws' });

    let earlyDataOpt = s.option(form.Value, 'transport_ws_max_early_data', _('Max Early Data'),
        _("Maximum early-data size in bytes; use the same setting on the server."));
    earlyDataOpt.datatype = 'uinteger';
    earlyDataOpt.modalonly = true;
    ProxyFormUtils.forProtocols(earlyDataOpt, [PROXY_TYPE.VLESS], { transport_type: 'ws' });

    let headerNameOpt = s.option(form.Value, 'transport_ws_early_data_header_name', _('Early Data Header Name'),
        _("Match the server; use Sec-WebSocket-Protocol for compatibility with Xray."));
    headerNameOpt.modalonly = true;
    ProxyFormUtils.forProtocols(headerNameOpt, [PROXY_TYPE.VLESS], { transport_type: 'ws' });
}

/**
 * 创建通用的gRPC传输选项（用于支持Transport的协议：VLESS等）
 */
function createTransportGrpcOptions(s: LuCI.form.AbstractSection) {
    let serviceOpt = s.option(form.Value, 'transport_grpc_service_name', _('gRPC Service Name'),
        _("gRPC service name; must match the server exactly."));
    serviceOpt.modalonly = true;
    serviceOpt.default = 'TunService';
    ProxyFormUtils.forProtocols(serviceOpt, [PROXY_TYPE.VLESS], { transport_type: 'grpc' });

    let idleOpt = s.option(form.Value, 'transport_grpc_idle_timeout', _('Idle Timeout'),
        _('Idle Timeout'));
    idleOpt.modalonly = true;
    idleOpt.default = '15s';
    ProxyFormUtils.forProtocols(idleOpt, [PROXY_TYPE.VLESS], { transport_type: 'grpc' });

    let pingOpt = s.option(form.Value, 'transport_grpc_ping_timeout', _('PING Timeout'),
        _('PING Response Timeout'));
    pingOpt.modalonly = true;
    pingOpt.default = '15s';
    ProxyFormUtils.forProtocols(pingOpt, [PROXY_TYPE.VLESS], { transport_type: 'grpc' });

    let permitOpt = s.option(form.Flag, 'transport_grpc_permit_without_stream', _('Permit Without Stream'),
        _('Send Keepalive Ping'));
    permitOpt.modalonly = true;
    ProxyFormUtils.forProtocols(permitOpt, [PROXY_TYPE.VLESS], { transport_type: 'grpc' });
}

/**
 * 创建通用的HTTPUpgrade传输选项（用于支持Transport的协议：VLESS等）
 */
function createTransportHttpupgradeOptions(s: LuCI.form.AbstractSection) {
    let hostOpt = s.option(form.Value, 'transport_httpupgrade_host', _('HTTPUpgrade Host'),
        _("HTTPUpgrade Host; must match the server value when Host verification is enabled."));
    hostOpt.modalonly = true;
    ProxyFormUtils.forProtocols(hostOpt, [PROXY_TYPE.VLESS], { transport_type: 'httpupgrade' });

    let pathOpt = s.option(form.Value, 'transport_httpupgrade_path', _('HTTPUpgrade Path'),
        _("Start with /, for example /proxy; match the path configured on the peer."));
    pathOpt.modalonly = true;
    ProxyFormUtils.forProtocols(pathOpt, [PROXY_TYPE.VLESS], { transport_type: 'httpupgrade' });
}

/**
 * 创建通用TLS配置选项（用于支持TLS的协议：Hysteria2、TUIC、ShadowTLS、VLESS）
 */
function createCommonTlsOptions(s: LuCI.form.AbstractSection) {
    let serverNameOpt = s.option(form.Value, 'tls_server_name', _('TLS Server Name'),
        _("TLS server name (SNI). For VLESS, empty uses the server address; REALITY must use an allowed server name."));
    serverNameOpt.modalonly = true;
    serverNameOpt.rmempty = true;
    serverNameOpt.validate = function (id: string, value: string) {
        return value || this.section.formvalue(id, 'type') === PROXY_TYPE.VLESS
            ? true : _('Expecting a non-empty value');
    };
    ProxyFormUtils.forProtocols(serverNameOpt, [PROXY_TYPE.HYSTERIA2, PROXY_TYPE.TUIC,
    PROXY_TYPE.SHADOWTLS]);
    for (const security of ['tls', 'reality']) {
        ProxyFormUtils.forProtocols(serverNameOpt, [PROXY_TYPE.VLESS], { security });
    }

    let insecureOpt = s.option(form.Flag, 'tls_insecure', _('Ignore Certificate Verification'),
        _("Skip server certificate verification; normally leave disabled."));
    insecureOpt.modalonly = true;
    insecureOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.SING_BOX });
    insecureOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.VLESS, core: CORE_TYPE.SING_BOX, security: 'tls' });
    ProxyFormUtils.forProtocols(insecureOpt, [PROXY_TYPE.TUIC, PROXY_TYPE.SHADOWTLS]);
}

/**
 * VLESS 安全方式使用互斥选项；读取旧配置时保留原来的 TLS 行为。
 */
function createVlessSecurityOption(s: LuCI.form.AbstractSection) {
    const option = s.option(form.ListValue, 'security', _('Transport Security'),
        _("None adds no transport encryption; TLS verifies a certificate; REALITY uses the server public key."));
    option.value('none', _('None'));
    option.value('tls', 'TLS');
    option.value('reality', 'REALITY');
    option.modalonly = true;
    option.rmempty = false;
    option.forcewrite = true;
    ProxyFormUtils.forProtocols(option, [PROXY_TYPE.VLESS]);
    option.load = (id: string) => vlessSecurity(uci.get(LuciFlied.CONF_NAME, id) || {});
    option.write = (id: string, value: string) => {
        uci.set(LuciFlied.CONF_NAME, id, 'security', value);
        uci.unset(LuciFlied.CONF_NAME, id, 'tls_reality_enabled');
    };
}

function createTlsRealityOptions(s: LuCI.form.AbstractSection) {
    let publicKeyOpt = s.option(form.Value, 'tls_reality_public_key', _('Reality Public Key'),
        _("Public key paired with the REALITY private key on the server."));
    publicKeyOpt.modalonly = true;
    ProxyFormUtils.forProtocols(publicKeyOpt, [PROXY_TYPE.VLESS], { security: 'reality' });

    let shortIdOpt = s.option(form.Value, 'tls_reality_short_id', _('Reality Short ID'),
        _("Use the same short ID on both ends: an even number of hexadecimal digits, up to 16; empty is allowed."));
    shortIdOpt.modalonly = true;
    ProxyFormUtils.forProtocols(shortIdOpt, [PROXY_TYPE.VLESS], { security: 'reality' });
}

/**
 * 创建Hysteria2代理的调试选项（sing-box 核心独有）
 */
function createHysteria2DebugOptions(s: LuCI.form.AbstractSection) {
    let o = s.option(form.Flag, 'brutal_debug', _('Enable Brutal CC Debug'),
        _('Enable Hysteria Brutal CC Debug'));
    o.modalonly = true;
    o.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.HYSTERIA2, core: CORE_TYPE.SING_BOX });
}

function createNetworkOption(s: LuCI.form.AbstractSection) {
    let networkOpt = s.option(form.ListValue, 'network', _('Network Protocol'),
        _('Enabled Network Protocols'));
    networkOpt.modalonly = true;
    networkOpt.default = '';
    networkOpt.value('', _('Default'));
    networkOpt.value('tcp', 'TCP');
    networkOpt.value('udp', 'UDP');
    ProxyFormUtils.forProtocols(networkOpt, [PROXY_TYPE.HYSTERIA2, PROXY_TYPE.SHADOWSOCKS,
    PROXY_TYPE.TUIC, PROXY_TYPE.VLESS]);
}

function createPasswordOption(s: LuCI.form.AbstractSection) {
    let passwordOpt = s.option(form.Value, 'password', _('Password'),
        _("Must match the server password or key for the selected protocol."));
    passwordOpt.modalonly = true;
    passwordOpt.password = true;
    passwordOpt.rmempty = false;
    ProxyFormUtils.forProtocols(passwordOpt, [PROXY_TYPE.HYSTERIA2, PROXY_TYPE.SHADOWSOCKS, PROXY_TYPE.TUIC]);
    // ShadowTLS v2/v3 only — compound depends, must stay separate
    ProxyFormUtils.forProtocols(passwordOpt, [PROXY_TYPE.SHADOWTLS], { version: '2' });
    ProxyFormUtils.forProtocols(passwordOpt, [PROXY_TYPE.SHADOWTLS], { version: '3' });
}

function createUuidOption(s: LuCI.form.AbstractSection) {
    let uuidOpt = s.option(form.Value, 'uuid', _('UUID'),
        _("User UUID configured on the server; copy it exactly."));
    uuidOpt.modalonly = true;
    uuidOpt.rmempty = false;
    ProxyFormUtils.forProtocols(uuidOpt, [PROXY_TYPE.VLESS, PROXY_TYPE.TUIC]);
}

function createMultiplexOptions(s: LuCI.form.AbstractSection) {
    const muxTypes: ProxyType[] = [PROXY_TYPE.SHADOWSOCKS, PROXY_TYPE.VLESS];

    const xrayEnabled = s.option(form.Flag, 'mux_enabled', _('Enable Multiplexing'),
        _('Use Xray Mux.Cool; the server handles it automatically.'));
    xrayEnabled.modalonly = true;
    ProxyFormUtils.forCoreProtocols(xrayEnabled, CORE_TYPE.XRAY, muxTypes);
    const xrayDependencies = muxTypes.map(type => ({ config_type: PROXY_CONFIG_TYPE.GENERATED,
        type, core: CORE_TYPE.XRAY, mux_enabled: '1' }));
    for (const [key, label, maximum, value, description] of [
        ['mux_concurrency', _('TCP Multiplex Concurrency'), 128, '8',
            _('Streams per TCP connection (1–128); 0 uses 8, -1 disables TCP multiplexing. Vision requires -1.')],
        ['mux_xudp_concurrency', _('XUDP Concurrency'), 1024, '16',
            _('UDP streams per XUDP connection (1–1024); 0 shares the TCP path, -1 uses native UDP handling.')],
    ] as const) {
        const option = s.option(form.Value, key, label, description);
        option.modalonly = true;
        option.default = value;
        option.rmempty = false;
        option.datatype = `range(-1,${maximum})`;
        xrayDependencies.forEach(dependency => option.depends(dependency));
        option.validate = function (id: string, value: string) {
            if (!/^-?\d+$/.test(value) || Number(value) < -1 || Number(value) > maximum)
                return _('Invalid multiplex concurrency');
            if (key === 'mux_concurrency' && this.section.formvalue(id, 'type') === PROXY_TYPE.VLESS
                && this.section.formvalue(id, 'flow') && Number(value) >= 0)
                return _('Vision requires Mux TCP concurrency -1; use XUDP for UDP multiplexing');
            return true;
        };
    }
    const udp443 = s.option(form.ListValue, 'mux_udp443', _('Mux UDP/443 Policy'),
        _('Handle QUIC traffic: reject, carry over Mux, or bypass Mux using the proxy protocol.'));
    udp443.modalonly = true;
    udp443.default = 'reject';
    udp443.rmempty = false;
    udp443.value('reject', _('Reject'));
    udp443.value('allow', _('Allow over Mux'));
    udp443.value('skip', _('Bypass Mux'));
    xrayDependencies.forEach(dependency => udp443.depends(dependency));

    let enabledOpt = s.option(form.Flag, 'multiplex_enabled', _('Enable Multiplexing'),
        _('Enable Multiplexing for Better Efficiency'));
    enabledOpt.modalonly = true;
    ProxyFormUtils.forCoreProtocols(enabledOpt, CORE_TYPE.SING_BOX, muxTypes);

    let protocolOpt = s.option(form.ListValue, 'multiplex_protocol', _('Multiplexing Protocol'),
        _('Multiplexing Protocol'));
    protocolOpt.modalonly = true;
    protocolOpt.default = 'h2mux';
    muxTypes.forEach(t => protocolOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: t, core: CORE_TYPE.SING_BOX, multiplex_enabled: '1' }));
    HijpassValues.MULTIPLEX_PROTOCOLS.forEach(item => protocolOpt.value(item.value, item.label));

    let maxConnOpt = s.option(form.Value, 'multiplex_max_connections', _('Max Connections'),
        _('Max Connections'));
    maxConnOpt.datatype = 'uinteger';
    maxConnOpt.modalonly = true;
    muxTypes.forEach(t => maxConnOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: t, core: CORE_TYPE.SING_BOX, multiplex_enabled: '1' }));

    let minStreamsOpt = s.option(form.Value, 'multiplex_min_streams', _('Min Streams'),
        _('Min Concurrent Streams'));
    minStreamsOpt.datatype = 'uinteger';
    minStreamsOpt.modalonly = true;
    muxTypes.forEach(t => minStreamsOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: t, core: CORE_TYPE.SING_BOX, multiplex_enabled: '1' }));

    let maxStreamsOpt = s.option(form.Value, 'multiplex_max_streams', _('Max Streams'),
        _('Max Concurrent Streams'));
    maxStreamsOpt.datatype = 'uinteger';
    maxStreamsOpt.modalonly = true;
    muxTypes.forEach(t => maxStreamsOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: t, core: CORE_TYPE.SING_BOX, multiplex_enabled: '1' }));

    const paddingOpt = s.option(form.Flag, 'multiplex_padding', _('Multiplex Padding'),
        _('Enable padding when required by the sing-box server.'));
    paddingOpt.modalonly = true;
    muxTypes.forEach(type => paddingOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,
        type, core: CORE_TYPE.SING_BOX, multiplex_enabled: '1' }));

    let brutalEnabledOpt = s.option(form.Flag, 'multiplex_brutal_enabled', _('Enable TCP Brutal'),
        _('Enable TCP Brutal Congestion Control'));
    brutalEnabledOpt.modalonly = true;
    muxTypes.forEach(t => brutalEnabledOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: t, core: CORE_TYPE.SING_BOX, multiplex_enabled: '1' }));

    let brutalUpOpt = s.option(form.Value, 'multiplex_brutal_up_mbps', _('Uplink Bandwidth'),
        _('Uplink Bandwidth'));
    brutalUpOpt.datatype = 'uinteger';
    brutalUpOpt.modalonly = true;
    muxTypes.forEach(t => brutalUpOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: t, core: CORE_TYPE.SING_BOX, multiplex_enabled: '1', multiplex_brutal_enabled: '1' }));

    let brutalDownOpt = s.option(form.Value, 'multiplex_brutal_down_mbps', _('Downlink Bandwidth'),
        _('Downlink Bandwidth'));
    brutalDownOpt.datatype = 'uinteger';
    brutalDownOpt.modalonly = true;
    muxTypes.forEach(t => brutalDownOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: t, core: CORE_TYPE.SING_BOX, multiplex_enabled: '1', multiplex_brutal_enabled: '1' }));
}

/**
 * 创建Shadowsocks代理的加密和密码选项
 */
function createShadowsocksEncryptionOptions(s: LuCI.form.AbstractSection) {
    let methodOpt = s.option(form.ListValue, 'method', _('Encryption Method'),
        _('Shadowsocks Encryption Method'));
    methodOpt.modalonly = true;
    methodOpt.rmempty = false;
    methodOpt.default = '2022-blake3-aes-256-gcm';
    ProxyFormUtils.forProtocols(methodOpt, [PROXY_TYPE.SHADOWSOCKS]);

    HijpassValues.SHADOWSOCKS_METHODS.forEach((item) => {
        methodOpt.value(item.value, item.label);
    });
}

/**
 * 创建Shadowsocks代理的插件选项
 */
function createShadowsocksPluginOptions(s: LuCI.form.AbstractSection) {
    let pluginOpt = s.option(form.ListValue, 'plugin', _('Plugin'),
        _('Shadowsocks SIP003 Plugin'));
    pluginOpt.modalonly = true;
    pluginOpt.value('', _('None'));
    pluginOpt.value('obfs-local', 'obfs-local');
    pluginOpt.value('v2ray-plugin', 'v2ray-plugin');
    ProxyFormUtils.forProtocols(pluginOpt, [PROXY_TYPE.SHADOWSOCKS]);

    let pluginOptsOpt = s.option(form.Value, 'plugin_opts', _('Plugin Options'),
        _('Shadowsocks SIP003 Plugin Options'));
    pluginOptsOpt.modalonly = true;
    // plugin_opts 依赖于类型是 Shadowsocks 且 plugin 有值
    ProxyFormUtils.forProtocols(pluginOptsOpt, [PROXY_TYPE.SHADOWSOCKS], { plugin: /./ });
}

/**
 * 创建Shadowsocks代理的网络选项
 */
function createShadowsocksNetworkOptions(s: LuCI.form.AbstractSection) {
    let udpOverTcpOpt = s.option(form.Flag, 'udp_over_tcp', _('UDP over TCP'),
        _('Enable UDP over TCP'));
    udpOverTcpOpt.modalonly = true;
    ProxyFormUtils.forProtocols(udpOverTcpOpt, [PROXY_TYPE.SHADOWSOCKS]);
}

/**
 * 创建TUIC代理的高级选项
 */
function createTuicAdvancedOptions(s: LuCI.form.AbstractSection) {
    let congestionOpt = s.option(form.ListValue, 'congestion_control', _('Congestion Control'),
        _('QUIC Congestion Control'));
    congestionOpt.modalonly = true;
    congestionOpt.default = 'cubic';
    ProxyFormUtils.forProtocols(congestionOpt, [PROXY_TYPE.TUIC]);

    HijpassValues.TUIC_CONGESTION_CONTROLS.forEach((item) => {
        congestionOpt.value(item.value, item.label);
    });

    let udpRelayOpt = s.option(form.ListValue, 'udp_relay_mode', _('UDP Relay Mode'),
        _('UDP Packet Relay Mode'));
    udpRelayOpt.modalonly = true;
    udpRelayOpt.default = '';
    // udp_relay_mode 依赖于 udp_over_stream 未启用
    ProxyFormUtils.forProtocols(udpRelayOpt, [PROXY_TYPE.TUIC], { udp_over_stream: '0' });

    udpRelayOpt.value('', _('None'));
    HijpassValues.TUIC_UDP_RELAY_MODES.forEach((item) => {
        udpRelayOpt.value(item.value, _(item.label));
    });

    let udpOverStreamOpt = s.option(form.Flag, 'udp_over_stream', _('UDP over Stream'),
        _('Use UDP Stream Relay'));
    udpOverStreamOpt.modalonly = true;
    ProxyFormUtils.forProtocols(udpOverStreamOpt, [PROXY_TYPE.TUIC]);

    let zero_rttOpt = s.option(form.Flag, 'zero_rtt_handshake', _('0-RTT Handshake'),
        _('Enable 0-RTT QUIC Handshake'));
    zero_rttOpt.modalonly = true;
    ProxyFormUtils.forProtocols(zero_rttOpt, [PROXY_TYPE.TUIC]);

    let heartbeatOpt = s.option(form.Value, 'heartbeat', _('Heartbeat Interval'),
        _('Heartbeat Interval'));
    heartbeatOpt.modalonly = true;
    heartbeatOpt.default = '10s';
    ProxyFormUtils.forProtocols(heartbeatOpt, [PROXY_TYPE.TUIC]);
}

/**
 * 创建ShadowTLS代理的版本和密码选项
 */
function createShadowTLSAuthOptions(s: LuCI.form.AbstractSection) {
    let versionOpt = s.option(form.ListValue, 'version', _('Protocol Version'),
        _('ShadowTLS Protocol Version'));
    versionOpt.modalonly = true;
    versionOpt.default = '1';
    ProxyFormUtils.forProtocols(versionOpt, [PROXY_TYPE.SHADOWTLS]);

    HijpassValues.SHADOWTLS_VERSIONS.forEach((item) => {
        versionOpt.value(item.value, item.label);
    });
}

/**
 * 创建VLESS代理的认证选项
 * flow (XTLS Vision) 对 sing-box 和 xray 均支持
 */
function createVlessAuthOptions(s: LuCI.form.AbstractSection) {
    let flowOpt = s.option(form.ListValue, 'flow', _('VLESS Flow Control'),
        _("Use Vision only with TCP and TLS or REALITY; match the server flow. Leave empty otherwise."));
    flowOpt.modalonly = true;
    // sing-box 和 xray 均支持 flow: xtls-rprx-vision
    ProxyFormUtils.forProtocols(flowOpt, [PROXY_TYPE.VLESS]);

    HijpassValues.VLESS_FLOWS.forEach((item) => {
        flowOpt.value(item.value, _(item.label));
    });
}

/**
 * 创建通用的XHTTP传输选项（Xray 核心专用，sing-box 不支持 xhttp transport）
 */
function createTransportXhttpOptions(s: LuCI.form.AbstractSection) {
    let hostOpt = s.option(form.Value, 'transport_xhttp_host', _('XHTTP Host'),
        _("HTTP Host used for XHTTP; match the reverse proxy and any server Host restriction."));
    hostOpt.modalonly = true;
    hostOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.VLESS, core: CORE_TYPE.XRAY, transport_type: 'xhttp' });

    let pathOpt = s.option(form.Value, 'transport_xhttp_path', _('XHTTP Path'),
        _("Start with /, for example /proxy; match the path configured on the peer."));
    pathOpt.modalonly = true;
    pathOpt.default = '/';
    pathOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.VLESS, core: CORE_TYPE.XRAY, transport_type: 'xhttp' });

    let modeOpt = s.option(form.ListValue, 'transport_xhttp_mode', _('XHTTP Mode'),
        _("Prefer auto. packet-up sends separate upload requests; stream-up and stream-one use streaming."));
    modeOpt.modalonly = true;
    modeOpt.default = 'auto';
    modeOpt.value('auto', _('Auto'));
    modeOpt.value('packet-up', 'packet-up');
    modeOpt.value('stream-one', 'stream-one');
    modeOpt.value('stream-up', 'stream-up');
    modeOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED,  type: PROXY_TYPE.VLESS, core: CORE_TYPE.XRAY, transport_type: 'xhttp' });

    const methodOpt = s.option(form.Value, 'transport_xhttp_method', _('HTTP Method'),
        _("Optional XHTTP upload method, for example PUT; match the server setting."));
    methodOpt.modalonly = true;
    methodOpt.depends({ config_type: PROXY_CONFIG_TYPE.GENERATED, type: PROXY_TYPE.VLESS, core: CORE_TYPE.XRAY, transport_type: 'xhttp' });
}


/**
 * 创建所有代理配置选项
 */
function createProxyOptions(s: LuCI.form.AbstractSection, instances: any) {
    // Grid表格显示选项（所有类型都显示）
    createGridDisplayOptions(s, instances);

    // 通用选项（所有类型都需要）
    createNodeNameOption(s);
    createEnabledOption(s);
    ProxyFormUtils.createCoreAndTypeOptions(s);
    ProxyFormUtils.createUpstreamProxyNodeOption(s);
    createLoadBalanceOptions(s);

    // 类型特定的选项 - 服务器地址和端口
    createCommonServerOptions(s);

    // 自定义代理选项
    createCustomProxyOptions(s);

    createUuidOption(s);
    createPasswordOption(s);

    // 通用TLS配置（供所有支持TLS的协议使用）
    createVlessSecurityOption(s);
    createCommonTlsOptions(s);

    createNetworkOption(s);
    createHysteria2AdvancedOptions(s);
    createHysteria2XrayOptions(s);
    createHysteria2ObfsOptions(s);
    createHysteria2DebugOptions(s);

    // Shadowsocks代理选项
    createShadowsocksEncryptionOptions(s);
    createShadowsocksPluginOptions(s);
    createShadowsocksNetworkOptions(s);

    createTuicAdvancedOptions(s);

    // ShadowTLS代理选项
    createShadowTLSAuthOptions(s);

    // VLESS代理选项
    createVlessAuthOptions(s);
    createVlessNetworkOptions(s);

    // TLS Reality配置（供支持Reality的协议使用：VLESS等）
    createTlsRealityOptions(s);

    // 通用传输层配置（供支持Transport的协议使用：VLESS等）
    createTransportTypeOption(s);
    createTransportHttpOptions(s);
    createTransportWsOptions(s);
    createTransportGrpcOptions(s);
    createTransportHttpupgradeOptions(s);
    createTransportXhttpOptions(s);

    // 通用多路复用配置（供支持多路复用的协议使用：Shadowsocks、VLESS）
    createMultiplexOptions(s);
    // 通用的监听端口选项（所有代理类型都需要）
    ProxyFormUtils.createProxyPortOptions(s);
    createProxyEnvironmentOptions(s);
}

export default v;
