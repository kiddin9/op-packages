'use strict';

let core = require('core');
let runtime = require('runtime');

let uci = core.uci;
let PKG_NAME = core.PKG_NAME;
let CONFIG_SCHEMA_NAME = core.CONFIG_SCHEMA_NAME;
let CONFIG_SCHEMA_VERSION = core.CONFIG_SCHEMA_VERSION;
let CONFIG_SPEC = core.CONFIG_SPEC;
let reload_uci = core.reload_uci;
let cfg = core.cfg;
let to_bool = core.to_bool;
let to_int = core.to_int;
let mask_secret = core.mask_secret;
let api_error = core.api_error;
let uci_commit_option = core.uci_commit_option;
let bool_uci = core.bool_uci;
let run_service_action = runtime.run_service_action;
let start_refresh_async = runtime.start_refresh_async;

function config_public_value(name, spec) {
    let raw = cfg(name, null);

    if (spec.kind == 'bool') {
        return to_bool(raw, spec.def);
    }

    return to_int(raw, spec.def);
}

function build_config() {
    reload_uci();

    let values = {};

    for (let name, spec in CONFIG_SPEC) {
        values[name] = config_public_value(name, spec);
    }

    values.enabled = to_bool(cfg('enabled', '0'), false);

    return {
        schema: {
            name: CONFIG_SCHEMA_NAME,
            version: CONFIG_SCHEMA_VERSION
        },
        values: values,
        license: {
            configured: !!cfg('license_key', ''),
            key_masked: mask_secret(cfg('license_key', ''))
        },
        device: {
            vendor: cfg('device_vendor', ''),
            model: cfg('device_model', ''),
            arch: cfg('device_arch', ''),
            memory_mb: to_int(cfg('device_memory_mb', ''), 0)
        }
    };
}

function validate_config_value(name, value) {
    let spec = CONFIG_SPEC[name];

    if (!spec) {
        if (name == 'enabled') {
            return api_error('dedicated_method_required', 'Use set_enabled to change enabled state', name);
        }

        if (name == 'license_key') {
            return api_error('dedicated_method_required', 'Use license_update to change the license key', name);
        }

        return api_error('unknown_option', 'Unsupported SafeShield configuration option', name);
    }

    if (spec.kind == 'bool') {
        if (type(value) != 'bool') {
            return api_error('invalid_type', 'Expected a boolean value', name);
        }

        return {
            ok: true,
            uci: bool_uci(value),
            value: value
        };
    }

    if (spec.kind == 'int') {
        if (type(value) != 'int') {
            return api_error('invalid_type', 'Expected an integer value', name);
        }

        if (value < spec.min || value > spec.max) {
            return api_error(
                'out_of_range',
                sprintf('Value must be between %d and %d', spec.min, spec.max),
                name
            );
        }

        return {
            ok: true,
            uci: sprintf('%d', value),
            value: value
        };
    }

    return api_error('invalid_spec', 'Invalid internal configuration specification', name);
}

function config_update_call(request) {
    reload_uci();

    let values = request.args.values || {};
    let changes = {};
    let changed_names = [];

    if (type(values) != 'object') {
        return api_error('invalid_type', 'values must be an object', 'values');
    }

    for (let name, value in values) {
        let checked = validate_config_value(name, value);

        if (!checked.ok) {
            return checked;
        }

        let current = cfg(name, null);
        if (sprintf('%s', current) != checked.uci) {
            changes[name] = checked.uci;
            push(changed_names, name);
        }
    }

    if (length(changed_names) == 0) {
        return {
            ok: true,
            changed: [],
            restarted: false,
            config: build_config()
        };
    }

    for (let name, value in changes) {
        if (!uci.set(PKG_NAME, 'config', name, value)) {
            uci.revert(PKG_NAME);
            return api_error('uci_set_failed', 'Failed to update SafeShield configuration', name);
        }
    }

    if (!uci.commit(PKG_NAME)) {
        uci.revert(PKG_NAME);
        return api_error('uci_commit_failed', 'Failed to commit SafeShield configuration');
    }

    reload_uci();

    let statistics_only =
        length(changed_names) == 1 &&
        changed_names[0] == 'statistics_enabled';

    if (statistics_only) {
        let reconciled = run_service_action('reconcile_statistics', 60000);
        if (!reconciled.ok) {
            return {
                ok: false,
                committed: true,
                changed: changed_names,
                restarted: false,
                reconciled: false,
                service_rc: reconciled.rc,
                error: {
                    code: 'statistics_reconcile_failed',
                    message: 'Configuration was committed but SafeShield statistics runtime reconciliation failed'
                },
                config: build_config()
            };
        }

        return {
            ok: true,
            changed: changed_names,
            restarted: false,
            reconciled: true,
            refresh: {
                requested: false,
                accepted: false,
                reason: 'not_required'
            },
            config: build_config()
        };
    }

    let restarted = run_service_action('restart', 60000);
    if (!restarted.ok) {
        return {
            ok: false,
            committed: true,
            changed: changed_names,
            restarted: false,
            service_rc: restarted.rc,
            error: {
                code: 'service_restart_failed',
                message: 'Configuration was committed but SafeShield failed to restart'
            },
            config: build_config()
        };
    }

    let refresh = start_refresh_async();

    return {
        ok: true,
        changed: changed_names,
        restarted: true,
        refresh: {
            requested: true,
            accepted: refresh.accepted,
            reason: refresh.reason || ''
        },
        config: build_config()
    };
}

function set_enabled_call(request) {
    reload_uci();

    if (request.args.enabled == null) {
        return api_error('missing_argument', 'enabled is required', 'enabled');
    }

    if (type(request.args.enabled) != 'bool') {
        return api_error('invalid_type', 'enabled must be a boolean', 'enabled');
    }

    let enabled = request.args.enabled;
    let current = to_bool(cfg('enabled', '0'), false);
    let changed = enabled != current;

    if (changed && !uci_commit_option('enabled', bool_uci(enabled))) {
        return api_error('uci_commit_failed', 'Failed to update enabled state');
    }

    let restarted = run_service_action('restart', 60000);
    if (!restarted.ok) {
        return {
            ok: false,
            committed: changed,
            changed: changed,
            accepted: false,
            target_enabled: enabled,
            reconciled: false,
            service_rc: restarted.rc,
            error: {
                code: 'service_restart_failed',
                message: 'Enabled state is configured but SafeShield failed to request runtime lifecycle reconciliation'
            }
        };
    }

    return {
        ok: true,
        changed: changed,
        accepted: true,
        target_enabled: enabled,
        reconciled: false
    };
}

return {
    build: build_config,
    update: config_update_call,
    set_enabled: set_enabled_call
};
