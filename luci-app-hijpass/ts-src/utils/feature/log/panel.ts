import fs from "fs";
import uci from "uci";
import { LuciFlied } from "../../../enum/hijpass";

function createLogFileOptions() {
    let options = [];

    let hijpassLog = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.CONF_NAME, 'log_path');
    options.push(E('option', {'value': hijpassLog}, _('Main Log')));

    let shuntLog = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE, 'log_path');
    if (shuntLog) {
        options.push(E('option', {'value': shuntLog}, _('Shunt Log')));
    }

    uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, (proxySection) => {
        let proxyName = proxySection['.name'];
        let displayName = proxySection.name || proxyName;
        let log_path = proxySection.log_path;

        if (log_path) {
            options.push(E('option', {'value': log_path}, _('Proxy Log') + ' - ' + displayName));
        }
    });

    uci.sections(LuciFlied.SERVER_CONF_NAME, LuciFlied.SERVER_NODE_TYPE, (serverSection) => {
        let proxyName = serverSection['.name'];
        let displayName = serverSection.name || proxyName;
        let log_path = serverSection.log_path;

        if (log_path) {
            options.push(E('option', {'value': log_path}, _('Server Log') + ' - ' + displayName));
        }
    });

    return options;
}

function loadLogs(
    logFileSelect: HTMLSelectElement,
    levelFilterSelect: HTMLSelectElement,
    linesCountSelect: HTMLSelectElement,
    statusElement: HTMLElement,
    logContentElement: HTMLElement
) {
    let logFile = logFileSelect.value;
    let levelFilter = levelFilterSelect.value;
    let linesCount = linesCountSelect.value;

    updateLogStatus(statusElement, _('Loading Logs'));

    fs.exec('/usr/bin/tail', ['-n', linesCount, logFile]).then(function (result) {
        let logContent = result.stdout || '';

        if (levelFilter) {
            let upperFilter = levelFilter.toUpperCase();
            let filteredLines = logContent.split('\n').filter(function (line) {
                let upperLine = line.toUpperCase();
                if (upperFilter === 'WARN') {
                    return upperLine.includes('WARN') || upperLine.includes('WARNING');
                }

                return upperLine.includes(upperFilter);
            });
            logContent = filteredLines.join('\n');
        }

        logContent = highlightLogContent(logContent);

        logContentElement.innerHTML = logContent;
        logContentElement.scrollTop = logContentElement.scrollHeight;

        updateLogStatus(statusElement, _('Log Updated') + ' - ' + new Date().toLocaleTimeString());
    }).catch(function (error) {
        updateLogStatus(statusElement, _('Failed to Load Log') + error.message);
        logContentElement.textContent = _('Failed to Load Log File') + logFile;
    });
}

function highlightLogContent(content) {
    content = content.replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');

    content = convertAnsiToHtml(content);

    content = content.replace(/\s+\[?(ERROR|WARN|WARNING|INFO|DEBUG)\]?\s+/gmi, function (match, level) {
        if (match.includes('<span')) return match;
        let color = getLogLevelColor(level);
        return '<span style="color: ' + color + '; font-weight: bold;">' + match + '</span>';
    });

    return content;
}

function getLogLevelColor(level) {
    switch (level.toUpperCase()) {
        case 'ERROR':
            return '#ff6b6b';
        case 'WARN':
        case 'WARNING':
            return '#ffa500';
        case 'INFO':
            return '#4ecdc4';
        case 'DEBUG':
            return '#95a5a6';
        default:
            return '#ffffff';
    }
}

function convertAnsiToHtml(text) {
    const ansiColorMap = {
        '30': '#2e3436',
        '31': '#cc0000',
        '32': '#4e9a06',
        '33': '#c4a000',
        '34': '#3465a4',
        '35': '#75507b',
        '36': '#06989a',
        '37': '#d3d7cf',
        '90': '#555753',
        '91': '#ef2929',
        '92': '#8ae234',
        '93': '#fce94f',
        '94': '#729fcf',
        '95': '#ad7fa8',
        '96': '#34e2e2',
        '97': '#eeeeec'
    };

    const ansiBgColorMap = {
        '40': '#2e3436',
        '41': '#cc0000',
        '42': '#4e9a06',
        '43': '#c4a000',
        '44': '#3465a4',
        '45': '#75507b',
        '46': '#06989a',
        '47': '#d3d7cf',
        '100': '#555753',
        '101': '#ef2929',
        '102': '#8ae234',
        '103': '#fce94f',
        '104': '#729fcf',
        '105': '#ad7fa8',
        '106': '#34e2e2',
        '107': '#eeeeec'
    };

    let result = text;
    let openTags = [];

    result = result.replace(/\x1b\[([0-9;]*)m/g, function (match, codes) {
        if (!codes) codes = '0';

        let codeArray = codes.split(';');
        let html = '';

        for (let code of codeArray) {
            code = code.trim();

            if (code === '0' || code === '') {
                while (openTags.length > 0) {
                    html += '</span>';
                    openTags.pop();
                }
            } else if (code === '1') {
                html += '<span style="font-weight: bold;">';
                openTags.push('bold');
            } else if (code === '4') {
                html += '<span style="text-decoration: underline;">';
                openTags.push('underline');
            } else if (ansiColorMap[code]) {
                html += '<span style="color: ' + ansiColorMap[code] + ';">';
                openTags.push('color');
            } else if (ansiBgColorMap[code]) {
                html += '<span style="background-color: ' + ansiBgColorMap[code] + ';">';
                openTags.push('bgcolor');
            }
        }

        return html;
    });

    while (openTags.length > 0) {
        result += '</span>';
        openTags.pop();
    }

    return result;
}

function downloadLogs(logFileSelect: HTMLSelectElement, statusElement: HTMLElement) {
    let logFile = logFileSelect.value;

    updateLogStatus(statusElement, _('Preparing Download'));

    fs.read(logFile).then(function (content) {
        let blob = new Blob([content], {type: 'text/plain'});
        let url = window.URL.createObjectURL(blob);
        let a = document.createElement('a');
        a.href = url;
        a.download = logFile.split('/').pop() + '_' + new Date().toISOString().slice(0, 19).replace(/:/g, '-') + '.log';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);

        updateLogStatus(statusElement, _('Log Downloaded'));
    }).catch(function (error) {
        updateLogStatus(statusElement, _('Download Failed') + error.message);
    });
}

function clearLogs(
    logFileSelect: HTMLSelectElement,
    levelFilterSelect: HTMLSelectElement,
    linesCountSelect: HTMLSelectElement,
    statusElement: HTMLElement,
    logContentElement: HTMLElement
) {
    let logFile = logFileSelect.value;

    updateLogStatus(statusElement, _('Clearing Logs'));

    fs.write(logFile, '').then(function () {
        updateLogStatus(statusElement, _('Log Cleared'));
        loadLogs(logFileSelect, levelFilterSelect, linesCountSelect, statusElement, logContentElement);
    }).catch(function (error) {
        updateLogStatus(statusElement, _('Clear Failed') + error.message);
    });
}

function updateLogStatus(statusElement: HTMLElement, message: string) {
    statusElement.textContent = message;
    statusElement.style.color = '#666';
}

type TraceDiagnosticsValues = {
    url: string;
    mode: string;
    clientIp: string;
    method: string;
    timeout: string;
    tcpdump: boolean;
    tcpdumpInterface: string;
    verbose: boolean;
};

function setTraceStatus(statusElement: HTMLElement, message: string, color?: string) {
    statusElement.textContent = message;
    statusElement.style.display = message ? 'block' : 'none';
    statusElement.style.color = color || '#666';
}

function setTraceOutput(outputElement: HTMLElement, content: string) {
    outputElement.innerHTML = highlightLogContent(content);
    outputElement.scrollTop = 0;
}

function buildTraceArgs(values: TraceDiagnosticsValues) {
    const url = values.url.trim();
    const timeout = values.timeout.trim();
    const method = values.method || 'HEAD';
    const args = [];

    if (!/^https?:\/\/[A-Za-z0-9_.:\-/?#%=&+~[\]]+$/.test(url)) {
        throw new Error(_('Please enter a valid HTTP or HTTPS URL'));
    }

    if (!/^[0-9]+$/.test(timeout) || parseInt(timeout, 10) < 1 || parseInt(timeout, 10) > 120) {
        throw new Error(_('Timeout must be an integer between 1 and 120'));
    }

    args.push('-t', timeout);
    args.push('-X', method);

    if (values.mode === 'client') {
        const clientIp = values.clientIp.trim();
        if (!/^[A-Fa-f0-9:.]+$/.test(clientIp)) {
            throw new Error(_('Please enter a valid client IP address'));
        }
        args.push('-c', clientIp);
    }

    if (values.tcpdump) {
        const iface = values.tcpdumpInterface.trim() || 'any';
        args.push('-p');
        if (!/^[A-Za-z0-9_.:@-]+$/.test(iface)) {
            throw new Error(_('Please enter a valid tcpdump interface'));
        }
        args.push('-i', iface);
    }

    if (values.verbose) {
        args.push('-v');
    }

    args.push(url);
    return args;
}

function runTraceDiagnostics(
    values: TraceDiagnosticsValues,
    statusElement: HTMLElement,
    outputElement: HTMLElement,
    runButton: HTMLButtonElement
) {
    let args;

    try {
        args = buildTraceArgs(values);
    } catch (error) {
        setTraceStatus(statusElement, (error as Error).message, '#b00020');
        return;
    }

    outputElement.innerHTML = '';
    runButton.disabled = true;
    setTraceStatus(statusElement, _('Running Trace Diagnostics'));

    fs.exec('/usr/lib/hijpass/trace-url.sh', args).then(function (result) {
        const stdout = result.stdout || '';
        const stderr = result.stderr || '';
        setTraceOutput(outputElement, stdout || stderr || _('No Output'));

        if (result.code === 0) {
            setTraceStatus(statusElement, _('Trace Completed') + ' - ' + new Date().toLocaleTimeString());
        } else {
            setTraceStatus(statusElement, _('Trace Failed') + ' - ' + (stderr || _('Exit Code') + ': ' + result.code), '#b00020');
        }
    }).catch(function (error) {
        setTraceOutput(outputElement, error.message || String(error));
        setTraceStatus(statusElement, _('Trace Failed') + ' - ' + error.message, '#b00020');
    }).finally(function () {
        runButton.disabled = false;
    });
}

function createTraceOutputPanel() {
    const statusElement = E('div', {
        'style': 'display: none; font-size: 12px; color: #666; margin-bottom: 6px;'
    }) as HTMLElement;
    const outputElement = E('pre', {
        'style': 'width: 100%; min-height: 260px; max-height: 520px; box-sizing: border-box; margin: 0; font-family: monospace; font-size: 12px; background: #101010; color: #eee; border: 1px solid #ccc; padding: 10px; overflow: auto; white-space: pre-wrap; line-height: 1.45;'
    }, _('Trace output will be shown here')) as HTMLElement;

    return {
        statusElement,
        outputElement,
        node: E('div', {}, [
            statusElement,
            outputElement
        ]) as HTMLElement
    };
}

const LogPanelUtils = {
    createLogControlPanel: function () {
        const logFileSelect = E('select', {
            'class': 'cbi-input-select',
            'style': 'margin-right: 10px;'
        }, createLogFileOptions()) as HTMLSelectElement;
        const levelFilterSelect = E('select', {
            'class': 'cbi-input-select',
            'style': 'margin-right: 10px;'
        }, [
            E('option', {'value': ''}, _('All')),
            E('option', {'value': 'DEBUG'}, _('Debug')),
            E('option', {'value': 'INFO'}, _('Info')),
            E('option', {'value': 'WARN'}, _('Warning')),
            E('option', {'value': 'ERROR'}, _('Error'))
        ]) as HTMLSelectElement;
        const linesCountSelect = E('select', {
            'class': 'cbi-input-select',
            'style': 'margin-right: 10px;'
        }, [
            E('option', {'value': '50'}, '50'),
            E('option', {'value': '100', 'selected': 'selected'}, '100'),
            E('option', {'value': '200'}, '200'),
            E('option', {'value': '500'}, '500'),
            E('option', {'value': '1000'}, '1000')
        ]) as HTMLSelectElement;
        const statusElement = E('div', {
            'style': 'font-size: 12px; color: #666; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;'
        }) as HTMLElement;
        const logContentElement = E('div', {
            'class': 'log-display',
            'style': 'width: 100%; height: 500px; font-family: monospace; font-size: 12px; background: #101010; color: #eee; border: 1px solid #ccc; padding: 10px; overflow: auto; white-space: pre; line-height: 1.4;'
        }, _('Log Content')) as HTMLElement;
        let panel: HTMLElement;
        let autoRefreshInterval: number | null = null;

        const load = function () {
            loadLogs(logFileSelect, levelFilterSelect, linesCountSelect, statusElement, logContentElement);
        };
        const stopAutoRefresh = function (button: HTMLElement) {
            if (autoRefreshInterval !== null) {
                clearInterval(autoRefreshInterval);
                autoRefreshInterval = null;
            }
            button.textContent = _('Auto Refresh');
            button.className = 'cbi-button cbi-button-neutral';
        };
        const autoRefreshButton = E('button', {
            'class': 'cbi-button cbi-button-neutral',
            'style': 'margin-right: 5px;',
            'type': 'button',
            'click': function (ev: Event) {
                ev.preventDefault();
                if (autoRefreshInterval === null) {
                    autoRefreshButton.textContent = _('Stop Auto Refresh');
                    autoRefreshButton.className = 'cbi-button cbi-button-negative';
                    autoRefreshInterval = window.setInterval(function () {
                        if (!panel.isConnected) {
                            stopAutoRefresh(autoRefreshButton);
                            return;
                        }
                        load();
                    }, 3000);
                    updateLogStatus(statusElement, _('Auto Refresh Enabled'));
                } else {
                    stopAutoRefresh(autoRefreshButton);
                    updateLogStatus(statusElement, _('Auto Refresh Disabled'));
                }
            }
        }, _('Auto Refresh')) as HTMLElement;

        logFileSelect.addEventListener('change', load);
        levelFilterSelect.addEventListener('change', load);
        linesCountSelect.addEventListener('change', load);

        panel = E('div', {'class': 'cbi-section'}, [
            E('div', {'class': 'cbi-section-node'}, [
                E('div', {'class': 'cbi-value'}, [
                    E('label', {'class': 'cbi-value-title'}, _('Log File')),
                    E('div', {'class': 'cbi-value-field'}, [logFileSelect])
                ]),
                E('div', {'class': 'cbi-value'}, [
                    E('label', {'class': 'cbi-value-title'}, _('Log Level Filter')),
                    E('div', {'class': 'cbi-value-field'}, [levelFilterSelect])
                ]),
                E('div', {'class': 'cbi-value'}, [
                    E('label', {'class': 'cbi-value-title'}, _('Display Lines')),
                    E('div', {'class': 'cbi-value-field'}, [linesCountSelect])
                ]),
                E('div', {'class': 'cbi-value'}, [
                    E('label', {'class': 'cbi-value-title'}, _('Actions')),
                    E('div', {'class': 'cbi-value-field'}, [
                        E('button', {
                            'class': 'cbi-button cbi-button-action',
                            'style': 'margin-right: 5px;',
                            'type': 'button',
                            'click': function (ev: Event) {
                                ev.preventDefault();
                                load();
                            }
                        }, _('Refresh')),
                        autoRefreshButton,
                        E('button', {
                            'class': 'cbi-button cbi-button-positive',
                            'style': 'margin-right: 5px;',
                            'type': 'button',
                            'click': function (ev: Event) {
                                ev.preventDefault();
                                downloadLogs(logFileSelect, statusElement);
                            }
                        }, _('Download')),
                        E('button', {
                            'class': 'cbi-button cbi-button-negative',
                            'type': 'button',
                            'click': function (ev: Event) {
                                ev.preventDefault();
                                if (confirm(_('Clear Log Confirmation'))) {
                                    clearLogs(logFileSelect, levelFilterSelect, linesCountSelect, statusElement, logContentElement);
                                }
                            }
                        }, _('Clear'))
                    ])
                ]),
                E('div', {'class': 'cbi-value'}, [
                    statusElement,
                    logContentElement
                ])
            ])
        ]) as HTMLElement;

        load();
        return panel;
    },

    createTraceOutputPanel: createTraceOutputPanel,
    runTraceDiagnostics: runTraceDiagnostics,
}

export { LogPanelUtils }
