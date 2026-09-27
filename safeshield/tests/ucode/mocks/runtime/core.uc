'use strict';

let values = {
    enabled: '1',
    apply_local_overrides: '1'
};

let state = {
    status: { data: { status: 'idle' } },
    reloads: 0
};

function to_bool(v, def) {
    if (v == null) return def;
    let s = sprintf('%s', v);
    if (s == '1' || s == 'true' || s == 'yes' || s == 'on') return true;
    if (s == '0' || s == 'false' || s == 'no' || s == 'off') return false;
    return def;
}

return {
    PKG_NAME: 'safeshield',
    STATUS_FILE: sprintf('%s/status.json', TEST_TMP),
    SERVICE_INIT: '/bin/true',
    values: values,
    state: state,
    read_json_file: function() { return state.status; },
    to_bool: to_bool,
    reload_uci: function() { state.reloads++; return true; },
    cfg: function(name, def) { return values[name] == null ? def : values[name]; }
};
