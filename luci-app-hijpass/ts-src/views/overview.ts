import {LuciFlied} from "../enum/hijpass";
import view from 'view';
import uci from 'uci';
import form from "form";
import {SaveApplyUtils} from "../utils/actions/save-apply/index";
import {ServiceUtils} from "../utils/base/luci/service";
import { OverviewPanelUtils } from "../utils/feature/overview/panel";
import { FlowPreviewUtils } from "../utils/feature/overview/flow-preview";

const v = view.extend({
    load: function () {
        return Promise.all([
            uci.load(LuciFlied.CONF_NAME),
            uci.load(LuciFlied.SERVER_CONF_NAME),
            uci.load('dhcp')
        ]);
    },

    handleSaveApply: SaveApplyUtils.genHandleSaveApply(),

    render: async function () {
        let m = new form.Map(LuciFlied.CONF_NAME, _('HiJpass'));

        ServiceUtils.createStatusSection(m);

        let s = m.section(form.TypedSection, LuciFlied.GLOBAL_SECTION_TYPE);
        s.anonymous = true;
        s.addremove = false;

        s.tab('configuration', _('Configuration'));
        s.tab('flow', _('Flow preview'));

        let enabled = s.taboption('configuration', form.Flag, 'enabled', _('Enable'),
            _('Enable or Disable HiJpass'));
        enabled.default = '0';
        enabled.rmempty = false;

        let delayTime = s.taboption('configuration', form.Value, 'delay_time', _('Delay Time'),
            _('Startup Delay'));
        delayTime.datatype = 'uinteger';
        delayTime.default = '60';
        delayTime.rmempty = false;

        let logLevel = s.taboption('configuration', form.ListValue, 'log_level', _('Log Level'),
            _('Service Log Level'));
        logLevel.modalonly = true;
        logLevel.value('DEBUG', _('Debug'));
        logLevel.value('INFO', _('Info'));
        logLevel.value('WARN', _('Warning'));
        logLevel.value('ERROR', _('Error'));
        logLevel.default = 'INFO';
        logLevel.rmempty = false;

        let preview = s.taboption('configuration', form.Button, '_preview');
        preview.render = function () {
            return OverviewPanelUtils.createActionButtons();
        };

        let flowPreview = s.taboption('flow', form.DummyValue, '_flow_preview');
        flowPreview.render = FlowPreviewUtils.createConfigurationFlowPreview;

        let sTest = m.section(form.TypedSection, 'connectivity_test_section');
        sTest.anonymous = true;
        sTest.addremove = false;
        sTest.render = OverviewPanelUtils.createConnectivityTest

        return m.render();
    }
});

export default v;
