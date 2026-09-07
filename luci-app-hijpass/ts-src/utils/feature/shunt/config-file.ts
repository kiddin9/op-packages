import { LuciFlied } from "../../../enum/hijpass";
import uci from "uci";
import { CoreAdapterFactory } from "../../../core/adapter";
import { JsonUtils } from "../../base/files/json";

const ShuntConfigUtils = {
    getShuntConfData: function () {
        const shuntEnabled = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'enabled');
        if (shuntEnabled === '0') {
            return "";
        }

        const configType = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'config_type');
        if (configType !== 'tmpl') {
            return "";
        }

        let type = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'type');
        return JSON.stringify(CoreAdapterFactory.getCoreAdapter(type).genShuntConf(), JsonUtils.omitEmptyReplacer, 2);
    },
}

export { ShuntConfigUtils }
