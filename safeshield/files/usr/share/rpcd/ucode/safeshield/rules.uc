'use strict';

let fs = require('fs');
let core = require('core');
let runtime = require('runtime');

let LOCAL_ALLOWLIST_FILE = core.LOCAL_ALLOWLIST_FILE;
let LOCAL_BLOCKLIST_FILE = core.LOCAL_BLOCKLIST_FILE;
let RULES_SCHEMA_NAME = core.RULES_SCHEMA_NAME;
let RULES_SCHEMA_VERSION = core.RULES_SCHEMA_VERSION;
let RULES_DIR = core.RULES_DIR;
let trim = core.trim;
let reload_uci = core.reload_uci;
let cfg = core.cfg;
let to_bool = core.to_bool;
let api_error = core.api_error;
let start_local_apply_async = runtime.start_local_apply_async;

function normalize_rule_domain(value) {
    if (type(value) != 'string') {
        return '';
    }

    let domain = lc(trim(value));

    if (!domain || substr(domain, 0, 1) == '#' || substr(domain, 0, 1) == '!') {
        return '';
    }

    domain = replace(domain, /^0\.0\.0\.0[ \t]+/, '');
    domain = replace(domain, /^127\.0\.0\.1[ \t]+/, '');
    domain = replace(domain, /^local=\//, '');
    domain = replace(domain, /^address=\//, '');
    domain = replace(domain, /\/0\.0\.0\.0$/, '');
    domain = replace(domain, /\/::$/, '');
    domain = replace(domain, /\/$/, '');
    domain = replace(domain, /^\//, '');

    if (!match(domain, /^[a-z0-9._-]+$/) || length(domain) > 253 || index(domain, '..') >= 0) {
        return '';
    }

    for (let label in split(domain, '.')) {
        if (!label || length(label) > 63 || substr(label, 0, 1) == '-' || substr(label, -1) == '-') {
            return '';
        }
    }

    return domain;
}

function rule_path(action) {
    if (action == 'allow') {
        return LOCAL_ALLOWLIST_FILE;
    }

    if (action == 'block') {
        return LOCAL_BLOCKLIST_FILE;
    }

    return null;
}

function read_rule_entries(path) {
    let content = fs.readfile(path) || '';
    let entries = [];
    let seen = {};

    for (let line in split(content, /\n/)) {
        let domain = normalize_rule_domain(line);

        if (!domain || seen[domain]) {
            continue;
        }

        seen[domain] = true;
        push(entries, domain);
    }

    sort(entries);
    return entries;
}

function write_rule_file_atomic(path, content) {
    if (!fs.stat(RULES_DIR) && !fs.mkdir(RULES_DIR)) {
        return false;
    }

    let tmp = sprintf('%s.tmp.%d', path, time());

    if (fs.writefile(tmp, content) == null) {
        fs.unlink(tmp);
        return false;
    }

    if (!fs.chmod(tmp, 0o644)) {
        fs.unlink(tmp);
        return false;
    }

    if (!fs.rename(tmp, path)) {
        fs.unlink(tmp);
        return false;
    }

    return true;
}

function rule_file_contains(path, domain) {
    for (let existing in read_rule_entries(path)) {
        if (existing == domain) {
            return true;
        }
    }

    return false;
}

function add_rule_to_file(path, domain) {
    let content = fs.readfile(path) || '';

    if (rule_file_contains(path, domain)) {
        return {
            ok: true,
            changed: false
        };
    }

    if (content && substr(content, -1) != '\n') {
        content += '\n';
    }

    content += domain + '\n';

    return {
        ok: write_rule_file_atomic(path, content),
        changed: true
    };
}

function delete_rule_from_file(path, domain) {
    let content = fs.readfile(path) || '';
    let lines = split(content, /\n/);
    let kept = [];
    let changed = false;

    for (let line in lines) {
        if (normalize_rule_domain(line) == domain) {
            changed = true;
            continue;
        }

        push(kept, line);
    }

    if (!changed) {
        return {
            ok: true,
            changed: false
        };
    }

    let next = join('\n', kept);

    return {
        ok: write_rule_file_atomic(path, next),
        changed: true
    };
}

function build_rules(action) {
    let allow = read_rule_entries(LOCAL_ALLOWLIST_FILE);
    let block = read_rule_entries(LOCAL_BLOCKLIST_FILE);

    if (action == 'allow') {
        block = [];
    }
    else if (action == 'block') {
        allow = [];
    }

    return {
        schema: {
            name: RULES_SCHEMA_NAME,
            version: RULES_SCHEMA_VERSION
        },
        allow: allow,
        block: block,
        counts: {
            allow: length(allow),
            block: length(block)
        }
    };
}

function validate_rule_request(args) {
    let action = args.action || '';
    let domain = normalize_rule_domain(args.domain);

    if (!rule_path(action)) {
        return api_error('invalid_action', 'action must be either allow or block', 'action');
    }

    if (!domain) {
        return api_error('invalid_domain', 'domain must be a plain valid domain name', 'domain');
    }

    return {
        ok: true,
        action: action,
        domain: domain,
        path: rule_path(action)
    };
}

function apply_rule_refresh(args) {
    reload_uci();

    let should_refresh = (args.refresh == null) ? true : args.refresh;

    if (!should_refresh) {
        return {
            requested: false,
            accepted: false,
            reason: 'not_requested'
        };
    }

    if (!to_bool(cfg('apply_local_overrides', '1'), true)) {
        return {
            requested: false,
            accepted: false,
            reason: 'local_overrides_disabled'
        };
    }

    let r = start_local_apply_async();

    return {
        requested: true,
        accepted: r.accepted,
        reason: r.reason || ''
    };
}

function rules_list_call(request) {
    let action = request.args.action || '';

    if (action && !rule_path(action)) {
        return api_error('invalid_action', 'action must be allow, block or omitted', 'action');
    }

    let result = build_rules(action);
    result.ok = true;
    return result;
}

function rule_add_call(request) {
    let checked = validate_rule_request(request.args);

    if (!checked.ok) {
        return checked;
    }

    let result = add_rule_to_file(checked.path, checked.domain);

    if (!result.ok) {
        return api_error('rule_write_failed', 'Failed to update the local rule file');
    }

    let refresh = result.changed
        ? apply_rule_refresh(request.args)
        : { requested: false, accepted: false, reason: 'unchanged' };

    return {
        ok: true,
        action: checked.action,
        domain: checked.domain,
        added: result.changed,
        refresh: refresh,
        rules: build_rules(checked.action)
    };
}

function rule_delete_call(request) {
    let checked = validate_rule_request(request.args);

    if (!checked.ok) {
        return checked;
    }

    let result = delete_rule_from_file(checked.path, checked.domain);

    if (!result.ok) {
        return api_error('rule_write_failed', 'Failed to update the local rule file');
    }

    let refresh = result.changed
        ? apply_rule_refresh(request.args)
        : { requested: false, accepted: false, reason: 'unchanged' };

    return {
        ok: true,
        action: checked.action,
        domain: checked.domain,
        deleted: result.changed,
        refresh: refresh,
        rules: build_rules(checked.action)
    };
}

return {
    list: rules_list_call,
    add: rule_add_call,
    delete: rule_delete_call
};
