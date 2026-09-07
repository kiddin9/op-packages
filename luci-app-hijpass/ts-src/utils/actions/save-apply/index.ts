import { LuciFlied } from "../../../enum/hijpass";
import fs from "fs";
import uci from "uci";
import ui from "ui";
import { SingBoxUtils } from "../../../core/singbox/builder";
import { FactoryType } from "../../../core/adapter";
import { NodeFileCleanupUtils } from "./node-file-cleanup";
import { FilePathUtils } from "../../base/files/paths";
import { ShuntConfigUtils } from "../../feature/shunt/config-file";
import { NotificationUtils } from "../../base/luci/notification";
import { ProxyConfigFileUtils } from "../../feature/proxy/config-file";
import { FormUtils } from "../../base/luci/form";
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
                    await ui.changes.apply(mode == '0');
                    return;
                }

                if (!await PrecheckUtils.runSaveApplyPrechecks()) {
                    return;
                }

                // 生成分流配置并写入文件
                const shuntCoreType = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'type')
                if (shuntCoreType === FactoryType.SING_BOX
                    && uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'ruleset_convert') === '1') {
                    SingBoxUtils.writeGeoRule()
                }
                const shuntConfigType = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'config_type')
                if (shuntConfigType === 'tmpl') {
                    let data = ShuntConfigUtils.getShuntConfData()
                    await fs.write(FilePathUtils.getFilePath('shunt_conf'), data);
                    uci.set_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE,
                        'shunt_hash', data ? String(FormUtils.simpleHash(data)) : '-1');
                }

                await uci.save();
                let changes = await uci.changes()
                await NodeFileCleanupUtils.cleanupChangedNodeFiles(changes)

                // 生成各代理节点客户端配置文件
                await ProxyConfigFileUtils.writeGeneratedProxyConfigs();

                await ui.changes.apply(mode == '0');
            } catch (e) {
                console.log(e)
                NotificationUtils.error(_('Configuration Apply Failed'), _(e.message), 5000);
            }
        }
    },
}

export { SaveApplyUtils }
