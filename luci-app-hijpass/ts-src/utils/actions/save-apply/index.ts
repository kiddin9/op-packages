import { LuciFlied } from "../../../enum/hijpass";
import uci from "uci";
import ui from "ui";
import { NotificationUtils } from "../../base/luci/notification";
import { Backend } from "../../backend";
import { PrecheckUtils } from "./precheck";

function isGlobalServiceDisabled() {
    return uci.get_first(LuciFlied.CONF_NAME, LuciFlied.GLOBAL_SECTION_TYPE, 'enabled') === '0';
}

const SaveApplyUtils = {
    genHandleSaveApply: function () {
        return async function (ev: Event, mode?: string | number) {
            try {
                await this.handleSave(ev)

                if (isGlobalServiceDisabled()) {
                    await uci.save();
                    ui.changes.apply(mode == '0');
                    return;
                }

                if (!await PrecheckUtils.runSaveApplyPrechecks()) {
                    return;
                }

                await Backend.validateConfigs(JSON.stringify(uci.sections(LuciFlied.CONF_NAME, undefined)));
                await uci.save();

                ui.changes.apply(mode == '0');
            } catch (e) {
                console.log(e)
                NotificationUtils.error(_('Configuration Apply Failed'), _(e.message), 5000);
            }
        }
    },
}

export { SaveApplyUtils }
