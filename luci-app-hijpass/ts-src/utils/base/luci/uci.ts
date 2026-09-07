import { LuciFlied } from "../../../enum/hijpass";
import uci from "uci";

const UciUtils = {
    camelToSnake: function (str: string) {
        return str.replace(/([A-Z])/g, function (match) {
            return '_' + match.toLowerCase();
        });
    },

    transFromUci: function (object: any, section: any) {
        Object.keys(object).forEach(key => {
            let uciOption = UciUtils.camelToSnake(key)
            if (section[uciOption]) {
                object[key] = section[uciOption]
            }
        });
    },

    generateUniqueSectionId: function (confName: string = LuciFlied.CONF_NAME) {
        let chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
        let result = '';

        for (; ;) {
            result = '';
            for (let i = 0; i < 8; i++) {
                result += chars.charAt(Math.floor(Math.random() * chars.length));
            }

            if (!uci.get(confName, result)) {
                break
            }
        }

        return result;
    },
};

export { UciUtils }
