import fs from "fs";
import form from "form";
import uci from "uci";
import ui from "ui";
import { CORE_TYPE, LuciFlied, ShuntTag } from "../../../enum/hijpass";
import { FilePathUtils } from "../../base/files/paths";
import { FormUtils } from "../../base/luci/form";
import { NotificationUtils } from "../../base/luci/notification";
import { ShuntConfigUtils } from "./config-file";

function makeSelect(id: string, options: { value: string, label: string }[]) {
    const sel = E('select', {id, class: 'cbi-input-select', style: 'width:100%'}) as HTMLSelectElement;
    options.forEach(({value, label}) => {
        const opt = document.createElement('option');
        opt.value = value;
        opt.textContent = label;
        sel.appendChild(opt);
    });
    return sel;
}

function getReplaceableProxyNodeFields(section: any) {
    const routeFields = section.ip_version_split === '1'
        ? ['proxy_node_v4', 'proxy_node_v6']
        : ['proxy_node'];
    return [...routeFields, 'dns_proxy_node'];
}

function canUseAsDnsExit(node: string) {
    return node !== ShuntTag.BLOCK_OUTBOUND_TAG;
}

const ShuntFormUtils = {
    configureConfigEditor: function (o: LuCI.form.TextValue) {
        o.rows = 30;
        o.monospace = true;
        o.load = async function (_: string) {
            return L.resolveDefault(fs.read(FilePathUtils.getFilePath('shunt_conf')), '');
        };
        o.write = async function (sectionId: string, value: string) {
            const content = (value || '').trim().replace(/\r\n/g, '\n');
            await fs.write(FilePathUtils.getFilePath('shunt_conf'), content ? content + '\n' : '');
            uci.set(LuciFlied.CONF_NAME, sectionId, 'shunt_hash', String(FormUtils.simpleHash(content)));
        };
        o.remove = async function (sectionId: string) {
            if (uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'config_type') !== 'tmpl') {
                await fs.write(FilePathUtils.getFilePath('shunt_conf'), '');
                uci.set(LuciFlied.CONF_NAME, sectionId, 'shunt_hash', '-1');
            }
        };
        o.rmempty = false;
    },

    showPreview: function () {
        try {
            let configJson = ShuntConfigUtils.getShuntConfData()
            let shuntType = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'type') || CORE_TYPE.XRAY
            ui.showModal(_('Preview Configuration'), [
                E('div', {'class': 'cbi-section'}, [
                    E('div', {'class': 'cbi-section-descr'},
                        _('Generated %s JSON Configuration').format(shuntType)),
                    E('pre', {
                        'style': 'max-height: 500px; overflow: auto; padding: 10px; border-radius: 4px;',
                        'id': 'config-preview-content'
                    }, configJson)
                ]),
                E('div', {
                    'class': 'right',
                    'style': 'display: flex; justify-content: flex-end; align-items: center; gap: 10px;'
                }, [
                    E('button', {
                        'class': 'btn cbi-button',
                        'click': ui.hideModal
                    }, _('Close')),
                    E('button', {
                        'class': 'btn cbi-button-action',
                        'click': function (ev) {
                            ev.preventDefault();
                            ev.stopPropagation();
                            let content = document.getElementById('config-preview-content').textContent;
                            navigator.clipboard.writeText(content).then(function () {
                                NotificationUtils.success(_('Success'), _('Configuration copied to clipboard'), 3000);
                            })
                        }
                    }, _('Copy Configuration'))
                ])
            ]);
        } catch (err) {
            console.log(err);
            NotificationUtils.error(_('Configuration Generation Failed'), _(err.message), 5000);
        }
    },

    showBulkReplaceModal: function () {
        const usedNodeValues = new Set<string>();
        const routeRules = uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_ROUTE_RULE_TYPE);
        routeRules.forEach(function (section: any) {
            getReplaceableProxyNodeFields(section).forEach(field => {
                if (section[field]) usedNodeValues.add(section[field]);
            });
        });

        const allNodeOptions = FormUtils.getEnabledProxyNodeOptions(true);
        const fromNodeOptions = allNodeOptions.filter(o => usedNodeValues.has(o.value));

        const fromSel = makeSelect('replace-from', fromNodeOptions);
        const toSel = makeSelect('replace-to', allNodeOptions);

        ui.showModal(_('Bulk Replace Nodes'), [
            E('div', {class: 'cbi-section'}, [
                E('div', {style: 'display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:center'}, [
                    E('div', {}, [E('label', {}, _('From Node')), fromSel]),
                    E('div', {}, [E('label', {}, _('Replace With')), toSel]),
                ])
            ]),
            E('div', {class: 'right', style: 'display:flex;justify-content:flex-end;gap:10px'}, [
                E('button', {class: 'btn cbi-button', click: ui.hideModal}, _('Cancel')),
                E('button', {
                    class: 'btn cbi-button-action',
                    click: async function () {
                        const fromVal = fromSel.value;
                        const toVal = toSel.value;
                        if (fromVal === toVal) {
                            ui.hideModal();
                            return;
                        }
                        const replacesDnsExit = routeRules.some((section: any) => section.dns_proxy_node === fromVal);
                        if (replacesDnsExit && !canUseAsDnsExit(toVal)) {
                            NotificationUtils.warning(
                                _('Configuration conflict'),
                                _('DNS exit cannot use Block'),
                                5000
                            );
                            return;
                        }
                        routeRules.forEach(function (section: any) {
                            getReplaceableProxyNodeFields(section).forEach(field => {
                                if (section[field] === fromVal) {
                                    uci.set(LuciFlied.CONF_NAME, section['.name'], field, toVal);
                                }
                            });
                        });
                        await uci.save();
                        ui.hideModal();
                        location.reload();
                    }
                }, _('Confirm Replace'))
            ])
        ]);
    },

    loadProxyNodeOptions: function (option: LuCI.form.AbstractValue, includeSLB: boolean) {
        FormUtils.loadProxyNodeOptions(option, includeSLB);
    },

    loadDNSServerOptions: function (option: LuCI.form.AbstractValue, includeDefault: boolean) {
        option.load = function (section_id) {
            delete this.keylist;
            delete this.vallist;

            if (includeDefault) {
                this.value('', _('Use Global Default DNS'));
            }

            uci.sections(LuciFlied.CONF_NAME, LuciFlied.SHUNT_DNS_NODE_TYPE, function (section: any) {
                if (section.tag && section.enabled !== '0') {
                    let displayName = section.tag;
                    if (section.server) {
                        displayName += ' (' + section.server + ')';
                    }
                    this.value(section.tag, displayName);
                }
            }.bind(this));

            return form.ListValue.prototype.load.apply(this, [section_id]);
        };
    },

    createSectionContainer: function <T extends LuCI.form.AbstractSection>(
        s: LuCI.form.AbstractSection,
        tab: string,
        id: string,
        sectionType: T,
        sectionName: string,
        title: string
    ) {
        let o = s.taboption(tab, form.SectionValue, id, sectionType, sectionName, title);
        o.depends({config_type: "tmpl"});
        return o;
    },

    createRequiredListValue: function (
        section: LuCI.form.AbstractSection,
        name: string,
        title: string,
        description: string,
        validator?: Function
    ) {
        let o = section.option(form.ListValue, name, title, description);
        o.rmempty = false;
        if (validator) {
            o.validate = validator;
        }
        return o;
    },

    createValidatedDynamicList: function (
        section: LuCI.form.AbstractSection,
        name: string,
        title: string,
        description: string,
        sectionType: string,
        getItemName: (section: any) => any
    ) {
        let o = section.option(form.DynamicList, name, title, description);

        o.load = function (section_id: any) {
            delete this.keylist;
            delete this.vallist;

            uci.sections(LuciFlied.CONF_NAME, sectionType, function (section: any) {
                let itemName = getItemName(section);
                if (itemName) {
                    this.value(itemName.value, itemName.display);
                }
            }.bind(this));

            return form.DynamicList.prototype.load.apply(this, [section_id]);
        };

        o.validate = function (section_id: string, value: string) {
            if (!value || value === '') {
                return true;
            }

            let availableItems = [];
            uci.sections(LuciFlied.CONF_NAME, sectionType, function (section) {
                let itemName = getItemName(section);
                if (itemName) {
                    availableItems.push(itemName.value);
                }
            });

            if (availableItems.indexOf(value) === -1) {
                return _('Item Not Found').format(title, value);
            }

            return true;
        };

        return o;
    },
}

export { ShuntFormUtils }
