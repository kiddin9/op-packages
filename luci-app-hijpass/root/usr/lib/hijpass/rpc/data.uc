import * as fs from 'fs';
import * as ubus from 'ubus';
import { defaultTemplate } from '../firewall/generate.uc';
import { logs, log } from './files.uc';
import { generate, validate } from 'hijpass.config.generate';
import { generate as generateServers, render as renderServer } from 'hijpass.server.generate';
import { validateSections, filterServerNodeSections } from 'hijpass.config.sections';
import { read } from 'hijpass.uci.read';
import { writeOutput } from 'hijpass.command.runtime';

// RPC 参数是业务数据。没有文件路径或通用 command/argv 入口。
const methods = {
    firewall_template_default: {}, editor_sessions: { sessions: [] },
    config_render: { sections: '', target: '' }, config_validate: { sections: '' },
    log_list: {}, log_read: { id: '', action: '', lines: '' },
    log_clear: { id: '' },
    server_render: { sections: '', target: '' }, server_validate: { sections: '' },
    cleanup_node: { kind: '', section: '', name: '' },
    service_restart: {}, firewall_reset: {}, firewall_show: {},
    network_connect: { url: '', timeout: '' }, network_ping: { port: '' },
    rule_update: {}, rule_update_status: {}, rule_query: { keyword: '' }, rule_match: { keyword: '' },
    geo_lookup: { type: '', keyword: '', mode: '' }, geo_query: { keyword: '' },
    core_version: { core: '' }, core_latest: { core: '' }, core_update: { core: '' }, core_update_status: { core: '' },
    job_status: { id: '' },
    trace_capabilities: {}, trace_start: { args: [] }, trace_status: { id: '' }, trace_release: { id: '' },
};

try {
    if (ARGV[0] == 'list') {
        writeOutput(sprintf('%J\n', methods));
        exit(0);
    }
    let method = ARGV[1], input = fs.stdin.read(4 * 1024 * 1024 + 1);
    if (type(input) != 'string' || length(input) > 4 * 1024 * 1024) {
        die('invalid request size');
    }
    if (type(method) != 'string') {
        die('missing RPC method');
    }
    let request = json(input);
    if (type(request) != 'object' || !exists(methods, method)) {
        die('unknown RPC method');
    }
    const hasSections = request.sections != null;
    for (let key, fallback in methods[method]) {
        if (request[key] == null) {
            request[key] = fallback;
        }
        if (type(request[key]) != type(fallback)) {
            die(`invalid RPC argument: ${key}`);
        }
    }
    let result;
    if (method == 'firewall_template_default') {
        result = { content: defaultTemplate() };
    }
    else if (method == 'editor_sessions') {
        if (length(request.sessions) > 64 || length(filter(request.sessions,
            id => type(id) != 'string' || !match(id, /^[a-f0-9]{32}$/)))) die('invalid session list');
        let bus = ubus.connect();
        if (!bus) die('cannot connect to rpcd');
        // 枚举不会延长旧会话寿命；只返回浏览器已经持有的 ID。
        let sessions = bus.call('session', 'list', {}, 'multiple');
        bus.disconnect();
        if (type(sessions) != 'array') die('cannot list rpcd sessions');
        let active = map(sessions, item => item.ubus_rpc_session);
        result = { sessions: filter(request.sessions, id => index(active, id) >= 0) };
    }
    else if (method == 'log_list') {
        result = logs();
    }
    else if (method == 'log_read') {
        if (index(['read', 'download'], request.action) < 0) {
            die('invalid log read action');
        }
        result = log(request);
    }
    else if (method == 'log_clear') {
        result = log({ id: request.id, action: 'clear' });
    }
    else if (method == 'server_render' || method == 'server_validate') {
        let sections = hasSections ? json(request.sections) : read('hijserver');
        validateSections(sections);
        if (method == 'server_render') {
            let section = filter(filterServerNodeSections(sections), s => s['.name'] == request.target)[0];
            if (!section) die('server node not found');
            result = { config: renderServer(section) };
        }
        else {
            generateServers(sections);
            result = { ok: true };
        }
    }
    else if (method == 'config_render' || method == 'config_validate') {
        // 显式空快照仍须报错；只有省略 sections 才读取已提交 UCI。
        let sections = hasSections ? json(request.sections) : read();
        if (method == 'config_validate') {
            result = validate(sections);
        }
        else {
            let generated = generate(sections, request.target);
            result = request.target ? { config: generated } : generated;
        }
    }
    else {
        die('unknown data method');
    }
    writeOutput(sprintf('%J\n', result));
}
catch (e) { writeOutput(sprintf('%J\n', { error: e.message })); }
