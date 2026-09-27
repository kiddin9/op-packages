'use strict';

let fs = require('fs');
let uci = require('uci').cursor();

const PKG_NAME = 'safeshield';
const STATUS_FILE = `/dev/shm/${PKG_NAME}.status.json`;
const BLOCKLIST_FILE = '/tmp/dnsmasq.d/safeshield.blocklist';
const LOCAL_ALLOWLIST_FILE = '/etc/safeshield/allowlist';
const LOCAL_BLOCKLIST_FILE = '/etc/safeshield/blocklist';
const SCHEMA_NAME = 'safeshield.status';
const SCHEMA_VERSION = 1;
const CONFIG_SCHEMA_NAME = 'safeshield.config';
const CONFIG_SCHEMA_VERSION = 1;
const RULES_SCHEMA_NAME = 'safeshield.rules';
const RULES_SCHEMA_VERSION = 1;
const STATISTICS_SCHEMA_NAME = 'safeshield.statistics';
const STATISTICS_SCHEMA_VERSION = 3;
const STATISTICS_FILE = '/tmp/safeshield/statistics/statistics.json';
const SERVICE_INIT = '/etc/init.d/safeshield';
const RULES_DIR = '/etc/safeshield';

const CONFIG_SPEC = {
    verbosity: { kind: 'int', def: 2, min: 0, max: 7 },
    apply_local_overrides: { kind: 'bool', def: true },
    max_blocklist_file_size_kb: { kind: 'int', def: 30000, min: 1, max: 2147483647 },
    min_valid_line_count: { kind: 'int', def: 3000, min: 0, max: 2147483647 },
    compress_blocklist: { kind: 'bool', def: false },
    initial_dnsmasq_restart: { kind: 'bool', def: false },
    dnsmasq_sanity_check: { kind: 'bool', def: true },
    statistics_enabled: { kind: 'bool', def: true },
    statistics_snapshot_interval_s: { kind: 'int', def: 60, min: 10, max: 3600 },
    statistics_retention_hours: { kind: 'int', def: 168, min: 1, max: 168 },
    download_timeout: { kind: 'int', def: 10, min: 1, max: 86400 },
    download_retry: { kind: 'int', def: 3, min: 1, max: 100 },
    pause_timeout: { kind: 'int', def: 20, min: 1, max: 86400 },
    boot_start_delay_s: { kind: 'int', def: 30, min: 0, max: 86400 },
    refresh_on_boot: { kind: 'bool', def: true },
    refresh_interval_s: { kind: 'int', def: 28800, min: 1, max: 2147483647 },
    require_wan: { kind: 'bool', def: true },
    debug: { kind: 'bool', def: false }
};

function trim(s) {
    return replace(s, /^[\r\n\t ]+|[\r\n\t ]+$/g, '');
}

function pkg_version() {
    let s = fs.readfile(`/usr/lib/${PKG_NAME}/version`);
    if (!s) {
        return 'unknown';
    }

    return trim(s);
}

const PKG_VERSION = pkg_version();

function read_json_file(path, def) {
    let s = fs.readfile(path);
    if (!s) {
        return def;
    }

    try {
        return json(s);
    }
    catch (e) {
        return def;
    }
}

function file_exists(path) {
    let st = fs.stat(path);
    return !!st;
}

function file_size_kb(path) {
    let st = fs.stat(path);
    if (!st || type(st.size) != 'int') {
        return 0;
    }

    return int((st.size + 1023) / 1024);
}

function to_bool(v, def) {
    if (v == null) {
        return def;
    }

    switch (sprintf('%s', v)) {
        case '1':
        case 'true':
        case 'yes':
        case 'on':
            return true;
        case '0':
        case 'false':
        case 'no':
        case 'off':
            return false;
    }

    return def;
}

function to_optional_bool(v) {
    if (v == null || v == '') {
        return null;
    }

    switch (sprintf('%s', v)) {
        case '1':
        case 'true':
        case 'yes':
        case 'on':
            return true;
        case '0':
        case 'false':
        case 'no':
        case 'off':
            return false;
    }

    return null;
}

function to_int(v, def) {
    if (v == null || v == '') {
        return def;
    }

    let n = int(v);
    return (type(n) == 'int') ? n : def;
}

function reload_uci() {
    return !!uci.load(PKG_NAME);
}

function cfg(name, def) {
    let v = uci.get(PKG_NAME, 'config', name);
    return (v == null) ? def : v;
}

function identity_cfg(name, def) {
    let v = uci.get(PKG_NAME, 'identity', name);
    return (v == null) ? def : v;
}

function mask_secret(v) {
    let s = sprintf('%s', v || '');
    let n = length(s);

    if (n == 0) {
        return '';
    }

    if (n <= 8) {
        return '********';
    }

    return sprintf('%s...%s', substr(s, 0, 4), substr(s, n - 4));
}

function api_error(code, message, field) {
    let error = {
        code: code,
        message: message
    };

    if (field) {
        error.field = field;
    }

    return {
        ok: false,
        error: error
    };
}

function uci_commit_option(name, value) {
    if (!uci.set(PKG_NAME, 'config', name, sprintf('%s', value))) {
        return false;
    }

    if (!uci.commit(PKG_NAME)) {
        uci.revert(PKG_NAME);
        return false;
    }

    reload_uci();
    return true;
}

function uci_delete_option(name) {
    if (!uci.delete(PKG_NAME, 'config', name)) {
        return false;
    }

    if (!uci.commit(PKG_NAME)) {
        uci.revert(PKG_NAME);
        return false;
    }

    reload_uci();
    return true;
}

function bool_uci(v) {
    return v ? '1' : '0';
}

return {
    uci: uci,
    PKG_NAME: PKG_NAME,
    PKG_VERSION: PKG_VERSION,
    STATUS_FILE: STATUS_FILE,
    BLOCKLIST_FILE: BLOCKLIST_FILE,
    LOCAL_ALLOWLIST_FILE: LOCAL_ALLOWLIST_FILE,
    LOCAL_BLOCKLIST_FILE: LOCAL_BLOCKLIST_FILE,
    SCHEMA_NAME: SCHEMA_NAME,
    SCHEMA_VERSION: SCHEMA_VERSION,
    CONFIG_SCHEMA_NAME: CONFIG_SCHEMA_NAME,
    CONFIG_SCHEMA_VERSION: CONFIG_SCHEMA_VERSION,
    RULES_SCHEMA_NAME: RULES_SCHEMA_NAME,
    RULES_SCHEMA_VERSION: RULES_SCHEMA_VERSION,
    STATISTICS_SCHEMA_NAME: STATISTICS_SCHEMA_NAME,
    STATISTICS_SCHEMA_VERSION: STATISTICS_SCHEMA_VERSION,
    STATISTICS_FILE: STATISTICS_FILE,
    SERVICE_INIT: SERVICE_INIT,
    RULES_DIR: RULES_DIR,
    CONFIG_SPEC: CONFIG_SPEC,
    trim: trim,
    read_json_file: read_json_file,
    file_exists: file_exists,
    file_size_kb: file_size_kb,
    to_bool: to_bool,
    to_optional_bool: to_optional_bool,
    to_int: to_int,
    reload_uci: reload_uci,
    cfg: cfg,
    identity_cfg: identity_cfg,
    mask_secret: mask_secret,
    api_error: api_error,
    uci_commit_option: uci_commit_option,
    uci_delete_option: uci_delete_option,
    bool_uci: bool_uci
};
