'use strict';

let core = require('core');
let runtime = require('runtime');

let PKG_NAME = core.PKG_NAME;
let PKG_VERSION = core.PKG_VERSION;
let STATUS_FILE = core.STATUS_FILE;
let BLOCKLIST_FILE = core.BLOCKLIST_FILE;
let LOCAL_ALLOWLIST_FILE = core.LOCAL_ALLOWLIST_FILE;
let LOCAL_BLOCKLIST_FILE = core.LOCAL_BLOCKLIST_FILE;
let SCHEMA_NAME = core.SCHEMA_NAME;
let SCHEMA_VERSION = core.SCHEMA_VERSION;
let reload_uci = core.reload_uci;
let cfg = core.cfg;
let identity_cfg = core.identity_cfg;
let read_json_file = core.read_json_file;
let file_exists = core.file_exists;
let file_size_kb = core.file_size_kb;
let to_bool = core.to_bool;
let to_optional_bool = core.to_optional_bool;
let to_int = core.to_int;
let mask_secret = core.mask_secret;
let service_running = runtime.service_running;
let dnsmasq_running = runtime.dnsmasq_running;

function build_api_source(data, enabled) {
    let api_resolve_ok = to_optional_bool(data.health_api_resolve);
    let artifact_download_ok = to_optional_bool(data.health_artifact_download);
    let last_result = data.last_result || '';
    let last_error_code = data.last_error_code || '';

    if (!enabled) {
        last_result = 'disabled';
    }
    else if (api_resolve_ok == true && artifact_download_ok == true) {
        last_result = 'ok';
    }
    else if (api_resolve_ok == false) {
        last_result = last_error_code == 'safeshield_upgrade_required' ? last_error_code : 'api_resolve_failed';
    }
    else if (artifact_download_ok == false) {
        last_result = last_error_code == 'safeshield_upgrade_required' ? last_error_code : 'artifact_download_failed';
    }
    else if (!last_result || last_result == 'idle') {
        last_result = 'configured';
    }

    return {
        section: 'hub_api',
        name: 'SmartSafeHub API Artifacts',
        action: 'block',
        enabled: enabled,
        last_result: last_result,
        line_count: to_int(data.artifact_unique_domains || data.valid_line_count || 0, 0),
        size_kb: to_int(data.blocklist_file_size_kb || 0, 0),
        artifact_tier: data.artifact_tier || '',
        artifact_version: data.artifact_version || '',
        source_count: to_int(data.artifact_source_count || (to_bool(data.artifact_download_url_present || '0', false) ? 1 : 0), 0),
        block_source_count: to_int(data.artifact_block_source_count || (to_bool(data.artifact_download_url_present || '0', false) ? 1 : 0), 0),
        allow_source_count: to_int(data.artifact_allow_source_count || 0, 0)
    };
}

function first_error_code(errors) {
    if (type(errors) != 'array' || length(errors) == 0) {
        return '';
    }

    let e = errors[0];
    if (type(e) == 'object' && e.code != null) {
        return sprintf('%s', e.code);
    }

    return sprintf('%s', e);
}

function build_summary(status, stage, valid_line_count, artifact_tier, artifact_version, errors, warnings) {
    let sev = 'info';
    let label = 'Idle';
    let msg = 'SafeShield is idle';

    if (status == 'ready') {
        label = 'Ready';

        if (artifact_tier || artifact_version) {
            msg = sprintf('Hub artifact %s/%s is active, %d rules active', artifact_tier || 'unknown', artifact_version || 'unknown', valid_line_count);
        }
        else {
            msg = sprintf('Hub artifact is active, %d rules active', valid_line_count);
        }
    }
    else if (status == 'running') {
        sev = 'notice';
        label = 'Running';
        msg = stage ? sprintf('Refresh in progress (%s)', stage) : 'Refresh in progress';
    }
    else if (status == 'error') {
        sev = 'error';
        label = 'Error';
        msg = first_error_code(errors) || 'Refresh failed';
    }
    else if (status == 'paused') {
        sev = 'warning';
        label = 'Paused';
        msg = 'SafeShield is paused';
    }
    else if (status == 'disabled') {
        sev = 'warning';
        label = 'Disabled';
        msg = 'SafeShield is disabled';
    }

    if (type(warnings) == 'array' && length(warnings) > 0 && sev == 'info') {
        sev = 'warning';
    }

    return {
        label: label,
        message: msg,
        severity: sev
    };
}

function build_status() {
    reload_uci();

    let state = read_json_file(STATUS_FILE, {});
    let data = state.data || {};

    let enabled = to_bool(cfg('enabled', '0'), false);
    let refresh_on_boot = to_bool(cfg('refresh_on_boot', '1'), true);
    let require_wan = to_bool(cfg('require_wan', '1'), true);
    let refresh_interval_s = to_int(cfg('refresh_interval_s', '28800'), 28800);
    let boot_start_delay_s = to_int(cfg('boot_start_delay_s', '30'), 30);

    let license_key = cfg('license_key', '');
    let license_configured = !!license_key;
    let apply_local_overrides = to_bool(cfg('apply_local_overrides', '1'), true);

    let cfg_physical_fingerprint = identity_cfg('physical_fingerprint', '');
    let cfg_fingerprint_version = identity_cfg('fingerprint_version', '1');
    let cfg_identity_provider = identity_cfg('identity_provider', '');
    let cfg_identity_source = identity_cfg('identity_source', '');
    let cfg_identity_strength = identity_cfg('identity_strength', '');
    let cfg_identity_profile = identity_cfg('identity_profile', '');
    let cfg_device_code = identity_cfg('device_code', '');
    let cfg_device_code_source = identity_cfg('device_code_source', 'unknown');
    let cfg_installation_id = identity_cfg('installation_id', '');
    let cfg_device_vendor = cfg('device_vendor', '');
    let cfg_device_model = cfg('device_model', '');
    let cfg_device_arch = cfg('device_arch', '');
    let cfg_device_memory_mb = cfg('device_memory_mb', '');

    let status = data.status || (enabled ? 'idle' : 'disabled');
    let stage = data.stage || '';
    let valid_line_count = to_int(data.valid_line_count || 0, 0);
    let warnings = (type(state.warnings) == 'array') ? state.warnings : [];
    let errors = (type(state.errors) == 'array') ? state.errors : [];

    let last_attempt = to_int(data.last_attempt || 0, 0);
    let last_success = to_int(data.last_success || 0, 0);
    let last_failure = to_int(data.last_failure || 0, 0);
    let last_local_apply = to_int(data.last_local_apply || 0, 0);
    let last_local_apply_failure = to_int(data.last_local_apply_failure || 0, 0);
    let next_refresh_at = to_int(data.next_refresh_at || 0, 0);
    let last_result = data.last_result || '';
    let last_error_code = data.last_error_code || '';

    let blocklist_file_size_kb = to_int(data.blocklist_file_size_kb || 0, 0);
    let blocklist_installed = to_bool(data.blocklist_installed || '0', false);
    let blocklist_verification_ok = to_bool(data.blocklist_verification_ok || '0', false);
    let blocklist_test_domain = data.blocklist_test_domain || '';
    let blocklist_test_domain_sample_count = to_int(data.blocklist_test_domain_sample_count || 0, 0);
    let blocklist_test_domain_success_count = to_int(data.blocklist_test_domain_success_count || 0, 0);
    let blocklist_test_domains = data.blocklist_test_domains || '';
    let blocklist_backup_available = to_bool(data.blocklist_backup_available || '0', false);

    let artifact_tier = data.artifact_tier || '';
    let artifact_version = data.artifact_version || '';
    let artifact_sha256 = data.artifact_sha256 || '';
    let artifact_unique_domains = to_int(data.artifact_unique_domains || 0, 0);
    let artifact_rules = to_int(data.artifact_rules || 0, 0);
    let artifact_download_url_present = to_bool(data.artifact_download_url_present || '0', false);
    let artifact_source_count = to_int(data.artifact_source_count || (artifact_download_url_present ? 1 : 0), 0);
    let artifact_block_source_count = to_int(data.artifact_block_source_count || (artifact_download_url_present ? 1 : 0), 0);
    let artifact_allow_source_count = to_int(data.artifact_allow_source_count || 0, 0);

    let license_plan = data.license_plan || '';
    let license_status = data.license_status || '';
    let physical_fingerprint = data.physical_fingerprint || cfg_physical_fingerprint || '';
    let fingerprint_version = to_int(data.fingerprint_version || cfg_fingerprint_version || 1, 1);
    let identity_provider = data.identity_provider || cfg_identity_provider || '';
    let identity_source = data.identity_source || cfg_identity_source || '';
    let identity_strength = data.identity_strength || cfg_identity_strength || '';
    let identity_profile = data.identity_profile || cfg_identity_profile || '';
    let device_code = data.device_code || cfg_device_code || '';
    let device_code_source = data.device_code_source || cfg_device_code_source || 'unknown';
    let installation_id = data.installation_id || cfg_installation_id || '';
    let device_profile = data.device_profile || '';
    let dnsmasq_version = data.dnsmasq_version || '';
    let dnsmasq_min_version = data.dnsmasq_min_version || '2.93';

    let health_dnsmasq_binary = to_bool(data.health_dnsmasq_binary || '0', false);
    let health_dnsmasq_version = to_bool(data.health_dnsmasq_version || '0', false);
    let health_dnsmasq_features = to_bool(data.health_dnsmasq_features || '0', false);
    let health_dnsmasq_confdir = to_bool(data.health_dnsmasq_confdir || '0', false);
    let health_dnsmasq_initial_restart = to_optional_bool(data.health_dnsmasq_initial_restart);
    let health_dnsmasq_final_restart = to_bool(data.health_dnsmasq_final_restart || '0', false);
    let health_dns_runtime = to_bool(data.health_dns_runtime || '0', false);
    let health_blocklist_verify = to_bool(data.health_blocklist_verify || '0', false);
    let health_min_valid_line_count = to_bool(data.health_min_valid_line_count || '0', false);
    let health_max_file_size = to_bool(data.health_max_file_size || '0', false);
    let health_api_resolve = to_optional_bool(data.health_api_resolve);
    let health_artifact_download = to_optional_bool(data.health_artifact_download);
    let health_artifact_sha256 = to_optional_bool(data.health_artifact_sha256);

    let hub_source = build_api_source(data, enabled);
    let installed = blocklist_installed || file_exists(BLOCKLIST_FILE);
    let refreshd_running = service_running(PKG_NAME);
    let dns_running = dnsmasq_running();

    let generated_at = time();
    let next_refresh_in_s = 0;

    if (next_refresh_at > generated_at) {
        next_refresh_in_s = next_refresh_at - generated_at;
    }

    return {
        schema: {
            name: SCHEMA_NAME,
            version: SCHEMA_VERSION
        },

        name: PKG_NAME,
        version: PKG_VERSION,

        enabled: enabled,
        active: refreshd_running,
        status: status,
        stage: stage,

        summary: build_summary(status, stage, valid_line_count, artifact_tier, artifact_version, errors, warnings),

        runtime: {
            refreshd_running: refreshd_running,
            dnsmasq_running: dns_running,
            dnsmasq_version: dnsmasq_version,
            dnsmasq_min_version: dnsmasq_min_version,
            dns_runtime_ok: health_dns_runtime || dns_running,
            config_loaded: true,
            require_wan: require_wan,
            refresh_on_boot: refresh_on_boot,
            last_result: last_result,
            last_error_code: last_error_code
        },
        license: {
            configured: license_configured,
            key_masked: mask_secret(license_key),
            plan: license_plan,
            status: license_status
        },

        device: {
            physical_fingerprint: physical_fingerprint,
            fingerprint_version: fingerprint_version,
            identity_provider: identity_provider,
            identity_source: identity_source,
            identity_strength: identity_strength,
            identity_profile: identity_profile,
            device_code: device_code,
            device_code_source: device_code_source,
            installation_id: installation_id,
            profile: device_profile,
            configured: {
                physical_fingerprint: cfg_physical_fingerprint,
                vendor: cfg_device_vendor,
                model: cfg_device_model,
                arch: cfg_device_arch,
                memory_mb: to_int(cfg_device_memory_mb, 0)
            }
        },

        artifact: {
            resolved: !!artifact_tier || !!artifact_version || artifact_download_url_present,
            tier: artifact_tier,
            version: artifact_version,
            sha256: artifact_sha256,
            unique_domains: artifact_unique_domains,
            rules: artifact_rules,
            download_url_present: artifact_download_url_present,
            source_count: artifact_source_count,
            block_source_count: artifact_block_source_count,
            allow_source_count: artifact_allow_source_count
        },

        local_overrides: {
            enabled: apply_local_overrides,
            allowlist_path: LOCAL_ALLOWLIST_FILE,
            blocklist_path: LOCAL_BLOCKLIST_FILE
        },

        blocklist: {
            installed: installed,
            path: BLOCKLIST_FILE,
            valid_line_count: valid_line_count,
            file_size_kb: blocklist_file_size_kb || file_size_kb(BLOCKLIST_FILE),
            verification_ok: blocklist_verification_ok,
            test_domain: blocklist_test_domain,
            test_domain_sample_count: blocklist_test_domain_sample_count,
            test_domain_success_count: blocklist_test_domain_success_count,
            test_domains: blocklist_test_domains,
            compressed: false,
            previous_backup_available: blocklist_backup_available
        },

        sources: {
            mode: 'hub_api',
            total: 1,
            enabled: hub_source.enabled ? 1 : 0,
            items: [ hub_source ]
        },

        health: {
            overall: (status == 'error') ? 'error' : ((type(warnings) == 'array' && length(warnings) > 0) ? 'warning' : 'ok'),
            checks: {
                api_resolve: health_api_resolve,
                artifact_download: health_artifact_download,
                artifact_sha256: health_artifact_sha256,
                dnsmasq_binary: health_dnsmasq_binary,
                dnsmasq_version: health_dnsmasq_version,
                dnsmasq_features: health_dnsmasq_features,
                dnsmasq_confdir: health_dnsmasq_confdir,
                dnsmasq_initial_restart: health_dnsmasq_initial_restart,
                dnsmasq_final_restart: health_dnsmasq_final_restart,
                dns_runtime: health_dns_runtime,
                blocklist_verify: health_blocklist_verify,
                min_valid_line_count: health_min_valid_line_count,
                max_file_size: health_max_file_size
            }
        },

        warnings: warnings,
        errors: errors,

        timestamps: {
            generated_at: generated_at,
            last_attempt: last_attempt,
            last_success: last_success,
            last_failure: last_failure,
            last_local_apply: last_local_apply,
            last_local_apply_failure: last_local_apply_failure,
            next_refresh_at: next_refresh_at,
            refresh_interval_s: refresh_interval_s,
            next_refresh_in_s: next_refresh_in_s,
            boot_start_delay_s: boot_start_delay_s
        }
    };
}

return {
    build: build_status
};
