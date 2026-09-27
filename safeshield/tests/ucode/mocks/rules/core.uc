'use strict';

function trim(s) {
    return replace(s, /^[\r\n\t ]+|[\r\n\t ]+$/g, '');
}

function to_bool(v, def) {
    if (v == null) return def;
    let s = sprintf('%s', v);
    if (s == '1' || s == 'true' || s == 'yes' || s == 'on') return true;
    if (s == '0' || s == 'false' || s == 'no' || s == 'off') return false;
    return def;
}

function api_error(code, message, field) {
    let error = { code: code, message: message };
    if (field) error.field = field;
    return { ok: false, error: error };
}

return {
    LOCAL_ALLOWLIST_FILE: sprintf('%s/allowlist', TEST_TMP),
    LOCAL_BLOCKLIST_FILE: sprintf('%s/blocklist', TEST_TMP),
    RULES_SCHEMA_NAME: 'safeshield.rules',
    RULES_SCHEMA_VERSION: 1,
    RULES_DIR: TEST_TMP,
    trim: trim,
    reload_uci: function() { return true; },
    cfg: function(name, def) { return name == 'apply_local_overrides' ? '1' : def; },
    to_bool: to_bool,
    api_error: api_error
};
