import view from "view";

import {LuciFlied} from "../enum/hijpass";
import form from "form";
import uci from "uci";
import { Backend } from "../utils/backend";
import { LogPanelUtils } from "../utils/feature/log/panel";
import { RulePanelUtils } from "../utils/feature/rule/panel";

const v = view.extend({
    load: function () {
        return Promise.all([
            uci.load(LuciFlied.CONF_NAME),
            uci.load(LuciFlied.SERVER_CONF_NAME),
            Backend.traceCapabilities().catch(() => ({ tcpdump: false }))
        ]);
    },
    handleSaveApply: null,
    handleReset: null,
    handleSave: null,
    render: function (data: [unknown, unknown, { tcpdump: boolean }]) {

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

        let traceMode = s.taboption('trace', form.ListValue, '_trace_mode', _('Mode'));
        traceMode.value('router', _('Router Local'));
        traceMode.value('client', _('Client Transparent Proxy'));
        traceMode.default = 'router';
        traceMode.rmempty = false;

        let traceUrl = s.taboption('trace', form.Value, '_trace_url', _('URL'));
        traceUrl.default = 'https://www.gstatic.com/generate_204';
        traceUrl.placeholder = 'https://www.gstatic.com/generate_204';
        traceUrl.rmempty = false;
        traceUrl.depends('_trace_mode', 'router');

        let traceClientIp = s.taboption('trace', form.Value, '_trace_client_ip', _('Client IP'),
            _('Observe traffic from this client during the capture window. Generate requests on the client after capture starts.'));
        traceClientIp.placeholder = '192.168.1.100';
        traceClientIp.datatype = 'ipaddr';
        traceClientIp.rmempty = false;
        traceClientIp.depends('_trace_mode', 'client');

        let traceProtocol = s.taboption('trace', form.ListValue, '_trace_protocol', _('Transport Protocol'));
        traceProtocol.value('all', _('All'));
        traceProtocol.value('tcp', 'TCP');
        traceProtocol.value('udp', 'UDP');
        traceProtocol.default = 'all';
        traceProtocol.rmempty = false;
        traceProtocol.depends('_trace_mode', 'client');

        let tracePort = s.taboption('trace', form.Value, '_trace_port', _('Destination Port'),
            _('Optional TCP/UDP destination port. Leave empty to capture all ports.'));
        tracePort.placeholder = _('All ports');
        tracePort.datatype = 'port';
        tracePort.rmempty = true;
        tracePort.depends('_trace_mode', 'client');

        let traceMethod = s.taboption('trace', form.ListValue, '_trace_method', _('Request Method'));
        traceMethod.value('HEAD', 'HEAD');
        traceMethod.value('GET', 'GET');
        traceMethod.default = 'HEAD';
        traceMethod.rmempty = false;
        traceMethod.depends('_trace_mode', 'router');

        let traceTimeout = s.taboption('trace', form.Value, '_trace_timeout', _('Timeout'));
        traceTimeout.default = '8';
        traceTimeout.datatype = 'range(1,120)';
        traceTimeout.rmempty = false;
        traceTimeout.depends('_trace_mode', 'router');

        let traceDuration = s.taboption('trace', form.Value, '_trace_duration', _('Capture Duration (seconds)'));
        traceDuration.default = '30';
        traceDuration.datatype = 'range(1,120)';
        traceDuration.rmempty = false;
        traceDuration.depends('_trace_mode', 'client');

        let traceTcpdump: LuCI.form.Value | undefined;
        let traceTcpdumpIface: LuCI.form.Value | undefined;
        if (data[2].tcpdump) {
            traceTcpdump = s.taboption('trace', form.Flag, '_trace_tcpdump', _('Enable tcpdump'));
            traceTcpdump.default = '0';
            traceTcpdump.rmempty = true;

            traceTcpdumpIface = s.taboption('trace', form.Value, '_trace_tcpdump_iface', _('tcpdump Interface'));
            traceTcpdumpIface.default = 'any';
            traceTcpdumpIface.placeholder = 'any';
            traceTcpdumpIface.rmempty = true;
            traceTcpdumpIface.depends('_trace_tcpdump', '1');
        }

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
                protocol: String(traceProtocol.formvalue(sectionId) || 'all'),
                port: String(tracePort.formvalue(sectionId) || ''),
                method: String(traceMethod.formvalue(sectionId) || 'HEAD'),
                timeout: traceMode.formvalue(sectionId) === 'client'
                    ? String(traceDuration.formvalue(sectionId) || '30')
                    : String(traceTimeout.formvalue(sectionId) || '8'),
                tcpdump: traceTcpdump?.formvalue(sectionId) === '1',
                tcpdumpInterface: String(traceTcpdumpIface?.formvalue(sectionId) || 'any'),
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
