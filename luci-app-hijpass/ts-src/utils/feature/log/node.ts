import { Backend } from "../../backend";
import uci from "uci";
import ui from "ui";

function loadNodeLog(logId: string, contentEl: HTMLElement) {
    contentEl.textContent = _('Loading...');
    Backend.readLog(logId)
        .then(result => {
            const text = (result || '').trim().replace(/\x1b\[[0-9;]*m/g, '');
            contentEl.textContent = text || _('No Logs');
            contentEl.scrollTop = contentEl.scrollHeight;
        })
        .catch(error => { contentEl.textContent = _('Read Failed') + ': ' + error.message; });
}

export function createNodeLogButton(configName: string, sectionId: string): HTMLElement | null {
    if (uci.get(configName, sectionId, 'log_enabled') !== '1') return null;

    const name = uci.get(configName, sectionId, 'name') || sectionId;
    const logId = configName + ':' + sectionId;
    return E('button', {
        class: 'btn cbi-button',
        style: 'background-color:#3d6b5e;border-color:#3d6b5e',
        click: function () {
            const contentEl = E('pre', {
                style: 'max-height:500px;overflow:auto;padding:10px;border-radius:4px;white-space:pre;font-size:0.8em'
            }, '') as HTMLElement;
            loadNodeLog(logId, contentEl);
            ui.showModal(name + ' - ' + _('Log'), [
                E('div', { class: 'cbi-section' }, [contentEl]),
                E('div', { class: 'right', style: 'display:flex;justify-content:flex-end;gap:10px' }, [
                    E('button', { class: 'btn cbi-button', click: ui.hideModal }, _('Close')),
                    E('button', { class: 'btn cbi-button-action', click: function () { loadNodeLog(logId, contentEl); } }, _('Refresh'))
                ])
            ]);
        }
    }, _('Log')) as HTMLElement;
}
