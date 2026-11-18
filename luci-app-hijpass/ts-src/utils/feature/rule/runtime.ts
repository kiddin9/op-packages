import { formatUpdateProgress } from './progress';
import { Backend } from "../../backend";

import { HijpassValues } from "../../../enum/hijpass";
import { NotificationUtils } from "../../base/luci/notification";

function loadCoreVersion(versionElement: HTMLElement, core: string) {
    Backend.coreAction('version', core)
        .then((result: any) => {
            versionElement.textContent = result?.version || _('Unknown');
        })
        .catch(() => {
            versionElement.textContent = _('Unknown');
        });
}

function loadLatestCoreVersion(versionElement: HTMLElement, core: string) {
    Backend.coreAction('latest', core)
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
    button: HTMLButtonElement,
    statusElement: HTMLElement,
    taskId?: string
) {
    button.disabled = true;
    button.textContent = _('Updating...');

    statusElement.textContent = _('Updating...');
    const progress = value => { statusElement.textContent = formatUpdateProgress(value); };
    (taskId ? Backend.resumeCoreUpdate(taskId, progress) : Backend.coreAction('update', core, progress))
        .then((result: any) => {
            if (result?.success) {
                versionElement.textContent = result.version || _('Updated');
                statusElement.textContent = _('Updated to %s. Restart affected services to use the new version.').format(result.version);
                NotificationUtils.success(
                    title,
                    _('Updated to %s. Restart affected services to use the new version.').format(result.version),
                    6000
                );
                return;
            }

            statusElement.textContent = _('Update failed: %s').format(result?.error || 'unknown');
            NotificationUtils.error(
                title,
                _('Update failed: %s').format(result?.error || 'unknown'),
                5000
            );
        })
        .catch((error: any) => {
            statusElement.textContent = error.message || _('Update failed');
            NotificationUtils.error(title, statusElement.textContent, 5000);
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
    const statusElement = E('span', { role: 'status', 'aria-live': 'polite',
        style: 'flex-basis:100%;overflow-wrap:anywhere' }) as HTMLElement;
    const updateButton = E('button', {
        'class': 'cbi-button cbi-button-action',
        'type': 'button',
        'click': function (event: MouseEvent) {
            event.preventDefault();
            if (updateButton.disabled) return;
            updateCore(core, label, currentVersionElement, event.currentTarget as HTMLButtonElement, statusElement);
        }
    }, _('Checking...')) as HTMLButtonElement;
    updateButton.disabled = true;
    const loadStatus = () => Backend.coreUpdateStatus(core).then(({ id }) => {
        if (id) updateCore(core, label, currentVersionElement, updateButton, statusElement, id);
        else { updateButton.disabled = false; updateButton.textContent = _('Update'); }
    }).catch(error => {
        statusElement.textContent = _('Failed to check update status: %s').format(error.message);
        updateButton.disabled = false;
        updateButton.textContent = _('Update');
    });

    const element = E('div', { 'class': 'cbi-value', 'data-core': core }, [
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
            updateButton, statusElement
        ])
    ]);
    return { element, loadVersions: () => {
        loadStatus();
        loadCoreVersion(currentVersionElement, core);
        loadLatestCoreVersion(latestVersionElement, core);
    } };
}

const RuntimePanelUtils = {
    createCoreVersionPanel: function () {
        const rows = HijpassValues.DUAL_CORES.map(core => createCoreRow(core.value, core.label));
        const panel = E('div', { 'class': 'cbi-section' }, [
            E('div', { 'class': 'cbi-section-descr' },
                _('View installed core versions and update runtime components.')),
            E('div', { 'class': 'cbi-section-node' }, rows.map(row => row.element))
        ]) as HTMLElement;
        // 等 LuCI 挂载并初始化页签，兼容恢复上次选中的“运行时”页签。
        window.requestAnimationFrame(() => {
            if (!panel.isConnected) return;
            const pane = panel.closest('[data-tab="runtime"]');
            if (!pane) return;
            const load = () => rows.forEach(row => row.loadVersions());
            if (pane.getAttribute('data-tab-active') === 'true') load();
            else pane.addEventListener('cbi-tab-active', load, { once: true });
        });
        return panel;
    }
};

export { RuntimePanelUtils };
