'use strict';

let statistics = require('statistics');

let result = statistics.build();
assert(result.schema.name == 'safeshield.statistics' && result.schema.version == 3, 'statistics schema is preserved');
assert(result.enabled == true && result.effective_enabled == true && result.available == true, 'configured and effective statistics availability are reported');
assert(result.collector_state == 'running' && result.collector_lookup_ok == true, 'collector lookup detail is exposed');
assert(result.collector_running == true, 'statistics collector state is reported');
assert(result.snapshot_interval_s == 30 && result.effective_snapshot_interval_s == 30 && result.retention_hours == 24, 'statistics config values are normalized');
assert(result.generation_id == 'generation-test', 'statistics generation is preserved');
assert(result.snapshot_seq == 42, 'statistics snapshot sequence is preserved');
assert(result.started_at == 100 && result.session_started_at == 150 && result.updated_at == 200, 'statistics timestamps are normalized');
assert(result.volatile == false && result.storage == 'tmpfs+flash' && result.persistent == true, 'statistics storage metadata is normalized');
assert(result.persistence_enabled == true && result.persistence_healthy == true && result.persistence_mode == 'journal', 'statistics persistence state is normalized');
assert(result.persistent_error_count == 2 && result.persistent_last_error_at == 190, 'statistics persistence errors are normalized');
assert(result.persistent_updated_at == 195 && result.persistent_checkpoint_interval_s == 3600, 'statistics persistence checkpoint metadata is normalized');
assert(result.totals.queries == 120 && result.totals.blocked == 12, 'statistics totals are normalized');
assert(result.source.backend == 'dnsmasq_ubus' && result.source.available == true, 'statistics source backend is normalized');
assert(result.source.instance_id == 'epoch-test' && result.source.transport_scope == 'udp', 'statistics source epoch and transport scope are preserved');
assert(result.source.client_capacity == 128 && result.source.tracked_clients == 2 && result.source.untracked_queries == 3 && result.source.untracked_blocked == 2, 'statistics source client metadata is normalized');
assert(result.source.poll_error_count == 4 && result.source.last_error_at == 199, 'statistics source errors are normalized');
assert(length(result.hourly) == 2, 'invalid hourly entries are discarded');
assert(result.hourly[0].queries == 20 && result.hourly[1].blocked == 3, 'hourly values are normalized');
assert(result.device_limit == 128 && result.devices_truncated == true, 'device metadata is normalized');
assert(length(result.devices) == 1, 'invalid devices and empty ids are discarded');
assert(result.devices[0].identified == true, 'device identified flag is normalized');
assert(result.devices[0].queries == 50 && result.devices[0].blocked == 5, 'device counters are normalized');

print('ucode statistics tests: ok\n');

// Summary is deliberately opt-in. It must not duplicate large per-device
// arrays while preserving the health/totals metadata used by lightweight UIs.
let summary = statistics.summary();
assert(summary.schema.name == result.schema.name && summary.schema.version == result.schema.version, 'summary preserves schema');
assert(summary.snapshot_seq == result.snapshot_seq && summary.generation_id == result.generation_id, 'summary preserves freshness');
assert(summary.enabled == result.enabled && summary.collector_running == result.collector_running, 'summary preserves service status');
assert(summary.source.backend == result.source.backend && summary.source.tracked_clients == result.source.tracked_clients, 'summary preserves source health');
assert(summary.totals.queries == result.totals.queries && summary.totals.blocked == result.totals.blocked, 'summary preserves totals');
assert(summary.device_limit == result.device_limit && summary.devices_truncated == result.devices_truncated, 'summary preserves device capacity metadata');
assert(summary.hourly == null && summary.devices == null, 'summary omits detailed arrays');
assert(length(result.hourly) == 2 && length(result.devices) == 1, 'full statistics remains unchanged after summary');
