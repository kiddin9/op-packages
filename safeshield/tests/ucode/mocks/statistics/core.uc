'use strict';

let config = {
    statistics_enabled: '1',
    statistics_retention_hours: '24',
    statistics_snapshot_interval_s: '30'
};

let data = {
    schema: { name: 'collector' },
    generation_id: 'generation-test',
    snapshot_seq: '42',
    volatile: '0',
    storage: 'tmpfs+flash',
    persistent: '1',
    persistence_enabled: '1',
    persistence_healthy: '1',
    persistence_mode: 'journal',
    persistent_error_count: '2',
    persistent_last_error_at: '190',
    persistent_updated_at: '195',
    persistent_checkpoint_interval_s: '3600',
    persistent_compacted_at: '180',
    persistent_compact_interval_s: '604800',
    started_at: '100',
    session_started_at: '150',
    updated_at: '200',
    totals: { queries: '120', blocked: '12' },
    source: {
        backend: 'dnsmasq_ubus',
        available: '1',
        instance_id: 'epoch-test',
        transport_scope: 'udp',
        client_capacity: '128',
        tracked_clients: '2',
        untracked_queries: '3',
        untracked_blocked: '2',
        poll_error_count: '4',
        last_error_at: '199'
    },
    hourly: [
        { bucket_start: '10', queries: '20', blocked: '2' },
        'invalid',
        { bucket_start: 20, queries: 30, blocked: 3 }
    ],
    device_limit: '128',
    devices_truncated: '1',
    devices: [
        { id: 'aa:bb', mac: 'AA:BB', ip: '192.0.2.10', hostname: 'phone', identified: '1', queries: '50', blocked: '5' },
        { id: '', ip: '192.0.2.11', queries: 10 },
        'invalid'
    ]
};

function to_bool(v, def) {
    if (v == null) return def;
    let s = sprintf('%s', v);
    if (s == '1' || s == 'true' || s == 'yes' || s == 'on') return true;
    if (s == '0' || s == 'false' || s == 'no' || s == 'off') return false;
    return def;
}

function to_int(v, def) {
    if (v == null || v == '') return def;
    let n = int(v);
    return type(n) == 'int' ? n : def;
}

return {
    PKG_NAME: 'safeshield',
    STATISTICS_SCHEMA_NAME: 'safeshield.statistics',
    STATISTICS_SCHEMA_VERSION: 3,
    STATISTICS_FILE: '/tmp/statistics.json',
    data: data,
    reload_uci: function() { return true; },
    cfg: function(name, def) { return config[name] == null ? def : config[name]; },
    read_json_file: function() { return data; },
    to_bool: to_bool,
    to_int: to_int
};
