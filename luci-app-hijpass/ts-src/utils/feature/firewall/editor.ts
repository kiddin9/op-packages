import editor from 'hijpass.editor';
import ui from 'ui';

function showParameters(event: Event) {
    const button = event.currentTarget as HTMLButtonElement;
    const parameters = [
        ['proxyPort', 'integer', _('Proxy node port; 0 disables this entry.')],
        ['shuntPort', 'integer', _('Shunt node port; 0 disables this entry.')],
        ['forwardPort', 'integer', _('Local DNS forwarding port; 0 disables DNS forwarding.')],
        ['protocols', 'string[]', _('Protocols selected for transparent proxying: tcp, udp, or both.')],
        ['proxyLocal', 'boolean', _('Whether to proxy traffic originating from the router.')],
        ['allowAll', 'boolean', _('true: proxy all clients except exclusions; false: proxy only selected clients.')],
        ['proxyMark', 'integer', _('Connection mark for forced proxying (0x1).')],
        ['shuntMark', 'integer', _('Connection mark for shunt routing (0x3).')],
        ['user', 'string', _('Proxy process group excluded from interception.')],
        ['wan', 'string[]', _('WAN device names excluded from interception.')],
        ['interfaces', 'string[]', _('Client device names selected for proxying.')],
        ['macs', 'string[]', _('Client MAC addresses selected for proxying.')],
        ['excludedInterfaces', 'string[]', _('Client device names excluded when allowAll is true.')],
        ['excludedMacs', 'string[]', _('Client MAC addresses excluded when allowAll is true.')],
        ['wanNames', 'string', _('Quoted, comma-separated WAN names for nft interface matches.')],
        ['interfaceNames', 'string', _('Quoted, comma-separated selected client device names.')],
        ['excludedInterfaceNames', 'string', _('Quoted, comma-separated excluded client device names.')],
        ['domainSets', 'boolean', _('Whether to create DNS-managed address sets.')],
        ['useChn', 'boolean', _('Whether to create the CHN domain address sets.')],
        ['useChnRoute', 'boolean', _('Whether to load CHN IPv4/IPv6 route lists.')],
        ['useGfw', 'boolean', _('Whether to create the GFW domain address sets.')],
        ['ip4', 'object', _('IPv4 lists: direct (local, DNS and bypass addresses), proxy (force proxy), china (CHN routes).')],
        ['ip6', 'object', _('IPv6 lists: direct (local, DNS and bypass addresses), proxy (force proxy), china (CHN routes).')],
    ];
    const cellStyle = 'text-align:left;padding:.5rem';
    ui.showModal(_('Template Parameters'), [
        // 样式随内容移除，避免影响 LuCI 复用的其它弹窗。
        E('style', {}, '.hijpass-template-parameters { width:min(56rem, 100%); overflow:hidden; }'),
        E('div', { style: 'max-height:65vh;overflow:auto' }, [
            E('table', { class: 'table' }, [
                E('thead', {}, E('tr', { class: 'tr' }, [_('Parameter'), _('Type'), _('Description')]
                    .map((title, index) => E('th', { class: 'th', scope: 'col', style: cellStyle + (index === 0 ? ';width:40%' : '') }, title)))),
                E('tbody', {}, parameters.map(([name, type, description]) => E('tr', { class: 'tr' }, [
                    E('th', { class: 'td', scope: 'row', style: cellStyle + ';font-weight:normal;overflow-wrap:anywhere' },
                        E('span', { style: 'font-family:monospace' }, 'options.' + name)),
                    E('td', { class: 'td', style: cellStyle }, type),
                    E('td', { class: 'td', style: cellStyle }, description),
                ]))),
            ]),
        ]),
        E('div', { class: 'right' }, E('button', {
            type: 'button', class: 'btn cbi-button',
            click: () => { ui.hideModal(); button.focus(); },
        }, _('Close'))),
    ], 'hijpass-template-parameters');
}

function mount(widget: HTMLElement, label: string) {
    editor.mount(widget, 'firewall', label);
}

export const FirewallEditorUtils = { mount, showParameters };
