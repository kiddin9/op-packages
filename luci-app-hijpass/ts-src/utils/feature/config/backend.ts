import uci from 'uci';
import { LuciFlied } from '../../../enum/hijpass';
import { Backend } from '../../backend';

function snapshot() {
    return JSON.stringify(uci.sections(LuciFlied.CONF_NAME, undefined));
}

async function preview(sectionId: string) {
    const result = await Backend.renderConfigs(snapshot(), sectionId);
    return result.config;
}

const GeneratedConfigUtils = {
    preview,
    validate: async function () {
        const result = await Backend.validateConfigs(snapshot());
        if (!result.ok) throw new Error(_('Configuration validation failed'));
    },
};

export { GeneratedConfigUtils };
