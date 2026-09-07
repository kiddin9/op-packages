import uci from "uci";
import { FIREWALL_DNS_FORWARD, type FirewallDnsForward, LuciFlied } from "../../../enum/hijpass";

type DnsForwardTarget = {
    available: boolean;
    port: string;
}

function isPort(value: string) {
    const port = Number(value);
    return Number.isInteger(port) && port > 0 && port <= 65535;
}

function getPreRoutingTarget(): DnsForwardTarget {
    const dns = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE);
    const port = dns?.cdg_port || '';
    return {
        available: dns?.dns_service === 'chinadns-ng' && isPort(port),
        port,
    };
}

function getRoutingTarget(): DnsForwardTarget {
    const shunt = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE);
    const port = shunt?.dns_listen_port || '';
    return {
        available: shunt?.enabled !== '0' && isPort(port),
        port,
    };
}

function getTargetLabel(name: string, target: DnsForwardTarget) {
    let label = name;
    if (target.port) {
        label += ': ' + target.port;
    }
    if (!target.available) {
        label += ' - ' + _('Not available');
    }
    return label;
}

const FirewallDnsForwardUtils = {
    getSource: function (): FirewallDnsForward | string {
        return uci.get_first(LuciFlied.CONF_NAME, LuciFlied.FIREWALL_SECTION_TYPE, 'dns_forward')
            || FIREWALL_DNS_FORWARD.NONE;
    },

    getPreRoutingTarget,

    getRoutingTarget,

    getTargetLabel,

    validateSource: function (source: FirewallDnsForward | string): true | string {
        if (!source || source === FIREWALL_DNS_FORWARD.NONE) {
            return true;
        }
        if (source === FIREWALL_DNS_FORWARD.PRE_ROUTING) {
            return getPreRoutingTarget().available
                ? true
                : _('Independent DNS is unavailable or has no valid listen port');
        }
        if (source === FIREWALL_DNS_FORWARD.ROUTING) {
            return getRoutingTarget().available
                ? true
                : _('Core DNS is disabled or has no valid listen port');
        }
        return _('Unknown DNS forwarding source: %s').format(source);
    },
}

export { FirewallDnsForwardUtils }
