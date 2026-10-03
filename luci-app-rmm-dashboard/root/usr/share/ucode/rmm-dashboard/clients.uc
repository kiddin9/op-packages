// Normalize passive kernel observations. No packet probes or network writes.
export function inventory(links, fdb, neighbors, wireless) {
    let devices = {}, own = {}, result = { fdb: [], neighbors: [], truncated: false };
    for (let link in links) {
        devices[link.dev] = link;
        if (link.address) own[uc(link.address)] = true;
    }
    function client_mac(value) {
        return type(value) == 'string' && match(value, /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/i) &&
            !(int(substr(value, 0, 2), 16) & 1) && value != '00:00:00:00:00:00' && !own[uc(value)];
    }
    for (let row in fdb) {
        let port = devices[row.dev];
        // Permanent/local/self entries and virtual or wireless paths do not prove Ethernet ingress.
        if (!client_mac(row.lladdr) || !port?.master || port.type != 1 || wireless[row.dev] ||
            (port.linkinfo?.type && port.linkinfo.type != 'dsa') || (row.state & (128 | 64)) || (row.flags & 2) || !(row.state & (2 | 4 | 8 | 16)))
            continue;
        if (length(result.fdb) >= 1024) { result.truncated = true; continue; }
        push(result.fdb, { mac: uc(row.lladdr), port: row.dev, bridge: port.master,
            vlan: row.vlan, link_up: type(port.carrier) == 'bool' ? port.carrier : null });
    }
    for (let row in neighbors) {
        if (!client_mac(row.lladdr) || type(row.dst) != 'string' || !devices[row.dev]) continue;
        if (length(result.neighbors) >= 1024) { result.truncated = true; continue; }
        let state = (row.state & 32) ? 'failed' : (row.state & 1) ? 'incomplete' :
            (row.state & 128) ? 'permanent' : (row.state & 2) ? 'reachable' :
            (row.state & 4) ? 'stale' : (row.state & 8) ? 'delay' : (row.state & 16) ? 'probe' : 'unknown';
        push(result.neighbors, { mac: uc(row.lladdr), address: row.dst, device: row.dev, state });
    }
    return result;
};
