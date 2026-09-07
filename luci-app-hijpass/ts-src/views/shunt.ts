import {SaveApplyUtils} from "../utils/actions/save-apply/index";
import {ServiceUtils} from "../utils/base/luci/service";
import {FormUtils} from "../utils/base/luci/form";
import {ValidationUtils} from "../utils/base/luci/validation";
import {NotificationUtils} from "../utils/base/luci/notification";
import {ShuntFormUtils} from "../utils/feature/shunt/form";
import {ShuntUtils} from "../utils/feature/shunt/section";
import {CORE_TYPE, FIREWALL_DNS_FORWARD, HijpassValues, LuciFlied} from "../enum/hijpass";
import {FirewallDnsForwardUtils} from "../utils/feature/firewall/dns-forward";
import form from "form";
import fs from "fs";
import view from 'view';
import uci from 'uci';

const XRAY_ROUTE_PROTOCOLS = ['http', 'tls', 'quic', 'bittorrent'];
type GeoRuleQueryType = 'geosite' | 'geoip';

function ensureInlineRuleQueryStyles() {
    if (document.getElementById('hijpass-inline-rule-query-styles')) {
        return;
    }

    const style = document.createElement('style');
    style.id = 'hijpass-inline-rule-query-styles';
    style.textContent = `
        .hijpass-rule-editor-query-layout {
            display: grid;
            grid-template-columns: auto minmax(14rem, 18rem);
            gap: 1rem;
            align-items: start;
            width: fit-content;
            max-width: 100%;
        }

        .cbi-value[data-name="domain_list"],
        .cbi-value[data-name="ip_list"] {
            display: flex;
            flex-wrap: wrap;
            align-items: flex-start;
        }

        .cbi-value[data-name="domain_list"] > .cbi-value-field,
        .cbi-value[data-name="ip_list"] > .cbi-value-field {
            display: block;
            flex: 1 1 0;
            min-width: 0;
        }

        .hijpass-rule-editor-query-layout > .hijpass-rule-editor,
        .hijpass-rule-editor-query-layout > .hijpass-inline-rule-query {
            min-width: 0;
        }

        .hijpass-rule-editor-query-layout > .hijpass-rule-editor {
            width: 370px;
            max-width: 100%;
            overflow: hidden;
        }

        .hijpass-rule-editor-query-layout .hijpass-rule-editor textarea.cbi-input-textarea {
            box-sizing: border-box;
            display: block;
            width: 100%;
            min-width: 0;
            max-width: none;
            max-height: 50vh;
            resize: both;
        }

        .hijpass-inline-rule-query {
            display: flex;
            flex-direction: column;
            gap: .375rem;
            box-sizing: border-box;
            width: 100%;
            padding: .5rem;
            border: 1px solid rgba(127, 127, 127, .35);
            border-radius: 4px;
            background: rgba(127, 127, 127, .05);
        }

        .hijpass-inline-rule-query > .cbi-section-descr {
            margin: 0;
        }

        .hijpass-inline-rule-query-header {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            gap: .5rem;
            min-width: 0;
        }

        .hijpass-inline-rule-query-controls {
            display: grid;
            grid-template-columns: minmax(0, 1fr) auto;
            gap: .5rem;
            align-self: stretch;
            min-width: 0;
        }

        .hijpass-rule-editor-query-layout .hijpass-inline-rule-query-controls > input.cbi-input-text {
            box-sizing: border-box;
            min-width: 0;
            width: auto;
            max-width: none;
        }

        .hijpass-inline-rule-query-controls > .cbi-button {
            margin: 0;
            white-space: nowrap;
        }

        .hijpass-inline-rule-query-status {
            flex: 0 0 auto;
            min-height: 0;
            text-align: right;
            white-space: nowrap;
        }

        .hijpass-inline-rule-query-status[data-state="success"] {
            color: var(--success-color, #2e7d32);
        }

        .hijpass-inline-rule-query-status[data-state="error"] {
            color: var(--danger-color, #c62828);
        }

        .hijpass-rule-editor-query-layout textarea.hijpass-inline-rule-query-result {
            box-sizing: border-box;
            align-self: stretch;
            width: auto;
            min-width: 0;
            max-width: none;
            height: 5rem;
            min-height: 4rem;
            max-height: 50vh;
            resize: vertical;
        }

        @media (max-width: 900px) {
            .cbi-value[data-name="domain_list"],
            .cbi-value[data-name="ip_list"] {
                display: block;
            }

            .cbi-value[data-name="domain_list"] > .cbi-value-title,
            .cbi-value[data-name="ip_list"] > .cbi-value-title,
            .cbi-value[data-name="domain_list"] > .cbi-value-field,
            .cbi-value[data-name="ip_list"] > .cbi-value-field {
                box-sizing: border-box;
                display: block;
                float: none;
                width: 100%;
                margin-left: 0;
                text-align: left;
            }

            .hijpass-rule-editor-query-layout {
                grid-template-columns: minmax(0, 1fr);
                width: 100%;
            }

            .hijpass-rule-editor-query-layout > .hijpass-rule-editor,
            .hijpass-rule-editor-query-layout .hijpass-rule-editor textarea.cbi-input-textarea {
                width: 100%;
                max-width: 100%;
            }
        }
    `;
    document.head.appendChild(style);
}

function createGeoRuleQuery(
    queryType: GeoRuleQueryType,
    editorId: string
): HTMLElement {
    const titleId = editorId + '-query-title';
    const inputId = editorId + '-query-keyword';
    const tagPrefix = queryType + ':';
    const statusElement = E('div', {
        'class': 'hijpass-inline-rule-query-status',
        'role': 'status',
        'aria-live': 'polite'
    }) as HTMLElement;
    const resultElement = E('textarea', {
        'class': 'cbi-input-textarea hijpass-inline-rule-query-result',
        'readonly': 'readonly',
        'placeholder': _('Query results will appear here'),
        'aria-label': _('Query Results')
    }) as HTMLTextAreaElement;
    const keywordInput = E('input', {
        'id': inputId,
        'class': 'cbi-input-text',
        'type': 'text',
        'placeholder': queryType === 'geosite' ? 'www.example.com / geosite:cn' : '1.1.1.1 / geoip:cn',
        'aria-label': _('Query Keyword')
    }) as HTMLInputElement;
    const queryButton = E('button', {
        'class': 'cbi-button cbi-button-action',
        'type': 'button'
    }, _('Query')) as HTMLButtonElement;
    const panel = E('div', {
        'class': 'hijpass-inline-rule-query',
        'role': 'group',
        'aria-labelledby': titleId
    }, [
        E('div', {'class': 'hijpass-inline-rule-query-header'}, [
            E('strong', {'id': titleId}, _('Geo Database Query')),
            statusElement
        ]),
        E('div', {'class': 'cbi-section-descr'}, queryType === 'geosite' ? [
            E('div', {}, _('Domain → GeoSite tags')),
            E('div', {}, _('geosite:tag → domains in tag'))
        ] : [
            E('div', {}, _('IP address → GeoIP tags')),
            E('div', {}, _('geoip:tag → networks in tag'))
        ]),
        E('div', {'class': 'hijpass-inline-rule-query-controls'}, [keywordInput, queryButton]),
        resultElement
    ]) as HTMLElement;

    const setStatus = function (message: string, state?: 'success' | 'error') {
        statusElement.textContent = message;
        if (state) {
            statusElement.dataset.state = state;
        } else {
            delete statusElement.dataset.state;
        }
    };

    const runQuery = async function () {
        if (queryButton.disabled) {
            return;
        }

        const keyword = keywordInput.value.trim();
        if (!keyword) {
            setStatus(_('Enter Query Keyword'), 'error');
            keywordInput.focus();
            return;
        }

        resultElement.value = '';

        queryButton.disabled = true;
        panel.setAttribute('aria-busy', 'true');
        setStatus(_('Querying'));
        try {
            const isTagQuery = keyword.toLowerCase().startsWith(tagPrefix);
            const queryValue = isTagQuery ? keyword.slice(tagPrefix.length).trim() : keyword;
            if (!queryValue) {
                setStatus(_('Enter Query Keyword'), 'error');
                keywordInput.focus();
                return;
            }

            const result = await fs.exec('/usr/lib/hijpass/geoview.sh',
                [isTagQuery ? '-e' : '-l', queryType, queryValue]);
            if (result.code !== 0) {
                throw new Error(result.stderr || _('Query Failed'));
            }

            let output = (result.stdout || '').trim();
            if (output) {
                if (!isTagQuery) {
                    output = output.split(/\r?\n/)
                        .filter(Boolean)
                        .map(tag => tagPrefix + tag)
                        .join('\n');
                }
                resultElement.value = output;
                setStatus(_('Query Complete'), 'success');
            } else {
                setStatus(_('No Matching Results'));
            }
        } catch (error) {
            console.log(error);
            setStatus(_('Query Failed'), 'error');
        } finally {
            queryButton.disabled = false;
            panel.removeAttribute('aria-busy');
        }
    };

    queryButton.addEventListener('click', function (event) {
        event.preventDefault();
        runQuery();
    });
    keywordInput.addEventListener('keydown', function (event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            runQuery();
        }
    });

    return panel;
}

function syncRuleEditorWidth(
    layout: HTMLElement,
    editor: HTMLElement,
    queryPanel: HTMLElement,
    textarea: HTMLTextAreaElement
) {
    if (typeof ResizeObserver === 'undefined') {
        return;
    }

    const mediaQuery = window.matchMedia('(max-width: 900px)');
    const initialTextareaWidth = textarea.style.width;
    let narrowLayout: boolean | null = null;
    let preferredWidth = 370;
    let appliedWidth = 0;
    let wasConnected = false;
    let observedField: HTMLElement | null = null;

    const updateWidth = function () {
        if (layout.isConnected) {
            wasConnected = true;
        } else if (wasConnected) {
            observer.disconnect();
            return;
        }

        if (mediaQuery.matches) {
            if (narrowLayout !== true) {
                editor.style.removeProperty('width');
                textarea.style.width = initialTextareaWidth;
            }
            narrowLayout = true;
            appliedWidth = 0;
            return;
        }

        if (narrowLayout === true) {
            editor.style.removeProperty('width');
            textarea.style.width = initialTextareaWidth;
            preferredWidth = 370;
        }
        narrowLayout = false;

        const field = layout.parentElement;
        if (!field || field.clientWidth === 0) {
            return;
        }
        if (field !== observedField) {
            observer.observe(field);
            observedField = field;
        }

        const currentWidth = textarea.offsetWidth;
        if (currentWidth > 0 && Math.abs(currentWidth - appliedWidth) > 1) {
            preferredWidth = currentWidth;
        }

        const gap = parseFloat(window.getComputedStyle(layout).columnGap) || 0;
        const availableWidth = field.clientWidth - queryPanel.offsetWidth - gap;
        if (availableWidth <= 0) {
            return;
        }

        const nextWidth = Math.min(preferredWidth, availableWidth);
        const width = nextWidth + 'px';
        appliedWidth = nextWidth;
        if (textarea.style.width !== width) {
            textarea.style.width = width;
        }
        if (editor.style.width !== width) {
            editor.style.width = width;
        }
    };

    const observer = new ResizeObserver(updateWidth);
    observer.observe(textarea);
    observer.observe(queryPanel);
    window.requestAnimationFrame(function () {
        updateWidth();
    });
}

function configureGeoRuleQuery(option: any, queryType: GeoRuleQueryType) {
    option.renderWidget = function (sectionId: string, optionIndex: number, cfgvalue: string): Node {
        const widget = form.TextValue.prototype.renderWidget.call(
            this, sectionId, optionIndex, cfgvalue) as HTMLElement;
        const editor = E('div', {'class': 'hijpass-rule-editor'}, [widget]) as HTMLElement;
        const queryPanel = createGeoRuleQuery(queryType, this.cbid(sectionId));
        const layout = E('div', {'class': 'hijpass-rule-editor-query-layout'}, [
            editor,
            queryPanel
        ]) as HTMLElement;
        const textarea = widget.querySelector('textarea.cbi-input-textarea') as HTMLTextAreaElement;
        if (textarea) {
            syncRuleEditorWidth(layout, editor, queryPanel, textarea);
        }
        return layout;
    };
}

function getCurrentShuntValue(section: LuCI.form.AbstractSection, option: string) {
    const shuntSection = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE);
    const sectionId = shuntSection?.['.name'];
    const lookup = sectionId ? section.map.lookupOption(option, sectionId) : null;
    return lookup ? lookup[0].formvalue(lookup[1]) : shuntSection?.[option];
}

function hasSplitDnsTarget(section: any, sectionId: string) {
    const ruleDTO = ShuntUtils.parseRuleList({
        domainList: section.formvalue(sectionId, 'domain_list') || '',
        ipList: section.formvalue(sectionId, 'ip_list') || '',
        network: [],
        protocol: [],
        port: [],
        portRange: []
    });
    const shuntType = getCurrentShuntValue(section, 'type');
    const rulesetConvert = getCurrentShuntValue(section, 'ruleset_convert');

    if (shuntType === CORE_TYPE.XRAY) {
        return ruleDTO.containDomain() || ruleDTO.geoSite.length > 0;
    }
    return ruleDTO.containDomain()
        || ruleDTO.containRuleSet()
        || (rulesetConvert === '1' && ruleDTO.geoSite.length > 0);
}

function getShuntDnsDependencyError(section: LuCI.form.AbstractSection, sectionId: string) {
    if (FirewallDnsForwardUtils.getSource() === FIREWALL_DNS_FORWARD.ROUTING) {
        return _('Firewall DNS forwarding is using Core DNS. Select another forwarding source in Firewall before disabling proxy routing.');
    }

    const dnsService = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE, 'dns_service');
    const directDns = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE, 'direct_dns');
    const proxyDns = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE, 'proxy_dns');
    const dnsListenPort = section.formvalue(sectionId, 'dns_listen_port');
    if (dnsService === 'chinadns-ng'
        && dnsListenPort
        && (directDns === '127.0.0.1#' + dnsListenPort
            || proxyDns === '127.0.0.1#' + dnsListenPort)) {
        return _('Independent DNS is using this Core DNS port. Change it in the Independent DNS module before disabling proxy routing.');
    }
    return null;
}

const v = view.extend({
    load: function () {
        return Promise.all([
            uci.load(LuciFlied.CONF_NAME)
        ]);
    },

    handleSave: async function (ev: Event) {
        try {
            await view.prototype.handleSave(ev)
        } catch (e) {
            console.log(e);
            NotificationUtils.error(_('Configuration Save Failed'), _(e.message), 5000);
        }
    },

    handleSaveApply: SaveApplyUtils.genHandleSaveApply(),

    render: function () {
        ensureInlineRuleQueryStyles();
        let m = new form.Map(LuciFlied.CONF_NAME, _('Proxy Routing'),
            _('Configure proxy core routing, DNS, and rule-set settings'));
        ServiceUtils.createStatusSection(m, 'shunt');

        let s = m.section(form.TypedSection, LuciFlied.SHUNT_SECTION_TYPE);
        s.anonymous = true;
        s.addremove = false;
        // 创建标签页
        createTabs(s);

        // 创建基础配置选项
        createBasicOptions(s);
        createConfigEditor(s);
        createRouteOptions(s);
        createDNSOptions(s);
        return m.render();
    }
})

// 创建基础配置选项
function createBasicOptions(s: LuCI.form.AbstractSection) {
    // 总开关
    let enabled = s.taboption('basic', form.Flag, 'enabled', _('Enable Shunt'), '');
    enabled.default = '1';
    enabled.rmempty = false;
    enabled.validate = function (sectionId: string, value: string) {
        if (value !== '0') {
            return true;
        }
        return getShuntDnsDependencyError(this.section, sectionId) || true;
    };
    enabled.renderWidget = function (sectionId: string, optionIndex: number, cfgvalue: string): Node {
        const widget = form.Flag.prototype.renderWidget.call(
            this, sectionId, optionIndex, cfgvalue) as HTMLElement;
        const checkbox = widget.querySelector('input[type="checkbox"]') as HTMLInputElement | null;
        checkbox?.addEventListener('change', (event: Event) => {
            if (checkbox.checked) {
                return;
            }

            const error = getShuntDnsDependencyError(this.section, sectionId);
            if (!error) {
                return;
            }

            checkbox.checked = true;
            event.stopImmediatePropagation();
            this.triggerValidation(sectionId);
            NotificationUtils.warning(_('Configuration conflict'), error, 8000);
        }, true);
        return widget;
    };

    // 分流类型
    let serviceType = s.taboption('basic', form.ListValue, 'type', _('Shunt Type'),
        _('Select Shunt Type'));
    HijpassValues.SHUNT_CONF_TYPE.forEach(function (type) {
        serviceType.value(type);
    })
    serviceType.default = CORE_TYPE.XRAY;
    serviceType.rmempty = false;

    let configType = s.taboption('basic', form.ListValue, 'config_type', _('Configuration Type'),
        _('Select Configuration Type'));
    configType.value('tmpl', _('Template Configuration'));
    configType.value('custom', _('Custom Edit'));
    configType.default = 'tmpl';
    configType.rmempty = false;

    // 分流监听端口
    let shuntListenPort = s.taboption('basic', form.Value, 'shunt_listen_port', _('Shunt Listen Port'),
        _('Shunt Listen Port'));
    shuntListenPort.default = '1041';
    shuntListenPort.datatype = 'port';
    shuntListenPort.rmempty = false;
    shuntListenPort.validate = function (sectionId: string, value: string) {
        const currentDnsListenPort = this.section.formvalue(sectionId, 'dns_listen_port');
        if (currentDnsListenPort === value) {
            return _("Conflicts with DNS Port")
        }
        return ValidationUtils.validatePortConflict.call(this, sectionId, value);
    }

    // DNS监听端口
    let dnsListenPort = s.taboption('basic', form.Value, 'dns_listen_port', _('DNS Listen Port'),
        _('DNS Listen Port'));
    dnsListenPort.default = '10153';
    dnsListenPort.datatype = 'port';
    dnsListenPort.rmempty = false;
    dnsListenPort.validate = function (sectionId: string, value: string) {
        const currentShuntListenPort = this.section.formvalue(sectionId, 'shunt_listen_port');
        if (currentShuntListenPort === value) {
            return _("Conflicts with Shunt Port")
        }
        return ValidationUtils.validatePortConflict.call(this, sectionId, value);
    }

    // 日志开关
    FormUtils.createLogFlagOption(s, LuciFlied.CONF_NAME, 'basic');

    // 日志路径
    let logLevel = s.taboption('basic', form.ListValue, 'log_level', _('Log Level'), _('Logging Level'));
    HijpassValues.SHUNT_LOG_LEVELS.forEach(function (level) {
        logLevel.value(level);
    })
    logLevel.default = 'warn';
    logLevel.rmempty = false;
    logLevel.depends('log_enabled', '1');

    // 预览配置按钮
    let previewConfigButton = s.taboption('basic', form.Button, '_preview_config', _('Preview Configuration'),
        _('Click to Preview'));
    previewConfigButton.depends('config_type', 'tmpl');
    previewConfigButton.inputtitle = _('Preview Configuration');
    previewConfigButton.inputstyle = 'apply';
    previewConfigButton.onclick = ShuntFormUtils.showPreview

}


function createConfigEditor(s: LuCI.form.AbstractSection) {
    let o = s.taboption('config', form.TextValue, 'shunt_conf_data', null, _('Edit Shunt Configuration File'));
    o.depends('config_type', 'custom')
    ShuntFormUtils.configureConfigEditor(o);
}

// 创建路由配置选项
function createRouteOptions(s: LuCI.form.AbstractSection) {
    // 默认全局路由出口配置
    let routeTypeSectionValue = ShuntFormUtils.createSectionContainer(s, 'route', '_route_global',
        form.TypedSection, LuciFlied.SHUNT_SECTION_TYPE, '');

    let routeTypeSection = routeTypeSectionValue.subsection;
    FormUtils.setAnonymousSection(routeTypeSection);

    let defaultProxyNode = ShuntFormUtils.createRequiredListValue(routeTypeSection, 'default_proxy_node', _('Default Global Exit'),
        _('Select Default Exit Node'),
        function (section_id: any, value: any) {
            if (!value) {
                return _('Configure Global Exit First');
            }
            return true;
        });
    ShuntFormUtils.loadProxyNodeOptions(defaultProxyNode, true);

    let rulesetOutNode = routeTypeSection.option(form.ListValue, 'ruleset_out_node', _('Rule-set Exit'),
        _('Rule-set Download Exit'));
    ShuntFormUtils.loadProxyNodeOptions(rulesetOutNode, false);

    let rulesetConvert = routeTypeSection.option(form.Flag, 'ruleset_convert',
        _('Use GeoSite Rule-set'), _('Convert Geo Rules'));
    rulesetConvert.rmempty = false;
    rulesetConvert.depends('type', CORE_TYPE.SING_BOX);

    let routeDiagnostics = routeTypeSection.option(form.Button, '_route_diagnostics', _('Shunt Troubleshooting'),
        _('Trace router or client traffic and inspect routing failures in Diagnostics.'));
    routeDiagnostics.inputtitle = _('Open Diagnostics');
    routeDiagnostics.inputstyle = 'action';
    routeDiagnostics.onclick = function () {
        window.location.href = L.url('admin/services/hijpass/log') + '?tab=trace';
    };

    // 批量替换节点按钮
    let replaceNodeBtn = routeTypeSection.option(form.Button, '_replace_node', _('Bulk Replace Nodes'));
    replaceNodeBtn.depends({config_type: "tmpl"});
    replaceNodeBtn.inputtitle = _('Bulk Replace Nodes');
    replaceNodeBtn.inputstyle = 'apply';
    replaceNodeBtn.onclick = ShuntFormUtils.showBulkReplaceModal;

    // 路由规则配置
    let routeGridSectionValue = s.taboption('route', form.SectionValue, '_route_rule',
        form.GridSection, LuciFlied.SHUNT_ROUTE_RULE_TYPE, _('Routing Rule Configuration'));
    routeGridSectionValue.depends({config_type: "tmpl"})

    let routeGridSection = routeGridSectionValue.subsection;
    routeGridSection.rowcolors = true
    FormUtils.setAnonymousGridSectionMembers(routeGridSection)
    routeGridSection.modaltitle = _('Edit Routing Rule');
    routeGridSection.sectiontitle = function (section_id: any) {
        return uci.get(LuciFlied.CONF_NAME, section_id, 'name') || _('Unnamed Rule');
    };
    routeGridSection.rowcolors = true
    routeGridSection.tab('_rule', _('Rule'));
    routeGridSection.tab('_dns', _('DNS Configuration'));

    // 规则名称
    let name = routeGridSection.taboption('_rule', form.Value, 'name', _('Rule Name'));
    name.validate = ValidationUtils.createTagValidator(LuciFlied.CONF_NAME, LuciFlied.SHUNT_ROUTE_RULE_TYPE, 'name')
    name.rmempty = false;
    name.modalonly = true;

    // 启用开关（从路由配置移过来）
    let enabled = routeGridSection.taboption('_rule', form.Flag, 'enabled', _('Enable'));
    enabled.default = '1';
    enabled.rmempty = false;
    enabled.editable = true;

    let proxyNodeView = routeGridSection.option(form.DummyValue, '_proxy_node_view', _('Proxy Node'));
    proxyNodeView.textvalue = function (sectionId) {
        if (uci.get(LuciFlied.CONF_NAME, sectionId, 'ip_version_split') === '1') {
            return _('IPv4: %s / IPv6: %s').format(
                uci.get(LuciFlied.CONF_NAME, sectionId, 'proxy_node_v4') || '-',
                uci.get(LuciFlied.CONF_NAME, sectionId, 'proxy_node_v6') || '-'
            );
        }
        return uci.get(LuciFlied.CONF_NAME, sectionId, 'proxy_node') || '-';
    }

    // 代理节点（动态生成选项）
    let proxyNode = routeGridSection.taboption('_rule', form.ListValue, 'proxy_node', _('Proxy Node'));
    proxyNode.rmempty = true;
    proxyNode.modalonly = true;
    proxyNode.depends({ip_version_split: '1', '!reverse': true});
    proxyNode.validate = function (sectionId: string, value: string) {
        if (this.section.formvalue(sectionId, 'ip_version_split') !== '1' && !value) {
            return _('Configure Proxy Node First');
        }
        return true;
    }
    ShuntFormUtils.loadProxyNodeOptions(proxyNode, true);  // 包含阻止和负载均衡

    let ipVersionSplit = routeGridSection.taboption('_rule', form.Flag, 'ip_version_split',
        _('Split IPv4/IPv6 Exit'),
        _('Use separate proxy nodes for IPv4 and IPv6 while sharing the same rule conditions'));
    ipVersionSplit.default = '0';
    ipVersionSplit.rmempty = false;
    ipVersionSplit.modalonly = true;

    let proxyNodeV4 = routeGridSection.taboption('_rule', form.ListValue, 'proxy_node_v4',
        _('IPv4 Proxy Node'), _('IPv4 traffic exit node'));
    proxyNodeV4.depends('ip_version_split', '1');
    proxyNodeV4.modalonly = true;
    proxyNodeV4.validate = function (sectionId: string, value: string) {
        if (this.section.formvalue(sectionId, 'ip_version_split') === '1' && !value) {
            return _('Configure IPv4 Proxy Node First');
        }
        return true;
    }
    ShuntFormUtils.loadProxyNodeOptions(proxyNodeV4, true);

    let proxyNodeV6 = routeGridSection.taboption('_rule', form.ListValue, 'proxy_node_v6',
        _('IPv6 Proxy Node'), _('IPv6 traffic exit node'));
    proxyNodeV6.depends('ip_version_split', '1');
    proxyNodeV6.modalonly = true;
    proxyNodeV6.validate = function (sectionId: string, value: string) {
        if (this.section.formvalue(sectionId, 'ip_version_split') === '1' && !value) {
            return _('Configure IPv6 Proxy Node First');
        }
        return true;
    }
    ShuntFormUtils.loadProxyNodeOptions(proxyNodeV6, true);

    // DNS服务器（动态生成选项）
    let dnsNode = routeGridSection.taboption('_dns', form.ListValue, 'dns_node', _('DNS Server'), _('Only Effective with Domain/GeoSite/Rule-set'));
    // dnsNode.modalonly = true;
    ShuntFormUtils.loadDNSServerOptions(dnsNode, true);  // 包含默认选项
    dnsNode.textvalue = function (sectionId) {
        let dnsNode = uci.get(LuciFlied.CONF_NAME, sectionId, 'dns_node');
        if (!dnsNode) {
            return _('-');
        }
        let dnsProxyNode = uci.get(LuciFlied.CONF_NAME, sectionId, 'dns_proxy_node');
        let value: string;
        if (!dnsProxyNode) {
            value = dnsNode
        } else {
            dnsProxyNode = dnsProxyNode === 'hijpass-direct' ? _('Direct') : dnsProxyNode;
            value = dnsNode + ' -> ' + dnsProxyNode;
        }
        return value;
    }

    let dnsStrategy = routeGridSection.taboption('_dns', form.ListValue, 'dns_strategy', _('DNS Resolution Strategy'));
    dnsStrategy.value('', _('Use Global Default Resolution Strategy'))
    HijpassValues.DNS_STRATEGY_VALUES.forEach(function (strategy) {
        dnsStrategy.value(strategy.value, _(strategy.label));
    });
    dnsStrategy.modalonly = true;

    let dnsProxyNode = routeGridSection.taboption('_dns', form.ListValue, 'dns_proxy_node', _('DNS Exit Node'));
    dnsProxyNode.value('', _('Use Routing Proxy Node'));
    dnsProxyNode.value('hijpass-direct', _('Direct'));
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section) {
        if (section.name && section.enabled === '1') {
            let displayName = section.name;
            if (section.socks_port) {
                displayName += ' (' + section.socks_port + ')';
            }
            dnsProxyNode.value(section.name, displayName);
        }
    });
    dnsProxyNode.modalonly = true;
    dnsProxyNode.validate = function (sectionId: string, value: string) {
        const section = this.section;
        if (section.formvalue(sectionId, 'ip_version_split') === '1' && !value && hasSplitDnsTarget(section, sectionId)) {
            return _('Configure DNS Exit Node when splitting IPv4/IPv6 exit');
        }
        return true;
    }

    // 网络
    let network = routeGridSection.taboption('_rule', form.MultiValue, 'network', _('Network'));
    network.value('tcp');
    network.value('udp');
    network.cfgvalue = function (sectionId) {
        let networks = uci.get(LuciFlied.CONF_NAME, sectionId, 'network');
        if (networks) {
            return networks.join(',');
        }
        return '-';
    }
    // network.modalonly = true

    // 协议
    let protocol = routeGridSection.taboption('_rule', form.MultiValue, 'protocol', _('Protocol'), _('Current Xray only supports http, tls, quic, and bittorrent'));
    protocol.value('tls');
    protocol.value('http');
    protocol.value('quic');
    protocol.value('stun');
    protocol.value('dns');
    protocol.value('bittorrent');
    protocol.value('dtls');
    protocol.value('ssh');
    protocol.value('rdp');
    protocol.value('ntp');
    // protocol.modalonly = true
    protocol.validate = function (_sectionId: string, value: any) {
        const shuntType = getCurrentShuntValue(this.section, 'type');
        if (shuntType !== CORE_TYPE.XRAY) {
            return true;
        }

        const selectedProtocols = Array.isArray(value) ? value : (value ? [value] : []);
        const unsupported = selectedProtocols.filter((item) => XRAY_ROUTE_PROTOCOLS.indexOf(item) === -1);
        if (unsupported.length > 0) {
            return _('Xray only supports route protocol filters: %s').format(XRAY_ROUTE_PROTOCOLS.join(', '));
        }
        return true;
    }
    protocol.cfgvalue = function (sectionId) {
        let protocols = uci.get(LuciFlied.CONF_NAME, sectionId, 'protocol');
        if (protocols) {
            return protocols.join(',')
        }
        return '-';
    }

    // 端口
    let port = routeGridSection.taboption('_rule', form.DynamicList, 'port', _('Port'));
    port.datatype = 'port';
    port.placeholder = '80';
    port.modalonly = true

    // 端口范围
    let portRange = routeGridSection.taboption('_rule', form.DynamicList, 'port_range', _('Port Range'));
    portRange.datatype = 'portrange';
    portRange.placeholder = '1000-2000';
    portRange.modalonly = true

    let portView = routeGridSection.option(form.TextValue, '_port_view', _('Port Range'))
    portView.textvalue = function (sectionId) {
        let port = uci.get(LuciFlied.CONF_NAME, sectionId, 'port');
        let portRange = uci.get(LuciFlied.CONF_NAME, sectionId, 'port_range');
        let value = []
        if (port) {
            value.push(...port)
        }
        if (portRange) {
            value.push(...portRange)
        }
        return value.join(',') || '-';
    }
    portView.modalonly = false

    // 域名规则列表
    let domainList = routeGridSection.taboption('_rule', form.TextValue, 'domain_list', _('Domain Rule List'), _('Plain string: When this string matches any part of the target domain, the rule takes effect.<br>' +
        'Regular expression: Starts with \'regexp:\', followed by a regular expression.<br>' +
        'Subdomain (recommended): Starts with \'domain:\', followed by a domain. The rule takes effect when this domain is the target domain or one of its subdomains.<br>' +
        'Full match: Starts with \'full:\', followed by a domain. The rule takes effect when the target domain exactly matches this domain.<br>' +
        'geosite: e.g. \'geosite:cn\'.<br>' +
        'rule-set: e.g. \'rule-set:local:/path/rulefile\' or \'rule-set:remote:https://file\'.<br>' +
        'Comment: starts with #'));
    domainList.rows = 4;
    domainList.monospace = true;
    domainList.modalonly = true
    configureGeoRuleQuery(domainList, 'geosite');

    let domainListView = routeGridSection.option(form.TextValue, '_domain_list_view', _('Domain Rule Count'))
    domainListView.textvalue = function (sectionId) {
        let domainList = uci.get(LuciFlied.CONF_NAME, sectionId, 'domain_list');
        if (domainList) {
            return domainList.split('\n').filter(item => !item.startsWith('#')).length;
        }
        return '-';
    }

    // IP规则列表
    let ipList = routeGridSection.taboption('_rule', form.TextValue, 'ip_list', _('IP Rule List'), _('IP: e.g. \'127.0.0.1\'.<br>' +
        'CIDR: e.g. \'10.0.0.0/8\'.<br>' +
        'geoip: e.g. \'geoip:cn\'.<br>' +
        'rule-set: e.g. \'rule-set:local:/path/rulefile\' or \'rule-set:remote:https://file\'.<br>' +
        'Comment: starts with #'));
    ipList.rows = 4;
    ipList.monospace = true;
    ipList.modalonly = true
    configureGeoRuleQuery(ipList, 'geoip');

    let ipListView = routeGridSection.option(form.TextValue, '_ip_list_view', _('IP Rule Count'))
    ipListView.textvalue = function (sectionId) {
        let ipList = uci.get(LuciFlied.CONF_NAME, sectionId, 'ip_list');
        if (ipList) {
            return ipList.split('\n').filter(item => !item.startsWith('#')).length;
        }
        return '-';
    }
}


// 创建DNS服务器配置选项
function createDNSOptions(s: LuCI.form.AbstractSection) {

    let dnsTypeSectionValue = ShuntFormUtils.createSectionContainer(s, 'dns', '_dns_global',
        form.TypedSection, LuciFlied.SHUNT_SECTION_TYPE, '');

    let dnsTypeSection = dnsTypeSectionValue.subsection;
    FormUtils.setAnonymousSection(dnsTypeSection);

    // 默认全局DNS配置
    let defaultDNSNode = ShuntFormUtils.createRequiredListValue(dnsTypeSection, 'default_dns_node', _('Default Global DNS'),
        _('Select Default DNS'),
        function (section_id: string, value: any) {
            if (!value) {
                return _('Please configure the global DNS server first');
            }
            return true;
        });
    ShuntFormUtils.loadDNSServerOptions(defaultDNSNode, false);

    let rulesetDNSNode = dnsTypeSection.option(form.ListValue, 'ruleset_dns_node',
        _('Rule-set DNS'), _('Select Rule-set DNS'));
    ShuntFormUtils.loadDNSServerOptions(rulesetDNSNode, true);

    let defaultStrategy = dnsTypeSection.option(form.ListValue, 'default_strategy', _('Internal DNS Resolution Strategy'),
        _('Select DNS Resolution Strategy'));
    HijpassValues.DNS_STRATEGY_VALUES.forEach(function (strategy) {
        defaultStrategy.value(strategy.value, _(strategy.label));
    });
    defaultStrategy.rmempty = false;

    let useCache = dnsTypeSection.option(form.Flag, 'use_cache', _('DNS Cache'));
    useCache.rmempty = false;

    let dnsGridSectionValue = s.taboption('dns', form.SectionValue, '_dns_servers',
        form.GridSection, LuciFlied.SHUNT_DNS_NODE_TYPE, _('DNS Node Configuration'));
    dnsGridSectionValue.depends({config_type: "tmpl"})

    let dnsGridSection = dnsGridSectionValue.subsection;
    dnsGridSection.rowcolors = true
    dnsGridSection.anonymous = true;
    dnsGridSection.addremove = true;
    dnsGridSection.sortable = true;
    dnsGridSection.nodescriptions = true;
    dnsGridSection.modaltitle = _('Edit DNS Server');
    dnsGridSection.sectiontitle = function (section_id) {
        return uci.get(LuciFlied.CONF_NAME, section_id, 'tag') || _('Unnamed');
    };

    let enabled = dnsGridSection.option(form.Flag, 'enabled', _('Enable'));
    enabled.default = '1';
    enabled.rmempty = false;
    enabled.editable = true;

    // DNS类型
    let type = dnsGridSection.option(form.ListValue, 'type', _('Type'),
        _('DNS Server Type'));
    type.value('tcp', 'TCP');
    type.value('udp', 'UDP');
    type.value('tls', _('TLS (sing-box only)'));
    type.value('https', 'HTTPS');
    type.value('quic', 'QUIC');
    type.default = 'tcp';
    type.rmempty = false;
    type.validate = function (_sectionId: string, value: string) {
        return value === 'tls' && getCurrentShuntValue(this.section, 'type') === CORE_TYPE.XRAY
            ? _('TLS (sing-box only)')
            : true;
    };

    // DNS标签
    let tag = dnsGridSection.option(form.Value, 'tag', _('Tag'),
        _('DNS Server Tag'));
    tag.placeholder = 'dns-local';
    tag.rmempty = false;
    tag.validate = ValidationUtils.createTagValidator(LuciFlied.CONF_NAME, LuciFlied.SHUNT_DNS_NODE_TYPE, 'tag')
    tag.modalonly = true

    // DNS服务器地址
    let server = dnsGridSection.option(form.Value, 'server', _('DNS Server'),
        _('DNS Server Address'));
    server.placeholder = '8.8.8.8';
    server.datatype = 'ipaddr';
    server.rmempty = false;

    // DNS服务器端口
    let port = dnsGridSection.option(form.Value, 'port', _('Port'),
        _('DNS Server Port'));
    port.placeholder = '53';
    port.datatype = 'port';
    port.rmempty = true;
}

// 创建所有标签页
function createTabs(s: LuCI.form.AbstractSection) {
    s.tab('basic', _('Basic Configuration'));
    s.tab('config', _('Shunt Configuration Editor'));
    s.tab('route', _('Routing Rules'));
    s.tab('dns', _('Core DNS'));
    s.tab('ruleset', _('Rule-set'));
}

export default v;
