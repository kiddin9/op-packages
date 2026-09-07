import fs from "fs";
import form from "form";
import network from "network";
import uci from "uci";

type AclContext = {
    hostHints: any,
    interfaces: AclInterfaceOption[],
}

type AclInterfaceOption = {
    device: string,
    networks: string[],
    zones: string[],
}

function buildMacLabel(hostHints: any, mac: string) {
    let name = hostHints[mac]?.name;
    let ip = hostHints[mac]?.ipaddrs?.[0];
    let label = ((name ?? '') + ' ' + (ip ?? '')).trim();
    return mac + (label ? ' (' + label + ')' : '');
}

function toStringArray(value: any): string[] {
    if (Array.isArray(value)) return value.filter((item: any) => typeof item === 'string' && item);
    return typeof value === 'string' ? value.trim().split(/\s+/).filter(Boolean) : [];
}

function getDeviceName(device: any): string {
    return device?.getName?.() ?? device?.device ?? '';
}

function appendZone(map: Map<string, string[]>, key: string, zone: string) {
    if (!key) return;
    const zones = map.get(key) ?? [];
    if (!zones.includes(zone)) zones.push(zone);
    map.set(key, zones);
}

function buildFirewallZoneContext() {
    const zonesByNetwork = new Map<string, string[]>();
    const zonesByDevice = new Map<string, string[]>();
    const wanNetworks = new Set<string>(['wan', 'wan6']);
    const wanDevices = new Set<string>();

    uci.sections('firewall', 'zone', (zone: any) => {
        const zoneName = zone.name ?? '';
        toStringArray(zone.network).forEach((networkName) => {
            appendZone(zonesByNetwork, networkName, zoneName);
            if (zoneName.toLowerCase() === 'wan') wanNetworks.add(networkName);
        });
        toStringArray(zone.device).forEach((deviceName) => {
            appendZone(zonesByDevice, deviceName, zoneName);
            if (zoneName.toLowerCase() === 'wan') wanDevices.add(deviceName);
        });
    });

    return {zonesByNetwork, zonesByDevice, wanNetworks, wanDevices};
}

function buildAclInterfaceOptions(networks: any[], devices: any[]): AclInterfaceOption[] {
    const knownDevices = new Set(devices.map(getDeviceName).filter(Boolean));
    const {zonesByNetwork, zonesByDevice, wanNetworks, wanDevices} = buildFirewallZoneContext();
    const records = networks.map((logicalNetwork: any) => {
        const networkName = logicalNetwork.getName?.() ?? '';
        const l3Device = logicalNetwork.getL3Device?.();
        const configuredDevice = logicalNetwork.getDevice?.();
        const l3DeviceName = getDeviceName(l3Device);
        const configuredDeviceName = getDeviceName(configuredDevice);
        const device = l3DeviceName || (knownDevices.has(configuredDeviceName) ? configuredDeviceName : '');
        const zones = Array.from(new Set([
            ...(zonesByNetwork.get(networkName) ?? []),
            ...(zonesByDevice.get(device) ?? []),
        ]));
        return {
            network: networkName,
            zones,
            device,
        };
    });
    const blockedWanDevices = new Set([
        ...wanDevices,
        ...records
        .filter((record) => wanNetworks.has(record.network) || record.zones.some((zone) => zone.toLowerCase() === 'wan'))
        .map((record) => record.device)
        .filter(Boolean),
    ]);
    const options = new Map<string, AclInterfaceOption>();

    records.forEach((record) => {
        if (!record.device || record.device === 'lo' || record.network === 'loopback') return;
        if (wanNetworks.has(record.network) || record.zones.some((zone) => zone.toLowerCase() === 'wan')) return;
        if (blockedWanDevices.has(record.device)) return;

        let option = options.get(record.device);
        if (!option) {
            option = {device: record.device, networks: [], zones: []};
            options.set(record.device, option);
        }
        if (!option.networks.includes(record.network)) option.networks.push(record.network);
        record.zones.forEach((zone) => {
            if (!option.zones.includes(zone)) option.zones.push(zone);
        });
    });

    return Array.from(options.values()).sort((a, b) => a.device.localeCompare(b.device));
}

function buildInterfaceLabel(iface: AclInterfaceOption) {
    const scope = [_('Networks: %s').format(iface.networks.join(', '))];
    if (iface.zones.length > 0) scope.push(_('Firewall zones: %s').format(iface.zones.join(', ')));
    return iface.device + ' (' + scope.join('; ') + ')';
}

const FirewallFormUtils = {
    loadAclContext: async function (): Promise<AclContext> {
        let hostHints: any = {};
        let networks: any[] = [];
        let devices: any[] = [];
        await Promise.all([
            network.getHostHints().then((r: any) => { hostHints = r?.hosts ?? {}; }),
            network.getNetworks().then((r: any) => { networks = r ?? []; }),
            network.getDevices().then((r: any) => { devices = r ?? []; }),
        ]);
        return {hostHints, interfaces: buildAclInterfaceOptions(networks, devices)};
    },

    appendHostHintOptions: function (option: LuCI.form.Value, hostHints: any) {
        Object.keys(hostHints).forEach((mac: any) => {
            option.value(mac, buildMacLabel(hostHints, mac));
        });
    },

    appendInterfaceOptions: function (option: LuCI.form.Value, interfaces: AclInterfaceOption[]) {
        interfaces.forEach((iface) => {
            option.value(iface.device, buildInterfaceLabel(iface));
        });
    },

    createIfaceValidator: function (interfaces: AclInterfaceOption[]) {
        return function (_sectionId: string, value: string) {
            if (!value) return true;
            const exists = interfaces.some((iface) => iface.device === value);
            if (!exists) return _('Interface "%s" Not Found').format(value);
            return true;
        };
    },

    createNftViewOption: function (s: LuCI.form.AbstractSection) {
        let nftViewOpt = s.taboption('nftables', form.TextValue, '_nft_view');
        nftViewOpt.rows = 30;
        nftViewOpt.monospace = true;
        nftViewOpt.load = function () { return ''; };
        nftViewOpt.write = function () { };
        nftViewOpt.renderWidget = function (section_id: string, option_index: number, cfgvalue: any) {
            let widget = form.TextValue.prototype.renderWidget.call(this, section_id, option_index, cfgvalue) as HTMLElement;
            let textarea = widget.querySelector('textarea') as HTMLTextAreaElement;
            let loaded = false;
            let loading = false;
            const loadPrompt = _('Click to View Firewall Rules');

            textarea.readOnly = true;
            textarea.placeholder = loadPrompt;
            textarea.setAttribute('aria-label', loadPrompt);
            textarea.title = loadPrompt;
            textarea.style.cursor = 'pointer';

            const loadRules = function () {
                if (loaded || loading) return;

                loading = true;
                textarea.setAttribute('aria-busy', 'true');
                textarea.style.cursor = 'progress';
                textarea.value = _('Loading');

                fs.exec_direct('/usr/lib/hijpass/nft.sh', ['show'], 'text')
                    .then((res: any) => {
                        textarea.value = res?.trim() || _('No Rules');
                        textarea.setAttribute('aria-label', _('Firewall Rules'));
                        textarea.removeAttribute('title');
                        loaded = true;
                    })
                    .catch(() => { textarea.value = _('Read Failed'); })
                    .finally(() => {
                        loading = false;
                        textarea.removeAttribute('aria-busy');
                        textarea.style.cursor = loaded ? 'text' : 'pointer';
                    });
            };

            textarea.addEventListener('click', loadRules);
            textarea.addEventListener('keydown', function (event: KeyboardEvent) {
                if (!loaded && (event.key === 'Enter' || event.key === ' ')) {
                    event.preventDefault();
                    loadRules();
                }
            });

            return widget;
        };
    },
}

export { FirewallFormUtils }
