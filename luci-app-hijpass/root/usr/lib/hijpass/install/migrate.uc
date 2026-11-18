#!/usr/bin/ucode -S
/** @typedef {import('../../../share/ucode/hijpass/types/sections.uc').LegacyHijpassSection} LegacyHijpassSection */
import { cursor } from 'uci';
import * as fs from 'fs';
import { RULE_FILES, FILES, CLIENT_DIR, SERVER_DIR, nodeConfig, logPath } from 'hijpass.config.paths';
import { logger, configuredLogger } from '../maintenance/logs.uc';

// 安装专用：历史字段按 schema_version 分阶段转换；业务模块只读取当前格式。
// 版本号在全部迁移成功后提交；同版本重复安装跳过，失败则保留入口供重试。
const VERSION = '5';

// 旧 Shell 变量模板与 ucode 模板格式不同，只保留来源供用户手动迁移。
/**
 * @param {uci.cursor} ctx
 * @param {LegacyHijpassSection} global
 */
function markLegacyFirewallTemplate(ctx, global) {
    let source = global.nft;
    const previous = ['/etc/hijpass/fw4-template.nft', '/etc/hijpass/fw4-template.ut'];
    if (!source && index(previous, global.firewall_template) >= 0) {
        source = global.firewall_template;
    }
    if (!source && !global.legacy_firewall_template && (!global.firewall_template || global.firewall_template == FILES.firewall_template)) {
        // schema 1–3 已删除 nft 字段；仍存在的默认旧文件也需要提醒。
        for (let name in ['fw4-template.nft', 'fw4-template.ut']) {
            let path = fs.dirname(FILES.firewall_template) + '/' + name;
            if (fs.stat(path)?.type == 'file') {
                source = path;
                break;
            }
        }
    }
    if (source) {
        ctx.set('hijpass', global['.name'], 'legacy_firewall_template', source);
        // 不把旧格式文件当作可用的新模板覆盖软件包提供的默认模板。
        ctx.delete('hijpass', global['.name'], 'firewall_template');
        warn(`Legacy firewall template ${source} requires manual migration; see the Firewall page.\n`);
        logger([global])('WARN', 'Legacy firewall template requires manual migration; see the Firewall page');
    }
}

/**
 * 把初始版本的核心、DNS 和负载均衡设置转成当前格式。
 * @param {uci.cursor} ctx
 * @returns {null} 无业务返回值；只修改 cursor，不提交 UCI。
 */
function migrateInitial(ctx) {
    // 迁移规则固定在安装脚本中，不依赖当前协议模型，避免业务扩展改变旧配置转换结果。
    const balanceKeys = [
        'url', 'interval', 'tolerance', 'idle_timeout', 'interrupt_exist_connections',
        'strategy', 'strategy_expected', 'strategy_max_rtt', 'strategy_tolerance', 'fallback_tag',
        'probe_url', 'probe_connectivity', 'probe_interval', 'probe_timeout', 'probe_sampling', 'probe_http_method',
    ];
    /**
     * 将旧配置中的单值和列表统一为数组。
     * @returns {array} 原数组或单项数组；空值返回空数组。
     */
    function list(value) {
        if (type(value) == 'array') {
            return value;
        }
        if (value) {
            return [value];
        }
        return [];
    }
    let shunt, dns, firewall, names = {}, ports = {};
    ctx.foreach('hijpass', null, s => {
        let id = s['.name'];
        if (s['.type'] == 'hijpass') {
            ctx.delete('hijpass', id, 'nft');
            ctx.delete('hijpass', id, 'firewall_rules');
        }
        if (s['.type'] == 'proxy_node') {
            let mode = s.config_type || (s.core == 'custom' || s.type == 'custom' ? 'custom' : 'generated');
            ctx.set('hijpass', id, 'config_type', mode);
            if (mode == 'custom') {
                // 用户命令和配置文件保持原样；自定义配置不再声明核心或协议。
                ctx.delete('hijpass', id, 'core');
                ctx.delete('hijpass', id, 'type');
            }
            else if (!s.core || s.core == 'singbox') {
                ctx.set('hijpass', id, 'core', 'sing-box');
            }
        }
        if (s['.type'] == 'firewall') {
            for (let key in [
                'pre_filter_hash', 'out_route_hash', 'tproxy_shunt_hash', 'tproxy_mark_hash',
                'proxy_port_filter_hash', 'dns_forward_hash', 'dns_forward_output_hash',
            ]) ctx.delete('hijpass', id, key);
        }
        if (s.name) {
            names[s.name] = true;
        }
        for (let key in ['listen_port', 'socks_port', 'shunt_listen_port', 'dns_listen_port', 'cdg_port']) {
            if (s[key]) {
                ports[s[key]] = true;
            }
        }
        if (s['.type'] == 'shunt' && !shunt) {
            shunt = s;
        }
        if (s['.type'] == 'dns' && !dns) {
            dns = s;
        }
        if (s['.type'] == 'firewall' && !firewall) {
            firewall = s;
        }
    });
    // 迁移负载均衡时也避开服务端已声明的端口。
    if (ctx.load('hijserver')) {
        ctx.foreach('hijserver', null, s => {
            for (let key in ['listen_port', 'socks_port']) {
                if (s[key]) {
                    ports[s[key]] = true;
                }
            }
        });
    }
    if (shunt && (!shunt.type || shunt.type == 'singbox')) {
        ctx.set('hijpass', shunt['.name'], 'type', 'sing-box');
    }
    if (dns) {
        for (let key in ['direct_dns', 'proxy_dns']) {
            if (dns[key] == 'system') {
                ctx.set('hijpass', dns['.name'], key, 'dnsmasq');
            }
        }
    }
    if (firewall && !firewall.proxy_local) {
        ctx.set('hijpass', firewall['.name'], 'proxy_local', '0');
    }
    if (shunt && length(list(shunt.lb_node_list))) {
        let name = 'load-balance', suffix = 2;
        while (names[name]) name = `load-balance-${suffix++}`;
        /**
         * 查找并登记一个未被已有配置占用的端口。
         * @returns {string} 十进制端口字符串；没有可用端口时抛错。
         */
        function available(start) {
            while (ports[start] && start <= 65535) start++;
            if (start > 65535) {
                die('no available load balancing port');
            }
            ports[start] = true;
            return `${start}`;
        }
        let listen = available(7890), socks = available(int(listen) + 1), id = ctx.add('hijpass', 'proxy_node');
        let options = {
            name, config_type: 'generated', type: 'load_balance', core: shunt.type == 'xray' ? 'xray' : 'sing-box', enabled: '1',
            listen_port: listen, socks_port: socks, log_level: 'info', member_node: list(shunt.lb_node_list),
            log_enabled: '1',
        };
        for (let key in balanceKeys) {
            if (shunt[key] != null) {
                options[key] = shunt[key];
            }
        }
        for (let key, value in options) ctx.set('hijpass', id, key, value);
        ctx.foreach('hijpass', null, s => {
            for (let key in ['default_proxy_node', 'ruleset_out_node', 'proxy_node', 'proxy_node_v4', 'proxy_node_v6', 'dns_proxy_node']) {
                if (s[key] == 'hijpass-slb') {
                    ctx.set('hijpass', s['.name'], key, name);
                }
            }
        });
        for (let key in ['lb_node_list', ...balanceKeys]) ctx.delete('hijpass', shunt['.name'], key);
    }
}

/**
 * 将旧 Xray VLESS HTTP 传输配置转换为 XHTTP。
 * @param {uci.cursor} ctx
 * @returns {null} 无业务返回值；只修改 cursor，不提交 UCI。
 */
function migrateHTTP(ctx) {
    ctx.foreach('hijpass', 'proxy_node', s => {
        if (s.config_type == 'custom' || s.core != 'xray' || s.type != 'vless' || s.transport_type != 'http') {
            return;
        }
        let id = s['.name'];
        // 只转换原先生效的 HTTP 字段；覆盖残留的 XHTTP 值，保持生成结果一致。
        ctx.set('hijpass', id, 'transport_type', 'xhttp');
        ctx.set('hijpass', id, 'transport_xhttp_mode', 'stream-one');
        for (let key in ['host', 'path', 'method'])
            ctx.set('hijpass', id, `transport_xhttp_${key}`, s[`transport_http_${key}`] || '');
        for (let key in ['host', 'path', 'method', 'idle_timeout', 'ping_timeout'])
            ctx.delete('hijpass', id, `transport_http_${key}`);
    });
}

/**
 * 创建迁移目标目录及缺失的父目录。
 * @param {string} path
 * @returns {null} 无业务返回值；创建失败时抛错。
 */
function mkdir(path) {
    if (fs.stat(path)?.type == 'directory') {
        return;
    }
    let parent = fs.dirname(path);
    if (parent != path) {
        mkdir(parent);
    }
    if (!fs.mkdir(path, 0o755)) {
        die(`cannot create migration directory ${path}`);
    }
}

/**
 * 通过临时文件原子替换迁移目标，并保留指定权限。
 * content 为已读取的文件文本。
 * @param {string} path 目标路径。
 * @param {integer} mode 文件权限。
 * @returns {null} 无业务返回值；失败时清理临时文件并抛错。
 */
function writeFile(path, content, mode) {
    mkdir(fs.dirname(path));
    let temp = `${path}.migrate-${fs.readlink('/proc/self')}`, file = fs.open(temp, 'wx');
    if (!file) {
        die(`cannot stage migration file ${path}`);
    }
    try {
        if (!fs.chmod(temp, mode) || file.write(content) != length(content) || !file.flush()) {
            die(`cannot write migration file ${path}`);
        }
        file.close();
        if (!fs.rename(temp, path)) {
            die(`cannot replace migration file ${path}`);
        }
    }
    catch (e) { file.close(); fs.unlink(temp); die(e.message); }
}

// 旧位置的内容优先于软件包默认文件；保留来源，并备份目标原内容，失败可重试。
/**
 * 把旧路径的文件复制到固定位置，覆盖前备份已有内容。
 * @param {string|null} source
 * @param {string} target
 * @returns {null} 无业务返回值；源文件缺失或路径相同时跳过。
 */
function copyManagedFile(source, target) {
    if (!source || source == target) {
        return;
    }
    let info = fs.stat(source);
    if (!info) {
        return;
    }
    let content = fs.readfile(source);
    if (info.type != 'file' || type(content) != 'string') {
        die(`cannot migrate ${source}`);
    }
    let existing = fs.stat(target), original = existing ? fs.readfile(target) : null;
    if (existing && type(original) != 'string') {
        die(`cannot back up ${target}`);
    }
    if (original == content) {
        return;
    }
    let backup = target + '.before-path-migration';
    if (existing && !fs.stat(backup)) {
        writeFile(backup, original, existing.mode);
    }
    writeFile(target, content, info.mode);
}

/**
 * 迁移受管文件，并把旧路径配置替换为当前开关。
 * @param {uci.cursor} ctx
 * @param {string} packageName
 * @returns {null} 无业务返回值；只修改文件和 cursor，不提交 UCI。
 */
function migratePaths(ctx, packageName) {
    let server = packageName == 'hijserver', global;
    ctx.foreach(packageName, packageName, s => {
        if (!global) {
            global = s;
        }
    });
    if (!global) {
        die(`missing ${packageName} global section`);
    }
    if (!server) {
        for (let key, target in { ...RULE_FILES, ...FILES }) {
            copyManagedFile(global[key], target);
            ctx.delete(packageName, global['.name'], key);
        }
    }
    let directoryKey = server ? 'server_dir' : 'client_dir';
    let oldDirectory = global[directoryKey], directory = server ? SERVER_DIR : CLIENT_DIR;
    ctx.foreach(packageName, null, s => {
        let id = s['.name'];
        if (s['.type'] == (server ? 'server_node' : 'proxy_node') && oldDirectory && oldDirectory != directory) {
            let target = nodeConfig(s, server);
            copyManagedFile(`${oldDirectory}/${fs.basename(target)}`, target);
        }
        if (s.log_path) {
            if (s['.type'] != packageName) {
                ctx.set(packageName, id, 'log_enabled', '1');
            }
            let target = logPath({ ...s, log_enabled: '1' }, server);
            if (target) {
                copyManagedFile(s.log_path, target);
            }
        }
        ctx.delete(packageName, id, 'log_path');
        ctx.delete(packageName, id, 'log_dir');
    });
    ctx.delete(packageName, global['.name'], directoryKey);
}

/**
 * 删除旧版本注册的定时任务，保留其他任务。
 * @param {string} path
 * @returns {null} 无业务返回值；文件不存在或内容未变时跳过。
 */
function cleanLegacyCron(path) {
    let info = fs.stat(path);
    if (!info) {
        return;
    }
    if (info.type != 'file') {
        die('cron path is not a file');
    }
    let original = fs.readfile(path);
    if (type(original) != 'string') {
        die('cannot read root crontab');
    }
    const scripts = [
        '/usr/lib/hijpass/rules.sh', '/usr/lib/hijpass/rules.uc',
        '/usr/lib/hijpass/clean-service-log.sh', '/usr/lib/hijpass/clean-service-log.uc',
    ];
    let lines = [];
    for (let line in split(original, '\n')) {
        let fields = split(trim(line) || '', /[ \t]+/);
        // 普通任务的命令在五个时间字段之后；@reboot 等宏任务只有一个时间字段。
        // 只检查命令位，保留注释及其他任务参数中提到旧路径的文本。
        let position = substr(fields[0] || '', 0, 1) == '@' ? 1 : 5;
        if (index(scripts, fields[position]) >= 0) {
            continue;
        }
        push(lines, line);
    }
    let content = join('\n', lines);
    if (content == original) {
        return;
    }
    // 原地暂存并保留权限，写入失败时不替换正在使用的 crontab。
    let temp = `${path}.new-${fs.readlink('/proc/self')}`, file = fs.open(temp, 'wx');
    if (!file) {
        die('cannot stage root crontab');
    }
    try {
        if (!fs.chmod(temp, info.mode) || file.write(content) != length(content) || !file.flush()) {
            die('cannot write root crontab');
        }
        file.close();
        if (!fs.rename(temp, path)) {
            die('cannot replace root crontab');
        }
    }
    catch (e) { file.close(); fs.unlink(temp); die(e.message); }
}

let log, directory, started = time();
try {
    if (length(ARGV)) {
        if (length(ARGV) != 2 || ARGV[0] != '--configdir' || !ARGV[1]) {
            die('usage: migrate.uc [--configdir DIRECTORY]');
        }
        directory = ARGV[1];
    }
    log = configuredLogger(directory);
    // 离线目录遵循 etc/config 与相邻 crontabs 的布局；delta 单独存放，避免文件锁冲突。
    if (directory) {
        fs.mkdir(directory + '/.uci', 0o700);
    }
    let ctx = cursor(directory, directory ? directory + '/.uci' : null);
    if (!ctx || !ctx.load('hijpass')) {
        die('cannot load hijpass for migration');
    }
    let global;
    ctx.foreach('hijpass', 'hijpass', s => {
        if (!global) {
            global = s;
        }
    });
    if (!global) {
        die('hijpass global section is missing');
    }
    let version = global.schema_version || '0';
    if (version == VERSION) {
        exit(0);
    }
    log('INFO', `Schema migration started: ${version} -> ${VERSION}`);
    if (index(['0', '1', '2', '3', '4'], version) < 0) {
        die(`unsupported schema_version "${version}"`);
    }
    if (version == '0') {
        migrateInitial(ctx);
    }
    if (version == '0' || version == '1') {
        migrateHTTP(ctx);
        cleanLegacyCron(directory ? fs.dirname(directory) + '/crontabs/root' : '/etc/crontabs/root');
    }
    markLegacyFirewallTemplate(ctx, global);
    if (int(version) < 3) migratePaths(ctx, 'hijpass');
    if (fs.stat((directory || '/etc/config') + '/hijserver')) {
        if (!ctx.load('hijserver')) {
            die('cannot load hijserver for migration');
        }
        if (int(version) < 3) migratePaths(ctx, 'hijserver');
        ctx.foreach('hijserver', 'server_node', section => {
            // 任意命令/JSON 无法可靠转换；保留文件和字段供人工迁移，不再执行。
            let path = nodeConfig(section, true);
            if (!fs.stat(path + '.legacy.json')) copyManagedFile(path, path + '.legacy.json');
            ctx.set('hijserver', section['.name'], 'enabled', '0');
            ctx.set('hijserver', section['.name'], 'legacy_custom', '1');
            log('WARN', `Server "${section.name || section['.name']}" disabled: select a protocol and configure credentials on the Local Server page`);
        });
        if (!ctx.commit('hijserver')) {
            die(`cannot commit hijserver migration: ${ctx.error()}`);
        }
    }
    ctx.set('hijpass', global['.name'], 'schema_version', VERSION);
    if (!ctx.commit('hijpass')) {
        die(`cannot commit hijpass migration: ${ctx.error()}`);
    }
    log('INFO', `Schema migration completed: version=${VERSION}, elapsed=${time() - started}s`);
}
catch (e) { (log || configuredLogger(directory))('ERROR', `Migration failed: ${e.message}`); warn(e.message + '\n'); exit(1); }
