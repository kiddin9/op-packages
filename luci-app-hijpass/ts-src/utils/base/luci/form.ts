import { LuciFlied, ShuntTag } from "../../../enum/hijpass";
import { Editor } from "../../backend";
import drafts from "hijpass.drafts";
import form from "form";
import uci from "uci";

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

    setEditorOptionMembers: function (o: LuCI.form.TextValue, editor: Editor, fieldName: string) {
        o.rows = 30;
        o.load = () => drafts.read(editor);
        o.write = (sectionId: string, content: string) =>
            drafts.save(editor, content, sectionId, fieldName);
        o.remove = (sectionId: string) => o.write(sectionId, '');
        o.monospace = true;

        return o;
    },

    setConfContentOptionMembers: function (
        o: LuCI.form.TextValue,
        confName: string,
    ) {
        o.monospace = true;
        o.rows = 20;

        o.load = (sectionId: string) => drafts.read({ resource: 'proxy_config', section: sectionId });
        o.write = function (sectionId: string, content: string) {
            return drafts.save({ resource: 'proxy_config', section: sectionId,
                name: this.section.formvalue(sectionId, 'name') || uci.get(confName, sectionId, 'name') || sectionId },
                content, sectionId, 'custom_conf_hash');
        };
        o.remove = (sectionId: string) => o.write(sectionId, '');
    },

    createTextOption: function (s: LuCI.form.AbstractSection, tabName: string,
        fieldName: string, title: string, description: string, editor: Editor) {
        let o = s.taboption(tabName, form.TextValue, fieldName, title, description);
        FormUtils.setEditorOptionMembers(o, editor, fieldName);
        return o;
    },

    createLogFlagOption: function (s: LuCI.form.AbstractSection, tab?: string) {
        let o = tab ? s.taboption(tab, form.Flag, 'log_enabled', _('Record Logs'))
            : s.option(form.Flag, 'log_enabled', _('Record Logs'));
        o.modalonly = true;
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
