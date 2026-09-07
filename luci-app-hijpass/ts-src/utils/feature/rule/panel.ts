import fs from "fs";

type RuleUpdateStatus = 'success' | 'error' | 'neutral';
type RuleUpdateResult = { success?: boolean };

function updateRuleFile(statusElement: HTMLElement, updateButton: HTMLButtonElement) {
    updateButton.disabled = true;
    updateUpdateStatus(statusElement, _('Updating Rule Files'), 'neutral');
    fs.exec_direct('/usr/lib/hijpass/rules.sh', ['update'], 'json')
        .then(function (result: RuleUpdateResult) {
            if (result?.success) {
                updateUpdateStatus(statusElement, _('Rule Files Updated'), 'success');
            } else {
                updateUpdateStatus(statusElement, _('Rule File Update Failed: %s').format(_('Update failed')), 'error');
            }
        })
        .catch(function (error) {
            updateUpdateStatus(statusElement, _('Error occurred while updating: %s').format(error.message), 'error');
        })
        .finally(function () {
            updateButton.disabled = false;
        });
}

function updateUpdateStatus(statusElement: HTMLElement, message: string, status: RuleUpdateStatus) {
    statusElement.textContent = message;
    statusElement.style.color = status === 'success' ? '#4caf50' :
        status === 'error' ? '#f44336' : '#666';
}

function performQuery(
    keywordInput: HTMLInputElement,
    queryTypeSelect: HTMLSelectElement,
    statusElement: HTMLElement,
    outputElement: HTMLTextAreaElement
) {
    let keyword = keywordInput.value.trim();
    let queryType = queryTypeSelect.value;

    if (!keyword) {
        statusElement.textContent = _('Enter Query Keyword');
        statusElement.style.color = '#f44336';
        return;
    }

    statusElement.textContent = _('Querying');
    statusElement.style.color = '#666';

    switch (queryType) {
        case 'domain':
            queryDomain(keyword, outputElement, statusElement);
            break;
        case 'geosite':
            queryGeoTag(keyword, 'geosite', outputElement, statusElement);
            break;
        case 'shunt':
            queryShunt(keyword, outputElement, statusElement);
            break;
        default:
            statusElement.textContent = _('Unknown Query Type');
            statusElement.style.color = '#f44336';
    }
}

function queryDomain(keyword: string, outputElement: HTMLTextAreaElement, statusElement: HTMLElement) {
    clearQuery(outputElement)
    fs.exec('/usr/bin/lua', ['/usr/lib/hijpass/luci-utils.lua', 'iptype', keyword])
        .then(function (result) {
            const geoType = result.code === 0 ? 'geoip' : 'geosite';
            return fs.exec('/usr/lib/hijpass/geoview.sh', ['-l', geoType, keyword])
                .then(setOutput(outputElement, statusElement, '# ' + geoType + '\n'));
        })
        .catch(setError(statusElement))
    fs.exec('/usr/lib/hijpass/rules.sh', ['query', keyword])
        .then(setOutput(outputElement, statusElement, _('# Local Rule Files\n')))
        .catch(setError(statusElement));
}

function queryShunt(keyword: string, outputElement: HTMLTextAreaElement, statusElement: HTMLElement) {
    clearQuery(outputElement)
    fs.exec('/usr/lib/hijpass/route-match.sh', [keyword])
        .then(setOutput(outputElement, statusElement, _('# Shunt Rules\n')))
        .catch(setError(statusElement))
}

function queryGeoTag(keyword: string, geoType: string, outputElement: HTMLTextAreaElement, statusElement: HTMLElement) {
    clearQuery(outputElement)
    fs.exec('/usr/lib/hijpass/geoview.sh', ['-e', geoType, keyword])
        .then(function (result) {
            if (result.code !== 0) {
                throw new Error(result.stderr || _('Query Failed'));
            }

            const output = result.stdout || '';
            if (output.trim()) {
                if (outputElement.value) {
                    outputElement.value += '\n';
                }
                outputElement.value += '# ' + geoType + '\n';
                outputElement.value += output;
                statusElement.textContent = _('Query Complete');
                statusElement.style.color = '#4caf50';
            } else {
                statusElement.textContent = _('No Matching Results');
                statusElement.style.color = '#666';
            }
        })
        .catch(setError(statusElement));
}

function clearQuery(outputElement: HTMLTextAreaElement) {
    outputElement.value = '';
}

function setOutput(outputElement: HTMLTextAreaElement, statusElement: HTMLElement, comment: string) {
    return function (result: any) {
        if (result.code === 0) {
            if (result.stdout) {
                if (outputElement.value) {
                    outputElement.value += '\n';
                }
                outputElement.value += comment;
                outputElement.value += result.stdout;
            }
            statusElement.textContent = _('Query Complete');
            statusElement.style.color = '#4caf50';
        } else {
            throw new Error(result.stderr || _('Query Failed'));
        }
    }
}

function setError(statusElement: HTMLElement) {
    return function (error) {
        console.log(error)
        statusElement.textContent = _('Query Failed');
        statusElement.style.color = '#f44336';
    }
}

const RulePanelUtils = {
    createUpdateButtons: function () {
        const statusElement = E('span', {
            'style': 'margin-left: 10px; font-size: 12px; color: #666;'
        }) as HTMLElement;
        const updateButton = E('button', {
            'class': 'cbi-button cbi-button-neutral',
            'style': 'margin-right: 10px;',
            'type': 'button',
            'click': function (ev: Event) {
                ev.preventDefault();
                updateRuleFile(statusElement, updateButton);
            }
        }, _('Update Rule Files')) as HTMLButtonElement;

        return E('div', {'class': 'cbi-section'}, [
            E('div', {'class': 'cbi-section-node'}, [
                E('div', {'class': 'cbi-value'}, [
                    E('label', {'class': 'cbi-value-title'}, _('Rule Update')),
                    E('div', {'class': 'cbi-value-field'}, [
                        updateButton,
                        statusElement
                    ])
                ])
            ])
        ]);
    },

    createQueryPanel: function () {
        const queryGuidance = {
            domain: {
                placeholder: _('Enter a domain or IP address'),
                description: [
                    _('Domain: Enter a domain (for example, www.example.com) to query GeoSite tags and local domain rule files.'),
                    _('IP address: Enter an IP address (for example, 8.8.8.8) to query GeoIP tags and local IP rule files.')
                ]
            },
            geosite: {
                placeholder: _('Enter a GeoSite tag'),
                description: [
                    _('Enter a GeoSite tag (for example, cn or google) to list the domain rules included in that tag.')
                ]
            },
            shunt: {
                placeholder: _('Enter a domain or IP address'),
                description: [
                    _('Enter a domain or IP address to show the first matching enabled shunt rule.'),
                    _('Protocol and port conditions are not evaluated.')
                ]
            }
        };
        const queryTypeSelect = E('select', {
            'id': 'hijpass-rule-query-type',
            'class': 'cbi-input-select',
            'style': 'width: 200px; margin-right: 10px;',
            'aria-describedby': 'hijpass-rule-query-type-description'
        }, [
            E('option', {'value': 'domain'}, _('Domain Query')),
            E('option', {'value': 'geosite'}, _('GeoSite')),
            E('option', {'value': 'shunt'}, _('Shunt Query')),
        ]) as HTMLSelectElement;
        const queryTypeDescription = E('div', {
            'id': 'hijpass-rule-query-type-description',
            'class': 'cbi-section-descr',
            'style': 'margin-top: 6px;',
            'aria-live': 'polite'
        }) as HTMLElement;
        const keywordInput = E('input', {
            'id': 'hijpass-rule-query-keyword',
            'type': 'text',
            'class': 'cbi-input-text',
            'style': 'margin-right: 10px;',
            'keydown': function (ev: KeyboardEvent) {
                if (ev.key === 'Enter') {
                    ev.preventDefault();
                    performQuery(keywordInput, queryTypeSelect, statusElement, outputElement);
                }
            }
        }) as HTMLInputElement;
        const statusElement = E('span', {
            'style': 'margin-left: 10px; font-size: 12px; color: #666;',
            'role': 'status',
            'aria-live': 'polite'
        }) as HTMLElement;
        const outputElement = E('textarea', {
            'id': 'hijpass-rule-query-results',
            'class': 'cbi-input-textarea',
            'readonly': 'readonly',
            'placeholder': _('Query results will appear here'),
            'style': 'width: 100%; height: 300px;',
            'aria-describedby': 'hijpass-rule-query-results-description'
        }) as HTMLTextAreaElement;
        const updateQueryGuidance = function () {
            const guidance = queryGuidance[queryTypeSelect.value] || queryGuidance.domain;
            keywordInput.placeholder = guidance.placeholder;
            queryTypeDescription.innerHTML = '';
            guidance.description.forEach(function (line) {
                queryTypeDescription.appendChild(E('div', {}, line));
            });
        };

        queryTypeSelect.addEventListener('change', updateQueryGuidance);
        updateQueryGuidance();

        return E('div', {'class': 'cbi-section'}, [
            E('div', {'class': 'cbi-section-descr'},
                _('Query saved rule data without changing configuration. Unsaved form changes are not included.')),
            E('div', {'class': 'cbi-section-node'}, [
                E('div', {'class': 'cbi-value', 'style': 'margin-bottom: 20px;'}, [
                    E('label', {'class': 'cbi-value-title', 'for': 'hijpass-rule-query-type'}, _('Query Type')),
                    E('div', {'class': 'cbi-value-field'}, [queryTypeSelect, queryTypeDescription])
                ]),
                E('div', {'class': 'cbi-value', 'style': 'margin-bottom: 20px;'}, [
                    E('label', {'class': 'cbi-value-title', 'for': 'hijpass-rule-query-keyword'}, _('Query Keyword')),
                    E('div', {'class': 'cbi-value-field'}, [
                        keywordInput,
                        E('button', {
                            'class': 'cbi-button cbi-button-action',
                            'style': 'margin-right: 10px;',
                            'type': 'button',
                            'click': function (ev: Event) {
                                ev.preventDefault();
                                performQuery(keywordInput, queryTypeSelect, statusElement, outputElement);
                            }
                        }, _('Query')),
                        statusElement
                    ])
                ]),
                E('div', {'class': 'cbi-value'}, [
                    E('label', {'class': 'cbi-value-title', 'for': 'hijpass-rule-query-results'}, _('Query Results')),
                    E('div', {'class': 'cbi-value-field'}, [
                        outputElement,
                        E('div', {
                            'id': 'hijpass-rule-query-results-description',
                            'class': 'cbi-section-descr',
                            'style': 'margin-top: 6px;'
                        },
                            _('An empty result means no matching entry was found.'))
                    ])
                ])
            ])
        ]);
    },
}

export { RulePanelUtils }
