import view from "view";
import form from "form";
import uci from "uci";
import ui from "ui";
import { Backend } from "../utils/backend";
import { HijpassValues, LuciFlied } from "../enum/hijpass";
import { ServiceUtils } from "../utils/base/luci/service";
import { FormUtils } from "../utils/base/luci/form";
import { ValidationUtils } from "../utils/base/luci/validation";
import { UciUtils } from "../utils/base/luci/uci";
import { NotificationUtils } from "../utils/base/luci/notification";
import { createNodeLogButton } from "../utils/feature/log/node";
import { ConfigPreviewUtils } from "../utils/feature/config/preview";

const configName = LuciFlied.SERVER_CONF_NAME;
const protocols = { shadowsocks: 'Shadowsocks', hysteria2: 'Hysteria2', vless: 'VLESS' };

export default view.extend({
    load: () => Promise.all([uci.load(configName), uci.load(LuciFlied.CONF_NAME),
        ServiceUtils.getServiceInstances(configName)]),

    handleSaveApply: async function (ev: Event, mode?: string | number) {
        try {
            await this.handleSave(ev);
            await Backend.validateServers(JSON.stringify(uci.sections(configName, undefined)));
            await uci.save();
            ui.changes.apply(mode == '0');
        } catch (error) {
            NotificationUtils.error(_('Configuration Apply Failed'), error.message, 5000);
        }
    },

    render: async function (data: any[]) {
        const map = new form.Map(configName, _('Local Server'), _('Run as Local Server'));
        const global = map.section(form.TypedSection, configName);
        global.anonymous = true;
        global.addremove = false;
        global.option(form.Flag, 'enabled', _('Enable')).rmempty = false;

        const section = map.section(form.GridSection, LuciFlied.SERVER_NODE_TYPE);
        FormUtils.setGridSectionMembers(section);
        section.anonymous = true;
        section.sectiontitle = id => uci.get(configName, id, 'name') || id;
        section.handleAdd = function (ev: Event) {
            return form.GridSection.prototype.handleAdd.call(this, ev, UciUtils.generateUniqueSectionId(configName));
        };
        createOptions(section, data[2] || {});
        const legacy = uci.sections(configName, LuciFlied.SERVER_NODE_TYPE).some(node => node.legacy_custom === '1');
        const content = await map.render();
        return E('div', {}, [
            ...(legacy ? [E('div', { class: 'alert-message warning' },
                _('Custom server nodes have been disabled. Edit each node to select a protocol and configure credentials. Original JSON files are retained as .legacy.json.'))] : []),
            content,
        ]);
    },
});

function createOptions(section: LuCI.form.AbstractSection, instances: any) {
    // 每个 UCI 字段只有一个表单选项，列表显示和弹窗编辑共用，避免值被重复解析覆盖。
    const coreOption = section.option(form.ListValue, 'core', _('Core'),
        _("Core used to run this server node; the protocol must be supported by the installed core."));
    HijpassValues.DUAL_CORES.forEach(core => coreOption.value(core.value, core.label));
    coreOption.default = 'sing-box';
    coreOption.rmempty = false;

    const typeOption = section.option(form.ListValue, 'type', _('Protocol'),
        _("Protocol offered to clients; configure the same protocol on each client."));
    typeOption.value('', _('Select protocol'));
    for (const [value, label] of Object.entries(protocols)) typeOption.value(value, label);
    typeOption.rmempty = false;
    typeOption.write = function (id: string, value: string) {
        uci.set(configName, id, 'type', value);
        if (value) {
            for (const key of ['legacy_custom', 'command', 'custom_conf_hash', 'procd_env']) uci.unset(configName, id, key);
        }
    };

    const listenPortOption = section.option(form.Value, 'listen_port', _('Listen Port'),
        _("Port listened on by this server; clients connect to this port or its forwarded public port."));
    listenPortOption.datatype = 'port';
    listenPortOption.rmempty = false;
    listenPortOption.validate = ValidationUtils.validatePortConflict;

    const status = section.option(form.DummyValue, 'run_status', _('Status'));
    status.modalonly = false;
    status.textvalue = (id: string) => {
        const name = uci.get(configName, id, 'name');
        const running = instances[id + (name ? '-' + name : '')]?.running;
        return E('span', { style: 'color:' + (running ? 'green' : 'red') }, running ? _('Running') : _('Not Running'));
    };
    const allowFirewallOption = section.option(form.Flag, 'allow_firewall', _('Allow Public Access'),
        _("Allow inbound access through the firewall to this node listening port."));
    allowFirewallOption.default = '1';
    allowFirewallOption.rmempty = false;
    const enabledOption = section.option(form.Flag, 'enabled', _('Enable'));
    enabledOption.default = '1';
    enabledOption.rmempty = false;
    enabledOption.editable = true;

    const actions = section.option(form.DummyValue, 'actions', '');
    actions.modalonly = false;
    actions.textvalue = (id: string) => {
        const log = createNodeLogButton(configName, id);
        const preview = E('button', { class: 'btn cbi-button', click: async () => {
            try {
                const result = await Backend.renderServer(JSON.stringify(uci.sections(configName, undefined)), id);
                const name = uci.get(configName, id, 'name') || id;
                ConfigPreviewUtils.show(name + ' - ' + _('Config Preview'), JSON.stringify(result.config, null, 2));
            } catch (error) { NotificationUtils.error(_('Configuration Preview'), error.message); }
        } }, _('Preview'));
        return E('span', { style: 'display:flex;gap:8px;flex-wrap:wrap' }, log ? [preview, log] : [preview]);
    };

    function field(kind: LuCI.form.Value, key: string, label: string, dependencies?: Record<string, string>[], description?: string) {
        const value = section.option(kind, key, label, description);
        value.modalonly = true;
        if (dependencies) for (const dependency of dependencies) value.depends(dependency);
        return value;
    }
    const nameOption = field(form.Value, 'name', _('Node Name'), undefined,
        _("Unique node name used to identify its configuration and logs."));
    nameOption.rmempty = false;
    nameOption.validate = ValidationUtils.createTagValidator(configName, LuciFlied.SERVER_NODE_TYPE, 'name');
    const listenOption = field(form.Value, 'listen', _('Listen Address'), undefined,
        _("Local bind address, for example 0.0.0.0, :: or 127.0.0.1; loopback only accepts local connections."));
    listenOption.default = '::';
    listenOption.datatype = 'ipaddr';
    listenOption.rmempty = false;

    const methodOption = field(form.ListValue, 'method', _('Encryption Method'), [{ type: 'shadowsocks' }],
        _('For Shadowsocks 2022, enter a base64 key: 16 bytes for AES-128, 32 bytes for other methods.'));
    for (const method of ['2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305',
        'aes-128-gcm', 'aes-256-gcm', 'chacha20-ietf-poly1305']) methodOption.value(method);
    methodOption.default = '2022-blake3-aes-128-gcm';
    methodOption.rmempty = false;
    const passwordOption = field(form.Value, 'password', _('Password'), [{ type: 'shadowsocks' }, { type: 'hysteria2' }],
        _("Set the password or key that clients must use."));
    passwordOption.password = true;
    passwordOption.rmempty = false;
    // SS2022 使用固定长度随机密钥；只在用户点击时替换当前表单值。
    function keyLength(section: LuCI.form.AbstractSection, id: string) {
        const type = section.formvalue(id, 'type');
        const method = section.formvalue(id, 'method') || methodOption.default;
        if (type !== 'shadowsocks' || !method?.startsWith('2022-')) return 0;
        return method === '2022-blake3-aes-128-gcm' ? 16 : 32;
    }
    passwordOption.renderWidget = function (id: string, index: number, value: string) {
        const widget = form.Value.prototype.renderWidget.call(this, id, index, value) as HTMLElement;
        const input = widget.querySelector('input') as HTMLInputElement;
        const button = E('button', {
            id: this.cbid(id) + '-generate', class: 'btn cbi-button', type: 'button',
            style: keyLength(this.section, id) ? '' : 'display:none',
            click: () => {
                const length = keyLength(this.section, id);
                if (!length) return;
                try {
                    const bytes = crypto.getRandomValues(new Uint8Array(length));
                    this.getUIElement(id)?.setValue(btoa(String.fromCharCode(...bytes)));
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.dispatchEvent(new Event('change', { bubbles: true }));
                } catch {
                    NotificationUtils.error(_('Key Generation Failed'), _('Unable to generate a secure random key in this browser.'));
                }
            },
        }, _('Generate Key'));
        return E('div', { style: 'display:inline-flex;align-items:center;gap:6px;flex-wrap:wrap;max-width:100%' }, [widget, button]);
    };
    const updateKeyButton = function (this: LuCI.form.Value, _event: Event, id: string) {
        const button = document.getElementById(passwordOption.cbid(id) + '-generate');
        if (button) button.style.display = keyLength(this.section, id) ? '' : 'none';
    };
    typeOption.onchange = updateKeyButton;
    methodOption.onchange = updateKeyButton;
    const uuidOption = field(form.Value, 'uuid', _('UUID'), [{ type: 'vless' }],
        _("User UUID accepted by this server; copy the same UUID to clients."));
    uuidOption.rmempty = false;
    uuidOption.datatype = 'uuid';

    const multiplex = ['shadowsocks', 'vless'].map(type => ({ core: 'sing-box', type }));
    field(form.Flag, 'multiplex_enabled', _('Enable Multiplexing'), multiplex,
        _('Accept sing-box multiplex connections; enable multiplexing on the client too.'));
    const multiplexEnabled = multiplex.map(dependency => ({ ...dependency, multiplex_enabled: '1' }));
    field(form.Flag, 'multiplex_padding', _('Require Multiplex Padding'), multiplexEnabled,
        _('Reject multiplex connections without padding; clients must enable padding.'));
    field(form.Flag, 'multiplex_brutal_enabled', _('Enable TCP Brutal'), multiplexEnabled,
        _('Requires the TCP Brutal kernel module on this server.'));
    for (const [key, label] of [
        ['multiplex_brutal_up_mbps', _('Uplink Bandwidth')],
        ['multiplex_brutal_down_mbps', _('Downlink Bandwidth')],
    ]) {
        const bandwidth = field(form.Value, key, label,
            multiplexEnabled.map(dependency => ({ ...dependency, multiplex_brutal_enabled: '1' })),
            _('Server bandwidth in Mbps; must be greater than zero.'));
        bandwidth.datatype = 'and(uinteger,range(1,2147483647))';
        bandwidth.rmempty = false;
    }

    const transportOption = field(form.ListValue, 'transport', _('Transport Protocol'), [{ type: 'vless' }],
        _("Leave empty for TCP. HTTP requires sing-box; XHTTP requires Xray. Match the peer transport."));
    for (const { value, label } of HijpassValues.V2RAY_TRANSPORT_TYPES) transportOption.value(value, _(label));
    transportOption.default = '';
    transportOption.load = (id: string) => {
        const value = uci.get(configName, id, 'transport');
        return value === 'tcp' ? '' : value || '';
    };
    transportOption.validate = function (id: string, value: string) {
        value ||= 'tcp';
        const core = this.section.formvalue(id, 'core');
        const security = this.section.formvalue(id, 'security');
        if (value === 'http' && core !== 'sing-box') return _('HTTP transport is only supported by sing-box core');
        if (value === 'xhttp' && core !== 'xray') return _('XHTTP transport is only supported by Xray core');
        if (security === 'reality') {
            if (core === 'sing-box' && value !== 'tcp') return _('sing-box REALITY requires TCP');
            if (core === 'xray' && !['tcp', 'xhttp', 'grpc'].includes(value))
                return _('Xray REALITY only supports RAW, XHTTP and gRPC transports');
        }
        return true;
    };
    const http = [{ type: 'vless', core: 'sing-box', transport: 'http' }];
    const httpHosts = field(form.DynamicList, 'http_host', _('HTTP Host'), http,
        _("Accepted HTTP Host values; leave empty to skip Host verification."));
    httpHosts.validate = (_id: string, value: string) => !value || !/\s/.test(value) || _('Invalid HTTP Host');
    const httpMethod = field(form.Value, 'http_method', _('HTTP Method'), http,
        _("Only accept this HTTP method, for example PUT; leave empty to skip method verification."));
    httpMethod.validate = (_id: string, value: string) => !value || /^[A-Z]+$/.test(value) || _('Invalid HTTP method');
    field(form.Value, 'http_idle_timeout', _('Idle Timeout'), http,
        _("HTTP/2 server idle timeout, for example 30s or 1m; empty uses the core default."));
    const httpupgrade = [{ type: 'vless', transport: 'httpupgrade' }];
    const upgradeHost = field(form.Value, 'httpupgrade_host', _('HTTPUpgrade Host'), httpupgrade,
        _("Required HTTPUpgrade Host; leave empty to skip Host verification."));
    upgradeHost.validate = (_id: string, value: string) => !value || !/\s/.test(value) || _('Invalid HTTP Host');
    for (const [key, label, dependencies] of [
        ['http_path', _('HTTP Path'), http], ['httpupgrade_path', _('HTTPUpgrade Path'), httpupgrade],
    ] as const) {
        const path = field(form.Value, key, label, dependencies,
            _("Start with /, for example /proxy; match the path configured on the peer."));
        path.default = '/';
        path.rmempty = false;
        path.validate = (_id: string, value: string) => value.startsWith('/') && !/\s/.test(value)
            || _('HTTP path must start with / and contain no whitespace');
    }
    const wsPathOption = field(form.Value, 'ws_path', _('WebSocket Path'), [{ type: 'vless', transport: 'ws' }],
        _("Start with /, for example /proxy; match the path configured on the peer."));
    wsPathOption.default = '/';
    wsPathOption.rmempty = false;
    const grpcServiceNameOption = field(form.Value, 'grpc_service_name', _('gRPC Service Name'), [{ type: 'vless', transport: 'grpc' }],
        _("gRPC service name; clients must use the same value."));
    grpcServiceNameOption.rmempty = false;
    const xhttp = [{ type: 'vless', core: 'xray', transport: 'xhttp' }];
    field(form.Value, 'xhttp_host', _('XHTTP Host'), xhttp,
        _("Required XHTTP Host; leave empty to skip Host verification."));
    const xhttpPath = field(form.Value, 'xhttp_path', _('XHTTP Path'), xhttp,
        _("Start with /, for example /proxy; match the path configured on the peer."));
    xhttpPath.default = '/';
    xhttpPath.rmempty = false;
    xhttpPath.validate = (_id: string, value: string) => value.startsWith('/') || _('XHTTP path must start with /');
    const xhttpMode = field(form.ListValue, 'xhttp_mode', _('XHTTP Mode'), xhttp,
        _("auto accepts all supported modes; a specific mode restricts clients to that mode."));
    xhttpMode.default = 'auto';
    xhttpMode.rmempty = false;
    xhttpMode.value('auto', _('Auto'));
    for (const mode of ['packet-up', 'stream-one', 'stream-up']) xhttpMode.value(mode);
    const xhttpMethod = field(form.Value, 'xhttp_method', _('HTTP Method'), xhttp,
        _("Optional upload method restriction, for example PUT; match the client setting."));
    xhttpMethod.validate = (_id: string, value: string) => !value || /^[A-Z]+$/.test(value) || _('Invalid HTTP method');

    const securityOption = field(form.ListValue, 'security', _('Transport Security'), [{ type: 'vless' }],
        _("TLS requires certificate files; REALITY requires a private key and handshake target; None adds no transport encryption."));
    securityOption.value('none', _('None'));
    securityOption.value('tls', 'TLS');
    securityOption.value('reality', 'REALITY');
    securityOption.default = 'tls';
    securityOption.rmempty = false;
    const flowOption = field(form.ListValue, 'flow', _('VLESS Flow Control'), [{ type: 'vless', transport: '', security: 'tls' },
        { type: 'vless', transport: '', security: 'reality' }],
        _("Vision requires TCP with TLS or REALITY; clients must use the matching flow."));
    flowOption.value('', _('None'));
    flowOption.value('xtls-rprx-vision', 'xtls-rprx-vision');

    const tls = [{ type: 'hysteria2' }, { type: 'vless', security: 'tls' }];
    field(form.Value, 'server_name', _('TLS Server Name'), [...tls, { type: 'vless', security: 'reality' }],
        _("TLS certificate domain; for REALITY, an allowed client SNI covered by the handshake target certificate."));
    const certificatePathOption = field(form.Value, 'certificate_path', _('Certificate File'), tls,
        _("Absolute path to the PEM certificate on this router, including intermediate certificates when needed."));
    certificatePathOption.rmempty = false;
    const keyPathOption = field(form.Value, 'key_path', _('Private Key File'), tls,
        _("Absolute path to the PEM private key paired with the certificate."));
    keyPathOption.rmempty = false;

    const reality = [{ type: 'vless', security: 'reality' }];
    const realityServerOption = field(form.Value, 'reality_server', _('REALITY Handshake Server'), reality,
        _("TLS handshake target hostname or IP, without a scheme or port."));
    realityServerOption.datatype = 'host';
    realityServerOption.rmempty = false;
    const realityPortOption = field(form.Value, 'reality_port', _('REALITY Handshake Port'), reality,
        _("TLS port of the handshake target, usually 443."));
    realityPortOption.default = '443';
    realityPortOption.datatype = 'port';
    realityPortOption.rmempty = false;
    const realityPrivateKeyOption = field(form.Value, 'reality_private_key', _('REALITY Private Key'), reality,
        _("REALITY X25519 private key; give clients its paired public key."));
    realityPrivateKeyOption.password = true;
    realityPrivateKeyOption.rmempty = false;
    field(form.Value, 'reality_short_id', _('REALITY Short ID'), reality,
        _("Use the same short ID on both ends: an even number of hexadecimal digits, up to 16; empty is allowed."));

    const hysteria = [{ type: 'hysteria2', core: 'sing-box' }];
    const obfsPasswordOption = field(form.Value, 'obfs_password', _('Salamander Password'), hysteria,
        _("Set a Salamander password to enable obfuscation; clients must use the same password."));
    obfsPasswordOption.password = true;
    for (const [key, label] of [['up_mbps', _('Upload Bandwidth (Mbps)')], ['down_mbps', _('Download Bandwidth (Mbps)')]]) {
        const bandwidthOption = field(form.Value, key, label, hysteria,
            _("Bandwidth in Mbps, from the server perspective; empty or 0 uses the core default."));
        bandwidthOption.datatype = 'range(0,1000000)';
        bandwidthOption.placeholder = '0';
    }
    FormUtils.createLogFlagOption(section);
    const logLevelOption = field(form.ListValue, 'log_level', _('Log Level'), undefined,
        _("Minimum severity recorded by the core; debug includes more connection details."));
    for (const level of ['debug', 'info', 'warn', 'error']) logLevelOption.value(level);
    logLevelOption.default = 'info';
    logLevelOption.rmempty = false;
}
