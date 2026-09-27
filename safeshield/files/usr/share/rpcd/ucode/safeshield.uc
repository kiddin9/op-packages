'use strict';

// Keep private SafeShield RPC modules next to this rpcd entrypoint.
// Prepend the private module directory to the ucode require() search path.
unshift(REQUIRE_SEARCH_PATH, '/usr/share/rpcd/ucode/safeshield/*.uc');

let status = require('status');
let config = require('config');
let refresh = require('refresh');
let rules = require('rules');
let license = require('license');
let statistics = require('statistics');

return {
    safeshield: {
        status: {
            call: status.build
        },

        config: {
            call: config.build
        },

        statistics: {
            call: statistics.build
        },

        config_update: {
            args: {
                values: {}
            },
            call: config.update
        },

        set_enabled: {
            args: {
                enabled: true
            },
            call: config.set_enabled
        },

        refresh: {
            call: refresh.call
        },

        rules_list: {
            args: {
                action: ''
            },
            call: rules.list
        },

        rule_add: {
            args: {
                action: '',
                domain: '',
                refresh: true
            },
            call: rules.add
        },

        rule_delete: {
            args: {
                action: '',
                domain: '',
                refresh: true
            },
            call: rules.delete
        },

        license_get: {
            call: license.get
        },

        license_update: {
            args: {
                license_key: ''
            },
            call: license.update
        }
    }
};
