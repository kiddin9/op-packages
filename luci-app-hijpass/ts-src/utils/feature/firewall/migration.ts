import uci from 'uci';
import form from 'form';
import { LuciFlied } from '../../../enum/hijpass';

function pending() {
    const global = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.GLOBAL_SECTION_TYPE);
    return global?.legacy_firewall_template && global.firewall_template_migration_ack !== '1' ? global : null;
}

function renderNotice(editorURL?: string): Node[] {
    const global = pending();
    if (!global) return [];
    return [E('div', { class: 'alert-message warning', role: 'status', style: 'overflow-wrap:anywhere' }, [
        E('strong', {}, _('Firewall template requires manual migration')),
        E('p', {}, _('Legacy and current firewall templates use different formats and cannot be upgraded automatically. Reapply your custom changes in the new template under Firewall Rules.')),
        E('p', {}, _('Previous template: %s').format(global.legacy_firewall_template)),
        ...(editorURL ? [E('a', { href: editorURL }, _('Open Firewall Configuration'))] : []),
    ])];
}

function createDismissOption(section: LuCI.form.AbstractSection) {
    const global = pending();
    if (!global) return;
    const option = section.taboption('nftables', form.Flag, 'firewall_template_migration_ack', _('Hide this migration notice'));
    option.ucisection = global['.name'];
    option.rmempty = false;
    option.default = '0';
}

export const FirewallMigrationUtils = { renderNotice, createDismissOption };
