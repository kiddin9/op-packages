import { LuciFlied } from "../../../enum/hijpass";
import fs from "fs";
import uci from "uci";
import { FilePathUtils } from "../../base/files/paths";

async function cleanupChangedNodeFiles(changes: any) {
    async function cleanup(type: string, sectionId: string, keepPath?: string) {
        const args = keepPath ? [type, sectionId, keepPath] : [type, sectionId];
        await fs.exec('/usr/lib/hijpass/rm.sh', args);
    }

    if (changes?.hijpass) {
        for (let change of changes.hijpass) {
            if (change.length === 2 && change[0] === 'remove') {
                await cleanup('proxy', change[1]);
            }
            if (change.length === 4 && change[0] === 'set' && change[2] === 'name') {
                const section = uci.get(LuciFlied.CONF_NAME, change[1]);
                const keepPath = section ? FilePathUtils.getProxyConfigFilePath(section) : undefined;
                await cleanup('proxy', change[1], keepPath);
            }
        }
    }

    if (changes?.hijserver) {
        for (let change of changes.hijserver) {
            if (change.length === 2 && change[0] === 'remove') {
                await cleanup('server', change[1]);
            }
            if (change.length === 4 && change[0] === 'set' && change[2] === 'name') {
                const section = uci.get(LuciFlied.SERVER_CONF_NAME, change[1]);
                const keepPath = section ? FilePathUtils.getServerConfigFilePath(section) : undefined;
                await cleanup('server', change[1], keepPath);
            }
        }
    }
}

const NodeFileCleanupUtils = {
    cleanupChangedNodeFiles,
}

export { NodeFileCleanupUtils }
