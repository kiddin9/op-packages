'use strict';

let core = require('core');
let runtime = require('runtime');

let reload_uci = core.reload_uci;
let cfg = core.cfg;
let trim = core.trim;
let mask_secret = core.mask_secret;
let api_error = core.api_error;
let uci_commit_option = core.uci_commit_option;
let uci_delete_option = core.uci_delete_option;
let start_refresh_async = runtime.start_refresh_async;
let reset_statistics_upload_state = runtime.reset_statistics_upload_state;

function license_get_call() {
    reload_uci();

    let key = cfg('license_key', '');

    return {
        ok: true,
        license: {
            configured: !!key,
            key: key
        }
    };
}

function license_update_call(request) {
    reload_uci();

    if (request.args.license_key == null) {
        return api_error('missing_argument', 'license_key is required; use an empty string to clear it', 'license_key');
    }

    let key = trim(request.args.license_key);

    if (length(key) > 512 || match(key, /[\r\n]/)) {
        return api_error('invalid_license_key', 'license_key must be at most 512 characters and contain no line breaks', 'license_key');
    }

    let current = cfg('license_key', '');

    if (current == key) {
        return {
            ok: true,
            changed: false,
            license: {
                configured: !!key,
                key_masked: mask_secret(key)
            },
            refresh: {
                requested: false,
                accepted: false,
                reason: 'unchanged'
            }
        };
    }

    let saved = key == ''
        ? uci_delete_option('license_key')
        : uci_commit_option('license_key', key);

    if (!saved) {
        return api_error('uci_commit_failed', 'Failed to update the SafeShield license key');
    }

    reset_statistics_upload_state();
    let refresh = start_refresh_async();

    return {
        ok: true,
        changed: true,
        license: {
            configured: !!key,
            key_masked: mask_secret(key)
        },
        refresh: {
            requested: true,
            accepted: refresh.accepted,
            reason: refresh.reason || ''
        }
    };
}

return {
    get: license_get_call,
    update: license_update_call
};
