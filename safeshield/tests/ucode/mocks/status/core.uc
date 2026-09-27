'use strict';

let config = {
    enabled: '1',
    refresh_on_boot: '1',
    require_wan: '1',
    refresh_interval_s: '28800',
    boot_start_delay_s: '30',
    license_key: 'abcd1234wxyz',
    apply_local_overrides: '1',
    device_vendor: 'Junatum',
    device_model: 'Test Router',
    device_arch: 'aarch64',
    device_memory_mb: '256'
};

let identity = {
    physical_fingerprint: 'fingerprint',
    fingerprint_version: '1',
    identity_provider: 'factory-mac',
    identity_source: 'eth0',
    identity_strength: 'strong',
    identity_profile: 'test-profile',
    device_code: 'xiaomi-ax3000t',
    device_code_source: 'smartsafehub_firmware',
    installation_id: 'install-id'
};

let state = {
    data: {
        status: 'ready',
        valid_line_count: '42000',
        artifact_tier: 'pro',
        artifact_version: '20260830T000000Z',
        artifact_unique_domains: '41000',
        artifact_source_count: '2',
        artifact_block_source_count: '1',
        artifact_allow_source_count: '1',
        health_api_resolve: '1',
        health_artifact_download: '1',
        health_dns_runtime: '1',
        blocklist_installed: '1',
        blocklist_file_size_kb: '2048',
        license_plan: 'pro',
        license_status: 'active'
    },
    warnings: [],
    errors: []
};

function to_bool(v, def) {
    if (v == null) return def;
    let s = sprintf('%s', v);
    if (s == '1' || s == 'true' || s == 'yes' || s == 'on') return true;
    if (s == '0' || s == 'false' || s == 'no' || s == 'off') return false;
    return def;
}

function to_optional_bool(v) {
    if (v == null || v == '') return null;
    return to_bool(v, null);
}

function to_int(v, def) {
    if (v == null || v == '') return def;
    let n = int(v);
    return type(n) == 'int' ? n : def;
}

function mask_secret(v) {
    let s = sprintf('%s', v || '');
    if (!length(s)) return '';
    if (length(s) <= 8) return '********';
    return sprintf('%s...%s', substr(s, 0, 4), substr(s, length(s) - 4));
}

return {
    PKG_NAME: 'safeshield',
    PKG_VERSION: '0.3.16-r4',
    STATUS_FILE: '/tmp/status.json',
    BLOCKLIST_FILE: '/tmp/blocklist',
    LOCAL_ALLOWLIST_FILE: '/etc/safeshield/allowlist',
    LOCAL_BLOCKLIST_FILE: '/etc/safeshield/blocklist',
    SCHEMA_NAME: 'safeshield.status',
    SCHEMA_VERSION: 1,
    state: state,
    config: config,
    reload_uci: function() { return true; },
    cfg: function(name, def) { return config[name] == null ? def : config[name]; },
    identity_cfg: function(name, def) { return identity[name] == null ? def : identity[name]; },
    read_json_file: function() { return state; },
    file_exists: function() { return false; },
    file_size_kb: function() { return 0; },
    to_bool: to_bool,
    to_optional_bool: to_optional_bool,
    to_int: to_int,
    mask_secret: mask_secret
};
