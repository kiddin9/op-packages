import { LuciFlied, ShuntTag } from "../../../enum/hijpass";
import fs from "fs";
import form from "form";
import uci from "uci";
import { FilePathUtils } from "../files/paths";

const FormUtils = {
    setAnonymousGridSectionMembers: function (section: any) {
        FormUtils.setGridSectionMembers(section);
        section.anonymous = true;
        section.sectiontitle = function (sectionId: any) {
            return uci.get(LuciFlied.CONF_NAME, sectionId, 'name')
                || uci.get(LuciFlied.CONF_NAME, sectionId, 'tag')
                || sectionId;
        };
    },

    setGridSectionMembers: function (section: any) {
        section.anonymous = false;
        section.addremove = true;
        section.sortable = true;
        section.nodescriptions = true;
        section.rowcolors = true;
    },

    setAnonymousSection: function (subsection: any) {
        subsection.anonymous = true;
        subsection.addremove = false;
    },

    simpleHash: function (str: string) {
        let hash = 0;
        str = str ? str : '';
        for (let i = 0; i < str.length; i++) {
            hash = ((hash << 5) - hash) + str.charCodeAt(i);
            hash |= 0;
        }
        return hash;
    },

    setEditorOptionMembers: function (o: LuCI.form.TextValue, filePath: string, fieldName: string) {
        o.rows = 30;
        o.load = function (_) {
            return fs.trimmed(filePath);
        };

        async function writeFile(sectionId: string, formvalue?: string) {
            let currentHash = String(FormUtils.simpleHash(formvalue))
            let oldHash = uci.get(LuciFlied.CONF_NAME, sectionId, fieldName)
            if (currentHash === oldHash) {
                return
            }
            uci.set(LuciFlied.CONF_NAME, sectionId, fieldName, currentHash)
            await fs.write(filePath, (formvalue || '').trim().replace(/\r\n/g, '\n') + '\n');
        }

        o.write = writeFile
        o.remove = writeFile
        o.monospace = true;

        return o;
    },

    setConfContentOptionMembers: function (
        o: LuCI.form.TextValue,
        confName: string,
        dirPath: string,
    ) {
        o.monospace = true;
        o.rows = 20;

        o.load = async function (section_id: string) {
            return L.resolveDefault(fs.read(FilePathUtils.getNodeConfigFilePath(confName, dirPath, section_id)), '');
        };
        o.write = async function (section_id: string, value: string) {
            const content = FilePathUtils.normalizeFileContent(value);
            await fs.write(FilePathUtils.getNodeConfigFilePath(confName, dirPath, section_id, this), content);
            uci.set(confName, section_id, 'custom_conf_hash', String(FormUtils.simpleHash(content)));
        };
        o.remove = async function (section_id: string) {
            await fs.write(FilePathUtils.getNodeConfigFilePath(confName, dirPath, section_id, this), '');
            uci.set(confName, section_id, 'custom_conf_hash', '');
        };
    },

    createTextOption: function (s: LuCI.form.AbstractSection, tabName: string,
        fieldName: string, title: string, description: string, filePath: string) {
        let o = s.taboption(tabName, form.TextValue, fieldName, title, description);
        FormUtils.setEditorOptionMembers(o, filePath, fieldName);
        return o;
    },

    createLogFlagOption: function (s: LuCI.form.AbstractSection, conf_type: string, tab: string) {
        let log_dir = uci.get_first(conf_type, conf_type, 'log_dir');

        let o = tab ? s.taboption(tab, form.Flag, 'log_enabled', _('Record Logs'))
            : s.option(form.Flag, 'log_enabled', _('Record Logs'));
        o.modalonly = true;
        o.write = function (section_id: string, value: string) {
            let log_file = 'shunt.log'
            let name = uci.get(conf_type, section_id, 'name');
            if (name) {
                log_file = name + '-' + section_id + '.log'
            }

            uci.set(conf_type, section_id, 'log_path', log_dir + '/' + log_file);
        }
        o.remove = function (section_id: string) {
            uci.unset(conf_type, section_id, 'log_path');
        }
        o.load = function (section_id: string) {
            if (uci.get(conf_type, section_id, 'log_path')) {
                return '1'
            }
            return '0'
        }
        o.rmempty = true;
        return o;
    },

    appendEnabledNodeListenPorts: function (option: LuCI.form.ListValue) {
        uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, (section: any) => {
            if (section.listen_port && section.enabled === '1') {
                let displayName = _('Proxy node %s: %s').format(section.name, section.listen_port);
                option.value(section.listen_port, displayName);
            }
        });
    },

    loadProxyNodeOptions: function (option: LuCI.form.AbstractValue, includeSlb: boolean = true) {
        option.load = function (section_id: string) {
            delete this.keylist;
            delete this.vallist;

            this.value(ShuntTag.DIRECT_OUTBOUND_TAG, _('Direct'));
            if (includeSlb) {
                this.value(ShuntTag.BLOCK_OUTBOUND_TAG, _('Block'));
            }

            uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, function (section: any) {
                if (section.name && section.enabled === '1') {
                    let displayName = section.name;
                    if (section.socks_port) displayName += ' (' + section.socks_port + ')';
                    this.value(section.name, displayName);
                }
            }.bind(this));

            return form.ListValue.prototype.load.apply(this, [section_id]);
        };
    },

    getEnabledProxyNodeOptions: function (includeSpecial: boolean = true): { value: string, label: string }[] {
        const options: { value: string, label: string }[] = [];

        if (includeSpecial) {
            options.push({ value: ShuntTag.DIRECT_OUTBOUND_TAG, label: _('Direct') });
            options.push({ value: ShuntTag.BLOCK_OUTBOUND_TAG, label: _('Block') });
        }

        uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, (section: any) => {
            if (section.name && section.enabled === '1') {
                let label = section.name;
                if (section.socks_port) label += ' (' + section.socks_port + ')';
                options.push({ value: section.name, label });
            }
        });

        return options;
    },
}

export { FormUtils }
