import fs from "fs";

type TestSite = {
    id: string,
    name: string,
    url: string,
    svg: string
}

type ActionStatus = 'success' | 'error' | 'neutral';

const TEST_SITES: TestSite[] = [
    {
        id: 'baidu',
        name: 'Baidu',
        url: 'https://www.baidu.com',
        svg: '<svg height="32" style="flex:none;line-height:1" viewBox="0 0 24 24" width="32" xmlns="http://www.w3.org/2000/svg"><title>Baidu</title><path d="M8.859 11.735c1.017-1.71 4.059-3.083 6.202.286 1.579 2.284 4.284 4.397 4.284 4.397s2.027 1.601.73 4.684c-1.24 2.956-5.64 1.607-6.005 1.49l-.024-.009s-1.746-.568-3.776-.112c-2.026.458-3.773.286-3.773.286l-.045-.001c-.328-.01-2.38-.187-3.001-2.968-.675-3.028 2.365-4.687 2.592-4.968.226-.288 1.802-1.37 2.816-3.085zm.986 1.738v2.032h-1.64s-1.64.138-2.213 2.014c-.2 1.252.177 1.99.242 2.148.067.157.596 1.073 1.927 1.342h3.078v-7.514l-1.394-.022zm3.588 2.191l-1.44.024v3.956s.064.985 1.44 1.344h3.541v-5.3h-1.528v3.979h-1.46s-.466-.068-.553-.447v-3.556zM9.82 16.715v3.06H8.58s-.863-.045-1.126-1.049c-.136-.445.02-.959.088-1.16.063-.203.353-.671.951-.85H9.82zm9.525-9.036c2.086 0 2.646 2.06 2.646 2.742 0 .688.284 3.597-2.309 3.655-2.595.057-2.704-1.77-2.704-3.08 0-1.374.277-3.317 2.367-3.317zM4.24 6.08c1.523-.135 2.645 1.55 2.762 2.513.07.625.393 3.486-1.975 4-2.364.515-3.244-2.249-2.984-3.544 0 0 .28-2.797 2.197-2.969zm8.847-1.483c.14-1.31 1.69-3.316 2.931-3.028 1.236.285 2.367 1.944 2.137 3.37-.224 1.428-1.345 3.313-3.095 3.082-1.748-.226-2.143-1.823-1.973-3.424zM9.425 1c1.307 0 2.364 1.519 2.364 3.398 0 1.879-1.057 3.4-2.364 3.4s-2.367-1.521-2.367-3.4C7.058 2.518 8.118 1 9.425 1z" fill="#2932E1" fill-rule="nonzero"></path></svg>'
    },
    {
        id: 'google',
        name: 'Google',
        url: 'https://www.google.com/ncr',
        svg: '<svg height="32" width="32" style="flex:none;line-height:1" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><title>Google</title><path d="M23 12.245c0-.905-.075-1.565-.236-2.25h-10.54v4.083h6.186c-.124 1.014-.797 2.542-2.294 3.569l-.021.136 3.332 2.53.23.022C21.779 18.417 23 15.593 23 12.245z" fill="#4285F4"></path><path d="M12.225 23c3.03 0 5.574-.978 7.433-2.665l-3.542-2.688c-.948.648-2.22 1.1-3.891 1.1a6.745 6.745 0 01-6.386-4.572l-.132.011-3.465 2.628-.045.124C4.043 20.531 7.835 23 12.225 23z" fill="#34A853"></path><path d="M5.84 14.175A6.65 6.65 0 015.463 12c0-.758.138-1.491.361-2.175l-.006-.147-3.508-2.67-.115.054A10.831 10.831 0 001 12c0 1.772.436 3.447 1.197 4.938l3.642-2.763z" fill="#FBBC05"></path><path d="M12.225 5.253c2.108 0 3.529.892 4.34 1.638l3.167-3.031C17.787 2.088 15.255 1 12.225 1 7.834 1 4.043 3.469 2.197 7.062l3.63 2.763a6.77 6.77 0 016.398-4.572z" fill="#EB4335"></path></svg>'
    },
    {
        id: 'github',
        name: 'GitHub',
        url: 'https://github.com',
        svg: '<svg fill="currentColor" fill-rule="evenodd" height="32" width="32" style="flex:none;line-height:1" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><title>Github</title><path d="M12 0c6.63 0 12 5.276 12 11.79-.001 5.067-3.29 9.567-8.175 11.187-.6.118-.825-.25-.825-.56 0-.398.015-1.665.015-3.242 0-1.105-.375-1.813-.81-2.181 2.67-.295 5.475-1.297 5.475-5.822 0-1.297-.465-2.344-1.23-3.169.12-.295.54-1.503-.12-3.125 0 0-1.005-.324-3.3 1.209a11.32 11.32 0 00-3-.398c-1.02 0-2.04.133-3 .398-2.295-1.518-3.3-1.209-3.3-1.209-.66 1.622-.24 2.83-.12 3.125-.765.825-1.23 1.887-1.23 3.169 0 4.51 2.79 5.527 5.46 5.822-.345.294-.66.81-.765 1.577-.69.31-2.415.81-3.495-.973-.225-.354-.9-1.223-1.845-1.209-1.005.015-.405.56.015.781.51.28 1.095 1.327 1.23 1.666.24.663 1.02 1.93 4.035 1.385 0 .988.015 1.916.015 2.196 0 .31-.225.664-.825.56C3.303 21.374-.003 16.867 0 11.791 0 5.276 5.37 0 12 0z"></path></svg>'
    },
    {
        id: 'bilibili',
        name: 'Bilibili',
        url: 'https://www.bilibili.com',
        svg: '<svg height="32" width="32" style="flex:none;line-height:1" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><title>bilibili</title><path clip-rule="evenodd" d="M4.977 3.561a1.31 1.31 0 111.818-1.884l2.828 2.728c.08.078.149.163.205.254h4.277a1.32 1.32 0 01.205-.254l2.828-2.728a1.31 1.31 0 011.818 1.884L17.82 4.66h.848A5.333 5.333 0 0124 9.992v7.34a5.333 5.333 0 01-5.333 5.334H5.333A5.333 5.333 0 010 17.333V9.992a5.333 5.333 0 015.333-5.333h.781L4.977 3.56zm.356 3.67a2.667 2.667 0 00-2.666 2.667v7.529a2.667 2.667 0 002.666 2.666h13.334a2.667 2.667 0 002.666-2.666v-7.53a2.667 2.667 0 00-2.666-2.666H5.333zm1.334 5.192a1.333 1.333 0 112.666 0v1.192a1.333 1.333 0 11-2.666 0v-1.192zM16 11.09c-.736 0-1.333.597-1.333 1.333v1.192a1.333 1.333 0 102.666 0v-1.192c0-.736-.597-1.333-1.333-1.333z" fill="#1b7be1" fill-rule="evenodd"></path></svg>'
    }
];

function restartService(statusElement: HTMLElement) {
    updateActionStatus(statusElement, _('Restarting Service'), 'neutral');

    fs.exec('/etc/init.d/hijpass', ['restart']).then(function (result) {
        if (result.code === 0) {
            updateActionStatus(statusElement, _('Service Restarted'), 'success');
            setTimeout(function () {
                location.reload();
            }, 2000);
        } else {
            updateActionStatus(statusElement, _('Service Restart Failed') + (result.stderr || result.stdout), 'error');
        }
    }).catch(function (error) {
        updateActionStatus(statusElement, _('Service Restart Failed') + error.message, 'error');
    });
}

function reloadFirewall(statusElement: HTMLElement) {
    updateActionStatus(statusElement, _('Refreshing Firewall'), 'neutral');

    fs.exec('/usr/lib/hijpass/nft.sh', ['reset']).then(function (result) {
        if (result.code === 0) {
            updateActionStatus(statusElement, _('Firewall Refreshed'), 'success');
        } else {
            updateActionStatus(statusElement, _('Firewall Refresh Failed') + (result.stderr || result.stdout), 'error');
        }
    }).catch(function (error) {
        updateActionStatus(statusElement, _('Firewall Refresh Failed') + error.message, 'error');
    });
}

function updateActionStatus(statusElement: HTMLElement, message: string, status: ActionStatus) {
    statusElement.textContent = message;
    statusElement.style.color = status === 'success' ? '#4caf50' :
        status === 'error' ? '#f44336' : '#666';
}

function createTestButton(info: TestSite) {
    const resultElement = E('div', {
        'style': 'font-size: 13px; color: #f44336;'
    }, _('Click to Test')) as HTMLElement;
    let buttonElement: HTMLElement;

    buttonElement = E('div', {
        'class': 'connectivity-btn cbi-section',
        'style': 'width: 100%; height: 100px; display: flex; ' +
            'flex-direction: column; align-items: center; justify-content: center; ' +
            'font-size: 15px; border-radius: 8px; padding: 0; ' +
            'box-shadow: 0 0 2rem 0 rgba(136, 152, 170, .15); border:1px solid rgba(0, 0, 0, .05); ' +
            'cursor: pointer;',
        'click': function () {
            testConnectivity(info.url, buttonElement, resultElement);
        }
    }, [
        E('div', {
            'style': 'display: flex; align-items: center; justify-content: center;'
        }, [
            E('span', {
                'style': 'width: 40px; height: 40px; display: flex; align-items: center; justify-content: center;'
            }, [E('raw', {}, info.svg)])
        ]),
        E('div', {
            'style': 'font-weight: bold; font-size: 16px; margin-bottom: 2px;'
        }, _(info.name)),
        resultElement
    ]) as HTMLElement;

    return E('div', {
        'class': 'connectivity-test-button',
        'style': 'flex: 1; min-width: 120px;'
    }, [buttonElement])
}

function testConnectivity(url: string, buttonElement: HTMLElement, resultElement: HTMLElement) {
    if (buttonElement.dataset.loading === '1') {
        return;
    }

    resultElement.textContent = _('Testing');
    resultElement.style.color = '#666';
    buttonElement.dataset.loading = '1';
    buttonElement.style.opacity = '0.7';

    fs.exec_direct("/usr/lib/hijpass/connect.sh", [url, '5'], 'json')
        .then(r => {
            updateTestResult(buttonElement, resultElement, r.success, r);
        })
        .catch(e => {
            console.error(e)
            updateTestResult(buttonElement, resultElement, false, undefined)
        })
}

function updateTestResult(buttonElement: HTMLElement, resultElement: HTMLElement, success: boolean, response: any) {
    delete buttonElement.dataset.loading;
    buttonElement.style.opacity = '1';

    if (success) {
        if (/^([45])\d{2}$/.test(response.http_code)) {
            resultElement.textContent = _('Connection Abnormal') + response.http_code;
            resultElement.style.color = '#f44336';
        } else {
            resultElement.textContent = response.tls_handshake_time_ms + ' ms'
            resultElement.style.color = '#4caf50';
        }
    } else {
        resultElement.textContent = _('Test Failed');
        resultElement.style.color = '#f44336';
    }
}

const OverviewPanelUtils = {
    createActionButtons: function () {
        const statusElement = E('span', {
            'style': 'margin-left: 10px; font-size: 12px; color: #666;'
        }) as HTMLElement;

        return E('div', {'class': 'cbi-value', 'style': 'margin-bottom: 2rem;'}, [
            E('label', {'class': 'cbi-value-title', 'style': 'visibility: hidden'}, _('Service Control')),
            E('div', {'class': 'cbi-value-field'}, [
                E('button', {
                    'class': 'cbi-button cbi-button-action',
                    'style': 'margin-right: 10px;',
                    'type': 'button',
                    'click': function (ev: Event) {
                        ev.preventDefault();
                        restartService(statusElement);
                    }
                }, _('Restart Service')),
                E('button', {
                    'class': 'cbi-button cbi-button-action',
                    'style': 'margin-right: 10px;',
                    'type': 'button',
                    'click': function (ev: Event) {
                        ev.preventDefault();
                        reloadFirewall(statusElement);
                    }
                }, _('Refresh Firewall')),
                statusElement
            ])
        ])
    },

    createConnectivityTest: function () {
        return E('div', {
            'id': 'custom-connectivity-test',
            'class': 'cbi-map'
        }, [
            E('h2', {}, _('Website Connectivity Test')),
            E('div', {
                'class': 'cbi-section',
                'style': 'display: flex; gap: 18px; padding: 18px; justify-content: center;'
            }, TEST_SITES.map(site => createTestButton(site)))
        ]);
    },
}

export { OverviewPanelUtils }
