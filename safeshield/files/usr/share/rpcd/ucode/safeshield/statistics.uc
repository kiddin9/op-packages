'use strict';

let core = require('core');
let runtime = require('runtime');

let PKG_NAME = core.PKG_NAME;
let STATISTICS_SCHEMA_NAME = core.STATISTICS_SCHEMA_NAME;
let STATISTICS_SCHEMA_VERSION = core.STATISTICS_SCHEMA_VERSION;
let STATISTICS_FILE = core.STATISTICS_FILE;
let reload_uci = core.reload_uci;
let cfg = core.cfg;
let read_json_file = core.read_json_file;
let to_bool = core.to_bool;
let to_int = core.to_int;
let service_instance_running = runtime.service_instance_running;
function sanitize_hourly(items) {
    let result = [];

    if (type(items) != 'array') {
        return result;
    }

    for (let item in items) {
        if (type(item) != 'object') {
            continue;
        }

        push(result, {
            bucket_start: to_int(item.bucket_start, 0),
            queries: to_int(item.queries, 0),
            blocked: to_int(item.blocked, 0)
        });
    }

    return result;
}

function sanitize_devices(items) {
    let result = [];
    if (type(items) != 'array') {
        return result;
    }

    for (let item in items) {
        if (type(item) != 'object') {
            continue;
        }

        let id = sprintf('%s', item.id || '');
        if (!id) {
            continue;
        }
        push(result, {
            id: id,
            mac: sprintf('%s', item.mac || ''),
            ip: sprintf('%s', item.ip || ''),
            hostname: sprintf('%s', item.hostname || ''),
            identified: to_bool(item.identified, false),
            queries: to_int(item.queries, 0),
            blocked: to_int(item.blocked, 0),
            hourly: sanitize_hourly(item.hourly)
        });
    }

    return result;
}

function sanitize_source(item) {
    if (type(item) != 'object') {
        item = {};
    }

    return {
        backend: sprintf('%s', item.backend || 'dnsmasq_ubus'),
        available: to_bool(item.available, false),
        instance_id: sprintf('%s', item.instance_id || ''),
        transport_scope: sprintf('%s', item.transport_scope || ''),
        client_capacity: to_int(item.client_capacity, 0),
        tracked_clients: to_int(item.tracked_clients, 0),
        untracked_queries: to_int(item.untracked_queries, 0),
        untracked_blocked: to_int(item.untracked_blocked, 0),
        poll_error_count: to_int(item.poll_error_count, 0),
        last_error_at: to_int(item.last_error_at, 0)
    };
}

function build_statistics() {
    reload_uci();
    let enabled = to_bool(cfg('statistics_enabled', '1'), true);
    let retention_hours = to_int(cfg('statistics_retention_hours', '168'), 168);
    let snapshot_interval_s = to_int(cfg('statistics_snapshot_interval_s', '60'), 60);
    let data = read_json_file(STATISTICS_FILE, {});
    let totals = (type(data.totals) == 'object') ? data.totals : {};
    let collector_running = service_instance_running(PKG_NAME, 'statistics');
    let effective_enabled = enabled && collector_running;
    let source = sanitize_source(data.source);
    if (!effective_enabled) {
        source.available = false;
    }
    return {
        schema: {
            name: STATISTICS_SCHEMA_NAME,
            version: STATISTICS_SCHEMA_VERSION
        },
        enabled: enabled,
        effective_enabled: effective_enabled,
        available: !!data.schema,
        collector_running: collector_running,
        volatile: to_bool(data.volatile, true),
        storage: sprintf('%s', data.storage || 'tmpfs'),
        persistent: to_bool(data.persistent, false),
        persistence_enabled: to_bool(data.persistence_enabled, false),
        persistence_healthy: to_bool(data.persistence_healthy, false),
        persistence_mode: sprintf('%s', data.persistence_mode || 'none'),
        persistent_error_count: to_int(data.persistent_error_count, 0),
        persistent_last_error_at: to_int(data.persistent_last_error_at, 0),
        persistent_updated_at: to_int(data.persistent_updated_at, 0),
        persistent_checkpoint_interval_s: to_int(data.persistent_checkpoint_interval_s, 3600),
        persistent_compacted_at: to_int(data.persistent_compacted_at, 0),
        persistent_compact_interval_s: to_int(data.persistent_compact_interval_s, 604800),
        snapshot_interval_s: snapshot_interval_s,
        effective_snapshot_interval_s: to_int(data.snapshot_interval_s, snapshot_interval_s),
        retention_hours: retention_hours,
        generation_id: sprintf('%s', data.generation_id || ''),
        snapshot_seq: to_int(data.snapshot_seq, 0),
        source: source,
        started_at: to_int(data.started_at, 0),
        session_started_at: to_int(data.session_started_at, 0),
        updated_at: to_int(data.updated_at, 0),
        totals: {
            queries: to_int(totals.queries, 0),
            blocked: to_int(totals.blocked, 0)
        },
        hourly: sanitize_hourly(data.hourly),
        device_limit: to_int(data.device_limit, 128),
        devices_truncated: to_bool(data.devices_truncated, false),
        devices: sanitize_devices(data.devices)
    };
}
return {
    build: build_statistics
};
