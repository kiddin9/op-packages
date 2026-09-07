import { LuciFlied } from "../../../enum/hijpass";
import uci from "uci";

const ValidationUtils = {
    createTagValidator: function (confName: string, sectionType: string, fieldName: string) {
        return function (section_id: any, value: any) {
            let formatResult = ValidationUtils.validateNameFormat(section_id, value);
            if (formatResult !== true) {
                return formatResult;
            }

            let duplicate = false;
            uci.sections(confName, sectionType, function (section) {
                if (section['.name'] !== section_id && section[fieldName] === value) {
                    duplicate = true;
                }
            });

            if (duplicate) {
                return _('%s already exists, use another %s').format(fieldName === 'tag' ? _('Tag') : _('Name'), fieldName === 'tag' ? _('Tag') : _('Name'));
            }

            return true;
        };
    },

    getUsedPorts: function (): number[] {
        let ports: number[] = [];
        uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, (section) => {
            if (section.listen_port) ports.push(Number(section.listen_port));
            if (section.socks_port) ports.push(Number(section.socks_port));
        });
        uci.sections(LuciFlied.SERVER_CONF_NAME, LuciFlied.SERVER_NODE_TYPE, (section) => {
            if (section.listen_port) ports.push(Number(section.listen_port));
        });
        const shunt = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE);
        if (shunt?.shunt_listen_port) ports.push(Number(shunt.shunt_listen_port));
        if (shunt?.dns_listen_port) ports.push(Number(shunt.dns_listen_port));
        const dns = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE);
        if (dns?.cdg_port) ports.push(Number(dns.cdg_port));
        return ports;
    },

    getUsedPortsExcluding: function (excludeSectionId: string): number[] {
        let ports: number[] = [];
        uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE, (section) => {
            if (section['.name'] === excludeSectionId) return;
            if (section.listen_port) ports.push(Number(section.listen_port));
            if (section.socks_port) ports.push(Number(section.socks_port));
        });
        uci.sections(LuciFlied.SERVER_CONF_NAME, LuciFlied.SERVER_NODE_TYPE, (section) => {
            if (section.listen_port) ports.push(Number(section.listen_port));
        });
        const shunt = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE);
        if (shunt?.shunt_listen_port) ports.push(Number(shunt.shunt_listen_port));
        if (shunt?.dns_listen_port) ports.push(Number(shunt.dns_listen_port));
        const dns = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE);
        if (dns?.cdg_port) ports.push(Number(dns.cdg_port));
        return ports;
    },

    findAvailablePort: function (startPort: number, extraExclude: number[] = []): number {
        const used = [...ValidationUtils.getUsedPorts(), ...extraExclude];
        let port = startPort;
        for (let i = 0; i < 1000; i++, port++) {
            if (!used.includes(port)) return port;
        }
        return startPort;
    },

    validatePortConflict: function (sectionId: string, value: string) {
        let shuntSection = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.SHUNT_SECTION_TYPE)
        if (shuntSection && shuntSection[".name"] !== sectionId && (shuntSection.dns_listen_port === value
            || shuntSection.shunt_listen_port === value)) {
            return _('Port %s is used by shunt configuration').format(value);
        }

        let dnsSection = uci.get_first(LuciFlied.CONF_NAME, LuciFlied.DNS_SECTION_TYPE)
        if (dnsSection && dnsSection[".name"] !== sectionId && dnsSection.cdg_port === value) {
            return _('Port %s is used by DNS configuration').format(value);
        }

        let proxySections = uci.sections(LuciFlied.CONF_NAME, LuciFlied.PROXY_NODE_TYPE);
        for (let i = 0; i < proxySections.length; i++) {
            let section = proxySections[i]
            if (section[".name"] === sectionId) {
                continue
            }
            if (section.listen_port === value || section.socks_port === value) {
                return _('Port %s is used by proxy node "%s"').format(value, section.name);
            }
        }

        let serverSections = uci.sections(LuciFlied.SERVER_CONF_NAME, LuciFlied.SERVER_NODE_TYPE);
        for (let i = 0; i < serverSections.length; i++) {
            let section = serverSections[i]
            if (section[".name"] === sectionId) {
                continue
            }

            if (section.listen_port === value) {
                return _('Port %s is used by server node "%s"').format(value, section.name);
            }
        }
        return true;
    },

    validateNameFormat: function (sectionId: any, value: any) {
        if (!value || value === '') {
            return _('Node name cannot be empty');
        }

        if (!/^[a-zA-Z0-9_-]+$/.test(value)) {
            return _('Node name can only contain letters, numbers, underscores, and hyphens');
        }

        return true;
    },
}

export { ValidationUtils }
