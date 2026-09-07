import view from "view";
import uci from "uci";
import form from "form";
import {LuciFlied} from "../enum/hijpass";
import {SaveApplyUtils} from "../utils/actions/save-apply/index";
import { RulePanelUtils } from "../utils/feature/rule/panel";
import { RuntimePanelUtils } from "../utils/feature/rule/runtime";

const v = view.extend({
    load: function () {
        return Promise.all([
            uci.load(LuciFlied.CONF_NAME)
        ]);
    },

    handleSaveApply: SaveApplyUtils.genHandleSaveApply(),

    render: function () {
        let m = new form.Map(LuciFlied.CONF_NAME, _('Resource Management'),
            _('Manage downloadable rule resources and runtime components'));

        let s = m.section(form.TypedSection, LuciFlied.RULE_SECTION_TYPE);
        s.anonymous = true;
        s.addremove = false;

        s.tab('resources', _('Rule Resources'));
        s.tab('runtime', _('Runtime'));

        let downloadButton = s.taboption('resources', form.Button, '_download_all', _('Update All Rules'),
            _('Download All Rules Now'));
        downloadButton.inputtitle = _('Update');
        downloadButton.render = function () {
            return RulePanelUtils.createUpdateButtons();
        }

        let chnDomainList = s.taboption('resources', form.DynamicList, 'chn_domain_list', _('CHN Domain List Download URL'),
            _('CHN Domain List URL'));
        chnDomainList.default = 'https://fastly.jsdelivr.net/gh/felixonmars/dnsmasq-china-list/accelerated-domains.china.conf';
        chnDomainList.rmempty = true;

        let chnV4Route = s.taboption('resources', form.DynamicList, 'chn_v4_route', _('CHN IPv4 Route Download URL'),
            _('CHN IPv4 Route URL'));
        chnV4Route.default = 'https://fastly.jsdelivr.net/gh/gaoyifan/china-operator-ip@ip-lists/china.txt';
        chnV4Route.rmempty = true;

        let chnV6Route = s.taboption('resources', form.DynamicList, 'chn_v6_route', _('CHN IPv6 Route Download URL'),
            _('CHN IPv6 Route URL'));
        chnV6Route.default = 'https://fastly.jsdelivr.net/gh/gaoyifan/china-operator-ip@ip-lists/china6.txt';
        chnV6Route.rmempty = true;

        let gfwList = s.taboption('resources', form.Value, 'gfw_list', _('GFW List Download URL'),
            _('GFW List URL'));
        gfwList.default = 'https://fastly.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/gfw.txt';
        gfwList.rmempty = true;

        let geosite = s.taboption('resources', form.Value, 'geosite', _('GeoSite Database Download URL'),
            _('GeoSite Database URL'));
        geosite.default = 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat';
        geosite.rmempty = false;

        let geoip = s.taboption('resources', form.Value, 'geoip', _('GeoIP Database Download URL'),
            _('GeoIP Database URL'));
        geoip.default = 'https://github.com/Loyalsoldier/geoip/releases/latest/download/geoip.dat';
        geoip.rmempty = false;

        let updateSchedule = s.taboption('resources', form.ListValue, 'update_schedule', _('Auto Update Time'),
            _('Set Auto Update Time'));
        updateSchedule.value('', _('Disable Auto Update'));
        updateSchedule.value('0 5 * * *', _('Every Day 5 AM'));
        updateSchedule.value('0 0 * * *', _('Every Day Midnight'));
        updateSchedule.value('0 5 * * 0', _('Every Sunday 5 AM'));
        updateSchedule.value('0 5 * * 1', _('Every Monday 5 AM'));
        updateSchedule.value('0 5 1 * *', _('1st Day of Month 5 AM'));
        updateSchedule.default = '0 5 * * 1';
        updateSchedule.rmempty = true;

        let downloadTimeout = s.taboption('resources', form.Value, 'download_timeout', _('Download Timeout'),
            _('Single Download Timeout'));
        downloadTimeout.datatype = 'uinteger';
        downloadTimeout.default = '3';
        downloadTimeout.rmempty = false;

        let runtimeTab = s.taboption('runtime', form.DummyValue, '_runtime_tab');
        runtimeTab.render = function () {
            return RuntimePanelUtils.createCoreVersionPanel();
        };

        return m.render();
    }
});

export default v;
