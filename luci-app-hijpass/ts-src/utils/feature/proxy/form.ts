import fs from "fs";
import form from "form";
import uci from "uci";
import ui from "ui";
import { CORE_PROTOCOLS, CORE_TYPE, CoreType, HijpassValues, LuciFlied, PROXY_TYPE, ProxyType, normalizeCoreType } from "../../../enum/hijpass";
import { JsonUtils } from "../../base/files/json";
import { NotificationUtils } from "../../base/luci/notification";
import { UciUtils } from "../../base/luci/uci";
import { ValidationUtils } from "../../base/luci/validation";
import { ProxyConfigFileUtils } from "./config-file";
import { ProxyChainUtils } from "./chain";
import { ImportedProxyConfig, ProxyShareLinkUtils } from "./share-link";
import { findProxyDependencyCycleFrom } from "./validation";

const PROTOCOL_CORES: CoreType[] = [CORE_TYPE.XRAY, CORE_TYPE.SING_BOX];

function loadProxyLog(logPath: string, contentEl: HTMLElement) {
    contentEl.textContent = _('Loading...');
    fs.exec('/usr/bin/tail', ['-n', '200', logPath])
        .then((result: any) => {
            let text = (result && result.stdout) ? result.stdout.trim() : '';
            text = text.replace(/\x1b\[[0-9;]*m/g, '');
            contentEl.textContent = text || _('No Logs');
            contentEl.scrollTop = contentEl.scrollHeight;
        })
        .catch(() => { contentEl.textContent = _('Read Failed'); });
}

function updateLatencyButton(el: HTMLElement, ms: number) {
    el.textContent = ms + 'ms';
    if (ms < 300) {
        el.style.backgroundColor = '#1a7a3a';
        el.style.borderColor = '#1a7a3a';
    } else if (ms < 500) {
        el.style.backgroundColor = '#7a6a00';
        el.style.borderColor = '#7a6a00';
    } else {
        el.style.backgroundColor = '#7a2020';
        el.style.borderColor = '#7a2020';
    }
}

function applyFilter(typeSelect: HTMLSelectElement, core: string): void {
    const normalizedCore = normalizeCoreType(core);
    if (normalizedCore === CORE_TYPE.CUSTOM) return;
    const effectiveCore: CoreType = (normalizedCore === CORE_TYPE.XRAY) ? CORE_TYPE.XRAY : CORE_TYPE.SING_BOX;
    const valid: ProxyType[] = [
        ...(CORE_PROTOCOLS[effectiveCore] ?? []),
        PROXY_TYPE.LOAD_BALANCE,
    ];
    Array.from(typeSelect.options).forEach(
        (o: HTMLOptionElement) => (o.hidden = !valid.includes(o.value as ProxyType))
    );
    if (!valid.includes(typeSelect.value as ProxyType)) {
        typeSelect.value = PROXY_TYPE.SHADOWSOCKS;
        typeSelect.dispatchEvent(new Event('change', { bubbles: true }));
    }
}

function getProxyChainText(sectionId: string): string {
    const currentName = uci.get(LuciFlied.CONF_NAME, sectionId, 'name') || sectionId;
    const chain = ProxyChainUtils.collectProxyChain(currentName, ProxyChainUtils.getProxySectionMap());
    const upstreamChain = chain.chain.slice(1);
    if (upstreamChain.length === 0) return '';
    return upstreamChain.join(' -> ') + (chain.cycle ? ' -> ...' : '');
}

function renderProxyInfoWithChain(sectionId: string, mainInfo: Node | string): Node | string {
    const upstreamChain = getProxyChainText(sectionId);
    if (!upstreamChain) return mainInfo;

    const rows: Node[] = [];
    if (typeof mainInfo === 'string') {
        if (mainInfo) rows.push(E('span', {}, mainInfo));
    } else {
        rows.push(mainInfo);
    }

    rows.push(E('span', {
        style: 'opacity:0.65;font-size:0.86em;line-height:1.35'
    }, _('Nested Proxy') + ': ' + upstreamChain));

    return E('span', {
        style: 'display:flex;flex-direction:column;gap:3px;line-height:1.35'
    }, rows);
}

function findProxySection(sectionId: string): any {
    return uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE)
        .find((section: any) => section['.name'] === sectionId);
}

function copyText(text: string, source?: HTMLTextAreaElement): Promise<void> {
    if (navigator.clipboard?.writeText) {
        return navigator.clipboard.writeText(text);
    }

    if (source) {
        source.focus();
        source.select();
        document.execCommand('copy');
        return Promise.resolve();
    }

    return Promise.reject(new Error(_('Clipboard is unavailable')));
}

function sanitizeProxyName(name: string): string {
    const sanitized = (name || '')
        .trim()
        .replace(/[^A-Za-z0-9_-]+/g, '-')
        .replace(/^-+|-+$/g, '');
    return sanitized.slice(0, 48).replace(/-+$/g, '');
}

function createImportedProxyName(imported: ImportedProxyConfig, sectionId: string): string {
    const values = imported.values;
    const base = sanitizeProxyName(imported.name || String(values.server || '') || String(values.type || 'proxy'))
        || 'proxy-' + sectionId;
    const existing = new Set<string>();
    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section: any) {
        if (section.name) existing.add(section.name);
    });

    if (!existing.has(base)) return base;

    for (let i = 2; i < 1000; i++) {
        const suffix = '-' + i;
        const candidate = base.slice(0, 48 - suffix.length) + suffix;
        if (!existing.has(candidate)) return candidate;
    }

    return 'proxy-' + sectionId;
}

function setImportedProxyValues(sectionId: string, imported: ImportedProxyConfig): string {
    const listenPort = ValidationUtils.findAvailablePort(7890);
    const socksPort = ValidationUtils.findAvailablePort(7891, [listenPort]);
    const nodeName = createImportedProxyName(imported, sectionId);
    const values: Record<string, string | string[]> = {
        ...imported.values,
        name: nodeName,
        listen_port: String(listenPort),
        socks_port: String(socksPort),
    };

    Object.keys(values).forEach((key) => {
        const value = values[key];
        if (Array.isArray(value)) {
            if (value.length > 0) uci.set(LuciFlied.CONF_NAME, sectionId, key, value);
        } else if (value !== '') {
            uci.set(LuciFlied.CONF_NAME, sectionId, key, value);
        }
    });

    return nodeName;
}

const ProxyFormUtils = {
    createShareLinkImportSection: function (m: LuCI.form.Map) {
        const s = m.section(form.TypedSection);
        s.anonymous = true;
        s.addremove = false;
        s.render = function () {
            return E('fieldset', { class: 'cbi-section' }, [
                E('legend', {}, _('Share Link')),
                E('div', {
                    style: 'display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap'
                }, [
                    E('div', { class: 'cbi-section-descr', style: 'margin:0' },
                        _('Import a proxy node from a supported share link')),
                    E('button', {
                        class: 'btn cbi-button-action',
                        click: ProxyFormUtils.showImportShareLinkModal,
                    }, _('Import Share Link')),
                ]),
            ]);
        };
        return s;
    },

    showImportShareLinkModal: function () {
        const coreSelect = E('select', {
            class: 'cbi-input-select',
            style: 'min-width:180px'
        }, [
            E('option', { value: CORE_TYPE.SING_BOX }, 'sing-box'),
            E('option', { value: CORE_TYPE.XRAY }, 'xray'),
        ]) as HTMLSelectElement;
        const input = E('textarea', {
            class: 'cbi-input-textarea',
            style: 'width:100%;min-height:120px;box-sizing:border-box',
            placeholder: 'vless://..., hysteria2://..., ss://...'
        }) as HTMLTextAreaElement;

        ui.showModal(_('Import Share Link'), [
            E('div', { class: 'cbi-section' }, [
                E('div', { class: 'cbi-section-descr' },
                    _('Paste one supported proxy share link. Select the backend core manually; local ports and runtime options will be generated automatically.')),
                E('div', {
                    style: 'display:grid;grid-template-columns:minmax(120px,180px) minmax(180px,1fr);gap:10px;align-items:center;margin:0 0 12px 0'
                }, [
                    E('label', {}, _('Backend Core')),
                    coreSelect,
                ]),
                input,
            ]),
            E('div', { class: 'right', style: 'display:flex;justify-content:flex-end;gap:10px' }, [
                E('button', { class: 'btn cbi-button', click: ui.hideModal }, _('Cancel')),
                E('button', {
                    class: 'btn cbi-button-action',
                    click: async function () {
                        const link = input.value.trim();
                        if (!link) {
                            NotificationUtils.warning(_('Import Failed'), _('Share link is empty'), 3000);
                            return;
                        }

                        try {
                            const imported = ProxyShareLinkUtils.parse(link, coreSelect.value as CoreType);
                            const sectionId = UciUtils.generateUniqueSectionId(LuciFlied.CONF_NAME);
                            uci.add(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, sectionId);
                            const nodeName = setImportedProxyValues(sectionId, imported);
                            await uci.save();
                            ui.hideModal();
                            NotificationUtils.success(_('Import Successful'),
                                _('Imported proxy node "%s". Click Save & Apply to apply it.').format(nodeName), 5000);
                            window.setTimeout(() => window.location.reload(), 500);
                        } catch (e: any) {
                            NotificationUtils.error(_('Import Failed'), _(e.message || 'Invalid share link'), 5000);
                        }
                    }
                }, _('Import')),
            ]),
        ]);
    },

    showExportShareLinkModal: function (sectionId: string) {
        const section = findProxySection(sectionId);
        if (!section) return;

        try {
            const link = ProxyShareLinkUtils.generate(section);
            const input = E('textarea', {
                class: 'cbi-input-textarea',
                readonly: 'readonly',
                style: 'width:100%;min-height:120px;box-sizing:border-box',
            }, link) as HTMLTextAreaElement;
            const name = uci.get(LuciFlied.CONF_NAME, sectionId, 'name') || sectionId;

            ui.showModal(name + ' - ' + _('Share Link'), [
                E('div', { class: 'cbi-section' }, [
                    E('div', { class: 'cbi-section-descr' },
                        _('This link contains protocol connection settings only. Local ports, logs, and nested proxy settings are not exported.')),
                    input,
                ]),
                E('div', { class: 'right', style: 'display:flex;justify-content:flex-end;gap:10px' }, [
                    E('button', { class: 'btn cbi-button', click: ui.hideModal }, _('Close')),
                    E('button', {
                        class: 'btn cbi-button-action',
                        click: function () {
                            copyText(link, input).then(function () {
                                NotificationUtils.success(_('Success'), _('Share link copied to clipboard'), 3000);
                            }).catch(function (e: any) {
                                NotificationUtils.error(_('Copy Failed'), _(e.message || 'Clipboard is unavailable'), 3000);
                            });
                        }
                    }, _('Copy Share Link')),
                ]),
            ]);
            window.setTimeout(() => input.select(), 0);
        } catch (e: any) {
            NotificationUtils.error(_('Export Failed'), _(e.message || 'Unsupported proxy type'), 5000);
        }
    },

    renderProxyType: function (section_id: string) {
        let type = uci.get(LuciFlied.CONF_NAME, section_id, 'type');
        let coreValue = normalizeCoreType(uci.get(LuciFlied.CONF_NAME, section_id, 'core') || CORE_TYPE.CUSTOM)
        if (coreValue === CORE_TYPE.CUSTOM) {
            return E('span', {}, _('Custom'));
        }
        let typeLabel = HijpassValues.PROXY_TYPES.find(t => t.value === type)?.label || type || '';
        let coreLabel = HijpassValues.DUAL_CORES.find(c => c.value === coreValue)?.label || coreValue;
        let coreTag = E('span', { style: 'opacity:0.55;font-size:0.82em;margin-left:4px' }, `(${coreLabel})`);
        return E('span', {}, [E('span', {}, _(typeLabel)), coreTag]);
    },

    renderProxyServerInfo: function (section_id: string) {
        const core = normalizeCoreType(uci.get(LuciFlied.CONF_NAME, section_id, 'core') || CORE_TYPE.CUSTOM);
        let type = uci.get(LuciFlied.CONF_NAME, section_id, 'type') || PROXY_TYPE.CUSTOM;
        let server_name = uci.get(LuciFlied.CONF_NAME, section_id, 'tls_server_name');
        if (!server_name) {
            server_name = uci.get(LuciFlied.CONF_NAME, section_id, 'server');
        }
        let server_port = uci.get(LuciFlied.CONF_NAME, section_id, 'server_port');

        if (core === CORE_TYPE.CUSTOM) {
            const command = uci.get(LuciFlied.CONF_NAME, section_id, 'command');
            if (command && command.length > 50) {
                return renderProxyInfoWithChain(section_id,
                    E('span', { title: command }, command.substring(0, 47) + '...'));
            }
            return renderProxyInfoWithChain(section_id, command || '');
        }

        switch (type) {
            case PROXY_TYPE.LOAD_BALANCE: {
                const members = ProxyChainUtils.normalizeProxyNodeList(
                    uci.get(LuciFlied.CONF_NAME, section_id, 'member_node'));
                const strategy = uci.get(LuciFlied.CONF_NAME, section_id, 'strategy') || 'leastLoad';
                const strategyLabels: Record<string, string> = {
                    random: _('Random'),
                    roundRobin: _('Round Robin'),
                    leastPing: _('Lowest Ping'),
                    leastLoad: _('Lowest Load'),
                };
                const mode = core === CORE_TYPE.SING_BOX ? 'URLTest' : (strategyLabels[strategy] || strategy);
                return E('span', {}, _('%s member nodes · %s').format(String(members.length), mode));
            }
            case PROXY_TYPE.HYSTERIA2:
                return renderProxyInfoWithChain(section_id,
                    E('span', {}, server_name ? server_name + ':' + (server_port || '443') : _('Not Configured')));
            case PROXY_TYPE.SHADOWSOCKS: {
                let method = uci.get(LuciFlied.CONF_NAME, section_id, 'method');
                return renderProxyInfoWithChain(section_id,
                    E('span', {}, server_name ? server_name + ':' + (server_port || '-') + ' (' + (method || '-') + ')' : _('Not Configured')));
            }
            case PROXY_TYPE.TUIC: {
                let congestion = uci.get(LuciFlied.CONF_NAME, section_id, 'congestion_control');
                return renderProxyInfoWithChain(section_id,
                    E('span', {}, server_name ? server_name + ':' + (server_port || '-') + ' (' + (congestion || 'cubic') + ')' : _('Not Configured')));
            }
            case PROXY_TYPE.SHADOWTLS: {
                let version = uci.get(LuciFlied.CONF_NAME, section_id, 'version');
                return renderProxyInfoWithChain(section_id,
                    E('span', {}, server_name ? server_name + ':' + (server_port || '-') + ' (v' + (version || '1') + ')' : _('Not Configured')));
            }
            case PROXY_TYPE.VLESS: {
                let flow = uci.get(LuciFlied.CONF_NAME, section_id, 'flow');
                return renderProxyInfoWithChain(section_id,
                    E('span', {}, server_name ? server_name + ':' + (server_port || '-') + (flow ? ' (' + flow + ')' : '') : _('Not Configured')));
            }
            default:
                return renderProxyInfoWithChain(section_id, '');
        }
    },

    renderRunStatus: function (section_id: string, instances: any) {
        const name = uci.get(LuciFlied.CONF_NAME, section_id, 'name');
        const instanceName = section_id + (name ? '-' + name : '');
        const running = instances?.[instanceName]?.running ?? false;
        return E('span', { style: 'color:' + (running ? 'green' : 'red') }, running ? _('Running') : _('Not Running'));
    },

    createGridActionButtons: function (section_id: string) {
        const btns: Node[] = [];
        const section = findProxySection(section_id);

        if (section && ProxyShareLinkUtils.canExport(section)) {
            btns.push(E('button', {
                class: 'btn cbi-button',
                style: 'background-color:#4d6270;border-color:#4d6270',
                click: function () {
                    ProxyFormUtils.showExportShareLinkModal(section_id);
                }
            }, _('Share')));
        }

        let core = uci.get(LuciFlied.CONF_NAME, section_id, 'core');
        if (normalizeCoreType(core) !== CORE_TYPE.CUSTOM) {
            btns.push(E('button', {
                class: 'btn cbi-button',
                style: 'background-color:#5a4a8a;border-color:#5a4a8a',
                click: function () {
                    let section = uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE)
                        .find((s: any) => s['.name'] === section_id);
                    if (!section) return;
                    let conf: {};
                    try {
                        conf = ProxyConfigFileUtils.generateProxyConfigFromSection(section)
                            || { error: _('Invalid proxy config') };
                    } catch (e: any) {
                        conf = { error: e.message };
                    }
                    let name = uci.get(LuciFlied.CONF_NAME, section_id, 'name') || section_id;
                    let contentEl = E('pre', {
                        style: 'max-height:500px;overflow:auto;padding:10px;border-radius:4px;white-space:pre;font-size:0.8em'
                    }, JSON.stringify(conf, JsonUtils.omitEmptyReplacer, 2)) as HTMLElement;
                    ui.showModal(name + ' - ' + _('Config Preview'), [
                        E('div', { class: 'cbi-section' }, [contentEl]),
                        E('div', { class: 'right' }, [
                            E('button', { class: 'btn cbi-button', click: ui.hideModal }, _('Close'))
                        ])
                    ]);
                }
            }, _('Preview')));
        }

        let logPath = uci.get(LuciFlied.CONF_NAME, section_id, 'log_path');
        if (logPath) {
            let name = uci.get(LuciFlied.CONF_NAME, section_id, 'name') || section_id;
            btns.push(E('button', {
                class: 'btn cbi-button',
                style: 'background-color:#3d6b5e;border-color:#3d6b5e',
                click: function () {
                    let contentEl = E('pre', {
                        style: 'max-height:500px;overflow:auto;padding:10px;border-radius:4px;white-space:pre;font-size:0.8em'
                    }, '') as HTMLElement;
                    loadProxyLog(logPath, contentEl);
                    ui.showModal(name + ' - ' + _('Log'), [
                        E('div', { class: 'cbi-section' }, [contentEl]),
                        E('div', { class: 'right', style: 'display:flex;justify-content:flex-end;gap:10px' }, [
                            E('button', { class: 'btn cbi-button', click: ui.hideModal }, _('Close')),
                            E('button', { class: 'btn cbi-button-action', click: function () { loadProxyLog(logPath, contentEl); } }, _('Refresh'))
                        ])
                    ]);
                }
            }, _('Log')));
        }

        let port = uci.get(LuciFlied.CONF_NAME, section_id, 'socks_port');
        let enabled = uci.get(LuciFlied.CONF_NAME, section_id, 'enabled');
        if (port && enabled === '1') {
            btns.push(E('button', {
                class: 'btn cbi-button',
                'data-latency': port,
                style: 'background-color:#1a6a8a;border-color:#1a6a8a;min-width:70px',
                click: function (ev: MouseEvent) {
                    let el = ev.currentTarget as HTMLElement;
                    el.setAttribute('disabled', 'true');
                    el.textContent = '...';
                    el.style.backgroundColor = '#1a6a8a';
                    el.style.borderColor = '#1a6a8a';
                    fs.exec_direct('/usr/lib/hijpass/net.sh', ['ping', port], 'json')
                        .then((res: any) => {
                            if (res && res.ms != null) {
                                updateLatencyButton(el, res.ms);
                            } else {
                                el.textContent = _('Timeout');
                                el.style.backgroundColor = '#7a2020';
                                el.style.borderColor = '#7a2020';
                            }
                        })
                        .catch(() => {
                            el.textContent = _('Failed');
                            el.style.backgroundColor = '#7a2020';
                            el.style.borderColor = '#7a2020';
                        })
                        .finally(() => { el.removeAttribute('disabled'); });
                }
            }, _('Speed Test')));
        }

        return E('span', { style: 'display:flex;gap:8px;flex-wrap:wrap' }, btns);
    },

    forProtocols: function (
        o: LuCI.form.AbstractValue,
        types: ProxyType[],
        conditions: Record<string, string | RegExp> = {}
    ): void {
        for (const type of types) {
            for (const core of PROTOCOL_CORES) {
                if (CORE_PROTOCOLS[core]?.includes(type)) {
                    o.depends({ type, core, ...conditions });
                }
            }
        }
    },

    forCoreProtocols: function (o: LuCI.form.AbstractValue, core: CoreType, types: ProxyType[]): void {
        types.forEach(t => o.depends({ type: t, core }));
    },

    createCoreAndTypeOptions: function (s: LuCI.form.AbstractSection): void {
        let coreOpt = s.option(form.ListValue, 'core', _('Backend Core'),
            _('Select backend core for this proxy node'));
        coreOpt.modalonly = true;
        coreOpt.default = CORE_TYPE.SING_BOX;
        coreOpt.rmempty = false;
        HijpassValues.DUAL_CORES.forEach(c => coreOpt.value(c.value, _(c.label)));

        let typeOpt = s.option(form.ListValue, 'type', _('Proxy Type'),
            _('Select Proxy Type'));
        typeOpt.modalonly = true;
        typeOpt.default = PROXY_TYPE.SHADOWSOCKS;
        typeOpt.rmempty = false;
        typeOpt.depends('core', CORE_TYPE.XRAY);
        typeOpt.depends('core', CORE_TYPE.SING_BOX);
        HijpassValues.PROXY_TYPES.forEach(t => typeOpt.value(t.value, _(t.label)));
        typeOpt.validate = function (sectionId: string, value: ProxyType) {
            const core = normalizeCoreType(this.section.formvalue(sectionId, 'core')) as CoreType;
            return value === PROXY_TYPE.LOAD_BALANCE || CORE_PROTOCOLS[core]?.includes(value)
                ? true
                : _('Selected core "%s" does not support %s').format(core, value);
        };

        typeOpt.renderWidget = function (section_id: string, option_index: number, cfgvalue: string): Node {
            const widget = form.ListValue.prototype.renderWidget.call(
                this, section_id, option_index, cfgvalue) as HTMLElement;
            const typeSelect = widget.querySelector('select') as HTMLSelectElement;

            setTimeout(() => {
                const coreEl = document.getElementById(coreOpt.cbid(section_id));
                const coreSelect = coreEl?.querySelector('select') as HTMLSelectElement | null;
                if (!coreSelect) return;
                applyFilter(typeSelect, coreSelect.value);
                if (!coreSelect.dataset['filterAttached']) {
                    coreSelect.dataset['filterAttached'] = '1';
                    coreSelect.addEventListener('change', () => applyFilter(typeSelect, coreSelect.value));
                }
            }, 0);

            return widget;
        };
    },

    createUpstreamProxyNodeOption: function (s: LuCI.form.AbstractSection): void {
        let upstreamOpt = s.option(form.ListValue, 'upstream_proxy_node', _('Upstream Proxy Node'),
            _('Use another proxy node as the upstream through its local SOCKS port'));
        upstreamOpt.modalonly = true;
        upstreamOpt.rmempty = true;
        const proxyProtocols = HijpassValues.PROXY_TYPES
            .map(item => item.value as ProxyType)
            .filter(type => type !== PROXY_TYPE.LOAD_BALANCE);
        ProxyFormUtils.forProtocols(upstreamOpt, proxyProtocols);
        upstreamOpt.load = function (sectionId: string) {
            delete this.keylist;
            delete this.vallist;
            this.value('', _('None'));

            const currentName = (uci.get(LuciFlied.CONF_NAME, sectionId, 'name') || sectionId);
            ProxyChainUtils.getProxySections().forEach((section: any) => {
                const name = ProxyChainUtils.getProxyName(section);
                if (!name || section['.name'] === sectionId || name === currentName) return;

                let label = name;
                if (section.socks_port) label += ' (' + section.socks_port + ')';
                if (section.enabled !== '1') label += ' - ' + _('Disabled');
                this.value(name, label);
            });

            return form.ListValue.prototype.load.apply(this, [sectionId]);
        };
        upstreamOpt.validate = function (sectionId: string, value: string) {
            if (!value) return true;
            const currentName = this.section.formvalue(sectionId, 'name')
                || uci.get(LuciFlied.CONF_NAME, sectionId, 'name')
                || sectionId;
            if (value === currentName) {
                return _('Cannot use itself as upstream proxy');
            }
            const sections = ProxyChainUtils.getProxySectionMap();
            if (!sections.has(value)) return _('Upstream proxy node not found');

            const dependencyCycle = findProxyDependencyCycleFrom(currentName, [value], sections);
            return dependencyCycle
                ? _('Proxy node dependency chain has a cycle: %s').format(dependencyCycle.join(' -> '))
                : true;
        };
    },

    createProxyPortOptions: function (s: LuCI.form.AbstractSection) {
        let listenInp: HTMLInputElement | null = null;
        let socksInp: HTMLInputElement | null = null;

        let listenPortOpt = s.option(form.Value, 'listen_port', _('Local Listen Port'),
            _('Local Transparent Proxy Listen Port'));
        listenPortOpt.datatype = 'port';
        listenPortOpt.rmempty = false;
        listenPortOpt.modalonly = true;
        listenPortOpt.validate = function (sectionId: string, value: string) {
            const socksPort = this.section.formvalue(sectionId, 'socks_port');
            if (socksPort === value) {
                return _("Conflicts with SOCKS Port")
            }
            return ValidationUtils.validatePortConflict.call(this, sectionId, value);
        }
        listenPortOpt.load = function (section_id: string) {
            let value = form.Value.prototype.load.call(this, section_id);
            if (value) {
                return value;
            }
            let port = ValidationUtils.findAvailablePort(7890)
            form.Value.prototype.write.call(this, section_id, port);
            return port.toString();
        };
        listenPortOpt.renderWidget = function (section_id: string, option_index: number, cfgvalue: any) {
            let input = form.Value.prototype.renderWidget.call(this, section_id, option_index, cfgvalue) as HTMLElement;
            listenInp = input.querySelector('input') as HTMLInputElement;
            let btn = E('button', {
                class: 'btn cbi-button',
                style: 'margin-left:6px',
                type: 'button',
                click: function () {
                    let current = Number(listenInp.value);
                    let usedPorts = ValidationUtils.getUsedPortsExcluding(section_id);
                    let siblingPort = socksInp ? Number(socksInp.value) : 0;
                    if (siblingPort) usedPorts.push(siblingPort);
                    if (current && !usedPorts.includes(current)) return;
                    let port = siblingPort ? siblingPort + 1 : 7890;
                    while (usedPorts.includes(port)) port++;
                    listenInp.value = port.toString();
                    listenInp.dispatchEvent(new Event('input', { bubbles: true }));
                    listenInp.dispatchEvent(new Event('change', { bubbles: true }));
                }
            }, _('Auto Generate'));
            return E('div', { style: 'display:flex;align-items:center' }, [input, btn]);
        };

        let socksPortOpt = s.option(form.Value, 'socks_port', _('Local SOCKS Port'),
            _('Local SOCKS Listen Port'));
        socksPortOpt.datatype = 'port';
        socksPortOpt.rmempty = false;
        socksPortOpt.modalonly = true;
        socksPortOpt.validate = function (sectionId: string, value: string) {
            const listenPort = this.section.formvalue(sectionId, 'listen_port');
            if (listenPort === value) {
                return _("Conflicts with Transparent Proxy Port")
            }
            return ValidationUtils.validatePortConflict.call(this, sectionId, value);
        }
        socksPortOpt.load = function (section_id: string) {
            let value = form.Value.prototype.load.call(this, section_id);
            if (value) {
                return value;
            }
            let port = ValidationUtils.findAvailablePort(7891)
            form.Value.prototype.write.call(this, section_id, port);
            return port.toString();
        };
        socksPortOpt.renderWidget = function (section_id: string, option_index: number, cfgvalue: any) {
            let input = form.Value.prototype.renderWidget.call(this, section_id, option_index, cfgvalue) as HTMLElement;
            socksInp = input.querySelector('input') as HTMLInputElement;
            let btn = E('button', {
                class: 'btn cbi-button',
                style: 'margin-left:6px',
                type: 'button',
                click: function () {
                    let current = Number(socksInp.value);
                    let usedPorts = ValidationUtils.getUsedPortsExcluding(section_id);
                    let siblingPort = listenInp ? Number(listenInp.value) : 0;
                    if (siblingPort) usedPorts.push(siblingPort);
                    if (current && !usedPorts.includes(current)) return;
                    let port = siblingPort ? siblingPort + 1 : 7891;
                    while (usedPorts.includes(port)) port++;
                    socksInp.value = port.toString();
                    socksInp.dispatchEvent(new Event('input', { bubbles: true }));
                    socksInp.dispatchEvent(new Event('change', { bubbles: true }));
                }
            }, _('Auto Generate'));
            return E('div', { style: 'display:flex;align-items:center' }, [input, btn]);
        };
    },
}

export { ProxyFormUtils }
