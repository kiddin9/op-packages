'use strict';

let state = {
    license_key: 'existing-license-key',
    commits: 0,
    deletes: 0
};

function trim(s) {
    return replace(s, /^[\r\n\t ]+|[\r\n\t ]+$/g, '');
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

return {
    state: state,
    reload_uci: function() { return true; },
    cfg: function(name, def) { return name == 'license_key' ? state.license_key : def; },
    trim: trim,
    mask_secret: mask_secret,
    api_error: api_error,
    uci_commit_option: function(name, value) {
        state.license_key = value;
        state.commits++;
        return true;
    },
    uci_delete_option: function(name) {
        state.license_key = '';
        state.deletes++;
        return true;
    }
};
