import view from "view";
import uci from "uci";
import {LuciFlied} from "../enum/hijpass";
import form from "form";
import {SaveApplyUtils} from "../utils/actions/save-apply/index";
import {ServiceUtils} from "../utils/base/luci/service";
import {FormUtils} from "../utils/base/luci/form";
import {ValidationUtils} from "../utils/base/luci/validation";
import {FilePathUtils} from "../utils/base/files/paths";
import {UciUtils} from "../utils/base/luci/uci";

const v = view.extend({
    load: function () {
        return Promise.all([
            uci.load(LuciFlied.SERVER_CONF_NAME),
            uci.load(LuciFlied.CONF_NAME),
            ServiceUtils.getServiceInstances(LuciFlied.SERVER_CONF_NAME),
        ]);
    },

    handleSaveApply: SaveApplyUtils.genHandleSaveApply(),
    handleSave: function (ev?: Event) {
        return view.prototype.handleSave.call(this, ev);
    },

    render: async function (data: any[]) {
        let m = new form.Map(LuciFlied.SERVER_CONF_NAME, _('Local Server'),
            _('Run as Local Server'));

        let globalSection = m.section(form.TypedSection, LuciFlied.SERVER_CONF_NAME)
        globalSection.addremove = false;
        globalSection.anonymous = true;
        globalSection.option(form.Flag, 'enabled', _('Enable'), '')
        let s = m.section(form.GridSection, LuciFlied.SERVER_NODE_TYPE)
        FormUtils.setGridSectionMembers(s);
        s.anonymous = true;
        s.sectiontitle = function (sectionId: any) {
            return uci.get(LuciFlied.SERVER_CONF_NAME, sectionId, 'name')
                || sectionId;
        };

        s.handleAdd = function (ev: Event, name?: string) {
            let sectionId = UciUtils.generateUniqueSectionId(LuciFlied.SERVER_CONF_NAME);
            return L.bind(form.GridSection.prototype.handleAdd, this, ev, sectionId)();
        };
        const instances = data[2] ?? {};
        createProxyOptions(s, instances);

        return m.render();
    },
});

// 创建启用状态选项
function createEnabledOption(s: LuCI.form.AbstractSection) {
    let enabled = s.option(form.Flag, 'enabled', _('Enable'), '');
    enabled.modalonly = true;
    enabled.default = '1';
    enabled.rmempty = false;
    return enabled;
}

function createFirewallEnabledOption(s: LuCI.form.AbstractSection) {
    let o = s.option(form.Flag, 'allow_firewall', _('Allow Public Access'), '');
    o.default = '1';
    o.rmempty = false;
    return o;
}

// 创建Grid表格显示选项
function createGridDisplayOptions(s: LuCI.form.AbstractSection, instances: any) {

    // 运行命令（在表格中显示，截取显示）
    let o = createCommandOption(s);
    o.modalonly = false;
    o.cfgvalue = function (section_id) {
        let command = uci.get(LuciFlied.SERVER_CONF_NAME, section_id, 'command');
        if (command && command.length > 50) {
            return command.substring(0, 47) + '...';
        }
        return command || '';
    };

    let portOpt = s.option(form.TextValue, 'listen_port', _('Listen Port'),
        _('Server Listen Port'));
    portOpt.modalonly = false;
    portOpt.textvalue = function (section_id: string) {
        let value = uci.get(LuciFlied.SERVER_CONF_NAME, section_id, 'listen_port');
        return E('span', {}, value || '-');
    };

    let statusOpt = s.option(form.TextValue, 'run_status', _('Status'), '');
    statusOpt.modalonly = false;
    statusOpt.textvalue = function (section_id: string) {
        const name = uci.get(LuciFlied.SERVER_CONF_NAME, section_id, 'name');
        const instanceName = section_id + (name ? '-' + name : '');
        const running = instances?.[instanceName]?.running ?? false;
        return E('span', {style: 'color:' + (running ? 'green' : 'red')}, running ? _('Running') : _('Not Running'));
    };

    o = createEnabledOption(s);
    o.editable = true;
    o.modalonly = false;
}

// 创建节点名称编辑选项
function createNodeNameOption(s: LuCI.form.AbstractSection) {
    let o = s.option(form.Value, 'name', _('Node Name'),
        _('Modify Server Node Name'));
    o.modalonly = true;
    o.validate = ValidationUtils.createTagValidator(LuciFlied.SERVER_CONF_NAME, LuciFlied.SERVER_NODE_TYPE, 'name')
    return o;
}

// 修改运行命令选项为编辑表单专用
function createCommandOption(s: LuCI.form.AbstractSection) {
    let o = s.option(form.Value, 'command', _('Run Command'),
        _('Server Run Command. Executed with root privileges.'));
    o.default = '/usr/bin/xray -c {conf_path}';
    o.rmempty = false;
    o.modalonly = true;
    return o;
}

// 配置文件内容编辑器
function createConfContentOption(s: LuCI.form.AbstractSection) {
    let o = s.option(form.TextValue, 'custom_conf', _('Configuration File Content'),
        _('Edit Configuration File'));
    o.modalonly = true;
    const serverDir = FilePathUtils.getFilePath('server_dir', LuciFlied.SERVER_CONF_NAME);
    FormUtils.setConfContentOptionMembers(o, LuciFlied.SERVER_CONF_NAME, serverDir);
    return o;
}

// 修改其他选项为编辑表单专用
function createListenPortOption(s: LuCI.form.AbstractSection) {
    let o = s.option(form.Value, 'listen_port', _('Listen Port'),
        _('Server Listen Port'));
    o.datatype = 'port';
    o.rmempty = false;
    o.modalonly = true;
    o.validate = ValidationUtils.validatePortConflict
    return o;
}

function createProcdEnvOption(s: LuCI.form.AbstractSection) {
    let o = s.option(form.DynamicList, 'procd_env', _('Procd Environment Variables'),
        _('Procd Environment Variables'));
    o.modalonly = true; // 只在编辑表单中显示
    return o;
}

function createLogRedirectOption(s: LuCI.form.AbstractSection) {
    return FormUtils.createLogFlagOption(s, LuciFlied.SERVER_CONF_NAME, undefined);
}

// 创建所有代理配置选项
function createProxyOptions(s: LuCI.form.AbstractSection, instances: any) {
    // 创建Grid表格显示选项
    createGridDisplayOptions(s, instances);
    createNodeNameOption(s);
    // 启用状态（在表格中显示并可直接修改）
    createEnabledOption(s);
    // 创建编辑表单选项
    createCommandOption(s);
    createConfContentOption(s);
    createListenPortOption(s);
    createFirewallEnabledOption(s);
    createProcdEnvOption(s);
    createLogRedirectOption(s);
}

export default v;
