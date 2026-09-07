import { LuciFlied } from "../../../enum/hijpass";
import form from "form";
import poll from "poll";
import rpc from "rpc";
import uci from "uci";

const callServiceList = rpc.declare({
    object: 'service',
    method: 'list',
    params: ['name'],
    expect: { '': {} }
})

const statusRefreshers: Record<string, () => Promise<void>> = {};

function getStatusKey(type?: string) {
    return type || 'all';
}

function getStatusElementId(type?: string) {
    return 'service_status_' + getStatusKey(type);
}

const ServiceUtils = {
    getServiceInstances: async function (confName: string): Promise<any> {
        const res = await callServiceList(confName);
        return res?.[confName]?.['instances'] ?? {};
    },

    getServiceInfo: async function () {
        const hijpass = await callServiceList(LuciFlied.CONF_NAME);
        const hijserver = await callServiceList(LuciFlied.SERVER_CONF_NAME);
        let serverInstances = hijserver?.[LuciFlied.SERVER_CONF_NAME]?.['instances'] ?? {};
        let instances = hijpass?.[LuciFlied.CONF_NAME]?.['instances'] ?? {};
        return {
            proxyInfos: ServiceUtils.getInstanceName(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE).map(
                (name) => {
                    return instances?.[name] ?? undefined;
                }
            ).filter(instance => instance),
            shuntInfo: instances?.[ServiceUtils.getInstanceName(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE)[0]] ?? undefined,
            dnsInfo: instances?.[ServiceUtils.getInstanceName(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE)[0]] ?? undefined,
            serverInfos: ServiceUtils.getInstanceName(LuciFlied.SERVER_CONF_NAME, LuciFlied.SERVER_NODE_TYPE).map(
                (name) => {
                    return serverInstances?.[name] ?? undefined;
                }
            ).filter(instance => instance),
        }
    },

    getInstanceName: function (confName: string, sectionType: string): string[] {
        return uci.sections(confName, sectionType).map((section) => {
            let cid = section['.name'];
            let name = section['name'] ?? section['tag'] ?? section['dns_service']
            if (!name) {
                name = sectionType
            }
            return cid + '-' + name;
        })
    },

    renderServiceStatusText: function (res: any, type?: string) {
        let renderHTML = "";
        let spanTemp = '<em><span style="color:%s"><strong>%s %s</strong></span></em>';
        let isProxyRunning = (res?.proxyInfos ?? [])
            .filter(instance => instance?.running)
            .length > 0
        let isServerRunning = (res?.serverInfos ?? [])
            .filter(instance => instance?.running)
            .length > 0
        let isShuntRunning = res?.shuntInfo?.running ?? false
        let isDnsRunning = res?.dnsInfo?.running ?? false

        let getColorSpan = function (title: string, isRunning: any) {
            if (isRunning) {
                return spanTemp.format('green', title, _("Running"));
            } else {
                return spanTemp.format('red', title, _("Not Running"));
            }
        }

        switch (type) {
            case 'dns':
                renderHTML += getColorSpan(_("Independent DNS"), isDnsRunning)
                break;
            case 'shunt':
                renderHTML += getColorSpan(_("Proxy Routing"), isShuntRunning)
                break;
            case 'server':
                renderHTML += getColorSpan(_("Local Server"), isServerRunning)
                break;
            case 'proxy':
                renderHTML += getColorSpan(_("Proxy Node"), isProxyRunning)
                break;
            default:
                renderHTML += getColorSpan(_("Proxy Node"), isProxyRunning)
                renderHTML += getColorSpan(_("Proxy Routing"), isShuntRunning)
                renderHTML += getColorSpan(_("Independent DNS"), isDnsRunning)
                renderHTML += getColorSpan(_("Local Server"), isServerRunning)
        }

        return renderHTML;
    },

    refreshServiceStatus: function (type?: string) {
        const key = getStatusKey(type);
        if (!statusRefreshers[key]) {
            const elementId = getStatusElementId(type);
            statusRefreshers[key] = async function () {
                const res = await L.resolveDefault(ServiceUtils.getServiceInfo());
                let view = document.getElementById(elementId);
                if (view) view.innerHTML = ServiceUtils.renderServiceStatusText(res, type);
            }
        }
        return statusRefreshers[key];
    },

    renderServiceStatus: function (type?: string) {
        return function () {
            const refresh = ServiceUtils.refreshServiceStatus(type);
            poll.add(refresh);
            window.setTimeout(refresh, 0);

            // Only actual form maps may use cbi-map: LuCI saves every matching node.
            return E('div', { class: 'hijpass-service-status' },
                E('fieldset', { class: 'cbi-section' }, [
                    E('p', { id: getStatusElementId(type), style: 'display: flex; gap: 1rem;' },
                        _('Fetching Status...'))
                ])
            );
        }
    },

    createStatusSection: function (m: LuCI.form.Map, type?: string) {
        let s = m.section(form.TypedSection);
        s.anonymous = true;
        s.render = ServiceUtils.renderServiceStatus(type);
        return s;
    },
}

export { ServiceUtils }
