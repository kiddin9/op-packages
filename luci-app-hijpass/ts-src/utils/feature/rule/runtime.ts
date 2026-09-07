import fs from "fs";

import { CORE_TYPE } from "../../../enum/hijpass";
import { NotificationUtils } from "../../base/luci/notification";

function loadCoreVersion(versionElement: HTMLElement, core: string) {
    fs.exec_direct('/usr/lib/hijpass/core-update.sh', ['version', core], 'json')
        .then((result: any) => {
            versionElement.textContent = result?.version || _('Unknown');
        })
        .catch(() => {
            versionElement.textContent = _('Unknown');
        });
}

function loadLatestCoreVersion(versionElement: HTMLElement, core: string) {
    fs.exec_direct('/usr/lib/hijpass/core-update.sh', ['latest', core], 'json')
        .then((result: any) => {
            versionElement.textContent = result?.version || _('Unavailable');
        })
        .catch(() => {
            versionElement.textContent = _('Unavailable');
        });
}

function updateCore(
    core: string,
    title: string,
    versionElement: HTMLElement,
    button: HTMLButtonElement
) {
    button.disabled = true;
    button.textContent = _('Updating...');

    fs.exec_direct('/usr/lib/hijpass/core-update.sh', ['update', core], 'json')
        .then((result: any) => {
            if (result?.success) {
                versionElement.textContent = result.version || _('Updated');
                NotificationUtils.success(
                    title,
                    _('Updated to %s. Restart affected services to use the new version.').format(result.version),
                    6000
                );
                return;
            }

            NotificationUtils.error(
                title,
                _('Update failed: %s').format(result?.error || 'unknown'),
                5000
            );
        })
        .catch((error: any) => {
            NotificationUtils.error(title, error.message || _('Update failed'), 5000);
        })
        .finally(() => {
            button.disabled = false;
            button.textContent = _('Update');
        });
}

function createCoreRow(core: string, label: string) {
    const currentVersionElement = E('span', {
        'style': 'display:inline-block;min-width:5.5em',
        'aria-live': 'polite'
    }, _('Loading...')) as HTMLElement;
    const latestVersionElement = E('span', {
        'style': 'display:inline-block;min-width:5.5em',
        'aria-live': 'polite'
    }, _('Loading...')) as HTMLElement;
    const updateButton = E('button', {
        'class': 'cbi-button cbi-button-action',
        'type': 'button',
        'click': function (event: MouseEvent) {
            event.preventDefault();
            updateCore(core, label, currentVersionElement, event.currentTarget as HTMLButtonElement);
        }
    }, _('Update')) as HTMLButtonElement;

    loadCoreVersion(currentVersionElement, core);
    loadLatestCoreVersion(latestVersionElement, core);

    return E('div', { 'class': 'cbi-value' }, [
        E('label', { 'class': 'cbi-value-title' }, label),
        E('div', {
            'class': 'cbi-value-field',
            'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:12px'
        }, [
            E('span', { 'style': 'display:inline-flex;gap:4px;white-space:nowrap' }, [
                E('strong', {}, _('Current Version') + ':'),
                currentVersionElement
            ]),
            E('span', { 'style': 'display:inline-flex;gap:4px;white-space:nowrap' }, [
                E('strong', {}, _('Latest Version') + ':'),
                latestVersionElement
            ]),
            updateButton
        ])
    ]);
}

const RuntimePanelUtils = {
    createCoreVersionPanel: function () {
        return E('div', { 'class': 'cbi-section' }, [
            E('div', { 'class': 'cbi-section-descr' },
                _('View installed core versions and update runtime components.')),
            E('div', { 'class': 'cbi-section-node' }, [
                createCoreRow(CORE_TYPE.SING_BOX, 'sing-box'),
                createCoreRow(CORE_TYPE.XRAY, 'Xray')
            ])
        ]);
    }
};

export { RuntimePanelUtils };
