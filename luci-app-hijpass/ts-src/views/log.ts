import view from "view";

import {LuciFlied} from "../enum/hijpass";
import form from "form";
import uci from "uci";
import { LogPanelUtils } from "../utils/feature/log/panel";
import { RulePanelUtils } from "../utils/feature/rule/panel";

const v = view.extend({
    load: function () {
        return Promise.all([
            uci.load(LuciFlied.CONF_NAME),
            uci.load(LuciFlied.SERVER_CONF_NAME)
        ]);
    },
    handleSaveApply: null,
    handleReset: null,
    handleSave: null,
    render: function () {

        let m = new form.Map(LuciFlied.CONF_NAME, _('Diagnostics'),
            _('Inspect logs, trace routing behavior, and query rule resources'));

        let s = m.section(form.TypedSection, LuciFlied.GLOBAL_SECTION_TYPE);
        s.anonymous = true;
        s.addremove = false;

        s.tab('logs', _('Logs'));
        s.tab('trace', _('Routing Diagnostics'));
        s.tab('rule', _('Rule Diagnostics'));

        const requestedTab = new URLSearchParams(window.location.search).get('tab');
        if (requestedTab === 'logs' || requestedTab === 'trace' || requestedTab === 'rule') {
            s.selected_tab = requestedTab;
        }

        let logsTab = s.taboption('logs', form.DummyValue, '_logs_tab');
        logsTab.render = function () {
            return LogPanelUtils.createLogControlPanel();
        };

        let traceUrl = s.taboption('trace', form.Value, '_trace_url', _('URL'));
        traceUrl.default = 'https://www.gstatic.com/generate_204';
        traceUrl.placeholder = 'https://www.gstatic.com/generate_204';
        traceUrl.rmempty = false;

        let traceMode = s.taboption('trace', form.ListValue, '_trace_mode', _('Mode'));
        traceMode.value('router', _('Router Local'));
        traceMode.value('client', _('Client Transparent Proxy'));
        traceMode.default = 'router';
        traceMode.rmempty = false;

        let traceClientIp = s.taboption('trace', form.Value, '_trace_client_ip', _('Client IP'),
            _('Required only for client transparent proxy mode'));
        traceClientIp.placeholder = '192.168.1.100';
        traceClientIp.datatype = 'ipaddr';
        traceClientIp.rmempty = false;
        traceClientIp.depends('_trace_mode', 'client');

        let traceMethod = s.taboption('trace', form.ListValue, '_trace_method', _('Request Method'));
        traceMethod.value('HEAD', 'HEAD');
        traceMethod.value('GET', 'GET');
        traceMethod.default = 'HEAD';
        traceMethod.rmempty = false;

        let traceTimeout = s.taboption('trace', form.Value, '_trace_timeout', _('Timeout'));
        traceTimeout.default = '8';
        traceTimeout.datatype = 'range(1,120)';
        traceTimeout.rmempty = false;

        let traceTcpdump = s.taboption('trace', form.Flag, '_trace_tcpdump', _('Enable tcpdump'),
            _('Optional. tcpdump must be installed on the router'));
        traceTcpdump.default = '0';
        traceTcpdump.rmempty = true;

        let traceTcpdumpIface = s.taboption('trace', form.Value, '_trace_tcpdump_iface', _('tcpdump Interface'));
        traceTcpdumpIface.default = 'any';
        traceTcpdumpIface.placeholder = 'any';
        traceTcpdumpIface.rmempty = true;
        traceTcpdumpIface.depends('_trace_tcpdump', '1');

        let traceVerbose = s.taboption('trace', form.Flag, '_trace_verbose', _('Show raw trace/log tail'));
        traceVerbose.default = '0';
        traceVerbose.rmempty = true;

        let traceStatusElement: HTMLElement | null = null;
        let traceOutputElement: HTMLElement | null = null;

        let traceRun = s.taboption('trace', form.Button, '_trace_run', _('Actions'));
        traceRun.inputtitle = _('Run Trace');
        traceRun.inputstyle = 'action';
        traceRun.onclick = function (ev: Event, sectionId: string) {
            if (!traceStatusElement || !traceOutputElement) {
                return;
            }

            return LogPanelUtils.runTraceDiagnostics({
                url: String(traceUrl.formvalue(sectionId) || ''),
                mode: String(traceMode.formvalue(sectionId) || 'router'),
                clientIp: String(traceClientIp.formvalue(sectionId) || ''),
                method: String(traceMethod.formvalue(sectionId) || 'HEAD'),
                timeout: String(traceTimeout.formvalue(sectionId) || '8'),
                tcpdump: traceTcpdump.formvalue(sectionId) === '1',
                tcpdumpInterface: String(traceTcpdumpIface.formvalue(sectionId) || 'any'),
                verbose: traceVerbose.formvalue(sectionId) === '1'
            }, traceStatusElement, traceOutputElement, ev.currentTarget as HTMLButtonElement);
        };

        let traceOutput = s.taboption('trace', form.DummyValue, '_trace_output');
        traceOutput.render = function () {
            const panel = LogPanelUtils.createTraceOutputPanel();
            traceStatusElement = panel.statusElement;
            traceOutputElement = panel.outputElement;
            return panel.node;
        };

        let ruleDiagnosticsTab = s.taboption('rule', form.DummyValue, '_rule_diagnostics_tab');
        ruleDiagnosticsTab.render = function () {
            return RulePanelUtils.createQueryPanel();
        };

        return m.render();
    }
});

export default v;
