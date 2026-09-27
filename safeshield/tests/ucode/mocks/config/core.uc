'use strict';

let values = {
    enabled: '0',
    debug: '0',
    download_retry: '3',
    statistics_enabled: '1',
    license_key: 'abcd1234wxyz',
    device_vendor: 'Junatum',
    device_model: 'Test Router',
    device_arch: 'aarch64',
    device_memory_mb: '256'
};

const CONFIG_SPEC = {
    debug: { kind: 'bool', def: false },
    download_retry: { kind: 'int', def: 3, min: 1, max: 100 },
    statistics_enabled: { kind: 'bool', def: true }
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

function mask_secret(v) {
    let s = sprintf('%s', v || '');
    if (!length(s)) return '';
    if (length(s) <= 8) return '********';
    return sprintf('%s...%s', substr(s, 0, 4), substr(s, length(s) - 4));
}

function api_error(code, message, field) {
    let error = { code: code, message: message };
    if (field) error.field = field;
    return { ok: false, error: error };
}

let uci = {
    set: function(pkg, section, name, value) {
        values[name] = value;
        return true;
    },
    commit: function() { return true; },
    revert: function() { return true; }
};

function uci_commit_option(name, value) {
    values[name] = sprintf('%s', value);
    return true;
}

return {
    uci: uci,
    PKG_NAME: 'safeshield',
    CONFIG_SCHEMA_NAME: 'safeshield.config',
    CONFIG_SCHEMA_VERSION: 1,
    CONFIG_SPEC: CONFIG_SPEC,
    values: values,
    reload_uci: function() { return true; },
    cfg: function(name, def) { return values[name] == null ? def : values[name]; },
    to_bool: to_bool,
    to_int: to_int,
    mask_secret: mask_secret,
    api_error: api_error,
    uci_commit_option: uci_commit_option,
    bool_uci: function(v) { return v ? '1' : '0'; }
};
